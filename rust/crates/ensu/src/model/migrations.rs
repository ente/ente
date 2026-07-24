use std::collections::{HashMap, HashSet};
use std::fs::{self, File};
use std::io::Read;
use std::path::{Path, PathBuf};

use ente_assets::{Asset, AssetStore};

use crate::config;
use crate::model::{self, InvalidPreset, trimmed};

pub struct LegacyAssets {
    pub llm_dir: Option<PathBuf>,
    pub transcription_dir: Option<PathBuf>,
    pub models_dir: Option<PathBuf>,
    pub model_url: Option<String>,
    pub mmproj_url: Option<String>,
}

pub fn needs_migration(legacy: &LegacyAssets) -> bool {
    [
        legacy.llm_dir.as_deref(),
        legacy.transcription_dir.as_deref(),
        legacy.models_dir.as_deref(),
    ]
    .into_iter()
    .flatten()
    .any(Path::exists)
}

pub fn migrate_ensu_assets(assets_dir: &Path, legacy: LegacyAssets) -> Option<String> {
    let store = AssetStore::new(assets_dir);
    let Ok(llm_migrations) = llm_migrations() else {
        return None;
    };

    if let Some(directory) = legacy.llm_dir {
        migrate_flat_models(
            &store,
            &llm_migrations,
            &directory.join("models"),
            &directory,
        );
    }
    if let Some(directory) = legacy.transcription_dir {
        migrate_transcription(&store, &directory);
    }
    if let Some(directory) = legacy.models_dir {
        migrate_flat_models(&store, &llm_migrations, &directory, &directory);
    }

    legacy_selected_preset_id(legacy.model_url.as_deref()?, legacy.mmproj_url.as_deref())
}

struct LlmMigration {
    asset: Asset,
    files: Vec<LlmFile>,
}

struct LlmFile {
    url: String,
    name: &'static str,
}

