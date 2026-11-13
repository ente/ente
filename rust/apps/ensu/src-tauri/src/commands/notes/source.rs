use std::collections::BTreeSet;
use std::fs::{self, File, Metadata};
use std::io::Read;
#[cfg(unix)]
use std::os::unix::ffi::OsStrExt;
use std::path::{Component, Path, PathBuf};

use ente_ensu::notes::{
    NOTES_MAX_COLLECTION_DOCUMENTS, NOTES_MAX_COLLECTION_SOURCE_BYTES, NOTES_MAX_SOURCE_BYTES,
    NotesSourceDocument, validate_document_id,
};

use crate::commands::common::ApiError;

use super::registry::RegisteredCollection;
use super::{NOTES_MAX_SCAN_ENTRIES, remove_owned_entry, source_scan_error, system_time_ms};

#[cfg(any(windows, test))]
mod scoped;

pub(super) fn inventory_source_root(
    root: &Path,
    check_for_cancellation: impl FnMut() -> Result<(), ApiError>,
) -> Result<Vec<NotesSourceDocument>, ApiError> {
    let mut documents = Vec::new();
    let mut source_bytes = 0_u64;
    walk_source_tree(
        root,
        check_for_cancellation,
        || {
            ApiError::new(
                "collection_too_large",
                "The folder contains too many filesystem entries to scan",
            )
        },
        |_| Ok(()),
        |path, metadata| {
            if !metadata.is_file() || !is_supported_file(path) {
                return Ok(());
            }
            if metadata.len() > NOTES_MAX_SOURCE_BYTES as u64 {
                return Ok(());
            }
            let Some(document_id) = relative_document_id(root, path) else {
                return Ok(());
            };
            let modified_at_ms = metadata.modified().ok().and_then(system_time_ms);
            if documents.len() >= NOTES_MAX_COLLECTION_DOCUMENTS {
                return Err(ApiError::new(
                    "collection_too_large",
                    "The folder contains too many notes to index",
                ));
            }
            source_bytes = source_bytes.checked_add(metadata.len()).ok_or_else(|| {
                ApiError::new(
                    "collection_too_large",
                    "The folder contains too much note content to index",
                )
            })?;
            if source_bytes > NOTES_MAX_COLLECTION_SOURCE_BYTES {
                return Err(ApiError::new(
                    "collection_too_large",
                    "The folder contains too much note content to index",
                ));
            }
            documents.push(NotesSourceDocument {
                document_id,
                size: metadata.len(),
                modified_at_ms,
            });
            Ok(())
        },
    )?;
    documents.sort_by(|left, right| left.document_id.cmp(&right.document_id));
    Ok(documents)
}

pub(super) fn walk_source_tree(
    root: &Path,
    mut check_for_cancellation: impl FnMut() -> Result<(), ApiError>,
    entry_limit_error: impl Fn() -> ApiError,
    mut visit_directory: impl FnMut(&Path) -> Result<(), ApiError>,
    mut visit_file: impl FnMut(&Path, &Metadata) -> Result<(), ApiError>,
) -> Result<(), ApiError> {
    let mut pending = vec![root.to_path_buf()];
    let mut visited_entries = 0_usize;
    while let Some(directory) = pending.pop() {
        check_for_cancellation()?;
        let metadata = fs::symlink_metadata(&directory).map_err(source_scan_error)?;
        if metadata.file_type().is_symlink() || !metadata.is_dir() {
            continue;
        }
        visit_directory(&directory)?;
        for entry in fs::read_dir(&directory).map_err(source_scan_error)? {
            check_for_cancellation()?;
            visited_entries = visited_entries.saturating_add(1);
            if visited_entries > NOTES_MAX_SCAN_ENTRIES {
                return Err(entry_limit_error());
            }
            let entry = entry.map_err(source_scan_error)?;
            let name = entry.file_name();
            if name.to_str().is_none_or(|name| name.starts_with('.')) {
                continue;
            }
            let path = entry.path();
            let metadata = fs::symlink_metadata(&path).map_err(source_scan_error)?;
            if metadata.file_type().is_symlink() {
                continue;
            }
            if metadata.is_dir() {
                pending.push(path);
            } else if metadata.is_file() {
                visit_file(&path, &metadata)?;
            }
        }
    }
    Ok(())
}

