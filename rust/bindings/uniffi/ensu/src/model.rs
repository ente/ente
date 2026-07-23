use std::path::{Path, PathBuf};
use std::sync::Arc;

use crate::download::DownloadError;
use crate::llm::LlmError;

#[derive(Debug, Clone, uniffi::Enum)]
pub enum ModelTarget {
    Files {
        id: String,
        files: Vec<ModelFile>,
    },
    TarGz {
        id: String,
        url: String,
        sha256: String,
    },
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct ModelFile {
    pub name: String,
    pub url: String,
    pub sha256: String,
}

impl From<ModelTarget> for ente_model_download::ModelTarget {
    fn from(value: ModelTarget) -> Self {
        match value {
            ModelTarget::Files { id, files } => Self::Files {
                id,
                files: files
                    .into_iter()
                    .map(|file| ente_model_download::ModelFile {
                        name: file.name,
                        url: file.url,
                        sha256: file.sha256,
                    })
                    .collect(),
            },
            ModelTarget::TarGz { id, url, sha256 } => Self::TarGz { id, url, sha256 },
        }
    }
}

impl From<ente_model_download::ModelTarget> for ModelTarget {
    fn from(value: ente_model_download::ModelTarget) -> Self {
        match value {
            ente_model_download::ModelTarget::Files { id, files } => Self::Files {
                id,
                files: files
                    .into_iter()
                    .map(|file| ModelFile {
                        name: file.name,
                        url: file.url,
                        sha256: file.sha256,
                    })
                    .collect(),
            },
            ente_model_download::ModelTarget::TarGz { id, url, sha256 } => {
                Self::TarGz { id, url, sha256 }
            }
        }
    }
}

#[uniffi::export]
pub fn mobile_llm_target(model_id: String) -> Result<ModelTarget, LlmError> {
    ente_ensu::model::mobile_llm_target(&model_id)
        .map(Into::into)
        .map_err(|err| LlmError::Download {
            error: DownloadError::InvalidTarget {
                message: err.to_string(),
            },
        })
}

#[uniffi::export]
pub fn transcription_model_target() -> ModelTarget {
    ente_ensu::model::transcription_target().into()
}

#[uniffi::export]
pub fn voice_activity_model_target() -> ModelTarget {
    ente_ensu::model::voice_activity_target().into()
}

#[uniffi::export]
pub fn knowledge_embedding_model_target() -> ModelTarget {
    ente_ensu::model::knowledge_embedding_target().into()
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
}

#[derive(uniffi::Record)]
pub struct LegacyModels {
    pub llm_dir: Option<String>,
    pub transcription_dir: String,
    pub model_url: Option<String>,
    pub mmproj_url: Option<String>,
}

#[uniffi::export]
pub fn migrate_mobile_models(models_dir: String, legacy: LegacyModels) -> Option<String> {
    ente_ensu::model::migrations::migrate_mobile_models(
        Path::new(&models_dir),
        ente_ensu::model::migrations::LegacyModels {
            llm_dir: legacy.llm_dir.map(PathBuf::from),
            transcription_dir: PathBuf::from(legacy.transcription_dir),
            model_url: legacy.model_url,
            mmproj_url: legacy.mmproj_url,
        },
    )
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

    pub fn model_dir(&self, target: ModelTarget) -> String {
        self.inner.model_dir(&target.into()).display().to_string()
    }

    pub fn llm_model_path(&self, target: ModelTarget) -> Option<String> {
        ente_ensu::model::llm_model_path(&self.inner, &target.into())
            .map(|path| path.display().to_string())
    }

    pub fn llm_mmproj_path(&self, target: ModelTarget) -> Option<String> {
        ente_ensu::model::llm_mmproj_path(&self.inner, &target.into())
            .map(|path| path.display().to_string())
    }

    pub fn voice_activity_model_path(&self) -> String {
        ente_ensu::model::voice_activity_model_path(&self.inner)
            .display()
            .to_string()
    }

    pub fn is_downloaded(&self, target: ModelTarget) -> bool {
        self.inner.is_downloaded(&target.into())
    }

    pub fn is_download_active(&self) -> bool {
        self.inner.is_download_active()
    }

    pub fn estimated_download_size(&self, target: ModelTarget) -> Option<i64> {
        self.inner
            .estimated_download_size(&target.into())
            .map(|size| i64::try_from(size).unwrap_or(i64::MAX))
    }

    pub fn remove_downloaded(&self, target: ModelTarget) -> bool {
        self.inner.remove_downloaded(&target.into())
    }

    pub fn download(
        &self,
        targets: Vec<ModelTarget>,
        callback: Box<dyn ModelDownloadCallback>,
        cancellation: Arc<CancellationToken>,
    ) -> Result<(), LlmError> {
        let targets: Vec<ente_model_download::ModelTarget> =
            targets.into_iter().map(Into::into).collect();
        self.inner
            .download(
                &targets,
                move |progress| callback.on_progress(progress.into()),
                &cancellation.inner,
            )
            .map_err(map_download_error)
    }
}

#[derive(Default, uniffi::Object)]
pub struct CancellationToken {
    pub(crate) inner: ente_model_download::download::CancellationToken,
}

#[uniffi::export]
impl CancellationToken {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self::default())
    }

    pub fn cancel(&self) {
        self.inner.cancel();
    }
}

fn map_download_error(err: ente_model_download::download::Error) -> LlmError {
    match DownloadError::from(err) {
        DownloadError::Cancelled => LlmError::Cancelled,
        error => LlmError::Download { error },
    }
}
