#![cfg(feature = "museum")]

use ente_collections::client;
use ente_core::{
    b64,
    crypto::{Key, sealed, secretbox},
};
use ente_test_support::{Museum, TestResult, account_fixture, photos_fixture};
use serde::Deserialize;
use serde_json::{Value, json};

const PAYLOAD: &[u8] = b"Museum collections fixture bytes";

#[test]
fn collections_and_files_diff_against_museum() -> TestResult {
    Museum::run(|museum| {
        tokio::runtime::Runtime::new()?.block_on(async move {
            collections_diff_and_files_diff(museum).await?;
            files_diff_equal_timestamp_boundaries(museum).await
        })
    })
}

async fn collections_diff_and_files_diff(museum: &Museum) -> TestResult {
    let endpoint = museum.endpoint();
    let owner = account_fixture::create_account(endpoint, "collections-owner").await?;
    let sharee = account_fixture::create_account(endpoint, "collections-sharee").await?;
    let owner_session = owner.session(endpoint, "ente-collections-e2e")?;
    let sharee_session = sharee.session(endpoint, "ente-collections-e2e")?;

    let (album_id, album_key) = photos_fixture::create_album(&owner_session, "Family 2026").await?;

    let legacy_key = Key::generate();
    let wrapped_legacy = secretbox::encrypt(legacy_key.as_bytes(), &owner_session.master_key);
    #[derive(Deserialize)]
    struct Created {
        collection: client::Collection,
    }
    let legacy: Created = owner_session
        .api
        .post("/collections")
        .json(&json!({
            "encryptedKey": b64::encode(&wrapped_legacy.encrypted_data),
            "keyDecryptionNonce": b64::encode(wrapped_legacy.nonce.as_bytes()),
            "name": "Legacy Plaintext",
            "type": "album",
            "attributes": {"version": 1}
        }))
        .send()
        .await?
        .error_for_code()
        .await?
        .json()
        .await?;
    museum.execute_sql(&format!(
        "UPDATE collections SET name = 'Legacy Plaintext', encrypted_name = NULL, name_decryption_nonce = NULL WHERE collection_id = {}",
        legacy.collection.id
    ))?;

    let sealed_key = sealed::seal(
        album_key.as_bytes(),
        &sharee_session.secret_key.public_key(),
    )?;
    owner_session
        .api
        .post("/collections/share")
        .json(&json!({
            "collectionID": album_id,
            "email": sharee.email,
            "encryptedKey": b64::encode(&sealed_key),
            "role": "COLLABORATOR"
        }))
        .send()
        .await?
        .error_for_code()
        .await?;

    let owner_page = client::diff(&owner_session, 0).await?;
    let owner_cursor = owner_page.cursor;
    let fetched_album = owner_page
        .collections
        .iter()
        .find(|c| c.id == album_id)
        .ok_or("missing owned encrypted collection")?;
    assert!(!fetched_album.is_deleted());
    assert_eq!(fetched_album.open_key(&owner_session)?, album_key);
    assert_eq!(fetched_album.open_name_bytes(&album_key)?, b"Family 2026");

    let fetched_legacy = owner_page
        .collections
        .iter()
        .find(|c| c.id == legacy.collection.id)
        .ok_or("missing legacy plaintext collection")?;
    assert!(
        fetched_legacy
            .encrypted_name
            .as_deref()
            .unwrap_or_default()
            .is_empty()
    );
    assert!(
        fetched_legacy
            .name_decryption_nonce
            .as_deref()
            .unwrap_or_default()
            .is_empty()
    );
    let reopened_legacy_key = fetched_legacy.open_key(&owner_session)?;
    assert_eq!(
        fetched_legacy.open_name_bytes(&reopened_legacy_key)?,
        b"Legacy Plaintext"
    );

    let sharee_page = client::diff(&sharee_session, 0).await?;
    let sharee_cursor = sharee_page.cursor;
    let shared_view = sharee_page
        .collections
        .iter()
        .find(|c| c.id == album_id)
        .ok_or("missing shared collection")?;
    assert!(!shared_view.is_deleted());
    assert_eq!(shared_view.owner.id, owner.user_id);
    let sharee_key = shared_view.open_key(&sharee_session)?;
    assert_eq!(sharee_key, album_key);
    assert_eq!(shared_view.open_name_bytes(&sharee_key)?, b"Family 2026");

    let (file_id, _) = photos_fixture::upload_file(
        &owner_session,
        album_id,
        &album_key,
        PAYLOAD,
        "photo.jpg",
        Some(&json!({"caption": "museum-caption"})),
    )
    .await?;

    let mut owner_files = client::file_pages(&owner_session, album_id, 0);
    let owner_file_page = owner_files
        .next()
        .await?
        .ok_or("expected owner files page")?;
    assert!(!owner_file_page.has_more);
    assert!(owner_files.next().await?.is_none());
    let owner_file = owner_file_page
        .files
        .iter()
        .find(|f| f.id == file_id)
        .ok_or("missing uploaded file in owner files_diff")?;
    assert!(!owner_file.is_deleted());
    assert_eq!(owner_file.collection_id, album_id);
    let owner_file_key = owner_file.open_key(&album_key)?;
    let public: Value = serde_json::from_slice(
        &owner_file
            .pub_magic_metadata
            .as_ref()
            .ok_or("missing pubMagicMetadata")?
            .decrypt(&owner_file_key)?,
    )?;
    assert_eq!(public["caption"], json!("museum-caption"));

    let mut sharee_files = client::file_pages(&sharee_session, album_id, 0);
    let sharee_file_page = sharee_files
        .next()
        .await?
        .ok_or("expected sharee files page")?;
    assert!(!sharee_file_page.has_more);
    let sharee_file = sharee_file_page
        .files
        .iter()
        .find(|f| f.id == file_id)
        .ok_or("missing uploaded file in sharee files_diff")?;
    assert_eq!(sharee_file.open_key(&sharee_key)?, owner_file_key);

    owner_session
        .api
        .post("/files/trash")
        .json(&json!({"items": [{"fileID": file_id, "collectionID": album_id}]}))
        .send()
        .await?
        .error_for_code()
        .await?;
    let mut removed_pages = client::file_pages(&owner_session, album_id, owner_file_page.cursor);
    let removed_page = removed_pages
        .next()
        .await?
        .ok_or("expected file deletion tombstone page")?;
    assert!(!removed_page.has_more);
    assert!(removed_pages.next().await?.is_none());
    let tombstone_file = removed_page
        .files
        .iter()
        .find(|f| f.id == file_id)
        .ok_or("missing removed file tombstone")?;
    assert!(tombstone_file.is_deleted());
    assert_eq!(tombstone_file.collection_id, album_id);
    assert!(removed_page.cursor > owner_file_page.cursor);

    owner_session
        .api
        .post("/collections/unshare")
        .json(&json!({"collectionID": album_id, "email": sharee.email}))
        .send()
        .await?
        .error_for_code()
        .await?;
    let sharee_unshared = client::diff(&sharee_session, sharee_cursor).await?;
    let unshared_tombstone = sharee_unshared
        .collections
        .iter()
        .find(|c| c.id == album_id)
        .ok_or("missing deleted share tombstone")?;
    assert!(unshared_tombstone.is_deleted());
    assert!(sharee_unshared.cursor > sharee_cursor);

    owner_session
        .api
        .delete(&format!(
            "/collections/v3/{album_id}?collectionID={album_id}&keepFiles=true"
        ))
        .send()
        .await?
        .error_for_code()
        .await?;
    let owner_deleted = client::diff(&owner_session, owner_cursor).await?;
    let deleted_collection = owner_deleted
        .collections
        .iter()
        .find(|c| c.id == album_id)
        .ok_or("missing deleted collection tombstone")?;
    assert!(deleted_collection.is_deleted());
    assert!(owner_deleted.cursor > owner_cursor);
    Ok(())
}