pub(super) fn relative_document_id(root: &Path, path: &Path) -> Option<String> {
    let document_id = path
        .strip_prefix(root)
        .ok()?
        .components()
        .map(|component| match component {
            Component::Normal(value) => value.to_str(),
            _ => None,
        })
        .collect::<Option<Vec<_>>>()?
        .join("/");
    validate_document_id(&document_id)
        .is_ok()
        .then_some(document_id)
}

fn read_supported_source_file(mut file: File) -> Result<(Vec<u8>, Metadata), ApiError> {
    let initial_metadata = file.metadata().map_err(source_file_error)?;
    if !initial_metadata.is_file() || initial_metadata.len() > NOTES_MAX_SOURCE_BYTES as u64 {
        return Err(ApiError::new(
            "invalid_document",
            "Source note is not supported",
        ));
    }
    let mut bytes = Vec::with_capacity(initial_metadata.len() as usize);
    (&mut file)
        .take(NOTES_MAX_SOURCE_BYTES as u64 + 1)
        .read_to_end(&mut bytes)
        .map_err(source_file_error)?;
    if bytes.len() > NOTES_MAX_SOURCE_BYTES {
        return Err(ApiError::new(
            "invalid_document",
            "Source note is too large",
        ));
    }
    let metadata = file.metadata().map_err(source_file_error)?;
    if metadata.len() != bytes.len() as u64
        || metadata.len() != initial_metadata.len()
        || metadata.modified().ok() != initial_metadata.modified().ok()
    {
        return Err(ApiError::new(
            "source_changed",
            "Source note changed while it was being indexed",
        ));
    }
    Ok((bytes, metadata))
}

pub(super) fn read_collection_source(
    root: &Path,
    document_id: &str,
) -> Result<(PathBuf, Vec<u8>, NotesSourceDocument), ApiError> {
    validate_document_id(document_id)
        .map_err(|_| ApiError::new("invalid_document", "Invalid note document ID"))?;
    let mut path = root.to_path_buf();
    for component in document_id.split('/') {
        path.push(component);
    }
    let file = open_collection_source(root, document_id, &path)?;
    let (bytes, metadata) = read_supported_source_file(file)?;
    let source = NotesSourceDocument {
        document_id: document_id.to_string(),
        size: metadata.len(),
        modified_at_ms: metadata.modified().ok().and_then(system_time_ms),
    };
    Ok((path, bytes, source))
}

#[cfg(unix)]
fn open_collection_source(root: &Path, document_id: &str, _path: &Path) -> Result<File, ApiError> {
    use rustix::fs::{Mode, OFlags, fcntl_getfl, fcntl_setfl, open, openat};
    use std::ffi::CString;

    let root = CString::new(root.as_os_str().as_bytes())
        .map_err(|_| ApiError::new("invalid_document", "Source note path is not allowed"))?;
    let directory_flags = OFlags::RDONLY | OFlags::DIRECTORY | OFlags::CLOEXEC | OFlags::NOFOLLOW;
    let mut directory =
        open(root.as_c_str(), directory_flags, Mode::empty()).map_err(scoped_open_error)?;
    let components = document_id.split('/').collect::<Vec<_>>();
    for component in &components[..components.len().saturating_sub(1)] {
        directory = openat(&directory, *component, directory_flags, Mode::empty())
            .map_err(scoped_open_error)?;
    }
    let file = File::from(
        openat(
            &directory,
            components.last().copied().unwrap_or_default(),
            OFlags::RDONLY | OFlags::CLOEXEC | OFlags::NOFOLLOW | OFlags::NONBLOCK,
            Mode::empty(),
        )
        .map_err(scoped_open_error)?,
    );
    if !file.metadata().map_err(source_file_error)?.is_file() {
        return Err(ApiError::new(
            "invalid_document",
            "Source note is not supported",
        ));
    }
    let flags = fcntl_getfl(&file).map_err(|error| source_file_error(error.into()))?;
    fcntl_setfl(&file, flags & !OFlags::NONBLOCK)
        .map_err(|error| source_file_error(error.into()))?;
    Ok(file)
}

