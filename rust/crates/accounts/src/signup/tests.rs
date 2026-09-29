use super::*;
use crate::{
    AccountsClientConfig,
    auth::SrpAttributes,
    test_support::{SetupSrpPayload, SrpState, make_client, parse_request_body, srp_proofs},
};
use mockito::{Matcher, Server};
use serde::Deserialize;
use serde_json::json;
use std::sync::{Arc, Mutex};

fn verified() -> Signup {
    Signup::verified(
        "new@example.org".into(),
        serde_json::from_value(json!({"id": 7, "token": b64::encode_url_safe(b"session-token")}))
            .unwrap(),
    )
    .unwrap()
}

fn restore(signup: &Signup) -> Signup {
    let bytes = serde_json::to_vec(signup).unwrap();
    assert!(!String::from_utf8_lossy(&bytes).contains("signup-password"));
    serde_json::from_slice(&bytes).unwrap()
}

#[tokio::test]
async fn checkpoints_preserve_keys_and_reconcile_an_accepted_upload() {
    let mut server = Server::new_async().await;
    let client =
        AccountsClient::new(AccountsClientConfig::new("io.ente.locker").with_origin(server.url()))
            .unwrap();
    let empty = server
        .mock("GET", "/users/session-validity/v2")
        .match_header(
            "x-auth-token",
            b64::encode_url_safe(b"session-token").as_str(),
        )
        .with_body(json!({"hasSetKeys": false}).to_string())
        .create_async()
        .await;
    let verified = restore(&verified());
    assert!(verified.recovery_key().unwrap().is_none());
    assert!(matches!(
        verified.finish(&client).await,
        Err(Error::InvalidInput(_))
    ));
    let prepared = verified
        .prepare_with_strength(
            &client,
            "signup-password",
            KeyDerivationStrength::Interactive,
        )
        .await
        .unwrap();
    let recovered = restore(&prepared);
    assert_eq!(
        prepared.recovery_key().unwrap(),
        recovered.recovery_key().unwrap()
    );
    let retried = recovered
        .prepare(&client, "different-password")
        .await
        .unwrap();
    assert!(serde_json::to_vec(&retried).unwrap() == serde_json::to_vec(&recovered).unwrap());
    let keys = recovered.keys.as_ref().unwrap();
    empty.assert_async().await;
    empty.remove_async().await;
    let accepted = server
        .mock("GET", "/users/session-validity/v2")
        .with_body(json!({"hasSetKeys": true, "keyAttributes": keys.attributes}).to_string())
        .create_async()
        .await;
    let setup = server
        .mock("POST", "/users/srp/setup")
        .with_status(400)
        .create_async()
        .await;
    let remote = server
        .mock("GET", "/users/srp/attributes?email=new%40example.org")
        .with_body(
            json!({"attributes": {
                "srpUserID": keys.srp_user_id, "srpSalt": b64::encode(&keys.srp_salt),
                "kekSalt": keys.attributes.kek_salt, "memLimit": keys.attributes.mem_limit,
                "opsLimit": keys.attributes.ops_limit,
            }})
            .to_string(),
        )
        .create_async()
        .await;
    let account = restore(&recovered).finish(&client).await.unwrap();
    assert_eq!(account.secrets.master_key, keys.master_key);
    assert_eq!(account.secrets.secret_key, keys.secret_key);
    assert_eq!(account.recovery_key, recovered.recovery_key().unwrap());
    accepted.assert_async().await;
    accepted.remove_async().await;
    let mut different = keys.attributes.clone();
    different.public_key = b64::encode(&[9; 32]);
    let conflict = server
        .mock("GET", "/users/session-validity/v2")
        .with_body(json!({"hasSetKeys": true, "keyAttributes": different}).to_string())
        .expect(2)
        .create_async()
        .await;
    assert!(matches!(
        recovered.finish(&client).await,
        Err(Error::AccountAlreadyExists)
    ));
    assert!(matches!(
        verified.prepare(&client, "signup-password").await,
        Err(Error::AccountAlreadyExists)
    ));
    setup.assert_async().await;
    remote.assert_async().await;
    conflict.assert_async().await;
}

