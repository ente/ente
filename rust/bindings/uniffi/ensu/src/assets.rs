use std::path::PathBuf;
use std::sync::{Arc, OnceLock};

use ente_assets::download;
use thiserror::Error;

#[derive(uniffi::Object)]
pub struct Asset {
    pub(crate) inner: ente_assets::Asset,
}

impl Asset {
    pub(crate) fn new(inner: ente_assets::Asset) -> Arc<Self> {
        Arc::new(Self { inner })
    }
}

#[derive(Debug, Error, uniffi::Error)]
pub enum AssetDownloadError {
    #[error("download cancelled")]
    Cancelled,
    #[error("{detail}")]
    Validation { detail: String },
    #[error("HTTP {status}")]
    Http { status: u16 },
    #[error("network: {detail}")]
    Network { detail: String },
    #[error("size mismatch: expected {expected} bytes, got {actual}")]
    SizeMismatch { expected: u64, actual: u64 },
    #[error("range protocol violation: {detail}")]
    Protocol { detail: String },
    #[error("invalid download target: {detail}")]
    InvalidTarget { detail: String },
    #[error("not enough storage space")]
    StorageFull,
    #[error("{detail}")]
    Io { detail: String },
}

impl From<download::Error> for AssetDownloadError {
    fn from(value: download::Error) -> Self {
        match value {
            download::Error::Cancelled => Self::Cancelled,
            download::Error::Target { source, .. } => Self::from(*source),
            download::Error::Fallback { single, .. } => Self::from(*single),
            download::Error::Validation(detail) => Self::Validation { detail },
            download::Error::Http(status) => Self::Http { status },
            download::Error::Network(detail) => Self::Network { detail },
            download::Error::SizeMismatch { expected, actual } => {
                Self::SizeMismatch { expected, actual }
            }
            download::Error::Protocol(detail) => Self::Protocol { detail },
            download::Error::InvalidTarget(detail) => Self::InvalidTarget { detail },
            download::Error::StorageFull => Self::StorageFull,
            download::Error::Io(error) => Self::Io {
                detail: error.to_string(),
            },
            download::Error::Json(error) => Self::Io {
                detail: error.to_string(),
            },
        }
    }
}

#[uniffi::export]
pub fn llm_asset(model_id: String) -> Arc<Asset> {
    Asset::new(ente_ensu::model::mobile_llm_asset(&model_id).expect("valid mobile model catalog"))
}

#[uniffi::export]
pub fn transcription_model_asset() -> Arc<Asset> {
    Asset::new(ente_ensu::model::transcription_model_asset())
}

#[uniffi::export]
pub fn voice_activity_model_asset() -> Arc<Asset> {
    Asset::new(ente_ensu::model::voice_activity_model_asset())
}

