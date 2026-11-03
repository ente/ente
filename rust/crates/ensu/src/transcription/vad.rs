use ort::{
    inputs,
    session::{
        Session,
        builder::{AutoDevicePolicy, GraphOptimizationLevel},
    },
    value::TensorRef,
};
use std::{collections::VecDeque, path::Path};

use super::{Result, TranscriptionError};

pub(crate) trait Vad: Send {
    fn frame_size(&self) -> usize;
    fn is_speech(&mut self, frame: &[f32]) -> Result<bool>;
    fn reset(&mut self);
    fn drain_prefill(&mut self) -> Vec<f32> {
        Vec::new()
    }
}

pub(super) struct SpeechGate {
    detector: Box<dyn Vad>,
    history: VecDeque<Vec<f32>>,
    pending_prefill: Vec<f32>,
    prefill_frames: usize,
    hangover_frames: usize,
    onset_frames: usize,
    consecutive_speech: usize,
    remaining_hangover: usize,
    active: bool,
}

impl SpeechGate {
    pub fn new(detector: Box<dyn Vad>, prefill: usize, hangover: usize, onset: usize) -> Self {
        Self {
            detector,
            history: VecDeque::new(),
            pending_prefill: Vec::new(),
            prefill_frames: prefill,
            hangover_frames: hangover,
            onset_frames: onset,
            consecutive_speech: 0,
            remaining_hangover: 0,
            active: false,
        }
    }
}

impl Vad for SpeechGate {
    fn frame_size(&self) -> usize {
        self.detector.frame_size()
    }

    fn is_speech(&mut self, frame: &[f32]) -> Result<bool> {
        let was_active = self.active;
        let voiced = if self.detector.is_speech(frame)? {
            self.consecutive_speech += 1;
            if self.active || self.consecutive_speech >= self.onset_frames {
                self.active = true;
                self.remaining_hangover = self.hangover_frames;
            }
            self.active
        } else {
            self.consecutive_speech = 0;
            if self.remaining_hangover > 0 {
                self.remaining_hangover -= 1;
                true
            } else {
                self.active = false;
                false
            }
        };
        if !was_active && self.active {
            self.pending_prefill = self.history.iter().flatten().copied().collect();
        }
        self.history.push_back(frame.to_vec());
        while self.history.len() > self.prefill_frames {
            self.history.pop_front();
        }
        Ok(voiced)
    }

    fn reset(&mut self) {
        self.detector.reset();
        self.history.clear();
        self.pending_prefill.clear();
        self.consecutive_speech = 0;
        self.remaining_hangover = 0;
        self.active = false;
    }

    fn drain_prefill(&mut self) -> Vec<f32> {
        std::mem::take(&mut self.pending_prefill)
    }
}

#[cfg(test)]
pub(super) struct EnergyVad {
    frame_samples: usize,
    threshold: f32,
}

#[cfg(test)]
impl EnergyVad {
    pub fn new(frame_samples: usize, threshold: f32) -> Self {
        Self {
            frame_samples,
            threshold,
        }
    }
}

#[cfg(test)]
impl Vad for EnergyVad {
    fn frame_size(&self) -> usize {
        self.frame_samples
    }
    fn is_speech(&mut self, frame: &[f32]) -> Result<bool> {
        Ok(frame.iter().map(|v| v * v).sum::<f32>()
            > self.threshold * self.threshold * frame.len() as f32)
    }
    fn reset(&mut self) {}
}

pub(super) const SILERO_V4_FRAME_SAMPLES: usize = 512;

pub(crate) struct SileroV4Vad {
    session: Session,
    hidden: [f32; 128],
    cell: [f32; 128],
    threshold: f32,
}

fn inference(error: impl std::fmt::Display) -> TranscriptionError {
    TranscriptionError::Transcribe(format!("inference error: Silero v4: {error}"))
}

impl SileroV4Vad {
    pub fn new(path: impl AsRef<Path>, threshold: f32) -> Result<Self> {
        let environment = super::environment()?;
        let session = Session::builder(&environment)
            .map_err(inference)?
            .with_auto_device(AutoDevicePolicy::PreferCPU)
            .map_err(inference)?
            .with_optimization_level(GraphOptimizationLevel::Level3)
            .map_err(inference)?
            .with_intra_threads(1)
            .map_err(inference)?
            .with_inter_threads(1)
            .map_err(inference)?
            .commit_from_file(path)
            .map_err(inference)?;
        Ok(Self {
            session,
            hidden: [0.0; 128],
            cell: [0.0; 128],
            threshold,
        })
    }

