#![cfg(feature = "museum")]

use std::collections::{BTreeSet, HashSet};
use std::io::Write;

use ente_core::{
    Session, b64,
    crypto::{Key, SecretKey, blob, secretbox},
    http::{ApiConfig, Auth},
};
use ente_photos::{ml_consent, people};
use ente_test_support::{Museum, TestResult, account_fixture};
use flate2::{Compression, write::GzEncoder};
use serde::Deserialize;
use serde_json::{Value, json};

#[test]
fn people_and_ml_consent_against_museum() -> TestResult {
    Museum::run(|museum| tokio::runtime::Runtime::new()?.block_on(run(museum)))
}

async fn run(museum: &Museum) -> TestResult {
    let endpoint = museum.endpoint();
    let owner = session(endpoint, "people-owner").await?;

    assert!(!ml_consent::granted(&owner).await?);
    set_flag(&owner, "faceSearchEnabled", "true").await?;
    assert!(ml_consent::granted(&owner).await?);
    set_flag(&owner, "faceSearchEnabled", "false").await?;
    assert!(!ml_consent::granted(&owner).await?);

    let empty = people::diff(&owner, 0).await?;
    assert!(empty.updated.is_empty() && empty.deleted.is_empty());
    assert_eq!(empty.cursor, 0);
    assert!(!empty.has_more);

    let key = Key::generate();
    create_key(&owner, &key).await?;
    let ada = create_person(
        &owner,
        &key,
        &json!({
            "name": "Ada",
            "assigned": [{"id": "c1", "faces": ["101_a", "102_a", "103_a"]}],
            "rejectedFaceIDs": ["103_a"],
            "manuallyAssigned": [104],
        }),
    )
    .await?;
    let gone = create_person(&owner, &key, &json!({"name": "Gone"})).await?;
    owner
        .api
        .delete("/user-entity/entity")
        .query(&[("id", gone.as_str())])
        .send()
        .await?
        .error_for_code()
        .await?;

    let page = people::diff(&owner, 0).await?;
    assert_eq!(page.deleted, [gone]);
    assert_eq!(page.updated.len(), 1);
    let remote = &page.updated[0];
    assert_eq!(remote.id, ada);
    assert!(page.cursor > remote.updated_at);
    let person = people::Person::from_json(&remote.data)?;
    assert_eq!(person.name, "Ada");
    assert!(!person.hidden);
    assert_eq!(person.file_ids(), BTreeSet::from([101, 102, 104]));

    let caught_up = people::diff(&owner, page.cursor).await?;
    assert!(caught_up.updated.is_empty() && caught_up.deleted.is_empty());
    assert_eq!(caught_up.cursor, page.cursor);

    following_the_cursor_keeps_rows_tied_across_a_page_boundary(museum).await
}

async fn following_the_cursor_keeps_rows_tied_across_a_page_boundary(
    museum: &Museum,
) -> TestResult {
    let session = session(museum.endpoint(), "people-tie").await?;
    create_key(&session, &Key::generate()).await?;
    let user_id = session.user_id;
    museum.execute_sql(&format!(
        "INSERT INTO entity_data (id, user_id, type, is_deleted, created_at, updated_at)
         SELECT gen_random_uuid(), {user_id}, 'cgroup', true, stamp, stamp
         FROM generate_series(1, 499) AS stamp;
         INSERT INTO entity_data (id, user_id, type, is_deleted, created_at, updated_at)
         SELECT gen_random_uuid(), {user_id}, 'cgroup', true, 1000, 1000
         FROM generate_series(1, 2);"
    ))?;

    let mut cursor = 0;
    let mut deleted = HashSet::new();
    let mut pages = 0;
    loop {
        let page = people::diff(&session, cursor).await?;
        assert!(page.updated.is_empty());
        deleted.extend(page.deleted);
        pages += 1;
        cursor = page.cursor;
        if !page.has_more {
            break;
        }
    }
    assert_eq!(deleted.len(), 501);
    assert_eq!(pages, 2);
    assert_eq!(cursor, 1000);
    Ok(())
}

async fn session(endpoint: &str, prefix: &str) -> TestResult<Session> {
    let account = account_fixture::create_account(endpoint, prefix).await?;
    Ok(Session::new(
        ApiConfig {
            origin: endpoint.into(),
            client_package: Some("io.ente.photos".into()),
            client_version: None,
            user_agent: Some("ente-photos-people-e2e".into()),
            auth: Some(Auth::User(account.auth_token.clone())),
        },
        account.user_id,
        Key::try_from_slice(&account.master_key)?,
        Key::try_from_slice(&account.recovery_key)?,
        SecretKey::try_from_slice(&account.secret_key)?,
    )?)
}

async fn set_flag(session: &Session, key: &str, value: &str) -> TestResult {
    session
        .api
        .post("/remote-store/update")
        .json(&json!({"key": key, "value": value}))
        .send()
        .await?
        .error_for_code()
        .await?;
    Ok(())
}

async fn create_key(session: &Session, key: &Key) -> TestResult {
    let wrapped = secretbox::encrypt(key.as_bytes(), &session.master_key);
    session
        .api
        .post("/user-entity/key")
        .json(&json!({
            "type": "cgroup",
            "encryptedKey": b64::encode(&wrapped.encrypted_data),
            "header": b64::encode(wrapped.nonce.as_bytes()),
        }))
        .send()
        .await?
        .error_for_code()
        .await?;
    Ok(())
}

async fn create_person(session: &Session, key: &Key, data: &Value) -> TestResult<String> {
    #[derive(Deserialize)]
    struct Created {
        id: String,
    }
    let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
    encoder.write_all(data.to_string().as_bytes())?;
    let encrypted = blob::encrypt(&encoder.finish()?, key)?;
    let created: Created = session
        .api
        .post("/user-entity/entity")
        .json(&json!({
            "type": "cgroup",
            "encryptedData": b64::encode(&encrypted.encrypted_data),
            "header": b64::encode(encrypted.decryption_header.as_bytes()),
        }))
        .send()
        .await?
        .error_for_code()
        .await?
        .json()
        .await?;
    Ok(created.id)
}
