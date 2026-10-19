use std::time::{Duration, SystemTime, UNIX_EPOCH};

use ente_accounts::auth::recovery_key_from_mnemonic_or_hex;
use ente_accounts::{
    AccountsClient, AccountsClientConfig, AuthenticatedAccount, TwoFactorSetup,
    login::{LoginFlow, LoginStep},
    signup::Signup,
};
use ente_core::b64;
use ente_test_support::HARDCODED_OTT;
pub use ente_test_support::account_fixture::{
    TestAccount, create_account as create_fixture_account,
};
use hmac::{Hmac, KeyInit, Mac};
use sha1::Sha1;

use crate::CLIENT_PACKAGE;

type HmacSha1 = Hmac<Sha1>;

pub async fn create_account(endpoint: &str, email: String, password: String) -> TestAccount {
    let client = accounts_client(endpoint).unwrap();

    let authenticated = tokio::time::timeout(Duration::from_secs(180), async {
        client.send_otp(&email, "signup").await?;
        let response = client
            .verify_email(&email, HARDCODED_OTT, Some("testAccount"))
            .await?;
        Signup::verified(email.clone(), response)?
            .prepare(&client, &password)
            .await?
            .finish(&client)
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

pub async fn login_without_totp(
    endpoint: &str,
    email: &str,
    password: &str,
) -> ente_accounts::Result<AuthenticatedAccount> {
    let client = accounts_client(endpoint)?;

    tokio::time::timeout(Duration::from_secs(90), async {
        let (mut flow, mut step) = LoginFlow::start(&client, email.into()).await?;
        loop {
            step = match step {
                LoginStep::EmailCode => flow.submit_code(&client, HARDCODED_OTT).await?,
                LoginStep::Password => flow.submit_password(&client, password).await?,
                LoginStep::SecondFactor { .. } => {
                    return Err(ente_accounts::Error::InvalidInput(
                        "Second factor was requested unexpectedly in this e2e flow".into(),
                    ));
                }
                LoginStep::Complete(account) => return Ok(*account),
            };
        }
    })
    .await
    .expect("login timed out")
}

pub async fn enable_totp(endpoint: &str, account: &TestAccount) -> String {
    let client = accounts_client(endpoint).unwrap();
    client.set_auth_token(Some(account.auth_token.clone()));

    let result = tokio::time::timeout(Duration::from_secs(60), async {
        let setup =
            TwoFactorSetup::start(&client, &account.master_key, &account.key_attributes).await?;
        setup
            .enable(&client, &current_totp(&setup.secret_code))
            .await?;
        Ok::<_, ente_accounts::Error>(setup)
    })
    .await
    .expect("two-factor setup timed out")
    .expect("two-factor setup failed");

    result.secret_code.clone()
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
    let recovery_key = recovery_key_from_mnemonic_or_hex(
        authenticated
            .recovery_key
            .as_deref()
            .expect("authentication should return a recovery key"),
    )
    .expect("authentication recovery key should be valid")
    .into_vec();

    TestAccount {
        email,
        password,
        user_id: authenticated.user_id,
        auth_token: auth_token_from_authenticated(&authenticated),
        master_key: authenticated.secrets.master_key.clone(),
        recovery_key,
        secret_key: authenticated.secrets.secret_key.clone(),
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
