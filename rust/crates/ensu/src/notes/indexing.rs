use std::collections::BTreeMap;
use std::path::Path;

use super::{NotesError, NotesIndexWriter, NotesSourceDocument, PreparedNotesDocument};

const MIN_CHECKPOINT_DOCUMENTS: usize = 8;
const MIN_CHECKPOINT_CHUNKS: usize = 32;
const TARGET_CHECKPOINT_COUNT: usize = 50;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum NotesDocumentLoad {
    Prepared {
        document: PreparedNotesDocument,
        source: NotesSourceDocument,
    },
    Unindexable {
        source: NotesSourceDocument,
    },
    Changed,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum NotesRevisionStatus {
    Matches { source: NotesSourceDocument },
    Changed,
}

#[derive(Debug)]
pub enum NotesIndexingError<E> {
    Notes(NotesError),
    Adapter(E),
}

impl<E> From<NotesError> for NotesIndexingError<E> {
    fn from(error: NotesError) -> Self {
        Self::Notes(error)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NotesIndexInput<'a> {
    pub index_root: &'a Path,
    pub collection_id: String,
    pub inventory: Vec<NotesSourceDocument>,
    pub forced_document_ids: &'a [String],
    pub force_full_hash: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NotesIndexProgress {
    pub percentage: u8,
    pub processed_document_count: u64,
    pub indexed_document_count: u64,
    pub total_document_count: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NotesIndexOutcome {
    pub changed_during_indexing: Option<String>,
    pub unchecked_document_ids: Vec<String>,
    pub indexed_document_count: u64,
}

impl NotesIndexOutcome {
    pub fn ready(&self) -> bool {
        self.changed_during_indexing.is_none() && self.indexed_document_count > 0
    }
}

pub fn index_notes_collection<E>(
    input: NotesIndexInput<'_>,
    mut check_for_cancellation: impl FnMut() -> Result<(), E>,
    mut load_document: impl FnMut(&str) -> Result<NotesDocumentLoad, E>,
    mut embed_document: impl FnMut(&PreparedNotesDocument) -> Result<Option<Vec<Vec<f32>>>, E>,
    mut verify_revision: impl FnMut(&str, &str) -> Result<NotesRevisionStatus, E>,
    mut on_progress: impl FnMut(NotesIndexProgress),
) -> Result<NotesIndexOutcome, NotesIndexingError<E>> {
    let NotesIndexInput {
        index_root,
        collection_id,
        inventory,
        forced_document_ids,
        force_full_hash,
    } = input;
    check_for_cancellation().map_err(NotesIndexingError::Adapter)?;
    NotesIndexWriter::validate_inventory_capacity(&collection_id, &inventory)?;
    let mut writer = NotesIndexWriter::open(index_root, collection_id)?;
    let index_was_ready = writer.initial_inventory_complete();
    let plan = writer.plan_reconciliation(&inventory, forced_document_ids, force_full_hash)?;
    writer.commit_deletions(&plan.deleted_document_ids)?;

    let source_document_count = inventory.len() as u64;
    let requested = plan.content_required_document_ids;
    let mut checkpointed_document_count =
        source_document_count.saturating_sub(requested.len() as u64);
    report_indexing_progress(
        &writer,
        checkpointed_document_count,
        source_document_count,
        &mut on_progress,
    );
    let mut source_bytes = inventory.iter().map(|source| source.size).sum::<u64>();
    let source_sizes = inventory
        .into_iter()
        .map(|source| (source.document_id, source.size))
        .collect::<BTreeMap<_, _>>();

    let mut documents_since_checkpoint = 0_usize;
    let mut chunks_since_checkpoint = 0_usize;
    let document_checkpoint = checkpoint_interval(requested.len(), MIN_CHECKPOINT_DOCUMENTS);
    let mut processed_chunks = 0_usize;
    let mut first_checkpoint = true;
    for (processed_requested, document_id) in requested.iter().enumerate() {
        check_for_cancellation().map_err(NotesIndexingError::Adapter)?;
        let (prepared, source_metadata) =
            match load_document(document_id).map_err(NotesIndexingError::Adapter)? {
                NotesDocumentLoad::Prepared { document, source } => (Some(document), source),
                NotesDocumentLoad::Unindexable { source } => (None, source),
                NotesDocumentLoad::Changed => {
                    return changed_during_indexing_outcome(
                        &mut writer,
                        index_was_ready,
                        document_id,
                        &requested,
                        processed_requested,
                    );
                }
            };
        if source_metadata.document_id != *document_id {
            return Err(NotesError::InvalidInput(
                "loaded source metadata does not match its document ID".to_string(),
            )
            .into());
        }
        source_metadata.validate()?;
        source_bytes = source_bytes - source_sizes[document_id] + source_metadata.size;
        if source_bytes > super::NOTES_MAX_COLLECTION_SOURCE_BYTES {
            return Err(NotesError::CollectionTooLarge(
                "The folder contains too much note content to index".to_string(),
            )
            .into());
        }
        let Some(prepared) = prepared else {
            writer.commit_deletions(std::slice::from_ref(document_id))?;
            continue;
        };
        let validated = match writer.validate_document(&prepared, &source_metadata) {
            Ok(validated) => validated,
            Err(NotesError::InvalidInput(_)) => {
                writer.commit_deletions(std::slice::from_ref(document_id))?;
                continue;
            }
            Err(error) => return Err(error.into()),
        };
        let embeddings = if validated.needs_embedding() {
            let Some(embeddings) =
                embed_document(&prepared).map_err(NotesIndexingError::Adapter)?
            else {
                writer.commit_deletions(std::slice::from_ref(document_id))?;
                continue;
            };
            Some(embeddings)
        } else {
            None
        };
        check_for_cancellation().map_err(NotesIndexingError::Adapter)?;
        let revision = verify_revision(document_id, &prepared.revision)
            .map_err(NotesIndexingError::Adapter)?;
        if !matches!(revision, NotesRevisionStatus::Matches { source } if source == source_metadata)
        {
            return changed_during_indexing_outcome(
                &mut writer,
                index_was_ready,
                document_id,
                &requested,
                processed_requested,
            );
        }
        writer.commit_validated_document(validated, embeddings.as_deref())?;
        documents_since_checkpoint += 1;
        chunks_since_checkpoint += prepared.chunks.len();
        processed_chunks += prepared.chunks.len();
        let chunk_checkpoint = checkpoint_interval(
            processed_chunks.saturating_mul(requested.len()) / (processed_requested + 1),
            MIN_CHECKPOINT_CHUNKS,
        );
        if processed_requested + 1 < requested.len()
            && (first_checkpoint
                || documents_since_checkpoint >= document_checkpoint
                || chunks_since_checkpoint >= chunk_checkpoint)
        {
            writer.publish(index_was_ready)?;
            checkpointed_document_count =
                checkpointed_document_count.saturating_add(documents_since_checkpoint as u64);
            report_indexing_progress(
                &writer,
                checkpointed_document_count,
                source_document_count,
                &mut on_progress,
            );
            first_checkpoint = false;
            documents_since_checkpoint = 0;
            chunks_since_checkpoint = 0;
        }
    }

    writer.publish(true)?;
    report_indexing_progress(
        &writer,
        source_document_count,
        source_document_count,
        &mut on_progress,
    );
    Ok(NotesIndexOutcome {
        changed_during_indexing: None,
        unchecked_document_ids: Vec::new(),
        indexed_document_count: writer.indexed_document_count() as u64,
    })
}

fn checkpoint_interval(total: usize, minimum: usize) -> usize {
    total.div_ceil(TARGET_CHECKPOINT_COUNT).max(minimum)
}

fn report_indexing_progress(
    writer: &NotesIndexWriter,
    processed_document_count: u64,
    total_document_count: u64,
    on_progress: &mut impl FnMut(NotesIndexProgress),
) {
    on_progress(NotesIndexProgress {
        percentage: indexing_progress(processed_document_count, total_document_count),
        processed_document_count,
        indexed_document_count: writer.indexed_document_count() as u64,
        total_document_count,
    });
}

fn indexing_progress(processed_document_count: u64, source_document_count: u64) -> u8 {
    if source_document_count == 0 {
        return 100;
    }
    (processed_document_count
        .min(source_document_count)
        .saturating_mul(100)
        / source_document_count) as u8
}

fn changed_during_indexing_outcome<E>(
    writer: &mut NotesIndexWriter,
    index_was_ready: bool,
    document_id: &str,
    requested: &[String],
    processed_requested: usize,
) -> Result<NotesIndexOutcome, NotesIndexingError<E>> {
    writer.publish(index_was_ready)?;
    Ok(NotesIndexOutcome {
        changed_during_indexing: Some(document_id.to_string()),
        unchecked_document_ids: requested
            .iter()
            .skip(processed_requested)
            .cloned()
            .collect(),
        indexed_document_count: writer.indexed_document_count() as u64,
    })
}

#[cfg(test)]
mod tests {
    use std::cell::{Cell, RefCell};

    use super::*;
    use crate::notes::{NotesCollectionIndex, prepare_notes_document};

    const COLLECTION_ID: &str = "123e4567-e89b-12d3-a456-426614174000";

    fn source() -> NotesSourceDocument {
        source_at(1)
    }

    fn source_at(modified_at_ms: i64) -> NotesSourceDocument {
        NotesSourceDocument {
            document_id: "note.md".to_string(),
            size: 4,
            modified_at_ms: Some(modified_at_ms),
        }
    }

    fn embedding(prepared: &PreparedNotesDocument) -> Vec<Vec<f32>> {
        prepared
            .chunks
            .iter()
            .map(|_| {
                let mut embedding = vec![0.0; 512];
                embedding[0] = 1.0;
                embedding
            })
            .collect()
    }

    #[test]
    fn coordinates_platform_callbacks_and_publishes_the_index() {
        let temp = tempfile::tempdir().unwrap();
        let prepared = prepare_notes_document("note.md", b"note").unwrap();
        let verified_source = source_at(2);
        let progress = RefCell::new(Vec::new());
        let outcome = index_notes_collection::<()>(
            NotesIndexInput {
                index_root: temp.path(),
                collection_id: COLLECTION_ID.to_string(),
                inventory: vec![source_at(1)],
                forced_document_ids: &[],
                force_full_hash: false,
            },
            || Ok(()),
            |_| {
                assert!(!progress.borrow().is_empty());
                Ok(NotesDocumentLoad::Prepared {
                    document: prepared.clone(),
                    source: verified_source.clone(),
                })
            },
            |document| Ok(Some(embedding(document))),
            |_, _| {
                Ok(NotesRevisionStatus::Matches {
                    source: verified_source.clone(),
                })
            },
            |value| progress.borrow_mut().push(value),
        )
        .unwrap();

        assert!(outcome.ready());
        let progress = progress.borrow();
        assert_eq!(
            progress.as_slice(),
            [
                NotesIndexProgress {
                    percentage: 0,
                    processed_document_count: 0,
                    indexed_document_count: 0,
                    total_document_count: 1,
                },
                NotesIndexProgress {
                    percentage: 100,
                    processed_document_count: 1,
                    indexed_document_count: 1,
                    total_document_count: 1,
                },
            ]
        );
        let index = NotesCollectionIndex::open(temp.path(), COLLECTION_ID.to_string()).unwrap();
        assert_eq!(index.document_count(), 1);
        let writer = NotesIndexWriter::open(temp.path(), COLLECTION_ID.to_string()).unwrap();
        assert!(
            writer
                .plan_reconciliation(&[verified_source], &[], false)
                .unwrap()
                .is_up_to_date()
        );
    }

    #[test]
    fn resumes_a_cancelled_checkpoint_without_reembedding_committed_documents() {
        let temp = tempfile::tempdir().unwrap();
        let source_for = |document_id: &str| NotesSourceDocument {
            document_id: document_id.to_string(),
            ..source()
        };
        let inventory = (0..2)
            .map(|index| source_for(&format!("note-{index:02}.md")))
            .collect::<Vec<_>>();
        let forced_document_ids = inventory
            .iter()
            .map(|source| source.document_id.clone())
            .collect::<Vec<_>>();
        let input = NotesIndexInput {
            index_root: temp.path(),
            collection_id: COLLECTION_ID.to_string(),
            inventory: inventory.clone(),
            forced_document_ids: &forced_document_ids,
            force_full_hash: false,
        };
        let load_document = |document_id: &str| {
            Ok(NotesDocumentLoad::Prepared {
                document: prepare_notes_document(document_id, b"note").unwrap(),
                source: source_for(document_id),
            })
        };
        let verify_revision = |document_id: &str, _: &str| {
            Ok(NotesRevisionStatus::Matches {
                source: source_for(document_id),
            })
        };
        let cancelled = Cell::new(false);
        let mut embedded = Vec::new();
        let result = index_notes_collection(
            input.clone(),
            || {
                if cancelled.get() {
                    Err("cancelled")
                } else {
                    Ok(())
                }
            },
            load_document,
            |document| {
                embedded.push(document.document_id.clone());
                Ok(Some(embedding(document)))
            },
            verify_revision,
            |progress| {
                if progress.processed_document_count > 0
                    && progress.processed_document_count < progress.total_document_count
                {
                    cancelled.set(true);
                }
            },
        );

        assert!(matches!(
            result,
            Err(NotesIndexingError::Adapter("cancelled"))
        ));
        assert_eq!(embedded.len(), 1);
        {
            let writer = NotesIndexWriter::open(temp.path(), COLLECTION_ID.to_string()).unwrap();
            assert!(!writer.initial_inventory_complete());
            assert_eq!(writer.indexed_document_ids().collect::<Vec<_>>(), embedded);
        }
        let outcome = index_notes_collection(
            input,
            || Ok(()),
            load_document,
            |document| {
                embedded.push(document.document_id.clone());
                Ok(Some(embedding(document)))
            },
            verify_revision,
            |_| {},
        )
        .unwrap();

        assert!(outcome.ready());
        let document_ids = inventory
            .iter()
            .map(|source| source.document_id.as_str())
            .collect::<Vec<_>>();
        assert_eq!(embedded, document_ids);
        let index = NotesCollectionIndex::open(temp.path(), COLLECTION_ID.to_string()).unwrap();
        assert_eq!(index.document_count(), inventory.len());
    }

    #[test]
    fn preserves_the_previous_publication_when_a_source_changes() {
        for phase in ["load", "revision", "metadata"] {
            let temp = tempfile::tempdir().unwrap();
            let previous = prepare_notes_document("note.md", b"previous note").unwrap();
            let mut writer =
                NotesIndexWriter::open(temp.path(), COLLECTION_ID.to_string()).unwrap();
            writer
                .commit_document(&previous, &embedding(&previous), &source())
                .unwrap();
            writer.publish(true).unwrap();

            let prepared = prepare_notes_document("note.md", b"updated note").unwrap();
            let updated_source = source_at(2);
            let embedded = Cell::new(false);
            let outcome = index_notes_collection::<()>(
                NotesIndexInput {
                    index_root: temp.path(),
                    collection_id: COLLECTION_ID.to_string(),
                    inventory: vec![updated_source.clone()],
                    forced_document_ids: &[],
                    force_full_hash: false,
                },
                || Ok(()),
                |_| {
                    Ok(if phase == "load" {
                        NotesDocumentLoad::Changed
                    } else {
                        NotesDocumentLoad::Prepared {
                            document: prepared.clone(),
                            source: updated_source.clone(),
                        }
                    })
                },
                |document| {
                    embedded.set(true);
                    Ok(Some(embedding(document)))
                },
                |_, _| {
                    Ok(if phase == "revision" {
                        NotesRevisionStatus::Changed
                    } else {
                        NotesRevisionStatus::Matches {
                            source: source_at(3),
                        }
                    })
                },
                |_| {},
            )
            .unwrap();

            assert_eq!(embedded.get(), phase != "load", "{phase}");
            assert_eq!(outcome.changed_during_indexing.as_deref(), Some("note.md"));
            assert_eq!(outcome.unchecked_document_ids, ["note.md"]);
            let index = NotesCollectionIndex::open(temp.path(), COLLECTION_ID.to_string()).unwrap();
            let hits = index.search(&embedding(&previous)[0]).unwrap();
            assert_eq!(hits.len(), 1);
            assert_eq!(hits[0].text, "previous note");
        }
    }

    #[test]
    fn stops_before_embedding_when_updated_inventory_exceeds_capacity() {
        let temp = tempfile::tempdir().unwrap();
        let inventory = (0..65)
            .map(|i| NotesSourceDocument {
                document_id: format!("note-{i:02}.md"),
                size: match i {
                    0 => 4,
                    1 => super::super::NOTES_MAX_SOURCE_BYTES as u64 - 4,
                    _ => super::super::NOTES_MAX_SOURCE_BYTES as u64,
                },
                modified_at_ms: Some(1),
            })
            .collect::<Vec<_>>();
        let embedded = Cell::new(0);
        let result = index_notes_collection::<()>(
            NotesIndexInput {
                index_root: temp.path(),
                collection_id: COLLECTION_ID.to_string(),
                inventory: inventory.clone(),
                forced_document_ids: &[],
                force_full_hash: false,
            },
            || Ok(()),
            |id| {
                let mut source = inventory
                    .iter()
                    .find(|source| source.document_id == id)
                    .unwrap()
                    .clone();
                if id == "note-01.md" {
                    source.size += 1;
                }
                let bytes = vec![b'x'; source.size as usize];
                Ok(NotesDocumentLoad::Prepared {
                    document: prepare_notes_document(id, &bytes).unwrap(),
                    source,
                })
            },
            |document| {
                embedded.set(embedded.get() + 1);
                Ok(Some(embedding(document)))
            },
            |id, _| {
                Ok(NotesRevisionStatus::Matches {
                    source: inventory
                        .iter()
                        .find(|source| source.document_id == id)
                        .unwrap()
                        .clone(),
                })
            },
            |_| {},
        );
        assert!(matches!(
            result,
            Err(NotesIndexingError::Notes(NotesError::CollectionTooLarge(_)))
        ));
        assert_eq!(embedded.get(), 1);
        let writer = NotesIndexWriter::open(temp.path(), COLLECTION_ID.to_string()).unwrap();
        assert_eq!(writer.indexed_document_count(), 1);
        assert!(!writer.initial_inventory_complete());
    }
}
