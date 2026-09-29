use super::*;
use mockito::{Matcher, Server};
use serde_json::json;
use uuid::Uuid;

use crate::{AccountsClientConfig, auth::KeyDerivationStrength, test_support::make_client};
use ente_core::crypto;

async fn start_email_login(
    server: &mut Server,
    attributes: &KeyAttributes,
    response: serde_json::Value,
) -> (AccountsClient, LoginFlow) {
    let srp = server
        .mock("GET", "/users/srp/attributes")
        .match_query(Matcher::UrlEncoded(
            "email".into(),
            "user@example.org".into(),
        ))
        .with_body(
            json!({"attributes": {
                "srpUserID": Uuid::new_v4(),
                "srpSalt": b64::encode(&[1; 16]),
                "memLimit": attributes.mem_limit,
                "opsLimit": attributes.ops_limit,
                "kekSalt": attributes.kek_salt,
                "isEmailMFAEnabled": true
            }})
            .to_string(),
        )
        .create_async()
        .await;
    let ott = server.mock("POST", "/users/ott").create_async().await;
    server
        .mock("POST", "/users/verify-email")
        .with_body(response.to_string())
        .create_async()
        .await;
    let client =
        AccountsClient::new(AccountsClientConfig::new("io.ente.photos").with_origin(server.url()))
            .unwrap();
    let (flow, step) = LoginFlow::start(&client, "user@example.org".into())
        .await
        .unwrap();
    assert!(matches!(step, LoginStep::EmailCode));
    srp.assert_async().await;
    ott.assert_async().await;
    (client, flow)
}

#[tokio::test]
async fn email_login_retries_password_and_accepts_plain_token_without_recovery_key() {
    let generated =
        auth::generate_keys_with_strength("password", KeyDerivationStrength::Interactive).unwrap();
    let mut attributes = generated.key_attributes;
    attributes.recovery_key_encrypted_with_master_key = None;
    attributes.recovery_key_decryption_nonce = None;
    let token = [255; 32];
    let mut server = Server::new_async().await;
    let (client, mut flow) = start_email_login(
        &mut server,
        &attributes,
        json!({"id": 77, "keyAttributes": attributes, "token": b64::encode_url_safe(&token)}),
    )
    .await;

    assert!(matches!(
        flow.submit_password(&client, "password").await,
        Err(Error::InvalidInput(_))
    ));
    assert!(matches!(
        flow.submit_code(&client, "123456").await.unwrap(),
        LoginStep::Password
    ));
    assert!(matches!(
        flow.submit_password(&client, "wrong").await,
        Err(Error::IncorrectPassword)
    ));
    let LoginStep::Complete(account) = flow.submit_password(&client, "password").await.unwrap()
    else {
        panic!("login did not complete");
    };
    assert_eq!(account.user_id, 77);
    assert_eq!(account.secrets.token, token);
    assert_eq!(
        account.secrets.master_key,
        b64::decode(&generated.private_key_attributes.key).unwrap()
    );
    assert!(account.recovery_key.is_none());
    assert!(matches!(
        flow.submit_password(&client, "password").await,
        Err(Error::InvalidInput(_))
    ));
}