#[cfg(feature = "museum")]
#[test]
fn checkpoints_resume_signup_against_museum() -> ente_test_support::TestResult {
    use ente_test_support::{HARDCODED_OTT, HARDCODED_OTT_EMAIL_SUFFIX, Museum};

    Museum::run_async(|endpoint| async move {
        let client =
            AccountsClient::new(AccountsClientConfig::new("io.ente.photos").with_origin(endpoint))?;
        let email = format!(
            "signup-resume-{}{HARDCODED_OTT_EMAIL_SUFFIX}",
            Uuid::new_v4()
        );
        client.send_otp(&email, "signup").await?;
        let response = client
            .verify_email(&email, HARDCODED_OTT, Some("testAccount"))
            .await?;
        let verified = Signup::verified(email.clone(), response)?;
        let prepared = restore(
            &restore(&verified)
                .prepare(&client, "signup-password")
                .await?,
        );
        let keys = prepared.keys.as_ref().unwrap();
        client
            .set_user_key_attributes(keys.attributes.clone())
            .await?;
        let account = restore(&prepared).finish(&client).await?;
        let resumed = restore(&prepared).finish(&client).await?;
        assert_eq!(account.secrets.master_key, keys.master_key);
        assert_eq!(resumed.secrets.master_key, account.secrets.master_key);
        assert_eq!(resumed.recovery_key, account.recovery_key);
        assert!(matches!(
            verified.prepare(&client, "different-password").await,
            Err(Error::AccountAlreadyExists)
        ));
        let attributes = client.get_srp_attributes(&email).await?;
        let (response, _) = client
            .login_with_srp("signup-password", &attributes)
            .await?;
        assert_eq!(response.id, resumed.user_id);
        Ok(())
    })
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SetUserAttributesPayload {
    key_attributes: KeyAttributes,
}

#[derive(Debug, Deserialize)]
struct CompleteSrpSetupPayload {
    #[serde(rename = "setupID")]
    setup_id: String,
    #[serde(rename = "srpM1")]
    srp_m1: String,
}

#[tokio::test]
async fn create_account_uploads_keys_and_completes_srp_setup() {
    let email = "fresh-user@example.org";
    let encoded_email = urlencoding::encode(email).into_owned();
    let signup_token_bytes = b"signup-session-token";
    let signup_token = b64::encode_url_safe(signup_token_bytes);
    let signup_state = Arc::new(Mutex::new(SrpState::default()));

    let mut server = Server::new_async().await;

    let send_otp = server
        .mock("POST", "/users/ott")
        .match_body(Matcher::PartialJson(serde_json::json!({
            "email": email,
            "purpose": "signup",
        })))
        .with_status(200)
        .create_async()
        .await;

    let verify_email = server
        .mock("POST", "/users/verify-email")
        .match_body(Matcher::PartialJson(serde_json::json!({
            "email": email,
            "ott": "123456",
            "source": "testAccount",
        })))
        .with_status(200)
        .with_body(
            serde_json::json!({
                "id": 99,
                "token": signup_token,
            })
            .to_string(),
        )
        .create_async()
        .await;

    let session_validity = server
        .mock("GET", "/users/session-validity/v2")
        .match_header("x-auth-token", signup_token.as_str())
        .match_header("x-client-package", "io.ente.photos")
        .with_status(200)
        .with_body(
            serde_json::json!({
                "hasSetKeys": false,
            })
            .to_string(),
        )
        .expect(2)
        .create_async()
        .await;

    let state = Arc::clone(&signup_state);
    let set_attributes = server
        .mock("PUT", "/users/attributes")
        .match_header("x-auth-token", signup_token.as_str())
        .match_header("x-client-package", "io.ente.photos")
        .with_status(200)
        .with_body_from_request(move |request| {
            let payload: SetUserAttributesPayload = parse_request_body(request);
            let key_attributes = payload.key_attributes;
            let mem_limit = u64::from(key_attributes.mem_limit);
            let ops_limit = u64::from(key_attributes.ops_limit);

            assert_eq!(mem_limit * ops_limit, 4_294_967_296);
            assert!(
                key_attributes
                    .master_key_encrypted_with_recovery_key
                    .is_some()
            );
            assert!(
                key_attributes
                    .recovery_key_encrypted_with_master_key
                    .is_some()
            );

            state.lock().unwrap().uploaded_key_attributes = Some(key_attributes);
            Vec::new()
        })
        .create_async()
        .await;

    let state = Arc::clone(&signup_state);
    let setup_srp = server
        .mock("POST", "/users/srp/setup")
        .match_header("x-auth-token", signup_token.as_str())
        .match_header("x-client-package", "io.ente.photos")
        .with_status(200)
        .with_body_from_request(move |request| {
            let payload: SetupSrpPayload = parse_request_body(request);
            let srp_user_id = Uuid::parse_str(&payload.srp_user_id).unwrap();
            let (srp_b, client_proof, server_proof) = srp_proofs(&payload);
            let setup_id = Uuid::new_v4();

            let mut state = state.lock().unwrap();
            let uploaded_key_attributes = state.uploaded_key_attributes.clone().unwrap();
            state.pending_setup_id = Some(setup_id);
            state.remote_srp_attributes = Some(SrpAttributes {
                srp_user_id,
                srp_salt: payload.srp_salt,
                mem_limit: uploaded_key_attributes.mem_limit,
                ops_limit: uploaded_key_attributes.ops_limit,
                kek_salt: uploaded_key_attributes.kek_salt,
                is_email_mfa_enabled: false,
            });
            state.pending_client_proof = Some(client_proof);
            state.pending_server_proof = Some(server_proof);

            serde_json::json!({
                "setupID": setup_id,
                "srpB": b64::encode(&srp_b),
            })
            .to_string()
            .into_bytes()
        })
        .create_async()
        .await;

    let state = Arc::clone(&signup_state);
    let complete_srp = server
        .mock("POST", "/users/srp/complete")
        .match_header("x-auth-token", signup_token.as_str())
        .match_header("x-client-package", "io.ente.photos")
        .with_status(200)
        .with_body_from_request(move |request| {
            let payload: CompleteSrpSetupPayload = parse_request_body(request);
            let setup_id = Uuid::parse_str(&payload.setup_id).unwrap();
            let srp_m1 = b64::decode(&payload.srp_m1).unwrap();

            let mut state = state.lock().unwrap();
            assert_eq!(state.pending_setup_id, Some(setup_id));
            assert_eq!(state.pending_client_proof.take().unwrap(), srp_m1);

            serde_json::json!({
                "setupID": setup_id,
                "srpM2": b64::encode(&state.pending_server_proof.take().unwrap()),
            })
            .to_string()
            .into_bytes()
        })
        .create_async()
        .await;

    let state = Arc::clone(&signup_state);
    let get_srp_attributes = server
        .mock("GET", Matcher::Any)
        .match_request(move |request| {
            request.path() == "/users/srp/attributes"
                && request.path_and_query()
                    == format!("/users/srp/attributes?email={encoded_email}")
        })
        .with_status(200)
        .with_body_from_request(move |_| {
            let state = state.lock().unwrap();
            serde_json::json!({
                "attributes": state.remote_srp_attributes.as_ref().unwrap()
            })
            .to_string()
            .into_bytes()
        })
        .create_async()
        .await;

    let client = make_client(server.url());

    client.send_otp(email, "signup").await.unwrap();
    let verification = client
        .verify_email(email, "123456", Some("testAccount"))
        .await
        .unwrap();
    let created = Signup::verified(email.into(), verification)
        .unwrap()
        .prepare(&client, "CorrectHorseBatteryStaple!")
        .await
        .unwrap()
        .finish(&client)
        .await
        .unwrap();

    assert_eq!(created.user_id, 99);
    assert_eq!(created.secrets.token, signup_token_bytes);
    assert!(created.recovery_key.is_some());

    send_otp.assert_async().await;
    verify_email.assert_async().await;
    session_validity.assert_async().await;
    set_attributes.assert_async().await;
    setup_srp.assert_async().await;
    complete_srp.assert_async().await;
    get_srp_attributes.assert_async().await;
}
