use rubato::audioadapter_buffers::direct::InterleavedSlice;
use rubato::{Fft, FixedSync, Resampler, WindowFunction};

use crate::voice::{CaptureFormat, Result, VoiceError};

pub const VAD_FRAME_SAMPLES: usize = super::vad::SILERO_V4_FRAME_SAMPLES;

pub(crate) struct StreamNormalizer {
    format: CaptureFormat,
    resampler: Option<Fft<f32>>,
    input: Vec<f32>,
    frame: Vec<f32>,
    delay: usize,
    input_frames: u64,
    emitted: u64,
    finished: bool,
}

impl StreamNormalizer {
    pub fn new(format: CaptureFormat) -> Result<Self> {
        let format = format.validate()?;
        let resampler = if format.sample_rate == 16_000 {
            None
        } else {
            Some(
                Fft::<f32>::new_custom(
                    format.sample_rate as usize,
                    16000,
                    1024,
                    1,
                    1,
                    WindowFunction::BlackmanHarris2,
                    FixedSync::Input,
                )
                .map_err(|error| super::voice_error("Create audio resampler", error))?,
            )
        };
        let delay = resampler.as_ref().map_or(0, Resampler::output_delay);
        Ok(Self {
            format,
            resampler,
            input: Vec::with_capacity(2048),
            frame: Vec::with_capacity(VAD_FRAME_SAMPLES),
            delay,
            input_frames: 0,
            emitted: 0,
            finished: false,
        })
    }

    pub fn push(
        &mut self,
        pcm: &[u8],
        emit: &mut impl FnMut(&[f32], usize) -> Result<()>,
    ) -> Result<()> {
        let frame_bytes = self.format.bytes_per_frame();
        if self.finished || !pcm.len().is_multiple_of(frame_bytes) {
            return Err(VoiceError::InvalidAudio(
                "Audio must contain complete PCM16 frames before normalization finishes".into(),
            ));
        }
        for frame in pcm.chunks_exact(frame_bytes) {
            let mono = frame
                .as_chunks::<2>()
                .0
                .iter()
                .map(|b| f32::from(i16::from_le_bytes(*b)) / 32768.0)
                .sum::<f32>()
                / f32::from(self.format.channels);
            self.input_frames += 1;
            if self.resampler.is_none() {
                self.emit_samples(&[mono], emit)?;
            } else {
                self.input.push(mono);
                if self
                    .resampler
                    .as_ref()
                    .is_some_and(|r| self.input.len() == r.input_frames_next())
                {
                    self.process_chunk(emit)?;
                }
            }
        }
        Ok(())
    }

    pub fn finish(&mut self, emit: &mut impl FnMut(&[f32], usize) -> Result<()>) -> Result<()> {
        if self.finished {
            return Ok(());
        }
        let expected = self.input_frames * 16000 / u64::from(self.format.sample_rate);
        while self.emitted < expected {
            let Some(resampler) = &self.resampler else {
                return Err(VoiceError::ProcessingFailed(
                    "Audio normalization did not produce all input samples".into(),
                ));
            };
            self.input.resize(resampler.input_frames_next(), 0.0);
            self.process_chunk(emit)?;
        }
        if !self.frame.is_empty() {
            let real = self.frame.len();
            self.frame.resize(VAD_FRAME_SAMPLES, 0.0);
            emit(&self.frame, real)?;
            self.frame.clear();
        }
        self.finished = true;
        Ok(())
    }

    fn process_chunk(&mut self, emit: &mut impl FnMut(&[f32], usize) -> Result<()>) -> Result<()> {
        let resampler = self.resampler.as_mut().ok_or(VoiceError::InvalidState)?;
        let input = InterleavedSlice::new(&self.input, 1, self.input.len()).map_err(|error| {
            VoiceError::InvalidAudio(format!("Prepare audio resampler input: {error}"))
        })?;
        let output = resampler
            .process(&input, None)
            .map_err(|error| {
                VoiceError::ProcessingFailed(format!("Resample captured audio: {error}"))
            })?
            .take_data();
        self.input.clear();
        let skip = self.delay.min(output.len());
        self.delay -= skip;
        let expected = self.input_frames * 16000 / u64::from(self.format.sample_rate);
        let take = (expected - self.emitted).min((output.len() - skip) as u64) as usize;
        self.emit_samples(&output[skip..skip + take], emit)
    }

    fn emit_samples(
        &mut self,
        mut samples: &[f32],
        emit: &mut impl FnMut(&[f32], usize) -> Result<()>,
    ) -> Result<()> {
        self.emitted += samples.len() as u64;
        while !samples.is_empty() {
            let take = samples.len().min(VAD_FRAME_SAMPLES - self.frame.len());
            self.frame.extend_from_slice(&samples[..take]);
            samples = &samples[take..];
            if self.frame.len() == VAD_FRAME_SAMPLES {
                emit(&self.frame, VAD_FRAME_SAMPLES)?;
                self.frame.clear();
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn normalized(rate: u32, channels: u16, frames: usize, chunk: usize) -> Vec<f32> {
        let mut normalizer = StreamNormalizer::new(CaptureFormat {
            sample_rate: rate,
            channels,
        })
        .unwrap();
        let pcm: Vec<u8> = (0..frames)
            .flat_map(|i| {
                let value = ((std::f32::consts::TAU * 1000.0 * i as f32 / rate as f32).sin()
                    * 10000.0) as i16;
                (0..channels).flat_map(move |_| value.to_le_bytes())
            })
            .collect();
        let mut output = Vec::new();
        let mut emit = |frame: &[f32], real: usize| {
            assert_eq!(frame.len(), VAD_FRAME_SAMPLES);
            output.extend_from_slice(&frame[..real]);
            Ok(())
        };
        for bytes in pcm.chunks(chunk * usize::from(channels) * 2) {
            normalizer.push(bytes, &mut emit).unwrap();
        }
        normalizer.finish(&mut emit).unwrap();
        normalizer.finish(&mut emit).unwrap();
        assert_eq!(output.len(), frames * 16000 / rate as usize);
        output
    }

    #[test]
    fn arbitrary_chunks_and_stereo_preserve_duration_and_final_tail() {
        for rate in [8000, 16000, 44100, 48000] {
            for frames in [1, 37, 1024, rate as usize + 19] {
                let expected = normalized(rate, 1, frames, 1024);
                for chunk in [1, 137, 4096] {
                    assert_eq!(
                        normalized(rate, 2, frames, chunk),
                        expected,
                        "{rate} Hz, {frames} frames, chunks {chunk}"
                    );
                }
            }
        }
    }

    #[test]
    fn fft_delay_does_not_shift_source_timestamps() {
        let output = normalized(48000, 1, 48000, 257);
        let error = output[1600..14400]
            .iter()
            .enumerate()
            .map(|(i, value)| {
                let expected = (std::f32::consts::TAU * 1000.0 * (i + 1600) as f32 / 16000.0).sin()
                    * 10000.0
                    / 32768.0;
                (value - expected).abs()
            })
            .fold(0.0_f32, f32::max);
        assert!(error < 0.001, "{error}");
    }
}
