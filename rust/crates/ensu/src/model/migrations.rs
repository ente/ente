use std::collections::{HashMap, HashSet};
use std::fs::{self, File};
use std::io::Read;
use std::path::{Path, PathBuf};

use ente_model_download::{ModelDownloader, ModelTarget};
use sha2::{Digest, Sha256};

use crate::config;
use crate::model::{self, InvalidPreset, trimmed};

pub struct LegacyModels {
    pub llm_dir: Option<PathBuf>,
    pub transcription_dir: PathBuf,
    pub model_url: Option<String>,
    pub mmproj_url: Option<String>,
}

pub fn migrate_mobile_models(models_dir: &Path, legacy: LegacyModels) -> Option<String> {
    let store = ModelDownloader::new(models_dir);
    if let Some(llm_dir) = &legacy.llm_dir
        && let Ok(targets) = llm_targets()
    {
        migrate_legacy_dir(&store, llm_dir, &targets);
    }
    migrate_legacy_transcription_dir(
        &store,
        &legacy.transcription_dir,
        &model::transcription_target(),
        &model::voice_activity_target(),
    );
    legacy_selected_preset_id(legacy.model_url.as_deref()?, legacy.mmproj_url.as_deref())
}

pub fn migrate_desktop_models(
    models_dir: &Path,
    model_url: Option<&str>,
    mmproj_url: Option<&str>,
) -> Option<String> {
    let selected = model_url.and_then(|model_url| legacy_selected_preset_id(model_url, mmproj_url));
    if let Ok(targets) = llm_targets() {
        migrate_flat_models_dir(models_dir, &targets);
    }
    selected
}

fn llm_targets() -> Result<Vec<ModelTarget>, InvalidPreset> {
    config::llm_catalog()
        .iter()
        .map(model::llm_target)
        .collect()
}

fn legacy_selected_preset_id(model_url: &str, mmproj_url: Option<&str>) -> Option<String> {
    let mmproj_url = trimmed(mmproj_url);
    config::llm_catalog()
        .into_iter()
        .find(|preset| {
            preset.url == model_url && trimmed(preset.mmproj_url.as_deref()) == mmproj_url
        })
        .map(|preset| preset.id)
}

fn migrate_legacy_dir(store: &ModelDownloader, legacy_dir: &Path, targets: &[ModelTarget]) {
    if !legacy_dir.exists() {
        return;
    }
    if adopt_targets(store, targets, &[], &legacy_dir.join("models")) {
        let _ = fs::remove_dir_all(legacy_dir);
    }
}

fn migrate_flat_models_dir(models_dir: &Path, targets: &[ModelTarget]) {
    if !models_dir.exists() {
        return;
    }
    let store = ModelDownloader::new(models_dir);
    let hashed_dirs = [models_dir.to_path_buf()];
    if !adopt_targets(&store, targets, &hashed_dirs, models_dir) {
        return;
    }
    let Ok(entries) = fs::read_dir(models_dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_file() {
            let _ = fs::remove_file(&path);
        } else if path.file_name().is_some_and(|name| name == "custom") {
            let _ = fs::remove_dir_all(&path);
        }
    }
}

fn migrate_legacy_transcription_dir(
    store: &ModelDownloader,
    legacy_dir: &Path,
    model: &ModelTarget,
    vad: &ModelTarget,
) {
    const LEGACY_MODEL_DIR_NAME: &str = "parakeet-tdt-0.6b-v3-int8";
    const LEGACY_MODEL_ID: &str = "parakeet-v3-int8";
    const LEGACY_VAD_FILE_NAME: &str = "silero_vad_v4.onnx";
    const LEGACY_VAD_ID: &str = "silero-vad-v4";
    if !legacy_dir.exists() {
        return;
    }
    let mut all_moved = true;

    if matches!(model, ModelTarget::TarGz { id, .. } if id == LEGACY_MODEL_ID) {
        let dest = store.model_dir(model);
        if !dest.exists() {
            let source = legacy_dir.join(LEGACY_MODEL_DIR_NAME);
            if source.is_dir() {
                if let Some(parent) = dest.parent() {
                    let _ = fs::create_dir_all(parent);
                }
                if fs::rename(&source, &dest).is_err() {
                    all_moved = false;
                }
            }
        }
    }

    if let ModelTarget::Files { id, files } = vad
        && id == LEGACY_VAD_ID
        && let [file] = files.as_slice()
    {
        let dest = store.model_dir(vad).join(&file.name);
        if !dest.exists() {
            let source = legacy_dir.join(LEGACY_VAD_FILE_NAME);
            if is_non_empty_file(&source) && !move_file(&source, &dest) {
                all_moved = false;
            }
        }
    }

    if all_moved {
        let _ = fs::remove_dir_all(legacy_dir);
    }
}

