use super::*;
use mockito::{Matcher, Server};
use serde::Deserialize;
use std::sync::{Arc, Mutex};

use crate::test_support::{SetupSrpPayload, SrpState, make_client, parse_request_body, srp_proofs};

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct UpdateSrpPayload {
    setup_id: String,
    srp_m1: String,
    updated_key_attr: UpdatedKeyAttr,
    log_out_other_devices: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ConfigurePasskeyRecoveryPayload {
    secret: String,
    user_secret_cipher: String,
    user_secret_nonce: String,
}

#[tokio::test]
async fn setup_two_factor_encrypts_secret_with_recovery_key() {
    let password = "pw";
    let key_gen =
        auth::generate_keys_with_strength(password, auth::KeyDerivationStrength::Interactive)
            .unwrap();
    let recovery_key = key_gen.private_key_attributes.recovery_key.into_string();
    let master_key = b64::decode(&key_gen.private_key_attributes.key).unwrap();
    let key_attributes = key_gen.key_attributes.clone();

    let mut server = Server::new_async().await;

    let setup = server
        .mock("POST", "/users/two-factor/setup")
        .match_header("x-auth-token", "session-token")
        .match_header("x-client-package", "io.ente.photos")
        .with_status(200)
        .with_body(
            serde_json::json!({
                "secretCode": "JBSWY3DPEHPK3PXP",
                "qrCode": "qr-png-b64"
            })
            .to_string(),
        )
        .create_async()
        .await;

    let enable = server
        .mock("POST", "/users/two-factor/enable")
        .match_header("x-auth-token", "session-token")
        .match_header("x-client-package", "io.ente.photos")
        .match_body(Matcher::Regex("\"encryptedTwoFactorSecret\"".into()))
        .with_status(200)
        .create_async()
        .await;

    let client = make_client(server.url());
    client.set_auth_token(Some("session-token".into()));

    let result = TwoFactorSetup::start(&client, &master_key, &key_attributes)
        .await
        .unwrap();
    result.enable(&client, "123123").await.unwrap();

    assert_eq!(result.secret_code, "JBSWY3DPEHPK3PXP");
    assert_eq!(result.recovery_key, recovery_key);

    setup.assert_async().await;
    enable.assert_async().await;
}

#[tokio::test]
async fn configure_passkey_recovery_accepts_hex_recovery_key() {
    let key_gen =
        auth::generate_keys_with_strength("pw", auth::KeyDerivationStrength::Interactive).unwrap();
    let recovery_key_hex = key_gen.private_key_attributes.recovery_key.into_string();
    let expected_recovery_key = hex::decode(&recovery_key_hex).unwrap();

    let mut server = Server::new_async().await;
    let configure = server
        .mock("POST", "/users/two-factor/passkeys/configure-recovery")
        .match_header("x-auth-token", "session-token")
        .match_header("x-client-package", "io.ente.photos")
        .with_status(200)
        .with_body_from_request(move |request| {
            let payload: ConfigurePasskeyRecoveryPayload = parse_request_body(request);
            let cipher = b64::decode(&payload.user_secret_cipher).unwrap();
            let nonce = b64::decode(&payload.user_secret_nonce).unwrap();
            let decrypted = secretbox::decrypt(
                &cipher,
                &crypto::Nonce::try_from_slice(&nonce).unwrap(),
                &crypto::Key::try_from_slice(&expected_recovery_key).unwrap(),
            )
            .unwrap();
            assert_eq!(payload.secret, "reset-secret");
            assert_eq!(String::from_utf8(decrypted).unwrap(), "reset-secret");
            Vec::new()
        })
        .create_async()
        .await;

    let client = make_client(server.url());
    client.set_auth_token(Some("session-token".into()));

    configure_passkey_recovery(&client, "reset-secret", &recovery_key_hex)
        .await
        .unwrap();

    configure.assert_async().await;
}

#[tokio::test]
async fn change_password_updates_srp_and_keys() {
    let original =
        auth::generate_keys_with_strength("old-password", auth::KeyDerivationStrength::Interactive)
            .unwrap();
    let key_attributes = original.key_attributes.clone();
    let master_key = b64::decode(&original.private_key_attributes.key).unwrap();
    let state = Arc::new(Mutex::new(SrpState::default()));

    let mut server = Server::new_async().await;

    let state_for_setup = Arc::clone(&state);
    let setup_srp = server
        .mock("POST", "/users/srp/setup")
        .match_header("x-auth-token", "session-token")
        .with_status(200)
        .with_body_from_request(move |request| {
            let payload: SetupSrpPayload = parse_request_body(request);
            let (srp_b, client_proof, server_proof) = srp_proofs(&payload);
            let setup_id = Uuid::new_v4();

            let state = &mut *state_for_setup.lock().unwrap();
            state.pending_setup_id = Some(setup_id);
            state.pending_client_proof = Some(client_proof);
            state.pending_server_proof = Some(server_proof);
            state.remote_srp_attributes = Some(SrpAttributes {
                srp_user_id: Uuid::parse_str(&payload.srp_user_id).unwrap(),
                srp_salt: payload.srp_salt.clone(),
                mem_limit: 0,
                ops_limit: 0,
                kek_salt: String::new(),
                is_email_mfa_enabled: false,
            });

            serde_json::json!({
                "setupID": setup_id,
                "srpB": b64::encode(&srp_b),
            })
            .to_string()
            .into_bytes()
        })
        .create_async()
        .await;

    let state_for_update = Arc::clone(&state);
    let update_srp = server
        .mock("POST", "/users/srp/update")
        .match_header("x-auth-token", "session-token")
        .with_status(200)
        .with_body_from_request(move |request| {
            let payload: UpdateSrpPayload = parse_request_body(request);
            let state = &mut *state_for_update.lock().unwrap();
            assert_eq!(
                payload.setup_id,
                state.pending_setup_id.unwrap().to_string()
            );
            assert_eq!(
                b64::decode(&payload.srp_m1).unwrap(),
                state.pending_client_proof.as_ref().unwrap().clone()
            );
            assert!(payload.log_out_other_devices);
            state.remote_srp_attributes = state.remote_srp_attributes.clone().map(|mut attrs| {
                attrs.mem_limit = payload.updated_key_attr.mem_limit;
                attrs.ops_limit = payload.updated_key_attr.ops_limit;
                attrs.kek_salt = payload.updated_key_attr.kek_salt.clone();
                attrs
            });
            serde_json::json!({
                "setupID": payload.setup_id,
                "srpM2": b64::encode(state.pending_server_proof.as_ref().unwrap()),
            })
            .to_string()
            .into_bytes()
        })
        .create_async()
        .await;

    let state_for_attrs = Arc::clone(&state);
    let get_srp_attributes = server
        .mock("GET", "/users/srp/attributes")
        .match_query(Matcher::UrlEncoded(
            "email".into(),
            "user@example.org".into(),
        ))
        .with_status(200)
        .with_body_from_request(move |_| {
            let state = state_for_attrs.lock().unwrap();
            serde_json::json!({
                "attributes": state.remote_srp_attributes
            })
            .to_string()
            .into_bytes()
        })
        .create_async()
        .await;

    let client = make_client(server.url());
    client.set_auth_token(Some("session-token".into()));

    let result = change_password_with_strength(
        &client,
        ChangePasswordParams {
            email: "user@example.org".into(),
            password: Zeroizing::new("new-password".into()),
            master_key: SecretVec::new(master_key),
            key_attributes,
            log_out_other_devices: true,
        },
        KeyDerivationStrength::Interactive,
    )
    .await
    .unwrap();

    assert_eq!(
        result.srp_attributes.kek_salt,
        result.key_attributes.kek_salt
    );

    setup_srp.assert_async().await;
    update_srp.assert_async().await;
    get_srp_attributes.assert_async().await;
}
