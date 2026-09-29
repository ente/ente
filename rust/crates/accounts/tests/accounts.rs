#![cfg(test)]
#![cfg(feature = "museum")]

use std::time::{SystemTime, UNIX_EPOCH};

use ente_accounts::{
    AccountsClient, AccountsClientConfig, TwoFactorSetup,
    login::{LoginFlow, LoginStep},
    signup::Signup,
};
use ente_test_support::{HARDCODED_OTT, HARDCODED_OTT_EMAIL_SUFFIX, Museum, TestResult};
use hmac::{Hmac, KeyInit, Mac};
use sha1::Sha1;
use uuid::Uuid;

type HmacSha1 = Hmac<Sha1>;

#[test]
fn accounts() -> TestResult {
    Museum::run_async(run)
}

async fn run(endpoint: String) -> TestResult {
    let endpoint = &endpoint;
    let email = format!(
        "accounts-e2e-{}{HARDCODED_OTT_EMAIL_SUFFIX}",
        Uuid::new_v4()
    );
    let password = format!("Accounts-{}!", Uuid::new_v4().simple());
    let client = accounts_client(endpoint);
    client.send_otp(&email, "signup").await?;
    let response = client
        .verify_email(&email, HARDCODED_OTT, Some("testAccount"))
        .await?;
    let created = Signup::verified(email.clone(), response)?
        .prepare(&client, &password)
        .await?
        .finish(&client)
        .await?;
    let setup = TwoFactorSetup::start(
        &client,
        &created.secrets.master_key,
        &created.key_attributes,
    )
    .await?;
    setup
        .enable(&client, &current_totp(&setup.secret_code))
        .await?;

    let login_client = accounts_client(endpoint);
    let (mut flow, mut step) = LoginFlow::start(&login_client, email.clone()).await?;
    let login = loop {
        step = match step {
            LoginStep::EmailCode => flow.submit_code(&login_client, HARDCODED_OTT).await?,
            LoginStep::Password => flow.submit_password(&login_client, &password).await?,
            LoginStep::SecondFactor { totp: true, .. } => {
                flow.submit_code(&login_client, &current_totp(&setup.secret_code))
                    .await?
            }
            LoginStep::SecondFactor { .. } => panic!("expected authenticator verification"),
            LoginStep::Complete(account) => break account,
        };
    };
    assert_eq!(login.user_id, created.user_id);
    assert_eq!(login.secrets.master_key, created.secrets.master_key);
    assert_eq!(client.email().await.unwrap(), email);
    assert!(client.get_two_factor_status().await.unwrap());
    Ok(())
}

fn accounts_client(endpoint: &str) -> AccountsClient {
    AccountsClient::new(
        AccountsClientConfig::new("io.ente.photos")
            .with_origin(endpoint)
            .with_user_agent("ente-accounts-e2e"),
    )
    .unwrap()
}

fn current_totp(secret: &str) -> String {
    let key = decode_base32(secret);
    let counter = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        / 30;
    let mut mac = HmacSha1::new_from_slice(&key).unwrap();
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
    for ch in secret.chars().filter(|ch| *ch != '=') {
        let value = match ch {
            'A'..='Z' => ch as u8 - b'A',
            '2'..='7' => ch as u8 - b'2' + 26,
            _ => panic!("invalid base32 character: {ch}"),
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
