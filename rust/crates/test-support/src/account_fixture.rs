use ente_accounts::auth::{SrpSession, generate_srp_setup_with_login_key};
use ente_accounts::{AccountsClient, AccountsClientConfig, KeyAttributes, models::SetupSrpRequest};
use ente_core::b64;
use ente_core::crypto::{Key, SecretKey, kdf, secretbox};
use uuid::Uuid;

use crate::{HARDCODED_OTT, HARDCODED_OTT_EMAIL_SUFFIX, TestResult};

pub const PASSWORD: &str = "museum-account-fixture-password";
// Argon2id(PASSWORD, 16 × 0x4d, 256 MiB, 16 ops).
pub const KEK: &str = "EwUWye3Qiu3bep2oujaO8oJvUgIdn0DSOk2g0oZ+AWs=";
pub const KEK_SALT: &str = "TU1NTU1NTU1NTU1NTU1NTQ==";
pub const MEM_LIMIT: u32 = 268_435_456;
pub const OPS_LIMIT: u32 = 16;

#[derive(Debug, Clone)]
pub struct TestAccount {
    pub email: String,
    pub password: String,
    pub user_id: i64,
    pub auth_token: String,
    pub master_key: Vec<u8>,
    pub recovery_key: Vec<u8>,
    pub secret_key: Vec<u8>,
    pub key_attributes: KeyAttributes,
}

pub async fn create_account(endpoint: &str, email_prefix: &str) -> TestResult<TestAccount> {
    let email = format!(
        "{email_prefix}-{}{HARDCODED_OTT_EMAIL_SUFFIX}",
        Uuid::new_v4()
    );
    let client = AccountsClient::new(
        AccountsClientConfig::new("io.ente.photos")
            .with_origin(endpoint.to_string())
            .with_user_agent("ente-tests"),
    )?;
    client.send_otp(&email, "signup").await?;
    let verification = client
        .verify_email(&email, HARDCODED_OTT, Some("testAccount"))
        .await?;
    let auth_token = verification.token.ok_or("signup should return a token")?;
    client.set_auth_token(Some(auth_token.clone()));

    let kek = Key::try_from_slice(&b64::decode(KEK)?)?;
    let master_key = Key::generate();
    let recovery_key = Key::generate();
    let secret_key = SecretKey::generate();
    let public_key = secret_key.public_key();
    let encrypted_master_key = secretbox::encrypt(master_key.as_bytes(), &kek);
    let encrypted_secret_key = secretbox::encrypt(secret_key.as_bytes(), &master_key);
    let encrypted_master_with_recovery = secretbox::encrypt(master_key.as_bytes(), &recovery_key);
    let encrypted_recovery_with_master = secretbox::encrypt(recovery_key.as_bytes(), &master_key);
    let key_attributes = KeyAttributes {
        kek_salt: KEK_SALT.into(),
        encrypted_key: b64::encode(&encrypted_master_key.encrypted_data),
        key_decryption_nonce: b64::encode(encrypted_master_key.nonce.as_bytes()),
        public_key: b64::encode(public_key.as_bytes()),
        encrypted_secret_key: b64::encode(&encrypted_secret_key.encrypted_data),
        secret_key_decryption_nonce: b64::encode(encrypted_secret_key.nonce.as_bytes()),
        mem_limit: MEM_LIMIT,
        ops_limit: OPS_LIMIT,
        master_key_encrypted_with_recovery_key: Some(b64::encode(
            &encrypted_master_with_recovery.encrypted_data,
        )),
        master_key_decryption_nonce: Some(b64::encode(
            encrypted_master_with_recovery.nonce.as_bytes(),
        )),
        recovery_key_encrypted_with_master_key: Some(b64::encode(
            &encrypted_recovery_with_master.encrypted_data,
        )),
        recovery_key_decryption_nonce: Some(b64::encode(
            encrypted_recovery_with_master.nonce.as_bytes(),
        )),
    };
    client
        .set_user_key_attributes(key_attributes.clone())
        .await?;

    let srp_user_id = Uuid::new_v4();
    let login_key = kdf::derive_login_key(&kek);
    let srp_setup = generate_srp_setup_with_login_key(&login_key, &srp_user_id.to_string())?;
    let mut srp_session = SrpSession::new(
        &srp_user_id.to_string(),
        &srp_setup.srp_salt,
        &srp_setup.login_sub_key,
    )?;
    let response = client
        .setup_srp(&SetupSrpRequest {
            srp_user_id: srp_user_id.to_string(),
            srp_salt: b64::encode(&srp_setup.srp_salt),
            srp_verifier: b64::encode(&srp_setup.srp_verifier),
            srp_a: b64::encode(&pad_left(&srp_session.public_a(), 512)),
        })
        .await?;
    let srp_m1 = b64::encode(&srp_session.compute_m1(&b64::decode(&response.srp_b)?)?);
    let complete = client
        .complete_srp_setup(&response.setup_id, &srp_m1)
        .await?;
    srp_session.verify_m2(&b64::decode(&complete.srp_m2)?)?;

    Ok(TestAccount {
        email,
        password: PASSWORD.into(),
        user_id: verification.id,
        auth_token,
        master_key: master_key.as_bytes().to_vec(),
        recovery_key: recovery_key.as_bytes().to_vec(),
        secret_key: secret_key.as_bytes().to_vec(),
        key_attributes,
    })
}

fn pad_left(data: &[u8], len: usize) -> Vec<u8> {
    let mut padded = vec![0; len.saturating_sub(data.len())];
    padded.extend_from_slice(data);
    padded
}
