use std::fs;
use std::path::{Path, PathBuf};

use ente_model_download::download::{self, Downloader, Progress, Target};

use crate::config::{
    KNOWLEDGE_ARTIFACT_FILENAMES, KnowledgeDatasetConfig, is_path_safe_component,
    knowledge_artifact_urls,
};

use super::{RetrievalError, index::RetrievalIndex};

pub fn download_knowledge_pack(
    pack_root: impl AsRef<Path>,
    expected_pack: &KnowledgeDatasetConfig,
    on_progress: impl FnMut(Progress) + Send,
    cancellation: download::CancellationToken,
) -> Result<(), download::Error> {
    let pack_root = pack_root.as_ref();
    let targets = knowledge_download_targets(pack_root, expected_pack)?;
    tokio::runtime::Builder::new_current_thread()
        .enable_io()
        .enable_time()
        .build()?
        .block_on(Downloader::new()?.download(targets, on_progress, cancellation))
}

fn knowledge_download_targets(
    pack_root: &Path,
    expected_pack: &KnowledgeDatasetConfig,
) -> Result<Vec<Target>, download::Error> {
    let root_identity = pack_root
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| {
            download::Error::InvalidTarget(
                "knowledge pack root must have a UTF-8 stable ID".to_string(),
            )
        })?;
    if root_identity != expected_pack.stable_id {
        return Err(download::Error::InvalidTarget(
            "knowledge pack root must end with the selected stable ID".to_string(),
        ));
    }
    fs::create_dir_all(pack_root)?;
    if !fs::symlink_metadata(pack_root)?.file_type().is_dir() {
        return Err(download::Error::InvalidTarget(
            "knowledge pack root must be a directory, not a symlink".to_string(),
        ));
    }
    let revision_directory = pack_root.join(&expected_pack.current_download_identity);
    fs::create_dir_all(&revision_directory)?;
    if !fs::symlink_metadata(&revision_directory)?
        .file_type()
        .is_dir()
    {
        return Err(download::Error::InvalidTarget(
            "knowledge revision path must be a directory, not a symlink".to_string(),
        ));
    }

    let urls = knowledge_artifact_urls(expected_pack);
    Ok(KNOWLEDGE_ARTIFACT_FILENAMES
        .into_iter()
        .zip(urls)
        .zip(expected_pack.artifact_sha256.iter().cloned())
        .map(|((filename, url), sha256)| Target {
            label: filename.to_owned(),
            url,
            sha256,
            destination: revision_directory.join(filename),
        })
        .collect())
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KnowledgeReconciliationStatus {
    Download,
    Ready,
    UpdateAvailable,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KnowledgeReconciliation {
    pub status: KnowledgeReconciliationStatus,
    pub active_identity: Option<String>,
    pub active_directory: Option<String>,
}

pub fn reconcile_knowledge_pack(
    pack_root: impl AsRef<Path>,
    expected_pack: &KnowledgeDatasetConfig,
) -> Result<KnowledgeReconciliation, RetrievalError> {
    let pack_root = pack_root.as_ref();
    validate_pack_root(pack_root, expected_pack, true)?;

    let mut valid = Vec::<(String, PathBuf)>::new();
    let mut invalid = Vec::<PathBuf>::new();
    for entry in fs::read_dir(pack_root)? {
        let entry = match entry {
            Ok(entry) => entry,
            Err(_) => continue,
        };
        let file_type = match entry.file_type() {
            Ok(file_type) => file_type,
            Err(_) => continue,
        };
        if !file_type.is_dir() {
            continue;
        }
        let path = entry.path();
        match RetrievalIndex::open(&path, expected_pack) {
            Ok(index) => valid.push((index.dataset_identity().to_owned(), path)),
            Err(_) => invalid.push(path),
        }
    }

    let current_position = valid
        .iter()
        .position(|(identity, _)| identity == &expected_pack.current_download_identity);
    let active = if let Some(position) = current_position {
        Some(valid.swap_remove(position))
    } else {
        valid.sort_by(|left, right| right.0.cmp(&left.0));
        (!valid.is_empty()).then(|| valid.remove(0))
    };

    for path in &invalid {
        let _ = fs::remove_dir_all(path);
    }

    match active {
        Some((identity, directory)) => {
            cleanup_revision_artifacts(&directory);
            let status = if identity == expected_pack.current_download_identity {
                KnowledgeReconciliationStatus::Ready
            } else {
                KnowledgeReconciliationStatus::UpdateAvailable
            };
            Ok(KnowledgeReconciliation {
                status,
                active_identity: Some(identity),
                active_directory: Some(directory.display().to_string()),
            })
        }
        None => Ok(KnowledgeReconciliation {
            status: KnowledgeReconciliationStatus::Download,
            active_identity: None,
            active_directory: None,
        }),
    }
}

pub fn cleanup_obsolete_knowledge_pack_revisions(
    pack_root: impl AsRef<Path>,
    expected_pack: &KnowledgeDatasetConfig,
    active_identity: &str,
) -> Result<(), RetrievalError> {
    if !is_path_safe_component(active_identity) {
        return Err(RetrievalError::InvalidInput(
            "active knowledge revision identity is not path-safe".to_string(),
        ));
    }

    let pack_root = pack_root.as_ref();
    validate_pack_root(pack_root, expected_pack, false)?;

    let active_directory = pack_root.join(active_identity);
    RetrievalIndex::open(&active_directory, expected_pack)?;

    for entry in fs::read_dir(pack_root)?.flatten() {
        let Ok(file_type) = entry.file_type() else {
            continue;
        };
        if file_type.is_dir() && entry.file_name().to_str() != Some(active_identity) {
            let _ = fs::remove_dir_all(entry.path());
        }
    }
    cleanup_revision_artifacts(&active_directory);
    Ok(())
}

fn validate_pack_root(
    pack_root: &Path,
    expected_pack: &KnowledgeDatasetConfig,
    create: bool,
) -> Result<(), RetrievalError> {
    let root_identity = pack_root
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| {
            RetrievalError::InvalidInput("pack root must have a UTF-8 stable ID".to_string())
        })?;
    if root_identity != expected_pack.stable_id || !is_path_safe_component(root_identity) {
        return Err(RetrievalError::InvalidInput(
            "pack root must end with the selected stable dataset ID".to_string(),
        ));
    }
    if create {
        fs::create_dir_all(pack_root)?;
    }
    if !fs::symlink_metadata(pack_root)?.file_type().is_dir() {
        return Err(RetrievalError::InvalidInput(
            "pack root must be a directory, not a symlink".to_string(),
        ));
    }
    Ok(())
}

