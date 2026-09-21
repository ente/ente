use ente_core::{Session, crypto::Key};
use serde::Deserialize;

const DEFAULT_HIDDEN_SUBTYPE: u8 = 1;
const ARCHIVED_VISIBILITY: u8 = 1;
const HIDDEN_VISIBILITY: u8 = 2;

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

#[derive(Debug, Clone, Copy)]
pub enum Kind {
    Album,
    Favorites,
    Uncategorized,
}

impl Kind {
    pub fn name(self) -> &'static str {
        match self {
            Self::Album => "album",
            Self::Favorites => "favorites",
            Self::Uncategorized => "uncategorized",
        }
    }
}

#[derive(Debug)]
pub enum Visibility {
    Visible,
    Archived,
    Hidden,
}

impl Visibility {
    pub fn name(&self) -> &'static str {
        match self {
            Self::Visible => "visible",
            Self::Archived => "archived",
            Self::Hidden => "hidden",
        }
    }
}

pub type Error = ente_collections::Error;

pub struct Change {
    pub id: i64,
    pub collection: Option<Collection>,
}

pub struct Page {
    pub changes: Vec<Change>,
    pub cursor: i64,
}

pub async fn diff(session: &Session, since: i64) -> Result<Page, Error> {
    let page = ente_collections::client::diff(session, since).await?;
    let changes = page
        .collections
        .into_iter()
        .map(|remote| {
            Ok(Change {
                id: remote.id,
                collection: if remote.is_deleted == Some(true) {
                    None
                } else {
                    Some(Collection::open(remote, session)?)
                },
            })
        })
        .collect::<Result<_, Error>>()?;
    Ok(Page {
        changes,
        cursor: page.cursor,
    })
}

pub async fn list(session: &Session) -> Result<Vec<Collection>, Error> {
    Ok(diff(session, 0)
        .await?
        .changes
        .into_iter()
        .filter_map(|change| change.collection)
        .collect())
}

impl Collection {
    fn open(
        remote: ente_collections::client::Collection,
        session: &Session,
    ) -> Result<Self, Error> {
        let key = remote.open_key(session)?;
        let name = remote.open_name(&key)?;
        let owned = remote.owner.id == session.user_id;
        let metadata = if owned {
            remote.magic_metadata.as_ref()
        } else {
            remote.shared_magic_metadata.as_ref()
        };
        let visibility = match metadata {
            Some(metadata) => {
                let metadata: Metadata = metadata.open(&key)?;
                if owned && metadata.sub_type == Some(DEFAULT_HIDDEN_SUBTYPE) {
                    HIDDEN_VISIBILITY
                } else {
                    metadata.visibility.unwrap_or(0)
                }
            }
            None => 0,
        };
        Ok(Self {
            id: remote.id,
            key,
            name,
            kind: match remote.kind.as_str() {
                "favorites" => Kind::Favorites,
                "uncategorized" => Kind::Uncategorized,
                _ => Kind::Album,
            },
            visibility: match visibility {
                ARCHIVED_VISIBILITY => Visibility::Archived,
                HIDDEN_VISIBILITY => Visibility::Hidden,
                _ => Visibility::Visible,
            },
            owner_id: remote.owner.id,
            updated_at_micros: remote.updation_time,
        })
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Metadata {
    visibility: Option<u8>,
    sub_type: Option<u8>,
}
