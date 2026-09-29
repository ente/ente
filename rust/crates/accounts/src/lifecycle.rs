use ente_core::b64;
use ente_core::crypto::{self, SecretVec, secretbox};
use std::fmt;
use uuid::Uuid;
use zeroize::{ZeroizeOnDrop, Zeroizing};

use crate::{
    AccountsClient, Error, Result,
    auth::{
        self, GeneratedSrpSetup, KeyDerivationStrength, generate_srp_setup_with_login_key,
        get_recovery_key,
    },
    models::{
        ConfigurePasskeyRecoveryRequest, EnableTwoFactorRequest, KeyAttributes,
        RemoveTwoFactorRequest, SetRecoveryKeyRequest, SetupSrpRequest, SrpAttributes,
        TwoFactorAuthorizationResponse, TwoFactorRecoveryResponse, TwoFactorType,
        UpdateSrpAndKeysRequest, UpdatedKeyAttr,
    },
};

pub struct ChangePasswordParams {
    pub email: String,
    pub password: Zeroizing<String>,
    pub master_key: SecretVec,
    pub key_attributes: KeyAttributes,
    pub log_out_other_devices: bool,
}

impl fmt::Debug for ChangePasswordParams {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("ChangePasswordParams")
            .field("email", &self.email)
            .field("password", &"[REDACTED]")
            .field("master_key", &"[REDACTED]")
            .field("key_attributes", &self.key_attributes)
            .field("log_out_other_devices", &self.log_out_other_devices)
            .finish()
    }
}

#[derive(Debug)]
pub struct ChangePasswordResult {
    pub key_attributes: KeyAttributes,
    pub srp_attributes: SrpAttributes,
}

#[derive(Debug)]
pub struct CheckSessionValidityParams {
    pub email: String,
    pub local_srp_attributes: SrpAttributes,
}

#[derive(Debug)]
#[cfg_attr(
    target_pointer_width = "64",
    expect(
        clippy::large_enum_variant,
        reason = "A single session-check result does not need a separate allocation"
    )
)]
pub enum SessionValidity {
    Invalid,
    Valid,
    ValidButPasswordChanged {
        updated_key_attributes: KeyAttributes,
        updated_srp_attributes: SrpAttributes,
    },
}

pub struct RecoveryKeyResult {
    pub recovery_key: String,
    pub key_attributes: KeyAttributes,
}

impl fmt::Debug for RecoveryKeyResult {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("RecoveryKeyResult")
            .field("recovery_key", &"[REDACTED]")
            .field("key_attributes", &self.key_attributes)
            .finish()
    }
}

#[derive(ZeroizeOnDrop)]
pub struct TwoFactorSetup {
    pub secret_code: String,
    pub qr_code: String,
    pub recovery_key: String,
}

impl TwoFactorSetup {
    pub async fn start(
        client: &AccountsClient,
        master_key: &[u8],
        key_attributes: &KeyAttributes,
    ) -> Result<Self> {
        let master_key = crypto::Key::try_from_slice(master_key)?;
        let recovery_key = get_recovery_key(&master_key, key_attributes)?;
        let secret = client.setup_two_factor().await?;
        Ok(Self {
            secret_code: secret.secret_code,
            qr_code: secret.qr_code,
            recovery_key,
        })
    }

    pub async fn enable(&self, client: &AccountsClient, code: &str) -> Result<()> {
        let request = encrypt_two_factor_secret(&self.secret_code, &self.recovery_key, code)?;
        client.enable_two_factor(&request).await
    }
}

pub async fn change_password(
    client: &AccountsClient,
    params: ChangePasswordParams,
) -> Result<ChangePasswordResult> {
    change_password_with_strength(client, params, KeyDerivationStrength::Sensitive).await
}

async fn change_password_with_strength(
    client: &AccountsClient,
    params: ChangePasswordParams,
    key_derivation_strength: KeyDerivationStrength,
) -> Result<ChangePasswordResult> {
    let (updated_key_attributes, login_key) =
        auth::generate_key_attributes_for_new_password_with_strength(
            &params.master_key,
            &params.key_attributes,
            &params.password,
            key_derivation_strength,
        )?;

    let updated_key_attr = UpdatedKeyAttr::from(&updated_key_attributes);

    let srp_user_id = Uuid::new_v4();
    let srp_setup = generate_srp_setup_with_login_key(&login_key, &srp_user_id.to_string())?;
    complete_srp_update(
        client,
        &srp_user_id,
        &srp_setup,
        &updated_key_attr,
        params.log_out_other_devices,
    )
    .await?;

    let srp_attributes = client.get_srp_attributes(&params.email).await?;

    srp_attributes.validate_setup(
        srp_user_id,
        &srp_setup.srp_salt,
        &updated_key_attributes,
        "password change",
    )?;

    Ok(ChangePasswordResult {
        key_attributes: updated_key_attributes,
        srp_attributes,
    })
}

pub async fn check_session_validity(
    client: &AccountsClient,
    params: CheckSessionValidityParams,
) -> Result<SessionValidity> {
    let remote = match client.get_session_validity().await {
        Ok(remote) => remote,
        Err(Error::SessionInvalid) => return Ok(SessionValidity::Invalid),
        Err(error) => return Err(error),
    };

    if let Some(remote_key_attributes) = remote.key_attributes {
        let remote_srp_attributes = client.get_srp_attributes(&params.email).await?;
        if remote_srp_attributes.kek_salt != params.local_srp_attributes.kek_salt {
            return Ok(SessionValidity::ValidButPasswordChanged {
                updated_key_attributes: remote_key_attributes,
                updated_srp_attributes: remote_srp_attributes,
            });
        }
    }

    Ok(SessionValidity::Valid)
}

