#![cfg(feature = "museum")]

use std::collections::HashMap;

use ente_collections::CollectionFileRef;
use ente_core::{
    Session, b64,
    crypto::{Key, blob, sealed, secretbox},
};
use ente_locker::sync::{
    CollectionChange, FileChange, TrashChange, collect_collection_keys, collections_diff,
    file_pages, trash_pages,
};
use ente_test_support::{Museum, TestResult, account_fixture, photos_fixture};
use serde::Deserialize;
use serde_json::{Value, json};

const PAYLOAD: &[u8] = b"Museum locker encrypted binary fixture";

#[derive(Deserialize)]
struct Uploaded {
    id: i64,
}

async fn upload_info_item(
    session: &Session,
    collection_id: i64,
    collection_key: &Key,
    title: &str,
    info_type: &str,
    info_data: Value,
    extra_meta: Option<(&str, Value)>,
) -> TestResult<(i64, Key)> {
    let key = Key::generate();
    let wrapped = secretbox::encrypt(key.as_bytes(), collection_key);
    let mut base = json!({
        "title": title,
        "fileType": 4,
        "creationTime": 1_700_000_000_123_i64,
        "modificationTime": 1_700_000_001_456_i64,
    });
    if let Some((extra_key, extra_val)) = extra_meta {
        base[extra_key] = extra_val;
    }
    let metadata = blob::encrypt_json(&base, &key)?;
    let public = blob::encrypt_json(
        &json!({
            "info": {"type": info_type, "data": info_data},
            "noThumb": true,
            "futurePubField": "keep"
        }),
        &key,
    )?;
    let uploaded: Uploaded = session
        .api
        .post("/files/meta")
        .json(&json!({
            "collectionID": collection_id,
            "encryptedKey": b64::encode(&wrapped.encrypted_data),
            "keyDecryptionNonce": b64::encode(wrapped.nonce.as_bytes()),
            "metadata": {
                "encryptedData": b64::encode(&metadata.encrypted_data),
                "decryptionHeader": b64::encode(metadata.decryption_header.as_bytes()),
            },
            "pubMagicMetadata": {
                "version": 1,
                "count": 3,
                "data": b64::encode(&public.encrypted_data),
                "header": b64::encode(public.decryption_header.as_bytes()),
            }
        }))
        .send()
        .await?
        .error_for_code()
        .await?
        .json()
        .await?;
    Ok((uploaded.id, key))
}

