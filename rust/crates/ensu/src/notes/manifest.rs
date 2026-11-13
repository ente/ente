use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

use crate::config::knowledge_index_contract;

use super::{
    NOTES_INDEX_CONTRACT_VERSION, NOTES_MAX_COLLECTION_CHUNKS, NOTES_MAX_COLLECTION_SOURCE_BYTES,
    NOTES_MAX_SOURCE_BYTES, NotesError, invalid_index_input, sha256_hex, validate_collection_id,
    validate_document_id, validate_revision,
};

pub(super) const NOTES_MANIFEST_FILE: &str = "manifest.json";
pub(super) const NOTES_MANIFEST_BACKUP_FILE: &str = "manifest.json.backup";
pub(super) const NOTES_DOCUMENTS_DIRECTORY: &str = "documents";
const NOTES_MANIFEST_SCHEMA_VERSION: u32 = 2;
const MAX_MANIFEST_BYTES: u64 = 8 * 1024 * 1024;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(super) struct NotesIndexContract {
    pub(super) version: u32,
    pub(super) embedding_model: String,
    pub(super) source_dimension: u32,
    pub(super) matryoshka: bool,
    pub(super) document_prompt: String,
    pub(super) query_prompt: String,
    pub(super) retrieval_dimension: u32,
    pub(super) quantization: String,
    pub(super) quantization_scale: u32,
}