#[cfg(unix)]
fn scoped_open_error(error: rustix::io::Errno) -> ApiError {
    if matches!(error, rustix::io::Errno::LOOP | rustix::io::Errno::NOTDIR) {
        ApiError::new("invalid_document", "Source note path is not allowed")
    } else {
        source_file_error(error.into())
    }
}

#[cfg(windows)]
fn open_collection_source(root: &Path, document_id: &str, _path: &Path) -> Result<File, ApiError> {
    scoped::open(root, document_id).map_err(windows_source_file_error)
}

#[cfg(any(windows, test))]
fn windows_source_file_error(error: std::io::Error) -> ApiError {
    if error.kind() == std::io::ErrorKind::PermissionDenied && error.raw_os_error().is_none() {
        ApiError::new("invalid_document", "Source note path is not allowed")
    } else {
        source_file_error(error)
    }
}

fn source_file_error(error: std::io::Error) -> ApiError {
    if error.kind() == std::io::ErrorKind::NotFound {
        ApiError::new(
            "source_changed",
            "Source note changed while it was being indexed",
        )
    } else {
        ApiError::new("source_io", "Source note could not be read")
    }
}

pub(super) fn canonical_source_root(path: &Path) -> Result<PathBuf, ApiError> {
    if path.as_os_str().is_empty() {
        return Err(ApiError::new("invalid_folder", "Choose a Notes folder"));
    }
    let metadata = fs::symlink_metadata(path)
        .map_err(|_| ApiError::new("unavailable", "The selected folder is unavailable"))?;
    if !metadata.is_dir() {
        return Err(ApiError::new(
            "invalid_folder",
            "Choose a folder, not a file",
        ));
    }
    let canonical = fs::canonicalize(path)
        .map_err(|_| ApiError::new("unavailable", "The selected folder is unavailable"))?;
    if canonical.to_str().is_none() {
        return Err(ApiError::new(
            "invalid_folder",
            "The selected folder name is not supported",
        ));
    }
    Ok(canonical)
}

pub(super) fn compact_source_location(root: &Path) -> String {
    root.file_name()
        .and_then(|name| name.to_str())
        .filter(|name| !name.is_empty())
        .unwrap_or("Selected folder")
        .to_string()
}

pub(super) fn validate_new_source_root(
    collections: &[RegisteredCollection],
    source_root: &Path,
) -> Result<(), ApiError> {
    for existing in collections {
        if source_root == existing.source_root {
            return Err(ApiError::new(
                "duplicate",
                "That folder is already in Your Notes",
            ));
        }
        if source_root.starts_with(&existing.source_root)
            || existing.source_root.starts_with(source_root)
        {
            return Err(ApiError::new(
                "nested",
                "Notes collection folders must not contain one another",
            ));
        }
    }
    Ok(())
}

pub(super) fn cleanup_unregistered_indexes(
    index_root: &Path,
    collections: &[RegisteredCollection],
) {
    let registered = collections
        .iter()
        .map(|collection| collection.id.as_str())
        .collect::<BTreeSet<_>>();
    let Ok(entries) = fs::read_dir(index_root) else {
        return;
    };
    for entry in entries.flatten() {
        let name = entry.file_name();
        let Some(name) = name.to_str() else { continue };
        if registered.contains(name) {
            continue;
        }
        if let Err(error) = remove_owned_entry(&entry.path()) {
            crate::logging::log(
                "Notes",
                format!(
                    "could not clean unregistered derived index path={} error={}",
                    entry.path().display(),
                    error.message
                ),
            );
        }
    }
}

pub(super) fn is_supported_file(path: &Path) -> bool {
    path.extension()
        .and_then(|extension| extension.to_str())
        .is_some_and(|extension| {
            matches!(extension.to_ascii_lowercase().as_str(), "md" | "markdown")
        })
}

pub(super) fn source_root_is_available(source_root: &Path) -> bool {
    canonical_source_root(source_root).is_ok_and(|canonical| canonical == source_root)
}

#[cfg(test)]
mod tests {
    use super::super::TestDirectory;
    use super::*;

