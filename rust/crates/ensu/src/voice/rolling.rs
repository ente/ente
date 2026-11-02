use std::collections::VecDeque;

use super::{
    AudioRing, MAX_WINDOW_SAMPLES, Result, VOICE_SAMPLE_RATE, VoiceError, transcript_separator,
};

const PRE_SPEECH: u64 = VOICE_SAMPLE_RATE;
const PHRASE_SILENCE: u64 = VOICE_SAMPLE_RATE * 3;
const LOOKBACK: u64 = VOICE_SAMPLE_RATE * 3 / 2;
const UPDATE_SAMPLES: u64 = VOICE_SAMPLE_RATE / 2;
const ALIGNMENT_TOLERANCE: u64 = VOICE_SAMPLE_RATE / 5;
const REQUIRED_OBSERVATIONS: u8 = 3;
const RIGHT_CONTEXT_WORDS: usize = 2;

#[derive(Clone, Debug)]
pub(crate) struct AlignedWord {
    pub text: String,
    pub start: u64,
    pub end: u64,
}

pub(crate) struct DecodeWindow {
    pub id: u64,
    pub start: u64,
    pub end: u64,
    pub final_phrase: bool,
    pub samples: Vec<f32>,
}

#[derive(Debug)]
pub(crate) struct RecognitionUpdate {
    pub commit: Option<(u64, u64, String)>,
    pub hypothesis: String,
    pub provisional: Vec<AlignedWord>,
    pub boundary: TranscriptBoundary,
}

#[derive(Clone, Debug, Default)]
pub(crate) struct TranscriptBoundary {
    pub end: u64,
    anchor: Option<AlignedWord>,
}

impl TranscriptBoundary {
    pub fn start(&self) -> u64 {
        self.anchor.as_ref().map_or(self.end, |anchor| {
            self.end
                .saturating_sub(LOOKBACK)
                .min(anchor.start.saturating_sub(PRE_SPEECH))
        })
    }

    pub fn recorded_update(
        &self,
        words: Vec<AlignedWord>,
        provisional: &[AlignedWord],
        samples: usize,
        final_window: bool,
    ) -> Result<RecognitionUpdate> {
        let end = self.start() + samples as u64;
        let words = absolute_words(words, self.start(), end)?;
        let skip = self.overlap_end(&words)?;
        if words[skip..].is_empty() {
            return Ok(self.pending_update(provisional.to_vec()));
        }
        let words = merge_provisional(provisional, &words[skip..], self.start(), end)?;
        let count = words
            .iter()
            .take_while(|word| {
                word.end
                    <= if final_window {
                        end
                    } else {
                        end.saturating_sub(LOOKBACK)
                    }
            })
            .count();
        if count > 0 && words[count - 1].end <= self.end {
            return Err(VoiceError::UnstableTranscript);
        }
        let boundary = if count == 0 {
            self.clone()
        } else {
            let anchor = words[count - 1].clone();
            Self {
                end: anchor.end,
                anchor: Some(anchor),
            }
        };
        let commit = (boundary.end > self.end)
            .then(|| (self.end, boundary.end, join_words(&words[..count])));
        let provisional = words[count..].to_vec();
        Ok(RecognitionUpdate {
            commit,
            hypothesis: join_words(&provisional),
            provisional,
            boundary,
        })
    }

    pub fn pending_update(&self, provisional: Vec<AlignedWord>) -> RecognitionUpdate {
        RecognitionUpdate {
            commit: None,
            hypothesis: join_words(&provisional),
            provisional,
            boundary: self.clone(),
        }
    }

