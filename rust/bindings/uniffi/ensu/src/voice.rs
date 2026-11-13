use ente_ensu::transcription::{DictationState, LiveControl, LiveEvent, LiveTranscription};
use ente_ensu::voice;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};
use std::time::{Duration, Instant};

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum DictationError {
    #[error("Transcription model is not downloaded")]
    NotDownloaded,
    #[error("Voice activity model is not downloaded")]
    VadNotDownloaded,
    #[error("not enough storage space")]
    StorageFull,
    #[error("Voice recording was cancelled")]
    Cancelled,
    #[error("{detail}")]
    InvalidAudio { detail: String },
    #[error("{detail}")]
    Io { detail: String },
    #[error("{detail}")]
    ProcessingFailed { detail: String },
    #[error("{detail}")]
    InvalidOperation { detail: String },
}

impl From<voice::VoiceError> for DictationError {
    fn from(value: voice::VoiceError) -> Self {
        match value {
            voice::VoiceError::NotDownloaded => Self::NotDownloaded,
            voice::VoiceError::VadNotDownloaded => Self::VadNotDownloaded,
            voice::VoiceError::StorageFull => Self::StorageFull,
            voice::VoiceError::Cancelled => Self::Cancelled,
            voice::VoiceError::InvalidAudio(detail) => Self::InvalidAudio { detail },
            voice::VoiceError::Io(detail) => Self::Io { detail },
            voice::VoiceError::ProcessingFailed(detail) => Self::ProcessingFailed { detail },
            error => Self::InvalidOperation {
                detail: error.to_string(),
            },
        }
    }
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct DictationInsertionResult {
    pub text: String,
    pub revision: u64,
    pub caret_utf16: u32,
}

#[derive(uniffi::Object)]
pub struct DictationInsertion {
    anchor: voice::ComposerAnchor,
    transfer: Mutex<voice::ComposerTransfer>,
}

#[uniffi::export]
impl DictationInsertion {
    #[uniffi::constructor]
    pub fn new(destination: String, revision: u64, start_utf16: u32, end_utf16: u32) -> Arc<Self> {
        Arc::new(Self {
            anchor: voice::ComposerAnchor {
                destination,
                revision,
                start_utf16,
                end_utf16,
            },
            transfer: Mutex::new(voice::ComposerTransfer::default()),
        })
    }

    pub fn preview(
        &self,
        text: String,
        voice_text: String,
    ) -> Result<DictationInsertionResult, DictationError> {
        let (text, caret_utf16) = voice::preview_insertion(&text, &self.anchor, &voice_text)?;
        Ok(DictationInsertionResult {
            text,
            revision: self.anchor.revision,
            caret_utf16,
        })
    }

