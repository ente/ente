use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, TryRecvError};
use std::time::Duration;

use super::vad::Vad;

use super::{StreamNormalizer, Transcriber};
use crate::voice::{
    AlignedWord, CaptureFeedResult, CaptureFormat, CaptureQueue, Result, RollingRecognizer,
    TranscriptBoundary, VoiceError,
};

pub enum LiveEvent {
    Ready,
    Audio {
        start: u64,
        end: u64,
        voiced: bool,
    },
    Hypothesis(String),
    Commit {
        start: u64,
        end: u64,
        text: String,
    },
    Deferred {
        reason: VoiceError,
        committed_through: u64,
        model_ready: bool,
    },
    Coverage(u64),
    Idle,
    CaptureClosed,
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum LiveControl {
    Continue,
    Finish,
    Cancel,
}

enum DecoderEvent {
    Prepared(Result<()>),
    Window(crate::voice::DecodeWindow, Result<Vec<AlignedWord>>),
}

pub struct LiveTranscription {
    pub(super) queue: CaptureQueue,
    started: AtomicBool,
}

pub(super) struct CaptureGuard<'a>(&'a CaptureQueue);
impl Drop for CaptureGuard<'_> {
    fn drop(&mut self) {
        self.0.clear();
    }
}

impl LiveTranscription {
    pub fn new(format: CaptureFormat) -> Result<Self> {
        Ok(Self {
            queue: CaptureQueue::new(format)?,
            started: AtomicBool::new(false),
        })
    }

    pub fn feed(&self, pcm: &[u8]) -> Result<CaptureFeedResult> {
        self.queue.push(pcm)
    }
    pub fn finish(&self) {
        self.queue.finish();
    }
    pub fn finish_if_empty(&self) -> bool {
        self.queue.finish_if_empty()
    }
    pub fn cancel(&self) {
        self.queue.cancel();
    }
    pub fn submitted_samples(&self) -> u64 {
        self.queue.submitted_frames() * 16000 / u64::from(self.queue.format().sample_rate)
    }