    fn overlap_end(&self, words: &[AlignedWord]) -> Result<usize> {
        let Some(anchor) = &self.anchor else {
            return Ok(0);
        };
        if words.is_empty() {
            return Ok(0);
        }
        let anchor_key = alignment_key(&anchor.text);
        for same_text in [true, false] {
            let mut matches = words.iter().enumerate().filter_map(|(i, word)| {
                let duration = if same_text {
                    (word.end - word.start).min(anchor.end - anchor.start)
                } else {
                    (word.end - word.start).max(anchor.end - anchor.start)
                };
                let overlap = word
                    .end
                    .min(anchor.end)
                    .saturating_sub(word.start.max(anchor.start));
                (word.start.abs_diff(anchor.start) <= ALIGNMENT_TOLERANCE
                    && word.end.abs_diff(anchor.end) <= ALIGNMENT_TOLERANCE
                    && (overlap * 2 > duration
                        || (same_text && duration == 0 && word.start == anchor.start))
                    && if same_text {
                        alignment_key(&word.text) == anchor_key
                    } else {
                        word.end <= self.end
                    })
                .then_some(i + 1)
            });
            match (matches.next(), matches.next()) {
                (Some(end), None) => return Ok(end),
                (Some(_), Some(_)) => return Err(VoiceError::UnstableTranscript),
                _ => {}
            }
        }
        if words[0].start >= self.end {
            Ok(0)
        } else {
            Err(VoiceError::UnstableTranscript)
        }
    }
}

struct Region {
    start: u64,
    last_voice: u64,
    end: Option<u64>,
}

#[derive(Default)]
pub(crate) struct RollingRecognizer {
    ring: AudioRing,
    regions: VecDeque<Region>,
    previous: Vec<AlignedWord>,
    observations: Vec<u8>,
    anchor: Option<AlignedWord>,
    covered: u64,
    last_decoded: u64,
    next_id: u64,
    in_flight: Option<(u64, u64, u64, bool)>,
}

impl RollingRecognizer {
    pub fn feed(&mut self, samples: &[f32], voiced: bool) -> Result<()> {
        if samples.is_empty() {
            return Err(VoiceError::InvalidAudio("Audio buffer is empty".into()));
        }
        let start = self.ring.accepted();
        self.ring.push(start, samples)?;
        let end = self.ring.accepted();
        if voiced {
            if let Some(region) = self.regions.back_mut().filter(|r| r.end.is_none()) {
                region.last_voice = end;
            } else {
                let prior_end = self
                    .regions
                    .back()
                    .and_then(|r| r.end)
                    .unwrap_or(self.covered);
                self.regions.push_back(Region {
                    start: start
                        .saturating_sub(PRE_SPEECH)
                        .max(self.ring.retained_from())
                        .max(prior_end),
                    last_voice: end,
                    end: None,
                });
            }
        } else if let Some(region) = self.regions.back_mut().filter(|r| r.end.is_none())
            && end - region.last_voice >= PHRASE_SILENCE
        {
            region.end = Some(end);
        }
        self.release_silence()?;
        Ok(())
    }

    fn release_silence(&mut self) -> Result<()> {
        if self.regions.is_empty() {
            let end = self.ring.accepted();
            self.ring.acknowledge(
                end,
                end.saturating_sub(PRE_SPEECH)
                    .max(self.ring.retained_from()),
            )?;
            self.covered = self.covered.max(self.ring.retained_from());
        }
        Ok(())
    }

    pub fn finish(&mut self) {
        if let Some(region) = self.regions.back_mut().filter(|r| r.end.is_none()) {
            region.end = Some(self.ring.accepted());
        }
    }

    pub fn next_window(&mut self) -> Result<Option<DecodeWindow>> {
        if self.in_flight.is_some() {
            return Ok(None);
        }
        let Some(region) = self.regions.front() else {
            return Ok(None);
        };
        let end = region
            .end
            .unwrap_or(self.ring.accepted())
            .min(region.start + MAX_WINDOW_SAMPLES as u64);
        let final_phrase = region.end == Some(end);
        let at_limit = end - region.start == MAX_WINDOW_SAMPLES as u64;
        if !final_phrase
            && !at_limit
            && (end - region.start < UPDATE_SAMPLES || end < self.last_decoded + UPDATE_SAMPLES)
        {
            return Ok(None);
        }
        self.next_id += 1;
        self.in_flight = Some((self.next_id, region.start, end, final_phrase));
        Ok(Some(DecodeWindow {
            id: self.next_id,
            start: region.start,
            end,
            final_phrase,
            samples: self.ring.window(region.start, end)?,
        }))
    }

