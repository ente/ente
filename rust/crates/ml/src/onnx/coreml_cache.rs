use std::path::{Path, PathBuf};

#[cfg(any(target_os = "ios", target_os = "macos", test))]
const SCHEMA: &str = "ort-1_28-mlprogram-all-default-v1";
const COMPLETE_MARKER: &str = ".ente-cache-complete";
const COMPILED_MODEL: &str = "compiled_model.mlmodelc";
const PACKAGE_WEIGHT_BLOB: &str = "weight.bin";

#[cfg(any(target_os = "ios", target_os = "macos"))]
pub(super) fn prepare_directory(
    model_path: &str,
    model_namespace: &str,
) -> std::io::Result<PathBuf> {
    let model_path = Path::new(model_path);
    let schema_root = cache_root(model_path);

    if let Some(coreml_root) = schema_root.parent() {
        match prune_stale_schema_directories(coreml_root, SCHEMA) {
            Ok(removed) => {
                for schema in removed {
                    log::info!("removed stale CoreML cache schema '{schema}'");
                }
            }
            Err(error) => log::warn!("failed to prune stale CoreML cache schemas: {error}"),
        }
    }

    let model_cache_root = schema_root.join(sanitize_component(model_namespace));
    std::fs::create_dir_all(&model_cache_root)?;

    let cache_key = model_cache_key(model_path)?;
    prune_superseded_directories(&model_cache_root, &cache_key)?;

    let cache_dir = model_cache_root.join(cache_key);
    prepare_entry(&cache_dir)?;
    Ok(cache_dir)
}

#[cfg(any(target_os = "ios", target_os = "macos"))]
pub(super) fn remove(model_path: &str) {
    let Some(coreml_root) = cache_root(Path::new(model_path))
        .parent()
        .map(Path::to_path_buf)
    else {
        return;
    };
    match std::fs::remove_dir_all(&coreml_root) {
        Ok(()) => log::info!("removed persistent CoreML cache (feature disabled)"),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => log::warn!("failed to remove disabled persistent CoreML cache: {error}"),
    }
}

pub(super) fn finalize(cache_dir: &Path, model_path: &str) {
    match trim_weights(cache_dir) {
        Ok(0) => {}
        Ok(reclaimed) => log::info!(
            "primed CoreML cache for '{}': trimmed {} MiB of generated package weights",
            super::model_file_label(model_path),
            reclaimed / (1024 * 1024)
        ),
        Err(error) => log::warn!(
            "failed to trim CoreML cache weights for '{}': {error}",
            super::model_file_label(model_path)
        ),
    }

    if let Err(error) = mark_complete(cache_dir) {
        log::warn!(
            "failed to mark CoreML cache complete for '{}': {error}",
            super::model_file_label(model_path)
        );
    }
}

pub(super) fn invalidate(cache_dir: &Path) -> std::io::Result<()> {
    match std::fs::remove_dir_all(cache_dir) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error),
    }
}

#[cfg(any(target_os = "ios", target_os = "macos", test))]
fn prepare_entry(cache_dir: &Path) -> std::io::Result<()> {
    if cache_dir.exists() && !complete_marker(cache_dir).is_file() {
        std::fs::remove_dir_all(cache_dir)?;
    }
    std::fs::create_dir_all(cache_dir)
}

fn trim_weights(cache_dir: &Path) -> std::io::Result<u64> {
    let mut reclaimed = 0;
    for model_hash_entry in std::fs::read_dir(cache_dir)? {
        let model_hash_entry = model_hash_entry?;
        if !model_hash_entry.file_type()?.is_dir() {
            continue;
        }
        for partition_entry in std::fs::read_dir(model_hash_entry.path())? {
            let partition_entry = partition_entry?;
            if !partition_entry.file_type()?.is_dir() {
                continue;
            }
            let package_dir = partition_entry.path().join("model");
            if !package_dir.is_dir() || !package_dir.join(COMPILED_MODEL).exists() {
                continue;
            }
            reclaimed += truncate_weight_blobs(&package_dir)?;
        }
    }
    Ok(reclaimed)
}

fn truncate_weight_blobs(dir: &Path) -> std::io::Result<u64> {
    let mut reclaimed = 0;
    for entry in std::fs::read_dir(dir)? {
        let entry = entry?;
        let file_type = entry.file_type()?;
        if file_type.is_dir() {
            // Compiled bundles keep the weights needed by warm cache loads.
            if entry.path().extension() == Some(std::ffi::OsStr::new("mlmodelc")) {
                continue;
            }
            reclaimed += truncate_weight_blobs(&entry.path())?;
        } else if file_type.is_file() && entry.file_name() == PACKAGE_WEIGHT_BLOB {
            let size = entry.metadata()?.len();
            if size > 0 {
                std::fs::write(entry.path(), [])?;
                reclaimed += size;
            }
        }
    }
    Ok(reclaimed)
}

