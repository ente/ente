use ente_accounts::Error as AccountsError;
use ente_core::{auth::AuthError, crypto::CryptoError};
use thiserror::Error;

#[derive(Error, Debug)]
pub enum Error {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Network error: {0}")]
    Network(#[from] reqwest::Error),

    #[error("Serialization error: {0}")]
    Serialization(#[from] serde_json::Error),

    #[error("Database error: {0}")]
    Database(#[from] rusqlite::Error),

    #[error("Crypto error: {0}")]
    Crypto(String),

    #[error("Authentication failed: {0}")]
    AuthenticationFailed(String),

    #[error("Invalid configuration: {0}")]
    InvalidConfig(String),

    #[error("Not found: {0}")]
    NotFound(String),

    #[error("Invalid input: {0}")]
    InvalidInput(String),

    #[error("SRP error: {0}")]
    Srp(String),

    #[error("Base64 decode error: {0}")]
    Base64Decode(#[from] base64::DecodeError),

    #[error("ZIP error: {0}")]
    Zip(#[from] zip::result::ZipError),

    #[error("API error ({status}): {message}")]
    ApiError {
        status: u16,
        code: Option<String>,
        message: String,
    },

    #[error("{0}")]
    Generic(String),
}

impl From<CryptoError> for Error {
    fn from(err: CryptoError) -> Self {
        match err {
            CryptoError::Base64Decode(source) => Error::Base64Decode(source),
            CryptoError::Io(source) => Error::Io(source),
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

impl From<AccountsError> for Error {
    fn from(err: AccountsError) -> Self {
        match err {
            AccountsError::Http(ente_core::http::Error::Http {
                status,
                code,
                message,
            }) => Error::ApiError {
                status,
                code,
                message,
            },
            AccountsError::Http(ente_core::http::Error::Network(message)) => {
                Error::Generic(format!("Network error: {message}"))
            }
            AccountsError::Http(ente_core::http::Error::Parse(message)) => {
                Error::Generic(format!("JSON parse error: {message}"))
            }
            AccountsError::Http(ente_core::http::Error::InvalidUrl(message)) => {
                Error::InvalidConfig(message)
            }
            AccountsError::Serialization(source) => Error::Serialization(source),
            AccountsError::Crypto(message) => Error::Crypto(message),
            AccountsError::AuthenticationFailed(message) => Error::AuthenticationFailed(message),
            AccountsError::InvalidInput(message) => Error::InvalidInput(message),
            AccountsError::Srp(message) => Error::Srp(message),
            AccountsError::Base64Decode(source) => Error::Base64Decode(source),
            AccountsError::Generic(message) => Error::Generic(message),
        }
    }
}

pub type Result<T> = std::result::Result<T, Error>;
