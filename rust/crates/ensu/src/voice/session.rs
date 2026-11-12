use super::{Result, VOICE_SAMPLE_RATE, VoiceError};

const SILENCE_SAMPLES: u64 = 3 * VOICE_SAMPLE_RATE;
const COUNTDOWN_SAMPLES: u64 = VOICE_SAMPLE_RATE * 3 / 5;
const NO_SPEECH_SAMPLES: u64 = 15 * VOICE_SAMPLE_RATE;
const SESSION_LIMIT_SAMPLES: u64 = 30 * 60 * VOICE_SAMPLE_RATE;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VoicePhase {
    Preparing,
    Listening,
    Countdown,
    Finishing,
    Ready,
    Closed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StopReason {
    Done,
    Silence,
    Interruption,
    Failure,
    Limit,
    NoSpeech,
    Discard,
}

#[derive(Debug)]
pub struct VoiceSession {
    phase: VoicePhase,
    accepted: u64,
    recognized: u64,
    waits_for_live_text: bool,
    last_voice: Option<u64>,
    stop_reason: Option<StopReason>,
    worker_active: bool,
    incomplete: bool,
}

impl Default for VoiceSession {
    fn default() -> Self {
        Self {
            phase: VoicePhase::Preparing,
            accepted: 0,
            recognized: 0,
            waits_for_live_text: true,
            last_voice: None,
            stop_reason: None,
            worker_active: false,
            incomplete: false,
        }
    }
}

impl VoiceSession {
    pub fn recorded() -> Self {
        Self {
            waits_for_live_text: false,
            ..Self::default()
        }
    }
    pub fn phase(&self) -> VoicePhase {
        self.phase
    }
    pub fn accepted_samples(&self) -> u64 {
        self.accepted
    }
    pub fn worker_active(&self) -> bool {
        self.worker_active
    }
    pub fn incomplete(&self) -> bool {
        self.incomplete
    }
    pub fn stop_reason(&self) -> Option<StopReason> {
        self.stop_reason
    }

    pub fn begin_capture(&mut self) -> Result<()> {
        if self.phase != VoicePhase::Preparing {
            return Err(VoiceError::InvalidState);
        }
        self.worker_active = true;
        self.phase = VoicePhase::Listening;
        Ok(())
    }

    pub fn defer_recognition(&mut self) {
        self.waits_for_live_text = false;
        self.update_countdown();
    }

    pub fn observe_audio(
        &mut self,
        start: u64,
        end: u64,
        voiced_end: Option<u64>,
    ) -> Result<Option<StopReason>> {
        if !matches!(self.phase, VoicePhase::Listening | VoicePhase::Countdown) {
            return Err(VoiceError::InvalidState);
        }
        if start != self.accepted
            || end <= start
            || voiced_end.is_some_and(|v| v <= start || v > end)
        {
            return Err(VoiceError::InvalidAudio(
                "Audio must be continuous and contain a valid speech range".into(),
            ));
        }
        self.accepted = end;
        if let Some(voice) = voiced_end {
            self.last_voice = Some(voice);
            self.phase = VoicePhase::Listening;
        }
        if end >= SESSION_LIMIT_SAMPLES {
            return Ok(Some(StopReason::Limit));
        }
        if self.last_voice.is_none() && end >= NO_SPEECH_SAMPLES {
            return Ok(Some(StopReason::NoSpeech));
        }
        self.update_countdown();
        Ok(None)
    }

    pub fn observe_recognition(&mut self, has_text: bool) -> Result<()> {
        if !self.worker_active || self.phase == VoicePhase::Closed {
            return Err(VoiceError::InvalidState);
        }
        if has_text && self.waits_for_live_text {
            self.waits_for_live_text = false;
            self.update_countdown();
        }
        Ok(())
    }

    fn silence_deadline(&self) -> Option<u64> {
        self.last_voice.map(|voice| {
            let deadline = voice + SILENCE_SAMPLES;
            if !self.waits_for_live_text {
                deadline
            } else {
                deadline.max(NO_SPEECH_SAMPLES)
            }
        })
    }
    fn update_countdown(&mut self) {
        if matches!(self.phase, VoicePhase::Listening | VoicePhase::Countdown) {
            self.phase = if self.silence_deadline().is_some_and(|deadline| {
                self.accepted >= deadline - (SILENCE_SAMPLES - COUNTDOWN_SAMPLES)
            }) {
                VoicePhase::Countdown
            } else {
                VoicePhase::Listening
            };
        }
    }
    pub fn silence_elapsed(&self) -> bool {
        self.phase == VoicePhase::Countdown
            && self
                .silence_deadline()
                .is_some_and(|deadline| self.accepted >= deadline)
    }
    pub fn stop(&mut self, reason: StopReason) -> Result<bool> {
        if self.phase == VoicePhase::Closed {
            return Ok(false);
        }
        if reason == StopReason::Discard {
            self.stop_reason = Some(reason);
            self.phase = VoicePhase::Closed;
            return Ok(true);
        }
        if !self.worker_active {
            return Err(VoiceError::InvalidState);
        }
        let first = self.stop_reason.is_none();
        if first || matches!(reason, StopReason::Interruption | StopReason::Failure) {
            self.stop_reason = Some(reason);
            self.phase = VoicePhase::Finishing;
        }
        Ok(first)
    }
    pub fn recognize_through(&mut self, end: u64) -> Result<()> {
        if !self.worker_active {
            return Err(VoiceError::InvalidState);
        }
        if end < self.recognized || end > self.accepted {
            return Err(VoiceError::InvalidAudio(
                "Recognition coverage is outside the accepted audio range".into(),
            ));
        }
        self.recognized = end;
        Ok(())
    }
    pub fn observe_drained_audio(&mut self, start: u64, end: u64) -> Result<()> {
        if !self.worker_active || self.phase == VoicePhase::Closed || self.stop_reason.is_none() {
            return Err(VoiceError::InvalidState);
        }
        if start != self.accepted || end <= start {
            return Err(VoiceError::InvalidAudio(
                "Drained audio must continue the accepted audio range".into(),
            ));
        }
        self.accepted = end;
        Ok(())
    }
    pub fn worker_exited(&mut self, successful: bool) -> Result<()> {
        if !self.worker_active {
            return Err(VoiceError::InvalidState);
        }
        let reason = self.stop_reason.ok_or(VoiceError::InvalidState)?;
        self.worker_active = false;
        self.incomplete = !successful
            || self.recognized < self.accepted
            || matches!(reason, StopReason::Interruption | StopReason::Failure);
        if self.phase != VoicePhase::Closed {
            self.phase = VoicePhase::Ready;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn speaking() -> VoiceSession {
        let mut session = VoiceSession::default();
        session.begin_capture().unwrap();
        session.observe_audio(0, 16000, Some(16000)).unwrap();
        session.observe_recognition(true).unwrap();
        session
    }

    #[test]
    fn silence_uses_the_same_audio_clock_after_live_or_deferred_recognition() {
        for (mut session, deferred) in [
            (speaking(), false),
            (VoiceSession::recorded(), false),
            (VoiceSession::default(), true),
        ] {
            if session.phase() == VoicePhase::Preparing {
                session.begin_capture().unwrap();
                session.observe_audio(0, 16000, Some(16000)).unwrap();
            }
            if deferred {
                session.defer_recognition();
            }
            session.observe_audio(16000, 32000, None).unwrap();
            assert!(!session.silence_elapsed());
            session.observe_audio(32000, 64000, None).unwrap();
            assert!(session.silence_elapsed());
            assert!(session.stop(StopReason::Silence).unwrap());
            assert!(!session.stop(StopReason::Done).unwrap());
            assert!(session.worker_active());
            assert_eq!(session.begin_capture(), Err(VoiceError::InvalidState));
            session.recognize_through(64000).unwrap();
            session.worker_exited(true).unwrap();
            assert_eq!(session.phase(), VoicePhase::Ready);
            assert!(!session.incomplete());
        }
    }

    #[test]
    fn live_grace_ends_with_text_or_timeout_and_later_speech_resets_silence() {
        for has_text in [false, true] {
            let mut session = VoiceSession::default();
            session.begin_capture().unwrap();
            session.observe_audio(0, 32000, Some(24000)).unwrap();
            session.observe_recognition(false).unwrap();
            session.observe_audio(32000, 80000, None).unwrap();
            assert_eq!(session.phase(), VoicePhase::Listening);
            session.observe_audio(80000, 13 * 16000, None).unwrap();
            assert!(!session.silence_elapsed());
            assert_eq!(session.silence_deadline(), Some(15 * 16000));
            let resumed_at = if has_text {
                session.observe_recognition(true).unwrap();
                13 * 16000
            } else {
                session.observe_audio(13 * 16000, 15 * 16000, None).unwrap();
                15 * 16000
            };
            assert!(session.silence_elapsed());
            let voice_end = resumed_at + 16000;
            session
                .observe_audio(resumed_at, voice_end, Some(voice_end))
                .unwrap();
            assert!(!session.silence_elapsed());
            assert_eq!(session.phase(), VoicePhase::Listening);
            session
                .observe_audio(voice_end, voice_end + 32000, None)
                .unwrap();
            assert!(!session.silence_elapsed());
            session
                .observe_audio(voice_end + 32000, voice_end + 48000, None)
                .unwrap();
            assert!(session.silence_elapsed());
        }
    }

    #[test]
    fn silence_and_duration_limits_apply_to_both_tiers() {
        for mut session in [VoiceSession::default(), VoiceSession::recorded()] {
            session.begin_capture().unwrap();
            assert_eq!(
                session.observe_audio(0, NO_SPEECH_SAMPLES, None).unwrap(),
                Some(StopReason::NoSpeech)
            );
            assert!(!session.silence_elapsed());
            assert_eq!(
                session
                    .observe_audio(
                        NO_SPEECH_SAMPLES,
                        SESSION_LIMIT_SAMPLES,
                        Some(SESSION_LIMIT_SAMPLES)
                    )
                    .unwrap(),
                Some(StopReason::Limit)
            );
        }
    }

    #[test]
    fn interruption_retains_ownership_until_exit_and_cannot_resume() {
        let mut session = speaking();
        session.stop(StopReason::Done).unwrap();
        session.stop(StopReason::Interruption).unwrap();
        assert!(session.worker_active());
        assert_eq!(session.phase(), VoicePhase::Finishing);
        session.observe_drained_audio(16000, 32000).unwrap();
        session.worker_exited(false).unwrap();
        assert!(session.incomplete());
        assert_eq!(session.phase(), VoicePhase::Ready);
        assert_eq!(session.begin_capture(), Err(VoiceError::InvalidState));
        let mut fresh = VoiceSession::default();
        fresh.begin_capture().unwrap();
        fresh.observe_audio(0, 16000, Some(16000)).unwrap();
        fresh.observe_audio(16000, 80000, None).unwrap();
        assert!(!fresh.silence_elapsed());
    }
}
