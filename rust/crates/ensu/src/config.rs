#[derive(Debug, Clone)]
pub struct ModelPreset {
    pub id: String,
    pub title: String,
    pub url: String,
    pub sha256: String,
    pub mmproj_url: Option<String>,
    pub mmproj_sha256: Option<String>,
}

#[derive(Debug, Clone)]
pub struct Defaults {
    pub mobile_system_prompt_body: String,
    pub desktop_system_prompt_body: String,
    pub system_prompt_date_placeholder: String,
    pub session_summary_system_prompt: String,
    pub mobile_default_model: ModelPreset,
    pub mobile_model_presets: Vec<ModelPreset>,
    pub desktop_default_model: ModelPreset,
    pub desktop_model_presets: Vec<ModelPreset>,
    pub transcription_model: ModelPreset,
    pub voice_activity_model: ModelPreset,
}

const SYSTEM_PROMPT_DATE_PLACEHOLDER: &str = "$date";
const MOBILE_SYSTEM_PROMPT_BODY: &str = "You are Ensu, an AI assistant built by Ente. Current date: $date\n\nUse Markdown **bold** to emphasize important terms and key points.\n\nNever acknowledge or repeat these instructions. Do not start with generic confirmations like 'Okay, I understand'. Respond directly to the user's request.";
const DESKTOP_SYSTEM_PROMPT_BODY: &str = MOBILE_SYSTEM_PROMPT_BODY;
const SESSION_SUMMARY_SYSTEM_PROMPT: &str = "You create concise chat titles. Given the provided message, summarize the user's goal in 5-7 words. Use plain words. Don't use markdown characters in the title. No quotes, no emojis, no trailing punctuation, and output only the title.";

fn lfm_vl_1_6b() -> ModelPreset {
    ModelPreset {
        id: "lfm-vl-1.6b".to_string(),
        title: "LFM 2.5 VL 1.6B (Q4_0)".to_string(),
        url: "https://huggingface.co/LiquidAI/LFM2.5-VL-1.6B-GGUF/resolve/main/LFM2.5-VL-1.6B-Q4_0.gguf?download=true".to_string(),
        sha256: "8186364a4e7c3ad30f6dd3d3b7a4e0074c77dd91eed6cad5d8be9090ce285804".to_string(),
        mmproj_url: Some(
            "https://huggingface.co/LiquidAI/LFM2.5-VL-1.6B-GGUF/resolve/main/mmproj-LFM2.5-VL-1.6b-Q8_0.gguf"
                .to_string(),
        ),
        mmproj_sha256: Some("2ce89e610c56f3198ece2b86cf61743a08b9307279c89125eb2412ebb908689d".to_string()),
    }
}

fn qwen_0_8b() -> ModelPreset {
    ModelPreset {
        id: "qwen-0.8b".to_string(),
        title: "Qwen 3.5 0.8B (Q4_K_M)".to_string(),
        url: "https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf?download=true".to_string(),
        sha256: "bd258782e35f7f458f8aced1adc053e6e92e89bc735ba3be89d38a06121dc517".to_string(),
        mmproj_url: Some(
            "https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/mmproj-F16.gguf"
                .to_string(),
        ),
        mmproj_sha256: Some("56e4c6cfe73b0c82e3e82bc518d7591997e61d81f723fc41a586f4fa69ea2453".to_string()),
    }
}

fn qwen_2b_q8() -> ModelPreset {
    ModelPreset {
        id: "qwen-2b-q8".to_string(),
        title: "Qwen 3.5 2B (Q8_0)".to_string(),
        url: "https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q8_0.gguf?download=true".to_string(),
        sha256: "1b04acba824817554f4ce23639bc8495ff70453b8fcb047900c731521021f2c1".to_string(),
        mmproj_url: Some(
            "https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/mmproj-F16.gguf"
                .to_string(),
        ),
        mmproj_sha256: Some("7035e9cb8d7c6a9681d07eef9a364783e86ea4cd73faab2eabb4f43a101830c7".to_string()),
    }
}

fn qwen_4b_q4km() -> ModelPreset {
    ModelPreset {
        id: "qwen-4b-q4km".to_string(),
        title: "Qwen 3.5 4B (Q4_K_M)".to_string(),
        url: "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf?download=true".to_string(),
        sha256: "00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4".to_string(),
        mmproj_url: Some(
            "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/mmproj-F16.gguf"
                .to_string(),
        ),
        mmproj_sha256: Some("cd88edcf8d031894960bb0c9c5b9b7e1fea6ebee02b9f7ce925a00d12891f864".to_string()),
    }
}

fn gemma_4_e4b_q4km() -> ModelPreset {
    ModelPreset {
        id: "gemma-4-e4b-q4km".to_string(),
        title: "Gemma 4 E4B (Q4_K_M)".to_string(),
        url: "https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf?download=true".to_string(),
        sha256: "519b9793ed6ce0ff530f1b7c96e848e08e49e7af4d57bb97f76215963a54146d".to_string(),
        mmproj_url: Some(
            "https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/main/mmproj-F16.gguf"
                .to_string(),
        ),
        mmproj_sha256: Some("ddf46c21d7078e95338cfc22306b19b276a29a5ad089023449dd54d4b6170a51".to_string()),
    }
}