    pub fn complete(
        &mut self,
        request: &DecodeWindow,
        words: Vec<AlignedWord>,
    ) -> Result<RecognitionUpdate> {
        if self.in_flight != Some((request.id, request.start, request.end, request.final_phrase)) {
            return Err(VoiceError::StaleEvent);
        }
        let current = absolute_words(words, request.start, request.end)?;
        let boundary = self.boundary();
        let skip = boundary.overlap_end(&current)?;
        let remaining = &current[skip..];
        let old_skip = boundary.overlap_end(&self.previous)?;
        let mut observations = vec![1; current.len()];
        let agreed_prefix = remaining
            .iter()
            .zip(&self.previous[old_skip..])
            .take_while(|(a, b)| {
                alignment_key(&a.text) == alignment_key(&b.text)
                    && a.start.abs_diff(b.start) <= ALIGNMENT_TOLERANCE
            })
            .count();
        for i in 0..agreed_prefix {
            observations[skip + i] = self.observations[old_skip + i].saturating_add(1);
        }
        let mature = observations[skip..]
            .iter()
            .take_while(|count| **count >= REQUIRED_OBSERVATIONS)
            .count()
            .saturating_sub(RIGHT_CONTEXT_WORDS);
        let agreed = remaining
            .iter()
            .take(mature)
            .take_while(|word| word.end <= request.end.saturating_sub(LOOKBACK))
            .count();
        let commit_count = if request.final_phrase {
            remaining.len()
        } else {
            agreed
        };
        if request.final_phrase {
            let last_word = remaining.last().ok_or(VoiceError::IncompleteAudio)?;
            if self.regions.front().is_some_and(|region| {
                last_word.end.saturating_add(VOICE_SAMPLE_RATE / 2) < region.last_voice
            }) {
                return Err(VoiceError::IncompleteAudio);
            }
        }
        let commit = if commit_count > 0 {
            let end = if request.final_phrase {
                request.end
            } else {
                remaining[commit_count - 1].end
            };
            if end <= self.covered {
                return Err(VoiceError::UnstableTranscript);
            }
            let text = join_words(&remaining[..commit_count]);
            let start = self.covered.max(request.start);
            self.covered = end;
            self.anchor = Some(remaining[commit_count - 1].clone());
            Some((start, end, text))
        } else {
            None
        };
        let provisional = remaining[commit_count..].to_vec();
        let hypothesis = join_words(&provisional);
        self.previous = current;
        self.observations = observations;
        self.last_decoded = request.end;
        self.in_flight = None;
        let mut retain_from = request.start;
        if request.final_phrase {
            self.covered = request.end;
            self.regions.pop_front();
            self.previous.clear();
            self.observations.clear();
            self.anchor = None;
            self.last_decoded = 0;
            retain_from = self.regions.front().map_or(request.end, |r| r.start);
            retain_from = retain_from.min(request.end);
        } else if request.end - request.start == MAX_WINDOW_SAMPLES as u64 {
            if self.covered <= request.start + LOOKBACK {
                return Err(VoiceError::UnstableTranscript);
            }
            retain_from = self.boundary().start().max(request.start);
            if retain_from <= request.start {
                return Err(VoiceError::UnstableTranscript);
            }
            if let Some(region) = self.regions.front_mut() {
                region.start = retain_from;
            }
        }
        self.ring.acknowledge(
            request.end.max(self.ring.processed()),
            retain_from.max(self.ring.retained_from()),
        )?;
        self.release_silence()?;
        Ok(RecognitionUpdate {
            commit,
            hypothesis,
            provisional,
            boundary: self.boundary(),
        })
    }

