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

    #[error(transparent)]
    Accounts(#[from] ente_accounts::Error),

    #[error("invalid input: {0}")]
    InvalidInput(String),

    #[error("legacy contact is not on Ente")]
    ContactNotOnEnte,

    #[error("a recovery is already in progress")]
    ActiveRecoverySession,

    #[error("legacy kit is inactive")]
    LegacyKitInactive,
}

pub type Result<T> = std::result::Result<T, Error>;
