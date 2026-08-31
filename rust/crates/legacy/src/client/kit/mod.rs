mod owner_blob;

use ente_accounts::auth::KeyAttributes;
use ente_core::crypto::{self, SecretVec, secretbox};
use ente_core::http;
use ente_core::{Session, b64};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::current_recovery_key;
use crate::kit::{
    LEGACY_KIT_PAYLOAD_VERSION, LegacyKit, LegacyKitCreateResult, LegacyKitOwnerRecoverySession,
    LegacyKitRecoveryInitiator, LegacyKitRecoverySession, LegacyKitShare, LegacyKitVariant,
    checksum, derive_kit_auth_keypair, derive_kit_encryption_key, split_secret_2_of_3,
};
use crate::{Error, Result};
use owner_blob::{
    create_owner_blob, decrypt_owner_blob, encrypt_owner_blob, metadata_from_owner_blob,
};

const NOTICE_PERIOD_OPTIONS: [i32; 5] = [0, 24, 168, 360, 720];

pub async fn kits(session: &Session) -> Result<Vec<LegacyKit>> {
    let response = session
        .api
        .get("/legacy-kits")
        .send()
        .await?
        .error_for_status()?
        .json::<ListLegacyKitsResponse>()
        .await?;
    response
        .kits
        .into_iter()
        .map(|kit| decode_kit_record(kit, &session.master_key))
        .collect()
}

pub async fn create_kit(
    session: &Session,
    key_attributes: &KeyAttributes,
    part_names: [String; 3],
    notice_period_in_hours: i32,
) -> Result<LegacyKitCreateResult> {
    let (request, shares) = {
        let recovery_key = current_recovery_key(session, key_attributes)?;
        create_kit_request(
            &recovery_key,
            &session.master_key,
            part_names,
            notice_period_in_hours,
        )?
    };

    let response = session
        .api
        .post("/legacy-kits")
        .json(&request)
        .send()
        .await?
        .error_for_status()?
        .json::<LegacyKitRecordResponse>()
        .await?;
    let kit = decode_kit_record(response, &session.master_key)?;
    Ok(LegacyKitCreateResult { kit, shares })
}

pub async fn download_kit_shares(session: &Session, kit_id: &str) -> Result<Vec<LegacyKitShare>> {
    let response = session
        .api
        .get(&format!("/legacy-kits/{kit_id}/download-content"))
        .send()
        .await?
        .error_for_status()?
        .json::<LegacyKitDownloadContentResponse>()
        .await?;
    decode_download_content(response, &session.master_key)
}

pub async fn kit_recovery_session(
    session: &Session,
    kit_id: &str,
) -> Result<LegacyKitOwnerRecoverySession> {
    let response = session
        .api
        .get(&format!("/legacy-kits/{kit_id}/recovery-session"))
        .send()
        .await?
        .error_for_status()?
        .json::<LegacyKitOwnerRecoverySessionResponse>()
        .await?;
    Ok(response.into())
}

pub async fn update_kit_recovery_notice(
    session: &Session,
    kit_id: &str,
    notice_period_in_hours: i32,
) -> Result<()> {
    validate_notice_period(notice_period_in_hours)?;
    let path = "/legacy-kits/update-recovery-notice";
    let response = session
        .api
        .post(path)
        .json(&LegacyKitUpdateRecoveryNoticeRequest {
            kit_id: kit_id.to_string(),
            notice_period_in_hours,
        })
        .send()
        .await?;
    if response.status() == 400 {
        return if response.text().await?.contains("active recovery session") {
            Err(Error::ActiveRecoverySession)
        } else {
            Err(http::Error::Http {
                status: 400,
                path: path.into(),
            }
            .into())
        };
    }
    response.error_for_status()?;
    Ok(())
}

pub async fn block_kit_recovery(session: &Session, kit_id: &str) -> Result<()> {
    session
        .api
        .post("/legacy-kits/block-recovery")
        .json(&LegacyKitOwnerActionRequest {
            kit_id: kit_id.to_string(),
        })
        .send()
        .await?
        .error_for_status()?;
    Ok(())
}

pub async fn delete_kit(session: &Session, kit_id: &str) -> Result<()> {
    session
        .api
        .delete(&format!("/legacy-kits/{kit_id}"))
        .send()
        .await?
        .error_for_status()?;
    Ok(())
}