#[tokio::test]
async fn passkey_login_waits_for_verification_before_requesting_password() {
    let generated =
        auth::generate_keys_with_strength("password", KeyDerivationStrength::Interactive).unwrap();
    let attributes = generated.key_attributes;
    let mut server = Server::new_async().await;
    let (client, mut flow) = start_email_login(
        &mut server,
        &attributes,
        json!({"id": 77, "passkeySessionID": "passkey-1", "accountsUrl": "https://accounts.ente.io"}),
    )
    .await;
    assert!(matches!(
        flow.submit_code(&client, "123456").await.unwrap(),
        LoginStep::SecondFactor {
            totp: false,
            passkey: true
        }
    ));
    assert_eq!(
        flow.passkey_url(&client, "ente-cli://passkey").unwrap(),
        "https://accounts.ente.io/passkeys/verify?clientPackage=io.ente.photos&passkeySessionID=passkey-1&redirect=ente-cli%3A%2F%2Fpasskey"
    );
    let pending = server
        .mock("GET", "/users/two-factor/passkeys/get-token")
        .match_query(Matcher::UrlEncoded("sessionID".into(), "passkey-1".into()))
        .with_status(400)
        .create_async()
        .await;
    assert!(flow.poll_passkey(&client).await.unwrap().is_none());
    pending.assert_async().await;
    pending.remove_async().await;

    let verified = server
        .mock("GET", "/users/two-factor/passkeys/get-token")
        .match_query(Matcher::UrlEncoded("sessionID".into(), "passkey-1".into()))
        .with_body(
            json!({"id": 77, "keyAttributes": attributes, "token": b64::encode(&[255; 32])})
                .to_string(),
        )
        .create_async()
        .await;
    assert!(matches!(
        flow.poll_passkey(&client).await.unwrap(),
        Some(LoginStep::Password)
    ));
    let LoginStep::Complete(account) = flow.submit_password(&client, "password").await.unwrap()
    else {
        panic!("login did not complete");
    };
    assert_eq!(account.secrets.token, [255; 32]);
    assert_eq!(
        account.recovery_key.as_deref(),
        Some(&*generated.private_key_attributes.recovery_key)
    );
    verified.assert_async().await;
}

#[tokio::test]
async fn login_retries_email_and_totp() {
    let password = "hunter2";
    let generated =
        auth::generate_keys_with_strength(password, KeyDerivationStrength::Interactive).unwrap();
    let key_attributes = generated.key_attributes;
    let public_key = b64::decode(&key_attributes.public_key).unwrap();
    let encrypted_token = b64::encode(
        &crypto::sealed::seal(
            b"plain-auth-token",
            &crypto::PublicKey::try_from_slice(&public_key).unwrap(),
        )
        .unwrap(),
    );
    let recovery_key = generated.private_key_attributes.recovery_key.into_string();

    let mut server = Server::new_async().await;

    let srp_attrs = server
        .mock("GET", Matcher::Any)
        .match_request(|request| {
            request.path() == "/users/srp/attributes"
                && request.path_and_query() == "/users/srp/attributes?email=user%40example.org"
        })
        .with_status(200)
        .with_body(
            serde_json::json!({
                "attributes": {
                    "srpUserID": Uuid::new_v4(),
                    "srpSalt": b64::encode(&[1u8; 16]),
                    "memLimit": key_attributes.mem_limit,
                    "opsLimit": key_attributes.ops_limit,
                    "kekSalt": key_attributes.kek_salt,
                    "isEmailMFAEnabled": true
                }
            })
            .to_string(),
        )
        .create_async()
        .await;

    let ott = server
        .mock("POST", "/users/ott")
        .with_status(200)
        .expect(2)
        .create_async()
        .await;

    let expired_email = server
        .mock("POST", "/users/verify-email")
        .match_body(Matcher::PartialJson(serde_json::json!({"ott": "expired"})))
        .with_status(410)
        .create_async()
        .await;
    let incorrect_email = server
        .mock("POST", "/users/verify-email")
        .match_body(Matcher::PartialJson(serde_json::json!({"ott": "wrong"})))
        .with_status(400)
        .create_async()
        .await;
    let verify_email = server
        .mock("POST", "/users/verify-email")
        .match_body(Matcher::PartialJson(serde_json::json!({"ott": "123456"})))
        .with_status(200)
        .with_body(
            serde_json::json!({
                "id": 77,
                "twoFactorSessionID": "session-1",
                "passkeySessionID": "passkey-1",
                "accountsUrl": "https://accounts.ente.io",
            })
            .to_string(),
        )
        .create_async()
        .await;

    let incorrect_totp = server
        .mock("POST", "/users/two-factor/verify")
        .match_body(Matcher::PartialJson(serde_json::json!({"code": "wrong"})))
        .with_status(400)
        .create_async()
        .await;
    let verify_totp = server
        .mock("POST", "/users/two-factor/verify")
        .match_body(Matcher::PartialJson(serde_json::json!({"code": "654321"})))
        .with_status(200)
        .with_body(
            serde_json::json!({
                "id": 77,
                "keyAttributes": key_attributes,
                "encryptedToken": encrypted_token,
            })
            .to_string(),
        )
        .create_async()
        .await;

    let client = make_client(server.url());

    let (mut flow, step) = LoginFlow::start(&client, "user@example.org".into())
        .await
        .unwrap();
    assert!(matches!(step, LoginStep::EmailCode));
    assert!(matches!(
        flow.submit_code(&client, "expired").await,
        Err(Error::EmailVerificationCodeExpired)
    ));
    flow.resend_code(&client).await.unwrap();
    assert!(matches!(
        flow.submit_code(&client, "wrong").await,
        Err(Error::IncorrectEmailVerificationCode)
    ));
    assert!(matches!(
        flow.submit_code(&client, "123456").await.unwrap(),
        LoginStep::SecondFactor {
            totp: true,
            passkey: true
        }
    ));
    assert!(matches!(
        flow.submit_code(&client, "wrong").await,
        Err(Error::IncorrectTotp)
    ));
    assert!(matches!(
        flow.submit_code(&client, "654321").await.unwrap(),
        LoginStep::Password
    ));
    let LoginStep::Complete(result) = flow.submit_password(&client, password).await.unwrap() else {
        panic!("login did not complete");
    };

    assert_eq!(result.user_id, 77);
    assert_eq!(result.secrets.token, b"plain-auth-token");
    assert_eq!(result.recovery_key.as_deref(), Some(recovery_key.as_str()));

    srp_attrs.assert_async().await;
    ott.assert_async().await;
    expired_email.assert_async().await;
    incorrect_email.assert_async().await;
    incorrect_totp.assert_async().await;
    verify_email.assert_async().await;
    verify_totp.assert_async().await;
}

