use std::collections::HashMap;

use ente_collections::client::{
    EncryptedMetadata, FilePage as RemoteFilePage, file_pages as collections_file_pages,
    trash_pages as collections_trash_pages,
};
pub use ente_collections::{
    CollectionFileRef,
    client::{Collection as RemoteCollection, File as RemoteFile, TrashEntry},
};
use ente_core::{
    Session, b64,
    crypto::{Header, Key, blob},
};

use crate::{
    Result,
    metadata::{self, CollectionDocuments, FileDocuments, VersionedJson},
};

pub struct LockerCollection {
    pub id: i64,
    pub key: Key,
    pub name: Option<String>,
    pub kind: String,
    pub owner_id: i64,
    pub updation_time: i64,
    pub documents: CollectionDocuments,
    pub remote: RemoteCollection,
}

pub enum CollectionChange {
    Upsert(Box<LockerCollection>),
    Deleted {
        id: i64,
        updation_time: i64,
        key: Key,
        remote: Box<RemoteCollection>,
    },
}

pub struct CollectionSyncPage {
    pub changes: Vec<CollectionChange>,
    pub cursor: i64,
}

pub struct LockerFile {
    pub file_ref: CollectionFileRef,
    pub owner_id: i64,
    pub key: Key,
    pub file_header: Option<Header>,
    pub has_object: bool,
    pub file_size: Option<u64>,
    pub updation_time: i64,
    pub documents: FileDocuments,
    pub remote: RemoteFile,
}

pub enum FileChange {
    Upsert(Box<LockerFile>),
    Deleted {
        file_ref: CollectionFileRef,
        updation_time: i64,
    },
}

pub struct FileSyncPage {
    pub collection_id: i64,
    pub changes: Vec<FileChange>,
    pub cursor: i64,
    pub has_more: bool,
}

pub struct LockerTrashItem {
    pub file: LockerFile,
    pub created_at: i64,
    pub updated_at: i64,
    pub delete_by: i64,
}

pub enum TrashChange {
    Trashed(Box<LockerTrashItem>),
    Restored {
        file_ref: CollectionFileRef,
        updated_at: i64,
    },
    Deleted {
        file_id: i64,
        updated_at: i64,
    },
    Unresolved {
        file_ref: CollectionFileRef,
        entry: Box<TrashEntry>,
    },
}

pub struct TrashSyncPage {
    pub changes: Vec<TrashChange>,
    pub cursor: i64,
    pub has_more: bool,
}

pub fn collect_collection_keys(changes: &[CollectionChange], keys: &mut HashMap<i64, Key>) {
    for change in changes {
        match change {
            CollectionChange::Upsert(collection) => {
                keys.insert(collection.id, Key::from_bytes(*collection.key.as_bytes()));
            }
            CollectionChange::Deleted { id, key, .. } => {
                keys.insert(*id, Key::from_bytes(*key.as_bytes()));
            }
        }
    }
}

pub async fn collections_diff(session: &Session, since: i64) -> Result<CollectionSyncPage> {
    let page = ente_collections::client::diff(session, since).await?;
    let changes = page
        .collections
        .into_iter()
        .map(|remote| decode_collection(session, remote))
        .collect::<Result<Vec<_>>>()?;
    Ok(CollectionSyncPage {
        changes,
        cursor: page.cursor,
    })
}

fn decode_collection(session: &Session, remote: RemoteCollection) -> Result<CollectionChange> {
    if remote.is_deleted() {
        let key = remote.open_key(session)?;
        return Ok(CollectionChange::Deleted {
            id: remote.id,
            updation_time: remote.updation_time,
            key,
            remote: Box::new(remote),
        });
    }
    Ok(CollectionChange::Upsert(Box::new(decrypt_collection(
        session, remote,
    )?)))
}

fn decrypt_collection(session: &Session, remote: RemoteCollection) -> Result<LockerCollection> {
    let key = remote.open_key(session)?;
    let name = remote
        .open_name_bytes(&key)
        .ok()
        .and_then(|bytes| String::from_utf8(bytes).ok());
    let private = remote
        .magic_metadata
        .as_ref()
        .map(|m| decrypt_versioned_json(m, &key))
        .transpose()?;
    let public = remote
        .pub_magic_metadata
        .as_ref()
        .map(|m| decrypt_versioned_json(m, &key))
        .transpose()?;
    let shared = remote
        .shared_magic_metadata
        .as_ref()
        .map(|m| decrypt_versioned_json(m, &key))
        .transpose()?;
    Ok(LockerCollection {
        id: remote.id,
        key,
        name,
        kind: remote.kind.clone(),
        owner_id: remote.owner.id,
        updation_time: remote.updation_time,
        documents: CollectionDocuments {
            private,
            public,
            shared,
        },
        remote,
    })
}

