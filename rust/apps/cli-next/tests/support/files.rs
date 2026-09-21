use ente_core::crypto::{secretbox, stream};
use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};

use super::*;

#[test]
fn file_pages_preserve_membership_changes_and_metadata() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let collection_key = Key::generate();
    let albums = server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(
            json!({"collections": [
                collection(1, "First", &collection_key),
                collection(2, "Second", &collection_key)
            ]})
            .to_string(),
        )
        .expect_at_least(1)
        .create();
    let (first, _) = remote_file(10, &collection_key, b"original");
    let mut second = first.clone();
    second["id"] = json!(11);
    let mut removed = second.clone();
    removed["updationTime"] = json!(20);
    removed["file"]["encryptedData"] = json!("-");
    removed["metadata"]["encryptedData"] = json!("-");
    let page_one = page(&mut server, 1, 0, json!([first, second]), true).create();
    let page_two = page(&mut server, 1, 10, json!([removed]), false).create();
    let duplicate = page(&mut server, 2, 0, json!([first]), false).create();
    let listed = home.json(&["photos", "file", "list"]);
    assert_eq!(listed.as_array().unwrap().len(), 1);
    let file = &listed[0];
    assert_eq!(file["id"], "10");
    assert_eq!(file["albumIds"], json!(["1", "2"]));
    assert_eq!(file["name"], "Edited 🌧.jpg");
    assert_eq!(file["createdAt"], "2026-09-01T00:00:00.000000Z");
    assert_eq!(file["caption"], "42");
    assert_eq!(
        file["location"],
        json!({"latitude": 12.5, "longitude": 0.0})
    );
    assert_eq!(file["visibility"], "archived");
    assert_eq!(file["dateTime"], "2026-09-01T05:30:00");
    assert_eq!(file["offsetTime"], "+05:30");
    assert_eq!(file["hash"], "original-hash");
    assert!(file.get("key").is_none());
    assert_eq!(
        home.json(&["photos", "file", "view", "Edited 🌧.jpg"]),
        *file
    );
    assert_eq!(home.json(&["photos", "file", "view", "10"]), *file);
    let scoped = home.json(&["photos", "file", "list", "--album", "First"]);
    assert_eq!(scoped[0]["albumIds"], json!(["1"]));
    assert!(failure(&home.run(&["photos", "file", "view", "11"])).contains("no file matches"));
    assert!(failure(&home.run(&["photos", "file", "view", "Edited"])).contains("no file matches"));
    let human = success(home.run(&["photos", "file", "view", "10"]));
    assert!(
        String::from_utf8(human.stdout)
            .unwrap()
            .contains("Edited 🌧.jpg")
    );
    albums.assert();
    page_one.assert();
    page_two.assert();
    duplicate.assert();
}

