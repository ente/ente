use ente_ensu::db;
use thiserror::Error;
use uuid::Uuid;

#[derive(Debug, Error, uniffi::Error)]
pub enum DbError {
    #[error("database is readonly")]
    ReadonlyDatabase,
    #[error("{detail}")]
    Other { detail: String },
}

impl From<db::Error> for DbError {
    fn from(error: db::Error) -> Self {
        match error {
            db::Error::ReadonlyDatabase => Self::ReadonlyDatabase,
            error => Self::Other {
                detail: ente_core::error::chain(&error),
            },
        }
    }
}

fn parse_uuid(value: &str) -> db::Result<Uuid> {
    Ok(Uuid::parse_str(value)?)
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
        let uuid = parse_uuid(&uuid)?;
        Ok(self.inner.get_session(uuid)?.map(to_session))
    }

    pub fn delete_session(&self, uuid: String) -> Result<Vec<String>, DbError> {
        let uuid = parse_uuid(&uuid)?;
        Ok(self.inner.delete_session(uuid)?)
    }

    pub fn update_session_title(&self, uuid: String, title: String) -> Result<(), DbError> {
        let uuid = parse_uuid(&uuid)?;
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
        let session_uuid = parse_uuid(&session_uuid)?;
        let parent = parent_message_uuid.as_deref().map(parse_uuid).transpose()?;

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
        let session_uuid = parse_uuid(&session_uuid)?;
        Ok(self
            .inner
            .get_messages(session_uuid)?
            .into_iter()
            .map(to_message)
            .collect())
    }

    pub fn update_message_text(&self, uuid: String, text: String) -> Result<(), DbError> {
        let uuid = parse_uuid(&uuid)?;
        Ok(self.inner.update_message_text(uuid, &text)?)
    }
}
