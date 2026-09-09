use std::collections::BTreeMap;
use std::fs::{self, OpenOptions};
use std::io::Write;
#[cfg(unix)]
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};

use uuid::Uuid;

use super::manifest::{
    NOTES_DOCUMENTS_DIRECTORY, NOTES_MANIFEST_BACKUP_FILE, NOTES_MANIFEST_FILE, NotesManifest,
    NotesManifestDocument, collection_directory, empty_manifest, load_manifest_file,
    load_published_manifest, manifest_document_entry_size, manifest_updated_at_ms,
    notes_index_contract, serialize_manifest_for_publish, shard_directory, validate_manifest_size,
};
use super::reconcile::{IndexedNotesDocument, plan_notes_reconciliation};
use super::shard::{
    NOTES_SHARD_FILE, NOTES_VECTORS_FILE, NotesShard, NotesShardIntegrity, load_and_validate_shard,
    serialize_shard,
};
use super::{
    NOTES_CHUNK_UTF8_BYTES, NOTES_MAX_COLLECTION_CHUNKS, NOTES_MAX_COLLECTION_DOCUMENTS,
    NOTES_MAX_COLLECTION_SOURCE_BYTES, NotesError, NotesReconciliationPlan, NotesSourceDocument,
    PreparedNotesDocument, collection_reader_snapshot, contains_unsupported_control,
    is_valid_label, pinned_revision_key, sha256_hex, validate_collection_id, validate_document_id,
    validate_revision,
};

pub struct NotesIndexWriter {
    collection_id: String,
    collection_directory: PathBuf,
    manifest: NotesManifest,
    source_bytes: u64,
    chunk_count: u64,
    manifest_bytes: u64,
}

pub struct ValidatedNotesDocument<'a> {
    collection_id: String,
    prepared: &'a PreparedNotesDocument,
    source_metadata: &'a NotesSourceDocument,
    shard_bytes: Vec<u8>,
    shard_sha256: String,
    cached_vectors_sha256: Option<String>,
}

impl ValidatedNotesDocument<'_> {
    pub fn needs_embedding(&self) -> bool {
        self.cached_vectors_sha256.is_none()
    }
}

pub fn remove_notes_collection(
    index_root: impl AsRef<Path>,
    collection_id: &str,
) -> Result<(), NotesError> {
    validate_collection_id(collection_id)?;
    match remove_owned_entry(&collection_directory(index_root.as_ref(), collection_id)) {
        Err(NotesError::Io(error)) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        result => result,
    }
}

pub fn cleanup_unreferenced_notes_shards(
    index_root: impl AsRef<Path>,
    collection_id: &str,
) -> Result<(), NotesError> {
    validate_collection_id(collection_id)?;
    let collection_directory =
        fs::canonicalize(collection_directory(index_root.as_ref(), collection_id))?;
    let (manifest, _) = load_published_manifest(&collection_directory, collection_id, false)?;
    cleanup_unreferenced_shards(&collection_directory, &manifest.documents)
}

impl NotesIndexWriter {
    pub fn validate_inventory_capacity(
        collection_id: &str,
        inventory: &[NotesSourceDocument],
    ) -> Result<(), NotesError> {
        validate_collection_id(collection_id)?;
        if inventory.len() > NOTES_MAX_COLLECTION_DOCUMENTS {
            return Err(NotesError::CollectionTooLarge(
                "The folder contains too many notes to index".to_string(),
            ));
        }
        let total_source_bytes = inventory.iter().try_fold(0_u64, |total, source| {
            source.validate()?;
            total
                .checked_add(source.size)
                .ok_or_else(source_content_too_large)
        })?;
        ensure_collection_capacity(total_source_bytes, 0)?;
        let digest = "a".repeat(64);
        let mut manifest = empty_manifest(collection_id);
        for source in inventory {
            manifest.documents.insert(
                source.document_id.clone(),
                NotesManifestDocument {
                    revision: digest.clone(),
                    source_size: source.size,
                    source_modified_at_ms: source.modified_at_ms,
                    chunk_count: 1,
                    shard_sha256: digest.clone(),
                    vectors_sha256: digest.clone(),
                },
            );
        }
        serialize_manifest_for_publish(&manifest, collection_id).map(|_| ())
    }

    pub fn open(index_root: impl AsRef<Path>, collection_id: String) -> Result<Self, NotesError> {
        validate_collection_id(&collection_id)?;
        ensure_directory(index_root.as_ref())?;
        let collection_directory = collection_directory(index_root.as_ref(), &collection_id);
        ensure_directory(&collection_directory)?;
        let collection_directory = fs::canonicalize(collection_directory)?;
        ensure_directory(&collection_directory.join(NOTES_DOCUMENTS_DIRECTORY))?;
        recover_manifest_publication(&collection_directory, &collection_id)?;

        let manifest_path = collection_directory.join(NOTES_MANIFEST_FILE);
        let manifest = if path_exists(&manifest_path)? {
            load_manifest_file(&manifest_path, &collection_id, false)?
        } else {
            empty_manifest(&collection_id)
        };
        let (source_bytes, chunk_count) = manifest_capacity(&manifest)?;
        let manifest_bytes =
            serialize_manifest_for_publish(&manifest, &collection_id)?.len() as u64;
        let _ = cleanup_unreferenced_shards(&collection_directory, &manifest.documents);
        Ok(Self {
            collection_id,
            collection_directory,
            manifest,
            source_bytes,
            chunk_count,
            manifest_bytes,
        })
    }

