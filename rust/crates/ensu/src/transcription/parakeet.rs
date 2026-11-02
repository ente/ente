use std::path::Path;

use ort::{
    inputs,
    session::{
        Session, SessionOutputs,
        builder::{AutoDevicePolicy, GraphOptimizationLevel},
    },
    value::{DynValue, TensorRef},
};
use regex::{Captures, regex};

use super::{Result, TranscriptionError};

const SAMPLE_RATE: usize = 16000;
const LEADING_SAMPLES: usize = SAMPLE_RATE / 4;
const FRAME_SECONDS: f32 = 0.08;
const ENCODER_CHANNELS: usize = 1024;
const STATE_SHAPE: [usize; 3] = [2, 1, 640];
const STATE_ELEMENTS: usize = 1280;
const MAX_SYMBOLS_PER_FRAME: usize = 10;
const DURATION_CLASSES: usize = 5;

#[derive(Debug, Default)]
pub(super) struct Transcript {
    pub text: String,
    pub words: Vec<TimedWord>,
}

#[derive(Debug)]
pub(super) struct TimedWord {
    pub text: String,
    pub start: f32,
    pub end: f32,
}

pub(super) struct Parakeet {
    features: Session,
    encoder: Session,
    decoder: Session,
    vocabulary: Vec<String>,
    blank: usize,
}

struct Emission {
    token: usize,
    frame: usize,
}

impl Parakeet {
    pub fn load(directory: &Path) -> Result<Self> {
        let vocabulary = read_vocabulary(&std::fs::read_to_string(directory.join("vocab.txt"))?)?;
        let blank = vocabulary
            .iter()
            .position(|token| token == "<blk>")
            .ok_or_else(|| invalid_model("vocabulary has no blank token"))?;
        Ok(Self {
            features: load_session(&directory.join("nemo128.onnx"))?,
            encoder: load_session(&directory.join("encoder-model.int8.onnx"))?,
            decoder: load_session(&directory.join("decoder_joint-model.int8.onnx"))?,
            vocabulary,
            blank,
        })
    }

    pub fn transcribe(&mut self, samples: &[f32]) -> Result<Transcript> {
        if samples.is_empty() {
            return Ok(Transcript::default());
        }
        if samples.iter().any(|value| !value.is_finite()) {
            return Err(TranscriptionError::InvalidAudio(
                "Recognition requires finite samples at 16 kHz".into(),
            ));
        }
        let mut waveform = vec![0.0; LEADING_SAMPLES];
        waveform.extend_from_slice(samples);
        let waveform_length = [waveform.len() as i64];
        let features = self.features.run(inputs![
            "waveforms" => TensorRef::from_array_view(([1, waveform.len()], waveform.as_slice()))?,
            "waveforms_lens" => TensorRef::from_array_view(([1], waveform_length.as_slice()))?,
        ])?;
        let (feature_shape, feature_values) =
            output(&features, "features")?.try_extract_tensor::<f32>()?;
        let (_, feature_lengths) =
            output(&features, "features_lens")?.try_extract_tensor::<i64>()?;
        if feature_shape.len() != 3
            || feature_shape[0] != 1
            || feature_shape[1] != 128
            || feature_lengths.len() != 1
        {
            return Err(invalid_model("invalid audio features"));
        }
        let encoded = self.encoder.run(inputs![
            "audio_signal" => TensorRef::from_array_view((feature_shape.clone(), feature_values))?,
            "length" => TensorRef::from_array_view(([1], feature_lengths))?,
        ])?;
        let (encoded_shape, encoded_values) =
            output(&encoded, "outputs")?.try_extract_tensor::<f32>()?;
        let (_, encoded_lengths) =
            output(&encoded, "encoded_lengths")?.try_extract_tensor::<i64>()?;
        if encoded_shape.len() != 3
            || encoded_shape[0] != 1
            || encoded_shape[1] != ENCODER_CHANNELS as i64
            || encoded_lengths.len() != 1
            || encoded_lengths[0] < 0
            || encoded_lengths[0] > encoded_shape[2]
        {
            return Err(invalid_model("invalid encoder output"));
        }
        let emissions = decode(
            &mut self.decoder,
            encoded_values,
            encoded_shape[2] as usize,
            encoded_lengths[0] as usize,
            self.vocabulary.len(),
            self.blank,
        )?;
        Ok(render(&emissions, &self.vocabulary))
    }
}

