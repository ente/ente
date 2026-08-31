use std::sync::Arc;

use ente_accounts::auth::{self, KeyAttributes, SrpSession};
use ente_core::b64;
use ente_core::crypto::{self, SecretString, SecretVec, sealed, secretbox};
use ente_core::http::{Api, ApiConfig, Http, Response};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::{
    LegacyKitRecoveryBundle, LegacyKitRecoverySession, LegacyKitShare, derive_kit_auth_keypair,
    derive_kit_encryption_key, reconstruct_secret_2_of_3, used_part_indexes,
};
use crate::{Error, Result};

pub struct LegacyKitRecoveryClient {
    api: Arc<Api>,
}

pub struct LegacyKitRecoveryHandle {
    api: Arc<Api>,
    session: LegacyKitRecoverySession,
    session_token: SecretString,
    kit_secret: SecretVec,
}

impl LegacyKitRecoveryClient {
    pub fn new(base_url: impl Into<String>) -> Result<Self> {
        Self::new_with_headers(
            base_url,
            None,
            None,
            Some("ente-rust-legacy-kit".to_string()),
        )
    }

    pub fn new_with_headers(
        base_url: impl Into<String>,
        client_package: Option<String>,
        client_version: Option<String>,
        user_agent: Option<String>,
    ) -> Result<Self> {
        let api = Api::new(
            Http::new()?,
            ApiConfig {
                origin: base_url.into(),
                client_package,
                client_version,
                user_agent,
                auth: None,
            },
        );
        Ok(Self { api: Arc::new(api) })
    }

    pub fn reconstruct_secret(shares: &[LegacyKitShare]) -> Result<SecretVec> {
        reconstruct_secret_2_of_3(shares)
    }

    pub async fn open_from_shares(
        &self,
        shares: &[LegacyKitShare],
        email: Option<&str>,
    ) -> Result<LegacyKitRecoveryHandle> {
        let first_share = shares.first().ok_or_else(|| {
            Error::InvalidInput("at least two legacy kit shares are required".into())
        })?;
        let response = self
            .api
            .post("/legacy-kits/recovery/challenge")
            .json(&LegacyKitChallengeRequest {
                kit_id: first_share.kit_id.clone(),
            })
            .send()
            .await?;
        let challenge = active_kit_response(response)?
            .json::<LegacyKitChallengeResponse>()
            .await?;
        self.open_from_encrypted_challenge(shares, &challenge.encrypted_challenge, email)
            .await
    }

    pub async fn open_from_encrypted_challenge(
        &self,
        shares: &[LegacyKitShare],
        encrypted_challenge: &str,
        email: Option<&str>,
    ) -> Result<LegacyKitRecoveryHandle> {
        let kit_secret = reconstruct_secret_2_of_3(shares)?;
        let first_share = shares.first().ok_or_else(|| {
            Error::InvalidInput("at least two legacy kit shares are required".into())
        })?;
        self.open(
            first_share,
            kit_secret,
            encrypted_challenge,
            Some(used_part_indexes(shares)?),
            email.map(ToOwned::to_owned),
        )
        .await
    }

    async fn open(
        &self,
        first_share: &LegacyKitShare,
        kit_secret: SecretVec,
        encrypted_challenge: &str,
        used_part_indexes: Option<Vec<u8>>,
        email: Option<String>,
    ) -> Result<LegacyKitRecoveryHandle> {
        let (auth_public_key, auth_secret_key) = derive_kit_auth_keypair(&kit_secret)?;
        let challenge = decrypt_challenge(&auth_public_key, &auth_secret_key, encrypted_challenge)?;
        let response = self
            .api
            .post("/legacy-kits/recovery/open")
            .json(&LegacyKitOpenRecoveryRequest {
                kit_id: first_share.kit_id.clone(),
                challenge,
                used_part_indexes,
                email,
            })
            .send()
            .await?;
        let response = active_kit_response(response)?
            .json::<LegacyKitOpenRecoveryResponse>()
            .await?;
        Ok(LegacyKitRecoveryHandle {
            api: Arc::clone(&self.api),
            session: response.session,
            session_token: SecretString::new(response.session_token),
            kit_secret,
        })
    }
}

