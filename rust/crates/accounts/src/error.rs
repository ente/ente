//! Shared error types for account flows.

use ente_core::{b64, crypto, http};
use thiserror::Error;

use crate::auth;

/// Result alias for the shared account crate.
pub type Result<T> = std::result::Result<T, Error>;

/// Errors emitted by the shared account crate.
#[derive(Error, Debug)]
pub enum Error {
    /// HTTP/transport or server error.
    #[error(transparent)]
    Http(#[from] http::Error),

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
    Base64Decode(#[from] b64::DecodeError),

    /// Fallback catch-all.
    #[error("{0}")]
    Generic(String),
}

impl Error {
    /// Return the HTTP status code if the error came from the API.
    pub fn status_code(&self) -> Option<u16> {
        match self {
            Error::Http(error) => error.status_code(),
            _ => None,
        }
    }

    /// Convenience helper for matching one of several HTTP status codes.
    pub fn is_http_status(&self, statuses: &[u16]) -> bool {
        self.status_code()
            .is_some_and(|status| statuses.contains(&status))
    }
}

impl From<crypto::Error> for Error {
    fn from(err: crypto::Error) -> Self {
        match err {
            crypto::Error::Io(source) => Error::Generic(source.to_string()),
            other => Error::Crypto(other.to_string()),
        }
    }
}

impl From<auth::Error> for Error {
    fn from(err: auth::Error) -> Self {
        use auth::Error as E;
        match err {
            E::IncorrectPassword => Error::AuthenticationFailed("Incorrect password".to_string()),
            E::IncorrectRecoveryKey => {
                Error::AuthenticationFailed("Incorrect recovery key".to_string())
            }
            E::InvalidKeyAttributes => Error::Crypto(err.to_string()),
            E::InsufficientMemory => Error::Crypto(err.to_string()),
            E::MissingField(field) => Error::Crypto(format!("Missing field: {field}")),
            E::Crypto(source) => source.into(),
            E::Decode(msg) => Error::Crypto(msg),
            E::InvalidKey(msg) => Error::Crypto(msg),
            E::Srp(msg) => Error::Srp(msg),
        }
    }
}
