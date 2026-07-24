use base64::{Engine, engine::general_purpose::STANDARD};
use ente_accounts::{
    AccountsClient, AccountsClientConfig, KeyAttributes,
    auth::{SrpSession, generate_srp_setup_with_login_key},
    models::SetupSrpRequest,
};
use ente_core::crypto::{Key, SecretKey, decode_b64, encode_b64, kdf, secretbox};
use ente_test_support::{HARDCODED_OTT, HARDCODED_OTT_EMAIL_SUFFIX, account_fixture};
use uuid::Uuid;

use super::{CLIENT_PACKAGE, USER_AGENT};

const SRP_A_LEN: usize = 512;

pub struct TestAccount {
    pub user_id: i64,
    pub auth_token: String,
    pub master_key: Vec<u8>,
}

pub async fn create_account(endpoint: &str, email_prefix: &str) -> TestAccount {
    let email = format!(
        "{email_prefix}-{}{HARDCODED_OTT_EMAIL_SUFFIX}",
        Uuid::new_v4()
    );
    let client = AccountsClient::new(
        AccountsClientConfig::new(CLIENT_PACKAGE)
            .with_origin(endpoint)
            .with_user_agent(USER_AGENT),
    )
    .unwrap();
    client.send_otp(&email, "signup").await.unwrap();
    let verification = client
        .verify_email(&email, HARDCODED_OTT, Some("testAccount"))
        .await
        .unwrap();
    let auth_token = verification.token.expect("signup should return a token");
    client.set_auth_token(Some(auth_token.clone()));

    let kek = Key::try_from_slice(&decode_b64(account_fixture::KEK).unwrap()).unwrap();
    let master_key = Key::generate();
    let recovery_key = Key::generate();
    let secret_key = SecretKey::generate();
    let public_key = secret_key.public_key();
    let encrypted_master_key = secretbox::encrypt(master_key.as_bytes(), &kek);
    let encrypted_secret_key = secretbox::encrypt(secret_key.as_bytes(), &master_key);
    let encrypted_master_with_recovery = secretbox::encrypt(master_key.as_bytes(), &recovery_key);
    let encrypted_recovery_with_master = secretbox::encrypt(recovery_key.as_bytes(), &master_key);
    let key_attributes = KeyAttributes {
        kek_salt: account_fixture::KEK_SALT.into(),
        kek_hash: None,
        encrypted_key: encode_b64(&encrypted_master_key.encrypted_data),
        key_decryption_nonce: encode_b64(encrypted_master_key.nonce.as_bytes()),
        public_key: encode_b64(public_key.as_bytes()),
        encrypted_secret_key: encode_b64(&encrypted_secret_key.encrypted_data),
        secret_key_decryption_nonce: encode_b64(encrypted_secret_key.nonce.as_bytes()),
        mem_limit: account_fixture::MEM_LIMIT,
        ops_limit: account_fixture::OPS_LIMIT,
        master_key_encrypted_with_recovery_key: Some(encode_b64(
            &encrypted_master_with_recovery.encrypted_data,
        )),
        master_key_decryption_nonce: Some(encode_b64(
            encrypted_master_with_recovery.nonce.as_bytes(),
        )),
        recovery_key_encrypted_with_master_key: Some(encode_b64(
            &encrypted_recovery_with_master.encrypted_data,
        )),
        recovery_key_decryption_nonce: Some(encode_b64(
            encrypted_recovery_with_master.nonce.as_bytes(),
        )),
    };
    client
        .set_user_key_attributes(key_attributes)
        .await
        .unwrap();

    let srp_user_id = Uuid::new_v4();
    let login_key = kdf::derive_login_key(&kek);
    let srp_setup =
        generate_srp_setup_with_login_key(&login_key, &srp_user_id.to_string()).unwrap();
    let mut srp_session = SrpSession::new(
        &srp_user_id.to_string(),
        &srp_setup.srp_salt,
        &srp_setup.login_sub_key,
    )
    .unwrap();
    let response = client
        .setup_srp(&SetupSrpRequest {
            srp_user_id: srp_user_id.to_string(),
            srp_salt: STANDARD.encode(&srp_setup.srp_salt),
            srp_verifier: STANDARD.encode(&srp_setup.srp_verifier),
            srp_a: STANDARD.encode(pad_left(&srp_session.public_a(), SRP_A_LEN)),
        })
        .await
        .unwrap();
    let srp_m1 = STANDARD.encode(
        srp_session
            .compute_m1(&STANDARD.decode(&response.srp_b).unwrap())
            .unwrap(),
    );
    let complete = client
        .complete_srp_setup(&response.setup_id, &srp_m1)
        .await
        .unwrap();
    srp_session
        .verify_m2(&STANDARD.decode(&complete.srp_m2).unwrap())
        .unwrap();

    TestAccount {
        user_id: verification.id,
        auth_token,
        master_key: master_key.as_bytes().to_vec(),
    }
}

fn pad_left(data: &[u8], len: usize) -> Vec<u8> {
    let mut padded = vec![0; len.saturating_sub(data.len())];
    padded.extend_from_slice(data);
    padded
}