async fn files_diff_equal_timestamp_boundaries(museum: &Museum) -> TestResult {
    let endpoint = museum.endpoint();
    let owner = account_fixture::create_account(endpoint, "collections-tie").await?;
    let session = owner.session(endpoint, "ente-collections-e2e")?;
    let (album_id, album_key) = photos_fixture::create_album(&session, "Boundary").await?;
    let (template_id, _) =
        photos_fixture::upload_file(&session, album_id, &album_key, PAYLOAD, "seed.jpg", None)
            .await?;

    museum.execute_sql(&format!(
        "UPDATE collection_files SET updation_time = 100 WHERE collection_id = {album_id} AND file_id = {template_id}"
    ))?;
    seed_file_copies(
        museum,
        album_id,
        template_id,
        owner.user_id,
        &[(200, 1000), (300, 1502)],
    )?;

    let mut split_pages = client::file_pages(&session, album_id, 100);
    let p1 = split_pages.next().await?.ok_or("expected split page 1")?;
    assert_eq!(p1.files.len(), 1000);
    assert_eq!(p1.cursor, 200);
    assert!(p1.has_more);
    assert!(p1.files.iter().all(|f| f.updation_time == 200));

    let p2 = split_pages.next().await?.ok_or("expected split page 2")?;
    assert_eq!(p2.files.len(), 1502);
    assert_eq!(p2.cursor, 300);
    assert!(!p2.has_more);
    assert!(p2.files.iter().all(|f| f.updation_time == 300));
    assert!(split_pages.next().await?.is_none());

    seed_file_copies(museum, album_id, template_id, owner.user_id, &[(400, 2501)])?;

    let mut oversize_pages = client::file_pages(&session, album_id, 300);
    let o1 = oversize_pages
        .next()
        .await?
        .ok_or("expected oversize page 1")?;
    assert_eq!(o1.files.len(), 2501);
    assert_eq!(o1.cursor, 400);
    assert!(o1.has_more);
    assert!(o1.files.iter().all(|f| f.updation_time == 400));

    let o2 = oversize_pages
        .next()
        .await?
        .ok_or("expected oversize terminal page")?;
    assert!(o2.files.is_empty());
    assert_eq!(o2.cursor, 400);
    assert!(!o2.has_more);
    assert!(oversize_pages.next().await?.is_none());
    Ok(())
}