fn mark_complete(cache_dir: &Path) -> std::io::Result<()> {
    std::fs::write(complete_marker(cache_dir), [])
}

fn complete_marker(cache_dir: &Path) -> PathBuf {
    cache_dir.join(COMPLETE_MARKER)
}

#[cfg(any(target_os = "ios", target_os = "macos", test))]
fn cache_root(model_path: &Path) -> PathBuf {
    let cache_base = model_path
        .ancestors()
        .find(|ancestor| ancestor.file_name().is_some_and(|name| name == "Library"))
        .map(|library| library.join("Caches"))
        .unwrap_or_else(std::env::temp_dir);

    cache_base
        .join("ente")
        .join("ml")
        .join("coreml")
        .join(SCHEMA)
}

#[cfg(any(target_os = "ios", target_os = "macos", test))]
fn model_cache_key(model_path: &Path) -> std::io::Result<String> {
    use std::time::UNIX_EPOCH;

    let metadata = std::fs::metadata(model_path)?;
    let modified = metadata
        .modified()?
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    Ok(format!(
        "{}-{}-{}-{}",
        sanitize_component(
            model_path
                .file_name()
                .and_then(|name| name.to_str())
                .unwrap_or("model")
        ),
        metadata.len(),
        modified.as_secs(),
        modified.subsec_nanos()
    ))
}

#[cfg(any(target_os = "ios", target_os = "macos", test))]
fn sanitize_component(value: &str) -> String {
    value
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() || matches!(character, '-' | '_' | '.') {
                character
            } else {
                '_'
            }
        })
        .collect()
}

#[cfg(any(target_os = "ios", target_os = "macos", test))]
fn prune_stale_schema_directories(
    coreml_root: &Path,
    current_schema: &str,
) -> std::io::Result<Vec<String>> {
    let mut removed = Vec::new();
    let entries = match std::fs::read_dir(coreml_root) {
        Ok(entries) => entries,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(removed),
        Err(error) => return Err(error),
    };
    for entry in entries {
        let entry = entry?;
        if entry.file_name() == current_schema || !entry.file_type()?.is_dir() {
            continue;
        }
        std::fs::remove_dir_all(entry.path())?;
        removed.push(entry.file_name().to_string_lossy().into_owned());
    }
    Ok(removed)
}