    pub(super) fn start(&self) -> Result<CaptureGuard<'_>> {
        if self.started.swap(true, Ordering::AcqRel) {
            return Err(VoiceError::InvalidState);
        }
        let guard = CaptureGuard(&self.queue);
        self.check()?;
        Ok(guard)
    }

    pub(super) fn check(&self) -> Result<()> {
        if self.queue.is_cancelled() {
            Err(VoiceError::Cancelled)
        } else if self.queue.failed() {
            Err(VoiceError::BacklogFull)
        } else {
            Ok(())
        }
    }

    pub(super) fn emit(
        &self,
        event: LiveEvent,
        on_event: &mut impl FnMut(LiveEvent) -> Result<LiveControl>,
    ) -> Result<()> {
        let idle = matches!(event, LiveEvent::Idle);
        match on_event(event)? {
            LiveControl::Cancel => {
                self.cancel();
                return Err(VoiceError::Cancelled);
            }
            LiveControl::Finish if idle => {
                self.queue.finish_if_empty();
            }
            LiveControl::Finish => self.queue.finish(),
            LiveControl::Continue => {}
        }
        Ok(())
    }

    pub fn run(
        &self,
        transcriber: &Transcriber,
        on_event: &mut impl FnMut(LiveEvent) -> Result<LiveControl>,
    ) -> Result<()> {
        self.run_with(
            || transcriber.live_vad(),
            || {
                transcriber
                    .load_model()
                    .map_err(|error| super::voice_error("Load transcription model", error))
            },
            |request| transcriber.transcribe_window(&request.samples, || self.queue.is_cancelled()),
            |pcm| transcriber.transcribe_tail(pcm, || self.queue.is_cancelled()),
            on_event,
        )
    }

    fn run_with(
        &self,
        make_vad: impl FnOnce() -> Result<Box<dyn Vad>>,
        prepare: impl FnOnce() -> Result<()> + Send,
        mut decode: impl FnMut(&crate::voice::DecodeWindow) -> Result<Vec<AlignedWord>> + Send,
        decode_recorded: impl FnMut(&[u8]) -> Result<Vec<AlignedWord>>,
        on_event: &mut impl FnMut(LiveEvent) -> Result<LiveControl>,
    ) -> Result<()> {
        let _capture = self.start()?;
        let mut vad = make_vad()?;
        if vad.frame_size() != super::VAD_FRAME_SAMPLES {
            return Err(VoiceError::InvalidAudio(
                "Voice activity model has an unsupported frame size".into(),
            ));
        }
        let mut normalizer = StreamNormalizer::new(self.queue.format())?;
        let mut rolling = RollingRecognizer::default();
        let mut boundary = TranscriptBoundary::default();
        let mut provisional = Vec::new();
        let mut pcm = super::recorded::RecordedPcm::default();
        let mut accepted = 0_u64;
        let mut deferred = false;
        self.emit(LiveEvent::Ready, on_event)?;
        std::thread::scope(|scope| {
            let (requests, request_rx) = mpsc::sync_channel::<crate::voice::DecodeWindow>(1);
            let (results, result_rx) = mpsc::sync_channel(1);
            let decoder = scope.spawn(move || {
                let prepared = if self.queue.is_cancelled() {
                    Err(VoiceError::Cancelled)
                } else {
                    prepare()
                };
                let failed = prepared.is_err();
                if results.send(DecoderEvent::Prepared(prepared)).is_err() || failed {
                    return;
                }
                while let Ok(request) = request_rx.recv() {
                    let output = if self.queue.is_cancelled() {
                        Err(VoiceError::Cancelled)
                    } else {
                        decode(&request)
                    };
                    if results.send(DecoderEvent::Window(request, output)).is_err() {
                        break;
                    }
                }
            });
            let mut finished = false;
            let mut prepared = false;
            let mut notified_stop = false;
            let processing = (|| -> Result<()> {
                loop {
                    self.check()?;
                    let chunk = self.queue.take();
                    let had_chunk = chunk.is_some();
                    let mut emit = |frame: &[f32], real: usize| -> Result<()> {
                        let voiced = vad.is_speech(frame).map_err(|error| {
                            super::voice_error("Detect speech in live audio", error)
                        })?;
                        let start = accepted;
                        accepted += real as u64;
                        self.emit(
                            LiveEvent::Audio {
                                start,
                                end: accepted,
                                voiced,
                            },
                            on_event,
                        )?;
                        pcm.push(&frame[..real], voiced)?;
                        if !deferred {
                            match rolling.feed(&frame[..real], voiced) {
                                Ok(()) => {}
                                Err(VoiceError::BacklogFull) => {
                                    deferred = true;
                                    self.emit(
                                        LiveEvent::Deferred {
                                            reason: VoiceError::BacklogFull,
                                            committed_through: boundary.end,
                                            model_ready: prepared,
                                        },
                                        on_event,
                                    )?;
                                }
                                Err(error) => return Err(error),
                            }
                        }
                        Ok(())
                    };
                    if let Some(chunk) = chunk {
                        normalizer.push(&chunk, &mut emit)?;
                    }
                    if !finished && self.queue.is_drained() {
                        normalizer.finish(&mut emit)?;
                        if !deferred {
                            rolling.finish();
                        }
                        finished = true;
                    }
                    if self.queue.is_closed() && !notified_stop {
                        self.emit(LiveEvent::CaptureClosed, on_event)?;
                        notified_stop = true;
                    }
                    match result_rx.try_recv() {
                        Ok(DecoderEvent::Prepared(result)) => {
                            result?;
                            prepared = true;
                        }
                        Ok(DecoderEvent::Window(request, words)) => {
                            if self.queue.is_cancelled() {
                                return Err(VoiceError::Cancelled);
                            }
                            if !deferred {
                                match words.and_then(|words| rolling.complete(&request, words)) {
                                    Ok(update) => {
                                        if let Some((start, end, text)) = update.commit {
                                            self.emit(
                                                LiveEvent::Commit { start, end, text },
                                                on_event,
                                            )?;
                                        }
                                        self.emit(
                                            LiveEvent::Hypothesis(update.hypothesis),
                                            on_event,
                                        )?;
                                        self.emit(
                                            LiveEvent::Coverage(update.boundary.end),
                                            on_event,
                                        )?;
                                        boundary = update.boundary;
                                        provisional = update.provisional;
                                    }
                                    Err(
                                        reason @ (VoiceError::UnstableTranscript
                                        | VoiceError::IncompleteAudio),
                                    ) => {
                                        deferred = true;
                                        self.emit(
                                            LiveEvent::Deferred {
                                                reason,
                                                committed_through: boundary.end,
                                                model_ready: prepared,
                                            },
                                            on_event,
                                        )?;
                                    }
                                    Err(error) => return Err(error),
                                }
                            }
                        }
                        Err(TryRecvError::Empty) => {}
                        Err(error @ TryRecvError::Disconnected) => {
                            return Err(VoiceError::ProcessingFailed(format!(
                                "Receive speech decoder result: {error}"
                            )));
                        }
                    }
                    if prepared && finished && (deferred || rolling.is_settled()) {
                        if !deferred {
                            self.emit(LiveEvent::Coverage(accepted), on_event)?;
                        }
                        return Ok(());
                    }
                    if prepared
                        && !deferred
                        && let Some(request) = rolling.next_window()?
                    {
                        requests.try_send(request).map_err(|error| {
                            VoiceError::ProcessingFailed(format!(
                                "Send speech decoder window: {error}"
                            ))
                        })?;
                    }
                    if !had_chunk && !finished {
                        self.emit(LiveEvent::Idle, on_event)?;
                    }
                    if !had_chunk {
                        std::thread::sleep(Duration::from_millis(10));
                    }
                }
            })();
            self.queue.finish();
            if !notified_stop {
                let _ = on_event(LiveEvent::CaptureClosed);
            }
            drop(requests);
            drop(result_rx);
            let exited = decoder
                .join()
                .map_err(|_| VoiceError::ProcessingFailed("Speech decoder thread panicked".into()));
            exited.and(processing)?;
            if deferred {
                drop(vad);
                drop(normalizer);
                self.check()?;
                self.finish_recording(&pcm, &boundary, &provisional, decode_recorded, on_event)?;
                self.check()?;
                self.emit(LiveEvent::Hypothesis(String::new()), on_event)?;
            }
            Ok(())
        })
    }
}

