use ente_accounts::auth::{self, KeyAttributes, SrpSession};
use ente_core::crypto::{self, SecretVec, sealed, secretbox};
use ente_core::{Session, b64};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{Error, Result};

#[derive(Debug)]
pub struct LegacyRecoveryBundle {
    pub recovery_key: SecretVec,
    pub user_key_attributes: KeyAttributes,
}

pub async fn start_recovery(
    session: &Session,
    user_id: i64,
    emergency_contact_id: i64,
) -> Result<()> {
    contact_action(
        session,
        "/emergency-contacts/start-recovery",
        user_id,
        emergency_contact_id,
    )
    .await
}

pub async fn stop_recovery(
    session: &Session,
    recovery_id: &str,
    user_id: i64,
    emergency_contact_id: i64,
) -> Result<()> {
    recovery_action(
        session,
        "/emergency-contacts/stop-recovery",
        recovery_id,
        user_id,
        emergency_contact_id,
    )
    .await
}

pub async fn reject_recovery(
    session: &Session,
    recovery_id: &str,
    user_id: i64,
    emergency_contact_id: i64,
) -> Result<()> {
    recovery_action(
        session,
        "/emergency-contacts/reject-recovery",
        recovery_id,
        user_id,
        emergency_contact_id,
    )
    .await
}

pub async fn approve_recovery(
    session: &Session,
    recovery_id: &str,
    user_id: i64,
    emergency_contact_id: i64,
) -> Result<()> {
    recovery_action(
        session,
        "/emergency-contacts/approve-recovery",
        recovery_id,
        user_id,
        emergency_contact_id,
    )
    .await
}

pub async fn recovery_bundle(
    session: &Session,
    recovery_id: &str,
    current_user_key_attrs: &KeyAttributes,
) -> Result<LegacyRecoveryBundle> {
    let response = recovery_info(session, recovery_id).await?;
    let recovery_key =
        decrypt_recovery_key(session, &response.encrypted_key, current_user_key_attrs)?;

    Ok(LegacyRecoveryBundle {
        recovery_key,
        user_key_attributes: response.user_key_attr,
    })
}

pub async fn change_password(
    session: &Session,
    recovery_id: &str,
    current_user_key_attrs: &KeyAttributes,
    new_password: &str,
) -> Result<()> {
    let bundle = recovery_bundle(session, recovery_id, current_user_key_attrs).await?;
    let target_master_key =
        decrypt_master_key_with_recovery_key(&bundle.user_key_attributes, &bundle.recovery_key)?;
    let (updated_key_attrs, login_key) = auth::generate_key_attributes_for_new_password(
        &target_master_key,
        &bundle.user_key_attributes,
        new_password,
    )?;
    let srp_user_id = Uuid::new_v4().to_string();
    let (mut srp_session, setup_request) = password_reset_setup_request(&srp_user_id, &login_key)?;
    let init_response = session
        .api
        .post("/emergency-contacts/init-change-password")
        .json(&LegacyInitChangePasswordRequest {
            recovery_id: recovery_id.to_string(),
            setup_srp_request: setup_request,
        })
        .send()
        .await?
        .error_for_status()?
        .json::<LegacySetupSrpResponse>()
        .await?;
    let srp_m1 = srp_session_m1(&mut srp_session, &init_response)?;
    let updated_key_attr = LegacyUpdatedKeyAttr {
        kek_salt: updated_key_attrs.kek_salt.clone(),
        encrypted_key: updated_key_attrs.encrypted_key.clone(),
        key_decryption_nonce: updated_key_attrs.key_decryption_nonce.clone(),
        mem_limit: updated_key_attrs.mem_limit,
        ops_limit: updated_key_attrs.ops_limit,
    };

    let change_response = session
        .api
        .post("/emergency-contacts/change-password")
        .json(&LegacyChangePasswordRequest {
            recovery_id: recovery_id.to_string(),
            update_srp_and_keys_request: LegacyUpdateSrpAndKeysRequest {
                setup_id: init_response.setup_id,
                srp_m1,
                updated_key_attr,
            },
        })
        .send()
        .await?
        .error_for_status()?
        .json::<LegacyChangePasswordResponse>()
        .await?;

    let server_m2 = b64::decode(&change_response.srp_m2)?;
    srp_session.verify_m2(&server_m2)?;
    Ok(())
}

async fn contact_action(
    session: &Session,
    path: &str,
    user_id: i64,
    emergency_contact_id: i64,
) -> Result<()> {
    session
        .api
        .post(path)
        .json(&LegacyContactIdentifier {
            user_id,
            emergency_contact_id,
        })
        .send()
        .await?
        .error_for_status()?;
    Ok(())
}

async fn recovery_action(
    session: &Session,
    path: &str,
    recovery_id: &str,
    user_id: i64,
    emergency_contact_id: i64,
) -> Result<()> {
    session
        .api
        .post(path)
        .json(&LegacyRecoveryIdentifier {
            id: recovery_id.to_string(),
            user_id,
            emergency_contact_id,
        })
        .send()
        .await?
        .error_for_status()?;
    Ok(())
}

async fn recovery_info(session: &Session, recovery_id: &str) -> Result<LegacyRecoveryInfoResponse> {
    Ok(session
        .api
        .get(&format!("/emergency-contacts/recovery-info/{recovery_id}"))
        .send()
        .await?
        .error_for_status()?
        .json::<LegacyRecoveryInfoResponse>()
        .await?)
}