fn sidecar_url(path: &Path) -> Option<String> {
    let sidecar = PathBuf::from(format!("{}.metadata.json", path.display()));
    let text = fs::read_to_string(sidecar).ok()?;
    let value: serde_json::Value = serde_json::from_str(&text).ok()?;
    value["url"].as_str().map(String::from)
}

fn adopt_targets(
    store: &ModelDownloader,
    targets: &[ModelTarget],
    hashed_dirs: &[PathBuf],
    flat_dir: &Path,
) -> bool {
    let mut plans: Vec<Vec<(&str, &str, PathBuf)>> = Vec::new();
    for target in targets {
        let ModelTarget::Files { files, .. } = target else {
            continue;
        };
        let dir = store.model_dir(target);
        plans.push(
            files
                .iter()
                .map(|file| (file.url.as_str(), file.name.as_str(), dir.join(&file.name)))
                .collect(),
        );
    }

    let mut basename_urls: HashMap<String, HashSet<&str>> = HashMap::new();
    for target in targets {
        let ModelTarget::Files { files, .. } = target else {
            continue;
        };
        for file in files {
            basename_urls
                .entry(filename_for_url(&file.url, &file.name))
                .or_default()
                .insert(file.url.as_str());
        }
    }

    let mut all_moved = true;
    for plan in &plans {
        let sources: Vec<Option<Option<PathBuf>>> = plan
            .iter()
            .map(|(url, fallback, dest)| {
                if dest.exists() {
                    return Some(None);
                }
                let basename = filename_for_url(url, fallback);
                let url = *url;
                for dir in hashed_dirs {
                    let hashed = dir.join(format!("{}_{basename}", sha256_hex(url)));
                    if looks_like_gguf(&hashed) {
                        return Some(Some(hashed));
                    }
                }
                let flat = flat_dir.join(&basename);
                if looks_like_gguf(&flat) {
                    match sidecar_url(&flat) {
                        Some(sidecar) => {
                            if sidecar == url {
                                return Some(Some(flat));
                            }
                        }
                        None => {
                            if basename_urls[&basename].len() == 1 {
                                return Some(Some(flat));
                            }
                        }
                    }
                }
                None
            })
            .collect();
        if sources.iter().any(Option::is_none) {
            continue;
        }
        for ((_, _, dest), source) in plan.iter().zip(sources) {
            let Some(Some(source)) = source else {
                continue;
            };
            if !move_file(&source, dest) {
                all_moved = false;
            }
        }
    }
    all_moved
}

fn move_file(source: &Path, dest: &Path) -> bool {
    if let Some(parent) = dest.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if fs::rename(source, dest).is_ok() {
        return true;
    }
    let staged = PathBuf::from(format!("{}.migrating", dest.display()));
    if fs::copy(source, &staged)
        .and_then(|_| fs::rename(&staged, dest))
        .is_err()
    {
        let _ = fs::remove_file(&staged);
        return false;
    }
    true
}

fn is_non_empty_file(path: &Path) -> bool {
    path.metadata()
        .map(|metadata| metadata.is_file() && metadata.len() > 0)
        .unwrap_or(false)
}

fn looks_like_gguf(path: &Path) -> bool {
    let mut file = match File::open(path) {
        Ok(file) => file,
        Err(_) => return false,
    };
    let mut header = [0u8; 4];
    file.read_exact(&mut header).is_ok() && &header == b"GGUF"
}

fn filename_for_url(url: &str, fallback: &str) -> String {
    let without_query = url.split(['?', '#']).next().unwrap_or(url);
    let name = without_query.rsplit('/').next().unwrap_or("");
    if name.trim().is_empty() {
        fallback.to_string()
    } else {
        name.to_string()
    }
}

