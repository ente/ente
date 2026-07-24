use ente_core::b64;
use ente_core::crypto::{Key, Nonce, secretbox};
use ente_core::http;
use ente_space::{AccountSpaceCtx, OpenAccountSpaceCtxInput, SpaceError};
use serde::Deserialize;

use super::{CLIENT_PACKAGE, USER_AGENT, auth::TestAccount};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SpaceBrowserSessionResponse {
    session_token: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SpaceEntityKeyResponse {
    encrypted_key: String,
    header: String,
}

pub async fn open_ctx(endpoint: &str, account: &TestAccount) -> AccountSpaceCtx {
    let space_root_key = ensure_space_root_key(endpoint, account).await;
    let session = reqwest::Client::new()
        .post(format!("{endpoint}/account/space/sessions"))
        .header("X-Auth-Token", &account.auth_token)
        .header("X-Client-Package", CLIENT_PACKAGE)
        .json(&serde_json::json!({ "sessionWrapKey": b64::encode(Key::generate().as_bytes()) }))
        .send()
        .await
        .expect("space session create request failed");
    assert!(
        session.status().is_success(),
        "space session create failed with HTTP {}",
        session.status()
    );
    let session = session
        .json::<SpaceBrowserSessionResponse>()
        .await
        .expect("space session create response parse failed");

    AccountSpaceCtx::open(OpenAccountSpaceCtxInput {
        base_url: endpoint.to_string(),
        space_session_token: Some(session.session_token),
        space_root_key,
        user_agent: Some(USER_AGENT.to_string()),
        client_package: Some(CLIENT_PACKAGE.to_string()),
        client_version: Some(USER_AGENT.to_string()),
    })
    .expect("space context should open")
}

async fn ensure_space_root_key(endpoint: &str, account: &TestAccount) -> Vec<u8> {
    let candidate = Key::generate().as_bytes().to_vec();
    let master_key = Key::try_from_slice(&account.master_key).expect("valid account master key");
    let encrypted = secretbox::encrypt_combined(&candidate, &master_key);
    let (header, encrypted_key) = encrypted.split_at(Nonce::BYTES);

    let response = reqwest::Client::new()
        .post(format!("{endpoint}/user-entity/key/ensure"))
        .header("X-Auth-Token", &account.auth_token)
        .header("X-Client-Package", CLIENT_PACKAGE)
        .json(&serde_json::json!({
            "type": "space",
            "encryptedKey": b64::encode(encrypted_key),
            "header": b64::encode(header),
        }))
        .send()
        .await
        .expect("space entity key ensure request failed");
    assert!(
        response.status().is_success(),
        "space entity key ensure failed with HTTP {}",
        response.status()
    );
    let ensured = response
        .json::<SpaceEntityKeyResponse>()
        .await
        .expect("space entity key ensure response parse failed");

    let mut combined = b64::decode(&ensured.header).expect("valid space entity key header");
    combined.extend_from_slice(
        &b64::decode(&ensured.encrypted_key).expect("valid space entity key body"),
    );
    secretbox::decrypt_combined(&combined, &master_key).expect("space root key should decrypt")
}

pub fn profile_payload(display_name: &str, bio: &str) -> Vec<u8> {
    format!(r#"{{"displayName":"{display_name}","bio":"{bio}"}}"#).into_bytes()
}

pub fn assert_http_status<T>(result: Result<T, SpaceError>, expected_status: u16) {
    match result {
        Err(SpaceError::Http(http::Error::Http { status, .. })) if status == expected_status => {}
        Err(error) => panic!("expected HTTP {expected_status}, got {error:?}"),
        Ok(_) => panic!("expected HTTP {expected_status}, got success"),
    }
}

pub fn assert_invalid_input_contains<T>(result: Result<T, SpaceError>, expected: &str) {
    match result {
        Err(SpaceError::InvalidInput(message)) if message.contains(expected) => {}
        Err(error) => panic!("expected invalid input containing {expected:?}, got {error:?}"),
        Ok(_) => panic!("expected invalid input containing {expected:?}, got success"),
    }
}
