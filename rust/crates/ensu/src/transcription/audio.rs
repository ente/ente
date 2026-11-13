use std::path::Path;
use std::time::Duration;

use super::vad::{SpeechGate, Vad};
use rubato::audioadapter_buffers::direct::InterleavedSlice;
use rubato::{Fft, FixedSync, Resampler, WindowFunction};

use crate::transcription::{Result, SileroV4Vad, TranscriptionError};

const TARGET_SAMPLE_RATE: usize = 16_000;
const RESAMPLER_CHUNK_SIZE: usize = 1024;
const VAD_PREFILL_FRAMES: usize = 3;
const VAD_HANGOVER_FRAMES: usize = 10;
const VAD_ONSET_FRAMES: usize = 2;

pub fn extract_speech_from_pcm16(
    vad_model_path: impl AsRef<Path>,
    input_sample_rate: u32,
    pcm_le: &[u8],
) -> Result<Vec<f32>> {
    if input_sample_rate == 0 {
        return Err(TranscriptionError::InvalidAudio(
            "input sample rate must be greater than zero".to_string(),
        ));
    }
    let samples = pcm16_samples(pcm_le)?;
    extract_speech(vad_model_path, input_sample_rate, &samples)
}

pub(super) fn pcm16_samples(pcm_le: &[u8]) -> Result<Vec<f32>> {
    if !pcm_le.len().is_multiple_of(2) {
        return Err(TranscriptionError::InvalidAudio(
            "PCM16 input must contain an even number of bytes".to_string(),
        ));
    }

    Ok(pcm_le
        .as_chunks::<2>()
        .0
        .iter()
        .map(|chunk| i16::from_le_bytes(*chunk) as f32 / 32768.0)
        .collect())
}

fn extract_speech(
    vad_model_path: impl AsRef<Path>,
    input_sample_rate: u32,
    samples: &[f32],
) -> Result<Vec<f32>> {
    if samples.is_empty() {
        return Ok(Vec::new());
    }

    let vad_model_path = vad_model_path.as_ref();
    if !vad_model_path.is_file() {
        return Err(TranscriptionError::VadNotDownloaded);
    }
    let silero = SileroV4Vad::new(vad_model_path, 0.5)?;
    let mut vad = SpeechGate::new(
        Box::new(silero),
        VAD_PREFILL_FRAMES,
        VAD_HANGOVER_FRAMES,
        VAD_ONSET_FRAMES,
    );

    extract_speech_with_vad(input_sample_rate, samples, &mut vad)
}

fn extract_speech_with_vad(
    input_sample_rate: u32,
    samples: &[f32],
    vad: &mut dyn Vad,
) -> Result<Vec<f32>> {
    let mut resampler = FrameResampler::new(
        input_sample_rate as usize,
        TARGET_SAMPLE_RATE,
        Duration::from_secs_f64(vad.frame_size() as f64 / TARGET_SAMPLE_RATE as f64),
    )?;
    let mut speech = Vec::new();
    let mut vad_error = None;
    let mut emit = |frame: &[f32]| {
        if vad_error.is_some() {
            return;
        }
        match vad.is_speech(frame) {
            Ok(true) => {
                speech.extend_from_slice(&vad.drain_prefill());
                speech.extend_from_slice(frame);
            }
            Ok(false) => {}
            Err(error) => vad_error = Some(error),
        }
    };
    resampler.push(samples, &mut emit)?;
    resampler.finish(&mut emit)?;
    if let Some(error) = vad_error {
        return Err(error);
    }
    vad.reset();

    let min_samples = TARGET_SAMPLE_RATE * 5 / 4;
    if speech.len() < TARGET_SAMPLE_RATE && !speech.is_empty() {
        speech.resize(min_samples, 0.0);
    }

    Ok(speech)
}

struct FrameResampler {
    resampler: Option<Fft<f32>>,
    chunk_in: usize,
    in_buf: Vec<f32>,
    frame_samples: usize,
    pending: Vec<f32>,
}

