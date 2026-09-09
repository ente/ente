use std::sync::Arc;

use ente_ensu::retrieval as core;
use thiserror::Error;

use crate::assets::{Asset, AssetStoreCore};

#[derive(Debug, Error, uniffi::Error)]
pub enum KnowledgeRetrievalError {
    #[error("{detail}")]
    Other { detail: String },
}

impl From<core::RetrievalError> for KnowledgeRetrievalError {
    fn from(value: core::RetrievalError) -> Self {
        Self::Other {
            detail: ente_core::error::chain(&value),
        }
    }
}

fn knowledge_dataset(
    stable_id: &str,
) -> Result<ente_ensu::config::KnowledgeDatasetConfig, KnowledgeRetrievalError> {
    ente_ensu::config::knowledge_dataset(stable_id).ok_or_else(|| KnowledgeRetrievalError::Other {
        detail: format!("invalid retrieval input: unknown knowledge dataset ID: {stable_id}"),
    })
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
    store: Arc<AssetStoreCore>,
    stable_id: String,
) -> Result<KnowledgeReconciliation, KnowledgeRetrievalError> {
    let dataset = knowledge_dataset(&stable_id)?;
    let pack_root = core::knowledge_pack_root(store.store(), &dataset).map_err(|error| {
        KnowledgeRetrievalError::Other {
            detail: format!("invalid retrieval input: {error}"),
        }
    })?;
    core::reconcile_knowledge_pack(pack_root, &dataset)
        .map(Into::into)
        .map_err(Into::into)
}