fn gemma_4_e2b_q4km() -> ModelPreset {
    ModelPreset {
        id: "gemma-4-e2b-q4km".to_string(),
        title: "Gemma 4 E2B (Q4_K_M)".to_string(),
        url: "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf?download=true".to_string(),
        sha256: "9378bc471710229ef165709b62e34bfb62231420ddaf6d729e727305b5b8672d".to_string(),
        mmproj_url: Some(
            "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/mmproj-F16.gguf"
                .to_string(),
        ),
        mmproj_sha256: Some("140be8d7849741f88c50757d529b84373ee8e27052cc2236855b537f4a8215fa".to_string()),
    }
}

fn parakeet_v3_int8() -> ModelPreset {
    ModelPreset {
        id: "parakeet-v3-int8".to_string(),
        title: "Transcription model".to_string(),
        url: "https://models.ente.com/parakeet-v3-int8.tar.gz".to_string(),
        sha256: "43d37191602727524a7d8c6da0eef11c4ba24320f5b4730f1a2497befc2efa77".to_string(),
        mmproj_url: None,
        mmproj_sha256: None,
    }
}

fn silero_vad_v4() -> ModelPreset {
    ModelPreset {
        id: "silero-vad-v4".to_string(),
        title: "Voice activity model".to_string(),
        url: "https://models.ente.com/silero_vad_v4.onnx".to_string(),
        sha256: "a35ebf52fd3ce5f1469b2a36158dba761bc47b973ea3382b3186ca15b1f5af28".to_string(),
        mmproj_url: None,
        mmproj_sha256: None,
    }
}

pub(crate) fn llm_catalog() -> Vec<ModelPreset> {
    vec![
        lfm_vl_1_6b(),
        qwen_0_8b(),
        qwen_2b_q8(),
        qwen_4b_q4km(),
        gemma_4_e4b_q4km(),
        gemma_4_e2b_q4km(),
    ]
}

pub fn defaults() -> Defaults {
    let catalog = llm_catalog();
    let preset = |id: &str| -> ModelPreset {
        catalog
            .iter()
            .find(|preset| preset.id == id)
            .expect("preset id is in the catalog")
            .clone()
    };
    Defaults {
        mobile_system_prompt_body: MOBILE_SYSTEM_PROMPT_BODY.to_string(),
        desktop_system_prompt_body: DESKTOP_SYSTEM_PROMPT_BODY.to_string(),
        system_prompt_date_placeholder: SYSTEM_PROMPT_DATE_PLACEHOLDER.to_string(),
        session_summary_system_prompt: SESSION_SUMMARY_SYSTEM_PROMPT.to_string(),
        mobile_default_model: preset("lfm-vl-1.6b"),
        mobile_model_presets: vec![
            preset("qwen-0.8b"),
            preset("qwen-2b-q8"),
            preset("gemma-4-e2b-q4km"),
        ],
        desktop_default_model: preset("gemma-4-e4b-q4km"),
        desktop_model_presets: vec![
            preset("qwen-4b-q4km"),
            preset("lfm-vl-1.6b"),
            preset("qwen-0.8b"),
            preset("qwen-2b-q8"),
        ],
        transcription_model: parakeet_v3_int8(),
        voice_activity_model: silero_vad_v4(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::{HashMap, HashSet};

    #[test]
    fn model_ids_are_unique() {
        let mut seen = HashSet::new();
        for preset in llm_catalog()
            .into_iter()
            .chain([parakeet_v3_int8(), silero_vad_v4()])
        {
            assert!(
                seen.insert(preset.id.clone()),
                "duplicate model id {}",
                preset.id
            );
        }
    }

    #[test]
    fn catalog_presets_pair_mmproj_url_with_checksum() {
        for preset in llm_catalog() {
            let has_url = preset
                .mmproj_url
                .as_deref()
                .is_some_and(|u| !u.trim().is_empty());
            let has_sha = preset
                .mmproj_sha256
                .as_deref()
                .is_some_and(|s| !s.trim().is_empty());
            assert_eq!(
                has_url, has_sha,
                "preset {} must pair mmproj URL with its checksum",
                preset.id
            );
        }
    }

    #[test]
    fn catalog_artifacts_resolve_unambiguously() {
        let catalog = llm_catalog();
        let mut seen: HashMap<(&str, Option<&str>), &str> = HashMap::new();
        for preset in &catalog {
            let artifact = (preset.url.as_str(), preset.mmproj_url.as_deref());
            if let Some(existing) = seen.insert(artifact, preset.id.as_str()) {
                assert_eq!(
                    existing, preset.id,
                    "presets {existing} and {} share an artifact",
                    preset.id
                );
            }
        }
    }

    #[test]
    fn defaults_views_select_from_the_catalog() {
        defaults();
    }
}