    pub fn initial_inventory_complete(&self) -> bool {
        self.manifest.initial_inventory_complete
    }

    pub fn last_updated_at_ms(&self) -> Option<i64> {
        self.initial_inventory_complete()
            .then(|| manifest_updated_at_ms(&self.collection_directory.join(NOTES_MANIFEST_FILE)))
            .flatten()
    }

    pub fn indexed_document_ids(&self) -> impl Iterator<Item = &str> {
        self.manifest.documents.keys().map(String::as_str)
    }

    pub fn indexed_document_count(&self) -> usize {
        self.manifest.documents.len()
    }

    pub fn indexed_revision(&self, document_id: &str) -> Option<&str> {
        self.manifest
            .documents
            .get(document_id)
            .map(|document| document.revision.as_str())
    }

    pub fn plan_reconciliation(
        &self,
        inventory: &[NotesSourceDocument],
        forced_document_ids: &[String],
        force_full_hash: bool,
    ) -> Result<NotesReconciliationPlan, NotesError> {
        let indexed = self
            .manifest
            .documents
            .iter()
            .map(|(document_id, document)| IndexedNotesDocument {
                document_id: document_id.clone(),
                revision: document.revision.clone(),
                source_size: document.source_size,
                source_modified_at_ms: document.source_modified_at_ms,
            })
            .collect::<Vec<_>>();
        plan_notes_reconciliation(inventory, &indexed, forced_document_ids, force_full_hash)
    }

    pub fn commit_document(
        &mut self,
        prepared: &PreparedNotesDocument,
        embeddings: &[Vec<f32>],
        source_metadata: &NotesSourceDocument,
    ) -> Result<(), NotesError> {
        let validated = self.validate_document(prepared, source_metadata)?;
        self.commit_validated_document(validated, Some(embeddings))
    }

    pub fn commit_validated_document(
        &mut self,
        validated: ValidatedNotesDocument<'_>,
        embeddings: Option<&[Vec<f32>]>,
    ) -> Result<(), NotesError> {
        let ValidatedNotesDocument {
            collection_id,
            prepared,
            source_metadata,
            shard_bytes,
            shard_sha256,
            cached_vectors_sha256,
        } = validated;
        if collection_id != self.collection_id {
            return Err(NotesError::InvalidInput(
                "validated document belongs to another collection".to_string(),
            ));
        }
        validate_prepared_document(prepared, source_metadata)?;
        self.validate_document_capacity(prepared, source_metadata)?;
        let Some(embeddings) = embeddings else {
            let vectors_sha256 = cached_vectors_sha256.ok_or_else(|| {
                NotesError::InvalidInput("document requires embeddings".to_string())
            })?;
            self.validate_existing_shard(prepared, &shard_sha256, &vectors_sha256)?;
            return self.activate_document(
                prepared,
                source_metadata,
                &shard_sha256,
                &vectors_sha256,
            );
        };
        if embeddings.len() != prepared.chunks.len() {
            return Err(NotesError::InvalidInput(
                "embedding count does not match prepared chunks".to_string(),
            ));
        }
        let vector_dimension = usize::try_from(notes_index_contract().retrieval_dimension)
            .map_err(|_| NotesError::InvalidInput("vector dimension is too large".to_string()))?;
        let vector_bytes_len = embeddings
            .len()
            .checked_mul(vector_dimension)
            .ok_or_else(|| NotesError::InvalidInput("vector byte length overflow".to_string()))?;
        let mut vector_bytes = Vec::new();
        vector_bytes
            .try_reserve_exact(vector_bytes_len)
            .map_err(|_| NotesError::InvalidInput("vector allocation is too large".to_string()))?;
        let scale = notes_index_contract().quantization_scale as f32;
        for embedding in embeddings {
            if embedding.len() != vector_dimension
                || embedding.iter().any(|component| !component.is_finite())
            {
                return Err(NotesError::InvalidInput(
                    "embedding shape or values are invalid".to_string(),
                ));
            }
            vector_bytes.extend(embedding.iter().map(|component| {
                (component.clamp(-1.0, 1.0) * scale)
                    .round_ties_even()
                    .clamp(-scale, scale) as i8 as u8
            }));
        }
        let vectors_sha256 = sha256_hex(&vector_bytes);

        let final_directory = shard_directory(
            &self.collection_directory,
            &prepared.document_id,
            &prepared.revision,
        );
        if path_exists(&final_directory)? {
            match self.validate_existing_shard(prepared, &shard_sha256, &vectors_sha256) {
                Ok(()) => {
                    return self.activate_document(
                        prepared,
                        source_metadata,
                        &shard_sha256,
                        &vectors_sha256,
                    );
                }
                Err(
                    NotesError::InvalidIndex(_)
                    | NotesError::IncompatibleIndex
                    | NotesError::Json(_),
                ) => remove_owned_entry(&final_directory)?,
                Err(NotesError::Io(error)) if error.kind() == std::io::ErrorKind::NotFound => {
                    remove_owned_entry(&final_directory)?;
                }
                Err(error) => return Err(error),
            }
        }

        let parent = final_directory
            .parent()
            .ok_or_else(|| NotesError::InvalidIndex("shard directory has no parent".to_string()))?;
        ensure_directory(parent)?;
        let temporary_directory = parent.join(format!(
            ".{}.tmp-{}",
            prepared.revision,
            Uuid::new_v4().hyphenated()
        ));
        fs::create_dir(&temporary_directory)?;
        let write_result = (|| {
            write_new_file(&temporary_directory.join(NOTES_SHARD_FILE), &shard_bytes)?;
            write_new_file(&temporary_directory.join(NOTES_VECTORS_FILE), &vector_bytes)?;
            load_and_validate_shard(
                &temporary_directory,
                &self.collection_id,
                &prepared.document_id,
                &prepared.revision,
                prepared.chunks.len(),
                NotesShardIntegrity {
                    shard_sha256: &shard_sha256,
                    vectors_sha256: &vectors_sha256,
                },
                Some(prepared),
            )?;
            match fs::rename(&temporary_directory, &final_directory) {
                Ok(()) => Ok(()),
                Err(_) if path_exists(&final_directory)? => {
                    self.validate_existing_shard(prepared, &shard_sha256, &vectors_sha256)
                }
                Err(rename_error) => Err(NotesError::Io(rename_error)),
            }
        })();
        if path_exists(&temporary_directory).unwrap_or(false) {
            let _ = remove_owned_entry(&temporary_directory);
        }
        write_result?;
        self.activate_document(prepared, source_metadata, &shard_sha256, &vectors_sha256)
    }