#[cfg(any(target_os = "ios", target_os = "macos", test))]
fn prune_superseded_directories(
    model_cache_root: &Path,
    current_cache_key: &str,
) -> std::io::Result<()> {
    for entry in std::fs::read_dir(model_cache_root)? {
        let entry = entry?;
        if entry.file_name() == current_cache_key || !entry.file_type()?.is_dir() {
            continue;
        }
        std::fs::remove_dir_all(entry.path())?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::{io::Write, path::Path};

    use super::{
        cache_root, invalidate, mark_complete, model_cache_key, prepare_entry,
        prune_stale_schema_directories, prune_superseded_directories, sanitize_component,
        trim_weights,
    };

    #[test]
    fn places_cache_in_library_caches() {
        let model = Path::new(
            "/var/mobile/Containers/Data/Application/APP/Library/Application Support/assets/model.onnx",
        );

        assert_eq!(
            cache_root(model),
            Path::new(
                "/var/mobile/Containers/Data/Application/APP/Library/Caches/ente/ml/coreml/ort-1_28-mlprogram-all-default-v1"
            )
        );
    }

    #[test]
    fn cache_key_changes_when_model_file_changes() {
        let mut model = tempfile::NamedTempFile::new().unwrap();
        model.write_all(b"first").unwrap();
        model.flush().unwrap();
        let first_key = model_cache_key(model.path()).unwrap();

        model.write_all(b" version").unwrap();
        model.flush().unwrap();
        let second_key = model_cache_key(model.path()).unwrap();

        assert_ne!(first_key, second_key);
    }

    #[test]
    fn sanitizes_cache_component() {
        assert_eq!(sanitize_component("model name.onnx"), "model_name.onnx");
    }

    #[test]
    fn prunes_only_superseded_directories_for_one_model() {
        let root = tempfile::tempdir().unwrap();
        let old_cache = root.path().join("old");
        let current_cache = root.path().join("current");
        std::fs::create_dir(&old_cache).unwrap();
        std::fs::create_dir(&current_cache).unwrap();
        std::fs::write(root.path().join("marker"), b"keep").unwrap();

        prune_superseded_directories(root.path(), "current").unwrap();

        assert!(!old_cache.exists());
        assert!(current_cache.exists());
        assert!(root.path().join("marker").exists());
    }

    #[test]
    fn prunes_stale_schema_directories_keeping_current_and_files() {
        let coreml_root = tempfile::tempdir().unwrap();
        let stale = coreml_root.path().join("ort-1_27-mlprogram-all-default-v1");
        let current = coreml_root.path().join("ort-1_28-mlprogram-all-default-v1");
        std::fs::create_dir(&stale).unwrap();
        std::fs::write(stale.join("cached"), b"stale").unwrap();
        std::fs::create_dir(&current).unwrap();
        std::fs::write(coreml_root.path().join("stray-file"), b"keep").unwrap();

        let removed =
            prune_stale_schema_directories(coreml_root.path(), "ort-1_28-mlprogram-all-default-v1")
                .unwrap();

        assert_eq!(removed, vec!["ort-1_27-mlprogram-all-default-v1"]);
        assert!(!stale.exists());
        assert!(current.exists());
        assert!(coreml_root.path().join("stray-file").exists());
    }

    #[test]
    fn schema_pruning_treats_a_missing_root_as_empty() {
        let parent = tempfile::tempdir().unwrap();
        let removed =
            prune_stale_schema_directories(&parent.path().join("missing"), "current").unwrap();
        assert!(removed.is_empty());
    }

    fn write_cache_partition(
        cache_dir: &Path,
        partition: &str,
        compiled: bool,
    ) -> std::path::PathBuf {
        let package_dir = cache_dir.join("modelhash").join(partition).join("model");
        let weights_dir = package_dir
            .join("Data")
            .join("com.microsoft.OnnxRuntime")
            .join("weights");
        std::fs::create_dir_all(&weights_dir).unwrap();
        let weight_blob = weights_dir.join("weight.bin");
        std::fs::write(&weight_blob, b"weights").unwrap();
        std::fs::write(package_dir.join("Manifest.json"), b"manifest").unwrap();
        if compiled {
            let compiled_weights_dir = package_dir.join("compiled_model.mlmodelc").join("weights");
            std::fs::create_dir_all(&compiled_weights_dir).unwrap();
            std::fs::write(compiled_weights_dir.join("weight.bin"), b"compiled-weights").unwrap();
        }
        weight_blob
    }

    #[test]
    fn trims_package_weights_only_where_a_compiled_model_exists() {
        let cache_dir = tempfile::tempdir().unwrap();
        let compiled_blob = write_cache_partition(cache_dir.path(), "0_static_mlprogram", true);
        let uncompiled_blob = write_cache_partition(cache_dir.path(), "1_static_mlprogram", false);
        mark_complete(cache_dir.path()).unwrap();

        let reclaimed = trim_weights(cache_dir.path()).unwrap();

        assert_eq!(reclaimed, b"weights".len() as u64);
        assert!(compiled_blob.exists());
        assert_eq!(std::fs::metadata(&compiled_blob).unwrap().len(), 0);
        let package_dir = compiled_blob.ancestors().nth(4).unwrap();
        assert!(package_dir.ends_with("model"));
        assert!(package_dir.is_dir());
        assert_eq!(
            std::fs::read(
                package_dir
                    .join("compiled_model.mlmodelc")
                    .join("weights")
                    .join("weight.bin")
            )
            .unwrap(),
            b"compiled-weights".to_vec()
        );
        assert_eq!(std::fs::read(uncompiled_blob).unwrap(), b"weights".to_vec());
    }

    #[test]
    fn trimming_an_already_trimmed_cache_reclaims_nothing() {
        let cache_dir = tempfile::tempdir().unwrap();
        write_cache_partition(cache_dir.path(), "0_static_mlprogram", true);

        assert!(trim_weights(cache_dir.path()).unwrap() > 0);
        assert_eq!(trim_weights(cache_dir.path()).unwrap(), 0);
    }

    #[test]
    fn replaces_an_incomplete_cache_entry() {
        let root = tempfile::tempdir().unwrap();
        let cache_dir = root.path().join("current");
        std::fs::create_dir(&cache_dir).unwrap();
        let partial_artifact = cache_dir.join("partial.mlmodelc");
        std::fs::write(&partial_artifact, b"partial").unwrap();

        prepare_entry(&cache_dir).unwrap();

        assert!(cache_dir.is_dir());
        assert!(!partial_artifact.exists());
    }

    #[test]
    fn preserves_a_completed_cache_entry() {
        let root = tempfile::tempdir().unwrap();
        let cache_dir = root.path().join("current");
        std::fs::create_dir(&cache_dir).unwrap();
        let artifact = cache_dir.join("model.mlmodelc");
        std::fs::write(&artifact, b"complete").unwrap();
        mark_complete(&cache_dir).unwrap();

        prepare_entry(&cache_dir).unwrap();

        assert!(artifact.exists());
    }

    #[test]
    fn invalidates_a_failed_cache_entry() {
        let root = tempfile::tempdir().unwrap();
        let cache_dir = root.path().join("current");
        std::fs::create_dir(&cache_dir).unwrap();

        invalidate(&cache_dir).unwrap();

        assert!(!cache_dir.exists());
        invalidate(&cache_dir).unwrap();
    }
}