#[test]
fn downloads_publish_only_complete_authenticated_originals() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let output_dir = tempfile::tempdir().unwrap();
    let path = output_dir.path().join("original.jpg");
    let collection_key = Key::generate();
    server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(json!({"collections": [collection(1, "First", &collection_key)]}).to_string())
        .create();
    let original = vec![37u8; stream::ENCRYPTION_CHUNK_SIZE + 321];
    let (file, encrypted) = remote_file(10, &collection_key, &original);
    page(&mut server, 1, 0, json!([file]), false).create();
    let signed = server
        .mock("GET", "/files/download/v3/10")
        .match_header("x-auth-token", "--8=")
        .with_body(json!({"url": format!("{}/original", server.url())}).to_string())
        .expect_at_least(1)
        .create();
    let args = [
        "photos",
        "file",
        "download",
        "10",
        "--output",
        path.to_str().unwrap(),
        "--json",
    ];
    let mut damaged = encrypted.clone();
    *damaged.last_mut().unwrap() ^= 1;
    let mut trailing = encrypted.clone();
    trailing.push(0);
    for bytes in [
        damaged,
        encrypted[..stream::DECRYPTION_CHUNK_SIZE].to_vec(),
        trailing,
    ] {
        let object = server.mock("GET", "/original").with_body(bytes).create();
        let output = home.run(&args);
        failure(&output);
        assert!(output.stdout.is_empty());
        assert!(!path.exists());
        assert_eq!(fs::read_dir(output_dir.path()).unwrap().count(), 0);
        object.assert();
        object.remove();
    }
    let attempts = Arc::new(AtomicUsize::new(0));
    let count = Arc::clone(&attempts);
    let object = server
        .mock("GET", "/original")
        .match_header("x-auth-token", mockito::Matcher::Missing)
        .match_header("x-client-package", mockito::Matcher::Missing)
        .with_chunked_body(move |writer| {
            if count.fetch_add(1, Ordering::SeqCst) == 0 {
                writer.write_all(&encrypted[..stream::DECRYPTION_CHUNK_SIZE + 1])?;
                return Err(std::io::Error::from(std::io::ErrorKind::ConnectionReset));
            }
            writer.write_all(&encrypted)
        })
        .expect_at_least(1)
        .create();
    let result: Value = serde_json::from_slice(&success(home.run(&args)).stdout).unwrap();
    assert_eq!(
        result,
        json!({"id": "10", "output": path, "bytes": original.len()})
    );
    assert_eq!(fs::read(&path).unwrap(), original);
    assert_eq!(attempts.load(Ordering::SeqCst), 2);
    fs::write(&path, b"existing user file").unwrap();
    failure(&home.run(&args));
    assert_eq!(fs::read(&path).unwrap(), b"existing user file");
    assert_eq!(fs::read_dir(output_dir.path()).unwrap().count(), 1);
    signed.assert();
    object.assert();
}

#[test]
fn replica_resumes_failed_pages_and_only_refreshes_changed_albums() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let key = Key::generate();
    let initial = server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::UrlEncoded("sinceTime".into(), "0".into()))
        .with_body(
            json!({"collections": [collection(1, "First", &key), collection(2, "Second", &key)]})
                .to_string(),
        )
        .expect(1)
        .create();
    let unchanged = server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::UrlEncoded(
            "sinceTime".into(),
            "20".into(),
        ))
        .with_body(json!({"collections": []}).to_string())
        .expect(2)
        .create();
    let (first, _) = remote_file(10, &key, b"first");
    let (second, _) = remote_file(11, &key, b"second");
    let first_page = page(&mut server, 1, 0, json!([first]), true)
        .expect(1)
        .create();
    let broken_page = server
        .mock("GET", "/collections/v2/diff")
        .match_query(mockito::Matcher::AllOf(vec![
            mockito::Matcher::UrlEncoded("collectionID".into(), "1".into()),
            mockito::Matcher::UrlEncoded("sinceTime".into(), "10".into()),
        ]))
        .with_status(400)
        .expect(1)
        .create();
    failure(&home.run(&["photos", "file", "list"]));
    assert!(
        failure(&home.run(&["--offline", "photos", "file", "list", "--album", "First"]))
            .contains("have not finished syncing")
    );
    first_page.assert();
    broken_page.assert();
    broken_page.remove();
    let mut second = second;
    second["updationTime"] = json!(20);
    let final_page = page(&mut server, 1, 10, json!([second]), false)
        .expect(1)
        .create();
    let other_album = page(&mut server, 2, 0, json!([first]), false)
        .expect(1)
        .create();
    let files = home.json(&["photos", "file", "list"]);
    assert_eq!(files.as_array().unwrap().len(), 2);
    assert_eq!(files[0]["albumIds"], json!(["1", "2"]));
    assert_eq!(home.json(&["photos", "file", "list"]), files);
    assert_eq!(home.json(&["--offline", "photos", "file", "list"]), files);
    initial.assert();
    unchanged.assert();
    first_page.assert();
    final_page.assert();
    other_album.assert();
    unchanged.remove();

    let mut deleted_album = collection(1, "First", &key);
    deleted_album["updationTime"] = json!(30);
    deleted_album["isDeleted"] = json!(true);
    let deletion = server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::UrlEncoded(
            "sinceTime".into(),
            "20".into(),
        ))
        .with_body(json!({"collections": [deleted_album]}).to_string())
        .expect(1)
        .create();
    let files = home.json(&["photos", "file", "list"]);
    assert_eq!(files.as_array().unwrap().len(), 1);
    assert_eq!(files[0]["albumIds"], json!(["2"]));
    deletion.assert();
    other_album.assert();

    let mut updated_album = collection(2, "Second", &key);
    updated_album["updationTime"] = json!(40);
    let updated = server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::UrlEncoded(
            "sinceTime".into(),
            "30".into(),
        ))
        .with_body(json!({"collections": [updated_album]}).to_string())
        .expect(1)
        .create();
    let mut removed = first;
    removed["updationTime"] = json!(40);
    removed["isDeleted"] = json!(true);
    let removal = page(&mut server, 2, 10, json!([removed]), false)
        .expect(1)
        .create();
    assert_eq!(home.json(&["photos", "file", "list"]), json!([]));
    updated.assert();
    removal.assert();
}