    pub fn validate_document<'a>(
        &self,
        prepared: &'a PreparedNotesDocument,
        source_metadata: &'a NotesSourceDocument,
    ) -> Result<ValidatedNotesDocument<'a>, NotesError> {
        validate_prepared_document(prepared, source_metadata)?;
        self.validate_document_capacity(prepared, source_metadata)?;
        let shard_bytes =
            serialize_shard(&NotesShard::from_prepared(&self.collection_id, prepared))?;
        let shard_sha256 = sha256_hex(&shard_bytes);
        let cached_vectors_sha256 = if let Some(existing) =
            self.manifest.documents.get(&prepared.document_id)
            && existing.revision == prepared.revision
            && existing.shard_sha256 == shard_sha256
            && existing.chunk_count as usize == prepared.chunks.len()
        {
            match self.validate_existing_shard(prepared, &shard_sha256, &existing.vectors_sha256) {
                Ok(()) => Some(existing.vectors_sha256.clone()),
                Err(
                    NotesError::InvalidIndex(_)
                    | NotesError::IncompatibleIndex
                    | NotesError::Json(_),
                ) => None,
                Err(NotesError::Io(error)) if error.kind() == std::io::ErrorKind::NotFound => None,
                Err(error) => return Err(error),
            }
        } else {
            None
        };
        Ok(ValidatedNotesDocument {
            collection_id: self.collection_id.clone(),
            prepared,
            source_metadata,
            shard_bytes,
            shard_sha256,
            cached_vectors_sha256,
        })
    }

    fn validate_existing_shard(
        &self,
        prepared: &PreparedNotesDocument,
        shard_sha256: &str,
        vectors_sha256: &str,
    ) -> Result<(), NotesError> {
        load_and_validate_shard(
            &shard_directory(
                &self.collection_directory,
                &prepared.document_id,
                &prepared.revision,
            ),
            &self.collection_id,
            &prepared.document_id,
            &prepared.revision,
            prepared.chunks.len(),
            NotesShardIntegrity {
                shard_sha256,
                vectors_sha256,
            },
            Some(prepared),
        )
    }

    fn validate_document_capacity(
        &self,
        prepared: &PreparedNotesDocument,
        source_metadata: &NotesSourceDocument,
    ) -> Result<(), NotesError> {
        let existing = self.manifest.documents.get(&prepared.document_id);
        let source_bytes = self
            .source_bytes
            .checked_sub(existing.map_or(0, |document| document.source_size))
            .and_then(|total| total.checked_add(source_metadata.size))
            .ok_or_else(source_content_too_large)?;
        let document_chunks =
            u64::try_from(prepared.chunks.len()).map_err(|_| chunk_count_too_large())?;
        let chunks = self
            .chunk_count
            .checked_sub(existing.map_or(0, |document| u64::from(document.chunk_count)))
            .and_then(|total| total.checked_add(document_chunks))
            .ok_or_else(chunk_count_too_large)?;
        ensure_collection_capacity(source_bytes, chunks)?;
        if self
            .manifest
            .documents
            .len()
            .saturating_add(usize::from(existing.is_none()))
            > NOTES_MAX_COLLECTION_DOCUMENTS
        {
            return Err(NotesError::CollectionTooLarge(
                "The folder contains too many notes to index".to_string(),
            ));
        }
        let document = manifest_document(
            prepared,
            source_metadata,
            &prepared.revision,
            &prepared.revision,
        )?;
        validate_manifest_size(self.updated_manifest_size(&prepared.document_id, Some(&document))?)
    }

    fn updated_manifest_size(
        &self,
        document_id: &str,
        document: Option<&NotesManifestDocument>,
    ) -> Result<u64, NotesError> {
        let existing = self.manifest.documents.get(document_id);
        let existing_bytes = existing
            .map(|entry| manifest_document_entry_size(document_id, entry))
            .transpose()?
            .unwrap_or(0);
        let document_bytes = document
            .map(|entry| manifest_document_entry_size(document_id, entry))
            .transpose()?
            .unwrap_or(0);
        let document_count = self.manifest.documents.len() - usize::from(existing.is_some())
            + usize::from(document.is_some());
        let old_object_spacing = 2 * u64::from(!self.manifest.documents.is_empty());
        let new_object_spacing = 2 * u64::from(document_count > 0);
        self.manifest_bytes
            .checked_sub(existing_bytes + old_object_spacing)
            .and_then(|bytes| bytes.checked_add(document_bytes + new_object_spacing))
            .ok_or_else(|| {
                NotesError::InvalidIndex("manifest byte total is inconsistent".to_string())
            })
    }

    pub fn commit_deletions(&mut self, document_ids: &[String]) -> Result<(), NotesError> {
        for document_id in document_ids {
            validate_document_id(document_id)?;
            let Some(document) = self.manifest.documents.get(document_id) else {
                continue;
            };
            let source_bytes = self
                .source_bytes
                .checked_sub(document.source_size)
                .ok_or_else(|| {
                    NotesError::InvalidIndex(
                        "manifest source byte total is inconsistent".to_string(),
                    )
                })?;
            let chunk_count = self
                .chunk_count
                .checked_sub(u64::from(document.chunk_count))
                .ok_or_else(|| {
                    NotesError::InvalidIndex("manifest chunk total is inconsistent".to_string())
                })?;
            let manifest_bytes = self.updated_manifest_size(document_id, None)?;
            self.manifest.documents.remove(document_id);
            self.source_bytes = source_bytes;
            self.chunk_count = chunk_count;
            self.manifest_bytes = manifest_bytes;
        }
        Ok(())
    }

    pub fn publish(&mut self, initial_complete: bool) -> Result<(), NotesError> {
        self.manifest_bytes += u64::from(self.manifest.initial_inventory_complete);
        self.manifest_bytes -= u64::from(initial_complete);
        self.manifest.initial_inventory_complete = initial_complete;
        publish_manifest_atomically(
            &self.collection_directory,
            &self.manifest,
            &self.collection_id,
        )?;
        let _ = cleanup_unreferenced_shards(&self.collection_directory, &self.manifest.documents);
        Ok(())
    }

    fn activate_document(
        &mut self,
        prepared: &PreparedNotesDocument,
        source_metadata: &NotesSourceDocument,
        shard_sha256: &str,
        vectors_sha256: &str,
    ) -> Result<(), NotesError> {
        let document = manifest_document(prepared, source_metadata, shard_sha256, vectors_sha256)?;
        let existing = self.manifest.documents.get(&prepared.document_id);
        let source_bytes = self
            .source_bytes
            .checked_sub(existing.map_or(0, |document| document.source_size))
            .and_then(|total| total.checked_add(source_metadata.size))
            .ok_or_else(source_content_too_large)?;
        let total_chunks = self
            .chunk_count
            .checked_sub(existing.map_or(0, |document| u64::from(document.chunk_count)))
            .and_then(|total| total.checked_add(u64::from(document.chunk_count)))
            .ok_or_else(chunk_count_too_large)?;
        ensure_collection_capacity(source_bytes, total_chunks)?;
        let manifest_bytes = self.updated_manifest_size(&prepared.document_id, Some(&document))?;
        validate_manifest_size(manifest_bytes)?;
        self.manifest
            .documents
            .insert(prepared.document_id.clone(), document);
        self.source_bytes = source_bytes;
        self.chunk_count = total_chunks;
        self.manifest_bytes = manifest_bytes;
        Ok(())
    }
}

