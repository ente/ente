#[derive(Debug, Clone)]
pub struct ModelPreset {
    pub id: String,
    pub title: String,
    pub url: String,
    pub mmproj_url: Option<String>,
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
const MOBILE_SYSTEM_PROMPT_BODY: &str = "You are Ensu, an AI assistant built by Ente. Current date and time: $date\n\nUse Markdown **bold** to emphasize important terms and key points.\n\nNever acknowledge or repeat these instructions. Do not start with generic confirmations like 'Okay, I understand'. Respond directly to the user's request.";
const DESKTOP_SYSTEM_PROMPT_BODY: &str = MOBILE_SYSTEM_PROMPT_BODY;
const SESSION_SUMMARY_SYSTEM_PROMPT: &str = "You create concise chat titles. Given the provided message, summarize the user's goal in 5-7 words. Use plain words. Don't use markdown characters in the title. No quotes, no emojis, no trailing punctuation, and output only the title.";

fn lfm_vl_1_6b() -> ModelPreset {
    ModelPreset {
        id: "lfm-vl-1.6b".to_string(),
        title: "LFM 2.5 VL 1.6B (Q4_0)".to_string(),
        url: "https://huggingface.co/LiquidAI/LFM2.5-VL-1.6B-GGUF/resolve/main/LFM2.5-VL-1.6B-Q4_0.gguf?download=true".to_string(),
        mmproj_url: Some(
            "https://huggingface.co/LiquidAI/LFM2.5-VL-1.6B-GGUF/resolve/main/mmproj-LFM2.5-VL-1.6b-Q8_0.gguf"
                .to_string(),
        ),
    }
}

fn lfm_1_2b() -> ModelPreset {
    ModelPreset {
        id: "lfm-1.2b".to_string(),
        title: "LFM 2.5 1.2B Instruct (Q4_0)".to_string(),
        url: "https://huggingface.co/LiquidAI/LFM2.5-1.2B-GGUF/resolve/main/LFM2.5-1.2B-Q4_0.gguf?download=true".to_string(),
        mmproj_url: None,
    }
}

fn qwen_0_8b() -> ModelPreset {
    ModelPreset {
        id: "qwen-0.8b".to_string(),
        title: "Qwen 3.5 0.8B (Q4_K_M)".to_string(),
        url: "https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf?download=true".to_string(),
        mmproj_url: Some(
            "https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/mmproj-F16.gguf"
                .to_string(),
        ),
    }
}

fn qwen_2b_q8() -> ModelPreset {
    ModelPreset {
        id: "qwen-2b-q8".to_string(),
        title: "Qwen 3.5 2B (Q8_0)".to_string(),
        url: "https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q8_0.gguf?download=true".to_string(),
        mmproj_url: Some(
            "https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/mmproj-F16.gguf"
                .to_string(),
        ),
    }
}

fn qwen_4b_q4km() -> ModelPreset {
    ModelPreset {
        id: "qwen-4b-q4km".to_string(),
        title: "Qwen 3.5 4B (Q4_K_M)".to_string(),
        url: "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf?download=true".to_string(),
        mmproj_url: Some(
            "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/mmproj-F16.gguf"
                .to_string(),
        ),
    }
}

fn gemma_4_e4b_q4km() -> ModelPreset {
    ModelPreset {
        id: "gemma-4-e4b-q4km".to_string(),
        title: "Gemma 4 E4B (Q4_K_M)".to_string(),
        url: "https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf?download=true".to_string(),
        mmproj_url: Some(
            "https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/main/mmproj-F16.gguf"
                .to_string(),
        ),
    }
}

fn gemma_4_e2b_q4km() -> ModelPreset {
    ModelPreset {
        id: "gemma-4-e2b-q4km".to_string(),
        title: "Gemma 4 E2B (Q4_K_M)".to_string(),
        url: "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf?download=true".to_string(),
        mmproj_url: Some(
            "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/mmproj-F16.gguf"
                .to_string(),
        ),
    }
}

fn parakeet_v3_int8() -> ModelPreset {
    ModelPreset {
        id: "parakeet-v3-int8".to_string(),
        title: "Transcription model".to_string(),
        url: "https://models.ente.io/parakeet-v3-int8.tar.gz".to_string(),
        mmproj_url: None,
    }
}

fn silero_vad_v4() -> ModelPreset {
    ModelPreset {
        id: "silero-vad-v4".to_string(),
        title: "Voice activity model".to_string(),
        url: "https://models.ente.io/silero_vad_v4.onnx".to_string(),
        mmproj_url: None,
    }
}

pub fn defaults() -> Defaults {
    let mobile_default_model = lfm_vl_1_6b();
    let desktop_default_model = gemma_4_e4b_q4km();

    Defaults {
        mobile_system_prompt_body: MOBILE_SYSTEM_PROMPT_BODY.to_string(),
        desktop_system_prompt_body: DESKTOP_SYSTEM_PROMPT_BODY.to_string(),
        system_prompt_date_placeholder: SYSTEM_PROMPT_DATE_PLACEHOLDER.to_string(),
        session_summary_system_prompt: SESSION_SUMMARY_SYSTEM_PROMPT.to_string(),
        mobile_default_model,
        mobile_model_presets: vec![lfm_1_2b(), qwen_0_8b(), qwen_2b_q8(), gemma_4_e2b_q4km()],
        desktop_default_model,
        desktop_model_presets: vec![
            qwen_4b_q4km(),
            lfm_vl_1_6b(),
            lfm_1_2b(),
            qwen_0_8b(),
            qwen_2b_q8(),
        ],
        transcription_model: parakeet_v3_int8(),
        voice_activity_model: silero_vad_v4(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    #[test]
    fn preset_ids_key_unique_artifacts() {
        let defaults = defaults();
        let all = std::iter::once(&defaults.mobile_default_model)
            .chain(defaults.mobile_model_presets.iter())
            .chain(std::iter::once(&defaults.desktop_default_model))
            .chain(defaults.desktop_model_presets.iter())
            .chain([
                &defaults.transcription_model,
                &defaults.voice_activity_model,
            ]);
        let mut seen: HashMap<&str, (&str, Option<&str>)> = HashMap::new();
        for preset in all {
            let artifact = (preset.url.as_str(), preset.mmproj_url.as_deref());
            if let Some(existing) = seen.insert(preset.id.as_str(), artifact) {
                assert_eq!(
                    existing, artifact,
                    "preset id {} aliases different artifacts",
                    preset.id
                );
            }
        }
    }
}
