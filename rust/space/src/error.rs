use ente_core::{auth::AuthError, crypto::Error as CryptoError, http::Error as HttpError};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum SpaceError {
    #[error(transparent)]
    Http(#[from] HttpError),

    #[error(transparent)]
    Crypto(#[from] CryptoError),

    #[error(transparent)]
    Auth(#[from] AuthError),

    #[error("invalid input: {0}")]
    InvalidInput(String),

    #[error("missing secret key material")]
    MissingSecretKey,

    #[error("missing friend sealed space key")]
    MissingFriendSealedSpaceKey,

    #[error("entity key conflict")]
    EntityKeyConflict,
}

impl SpaceError {
    pub fn is_unavailable_record(&self) -> bool {
        matches!(
            self,
            Self::Crypto(_) | Self::InvalidInput(_) | Self::MissingFriendSealedSpaceKey
        )
    }
}

pub type Result<T> = std::result::Result<T, SpaceError>;