fn create_kit_request(
    recovery_key: &[u8],
    master_key: &[u8],
    part_names: [String; 3],
    notice_period_in_hours: i32,
) -> Result<(CreateLegacyKitRequest, Vec<LegacyKitShare>)> {
    validate_notice_period(notice_period_in_hours)?;
    if part_names.iter().any(|name| name.trim().is_empty()) {
        return Err(Error::InvalidInput(
            "legacy kit part names must be non-empty".into(),
        ));
    }

    let kit_id = Uuid::new_v4().to_string();
    let variant = LegacyKitVariant::TwoOfThree;
    let kit_secret = SecretVec::new(crypto::random_bytes(32));
    let checksum = checksum(LEGACY_KIT_PAYLOAD_VERSION, variant, &kit_id, &kit_secret);
    let shares = split_secret_2_of_3(&kit_secret)?;
    let shares = shares
        .into_iter()
        .zip(part_names)
        .enumerate()
        .map(|(index, (share, part_name))| LegacyKitShare {
            payload_version: LEGACY_KIT_PAYLOAD_VERSION,
            variant,
            kit_id: kit_id.clone(),
            share_index: (index + 1) as u8,
            share: b64::encode(&share),
            checksum: checksum.clone(),
            part_name,
        })
        .collect::<Vec<_>>();

    let encryption_key = derive_kit_encryption_key(&kit_secret)?;
    let (auth_public_key, _) = derive_kit_auth_keypair(&kit_secret)?;
    let encrypted_recovery_blob =
        secretbox::encrypt_combined(recovery_key, &crypto::Key::try_from_slice(&encryption_key)?);
    let encrypted_owner_blob = encrypt_owner_blob(&create_owner_blob(&shares), master_key)?;

    Ok((
        CreateLegacyKitRequest {
            id: kit_id,
            variant,
            notice_period_in_hours,
            encrypted_recovery_blob: b64::encode(&encrypted_recovery_blob),
            auth_public_key: b64::encode(auth_public_key.as_bytes()),
            encrypted_owner_blob,
        },
        shares,
    ))
}

fn decode_kit_record(response: LegacyKitRecordResponse, master_key: &[u8]) -> Result<LegacyKit> {
    let owner_blob = decrypt_owner_blob(&response.encrypted_owner_blob, master_key)?;
    Ok(LegacyKit {
        id: response.id,
        variant: response.variant,
        notice_period_in_hours: response.notice_period_in_hours,
        legacy_url: response.legacy_url,
        metadata: metadata_from_owner_blob(&owner_blob),
        created_at: response.created_at,
        updated_at: response.updated_at,
        active_recovery_session: response.active_recovery_session,
    })
}

fn decode_download_content(
    response: LegacyKitDownloadContentResponse,
    master_key: &[u8],
) -> Result<Vec<LegacyKitShare>> {
    let owner_blob = decrypt_owner_blob(&response.encrypted_owner_blob, master_key)?;
    Ok(owner_blob
        .parts
        .into_iter()
        .map(|part| LegacyKitShare {
            payload_version: LEGACY_KIT_PAYLOAD_VERSION,
            variant: response.variant,
            kit_id: response.id.clone(),
            share_index: part.index,
            share: part.share,
            checksum: part.checksum,
            part_name: part.name,
        })
        .collect())
}

fn validate_notice_period(hours: i32) -> Result<()> {
    if NOTICE_PERIOD_OPTIONS.contains(&hours) {
        Ok(())
    } else {
        Err(Error::InvalidInput(
            "legacy kit notice period must be one of 0, 24, 168, 360, 720 hours".into(),
        ))
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CreateLegacyKitRequest {
    id: String,
    variant: LegacyKitVariant,
    notice_period_in_hours: i32,
    encrypted_recovery_blob: String,
    auth_public_key: String,
    encrypted_owner_blob: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LegacyKitRecordResponse {
    id: String,
    variant: LegacyKitVariant,
    notice_period_in_hours: i32,
    legacy_url: String,
    encrypted_owner_blob: String,
    created_at: i64,
    updated_at: i64,
    active_recovery_session: Option<LegacyKitRecoverySession>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ListLegacyKitsResponse {
    kits: Vec<LegacyKitRecordResponse>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LegacyKitDownloadContentResponse {
    id: String,
    variant: LegacyKitVariant,
    encrypted_owner_blob: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LegacyKitOwnerActionRequest {
    #[serde(rename = "kitID")]
    kit_id: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LegacyKitUpdateRecoveryNoticeRequest {
    #[serde(rename = "kitID")]
    kit_id: String,
    notice_period_in_hours: i32,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LegacyKitOwnerRecoverySessionResponse {
    session: Option<LegacyKitRecoverySession>,
    initiators: Vec<LegacyKitRecoveryInitiator>,
}

impl From<LegacyKitOwnerRecoverySessionResponse> for LegacyKitOwnerRecoverySession {
    fn from(value: LegacyKitOwnerRecoverySessionResponse) -> Self {
        Self {
            session: value.session,
            initiators: value.initiators,
        }
    }
}