    #[test]
    fn windows_source_errors_distinguish_io_failures_from_escaped_paths() {
        let denied = std::io::Error::new(std::io::ErrorKind::PermissionDenied, "escaped path");
        assert_eq!(
            windows_source_file_error(denied).name,
            Some("invalid_document")
        );
        for code in [5, 13] {
            let error = std::io::Error::from_raw_os_error(code);
            assert_eq!(windows_source_file_error(error).name, Some("source_io"));
        }
        let missing = std::io::Error::from(std::io::ErrorKind::NotFound);
        assert_eq!(
            windows_source_file_error(missing).name,
            Some("source_changed")
        );
    }

    #[test]
    fn collection_reads_literal_reserved_windows_filenames() {
        let temp = TestDirectory::new();
        let root = fs::canonicalize(temp.path()).unwrap();
        for name in ["con.md", "aux.notes.md", "com¹.md"] {
            fs::write(root.join(name), name).unwrap();
            let (_, bytes, source) = read_collection_source(&root, name).unwrap();
            assert_eq!(bytes, name.as_bytes());
            assert_eq!(source.document_id, name);
        }
        assert_eq!(inventory_source_root(&root, || Ok(())).unwrap().len(), 3);
    }

    #[cfg(windows)]
    #[test]
    fn collection_read_rejects_directory_and_root_junction_swaps() {
        let temp = TestDirectory::new();
        let root = temp.path().join("root");
        let outside = temp.path().join("outside");
        fs::create_dir_all(root.join("nested")).unwrap();
        fs::create_dir(&outside).unwrap();
        fs::write(root.join("nested/note.md"), "inside").unwrap();
        fs::write(outside.join("note.md"), "outside").unwrap();
        let root = fs::canonicalize(root).unwrap();
        assert_eq!(
            read_collection_source(&root, "nested/note.md").unwrap().1,
            b"inside"
        );
        fs::remove_file(root.join("nested/note.md")).unwrap();
        fs::remove_dir(root.join("nested")).unwrap();
        let junction = |path: &Path| {
            assert!(
                std::process::Command::new("cmd")
                    .args(["/C", "mklink", "/J"])
                    .arg(path)
                    .arg(&outside)
                    .status()
                    .unwrap()
                    .success()
            );
        };
        junction(&root.join("nested"));
        assert_eq!(
            read_collection_source(&root, "nested/note.md")
                .unwrap_err()
                .name,
            Some("invalid_document")
        );
        fs::rename(&root, temp.path().join("original-root")).unwrap();
        junction(&root);
        assert_eq!(
            read_collection_source(&root, "note.md").unwrap_err().name,
            Some("invalid_document")
        );
    }

    #[cfg(unix)]
    #[test]
    fn collection_read_rejects_symlink_swaps() {
        use std::os::unix::fs::symlink;

        let temp = TestDirectory::new();
        let root = temp.path().join("root");
        let nested = root.join("nested");
        let outside = temp.path().join("outside");
        fs::create_dir_all(&nested).unwrap();
        fs::create_dir(&outside).unwrap();
        fs::write(nested.join("note.md"), "inside").unwrap();
        fs::write(outside.join("note.md"), "outside").unwrap();
        let root = fs::canonicalize(root).unwrap();
        let inventory = inventory_source_root(&root, || Ok(())).unwrap();
        assert_eq!(inventory.len(), 1);
        let (_, bytes, _) = read_collection_source(&root, "nested/note.md").unwrap();
        assert_eq!(bytes, b"inside");

        fs::remove_file(root.join("nested/note.md")).unwrap();
        symlink(outside.join("note.md"), root.join("nested/note.md")).unwrap();
        let error = read_collection_source(&root, "nested/note.md").unwrap_err();
        assert_eq!(error.name, Some("invalid_document"));

        fs::remove_file(root.join("nested/note.md")).unwrap();
        fs::remove_dir(root.join("nested")).unwrap();
        symlink(&outside, root.join("nested")).unwrap();

        let error = read_collection_source(&root, "nested/note.md").unwrap_err();
        assert_eq!(error.name, Some("invalid_document"));
    }
}