#[cfg(test)]
mod tests {
    use super::super::vad::EnergyVad;
    use super::*;

    fn stream() -> LiveTranscription {
        LiveTranscription::new(CaptureFormat {
            sample_rate: 16000,
            channels: 1,
        })
        .unwrap()
    }

    fn vad() -> Result<Box<dyn Vad>> {
        Ok(Box::new(EnergyVad::new(
            super::super::VAD_FRAME_SAMPLES,
            0.01,
        )))
    }

    #[test]
    fn capture_and_vad_preserve_opening_audio_while_model_loads() {
        let stream = stream();
        let (release, loading) = mpsc::sync_channel(1);
        let loaded = &AtomicBool::new(false);
        let mut coverage = 0;
        let mut recognized = false;
        let prepared = AtomicBool::new(false);
        let mut closed = 0;
        stream
            .run_with(
                || {
                    prepared.store(true, Ordering::Release);
                    vad()
                },
                move || {
                    loading.recv_timeout(Duration::from_secs(3)).unwrap();
                    loaded.store(true, Ordering::Release);
                    Ok(())
                },
                |request| {
                    assert!(loaded.load(Ordering::Acquire));
                    assert_eq!(request.samples, vec![0.25; 10241]);
                    Ok(vec![AlignedWord {
                        text: "Opening words".into(),
                        start: 0,
                        end: 10241,
                    }])
                },
                |_| panic!("This capture must stay live"),
                &mut |event| {
                    match event {
                        LiveEvent::Ready => {
                            assert!(prepared.load(Ordering::Acquire));
                            assert!(!loaded.load(Ordering::Acquire));
                            for samples in [2560, 2560, 2560, 2561] {
                                stream.feed(&[0, 32].repeat(samples))?;
                            }
                        }
                        LiveEvent::Audio { end, .. } => {
                            if end <= 10240 {
                                assert!(!loaded.load(Ordering::Acquire));
                            }
                            if end == 10240 {
                                stream.finish();
                                release.send(()).unwrap();
                            }
                        }
                        LiveEvent::CaptureClosed => closed += 1,
                        LiveEvent::Commit { text, .. } => recognized |= text == "Opening words",
                        LiveEvent::Coverage(end) => coverage = end,
                        _ => {}
                    }
                    Ok(LiveControl::Continue)
                },
            )
            .unwrap();
        assert!(recognized);
        assert_eq!(coverage, 10241);
        assert_eq!(stream.submitted_samples(), 10241);
        assert_eq!(closed, 1);
    }