    fn boundary(&self) -> TranscriptBoundary {
        TranscriptBoundary {
            end: self.covered,
            anchor: self.anchor.clone(),
        }
    }

    pub fn is_settled(&self) -> bool {
        self.regions.is_empty() && self.in_flight.is_none()
    }
    #[cfg(test)]
    fn covered(&self) -> u64 {
        self.covered
    }
    #[cfg(test)]
    fn retained_samples(&self) -> usize {
        self.ring.retained_samples()
    }
}

fn merge_provisional(
    previous: &[AlignedWord],
    current: &[AlignedWord],
    start: u64,
    end: u64,
) -> Result<Vec<AlignedWord>> {
    let mut paired = vec![None; previous.len()];
    let mut matched = vec![false; current.len()];
    for (old_index, old) in previous.iter().enumerate() {
        if old.start < start || old.end > end {
            continue;
        }
        let key = alignment_key(&old.text);
        let mut candidates = current.iter().enumerate().filter_map(|(index, word)| {
            let same = alignment_key(&word.text) == key;
            let duration = if same {
                (word.end - word.start).min(old.end - old.start)
            } else {
                (word.end - word.start).max(old.end - old.start)
            };
            let overlap = word
                .end
                .min(old.end)
                .saturating_sub(word.start.max(old.start));
            (word.start.abs_diff(old.start) <= ALIGNMENT_TOLERANCE
                && (same || word.end.abs_diff(old.end) <= ALIGNMENT_TOLERANCE)
                && (overlap * 2 > duration || (same && duration == 0 && word.start == old.start)))
                .then_some(index)
        });
        match (candidates.next(), candidates.next()) {
            (Some(index), None) if !matched[index] => {
                matched[index] = true;
                paired[old_index] = Some(index);
            }
            (None, None) => {}
            _ => return Err(VoiceError::UnstableTranscript),
        }
    }
    let anchors = paired.clone();
    for index in 1..previous.len() {
        let (Some(left), Some(right)) = (anchors[index - 1], anchors[index]) else {
            continue;
        };
        if right != left + 1
            || alignment_key(&previous[index - 1].text) != alignment_key(&current[left].text)
            || alignment_key(&previous[index].text) != alignment_key(&current[right].text)
        {
            continue;
        }
        let mut old_index = index + 1;
        let mut new_index = right + 1;
        while let (Some(old), Some(word)) = (previous.get(old_index), current.get(new_index)) {
            if old.start < start
                || old.end > end
                || alignment_key(&old.text) != alignment_key(&word.text)
            {
                break;
            }
            if paired[old_index].is_some_and(|paired| paired != new_index)
                || (paired[old_index].is_none() && matched[new_index])
            {
                return Err(VoiceError::UnstableTranscript);
            }
            paired[old_index] = Some(new_index);
            matched[new_index] = true;
            old_index += 1;
            new_index += 1;
        }
    }
    let mut retained = Vec::new();
    for (old, paired) in previous.iter().zip(paired) {
        if paired.is_some() {
            continue;
        }
        if current.iter().any(|word| {
            (word.start < old.end && old.start < word.end)
                || (word.start == old.start && (word.end == word.start || old.end == old.start))
        }) {
            return Err(if old.start < start || old.end > end {
                VoiceError::IncompleteAudio
            } else {
                VoiceError::UnstableTranscript
            });
        }
        retained.push(old.clone());
    }
    retained.extend_from_slice(current);
    retained.sort_by_key(|word| word.start);
    Ok(retained)
}

fn absolute_words(mut words: Vec<AlignedWord>, start: u64, end: u64) -> Result<Vec<AlignedWord>> {
    let mut previous_start = 0;
    for word in &mut words {
        if word.text.trim().is_empty()
            || word.start < previous_start
            || word.end < word.start
            || word.end > end - start
        {
            return Err(VoiceError::UnstableTranscript);
        }
        previous_start = word.start;
        word.start += start;
        word.end += start;
    }
    Ok(words)
}