pub(super) fn notes_index_contract() -> NotesIndexContract {
    let embedding = knowledge_index_contract();
    NotesIndexContract {
        version: NOTES_INDEX_CONTRACT_VERSION,
        embedding_model: embedding.model,
        source_dimension: embedding.source_dim,
        matryoshka: embedding.matryoshka,
        document_prompt: embedding.doc_prompt,
        query_prompt: embedding.query_prompt,
        retrieval_dimension: embedding.dim,
        quantization: embedding.quant,
        quantization_scale: embedding.scale,
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct NotesManifest {
    pub(super) schema_version: u32,
    pub(super) collection_id: String,
    pub(super) initial_inventory_complete: bool,
    pub(super) index_contract: NotesIndexContract,
    pub(super) documents: BTreeMap<String, NotesManifestDocument>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(super) struct NotesManifestDocument {
    pub(super) revision: String,
    pub(super) source_size: u64,
    pub(super) source_modified_at_ms: Option<i64>,
    pub(super) chunk_count: u32,
    #[serde(default)]
    pub(super) shard_sha256: String,
    #[serde(default)]
    pub(super) vectors_sha256: String,
}

pub(super) fn empty_manifest(collection_id: &str) -> NotesManifest {
    NotesManifest {
        schema_version: NOTES_MANIFEST_SCHEMA_VERSION,
        collection_id: collection_id.to_string(),
        initial_inventory_complete: false,
        index_contract: notes_index_contract(),
        documents: BTreeMap::new(),
    }
}

pub(super) fn collection_directory(index_root: &Path, collection_id: &str) -> PathBuf {
    index_root.join(collection_id)
}

pub(super) fn shard_directory(
    collection_directory: &Path,
    document_id: &str,
    revision: &str,
) -> PathBuf {
    collection_directory
        .join(NOTES_DOCUMENTS_DIRECTORY)
        .join(document_storage_id(document_id))
        .join(revision)
}

pub(super) fn document_storage_id(document_id: &str) -> String {
    sha256_hex(document_id.as_bytes())
}

pub(super) fn validate_manifest(
    manifest: &NotesManifest,
    collection_id: &str,
    require_ready: bool,
) -> Result<(), NotesError> {
    validate_collection_id(collection_id)?;
    if manifest.schema_version != NOTES_MANIFEST_SCHEMA_VERSION {
        return Err(NotesError::IncompatibleIndex);
    }
    if manifest.collection_id != collection_id {
        return Err(NotesError::InvalidIndex(
            "manifest collection ID does not match its directory".to_string(),
        ));
    }
    if manifest.index_contract != notes_index_contract() {
        return Err(NotesError::IncompatibleIndex);
    }
    if require_ready && (!manifest.initial_inventory_complete || manifest.documents.is_empty()) {
        return Err(NotesError::NotReady);
    }

    let mut total_source_bytes = 0_u64;
    let mut total_chunks = 0_u64;
    for (document_id, document) in &manifest.documents {
        validate_manifest_document(document_id, document)?;
        total_source_bytes = total_source_bytes
            .checked_add(document.source_size)
            .ok_or_else(|| {
                NotesError::InvalidIndex("collection source byte count overflow".to_string())
            })?;
        total_chunks = total_chunks
            .checked_add(u64::from(document.chunk_count))
            .ok_or_else(|| {
                NotesError::InvalidIndex("collection chunk count overflow".to_string())
            })?;
    }
    if total_source_bytes > NOTES_MAX_COLLECTION_SOURCE_BYTES
        || total_chunks > NOTES_MAX_COLLECTION_CHUNKS
    {
        return Err(NotesError::InvalidIndex(
            "collection exceeds the supported aggregate index size".to_string(),
        ));
    }
    Ok(())
}

fn validate_manifest_document(
    document_id: &str,
    document: &NotesManifestDocument,
) -> Result<(), NotesError> {
    validate_document_id(document_id).map_err(invalid_index_input)?;
    validate_revision(&document.revision).map_err(invalid_index_input)?;
    validate_revision(&document.shard_sha256).map_err(invalid_index_input)?;
    validate_revision(&document.vectors_sha256).map_err(invalid_index_input)?;
    if document.source_size > NOTES_MAX_SOURCE_BYTES as u64 {
        return Err(NotesError::InvalidIndex(
            "manifest source size exceeds the supported limit".to_string(),
        ));
    }
    if document.chunk_count == 0 || u64::from(document.chunk_count) > document.source_size.max(1) {
        return Err(NotesError::InvalidIndex(
            "manifest document chunk count is invalid".to_string(),
        ));
    }
    Ok(())
}

pub(super) fn manifest_document_entry_size(
    document_id: &str,
    document: &NotesManifestDocument,
) -> Result<u64, NotesError> {
    validate_manifest_document(document_id, document)?;
    let bytes = serde_json::to_vec_pretty(&BTreeMap::from([(document_id, document)]))?;
    let nested_indent_bytes = 2 * bytes.iter().filter(|&&byte| byte == b'\n').count();
    Ok((bytes.len() + nested_indent_bytes - 4) as u64)
}

pub(super) fn validate_manifest_size(bytes: u64) -> Result<(), NotesError> {
    if bytes > MAX_MANIFEST_BYTES {
        return Err(NotesError::CollectionTooLarge(
            "The folder contains too many notes to index".to_string(),
        ));
    }
    Ok(())
}

pub(super) fn serialize_manifest_for_publish(
    manifest: &NotesManifest,
    collection_id: &str,
) -> Result<Vec<u8>, NotesError> {
    validate_manifest(manifest, collection_id, false)?;
    let mut bytes = serde_json::to_vec_pretty(manifest)?;
    bytes.push(b'\n');
    validate_manifest_size(bytes.len() as u64)?;
    Ok(bytes)
}

pub(super) fn load_manifest_file(
    path: &Path,
    collection_id: &str,
    require_ready: bool,
) -> Result<NotesManifest, NotesError> {
    let metadata = fs::symlink_metadata(path)?;
    if !metadata.file_type().is_file() {
        return Err(NotesError::InvalidIndex(
            "manifest must be a regular file".to_string(),
        ));
    }
    if metadata.len() == 0 || metadata.len() > MAX_MANIFEST_BYTES {
        return Err(NotesError::InvalidIndex(
            "manifest size is outside the supported range".to_string(),
        ));
    }
    let manifest = serde_json::from_slice(&fs::read(path)?)?;
    validate_manifest(&manifest, collection_id, require_ready)?;
    Ok(manifest)
}

pub(super) fn load_published_manifest(
    collection_directory: &Path,
    collection_id: &str,
    require_ready: bool,
) -> Result<(NotesManifest, Option<i64>), NotesError> {
    let manifest_path = collection_directory.join(NOTES_MANIFEST_FILE);
    match load_manifest_file(&manifest_path, collection_id, require_ready) {
        Ok(manifest) => Ok((manifest, manifest_updated_at_ms(&manifest_path))),
        Err(NotesError::Io(error)) if error.kind() == std::io::ErrorKind::NotFound => {
            let backup_path = collection_directory.join(NOTES_MANIFEST_BACKUP_FILE);
            load_manifest_file(&backup_path, collection_id, require_ready)
                .map(|manifest| (manifest, manifest_updated_at_ms(&backup_path)))
        }
        Err(primary_error) => {
            let backup_path = collection_directory.join(NOTES_MANIFEST_BACKUP_FILE);
            match load_manifest_file(&backup_path, collection_id, require_ready) {
                Ok(manifest) => Ok((manifest, manifest_updated_at_ms(&backup_path))),
                Err(_) => Err(primary_error),
            }
        }
    }
}

pub(super) fn manifest_updated_at_ms(path: &Path) -> Option<i64> {
    fs::metadata(path)
        .ok()?
        .modified()
        .ok()
        .and_then(system_time_ms)
}

fn system_time_ms(time: SystemTime) -> Option<i64> {
    time.duration_since(UNIX_EPOCH)
        .ok()?
        .as_millis()
        .try_into()
        .ok()
}