pub struct LockerFilePages<'a> {
    collection_id: i64,
    collection_key: &'a Key,
    inner: ente_collections::client::FilePages<'a>,
}

pub fn file_pages<'a>(
    session: &'a Session,
    collection_id: i64,
    collection_key: &'a Key,
    since: i64,
) -> LockerFilePages<'a> {
    LockerFilePages {
        collection_id,
        collection_key,
        inner: collections_file_pages(session, collection_id, since),
    }
}

pub async fn file_diff_page(
    session: &Session,
    collection_id: i64,
    collection_key: &Key,
    since: i64,
) -> Result<FileSyncPage> {
    let page = ente_collections::client::files_diff(session, collection_id, since).await?;
    decode_file_page(collection_id, collection_key, page)
}

impl LockerFilePages<'_> {
    pub async fn next(&mut self) -> Result<Option<FileSyncPage>> {
        let Some(page) = self.inner.next().await? else {
            return Ok(None);
        };
        Ok(Some(decode_file_page(
            self.collection_id,
            self.collection_key,
            page,
        )?))
    }
}

fn decode_file_page(
    collection_id: i64,
    collection_key: &Key,
    page: RemoteFilePage,
) -> Result<FileSyncPage> {
    let changes = page
        .files
        .into_iter()
        .map(|remote| decode_file_change(remote, collection_key))
        .collect::<Result<Vec<_>>>()?;
    Ok(FileSyncPage {
        collection_id,
        changes,
        cursor: page.cursor,
        has_more: page.has_more,
    })
}

pub struct LockerTrashPages<'a> {
    collection_keys: &'a HashMap<i64, Key>,
    inner: ente_collections::client::TrashPages<'a>,
}

pub fn trash_pages<'a>(
    session: &'a Session,
    since: i64,
    collection_keys: &'a HashMap<i64, Key>,
) -> LockerTrashPages<'a> {
    LockerTrashPages {
        collection_keys,
        inner: collections_trash_pages(session, since),
    }
}

impl LockerTrashPages<'_> {
    pub async fn next(&mut self) -> Result<Option<TrashSyncPage>> {
        let Some(page) = self.inner.next().await? else {
            return Ok(None);
        };
        let changes = page
            .entries
            .into_iter()
            .map(|entry| decode_trash_change(entry, self.collection_keys))
            .collect::<Result<Vec<_>>>()?;
        Ok(Some(TrashSyncPage {
            changes,
            cursor: page.cursor,
            has_more: page.has_more,
        }))
    }
}

fn decode_file_change(remote: RemoteFile, collection_key: &Key) -> Result<FileChange> {
    let file_ref = remote.file_ref();
    if remote.is_deleted() {
        return Ok(FileChange::Deleted {
            file_ref,
            updation_time: remote.updation_time,
        });
    }
    Ok(FileChange::Upsert(Box::new(decrypt_file(
        remote,
        collection_key,
    )?)))
}

fn decode_trash_change(
    entry: TrashEntry,
    collection_keys: &HashMap<i64, Key>,
) -> Result<TrashChange> {
    let file_ref = entry.file.file_ref();
    if entry.is_deleted {
        return Ok(TrashChange::Deleted {
            file_id: file_ref.file_id,
            updated_at: entry.updated_at,
        });
    }
    if entry.is_restored {
        return Ok(TrashChange::Restored {
            file_ref,
            updated_at: entry.updated_at,
        });
    }
    let Some(collection_key) = collection_keys.get(&file_ref.collection_id) else {
        return Ok(TrashChange::Unresolved {
            file_ref,
            entry: Box::new(entry),
        });
    };
    let file = decrypt_file(entry.file, collection_key)?;
    Ok(TrashChange::Trashed(Box::new(LockerTrashItem {
        file,
        created_at: entry.created_at,
        updated_at: entry.updated_at,
        delete_by: entry.delete_by,
    })))
}

