use thiserror::Error;

use crate::db::models::EntityType;

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Error, Debug)]
pub enum Error {
    #[error("invalid encryption key length: expected {expected}, got {actual}")]
    InvalidKeyLength { expected: usize, actual: usize },

    #[error("invalid blob length: expected at least {minimum} bytes, got {actual}")]
    InvalidBlobLength { minimum: usize, actual: usize },

    #[error("invalid encrypted field format")]
    InvalidEncryptedField,

    #[error("unsupported value type: {0}")]
    UnsupportedValueType(String),

    #[error("row error: {0}")]
    Row(String),

    #[error("invalid sender: {0}")]
    InvalidSender(String),

    #[error("{entity:?} not found: {id}")]
    NotFound { entity: EntityType, id: uuid::Uuid },

    #[error(transparent)]
    Crypto(#[from] ente_core::crypto::CryptoError),

    #[error(transparent)]
    SerdeJson(#[from] serde_json::Error),

    #[error(transparent)]
    Uuid(#[from] uuid::Error),

    #[error(transparent)]
    Utf8(#[from] std::string::FromUtf8Error),

    #[error(transparent)]
    Io(#[from] std::io::Error),

    #[error("database is readonly")]
    ReadonlyDatabase,

    #[cfg(feature = "sqlite")]
    #[error(transparent)]
    Sqlite(rusqlite::Error),

    #[error("unsupported operation: {0}")]
    UnsupportedOperation(String),

    #[error("migration error: {0}")]
    Migration(String),
}

#[cfg(feature = "sqlite")]
impl From<rusqlite::Error> for Error {
    fn from(err: rusqlite::Error) -> Self {
        match &err {
            rusqlite::Error::SqliteFailure(failure, _)
                if failure.code == rusqlite::ErrorCode::ReadOnly =>
            {
                Error::ReadonlyDatabase
            }
            _ => Error::Sqlite(err),
        }
    }
}
