use std::path::{Path, PathBuf};
use std::sync::{Mutex, MutexGuard, PoisonError};

use transcribe_rs::onnx::Quantization;
use transcribe_rs::onnx::parakeet::{ParakeetModel, ParakeetParams, TimestampGranularity};

use crate::transcription::audio::extract_speech_from_pcm16;
use crate::transcription::text::filter_transcription_output;
use crate::transcription::{Result, TranscriptionError};

pub struct Transcriber {
    model_dir: PathBuf,
    vad_model_path: PathBuf,
    loaded: Mutex<Option<ParakeetModel>>,
}

impl Transcriber {
    pub fn new(model_dir: impl Into<PathBuf>, vad_model_path: impl Into<PathBuf>) -> Self {
        Self {
            model_dir: model_dir.into(),
            vad_model_path: vad_model_path.into(),
            loaded: Mutex::new(None),
        }
    }

    pub fn load_model(&self) -> Result<()> {
        if !self.model_dir.is_dir() {
            return Err(TranscriptionError::NotDownloaded);
        }
        ensure_loaded(&mut self.lock(), &self.model_dir)?;
        Ok(())
    }

    pub fn unload_model(&self) {
        *self.lock() = None;
    }

    pub fn transcribe(&self, input_sample_rate: u32, pcm_le: Vec<u8>) -> Result<String> {
        if pcm_le.is_empty() {
            return Ok(String::new());
        }
        if !self.model_dir.is_dir() {
            return Err(TranscriptionError::NotDownloaded);
        }
        if !self.vad_model_path.is_file() {
            return Err(TranscriptionError::VadNotDownloaded);
        }

        let speech = extract_speech_from_pcm16(&self.vad_model_path, input_sample_rate, &pcm_le)?;
        if speech.is_empty() {
            return Ok(String::new());
        }

        let mut loaded = self.lock();
        let model = ensure_loaded(&mut loaded, &self.model_dir)?;
        let result = model.transcribe_with(
            &speech,
            &ParakeetParams {
                timestamp_granularity: Some(TimestampGranularity::Segment),
                ..Default::default()
            },
        )?;

        Ok(filter_transcription_output(&result.text))
    }

    fn lock(&self) -> MutexGuard<'_, Option<ParakeetModel>> {
        self.loaded.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

fn ensure_loaded<'a>(
    loaded: &'a mut Option<ParakeetModel>,
    model_dir: &Path,
) -> Result<&'a mut ParakeetModel> {
    match loaded {
        Some(model) => Ok(model),
        slot => Ok(slot.insert(ParakeetModel::load(model_dir, &Quantization::Int8)?)),
    }
}
