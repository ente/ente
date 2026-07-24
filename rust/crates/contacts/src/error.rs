use ente_accounts::auth::AuthError;
use ente_core::{crypto, http};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum ContactsError {
    #[error(transparent)]
    Http(#[from] http::Error),

    #[error(transparent)]
    Crypto(#[from] crypto::Error),

    #[error(transparent)]
    Auth(#[from] AuthError),

    #[error("invalid input: {0}")]
    InvalidInput(String),

    #[error("missing encrypted data for live contact")]
    MissingEncryptedData,

    #[error("missing encrypted key for live contact")]
    MissingEncryptedKey,

    #[error("profile picture not found")]
    ProfilePictureNotFound,

    #[error("a recovery is already in progress")]
    ActiveRecoverySession,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ErrorKind {
    Network,
    Http,
    Parse,
    Crypto,
    Auth,
    InvalidInput,
    MissingEncryptedData,
    MissingEncryptedKey,
    ProfilePictureNotFound,
    ActiveRecoverySession,
}

impl ContactsError {
    pub fn kind(&self) -> ErrorKind {
        match self {
            ContactsError::Http(http::Error::Network(_)) => ErrorKind::Network,
            ContactsError::Http(http::Error::Parse(_)) => ErrorKind::Parse,
            ContactsError::Http(_) => ErrorKind::Http,
            ContactsError::Crypto(_) => ErrorKind::Crypto,
            ContactsError::Auth(_) => ErrorKind::Auth,
            ContactsError::InvalidInput(_) => ErrorKind::InvalidInput,
            ContactsError::MissingEncryptedData => ErrorKind::MissingEncryptedData,
            ContactsError::MissingEncryptedKey => ErrorKind::MissingEncryptedKey,
            ContactsError::ProfilePictureNotFound => ErrorKind::ProfilePictureNotFound,
            ContactsError::ActiveRecoverySession => ErrorKind::ActiveRecoverySession,
        }
    }

    /// The HTTP status, when the server answered with one.
    pub fn status(&self) -> Option<u16> {
        match self {
            ContactsError::Http(error) => error.status_code(),
            _ => None,
        }
    }
}

pub type Result<T> = std::result::Result<T, ContactsError>;
