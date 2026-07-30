#![forbid(unsafe_code)]

pub mod backend;
pub mod chat;
pub mod crypto;
pub mod error;
pub mod models;
pub mod traits;

pub use crate::db::backend::{Backend, BackendTx, Row, Value};
pub use crate::db::chat::ChatDb;
pub use crate::db::error::{Error, Result};
pub use crate::db::models::{
    AttachmentKind, AttachmentMeta, EntityType, Message, Sender, Session, SessionWithPreview,
};
pub use crate::db::traits::{Clock, RandomUuidGen, SystemClock, UuidGen};

#[cfg(feature = "sqlite")]
pub use crate::db::backend::sqlite::SqliteBackend;
