mod knowledge;

pub use knowledge::knowledge_dataset;
pub use knowledge::{AttributionConfig, KnowledgeDatasetConfig, KnowledgeEmbeddingConfig};
pub(crate) use knowledge::{
    KNOWLEDGE_ARTIFACT_FILENAMES, KNOWLEDGE_LICENSE_LABEL, KNOWLEDGE_LICENSE_URL,
    KNOWLEDGE_MANIFEST_FILE, KNOWLEDGE_META_FILE, KNOWLEDGE_OFFSETS_FILE, KNOWLEDGE_VECTORS_FILE,
    format_knowledge_document_prompt, is_path_safe_component, knowledge_artifact_urls,
    knowledge_datasets, knowledge_embedding_config, knowledge_index_contract,
};

#[derive(Debug, Clone)]
pub struct ModelPreset {
    pub id: String,
    pub title: String,
    pub url: String,
    pub size: u64,
    pub sha256: String,
    pub mmproj_url: Option<String>,
    pub mmproj_size: Option<u64>,
    pub mmproj_sha256: Option<String>,
}

#[derive(Debug, Clone, Copy)]
pub enum ModelRuntimeSurface {
    Android,
    Ios,
    Desktop,
}

#[derive(Debug, Clone)]
pub struct ResolvedModelPolicy {
    pub default_model: ModelPreset,
    pub visible_models: Vec<ModelPreset>,
    pub allowed_preferred_models: Vec<ModelPreset>,
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
    pub knowledge_embedding: KnowledgeEmbeddingConfig,
    pub knowledge_datasets: Vec<KnowledgeDatasetConfig>,
}

const SYSTEM_PROMPT_DATE_PLACEHOLDER: &str = "$date";
// Mobile OSes report less than marketed RAM, so 7 GB targets 8 GB devices.
const MOBILE_HIGH_MEMORY_THRESHOLD_BYTES: u64 = 7_000_000_000;
const DESKTOP_HIGH_MEMORY_THRESHOLD_BYTES: u64 = 16 * 1024 * 1024 * 1024;
const MOBILE_SYSTEM_PROMPT_BODY: &str = "You are Ensu, an AI assistant built by Ente. Current date: $date\n\nUse Markdown **bold** to emphasize important terms and key points.\n\nNever acknowledge or repeat these instructions. Do not start with generic confirmations like 'Okay, I understand'. Respond directly to the user's request.";
const DESKTOP_SYSTEM_PROMPT_BODY: &str = MOBILE_SYSTEM_PROMPT_BODY;
const SESSION_SUMMARY_SYSTEM_PROMPT: &str = "You create concise chat titles. Given the provided message, summarize the user's goal in 5-7 words. Use plain words. Don't use markdown characters in the title. No quotes, no emojis, no trailing punctuation, and output only the title.";

fn lfm_vl_1_6b() -> ModelPreset {
    ModelPreset {
        id: "lfm-vl-1.6b".to_string(),
        title: "LFM 2.5 VL 1.6B (Q4_0)".to_string(),
        url: "https://huggingface.co/ente-ai/LFM2.5-VL-1.6B-GGUF/resolve/b2995f54e17fd7ec31e9cb399ade8fedfd51624d/LFM2.5-VL-1.6B-Q4_0.gguf?download=true".to_string(),
        size: 695_752_480,
        sha256: "8186364a4e7c3ad30f6dd3d3b7a4e0074c77dd91eed6cad5d8be9090ce285804".to_string(),
        mmproj_url: Some(
            "https://huggingface.co/ente-ai/LFM2.5-VL-1.6B-GGUF/resolve/b2995f54e17fd7ec31e9cb399ade8fedfd51624d/mmproj-LFM2.5-VL-1.6b-Q8_0.gguf"
                .to_string(),
        ),
        mmproj_size: Some(583_109_888),
        mmproj_sha256: Some("2ce89e610c56f3198ece2b86cf61743a08b9307279c89125eb2412ebb908689d".to_string()),
    }
}