fn manifest_document(
    prepared: &PreparedNotesDocument,
    source_metadata: &NotesSourceDocument,
    shard_sha256: &str,
    vectors_sha256: &str,
) -> Result<NotesManifestDocument, NotesError> {
    validate_revision(shard_sha256)?;
    validate_revision(vectors_sha256)?;
    let chunk_count = u32::try_from(prepared.chunks.len()).map_err(|_| chunk_count_too_large())?;
    Ok(NotesManifestDocument {
        revision: prepared.revision.clone(),
        source_size: source_metadata.size,
        source_modified_at_ms: source_metadata.modified_at_ms,
        chunk_count,
        shard_sha256: shard_sha256.to_string(),
        vectors_sha256: vectors_sha256.to_string(),
    })
}

fn manifest_capacity(manifest: &NotesManifest) -> Result<(u64, u64), NotesError> {
    let (source_bytes, chunks) = manifest.documents.values().try_fold(
        (0_u64, 0_u64),
        |(source_total, chunk_total), document| {
            let source_total = source_total
                .checked_add(document.source_size)
                .ok_or_else(|| {
                    NotesError::InvalidIndex("manifest source byte count overflow".to_string())
                })?;
            let chunk_total = chunk_total
                .checked_add(u64::from(document.chunk_count))
                .ok_or_else(|| {
                    NotesError::InvalidIndex("manifest chunk count overflow".to_string())
                })?;
            Ok::<_, NotesError>((source_total, chunk_total))
        },
    )?;
    Ok((source_bytes, chunks))
}

