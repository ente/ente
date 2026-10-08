pub mod backup;
pub mod record;

use ente_core::{
    Session, b64,
    crypto::{self, Key, Nonce, secretbox},
    http,
};
use serde::Deserialize;
use uuid::Uuid;
use zeroize::Zeroizing;

pub const PAGE_SIZE: usize = 5000;

#[derive(thiserror::Error, Debug)]
pub enum Error {
    #[error(transparent)]
    Http(#[from] http::Error),
    #[error(transparent)]
    Crypto(#[from] crypto::Error),
    #[error("invalid Auth base64 encoding")]
    Base64(#[from] b64::DecodeError),
    #[error("unreadable Auth record")]
    InvalidRecord,
    #[error("invalid encrypted Auth export")]
    InvalidBackup,
    #[error("unsupported Auth export version")]
    UnsupportedVersion,
    #[error("Auth export key derivation parameters exceed supported bounds")]
    UnsafeKdf,
}

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct WrappedKey {
    pub encrypted_key: String,
    pub header: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Entity {
    pub id: Uuid,
    pub updated_at: i64,
    pub is_deleted: bool,
    pub encrypted_data: Option<String>,
    pub header: Option<String>,
}

pub async fn fetch_key(session: &Session) -> Result<Option<WrappedKey>> {
    Ok(http::retry(|| async {
        let response = session.api.get("/authenticator/key").send().await?;
        if response.status() == 404 {
            return Ok(None);
        }
        response.error_for_code().await?.json().await.map(Some)
    })
    .await?)
}

pub async fn diff(session: &Session, since: i64) -> Result<Vec<Entity>> {
    #[derive(Deserialize)]
    struct Response {
        diff: Vec<Entity>,
    }
    let response: Response = http::retry(|| async {
        session
            .api
            .get("/authenticator/entity/diff")
            .query(&[("sinceTime", since), ("limit", PAGE_SIZE as i64)])
            .send()
            .await?
            .error_for_code()
            .await?
            .json()
            .await
    })
    .await?;
    Ok(response.diff)
}

pub fn open_key(wrapped: &WrappedKey, master_key: &Key) -> Result<Key> {
    let nonce = Nonce::try_from_slice(&b64::decode(&wrapped.header)?)?;
    let plaintext = Zeroizing::new(secretbox::decrypt(
        &b64::decode(&wrapped.encrypted_key)?,
        &nonce,
        master_key,
    )?);
    Ok(Key::try_from_slice(&plaintext)?)
}
