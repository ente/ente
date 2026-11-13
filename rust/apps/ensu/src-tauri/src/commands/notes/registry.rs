use std::collections::BTreeSet;
use std::fs::{self, OpenOptions};
use std::io::Write;
#[cfg(unix)]
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::commands::common::ApiError;

#[cfg(test)]
use super::TestDirectory;
use super::{ensure_directory, io_error, path_exists, remove_owned_entry};

const NOTES_REGISTRY_FILE: &str = "collections.json";
const NOTES_REGISTRY_BACKUP_FILE: &str = "collections.json.backup";
const NOTES_REGISTRY_SCHEMA_VERSION: u32 = 1;
const MAX_REGISTRY_BYTES: u64 = 1024 * 1024;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct RegisteredCollection {
    pub(super) id: String,
    pub(super) source_root: PathBuf,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct RegistryFile {
    pub(super) schema_version: u32,
    pub(super) collections: Vec<RegisteredCollection>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RegistryHeader {
    schema_version: u32,
}

impl Default for RegistryFile {
    fn default() -> Self {
        Self {
            schema_version: NOTES_REGISTRY_SCHEMA_VERSION,
            collections: Vec::new(),
        }
    }
}

pub(super) struct RegistryStore {
    directory: PathBuf,
    pub(super) registry: RegistryFile,
    pub(super) incompatible_error: Option<String>,
}

impl RegistryStore {
    pub(super) fn open(directory: PathBuf) -> Result<Self, ApiError> {
        ensure_directory(&directory)?;
        let (registry, incompatible_error) = match open_registry_file(&directory) {
            Ok(registry) => (registry, None),
            Err(error) if error.name == Some("incompatible_registry") => {
                crate::logging::log(
                    "Notes",
                    "incompatible registry preserved; Notes are disabled for this version",
                );
                (RegistryFile::default(), Some(error.message))
            }
            Err(error) if is_registry_content_error(&error) => {
                quarantine_invalid_registry_files(&directory)?;
                recover_registry_publication(&directory)?;
                crate::logging::log(
                    "Notes",
                    "invalid registry quarantined; starting with no registered folders",
                );
                (RegistryFile::default(), None)
            }
            Err(error) => return Err(error),
        };
        Ok(Self {
            directory,
            registry,
            incompatible_error,
        })
    }

    pub(super) fn ensure_compatible(&self) -> Result<(), ApiError> {
        match &self.incompatible_error {
            Some(message) => Err(ApiError::new("incompatible_registry", message.clone())),
            None => Ok(()),
        }
    }

    pub(super) fn replace(&mut self, registry: RegistryFile) -> Result<(), ApiError> {
        self.ensure_compatible()?;
        validate_registry(&registry)?;
        publish_registry(&self.directory, &registry)?;
        self.registry = registry;
        Ok(())
    }
}

fn validate_registry(registry: &RegistryFile) -> Result<(), ApiError> {
    if registry.schema_version != NOTES_REGISTRY_SCHEMA_VERSION {
        return Err(ApiError::new(
            "incompatible_registry",
            "This version of Ensu cannot use the existing Notes registry",
        ));
    }
    let mut ids = BTreeSet::new();
    let mut roots = Vec::<&Path>::new();
    for collection in &registry.collections {
        Uuid::parse_str(&collection.id)
            .map_err(|_| ApiError::new("registry", "Notes registry collection ID is invalid"))?;
        if !collection.source_root.is_absolute()
            || collection.source_root.to_str().is_none()
            || !ids.insert(&collection.id)
        {
            return Err(ApiError::new(
                "invalid_registry",
                "The Notes registry is invalid",
            ));
        }
        if roots.iter().any(|root| {
            collection.source_root.starts_with(root) || root.starts_with(&collection.source_root)
        }) {
            return Err(ApiError::new(
                "invalid_registry",
                "The Notes registry is invalid",
            ));
        }
        roots.push(&collection.source_root);
    }
    Ok(())
}

fn open_registry_file(directory: &Path) -> Result<RegistryFile, ApiError> {
    recover_registry_publication(directory)?;
    let path = directory.join(NOTES_REGISTRY_FILE);
    if !path_exists(&path)? {
        return Ok(RegistryFile::default());
    }
    load_valid_registry_file(&path)
}

fn load_valid_registry_file(path: &Path) -> Result<RegistryFile, ApiError> {
    let registry = load_registry_file(path)?;
    validate_registry(&registry)?;
    Ok(registry)
}

fn is_registry_content_error(error: &ApiError) -> bool {
    matches!(error.name, Some("registry" | "invalid_registry"))
}

fn quarantine_invalid_registry_files(directory: &Path) -> Result<(), ApiError> {
    for name in [NOTES_REGISTRY_FILE, NOTES_REGISTRY_BACKUP_FILE] {
        let path = directory.join(name);
        if path_exists(&path)? {
            let quarantined =
                directory.join(format!("{name}.invalid-{}", Uuid::new_v4().hyphenated()));
            fs::rename(path, quarantined).map_err(io_error)?;
        }
    }
    Ok(())
}

fn load_registry_file(path: &Path) -> Result<RegistryFile, ApiError> {
    let metadata = fs::symlink_metadata(path).map_err(io_error)?;
    if !metadata.is_file() || metadata.len() == 0 || metadata.len() > MAX_REGISTRY_BYTES {
        return Err(ApiError::new(
            "invalid_registry",
            "The Notes registry is invalid",
        ));
    }
    let bytes = fs::read(path).map_err(io_error)?;
    let header = serde_json::from_slice::<RegistryHeader>(&bytes)
        .map_err(|_| ApiError::new("invalid_registry", "The Notes registry is invalid"))?;
    if header.schema_version != NOTES_REGISTRY_SCHEMA_VERSION {
        return Err(ApiError::new(
            "incompatible_registry",
            "This version of Ensu cannot use the existing Notes registry",
        ));
    }
    serde_json::from_slice(&bytes)
        .map_err(|_| ApiError::new("invalid_registry", "The Notes registry is invalid"))
}

fn publish_registry(directory: &Path, registry: &RegistryFile) -> Result<(), ApiError> {
    let active = directory.join(NOTES_REGISTRY_FILE);
    let backup = directory.join(NOTES_REGISTRY_BACKUP_FILE);
    if path_exists(&backup)? {
        remove_owned_entry(&backup)?;
    }
    let temporary = directory.join(format!(".collections.tmp-{}", Uuid::new_v4().hyphenated()));
    let mut bytes = serde_json::to_vec_pretty(registry)
        .map_err(|_| ApiError::new("json", "The Notes registry could not be written"))?;
    bytes.push(b'\n');
    write_new_file(&temporary, &bytes)?;
    load_registry_file(&temporary)?;
    let had_active = path_exists(&active)?;
    if had_active {
        fs::rename(&active, &backup).map_err(io_error)?;
    }
    if let Err(error) = fs::rename(&temporary, &active) {
        if had_active && path_exists(&backup).unwrap_or(false) {
            let _ = fs::rename(&backup, &active);
        }
        let _ = fs::remove_file(&temporary);
        return Err(io_error(error));
    }
    if path_exists(&backup)? {
        remove_owned_entry(&backup)?;
    }
    Ok(())
}

fn recover_registry_publication(directory: &Path) -> Result<(), ApiError> {
    let active = directory.join(NOTES_REGISTRY_FILE);
    let backup = directory.join(NOTES_REGISTRY_BACKUP_FILE);
    match (path_exists(&active)?, path_exists(&backup)?) {
        (false, true) => {
            load_valid_registry_file(&backup)?;
            fs::rename(&backup, &active).map_err(io_error)?;
        }
        (true, true) => match load_valid_registry_file(&active) {
            Ok(_) => remove_owned_entry(&backup)?,
            Err(error) if error.name == Some("incompatible_registry") => return Err(error),
            Err(_) => {
                load_valid_registry_file(&backup)?;
                remove_owned_entry(&active)?;
                fs::rename(&backup, &active).map_err(io_error)?;
            }
        },
        _ => {}
    }
    for entry in fs::read_dir(directory).map_err(io_error)? {
        let entry = entry.map_err(io_error)?;
        if entry
            .file_name()
            .to_string_lossy()
            .starts_with(".collections.tmp-")
        {
            remove_owned_entry(&entry.path())?;
        }
    }
    Ok(())
}

fn write_new_file(path: &Path, bytes: &[u8]) -> Result<(), ApiError> {
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    options.mode(0o600);
    let mut file = options.open(path).map_err(io_error)?;
    file.write_all(bytes).map_err(io_error)?;
    file.sync_all().map_err(io_error)
}

#[cfg(test)]
mod tests {
    use super::*;

    const COLLECTION_ID: &str = "123e4567-e89b-12d3-a456-426614174000";

    fn registry_with_source(source_root: PathBuf) -> RegistryFile {
        RegistryFile {
            schema_version: NOTES_REGISTRY_SCHEMA_VERSION,
            collections: vec![RegisteredCollection {
                id: COLLECTION_ID.to_string(),
                source_root,
            }],
        }
    }

    #[test]
    fn recovers_interrupted_registry_publications() {
        let backup_only = TestDirectory::new();
        let source_root = backup_only.path().join("source");
        fs::create_dir(&source_root).unwrap();
        let registry = registry_with_source(fs::canonicalize(source_root).unwrap());
        publish_registry(backup_only.path(), &registry).unwrap();
        let active = backup_only.path().join(NOTES_REGISTRY_FILE);
        let backup = backup_only.path().join(NOTES_REGISTRY_BACKUP_FILE);
        fs::rename(&active, &backup).unwrap();
        recover_registry_publication(backup_only.path()).unwrap();
        assert_eq!(
            load_valid_registry_file(&active).unwrap().collections[0].id,
            COLLECTION_ID
        );
        assert!(!backup.exists());

        let valid_active = TestDirectory::new();
        let source_root = valid_active.path().join("source");
        fs::create_dir(&source_root).unwrap();
        let registry = registry_with_source(fs::canonicalize(source_root).unwrap());
        publish_registry(valid_active.path(), &registry).unwrap();
        let active = valid_active.path().join(NOTES_REGISTRY_FILE);
        let backup = valid_active.path().join(NOTES_REGISTRY_BACKUP_FILE);
        let temporary = valid_active.path().join(".collections.tmp-abandoned");
        fs::copy(&active, &backup).unwrap();
        fs::write(&temporary, b"incomplete").unwrap();
        let expected = fs::read(&active).unwrap();
        recover_registry_publication(valid_active.path()).unwrap();
        assert_eq!(fs::read(&active).unwrap(), expected);
        assert!(!backup.exists());
        assert!(!temporary.exists());

        let corrupt_active = TestDirectory::new();
        let source_root = corrupt_active.path().join("source");
        fs::create_dir(&source_root).unwrap();
        let registry = registry_with_source(fs::canonicalize(source_root).unwrap());
        publish_registry(corrupt_active.path(), &registry).unwrap();
        let active = corrupt_active.path().join(NOTES_REGISTRY_FILE);
        let backup = corrupt_active.path().join(NOTES_REGISTRY_BACKUP_FILE);
        let expected = fs::read(&active).unwrap();
        fs::copy(&active, &backup).unwrap();
        fs::write(&active, b"not a registry").unwrap();
        recover_registry_publication(corrupt_active.path()).unwrap();
        assert_eq!(fs::read(&active).unwrap(), expected);
        assert!(!backup.exists());

        let invalid_backup = TestDirectory::new();
        fs::write(
            invalid_backup.path().join(NOTES_REGISTRY_BACKUP_FILE),
            b"invalid",
        )
        .unwrap();
        assert!(recover_registry_publication(invalid_backup.path()).is_err());
        assert!(!invalid_backup.path().join(NOTES_REGISTRY_FILE).exists());
    }
}
