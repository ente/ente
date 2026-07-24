#![cfg(feature = "museum")]

use std::time::{SystemTime, UNIX_EPOCH};

use ente_accounts::{
    AccountsClient, AccountsClientConfig, AuthFlow, AuthFlowUi, CreateAccountParams,
    Error as AccountsError, LoginParams, OtpPurpose, Result as AccountsResult, SecondFactorMethod,
    SetupTwoFactorParams, TotpPurpose,
};
use ente_core::crypto::SecretVec;
use ente_test_support::{HARDCODED_OTT, HARDCODED_OTT_EMAIL_SUFFIX, Museum, TestResult};
use hmac::{Hmac, KeyInit, Mac};
use sha1::Sha1;
use uuid::Uuid;
use zeroize::Zeroizing;

type HmacSha1 = Hmac<Sha1>;

struct TestUi {
    totp_secret: Option<String>,
}

impl AuthFlowUi for TestUi {
    fn read_email_otp(
        &mut self,
        _email: &str,
        _purpose: OtpPurpose,
        _resent: bool,
    ) -> AccountsResult<String> {
        Ok(HARDCODED_OTT.into())
    }

    fn read_totp_code(&mut self, _purpose: TotpPurpose) -> AccountsResult<String> {
        self.totp_secret
            .as_deref()
            .map(current_totp)
            .ok_or_else(|| AccountsError::InvalidInput("TOTP secret missing".into()))
    }

    fn report_retryable_error(&mut self, _message: &str) -> AccountsResult<()> {
        Ok(())
    }

    fn choose_second_factor(
        &mut self,
        _methods: &[SecondFactorMethod],
    ) -> AccountsResult<SecondFactorMethod> {
        Ok(SecondFactorMethod::Totp)
    }

    fn present_passkey_verification(&mut self, _url: &str) -> AccountsResult<()> {
        Err(AccountsError::InvalidInput(
            "Passkey flow not expected".into(),
        ))
    }

    fn wait_for_passkey_verification(&mut self) -> AccountsResult<()> {
        Err(AccountsError::InvalidInput(
            "Passkey flow not expected".into(),
        ))
    }

    fn present_totp_secret(&mut self, secret_code: &str, _qr_code: &str) -> AccountsResult<()> {
        self.totp_secret = Some(secret_code.to_string());
        Ok(())
    }
}

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
    let mut ui = TestUi { totp_secret: None };
    let mut flow = AuthFlow::new(&client, &mut ui);
    let created = flow
        .create_account(CreateAccountParams {
            email: email.clone(),
            password: Zeroizing::new(password.clone()),
            source: Some("testAccount".into()),
        })
        .await
        .unwrap();

    let mut ui = TestUi { totp_secret: None };
    let setup = AuthFlow::new(&client, &mut ui)
        .setup_two_factor(SetupTwoFactorParams {
            master_key: SecretVec::new(created.secrets.master_key.clone()),
            key_attributes: Some(created.key_attributes.clone()),
        })
        .await
        .unwrap();

    let mut ui = TestUi {
        totp_secret: Some(setup.secret_code),
    };
    let login = AuthFlow::new(&accounts_client(endpoint), &mut ui)
        .login(LoginParams {
            email,
            password: Zeroizing::new(password),
        })
        .await
        .unwrap();
    assert_eq!(login.user_id, created.user_id);
    assert_eq!(login.secrets.master_key, created.secrets.master_key);
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