    #[test]
    fn slow_initialization_uses_existing_recorded_recovery_without_losing_audio() {
        let stream = stream();
        let (release, loading) = mpsc::sync_channel(1);
        let mut accepted = 0;
        let mut deferred = false;
        let mut replacement = String::new();
        let mut decoded_samples = 0;
        let mut coverage = 0;
        stream
            .run_with(
                vad,
                move || {
                    loading.recv_timeout(Duration::from_secs(3)).unwrap();
                    Ok(())
                },
                |_| panic!("Initialization exceeded the existing live backlog limit"),
                |pcm| {
                    assert!(pcm.len() <= super::super::MAX_RECORDED_WINDOW_SAMPLES * 2);
                    assert!(pcm.as_chunks::<2>().0.iter().all(|frame| *frame == [0, 32]));
                    let first = decoded_samples == 0;
                    decoded_samples += pcm.len() / 2;
                    super::super::recorded::decoded_chunk(
                        pcm,
                        if first { "All opening" } else { " speech" },
                    )
                },
                &mut |event| {
                    match event {
                        LiveEvent::Audio { end, .. } => accepted = end,
                        LiveEvent::Idle => {
                            if accepted < 12 * 16000 {
                                for _ in 0..5 {
                                    stream.feed(&[0, 32].repeat(3200))?;
                                }
                            } else {
                                assert!(deferred);
                                stream.finish();
                                release.send(()).unwrap();
                            }
                        }
                        LiveEvent::Deferred { .. } => deferred = true,
                        LiveEvent::Commit { text, .. } => replacement.push_str(&text),
                        LiveEvent::Coverage(end) => coverage = end,
                        _ => {}
                    }
                    Ok(LiveControl::Continue)
                },
            )
            .unwrap();
        assert_eq!(replacement, "All opening speech");
        assert!(decoded_samples >= 12 * 16000);
        assert_eq!(coverage, 12 * 16000);
    }

    #[test]
    fn stop_and_cancel_during_loading_close_capture_before_joining_the_worker() {
        for cancel in [false, true] {
            let stream = stream();
            let (release, loading) = mpsc::sync_channel(1);
            let exited = &AtomicBool::new(false);
            let started = &AtomicBool::new(false);
            let mut closed = 0;
            let result = stream.run_with(
                vad,
                move || {
                    started.store(true, Ordering::Release);
                    loading.recv_timeout(Duration::from_secs(3)).unwrap();
                    exited.store(true, Ordering::Release);
                    Ok(())
                },
                |_| panic!("No audio to decode"),
                |_| panic!("No recorded fallback"),
                &mut |event| {
                    match event {
                        LiveEvent::Ready if !cancel => stream.finish(),
                        LiveEvent::Idle if cancel && started.load(Ordering::Acquire) => {
                            stream.cancel()
                        }
                        LiveEvent::CaptureClosed => {
                            assert!(!exited.load(Ordering::Acquire));
                            closed += 1;
                            release.send(()).unwrap();
                        }
                        LiveEvent::Ready | LiveEvent::Idle | LiveEvent::Coverage(0) => {}
                        _ => panic!("Initialization emitted recognition"),
                    }
                    Ok(LiveControl::Continue)
                },
            );
            assert_eq!(
                result,
                if cancel {
                    Err(VoiceError::Cancelled)
                } else {
                    Ok(())
                }
            );
            assert_eq!(closed, 1);
            assert!(exited.load(Ordering::Acquire));
        }
    }

    #[test]
    fn model_initialization_failures_preserve_causes_and_close_capture() {
        use super::super::TranscriptionError;

        for (error, expected) in [
            (TranscriptionError::NotDownloaded, VoiceError::NotDownloaded),
            (
                TranscriptionError::VadNotDownloaded,
                VoiceError::VadNotDownloaded,
            ),
            (
                std::io::Error::from(std::io::ErrorKind::StorageFull).into(),
                VoiceError::StorageFull,
            ),
            (
                std::io::Error::other("injected I/O failure").into(),
                VoiceError::Io("Load transcription model: injected I/O failure".into()),
            ),
            (
                TranscriptionError::InvalidAudio("injected audio failure".into()),
                VoiceError::InvalidAudio("Load transcription model: injected audio failure".into()),
            ),
            (
                TranscriptionError::Transcribe(
                    "inference error: injected initialization failure".into(),
                ),
                VoiceError::ProcessingFailed(
                    "Load transcription model: inference error: injected initialization failure"
                        .into(),
                ),
            ),
        ] {
            let stream = stream();
            let mut closed = false;
            let result = stream.run_with(
                vad,
                || Err(super::super::voice_error("Load transcription model", error)),
                |_| panic!("Failed model must not decode"),
                |_| panic!("Failed model must not transcribe"),
                &mut |event| {
                    match event {
                        LiveEvent::Ready | LiveEvent::Idle => {}
                        LiveEvent::CaptureClosed => closed = true,
                        _ => panic!("Failed initialization emitted recognition"),
                    }
                    Ok(LiveControl::Continue)
                },
            );
            assert_eq!(result, Err(expected));
            assert!(closed);
        }
    }

