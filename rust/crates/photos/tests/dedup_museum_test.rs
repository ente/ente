#![cfg(feature = "museum")]

use std::collections::HashSet;

use ente_collections::client;
use ente_core::{
    Session, b64,
    crypto::{Header, Key, SecretKey, blob, hash, secretbox},
    http::{ApiConfig, Auth},
};
use ente_photos::dedup::{self, Duplicate, RemovalCollection, RemovalFile, RemovalProgress};
use ente_test_support::{Museum, TestResult, account_fixture};
use md5::{Digest, Md5};
use serde::Deserialize;
use serde_json::{Value, json};

const ORIGINAL: &[u8] = b"Duplicate removal local Museum encrypted file fixture";

#[test]
fn duplicate_removal_against_museum() -> TestResult {
    Museum::run_async(run)
}

async fn run(endpoint: String) -> TestResult {
    let account = account_fixture::create_account(&endpoint, "dedup-owner").await?;
    let session = open_session(&endpoint, &account)?;
    let albums = vec![
        create_album(&session, "A").await?,
        create_album(&session, "B").await?,
        create_album(&session, "C").await?,
    ];
    let cases = [
        (
            "caption",
            [
                json!({"editedName":"renamed"}),
                json!({"caption":"keep"}),
                json!({}),
            ],
            1,
        ),
        ("fallback", [json!({}), json!({}), json!({})], 0),
        (
            "rename",
            [json!({}), json!({}), json!({"editedName":"renamed"})],
            2,
        ),
        ("date", [json!({}), json!({"editedTime":123}), json!({})], 1),
        (
            "caption-tie",
            [
                json!({"caption":"first"}),
                json!({"caption":"second"}),
                json!({}),
            ],
            0,
        ),
        (
            "edit-tie",
            [
                json!({"editedName":"first"}),
                json!({"editedTime":123}),
                json!({}),
            ],
            0,
        ),
        (
            "empty-name",
            [
                json!({}),
                json!({"editedName":"","editedTime":123}),
                json!({}),
            ],
            0,
        ),
        (
            "normalized-zero-caption",
            [json!({}), json!({"caption":"0"}), json!({})],
            1,
        ),
    ];
    for (name, edits, retained_index) in cases {
        let files = upload_group(&session, &albums, name, &edits).await?;
        let groups = load_groups(&session, &albums, &files).await?;
        let retained = &files[retained_index];
        let expected_trash: Vec<_> = files
            .iter()
            .filter(|f| f.id != retained.id)
            .map(|f| f.id)
            .collect();
        let mut progress = Vec::new();
        let trashed =
            dedup::remove_duplicates(&session, &groups, &albums, &files, |p| progress.push(p))
                .await?;
        assert_eq!(trashed, expected_trash, "{name}");
        assert_eq!(
            progress,
            vec![
                RemovalProgress {
                    completed: 1,
                    total: 3
                },
                RemovalProgress {
                    completed: 2,
                    total: 3
                },
                RemovalProgress {
                    completed: 3,
                    total: 3
                }
            ],
            "{name}"
        );
        let ids: HashSet<_> = files.iter().map(|f| f.id).collect();
        for album in &albums {
            let active = active_files(&session, album.id, &ids).await?;
            assert_eq!(active.len(), 1, "{name}");
            let remote = &active[0];
            assert_eq!(remote.id, retained.id, "{name}");
            let key = remote.open_key(&album.key)?;
            assert_eq!(key.as_bytes(), retained.key.as_bytes(), "{name}");
            assert_eq!(
                public_metadata(remote, &key)?,
                edits[retained_index],
                "{name}"
            );
            let header = Header::try_from_slice(&b64::decode(&remote.file.decryption_header)?)?;
            let plaintext =
                ente_photos::files::download(&session, remote.id, &key, &header, || Ok(Vec::new()))
                    .await?;
            assert_eq!(plaintext, ORIGINAL, "{name}");
        }
        assert_eq!(
            trash_ids(&session, &ids).await?,
            expected_trash.into_iter().collect(),
            "{name}"
        );
    }

    let outsider = account_fixture::create_account(&endpoint, "dedup-outsider").await?;
    let outsider_session = open_session(&endpoint, &outsider)?;
    let foreign_album = create_album(&outsider_session, "Private").await?;
    for fail_first in [true, false] {
        let files = upload_group(
            &session,
            &albums,
            "permission-failure",
            &[json!({}), json!({"caption":"keep"}), json!({})],
        )
        .await?;
        let mut groups = load_groups(&session, &albums, &files).await?;
        if fail_first {
            groups[0][0].collection_ids.insert(0, foreign_album.id);
        } else {
            groups[0][0].collection_ids.push(foreign_album.id);
        }
        let mut available: Vec<_> = albums
            .iter()
            .map(|a| RemovalCollection {
                id: a.id,
                key: Key::from_bytes(*a.key.as_bytes()),
            })
            .collect();
        available.push(RemovalCollection {
            id: foreign_album.id,
            key: Key::from_bytes(*foreign_album.key.as_bytes()),
        });
        let mut progress = Vec::new();
        let error =
            dedup::remove_duplicates(&session, &groups, &available, &files, |p| progress.push(p))
                .await
                .err()
                .ok_or("Expected Museum to reject an inaccessible album")?;
        match error {
            dedup::RemovalError::Http(error) => assert_eq!(error.status_code(), Some(404)),
            error => panic!("Expected Museum permission failure, got {error}"),
        }
        assert_eq!(progress.len(), usize::from(!fail_first));
        let ids: HashSet<_> = files.iter().map(|f| f.id).collect();
        assert!(trash_ids(&session, &ids).await?.is_empty());
        for (index, album) in albums.iter().enumerate() {
            let active = active_files(&session, album.id, &ids).await?;
            let active_ids: HashSet<_> = active.iter().map(|f| f.id).collect();
            let mut expected = HashSet::from([files[index].id]);
            if !fail_first && index == 0 {
                expected.insert(files[1].id);
            }
            assert_eq!(active_ids, expected);
        }
    }
    Ok(())
}

