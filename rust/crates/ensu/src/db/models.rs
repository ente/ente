use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Session {
    pub uuid: Uuid,
    pub title: String,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionWithPreview {
    pub uuid: Uuid,
    pub title: String,
    pub created_at: i64,
    pub updated_at: i64,
    pub last_message_preview: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Message {
    pub uuid: Uuid,
    pub session_uuid: Uuid,
    pub parent_message_uuid: Option<Uuid>,
    pub sender: Sender,
    pub text: String,
    pub attachments: Vec<AttachmentMeta>,
    pub created_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AttachmentMeta {
    pub id: String,
    pub kind: AttachmentKind,
    pub size: i64,
    pub name: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AttachmentKind {
    Image,
    Document,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Sender {
    SelfUser,
    Other,
}

impl Sender {
    pub fn as_str(&self) -> &'static str {
        match self {
            Sender::SelfUser => "self",
            Sender::Other => "other",
        }
    }
}

impl std::str::FromStr for Sender {
    type Err = crate::db::Error;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "self" => Ok(Sender::SelfUser),
            "other" => Ok(Sender::Other),
            _ => Err(crate::db::Error::InvalidSender(value.to_string())),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EntityType {
    Session,
    Message,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct StoredAttachment {
    pub id: String,
    pub kind: AttachmentKind,
    pub size: i64,
    pub encrypted_name: String,
}