fn seed_file_copies(
    museum: &Museum,
    album_id: i64,
    template_id: i64,
    owner_id: i64,
    batches: &[(i64, usize)],
) -> TestResult {
    let union = batches
        .iter()
        .map(|(ts, count)| format!("SELECT {ts}::bigint AS ts FROM generate_series(1, {count})"))
        .collect::<Vec<_>>()
        .join(" UNION ALL ");
    museum.execute_sql(&format!(
        "WITH tpl AS (
             SELECT f.owner_id, f.file_decryption_header, f.thumbnail_decryption_header,
                    f.metadata_decryption_header, f.encrypted_metadata, f.app,
                    cf.encrypted_key, cf.key_decryption_nonce
             FROM files f
             JOIN collection_files cf ON cf.file_id = f.file_id
             WHERE cf.collection_id = {album_id} AND cf.file_id = {template_id}
         ), ins AS (
             INSERT INTO files (
                 owner_id, file_decryption_header, thumbnail_decryption_header,
                 metadata_decryption_header, encrypted_metadata, updation_time, app
             )
             SELECT tpl.owner_id, tpl.file_decryption_header, tpl.thumbnail_decryption_header,
                    tpl.metadata_decryption_header, tpl.encrypted_metadata, batch.ts, tpl.app
             FROM tpl
             CROSS JOIN ({union}) batch
             RETURNING file_id, owner_id, updation_time
         )
         INSERT INTO collection_files (
             file_id, collection_id, c_owner_id, f_owner_id,
             encrypted_key, key_decryption_nonce, is_deleted, updation_time, created_at
         )
         SELECT ins.file_id, {album_id}, {owner_id}, ins.owner_id,
                tpl.encrypted_key, tpl.key_decryption_nonce, false, ins.updation_time, ins.updation_time
         FROM ins CROSS JOIN tpl;"
    ))
}