fn ensure_collection_capacity(source_bytes: u64, chunks: u64) -> Result<(), NotesError> {
    if source_bytes > NOTES_MAX_COLLECTION_SOURCE_BYTES {
        return Err(source_content_too_large());
    }
    if chunks > NOTES_MAX_COLLECTION_CHUNKS {
        return Err(chunk_count_too_large());
    }
    Ok(())
}

fn source_content_too_large() -> NotesError {
    NotesError::CollectionTooLarge("The folder contains too much note content to index".to_string())
}

fn chunk_count_too_large() -> NotesError {
    NotesError::CollectionTooLarge("The folder contains too many note chunks to index".to_string())
}

fn validate_prepared_document(
    prepared: &PreparedNotesDocument,
    source_metadata: &NotesSourceDocument,
) -> Result<(), NotesError> {
    source_metadata.validate()?;
    validate_document_id(&prepared.document_id)?;
    validate_revision(&prepared.revision)?;
    if prepared.document_id != source_metadata.document_id {
        return Err(NotesError::InvalidInput(
            "prepared document does not match its source metadata".to_string(),
        ));
    }
    if !is_valid_label(&prepared.title) {
        return Err(NotesError::InvalidInput(
            "prepared title length is outside the supported range".to_string(),
        ));
    }
    if prepared.chunks.is_empty() {
        return Err(NotesError::InvalidInput(
            "prepared document must contain chunks".to_string(),
        ));
    }
    for chunk in &prepared.chunks {
        if chunk
            .section
            .as_ref()
            .is_some_and(|section| !is_valid_label(section))
        {
            return Err(NotesError::InvalidInput(
                "prepared chunk section is invalid".to_string(),
            ));
        }
        if chunk.text.trim().is_empty()
            || chunk.text.len() > NOTES_CHUNK_UTF8_BYTES
            || contains_unsupported_control(&chunk.text)
        {
            return Err(NotesError::InvalidInput(
                "prepared chunk text is invalid".to_string(),
            ));
        }
    }
    Ok(())
}

fn ensure_directory(path: &Path) -> Result<(), NotesError> {
    if !path_exists(path)? {
        fs::create_dir_all(path)?;
    }
    if !fs::symlink_metadata(path)?.file_type().is_dir() {
        return Err(NotesError::InvalidIndex(
            "Notes store path must be a directory".to_string(),
        ));
    }
    #[cfg(unix)]
    fs::set_permissions(path, fs::Permissions::from_mode(0o700))?;
    Ok(())
}

fn path_exists(path: &Path) -> Result<bool, NotesError> {
    match fs::symlink_metadata(path) {
        Ok(_) => Ok(true),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(error.into()),
    }
}

fn write_new_file(path: &Path, bytes: &[u8]) -> Result<(), NotesError> {
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    options.mode(0o600);
    let mut file = options.open(path)?;
    file.write_all(bytes)?;
    file.sync_all()?;
    Ok(())
}