#[tokio::test]
async fn totp_errors_are_preserved() {
    let attributes =
        auth::generate_keys_with_strength("password", KeyDerivationStrength::Interactive)
            .unwrap()
            .key_attributes;
    for status in [404, 429] {
        let mut server = Server::new_async().await;
        let (client, mut flow) = start_email_login(
            &mut server,
            &attributes,
            json!({"id": 77, "twoFactorSessionID": "session-1"}),
        )
        .await;
        assert!(matches!(
            flow.submit_code(&client, "123456").await.unwrap(),
            LoginStep::SecondFactor { totp: true, .. }
        ));
        let verify = server
            .mock("POST", "/users/two-factor/verify")
            .with_status(status)
            .create_async()
            .await;
        let error = flow.submit_code(&client, "654321").await.err().unwrap();
        assert!(matches!(
            (status, error),
            (404, Error::SecondFactorSessionExpired) | (429, Error::TotpRateLimited)
        ));
        verify.assert_async().await;
    }
}

#[tokio::test]
async fn passkey_expiry_is_preserved() {
    let attributes =
        auth::generate_keys_with_strength("password", KeyDerivationStrength::Interactive)
            .unwrap()
            .key_attributes;
    let mut server = Server::new_async().await;
    let (client, mut flow) = start_email_login(
        &mut server,
        &attributes,
        json!({"id": 77, "passkeySessionID": "passkey-1", "accountsUrl": "https://accounts.ente.io"}),
    )
    .await;
    assert!(matches!(
        flow.submit_code(&client, "123456").await.unwrap(),
        LoginStep::SecondFactor { passkey: true, .. }
    ));
    let status = server
        .mock("GET", "/users/two-factor/passkeys/get-token")
        .match_query(Matcher::UrlEncoded("sessionID".into(), "passkey-1".into()))
        .with_status(404)
        .create_async()
        .await;
    assert!(matches!(
        flow.poll_passkey(&client).await,
        Err(Error::SecondFactorSessionExpired)
    ));
    status.assert_async().await;
}
