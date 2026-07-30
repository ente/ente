use ente_ensu::db;
use thiserror::Error;
use uuid::Uuid;

#[derive(Debug, Error, uniffi::Error)]
pub enum DbError {
    #[error("invalid encryption key length: expected {expected}, got {actual}")]
    InvalidKeyLength { expected: u64, actual: u64 },
    #[error("invalid blob length: expected at least {minimum} bytes, got {actual}")]
    InvalidBlobLength { minimum: u64, actual: u64 },
    #[error("invalid encrypted field format")]
    InvalidEncryptedField,
    #[error("unsupported value type: {detail}")]
    UnsupportedValueType { detail: String },
    #[error("row error: {detail}")]
    Row { detail: String },
    #[error("invalid sender: {detail}")]
    InvalidSender { detail: String },
    #[error("{entity} not found: {id}")]
    NotFound { entity: String, id: String },
    #[error("{detail}")]
    Crypto { detail: String },
    #[error("{detail}")]
    Json { detail: String },
    #[error("invalid UUID: {detail}")]
    InvalidUuid { detail: String },
    #[error("{detail}")]
    Utf8 { detail: String },
    #[error("{detail}")]
    Io { detail: String },
    #[error("database is readonly")]
    ReadonlyDatabase,
    #[error("{detail}")]
    Sqlite { detail: String },
    #[error("unsupported operation: {detail}")]
    UnsupportedOperation { detail: String },
    #[error("migration error: {detail}")]
    Migration { detail: String },
}

impl From<db::Error> for DbError {
    fn from(err: db::Error) -> Self {
        use db::Error as E;
        match err {
            E::InvalidKeyLength { expected, actual } => Self::InvalidKeyLength {
                expected: expected as u64,
                actual: actual as u64,
            },
            E::InvalidBlobLength { minimum, actual } => Self::InvalidBlobLength {
                minimum: minimum as u64,
                actual: actual as u64,
            },
            E::InvalidEncryptedField => Self::InvalidEncryptedField,
            E::UnsupportedValueType(detail) => Self::UnsupportedValueType { detail },
            E::Row(detail) => Self::Row { detail },
            E::InvalidSender(detail) => Self::InvalidSender { detail },
            E::NotFound { entity, id } => Self::NotFound {
                entity: format!("{entity:?}"),
                id: id.to_string(),
            },
            E::Crypto(err) => Self::Crypto {
                detail: err.to_string(),
            },
            E::Base64Decode(err) => Self::Crypto {
                detail: err.to_string(),
            },
            E::SerdeJson(err) => Self::Json {
                detail: err.to_string(),
            },
            E::Uuid(err) => Self::InvalidUuid {
                detail: err.to_string(),
            },
            E::Utf8(err) => Self::Utf8 {
                detail: err.to_string(),
            },
            E::Io(err) => Self::Io {
                detail: err.to_string(),
            },
            E::ReadonlyDatabase => Self::ReadonlyDatabase,
            E::Sqlite(err) => Self::Sqlite {
                detail: err.to_string(),
            },
            E::UnsupportedOperation(detail) => Self::UnsupportedOperation { detail },
            E::Migration(detail) => Self::Migration { detail },
        }
    }
}

fn invalid_uuid(err: uuid::Error) -> DbError {
    DbError::InvalidUuid {
        detail: err.to_string(),
    }
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct DbSession {
    pub uuid: String,
    pub title: String,
    pub created_at_us: i64,
    pub updated_at_us: i64,
}

#[derive(Debug, Clone, uniffi::Enum)]
pub enum DbSender {
    SelfUser,
    Other,
}

impl DbSender {
    fn as_str(&self) -> &'static str {
        match self {
            DbSender::SelfUser => "self",
            DbSender::Other => "other",
        }
    }
}

#[derive(Debug, Clone, uniffi::Enum)]
pub enum DbAttachmentKind {
    Image,
    Document,
}

impl From<DbAttachmentKind> for db::AttachmentKind {
    fn from(value: DbAttachmentKind) -> Self {
        match value {
            DbAttachmentKind::Image => db::AttachmentKind::Image,
            DbAttachmentKind::Document => db::AttachmentKind::Document,
        }
    }
}

