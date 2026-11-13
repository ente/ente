use serde::{Deserialize, Serialize};

use super::{
    NotesError, is_valid_label, validate_collection_id, validate_document_id, validate_revision,
};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct NoteSourceReference {
    pub collection_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub collection_label: Option<String>,
    pub document_id: String,
    pub indexed_revision: String,
    pub title: String,
    pub section: Option<String>,
}

impl NoteSourceReference {
    pub fn with_collection_label(mut self, label: String) -> Self {
        self.collection_label = is_valid_label(&label).then_some(label);
        self
    }

    pub fn validate(&self) -> Result<(), NotesError> {
        validate_collection_id(&self.collection_id)?;
        if let Some(label) = &self.collection_label {
            validate_source_label(label, "note collection label")?;
        }
        validate_document_id(&self.document_id)?;
        validate_revision(&self.indexed_revision)?;
        validate_source_label(&self.title, "note title")?;
        if let Some(section) = &self.section {
            validate_source_label(section, "note section")?;
        }
        Ok(())
    }
}

fn validate_source_label(value: &str, label: &str) -> Result<(), NotesError> {
    if !is_valid_label(value) {
        return Err(NotesError::InvalidInput(format!(
            "{label} length or characters are invalid"
        )));
    }
    Ok(())
}
