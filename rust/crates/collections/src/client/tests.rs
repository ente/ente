use ente_core::{
    Session,
    crypto::{Key, SecretKey},
    http::{ApiConfig, Auth},
};
use mockito::{Matcher, Server};
use serde_json::json;

use super::*;

fn test_session(origin: String) -> Result<Session> {
    Ok(Session::new(
        ApiConfig {
            origin,
            client_package: Some("io.ente.photos".into()),
            client_version: None,
            user_agent: Some("ente-collections-tests".into()),
            auth: Some(Auth::User("token".into())),
        },
        1,
        Key::generate(),
        Key::generate(),
        SecretKey::generate(),
    )?)
}

fn minimal_collection_json(id: i64, owner_id: i64, updation_time: i64) -> serde_json::Value {
    json!({
        "id": id,
        "owner": {"id": owner_id},
        "encryptedKey": "k",
        "keyDecryptionNonce": "n",
        "type": "album",
        "updationTime": updation_time
    })
}

fn minimal_file_json(
    id: i64,
    collection_id: i64,
    owner_id: i64,
    updation_time: i64,
) -> serde_json::Value {
    json!({
        "id": id,
        "collectionID": collection_id,
        "ownerID": owner_id,
        "encryptedKey": "ek",
        "keyDecryptionNonce": "kn",
        "file": {"decryptionHeader": "fh"},
        "metadata": {"encryptedData": "md", "decryptionHeader": "mh"},
        "isDeleted": false,
        "updationTime": updation_time
    })
}

#[tokio::test]
async fn diff_rejects_invalid_and_malformed_rows() -> Result<()> {
    let mut server = Server::new_async().await;
    let session = test_session(server.url())?;

    let mut deleted_bad_owner = minimal_collection_json(13, 0, 200);
    deleted_bad_owner["isDeleted"] = json!(true);
    let mut missing_type = minimal_collection_json(15, 1, 200);
    missing_type
        .as_object_mut()
        .ok_or_else(|| Error::InvalidPage("expected object"))?
        .remove("type");
    let mut missing_owner = minimal_collection_json(16, 1, 200);
    missing_owner
        .as_object_mut()
        .ok_or_else(|| Error::InvalidPage("expected object"))?
        .remove("owner");

    for (item, expect_http) in [
        (deleted_bad_owner, false),
        (minimal_collection_json(14, 1, 99), false),
        (missing_type, true),
        (missing_owner, true),
    ] {
        let mock = server
            .mock("GET", "/collections/v2")
            .match_query(Matcher::UrlEncoded("sinceTime".into(), "100".into()))
            .with_status(200)
            .with_body(json!({"collections": [item]}).to_string())
            .expect(1)
            .create_async()
            .await;
        let result = diff(&session, 100).await;
        assert!(if expect_http {
            matches!(result, Err(Error::Http(_)))
        } else {
            matches!(result, Err(Error::InvalidPage(_)))
        });
        mock.assert_async().await;
    }
    Ok(())
}

#[tokio::test]
async fn files_diff_rejects_invalid_and_malformed_rows() -> Result<()> {
    let mut server = Server::new_async().await;
    let session = test_session(server.url())?;

    let mut deleted_bad_owner = minimal_file_json(5, 42, 0, 20);
    deleted_bad_owner["isDeleted"] = json!(true);
    deleted_bad_owner["metadata"] = json!({"encryptedData": "-", "decryptionHeader": ""});

    let mut missing_file = minimal_file_json(9, 42, 7, 20);
    missing_file
        .as_object_mut()
        .ok_or_else(|| Error::InvalidPage("expected object"))?
        .remove("file");
    let mut missing_collection_id = minimal_file_json(10, 42, 7, 20);
    missing_collection_id
        .as_object_mut()
        .ok_or_else(|| Error::InvalidPage("expected object"))?
        .remove("collectionID");

    for (item, expect_http) in [
        (minimal_file_json(6, 99, 7, 20), false),
        (deleted_bad_owner, false),
        (minimal_file_json(8, 42, 7, 9), false),
        (missing_file, true),
        (missing_collection_id, true),
    ] {
        let mock = server
            .mock("GET", "/collections/v2/diff")
            .match_query(Matcher::AllOf(vec![
                Matcher::UrlEncoded("collectionID".into(), "42".into()),
                Matcher::UrlEncoded("sinceTime".into(), "10".into()),
            ]))
            .with_status(200)
            .with_body(json!({"diff": [item], "hasMore": false}).to_string())
            .expect(1)
            .create_async()
            .await;
        let result = files_diff(&session, 42, 10).await;
        assert!(if expect_http {
            matches!(result, Err(Error::Http(_)))
        } else {
            matches!(result, Err(Error::InvalidPage(_)))
        });
        mock.assert_async().await;
    }
    Ok(())
}