fn qwen_0_8b() -> ModelPreset {
    ModelPreset {
        id: "qwen-0.8b".to_string(),
        title: "Qwen 3.5 0.8B (Q4_K_M)".to_string(),
        url: "https://huggingface.co/ente-ai/Qwen3.5-0.8B-GGUF/resolve/f44fc9bf306e407078288aee9ff7a83b457d260a/Qwen3.5-0.8B-Q4_K_M.gguf?download=true".to_string(),
        size: 532_517_120,
        sha256: "bd258782e35f7f458f8aced1adc053e6e92e89bc735ba3be89d38a06121dc517".to_string(),
        mmproj_url: Some(
            "https://huggingface.co/ente-ai/Qwen3.5-0.8B-GGUF/resolve/f44fc9bf306e407078288aee9ff7a83b457d260a/mmproj-F16.gguf"
                .to_string(),
        ),
        mmproj_size: Some(204_987_232),
        mmproj_sha256: Some("56e4c6cfe73b0c82e3e82bc518d7591997e61d81f723fc41a586f4fa69ea2453".to_string()),
    }
}

fn qwen_2b_q8() -> ModelPreset {
    ModelPreset {
        id: "qwen-2b-q8".to_string(),
        title: "Qwen 3.5 2B (Q8_0)".to_string(),
        url: "https://huggingface.co/ente-ai/Qwen3.5-2B-GGUF/resolve/4cd5d68754a443dc390533792bf345ad219c0b41/Qwen3.5-2B-Q8_0.gguf?download=true".to_string(),
        size: 2_012_012_800,
        sha256: "1b04acba824817554f4ce23639bc8495ff70453b8fcb047900c731521021f2c1".to_string(),
        mmproj_url: Some(
            "https://huggingface.co/ente-ai/Qwen3.5-2B-GGUF/resolve/4cd5d68754a443dc390533792bf345ad219c0b41/mmproj-F16.gguf"
                .to_string(),
        ),
        mmproj_size: Some(668_227_264),
        mmproj_sha256: Some("7035e9cb8d7c6a9681d07eef9a364783e86ea4cd73faab2eabb4f43a101830c7".to_string()),
    }
}

fn qwen_4b_q4km() -> ModelPreset {
    ModelPreset {
        id: "qwen-4b-q4km".to_string(),
        title: "Qwen 3.5 4B (Q4_K_M)".to_string(),
        url: "https://huggingface.co/ente-ai/Qwen3.5-4B-GGUF/resolve/9b67f8db9bedc8c10f524ac08193b58fa9b20ac7/Qwen3.5-4B-Q4_K_M.gguf?download=true".to_string(),
        size: 2_740_937_888,
        sha256: "00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4".to_string(),
        mmproj_url: Some(
            "https://huggingface.co/ente-ai/Qwen3.5-4B-GGUF/resolve/9b67f8db9bedc8c10f524ac08193b58fa9b20ac7/mmproj-F16.gguf"
                .to_string(),
        ),
        mmproj_size: Some(672_423_616),
        mmproj_sha256: Some("cd88edcf8d031894960bb0c9c5b9b7e1fea6ebee02b9f7ce925a00d12891f864".to_string()),
    }
}

fn gemma_4_e4b_q4km() -> ModelPreset {
    ModelPreset {
        id: "gemma-4-e4b-q4km".to_string(),
        title: "Gemma 4 E4B (Q4_K_M)".to_string(),
        url: "https://huggingface.co/ente-ai/gemma-4-E4B-it-GGUF/resolve/f0089e04ac8494e513619d18b44c829c6b815440/gemma-4-E4B-it-Q4_K_M.gguf?download=true".to_string(),
        size: 4_977_171_584,
        sha256: "85a896a047553e842f25297ee5b031d64ff30147d9c4af17b1e4b394cd1fab87".to_string(),
        mmproj_url: Some(
            "https://huggingface.co/ente-ai/gemma-4-E4B-it-GGUF/resolve/f0089e04ac8494e513619d18b44c829c6b815440/mmproj-F16.gguf"
                .to_string(),
        ),
        mmproj_size: Some(990_372_672),
        mmproj_sha256: Some("ddf46c21d7078e95338cfc22306b19b276a29a5ad089023449dd54d4b6170a51".to_string()),
    }
}