fn publish_manifest_atomically(
    collection_directory: &Path,
    manifest: &NotesManifest,
    collection_id: &str,
) -> Result<(), NotesError> {
    let manifest_path = collection_directory.join(NOTES_MANIFEST_FILE);
    let backup_path = collection_directory.join(NOTES_MANIFEST_BACKUP_FILE);
    if path_exists(&backup_path)? {
        remove_owned_entry(&backup_path)?;
    }
    let temporary_path =
        collection_directory.join(format!(".manifest.tmp-{}", Uuid::new_v4().hyphenated()));
    let bytes = serialize_manifest_for_publish(manifest, collection_id)?;
    write_new_file(&temporary_path, &bytes)?;
    load_manifest_file(&temporary_path, collection_id, false)?;

    let had_active = path_exists(&manifest_path)?;
    if had_active {
        fs::rename(&manifest_path, &backup_path)?;
    }
    if let Err(error) = fs::rename(&temporary_path, &manifest_path) {
        if had_active && path_exists(&backup_path).unwrap_or(false) {
            let _ = fs::rename(&backup_path, &manifest_path);
        }
        let _ = fs::remove_file(&temporary_path);
        return Err(error.into());
    }
    if path_exists(&backup_path)? {
        remove_owned_entry(&backup_path)?;
    }
    Ok(())
}

fn recover_manifest_publication(
    collection_directory: &Path,
    collection_id: &str,
) -> Result<(), NotesError> {
    let manifest_path = collection_directory.join(NOTES_MANIFEST_FILE);
    let backup_path = collection_directory.join(NOTES_MANIFEST_BACKUP_FILE);
    let has_manifest = path_exists(&manifest_path)?;
    let has_backup = path_exists(&backup_path)?;
    match (has_manifest, has_backup) {
        (false, true) => {
            load_manifest_file(&backup_path, collection_id, false)?;
            fs::rename(&backup_path, &manifest_path)?;
        }
        (true, true) => match load_manifest_file(&manifest_path, collection_id, false) {
            Ok(_) => remove_owned_entry(&backup_path)?,
            Err(primary_error) => {
                load_manifest_file(&backup_path, collection_id, false)?;
                remove_owned_entry(&manifest_path)?;
                fs::rename(&backup_path, &manifest_path).map_err(|_| primary_error)?;
            }
        },
        _ => {}
    }
    for entry in fs::read_dir(collection_directory)? {
        let entry = entry?;
        if entry
            .file_name()
            .to_string_lossy()
            .starts_with(".manifest.tmp-")
        {
            remove_owned_entry(&entry.path())?;
        }
    }
    Ok(())
}

fn cleanup_unreferenced_shards(
    collection_directory: &Path,
    documents: &BTreeMap<String, NotesManifestDocument>,
) -> Result<(), NotesError> {
    use super::manifest::document_storage_id;

    let (reader_opening, pinned_revisions) = collection_reader_snapshot(collection_directory);
    if reader_opening {
        return Ok(());
    }
    let keep = documents
        .iter()
        .map(|(document_id, document)| (document_storage_id(document_id), &document.revision))
        .collect::<BTreeMap<_, _>>();
    let documents_directory = collection_directory.join(NOTES_DOCUMENTS_DIRECTORY);
    for document_entry in fs::read_dir(&documents_directory)? {
        let document_entry = document_entry?;
        let name = document_entry.file_name().to_string_lossy().into_owned();
        if !document_entry.file_type()?.is_dir() {
            remove_owned_entry(&document_entry.path())?;
            continue;
        }
        for revision_entry in fs::read_dir(document_entry.path())? {
            let revision_entry = revision_entry?;
            let revision = revision_entry.file_name().to_string_lossy().into_owned();
            let is_active = keep
                .get(&name)
                .is_some_and(|active_revision| active_revision.as_str() == revision);
            if !is_active && !pinned_revisions.contains(&pinned_revision_key(&name, &revision)) {
                remove_owned_entry(&revision_entry.path())?;
            }
        }
        let document_key = ente_ensu_crypto::sha256(name.as_bytes());
        if !keep.contains_key(&name)
            && !pinned_revisions
                .iter()
                .any(|(document, _)| document == &document_key)
        {
            fs::remove_dir(document_entry.path())?;
        }
    }
    Ok(())
}

