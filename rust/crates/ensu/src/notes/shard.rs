use std::fs;
use std::path::Path;

use serde::{Deserialize, Serialize};

use super::manifest::notes_index_contract;
use super::{
    NOTES_CHUNK_UTF8_BYTES, NotesError, PreparedNotesDocument, contains_unsupported_control,
    invalid_index_input, is_valid_label, sha256_hex, validate_collection_id, validate_document_id,
    validate_revision,
};

pub(super) const NOTES_SHARD_FILE: &str = "shard.json";
pub(super) const NOTES_VECTORS_FILE: &str = "vectors.i8";
const MAX_SHARD_JSON_BYTES: u64 = 8 * 1024 * 1024;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(super) struct NotesShard {
    pub collection_id: String,
    pub document_id: String,
    pub revision: String,
    pub title: String,
    pub chunks: Vec<NotesShardChunk>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(super) struct NotesShardChunk {
    pub section: Option<String>,
    pub text: String,
}

#[derive(Clone, Copy)]
pub(super) struct NotesShardIntegrity<'a> {
    pub shard_sha256: &'a str,
    pub vectors_sha256: &'a str,
}

impl NotesShard {
    pub(super) fn from_prepared(collection_id: &str, prepared: &PreparedNotesDocument) -> Self {
        Self {
            collection_id: collection_id.to_string(),
            document_id: prepared.document_id.clone(),
            revision: prepared.revision.clone(),
            title: prepared.title.clone(),
            chunks: prepared
                .chunks
                .iter()
                .map(|chunk| NotesShardChunk {
                    section: chunk.section.clone(),
                    text: chunk.text.clone(),
                })
                .collect(),
        }
    }
}

pub(super) fn serialize_shard(shard: &NotesShard) -> Result<Vec<u8>, NotesError> {
    let bytes = serde_json::to_vec(shard)?;
    if bytes.is_empty() || bytes.len() as u64 > MAX_SHARD_JSON_BYTES {
        return Err(NotesError::InvalidInput(
            "serialized shard metadata exceeds the supported size".to_string(),
        ));
    }
    Ok(bytes)
}

pub(super) fn load_and_validate_shard(
    directory: &Path,
    collection_id: &str,
    expected_document_id: &str,
    expected_revision: &str,
    expected_chunk_count: usize,
    expected_integrity: NotesShardIntegrity<'_>,
    expected_prepared: Option<&PreparedNotesDocument>,
) -> Result<(), NotesError> {
    let shard = load_and_validate_shard_metadata(
        directory,
        collection_id,
        expected_document_id,
        expected_revision,
        expected_chunk_count,
        expected_integrity.shard_sha256,
        expected_prepared,
    )?;
    load_and_validate_vectors(
        directory,
        shard.chunks.len(),
        expected_integrity.vectors_sha256,
    )?;
    Ok(())
}

pub(super) fn load_and_validate_shard_metadata(
    directory: &Path,
    collection_id: &str,
    expected_document_id: &str,
    expected_revision: &str,
    expected_chunk_count: usize,
    expected_shard_sha256: &str,
    expected_prepared: Option<&PreparedNotesDocument>,
) -> Result<NotesShard, NotesError> {
    validate_revision(expected_shard_sha256).map_err(invalid_index_input)?;
    validate_shard_directory(directory)?;

    let shard_path = directory.join(NOTES_SHARD_FILE);
    let shard_metadata = regular_file_metadata(&shard_path, "shard metadata")?;
    if shard_metadata.len() == 0 || shard_metadata.len() > MAX_SHARD_JSON_BYTES {
        return Err(NotesError::InvalidIndex(
            "shard metadata size is outside the supported range".to_string(),
        ));
    }
    let shard_bytes = fs::read(shard_path)?;
    if shard_bytes.len() as u64 != shard_metadata.len()
        || sha256_hex(&shard_bytes) != expected_shard_sha256
    {
        return Err(NotesError::InvalidIndex(
            "shard metadata digest does not match its manifest".to_string(),
        ));
    }
    let shard: NotesShard = serde_json::from_slice(&shard_bytes)?;
    validate_shard(
        &shard,
        collection_id,
        expected_document_id,
        expected_revision,
        expected_chunk_count,
        expected_prepared,
    )?;
    Ok(shard)
}

