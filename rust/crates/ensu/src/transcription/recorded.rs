use std::ops::Range;
use std::time::Duration;

use super::vad::Vad;

use super::{LiveControl, LiveEvent, LiveTranscription, StreamNormalizer, Transcriber};
use crate::voice::{AlignedWord, RecognitionUpdate, Result, TranscriptBoundary, VoiceError};

const MAX_RECORDED_SAMPLES: usize = (30 * 60 + 4) * 16_000;

pub(super) fn chunk_end(samples: &[f32]) -> usize {
    use crate::voice::{MAX_WINDOW_SAMPLES, VOICE_SAMPLE_RATE};

    if samples.len() <= MAX_WINDOW_SAMPLES {
        samples.len()
    } else {
        let limit = MAX_WINDOW_SAMPLES.min(samples.len() - VOICE_SAMPLE_RATE as usize);
        let start = limit - 2 * VOICE_SAMPLE_RATE as usize;
        let offset = samples[start..limit]
            .as_chunks::<{ super::VAD_FRAME_SAMPLES }>()
            .0
            .iter()
            .enumerate()
            .map(|(index, frame)| {
                (
                    index,
                    frame.iter().map(|sample| sample * sample).sum::<f32>(),
                )
            })
            .min_by(|a, b| a.1.total_cmp(&b.1))
            .map_or(0, |(index, _)| (index + 1) * super::VAD_FRAME_SAMPLES);
        start + offset
    }
}

#[derive(Default)]
pub(super) struct RecordedPcm {
    bytes: Vec<u8>,
    speech: Vec<Range<usize>>,
}

impl RecordedPcm {
    pub fn push(&mut self, samples: &[f32], voiced: bool) -> Result<()> {
        let start = self.bytes.len() / 2;
        if samples.len() > MAX_RECORDED_SAMPLES.saturating_sub(start) {
            return Err(VoiceError::BacklogFull);
        }
        self.bytes.extend(samples.iter().flat_map(|sample| {
            ((sample * 32768.0).round().clamp(-32768.0, 32767.0) as i16).to_le_bytes()
        }));
        if voiced && !samples.is_empty() {
            let end = start + samples.len();
            if let Some(previous) = self.speech.last_mut().filter(|range| range.end == start) {
                previous.end = end;
            } else {
                self.speech.push(start..end);
            }
        }
        Ok(())
    }

    #[cfg(test)]
    pub fn bytes(&self) -> &[u8] {
        &self.bytes
    }