    #[test]
    fn failed_initial_decode_recovers_all_audio_without_ending_capture() {
        for failure in [VoiceError::UnstableTranscript, VoiceError::IncompleteAudio] {
            let stream = stream();
            for _ in 0..3 {
                stream.feed(&[0, 32].repeat(3200)).unwrap();
            }
            let mut deferred = false;
            let mut closed = false;
            let mut final_text = Vec::new();
            let mut coverage = 0;
            stream
                .run_with(
                    vad,
                    || Ok(()),
                    |_| Err(failure.clone()),
                    |pcm| {
                        assert_eq!(pcm, [0, 32].repeat(9600 + 1001));
                        super::super::recorded::decoded_chunk(pcm, "Complete recording")
                    },
                    &mut |event| {
                        match event {
                            LiveEvent::Deferred { .. } => {
                                assert!(!deferred);
                                assert!(!closed);
                                deferred = true;
                                stream.feed(&[0, 32].repeat(1001))?;
                                stream.finish();
                            }
                            LiveEvent::CaptureClosed => {
                                assert!(deferred);
                                closed = true;
                            }
                            LiveEvent::Commit { text, .. } => {
                                assert!(closed);
                                final_text.push(text);
                            }
                            LiveEvent::Coverage(end) => coverage = end,
                            _ => {}
                        }
                        Ok(LiveControl::Continue)
                    },
                )
                .unwrap();
            assert_eq!(final_text, ["Complete recording"]);
            assert_eq!(coverage, 10601);
        }
    }

    #[test]
    fn recovery_preserves_committed_prefix_and_cancel_keeps_the_visible_tail() {
        use super::super::DictationState;

        fn word(text: &str, start: u64, end: u64) -> AlignedWord {
            AlignedWord {
                text: text.into(),
                start,
                end,
            }
        }

        for failure in [VoiceError::UnstableTranscript, VoiceError::IncompleteAudio] {
            for outcome in 0..3 {
                let stream = stream();
                let (release, loading) = mpsc::sync_channel(1);
                let mut state = DictationState::new(true);
                state.session.begin_capture().unwrap();
                let mut samples = [0, 32].repeat(192000);
                samples[128000 * 2..128512 * 2].fill(0);
                let mut fed = 0;
                let mut calls = 0;
                let mut recovered = 0;
                let mut committed = false;
                let mut deferred = false;
                let expected_failure = failure.clone();
                let recovery_failure =
                    VoiceError::ProcessingFailed("injected recovery failure".into());
                let result = stream.run_with(
                    vad,
                    move || {
                        loading.recv_timeout(Duration::from_secs(3)).unwrap();
                        Ok(())
                    },
                    |_| {
                        calls += 1;
                        if calls > 3 {
                            return Err(failure.clone());
                        }
                        let mut words = vec![
                            word("Stable", 4000, 8000),
                            word("tentative", 64000, 68000),
                            word("tail", 72000, 76000),
                        ];
                        if calls == 3 {
                            words.push(word("later", 144000, 152000));
                        }
                        Ok(words)
                    },
                    |pcm| {
                        recovered += 1;
                        if recovered == 1 {
                            assert_eq!(pcm, &samples[..128512 * 2]);
                            if outcome == 1 {
                                stream.cancel();
                            }
                            Ok(vec![
                                word("Stable", 4000, 8000),
                                word("corrected", 64000, 68000),
                                word("tail", 72000, 76000),
                            ])
                        } else if outcome == 2 {
                            Err(recovery_failure.clone())
                        } else {
                            assert_eq!(recovered, 2);
                            assert_eq!(pcm, &samples[52000 * 2..]);
                            Ok(vec![
                                word("tail", 20000, 24000),
                                word("later", 92000, 100000),
                                word("ending", 138000, 140000),
                            ])
                        }
                    },
                    &mut |event| {
                        let feed_until = match &event {
                            LiveEvent::Idle if fed < 139264 => (fed + 3200).min(139264),
                            LiveEvent::Audio { end: 139264, .. } => {
                                release.send(()).unwrap();
                                fed
                            }
                            LiveEvent::Hypothesis(_) if !committed => fed + 8192,
                            LiveEvent::Commit { text, .. } if !committed => {
                                assert_eq!(text, "Stable");
                                committed = true;
                                fed + 8192
                            }
                            LiveEvent::Deferred {
                                reason,
                                committed_through,
                                model_ready,
                            } => {
                                assert_eq!(reason, &expected_failure);
                                assert_eq!(*committed_through, 8000);
                                assert!(*model_ready);
                                assert_eq!(state.text(), "Stable");
                                assert_eq!(state.hypothesis(), " tentative tail later");
                                deferred = true;
                                192000
                            }
                            _ => fed,
                        };
                        while fed < feed_until {
                            let end = (fed + 3200).min(feed_until);
                            stream.feed(&samples[fed * 2..end * 2])?;
                            fed = end;
                        }
                        if matches!(event, LiveEvent::Deferred { .. }) {
                            stream.finish();
                        }
                        state.apply(event, || false)?;
                        Ok(LiveControl::Continue)
                    },
                );
                assert!(deferred && committed);
                state.finish(result.is_ok()).unwrap();
                match outcome {
                    1 => {
                        assert_eq!(result, Err(VoiceError::Cancelled));
                        assert_eq!(state.text(), "Stable tentative tail later");
                    }
                    2 => {
                        assert_eq!(result, Err(recovery_failure));
                        assert_eq!(state.text(), "Stable corrected tail later");
                    }
                    _ => {
                        result.unwrap();
                        assert_eq!(state.text(), "Stable corrected tail later ending");
                    }
                }
                assert!(state.hypothesis().is_empty());
                assert_eq!(state.session.incomplete(), outcome != 0);
            }
        }
    }

