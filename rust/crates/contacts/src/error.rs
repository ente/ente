use ente_core::{b64, crypto, http};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum Error {
    #[error(transparent)]
    Http(#[from] http::Error),

    #[error(transparent)]
    Crypto(#[from] crypto::Error),

    #[error("base64 decode error: {0}")]
    Base64Decode(#[from] b64::DecodeError),

    #[error("invalid input: {0}")]
    InvalidInput(String),

    #[error("missing encrypted data for live contact")]
    MissingEncryptedData,

    #[error("missing encrypted key for live contact")]
    MissingEncryptedKey,

    #[error("profile picture not found")]
    ProfilePictureNotFound,
}

pub type Result<T> = std::result::Result<T, Error>;
