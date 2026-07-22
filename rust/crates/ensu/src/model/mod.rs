pub mod migrations;

use std::path::PathBuf;

use ente_model_download::{ModelDownloader, ModelFile, ModelTarget};

use crate::config::{self, ModelPreset};

const LLM_MODEL_FILE: &str = "model.gguf";
const LLM_MMPROJ_FILE: &str = "mmproj.gguf";
const VOICE_ACTIVITY_MODEL_FILE: &str = "model.onnx";

#[derive(Debug, thiserror::Error)]
#[error("preset {id} pairs only half of the mmproj URL and checksum")]
pub struct InvalidPreset {
    pub id: String,
}

pub(crate) fn llm_target(preset: &ModelPreset) -> Result<ModelTarget, InvalidPreset> {
    let mut files = vec![ModelFile {
        name: LLM_MODEL_FILE.to_string(),
        url: preset.url.clone(),
        sha256: preset.sha256.clone(),
    }];
    match (
        trimmed(preset.mmproj_url.as_deref()),
        trimmed(preset.mmproj_sha256.as_deref()),
    ) {
        (Some(url), Some(sha256)) => files.push(ModelFile {
            name: LLM_MMPROJ_FILE.to_string(),
            url: url.to_string(),
            sha256: sha256.to_string(),
        }),
        (None, None) => {}
        _ => {
            return Err(InvalidPreset {
                id: preset.id.clone(),
            });
        }
    }
    Ok(ModelTarget::Files {
        id: preset.id.clone(),
        files,
    })
}

pub fn mobile_llm_target(model_id: &str) -> Result<ModelTarget, InvalidPreset> {
    let preset = config::llm_catalog()
        .into_iter()
        .find(|preset| preset.id == model_id)
        .unwrap_or_else(|| config::defaults().mobile_default_model);
    llm_target(&preset)
}

pub fn desktop_llm_target(model_id: &str) -> Result<ModelTarget, InvalidPreset> {
    let preset = config::llm_catalog()
        .into_iter()
        .find(|preset| preset.id == model_id)
        .unwrap_or_else(|| config::defaults().desktop_default_model);
    llm_target(&preset)
}

pub fn transcription_target() -> ModelTarget {
    let preset = config::defaults().transcription_model;
    ModelTarget::TarGz {
        id: preset.id,
        url: preset.url,
        sha256: preset.sha256,
    }
}

pub fn voice_activity_target() -> ModelTarget {
    let preset = config::defaults().voice_activity_model;
    ModelTarget::Files {
        id: preset.id,
        files: vec![ModelFile {
            name: VOICE_ACTIVITY_MODEL_FILE.to_string(),
            url: preset.url,
            sha256: preset.sha256,
        }],
    }
}

pub fn llm_model_path(downloader: &ModelDownloader, target: &ModelTarget) -> Option<PathBuf> {
    downloader.file_path(target, LLM_MODEL_FILE)
}

pub fn llm_mmproj_path(downloader: &ModelDownloader, target: &ModelTarget) -> Option<PathBuf> {
    downloader.file_path(target, LLM_MMPROJ_FILE)
}

pub fn voice_activity_model_path(downloader: &ModelDownloader) -> PathBuf {
    downloader
        .model_dir(&voice_activity_target())
        .join(VOICE_ACTIVITY_MODEL_FILE)
}

pub(crate) fn trimmed(value: Option<&str>) -> Option<&str> {
    value.map(str::trim).filter(|value| !value.is_empty())
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
    fn llm_target_names_model_and_mmproj_files() {
        let target = llm_target(&preset(
            Some("https://example.org/mmproj.gguf"),
            Some("abc"),
        ))
        .expect("paired preset");
        let downloader = ModelDownloader::new(std::env::temp_dir().join("ensu-models-test"));
        assert_eq!(
            llm_model_path(&downloader, &target).unwrap(),
            downloader.model_dir(&target).join("model.gguf")
        );
        assert_eq!(
            llm_mmproj_path(&downloader, &target).unwrap(),
            downloader.model_dir(&target).join("mmproj.gguf")
        );
    }

    #[test]
    fn llm_target_without_mmproj_has_no_mmproj_path() {
        let target = llm_target(&preset(None, None)).expect("model-only preset");
        let downloader = ModelDownloader::new(std::env::temp_dir().join("ensu-models-test"));
        assert!(llm_model_path(&downloader, &target).is_some());
        assert!(llm_mmproj_path(&downloader, &target).is_none());
    }

    #[test]
    fn llm_target_rejects_half_specified_mmproj() {
        assert!(llm_target(&preset(Some("https://example.org/mmproj.gguf"), None)).is_err());
        assert!(llm_target(&preset(None, Some("abc"))).is_err());
        assert!(llm_target(&preset(Some(" "), Some("abc"))).is_err());
    }

    #[test]
    fn llm_targets_resolve_catalog_ids_or_fall_back_to_defaults() {
        let defaults = crate::config::defaults();
        for preset in crate::config::llm_catalog() {
            assert_eq!(
                mobile_llm_target(&preset.id).unwrap(),
                llm_target(&preset).unwrap(),
                "{}",
                preset.id
            );
            assert_eq!(
                desktop_llm_target(&preset.id).unwrap(),
                llm_target(&preset).unwrap(),
                "{}",
                preset.id
            );
        }
        let mobile_default = llm_target(&defaults.mobile_default_model).unwrap();
        assert_eq!(mobile_llm_target("").unwrap(), mobile_default);
        assert_eq!(mobile_llm_target("no-such-model").unwrap(), mobile_default);
        let desktop_default = llm_target(&defaults.desktop_default_model).unwrap();
        assert_eq!(desktop_llm_target("").unwrap(), desktop_default);
        assert_eq!(
            desktop_llm_target("no-such-model").unwrap(),
            desktop_default
        );
    }

    #[test]
    fn all_catalog_presets_produce_valid_targets() {
        for preset in crate::config::llm_catalog() {
            llm_target(&preset).expect("catalog preset");
        }
    }
}