fn load_session(path: &Path) -> Result<Session> {
    let environment = super::environment()?;
    Ok(Session::builder(&environment)?
        .with_auto_device(AutoDevicePolicy::PreferCPU)?
        .with_optimization_level(GraphOptimizationLevel::Level3)?
        .with_parallel_execution(true)?
        .with_execution_providers([ort::ep::CPU::default().build()])?
        .commit_from_file(path)?)
}

fn read_vocabulary(text: &str) -> Result<Vec<String>> {
    let mut vocabulary = Vec::new();
    for line in text.lines() {
        let (token, index) = line
            .rsplit_once(' ')
            .ok_or_else(|| invalid_model("invalid vocabulary entry"))?;
        if index.parse::<usize>().ok() != Some(vocabulary.len()) || token.is_empty() {
            return Err(invalid_model("vocabulary indices must be contiguous"));
        }
        vocabulary.push(token.to_owned());
    }
    Ok(vocabulary)
}

fn decode(
    decoder: &mut Session,
    encoded: &[f32],
    stride: usize,
    frames: usize,
    vocabulary_size: usize,
    blank: usize,
) -> Result<Vec<Emission>> {
    let mut hidden = vec![0.0_f32; STATE_ELEMENTS];
    let mut cell = vec![0.0_f32; STATE_ELEMENTS];
    let mut embedding = vec![0.0_f32; ENCODER_CHANNELS];
    let target_length = [1_i32];
    let mut target = [blank as i32];
    let mut emissions = Vec::new();
    let mut frame = 0;
    let mut symbols = 0;
    while frame < frames {
        for (channel, value) in embedding.iter_mut().enumerate() {
            *value = encoded[channel * stride + frame];
        }
        let decoded = decoder.run(inputs![
            "encoder_outputs" => TensorRef::from_array_view(([1, ENCODER_CHANNELS, 1], embedding.as_slice()))?,
            "targets" => TensorRef::from_array_view(([1, 1], target.as_slice()))?,
            "target_length" => TensorRef::from_array_view(([1], target_length.as_slice()))?,
            "input_states_1" => TensorRef::from_array_view((STATE_SHAPE, hidden.as_slice()))?,
            "input_states_2" => TensorRef::from_array_view((STATE_SHAPE, cell.as_slice()))?,
        ])?;
        let (_, logits) = output(&decoded, "outputs")?.try_extract_tensor::<f32>()?;
        if logits.len() != vocabulary_size + DURATION_CLASSES {
            return Err(invalid_model("invalid decoder logits"));
        }
        let token = argmax(&logits[..vocabulary_size])?;
        if token != blank {
            emissions.push(Emission { token, frame });
            target[0] = token as i32;
            let (_, next_hidden) =
                output(&decoded, "output_states_1")?.try_extract_tensor::<f32>()?;
            let (_, next_cell) =
                output(&decoded, "output_states_2")?.try_extract_tensor::<f32>()?;
            if next_hidden.len() != STATE_ELEMENTS || next_cell.len() != STATE_ELEMENTS {
                return Err(invalid_model("invalid decoder state"));
            }
            hidden.copy_from_slice(next_hidden);
            cell.copy_from_slice(next_cell);
        }
        symbols += 1;
        if token == blank || symbols >= MAX_SYMBOLS_PER_FRAME {
            frame += 1;
            symbols = 0;
        }
    }
    Ok(emissions)
}

