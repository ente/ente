use std::time::{Duration, SystemTime, UNIX_EPOCH};

use ente_accounts::auth::{SrpSession, generate_srp_setup_with_login_key};
use ente_accounts::{
    AccountsClient, AccountsClientConfig, AuthFlow, AuthFlowUi, AuthenticatedAccount,
    CreateAccountParams, KeyAttributes, LoginParams, OtpPurpose, SecondFactorMethod,
    SetupTwoFactorParams, TotpPurpose, models::SetupSrpRequest,
};
use ente_core::b64;
use ente_core::crypto::{Key, SecretKey, SecretVec, kdf, secretbox};
use ente_test_support::{HARDCODED_OTT, account_fixture};
use hmac::{Hmac, KeyInit, Mac};
use sha1::Sha1;
use uuid::Uuid;
use zeroize::Zeroizing;

use crate::CLIENT_PACKAGE;

type HmacSha1 = Hmac<Sha1>;

const SRP_A_LEN: usize = 512;

#[derive(Debug, Clone)]
pub struct TestAccount {
    pub email: String,
    pub password: String,
    pub user_id: i64,
    pub auth_token: String,
    pub master_key: Vec<u8>,
    pub key_attributes: KeyAttributes,
}

struct TestUi {
    otp: String,
    totp_secret: Option<String>,
    allow_totp: bool,
}

impl TestUi {
    fn otp_only() -> Self {
        Self {
            otp: HARDCODED_OTT.into(),
            totp_secret: None,
            allow_totp: false,
        }
    }

    fn with_totp(secret: Option<String>) -> Self {
        Self {
            otp: HARDCODED_OTT.into(),
            totp_secret: secret,
            allow_totp: true,
        }
    }
}

impl AuthFlowUi for TestUi {
    fn read_email_otp(
        &mut self,
        _email: &str,
        _purpose: OtpPurpose,
        _resent: bool,
    ) -> ente_accounts::Result<String> {
        Ok(self.otp.clone())
    }

    fn read_totp_code(&mut self, _purpose: TotpPurpose) -> ente_accounts::Result<String> {
        if !self.allow_totp {
            return Err(ente_accounts::Error::InvalidInput(
                "TOTP was requested unexpectedly in this e2e flow".into(),
            ));
        }

        let secret = self.totp_secret.as_deref().ok_or_else(|| {
            ente_accounts::Error::InvalidInput("No TOTP secret captured for rust e2e flow".into())
        })?;
        Ok(current_totp(secret))
    }

    fn report_retryable_error(&mut self, _message: &str) -> ente_accounts::Result<()> {
        Ok(())
    }

    fn choose_second_factor(
        &mut self,
        _methods: &[SecondFactorMethod],
    ) -> ente_accounts::Result<SecondFactorMethod> {
        Ok(SecondFactorMethod::Totp)
    }

    fn present_passkey_verification(&mut self, _url: &str) -> ente_accounts::Result<()> {
        Err(ente_accounts::Error::InvalidInput(
            "Passkey flow not expected in rust e2e tests".into(),
        ))
    }

    fn wait_for_passkey_verification(&mut self) -> ente_accounts::Result<()> {
        Err(ente_accounts::Error::InvalidInput(
            "Passkey flow not expected in rust e2e tests".into(),
        ))
    }

    fn present_totp_secret(
        &mut self,
        secret_code: &str,
        _qr_code: &str,
    ) -> ente_accounts::Result<()> {
        self.totp_secret = Some(secret_code.to_string());
        Ok(())
    }
}

pub async fn create_account(endpoint: &str, email: String, password: String) -> TestAccount {
    let client = accounts_client(endpoint).unwrap();
    let mut ui = TestUi::otp_only();

    let authenticated = tokio::time::timeout(Duration::from_secs(180), async {
        let mut flow = AuthFlow::new(&client, &mut ui);
        flow.create_account(CreateAccountParams {
            email: email.clone(),
            password: Zeroizing::new(password.clone()),
            source: Some("testAccount".into()),
        })
        .await
    })
    .await
    .expect("signup timed out")
    .expect("signup failed");

    test_account_from_authenticated(email, password, authenticated)
}

pub async fn create_account_strict(
    endpoint: &str,
    email_prefix: &str,
    password_prefix: &str,
) -> TestAccount {
    create_account(
        endpoint,
        crate::support::unique_test_email(email_prefix),
        crate::support::unique_password(password_prefix),
    )
    .await
}

pub async fn create_fixture_account(endpoint: &str, email_prefix: &str) -> TestAccount {
    let email = crate::support::unique_test_email(email_prefix);
    let client = accounts_client(endpoint).unwrap();
    client.send_otp(&email, "signup").await.unwrap();
    let verification = client
        .verify_email(&email, HARDCODED_OTT, Some("testAccount"))
        .await
        .unwrap();
    let auth_token = verification.token.expect("signup should return a token");
    client.set_auth_token(Some(auth_token.clone()));

    let kek = Key::try_from_slice(&b64::decode(account_fixture::KEK).unwrap()).unwrap();
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
        encrypted_key: b64::encode(&encrypted_master_key.encrypted_data),
        key_decryption_nonce: b64::encode(encrypted_master_key.nonce.as_bytes()),
        public_key: b64::encode(public_key.as_bytes()),
        encrypted_secret_key: b64::encode(&encrypted_secret_key.encrypted_data),
        secret_key_decryption_nonce: b64::encode(encrypted_secret_key.nonce.as_bytes()),
        mem_limit: account_fixture::MEM_LIMIT,
        ops_limit: account_fixture::OPS_LIMIT,
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
            srp_salt: b64::encode(&srp_setup.srp_salt),
            srp_verifier: b64::encode(&srp_setup.srp_verifier),
            srp_a: b64::encode(&pad_left(&srp_session.public_a(), SRP_A_LEN)),
        })
        .await
        .unwrap();
    let srp_m1 = b64::encode(
        &srp_session
            .compute_m1(&b64::decode(&response.srp_b).unwrap())
            .unwrap(),
    );
    let complete = client
        .complete_srp_setup(&response.setup_id, &srp_m1)
        .await
        .unwrap();
    srp_session
        .verify_m2(&b64::decode(&complete.srp_m2).unwrap())
        .unwrap();

    TestAccount {
        email,
        password: account_fixture::PASSWORD.into(),
        user_id: verification.id,
        auth_token,
        master_key: master_key.as_bytes().to_vec(),
        key_attributes,
    }
}

