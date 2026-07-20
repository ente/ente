use std::path::Path;
use std::sync::Arc;

use crate::download::DownloadError;
use crate::llm::LlmError;

#[derive(Debug, Clone, uniffi::Enum)]
pub enum ModelDownloadTarget {
    Gguf {
        id: String,
        url: String,
        mmproj_url: Option<String>,
    },
    TarGz {
        id: String,
        url: String,
    },
    Onnx {
        id: String,
        url: String,
    },
}

impl From<ModelDownloadTarget> for ente_model_download::ModelDownloadTarget {
    fn from(value: ModelDownloadTarget) -> Self {
        match value {
            ModelDownloadTarget::Gguf {
                id,
                url,
                mmproj_url,
            } => Self::Gguf {
                id,
                url,
                mmproj_url,
            },
            ModelDownloadTarget::TarGz { id, url } => Self::TarGz { id, url },
            ModelDownloadTarget::Onnx { id, url } => Self::Onnx { id, url },
        }
    }
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct ModelDownloadProgress {
    pub downloaded_bytes: i64,
    pub total_bytes: Option<i64>,
    pub percent: i32,
    pub status: String,
    pub log_line: Option<String>,
}

impl From<ente_model_download::ModelDownloadProgress> for ModelDownloadProgress {
    fn from(value: ente_model_download::ModelDownloadProgress) -> Self {
        Self {
            downloaded_bytes: i64::try_from(value.downloaded_bytes).unwrap_or(i64::MAX),
            total_bytes: value
                .total_bytes
                .map(|total| i64::try_from(total).unwrap_or(i64::MAX)),
            percent: value.percent,
            status: value.status,
            log_line: value.log_line,
        }
    }
}

#[uniffi::export(callback_interface)]
pub trait ModelDownloadCallback: Send + Sync {
    fn on_progress(&self, progress: ModelDownloadProgress);
    fn is_cancelled(&self) -> bool;
}

#[uniffi::export]
pub fn migrate_ensu_legacy_models(
    models_dir: String,
    llm_legacy_dir: Option<String>,
    transcription_legacy_dir: String,
    llm_targets: Vec<ModelDownloadTarget>,
    transcription_model: ModelDownloadTarget,
    voice_activity_model: ModelDownloadTarget,
) {
    let llm_targets: Vec<ente_model_download::ModelDownloadTarget> =
        llm_targets.into_iter().map(Into::into).collect();
    ente_model_download::migrate_ensu_legacy_models(
        Path::new(&models_dir),
        llm_legacy_dir.as_deref().map(Path::new),
        Path::new(&transcription_legacy_dir),
        &llm_targets,
        &transcription_model.into(),
        &voice_activity_model.into(),
    );
}

#[derive(uniffi::Object)]
pub struct ModelDownloadCore {
    inner: ente_model_download::ModelDownloader,
}

#[uniffi::export]
impl ModelDownloadCore {
    #[uniffi::constructor]
    pub fn new(models_dir: String) -> Arc<Self> {
        Arc::new(Self {
            inner: ente_model_download::ModelDownloader::new(models_dir),
        })
    }

    pub fn model_path(&self, target: ModelDownloadTarget) -> String {
        self.inner.model_path(&target.into()).display().to_string()
    }

    pub fn mmproj_path(&self, target: ModelDownloadTarget) -> Option<String> {
        self.inner
            .mmproj_path(&target.into())
            .map(|path| path.display().to_string())
    }

    pub fn is_downloaded(&self, target: ModelDownloadTarget) -> bool {
        self.inner.is_downloaded(&target.into())
    }

    pub fn is_download_active(&self) -> bool {
        self.inner.is_download_active()
    }

    pub fn estimated_download_size(&self, target: ModelDownloadTarget) -> Option<i64> {
        self.inner.estimated_download_size(&target.into())
    }

    pub fn cancel(&self) {
        self.inner.cancel();
    }

    pub fn remove_downloaded(&self, target: ModelDownloadTarget) -> bool {
        self.inner.remove_downloaded(&target.into())
    }

    pub fn download(
        &self,
        targets: Vec<ModelDownloadTarget>,
        callback: Box<dyn ModelDownloadCallback>,
    ) -> Result<bool, LlmError> {
        let callback: Arc<dyn ModelDownloadCallback> = Arc::from(callback);
        let progress_callback = Arc::clone(&callback);
        let cancel_callback = Arc::clone(&callback);
        let targets: Vec<ente_model_download::ModelDownloadTarget> =
            targets.into_iter().map(Into::into).collect();
        self.inner
            .download(
                &targets,
                move |progress| progress_callback.on_progress(progress.into()),
                move || cancel_callback.is_cancelled(),
            )
            .map_err(|err| match DownloadError::from(err) {
                DownloadError::Cancelled => LlmError::Cancelled,
                error => LlmError::Download { error },
            })
    }
}