pub(super) fn load_and_validate_vectors(
    directory: &Path,
    expected_chunk_count: usize,
    expected_vectors_sha256: &str,
) -> Result<Vec<u8>, NotesError> {
    validate_revision(expected_vectors_sha256).map_err(invalid_index_input)?;
    validate_shard_directory(directory)?;
    let vectors_path = directory.join(NOTES_VECTORS_FILE);
    let vector_metadata = regular_file_metadata(&vectors_path, "shard vectors")?;
    let vector_dimension = usize::try_from(notes_index_contract().retrieval_dimension)
        .map_err(|_| NotesError::InvalidIndex("vector dimension is too large".to_string()))?;
    let expected_vector_bytes = expected_chunk_count
        .checked_mul(vector_dimension)
        .ok_or_else(|| NotesError::InvalidIndex("shard vector byte length overflow".to_string()))?;
    let vectors = fs::read(vectors_path)?;
    if vector_metadata.len() != expected_vector_bytes as u64
        || vectors.len() != expected_vector_bytes
    {
        return Err(NotesError::InvalidIndex(
            "shard vector byte length does not match its metadata".to_string(),
        ));
    }
    if sha256_hex(&vectors) != expected_vectors_sha256 {
        return Err(NotesError::InvalidIndex(
            "shard vector digest does not match its manifest".to_string(),
        ));
    }
    Ok(vectors)
}

fn validate_shard_directory(directory: &Path) -> Result<(), NotesError> {
    let directory_metadata = fs::symlink_metadata(directory)?;
    if !directory_metadata.file_type().is_dir() {
        return Err(NotesError::InvalidIndex(
            "shard path must be a directory".to_string(),
        ));
    }
    Ok(())
}

fn validate_shard(
    shard: &NotesShard,
    collection_id: &str,
    expected_document_id: &str,
    expected_revision: &str,
    expected_chunk_count: usize,
    expected_prepared: Option<&PreparedNotesDocument>,
) -> Result<(), NotesError> {
    validate_collection_id(collection_id).map_err(invalid_index_input)?;
    if shard.collection_id != collection_id
        || shard.document_id != expected_document_id
        || shard.revision != expected_revision
    {
        return Err(NotesError::InvalidIndex(
            "shard identity does not match its manifest".to_string(),
        ));
    }
    validate_document_id(&shard.document_id).map_err(invalid_index_input)?;
    validate_revision(&shard.revision).map_err(invalid_index_input)?;
    if !is_valid_label(&shard.title) {
        return Err(NotesError::InvalidIndex(
            "shard title length is outside the supported range".to_string(),
        ));
    }
    if shard.chunks.is_empty() || expected_chunk_count != shard.chunks.len() {
        return Err(NotesError::InvalidIndex(
            "shard chunk/vector shape is invalid".to_string(),
        ));
    }
    for chunk in &shard.chunks {
        if chunk.text.trim().is_empty()
            || chunk.text.len() > NOTES_CHUNK_UTF8_BYTES
            || contains_unsupported_control(&chunk.text)
        {
            return Err(NotesError::InvalidIndex(
                "shard chunk text length is outside the supported range".to_string(),
            ));
        }
        if chunk
            .section
            .as_ref()
            .is_some_and(|section| !is_valid_label(section))
        {
            return Err(NotesError::InvalidIndex(
                "shard section length is outside the supported range".to_string(),
            ));
        }
    }

    if let Some(prepared) = expected_prepared
        && (shard.document_id != prepared.document_id
            || shard.revision != prepared.revision
            || shard.title != prepared.title
            || shard.chunks.len() != prepared.chunks.len()
            || shard
                .chunks
                .iter()
                .zip(&prepared.chunks)
                .any(|(stored, prepared)| {
                    stored.section != prepared.section || stored.text != prepared.text
                }))
    {
        return Err(NotesError::InvalidIndex(
            "existing shard does not match the prepared document".to_string(),
        ));
    }
    Ok(())
}

fn regular_file_metadata(path: &Path, label: &str) -> Result<fs::Metadata, NotesError> {
    let metadata = fs::symlink_metadata(path)?;
    if !metadata.file_type().is_file() {
        return Err(NotesError::InvalidIndex(format!(
            "{label} must be a regular file"
        )));
    }
    Ok(metadata)
}