    pub fn transcribe(
        &self,
        boundary: &TranscriptBoundary,
        provisional: &[AlignedWord],
        mut decode: impl FnMut(&[u8]) -> Result<Vec<AlignedWord>>,
        mut on_update: impl FnMut(RecognitionUpdate) -> Result<()>,
    ) -> Result<()> {
        use crate::voice::{MAX_WINDOW_SAMPLES, VOICE_SAMPLE_RATE};

        let total = self.bytes.len() / 2;
        let mut boundary = boundary.clone();
        let mut provisional = provisional.to_vec();
        if self.speech.is_empty() && provisional.is_empty() {
            boundary.end = total as u64;
            return on_update(boundary.pending_update(provisional));
        }
        while boundary.end < total as u64 {
            let start = boundary.start() as usize;
            let available = (start + MAX_WINDOW_SAMPLES + VOICE_SAMPLE_RATE as usize).min(total);
            let samples = super::audio::pcm16_samples(&self.bytes[start * 2..available * 2])
                .map_err(|error| super::voice_error("Read recorded audio", error))?;
            let normal_end = start + chunk_end(&samples);
            let recovery_end = (start + super::MAX_RECORDED_WINDOW_SAMPLES).min(total);
            let mut progressed = false;
            let mut failure = VoiceError::IncompleteAudio;
            for end in [normal_end, recovery_end] {
                if end as u64 <= boundary.end {
                    continue;
                }
                let result = decode(&self.bytes[start * 2..end * 2]).and_then(|words| {
                    let update =
                        boundary.recorded_update(words, &provisional, end - start, end == total)?;
                    if update.commit.is_none()
                        && update.provisional.is_empty()
                        && !self.has_speech(boundary.end as usize..end)
                    {
                        let mut next = TranscriptBoundary::default();
                        next.end = if end == total {
                            end as u64
                        } else {
                            (end as u64 - VOICE_SAMPLE_RATE * 3 / 2).max(boundary.end)
                        };
                        return Ok(next.pending_update(Vec::new()));
                    }
                    Ok(update)
                });
                match result {
                    Ok(update) => {
                        provisional = update.provisional.clone();
                        if update.boundary.end <= boundary.end {
                            on_update(update)?;
                            failure = VoiceError::IncompleteAudio;
                        } else {
                            boundary = update.boundary.clone();
                            on_update(update)?;
                            if end == total {
                                if self.has_speech(
                                    (boundary.end as usize + super::ENDPOINT_PADDING_SAMPLES)
                                        .min(total)..total,
                                ) {
                                    return Err(VoiceError::IncompleteAudio);
                                }
                                if boundary.end < total as u64 {
                                    boundary.end = total as u64;
                                    on_update(boundary.pending_update(provisional))?;
                                }
                                return Ok(());
                            }
                            progressed = true;
                            break;
                        }
                    }
                    Err(error @ VoiceError::IncompleteAudio) => {
                        failure = error;
                    }
                    Err(error) => {
                        if error != VoiceError::Cancelled {
                            on_update(boundary.pending_update(provisional))?;
                        }
                        return Err(error);
                    }
                }
                if normal_end == recovery_end {
                    break;
                }
            }
            if !progressed {
                on_update(boundary.pending_update(provisional))?;
                return Err(failure);
            }
        }
        Ok(())
    }

    fn has_speech(&self, range: Range<usize>) -> bool {
        let index = self
            .speech
            .partition_point(|speech| speech.end <= range.start);
        range.start < range.end
            && self
                .speech
                .get(index)
                .is_some_and(|speech| speech.start < range.end)
    }
}

impl Drop for RecordedPcm {
    fn drop(&mut self) {
        use zeroize::Zeroize;
        self.bytes.zeroize();
    }
}

#[cfg(test)]
pub(super) fn decoded_chunk(pcm: &[u8], text: &str) -> Result<Vec<AlignedWord>> {
    if text.is_empty() {
        return Ok(Vec::new());
    }
    Ok(vec![AlignedWord {
        text: text.into(),
        start: (pcm.len() as u64 / 2).saturating_sub(1600),
        end: pcm.len() as u64 / 2,
    }])
}

impl LiveTranscription {
    pub fn run_recorded(
        &self,
        transcriber: &Transcriber,
        on_event: &mut impl FnMut(LiveEvent) -> Result<LiveControl>,
    ) -> Result<()> {
        self.run_recorded_with(
            || transcriber.live_vad(),
            |pcm| transcriber.transcribe_tail(pcm, || self.queue.is_cancelled()),
            on_event,
        )
    }