fn alignment_key(text: &str) -> String {
    let lexical = text.trim().trim_matches([
        '.', ',', '!', '?', ':', ';', '…', '。', '，', '！', '？', '؛', '،', '।', '॥', '¿', '¡',
        '"', '“', '”',
    ]);
    if lexical.is_empty() {
        text.trim().to_owned()
    } else {
        lexical.to_lowercase()
    }
}

fn join_words(words: &[AlignedWord]) -> String {
    let mut text = String::new();
    for word in words {
        text.push_str(transcript_separator(&text, &word.text));
        text.push_str(&word.text);
    }
    text
}

#[cfg(test)]
mod tests {
    use super::*;

    fn aligned(text: &str, start: u64, end: u64) -> AlignedWord {
        AlignedWord {
            text: text.into(),
            start,
            end,
        }
    }

    #[test]
    fn provisional_revisions_need_repeated_right_context_before_commit() {
        let mut rolling = RollingRecognizer::default();
        for index in 0..5 {
            rolling.feed(&vec![0.1; 8000], index == 0).unwrap();
            let request = rolling.next_window().unwrap().unwrap();
            let first = match index {
                0 | 1 => "Friday",
                3 => "Saturday,",
                _ => "Saturday",
            };
            let update = rolling
                .complete(
                    &request,
                    vec![
                        aligned(first, 0, 1000),
                        aligned("at", 1000, 2000),
                        aligned("noon", 2000, 3000),
                    ],
                )
                .unwrap();
            if index < 4 {
                assert!(update.commit.is_none());
                assert_eq!(update.hypothesis, format!("{first} at noon"));
            } else {
                assert_eq!(update.commit.unwrap().2, "Saturday");
                assert_eq!(update.hypothesis, "at noon");
            }
        }
        rolling.finish();
        let request = rolling.next_window().unwrap().unwrap();
        for words in [Vec::new(), vec![aligned("Saturday", 0, 1000)]] {
            assert!(matches!(
                rolling.complete(&request, words),
                Err(VoiceError::IncompleteAudio)
            ));
            assert_eq!(rolling.covered(), 1000);
            assert!(!rolling.is_settled());
        }
        let update = rolling
            .complete(
                &request,
                vec![
                    aligned("Saturday", 0, 1000),
                    aligned("at", 1000, 2000),
                    aligned("noon", 2000, 3000),
                ],
            )
            .unwrap();
        assert_eq!(update.commit.unwrap(), (1000, 40000, "at noon".into()));
        assert!(update.hypothesis.is_empty());
        assert!(rolling.is_settled());
    }

    #[test]
    fn repeated_unfinished_tail_stays_revisable_until_endpoint() {
        let mut rolling = RollingRecognizer::default();
        for index in 0..6 {
            rolling.feed(&vec![0.1; 8000], index == 0).unwrap();
            let request = rolling.next_window().unwrap().unwrap();
            let update = rolling
                .complete(
                    &request,
                    vec![aligned("This", 0, 1000), aligned("one.", 1000, 2000)],
                )
                .unwrap();
            assert!(update.commit.is_none());
        }
        rolling.finish();
        let request = rolling.next_window().unwrap().unwrap();
        let update = rolling
            .complete(
                &request,
                vec![aligned("And", 0, 1000), aligned("so", 1000, 2000)],
            )
            .unwrap();
        assert_eq!(update.commit.unwrap().2, "And so");
        assert!(rolling.is_settled());
    }

