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

    #[error("missing secret key material")]
    MissingSecretKey,

    #[error("missing friend sealed space key")]
    MissingFriendSealedSpaceKey,

    #[error("entity key conflict")]
    EntityKeyConflict,

    #[error("space limit reached")]
    SpaceLimitReached,

    #[error("space slug already exists")]
    SpaceSlugAlreadyExists,

    #[error("space slug is reserved")]
    SpaceSlugReserved,

    #[error("invalid space slug")]
    InvalidSpaceSlug,

    #[error("space post limit reached")]
    PostLimitReached,

    #[error("space session is unauthorized")]
    SessionUnauthorized,

    #[error("permission denied")]
    PermissionDenied,
}

impl Error {
    pub fn is_content_error(&self) -> bool {
        matches!(
            self,
            Self::Crypto(_)
                | Self::Base64Decode(_)
                | Self::InvalidInput(_)
                | Self::MissingFriendSealedSpaceKey
        )
    }
}

pub type Result<T> = std::result::Result<T, Error>;