fn open_session(endpoint: &str, account: &account_fixture::TestAccount) -> TestResult<Session> {
    Ok(Session::new(
        ApiConfig {
            origin: endpoint.into(),
            client_package: Some("io.ente.photos".into()),
            client_version: None,
            user_agent: Some("ente-photos-dedup-e2e".into()),
            auth: Some(Auth::User(account.auth_token.clone())),
        },
        account.user_id,
        Key::try_from_slice(&account.master_key)?,
        Key::try_from_slice(&account.recovery_key)?,
        SecretKey::try_from_slice(&account.secret_key)?,
    )?)
}

async fn create_album(session: &Session, name: &str) -> TestResult<RemovalCollection> {
    #[derive(Deserialize)]
    struct Created {
        collection: client::Collection,
    }
    let key = Key::generate();
    let wrapped = secretbox::encrypt(key.as_bytes(), &session.master_key);
    let name = secretbox::encrypt(name.as_bytes(), &key);
    let created: Created = session.api.post("/collections").json(&json!({
        "encryptedKey":b64::encode(&wrapped.encrypted_data),"keyDecryptionNonce":b64::encode(wrapped.nonce.as_bytes()),
        "encryptedName":b64::encode(&name.encrypted_data),"nameDecryptionNonce":b64::encode(name.nonce.as_bytes()),"type":"album","attributes":{"version":1}
    })).send().await?.error_for_code().await?.json().await?;
    Ok(RemovalCollection {
        id: created.collection.id,
        key,
    })
}

async fn upload_object(session: &Session, bytes: Vec<u8>) -> TestResult<String> {
    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct Upload {
        url: String,
        object_key: String,
    }
    let checksum = b64::encode(&Md5::digest(&bytes));
    let upload: Upload = session
        .api
        .post("/files/upload-url")
        .json(&json!({"contentLength":bytes.len(),"contentMD5":checksum}))
        .send()
        .await?
        .error_for_code()
        .await?
        .json()
        .await?;
    session
        .api
        .http()
        .put(&upload.url)
        .header("content-md5", &checksum)
        .header("content-length", &bytes.len().to_string())
        .body(bytes)
        .send()
        .await?
        .error_for_status()?;
    Ok(upload.object_key)
}