impl LegacyKitRecoveryHandle {
    pub fn session(&self) -> &LegacyKitRecoverySession {
        &self.session
    }

    pub async fn refresh_session(&self) -> Result<LegacyKitRecoverySession> {
        let response = self
            .api
            .post("/legacy-kits/recovery/session")
            .json(&self.session_request())
            .send()
            .await?;
        Ok(response.error_for_status()?.json().await?)
    }

    pub async fn recovery_bundle(&self) -> Result<LegacyKitRecoveryBundle> {
        let response = self
            .api
            .post("/legacy-kits/recovery/info")
            .json(&self.session_request())
            .send()
            .await?
            .error_for_status()?
            .json::<LegacyKitRecoveryInfoResponse>()
            .await?;
        let encryption_key = derive_kit_encryption_key(&self.kit_secret)?;
        let encrypted_recovery_blob = b64::decode(&response.encrypted_recovery_blob)?;
        let recovery_key = secretbox::decrypt_combined(
            &encrypted_recovery_blob,
            &crypto::Key::try_from_slice(&encryption_key)?,
        )?;
        Ok(LegacyKitRecoveryBundle {
            recovery_key: SecretVec::new(recovery_key),
            user_key_attributes: response.user_key_attr,
        })
    }

    pub async fn change_password(&self, new_password: &str) -> Result<()> {
        let bundle = self.recovery_bundle().await?;
        let master_key = decrypt_master_key(&bundle.user_key_attributes, &bundle.recovery_key)?;
        let (updated_key_attrs, login_key) = auth::generate_key_attributes_for_new_password(
            &master_key,
            &bundle.user_key_attributes,
            new_password,
        )?;
        let srp_user_id = Uuid::new_v4().to_string();
        let (mut srp_session, setup_request) = setup_srp(&srp_user_id, &login_key)?;
        let init_response = self
            .api
            .post("/legacy-kits/recovery/init-change-password")
            .json(&LegacyKitInitChangePasswordRequest {
                session_id: self.session.id.clone(),
                session_token: self.session_token.as_ref().to_owned(),
                setup_srp_request: setup_request,
            })
            .send()
            .await?
            .error_for_status()?
            .json::<LegacyKitSetupSrpResponse>()
            .await?;
        let srp_m1 = srp_m1(&mut srp_session, &init_response)?;
        let change_response = self
            .api
            .post("/legacy-kits/recovery/change-password")
            .json(&LegacyKitChangePasswordRequest {
                session_id: self.session.id.clone(),
                session_token: self.session_token.as_ref().to_owned(),
                update_srp_and_keys_request: LegacyKitUpdateSrpAndKeysRequest {
                    setup_id: init_response.setup_id,
                    srp_m1,
                    updated_key_attr: LegacyKitUpdatedKeyAttr {
                        kek_salt: updated_key_attrs.kek_salt,
                        encrypted_key: updated_key_attrs.encrypted_key,
                        key_decryption_nonce: updated_key_attrs.key_decryption_nonce,
                        mem_limit: updated_key_attrs.mem_limit,
                        ops_limit: updated_key_attrs.ops_limit,
                    },
                },
            })
            .send()
            .await?
            .error_for_status()?
            .json::<LegacyKitChangePasswordResponse>()
            .await?;

        srp_session.verify_m2(&b64::decode(&change_response.srp_m2)?)?;
        Ok(())
    }

    fn session_request(&self) -> LegacyKitSessionRequest {
        LegacyKitSessionRequest {
            session_id: self.session.id.clone(),
            session_token: self.session_token.as_ref().to_owned(),
        }
    }
}

fn active_kit_response(response: Response) -> Result<Response> {
    if response.status() == 404 {
        Err(Error::LegacyKitInactive)
    } else {
        Ok(response.error_for_status()?)
    }
}

fn decrypt_challenge(
    public_key: &crypto::PublicKey,
    secret_key: &crypto::SecretKey,
    encrypted_challenge_b64: &str,
) -> Result<String> {
    let encrypted_challenge = b64::decode(encrypted_challenge_b64)?;
    let plaintext = sealed::open(&encrypted_challenge, public_key, secret_key)?;
    String::from_utf8(plaintext).map_err(|error| {
        Error::InvalidInput(format!("legacy kit challenge was not valid UTF-8: {error}"))
    })
}