fn sha256_hex(value: &str) -> String {
    Sha256::digest(value.as_bytes())
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

#[cfg(test)]
mod tests {
    use ente_model_download::ModelFile;

    use super::*;
    use crate::config::ModelPreset;
    use crate::model;

    fn scratch_dir(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "ente-ensu-migrations-{name}-{}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&dir).expect("create test dir");
        dir
    }

    fn test_sha() -> String {
        "0".repeat(64)
    }

    fn gguf_target(id: &str, url: String, mmproj_url: String) -> ModelTarget {
        model::llm_target(&ModelPreset {
            id: id.to_string(),
            title: String::new(),
            url,
            sha256: test_sha(),
            mmproj_url: Some(mmproj_url),
            mmproj_sha256: Some(test_sha()),
        })
        .unwrap()
    }

    fn target(id: &str) -> ModelTarget {
        gguf_target(
            id,
            "https://example.org/models/main.gguf?download=true".to_string(),
            "https://example.org/models/mmproj.gguf".to_string(),
        )
    }

    fn tar_gz_target(id: &str) -> ModelTarget {
        ModelTarget::TarGz {
            id: id.to_string(),
            url: format!("https://models.example.org/{id}.tar.gz"),
            sha256: test_sha(),
        }
    }

    fn vad_target(id: &str, url: String) -> ModelTarget {
        ModelTarget::Files {
            id: id.to_string(),
            files: vec![ModelFile {
                name: "model.onnx".to_string(),
                url,
                sha256: test_sha(),
            }],
        }
    }

    fn file_target(id: &str) -> ModelTarget {
        vad_target(id, format!("https://models.example.org/{id}.onnx"))
    }

    fn write_gguf(path: &Path, content: &[u8]) {
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, content).unwrap();
    }

    #[test]
    fn mobile_migration_resolves_preset_selection() {
        let base = scratch_dir("mobile-selection");
        let defaults = config::defaults();
        let preset = &defaults.mobile_model_presets[0];
        let selected = migrate_mobile_models(
            &base.join("models"),
            LegacyModels {
                llm_dir: None,
                transcription_dir: base.join("transcription"),
                model_url: Some(preset.url.clone()),
                mmproj_url: preset.mmproj_url.clone(),
            },
        );
        assert_eq!(selected.as_deref(), Some(preset.id.as_str()));

        let unknown = migrate_mobile_models(
            &base.join("models"),
            LegacyModels {
                llm_dir: None,
                transcription_dir: base.join("transcription"),
                model_url: Some("https://example.org/custom.gguf".to_string()),
                mmproj_url: None,
            },
        );
        assert_eq!(unknown, None);

        let _ = fs::remove_dir_all(base);
    }

    #[test]
    fn desktop_migration_resolves_preset_selection() {
        let base = scratch_dir("desktop-selection");
        let defaults = config::defaults();
        let preset = &defaults.desktop_model_presets[0];
        let selected = migrate_desktop_models(
            &base.join("models"),
            Some(&preset.url),
            preset.mmproj_url.as_deref(),
        );
        assert_eq!(selected.as_deref(), Some(preset.id.as_str()));

        assert_eq!(
            migrate_desktop_models(&base.join("models"), None, None),
            None
        );

        let _ = fs::remove_dir_all(base);
    }

    #[test]
    fn migrate_transcription_moves_model_dir_and_vad_file() {
        let base = scratch_dir("migrate-transcription");
        let legacy = base.join("transcription");
        fs::create_dir_all(legacy.join("parakeet-tdt-0.6b-v3-int8")).unwrap();
        fs::write(
            legacy.join("parakeet-tdt-0.6b-v3-int8/encoder.onnx"),
            b"enc",
        )
        .unwrap();
        fs::write(legacy.join("silero_vad_v4.onnx"), b"vad").unwrap();
        fs::write(legacy.join("stale.partial"), b"junk").unwrap();

        let models_dir = base.join("models");
        let model = tar_gz_target("parakeet-v3-int8");
        let vad = vad_target(
            "silero-vad-v4",
            "https://models.example.org/silero_vad_v4.onnx".to_string(),
        );
        migrate_legacy_transcription_dir(&ModelDownloader::new(&models_dir), &legacy, &model, &vad);

        let downloader = ModelDownloader::new(&models_dir);
        assert!(downloader.is_downloaded(&model));
        assert!(downloader.is_downloaded(&vad));
        assert_eq!(
            fs::read(models_dir.join("parakeet-v3-int8/encoder.onnx")).unwrap(),
            b"enc"
        );
        assert_eq!(
            fs::read(models_dir.join("silero-vad-v4/model.onnx")).unwrap(),
            b"vad"
        );
        assert!(!legacy.exists());

        migrate_legacy_transcription_dir(&ModelDownloader::new(&models_dir), &legacy, &model, &vad);
        assert!(downloader.is_downloaded(&model));

        let _ = fs::remove_dir_all(base);
    }

    #[test]
    fn migrate_transcription_keeps_existing_destinations() {
        let base = scratch_dir("migrate-transcription-existing");
        let legacy = base.join("transcription");
        fs::create_dir_all(legacy.join("parakeet-tdt-0.6b-v3-int8")).unwrap();
        fs::write(
            legacy.join("parakeet-tdt-0.6b-v3-int8/encoder.onnx"),
            b"old",
        )
        .unwrap();

        let models_dir = base.join("models");
        let model = tar_gz_target("parakeet-v3-int8");
        let vad = file_target("silero-vad-v4");
        fs::create_dir_all(models_dir.join("parakeet-v3-int8")).unwrap();
        fs::write(models_dir.join("parakeet-v3-int8/encoder.onnx"), b"new").unwrap();

        migrate_legacy_transcription_dir(&ModelDownloader::new(&models_dir), &legacy, &model, &vad);

        assert_eq!(
            fs::read(models_dir.join("parakeet-v3-int8/encoder.onnx")).unwrap(),
            b"new"
        );
        assert!(!legacy.exists());

        let _ = fs::remove_dir_all(base);
    }

    #[test]
    fn migrate_transcription_adopts_nothing_when_target_ids_differ() {
        let base = scratch_dir("migrate-transcription-mismatch");
        let legacy = base.join("transcription");
        fs::create_dir_all(legacy.join("parakeet-tdt-0.6b-v3-int8")).unwrap();
        fs::write(
            legacy.join("parakeet-tdt-0.6b-v3-int8/encoder.onnx"),
            b"enc",
        )
        .unwrap();
        fs::write(legacy.join("silero_vad_v4.onnx"), b"vad").unwrap();

        let models_dir = base.join("models");
        let model = tar_gz_target("parakeet-v4-int8");
        let vad = file_target("silero-vad-v5");
        migrate_legacy_transcription_dir(&ModelDownloader::new(&models_dir), &legacy, &model, &vad);

        let downloader = ModelDownloader::new(&models_dir);
        assert!(!downloader.is_downloaded(&model));
        assert!(!downloader.is_downloaded(&vad));
        assert!(!legacy.exists());

        let _ = fs::remove_dir_all(base);
    }

    #[test]
    fn migrate_adopts_known_files_and_discards_legacy_dir() {
        let base = scratch_dir("migrate");
        let legacy = base.join("llm");
        let legacy_models = legacy.join("models");
        fs::create_dir_all(&legacy_models).unwrap();

        fs::write(legacy_models.join("main.gguf"), b"GGUFmain").unwrap();
        fs::write(legacy_models.join("mmproj.gguf"), b"GGUFmmproj").unwrap();
        fs::write(legacy_models.join("main.gguf.tmp"), b"GGUFpartial").unwrap();
        fs::write(legacy_models.join("main.gguf.metadata.json"), b"{}").unwrap();
        fs::write(legacy_models.join("orphan.gguf"), b"GGUForphan").unwrap();

        let models_dir = base.join("models");
        let preset = target("qwen-2b-q8");
        migrate_legacy_dir(
            &ModelDownloader::new(&models_dir),
            &legacy,
            std::slice::from_ref(&preset),
        );

        let downloader = ModelDownloader::new(&models_dir);
        assert_eq!(
            fs::read(model::llm_model_path(&downloader, &preset).unwrap()).unwrap(),
            b"GGUFmain"
        );
        assert_eq!(
            fs::read(model::llm_mmproj_path(&downloader, &preset).unwrap()).unwrap(),
            b"GGUFmmproj"
        );
        assert_eq!(fs::read_dir(&models_dir).unwrap().count(), 1);
        assert!(!legacy.exists());

        let _ = fs::remove_dir_all(base);
    }

    #[test]
    fn migrate_adopts_targets_only_when_every_file_resolves() {
        let base = scratch_dir("migrate-ambiguous");
        let legacy = base.join("llm");
        let legacy_models = legacy.join("models");
        fs::create_dir_all(&legacy_models).unwrap();
        fs::write(legacy_models.join("a.gguf"), b"GGUFa").unwrap();
        fs::write(legacy_models.join("b.gguf"), b"GGUFb").unwrap();
        fs::write(legacy_models.join("mmproj-F16.gguf"), b"GGUFshared").unwrap();

        let targets = ["a", "b"].map(|name| {
            gguf_target(
                &format!("preset-{name}"),
                format!("https://example.org/{name}/{name}.gguf"),
                format!("https://example.org/{name}/mmproj-F16.gguf"),
            )
        });

        let models_dir = base.join("models");
        migrate_legacy_dir(&ModelDownloader::new(&models_dir), &legacy, &targets);

        assert!(!models_dir.exists() || fs::read_dir(&models_dir).unwrap().count() == 0);
        assert!(!legacy.exists());

        let _ = fs::remove_dir_all(base);
    }

    #[test]
    fn migrate_flat_models_dir_adopts_known_files_and_cleans_root() {
        let models_dir = scratch_dir("flat-migrate");
        fs::create_dir_all(models_dir.join("custom")).unwrap();

        let preset = target("qwen-2b-q8");
        fs::write(models_dir.join("main.gguf"), b"GGUFmain").unwrap();
        let mmproj_hashed = format!(
            "{}_mmproj.gguf",
            sha256_hex("https://example.org/models/mmproj.gguf")
        );
        fs::write(models_dir.join(mmproj_hashed), b"GGUFmm").unwrap();

        fs::write(models_dir.join("orphan.gguf"), b"GGUForphan").unwrap();
        fs::write(models_dir.join("main.gguf.tmp"), b"GGUFpartial").unwrap();
        let downloader = ModelDownloader::new(&models_dir);
        write_gguf(
            &models_dir.join("other-key").join("model.gguf"),
            b"GGUFkeep",
        );

        migrate_flat_models_dir(&models_dir, std::slice::from_ref(&preset));

        assert_eq!(
            fs::read(model::llm_model_path(&downloader, &preset).unwrap()).unwrap(),
            b"GGUFmain"
        );
        assert_eq!(
            fs::read(model::llm_mmproj_path(&downloader, &preset).unwrap()).unwrap(),
            b"GGUFmm"
        );
        assert_eq!(
            fs::read(models_dir.join("other-key/model.gguf")).unwrap(),
            b"GGUFkeep"
        );
        assert!(!models_dir.join("custom").exists());
        let root_files = fs::read_dir(&models_dir)
            .unwrap()
            .flatten()
            .filter(|entry| entry.path().is_file())
            .count();
        assert_eq!(root_files, 0);

        migrate_flat_models_dir(&models_dir, std::slice::from_ref(&preset));
        assert_eq!(
            fs::read(model::llm_model_path(&downloader, &preset).unwrap()).unwrap(),
            b"GGUFmain"
        );

        let _ = fs::remove_dir_all(models_dir);
    }

    #[test]
    fn migrate_flat_models_dir_adopts_sidecarless_files_for_duplicated_targets() {
        let models_dir = scratch_dir("flat-duplicate-targets");
        fs::create_dir_all(&models_dir).unwrap();
        fs::write(models_dir.join("main.gguf"), b"GGUFmain").unwrap();
        fs::write(models_dir.join("mmproj.gguf"), b"GGUFmm").unwrap();

        let preset = target("lfm-vl-1.6b");
        migrate_flat_models_dir(&models_dir, &[preset.clone(), preset.clone()]);

        let downloader = ModelDownloader::new(&models_dir);
        assert_eq!(
            fs::read(model::llm_model_path(&downloader, &preset).unwrap()).unwrap(),
            b"GGUFmain"
        );
        assert_eq!(
            fs::read(model::llm_mmproj_path(&downloader, &preset).unwrap()).unwrap(),
            b"GGUFmm"
        );

        let _ = fs::remove_dir_all(models_dir);
    }

    #[test]
    fn migrate_flat_models_dir_resolves_ambiguity_via_metadata_sidecars() {
        let models_dir = scratch_dir("flat-sidecar");
        fs::create_dir_all(&models_dir).unwrap();

        let targets = ["a", "b"].map(|name| {
            gguf_target(
                &format!("preset-{name}"),
                format!("https://example.org/{name}/{name}.gguf"),
                format!("https://example.org/{name}/mmproj-F16.gguf"),
            )
        });

        fs::write(models_dir.join("a.gguf"), b"GGUFa").unwrap();
        fs::write(
            models_dir.join("a.gguf.metadata.json"),
            br#"{"url": "https://example.org/a/a.gguf"}"#,
        )
        .unwrap();
        fs::write(models_dir.join("mmproj-F16.gguf"), b"GGUFmma").unwrap();
        fs::write(
            models_dir.join("mmproj-F16.gguf.metadata.json"),
            br#"{"url": "https://example.org/a/mmproj-F16.gguf"}"#,
        )
        .unwrap();

        migrate_flat_models_dir(&models_dir, &targets);

        let downloader = ModelDownloader::new(&models_dir);
        assert_eq!(
            fs::read(model::llm_model_path(&downloader, &targets[0]).unwrap()).unwrap(),
            b"GGUFa"
        );
        assert_eq!(
            fs::read(model::llm_mmproj_path(&downloader, &targets[0]).unwrap()).unwrap(),
            b"GGUFmma"
        );
        assert!(
            !model::llm_model_path(&downloader, &targets[1])
                .unwrap()
                .exists()
        );

        let _ = fs::remove_dir_all(models_dir);
    }

    #[test]
    fn migrate_flat_models_dir_rejects_files_whose_sidecar_disagrees() {
        let models_dir = scratch_dir("flat-sidecar-mismatch");
        fs::create_dir_all(&models_dir).unwrap();

        let preset = target("qwen-2b-q8");
        fs::write(models_dir.join("main.gguf"), b"GGUFstale").unwrap();
        fs::write(
            models_dir.join("main.gguf.metadata.json"),
            br#"{"url": "https://example.org/elsewhere/main.gguf"}"#,
        )
        .unwrap();

        migrate_flat_models_dir(&models_dir, std::slice::from_ref(&preset));

        let downloader = ModelDownloader::new(&models_dir);
        assert!(
            !model::llm_model_path(&downloader, &preset)
                .unwrap()
                .exists()
        );

        let _ = fs::remove_dir_all(models_dir);
    }

    #[test]
    fn migrate_flat_models_dir_drops_targets_with_ambiguous_basenames() {
        let models_dir = scratch_dir("flat-ambiguous");
        fs::create_dir_all(&models_dir).unwrap();
        fs::write(models_dir.join("a.gguf"), b"GGUFa").unwrap();
        fs::write(models_dir.join("mmproj-F16.gguf"), b"GGUFshared").unwrap();

        let targets = ["a", "b"].map(|name| {
            gguf_target(
                &format!("preset-{name}"),
                format!("https://example.org/{name}/{name}.gguf"),
                format!("https://example.org/{name}/mmproj-F16.gguf"),
            )
        });

        migrate_flat_models_dir(&models_dir, &targets);

        assert_eq!(fs::read_dir(&models_dir).unwrap().count(), 0);

        let _ = fs::remove_dir_all(models_dir);
    }

    #[test]
    fn migrate_keeps_existing_destination_files() {
        let base = scratch_dir("migrate-existing");
        let legacy = base.join("llm");
        fs::create_dir_all(legacy.join("models")).unwrap();
        fs::write(legacy.join("models/main.gguf"), b"GGUFold").unwrap();
        fs::write(legacy.join("models/mmproj.gguf"), b"GGUFmm").unwrap();

        let models_dir = base.join("models");
        let preset = target("qwen-2b-q8");
        let downloader = ModelDownloader::new(&models_dir);
        write_gguf(
            &model::llm_model_path(&downloader, &preset).unwrap(),
            b"GGUFnew",
        );

        migrate_legacy_dir(
            &ModelDownloader::new(&models_dir),
            &legacy,
            std::slice::from_ref(&preset),
        );

        assert_eq!(
            fs::read(model::llm_model_path(&downloader, &preset).unwrap()).unwrap(),
            b"GGUFnew"
        );
        assert_eq!(
            fs::read(model::llm_mmproj_path(&downloader, &preset).unwrap()).unwrap(),
            b"GGUFmm"
        );
        assert!(!legacy.exists());

        let _ = fs::remove_dir_all(base);
    }
}