#[uniffi::export]
pub fn knowledge_embedding_model_asset() -> Arc<Asset> {
    Asset::new(ente_ensu::model::knowledge_embedding_model_asset())
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct AssetDownloadProgress {
    pub label: String,
    pub downloaded_bytes: i64,
    pub total_bytes: Option<i64>,
    pub percentage: f64,
    pub status: String,
    pub log_line: Option<String>,
}

impl From<ente_assets::AssetDownloadProgress> for AssetDownloadProgress {
    fn from(value: ente_assets::AssetDownloadProgress) -> Self {
        let display = ente_ensu::model::display_progress(&value);
        Self {
            label: value.asset_progress.label,
            downloaded_bytes: i64::try_from(value.downloaded_bytes).unwrap_or(i64::MAX),
            total_bytes: value
                .total_bytes
                .map(|total| i64::try_from(total).unwrap_or(i64::MAX)),
            percentage: value.percentage,
            status: display.status,
            log_line: display.log_line,
        }
    }
}

#[uniffi::export(callback_interface)]
pub trait AssetDownloadCallback: Send + Sync {
    fn on_progress(&self, progress: AssetDownloadProgress);
}

#[derive(Clone, uniffi::Record)]
pub struct LegacyAssets {
    pub llm_dir: Option<String>,
    pub transcription_dir: Option<String>,
    pub model_url: Option<String>,
    pub mmproj_url: Option<String>,
}

impl From<LegacyAssets> for ente_ensu::model::migrations::LegacyAssets {
    fn from(value: LegacyAssets) -> Self {
        Self {
            llm_dir: value.llm_dir.map(PathBuf::from),
            transcription_dir: value.transcription_dir.map(PathBuf::from),
            models_dir: None,
            model_url: value.model_url,
            mmproj_url: value.mmproj_url,
        }
    }
}

#[uniffi::export]
pub fn needs_asset_migration(legacy: LegacyAssets) -> bool {
    ente_ensu::model::migrations::needs_migration(&legacy.into())
}

#[uniffi::export]
pub fn migrate_ensu_assets(assets_dir: String, legacy: LegacyAssets) -> Option<String> {
    ente_ensu::model::migrations::migrate_ensu_assets(
        PathBuf::from(assets_dir).as_path(),
        legacy.into(),
    )
}

#[derive(uniffi::Object)]
pub struct AssetStoreCore {
    inner: ente_assets::AssetStore,
    runtime: OnceLock<tokio::runtime::Runtime>,
}

#[uniffi::export]
impl AssetStoreCore {
    #[uniffi::constructor]
    pub fn new(assets_dir: String) -> Arc<Self> {
        Arc::new(Self {
            inner: ente_assets::AssetStore::new(assets_dir),
            runtime: OnceLock::new(),
        })
    }

    pub fn asset_dir(&self, asset: Arc<Asset>) -> String {
        self.inner.asset_dir(&asset.inner).display().to_string()
    }

    pub fn llm_model_path(&self, asset: Arc<Asset>) -> Option<String> {
        ente_ensu::model::llm_model_path(&self.inner, &asset.inner)
            .map(|path| path.display().to_string())
    }

    pub fn llm_mmproj_path(&self, asset: Arc<Asset>) -> Option<String> {
        ente_ensu::model::llm_mmproj_path(&self.inner, &asset.inner)
            .map(|path| path.display().to_string())
    }

    pub fn voice_activity_model_path(&self, asset: Arc<Asset>) -> String {
        ente_ensu::model::voice_activity_model_path(&self.inner, &asset.inner)
            .display()
            .to_string()
    }

    pub fn is_downloaded(&self, asset: Arc<Asset>) -> bool {
        self.inner.is_downloaded(&asset.inner)
    }

    pub fn estimated_download_size(&self, asset: Arc<Asset>) -> Option<i64> {
        self.runtime()
            .ok()?
            .block_on(
                self.inner
                    .estimated_download_size(std::slice::from_ref(&asset.inner)),
            )
            .map(|size| i64::try_from(size).unwrap_or(i64::MAX))
    }

    pub fn remove_downloaded(&self, asset: Arc<Asset>) -> bool {
        let existed = self.inner.is_downloaded(&asset.inner);
        let removed = self
            .runtime()
            .is_ok_and(|runtime| runtime.block_on(self.inner.remove(&asset.inner)).is_ok());
        existed && removed
    }

    pub fn download(
        &self,
        assets: Vec<Arc<Asset>>,
        callback: Box<dyn AssetDownloadCallback>,
        cancellation: Arc<CancellationToken>,
    ) -> Result<(), AssetDownloadError> {
        let assets = assets
            .into_iter()
            .map(|asset| asset.inner.clone())
            .collect::<Vec<_>>();
        match self.runtime() {
            Ok(runtime) => runtime
                .block_on(self.inner.download(
                    &assets,
                    |progress| callback.on_progress(progress.into()),
                    cancellation.inner.clone(),
                ))
                .map_err(AssetDownloadError::from),
            Err(error) => Err(AssetDownloadError::from(error)),
        }
    }
}

impl AssetStoreCore {
    pub(crate) fn store(&self) -> &ente_assets::AssetStore {
        &self.inner
    }

    pub(crate) fn runtime(&self) -> Result<&tokio::runtime::Runtime, ente_assets::download::Error> {
        if let Some(runtime) = self.runtime.get() {
            return Ok(runtime);
        }
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()?;
        Ok(self.runtime.get_or_init(|| runtime))
    }
}

#[derive(Default, uniffi::Object)]
pub struct CancellationToken {
    pub(crate) inner: ente_assets::download::CancellationToken,
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
