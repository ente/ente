use ente_core::{
    Session, b64,
    crypto::{self, Header, Key, blob},
    http,
};
use serde::Deserialize;

use crate::collections::{Collection, Visibility};

#[derive(Debug)]
pub struct File {
    pub id: i64,
    pub owner_id: i64,
    pub updated_at_micros: i64,
    pub name: String,
    pub kind: Kind,
    pub created_at_micros: i64,
    pub modified_at_micros: i64,
    pub location: Option<Location>,
    pub caption: Option<String>,
    pub hash: Option<String>,
    pub date_time: Option<String>,
    pub offset_time: Option<String>,
    pub duration_seconds: Option<u64>,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub visibility: Visibility,
    pub key: Key,
    pub header: Header,
}

#[derive(Debug, Clone, Copy)]
pub enum Kind {
    Image,
    Video,
    LivePhoto,
    Unknown,
}

impl Kind {
    pub fn name(self) -> &'static str {
        match self {
            Self::Image => "image",
            Self::Video => "video",
            Self::LivePhoto => "livephoto",
            Self::Unknown => "unknown",
        }
    }
}

#[derive(Debug)]
pub struct Location {
    pub latitude: f64,
    pub longitude: f64,
}

pub struct Change {
    pub id: i64,
    pub file: Option<File>,
}

pub struct Page {
    pub changes: Vec<Change>,
    pub cursor: i64,
    pub has_more: bool,
}

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Http(#[from] http::Error),
    #[error(transparent)]
    Crypto(#[from] crypto::Error),
    #[error(transparent)]
    Base64(#[from] b64::DecodeError),
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error(transparent)]
    Collections(#[from] ente_collections::Error),
}

pub async fn diff(session: &Session, collection: &Collection, since: i64) -> Result<Page, Error> {
    let page = ente_collections::client::files_diff(session, collection.id, since).await?;
    let changes = page
        .files
        .into_iter()
        .map(|remote| {
            Ok(Change {
                id: remote.id,
                file: if remote.is_deleted() {
                    None
                } else {
                    Some(File::open(remote, &collection.key)?)
                },
            })
        })
        .collect::<Result<_, Error>>()?;
    Ok(Page {
        changes,
        cursor: page.cursor,
        has_more: page.has_more,
    })
}

#[cfg(not(target_arch = "wasm32"))]
pub async fn download<W: std::io::Write>(
    session: &Session,
    file: &File,
    mut output: impl FnMut() -> std::io::Result<W>,
) -> Result<(), Error> {
    use ente_core::crypto::stream::DecryptingWriter;
    use futures_util::StreamExt;

    http::retry_if(
        || {
            let output = output();
            async move {
                let output = output?;
                let signed: DownloadUrl = session
                    .api
                    .get(&format!("/files/download/v3/{}", file.id))
                    .send()
                    .await?
                    .error_for_code()
                    .await?
                    .json()
                    .await?;
                let response = session
                    .api
                    .http()
                    .get(&signed.url)
                    .send()
                    .await?
                    .error_for_status()?;
                let mut body = std::pin::pin!(response.bytes_stream());
                let mut decryptor = DecryptingWriter::new(&file.header, &file.key, output);
                while let Some(chunk) = body.next().await {
                    decryptor.write(&chunk?)?;
                }
                decryptor.finish()?;
                Ok(())
            }
        },
        |error| matches!(error, Error::Http(error) if error.is_retryable()),
    )
    .await
}

#[cfg(not(target_arch = "wasm32"))]
#[derive(Deserialize)]
struct DownloadUrl {
    url: String,
}

impl File {
    fn open(remote: ente_collections::client::File, collection_key: &Key) -> Result<Self, Error> {
        let key = remote.open_key(collection_key)?;
        let metadata: Metadata = blob::decrypt_json(
            &blob::EncryptedBlob {
                encrypted_data: b64::decode(
                    remote.metadata.encrypted_data.as_deref().unwrap_or(""),
                )?,
                decryption_header: Header::try_from_slice(&b64::decode(
                    &remote.metadata.decryption_header,
                )?)?,
            },
            &key,
        )?;
        let public: PublicMetadata = match remote.pub_magic_metadata {
            Some(encrypted) => encrypted.open(&key)?,
            None => PublicMetadata::default(),
        };
        let private: PrivateMetadata = match remote.magic_metadata {
            Some(encrypted) => encrypted.open(&key)?,
            None => PrivateMetadata::default(),
        };
        let kind = match metadata.file_type {
            Some(0) => Kind::Image,
            Some(1) => Kind::Video,
            Some(2) => Kind::LivePhoto,
            _ => Kind::Unknown,
        };
        let hash = metadata.hash.filter(|hash| !hash.is_empty()).or_else(|| {
            if matches!(kind, Kind::LivePhoto) {
                metadata
                    .image_hash
                    .zip(metadata.video_hash)
                    .map(|(image, video)| format!("{image}:{video}"))
            } else {
                None
            }
        });
        let location = public
            .lat
            .zip(public.long)
            .or(metadata.latitude.zip(metadata.longitude))
            .filter(|&(lat, long)| lat != 0.0 || long != 0.0)
            .map(|(latitude, longitude)| Location {
                latitude,
                longitude,
            });
        Ok(File {
            id: remote.id,
            owner_id: remote.owner_id,
            updated_at_micros: remote.updation_time,
            name: public.edited_name.unwrap_or(metadata.title),
            kind,
            created_at_micros: public.edited_time.unwrap_or(metadata.creation_time),
            modified_at_micros: metadata.modification_time.unwrap_or(metadata.creation_time),
            location,
            caption: public.caption.map(|caption| match caption {
                Caption::Text(text) => text,
                Caption::Number(number) => number.to_string(),
            }),
            hash,
            date_time: public.date_time,
            offset_time: public.offset_time,
            duration_seconds: metadata.duration,
            width: public.w,
            height: public.h,
            visibility: match private.visibility {
                Some(1) => Visibility::Archived,
                Some(2) => Visibility::Hidden,
                _ => Visibility::Visible,
            },
            key,
            header: Header::try_from_slice(&b64::decode(&remote.file.decryption_header)?)?,
        })
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Metadata {
    title: String,
    file_type: Option<i32>,
    creation_time: i64,
    modification_time: Option<i64>,
    latitude: Option<f64>,
    longitude: Option<f64>,
    hash: Option<String>,
    image_hash: Option<String>,
    video_hash: Option<String>,
    duration: Option<u64>,
}

#[derive(Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PublicMetadata {
    edited_name: Option<String>,
    edited_time: Option<i64>,
    date_time: Option<String>,
    offset_time: Option<String>,
    caption: Option<Caption>,
    lat: Option<f64>,
    long: Option<f64>,
    w: Option<u32>,
    h: Option<u32>,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum Caption {
    Text(String),
    Number(serde_json::Number),
}

#[derive(Default, Deserialize)]
struct PrivateMetadata {
    visibility: Option<u8>,
}
