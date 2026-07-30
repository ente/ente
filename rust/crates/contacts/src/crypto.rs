use md5::{Digest, Md5};

use ente_core::b64;
use ente_core::crypto::{self, blob, secretbox};

use crate::error::{ContactsError, Result};
use crate::models::{ContactData, WrappedRootContactKey};

pub fn encrypt_root_contact_key(
    root_contact_key: &[u8],
    master_key: &[u8],
) -> Result<WrappedRootContactKey> {
    let encrypted = secretbox::encrypt(root_contact_key, &crypto::Key::try_from_slice(master_key)?);
    Ok(WrappedRootContactKey {
        encrypted_key: b64::encode(&encrypted.encrypted_data),
        header: b64::encode(encrypted.nonce.as_bytes()),
    })
}

pub fn decrypt_root_contact_key(
    wrapped_root_contact_key: &WrappedRootContactKey,
    master_key: &[u8],
) -> Result<Vec<u8>> {
    let encrypted_key = b64::decode(&wrapped_root_contact_key.encrypted_key)?;
    let header = b64::decode(&wrapped_root_contact_key.header)?;
    Ok(secretbox::decrypt(
        &encrypted_key,
        &crypto::Nonce::try_from_slice(&header)?,
        &crypto::Key::try_from_slice(master_key)?,
    )?)
}

pub fn wrap_contact_key(contact_key: &[u8], root_contact_key: &[u8]) -> Result<String> {
    let encrypted =
        secretbox::encrypt_combined(contact_key, &crypto::Key::try_from_slice(root_contact_key)?);
    Ok(b64::encode(&encrypted))
}

pub fn unwrap_contact_key(encrypted_key_b64: &str, root_contact_key: &[u8]) -> Result<Vec<u8>> {
    let encrypted_key = b64::decode(encrypted_key_b64)?;
    Ok(secretbox::decrypt_combined(
        &encrypted_key,
        &crypto::Key::try_from_slice(root_contact_key)?,
    )?)
}

pub fn encrypt_contact_data(data: &ContactData, contact_key: &[u8]) -> Result<String> {
    let encrypted = blob::encrypt_json_combined(data, &crypto::Key::try_from_slice(contact_key)?)?;
    Ok(b64::encode(&encrypted))
}

pub fn decrypt_contact_data(encrypted_data_b64: &str, contact_key: &[u8]) -> Result<ContactData> {
    let encrypted_data = b64::decode(encrypted_data_b64)?;
    Ok(blob::decrypt_json_combined(
        &encrypted_data,
        &crypto::Key::try_from_slice(contact_key)?,
    )?)
}

pub fn encrypt_profile_picture(bytes: &[u8], contact_key: &[u8]) -> Result<Vec<u8>> {
    Ok(blob::encrypt_combined(
        bytes,
        &crypto::Key::try_from_slice(contact_key)?,
    )?)
}

pub fn decrypt_profile_picture(bytes: &[u8], contact_key: &[u8]) -> Result<Vec<u8>> {
    Ok(blob::decrypt_combined(
        bytes,
        &crypto::Key::try_from_slice(contact_key)?,
    )?)
}

pub fn content_md5_base64(bytes: &[u8]) -> String {
    let digest = Md5::digest(bytes);
    b64::encode(digest.as_slice())
}

pub fn validate_contact_data(data: &ContactData) -> Result<()> {
    if data.contact_user_id <= 0 {
        return Err(ContactsError::InvalidInput(
            "contact_user_id must be greater than 0".to_string(),
        ));
    }
    if data.name.trim().is_empty() {
        return Err(ContactsError::InvalidInput("name is required".to_string()));
    }
    Ok(())
}