impl FrameResampler {
    fn new(in_hz: usize, out_hz: usize, frame_dur: Duration) -> Result<Self> {
        let frame_samples = ((out_hz as f64 * frame_dur.as_secs_f64()).round()) as usize;
        if frame_samples == 0 {
            return Err(TranscriptionError::InvalidAudio(
                "frame duration too short".to_string(),
            ));
        }

        let resampler = if in_hz == out_hz {
            None
        } else {
            Some(Fft::<f32>::new_custom(
                in_hz,
                out_hz,
                RESAMPLER_CHUNK_SIZE,
                1,
                1,
                WindowFunction::BlackmanHarris2,
                FixedSync::Input,
            )?)
        };

        Ok(Self {
            resampler,
            chunk_in: RESAMPLER_CHUNK_SIZE,
            in_buf: Vec::with_capacity(RESAMPLER_CHUNK_SIZE),
            frame_samples,
            pending: Vec::with_capacity(frame_samples),
        })
    }

    fn push(&mut self, mut src: &[f32], mut emit: impl FnMut(&[f32])) -> Result<()> {
        if self.resampler.is_none() {
            self.emit_frames(src, &mut emit);
            return Ok(());
        }

        while !src.is_empty() {
            let space = self.chunk_in - self.in_buf.len();
            let take = space.min(src.len());
            self.in_buf.extend_from_slice(&src[..take]);
            src = &src[take..];

            if self.in_buf.len() == self.chunk_in {
                if let Some(resampler) = self.resampler.as_mut() {
                    let input =
                        InterleavedSlice::new(&self.in_buf, 1, self.chunk_in).map_err(|error| {
                            TranscriptionError::InvalidAudio(format!(
                                "Prepare audio resampler input: {error}"
                            ))
                        })?;
                    let out = resampler.process(&input, None).map_err(|error| {
                        TranscriptionError::Transcribe(format!("Resample recorded audio: {error}"))
                    })?;
                    self.emit_frames(&out.take_data(), &mut emit);
                }
                self.in_buf.clear();
            }
        }
        Ok(())
    }

    fn finish(&mut self, mut emit: impl FnMut(&[f32])) -> Result<()> {
        if let Some(resampler) = self.resampler.as_mut()
            && !self.in_buf.is_empty()
        {
            self.in_buf.resize(self.chunk_in, 0.0);
            let input = InterleavedSlice::new(&self.in_buf, 1, self.chunk_in).map_err(|error| {
                TranscriptionError::InvalidAudio(format!(
                    "Prepare final audio resampler input: {error}"
                ))
            })?;
            let out = resampler.process(&input, None).map_err(|error| {
                TranscriptionError::Transcribe(format!("Resample final recorded audio: {error}"))
            })?;
            self.emit_frames(&out.take_data(), &mut emit);
        }

        if !self.pending.is_empty() {
            self.pending.resize(self.frame_samples, 0.0);
            emit(&self.pending);
            self.pending.clear();
        }
        Ok(())
    }