#[uniffi::export]
pub fn cleanup_obsolete_knowledge_pack_revisions(
    store: Arc<AssetStoreCore>,
    stable_id: String,
    active_identity: String,
) -> Result<(), KnowledgeRetrievalError> {
    let dataset = knowledge_dataset(&stable_id)?;
    let pack_root = core::knowledge_pack_root(store.store(), &dataset).map_err(|error| {
        KnowledgeRetrievalError::Other {
            detail: format!("invalid retrieval input: {error}"),
        }
    })?;
    core::cleanup_obsolete_knowledge_pack_revisions(pack_root, &dataset, &active_identity)
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

#[uniffi::export]
pub fn knowledge_pack_asset(stable_id: String) -> Result<Arc<Asset>, KnowledgeRetrievalError> {
    let dataset = knowledge_dataset(&stable_id)?;
    core::knowledge_asset(&dataset)
        .map(Asset::new)
        .map_err(|error| KnowledgeRetrievalError::Other {
            detail: format!("invalid retrieval input: {error}"),
        })
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct NoteSourceReference {
    pub collection_id: String,
    pub collection_label: Option<String>,
    pub document_id: String,
    pub indexed_revision: String,
    pub title: String,
    pub section: Option<String>,
}

impl From<ente_ensu::notes::NoteSourceReference> for NoteSourceReference {
    fn from(value: ente_ensu::notes::NoteSourceReference) -> Self {
        Self {
            collection_id: value.collection_id,
            collection_label: value.collection_label,
            document_id: value.document_id,
            indexed_revision: value.indexed_revision,
            title: value.title,
            section: value.section,
        }
    }
}

impl From<NoteSourceReference> for ente_ensu::notes::NoteSourceReference {
    fn from(value: NoteSourceReference) -> Self {
        Self {
            collection_id: value.collection_id,
            collection_label: value.collection_label,
            document_id: value.document_id,
            indexed_revision: value.indexed_revision,
            title: value.title,
            section: value.section,
        }
    }
}

#[uniffi::export]
pub fn with_notes_collection_label(
    reference: NoteSourceReference,
    label: String,
) -> NoteSourceReference {
    ente_ensu::notes::NoteSourceReference::from(reference)
        .with_collection_label(label)
        .into()
}

#[derive(Debug, Clone, uniffi::Enum)]
pub enum GroundedSource {
    EnsuPack { citation: SourceCitation },
    LocalNote { reference: NoteSourceReference },
}

impl From<core::GroundedSource> for GroundedSource {
    fn from(value: core::GroundedSource) -> Self {
        match value {
            core::GroundedSource::EnsuPack { citation } => Self::EnsuPack {
                citation: citation.into(),
            },
            core::GroundedSource::LocalNote { reference } => Self::LocalNote {
                reference: reference.into(),
            },
        }
    }
}

impl From<GroundedSource> for core::GroundedSource {
    fn from(value: GroundedSource) -> Self {
        match value {
            GroundedSource::EnsuPack { citation } => Self::EnsuPack {
                citation: citation.into(),
            },
            GroundedSource::LocalNote { reference } => Self::LocalNote {
                reference: reference.into(),
            },
        }
    }
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct GroundedExcerpt {
    pub score: f32,
    pub source: GroundedSource,
    pub text: String,
}

impl From<core::GroundedExcerpt> for GroundedExcerpt {
    fn from(value: core::GroundedExcerpt) -> Self {
        Self {
            score: value.score,
            source: value.source.into(),
            text: value.text,
        }
    }
}

impl From<GroundedExcerpt> for core::GroundedExcerpt {
    fn from(value: GroundedExcerpt) -> Self {
        Self {
            score: value.score,
            source: value.source.into(),
            text: value.text,
        }
    }
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct GroundedPromptContext {
    pub text: String,
    pub sources: Vec<GroundedSource>,
}

impl From<core::GroundedPromptContext> for GroundedPromptContext {
    fn from(value: core::GroundedPromptContext) -> Self {
        Self {
            text: value.text,
            sources: value.sources.into_iter().map(Into::into).collect(),
        }
    }
}

#[uniffi::export]
pub fn select_mixed_grounding_candidates(
    pack_hits: Vec<KnowledgePromptHit>,
    notes_hits: Vec<crate::notes::NotesHit>,
    notes_limit: u32,
) -> Result<Vec<GroundedExcerpt>, KnowledgeRetrievalError> {
    let packs = pack_hits.into_iter().map(Into::into).collect::<Vec<_>>();
    let notes = notes_hits.into_iter().map(Into::into).collect::<Vec<_>>();
    core::select_mixed_grounding_candidates(&packs, &notes, notes_limit as usize)
        .map(|hits| hits.into_iter().map(Into::into).collect())
        .map_err(Into::into)
}

#[uniffi::export]
pub fn build_grounded_prompt_context(
    excerpts: Vec<GroundedExcerpt>,
    max_utf8_bytes: u32,
) -> Result<Option<GroundedPromptContext>, KnowledgeRetrievalError> {
    let excerpts = excerpts.into_iter().map(Into::into).collect::<Vec<_>>();
    core::build_grounded_prompt_context(&excerpts, max_utf8_bytes as usize)
        .map(|context| context.map(Into::into))
        .map_err(Into::into)
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct ParsedGroundedAssistantText {
    pub text: String,
    pub sources: Vec<GroundedSource>,
    pub source_labels: Vec<String>,
}

#[uniffi::export]
pub fn parse_grounded_assistant_text(stored_text: String) -> ParsedGroundedAssistantText {
    let parsed = core::parse_grounded_assistant_text(&stored_text);
    let source_labels = core::grounded_source_chip_labels(&parsed.sources);
    ParsedGroundedAssistantText {
        text: parsed.text,
        sources: parsed.sources.into_iter().map(Into::into).collect(),
        source_labels,
    }
}

#[uniffi::export]
pub fn finalize_grounded_assistant_text(
    raw_assistant_text: String,
    sources: Vec<GroundedSource>,
) -> Result<String, KnowledgeRetrievalError> {
    let sources = sources.into_iter().map(Into::into).collect::<Vec<_>>();
    core::finalize_grounded_assistant_text(&raw_assistant_text, &sources).map_err(Into::into)
}
