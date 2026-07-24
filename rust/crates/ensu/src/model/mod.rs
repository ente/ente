pub mod migrations;

use std::path::PathBuf;

use ente_assets::{Asset, AssetDownloadProgress, AssetFile, AssetStore};

use crate::config::{self, ModelPreset};

const MODELS: &str = "models";
const LLM_MODEL_FILE: &str = "model.gguf";
const LLM_MMPROJ_FILE: &str = "mmproj.gguf";
const VOICE_ACTIVITY_MODEL_FILE: &str = "model.onnx";

#[derive(Debug, thiserror::Error)]
#[error("invalid preset {id}: {reason}")]
pub struct InvalidPreset {
    pub id: String,
    reason: String,
}

pub struct ModelDownloadProgress {
    pub downloaded_bytes: u64,
    pub total_bytes: Option<u64>,
    pub percent: i32,
    pub status: String,
    pub log_line: Option<String>,
}

pub(crate) fn llm_asset(preset: &ModelPreset) -> Result<Asset, InvalidPreset> {
    let mut files = vec![AssetFile {
        name: LLM_MODEL_FILE.to_string(),
        url: preset.url.clone(),
        sha256: preset.sha256.clone(),
    }];
    match (
        trimmed(preset.mmproj_url.as_deref()),
        trimmed(preset.mmproj_sha256.as_deref()),
    ) {
        (Some(url), Some(sha256)) => files.push(AssetFile {
            name: LLM_MMPROJ_FILE.to_string(),
            url: url.to_string(),
            sha256: sha256.to_string(),
        }),
        (None, None) => {}
        _ => {
            return Err(invalid_preset(
                preset,
                "mmproj URL and checksum must be paired",
            ));
        }
    }
    Asset::files(model_key(&preset.id), files)
        .map_err(|error| invalid_preset(preset, error.to_string()))
}

pub fn mobile_llm_asset(model_id: &str) -> Result<Asset, InvalidPreset> {
    let preset = config::llm_catalog()
        .into_iter()
        .find(|preset| preset.id == model_id)
        .unwrap_or_else(|| config::defaults().mobile_default_model);
    llm_asset(&preset)
}

pub fn desktop_llm_asset(model_id: &str) -> Result<Asset, InvalidPreset> {
    let preset = config::llm_catalog()
        .into_iter()
        .find(|preset| preset.id == model_id)
        .unwrap_or_else(|| config::defaults().desktop_default_model);
    llm_asset(&preset)
}

pub fn transcription_model_asset() -> Asset {
    let preset = config::defaults().transcription_model;
    Asset::tar_gz(model_key(&preset.id), preset.url, preset.sha256)
        .expect("transcription asset config")
}

pub fn voice_activity_model_asset() -> Asset {
    let preset = config::defaults().voice_activity_model;
    Asset::files(
        model_key(&preset.id),
        vec![AssetFile {
            name: VOICE_ACTIVITY_MODEL_FILE.to_string(),
            url: preset.url,
            sha256: preset.sha256,
        }],
    )
    .expect("voice activity asset config")
}

pub fn knowledge_embedding_model_asset() -> Asset {
    let embedding = config::knowledge_embedding_config();
    Asset::files(
        model_key(&embedding.target_id),
        vec![AssetFile {
            name: LLM_MODEL_FILE.to_string(),
            url: embedding.model_url,
            sha256: embedding.model_sha256,
        }],
    )
    .expect("knowledge embedding asset config")
}

pub fn llm_model_path(store: &AssetStore, asset: &Asset) -> Option<PathBuf> {
    store.file_path(asset, LLM_MODEL_FILE)
}

pub fn llm_mmproj_path(store: &AssetStore, asset: &Asset) -> Option<PathBuf> {
    store.file_path(asset, LLM_MMPROJ_FILE)
}

pub fn voice_activity_model_path(store: &AssetStore, asset: &Asset) -> PathBuf {
    store
        .file_path(asset, VOICE_ACTIVITY_MODEL_FILE)
        .expect("voice activity model file")
}

pub(crate) fn model_key(id: &str) -> Vec<String> {
    vec![MODELS.to_string(), id.to_string()]
}

pub(crate) fn trimmed(value: Option<&str>) -> Option<&str> {
    value.map(str::trim).filter(|value| !value.is_empty())
}

pub fn display_progress(progress: &AssetDownloadProgress) -> ModelDownloadProgress {
    let total = progress.total_bytes.filter(|total| *total > 0);
    let percent = total
        .map(|total| ((progress.downloaded_bytes * 100 / total) as i32).clamp(0, 99))
        .unwrap_or(0);
    let status = if let Some(total) = total {
        format!(
            "Downloading... {} / {}",
            format_bytes(progress.downloaded_bytes),
            format_bytes(total)
        )
    } else if progress.downloaded_bytes > 0 {
        format!("Downloading... {}", format_bytes(progress.downloaded_bytes))
    } else {
        "Downloading...".to_string()
    };
    let asset = &progress.asset_progress;
    let log_line = if asset.file_complete {
        Some(format!(
            "Asset download file complete label={} bytes={} elapsedMs={} rate={}/s retries={}",
            asset.label,
            asset.file_downloaded_bytes,
            asset.file_elapsed_ms,
            format_bytes(rate_bytes(asset.file_bytes_per_second)),
            asset.file_retry_count
        ))
    } else {
        None
    };

    ModelDownloadProgress {
        downloaded_bytes: progress.downloaded_bytes,
        total_bytes: progress.total_bytes,
        percent,
        status,
        log_line,
    }
}