fn remove_owned_entry(path: &Path) -> Result<(), NotesError> {
    let metadata = fs::symlink_metadata(path)?;
    if metadata.file_type().is_dir() {
        fs::remove_dir_all(path)?;
    } else {
        fs::remove_file(path)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::notes::{NOTES_MAX_SOURCE_BYTES, NotesCollectionIndex, prepare_notes_document};

    fn collection() -> String {
        "123e4567-e89b-12d3-a456-426614174000".to_string()
    }

    fn prepared(id: &str, text: &str) -> PreparedNotesDocument {
        prepare_notes_document(id, text.as_bytes()).unwrap()
    }

    fn metadata(prepared: &PreparedNotesDocument, size: usize) -> NotesSourceDocument {
        NotesSourceDocument {
            document_id: prepared.document_id.clone(),
            size: size as u64,
            modified_at_ms: Some(1_000),
        }
    }

    fn embeddings(prepared: &PreparedNotesDocument, scores: &[f32]) -> Vec<Vec<f32>> {
        assert_eq!(prepared.chunks.len(), scores.len());
        scores
            .iter()
            .map(|score| {
                let mut embedding = vec![0.0; 512];
                embedding[0] = *score;
                embedding
            })
            .collect()
    }

    fn publish_ready_manifest(index_root: &Path) -> PathBuf {
        let document = prepared("note.md", "note");
        let mut writer = NotesIndexWriter::open(index_root, collection()).unwrap();
        writer
            .commit_document(
                &document,
                &embeddings(&document, &[1.0]),
                &metadata(&document, 4),
            )
            .unwrap();
        writer.publish(true).unwrap();
        collection_directory(index_root, &collection())
    }

    #[test]
    fn collection_removal_is_confined_to_canonical_uuid_children() {
        let root = tempfile::tempdir().unwrap();
        assert!(remove_notes_collection(root.path(), "../source").is_err());
        let directory = publish_ready_manifest(root.path());
        fs::write(root.path().join("source.md"), b"keep").unwrap();
        remove_notes_collection(root.path(), &collection()).unwrap();
        assert!(root.path().join("source.md").exists());
        assert!(!directory.exists());
        remove_notes_collection(root.path(), &collection()).unwrap();
    }

    #[test]
    fn writes_opens_and_searches_documents() {
        let temp = tempfile::tempdir().unwrap();
        let first_text = "first document";
        let first = prepared("first.md", first_text);
        let second = prepared("second.md", "second document");
        let mut writer = NotesIndexWriter::open(temp.path(), collection()).unwrap();
        assert!(writer.last_updated_at_ms().is_none());
        writer
            .commit_document(
                &first,
                &embeddings(&first, &[1.0]),
                &metadata(&first, first_text.len()),
            )
            .unwrap();
        writer
            .commit_document(
                &second,
                &embeddings(&second, &[0.8]),
                &metadata(&second, "second document".len()),
            )
            .unwrap();
        writer.publish(true).unwrap();

        let index = NotesCollectionIndex::open(temp.path(), collection()).unwrap();
        assert_eq!(index.document_count(), 2);
        assert!(index.last_updated_at_ms().is_some());
        assert_eq!(writer.last_updated_at_ms(), index.last_updated_at_ms());
        let mut query = vec![0.0; 512];
        query[0] = 1.0;
        let hits = index.search(&query).unwrap();
        assert_eq!(hits.len(), 2);
        assert_eq!(hits[0].document_id, "first.md");
        assert_eq!(hits[1].document_id, "second.md");
        assert!(hits[0].score > hits[1].score);

        let vectors_path = shard_directory(
            &collection_directory(temp.path(), &collection()),
            &first.document_id,
            &first.revision,
        )
        .join(NOTES_VECTORS_FILE);
        let mut corrupted = fs::read(&vectors_path).unwrap();
        corrupted[0] ^= 1;
        fs::write(vectors_path, corrupted).unwrap();
        assert!(matches!(
            NotesCollectionIndex::open(temp.path(), collection()),
            Err(NotesError::InvalidIndex(_))
        ));
    }

    #[test]
    fn repairs_missing_shard_files_in_complete_and_partial_indexes() {
        for complete in [false, true] {
            for missing in [NOTES_SHARD_FILE, NOTES_VECTORS_FILE] {
                let temp = tempfile::tempdir().unwrap();
                let document = prepared("note.md", "note");
                let vectors = embeddings(&document, &[1.0]);
                let source = metadata(&document, 4);
                let mut writer = NotesIndexWriter::open(temp.path(), collection()).unwrap();
                writer
                    .commit_document(&document, &vectors, &source)
                    .unwrap();
                writer.publish(complete).unwrap();
                let directory = shard_directory(
                    &collection_directory(temp.path(), &collection()),
                    &document.document_id,
                    &document.revision,
                );
                fs::remove_file(directory.join(missing)).unwrap();
                let mut writer = NotesIndexWriter::open(temp.path(), collection()).unwrap();
                assert_eq!(writer.initial_inventory_complete(), complete);
                writer
                    .commit_document(&document, &vectors, &source)
                    .unwrap();
                writer.publish(true).unwrap();
                let index = NotesCollectionIndex::open(temp.path(), collection()).unwrap();
                assert_eq!(index.search(&vectors[0]).unwrap()[0].document_id, "note.md");
            }
        }
    }

    #[test]
    fn maintains_cached_capacity_totals_across_replacement_and_deletion() {
        let temp = tempfile::tempdir().unwrap();
        let first = prepared("first.md", "first");
        let second = prepared("second.md", "second");
        let mut writer = NotesIndexWriter::open(temp.path(), collection()).unwrap();
        writer
            .commit_document(&first, &embeddings(&first, &[1.0]), &metadata(&first, 5))
            .unwrap();
        writer
            .commit_document(&second, &embeddings(&second, &[0.8]), &metadata(&second, 6))
            .unwrap();
        assert_eq!(writer.source_bytes, 11);
        assert_eq!(writer.chunk_count, 2);

        let replacement = prepared("first.md", "replacement");
        writer
            .commit_document(
                &replacement,
                &embeddings(&replacement, &[0.9]),
                &metadata(&replacement, 11),
            )
            .unwrap();
        assert_eq!(writer.source_bytes, 17);
        assert_eq!(writer.chunk_count, 2);

        writer.commit_deletions(&[second.document_id]).unwrap();
        assert_eq!(writer.source_bytes, 11);
        assert_eq!(writer.chunk_count, 1);
    }

    #[test]
    fn rejects_collections_over_capacity_before_embedding() {
        let inventory = (0..=NOTES_MAX_COLLECTION_DOCUMENTS)
            .map(|index| NotesSourceDocument {
                document_id: format!("note-{index:05}.md"),
                size: 1,
                modified_at_ms: Some(1),
            })
            .collect::<Vec<_>>();
        assert!(matches!(
            NotesIndexWriter::validate_inventory_capacity(&collection(), &inventory),
            Err(NotesError::CollectionTooLarge(_))
        ));

        let supported_count = NOTES_MAX_COLLECTION_SOURCE_BYTES / NOTES_MAX_SOURCE_BYTES as u64;
        let inventory = (0..=supported_count)
            .map(|index| NotesSourceDocument {
                document_id: format!("note-{index:03}.md"),
                size: NOTES_MAX_SOURCE_BYTES as u64,
                modified_at_ms: Some(1),
            })
            .collect::<Vec<_>>();
        assert!(matches!(
            NotesIndexWriter::validate_inventory_capacity(&collection(), &inventory),
            Err(NotesError::CollectionTooLarge(_))
        ));

        let temp = tempfile::tempdir().unwrap();
        let mut writer = NotesIndexWriter::open(temp.path(), collection()).unwrap();
        let document = prepared("note.md", "note");
        let source = metadata(&document, 4);
        writer.chunk_count = NOTES_MAX_COLLECTION_CHUNKS;
        assert!(matches!(
            writer.validate_document(&document, &source),
            Err(NotesError::CollectionTooLarge(_))
        ));
        writer.chunk_count = 0;
        writer.source_bytes = NOTES_MAX_COLLECTION_SOURCE_BYTES;
        assert!(matches!(
            writer.validate_document(&document, &source),
            Err(NotesError::CollectionTooLarge(_))
        ));
        writer.source_bytes = 0;
        writer.manifest_bytes = 8 * 1024 * 1024;
        assert!(matches!(
            writer.validate_document(&document, &source),
            Err(NotesError::CollectionTooLarge(_))
        ));
    }

    #[test]
    fn recovers_interrupted_manifest_publications() {
        let backup_only = tempfile::tempdir().unwrap();
        let directory = publish_ready_manifest(backup_only.path());
        let active = directory.join(NOTES_MANIFEST_FILE);
        let backup = directory.join(NOTES_MANIFEST_BACKUP_FILE);
        fs::rename(&active, &backup).unwrap();
        recover_manifest_publication(&directory, &collection()).unwrap();
        assert!(active.is_file());
        assert!(!backup.exists());

        let valid_active = tempfile::tempdir().unwrap();
        let directory = publish_ready_manifest(valid_active.path());
        let active = directory.join(NOTES_MANIFEST_FILE);
        let backup = directory.join(NOTES_MANIFEST_BACKUP_FILE);
        let temporary = directory.join(".manifest.tmp-abandoned");
        fs::copy(&active, &backup).unwrap();
        fs::write(&temporary, b"incomplete").unwrap();
        let expected = fs::read(&active).unwrap();
        recover_manifest_publication(&directory, &collection()).unwrap();
        assert_eq!(fs::read(&active).unwrap(), expected);
        assert!(!backup.exists());
        assert!(!temporary.exists());

        let corrupt_active = tempfile::tempdir().unwrap();
        let directory = publish_ready_manifest(corrupt_active.path());
        let active = directory.join(NOTES_MANIFEST_FILE);
        let backup = directory.join(NOTES_MANIFEST_BACKUP_FILE);
        let expected = fs::read(&active).unwrap();
        fs::copy(&active, &backup).unwrap();
        fs::write(&active, b"not a manifest").unwrap();
        recover_manifest_publication(&directory, &collection()).unwrap();
        assert_eq!(fs::read(&active).unwrap(), expected);
        assert!(!backup.exists());

        let invalid_backup = tempfile::tempdir().unwrap();
        let directory = invalid_backup.path().join(collection());
        fs::create_dir_all(&directory).unwrap();
        fs::write(directory.join(NOTES_MANIFEST_BACKUP_FILE), b"invalid").unwrap();
        assert!(recover_manifest_publication(&directory, &collection()).is_err());
        assert!(!directory.join(NOTES_MANIFEST_FILE).exists());
    }
}
