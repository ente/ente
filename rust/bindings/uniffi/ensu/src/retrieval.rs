use std::sync::Arc;

use ente_ensu::retrieval as core;
use thiserror::Error;

use crate::download::DownloadError;
use crate::model::CancellationToken;

#[derive(Debug, Error, uniffi::Error)]
pub enum KnowledgeRetrievalError {
    #[error("invalid retrieval input: {detail}")]
    InvalidInput { detail: String },
    #[error("invalid knowledge pack: {detail}")]
    InvalidPack { detail: String },
    #[error("knowledge pack I/O failed: {detail}")]
    Io { detail: String },
    #[error("knowledge pack JSON failed: {detail}")]
    Json { detail: String },
    #[error("knowledge pack metadata decompression failed: {detail}")]
    Zstd { detail: String },
}

impl From<core::RetrievalError> for KnowledgeRetrievalError {
    fn from(value: core::RetrievalError) -> Self {
        match value {
            core::RetrievalError::InvalidInput(detail) => Self::InvalidInput { detail },
            core::RetrievalError::InvalidPack(detail) => Self::InvalidPack { detail },
            core::RetrievalError::Io(error) => Self::Io {
                detail: error.to_string(),
            },
            core::RetrievalError::Json(error) => Self::Json {
                detail: error.to_string(),
            },
            core::RetrievalError::Zstd(detail) => Self::Zstd { detail },
        }
    }
}

fn knowledge_dataset(
    stable_id: &str,
) -> Result<ente_ensu::config::KnowledgeDatasetConfig, KnowledgeRetrievalError> {
    ente_ensu::config::knowledge_dataset(stable_id).ok_or_else(|| {
        KnowledgeRetrievalError::InvalidInput {
            detail: format!("unknown knowledge dataset ID: {stable_id}"),
        }
    })
}

#[derive(Debug, Error, uniffi::Error)]
pub enum KnowledgeDownloadError {
    #[error("knowledge download failed")]
    Download { error: DownloadError },
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct RetrievalHit {
    pub score: f32,
    pub text: String,
    pub title: String,
    pub section: Option<String>,
    pub source_url: String,
}

impl From<core::RetrievalHit> for RetrievalHit {
    fn from(value: core::RetrievalHit) -> Self {
        Self {
            score: value.score,
            text: value.text,
            title: value.title,
            section: value.section,
            source_url: value.source_url,
        }
    }
}

impl From<RetrievalHit> for core::RetrievalHit {
    fn from(value: RetrievalHit) -> Self {
        Self {
            score: value.score,
            text: value.text,
            title: value.title,
            section: value.section,
            source_url: value.source_url,
        }
    }
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct KnowledgePromptHit {
    pub dataset_id: String,
    pub hit: RetrievalHit,
}

impl From<KnowledgePromptHit> for core::KnowledgePromptHit {
    fn from(value: KnowledgePromptHit) -> Self {
        Self {
            dataset_id: value.dataset_id,
            hit: value.hit.into(),
        }
    }
}

#[derive(uniffi::Object)]
pub struct RetrievalIndex {
    inner: core::RetrievalIndex,
}

#[uniffi::export]
impl RetrievalIndex {
    #[uniffi::constructor]
    pub fn open(
        directory: String,
        stable_id: String,
    ) -> Result<Arc<Self>, KnowledgeRetrievalError> {
        let inner = core::RetrievalIndex::open(directory, &knowledge_dataset(&stable_id)?)?;
        Ok(Arc::new(Self { inner }))
    }