#[test]
fn account_replica_is_encrypted_and_available_offline() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    assert!(
        failure(&home.run(&["photos", "album", "list", "--offline"])).contains("no local data")
    );
    assert!(!home.dir.path().join("accounts").exists());
    let failed_sync = server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_status(400)
        .create();
    failure(&home.run(&["photos", "album", "list"]));
    assert!(
        failure(&home.run(&["photos", "album", "list", "--offline"]))
            .contains("no local Photos data")
    );
    failed_sync.assert();
    failed_sync.remove();
    let key = Key::generate();
    let albums = server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(json!({"collections": [collection(1, "Private album", &key)]}).to_string())
        .expect(2)
        .create();
    home.json(&["photos", "album", "list"]);
    let state = home.read_vault();
    let directory = home
        .dir
        .path()
        .join("accounts")
        .join(state["accounts"][0]["storage_id"].as_str().unwrap());
    let path = directory.join("data.db");
    let lock_path = directory.with_extension("lock");
    let connection = rusqlite::Connection::open(&path).unwrap();
    connection
        .pragma_update(None, "key", format!("x'{}'", "2a".repeat(32)))
        .unwrap();
    connection
        .query_row("SELECT count(*) FROM sqlite_master", [], |row| {
            row.get::<_, i64>(0)
        })
        .unwrap();
    let (file, _) = remote_file(10, &key, b"original");
    let files_page = page(&mut server, 1, 0, json!([file]), false)
        .expect(1)
        .create();
    let files = home.json(&["photos", "file", "list"]);
    assert!(directory.join("data.db-wal").exists());
    for filename in ["data.db", "data.db-wal"] {
        let bytes = fs::read(directory.join(filename)).unwrap();
        assert!(!bytes.is_empty());
        for plaintext in ["SQLite format 3", "Private album", "Edited 🌧.jpg"] {
            assert!(
                !bytes
                    .windows(plaintext.len())
                    .any(|window| window == plaintext.as_bytes())
            );
        }
    }
    drop(connection);
    let unkeyed = rusqlite::Connection::open(&path).unwrap();
    assert!(
        unkeyed
            .query_row("SELECT count(*) FROM sqlite_master", [], |row| row
                .get::<_, i64>(0))
            .is_err()
    );
    drop(unkeyed);
    albums.assert();
    files_page.assert();
    drop(server);
    assert_eq!(home.json(&["photos", "file", "list", "--offline"]), files);
    assert!(
        failure(&home.run(&[
            "photos",
            "file",
            "download",
            "10",
            "--output",
            "unused.jpg",
            "--offline"
        ]))
        .contains("download requires network access")
    );

    let mut wrong_key = state.clone();
    wrong_key["accounts"][0]["db_key"] = json!(vec![43u8; 32]);
    home.write_vault(&wrong_key);
    assert!(
        failure(&home.run(&["photos", "album", "list", "--offline"]))
            .contains("cannot open the encrypted database")
    );
    home.write_vault(&state);
    fs::remove_file(&lock_path).unwrap();
    assert_eq!(home.json(&["photos", "file", "list", "--offline"]), files);
    assert!(lock_path.is_file());
    home.json(&["accounts", "rename", "fixture", "renamed"]);
    assert_eq!(
        home.json(&[
            "photos",
            "file",
            "list",
            "--account",
            "renamed",
            "--offline"
        ]),
        files
    );
    let mut two_accounts = home.read_vault();
    let mut other = two_accounts["accounts"][0].clone();
    other["storage_id"] = json!("45b3495e-92de-43a1-a58b-e0b1e57d8c68");
    other["name"] = json!("other");
    other["user_id"] = json!(123);
    other["db_key"] = json!(vec![43u8; 32]);
    two_accounts["accounts"].as_array_mut().unwrap().push(other);
    home.write_vault(&two_accounts);
    assert!(
        failure(&home.run(&["photos", "album", "list", "--account", "other", "--offline"]))
            .contains("no local data")
    );
    assert!(
        !home
            .dir
            .path()
            .join("accounts")
            .join("45b3495e-92de-43a1-a58b-e0b1e57d8c68.lock")
            .exists()
    );
    let other_directory = home
        .dir
        .path()
        .join("accounts/45b3495e-92de-43a1-a58b-e0b1e57d8c68");
    fs::create_dir(&other_directory).unwrap();
    assert!(
        failure(&home.run(&["photos", "album", "list", "--account", "other", "--offline"]))
            .contains("unable to open database file")
    );
    assert!(!other_directory.join("data.db").exists());
    home.json(&["accounts", "logout", "renamed", "--local", "--offline"]);
    assert!(!directory.exists());
    assert!(!lock_path.exists());
}