impl From<db::AttachmentKind> for DbAttachmentKind {
    fn from(value: db::AttachmentKind) -> Self {
        match value {
            db::AttachmentKind::Image => DbAttachmentKind::Image,
            db::AttachmentKind::Document => DbAttachmentKind::Document,
        }
    }
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct DbAttachmentMeta {
    pub id: String,
    pub kind: DbAttachmentKind,
    pub size: i64,
    pub name: String,
}

impl From<DbAttachmentMeta> for db::AttachmentMeta {
    fn from(value: DbAttachmentMeta) -> Self {
        db::AttachmentMeta {
            id: value.id,
            kind: value.kind.into(),
            size: value.size,
            name: value.name,
        }
    }
}

impl From<db::AttachmentMeta> for DbAttachmentMeta {
    fn from(value: db::AttachmentMeta) -> Self {
        DbAttachmentMeta {
            id: value.id,
            kind: value.kind.into(),
            size: value.size,
            name: value.name,
        }
    }
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct DbMessage {
    pub uuid: String,
    pub session_uuid: String,
    pub parent_message_uuid: Option<String>,
    pub sender: DbSender,
    pub text: String,
    pub attachments: Vec<DbAttachmentMeta>,
    pub created_at_us: i64,
}

#[derive(uniffi::Object)]
pub struct EnsuDb {
    inner: db::ChatDb<db::SqliteBackend>,
}

fn to_session(session: db::Session) -> DbSession {
    DbSession {
        uuid: session.uuid.to_string(),
        title: session.title,
        created_at_us: session.created_at,
        updated_at_us: session.updated_at,
    }
}

fn to_message(message: db::Message) -> DbMessage {
    DbMessage {
        uuid: message.uuid.to_string(),
        session_uuid: message.session_uuid.to_string(),
        parent_message_uuid: message.parent_message_uuid.map(|v| v.to_string()),
        sender: match message.sender {
            db::Sender::SelfUser => DbSender::SelfUser,
            db::Sender::Other => DbSender::Other,
        },
        text: message.text,
        attachments: message.attachments.into_iter().map(Into::into).collect(),
        created_at_us: message.created_at,
    }
}

#[uniffi::export]
impl EnsuDb {
    #[uniffi::constructor]
    pub fn open(main_db_path: String, key: Vec<u8>) -> Result<Self, DbError> {
        let inner = db::ChatDb::open_sqlite_with_defaults(main_db_path, key)?;
        Ok(Self { inner })
    }

    pub fn create_session(&self, title: String) -> Result<DbSession, DbError> {
        Ok(to_session(self.inner.create_session(&title)?))
    }

    pub fn list_sessions(&self) -> Result<Vec<DbSession>, DbError> {
        Ok(self
            .inner
            .list_sessions()?
            .into_iter()
            .map(to_session)
            .collect())
    }

    pub fn get_session(&self, uuid: String) -> Result<Option<DbSession>, DbError> {
        let uuid = Uuid::parse_str(&uuid).map_err(invalid_uuid)?;
        Ok(self.inner.get_session(uuid)?.map(to_session))
    }

    pub fn delete_session(&self, uuid: String) -> Result<Vec<String>, DbError> {
        let uuid = Uuid::parse_str(&uuid).map_err(invalid_uuid)?;
        Ok(self.inner.delete_session(uuid)?)
    }

    pub fn update_session_title(&self, uuid: String, title: String) -> Result<(), DbError> {
        let uuid = Uuid::parse_str(&uuid).map_err(invalid_uuid)?;
        Ok(self.inner.update_session_title(uuid, &title)?)
    }

    pub fn insert_message(
        &self,
        session_uuid: String,
        sender: DbSender,
        text: String,
        parent_message_uuid: Option<String>,
        attachments: Vec<DbAttachmentMeta>,
    ) -> Result<DbMessage, DbError> {
        let session_uuid = Uuid::parse_str(&session_uuid).map_err(invalid_uuid)?;
        let parent = parent_message_uuid
            .map(|v| Uuid::parse_str(&v))
            .transpose()
            .map_err(invalid_uuid)?;

        let message = self.inner.insert_message(
            session_uuid,
            sender.as_str(),
            &text,
            parent,
            attachments.into_iter().map(Into::into).collect(),
        )?;
        Ok(to_message(message))
    }

    pub fn get_messages(&self, session_uuid: String) -> Result<Vec<DbMessage>, DbError> {
        let session_uuid = Uuid::parse_str(&session_uuid).map_err(invalid_uuid)?;
        Ok(self
            .inner
            .get_messages(session_uuid)?
            .into_iter()
            .map(to_message)
            .collect())
    }

    pub fn update_message_text(&self, uuid: String, text: String) -> Result<(), DbError> {
        let uuid = Uuid::parse_str(&uuid).map_err(invalid_uuid)?;
        Ok(self.inner.update_message_text(uuid, &text)?)
    }
}