    pub fn search(
        &self,
        query: Vec<f32>,
        max_hits: u32,
        threshold: f32,
    ) -> Result<Vec<RetrievalHit>, KnowledgeRetrievalError> {
        self.inner
            .search(&query, max_hits, threshold)
            .map(|hits| hits.into_iter().map(Into::into).collect())
            .map_err(Into::into)
    }
}

#[derive(Debug, Clone, uniffi::Enum)]
pub enum KnowledgeReconciliationStatus {
    Download,
    Ready,
    UpdateAvailable,
}

impl From<core::KnowledgeReconciliationStatus> for KnowledgeReconciliationStatus {
    fn from(value: core::KnowledgeReconciliationStatus) -> Self {
        match value {
            core::KnowledgeReconciliationStatus::Download => Self::Download,
            core::KnowledgeReconciliationStatus::Ready => Self::Ready,
            core::KnowledgeReconciliationStatus::UpdateAvailable => Self::UpdateAvailable,
        }
    }
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct KnowledgeReconciliation {
    pub status: KnowledgeReconciliationStatus,
    pub active_identity: Option<String>,
    pub active_directory: Option<String>,
}

impl From<core::KnowledgeReconciliation> for KnowledgeReconciliation {
    fn from(value: core::KnowledgeReconciliation) -> Self {
        Self {
            status: value.status.into(),
            active_identity: value.active_identity,
            active_directory: value.active_directory,
        }
    }
}

#[uniffi::export]
pub fn reconcile_knowledge_pack(
    pack_root: String,
    stable_id: String,
) -> Result<KnowledgeReconciliation, KnowledgeRetrievalError> {
    core::reconcile_knowledge_pack(pack_root, &knowledge_dataset(&stable_id)?)
        .map(Into::into)
        .map_err(Into::into)
}

#[uniffi::export]
pub fn cleanup_obsolete_knowledge_pack_revisions(
    pack_root: String,
    stable_id: String,
    active_identity: String,
) -> Result<(), KnowledgeRetrievalError> {
    core::cleanup_obsolete_knowledge_pack_revisions(
        pack_root,
        &knowledge_dataset(&stable_id)?,
        &active_identity,
    )
    .map_err(Into::into)
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct SourceCitation {
    pub dataset_id: String,
    pub dataset_label: String,
    pub credit: String,
    pub title: String,
    pub source_url: String,
    pub license_label: String,
    pub license_url: String,
}

impl From<SourceCitation> for core::SourceCitation {
    fn from(value: SourceCitation) -> Self {
        Self {
            dataset_id: value.dataset_id,
            dataset_label: value.dataset_label,
            credit: value.credit,
            title: value.title,
            source_url: value.source_url,
            license_label: value.license_label,
            license_url: value.license_url,
        }
    }
}

impl From<core::SourceCitation> for SourceCitation {
    fn from(value: core::SourceCitation) -> Self {
        Self {
            dataset_id: value.dataset_id,
            dataset_label: value.dataset_label,
            credit: value.credit,
            title: value.title,
            source_url: value.source_url,
            license_label: value.license_label,
            license_url: value.license_url,
        }
    }
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct KnowledgePromptContext {
    pub text: String,
    pub citations: Vec<SourceCitation>,
}

impl From<core::KnowledgePromptContext> for KnowledgePromptContext {
    fn from(value: core::KnowledgePromptContext) -> Self {
        Self {
            text: value.text,
            citations: value.citations.into_iter().map(Into::into).collect(),
        }
    }
}

#[uniffi::export]
pub fn build_knowledge_prompt_context(
    hits: Vec<KnowledgePromptHit>,
    max_utf8_bytes: u32,
) -> Result<Option<KnowledgePromptContext>, KnowledgeRetrievalError> {
    let hits = hits.into_iter().map(Into::into).collect::<Vec<_>>();
    core::build_knowledge_prompt_context(&hits, max_utf8_bytes as usize)
        .map(|context| context.map(Into::into))
        .map_err(Into::into)
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct ParsedAssistantText {
    pub text: String,
    pub citations: Vec<SourceCitation>,
    pub source_label: Option<String>,
}

impl From<core::ParsedAssistantText> for ParsedAssistantText {
    fn from(value: core::ParsedAssistantText) -> Self {
        let source_label = core::knowledge_source_chip_label(&value.citations);
        Self {
            text: value.text,
            citations: value.citations.into_iter().map(Into::into).collect(),
            source_label,
        }
    }
}

#[uniffi::export]
pub fn finalize_assistant_text(
    raw_assistant_text: String,
    citations: Vec<SourceCitation>,
) -> Result<String, KnowledgeRetrievalError> {
    let citations = citations.into_iter().map(Into::into).collect::<Vec<_>>();
    core::finalize_assistant_text(&raw_assistant_text, &citations).map_err(Into::into)
}

#[uniffi::export]
pub fn parse_assistant_text(stored_text: String) -> ParsedAssistantText {
    core::parse_assistant_text(&stored_text).into()
}

#[uniffi::export]
pub fn clean_assistant_text(stored_text: String) -> String {
    core::clean_assistant_text(&stored_text)
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct KnowledgeDownloadProgress {
    pub label: String,
    pub percentage: f64,
}

impl From<ente_model_download::download::Progress> for KnowledgeDownloadProgress {
    fn from(value: ente_model_download::download::Progress) -> Self {
        Self {
            label: value.label,
            percentage: value.percentage,
        }
    }
}

#[uniffi::export(callback_interface)]
pub trait KnowledgeDownloadCallback: Send + Sync {
    fn on_progress(&self, progress: KnowledgeDownloadProgress);
}

#[uniffi::export]
pub fn download_knowledge_pack(
    pack_root: String,
    stable_id: String,
    callback: Box<dyn KnowledgeDownloadCallback>,
    cancellation: Arc<CancellationToken>,
) -> Result<(), KnowledgeDownloadError> {
    let expected_dataset = ente_ensu::config::knowledge_dataset(&stable_id).ok_or_else(|| {
        KnowledgeDownloadError::Download {
            error: DownloadError::InvalidTarget {
                message: format!("unknown knowledge dataset ID: {stable_id}"),
            },
        }
    })?;
    core::download_knowledge_pack(
        pack_root,
        &expected_dataset,
        move |progress| callback.on_progress(progress.into()),
        cancellation.inner.clone(),
    )
    .map_err(|error| KnowledgeDownloadError::Download {
        error: error.into(),
    })
}
