use std::path::Path;

use ente_ensu::llm;
use ente_ensu::notes::{
    NotesCollectionIndex, NotesDocumentLoad, NotesError, NotesIndexInput, NotesIndexOutcome,
    NotesIndexProgress, NotesIndexingError, NotesRevisionStatus, index_notes_collection,
    notes_content_revision, prepare_notes_document, remove_notes_collection,
};

use crate::commands::common::ApiError;

use super::registry::RegisteredCollection;
use super::source::{
    canonical_source_root, inventory_source_root, read_collection_source, source_root_is_available,
};
use super::{UpdateSnapshot, check_cancelled, notes_error};

pub(super) fn index_collection(
    index_root: &Path,
    collection: &RegisteredCollection,
    embedding_path: Option<&Path>,
    cancellation_epoch: &std::sync::atomic::AtomicU64,
    retrieval_epoch: u64,
    update: &UpdateSnapshot,
    on_progress: impl FnMut(NotesIndexProgress),
) -> Result<NotesIndexOutcome, ApiError> {
    check_cancelled(cancellation_epoch, retrieval_epoch)?;
    let canonical_root = canonical_source_root(&collection.source_root)?;
    if canonical_root != collection.source_root {
        return Err(ApiError::new(
            "source_changed",
            "Notes source folder identity changed",
        ));
    }
    let inventory = inventory_source_root(&canonical_root, || {
        check_cancelled(cancellation_epoch, retrieval_epoch)
    })?;
    if update.rebuild_derived_index {
        remove_notes_collection(index_root, &collection.id).map_err(notes_error)?;
    }
    let mut embedding_context = None;
    index_notes_collection(
        NotesIndexInput {
            index_root,
            collection_id: collection.id.clone(),
            inventory,
            forced_document_ids: &update.forced_document_ids,
            force_full_hash: update.force_full_hash,
        },
        || check_cancelled(cancellation_epoch, retrieval_epoch),
        |document_id| load_notes_document(&canonical_root, document_id),
        |prepared| {
            let embedding_path = embedding_path.ok_or_else(|| {
                ApiError::new(
                    "embedding_missing",
                    "The knowledge embedding model is not downloaded",
                )
            })?;
            let context = match &mut embedding_context {
                Some(context) => context,
                slot => slot.insert(crate::commands::llm::load_knowledge_embedding_context(
                    embedding_path,
                    || check_cancelled(cancellation_epoch, retrieval_epoch),
                )?),
            };
            prepared
                .embed(|title, text| {
                    check_cancelled(cancellation_epoch, retrieval_epoch)
                        .map_err(|_| llm::Error::Cancelled)?;
                    context.embed_document(title, text)
                })
                .map_err(crate::commands::llm::llm_api_error)
        },
        |document_id, revision| {
            verify_notes_document_revision(&canonical_root, document_id, revision)
        },
        on_progress,
    )
    .map_err(notes_indexing_error)
}

pub(super) fn should_rebuild_derived_index(
    index_root: &Path,
    collection_id: &str,
    force: bool,
    has_available_index: bool,
) -> Result<bool, ApiError> {
    if !force {
        if has_available_index {
            return Ok(false);
        }
        return match NotesCollectionIndex::open(index_root, collection_id.to_string()) {
            Err(NotesError::IncompatibleIndex) => Ok(true),
            _ => Ok(false),
        };
    }
    match NotesCollectionIndex::open(index_root, collection_id.to_string()) {
        Ok(_) | Err(NotesError::NotReady) => Ok(false),
        Err(NotesError::InvalidIndex(_) | NotesError::IncompatibleIndex | NotesError::Json(_)) => {
            Ok(true)
        }
        Err(NotesError::Io(error)) if error.kind() == std::io::ErrorKind::NotFound => Ok(true),
        Err(error) => Err(notes_error(error)),
    }
}

fn load_notes_document(root: &Path, document_id: &str) -> Result<NotesDocumentLoad, ApiError> {
    match read_collection_source(root, document_id) {
        Ok((_, bytes, source)) => Ok(match prepare_notes_document(document_id, &bytes) {
            Ok(document) => NotesDocumentLoad::Prepared { document, source },
            Err(_) => NotesDocumentLoad::Unindexable { source },
        }),
        Err(error) if error.name == Some("invalid_document") => Ok(NotesDocumentLoad::Changed),
        Err(error) if error.name == Some("source_changed") && source_root_is_available(root) => {
            Ok(NotesDocumentLoad::Changed)
        }
        Err(error) => Err(error),
    }
}

fn verify_notes_document_revision(
    root: &Path,
    document_id: &str,
    expected_revision: &str,
) -> Result<NotesRevisionStatus, ApiError> {
    match read_collection_source(root, document_id) {
        Ok((_, bytes, source)) if notes_content_revision(&bytes) == expected_revision => {
            Ok(NotesRevisionStatus::Matches { source })
        }
        Ok(_) => Ok(NotesRevisionStatus::Changed),
        Err(error) if error.name == Some("source_changed") && source_root_is_available(root) => {
            Ok(NotesRevisionStatus::Changed)
        }
        Err(error) => Err(error),
    }
}

fn notes_indexing_error(error: NotesIndexingError<ApiError>) -> ApiError {
    match error {
        NotesIndexingError::Notes(error) => notes_error(error),
        NotesIndexingError::Adapter(error) => error,
    }
}