pub async fn create_recovery_key(
    client: &AccountsClient,
    master_key: &[u8],
    existing_attributes: &KeyAttributes,
) -> Result<RecoveryKeyResult> {
    let (
        recovery_key,
        master_key_encrypted_with_recovery_key,
        master_key_decryption_nonce,
        recovery_key_encrypted_with_master_key,
        recovery_key_decryption_nonce,
    ) = auth::create_new_recovery_key(master_key)?;

    let request = SetRecoveryKeyRequest {
        master_key_encrypted_with_recovery_key: master_key_encrypted_with_recovery_key.clone(),
        master_key_decryption_nonce: master_key_decryption_nonce.clone(),
        recovery_key_encrypted_with_master_key: recovery_key_encrypted_with_master_key.clone(),
        recovery_key_decryption_nonce: recovery_key_decryption_nonce.clone(),
    };
    client.set_recovery_key_attributes(request).await?;

    let key_attributes = KeyAttributes {
        master_key_encrypted_with_recovery_key: Some(master_key_encrypted_with_recovery_key),
        master_key_decryption_nonce: Some(master_key_decryption_nonce),
        recovery_key_encrypted_with_master_key: Some(recovery_key_encrypted_with_master_key),
        recovery_key_decryption_nonce: Some(recovery_key_decryption_nonce),
        ..existing_attributes.clone()
    };

    Ok(RecoveryKeyResult {
        recovery_key,
        key_attributes,
    })
}

pub async fn recover_two_factor(
    client: &AccountsClient,
    two_factor_type: TwoFactorType,
    session_id: &str,
    recovery_response: &TwoFactorRecoveryResponse,
    recovery_key_mnemonic_or_hex: &str,
) -> Result<TwoFactorAuthorizationResponse> {
    let recovery_key = auth::recovery_key_from_mnemonic_or_hex(recovery_key_mnemonic_or_hex)?;
    let encrypted_secret = b64::decode(&recovery_response.encrypted_secret)?;
    let nonce = b64::decode(&recovery_response.secret_decryption_nonce)?;
    let secret = secretbox::decrypt(
        &encrypted_secret,
        &crypto::Nonce::try_from_slice(&nonce)?,
        &crypto::Key::try_from_slice(&recovery_key)?,
    )
    .map_err(|_| Error::IncorrectRecoveryKey)?;
    let request = RemoveTwoFactorRequest {
        session_id: session_id.to_string(),
        secret: String::from_utf8(secret)
            .map_err(|e| Error::Protocol(format!("invalid recovery secret: {e}")))?,
        two_factor_type,
    };
    client.remove_two_factor(&request).await
}

pub async fn configure_passkey_recovery(
    client: &AccountsClient,
    secret: &str,
    recovery_key_mnemonic_or_hex: &str,
) -> Result<()> {
    let recovery_key = auth::recovery_key_from_mnemonic_or_hex(recovery_key_mnemonic_or_hex)?;
    let encrypted = secretbox::encrypt(
        secret.as_bytes(),
        &crypto::Key::try_from_slice(&recovery_key)?,
    );
    let request = ConfigurePasskeyRecoveryRequest {
        secret: secret.to_string(),
        user_secret_cipher: b64::encode(&encrypted.encrypted_data),
        user_secret_nonce: b64::encode(encrypted.nonce.as_bytes()),
    };
    client.configure_passkey_recovery(&request).await
}

async fn complete_srp_update(
    client: &AccountsClient,
    srp_user_id: &Uuid,
    srp_setup: &GeneratedSrpSetup,
    updated_key_attr: &UpdatedKeyAttr,
    log_out_other_devices: bool,
) -> Result<crate::models::UpdateSrpAndKeysResponse> {
    let mut srp_session = auth::SrpSession::new(
        &srp_user_id.to_string(),
        &srp_setup.srp_salt,
        &srp_setup.login_sub_key,
    )?;
    let srp_a = b64::encode(&srp_session.public_a());

    let setup = client
        .setup_srp(&SetupSrpRequest {
            srp_user_id: srp_user_id.to_string(),
            srp_salt: b64::encode(&srp_setup.srp_salt),
            srp_verifier: b64::encode(&srp_setup.srp_verifier),
            srp_a,
        })
        .await?;

    let srp_b = b64::decode(&setup.srp_b)?;
    let srp_m1 = b64::encode(&srp_session.compute_m1(&srp_b)?);

    let response = client
        .update_srp_and_key_attributes(&UpdateSrpAndKeysRequest {
            setup_id: setup.setup_id.to_string(),
            srp_m1,
            updated_key_attr: updated_key_attr.clone(),
            log_out_other_devices,
        })
        .await?;

    let srp_m2 = b64::decode(&response.srp_m2)?;
    srp_session.verify_m2(&srp_m2)?;
    Ok(response)
}

fn encrypt_two_factor_secret(
    secret_code: &str,
    recovery_key_hex: &str,
    code: &str,
) -> Result<EnableTwoFactorRequest> {
    let recovery_key =
        hex::decode(recovery_key_hex).map_err(|e| Error::Decode(format!("recovery_key: {e}")))?;
    let encrypted = secretbox::encrypt(
        secret_code.as_bytes(),
        &crypto::Key::try_from_slice(&recovery_key)?,
    );

    Ok(EnableTwoFactorRequest {
        code: code.to_string(),
        encrypted_two_factor_secret: b64::encode(&encrypted.encrypted_data),
        two_factor_secret_decryption_nonce: b64::encode(encrypted.nonce.as_bytes()),
    })
}

#[cfg(test)]
mod tests;