    #[test]
    fn incomplete_or_cancelled_recovery_cannot_publish_text_or_coverage() {
        for (samples, cancelled) in [(1001, false), (1001, true), (32000, false), (32000, true)] {
            let stream = stream();
            for chunk in [0, 32].repeat(samples).chunks(3200 * 2) {
                stream.feed(chunk).unwrap();
            }
            stream.finish();
            let result = stream.run_with(
                vad,
                || Ok(()),
                |_| {
                    if samples == 1001 {
                        Err(VoiceError::UnstableTranscript)
                    } else {
                        Ok(vec![AlignedWord {
                            text: "truncated prefix".into(),
                            start: 0,
                            end: 8000,
                        }])
                    }
                },
                |pcm| {
                    if cancelled {
                        stream.cancel();
                        super::super::recorded::decoded_chunk(pcm, "late result")
                    } else {
                        super::super::recorded::decoded_chunk(pcm, "")
                    }
                },
                &mut |event| {
                    assert!(!matches!(event, LiveEvent::Commit { .. }));
                    if let LiveEvent::Coverage(end) = event {
                        assert_eq!(end, 0);
                    }
                    Ok(LiveControl::Continue)
                },
            );
            assert_eq!(
                result,
                Err(if cancelled {
                    VoiceError::Cancelled
                } else {
                    VoiceError::IncompleteAudio
                })
            );
        }
    }

    #[test]
    fn vad_keeps_running_during_decode_and_cancel_joins_native_work() {
        let stream = stream();
        for _ in 0..3 {
            stream.feed(&[1, 32].repeat(3200)).unwrap();
        }
        let decoded = &AtomicBool::new(false);
        let exited = &AtomicBool::new(false);
        let (release, decoding) = mpsc::sync_channel(1);
        let mut observed_during_decode = false;
        let mut fed = false;
        let result = stream.run_with(
            vad,
            || Ok(()),
            move |_| {
                decoded.store(true, Ordering::Release);
                decoding.recv_timeout(Duration::from_secs(3)).unwrap();
                exited.store(true, Ordering::Release);
                Ok(Vec::new())
            },
            |_| panic!("Cancelled decode must not transcribe"),
            &mut |event| {
                match event {
                    LiveEvent::Idle if !fed && decoded.load(Ordering::Acquire) => {
                        stream.feed(&[1, 32].repeat(3200))?;
                        fed = true;
                    }
                    LiveEvent::Audio { end, .. } if end > 9600 => {
                        assert!(!exited.load(Ordering::Acquire));
                        observed_during_decode = true;
                        return Ok(LiveControl::Cancel);
                    }
                    LiveEvent::CaptureClosed => release.send(()).unwrap(),
                    _ => {}
                }
                Ok(LiveControl::Continue)
            },
        );
        assert_eq!(result, Err(VoiceError::Cancelled));
        assert!(observed_during_decode && exited.load(Ordering::Acquire));
    }
}
