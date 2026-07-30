mod context;
mod embed;
mod event;
mod generate;
mod model;

pub use context::*;
pub use event::*;
pub use generate::*;
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
    match BACKEND.get_or_init(|| LlamaBackend::init().map_err(|err| err.to_string())) {
        Ok(backend) => Ok(backend),
        Err(err) => Err(Error::Llama {
            op: "Failed to initialize backend",
            message: err.clone(),
        }),
    }
}

fn format_error(context: &str, err: impl std::fmt::Display) -> String {
    format!("{context}: {err}")
}
