use ente_ensu::config;
use serde::Serialize;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelPreset {
    id: String,
    title: String,
    url: String,
    mmproj_url: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Defaults {
    mobile_system_prompt_body: String,
    desktop_system_prompt_body: String,
    system_prompt_date_placeholder: String,
    session_summary_system_prompt: String,
    mobile_default_model: ModelPreset,
    mobile_model_presets: Vec<ModelPreset>,
    desktop_default_model: ModelPreset,
    desktop_model_presets: Vec<ModelPreset>,
}

impl From<config::ModelPreset> for ModelPreset {
    fn from(p: config::ModelPreset) -> Self {
        Self {
            id: p.id,
            title: p.title,
            url: p.url,
            mmproj_url: p.mmproj_url,
        }
    }
}

impl From<config::Defaults> for Defaults {
    fn from(d: config::Defaults) -> Self {
        Self {
            mobile_system_prompt_body: d.mobile_system_prompt_body,
            desktop_system_prompt_body: d.desktop_system_prompt_body,
            system_prompt_date_placeholder: d.system_prompt_date_placeholder,
            session_summary_system_prompt: d.session_summary_system_prompt,
            mobile_default_model: d.mobile_default_model.into(),
            mobile_model_presets: d.mobile_model_presets.into_iter().map(Into::into).collect(),
            desktop_default_model: d.desktop_default_model.into(),
            desktop_model_presets: d
                .desktop_model_presets
                .into_iter()
                .map(Into::into)
                .collect(),
        }
    }
}

#[tauri::command]
pub fn config_defaults() -> Defaults {
    config::defaults().into()
}