    fn speech_probability(&mut self, frame: &[f32]) -> Result<f32> {
        validate_frame(frame)?;
        let sample_rate = [16000_i64];
        let outputs = self.session.run(inputs![
            "input" => TensorRef::from_array_view(([1, SILERO_V4_FRAME_SAMPLES], frame)).map_err(inference)?,
            "sr" => TensorRef::from_array_view(([1], sample_rate.as_slice())).map_err(inference)?,
            "h" => TensorRef::from_array_view(([2,1,64], self.hidden.as_slice())).map_err(inference)?,
            "c" => TensorRef::from_array_view(([2,1,64], self.cell.as_slice())).map_err(inference)?,
        ]).map_err(inference)?;
        let (shape, probability) = outputs
            .get("output")
            .ok_or_else(|| inference("missing probability"))?
            .try_extract_tensor::<f32>()
            .map_err(inference)?;
        if shape.as_ref() != [1, 1]
            || probability.len() != 1
            || !probability[0].is_finite()
            || !(0.0..=1.0).contains(&probability[0])
        {
            return Err(inference("invalid probability"));
        }
        let probability = probability[0];
        let (h_shape, hidden) = outputs
            .get("hn")
            .ok_or_else(|| inference("missing hidden state"))?
            .try_extract_tensor::<f32>()
            .map_err(inference)?;
        let (c_shape, cell) = outputs
            .get("cn")
            .ok_or_else(|| inference("missing cell state"))?
            .try_extract_tensor::<f32>()
            .map_err(inference)?;
        if h_shape.as_ref() != [2, 1, 64]
            || c_shape.as_ref() != [2, 1, 64]
            || hidden.len() != 128
            || cell.len() != 128
            || hidden.iter().chain(cell).any(|x| !x.is_finite())
        {
            return Err(inference("invalid recurrent state"));
        }
        self.hidden.copy_from_slice(hidden);
        self.cell.copy_from_slice(cell);
        Ok(probability)
    }
}

fn validate_frame(frame: &[f32]) -> Result<()> {
    if frame.len() != SILERO_V4_FRAME_SAMPLES || frame.iter().any(|s| !s.is_finite()) {
        return Err(TranscriptionError::InvalidAudio(
            "Silero v4 requires 512 finite samples at 16 kHz".into(),
        ));
    }
    Ok(())
}

impl Vad for SileroV4Vad {
    fn frame_size(&self) -> usize {
        SILERO_V4_FRAME_SAMPLES
    }
    fn is_speech(&mut self, frame: &[f32]) -> Result<bool> {
        Ok(self.speech_probability(frame)? > self.threshold)
    }
    fn reset(&mut self) {
        self.hidden.fill(0.0);
        self.cell.fill(0.0);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Scripted(VecDeque<bool>);

    impl Vad for Scripted {
        fn frame_size(&self) -> usize {
            4
        }
        fn is_speech(&mut self, _: &[f32]) -> Result<bool> {
            Ok(self.0.pop_front().unwrap())
        }
        fn reset(&mut self) {}
    }

    #[test]
    fn speech_gate_preserves_onset_prefill_and_hangover() {
        for (pattern, expected, onset, prefill) in [
            ("000000", "000000", None, vec![]),
            ("100000", "000000", None, vec![]),
            ("110000", "011100", Some(1), vec![0]),
            ("00110000", "00011100", Some(3), vec![0, 1, 2]),
            ("001010110000", "000000011100", Some(7), vec![4, 5, 6]),
            ("011100110000", "001111111100", Some(2), vec![0, 1]),
            ("111111", "011111", Some(1), vec![0]),
        ] {
            let detector = Scripted(pattern.bytes().map(|value| value == b'1').collect());
            let mut gate = SpeechGate::new(Box::new(detector), 3, 2, 2);
            let mut actual = String::new();
            for index in 0..pattern.len() {
                let voiced = gate.is_speech(&[index as f32; 4]).unwrap();
                actual.push(if voiced { '1' } else { '0' });
                if voiced {
                    let wanted: Vec<f32> = if Some(index) == onset {
                        prefill.iter().flat_map(|&v| [v as f32; 4]).collect()
                    } else {
                        Vec::new()
                    };
                    assert_eq!(gate.drain_prefill(), wanted, "{pattern}: frame {index}");
                }
            }
            assert_eq!(actual, expected, "{pattern}");
            gate.reset();
            assert!(gate.drain_prefill().is_empty());
            assert!(!gate.active);
            assert_eq!(gate.remaining_hangover, 0);
            assert_eq!(gate.consecutive_speech, 0);
        }
    }

    #[test]
    fn silero_frames_require_finite_samples_at_the_expected_length() {
        assert!(validate_frame(&[0.0; SILERO_V4_FRAME_SAMPLES]).is_ok());
        assert!(validate_frame(&[]).is_err());
        assert!(validate_frame(&[0.0; SILERO_V4_FRAME_SAMPLES - 1]).is_err());
        assert!(validate_frame(&[f32::NAN; SILERO_V4_FRAME_SAMPLES]).is_err());
        assert!(validate_frame(&[f32::INFINITY; SILERO_V4_FRAME_SAMPLES]).is_err());
    }

    #[test]
    fn speech_reentry_keeps_the_full_prefill_history_after_hangover() {
        for gap in 11..=14 {
            let pattern = [vec![true; 2], vec![false; gap], vec![true; 2]].concat();
            let mut gate = SpeechGate::new(Box::new(Scripted(pattern.into())), 3, 10, 2);
            for index in 0..gap + 4 {
                let voiced = gate.is_speech(&[index as f32; 4]).unwrap();
                assert_eq!(voiced, (1..=11).contains(&index) || index == gap + 3);
                if voiced {
                    let expected = if index == 1 {
                        vec![0.0; 4]
                    } else if index == gap + 3 {
                        (index - 3..index).flat_map(|i| [i as f32; 4]).collect()
                    } else {
                        Vec::new()
                    };
                    assert_eq!(gate.drain_prefill(), expected, "gap {gap}, frame {index}");
                }
            }
        }
    }
}
