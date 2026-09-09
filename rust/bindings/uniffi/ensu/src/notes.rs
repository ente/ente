use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};

use ente_ensu::{llm, notes as core};
use thiserror::Error;

use crate::llm::LlmContext;

#[derive(Debug, Error, uniffi::Error)]
pub enum NotesError {
    #[error("Notes operation cancelled")]
    Cancelled,
    #[error("The note changed during reading")]
    SourceChanged,
    #[error("The Notes folder is unavailable")]
    Unavailable,
    #[error("Notes collection is not ready")]
    NotReady,
    #[error("The Notes index needs rebuilding")]
    RebuildRequired,
    #[error("{detail}")]
    SourceRead { detail: String },
    #[error("{detail}")]
    InvalidInput { detail: String },
    #[error("{detail}")]
    Storage { detail: String },
    #[error("{detail}")]
    Other { detail: String },
}

impl From<core::NotesError> for NotesError {
    fn from(error: core::NotesError) -> Self {
        match error {
            core::NotesError::NotReady => Self::NotReady,
            core::NotesError::InvalidIndex(_)
            | core::NotesError::IncompatibleIndex
            | core::NotesError::Json(_) => Self::RebuildRequired,
            core::NotesError::InvalidInput(detail)
            | core::NotesError::CollectionTooLarge(detail) => Self::InvalidInput { detail },
            core::NotesError::Io(error) => Self::Storage {
                detail: error.to_string(),
            },
        }
    }
}

impl From<core::NotesIndexingError<Self>> for NotesError {
    fn from(error: core::NotesIndexingError<Self>) -> Self {
        match error {
            core::NotesIndexingError::Notes(error) => error.into(),
            core::NotesIndexingError::Adapter(error) => error,
        }
    }
}

#[derive(Default, uniffi::Object)]
pub struct NotesCancellation {
    cancelled: AtomicBool,
}

#[uniffi::export]
impl NotesCancellation {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self::default())
    }

    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::SeqCst);
    }

    pub fn check(&self) -> Result<(), NotesError> {
        if self.cancelled.load(Ordering::SeqCst) {
            Err(NotesError::Cancelled)
        } else {
            Ok(())
        }
    }
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct NotesDocument {
    pub document_id: String,
    pub size: u64,
    pub modified_at_ms: Option<i64>,
}

