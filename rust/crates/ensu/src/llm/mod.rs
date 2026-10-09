mod chat_template_bridge;
mod context;
mod embed;
mod event;
mod generate;
mod history;
pub mod memory;
mod model;
mod template;
mod worker;

pub use context::*;
pub use event::*;
pub use generate::*;
pub use history::*;
pub use model::*;

use llama_cpp_2::llama_backend::LlamaBackend;
use std::sync::{Mutex, MutexGuard, OnceLock, PoisonError};

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("Generation cancelled")]
    Cancelled,
    #[error("Generation panicked")]
    Panicked,
    #[error("{0}")]
    InvalidInput(String),
    #[error("{what} not found at {path}")]
    NotFound { what: &'static str, path: String },
    #[error("{0}")]
    Unsupported(&'static str),
    #[error("Prompt length {tokens} exceeds context size {context_size}")]
    PromptTooLong { tokens: usize, context_size: u32 },
    #[error("{op}: {message}")]
    Llama { op: &'static str, message: String },
}

static BACKEND: OnceLock<Result<LlamaBackend, String>> = OnceLock::new();

fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex.lock().unwrap_or_else(PoisonError::into_inner)
}

fn backend() -> Result<&'static LlamaBackend, Error> {
    #[cfg(all(target_os = "android", target_arch = "aarch64"))]
    let result = BACKEND.get().ok_or_else(|| {
        Error::InvalidInput(
            "Initialize CPU backends from nativeLibraryDir before loading a model".to_owned(),
        )
    })?;
    #[cfg(not(all(target_os = "android", target_arch = "aarch64")))]
    let result = BACKEND.get_or_init(|| LlamaBackend::init().map_err(|err| err.to_string()));
    match result {
        Ok(backend) => Ok(backend),
        Err(err) => Err(Error::Llama {
            op: "Failed to initialize backend",
            message: err.clone(),
        }),
    }
}

pub fn init_backend_from_directory(directory: &str) -> Result<(), Error> {
    #[cfg(all(target_os = "android", target_arch = "aarch64"))]
    {
        let path = std::path::Path::new(directory);
        if directory.contains('\0') || !path.is_absolute() || !path.is_dir() {
            return Err(Error::InvalidInput(
                "Invalid native-library directory".to_owned(),
            ));
        }
        if !path.join("libggml-cpu-android_armv8.0_1.so").is_file() {
            return Err(Error::InvalidInput(
                "Baseline CPU backend is missing from nativeLibraryDir".to_owned(),
            ));
        }
        BACKEND.get_or_init(|| {
            llama_cpp_2::llama_backend::load_backends_from_path(path);
            if !cpu_backend_available() {
                return Err(
                    "No compatible CPU backend could be loaded from nativeLibraryDir".to_owned(),
                );
            }
            LlamaBackend::init().map_err(|err| err.to_string())
        });
    }
    #[cfg(not(all(target_os = "android", target_arch = "aarch64")))]
    let _ = directory;
    backend().map(|_| ())
}

#[cfg(all(target_os = "android", target_arch = "aarch64"))]
fn cpu_backend_available() -> bool {
    llama_cpp_2::list_llama_ggml_backend_devices()
        .iter()
        .any(|device| device.device_type == llama_cpp_2::LlamaBackendDeviceType::Cpu)
}

fn format_error(context: &str, err: impl std::fmt::Display) -> String {
    format!("{context}: {err}")
}
