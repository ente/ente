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
        }
    }
}

#[uniffi::export]
pub fn config_defaults() -> ConfigDefaults {
    config::defaults().into()
}