fn gemma_4_e2b_q4km() -> ModelPreset {
    ModelPreset {
        id: "gemma-4-e2b-q4km".to_string(),
        title: "Gemma 4 E2B (Q4_K_M)".to_string(),
        url: "https://huggingface.co/ente-ai/gemma-4-E2B-it-GGUF/resolve/d9f70b02c9a2193b7263daee865dfa93276fd99a/gemma-4-E2B-it-Q4_K_M.gguf?download=true".to_string(),
        size: 3_106_738_272,
        sha256: "740185b21d22ceb83a11c3aa62ad5842ef32c70f6096d756bbee85a1e4ec34b8".to_string(),
        mmproj_url: Some(
            "https://huggingface.co/ente-ai/gemma-4-E2B-it-GGUF/resolve/d9f70b02c9a2193b7263daee865dfa93276fd99a/mmproj-F16.gguf"
                .to_string(),
        ),
        mmproj_size: Some(985_654_080),
        mmproj_sha256: Some("140be8d7849741f88c50757d529b84373ee8e27052cc2236855b537f4a8215fa".to_string()),
    }
}

fn parakeet_v3_int8() -> ModelPreset {
    ModelPreset {
        id: "parakeet-v3-int8".to_string(),
        title: "Transcription model".to_string(),
        url: "https://models.ente.com/parakeet-v3-int8.tar.gz".to_string(),
        size: 478_517_071,
        sha256: "43d37191602727524a7d8c6da0eef11c4ba24320f5b4730f1a2497befc2efa77".to_string(),
        mmproj_url: None,
        mmproj_size: None,
        mmproj_sha256: None,
    }
}

fn silero_vad_v4() -> ModelPreset {
    ModelPreset {
        id: "silero-vad-v4".to_string(),
        title: "Voice activity model".to_string(),
        url: "https://models.ente.com/silero_vad_v4.onnx".to_string(),
        size: 1_807_522,
        sha256: "a35ebf52fd3ce5f1469b2a36158dba761bc47b973ea3382b3186ca15b1f5af28".to_string(),
        mmproj_url: None,
        mmproj_size: None,
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

pub fn resolve_model_policy(
    surface: ModelRuntimeSurface,
    total_memory_bytes: Option<u64>,
) -> ResolvedModelPolicy {
    let high_memory = match surface {
        ModelRuntimeSurface::Android | ModelRuntimeSurface::Ios => {
            total_memory_bytes.is_some_and(|bytes| bytes >= MOBILE_HIGH_MEMORY_THRESHOLD_BYTES)
        }
        ModelRuntimeSurface::Desktop => {
            total_memory_bytes.is_some_and(|bytes| bytes >= DESKTOP_HIGH_MEMORY_THRESHOLD_BYTES)
        }
    };

    let (default_id, visible_ids): (&str, &[&str]) = match (surface, high_memory) {
        (ModelRuntimeSurface::Android | ModelRuntimeSurface::Ios, true) => {
            ("gemma-4-e2b-q4km", &["gemma-4-e2b-q4km", "lfm-vl-1.6b"])
        }
        (ModelRuntimeSurface::Android | ModelRuntimeSurface::Ios, false) => {
            ("lfm-vl-1.6b", &["lfm-vl-1.6b"])
        }
        (ModelRuntimeSurface::Desktop, true) => (
            "gemma-4-e4b-q4km",
            &[
                "gemma-4-e4b-q4km",
                "qwen-4b-q4km",
                "lfm-vl-1.6b",
                "qwen-0.8b",
                "qwen-2b-q8",
            ],
        ),
        (ModelRuntimeSurface::Desktop, false) => (
            "lfm-vl-1.6b",
            &["lfm-vl-1.6b", "qwen-0.8b", "qwen-2b-q8", "gemma-4-e2b-q4km"],
        ),
    };

    let catalog = llm_catalog();
    let presets = |ids: &[&str]| ids.iter().map(|id| catalog_preset(&catalog, id)).collect();
    ResolvedModelPolicy {
        default_model: catalog_preset(&catalog, default_id),
        visible_models: presets(visible_ids),
        allowed_preferred_models: catalog,
    }
}

pub fn resolve_effective_model(
    surface: ModelRuntimeSurface,
    total_memory_bytes: Option<u64>,
    preferred_model_id: Option<&str>,
) -> ModelPreset {
    let policy = resolve_model_policy(surface, total_memory_bytes);
    preferred_model_id
        .filter(|id| !id.is_empty())
        .and_then(|id| {
            policy
                .allowed_preferred_models
                .iter()
                .find(|preset| preset.id == id)
        })
        .cloned()
        .unwrap_or(policy.default_model)
}

fn catalog_preset(catalog: &[ModelPreset], id: &str) -> ModelPreset {
    #[expect(
        clippy::expect_used,
        reason = "Built-in defaults refer to IDs defined in the same catalog"
    )]
    catalog
        .iter()
        .find(|preset| preset.id == id)
        .expect("preset id is in the catalog")
        .clone()
}