fn argmax(values: &[f32]) -> Result<usize> {
    if values.is_empty() {
        return Err(invalid_model("empty decoder logits"));
    }
    let mut best = 0;
    for (index, &value) in values.iter().enumerate() {
        if !value.is_finite() {
            return Err(invalid_model("non-finite decoder logits"));
        }
        if value >= values[best] {
            best = index;
        }
    }
    Ok(best)
}

fn attaches_to_previous_word(piece: &str) -> bool {
    regex!(r"\A[\p{P}--[¿¡\p{Ps}\p{Pi}]]").is_match(piece)
}

fn render(emissions: &[Emission], vocabulary: &[String]) -> Transcript {
    let mut transcript = Transcript::default();
    let mut after_standalone_marker = false;
    for (index, emission) in emissions.iter().enumerate() {
        let piece = vocabulary[emission.token].replace('▁', " ");
        let start = emission.frame as f32 * FRAME_SECONDS;
        let end = emissions
            .get(index + 1)
            .map_or(start + 0.05, |next| next.frame as f32 * FRAME_SECONDS);
        transcript.text.push_str(&piece);
        if piece.trim().is_empty() {
            after_standalone_marker = true;
            continue;
        }
        let starts_word = piece.starts_with(' ')
            || transcript.words.is_empty()
            || (after_standalone_marker && !attaches_to_previous_word(&piece));
        after_standalone_marker = false;
        if starts_word {
            transcript.words.push(TimedWord {
                text: piece.trim().to_owned(),
                start,
                end,
            });
        } else if let Some(word) = transcript.words.last_mut() {
            word.text.push_str(&piece);
            word.end = end;
        }
    }
    transcript.text = regex!(r"\A\s|\s\B|(\s)\b")
        .replace_all(&transcript.text, |captures: &Captures<'_>| {
            if captures.get(1).is_some() { " " } else { "" }
        })
        .into_owned();
    for word in &mut transcript.words {
        word.start = (word.start - 0.25).max(0.0);
        word.end = (word.end - 0.25).max(0.0);
    }
    transcript
}

fn invalid_model(detail: &str) -> TranscriptionError {
    TranscriptionError::Transcribe(format!("Parakeet: {detail}"))
}