async fn upload_group(
    session: &Session,
    albums: &[RemovalCollection],
    name: &str,
    edits: &[Value; 3],
) -> TestResult<Vec<RemovalFile>> {
    let mut files = Vec::new();
    for (index, album) in albums.iter().enumerate() {
        let key = Key::generate();
        let wrapped = secretbox::encrypt(key.as_bytes(), &album.key);
        let file = blob::encrypt(ORIGINAL, &key)?;
        let thumbnail = blob::encrypt(b"thumbnail", &key)?;
        let metadata = blob::encrypt_json(
            &json!({"title":format!("{name}-{index}.jpg"),"fileType":0,"hash":b64::encode(&hash::hash(ORIGINAL,None,None)?),"creationTime":1_700_000_000_000_000_i64,"modificationTime":1_700_000_000_000_000_i64}),
            &key,
        )?;
        let file_object = upload_object(session, file.encrypted_data).await?;
        let thumbnail_object = upload_object(session, thumbnail.encrypted_data).await?;
        let mut request = json!({"collectionID":album.id,"encryptedKey":b64::encode(&wrapped.encrypted_data),"keyDecryptionNonce":b64::encode(wrapped.nonce.as_bytes()),
            "file":{"objectKey":file_object,"decryptionHeader":b64::encode(file.decryption_header.as_bytes())},
            "thumbnail":{"objectKey":thumbnail_object,"decryptionHeader":b64::encode(thumbnail.decryption_header.as_bytes())},
            "metadata":{"encryptedData":b64::encode(&metadata.encrypted_data),"decryptionHeader":b64::encode(metadata.decryption_header.as_bytes())}});
        let count = edits[index]
            .as_object()
            .ok_or("Expected metadata object")?
            .len();
        if count > 0 {
            let encrypted = blob::encrypt_json(&edits[index], &key)?;
            request["pubMagicMetadata"] = json!({"version":1,"count":count,"data":b64::encode(&encrypted.encrypted_data),"header":b64::encode(encrypted.decryption_header.as_bytes())});
        }
        #[derive(Deserialize)]
        struct Uploaded {
            id: i64,
        }
        let uploaded: Uploaded = session
            .api
            .post("/files")
            .json(&request)
            .send()
            .await?
            .error_for_code()
            .await?
            .json()
            .await?;
        files.push(RemovalFile {
            id: uploaded.id,
            collection_id: album.id,
            key,
        });
    }
    Ok(files)
}

fn public_metadata(file: &client::File, key: &Key) -> TestResult<Value> {
    Ok(match &file.pub_magic_metadata {
        Some(metadata) => serde_json::from_slice(&metadata.decrypt(key)?)?,
        None => json!({}),
    })
}

async fn active_files(
    session: &Session,
    collection_id: i64,
    ids: &HashSet<i64>,
) -> TestResult<Vec<client::File>> {
    let page = client::files_diff(session, collection_id, 0).await?;
    assert!(!page.has_more);
    Ok(page
        .files
        .into_iter()
        .filter(|f| ids.contains(&f.id) && !f.is_deleted())
        .collect())
}

async fn load_groups(
    session: &Session,
    albums: &[RemovalCollection],
    files: &[RemovalFile],
) -> TestResult<Vec<Vec<Duplicate>>> {
    let mut candidates = Vec::new();
    let mut duplicates = Vec::new();
    let ids: HashSet<_> = files.iter().map(|f| f.id).collect();
    for album in albums {
        for remote in active_files(session, album.id, &ids).await? {
            let key = remote.open_key(&album.key)?;
            let metadata: Value = serde_json::from_slice(&blob::decrypt(
                &b64::decode(
                    remote
                        .metadata
                        .encrypted_data
                        .as_deref()
                        .ok_or("Missing metadata")?,
                )?,
                &Header::try_from_slice(&b64::decode(&remote.metadata.decryption_header)?)?,
                &key,
            )?)?;
            let edits = public_metadata(&remote, &key)?;
            candidates.push(dedup::File {
                id: remote.id,
                collection_id: album.id,
                owner_id: remote.owner_id,
                hash: metadata["hash"].as_str().map(String::from),
                size: remote
                    .extra
                    .get("info")
                    .and_then(|info| info["fileSize"].as_u64()),
            });
            duplicates.push(Duplicate {
                file_id: remote.id,
                collection_ids: vec![album.id],
                caption: edits["caption"].as_str().map(String::from),
                edited_name: edits["editedName"].as_str().map(String::from),
                edited_time: edits["editedTime"].as_i64(),
            });
        }
    }
    let collections: Vec<_> = albums
        .iter()
        .map(|a| dedup::Collection {
            id: a.id,
            owner_id: session.user_id,
        })
        .collect();
    let groups = dedup::find_duplicates(session.user_id, &collections, &candidates);
    assert_eq!(groups.len(), 1);
    assert_eq!(groups[0].items.len(), 3);
    Ok(vec![duplicates])
}

async fn trash_ids(session: &Session, ids: &HashSet<i64>) -> TestResult<HashSet<i64>> {
    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct Page {
        diff: Vec<Item>,
        has_more: bool,
    }
    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct Item {
        file: client::File,
        is_deleted: bool,
        is_restored: bool,
    }
    let page: Page = session
        .api
        .get("/trash/v2/diff")
        .query(&[("sinceTime", 0)])
        .send()
        .await?
        .error_for_code()
        .await?
        .json()
        .await?;
    assert!(!page.has_more);
    Ok(page
        .diff
        .into_iter()
        .filter(|t| ids.contains(&t.file.id) && !t.is_deleted && !t.is_restored)
        .map(|t| t.file.id)
        .collect())
}