fn decrypt_master_key(key_attributes: &KeyAttributes, recovery_key: &[u8]) -> Result<SecretVec> {
    let encrypted_master_key = key_attributes
        .master_key_encrypted_with_recovery_key
        .as_ref()
        .ok_or_else(|| {
            Error::InvalidInput(
                "target key attributes missing masterKeyEncryptedWithRecoveryKey".into(),
            )
        })?;
    let nonce = key_attributes
        .master_key_decryption_nonce
        .as_ref()
        .ok_or_else(|| {
            Error::InvalidInput("target key attributes missing masterKeyDecryptionNonce".into())
        })?;
    secretbox::decrypt(
        &b64::decode(encrypted_master_key)?,
        &crypto::Nonce::try_from_slice(&b64::decode(nonce)?)?,
        &crypto::Key::try_from_slice(recovery_key)?,
    )
    .map(SecretVec::new)
    .map_err(Into::into)
}

fn setup_srp(user_id: &str, login_key: &[u8]) -> Result<(SrpSession, LegacyKitSetupSrpRequest)> {
    let generated = auth::generate_srp_setup_with_login_key(login_key, user_id)?;
    let session = SrpSession::new(user_id, &generated.srp_salt, &generated.login_sub_key)?;
    let srp_a = b64::encode(&session.public_a());
    Ok((
        session,
        LegacyKitSetupSrpRequest {
            srp_user_id: user_id.to_string(),
            srp_salt: b64::encode(&generated.srp_salt),
            srp_verifier: b64::encode(&generated.srp_verifier),
            srp_a,
        },
    ))
}

fn srp_m1(session: &mut SrpSession, response: &LegacyKitSetupSrpResponse) -> Result<String> {
    Ok(b64::encode(
        &session.compute_m1(&b64::decode(&response.srp_b)?)?,
    ))
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LegacyKitChallengeRequest {
    #[serde(rename = "kitID")]
    kit_id: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LegacyKitChallengeResponse {
    encrypted_challenge: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LegacyKitOpenRecoveryRequest {
    #[serde(rename = "kitID")]
    kit_id: String,
    challenge: String,
    used_part_indexes: Option<Vec<u8>>,
    email: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LegacyKitOpenRecoveryResponse {
    session: LegacyKitRecoverySession,
    session_token: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LegacyKitSessionRequest {
    #[serde(rename = "sessionID")]
    session_id: String,
    session_token: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LegacyKitRecoveryInfoResponse {
    encrypted_recovery_blob: String,
    #[serde(rename = "userKeyAttr")]
    user_key_attr: KeyAttributes,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LegacyKitSetupSrpRequest {
    #[serde(rename = "srpUserID")]
    srp_user_id: String,
    srp_salt: String,
    srp_verifier: String,
    #[serde(rename = "srpA")]
    srp_a: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LegacyKitInitChangePasswordRequest {
    #[serde(rename = "sessionID")]
    session_id: String,
    session_token: String,
    #[serde(rename = "setupSRPRequest")]
    setup_srp_request: LegacyKitSetupSrpRequest,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LegacyKitSetupSrpResponse {
    #[serde(rename = "setupID")]
    setup_id: String,
    #[serde(rename = "srpB")]
    srp_b: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LegacyKitUpdatedKeyAttr {
    kek_salt: String,
    encrypted_key: String,
    key_decryption_nonce: String,
    mem_limit: u32,
    ops_limit: u32,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LegacyKitUpdateSrpAndKeysRequest {
    #[serde(rename = "setupID")]
    setup_id: String,
    #[serde(rename = "srpM1")]
    srp_m1: String,
    #[serde(rename = "updatedKeyAttr")]
    updated_key_attr: LegacyKitUpdatedKeyAttr,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LegacyKitChangePasswordRequest {
    #[serde(rename = "sessionID")]
    session_id: String,
    session_token: String,
    #[serde(rename = "updateSrpAndKeysRequest")]
    update_srp_and_keys_request: LegacyKitUpdateSrpAndKeysRequest,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LegacyKitChangePasswordResponse {
    #[serde(rename = "srpM2")]
    srp_m2: String,
}
