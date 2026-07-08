mod owner_blob;
mod shares;

use std::sync::Arc;

use ente_core::{
    auth::{self, KeyAttributes, SrpSession},
    crypto::{self, SecretString, SecretVec, kdf, sealed, secretbox},
    http::{HttpClient, HttpConfig},
};
use uuid::Uuid;

use crate::{
    ContactsError, Result,
    legacy_kit_models::{
        LEGACY_KIT_PAYLOAD_VERSION, LegacyKit, LegacyKitRecoveryBundle, LegacyKitRecoverySession,
        LegacyKitShare, LegacyKitVariant,
    },
    legacy_kit_transport::{
        CreateLegacyKitRequest, LegacyKitChallengeRequest, LegacyKitChallengeResponse,
        LegacyKitChangePasswordRequest, LegacyKitChangePasswordResponse,
        LegacyKitDownloadContentResponse, LegacyKitInitChangePasswordRequest,
        LegacyKitOpenRecoveryRequest, LegacyKitOpenRecoveryResponse, LegacyKitRecordResponse,
        LegacyKitRecoveryInfoResponse, LegacyKitSessionRequest, LegacyKitSetupSrpRequest,
        LegacyKitSetupSrpResponse, LegacyKitUpdateSrpAndKeysRequest, LegacyKitUpdatedKeyAttr,
    },
};
use owner_blob::{
    create_owner_blob, decrypt_owner_blob, encrypt_owner_blob, metadata_from_owner_blob,
};
use shares::{checksum, reconstruct_secret_2_of_3, split_secret_2_of_3, used_part_indexes};

const LEGACY_KIT_NOTICE_OPTIONS: [i32; 5] = [0, 24, 168, 360, 720];

pub(crate) fn create_legacy_kit_request(
    recovery_key: &[u8],
    master_key: &[u8],
    part_names: [String; 3],
    notice_period_in_hours: i32,
) -> Result<(CreateLegacyKitRequest, Vec<LegacyKitShare>)> {
    validate_notice_period(notice_period_in_hours)?;
    if part_names.iter().any(|name| name.trim().is_empty()) {
        return Err(ContactsError::InvalidInput(
            "legacy kit part names must be non-empty".into(),
        ));
    }

    let kit_id = Uuid::new_v4().to_string();
    let variant = LegacyKitVariant::TwoOfThree;
    let kit_secret = SecretVec::new(crypto::random_bytes(32));
    let checksum = checksum(LEGACY_KIT_PAYLOAD_VERSION, variant, &kit_id, &kit_secret);
    let shares = split_secret_2_of_3(&kit_secret)?;
    let result_shares = shares
        .into_iter()
        .zip(part_names.iter())
        .enumerate()
        .map(|(index, (share_bytes, part_name))| LegacyKitShare {
            payload_version: LEGACY_KIT_PAYLOAD_VERSION,
            variant,
            kit_id: kit_id.clone(),
            share_index: (index + 1) as u8,
            share: crypto::encode_b64(&share_bytes),
            checksum: checksum.clone(),
            part_name: part_name.clone(),
        })
        .collect::<Vec<_>>();

    let enc_key = derive_kit_enc_key(&kit_secret)?;
    let (auth_public_key, _auth_secret_key) = derive_kit_auth_keypair(&kit_secret)?;

    let encrypted_recovery_blob =
        secretbox::encrypt_combined(recovery_key, &crypto::Key::try_from_slice(&enc_key)?);
    let owner_blob = create_owner_blob(&result_shares);
    let encrypted_owner_blob = encrypt_owner_blob(&owner_blob, master_key)?;

    Ok((
        CreateLegacyKitRequest {
            id: kit_id,
            variant,
            notice_period_in_hours,
            encrypted_recovery_blob: crypto::encode_b64(&encrypted_recovery_blob),
            auth_public_key: crypto::encode_b64(auth_public_key.as_bytes()),
            encrypted_owner_blob,
        },
        result_shares,
    ))
}

pub(crate) fn decode_legacy_kit_record(
    response: LegacyKitRecordResponse,
    master_key: &[u8],
) -> Result<LegacyKit> {
    let owner_blob = decrypt_owner_blob(&response.encrypted_owner_blob, master_key)?;
    let metadata = metadata_from_owner_blob(&owner_blob);
    Ok(LegacyKit {
        id: response.id,
        variant: response.variant,
        notice_period_in_hours: response.notice_period_in_hours,
        legacy_url: response.legacy_url,
        metadata,
        created_at: response.created_at,
        updated_at: response.updated_at,
        active_recovery_session: response.active_recovery_session,
    })
}

pub(crate) fn decode_download_content(
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
        .collect::<Vec<_>>())
}

