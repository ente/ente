use super::{LiveControl, LiveEvent};
use crate::voice;

#[derive(Default)]
pub struct DictationState {
    pub session: voice::VoiceSession,
    text: String,
    hypothesis: String,
    last_commit_end: u64,
}
impl DictationState {
    pub fn new(live: bool) -> Self {
        Self {
            session: if live {
                voice::VoiceSession::default()
            } else {
                voice::VoiceSession::recorded()
            },
            ..Self::default()
        }
    }

    pub fn text(&self) -> &str {
        &self.text
    }

    pub fn hypothesis(&self) -> String {
        format!(
            "{}{}",
            voice::transcript_separator(&self.text, &self.hypothesis),
            self.hypothesis
        )
    }

    pub fn finish(&mut self, successful: bool) -> voice::Result<()> {
        self.session.worker_exited(successful)?;
        self.text = super::text::filter_transcription_output(&format!(
            "{}{}",
            self.text,
            self.hypothesis()
        ));
        self.hypothesis.clear();
        Ok(())
    }

    pub fn apply(
        &mut self,
        event: LiveEvent,
        finish_if_empty: impl FnOnce() -> bool,
    ) -> voice::Result<LiveControl> {
        if !self.session.worker_active() || self.session.phase() == voice::VoicePhase::Closed {
            return Ok(LiveControl::Cancel);
        }
        match event {
            LiveEvent::Ready => {}
            LiveEvent::Audio { start, end, voiced } => {
                if self.session.stop_reason().is_some() {
                    self.session.observe_drained_audio(start, end)?;
                } else if let Some(reason) =
                    self.session
                        .observe_audio(start, end, voiced.then_some(end))?
                {
                    self.session.stop(reason)?;
                    return Ok(LiveControl::Finish);
                }
            }
            LiveEvent::Hypothesis(text) => {
                self.session.observe_recognition(!text.trim().is_empty())?;
                self.hypothesis = text;
            }
            LiveEvent::Commit { start, end, text } => {
                if end <= start || start < self.last_commit_end {
                    return Err(voice::VoiceError::InvalidAudio(
                        "Transcript commits must have non-overlapping audio ranges".into(),
                    ));
                }
                self.last_commit_end = end;
                self.session.observe_recognition(!text.trim().is_empty())?;
                self.text
                    .push_str(voice::transcript_separator(&self.text, &text));
                self.text.push_str(&text);
                self.hypothesis.clear();
            }
            LiveEvent::Deferred { .. } => self.session.defer_recognition(),
            LiveEvent::Coverage(end) => self.session.recognize_through(end)?,
            LiveEvent::Idle => {
                if self.session.silence_elapsed() && finish_if_empty() {
                    self.session.stop(voice::StopReason::Silence)?;
                }
            }
            LiveEvent::CaptureClosed => {
                if self.session.stop_reason().is_none() {
                    self.session.stop(voice::StopReason::Silence)?;
                }
            }
        }
        Ok(LiveControl::Continue)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn event(state: &mut DictationState, event: LiveEvent) {
        state.apply(event, || true).unwrap();
    }

    #[test]
    fn cleanup_waits_for_completion_and_spans_commits_and_unfinished_hypotheses() {
        for successful in [false, true] {
            let mut state = DictationState::new(true);
            state.session.begin_capture().unwrap();
            event(
                &mut state,
                LiveEvent::Audio {
                    start: 0,
                    end: 32000,
                    voiced: true,
                },
            );
            event(
                &mut state,
                LiveEvent::Commit {
                    start: 0,
                    end: 16000,
                    text: "um I I".into(),
                },
            );
            event(&mut state, LiveEvent::Hypothesis("I uh think".into()));
            assert_eq!(state.text(), "um I I");
            assert_eq!(state.hypothesis(), " I uh think");
            if successful {
                event(
                    &mut state,
                    LiveEvent::Commit {
                        start: 16000,
                        end: 32000,
                        text: "I uh think".into(),
                    },
                );
                event(&mut state, LiveEvent::Coverage(32000));
            }
            state
                .session
                .stop(if successful {
                    voice::StopReason::Done
                } else {
                    voice::StopReason::Interruption
                })
                .unwrap();
            state.finish(successful).unwrap();
            assert_eq!(state.text(), "I think");
            assert!(state.hypothesis().is_empty());
            assert_eq!(state.session.incomplete(), !successful);
        }
    }

    #[test]
    fn queued_audio_is_processed_before_silence_can_stop_capture() {
        let mut state = DictationState::new(false);
        state.session.begin_capture().unwrap();
        event(
            &mut state,
            LiveEvent::Audio {
                start: 0,
                end: 16000,
                voiced: true,
            },
        );
        event(
            &mut state,
            LiveEvent::Audio {
                start: 16000,
                end: 64000,
                voiced: false,
            },
        );
        state.apply(LiveEvent::Idle, || false).unwrap();
        assert!(state.session.stop_reason().is_none());
        event(
            &mut state,
            LiveEvent::Audio {
                start: 64000,
                end: 65000,
                voiced: true,
            },
        );
        event(&mut state, LiveEvent::Idle);
        assert!(state.session.stop_reason().is_none());
        event(
            &mut state,
            LiveEvent::Audio {
                start: 65000,
                end: 113000,
                voiced: false,
            },
        );
        event(&mut state, LiveEvent::Idle);
        assert_eq!(
            state.session.stop_reason(),
            Some(voice::StopReason::Silence)
        );
    }

    #[test]
    fn recognized_word_boundaries_survive_preview_and_commit() {
        fn apply_update(state: &mut DictationState, update: voice::RecognitionUpdate) {
            if let Some((start, end, text)) = update.commit {
                event(state, LiveEvent::Commit { start, end, text });
            }
            event(state, LiveEvent::Hypothesis(update.hypothesis));
            event(state, LiveEvent::Coverage(update.boundary.end));
        }

        for (words, expected) in [
            (vec!["明", "天", "见", "面"], "明天见面"),
            (
                vec!["hello", "world", "again", "today"],
                "hello world again today",
            ),
            (
                vec!["hello", "world ", "again", "today"],
                "hello world again today",
            ),
            (
                vec!["It", "costs", "$20.", "today."],
                "It costs $20. today.",
            ),
            (
                vec!["The", "change", "is", "-5", "percent."],
                "The change is -5 percent.",
            ),
            (
                vec!["Say", "\"hello.\"", "Then", "leave."],
                "Say \"hello.\" Then leave.",
            ),
        ] {
            let mut state = DictationState::new(true);
            state.session.begin_capture().unwrap();
            let mut rolling = voice::RollingRecognizer::default();
            let aligned = || {
                words
                    .iter()
                    .enumerate()
                    .map(|(i, text)| voice::AlignedWord {
                        text: (*text).into(),
                        start: i as u64 * 1000,
                        end: (i as u64 + 1) * 1000,
                    })
                    .collect()
            };
            for i in 0..3 {
                rolling.feed(&vec![0.2; 8000], i == 0).unwrap();
                rolling.feed(&vec![0.2; 8000], false).unwrap();
                event(
                    &mut state,
                    LiveEvent::Audio {
                        start: i * 16000,
                        end: (i + 1) * 16000,
                        voiced: i == 0,
                    },
                );
                let request = rolling.next_window().unwrap().unwrap();
                apply_update(&mut state, rolling.complete(&request, aligned()).unwrap());
                assert_eq!(state.text().to_owned() + &state.hypothesis(), expected);
            }
            assert!(!state.text().is_empty());
            assert!(!state.hypothesis().is_empty());
            rolling.finish();
            let request = rolling.next_window().unwrap().unwrap();
            apply_update(&mut state, rolling.complete(&request, aligned()).unwrap());
            assert_eq!(state.text(), expected);
            assert!(state.hypothesis().is_empty());
        }
    }
}
