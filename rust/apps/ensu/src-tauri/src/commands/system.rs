use serde::Serialize;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SystemInfo {
    platform: String,
    total_memory_bytes: Option<u64>,
}

#[tauri::command]
pub fn system_info() -> SystemInfo {
    SystemInfo {
        platform: std::env::consts::OS.to_string(),
        total_memory_bytes: crate::platform::total_memory_bytes(),
    }
}