fn invalid_preset(preset: &ModelPreset, reason: impl Into<String>) -> InvalidPreset {
    InvalidPreset {
        id: preset.id.clone(),
        reason: reason.into(),
    }
}

fn rate_bytes(bytes_per_second: f64) -> u64 {
    if bytes_per_second.is_finite() && bytes_per_second > 0.0 {
        bytes_per_second as u64
    } else {
        0
    }
}

fn format_bytes(bytes: u64) -> String {
    const UNITS: [&str; 4] = ["B", "KB", "MB", "GB"];
    let mut size = bytes as f64;
    let mut unit = 0;
    while size >= 1024.0 && unit < UNITS.len() - 1 {
        size /= 1024.0;
        unit += 1;
    }
    format!("{size:.1} {}", UNITS[unit])
}

#[cfg(test)]
mod tests {
    use super::*;

    fn preset(mmproj_url: Option<&str>, mmproj_sha256: Option<&str>) -> ModelPreset {
        ModelPreset {
            id: "qwen-2b-q8".to_string(),
            title: "Qwen".to_string(),
            url: "https://example.org/main.gguf".to_string(),
            sha256: "0".repeat(64),
            mmproj_url: mmproj_url.map(Into::into),
            mmproj_sha256: mmproj_sha256.map(Into::into),
        }
    }

    #[test]
    fn llm_asset_names_model_and_mmproj_files() {
        let asset = llm_asset(&preset(
            Some("https://example.org/mmproj.gguf"),
            Some(&"a".repeat(64)),
        ))
        .expect("paired preset");
        let store = AssetStore::new(std::env::temp_dir().join("ensu-assets-test"));
        assert_eq!(
            llm_model_path(&store, &asset).unwrap(),
            store.asset_dir(&asset).join("model.gguf")
        );
        assert_eq!(
            llm_mmproj_path(&store, &asset).unwrap(),
            store.asset_dir(&asset).join("mmproj.gguf")
        );
    }

    #[test]
    fn llm_asset_without_mmproj_has_no_mmproj_path() {
        let asset = llm_asset(&preset(None, None)).expect("model-only preset");
        let store = AssetStore::new(std::env::temp_dir().join("ensu-assets-test"));
        assert!(llm_model_path(&store, &asset).is_some());
        assert!(llm_mmproj_path(&store, &asset).is_none());
    }

    #[test]
    fn llm_asset_rejects_half_specified_mmproj() {
        assert!(llm_asset(&preset(Some("https://example.org/mmproj.gguf"), None)).is_err());
        assert!(llm_asset(&preset(None, Some(&"a".repeat(64)))).is_err());
        assert!(llm_asset(&preset(Some(" "), Some(&"a".repeat(64)))).is_err());
    }

    #[test]
    fn llm_assets_resolve_catalog_ids_or_fall_back_to_defaults() {
        let defaults = crate::config::defaults();
        for preset in crate::config::llm_catalog() {
            assert_eq!(
                mobile_llm_asset(&preset.id).unwrap(),
                llm_asset(&preset).unwrap(),
                "{}",
                preset.id
            );
            assert_eq!(
                desktop_llm_asset(&preset.id).unwrap(),
                llm_asset(&preset).unwrap(),
                "{}",
                preset.id
            );
        }
        let mobile_default = llm_asset(&defaults.mobile_default_model).unwrap();
        assert_eq!(mobile_llm_asset("").unwrap(), mobile_default);
        assert_eq!(mobile_llm_asset("no-such-model").unwrap(), mobile_default);
        let desktop_default = llm_asset(&defaults.desktop_default_model).unwrap();
        assert_eq!(desktop_llm_asset("").unwrap(), desktop_default);
        assert_eq!(desktop_llm_asset("no-such-model").unwrap(), desktop_default);
    }

    #[test]
    fn all_catalog_presets_produce_valid_assets() {
        for preset in crate::config::llm_catalog() {
            llm_asset(&preset).expect("catalog preset");
        }
    }

    #[test]
    fn knowledge_embedding_asset_is_checksum_backed() {
        let store = AssetStore::new(std::env::temp_dir().join("ensu-assets-test"));
        let asset = knowledge_embedding_model_asset();
        assert_eq!(
            store.file_path(&asset, "model.gguf"),
            Some(store.asset_dir(&asset).join("model.gguf"))
        );
    }
}
