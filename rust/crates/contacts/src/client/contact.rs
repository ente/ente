use ente_core::Session;
use ente_core::b64;
use ente_core::crypto::{self, SecretVec, blob};
use serde::{Deserialize, Serialize};

use super::{ContactOutput, RootContactKey, WrappedRootContactKey, root_contact_key};
use crate::{Error, Result};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ContactData {
    pub contact_user_id: i64,
    pub name: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ContactRecord {
    pub id: String,
    pub contact_user_id: i64,
    pub email: Option<String>,
    pub name: Option<String>,
    pub profile_picture_attachment_id: Option<String>,
    pub is_deleted: bool,
    pub created_at: i64,
    pub updated_at: i64,
}

pub async fn create_contact(
    session: &Session,
    wrapped_root_contact_key: Option<&WrappedRootContactKey>,
    data: &ContactData,
) -> Result<ContactOutput<ContactRecord>> {
    validate_contact_data(data)?;
    let root_contact_key = root_contact_key(session, wrapped_root_contact_key).await?;
    let contact_key = SecretVec::new(crypto::random_bytes(32));
    let wrapped_contact_key = root_contact_key.encrypt_contact_key(&contact_key)?;
    let encrypted_data = encrypt_contact_data(data, &contact_key)?;
    let response = session
        .api
        .post("/contacts")
        .json(&CreateContactRequest {
            contact_user_id: data.contact_user_id,
            encrypted_key: &wrapped_contact_key,
            encrypted_data: &encrypted_data,
        })
        .send()
        .await?
        .error_for_status()?
        .json::<ContactEntityResponse>()
        .await?;
    let record = decode_contact(response, Some(&root_contact_key))?;

    Ok(ContactOutput::new(record, Some(root_contact_key)))
}

pub async fn get_contact(
    session: &Session,
    wrapped_root_contact_key: Option<&WrappedRootContactKey>,
    contact_id: &str,
) -> Result<ContactOutput<ContactRecord>> {
    let response = session
        .api
        .get(&format!("/contacts/{contact_id}"))
        .send()
        .await?
        .error_for_status()?
        .json::<ContactEntityResponse>()
        .await?;
    let root_contact_key = if response.is_deleted {
        None
    } else {
        Some(root_contact_key(session, wrapped_root_contact_key).await?)
    };
    let record = decode_contact(response, root_contact_key.as_ref())?;

    Ok(ContactOutput::new(record, root_contact_key))
}

pub async fn update_contact(
    session: &Session,
    wrapped_root_contact_key: Option<&WrappedRootContactKey>,
    contact_id: &str,
    data: &ContactData,
) -> Result<ContactOutput<ContactRecord>> {
    validate_contact_data(data)?;
    let root_contact_key = root_contact_key(session, wrapped_root_contact_key).await?;
    let current = session
        .api
        .get(&format!("/contacts/{contact_id}"))
        .send()
        .await?
        .error_for_status()?
        .json::<ContactEntityResponse>()
        .await?;
    let encrypted_key = current
        .encrypted_key
        .as_deref()
        .ok_or(Error::MissingEncryptedKey)?;
    let contact_key = root_contact_key.decrypt_contact_key(encrypted_key)?;
    let encrypted_data = encrypt_contact_data(data, &contact_key)?;
    let response = session
        .api
        .put(&format!("/contacts/{contact_id}"))
        .json(&UpdateContactRequest {
            contact_user_id: data.contact_user_id,
            encrypted_data: &encrypted_data,
        })
        .send()
        .await?
        .error_for_status()?
        .json::<ContactEntityResponse>()
        .await?;
    let record = decode_contact(response, Some(&root_contact_key))?;

    Ok(ContactOutput::new(record, Some(root_contact_key)))
}

pub async fn delete_contact(session: &Session, contact_id: &str) -> Result<()> {
    session
        .api
        .delete(&format!("/contacts/{contact_id}"))
        .send()
        .await?
        .error_for_status()?;
    Ok(())
}

pub async fn get_diff(
    session: &Session,
    wrapped_root_contact_key: Option<&WrappedRootContactKey>,
    since_time: i64,
    limit: u16,
) -> Result<ContactOutput<Vec<ContactRecord>>> {
    let response = session
        .api
        .get("/contacts/diff")
        .query(&[
            ("sinceTime", since_time.to_string()),
            ("limit", limit.to_string()),
        ])
        .send()
        .await?
        .error_for_status()?
        .json::<ContactDiffResponse>()
        .await?;
    let root_contact_key = if response.diff.iter().any(|entity| !entity.is_deleted) {
        Some(root_contact_key(session, wrapped_root_contact_key).await?)
    } else {
        None
    };
    let records = response
        .diff
        .into_iter()
        .map(|entity| decode_contact(entity, root_contact_key.as_ref()))
        .collect::<Result<_>>()?;

    Ok(ContactOutput::new(records, root_contact_key))
}

pub(super) fn decode_contact(
    entity: ContactEntityResponse,
    root_contact_key: Option<&RootContactKey>,
) -> Result<ContactRecord> {
    if entity.is_deleted {
        return Ok(ContactRecord {
            id: entity.id,
            contact_user_id: entity.contact_user_id,
            email: None,
            name: None,
            profile_picture_attachment_id: None,
            is_deleted: true,
            created_at: entity.created_at,
            updated_at: entity.updated_at,
        });
    }

    let root_contact_key = root_contact_key
        .ok_or_else(|| Error::InvalidInput("contacts root key is unresolved".into()))?;
    let encrypted_key = entity
        .encrypted_key
        .as_deref()
        .ok_or(Error::MissingEncryptedKey)?;
    let encrypted_data = entity
        .encrypted_data
        .as_deref()
        .ok_or(Error::MissingEncryptedData)?;
    let contact_key = root_contact_key.decrypt_contact_key(encrypted_key)?;
    let data = decrypt_contact_data(encrypted_data, &contact_key)?;

    Ok(ContactRecord {
        id: entity.id,
        contact_user_id: entity.contact_user_id,
        email: entity.email,
        name: Some(data.name),
        profile_picture_attachment_id: entity.profile_picture_attachment_id,
        is_deleted: false,
        created_at: entity.created_at,
        updated_at: entity.updated_at,
    })
}

fn validate_contact_data(data: &ContactData) -> Result<()> {
    if data.contact_user_id <= 0 {
        return Err(Error::InvalidInput(
            "contact_user_id must be greater than 0".to_string(),
        ));
    }
    if data.name.trim().is_empty() {
        return Err(Error::InvalidInput("name is required".to_string()));
    }
    Ok(())
}

fn encrypt_contact_data(data: &ContactData, contact_key: &[u8]) -> Result<String> {
    let encrypted = blob::encrypt_json_combined(data, &crypto::Key::try_from_slice(contact_key)?)?;
    Ok(b64::encode(&encrypted))
}

fn decrypt_contact_data(encrypted_data: &str, contact_key: &[u8]) -> Result<ContactData> {
    let encrypted_data = b64::decode(encrypted_data)?;
    Ok(blob::decrypt_json_combined(
        &encrypted_data,
        &crypto::Key::try_from_slice(contact_key)?,
    )?)
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CreateContactRequest<'a> {
    #[serde(rename = "contactUserID")]
    contact_user_id: i64,
    encrypted_key: &'a str,
    encrypted_data: &'a str,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct UpdateContactRequest<'a> {
    #[serde(rename = "contactUserID")]
    contact_user_id: i64,
    encrypted_data: &'a str,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct ContactEntityResponse {
    id: String,
    #[serde(rename = "contactUserID")]
    contact_user_id: i64,
    email: Option<String>,
    #[serde(rename = "profilePictureAttachmentID")]
    pub(super) profile_picture_attachment_id: Option<String>,
    pub(super) encrypted_key: Option<String>,
    encrypted_data: Option<String>,
    pub(super) is_deleted: bool,
    created_at: i64,
    updated_at: i64,
}

#[derive(Deserialize)]
struct ContactDiffResponse {
    diff: Vec<ContactEntityResponse>,
}