fn decrypt_recovery_key(
    session: &Session,
    encrypted_key_b64: &str,
    current_user_key_attrs: &KeyAttributes,
) -> Result<SecretVec> {
    let public_key = b64::decode(&current_user_key_attrs.public_key)?;
    let encrypted_key = b64::decode(encrypted_key_b64)?;
    let secret_key = current_secret_key(session, current_user_key_attrs)?;
    let decrypted = sealed::open(
        &encrypted_key,
        &crypto::PublicKey::try_from_slice(&public_key)?,
        &crypto::SecretKey::try_from_slice(&secret_key)?,
    )?;
    Ok(SecretVec::new(decrypted))
}

fn current_secret_key(
    session: &Session,
    current_user_key_attrs: &KeyAttributes,
) -> Result<SecretVec> {
    let encrypted_secret_key = b64::decode(&current_user_key_attrs.encrypted_secret_key)?;
    let secret_key_nonce = b64::decode(&current_user_key_attrs.secret_key_decryption_nonce)?;
    let secret_key = secretbox::decrypt(
        &encrypted_secret_key,
        &crypto::Nonce::try_from_slice(&secret_key_nonce)?,
        &crypto::Key::try_from_slice(&session.master_key)?,
    )?;
    Ok(SecretVec::new(secret_key))
}

fn decrypt_master_key_with_recovery_key(
    key_attributes: &KeyAttributes,
    recovery_key: &[u8],
) -> Result<SecretVec> {
    let encrypted_master_key = key_attributes
        .master_key_encrypted_with_recovery_key
        .as_ref()
        .ok_or_else(|| {
            Error::InvalidInput(
                "target key attributes missing masterKeyEncryptedWithRecoveryKey".into(),
            )
        })?;
    let master_key_nonce = key_attributes
        .master_key_decryption_nonce
        .as_ref()
        .ok_or_else(|| {
            Error::InvalidInput("target key attributes missing masterKeyDecryptionNonce".into())
        })?;
    let encrypted_master_key = b64::decode(encrypted_master_key)?;
    let master_key_nonce = b64::decode(master_key_nonce)?;
    secretbox::decrypt(
        &encrypted_master_key,
        &crypto::Nonce::try_from_slice(&master_key_nonce)?,
        &crypto::Key::try_from_slice(recovery_key)?,
    )
    .map(SecretVec::new)
    .map_err(Into::into)
}

fn password_reset_setup_request(
    srp_user_id: &str,
    login_key: &[u8],
) -> Result<(SrpSession, LegacySetupSrpRequest)> {
    let generated_srp = auth::generate_srp_setup_with_login_key(login_key, srp_user_id)?;
    let srp_session = SrpSession::new(
        srp_user_id,
        &generated_srp.srp_salt,
        &generated_srp.login_sub_key,
    )?;
    let srp_a = b64::encode(&srp_session.public_a());

    Ok((
        srp_session,
        LegacySetupSrpRequest {
            srp_user_id: srp_user_id.to_string(),
            srp_salt: b64::encode(&generated_srp.srp_salt),
            srp_verifier: b64::encode(&generated_srp.srp_verifier),
            srp_a,
        },
    ))
}

fn srp_session_m1(
    srp_session: &mut SrpSession,
    init_response: &LegacySetupSrpResponse,
) -> Result<String> {
    let server_b = b64::decode(&init_response.srp_b)?;
    let client_m1 = srp_session.compute_m1(&server_b)?;
    Ok(b64::encode(&client_m1))
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LegacyContactIdentifier {
    #[serde(rename = "userID")]
    user_id: i64,
    #[serde(rename = "emergencyContactID")]
    emergency_contact_id: i64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LegacyRecoveryIdentifier {
    id: String,
    #[serde(rename = "userID")]
    user_id: i64,
    #[serde(rename = "emergencyContactID")]
    emergency_contact_id: i64,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LegacyRecoveryInfoResponse {
    encrypted_key: String,
    #[serde(rename = "userKeyAttr")]
    user_key_attr: KeyAttributes,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LegacySetupSrpRequest {
    #[serde(rename = "srpUserID")]
    srp_user_id: String,
    srp_salt: String,
    srp_verifier: String,
    #[serde(rename = "srpA")]
    srp_a: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LegacyInitChangePasswordRequest {
    #[serde(rename = "recoveryID")]
    recovery_id: String,
    #[serde(rename = "setupSRPRequest")]
    setup_srp_request: LegacySetupSrpRequest,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LegacySetupSrpResponse {
    #[serde(rename = "setupID")]
    setup_id: String,
    #[serde(rename = "srpB")]
    srp_b: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LegacyUpdatedKeyAttr {
    kek_salt: String,
    encrypted_key: String,
    key_decryption_nonce: String,
    mem_limit: u32,
    ops_limit: u32,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LegacyUpdateSrpAndKeysRequest {
    #[serde(rename = "setupID")]
    setup_id: String,
    #[serde(rename = "srpM1")]
    srp_m1: String,
    #[serde(rename = "updatedKeyAttr")]
    updated_key_attr: LegacyUpdatedKeyAttr,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LegacyChangePasswordRequest {
    #[serde(rename = "recoveryID")]
    recovery_id: String,
    #[serde(rename = "updateSrpAndKeysRequest")]
    update_srp_and_keys_request: LegacyUpdateSrpAndKeysRequest,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LegacyChangePasswordResponse {
    #[serde(rename = "srpM2")]
    srp_m2: String,
}