#[test]
fn photos_lists_limit_output_and_stream_complete_results() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let key = Key::generate();
    let albums = (1..=150)
        .map(|id| collection(id, "Same album", &key))
        .collect::<Vec<_>>();
    let albums = server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(json!({"collections": albums}).to_string())
        .expect(2)
        .create();
    let (file, _) = remote_file(1, &key, b"original");
    let files = (1..=150)
        .map(|id| {
            let mut file = file.clone();
            file["id"] = json!(id);
            file
        })
        .collect::<Vec<_>>();
    let files = page(&mut server, 1, 0, json!(files), false)
        .expect(1)
        .create();
    let output = success(home.run(&["photos", "album", "list", "--json"]));
    let listed: Vec<Value> = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(listed.len(), 100);
    assert!(String::from_utf8_lossy(&output.stderr).contains("Showing first 100"));
    assert_eq!(
        home.json(&["photos", "file", "list", "--album", "1", "--limit", "1"])
            .as_array()
            .unwrap()
            .len(),
        1
    );
    albums.assert();
    files.assert();
    drop(server);

    for resource in ["album", "file"] {
        let mut base = vec!["--offline", "photos", resource, "list"];
        if resource == "file" {
            base.extend(["--album", "1"]);
        }
        for (extra, count, truncated) in [
            (vec![], 100, true),
            (vec!["--limit", "1"], 1, true),
            (vec!["--limit", "150"], 150, false),
            (vec!["--limit", "4294967295"], 150, false),
            (vec!["--all"], 150, false),
        ] {
            for as_json in [false, true] {
                let mut args = base.clone();
                args.extend(&extra);
                if as_json {
                    args.push("--json");
                }
                let output = success(home.run(&args));
                if as_json {
                    let values: Vec<Value> = serde_json::from_slice(&output.stdout).unwrap();
                    assert_eq!(values.len(), count);
                    assert_eq!(values[0]["id"], "1");
                    assert_eq!(values[count - 1]["id"], count.to_string());
                } else {
                    assert_eq!(
                        String::from_utf8_lossy(&output.stdout).lines().count(),
                        count + 1
                    );
                }
                assert_eq!(!output.stderr.is_empty(), truncated);
            }
        }
        for extra in [
            vec!["--limit", "0"],
            vec!["--limit", "-1"],
            vec!["--all", "--limit", "1"],
        ] {
            let mut args = base.clone();
            args.extend(extra);
            failure(&home.run(&args));
        }
    }
    for args in [
        vec!["--offline", "photos", "album", "view", "Same album"],
        vec![
            "--offline",
            "photos",
            "file",
            "view",
            "Edited 🌧.jpg",
            "--album",
            "1",
        ],
    ] {
        let output = home.run(&args);
        let error = failure(&output);
        assert!(output.stdout.is_empty());
        assert_eq!(
            error.lines().filter(|line| line.starts_with("  ")).count(),
            10
        );
        assert!(error.contains("More matches omitted"));
    }

    let state = home.read_vault();
    let database = home
        .dir
        .path()
        .join("accounts")
        .join(state["accounts"][0]["storage_id"].as_str().unwrap())
        .join("data.db");
    let connection = rusqlite::Connection::open(database).unwrap();
    connection
        .pragma_update(None, "key", format!("x'{}'", "2a".repeat(32)))
        .unwrap();
    connection
        .execute(
            "UPDATE photos_files SET created_at=?1 WHERE id=150",
            [i64::MAX],
        )
        .unwrap();
    drop(connection);
    for as_json in [false, true] {
        let mut args = vec![
            "--offline",
            "photos",
            "file",
            "list",
            "--album",
            "1",
            "--all",
        ];
        if as_json {
            args.push("--json");
        }
        let output = home.run(&args);
        assert!(failure(&output).contains("timestamp is outside the supported range"));
        assert!(String::from_utf8_lossy(&output.stdout).contains("Edited 🌧.jpg"));
    }
}

