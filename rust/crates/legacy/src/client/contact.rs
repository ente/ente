use ente_accounts::auth::KeyAttributes;
use ente_core::crypto::{self, sealed};
use ente_core::http;
use ente_core::{Session, b64};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use super::current_recovery_key;
use crate::{Error, Result};

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum LegacyContactState {
    Invited,
    Revoked,
    Accepted,
    ContactLeft,
    ContactDenied,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum LegacyRecoveryStatus {
    Initiated,
    Waiting,
    Rejected,
    Recovered,
    Stopped,
    Ready,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct LegacyUser {
    pub id: i64,
    pub email: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct LegacyContactRecord {
    pub user: LegacyUser,
    pub emergency_contact: LegacyUser,
    pub state: LegacyContactState,
    pub recovery_notice_in_days: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct LegacyRecoverySession {
    pub id: String,
    pub user: LegacyUser,
    pub emergency_contact: LegacyUser,
    pub status: LegacyRecoveryStatus,
    pub wait_till: i64,
    pub created_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct LegacyInfo {
    pub contacts: Vec<LegacyContactRecord>,
    #[serde(rename = "recoverSessions")]
    pub recover_sessions: Vec<LegacyRecoverySession>,
    pub others_emergency_contact: Vec<LegacyContactRecord>,
    #[serde(rename = "othersRecoverySession")]
    pub others_recovery_session: Vec<LegacyRecoverySession>,
}

pub async fn info(session: &Session) -> Result<LegacyInfo> {
    Ok(session
        .api
        .get("/emergency-contacts/info")
        .send()
        .await?
        .error_for_status()?
        .json::<LegacyInfo>()
        .await?)
}

pub async fn public_key(session: &Session, email: &str) -> Result<Option<String>> {
    let response = session
        .api
        .get("/users/public-key")
        .query(&[("email", email.trim())])
        .send()
        .await?;
    if response.status() == 404 {
        return Ok(None);
    }
    let response = response
        .error_for_status()?
        .json::<LegacyPublicKeyResponse>()
        .await?;
    Ok(Some(response.public_key))
}

pub fn verification_id(public_key_b64: &str) -> Result<String> {
    let public_key = b64::decode(public_key_b64)?;
    let digest = Sha256::digest(&public_key);
    ente_accounts::auth::recovery_key_to_mnemonic(&b64::encode(digest.as_slice()))
        .map_err(Into::into)
}

pub async fn add_contact(
    session: &Session,
    email: &str,
    current_user_key_attrs: &KeyAttributes,
    recovery_notice_in_days: Option<i32>,
) -> Result<()> {
    let public_key = public_key(session, email)
        .await?
        .ok_or(Error::ContactNotOnEnte)?;
    let recovery_key = current_recovery_key(session, current_user_key_attrs)?;
    let recipient_public_key = b64::decode(&public_key)?;
    let encrypted_key = sealed::seal(
        &recovery_key,
        &crypto::PublicKey::try_from_slice(&recipient_public_key)?,
    )?;

    session
        .api
        .post("/emergency-contacts/add")
        .json(&LegacyAddContactRequest {
            email: email.trim().to_string(),
            encrypted_key: b64::encode(&encrypted_key),
            recovery_notice_in_days,
        })
        .send()
        .await?
        .error_for_status()?;
    Ok(())
}

pub async fn update_contact(
    session: &Session,
    user_id: i64,
    emergency_contact_id: i64,
    state: LegacyContactState,
) -> Result<()> {
    session
        .api
        .post("/emergency-contacts/update")
        .json(&LegacyUpdateContactRequest {
            user_id,
            emergency_contact_id,
            state,
        })
        .send()
        .await?
        .error_for_status()?;
    Ok(())
}

pub async fn update_recovery_notice(
    session: &Session,
    emergency_contact_id: i64,
    recovery_notice_in_days: i32,
) -> Result<()> {
    let path = "/emergency-contacts/update-recovery-notice";
    let response = session
        .api
        .post(path)
        .json(&LegacyUpdateRecoveryNoticeRequest {
            emergency_contact_id,
            recovery_notice_in_days,
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

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LegacyPublicKeyResponse {
    public_key: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LegacyAddContactRequest {
    email: String,
    encrypted_key: String,
    recovery_notice_in_days: Option<i32>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LegacyUpdateContactRequest {
    #[serde(rename = "userID")]
    user_id: i64,
    #[serde(rename = "emergencyContactID")]
    emergency_contact_id: i64,
    state: LegacyContactState,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LegacyUpdateRecoveryNoticeRequest {
    #[serde(rename = "emergencyContactID")]
    emergency_contact_id: i64,
    recovery_notice_in_days: i32,
}