pub struct LegacyKitRecoveryClient {
    http: Arc<HttpClient>,
}

pub struct LegacyKitRecoveryHandle {
    http: Arc<HttpClient>,
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
        let http = HttpClient::new_with_config(HttpConfig {
            base_url: base_url.into(),
            auth_token: None,
            user_agent,
            client_package,
            client_version,
            timeout_secs: Some(30),
        })?;
        Ok(Self {
            http: Arc::new(http),
        })
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
            ContactsError::InvalidInput("at least two legacy kit shares are required".into())
        })?;
        let challenge = self
            .http
            .post_json::<LegacyKitChallengeResponse, _>(
                "/legacy-kits/recovery/challenge",
                &LegacyKitChallengeRequest {
                    kit_id: first_share.kit_id.clone(),
                },
            )
            .await
            .map_err(ContactsError::from)?;
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
            ContactsError::InvalidInput("at least two legacy kit shares are required".into())
        })?;
        let used_part_indexes = used_part_indexes(shares)?;
        self.open_with_kit_secret(
            first_share,
            kit_secret,
            encrypted_challenge,
            Some(used_part_indexes),
            email.map(ToOwned::to_owned),
        )
        .await
    }
}

impl LegacyKitRecoveryHandle {
    pub fn session(&self) -> &LegacyKitRecoverySession {
        &self.session
    }

    pub async fn refresh_session(&self) -> Result<LegacyKitRecoverySession> {
        self.http
            .post_json(
                "/legacy-kits/recovery/session",
                &LegacyKitSessionRequest {
                    session_id: self.session.id.clone(),
                    session_token: self.session_token.as_ref().to_owned(),
                },
            )
            .await
            .map_err(ContactsError::from)
    }

    pub async fn recovery_bundle(&self) -> Result<LegacyKitRecoveryBundle> {
        let response = self
            .http
            .post_json::<LegacyKitRecoveryInfoResponse, _>(
                "/legacy-kits/recovery/info",
                &LegacyKitSessionRequest {
                    session_id: self.session.id.clone(),
                    session_token: self.session_token.as_ref().to_owned(),
                },
            )
            .await
            .map_err(ContactsError::from)?;
        let enc_key = derive_kit_enc_key(&self.kit_secret)?;
        let encrypted_recovery_blob = crypto::decode_b64(&response.encrypted_recovery_blob)?;
        let recovery_key = secretbox::decrypt_combined(
            &encrypted_recovery_blob,
            &crypto::Key::try_from_slice(&enc_key)?,
        )?;
        Ok(LegacyKitRecoveryBundle {
            recovery_key: SecretVec::new(recovery_key),
            user_key_attributes: response.user_key_attr,
        })
    }

    pub async fn change_password(&self, new_password: &str) -> Result<()> {
        let bundle = self.recovery_bundle().await?;
        let target_master_key = decrypt_master_key_with_recovery_key(
            &bundle.user_key_attributes,
            &bundle.recovery_key,
        )?;
        let (updated_key_attrs, login_key) = auth::generate_key_attributes_for_new_password(
            &target_master_key,
            &bundle.user_key_attributes,
            new_password,
        )?;
        let srp_user_id = Uuid::new_v4().to_string();
        let (mut srp_session, setup_request) =
            password_reset_setup_request(&srp_user_id, &login_key)?;
        let init_response = self
            .http
            .post_json::<LegacyKitSetupSrpResponse, _>(
                "/legacy-kits/recovery/init-change-password",
                &LegacyKitInitChangePasswordRequest {
                    session_id: self.session.id.clone(),
                    session_token: self.session_token.as_ref().to_owned(),
                    setup_srp_request: setup_request,
                },
            )
            .await
            .map_err(ContactsError::from)?;
        let srp_m1 = srp_session_m1(&mut srp_session, &init_response)?;
        let updated_key_attr = LegacyKitUpdatedKeyAttr {
            kek_salt: updated_key_attrs.kek_salt.clone(),
            encrypted_key: updated_key_attrs.encrypted_key.clone(),
            key_decryption_nonce: updated_key_attrs.key_decryption_nonce.clone(),
            mem_limit: updated_key_attrs.mem_limit.ok_or_else(|| {
                ContactsError::InvalidInput("updated key attributes missing memLimit".into())
            })?,
            ops_limit: updated_key_attrs.ops_limit.ok_or_else(|| {
                ContactsError::InvalidInput("updated key attributes missing opsLimit".into())
            })?,
        };
        let change_response = self
            .http
            .post_json::<LegacyKitChangePasswordResponse, _>(
                "/legacy-kits/recovery/change-password",
                &LegacyKitChangePasswordRequest {
                    session_id: self.session.id.clone(),
                    session_token: self.session_token.as_ref().to_owned(),
                    update_srp_and_keys_request: LegacyKitUpdateSrpAndKeysRequest {
                        setup_id: init_response.setup_id,
                        srp_m1,
                        updated_key_attr,
                    },
                },
            )
            .await
            .map_err(ContactsError::from)?;
        let server_m2 = crypto::decode_b64(&change_response.srp_m2)?;
        srp_session.verify_m2(&server_m2)?;
        Ok(())
    }
}