#[test]
fn locker_collections_files_and_trash_against_museum() -> TestResult {
    Museum::run(|museum| {
        tokio::runtime::Runtime::new()?.block_on(async move {
            let endpoint = museum.endpoint();
            let owner =
                account_fixture::create_account_for_app(endpoint, "locker-owner", "io.ente.locker")
                    .await?;
            let sharee = account_fixture::create_account_for_app(
                endpoint,
                "locker-sharee",
                "io.ente.locker",
            )
            .await?;
            let owner_session = owner.session_for_app(endpoint, "io.ente.locker", "ente-locker-e2e")?;
            let sharee_session =
                sharee.session_for_app(endpoint, "io.ente.locker", "ente-locker-e2e")?;

            let (vault_a, key_a) = photos_fixture::create_album(&owner_session, "Vault A").await?;
            let (vault_b, key_b) = photos_fixture::create_album(&owner_session, "Vault B").await?;
            let (to_delete, key_del) =
                photos_fixture::create_album(&owner_session, "Delete Me").await?;

            let sealed_key =
                sealed::seal(key_a.as_bytes(), &sharee_session.secret_key.public_key())?;
            owner_session
                .api
                .post("/collections/share")
                .json(&json!({
                    "collectionID": vault_a,
                    "email": sharee.email,
                    "encryptedKey": b64::encode(&sealed_key),
                    "role": "VIEWER"
                }))
                .send()
                .await?
                .error_for_code()
                .await?;

            let (note_id, _) = upload_info_item(
                &owner_session,
                vault_a,
                &key_a,
                "Fallback Note",
                "note",
                json!({"title": "Seed Words", "content": "alpha beta"}),
                Some(("customTag", json!("preserve-me"))),
            )
            .await?;
            let (cred_id, _) = upload_info_item(
                &owner_session,
                vault_a,
                &key_a,
                "Secret",
                "account-credential",
                json!({"name": "Email", "username": "u@example.org", "password": "pw", "notes": "n"}),
                None,
            )
            .await?;
            let (rec_id, _) = upload_info_item(
                &owner_session,
                vault_a,
                &key_a,
                "Passport",
                "physicalRecord",
                json!({"name": "Passport", "location": "Safe"}),
                None,
            )
            .await?;
            let (contact_id, _) = upload_info_item(
                &owner_session,
                vault_a,
                &key_a,
                "Doctor",
                "emergencyContact",
                json!({"name": "Dr. Lee", "contactDetails": "+15550100"}),
                None,
            )
            .await?;
            let (unknown_id, _) = upload_info_item(
                &owner_session,
                vault_a,
                &key_a,
                "Custom Entry",
                "futureWidget",
                json!({"k": 1}),
                None,
            )
            .await?;

            let (file_id, file_key) = photos_fixture::upload_file(
                &owner_session,
                vault_a,
                &key_a,
                PAYLOAD,
                "contract.pdf",
                None,
            )
            .await?;
            let rewrapped = secretbox::encrypt(file_key.as_bytes(), &key_b);
            owner_session
                .api
                .post("/collections/add-files")
                .json(&json!({
                    "collectionID": vault_b,
                    "files": [{
                        "id": file_id,
                        "encryptedKey": b64::encode(&rewrapped.encrypted_data),
                        "keyDecryptionNonce": b64::encode(rewrapped.nonce.as_bytes()),
                    }]
                }))
                .send()
                .await?
                .error_for_code()
                .await?;

            let (del_col_file_id, _) = photos_fixture::upload_file(
                &owner_session,
                to_delete,
                &key_del,
                PAYLOAD,
                "ephemeral.bin",
                None,
            )
            .await?;

            let owner_cols = collections_diff(&owner_session, 0).await?;
            let mut collection_keys = HashMap::new();
            collect_collection_keys(&owner_cols.changes, &mut collection_keys);
            assert!(collection_keys.contains_key(&vault_a));
            assert!(collection_keys.contains_key(&vault_b));

            let sharee_cols = collections_diff(&sharee_session, 0).await?;
            let shared_a = sharee_cols
                .changes
                .iter()
                .find_map(|c| match c {
                    CollectionChange::Upsert(col) if col.id == vault_a => Some(col),
                    _ => None,
                })
                .ok_or("missing shared collection")?;
            assert_eq!(shared_a.name.as_deref(), Some("Vault A"));

            let mut pages_a = file_pages(&owner_session, vault_a, &key_a, 0);
            let page_a = pages_a.next().await?.ok_or("expected page for vault a")?;
            assert!(pages_a.next().await?.is_none());

            let by_id: HashMap<i64, _> = page_a
                .changes
                .into_iter()
                .filter_map(|c| match c {
                    FileChange::Upsert(f) => Some((f.file_ref.file_id, f)),
                    _ => None,
                })
                .collect();

            let note = by_id.get(&note_id).ok_or("missing note")?;
            assert!(!note.has_object);
            assert_eq!(note.documents.metadata["title"], json!("Fallback Note"));
            assert_eq!(note.documents.metadata["fileType"], json!(4));
            assert_eq!(
                note.documents.metadata["creationTime"],
                json!(1_700_000_000_123_i64)
            );
            assert_eq!(note.documents.metadata["customTag"], json!("preserve-me"));
            let pub_doc = note
                .documents
                .pub_magic_metadata
                .as_ref()
                .ok_or("missing public doc")?;
            assert_eq!(pub_doc.version, 1);
            assert_eq!(pub_doc.data["info"]["type"], json!("note"));
            assert_eq!(pub_doc.data["info"]["data"]["title"], json!("Seed Words"));
            assert_eq!(pub_doc.data["futurePubField"], json!("keep"));

            assert_eq!(
                by_id
                    .get(&cred_id)
                    .ok_or("missing cred")?
                    .documents
                    .pub_magic_metadata
                    .as_ref()
                    .ok_or("missing cred public doc")?
                    .data["info"]["type"],
                json!("account-credential")
            );
            assert_eq!(
                by_id
                    .get(&rec_id)
                    .ok_or("missing record")?
                    .documents
                    .pub_magic_metadata
                    .as_ref()
                    .ok_or("missing record public doc")?
                    .data["info"]["type"],
                json!("physicalRecord")
            );
            assert_eq!(
                by_id
                    .get(&contact_id)
                    .ok_or("missing contact")?
                    .documents
                    .pub_magic_metadata
                    .as_ref()
                    .ok_or("missing contact public doc")?
                    .data["info"]["type"],
                json!("emergencyContact")
            );
            assert_eq!(
                by_id
                    .get(&unknown_id)
                    .ok_or("missing unknown info")?
                    .documents
                    .pub_magic_metadata
                    .as_ref()
                    .ok_or("missing unknown public doc")?
                    .data["info"]["type"],
                json!("futureWidget")
            );

            let bin_a = by_id.get(&file_id).ok_or("missing file in vault a")?;
            assert!(bin_a.has_object);
            assert_eq!(bin_a.key, file_key);
            assert_eq!(bin_a.file_ref, CollectionFileRef { file_id, collection_id: vault_a });
            assert_eq!(bin_a.documents.metadata["title"], json!("contract.pdf"));

            let mut pages_b = file_pages(&owner_session, vault_b, &key_b, 0);
            let page_b = pages_b.next().await?.ok_or("expected page for vault b")?;
            let bin_b = page_b
                .changes
                .into_iter()
                .find_map(|c| match c {
                    FileChange::Upsert(f) if f.file_ref.file_id == file_id => Some(f),
                    _ => None,
                })
                .ok_or("missing file in vault b")?;
            assert_eq!(bin_b.key, file_key);
            assert_eq!(bin_b.file_ref, CollectionFileRef { file_id, collection_id: vault_b });

            owner_session
                .api
                .post("/files/trash")
                .json(&json!({"items": [{"fileID": file_id, "collectionID": vault_a}]}))
                .send()
                .await?
                .error_for_code()
                .await?;
            let mut after_trash = file_pages(&owner_session, vault_a, &key_a, page_a.cursor);
            let tomb_page = after_trash.next().await?.ok_or("expected tombstone page")?;
            assert!(tomb_page.changes.iter().any(|c| matches!(
                c,
                FileChange::Deleted { file_ref, .. } if *file_ref == CollectionFileRef { file_id, collection_id: vault_a }
            )));

            let empty_keys = HashMap::new();
            let mut unresolved_pages = trash_pages(&owner_session, 0, &empty_keys);
            let unresolved = unresolved_pages
                .next()
                .await?
                .ok_or("expected unresolved trash page")?;
            assert!(unresolved.changes.iter().any(|c| matches!(
                c,
                TrashChange::Unresolved { file_ref, .. } if file_ref.file_id == file_id
            )));

            let mut trashed_pages = trash_pages(&owner_session, 0, &collection_keys);
            let trashed = trashed_pages.next().await?.ok_or("expected trashed page")?;
            assert!(trashed.changes.iter().any(|c| matches!(
                c,
                TrashChange::Trashed(item)
                    if item.file.file_ref.file_id == file_id
                    && item.file.documents.metadata["title"] == json!("contract.pdf")
            )));

            let restore_wrapped = secretbox::encrypt(file_key.as_bytes(), &key_a);
            owner_session
                .api
                .post("/collections/restore-files")
                .json(&json!({
                    "collectionID": vault_a,
                    "files": [{
                        "id": file_id,
                        "encryptedKey": b64::encode(&restore_wrapped.encrypted_data),
                        "keyDecryptionNonce": b64::encode(restore_wrapped.nonce.as_bytes()),
                    }]
                }))
                .send()
                .await?
                .error_for_code()
                .await?;
            let mut restored_pages = trash_pages(&owner_session, trashed.cursor, &collection_keys);
            let restored = restored_pages.next().await?.ok_or("expected restored page")?;
            assert!(restored.changes.iter().any(|c| matches!(
                c,
                TrashChange::Restored { file_ref, .. } if file_ref.file_id == file_id
            )));

            // Trash the file in to_delete, delete the collection with keepFiles=false, and verify
            // collections_diff keeps the deleted collection key so trash_pages decrypts its item.
            owner_session
                .api
                .post("/files/trash")
                .json(&json!({"items": [{"fileID": del_col_file_id, "collectionID": to_delete}]}))
                .send()
                .await?
                .error_for_code()
                .await?;
            owner_session
                .api
                .delete(&format!(
                    "/collections/v3/{to_delete}?collectionID={to_delete}&keepFiles=false"
                ))
                .send()
                .await?
                .error_for_code()
                .await?;

            let delta_cols = collections_diff(&owner_session, owner_cols.cursor).await?;
            let deleted_entry = delta_cols
                .changes
                .iter()
                .find_map(|c| match c {
                    CollectionChange::Deleted { id, key, .. } if *id == to_delete => Some(key),
                    _ => None,
                })
                .ok_or("missing deleted collection change")?;
            assert_eq!(deleted_entry, &key_del);

            let mut refreshed_keys = HashMap::new();
            collect_collection_keys(&delta_cols.changes, &mut refreshed_keys);
            let mut del_trash_pages = trash_pages(&owner_session, restored.cursor, &refreshed_keys);
            let del_trash_page = del_trash_pages
                .next()
                .await?
                .ok_or("expected deleted collection trash page")?;
            assert!(del_trash_page.changes.iter().any(|c| matches!(
                c,
                TrashChange::Trashed(item)
                    if item.file.file_ref == CollectionFileRef { file_id: del_col_file_id, collection_id: to_delete }
                    && item.file.documents.metadata["title"] == json!("ephemeral.bin")
            )));

            owner_session
                .api
                .post("/trash/delete")
                .json(&json!({"fileIDs": [del_col_file_id]}))
                .send()
                .await?
                .error_for_code()
                .await?;
            let mut perm_pages =
                trash_pages(&owner_session, del_trash_page.cursor, &refreshed_keys);
            let perm_page = perm_pages
                .next()
                .await?
                .ok_or("expected permanently deleted trash page")?;
            assert!(perm_page.changes.iter().any(|c| matches!(
                c,
                TrashChange::Deleted { file_id, .. } if *file_id == del_col_file_id
            )));

            Ok(())
        })
    })
}