fn decrypt_file(remote: RemoteFile, collection_key: &Key) -> Result<LockerFile> {
    let file_ref = remote.file_ref();
    let key = remote.open_key(collection_key)?;
    let original_bytes = blob::decrypt(
        &b64::decode(remote.metadata.encrypted_data.as_deref().unwrap_or(""))?,
        &Header::try_from_slice(&b64::decode(&remote.metadata.decryption_header)?)?,
        &key,
    )?;
    let metadata = metadata::parse_json(&original_bytes)?;
    let pub_magic_metadata = remote
        .pub_magic_metadata
        .as_ref()
        .map(|m| decrypt_versioned_json(m, &key))
        .transpose()?;
    let magic_metadata = remote
        .magic_metadata
        .as_ref()
        .map(|m| decrypt_versioned_json(m, &key))
        .transpose()?;

    let has_object = !remote.file.decryption_header.is_empty();
    let file_header = has_object
        .then(|| -> Result<Header> {
            Ok(Header::try_from_slice(&b64::decode(
                &remote.file.decryption_header,
            )?)?)
        })
        .transpose()?;
    let file_size = remote
        .extra
        .get("info")
        .and_then(|info| info.get("fileSize"))
        .and_then(serde_json::Value::as_u64);

    Ok(LockerFile {
        file_ref,
        owner_id: remote.owner_id,
        key,
        file_header,
        has_object,
        file_size,
        updation_time: remote.updation_time,
        documents: FileDocuments {
            metadata,
            pub_magic_metadata,
            magic_metadata,
        },
        remote,
    })
}

fn decrypt_versioned_json(encrypted: &EncryptedMetadata, key: &Key) -> Result<VersionedJson> {
    let bytes = encrypted.decrypt(key)?;
    let data = metadata::parse_json(&bytes)?;
    let version = encrypted
        .extra
        .get("version")
        .and_then(serde_json::Value::as_i64)
        .unwrap_or(0);
    Ok(VersionedJson { version, data })
}

#[cfg(test)]
mod tests {
    use ente_core::{
        crypto::{SecretKey, secretbox, stream},
        http::{ApiConfig, Auth},
    };
    use mockito::{Matcher, Server};
    use serde_json::{Value, json};

    use super::*;

    fn test_session(origin: String, user_id: i64) -> Result<Session> {
        Ok(Session::new(
            ApiConfig {
                origin,
                client_package: Some("io.ente.locker".into()),
                client_version: None,
                user_agent: Some("ente-locker-tests".into()),
                auth: Some(Auth::User("token".into())),
            },
            user_id,
            Key::generate(),
            Key::generate(),
            SecretKey::generate(),
        )
        .map_err(ente_collections::Error::from)?)
    }

    fn encrypted_file_json(
        id: i64,
        collection_id: i64,
        owner_id: i64,
        collection_key: &Key,
        file_key: &Key,
        raw_metadata: &[u8],
        public: Option<(Vec<u8>, &Key)>,
    ) -> Value {
        let wrapped_key = secretbox::encrypt(file_key.as_bytes(), collection_key);
        let enc_meta = blob::encrypt(raw_metadata, file_key).unwrap();
        let file_header = stream::encrypt_file(
            &mut std::io::Cursor::new(b"bytes"),
            &mut Vec::new(),
            file_key,
        )
        .unwrap();
        let pub_json = match public {
            Some((bytes, pub_key)) => {
                let enc = blob::encrypt(&bytes, pub_key).unwrap();
                json!({
                    "version": 1,
                    "data": b64::encode(&enc.encrypted_data),
                    "header": b64::encode(enc.decryption_header.as_bytes()),
                })
            }
            None => Value::Null,
        };
        json!({
            "id": id,
            "collectionID": collection_id,
            "ownerID": owner_id,
            "encryptedKey": b64::encode(&wrapped_key.encrypted_data),
            "keyDecryptionNonce": b64::encode(wrapped_key.nonce.as_bytes()),
            "file": {"decryptionHeader": b64::encode(file_header.as_bytes())},
            "metadata": {
                "encryptedData": b64::encode(&enc_meta.encrypted_data),
                "decryptionHeader": b64::encode(enc_meta.decryption_header.as_bytes())
            },
            "pubMagicMetadata": pub_json,
            "info": {"fileSize": 5},
            "isDeleted": false,
            "updationTime": 200
        })
    }