    fn emit_frames(&mut self, mut data: &[f32], emit: &mut impl FnMut(&[f32])) {
        while !data.is_empty() {
            let space = self.frame_samples - self.pending.len();
            let take = space.min(data.len());
            self.pending.extend_from_slice(&data[..take]);
            data = &data[take..];

            if self.pending.len() == self.frame_samples {
                emit(&self.pending);
                self.pending.clear();
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use std::f32::consts::TAU;

    use super::*;

    #[test]
    fn vad_failure_does_not_return_partial_recording() {
        struct FailsAfterSpeech {
            frames: usize,
        }
        impl Vad for FailsAfterSpeech {
            fn frame_size(&self) -> usize {
                480
            }
            fn is_speech(&mut self, _: &[f32]) -> Result<bool> {
                self.frames += 1;
                if self.frames == 1 {
                    Ok(true)
                } else {
                    Err(TranscriptionError::Transcribe(
                        "injected VAD failure".into(),
                    ))
                }
            }
            fn reset(&mut self) {}
        }
        let mut vad = FailsAfterSpeech { frames: 0 };
        assert!(
            matches!(extract_speech_with_vad(16000, &vec![0.2; 1440], &mut vad), Err(TranscriptionError::Transcribe(detail)) if detail.contains("injected VAD failure"))
        );
        assert_eq!(vad.frames, 2);
    }

    fn resample(input: &[f32], sample_rate: usize, push_size: usize) -> Vec<f32> {
        let mut resampler =
            FrameResampler::new(sample_rate, 16_000, Duration::from_millis(30)).unwrap();
        let mut output = Vec::new();
        let mut emit = |frame: &[f32]| {
            assert_eq!(frame.len(), 480);
            output.extend_from_slice(frame);
        };
        for chunk in input.chunks(push_size) {
            resampler.push(chunk, &mut emit).unwrap();
        }
        resampler.finish(emit).unwrap();
        output
    }

    #[test]
    fn native_rate_preserves_samples_and_pads_the_last_frame() {
        let pcm = [-32768_i16, -512, -1, 0, 1, 512, 32767];
        let bytes: Vec<_> = pcm.iter().flat_map(|sample| sample.to_le_bytes()).collect();
        assert_eq!(
            pcm16_samples(&bytes).unwrap(),
            pcm.map(|sample| f32::from(sample) / 32768.0)
        );
        assert!(pcm16_samples(&bytes[..bytes.len() - 1]).is_err());
        let input: Vec<_> = (0..961).map(|i| i as f32 / 1000.0 - 0.5).collect();
        let output = resample(&input, 16_000, 137);

        assert_eq!(output.len(), 1440);
        assert_eq!(&output[..input.len()], input);
        assert!(output[input.len()..].iter().all(|&sample| sample == 0.0));
    }

    #[test]
    fn resampling_is_independent_of_push_boundaries() {
        for sample_rate in [44_100, 48_000] {
            let input: Vec<_> = (0..sample_rate / 4 + 19)
                .map(|i| (TAU * 1000.0 * i as f32 / sample_rate as f32).sin())
                .collect();
            let expected = resample(&input, sample_rate, input.len());
            assert!(!expected.is_empty());

            for push_size in [1, 257, 1023, 1024, 1025] {
                assert_eq!(
                    resample(&input, sample_rate, push_size),
                    expected,
                    "{sample_rate} Hz, {push_size} samples per push"
                );
            }
        }
    }

    #[test]
    fn downsampling_preserves_speech_frequencies_and_rejects_aliasing() {
        fn amplitude(samples: &[f32], frequency: f32) -> f32 {
            let (sin, cos) =
                samples
                    .iter()
                    .enumerate()
                    .fold((0.0, 0.0), |(sin, cos), (i, &sample)| {
                        let phase = TAU * frequency * i as f32 / 16_000.0;
                        (sin + sample * phase.sin(), cos + sample * phase.cos())
                    });
            2.0 * sin.hypot(cos) / samples.len() as f32
        }

        for sample_rate in [44_100, 48_000] {
            let input: Vec<_> = (0..sample_rate)
                .map(|i| {
                    let phase = TAU * i as f32 / sample_rate as f32;
                    0.5 * (1000.0 * phase).sin() + 0.5 * (12_000.0 * phase).sin()
                })
                .collect();
            let output = resample(&input, sample_rate, 257);
            let settled = &output[1600..9600];
            let speech = amplitude(settled, 1000.0);
            let alias = amplitude(settled, 4000.0);

            assert!((speech - 0.5).abs() < 0.01, "{sample_rate} Hz: {speech}");
            assert!(alias < 0.01, "{sample_rate} Hz: {alias}");
        }
    }
}
