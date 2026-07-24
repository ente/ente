use ente_core::b64;
use ente_core::crypto::{self, secretbox};
use serde::{Deserialize, Serialize, de::DeserializeOwned};

use crate::{
    ContactsError, Result,
    legacy_kit_models::{LegacyKitMetadata, LegacyKitPart, LegacyKitShare},
};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct StoredOwnerPart {
    pub(super) index: u8,
    pub(super) name: String,
    pub(super) share: String,
    pub(super) checksum: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct StoredOwnerBlob {
    pub(super) parts: Vec<StoredOwnerPart>,
}

pub(super) fn create_owner_blob(shares: &[LegacyKitShare]) -> StoredOwnerBlob {
    StoredOwnerBlob {
        parts: shares
            .iter()
            .map(|share| StoredOwnerPart {
                index: share.share_index,
                name: share.part_name.clone(),
                share: share.share.clone(),
                checksum: share.checksum.clone(),
            })
            .collect(),
    }
}

pub(super) fn encrypt_owner_blob(
    owner_blob: &StoredOwnerBlob,
    master_key: &[u8],
) -> Result<String> {
    encrypt_blob(owner_blob, master_key, "legacy kit owner")
}

pub(super) fn decrypt_owner_blob(
    encrypted_blob_b64: &str,
    master_key: &[u8],
) -> Result<StoredOwnerBlob> {
    decrypt_blob(encrypted_blob_b64, master_key, "legacy kit owner")
}

fn encrypt_blob<T: Serialize>(payload: &T, master_key: &[u8], label: &str) -> Result<String> {
    let payload = serde_json::to_vec(payload).map_err(|error| {
        ContactsError::InvalidInput(format!("failed to encode {label} payload: {error}"))
    })?;
    let encrypted =
        secretbox::encrypt_combined(&payload, &crypto::Key::try_from_slice(master_key)?);
    Ok(b64::encode(&encrypted))
}

fn decrypt_blob<T: DeserializeOwned>(
    encrypted_blob_b64: &str,
    master_key: &[u8],
    label: &str,
) -> Result<T> {
    let encrypted_blob = b64::decode(encrypted_blob_b64)?;
    let plaintext =
        secretbox::decrypt_combined(&encrypted_blob, &crypto::Key::try_from_slice(master_key)?)?;
    serde_json::from_slice(&plaintext).map_err(|error| {
        ContactsError::InvalidInput(format!("failed to decode {label} payload: {error}"))
    })
}

pub(super) fn metadata_from_owner_blob(owner_blob: &StoredOwnerBlob) -> LegacyKitMetadata {
    LegacyKitMetadata {
        parts: owner_blob
            .parts
            .iter()
            .map(|part| LegacyKitPart {
                index: part.index,
                name: part.name.clone(),
            })
            .collect(),
    }
}