    #[test]
    fn short_vad_dropout_preserves_contiguous_audio_and_phrase() {
        let mut rolling = RollingRecognizer::default();
        rolling.feed(&vec![0.1; 8000], false).unwrap();
        rolling.feed(&vec![0.2; 8000], true).unwrap();
        rolling.feed(&vec![0.3; 16000], false).unwrap();
        rolling.feed(&vec![0.4; 8000], true).unwrap();
        let request = rolling.next_window().unwrap().unwrap();
        assert_eq!((request.start, request.end), (0, 40000));
        assert!(!request.final_phrase);
        assert_eq!(&request.samples[16000..32000], &vec![0.3; 16000]);
        assert_eq!(rolling.regions.len(), 1);
    }

    #[test]
    fn overlap_ignores_boundary_punctuation_but_preserves_acoustic_identity() {
        let boundary = TranscriptBoundary {
            anchor: Some(aligned("You.", 16000, 20000)),
            end: 20000,
        };
        assert_eq!(
            boundary.overlap_end(&[aligned("you,", 16000, 20000), aligned("you", 22000, 26000)]),
            Ok(1)
        );
        assert_eq!(
            boundary.overlap_end(&[aligned("to", 14000, 18000), aligned("you", 16000, 20000)]),
            Ok(2)
        );
        assert_eq!(
            boundary.overlap_end(&[aligned("you", 16000, 18000), aligned("you", 18000, 20000)]),
            Err(VoiceError::UnstableTranscript)
        );
        assert_eq!(
            boundary.overlap_end(&[aligned("you", 12000, 20000)]),
            Err(VoiceError::UnstableTranscript)
        );
        assert_eq!(boundary.overlap_end(&[aligned("not", 16000, 20000)]), Ok(1));
        assert_eq!(
            boundary.overlap_end(&[aligned("to", 14000, 18000)]),
            Err(VoiceError::UnstableTranscript)
        );
        let repeated = [aligned("no", 0, 1600), aligned("no", 1600, 3200)];
        assert!(matches!(
            merge_provisional(&repeated, &[aligned("no", 0, 3200)], 0, 40000),
            Err(VoiceError::UnstableTranscript)
        ));
        assert_eq!(
            join_words(
                &merge_provisional(
                    &[aligned("no", 0, 1600)],
                    &[aligned("no", 1600, 3200)],
                    0,
                    40000
                )
                .unwrap()
            ),
            "no no"
        );
        assert!(matches!(
            merge_provisional(
                &[aligned("a", 16000, 16000)],
                &[aligned("the", 16000, 16000)],
                0,
                40000
            ),
            Err(VoiceError::UnstableTranscript)
        ));
        let retained = merge_provisional(
            &[
                aligned("earlier", 16000, 20000),
                aligned("later", 100000, 104000),
            ],
            &[aligned("corrected", 40000, 44000)],
            0,
            80000,
        )
        .unwrap();
        assert_eq!(join_words(&retained), "earlier corrected later");
        assert!(matches!(
            merge_provisional(
                &[aligned("hello", 100, 300)],
                &[aligned("hello", 100, 200)],
                0,
                200,
            ),
            Err(VoiceError::IncompleteAudio)
        ));
        let compressed = [
            aligned("campuses", 464320, 473280),
            aligned("easier", 473280, 478400),
            aligned("to", 478400, 479680),
            aligned("reach", 479680, 482240),
            aligned("than", 482240, 483040),
        ];
        let revised = [
            aligned("campuses,", 464480, 474720),
            aligned("easier", 474720, 481120),
            aligned("to", 481120, 483680),
            aligned("reach", 483680, 487520),
            aligned("than", 487520, 490080),
        ];
        assert_eq!(
            join_words(&merge_provisional(&compressed, &revised, 440320, 581120).unwrap()),
            "campuses, easier to reach than"
        );
        let omitted = [&revised[..3], &revised[4..]].concat();
        assert!(
            merge_provisional(&compressed, &omitted, 440320, 581120)
                .map_or(true, |words| join_words(&words).contains("reach"))
        );
        assert_ne!(alignment_key("don't"), alignment_key("do"));
        assert_ne!(alignment_key("कि"), alignment_key("क"));
        assert_ne!(alignment_key("-5"), alignment_key("5"));
        let boundary = TranscriptBoundary {
            anchor: Some(aligned("two", 16000, 18560)),
            end: 18560,
        };
        for revised in ["two", "to"] {
            assert_eq!(
                boundary
                    .recorded_update(
                        vec![
                            aligned(revised, 16000, 18560),
                            aligned("two", 18560, 21120),
                            aligned("people", 21120, 25000),
                        ],
                        &[],
                        32000,
                        true,
                    )
                    .unwrap()
                    .commit
                    .unwrap()
                    .2,
                "two people"
            );
        }
        let boundary = TranscriptBoundary {
            anchor: Some(aligned("a", 16000, 16000)),
            end: 16000,
        };
        assert_eq!(boundary.overlap_end(&[aligned("a", 16000, 16000)]), Ok(1));
        assert_eq!(boundary.overlap_end(&[aligned("the", 16000, 16000)]), Ok(0));
        assert_eq!(
            boundary.overlap_end(&[aligned("a", 16000, 16000), aligned("a", 16000, 16000)]),
            Err(VoiceError::UnstableTranscript)
        );
        let boundary = TranscriptBoundary {
            anchor: Some(aligned("going", 16000, 21000)),
            end: 21000,
        };
        assert_eq!(
            boundary.overlap_end(&[aligned("gonna", 16000, 23000)]),
            Err(VoiceError::UnstableTranscript)
        );
        assert_eq!(
            boundary.overlap_end(&[aligned("going", 16000, 23000)]),
            Ok(1)
        );
        let boundary = TranscriptBoundary {
            anchor: Some(aligned("are", 338400, 339200)),
            end: 339200,
        };
        assert_eq!(
            boundary.overlap_end(&[aligned("are", 338080, 340640)]),
            Ok(1)
        );
        assert_eq!(
            boundary.overlap_end(&[aligned("were", 338080, 340640)]),
            Err(VoiceError::UnstableTranscript)
        );
        assert_eq!(
            boundary.overlap_end(&[
                aligned("are", 338080, 340640),
                aligned("are", 338400, 339200),
            ]),
            Err(VoiceError::UnstableTranscript)
        );
        let boundary = TranscriptBoundary {
            anchor: Some(aligned("Café!", 16000, 20000)),
            end: 20000,
        };
        assert_eq!(
            boundary.overlap_end(&[aligned("café", 16000, 20000)]),
            Ok(1)
        );
        assert_eq!(
            boundary.overlap_end(&[aligned("cafe\u{301}", 16000, 20000)]),
            Ok(1)
        );
        let boundary = TranscriptBoundary {
            end: 56000,
            anchor: Some(aligned("You.", 50000, 56000)),
        };
        assert_eq!(boundary.start(), 32000);
        assert_eq!(
            boundary
                .recorded_update(
                    vec![
                        aligned("before", 0, 8000),
                        aligned("you,", 18000, 24000),
                        aligned("you", 26000, 30000),
                        aligned("again", 30000, 34000),
                    ],
                    &[],
                    40000,
                    true,
                )
                .unwrap()
                .commit
                .unwrap()
                .2,
            "you again"
        );
        assert!(matches!(
            boundary.recorded_update(vec![aligned("different", 12000, 24000)], &[], 40000, true),
            Err(VoiceError::UnstableTranscript)
        ));
        assert!(matches!(
            boundary.recorded_update(vec![aligned("you", 18000, 50000)], &[], 40000, true),
            Err(VoiceError::UnstableTranscript)
        ));
        let provisional = [aligned("you", 58000, 62000), aligned("again", 62000, 66000)];
        for words in [Vec::new(), vec![aligned("you", 18000, 24000)]] {
            let update = boundary
                .recorded_update(words, &provisional, 40000, true)
                .unwrap();
            assert!(update.commit.is_none());
            assert_eq!(update.boundary.end, boundary.end);
            assert_eq!(update.hypothesis, "you again");
            assert_eq!(join_words(&update.provisional), "you again");
        }
        assert_eq!(
            TranscriptBoundary {
                end: 56000,
                anchor: None
            }
            .start(),
            56000
        );
        let boundary = TranscriptBoundary {
            end: 403520,
            anchor: Some(aligned("Americans", 379200, 403520)),
        };
        assert_eq!(boundary.start(), 363200);
        assert_eq!(
            boundary
                .recorded_update(
                    vec![
                        aligned("America,", 18400, 40160),
                        aligned("ask", 40160, 51680),
                        aligned("Americans", 70000, 94000),
                    ],
                    &[],
                    128000,
                    true,
                )
                .unwrap()
                .commit
                .unwrap()
                .2,
            "ask Americans"
        );
    }

