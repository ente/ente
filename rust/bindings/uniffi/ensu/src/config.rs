use ente_ensu::config;

#[derive(Debug, Clone, uniffi::Record)]
pub struct ConfigModelPreset {
    pub id: String,
    pub title: String,
    pub url: String,
    pub sha256: String,
    pub mmproj_url: Option<String>,
    pub mmproj_sha256: Option<String>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct KnowledgeEmbeddingConfig {
    pub target_id: String,
    pub max_hits: u32,
    pub max_context_utf8_bytes: u32,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct AttributionConfig {
    pub credit: String,
    pub license_label: String,
    pub license_url: String,
    pub public_pack_url: String,
    pub modification_notice: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct KnowledgeDatasetConfig {
    pub stable_id: String,
    pub label: String,
    pub current_download_identity: String,
    pub download_size_bytes: i64,
    pub relevance_threshold: f32,
    pub attribution: AttributionConfig,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct ConfigDefaults {
    pub mobile_system_prompt_body: String,
    pub desktop_system_prompt_body: String,
    pub system_prompt_date_placeholder: String,
    pub session_summary_system_prompt: String,
    pub mobile_default_model: ConfigModelPreset,
    pub mobile_model_presets: Vec<ConfigModelPreset>,
    pub desktop_default_model: ConfigModelPreset,
    pub desktop_model_presets: Vec<ConfigModelPreset>,
    pub transcription_model: ConfigModelPreset,
    pub voice_activity_model: ConfigModelPreset,
    pub knowledge_embedding: KnowledgeEmbeddingConfig,
    pub knowledge_datasets: Vec<KnowledgeDatasetConfig>,
}

impl From<config::ModelPreset> for ConfigModelPreset {
    fn from(value: config::ModelPreset) -> Self {
        Self {
            id: value.id,
            title: value.title,
            url: value.url,
            sha256: value.sha256,
            mmproj_url: value.mmproj_url,
            mmproj_sha256: value.mmproj_sha256,
        }
    }
}

impl From<config::KnowledgeEmbeddingConfig> for KnowledgeEmbeddingConfig {
    fn from(value: config::KnowledgeEmbeddingConfig) -> Self {
        Self {
            target_id: value.target_id,
            max_hits: value.max_hits,
            max_context_utf8_bytes: value.max_context_utf8_bytes,
        }
    }
}

impl From<config::AttributionConfig> for AttributionConfig {
    fn from(value: config::AttributionConfig) -> Self {
        Self {
            credit: value.credit,
            license_label: value.license_label,
            license_url: value.license_url,
            public_pack_url: value.public_pack_url,
            modification_notice: value.modification_notice,
        }
    }
}

impl From<config::KnowledgeDatasetConfig> for KnowledgeDatasetConfig {
    fn from(value: config::KnowledgeDatasetConfig) -> Self {
        Self {
            stable_id: value.stable_id,
            label: value.label,
            current_download_identity: value.current_download_identity,
            download_size_bytes: value.download_size_bytes,
            relevance_threshold: value.relevance_threshold,
            attribution: value.attribution.into(),
        }
    }
}

impl From<config::Defaults> for ConfigDefaults {
    fn from(value: config::Defaults) -> Self {
        Self {
            mobile_system_prompt_body: value.mobile_system_prompt_body,
            desktop_system_prompt_body: value.desktop_system_prompt_body,
            system_prompt_date_placeholder: value.system_prompt_date_placeholder,
            session_summary_system_prompt: value.session_summary_system_prompt,
            mobile_default_model: value.mobile_default_model.into(),
            mobile_model_presets: value
                .mobile_model_presets
                .into_iter()
                .map(Into::into)
                .collect(),
            desktop_default_model: value.desktop_default_model.into(),
            desktop_model_presets: value
                .desktop_model_presets
                .into_iter()
                .map(Into::into)
                .collect(),
            transcription_model: value.transcription_model.into(),
            voice_activity_model: value.voice_activity_model.into(),
            knowledge_embedding: value.knowledge_embedding.into(),
            knowledge_datasets: value
                .knowledge_datasets
                .into_iter()
                .map(Into::into)
                .collect(),
        }
    }
}

#[uniffi::export]
pub fn config_defaults() -> ConfigDefaults {
    config::defaults().into()
}