impl LegacyKitRecoveryClient {
    async fn open_with_kit_secret(
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
            .http
            .post_json::<LegacyKitOpenRecoveryResponse, _>(
                "/legacy-kits/recovery/open",
                &LegacyKitOpenRecoveryRequest {
                    kit_id: first_share.kit_id.clone(),
                    challenge,
                    used_part_indexes,
                    email,
                },
            )
            .await
            .map_err(ContactsError::from)?;
        Ok(LegacyKitRecoveryHandle {
            http: Arc::clone(&self.http),
            session: response.session,
            session_token: SecretString::new(response.session_token),
            kit_secret,
        })
    }
}

pub(crate) fn validate_notice_period(hours: i32) -> Result<()> {
    if LEGACY_KIT_NOTICE_OPTIONS.contains(&hours) {
        Ok(())
    } else {
        Err(ContactsError::InvalidInput(
            "legacy kit notice period must be one of 0, 24, 168, 360, 720 hours".into(),
        ))
    }
}

fn derive_kit_enc_key(kit_secret: &[u8]) -> Result<SecretVec> {
    let kit_key = crypto::Key::try_from_slice(kit_secret)?;
    kdf::derive_subkey(&kit_key, 32, 1, b"lgkenc01").map_err(ContactsError::from)
}

fn derive_kit_auth_keypair(kit_secret: &[u8]) -> Result<(crypto::PublicKey, crypto::SecretKey)> {
    let kit_key = crypto::Key::try_from_slice(kit_secret)?;
    let seed = kdf::derive_subkey(&kit_key, 32, 2, b"lgkauth1").map_err(ContactsError::from)?;
    let sk = crypto::SecretKey::from_seed(seed.as_ref())?;
    Ok((sk.public_key(), sk))
}

fn decrypt_challenge(
    auth_public_key: &crypto::PublicKey,
    auth_secret_key: &crypto::SecretKey,
    encrypted_challenge_b64: &str,
) -> Result<String> {
    let encrypted_challenge = crypto::decode_b64(encrypted_challenge_b64)?;
    let plaintext = sealed::open(&encrypted_challenge, auth_public_key, auth_secret_key)?;
    String::from_utf8(plaintext).map_err(|error| {
        ContactsError::InvalidInput(format!("legacy kit challenge was not valid UTF-8: {error}"))
    })
}

fn decrypt_master_key_with_recovery_key(
    key_attributes: &KeyAttributes,
    recovery_key: &[u8],
) -> Result<SecretVec> {
    let encrypted_master_key = key_attributes
        .master_key_encrypted_with_recovery_key
        .as_ref()
        .ok_or_else(|| {
            ContactsError::InvalidInput(
                "target key attributes missing masterKeyEncryptedWithRecoveryKey".into(),
            )
        })?;
    let master_key_nonce = key_attributes
        .master_key_decryption_nonce
        .as_ref()
        .ok_or_else(|| {
            ContactsError::InvalidInput(
                "target key attributes missing masterKeyDecryptionNonce".into(),
            )
        })?;
    let encrypted_master_key = crypto::decode_b64(encrypted_master_key)?;
    let master_key_nonce = crypto::decode_b64(master_key_nonce)?;
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
) -> Result<(SrpSession, LegacyKitSetupSrpRequest)> {
    let generated_srp = auth::generate_srp_setup_with_login_key(login_key, srp_user_id)?;
    let srp_session = SrpSession::new(
        srp_user_id,
        &generated_srp.srp_salt,
        &generated_srp.login_sub_key,
    )?;
    let srp_a = crypto::encode_b64(&srp_session.public_a());
    Ok((
        srp_session,
        LegacyKitSetupSrpRequest {
            srp_user_id: srp_user_id.to_string(),
            srp_salt: crypto::encode_b64(&generated_srp.srp_salt),
            srp_verifier: crypto::encode_b64(&generated_srp.srp_verifier),
            srp_a,
        },
    ))
}

fn srp_session_m1(
    srp_session: &mut SrpSession,
    init_response: &LegacyKitSetupSrpResponse,
) -> Result<String> {
    let server_b = crypto::decode_b64(&init_response.srp_b)?;
    let client_m1 = srp_session.compute_m1(&server_b)?;
    Ok(crypto::encode_b64(&client_m1))
}