fn collection(id: i64, name: &str, key: &Key) -> Value {
    let wrapped = secretbox::encrypt(key.as_bytes(), &Key::from_bytes([0; 32]));
    json!({
        "id": id, "owner": {"id": 9007199254740993i64}, "name": name, "type": "album",
        "updationTime": 20, "encryptedKey": b64::encode(&wrapped.encrypted_data),
        "keyDecryptionNonce": b64::encode(wrapped.nonce.as_bytes()),
    })
}

fn remote_file(id: i64, collection_key: &Key, original: &[u8]) -> (Value, Vec<u8>) {
    let key = Key::generate();
    let wrapped = secretbox::encrypt(key.as_bytes(), collection_key);
    let metadata = blob::encrypt_json(
        &json!({
            "title": "Original.jpg", "fileType": 0,
            "creationTime": 1_700_000_000_000_000i64,
            "modificationTime": 1_700_000_001_000_000i64,
            "latitude": 1.0, "longitude": 2.0, "hash": "original-hash"
        }),
        &key,
    )
    .unwrap();
    let public = blob::encrypt_json(
        &json!({
            "editedName": "Edited 🌧.jpg", "editedTime": 1_788_220_800_000_000i64,
            "caption": 42, "lat": 12.5, "long": 0.0,
            "dateTime": "2026-09-01T05:30:00", "offsetTime": "+05:30",
        }),
        &key,
    )
    .unwrap();
    let private = blob::encrypt_json(&json!({"visibility": 1}), &key).unwrap();
    let mut encrypted = Vec::new();
    let header =
        stream::encrypt_file(&mut std::io::Cursor::new(original), &mut encrypted, &key).unwrap();
    (
        json!({
            "id": id, "ownerID": 9007199254740993i64, "collectionID": 1, "updationTime": 10,
            "encryptedKey": b64::encode(&wrapped.encrypted_data),
            "keyDecryptionNonce": b64::encode(wrapped.nonce.as_bytes()),
            "file": {"decryptionHeader": b64::encode(header.as_bytes())},
            "metadata": {"encryptedData": b64::encode(&metadata.encrypted_data),
                "decryptionHeader": b64::encode(metadata.decryption_header.as_bytes())},
            "pubMagicMetadata": {"data": b64::encode(&public.encrypted_data),
                "header": b64::encode(public.decryption_header.as_bytes())},
            "magicMetadata": {"data": b64::encode(&private.encrypted_data),
                "header": b64::encode(private.decryption_header.as_bytes())},
            "isDeleted": false
        }),
        encrypted,
    )
}

fn page(
    server: &mut mockito::ServerGuard,
    collection: i64,
    since: i64,
    diff: Value,
    more: bool,
) -> mockito::Mock {
    server
        .mock("GET", "/collections/v2/diff")
        .match_query(mockito::Matcher::AllOf(vec![
            mockito::Matcher::UrlEncoded("collectionID".into(), collection.to_string()),
            mockito::Matcher::UrlEncoded("sinceTime".into(), since.to_string()),
        ]))
        .with_body(json!({"diff": diff, "hasMore": more}).to_string())
}