    pub fn apply(
        &self,
        destination: String,
        mut revision: u64,
        mut text: String,
        voice_text: String,
        foreground: bool,
        keyboard_composing: bool,
    ) -> Result<DictationInsertionResult, DictationError> {
        let caret_utf16 = self
            .transfer
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .apply(
                &voice::VoiceInsertion {
                    anchor: self.anchor.clone(),
                    text: voice_text,
                },
                &destination,
                &mut revision,
                &mut text,
                foreground,
                keyboard_composing,
            )?;
        Ok(DictationInsertionResult {
            text,
            revision,
            caret_utf16,
        })
    }
}

#[derive(Debug, Clone, Copy, uniffi::Enum)]
pub enum DictationPhase {
    Preparing,
    Listening,
    Countdown,
    Finishing,
    Ready,
    Closed,
}

#[derive(Debug, Clone, Copy, uniffi::Enum)]
pub enum DictationStopReason {
    Done,
    Interruption,
    Failure,
    Discard,
}
impl From<DictationStopReason> for voice::StopReason {
    fn from(value: DictationStopReason) -> Self {
        match value {
            DictationStopReason::Done => Self::Done,
            DictationStopReason::Interruption => Self::Interruption,
            DictationStopReason::Failure => Self::Failure,
            DictationStopReason::Discard => Self::Discard,
        }
    }
}
#[derive(Debug, Clone, uniffi::Record)]
pub struct DictationSnapshot {
    pub phase: DictationPhase,
    pub text: String,
    pub hypothesis: String,
    pub worker_active: bool,
    pub incomplete: bool,
}
#[derive(uniffi::Object)]
pub struct DictationSession {
    state: Mutex<DictationState>,
    live: bool,
}

#[uniffi::export(foreign)]
pub trait DictationStreamCallback: Send + Sync {
    fn on_ready(&self);
    fn on_change(&self);
    fn on_capture_closed(&self);
}

#[derive(uniffi::Object)]
pub struct DictationStream {
    session: Arc<DictationSession>,
    stream: LiveTranscription,
    started: AtomicBool,
}

#[derive(Debug, Clone, Copy, uniffi::Enum)]
pub enum DictationFeedResult {
    Accepted,
    Closed,
}

#[uniffi::export]
impl DictationStream {
    #[uniffi::constructor]
    pub fn new(
        session: Arc<DictationSession>,
        sample_rate: u32,
        channels: u16,
    ) -> Result<Arc<Self>, DictationError> {
        let stream = LiveTranscription::new(voice::CaptureFormat {
            sample_rate,
            channels,
        })?;
        session.lock().session.begin_capture()?;
        Ok(Arc::new(Self {
            session,
            stream,
            started: AtomicBool::new(false),
        }))
    }
    pub fn feed(&self, pcm_le: &[u8]) -> Result<DictationFeedResult, DictationError> {
        Ok(match self.stream.feed(pcm_le)? {
            voice::CaptureFeedResult::Accepted => DictationFeedResult::Accepted,
            voice::CaptureFeedResult::Closed => DictationFeedResult::Closed,
        })
    }
    pub fn stop(&self, reason: DictationStopReason) -> Result<(), DictationError> {
        self.session.lock().session.stop(reason.into())?;
        if matches!(
            reason,
            DictationStopReason::Discard
                | DictationStopReason::Interruption
                | DictationStopReason::Failure
        ) {
            self.stream.cancel();
        } else {
            self.stream.finish();
        }
        Ok(())
    }
    pub fn abandon(&self, reason: DictationStopReason) -> Result<(), DictationError> {
        if !matches!(
            reason,
            DictationStopReason::Failure
                | DictationStopReason::Interruption
                | DictationStopReason::Discard
        ) {
            return Err(voice::VoiceError::InvalidState.into());
        }
        self.stop(reason)?;
        if self
            .started
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
            .is_ok()
        {
            self.session.lock().finish(false)?;
        }
        Ok(())
    }
    pub fn run(
        &self,
        transcriber: Arc<crate::transcription::Transcriber>,
        callback: Arc<dyn DictationStreamCallback>,
    ) -> Result<(), DictationError> {
        if self.started.swap(true, Ordering::AcqRel) {
            return Err(voice::VoiceError::InvalidState.into());
        }
        let mut notified_stop = false;
        let mut last_notification = Instant::now();
        let mut on_event = |event: LiveEvent| {
            if let LiveEvent::Deferred {
                reason,
                committed_through,
                model_ready,
            } = &event
            {
                let committed_ms = committed_through / 16;
                let audio_ms = self.session.lock().session.accepted_samples() / 16;
                ente_uniffi_log::info!(
                    "Dictation deferring remaining audio: reason={reason} committed_ms={committed_ms} audio_ms={audio_ms} model_ready={model_ready}"
                );
            }
            let immediate = matches!(
                &event,
                LiveEvent::Commit { .. } | LiveEvent::Deferred { .. } | LiveEvent::CaptureClosed
            );
            if matches!(&event, LiveEvent::Ready) {
                let phase = self.session.lock().session.phase();
                if phase == voice::VoicePhase::Closed {
                    return Ok(LiveControl::Cancel);
                }
                if phase == voice::VoicePhase::Listening {
                    callback.on_ready();
                }
                return Ok(LiveControl::Continue);
            }
            let control = self
                .session
                .lock()
                .apply(event, || self.stream.finish_if_empty())?;
            if !notified_stop && self.session.lock().session.stop_reason().is_some() {
                notified_stop = true;
                callback.on_capture_closed();
            }
            if immediate || last_notification.elapsed() >= Duration::from_millis(250) {
                callback.on_change();
                last_notification = Instant::now();
            }
            Ok(control)
        };
        let result = if self.session.live {
            self.stream.run(&transcriber.inner, &mut on_event)
        } else {
            self.stream.run_recorded(&transcriber.inner, &mut on_event)
        };
        let mut state = self.session.lock();
        if result.is_err() && state.session.phase() != voice::VoicePhase::Closed {
            if state.session.stop_reason() != Some(voice::StopReason::Interruption) {
                state.session.stop(voice::StopReason::Failure)?;
            }
            let accepted = state.session.accepted_samples();
            let submitted = self.stream.submitted_samples();
            if submitted > accepted {
                state.session.observe_drained_audio(accepted, submitted)?;
            }
        }
        state.finish(result.is_ok())?;
        let reason = state.session.stop_reason();
        let audio_ms = state.session.accepted_samples() / 16;
        let incomplete = state.session.incomplete();
        drop(state);
        ente_uniffi_log::info!(
            "Dictation finished: reason={reason:?} audio_ms={audio_ms} incomplete={incomplete}"
        );
        self.stream.finish();
        if !notified_stop {
            callback.on_capture_closed();
        }
        callback.on_change();
        result.map_err(Into::into)
    }
}
impl DictationSession {
    fn lock(&self) -> MutexGuard<'_, DictationState> {
        self.state.lock().unwrap_or_else(PoisonError::into_inner)
    }
}
#[uniffi::export]
impl DictationSession {
    #[uniffi::constructor]
    pub fn new(live: bool) -> Arc<Self> {
        Arc::new(Self {
            live,
            state: Mutex::new(DictationState::new(live)),
        })
    }
    pub fn stop(&self, reason: DictationStopReason) -> Result<bool, DictationError> {
        self.lock().session.stop(reason.into()).map_err(Into::into)
    }
    pub fn snapshot(&self) -> DictationSnapshot {
        let state = self.lock();
        let phase = match state.session.phase() {
            voice::VoicePhase::Preparing => DictationPhase::Preparing,
            voice::VoicePhase::Listening => DictationPhase::Listening,
            voice::VoicePhase::Countdown => DictationPhase::Countdown,
            voice::VoicePhase::Finishing => DictationPhase::Finishing,
            voice::VoicePhase::Ready => DictationPhase::Ready,
            voice::VoicePhase::Closed => DictationPhase::Closed,
        };
        DictationSnapshot {
            phase,
            text: state.text().to_owned(),
            hypothesis: state.hypothesis(),
            worker_active: state.session.worker_active(),
            incomplete: state.session.incomplete(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[derive(Default)]
    struct StreamSignals {
        stopped: std::sync::atomic::AtomicUsize,
        ready: std::sync::atomic::AtomicUsize,
    }
    impl DictationStreamCallback for StreamSignals {
        fn on_ready(&self) {
            self.ready.fetch_add(1, Ordering::Relaxed);
        }
        fn on_change(&self) {}
        fn on_capture_closed(&self) {
            self.stopped.fetch_add(1, Ordering::Relaxed);
        }
    }

    fn event(session: &DictationSession, event: LiveEvent) {
        session.lock().apply(event, || true).unwrap();
    }

    #[test]
    fn interruption_keeps_visible_text_until_actual_worker_exit() {
        let owner = DictationSession::new(true);
        let stream = DictationStream::new(owner.clone(), 16000, 1).unwrap();
        stream.started.store(true, Ordering::Release);
        event(
            &owner,
            LiveEvent::Audio {
                start: 0,
                end: 32000,
                voiced: true,
            },
        );
        event(
            &owner,
            LiveEvent::Commit {
                start: 0,
                end: 16000,
                text: "Keep this".into(),
            },
        );
        event(&owner, LiveEvent::Hypothesis("opening word".into()));
        stream.stop(DictationStopReason::Done).unwrap();
        stream.abandon(DictationStopReason::Interruption).unwrap();
        assert!(owner.snapshot().worker_active);
        assert!(DictationStream::new(owner.clone(), 16000, 1).is_err());
        owner.lock().finish(false).unwrap();
        let value = owner.snapshot();
        assert_eq!(
            format!("{}{}", value.text, value.hypothesis),
            "Keep this opening word"
        );
        assert!(!value.worker_active);
        assert!(value.incomplete);
        assert!(matches!(value.phase, DictationPhase::Ready));
        assert!(matches!(
            owner
                .lock()
                .apply(LiveEvent::Hypothesis("late".into()), || true)
                .unwrap(),
            LiveControl::Cancel
        ));
        assert!(DictationStream::new(owner, 16000, 1).is_err());
        assert!(DictationStream::new(DictationSession::new(true), 16000, 1).is_ok());
    }
    #[test]
    fn format_failure_does_not_reserve_a_worker_and_cancel_before_run_cannot_resume() {
        let owner = DictationSession::new(true);
        assert!(DictationStream::new(owner.clone(), 0, 1).is_err());
        assert!(!owner.snapshot().worker_active);
        let stream = DictationStream::new(owner.clone(), 16000, 1).unwrap();
        stream.abandon(DictationStopReason::Failure).unwrap();
        assert!(!owner.snapshot().worker_active);
        assert!(DictationStream::new(owner, 16000, 1).is_err());
        assert!(stream.feed(&[0, 0]).is_err());
    }
    #[test]
    fn missing_models_close_capture_once_without_starting_hardware() {
        for live in [true, false] {
            let owner = DictationSession::new(live);
            let stream = DictationStream::new(owner.clone(), 16000, 1).unwrap();
            let signals = Arc::new(StreamSignals::default());
            assert!(matches!(
                stream.run(
                    crate::transcription::Transcriber::new("missing".into(), "missing".into()),
                    signals.clone()
                ),
                Err(DictationError::VadNotDownloaded)
            ));
            assert_eq!(signals.ready.load(Ordering::Relaxed), 0);
            assert_eq!(signals.stopped.load(Ordering::Relaxed), 1);
            assert!(!owner.snapshot().worker_active);
            assert!(owner.snapshot().incomplete);
        }
    }
    #[test]
    fn completion_preserves_committed_text_and_discard_rejects_late_text() {
        let owner = DictationSession::new(true);
        let stream = DictationStream::new(owner.clone(), 16000, 1).unwrap();
        event(
            &owner,
            LiveEvent::Commit {
                start: 0,
                end: 16000,
                text: "partial".into(),
            },
        );
        event(&owner, LiveEvent::Hypothesis("preview".into()));
        assert!(
            owner
                .lock()
                .apply(
                    LiveEvent::Commit {
                        start: 1,
                        end: 16000,
                        text: "overlap".into()
                    },
                    || true
                )
                .is_err()
        );
        event(
            &owner,
            LiveEvent::Commit {
                start: 16000,
                end: 32000,
                text: "corrected tail".into(),
            },
        );
        assert_eq!(owner.snapshot().text, "partial corrected tail");
        assert!(owner.snapshot().hypothesis.is_empty());
        stream.abandon(DictationStopReason::Discard).unwrap();
        event(
            &owner,
            LiveEvent::Commit {
                start: 32000,
                end: 48000,
                text: "late".into(),
            },
        );
        assert_eq!(owner.snapshot().text, "partial corrected tail");
        assert!(matches!(owner.snapshot().phase, DictationPhase::Closed));
    }
}
