use std::collections::VecDeque;

use super::{Result, VoiceError};

pub(crate) const VOICE_SAMPLE_RATE: u64 = 16_000;
pub(crate) const MAX_WINDOW_SAMPLES: usize = 10 * VOICE_SAMPLE_RATE as usize;
const MAX_RING_SAMPLES: usize = 30 * VOICE_SAMPLE_RATE as usize;
const MAX_BACKLOG_SAMPLES: u64 = 10 * VOICE_SAMPLE_RATE;

#[derive(Debug)]
pub(crate) struct AudioRing {
    samples: VecDeque<f32>,
    start: u64,
    processed: u64,
}

impl Default for AudioRing {
    fn default() -> Self {
        Self {
            samples: VecDeque::with_capacity(MAX_RING_SAMPLES),
            start: 0,
            processed: 0,
        }
    }
}

impl AudioRing {
    pub fn push(&mut self, offset: u64, samples: &[f32]) -> Result<()> {
        if offset != self.accepted() || samples.iter().any(|v| !v.is_finite()) {
            return Err(VoiceError::InvalidAudio(
                "Invalid audio offset or samples".into(),
            ));
        }
        let end = offset
            .checked_add(samples.len() as u64)
            .ok_or_else(|| VoiceError::InvalidAudio("Audio offset overflow".into()))?;
        if end - self.processed > MAX_BACKLOG_SAMPLES
            || self.samples.len().saturating_add(samples.len()) > MAX_RING_SAMPLES
        {
            return Err(VoiceError::BacklogFull);
        }
        self.samples.extend(samples);
        Ok(())
    }

    pub fn window(&self, start: u64, end: u64) -> Result<Vec<f32>> {
        if start < self.start
            || end > self.accepted()
            || end < start
            || end - start > MAX_WINDOW_SAMPLES as u64
        {
            return Err(VoiceError::InvalidAudio(
                "Audio window is outside the retained range".into(),
            ));
        }
        Ok(self
            .samples
            .iter()
            .skip((start - self.start) as usize)
            .take((end - start) as usize)
            .copied()
            .collect())
    }

    pub fn acknowledge(&mut self, processed: u64, retain_from: u64) -> Result<()> {
        if processed < self.processed
            || processed > self.accepted()
            || retain_from < self.start
            || retain_from > processed
        {
            return Err(VoiceError::InvalidAudio(
                "Invalid processed audio range".into(),
            ));
        }
        self.samples.drain(..(retain_from - self.start) as usize);
        self.start = retain_from;
        self.processed = processed;
        Ok(())
    }

    pub fn accepted(&self) -> u64 {
        self.start + self.samples.len() as u64
    }
    pub fn retained_from(&self) -> u64 {
        self.start
    }
    pub fn processed(&self) -> u64 {
        self.processed
    }
    #[cfg(test)]
    pub(super) fn retained_samples(&self) -> usize {
        self.samples.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn saturation_never_overwrites_unrecognized_audio() {
        let mut ring = AudioRing::default();
        ring.push(0, &vec![0.25; MAX_BACKLOG_SAMPLES as usize])
            .unwrap();
        assert_eq!(
            ring.push(ring.accepted(), &[0.5]),
            Err(VoiceError::BacklogFull)
        );
        assert_eq!(ring.accepted(), MAX_BACKLOG_SAMPLES);
        assert_eq!(ring.window(0, 1).unwrap(), vec![0.25]);
        ring.acknowledge(ring.accepted(), ring.accepted() - 8000)
            .unwrap();
        ring.push(ring.accepted(), &[0.5]).unwrap();
        assert_eq!(ring.retained_samples(), 8001);
        assert_eq!(ring.accepted(), MAX_BACKLOG_SAMPLES + 1);
    }

    #[test]
    fn invalid_offsets_and_nan_are_rejected_atomically() {
        let mut ring = AudioRing::default();
        assert!(matches!(
            ring.push(1, &[0.0]),
            Err(VoiceError::InvalidAudio(_))
        ));
        assert!(matches!(
            ring.push(0, &[f32::NAN]),
            Err(VoiceError::InvalidAudio(_))
        ));
        assert_eq!(ring.accepted(), 0);
        ring.push(0, &[0.1, 0.2]).unwrap();
        assert!(matches!(
            ring.acknowledge(3, 0),
            Err(VoiceError::InvalidAudio(_))
        ));
    }
}