fn llm_migrations() -> Result<Vec<LlmMigration>, InvalidPreset> {
    config::llm_catalog()
        .iter()
        .map(|preset| {
            let mut files = vec![LlmFile {
                url: preset.url.clone(),
                name: "model.gguf",
            }];
            if let Some(url) = trimmed(preset.mmproj_url.as_deref()) {
                files.push(LlmFile {
                    url: url.to_string(),
                    name: "mmproj.gguf",
                });
            }
            Ok(LlmMigration {
                asset: model::llm_asset(preset)?,
                files,
            })
        })
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

fn migrate_flat_models(
    store: &AssetStore,
    targets: &[LlmMigration],
    source: &Path,
    cleanup: &Path,
) {
    if source.exists() && adopt_flat_targets(store, targets, source) {
        let _ = fs::remove_dir_all(cleanup);
    }
}

fn migrate_transcription(store: &AssetStore, legacy_dir: &Path) {
    const LEGACY_MODEL_DIR: &str = "parakeet-tdt-0.6b-v3-int8";
    const LEGACY_VAD_FILE: &str = "silero_vad_v4.onnx";
    if !legacy_dir.exists() {
        return;
    }
    let mut complete = true;

    let model = model::transcription_model_asset();
    let model_destination = store.asset_dir(&model);
    if !store.is_downloaded(&model) {
        let source = legacy_dir.join(LEGACY_MODEL_DIR);
        if source.is_dir() {
            if let Some(parent) = model_destination.parent() {
                let _ = fs::create_dir_all(parent);
            }
            complete &= fs::rename(source, model_destination).is_ok();
        }
    }

    let vad = model::voice_activity_model_asset();
    let vad_destination = model::voice_activity_model_path(store, &vad);
    if !store.is_downloaded(&vad) {
        let source = legacy_dir.join(LEGACY_VAD_FILE);
        if is_non_empty_file(&source) {
            complete &= move_file(&source, &vad_destination);
        }
    }
    if complete {
        let _ = fs::remove_dir_all(legacy_dir);
    }
}

fn adopt_flat_targets(store: &AssetStore, targets: &[LlmMigration], flat_dir: &Path) -> bool {
    let mut basename_urls: HashMap<String, HashSet<&str>> = HashMap::new();
    let mut complete = true;
    for target in targets {
        for file in &target.files {
            basename_urls
                .entry(filename_for_url(&file.url, file.name))
                .or_default()
                .insert(&file.url);
        }
    }

    for target in targets {
        let destination = store.asset_dir(&target.asset);
        let sources = target
            .files
            .iter()
            .map(|file| {
                let final_path = destination.join(file.name);
                if final_path.exists() {
                    return Some(None);
                }
                let basename = filename_for_url(&file.url, file.name);
                let source = flat_dir.join(&basename);
                if !looks_like_gguf(&source) {
                    return None;
                }
                match sidecar_url(&source) {
                    Some(url) if url == file.url => Some(Some(source)),
                    None if basename_urls[&basename].len() == 1 => Some(Some(source)),
                    _ => None,
                }
            })
            .collect::<Vec<_>>();
        if sources.iter().any(Option::is_none) {
            continue;
        }
        for (file, source) in target.files.iter().zip(sources) {
            if let Some(Some(source)) = source {
                complete &= move_file(&source, &destination.join(file.name));
            }
        }
    }
    complete
}

fn move_file(source: &Path, destination: &Path) -> bool {
    if let Some(parent) = destination.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if fs::rename(source, destination).is_ok() {
        return true;
    }
    let staging = PathBuf::from(format!("{}.migrating", destination.display()));
    if fs::copy(source, &staging)
        .and_then(|_| fs::rename(&staging, destination))
        .is_err()
    {
        let _ = fs::remove_file(staging);
        return false;
    }
    true
}

fn sidecar_url(path: &Path) -> Option<String> {
    let sidecar = PathBuf::from(format!("{}.metadata.json", path.display()));
    let text = fs::read_to_string(sidecar).ok()?;
    let value: serde_json::Value = serde_json::from_str(&text).ok()?;
    value["url"].as_str().map(String::from)
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::ModelPreset;

    fn scratch_dir(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "ente-ensu-migrations-{name}-{}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn target(id: &str, model_url: &str, mmproj_url: &str) -> LlmMigration {
        let preset = ModelPreset {
            id: id.to_string(),
            title: String::new(),
            url: model_url.to_string(),
            sha256: "0".repeat(64),
            mmproj_url: Some(mmproj_url.to_string()),
            mmproj_sha256: Some("0".repeat(64)),
        };
        LlmMigration {
            asset: model::llm_asset(&preset).unwrap(),
            files: vec![
                LlmFile {
                    url: model_url.to_string(),
                    name: "model.gguf",
                },
                LlmFile {
                    url: mmproj_url.to_string(),
                    name: "mmproj.gguf",
                },
            ],
        }
    }

    #[test]
    fn resolves_only_catalog_selections() {
        let defaults = config::defaults();
        let preset = &defaults.mobile_model_presets[0];
        assert_eq!(
            legacy_selected_preset_id(&preset.url, preset.mmproj_url.as_deref()).as_deref(),
            Some(preset.id.as_str())
        );
        assert_eq!(
            legacy_selected_preset_id("https://example.org/custom.gguf", None),
            None
        );
    }

    #[test]
    fn adopts_released_flat_model_all_or_nothing() {
        let base = scratch_dir("flat");
        let legacy = base.join("llm/models");
        fs::create_dir_all(&legacy).unwrap();
        fs::write(legacy.join("model.gguf"), b"GGUFmodel").unwrap();
        fs::write(legacy.join("mmproj.gguf"), b"GGUFmmproj").unwrap();
        let target = target(
            "model",
            "https://example.org/model.gguf",
            "https://example.org/mmproj.gguf",
        );
        let store = AssetStore::new(base.join("assets"));

        adopt_flat_targets(&store, &[target], &legacy);

        assert_eq!(
            fs::read(base.join("assets/models/model/model.gguf")).unwrap(),
            b"GGUFmodel"
        );
        assert_eq!(
            fs::read(base.join("assets/models/model/mmproj.gguf")).unwrap(),
            b"GGUFmmproj"
        );
        let _ = fs::remove_dir_all(base);
    }

    #[test]
    fn rejects_ambiguous_flat_projector() {
        let base = scratch_dir("ambiguous");
        let legacy = base.join("models");
        fs::create_dir_all(&legacy).unwrap();
        fs::write(legacy.join("a.gguf"), b"GGUFa").unwrap();
        fs::write(legacy.join("b.gguf"), b"GGUFb").unwrap();
        fs::write(legacy.join("mmproj.gguf"), b"GGUFshared").unwrap();
        let targets = [
            target(
                "a",
                "https://example.org/a.gguf",
                "https://example.org/a/mmproj.gguf",
            ),
            target(
                "b",
                "https://example.org/b.gguf",
                "https://example.org/b/mmproj.gguf",
            ),
        ];
        let store = AssetStore::new(base.join("assets"));

        adopt_flat_targets(&store, &targets, &legacy);

        assert!(!base.join("assets/models/a").exists());
        assert!(!base.join("assets/models/b").exists());
        let _ = fs::remove_dir_all(base);
    }

    #[test]
    fn adopts_released_transcription() {
        let base = scratch_dir("transcription");
        let legacy = base.join("transcription");
        fs::create_dir_all(legacy.join("parakeet-tdt-0.6b-v3-int8")).unwrap();
        fs::write(
            legacy.join("parakeet-tdt-0.6b-v3-int8/encoder.onnx"),
            b"model",
        )
        .unwrap();
        fs::write(legacy.join("silero_vad_v4.onnx"), b"vad").unwrap();
        let store = AssetStore::new(base.join("assets"));

        migrate_transcription(&store, &legacy);

        assert!(store.is_downloaded(&model::transcription_model_asset()));
        assert!(store.is_downloaded(&model::voice_activity_model_asset()));
        assert!(!legacy.exists());
        let _ = fs::remove_dir_all(base);
    }
}