    fn words(request: &DecodeWindow) -> Vec<AlignedWord> {
        (0..request.end / 4000)
            .filter_map(|i| {
                let start = i * 4000;
                (start >= request.start).then(|| AlignedWord {
                    text: "no".into(),
                    start: start - request.start,
                    end: (start + 3000).min(request.end) - request.start,
                })
            })
            .collect()
    }

    #[test]
    fn continuous_speech_advances_stable_text_without_losing_repetitions() {
        let mut rolling = RollingRecognizer::default();
        let mut committed = String::new();
        for _ in 0..7200 {
            rolling.feed(&vec![0.2; 4000], true).unwrap();
            if let Some(request) = rolling.next_window().unwrap() {
                assert!(request.samples.len() <= MAX_WINDOW_SAMPLES);
                let update = rolling.complete(&request, words(&request)).unwrap();
                if let Some((_, _, text)) = update.commit {
                    committed.push_str(&text);
                    committed.push(' ');
                }
            }
            assert!(rolling.retained_samples() <= 30 * 16000);
        }
        assert!(committed.split_whitespace().count() > 7100);
        rolling.finish();
        while let Some(request) = rolling.next_window().unwrap() {
            if let Some((_, _, text)) = rolling.complete(&request, words(&request)).unwrap().commit
            {
                committed.push_str(&text);
                committed.push(' ');
            }
        }
        assert!(rolling.is_settled());
        assert_eq!(committed.split_whitespace().count(), 7200);
    }