    #[tokio::test]
    async fn collections_and_files_fail_closed_except_bad_collection_name() -> Result<()> {
        let mut server = Server::new_async().await;
        let session = test_session(server.url(), 7)?;
        let key_a = Key::generate();
        let key_b = Key::generate();
        let wrong_key = Key::generate();
        let wrapped_key_a = secretbox::encrypt(key_a.as_bytes(), &session.master_key);
        let bad_wrapped_key = secretbox::encrypt(key_a.as_bytes(), &wrong_key);
        let bad_name = secretbox::encrypt(b"Corrupt Name", &wrong_key);
        let good_col_pub = blob::encrypt_json(&json!({"order": 1}), &key_a)?;
        let bad_col_pub = blob::encrypt_json(&json!({"order": 1}), &wrong_key)?;
        let invalid_json_col_pub = blob::encrypt(b"{not-json", &key_a)?;

        let mock_bad_name = server
            .mock("GET", "/collections/v2")
            .match_query(Matcher::UrlEncoded("sinceTime".into(), "0".into()))
            .with_status(200)
            .with_body(
                json!({
                    "collections": [{
                        "id": 10,
                        "owner": {"id": 7},
                        "encryptedKey": b64::encode(&wrapped_key_a.encrypted_data),
                        "keyDecryptionNonce": b64::encode(wrapped_key_a.nonce.as_bytes()),
                        "encryptedName": b64::encode(&bad_name.encrypted_data),
                        "nameDecryptionNonce": b64::encode(bad_name.nonce.as_bytes()),
                        "type": "album",
                        "updationTime": 100,
                        "pubMagicMetadata": {
                            "version": 1,
                            "data": b64::encode(&good_col_pub.encrypted_data),
                            "header": b64::encode(good_col_pub.decryption_header.as_bytes()),
                        }
                    }]
                })
                .to_string(),
            )
            .expect(1)
            .create_async()
            .await;

        let col_page = collections_diff(&session, 0).await?;
        mock_bad_name.assert_async().await;
        match &col_page.changes[0] {
            CollectionChange::Upsert(col) => {
                assert_eq!(col.id, 10);
                assert!(col.name.is_none());
                assert_eq!(
                    col.documents
                        .public
                        .as_ref()
                        .map(|doc| (&doc.version, &doc.data)),
                    Some((&1, &json!({"order": 1})))
                );
            }
            _ => panic!("expected collection upsert with unreadable name"),
        }
        let mut collected_keys = HashMap::new();
        collect_collection_keys(&col_page.changes, &mut collected_keys);
        assert_eq!(collected_keys.get(&10), Some(&key_a));

        let mock_bad_key = server
            .mock("GET", "/collections/v2")
            .match_query(Matcher::UrlEncoded("sinceTime".into(), "1".into()))
            .with_status(200)
            .with_body(
                json!({
                    "collections": [{
                        "id": 11,
                        "owner": {"id": 7},
                        "encryptedKey": b64::encode(&bad_wrapped_key.encrypted_data),
                        "keyDecryptionNonce": b64::encode(bad_wrapped_key.nonce.as_bytes()),
                        "type": "album",
                        "updationTime": 101
                    }]
                })
                .to_string(),
            )
            .expect(1)
            .create_async()
            .await;
        assert!(collections_diff(&session, 1).await.is_err());
        mock_bad_key.assert_async().await;

        let mock_bad_col_pub = server
            .mock("GET", "/collections/v2")
            .match_query(Matcher::UrlEncoded("sinceTime".into(), "2".into()))
            .with_status(200)
            .with_body(
                json!({
                    "collections": [{
                        "id": 12,
                        "owner": {"id": 7},
                        "encryptedKey": b64::encode(&wrapped_key_a.encrypted_data),
                        "keyDecryptionNonce": b64::encode(wrapped_key_a.nonce.as_bytes()),
                        "name": "Bad Pub",
                        "type": "album",
                        "updationTime": 102,
                        "pubMagicMetadata": {
                            "version": 1,
                            "data": b64::encode(&bad_col_pub.encrypted_data),
                            "header": b64::encode(bad_col_pub.decryption_header.as_bytes()),
                        }
                    }]
                })
                .to_string(),
            )
            .expect(1)
            .create_async()
            .await;
        assert!(collections_diff(&session, 2).await.is_err());
        mock_bad_col_pub.assert_async().await;

        let mock_bad_col_json = server
            .mock("GET", "/collections/v2")
            .match_query(Matcher::UrlEncoded("sinceTime".into(), "3".into()))
            .with_status(200)
            .with_body(
                json!({
                    "collections": [{
                        "id": 13,
                        "owner": {"id": 7},
                        "encryptedKey": b64::encode(&wrapped_key_a.encrypted_data),
                        "keyDecryptionNonce": b64::encode(wrapped_key_a.nonce.as_bytes()),
                        "name": "Bad JSON",
                        "type": "album",
                        "updationTime": 103,
                        "pubMagicMetadata": {
                            "version": 1,
                            "data": b64::encode(&invalid_json_col_pub.encrypted_data),
                            "header": b64::encode(invalid_json_col_pub.decryption_header.as_bytes()),
                        }
                    }]
                })
                .to_string(),
            )
            .expect(1)
            .create_async()
            .await;
        assert!(collections_diff(&session, 3).await.is_err());
        mock_bad_col_json.assert_async().await;

        let regular_key = Key::generate();
        let bad_file_pub = encrypted_file_json(
            1,
            10,
            7,
            &key_a,
            &regular_key,
            br#"{"title":"doc.pdf","fileType":3}"#,
            Some((br#"{"editedName":"ignored"}"#.to_vec(), &wrong_key)),
        );
        let mock_bad_file_pub = server
            .mock("GET", "/collections/v2/diff")
            .match_query(Matcher::AllOf(vec![
                Matcher::UrlEncoded("collectionID".into(), "10".into()),
                Matcher::UrlEncoded("sinceTime".into(), "0".into()),
            ]))
            .with_status(200)
            .with_body(json!({"diff": [bad_file_pub], "hasMore": false}).to_string())
            .expect(1)
            .create_async()
            .await;
        assert!(file_pages(&session, 10, &key_a, 0).next().await.is_err());
        mock_bad_file_pub.assert_async().await;

        let bad_file_json =
            encrypted_file_json(2, 10, 7, &key_a, &Key::generate(), b"not-valid-json", None);
        let mock_bad_file_json = server
            .mock("GET", "/collections/v2/diff")
            .match_query(Matcher::AllOf(vec![
                Matcher::UrlEncoded("collectionID".into(), "10".into()),
                Matcher::UrlEncoded("sinceTime".into(), "1".into()),
            ]))
            .with_status(200)
            .with_body(json!({"diff": [bad_file_json], "hasMore": false}).to_string())
            .expect(1)
            .create_async()
            .await;
        assert!(file_pages(&session, 10, &key_a, 1).next().await.is_err());
        mock_bad_file_json.assert_async().await;

        let shared_file_key = Key::generate();
        let copy_a = encrypted_file_json(
            3,
            10,
            7,
            &key_a,
            &shared_file_key,
            br#"{"title":"shared.bin","fileType":3}"#,
            None,
        );
        let copy_b = encrypted_file_json(
            3,
            20,
            7,
            &key_b,
            &shared_file_key,
            br#"{"title":"shared.bin","fileType":3}"#,
            None,
        );
        let mock_a = server
            .mock("GET", "/collections/v2/diff")
            .match_query(Matcher::AllOf(vec![
                Matcher::UrlEncoded("collectionID".into(), "10".into()),
                Matcher::UrlEncoded("sinceTime".into(), "2".into()),
            ]))
            .with_status(200)
            .with_body(json!({"diff": [copy_a], "hasMore": false}).to_string())
            .expect(1)
            .create_async()
            .await;
        let mock_b = server
            .mock("GET", "/collections/v2/diff")
            .match_query(Matcher::AllOf(vec![
                Matcher::UrlEncoded("collectionID".into(), "20".into()),
                Matcher::UrlEncoded("sinceTime".into(), "0".into()),
            ]))
            .with_status(200)
            .with_body(json!({"diff": [copy_b], "hasMore": false}).to_string())
            .expect(1)
            .create_async()
            .await;

        let mut pages_a = file_pages(&session, 10, &key_a, 2);
        let page_a = pages_a.next().await?.unwrap();
        assert!(pages_a.next().await?.is_none());
        mock_a.assert_async().await;
        match &page_a.changes[0] {
            FileChange::Upsert(file) => {
                assert_eq!(
                    file.file_ref,
                    CollectionFileRef {
                        file_id: 3,
                        collection_id: 10
                    }
                );
                assert_eq!(file.key, shared_file_key);
                assert_eq!(
                    file.documents.metadata,
                    json!({"title": "shared.bin", "fileType": 3})
                );
            }
            _ => panic!("expected upsert for copy a"),
        }

        let mut pages_b = file_pages(&session, 20, &key_b, 0);
        let page_b = pages_b.next().await?.unwrap();
        mock_b.assert_async().await;
        match &page_b.changes[0] {
            FileChange::Upsert(file) => {
                assert_eq!(
                    file.file_ref,
                    CollectionFileRef {
                        file_id: 3,
                        collection_id: 20
                    }
                );
                assert_eq!(file.key, shared_file_key);
            }
            _ => panic!("expected upsert for copy b"),
        }
        Ok(())
    }

    #[tokio::test]
    async fn trash_pages_fails_closed_on_corrupt_entry_with_known_key() -> Result<()> {
        let mut server = Server::new_async().await;
        let session = test_session(server.url(), 7)?;
        let key_a = Key::generate();
        let wrong_key = Key::generate();
        let keys = HashMap::from([(10, Key::from_bytes(*key_a.as_bytes()))]);

        let mock_bad_file_key = server
            .mock("GET", "/trash/v2/diff")
            .match_query(Matcher::UrlEncoded("sinceTime".into(), "0".into()))
            .with_status(200)
            .with_body(
                json!({
                    "diff": [{
                        "file": encrypted_file_json(
                            101,
                            10,
                            7,
                            &wrong_key,
                            &Key::generate(),
                            br#"{"title":"a.pdf","fileType":3}"#,
                            None,
                        ),
                        "isDeleted": false,
                        "isRestored": false,
                        "deleteBy": 300,
                        "createdAt": 100,
                        "updatedAt": 200
                    }],
                    "hasMore": false
                })
                .to_string(),
            )
            .expect(1)
            .create_async()
            .await;
        assert!(trash_pages(&session, 0, &keys).next().await.is_err());
        mock_bad_file_key.assert_async().await;

        let mock_bad_metadata = server
            .mock("GET", "/trash/v2/diff")
            .match_query(Matcher::UrlEncoded("sinceTime".into(), "1".into()))
            .with_status(200)
            .with_body(
                json!({
                    "diff": [{
                        "file": encrypted_file_json(
                            102,
                            10,
                            7,
                            &key_a,
                            &Key::generate(),
                            b"not-valid-json",
                            None,
                        ),
                        "isDeleted": false,
                        "isRestored": false,
                        "deleteBy": 300,
                        "createdAt": 100,
                        "updatedAt": 200
                    }],
                    "hasMore": false
                })
                .to_string(),
            )
            .expect(1)
            .create_async()
            .await;
        assert!(trash_pages(&session, 1, &keys).next().await.is_err());
        mock_bad_metadata.assert_async().await;
        Ok(())
    }

    #[tokio::test]
    async fn deleted_collection_with_unreadable_key_fails_closed() -> Result<()> {
        let mut server = Server::new_async().await;
        let session = test_session(server.url(), 7)?;
        let wrong_key = Key::generate();
        let bad_wrapped_key = secretbox::encrypt(Key::generate().as_bytes(), &wrong_key);

        let mock_bad_deleted = server
            .mock("GET", "/collections/v2")
            .match_query(Matcher::UrlEncoded("sinceTime".into(), "0".into()))
            .with_status(200)
            .with_body(
                json!({
                    "collections": [{
                        "id": 99,
                        "owner": {"id": 7},
                        "encryptedKey": b64::encode(&bad_wrapped_key.encrypted_data),
                        "keyDecryptionNonce": b64::encode(bad_wrapped_key.nonce.as_bytes()),
                        "type": "folder",
                        "updationTime": 300,
                        "isDeleted": true
                    }]
                })
                .to_string(),
            )
            .expect(1)
            .create_async()
            .await;

        assert!(collections_diff(&session, 0).await.is_err());
        mock_bad_deleted.assert_async().await;
        Ok(())
    }
}
