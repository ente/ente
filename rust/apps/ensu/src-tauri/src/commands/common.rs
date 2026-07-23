use std::path::PathBuf;

use serde::Serialize;
use tauri::{AppHandle, Manager};

use crate::logging;

#[derive(Debug, Serialize)]
pub struct ApiError {
    pub(crate) code: String,
    pub(crate) message: String,
}

impl ApiError {
    pub(crate) fn new(code: &str, message: impl Into<String>) -> Self {
        Self {
            code: code.to_string(),
            message: message.into(),
        }
    }
}

pub(crate) fn panic_message(payload: Box<dyn std::any::Any + Send>) -> String {
    match payload.downcast::<String>() {
        Ok(message) => *message,
        Err(payload) => match payload.downcast::<&'static str>() {
            Ok(message) => (*message).to_string(),
            Err(_) => "non-string panic payload".to_string(),
        },
    }
}

pub(crate) fn log_command_panic(command: &str, message: &str) {
    logging::log("Panic", format!("command={command} panic={message}"));
}

pub(crate) fn app_data_dir(app: &AppHandle) -> Result<PathBuf, ApiError> {
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|err| ApiError::new("path", err.to_string()))?;
    std::fs::create_dir_all(&dir).map_err(|err| ApiError::new("io", err.to_string()))?;
    Ok(dir)
}