    #[test]
    fn final_short_speech_and_stale_results_are_handled() {
        let mut rolling = RollingRecognizer::default();
        rolling.feed(&vec![0.1; 3200], true).unwrap();
        assert!(rolling.next_window().unwrap().is_none());
        rolling.finish();
        let request = rolling.next_window().unwrap().unwrap();
        let update = rolling
            .complete(
                &request,
                vec![AlignedWord {
                    text: "Ha".into(),
                    start: 0,
                    end: 3200,
                }],
            )
            .unwrap();
        assert_eq!(update.commit.unwrap().2, "Ha");
        assert!(matches!(
            rolling.complete(&request, Vec::new()),
            Err(VoiceError::StaleEvent)
        ));
    }

    #[test]
    fn failed_alignment_keeps_audio_and_does_not_claim_completion() {
        for (samples, finished, word_end, error) in [
            (8000, false, 9000, VoiceError::UnstableTranscript),
            (32000, true, 8000, VoiceError::IncompleteAudio),
        ] {
            let mut rolling = RollingRecognizer::default();
            rolling.feed(&vec![0.1; samples], true).unwrap();
            if finished {
                rolling.finish();
            }
            let request = rolling.next_window().unwrap().unwrap();
            assert_eq!(
                rolling
                    .complete(
                        &request,
                        vec![AlignedWord {
                            text: "prefix".into(),
                            start: 0,
                            end: word_end,
                        }]
                    )
                    .unwrap_err(),
                error
            );
            assert_eq!(rolling.retained_samples(), samples);
            assert_eq!(rolling.covered(), 0);
            assert!(!rolling.is_settled());
        }
    }
}