#[tokio::test]
async fn file_pages_rejects_stalled_cursor() -> Result<()> {
    let mut server = Server::new_async().await;
    let session = test_session(server.url())?;

    for stalled_body in [
        json!({"diff": [], "hasMore": true}),
        json!({
            "diff": [minimal_file_json(3, 42, 7, 50)],
            "hasMore": true
        }),
    ] {
        let stalled = server
            .mock("GET", "/collections/v2/diff")
            .match_query(Matcher::AllOf(vec![
                Matcher::UrlEncoded("collectionID".into(), "42".into()),
                Matcher::UrlEncoded("sinceTime".into(), "50".into()),
            ]))
            .with_status(200)
            .with_body(stalled_body.to_string())
            .expect(1)
            .create_async()
            .await;
        let mut stalled_pages = file_pages(&session, 42, 50);
        assert!(matches!(
            stalled_pages.next().await,
            Err(Error::CursorDidNotAdvance(42))
        ));
        stalled.assert_async().await;
    }
    Ok(())
}

#[test]
fn preserves_unknown_types_roles_and_raw_metadata() -> std::result::Result<(), serde_json::Error> {
    let raw_collection = json!({
        "id": 55,
        "owner": {"id": 7, "role": "FUTURE_OWNER_ROLE", "displayName": "Alice"},
        "encryptedKey": "k",
        "type": "future_collection_kind",
        "updationTime": 500,
        "sharees": [{"id": 8, "email": "b@example.org", "role": "AUDITOR"}],
        "magicMetadata": {"data": "d1", "header": "h1", "version": 4, "extraMeta": "x"},
        "pubMagicMetadata": {"data": "d2", "header": "h2", "count": 2},
        "sharedMagicMetadata": {"data": "d3", "header": "h3", "futureFlag": true},
        "unmodeledField": {"nested": [1, 2]}
    });
    let collection: Collection = serde_json::from_value(raw_collection.clone())?;
    assert_eq!(collection.kind, "future_collection_kind");
    assert_eq!(collection.owner.extra["role"], json!("FUTURE_OWNER_ROLE"));
    assert_eq!(collection.extra["sharees"][0]["role"], json!("AUDITOR"));
    let encoded_collection = serde_json::to_value(&collection)?;
    assert_eq!(encoded_collection["type"], raw_collection["type"]);
    assert_eq!(encoded_collection["owner"], raw_collection["owner"]);
    assert_eq!(encoded_collection["sharees"], raw_collection["sharees"]);
    assert_eq!(
        encoded_collection["magicMetadata"],
        raw_collection["magicMetadata"]
    );
    assert_eq!(
        encoded_collection["pubMagicMetadata"],
        raw_collection["pubMagicMetadata"]
    );
    assert_eq!(
        encoded_collection["sharedMagicMetadata"],
        raw_collection["sharedMagicMetadata"]
    );
    assert_eq!(
        encoded_collection["unmodeledField"],
        raw_collection["unmodeledField"]
    );

    let raw_file = json!({
        "id": 88,
        "collectionID": 55,
        "ownerID": 7,
        "encryptedKey": "fk",
        "keyDecryptionNonce": "fn",
        "file": {"objectKey": "obj", "decryptionHeader": "fh", "size": 123},
        "metadata": {"encryptedData": "md", "decryptionHeader": "mh", "extraAttr": "keep"},
        "isDeleted": false,
        "updationTime": 600,
        "magicMetadata": {"data": "fd", "header": "fh2", "version": 2},
        "info": {"fileSize": 123, "futureInfo": "yes"},
        "action": "FUTURE_ACTION"
    });
    let file: File = serde_json::from_value(raw_file.clone())?;
    assert_eq!(file.extra["action"], json!("FUTURE_ACTION"));
    let encoded_file = serde_json::to_value(&file)?;
    assert_eq!(encoded_file["collectionID"], json!(55));
    assert_eq!(
        encoded_file["file"],
        json!({"objectKey": "obj", "decryptionHeader": "fh", "size": 123, "encryptedData": null})
    );
    assert_eq!(encoded_file["metadata"], raw_file["metadata"]);
    assert_eq!(encoded_file["magicMetadata"], raw_file["magicMetadata"]);
    assert_eq!(encoded_file["info"], raw_file["info"]);
    assert_eq!(encoded_file["action"], raw_file["action"]);
    Ok(())
}
