mod chunk;
mod document;
mod index;
mod indexing;
mod maintenance;
mod manifest;
mod reconcile;
mod shard;
mod source;
mod writer;

use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock, PoisonError};

use thiserror::Error;
use uuid::Uuid;

const NOTES_INDEX_CONTRACT_VERSION: u32 = 2;
pub const NOTES_MAX_SOURCE_BYTES: usize = 2 * 1024 * 1024;
pub const NOTES_MAX_COLLECTION_SOURCE_BYTES: u64 = 128 * 1024 * 1024;
pub const NOTES_MAX_COLLECTION_DOCUMENTS: usize = 20_000;
const NOTES_MAX_COLLECTION_CHUNKS: u64 = 131_072;
const NOTES_CHUNK_UTF8_BYTES: usize = 1_400;
const NOTES_CHUNK_OVERLAP_UTF8_BYTES: usize = 200;
const NOTES_HEADING_MAX_UTF8_BYTES: usize = 512;

#[derive(Debug, Error)]
pub enum NotesError {
    #[error("invalid Notes input: {0}")]
    InvalidInput(String),
    #[error("invalid Notes index: {0}")]
    InvalidIndex(String),
    #[error("incompatible Notes index contract")]
    IncompatibleIndex,
    #[error("Notes collection is not ready")]
    NotReady,
    #[error("Notes collection is too large: {0}")]
    CollectionTooLarge(String),
    #[error("Notes index I/O failed: {0}")]
    Io(#[from] std::io::Error),
    #[error("Notes index JSON failed: {0}")]
    Json(#[from] serde_json::Error),
}

pub use document::{
    NotesSourceDocument, PreparedNotesChunk, PreparedNotesDocument, prepare_notes_document,
};
pub use index::{NotesCollectionIndex, NotesCollectionIndexSummary, NotesSearchHit};
pub use indexing::{
    NotesDocumentLoad, NotesIndexInput, NotesIndexOutcome, NotesIndexProgress, NotesIndexingError,
    NotesRevisionStatus, index_notes_collection,
};
pub use maintenance::{
    NotesDocumentContent, NotesFreshness, inspect_notes_freshness, notes_index_needs_rebuild,
};
pub use reconcile::NotesReconciliationPlan;
pub use source::NoteSourceReference;
pub use writer::{
    NotesIndexWriter, ValidatedNotesDocument, cleanup_unreferenced_notes_shards,
    remove_notes_collection,
};

pub fn notes_content_revision(bytes: &[u8]) -> String {
    sha256_hex(bytes)
}

type PinnedRevision = ([u8; 32], [u8; 32]);

fn pinned_revision_key(document_storage_id: &str, revision: &str) -> PinnedRevision {
    (
        ente_ensu_crypto::sha256(document_storage_id.as_bytes()),
        ente_ensu_crypto::sha256(revision.as_bytes()),
    )
}

#[derive(Default)]
struct CollectionReaders {
    opening: usize,
    revisions: HashMap<PinnedRevision, usize>,
}

static ACTIVE_COLLECTION_READERS: OnceLock<Mutex<HashMap<PathBuf, CollectionReaders>>> =
    OnceLock::new();

struct NotesCollectionReadPin {
    collection_directory: PathBuf,
    opening: bool,
    revisions: Vec<PinnedRevision>,
}

impl NotesCollectionReadPin {
    fn acquire(collection_directory: &Path) -> Result<Self, NotesError> {
        let collection_directory = fs::canonicalize(collection_directory)?;
        let mut readers = active_collection_readers()
            .lock()
            .unwrap_or_else(PoisonError::into_inner);
        let collection = readers.entry(collection_directory.clone()).or_default();
        collection.opening = collection.opening.checked_add(1).ok_or_else(|| {
            NotesError::InvalidIndex("active Notes reader count overflow".to_string())
        })?;
        Ok(Self {
            collection_directory,
            opening: true,
            revisions: Vec::new(),
        })
    }

    fn collection_directory(&self) -> &Path {
        &self.collection_directory
    }

    fn estimated_heap_bytes(&self) -> usize {
        let pinned_revision_bytes = std::mem::size_of::<PinnedRevision>();
        self.collection_directory
            .as_os_str()
            .len()
            .saturating_add(
                self.revisions
                    .capacity()
                    .saturating_mul(pinned_revision_bytes),
            )
            .saturating_add(
                self.revisions.len().saturating_mul(
                    pinned_revision_bytes
                        .saturating_add(std::mem::size_of::<usize>())
                        .saturating_add(1),
                ),
            )
    }

    fn pin_revisions(
        &mut self,
        revisions: impl IntoIterator<Item = PinnedRevision>,
    ) -> Result<(), NotesError> {
        let revisions = revisions.into_iter().collect::<HashSet<_>>();
        let mut readers = active_collection_readers()
            .lock()
            .unwrap_or_else(PoisonError::into_inner);
        let collection = readers.get_mut(&self.collection_directory).ok_or_else(|| {
            NotesError::InvalidIndex("active Notes reader registration is missing".to_string())
        })?;
        collection.opening = collection.opening.checked_sub(1).ok_or_else(|| {
            NotesError::InvalidIndex("active Notes reader registration is inconsistent".to_string())
        })?;
        self.opening = false;
        self.revisions.reserve(revisions.len());
        for revision in revisions {
            let reader_count = collection.revisions.entry(revision).or_default();
            *reader_count = reader_count.checked_add(1).ok_or_else(|| {
                NotesError::InvalidIndex("active Notes revision reader count overflow".to_string())
            })?;
            self.revisions.push(revision);
        }
        Ok(())
    }
}

impl Drop for NotesCollectionReadPin {
    fn drop(&mut self) {
        let mut readers = active_collection_readers()
            .lock()
            .unwrap_or_else(PoisonError::into_inner);
        let Some(collection) = readers.get_mut(&self.collection_directory) else {
            return;
        };
        if self.opening {
            collection.opening = collection.opening.saturating_sub(1);
        } else {
            for revision in &self.revisions {
                let remove = collection
                    .revisions
                    .get_mut(revision)
                    .is_some_and(|reader_count| {
                        *reader_count = reader_count.saturating_sub(1);
                        *reader_count == 0
                    });
                if remove {
                    collection.revisions.remove(revision);
                }
            }
        }
        if collection.opening == 0 && collection.revisions.is_empty() {
            readers.remove(&self.collection_directory);
        }
    }
}

fn active_collection_readers() -> &'static Mutex<HashMap<PathBuf, CollectionReaders>> {
    ACTIVE_COLLECTION_READERS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn collection_reader_snapshot(collection_directory: &Path) -> (bool, HashSet<PinnedRevision>) {
    let readers = active_collection_readers()
        .lock()
        .unwrap_or_else(PoisonError::into_inner);
    let Some(collection) = readers.get(collection_directory) else {
        return (false, HashSet::new());
    };
    (
        collection.opening > 0,
        collection.revisions.keys().cloned().collect(),
    )
}

fn sha256_hex(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut encoded = String::with_capacity(64);
    for byte in ente_ensu_crypto::sha256(bytes) {
        encoded.push(char::from(HEX[usize::from(byte >> 4)]));
        encoded.push(char::from(HEX[usize::from(byte & 0x0f)]));
    }
    encoded
}

pub fn validate_document_id(document_id: &str) -> Result<(), NotesError> {
    if document_id.is_empty() || document_id.len() > 4_096 {
        return Err(NotesError::InvalidInput(
            "document ID length is outside the supported range".to_string(),
        ));
    }
    if document_id.chars().any(char::is_control) {
        return Err(NotesError::InvalidInput(
            "document ID contains a control character".to_string(),
        ));
    }
    #[cfg(windows)]
    if document_id.contains('\\') {
        return Err(NotesError::InvalidInput(
            "document ID contains an invalid path separator".to_string(),
        ));
    }
    if looks_like_absolute_local_path(document_id) {
        return Err(NotesError::InvalidInput(
            "document ID must not be an absolute local path".to_string(),
        ));
    }
    if document_id
        .split('/')
        .any(|component| component.is_empty() || matches!(component, "." | ".."))
    {
        return Err(NotesError::InvalidInput(
            "document ID contains an invalid path component".to_string(),
        ));
    }
    Ok(())
}

fn validate_collection_id(collection_id: &str) -> Result<(), NotesError> {
    let parsed = Uuid::parse_str(collection_id)
        .map_err(|_| NotesError::InvalidInput("collection ID must be a UUID".to_string()))?;
    if parsed.hyphenated().to_string() != collection_id {
        return Err(NotesError::InvalidInput(
            "collection ID must use canonical lowercase UUID form".to_string(),
        ));
    }
    Ok(())
}

fn looks_like_absolute_local_path(value: &str) -> bool {
    value.starts_with('/')
        || value.starts_with('\\')
        || value
            .get(..5)
            .is_some_and(|prefix| prefix.eq_ignore_ascii_case("file:"))
        || (value.len() >= 3
            && value.as_bytes()[0].is_ascii_alphabetic()
            && value.as_bytes()[1] == b':'
            && matches!(value.as_bytes()[2], b'/' | b'\\'))
}

fn validate_revision(revision: &str) -> Result<(), NotesError> {
    if revision.len() != 64
        || !revision
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        return Err(NotesError::InvalidInput(
            "revision must be a lowercase SHA-256 digest".to_string(),
        ));
    }
    Ok(())
}

fn is_valid_label(value: &str) -> bool {
    !value.trim().is_empty() && value.len() <= 4_096 && !value.chars().any(char::is_control)
}

fn contains_unsupported_control(value: &str) -> bool {
    value
        .chars()
        .any(|character| character.is_control() && !matches!(character, '\n' | '\r' | '\t'))
}

fn invalid_index_input(error: NotesError) -> NotesError {
    NotesError::InvalidIndex(match error {
        NotesError::InvalidInput(detail) => detail,
        _ => "index field is invalid".to_string(),
    })
}
