use ente_core::{Session, crypto::Key};
use serde::Deserialize;

use crate::source::{self, Documents, MetadataError};

pub use ente_collections::client::Collection as RemoteCollection;

#[derive(Debug)]
pub struct Collection {
    pub id: i64,
    pub key: Key,
    pub name: String,
    pub kind: Kind,
    pub visibility: Visibility,
    pub owner_id: i64,
    pub updated_at_micros: i64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Album,
    Folder,
    Favorites,
    Uncategorized,
    DefaultHidden,
    Quicklink,
}

impl Kind {
    pub fn name(self) -> &'static str {
        match self {
            Self::Album => "album",
            Self::Folder => "folder",
            Self::Favorites => "favorites",
            Self::Uncategorized => "uncategorized",
            Self::DefaultHidden => "defaultHidden",
            Self::Quicklink => "quicklink",
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub enum Visibility {
    Visible,
    Archived,
    Hidden,
}

impl Visibility {
    pub fn name(self) -> &'static str {
        match self {
            Self::Visible => "visible",
            Self::Archived => "archived",
            Self::Hidden => "hidden",
        }
    }

    pub fn from_value(value: Option<u8>) -> Result<Self, MetadataError> {
        match value.unwrap_or(0) {
            0 => Ok(Self::Visible),
            1 => Ok(Self::Archived),
            2 => Ok(Self::Hidden),
            _ => Err(MetadataError("unsupported visibility")),
        }
    }
}

pub fn decrypt(
    remote: &RemoteCollection,
    session: &Session,
) -> Result<(Key, Documents), ente_collections::Error> {
    let key = remote.open_key(session)?;
    let original = remote.open_name_bytes(&key)?;
    let documents = Documents {
        original,
        public: remote
            .pub_magic_metadata
            .as_ref()
            .map(|m| m.decrypt(&key))
            .transpose()?,
        private: remote
            .magic_metadata
            .as_ref()
            .map(|m| m.decrypt(&key))
            .transpose()?,
        shared: remote
            .shared_magic_metadata
            .as_ref()
            .map(|m| m.decrypt(&key))
            .transpose()?,
    };
    Ok((key, documents))
}

pub fn interpret(
    remote: &RemoteCollection,
    key: &Key,
    documents: &Documents,
    user_id: i64,
) -> Result<Collection, MetadataError> {
    let owned = remote.owner.id == user_id;
    let private: PrivateMetadata = source::optional(
        documents.private.as_deref(),
        "invalid album private metadata",
    )?;
    let shared: ShareeMetadata =
        source::optional(documents.shared.as_deref(), "invalid album sharee metadata")?;
    let kind = match (
        owned.then_some(private.sub_type).flatten().unwrap_or(0),
        remote.kind.as_str(),
    ) {
        (1, _) => Kind::DefaultHidden,
        (2, _) => Kind::Quicklink,
        (0, "album") => Kind::Album,
        (0, "folder") => Kind::Folder,
        (0, "favorites") => Kind::Favorites,
        (0, "uncategorized") => Kind::Uncategorized,
        (0, "quicklink") => Kind::Quicklink,
        _ => return Err(MetadataError("unsupported album type")),
    };
    let visibility = if kind == Kind::DefaultHidden {
        Visibility::Hidden
    } else {
        Visibility::from_value(if owned {
            private.visibility
        } else {
            shared.visibility
        })?
    };
    Ok(Collection {
        id: remote.id,
        key: Key::from_bytes(*key.as_bytes()),
        name: if kind == Kind::DefaultHidden {
            "Hidden".to_owned()
        } else {
            String::from_utf8(documents.original.clone())
                .map_err(|_| MetadataError("album name is not UTF-8"))?
        },
        kind,
        visibility,
        owner_id: remote.owner.id,
        updated_at_micros: remote.updation_time,
    })
}

#[derive(Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PrivateMetadata {
    visibility: Option<u8>,
    sub_type: Option<u8>,
}

#[derive(Default, Deserialize)]
struct ShareeMetadata {
    visibility: Option<u8>,
}
