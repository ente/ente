#![cfg(feature = "museum")]

use std::collections::HashSet;

use ente_collections::client;
use ente_core::{
    Session, b64,
    crypto::{Header, Key, blob},
};
use ente_photos::dedup::{self, Duplicate, RemovalCollection, RemovalFile, RemovalProgress};
use ente_test_support::{Museum, TestResult, account_fixture, photos_fixture};
use serde::Deserialize;
use serde_json::{Value, json};

const ORIGINAL: &[u8] = b"Duplicate removal local Museum encrypted file fixture";

#[test]
fn duplicate_removal_against_museum() -> TestResult {
    Museum::run_async(run)
}

async fn run(endpoint: String) -> TestResult {
    let account = account_fixture::create_account(&endpoint, "dedup-owner").await?;
    let session = account.session(&endpoint, "ente-photos-dedup-e2e")?;
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
    let outsider_session = outsider.session(&endpoint, "ente-photos-dedup-e2e")?;
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

async fn create_album(session: &Session, name: &str) -> TestResult<RemovalCollection> {
    let (id, key) = photos_fixture::create_album(session, name).await?;
    Ok(RemovalCollection { id, key })
}

async fn upload_group(
    session: &Session,
    albums: &[RemovalCollection],
    name: &str,
    edits: &[Value; 3],
) -> TestResult<Vec<RemovalFile>> {
    let mut files = Vec::new();
    for (index, album) in albums.iter().enumerate() {
        let (id, key) = photos_fixture::upload_file(
            session,
            album.id,
            &album.key,
            ORIGINAL,
            &format!("{name}-{index}.jpg"),
            Some(&edits[index]),
        )
        .await?;
        files.push(RemovalFile {
            id,
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
            is_hidden: false,
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
