mod attachment;
mod contact;

pub use attachment::{
    AttachmentType, delete_attachment, delete_profile_picture, get_attachment_encrypted,
    get_profile_picture, set_attachment, set_profile_picture,
};
pub use contact::{
    ContactData, ContactRecord, create_contact, delete_contact, get_contact, get_diff,
    update_contact,
};

use ente_core::Session;
use ente_core::b64;
use ente_core::crypto::{self, SecretVec, secretbox};
use ente_core::http::Api;
use serde::{Deserialize, Serialize};

use crate::Result;

const CONTACT_TYPE: &str = "contact";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct WrappedRootContactKey {
    pub encrypted_key: String,
    pub header: String,
}

pub struct ContactOutput<T> {
    pub value: T,
    pub wrapped_root_contact_key: Option<WrappedRootContactKey>,
}

struct RootContactKey {
    key: SecretVec,
    wrapped: WrappedRootContactKey,
}

impl RootContactKey {
    fn from_wrapped(wrapped: WrappedRootContactKey, master_key: &[u8]) -> Result<Self> {
        let key = decrypt_root_contact_key(&wrapped, master_key)?;
        Ok(Self { key, wrapped })
    }

    fn encrypt_contact_key(&self, contact_key: &[u8]) -> Result<String> {
        let encrypted =
            secretbox::encrypt_combined(contact_key, &crypto::Key::try_from_slice(&self.key)?);
        Ok(b64::encode(&encrypted))
    }

    fn decrypt_contact_key(&self, encrypted_key: &str) -> Result<SecretVec> {
        let encrypted_key = b64::decode(encrypted_key)?;
        let contact_key =
            secretbox::decrypt_combined(&encrypted_key, &crypto::Key::try_from_slice(&self.key)?)?;
        Ok(SecretVec::new(contact_key))
    }
}

impl<T> ContactOutput<T> {
    fn new(value: T, root_contact_key: Option<RootContactKey>) -> Self {
        Self {
            value,
            wrapped_root_contact_key: root_contact_key.map(|key| key.wrapped),
        }
    }
}

async fn root_contact_key(
    session: &Session,
    cached: Option<&WrappedRootContactKey>,
) -> Result<RootContactKey> {
    if let Some(cached) = cached {
        return RootContactKey::from_wrapped(cached.clone(), &session.master_key);
    }

    let wrapped = if let Some(remote) = fetch_root_key(&session.api).await? {
        remote.into()
    } else {
        let key = SecretVec::new(crypto::random_bytes(32));
        let wrapped = encrypt_root_contact_key(&key, &session.master_key)?;
        create_root_key(&session.api, &wrapped)
            .await?
            .map(Into::into)
            .unwrap_or(wrapped)
    };

    RootContactKey::from_wrapped(wrapped, &session.master_key)
}

fn encrypt_root_contact_key(
    root_contact_key: &[u8],
    master_key: &[u8],
) -> Result<WrappedRootContactKey> {
    let encrypted = secretbox::encrypt(root_contact_key, &crypto::Key::try_from_slice(master_key)?);
    Ok(WrappedRootContactKey {
        encrypted_key: b64::encode(&encrypted.encrypted_data),
        header: b64::encode(encrypted.nonce.as_bytes()),
    })
}

fn decrypt_root_contact_key(
    wrapped_root_contact_key: &WrappedRootContactKey,
    master_key: &[u8],
) -> Result<SecretVec> {
    let encrypted_key = b64::decode(&wrapped_root_contact_key.encrypted_key)?;
    let header = b64::decode(&wrapped_root_contact_key.header)?;
    let root_contact_key = secretbox::decrypt(
        &encrypted_key,
        &crypto::Nonce::try_from_slice(&header)?,
        &crypto::Key::try_from_slice(master_key)?,
    )?;
    Ok(SecretVec::new(root_contact_key))
}

async fn fetch_root_key(api: &Api) -> Result<Option<RootKeyResponse>> {
    let response = api
        .get("/user-entity/key")
        .query(&[("type", CONTACT_TYPE)])
        .send()
        .await?;
    if response.status() == 404 {
        return Ok(None);
    }
    Ok(Some(response.error_for_status()?.json().await?))
}

async fn create_root_key(
    api: &Api,
    wrapped_root_contact_key: &WrappedRootContactKey,
) -> Result<Option<RootKeyResponse>> {
    let request = CreateRootKeyRequest {
        r#type: CONTACT_TYPE,
        encrypted_key: &wrapped_root_contact_key.encrypted_key,
        header: &wrapped_root_contact_key.header,
    };

    let response = api.post("/user-entity/key").json(&request).send().await?;
    if response.status() == 409
        && let Some(remote_root_key) = fetch_root_key(api).await?
    {
        return Ok(Some(remote_root_key));
    }
    response.error_for_status()?;
    Ok(None)
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RootKeyResponse {
    encrypted_key: String,
    header: String,
}

impl From<RootKeyResponse> for WrappedRootContactKey {
    fn from(value: RootKeyResponse) -> Self {
        Self {
            encrypted_key: value.encrypted_key,
            header: value.header,
        }
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CreateRootKeyRequest<'a> {
    r#type: &'a str,
    encrypted_key: &'a str,
    header: &'a str,
}