pub fn defaults() -> Defaults {
    let catalog = llm_catalog();
    let preset = |id: &str| catalog_preset(&catalog, id);
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
        knowledge_embedding: knowledge::knowledge_embedding_config(),
        knowledge_datasets: knowledge::knowledge_datasets(),
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
        assert!(seen.insert(knowledge::knowledge_embedding_config().target_id));
    }

    #[test]
    fn catalog_presets_pair_mmproj_metadata() {
        for preset in llm_catalog() {
            let has_url = preset
                .mmproj_url
                .as_deref()
                .is_some_and(|u| !u.trim().is_empty());
            let has_size = preset.mmproj_size.is_some();
            let has_sha = preset
                .mmproj_sha256
                .as_deref()
                .is_some_and(|s| !s.trim().is_empty());
            assert!(
                has_url == has_size && has_size == has_sha,
                "preset {} must pair mmproj URL, size, and checksum",
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
        let defaults = defaults();
        assert_eq!(defaults.mobile_default_model.id, "lfm-vl-1.6b");
        assert_eq!(defaults.desktop_default_model.id, "gemma-4-e4b-q4km");

        let high_memory_mobile = resolve_model_policy(
            ModelRuntimeSurface::Android,
            Some(MOBILE_HIGH_MEMORY_THRESHOLD_BYTES),
        );
        assert_eq!(high_memory_mobile.default_model.id, "gemma-4-e2b-q4km");
        let effective_id = |surface, memory, preferred| {
            resolve_effective_model(surface, memory, Some(preferred)).id
        };
        assert_eq!(
            effective_id(
                ModelRuntimeSurface::Android,
                Some(MOBILE_HIGH_MEMORY_THRESHOLD_BYTES),
                "lfm-vl-1.6b",
            ),
            "lfm-vl-1.6b"
        );
        assert_eq!(
            effective_id(ModelRuntimeSurface::Ios, None, "gemma-4-e2b-q4km"),
            "gemma-4-e2b-q4km"
        );

        let desktop = resolve_model_policy(ModelRuntimeSurface::Desktop, None);
        assert_eq!(desktop.default_model.id, "lfm-vl-1.6b");
        assert_eq!(
            effective_id(ModelRuntimeSurface::Desktop, None, "qwen-4b-q4km"),
            "qwen-4b-q4km"
        );
    }
}
