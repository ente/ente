use std::collections::{BTreeMap, BTreeSet};

use super::{NotesError, NotesSourceDocument, validate_document_id, validate_revision};

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct IndexedNotesDocument {
    pub document_id: String,
    pub revision: String,
    pub source_size: u64,
    pub source_modified_at_ms: Option<i64>,
}

impl IndexedNotesDocument {
    pub fn validate(&self) -> Result<(), NotesError> {
        validate_document_id(&self.document_id)?;
        validate_revision(&self.revision)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NotesReconciliationPlan {
    pub content_required_document_ids: Vec<String>,
    pub deleted_document_ids: Vec<String>,
}

impl NotesReconciliationPlan {
    pub fn is_up_to_date(&self) -> bool {
        self.content_required_document_ids.is_empty() && self.deleted_document_ids.is_empty()
    }
}

pub(super) fn plan_notes_reconciliation(
    inventory: &[NotesSourceDocument],
    indexed_documents: &[IndexedNotesDocument],
    forced_document_ids: &[String],
    force_full_hash: bool,
) -> Result<NotesReconciliationPlan, NotesError> {
    let mut inventory_by_id = BTreeMap::new();
    for source in inventory {
        source.validate()?;
        if inventory_by_id
            .insert(source.document_id.clone(), source)
            .is_some()
        {
            return Err(NotesError::InvalidInput(
                "source inventory contains a duplicate document ID".to_string(),
            ));
        }
    }

    let mut indexed_by_id = BTreeMap::new();
    for indexed in indexed_documents {
        indexed.validate()?;
        if indexed_by_id
            .insert(indexed.document_id.clone(), indexed)
            .is_some()
        {
            return Err(NotesError::InvalidInput(
                "indexed documents contain a duplicate document ID".to_string(),
            ));
        }
    }

    let forced = forced_document_ids
        .iter()
        .map(|document_id| {
            validate_document_id(document_id)?;
            Ok(document_id.clone())
        })
        .collect::<Result<BTreeSet<_>, NotesError>>()?;

    let mut content_required_document_ids = Vec::new();
    for (document_id, source) in &inventory_by_id {
        let Some(indexed) = indexed_by_id.get(document_id) else {
            content_required_document_ids.push(document_id.clone());
            continue;
        };
        let reliable_hints_match = source.size == indexed.source_size
            && matches!(
                (source.modified_at_ms, indexed.source_modified_at_ms),
                (Some(source_modified), Some(indexed_modified)) if source_modified == indexed_modified
            );
        if force_full_hash || forced.contains(document_id) || !reliable_hints_match {
            content_required_document_ids.push(document_id.clone());
        }
    }

    let deleted_document_ids = indexed_by_id
        .keys()
        .filter(|document_id| !inventory_by_id.contains_key(*document_id))
        .cloned()
        .collect();
    Ok(NotesReconciliationPlan {
        content_required_document_ids,
        deleted_document_ids,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn source(id: &str, size: u64, modified: Option<i64>) -> NotesSourceDocument {
        NotesSourceDocument {
            document_id: id.to_string(),
            size,
            modified_at_ms: modified,
        }
    }

    fn indexed(id: &str, size: u64, modified: Option<i64>) -> IndexedNotesDocument {
        IndexedNotesDocument {
            document_id: id.to_string(),
            revision: "a".repeat(64),
            source_size: size,
            source_modified_at_ms: modified,
        }
    }

    #[test]
    fn plans_new_changed_deleted_and_unchanged_documents() {
        let inventory = vec![
            source("changed.md", 20, Some(2)),
            source("new.md", 40, Some(4)),
            source("same.md", 10, Some(1)),
        ];
        let indexed = vec![
            indexed("changed.md", 19, Some(1)),
            indexed("deleted.md", 5, Some(1)),
            indexed("same.md", 10, Some(1)),
        ];
        let plan = plan_notes_reconciliation(&inventory, &indexed, &[], false).unwrap();
        assert_eq!(plan.content_required_document_ids, ["changed.md", "new.md"]);
        assert_eq!(plan.deleted_document_ids, ["deleted.md"]);
        assert!(!plan.is_up_to_date());
    }
}
