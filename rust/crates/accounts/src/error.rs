//! Shared error types for account flows.

use base64::DecodeError;
use ente_core::{auth::AuthError, crypto::CryptoError, http::Error as HttpError};
use thiserror::Error;

/// Result alias for the shared account crate.
pub type Result<T> = std::result::Result<T, Error>;

/// Errors emitted by the shared account crate.
#[derive(Error, Debug)]
pub enum Error {
    /// HTTP/transport or server error.
    #[error("{0}")]
    Http(#[from] HttpError),

    /// Serialization/deserialization error.
    #[error("Serialization error: {0}")]
    Serialization(#[from] serde_json::Error),

    /// Wrapped cryptographic error.
    #[error("Crypto error: {0}")]
    Crypto(String),

    /// Account/authentication failure.
    #[error("Authentication failed: {0}")]
    AuthenticationFailed(String),

    /// Invalid input.
    #[error("Invalid input: {0}")]
    InvalidInput(String),

    /// SRP-specific failure.
    #[error("SRP error: {0}")]
    Srp(String),

    /// Base64 decode error.
    #[error("Base64 decode error: {0}")]
    Base64Decode(#[from] DecodeError),

    /// Fallback catch-all.
    #[error("{0}")]
    Generic(String),
}

impl Error {
    /// Return the HTTP status code if the error came from the API.
    pub fn status_code(&self) -> Option<u16> {
        match self {
            Error::Http(HttpError::Http { status, .. }) => Some(*status),
            _ => None,
        }
    }

    /// Return the structured server error code if available.
    pub fn api_code(&self) -> Option<&str> {
        match self {
            Error::Http(HttpError::Http { code, .. }) => code.as_deref(),
            _ => None,
        }
    }

    /// Return the server-provided message if available.
    pub fn api_message(&self) -> Option<&str> {
        match self {
            Error::Http(HttpError::Http { message, .. }) => Some(message.as_str()),
            _ => None,
        }
    }

    /// Convenience helper for matching one of several HTTP status codes.
    pub fn is_http_status(&self, statuses: &[u16]) -> bool {
        self.status_code()
            .is_some_and(|status| statuses.contains(&status))
    }
}

impl From<CryptoError> for Error {
    fn from(err: CryptoError) -> Self {
        match err {
            CryptoError::Base64Decode(source) => Error::Base64Decode(source),
            CryptoError::Io(source) => Error::Generic(source.to_string()),
            other => Error::Crypto(other.to_string()),
        }
    }
}

impl From<AuthError> for Error {
    fn from(err: AuthError) -> Self {
        match err {
            AuthError::IncorrectPassword => {
                Error::AuthenticationFailed("Incorrect password".to_string())
            }
            AuthError::IncorrectRecoveryKey => {
                Error::AuthenticationFailed("Incorrect recovery key".to_string())
            }
            AuthError::InvalidKeyAttributes => Error::Crypto(err.to_string()),
            AuthError::InsufficientMemory => Error::Crypto(err.to_string()),
            AuthError::MissingField(field) => Error::Crypto(format!("Missing field: {field}")),
            AuthError::Crypto(source) => source.into(),
            AuthError::Decode(msg) => Error::Crypto(msg),
            AuthError::InvalidKey(msg) => Error::Crypto(msg),
            AuthError::Srp(msg) => Error::Srp(msg),
        }
    }
}