    fn run_recorded_with(
        &self,
        make_vad: impl FnOnce() -> Result<Box<dyn Vad>>,
        decode: impl FnMut(&[u8]) -> Result<Vec<AlignedWord>>,
        on_event: &mut impl FnMut(LiveEvent) -> Result<LiveControl>,
    ) -> Result<()> {
        let _capture = self.start()?;
        let mut vad = make_vad()?;
        let mut normalizer = StreamNormalizer::new(self.queue.format())?;
        self.emit(LiveEvent::Ready, on_event)?;
        let mut pcm = RecordedPcm::default();
        let mut accepted = 0_u64;
        let mut notified_stop = false;
        loop {
            self.check()?;
            let chunk = self.queue.take();
            let had_chunk = chunk.is_some();
            let mut emit = |frame: &[f32], real: usize| -> Result<()> {
                let voiced = vad.is_speech(frame).map_err(|error| {
                    super::voice_error("Detect speech in recorded audio", error)
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
                pcm.push(&frame[..real], voiced)
            };
            if let Some(chunk) = chunk {
                normalizer.push(&chunk, &mut emit)?;
            }
            let drained = self.queue.is_drained();
            if drained {
                normalizer.finish(&mut emit)?;
            }
            if self.queue.is_closed() && !notified_stop {
                self.emit(LiveEvent::CaptureClosed, on_event)?;
                notified_stop = true;
            }
            if drained {
                break;
            }
            if !had_chunk {
                self.emit(LiveEvent::Idle, on_event)?;
                std::thread::sleep(Duration::from_millis(10));
            }
        }
        drop(vad);
        drop(normalizer);
        self.check()?;
        self.finish_recording(&pcm, &TranscriptBoundary::default(), &[], decode, on_event)
    }

    pub(super) fn finish_recording(
        &self,
        pcm: &RecordedPcm,
        boundary: &TranscriptBoundary,
        provisional: &[AlignedWord],
        mut decode: impl FnMut(&[u8]) -> Result<Vec<AlignedWord>>,
        on_event: &mut impl FnMut(LiveEvent) -> Result<LiveControl>,
    ) -> Result<()> {
        pcm.transcribe(
            boundary,
            provisional,
            |bytes| {
                self.check()?;
                let words = decode(bytes)?;
                self.check()?;
                Ok(words)
            },
            |update| {
                self.check()?;
                if let Some((start, end, text)) = update.commit {
                    self.emit(LiveEvent::Commit { start, end, text }, on_event)?;
                }
                self.emit(LiveEvent::Hypothesis(update.hypothesis), on_event)?;
                self.emit(LiveEvent::Coverage(update.boundary.end), on_event)
            },
        )
    }
}

#[cfg(test)]
mod tests {
    use super::super::vad::EnergyVad;
    use super::*;
    use crate::voice::CaptureFormat;

    #[test]
    fn recorded_decoding_bounds_windows_preserves_tails_and_stops_on_cancel() {
        use crate::voice::MAX_WINDOW_SAMPLES;

        let mut samples = vec![0.25; MAX_WINDOW_SAMPLES * 3 + 1];
        let quiet = MAX_WINDOW_SAMPLES - 2 * 16000 + 10 * super::super::VAD_FRAME_SAMPLES;
        samples[quiet..quiet + super::super::VAD_FRAME_SAMPLES].fill(0.0);
        let mut pcm = RecordedPcm::default();
        pcm.push(&samples, true).unwrap();
        let mut calls = 0;
        let mut previous_window_end = 0;
        let mut covered = 0;
        let boundary = std::cell::RefCell::new(TranscriptBoundary::default());
        pcm.transcribe(
            &TranscriptBoundary::default(),
            &[],
            |bytes| {
                let boundary = boundary.borrow();
                let start = boundary.start() as usize;
                let end = start + bytes.len() / 2;
                assert!(bytes.len() <= MAX_WINDOW_SAMPLES * 2);
                if calls == 0 {
                    assert_eq!(end, quiet + super::super::VAD_FRAME_SAMPLES);
                } else {
                    assert!(start < boundary.end as usize);
                    assert!(boundary.end < previous_window_end as u64);
                }
                previous_window_end = end;
                calls += 1;
                let word_end = if end == samples.len() {
                    end
                } else {
                    end - 32000
                };
                Ok(vec![AlignedWord {
                    text: "again".into(),
                    start: (word_end - start - 1600) as u64,
                    end: (word_end - start) as u64,
                }])
            },
            |update| {
                assert!(update.boundary.end > covered);
                covered = update.boundary.end;
                *boundary.borrow_mut() = update.boundary;
                Ok(())
            },
        )
        .unwrap();
        assert_eq!(covered, samples.len() as u64);
        assert!(calls > 3);
        let mut calls = 0;
        let mut pending = String::new();
        assert_eq!(
            pcm.transcribe(
                &TranscriptBoundary::default(),
                &[],
                |bytes| {
                    calls += 1;
                    if calls == 1 {
                        decoded_chunk(bytes, "unfinished")
                    } else {
                        Err(VoiceError::Cancelled)
                    }
                },
                |update| {
                    assert!(update.commit.is_none());
                    pending = update.hypothesis;
                    Ok(())
                },
            ),
            Err(VoiceError::Cancelled)
        );
        assert_eq!(calls, 2);
        assert_eq!(pending, "unfinished");

        let mut pcm = RecordedPcm::default();
        pcm.push(&vec![0.0; MAX_WINDOW_SAMPLES], false).unwrap();
        pcm.push(&vec![0.25; 16000], true).unwrap();
        let mut decoded = 0;
        let mut covered = 0;
        assert_eq!(
            pcm.transcribe(
                &TranscriptBoundary::default(),
                &[],
                |pcm| {
                    decoded += 1;
                    decoded_chunk(pcm, "")
                },
                |update| {
                    assert!(update.commit.is_none() && update.hypothesis.is_empty());
                    covered = update.boundary.end;
                    Ok(())
                },
            ),
            Err(VoiceError::IncompleteAudio)
        );
        assert_eq!(decoded, 2);
        assert!(covered > 0 && covered <= MAX_WINDOW_SAMPLES as u64);
    }

    #[test]
    fn recorded_capacity_drains_resampler_and_rejects_overflow_atomically() {
        let prefix = (30 * 60 - 2) * 16_000;
        let mut pcm = RecordedPcm {
            bytes: vec![0; prefix * 2],
            speech: Vec::new(),
        };
        let mut normalizer = StreamNormalizer::new(CaptureFormat {
            sample_rate: 47_999,
            channels: 1,
        })
        .unwrap();
        let input = vec![0; 4799 * 2];
        let accepted = std::cell::Cell::new(0);
        let mut emit = |frame: &[f32], real: usize| {
            accepted.set(accepted.get() + real);
            pcm.push(&frame[..real], true)
        };
        while accepted.get() < 2 * 16_000 {
            normalizer.push(&input, &mut emit).unwrap();
        }
        for _ in 0..20 {
            normalizer.push(&input, &mut emit).unwrap();
        }
        normalizer.finish(&mut emit).unwrap();
        assert!(accepted.get() > 5 * 16_000);
        assert_eq!(pcm.bytes().len(), (prefix + accepted.get()) * 2);
        pcm.bytes.resize((MAX_RECORDED_SAMPLES - 1) * 2, 0);
        pcm.push(&[0.25], true).unwrap();
        assert_eq!(pcm.bytes().len(), MAX_RECORDED_SAMPLES * 2);
        assert_eq!(pcm.push(&[0.5], true), Err(VoiceError::BacklogFull));
        assert_eq!(
            &pcm.bytes()[pcm.bytes().len() - 2..],
            &8192_i16.to_le_bytes()
        );
    }

    #[test]
    fn recorded_completion_preserves_the_tail_and_cancellation_suppresses_results() {
        use super::super::DictationState;

        for (cancelled, incomplete) in [(false, false), (true, false), (false, true)] {
            let stream = LiveTranscription::new(CaptureFormat {
                sample_rate: 16000,
                channels: 1,
            })
            .unwrap();
            let audio = [0, 32].repeat(12 * 16000 + 1001);
            let mut chunks = audio.chunks(6400);
            let mut state = DictationState::new(false);
            state.session.begin_capture().unwrap();
            let mut closed = 0;
            let mut decoded = 0;
            let mut covered = 0;
            let result = stream.run_recorded_with(
                || {
                    Ok(Box::new(EnergyVad::new(
                        super::super::VAD_FRAME_SAMPLES,
                        0.01,
                    )))
                },
                |pcm| {
                    assert!(
                        !pcm.is_empty()
                            && pcm.len() <= super::super::MAX_RECORDED_WINDOW_SAMPLES * 2
                    );
                    decoded += 1;
                    if decoded == 1 {
                        let end = pcm.len() as u64 / 2 - 32000;
                        return Ok(vec![AlignedWord {
                            text: "dictated words".into(),
                            start: end - 1600,
                            end,
                        }]);
                    }
                    if cancelled {
                        stream.cancel();
                    }
                    decoded_chunk(pcm, if incomplete { "" } else { "continued" })
                },
                &mut |event| {
                    match event {
                        LiveEvent::Ready | LiveEvent::Idle => {
                            if let Some(chunk) = chunks.next() {
                                stream.feed(chunk)?;
                            } else {
                                stream.finish();
                            }
                        }
                        LiveEvent::CaptureClosed => closed += 1,
                        LiveEvent::Commit { .. } => assert_eq!(closed, 1),
                        LiveEvent::Coverage(end) => covered = end,
                        _ => {}
                    }
                    state.apply(event, || false)?;
                    Ok(LiveControl::Continue)
                },
            );
            assert_eq!(closed, 1);
            assert_eq!(decoded, 2);
            state.session.worker_exited(result.is_ok()).unwrap();
            if cancelled || incomplete {
                assert_eq!(
                    result,
                    Err(if cancelled {
                        VoiceError::Cancelled
                    } else {
                        VoiceError::IncompleteAudio
                    })
                );
                assert_eq!(state.text(), "dictated words");
                assert!(covered > 0 && covered < audio.len() as u64 / 2);
                assert!(state.session.incomplete());
            } else {
                result.unwrap();
                assert_eq!(state.text(), "dictated words continued");
                assert_eq!(covered, audio.len() as u64 / 2);
                assert!(!state.session.incomplete());
            }
        }
    }

    #[test]
    fn silence_stop_preserves_transcription_when_a_capture_buffer_arrives_late() {
        use super::super::DictationState;
        use crate::voice::{CaptureFeedResult, StopReason};

        let stream = LiveTranscription::new(CaptureFormat {
            sample_rate: 16000,
            channels: 1,
        })
        .unwrap();
        let mut state = DictationState::new(false);
        state.session.begin_capture().unwrap();
        let mut audio = [0, 32].repeat(512);
        audio.extend(vec![0; (3 * 16000_usize).div_ceil(512) * 512 * 2]);
        let mut chunks = audio.chunks(1024);
        let mut capture_closed = false;
        let mut late_buffer = false;
        stream
            .run_recorded_with(
                || {
                    Ok(Box::new(EnergyVad::new(
                        super::super::VAD_FRAME_SAMPLES,
                        0.01,
                    )))
                },
                |pcm| {
                    assert_eq!(pcm, audio);
                    decoded_chunk(pcm, "Complete recorded transcript")
                },
                &mut |event| {
                    let idle = matches!(event, LiveEvent::Idle);
                    if matches!(event, LiveEvent::CaptureClosed) {
                        capture_closed = true;
                    }
                    let control = state.apply(event, || stream.finish_if_empty())?;
                    if idle && state.session.stop_reason() == Some(StopReason::Silence) {
                        assert!(!capture_closed);
                        assert_eq!(stream.feed(&[0; 3200])?, CaptureFeedResult::Closed);
                        late_buffer = true;
                    } else if idle {
                        stream.feed(chunks.next().unwrap())?;
                    }
                    Ok(control)
                },
            )
            .unwrap();
        state.session.worker_exited(true).unwrap();
        assert!(late_buffer);
        assert!(capture_closed);
        assert_eq!(state.session.stop_reason(), Some(StopReason::Silence));
        assert!(!state.session.incomplete());
        assert_eq!(state.text(), "Complete recorded transcript");
        assert_eq!(stream.submitted_samples(), (audio.len() / 2) as u64);
    }
}
