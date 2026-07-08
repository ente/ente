//! WASM bindings for the HTTP client.

use ente_core::http::{Error as CoreError, HttpClient as CoreHttpClient};
use wasm_bindgen::prelude::*;

/// HTTP client error.
#[wasm_bindgen]
pub struct HttpError {
    code: String,
    message: String,
    status: Option<u16>,
}

#[wasm_bindgen]
impl HttpError {
    /// Error code: "invalid_url", "network", "http", or "parse".
    #[wasm_bindgen(getter)]
    pub fn code(&self) -> String {
        self.code.clone()
    }

    /// Error message.
    #[wasm_bindgen(getter)]
    pub fn message(&self) -> String {
        self.message.clone()
    }

    /// HTTP status code (only for "http" errors).
    #[wasm_bindgen(getter)]
    pub fn status(&self) -> Option<u16> {
        self.status
    }
}

impl From<CoreError> for HttpError {
    fn from(e: CoreError) -> Self {
        match e {
            CoreError::InvalidUrl(message) => HttpError {
                code: "invalid_url".to_string(),
                message,
                status: None,
            },
            CoreError::Network(message) => HttpError {
                code: "network".to_string(),
                message,
                status: None,
            },
            CoreError::Http {
                status, message, ..
            } => HttpError {
                code: "http".to_string(),
                message,
                status: Some(status),
            },
            CoreError::Parse(message) => HttpError {
                code: "parse".to_string(),
                message,
                status: None,
            },
        }
    }
}

/// HTTP client for making requests to the Ente API.
#[wasm_bindgen]
pub struct HttpClient {
    inner: CoreHttpClient,
}

#[wasm_bindgen]
impl HttpClient {
    /// Create a client with the given base URL.
    #[wasm_bindgen(constructor)]
    pub fn new(base_url: &str) -> Self {
        Self {
            inner: CoreHttpClient::new(base_url).expect("failed to build HTTP client"),
        }
    }

    /// GET request, returns response body as text.
    pub async fn get(&self, path: &str) -> Result<String, HttpError> {
        self.inner.get(path).await.map_err(|e| e.into())
    }
}