pub async fn login_without_totp(
    endpoint: &str,
    email: &str,
    password: &str,
) -> ente_accounts::Result<AuthenticatedAccount> {
    let mut ui = TestUi::otp_only();
    login_with_ui(endpoint, email, password, &mut ui).await
}

async fn login_with_ui<U: AuthFlowUi>(
    endpoint: &str,
    email: &str,
    password: &str,
    ui: &mut U,
) -> ente_accounts::Result<AuthenticatedAccount> {
    let client = accounts_client(endpoint)?;

    tokio::time::timeout(Duration::from_secs(90), async {
        let mut flow = AuthFlow::new(&client, ui);
        flow.login(LoginParams {
            email: email.to_string(),
            password: Zeroizing::new(password.to_string()),
        })
        .await
    })
    .await
    .expect("login timed out")
}

pub async fn enable_totp(endpoint: &str, account: &TestAccount) -> String {
    let client = accounts_client(endpoint).unwrap();
    client.set_auth_token(Some(account.auth_token.clone()));
    let mut ui = TestUi::with_totp(None);

    let result = tokio::time::timeout(Duration::from_secs(60), async {
        let mut flow = AuthFlow::new(&client, &mut ui);
        flow.setup_two_factor(SetupTwoFactorParams {
            master_key: SecretVec::new(account.master_key.clone()),
            key_attributes: Some(account.key_attributes.clone()),
        })
        .await
    })
    .await
    .expect("two-factor setup timed out")
    .expect("two-factor setup failed");

    result.secret_code
}

pub async fn fetch_two_factor_status(
    endpoint: &str,
    account: &TestAccount,
) -> ente_accounts::Result<bool> {
    fetch_two_factor_status_with_token(endpoint, &account.auth_token).await
}

async fn fetch_two_factor_status_with_token(
    endpoint: &str,
    auth_token: &str,
) -> ente_accounts::Result<bool> {
    let client = accounts_client(endpoint)?;
    client.set_auth_token(Some(auth_token.to_string()));
    client.get_two_factor_status().await
}

fn auth_token_from_authenticated(account: &AuthenticatedAccount) -> String {
    b64::encode_url_safe(&account.secrets.token)
}

pub fn test_account_from_authenticated(
    email: String,
    password: String,
    authenticated: AuthenticatedAccount,
) -> TestAccount {
    assert!(
        authenticated.recovery_key.is_some(),
        "signup should return a recovery key"
    );

    TestAccount {
        email,
        password,
        user_id: authenticated.user_id,
        auth_token: auth_token_from_authenticated(&authenticated),
        master_key: authenticated.secrets.master_key.clone(),
        key_attributes: authenticated.key_attributes,
    }
}

fn current_totp(secret: &str) -> String {
    let key = decode_base32(secret);
    let counter = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system time before UNIX_EPOCH")
        .as_secs()
        / 30;

    let mut mac = HmacSha1::new_from_slice(&key).expect("invalid HMAC key");
    mac.update(&counter.to_be_bytes());
    let digest = mac.finalize().into_bytes();
    let offset = (digest[19] & 0x0f) as usize;

    let binary = ((digest[offset] as u32 & 0x7f) << 24)
        | ((digest[offset + 1] as u32) << 16)
        | ((digest[offset + 2] as u32) << 8)
        | digest[offset + 3] as u32;

    format!("{:06}", binary % 1_000_000)
}

fn decode_base32(secret: &str) -> Vec<u8> {
    let mut output = Vec::new();
    let mut buffer = 0u32;
    let mut bits = 0u8;

    for ch in secret
        .chars()
        .filter(|ch| !ch.is_whitespace() && *ch != '=')
    {
        let value = match ch {
            'A'..='Z' => ch as u8 - b'A',
            'a'..='z' => ch as u8 - b'a',
            '2'..='7' => ch as u8 - b'2' + 26,
            _ => panic!("invalid base32 character in TOTP secret: {ch}"),
        } as u32;

        buffer = (buffer << 5) | value;
        bits += 5;

        while bits >= 8 {
            bits -= 8;
            output.push(((buffer >> bits) & 0xff) as u8);
        }
    }

    output
}

fn accounts_client(endpoint: &str) -> ente_accounts::Result<AccountsClient> {
    AccountsClient::new(
        AccountsClientConfig::new(CLIENT_PACKAGE)
            .with_origin(endpoint.to_string())
            .with_user_agent("ente-contacts-e2e"),
    )
}

fn pad_left(data: &[u8], len: usize) -> Vec<u8> {
    let mut padded = vec![0; len.saturating_sub(data.len())];
    padded.extend_from_slice(data);
    padded
}
