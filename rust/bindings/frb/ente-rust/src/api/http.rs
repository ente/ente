//! FRB bindings for the HTTP client

use ente_core::http::{Error as CoreError, HttpClient as CoreHttpClient};
use flutter_rust_bridge::frb;

/// HTTP client errors.
#[frb]
pub enum HttpError {
    /// Network error - connection failed, timeout, etc.
    Network {
        /// Error message.
        message: String,
    },
    /// Server return an HTTP error status.
    Http {
        /// Error message.
        message: String,
        /// HTTP status code.
        status: u16,
    },
    /// Failed to parse response.
    Parse {
        /// Error message.
        message: String,
    },
    /// Invalid base URL or request path.
    InvalidUrl {
        /// Error message.
        message: String,
    },
}

impl From<CoreError> for HttpError {
    fn from(e: CoreError) -> Self {
        match e {
            CoreError::Network(message) => HttpError::Network { message },
            CoreError::Http {
                status, message, ..
            } => HttpError::Http { status, message },
            CoreError::Parse(message) => HttpError::Parse { message },
            CoreError::InvalidUrl(message) => HttpError::InvalidUrl { message },
        }
    }
}

/// HTTP client for making requests to the Ente API.
#[frb(opaque)]
pub struct HttpClient {
    inner: CoreHttpClient,
}

impl HttpClient {
    /// Create a client with the given base URL.
    #[frb(sync)]
    pub fn new(base_url: String) -> HttpClient {
        Self {
            inner: CoreHttpClient::new(&base_url).expect("failed to build HTTP client"),
        }
    }

    /// GET request, returns response body as text.
    pub async fn get(&self, path: String) -> Result<String, HttpError> {
        self.inner.get(&path).await.map_err(|e| e.into())
    }
}
