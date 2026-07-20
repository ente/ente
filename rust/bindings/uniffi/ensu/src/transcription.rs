use std::sync::Arc;

use thiserror::Error;

use ente_ensu::transcription;

#[derive(Debug, Error, uniffi::Error)]
pub enum TranscriptionError {
    #[error("Transcription model is not downloaded")]
    NotDownloaded,
    #[error("Voice activity model is not downloaded")]
    VadNotDownloaded,
    #[error("{detail}")]
    InvalidAudio { detail: String },
    #[error("{detail}")]
    Transcribe { detail: String },
    #[error("not enough storage space")]
    StorageFull,
    #[error("{detail}")]
    Io { detail: String },
}

impl From<transcription::TranscriptionError> for TranscriptionError {
    fn from(value: transcription::TranscriptionError) -> Self {
        match value {
            transcription::TranscriptionError::NotDownloaded => Self::NotDownloaded,
            transcription::TranscriptionError::VadNotDownloaded => Self::VadNotDownloaded,
            transcription::TranscriptionError::InvalidAudio(message) => {
                Self::InvalidAudio { detail: message }
            }
            transcription::TranscriptionError::Transcribe(message) => {
                Self::Transcribe { detail: message }
            }
            transcription::TranscriptionError::StorageFull => Self::StorageFull,
            transcription::TranscriptionError::Io(err) => Self::Io {
                detail: err.to_string(),
            },
        }
    }
}

#[derive(uniffi::Object)]
pub struct Transcriber {
    inner: transcription::Transcriber,
}

#[uniffi::export]
impl Transcriber {
    #[uniffi::constructor]
    pub fn new(model_dir: String, vad_model_path: String) -> Arc<Self> {
        Arc::new(Self {
            inner: transcription::Transcriber::new(model_dir, vad_model_path),
        })
    }

    pub fn load_model(&self) -> Result<(), TranscriptionError> {
        self.inner.load_model().map_err(Into::into)
    }

    pub fn unload_model(&self) {
        self.inner.unload_model();
    }

    pub fn transcribe(
        &self,
        input_sample_rate: u32,
        pcm_le: Vec<u8>,
    ) -> Result<String, TranscriptionError> {
        self.inner
            .transcribe(input_sample_rate, pcm_le)
            .map_err(Into::into)
    }
}