impl From<NotesDocument> for core::NotesSourceDocument {
    fn from(value: NotesDocument) -> Self {
        Self {
            document_id: value.document_id,
            size: value.size,
            modified_at_ms: value.modified_at_ms,
        }
    }
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct NotesRead {
    pub bytes: Vec<u8>,
    pub source: NotesDocument,
}

#[uniffi::export(callback_interface)]
pub trait NotesSource: Send + Sync {
    fn list_documents(&self) -> Result<Vec<NotesDocument>, NotesError>;
    fn read_document(&self, document_id: String) -> Result<NotesRead, NotesError>;
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct NotesProgress {
    pub percentage: u8,
    pub indexed_document_count: u64,
}

#[uniffi::export(callback_interface)]
pub trait NotesProgressCallback: Send + Sync {
    fn on_progress(&self, progress: NotesProgress);
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct NotesSummary {
    pub initial_complete: bool,
    pub document_count: u64,
    pub last_updated_at_ms: Option<i64>,
}

impl From<&core::NotesIndexWriter> for NotesSummary {
    fn from(writer: &core::NotesIndexWriter) -> Self {
        Self {
            initial_complete: writer.initial_inventory_complete(),
            document_count: writer.indexed_document_count() as u64,
            last_updated_at_ms: writer.last_updated_at_ms(),
        }
    }
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct NotesFreshness {
    pub summary: NotesSummary,
    pub changed: bool,
    pub forced_document_ids: Vec<String>,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct NotesLimits {
    pub max_source_bytes: u64,
    pub max_collection_source_bytes: u64,
    pub max_collection_documents: u64,
    pub max_grounding_hits: u32,
}

#[uniffi::export]
pub fn notes_limits() -> NotesLimits {
    NotesLimits {
        max_source_bytes: core::NOTES_MAX_SOURCE_BYTES as u64,
        max_collection_source_bytes: core::NOTES_MAX_COLLECTION_SOURCE_BYTES,
        max_collection_documents: core::NOTES_MAX_COLLECTION_DOCUMENTS as u64,
        max_grounding_hits: ente_ensu::retrieval::MAX_NOTES_GROUNDING_HITS as u32,
    }
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct NotesIndexOptions {
    pub forced_document_ids: Vec<String>,
    pub rebuild: bool,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct NotesOutcome {
    pub summary: NotesSummary,
    pub changed_document_id: Option<String>,
    pub unchecked_document_ids: Vec<String>,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct NotesHit {
    pub collection_id: String,
    pub document_id: String,
    pub revision: String,
    pub score: f32,
    pub title: String,
    pub section: Option<String>,
    pub text: String,
}

impl From<core::NotesSearchHit> for NotesHit {
    fn from(value: core::NotesSearchHit) -> Self {
        Self {
            collection_id: value.collection_id,
            document_id: value.document_id,
            revision: value.revision,
            score: value.score,
            title: value.title,
            section: value.section,
            text: value.text,
        }
    }
}

impl From<NotesHit> for core::NotesSearchHit {
    fn from(value: NotesHit) -> Self {
        Self {
            collection_id: value.collection_id,
            document_id: value.document_id,
            revision: value.revision,
            score: value.score,
            title: value.title,
            section: value.section,
            text: value.text,
        }
    }
}

#[derive(uniffi::Object)]
pub struct NotesCollection {
    root: PathBuf,
    id: String,
}

#[uniffi::export]
impl NotesCollection {
    #[uniffi::constructor]
    pub fn new(index_root: String, collection_id: String) -> Result<Arc<Self>, NotesError> {
        let id = uuid::Uuid::parse_str(&collection_id).map_err(|_| NotesError::InvalidInput {
            detail: "Invalid Notes collection ID".into(),
        })?;
        if id.hyphenated().to_string() != collection_id || !Path::new(&index_root).is_absolute() {
            return Err(NotesError::InvalidInput {
                detail: "Invalid Notes index location".into(),
            });
        }
        Ok(Arc::new(Self {
            root: index_root.into(),
            id: collection_id,
        }))
    }

    pub fn inspect(&self) -> Result<NotesSummary, NotesError> {
        let writer = core::NotesIndexWriter::open(&self.root, self.id.clone())?;
        Ok((&writer).into())
    }

    pub fn inspect_freshness(
        &self,
        source: Box<dyn NotesSource>,
        cancellation: Arc<NotesCancellation>,
    ) -> Result<NotesFreshness, NotesError> {
        cancellation.check()?;
        let inventory = inventory(source.as_ref(), &cancellation, &self.id)?;
        let writer = core::NotesIndexWriter::open(&self.root, self.id.clone())?;
        let freshness = core::inspect_notes_freshness(
            &writer,
            &inventory,
            || cancellation.check(),
            |id| match read(source.as_ref(), id, &cancellation) {
                Ok(value) => Ok(core::NotesDocumentContent::Bytes(value.bytes)),
                Err(NotesError::SourceChanged) => Ok(core::NotesDocumentContent::Changed),
                Err(error) => Err(error),
            },
        )?;
        Ok(NotesFreshness {
            summary: (&writer).into(),
            changed: freshness.changed,
            forced_document_ids: freshness.forced_document_ids,
        })
    }

    pub fn index(
        &self,
        source: Box<dyn NotesSource>,
        context: Arc<LlmContext>,
        cancellation: Arc<NotesCancellation>,
        progress: Box<dyn NotesProgressCallback>,
        options: NotesIndexOptions,
    ) -> Result<NotesOutcome, NotesError> {
        let NotesIndexOptions {
            forced_document_ids,
            rebuild,
        } = options;
        cancellation.check()?;
        let inventory = inventory(source.as_ref(), &cancellation, &self.id)?;
        cancellation.check()?;
        let remove = core::notes_index_needs_rebuild(&self.root, &self.id, rebuild)?;
        cancellation.check()?;
        if remove {
            self.remove()?;
        }
        let outcome = core::index_notes_collection(
            core::NotesIndexInput {
                index_root: &self.root,
                collection_id: self.id.clone(),
                inventory,
                forced_document_ids: &forced_document_ids,
                force_full_hash: false,
            },
            || cancellation.check(),
            |id| match read(source.as_ref(), id, &cancellation) {
                Ok(value) => {
                    let source = value.source.into();
                    Ok(match core::prepare_notes_document(id, &value.bytes) {
                        Ok(document) => core::NotesDocumentLoad::Prepared { document, source },
                        Err(_) => core::NotesDocumentLoad::Unindexable { source },
                    })
                }
                Err(NotesError::SourceChanged) => Ok(core::NotesDocumentLoad::Changed),
                Err(error) => Err(error),
            },
            |prepared| {
                prepared
                    .embed(|title, text| {
                        cancellation.check().map_err(|_| llm::Error::Cancelled)?;
                        context.handle.embed_document(title, text)
                    })
                    .map_err(|error| match error {
                        llm::Error::Cancelled => NotesError::Cancelled,
                        error => NotesError::Other {
                            detail: error.to_string(),
                        },
                    })
            },
            |id, revision| match read(source.as_ref(), id, &cancellation) {
                Ok(value) if core::notes_content_revision(&value.bytes) == revision => {
                    Ok(core::NotesRevisionStatus::Matches {
                        source: value.source.into(),
                    })
                }
                Ok(_) | Err(NotesError::SourceChanged) => Ok(core::NotesRevisionStatus::Changed),
                Err(error) => Err(error),
            },
            |p| {
                progress.on_progress(NotesProgress {
                    percentage: p.percentage,
                    indexed_document_count: p.indexed_document_count,
                })
            },
        )?;
        Ok(NotesOutcome {
            summary: self.inspect()?,
            changed_document_id: outcome.changed_during_indexing,
            unchecked_document_ids: outcome.unchecked_document_ids,
        })
    }

    pub fn search(&self, query: Vec<f32>) -> Result<Vec<NotesHit>, NotesError> {
        let result = core::NotesCollectionIndex::open(&self.root, self.id.clone())
            .and_then(|index| index.search(&query));
        match result {
            Ok(hits) => Ok(hits.into_iter().map(Into::into).collect()),
            Err(core::NotesError::Io(error)) if error.kind() == std::io::ErrorKind::NotFound => {
                Err(NotesError::RebuildRequired)
            }
            Err(error) => Err(error.into()),
        }
    }

    pub fn remove(&self) -> Result<(), NotesError> {
        core::remove_notes_collection(&self.root, &self.id).map_err(Into::into)
    }
}

fn inventory(
    source: &dyn NotesSource,
    cancellation: &NotesCancellation,
    id: &str,
) -> Result<Vec<core::NotesSourceDocument>, NotesError> {
    let inventory: Vec<core::NotesSourceDocument> = source
        .list_documents()?
        .into_iter()
        .map(Into::into)
        .collect();
    cancellation.check()?;
    core::NotesIndexWriter::validate_inventory_capacity(id, &inventory)?;
    let ids: BTreeSet<_> = inventory.iter().map(|v| &v.document_id).collect();
    if ids.len() != inventory.len() {
        return Err(NotesError::InvalidInput {
            detail: "Ambiguous Notes document IDs".into(),
        });
    }
    Ok(inventory)
}

fn read(
    source: &dyn NotesSource,
    id: &str,
    cancellation: &NotesCancellation,
) -> Result<NotesRead, NotesError> {
    cancellation.check()?;
    core::validate_document_id(id)?;
    let value = source.read_document(id.into())?;
    cancellation.check()?;
    if value.source.document_id != id
        || value.source.size != value.bytes.len() as u64
        || value.bytes.len() > core::NOTES_MAX_SOURCE_BYTES
    {
        return Err(NotesError::SourceChanged);
    }
    Ok(value)
}

#[uniffi::export]
pub fn notes_content_revision(bytes: Vec<u8>) -> String {
    core::notes_content_revision(&bytes)
}

#[uniffi::export]
pub fn validate_notes_document_id(document_id: String) -> Result<(), NotesError> {
    core::validate_document_id(&document_id).map_err(Into::into)
}