fn output<'a>(outputs: &'a SessionOutputs<'_>, name: &str) -> Result<&'a DynValue> {
    outputs
        .get(name)
        .ok_or_else(|| invalid_model(&format!("missing {name} output")))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn vocabulary_requires_ordered_indices_and_nonempty_tokens() {
        assert_eq!(
            read_vocabulary("▁Hello 0\n界 1\n<blk> 2\n").unwrap(),
            ["▁Hello", "界", "<blk>"]
        );
        for invalid in ["word", "word 1", "word 0\nnext 0", " 0"] {
            assert!(read_vocabulary(invalid).is_err(), "{invalid}");
        }
    }

    #[test]
    fn word_boundaries_keep_unicode_punctuation_and_remove_leading_padding() {
        let vocabulary = vec![
            "▁Hello".into(),
            ",".into(),
            "▁世".into(),
            "界".into(),
            "!".into(),
        ];
        let emissions = vec![
            Emission { token: 0, frame: 1 },
            Emission { token: 1, frame: 4 },
            Emission { token: 2, frame: 5 },
            Emission { token: 3, frame: 5 },
            Emission { token: 4, frame: 9 },
        ];
        let transcript = render(&emissions, &vocabulary);
        assert_eq!(transcript.text, "Hello, 世界!");
        assert_eq!(transcript.words.len(), 2);
        assert_eq!(transcript.words[0].text, "Hello,");
        assert_eq!(transcript.words[0].start, 0.0);
        assert_eq!(transcript.words[0].end, 5.0 * FRAME_SECONDS - 0.25);
        assert_eq!(transcript.words[1].text, "世界!");
        assert_eq!(transcript.words[1].start, 5.0 * FRAME_SECONDS - 0.25);
        assert_eq!(transcript.words[1].end, 9.0 * FRAME_SECONDS + 0.05 - 0.25);
        assert!(render(&[], &vocabulary).words.is_empty());
    }

    #[test]
    fn decoder_logits_require_finite_values() {
        assert_eq!(argmax(&[-3.0, 2.0, 2.0]).unwrap(), 2);
        assert!(argmax(&[]).is_err());
        assert!(argmax(&[0.0, f32::NAN]).is_err());
        assert!(argmax(&[f32::INFINITY]).is_err());
    }

    #[test]
    fn standalone_word_markers_do_not_emit_empty_words_or_double_spaces() {
        let vocabulary = vec!["▁Hello".into(), "▁".into(), "▁世界".into(), "!".into()];
        let emissions: Vec<_> = (0..4)
            .map(|token| Emission {
                token,
                frame: token + 4,
            })
            .collect();
        let transcript = render(&emissions, &vocabulary);
        assert_eq!(transcript.text, "Hello 世界!");
        assert_eq!(transcript.words.len(), 2);
        assert_eq!(transcript.words[0].end, 5.0 * FRAME_SECONDS - 0.25);
        assert_eq!(transcript.words[1].start, 6.0 * FRAME_SECONDS - 0.25);
        assert_eq!(transcript.words[1].end, 7.0 * FRAME_SECONDS + 0.05 - 0.25);
        let trailing = render(&emissions[..2], &vocabulary);
        assert_eq!(trailing.text, "Hello");
        assert_eq!(trailing.words.len(), 1);
        assert_eq!(trailing.words[0].end, 5.0 * FRAME_SECONDS - 0.25);
        let vocabulary = vec!["▁Hello".into(), "▁".into(), "世界".into(), "!".into()];
        let continuation = render(&emissions, &vocabulary);
        assert_eq!(continuation.text, "Hello 世界!");
        assert_eq!(continuation.words.len(), 2);
        assert_eq!(continuation.words[0].text, "Hello");
        assert_eq!(continuation.words[0].end, 5.0 * FRAME_SECONDS - 0.25);
        assert_eq!(continuation.words[1].text, "世界!");
        assert_eq!(continuation.words[1].start, 6.0 * FRAME_SECONDS - 0.25);
        assert_eq!(continuation.words[1].end, 7.0 * FRAME_SECONDS + 0.05 - 0.25);
    }

    #[test]
    fn standalone_markers_start_words_unless_closing_punctuation_follows() {
        let vocabulary = vec![
            "▁at".into(),
            "▁".into(),
            "1".into(),
            "0".into(),
            "р".into(),
            "$".into(),
            "5".into(),
            ",".into(),
            "¿".into(),
            "qué".into(),
        ];
        let tokens = [0, 1, 2, 3, 1, 4, 1, 5, 6, 1, 7, 1, 8, 9];
        let emissions: Vec<_> = tokens
            .into_iter()
            .enumerate()
            .map(|(frame, token)| Emission { token, frame })
            .collect();
        let words: Vec<_> = render(&emissions, &vocabulary)
            .words
            .into_iter()
            .map(|word| word.text)
            .collect();
        assert_eq!(words, ["at", "10", "р", "$5,", "¿qué"]);
    }

    #[test]
    fn text_drops_spaces_before_non_word_tokens_without_changing_words() {
        let vocabulary = vec![
            "▁cost".into(),
            "▁$".into(),
            "5".into(),
            "▁".into(),
            ",".into(),
            "▁¿".into(),
            "qué".into(),
        ];
        let emissions: Vec<_> = (0..vocabulary.len())
            .map(|token| Emission {
                token,
                frame: token,
            })
            .collect();
        let transcript = render(&emissions, &vocabulary);
        assert_eq!(transcript.text, "cost$5,¿qué");
        let words: Vec<_> = transcript
            .words
            .iter()
            .map(|word| word.text.as_str())
            .collect();
        assert_eq!(words, ["cost", "$5,", "¿qué"]);
    }
}
