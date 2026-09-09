use std::path::Path;

use super::{
    NotesError, NotesIndexWriter, NotesIndexingError, NotesSourceDocument, notes_content_revision,
    prepare_notes_document,
};

pub enum NotesDocumentContent {
    Bytes(Vec<u8>),
    Changed,
}

pub struct NotesFreshness {
    pub changed: bool,
    pub forced_document_ids: Vec<String>,
}

pub fn inspect_notes_freshness<E>(
    writer: &NotesIndexWriter,
    inventory: &[NotesSourceDocument],
    mut check_for_cancellation: impl FnMut() -> Result<(), E>,
    mut read_document: impl FnMut(&str) -> Result<NotesDocumentContent, E>,
) -> Result<NotesFreshness, NotesIndexingError<E>> {
    check_for_cancellation().map_err(NotesIndexingError::Adapter)?;
    let plan = writer.plan_reconciliation(inventory, &[], false)?;
    let mut changed = !plan.deleted_document_ids.is_empty() || !writer.initial_inventory_complete();
    let mut forced_document_ids = Vec::new();
    for document in inventory {
        check_for_cancellation().map_err(NotesIndexingError::Adapter)?;
        match read_document(&document.document_id).map_err(NotesIndexingError::Adapter)? {
            NotesDocumentContent::Bytes(bytes) => {
                let revision = notes_content_revision(&bytes);
                if let Some(saved) = writer.indexed_revision(&document.document_id) {
                    if revision != saved {
                        forced_document_ids.push(document.document_id.clone());
                        changed = true;
                    }
                } else if prepare_notes_document(&document.document_id, &bytes).is_ok() {
                    changed = true;
                }
            }
            NotesDocumentContent::Changed => {
                changed = true;
                forced_document_ids.push(document.document_id.clone());
            }
        }
    }
    Ok(NotesFreshness {
        changed,
        forced_document_ids,
    })
}

pub fn notes_index_needs_rebuild(
    index_root: &Path,
    collection_id: &str,
    rebuild: bool,
) -> Result<bool, NotesError> {
    if !rebuild {
        return Ok(false);
    }
    match NotesIndexWriter::open(index_root, collection_id.to_owned()) {
        Ok(writer) => Ok(writer.initial_inventory_complete()),
        Err(NotesError::InvalidIndex(_) | NotesError::IncompatibleIndex | NotesError::Json(_)) => {
            Ok(true)
        }
        Err(error) => Err(error),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const ID: &str = "123e4567-e89b-12d3-a456-426614174000";

    fn source(text: &[u8], modified_at_ms: Option<i64>) -> NotesSourceDocument {
        NotesSourceDocument {
            document_id: "note.md".into(),
            size: text.len() as u64,
            modified_at_ms,
        }
    }

    fn fixture(root: &Path, text: Option<&[u8]>, complete: bool) -> NotesIndexWriter {
        let mut writer = NotesIndexWriter::open(root, ID.into()).unwrap();
        if let Some(text) = text {
            let prepared = prepare_notes_document("note.md", text).unwrap();
            let mut vector = vec![0.0; 512];
            vector[0] = 1.0;
            writer
                .commit_document(
                    &prepared,
                    &vec![vector; prepared.chunks.len()],
                    &source(text, Some(1)),
                )
                .unwrap();
        }
        writer.publish(complete).unwrap();
        writer
    }

    #[test]
    fn freshness_uses_revisions_for_missing_or_unchanged_metadata() {
        let root = tempfile::tempdir().unwrap();
        let writer = fixture(root.path(), Some(b"first"), true);
        let inspect = |text: &[u8], mtime| {
            inspect_notes_freshness(
                &writer,
                &[source(text, mtime)],
                || Ok::<_, ()>(()),
                |_| Ok(NotesDocumentContent::Bytes(text.into())),
            )
            .unwrap()
        };
        assert!(!inspect(b"first", None).changed);
        assert!(!inspect(b"first", Some(2)).changed);
        let changed = inspect(b"other", Some(1));
        assert!(changed.changed);
        assert_eq!(changed.forced_document_ids, ["note.md"]);
    }

    #[test]
    fn unchanged_unindexable_source_does_not_schedule_another_index() {
        let root = tempfile::tempdir().unwrap();
        let writer = fixture(root.path(), None, true);
        let result = inspect_notes_freshness(
            &writer,
            &[source(b" \n", None)],
            || Ok::<_, ()>(()),
            |_| Ok(NotesDocumentContent::Bytes(b" \n".to_vec())),
        )
        .unwrap();
        assert!(!result.changed);
    }

    #[test]
    fn freshness_detects_changes_during_content_reads() {
        let root = tempfile::tempdir().unwrap();
        let writer = fixture(root.path(), Some(b"note"), true);
        let inventory = [source(b"note", None)];
        let changed = inspect_notes_freshness(
            &writer,
            &inventory,
            || Ok::<_, &str>(()),
            |_| Ok(NotesDocumentContent::Changed),
        )
        .unwrap();
        assert!(changed.changed);
        assert_eq!(changed.forced_document_ids, ["note.md"]);
    }

    #[test]
    fn rebuild_preserves_partial_checkpoints() {
        let root = tempfile::tempdir().unwrap();
        fixture(root.path(), Some(b"note"), true);
        assert!(notes_index_needs_rebuild(root.path(), ID, true).unwrap());
        fixture(root.path(), Some(b"note"), false);
        assert!(!notes_index_needs_rebuild(root.path(), ID, true).unwrap());
        assert_eq!(
            NotesIndexWriter::open(root.path(), ID.into())
                .unwrap()
                .indexed_document_count(),
            1
        );
    }
}
