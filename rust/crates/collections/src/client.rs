use ente_core::{
    Session, b64,
    crypto::{Header, Key, Nonce, blob, secretbox},
    http,
};
use serde::{Deserialize, de::DeserializeOwned};

use crate::{Error, Result, open_collection_key};

pub struct CollectionPage {
    pub collections: Vec<Collection>,
    pub cursor: i64,
}

pub async fn diff(session: &Session, since: i64) -> Result<CollectionPage> {
    #[derive(Deserialize)]
    struct Response {
        collections: Vec<Collection>,
    }
    let response: Response = http::retry(|| async {
        session
            .api
            .get("/collections/v2")
            .query(&[("sinceTime", since)])
            .send()
            .await?
            .error_for_code()
            .await?
            .json()
            .await
    })
    .await?;
    let cursor = response
        .collections
        .iter()
        .map(|c| c.updation_time)
        .max()
        .unwrap_or(since);
    Ok(CollectionPage {
        collections: response.collections,
        cursor,
    })
}

pub struct FilePage {
    pub files: Vec<File>,
    pub cursor: i64,
    pub has_more: bool,
}

pub async fn files_diff(session: &Session, collection_id: i64, since: i64) -> Result<FilePage> {
    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct Response {
        diff: Vec<File>,
        has_more: bool,
    }
    let response: Response = http::retry(|| async {
        session
            .api
            .get("/collections/v2/diff")
            .query(&[("collectionID", collection_id), ("sinceTime", since)])
            .send()
            .await?
            .error_for_code()
            .await?
            .json()
            .await
    })
    .await?;
    let cursor = response
        .diff
        .iter()
        .map(|f| f.updation_time)
        .max()
        .unwrap_or(since);
    if response.has_more && cursor <= since {
        return Err(Error::CursorDidNotAdvance(collection_id));
    }
    Ok(FilePage {
        files: response.diff,
        cursor,
        has_more: response.has_more,
    })
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Collection {
    pub id: i64,
    pub owner: Owner,
    pub encrypted_key: String,
    pub key_decryption_nonce: Option<String>,
    pub encrypted_name: Option<String>,
    pub name_decryption_nonce: Option<String>,
    pub name: Option<String>,
    #[serde(rename = "type")]
    pub kind: String,
    pub updation_time: i64,
    pub is_deleted: Option<bool>,
    pub magic_metadata: Option<EncryptedMetadata>,
    pub shared_magic_metadata: Option<EncryptedMetadata>,
}

impl Collection {
    pub fn open_key(&self, session: &Session) -> Result<Key> {
        open_collection_key(
            session,
            self.owner.id,
            &self.encrypted_key,
            self.key_decryption_nonce.as_deref(),
        )
    }

    pub fn open_name(&self, key: &Key) -> Result<String> {
        if let Some(name) = self.name.as_ref().filter(|name| !name.is_empty()) {
            return Ok(name.clone());
        }
        let encrypted = self
            .encrypted_name
            .as_deref()
            .ok_or(Error::InvalidCollection {
                id: self.id,
                reason: "missing name",
            })?;
        let nonce = self
            .name_decryption_nonce
            .as_deref()
            .ok_or(Error::InvalidCollection {
                id: self.id,
                reason: "missing name nonce",
            })?;
        let bytes = secretbox::decrypt(
            &b64::decode(encrypted)?,
            &Nonce::try_from_slice(&b64::decode(nonce)?)?,
            key,
        )?;
        String::from_utf8(bytes).map_err(|_| Error::InvalidCollection {
            id: self.id,
            reason: "name is not UTF-8",
        })
    }
}

#[derive(Deserialize)]
pub struct Owner {
    pub id: i64,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct File {
    pub id: i64,
    #[serde(rename = "ownerID")]
    pub owner_id: i64,
    pub encrypted_key: String,
    pub key_decryption_nonce: String,
    pub file: FileAttributes,
    pub metadata: FileAttributes,
    pub is_deleted: bool,
    pub updation_time: i64,
    pub magic_metadata: Option<EncryptedMetadata>,
    pub pub_magic_metadata: Option<EncryptedMetadata>,
}

impl File {
    pub fn is_deleted(&self) -> bool {
        self.is_deleted || self.metadata.encrypted_data.as_deref() == Some("-")
    }

    pub fn open_key(&self, collection_key: &Key) -> Result<Key> {
        let bytes = secretbox::decrypt(
            &b64::decode(&self.encrypted_key)?,
            &Nonce::try_from_slice(&b64::decode(&self.key_decryption_nonce)?)?,
            collection_key,
        )?;
        Ok(Key::try_from_slice(&bytes)?)
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FileAttributes {
    pub encrypted_data: Option<String>,
    pub decryption_header: String,
}

#[derive(Deserialize)]
pub struct EncryptedMetadata {
    pub data: String,
    pub header: String,
}

impl EncryptedMetadata {
    pub fn open<T: DeserializeOwned>(&self, key: &Key) -> Result<T> {
        Ok(blob::decrypt_json(
            &blob::EncryptedBlob {
                encrypted_data: b64::decode(&self.data)?,
                decryption_header: Header::try_from_slice(&b64::decode(&self.header)?)?,
            },
            key,
        )?)
    }
}