fn cleanup_revision_artifacts(directory: &Path) {
    let Ok(entries) = fs::read_dir(directory) else {
        return;
    };
    for entry in entries.flatten() {
        if entry
            .file_name()
            .to_str()
            .is_some_and(|name| KNOWLEDGE_ARTIFACT_FILENAMES.contains(&name))
        {
            continue;
        }
        let path = entry.path();
        match entry.file_type() {
            Ok(file_type) if file_type.is_dir() => {
                let _ = fs::remove_dir_all(path);
            }
            Ok(_) => {
                let _ = fs::remove_file(path);
            }
            Err(_) => {}
        }
    }
}

#[cfg(test)]
mod tests {
    use std::fs;

    use super::*;
    use crate::config::defaults;
    use crate::retrieval::index::tests::synthetic_pack;

    #[test]
    fn constructs_only_the_four_fixed_download_targets() {
        let temp = tempfile::tempdir().unwrap();
        let expected = defaults().knowledge_datasets.remove(0);
        let pack_root = temp.path().join(&expected.stable_id);
        let targets = knowledge_download_targets(&pack_root, &expected).unwrap();
        assert_eq!(targets.len(), 4);
        for (target, filename) in targets.iter().zip(KNOWLEDGE_ARTIFACT_FILENAMES) {
            assert!(target.url.ends_with(filename));
            assert!(target.destination.ends_with(filename));
            assert!(
                target
                    .destination
                    .to_string_lossy()
                    .contains(&expected.current_download_identity)
            );
            assert_eq!(target.sha256.len(), 64);
        }
    }

    #[test]
    fn retains_a_non_current_revision_and_reports_update() {
        let pack = synthetic_pack("simplewiki-old");
        let invalid_current = pack
            .pack_root
            .join(&pack.expected.current_download_identity);
        fs::create_dir_all(&invalid_current).unwrap();

        let result = reconcile_knowledge_pack(&pack.pack_root, &pack.expected).unwrap();
        assert_eq!(
            result.status,
            KnowledgeReconciliationStatus::UpdateAvailable
        );
        assert_eq!(result.active_identity.as_deref(), Some("simplewiki-old"));
        assert!(!invalid_current.exists());
        assert!(pack.revision.exists());
    }

    #[test]
    fn current_revision_wins_and_artifacts_are_removed() {
        let old = synthetic_pack("simplewiki-old");
        let current_identity = old.expected.current_download_identity.clone();
        let current = old.pack_root.join(&current_identity);
        copy_dir(&old.revision, &current);
        let mut manifest: serde_json::Value =
            serde_json::from_slice(&fs::read(current.join("manifest.json")).unwrap()).unwrap();
        manifest["dataset"] = serde_json::Value::String(current_identity.clone());
        fs::write(
            current.join("manifest.json"),
            serde_json::to_vec(&manifest).unwrap(),
        )
        .unwrap();
        fs::write(current.join("manifest.json.metadata.json"), "sidecar").unwrap();
        fs::create_dir(current.join("orphan")).unwrap();

        let result = reconcile_knowledge_pack(&old.pack_root, &old.expected).unwrap();
        assert_eq!(result.status, KnowledgeReconciliationStatus::Ready);
        assert_eq!(
            result.active_identity.as_deref(),
            Some(current_identity.as_str())
        );
        cleanup_obsolete_knowledge_pack_revisions(&old.pack_root, &old.expected, &current_identity)
            .unwrap();
        assert!(!old.revision.exists());
        assert!(!current.join("manifest.json.metadata.json").exists());
        assert!(!current.join("orphan").exists());
        let retained = fs::read_dir(current)
            .unwrap()
            .map(|entry| entry.unwrap().file_name().into_string().unwrap())
            .collect::<std::collections::HashSet<_>>();
        assert_eq!(
            retained,
            KNOWLEDGE_ARTIFACT_FILENAMES
                .map(str::to_owned)
                .into_iter()
                .collect()
        );
    }

    #[test]
    fn no_valid_revision_reports_download_and_cleans_invalid_directories() {
        let pack = synthetic_pack("simplewiki-old");
        fs::remove_file(pack.revision.join("vectors.i8")).unwrap();
        let result = reconcile_knowledge_pack(&pack.pack_root, &pack.expected).unwrap();
        assert_eq!(result.status, KnowledgeReconciliationStatus::Download);
        assert!(!pack.revision.exists());
    }

    fn copy_dir(source: &Path, destination: &Path) {
        fs::create_dir_all(destination).unwrap();
        for entry in fs::read_dir(source).unwrap() {
            let entry = entry.unwrap();
            fs::copy(entry.path(), destination.join(entry.file_name())).unwrap();
        }
    }
}
