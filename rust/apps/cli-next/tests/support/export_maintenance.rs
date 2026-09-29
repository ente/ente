use super::*;
use crate::export_process::ExportChild;

fn listing(server: &mut mockito::ServerGuard, albums: Value) -> mockito::Mock {
    server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(json!({"collections":albums}).to_string())
        .create()
}

fn revision(mut record: Value, version: i64) -> Value {
    record["updationTime"] = json!(version);
    record
}

fn removed(mut file: Value, version: i64) -> Value {
    file["updationTime"] = json!(version);
    file["file"]["encryptedData"] = json!("-");
    file["metadata"]["encryptedData"] = json!("-");
    file
}

fn file_key(file: &Value, album_key: &Key) -> Key {
    Key::try_from_slice(
        &secretbox::decrypt(
            &b64::decode(file["encryptedKey"].as_str().unwrap()).unwrap(),
            &Nonce::try_from_slice(
                &b64::decode(file["keyDecryptionNonce"].as_str().unwrap()).unwrap(),
            )
            .unwrap(),
            album_key,
        )
        .unwrap(),
    )
    .unwrap()
}

fn public(mut file: Value, album_key: &Key, value: Value, version: i64) -> Value {
    let encrypted = blob::encrypt_json(&value, &file_key(&file, album_key)).unwrap();
    file["pubMagicMetadata"] = json!({"data":b64::encode(&encrypted.encrypted_data),"header":b64::encode(encrypted.decryption_header.as_bytes())});
    revision(file, version)
}

fn count(db: &rusqlite::Connection, sql: &str) -> i64 {
    db.query_row(sql, [], |r| r.get(0)).unwrap()
}

#[test]
fn export_retries_transient_collection_and_file_refresh_failures() {
    for route in ["/collections/v2", "/collections/v2/diff"] {
        let mut server = mockito::Server::new();
        let home = TestHome::new();
        home.seed(&server.url());
        let key = Key::generate();
        let failed = server
            .mock("GET", route)
            .match_query(mockito::Matcher::Any)
            .with_status(503)
            .expect(1)
            .create();
        let albums = listing(&mut server, json!([collection(1, "First", &key)]));
        let (file, bytes) = source(10, &key, b"original", "Photo.jpg");
        let files = page(&mut server, 1, 0, json!([file]), false)
            .expect(1)
            .create();
        let fetched = download(&mut server, 10, &bytes, 1);
        let destination = tempfile::tempdir().unwrap();
        let root = destination.path().join("photos");
        let result = run(&home, &root, &[], true);
        assert_eq!(
            result["copies"],
            json!({"expected":1,"completed":1,"pending":0})
        );
        assert_component(&root, "First", "Photo.jpg", b"original");
        let db = database(&home);
        assert_eq!(count(&db, "SELECT cursor FROM photos_sync"), 20);
        assert_eq!(
            db.query_row(
                "SELECT files_cursor,files_synced_to FROM photos_collections WHERE id=1",
                [],
                |r| Ok((r.get::<_, i64>(0)?, r.get::<_, i64>(1)?))
            )
            .unwrap(),
            (10, 20)
        );
        failed.assert();
        albums.assert();
        files.assert();
        fetched.assert();
    }
}

#[test]
fn export_local_inventory_failure_preserves_output_and_reports_unknown_totals() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let key = Key::generate();
    listing(&mut server, json!([collection(1, "First", &key)]));
    let (file, bytes) = source(10, &key, b"original", "Photo.jpg");
    page(&mut server, 1, 0, json!([file]), false).create();
    let downloaded = download(&mut server, 10, &bytes, 1);
    let destination = tempfile::tempdir().unwrap();
    let root = destination.path().join("photos");
    assert_eq!(run(&home, &root, &[], true)["copies"]["completed"], 1);
    let published = [
        "export.json",
        "First/metadata.json",
        "First/Photo.jpg",
        "First/metadata/Photo.jpg.json",
    ]
    .map(|path| (path, fs::read(root.join(path)).unwrap()));
    database(&home)
        .execute_batch(
            "UPDATE photos_files SET record='{}' WHERE collection_id=1 AND id=10; UPDATE photos_collections SET files_synced_to=NULL WHERE id=1;",
        )
        .unwrap();
    let refreshed = page(&mut server, 1, 10, json!([]), false)
        .expect(1)
        .create();
    let result = run_failure(&home, &root, &[], "missing field `remote`");
    assert!(result["files"].is_null());
    assert!(result["copies"].is_null());
    assert_eq!(result["failures"], 1);
    let output = home.run(&["photos", "export", root.to_str().unwrap()]);
    assert!(failure(&output).contains("missing field `remote`"));
    assert!(
        String::from_utf8(output.stdout)
            .unwrap()
            .contains("inventory incomplete")
    );
    for (path, bytes) in published {
        assert_eq!(fs::read(root.join(path)).unwrap(), bytes);
    }
    refreshed.assert();
    downloaded.assert();
}

#[test]
fn export_snapshot_uses_current_healthy_memberships_and_preserves_raw_bytes() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let key = Key::generate();
    let mut favorites = collection(5, "Favorites", &key);
    favorites["type"] = json!("favorites");
    listing(
        &mut server,
        json!([
            collection(1, "First", &key),
            collection(2, "Second", &key),
            collection(3, "Third", &key),
            collection(4, "Broken", &key),
            favorites
        ]),
    );
    let (base, encrypted) = source(10, &key, b"shared original", "Photo.jpg");
    let first = public(base.clone(), &key, json!({"caption":"older"}), 10);
    let second = public(base.clone(), &key, json!({"caption":"winner"}), 30);
    let third = public(base.clone(), &key, json!({"caption":"losing tie"}), 30);
    let mut broken = revision(base.clone(), 40);
    broken["metadata"]["encryptedData"] = json!("invalid ciphertext");
    let mut invalid = Vec::new();
    for (id, bytes) in [(11, b"\xff\0{".as_slice()), (12, b"{broken".as_slice())] {
        let (mut file, _) = source(id, &key, b"unused", "Invalid.jpg");
        let encrypted = blob::encrypt(bytes, &file_key(&file, &key)).unwrap();
        file["metadata"] = json!({"encryptedData":b64::encode(&encrypted.encrypted_data),"decryptionHeader":b64::encode(encrypted.decryption_header.as_bytes())});
        invalid.push(revision(file, 50));
    }
    page(&mut server, 1, 0, json!([first]), false).create();
    page(&mut server, 2, 0, json!([second]), false).create();
    page(&mut server, 3, 0, json!([third]), false).create();
    page(
        &mut server,
        4,
        0,
        json!([broken, invalid[0], invalid[1]]),
        false,
    )
    .create();
    let favorite_page = page(&mut server, 5, 0, json!([base]), false)
        .expect(1)
        .create();
    let downloaded = download(&mut server, 10, &encrypted, 1);
    let destination = tempfile::tempdir().unwrap();
    let root = destination.path().join("photos");
    let result = run(&home, &root, &[], false);
    assert_eq!(
        result["copies"],
        json!({"expected":7,"completed":4,"pending":3})
    );
    for folder in ["First", "Second", "Third", "Favorites"] {
        let record = read_json(&root.join(format!("{folder}/metadata/Photo.jpg.json")));
        assert_eq!(record["description"], "winner");
        assert_eq!(record["favorited"], true);
    }
    let state = export_database(&home);
    for table in ["sources", "album_sources"] {
        for action in ["INSERT", "UPDATE", "DELETE"] {
            state.execute_batch(&format!(
                "CREATE TRIGGER unchanged_{table}_{action} AFTER {action} ON {table} BEGIN SELECT RAISE(ABORT,'unchanged snapshot write'); END;",
            )).unwrap();
        }
    }
    let unchanged = run(&home, &root, &[], false);
    assert_eq!(unchanged["copies"], result["copies"]);
    assert_eq!(
        unchanged["changes"],
        json!({"exported":0,"metadataUpdated":0,"renamed":0,"retained":0})
    );
    for table in ["sources", "album_sources"] {
        for action in ["INSERT", "UPDATE", "DELETE"] {
            state
                .execute_batch(&format!("DROP TRIGGER unchanged_{table}_{action};"))
                .unwrap();
        }
    }
    let untouched = root.join("Second/metadata/Photo.jpg.json");
    let before = (
        fs::read(&untouched).unwrap(),
        fs::metadata(&untouched).unwrap().modified().unwrap(),
    );
    run(&home, &root, &["--album", "First"], true);
    assert_eq!(
        read_json(&root.join("First/metadata/Photo.jpg.json"))["description"],
        "older"
    );
    assert_eq!(
        (
            fs::read(&untouched).unwrap(),
            fs::metadata(&untouched).unwrap().modified().unwrap()
        ),
        before
    );
    run(&home, &root, &["--album", "Broken"], false);
    let replica = database(&home);
    for (id, bytes) in [(11, b"\xff\0{".as_slice()), (12, b"{broken".as_slice())] {
        let raw = record(&replica, 4, id);
        assert_eq!(
            b64::decode(raw["documents"]["original"].as_str().unwrap()).unwrap(),
            bytes
        );
    }
    favorite_page.assert();
    downloaded.assert();
}

#[test]
fn export_keeps_latest_deleted_album_selector_without_rewriting_retained_history() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let key = Key::generate();
    let albums = listing(&mut server, json!([collection(1, "Family", &key)]));
    let (gone, gone_bytes) = source(10, &key, b"gone", "Gone.jpg");
    let (kept, kept_bytes) = source(11, &key, b"kept", "Kept.jpg");
    page(&mut server, 1, 0, json!([gone, kept]), false).create();
    download(&mut server, 10, &gone_bytes, 1);
    download(&mut server, 11, &kept_bytes, 1);
    let destination = tempfile::tempdir().unwrap();
    let root = destination.path().join("photos");
    run(&home, &root, &[], true);
    albums.remove();
    let albums = listing(
        &mut server,
        json!([revision(collection(1, "Family", &key), 40)]),
    );
    page(&mut server, 1, 10, json!([removed(gone, 30)]), false).create();
    run(&home, &root, &[], true);
    let history = root.join("Trash/Family/metadata.json");
    let retained = (
        fs::read(&history).unwrap(),
        fs::metadata(&history).unwrap().modified().unwrap(),
    );
    albums.remove();
    let travel = revision(collection(1, "Travel", &key), 50);
    let albums = listing(&mut server, json!([travel]));
    page(&mut server, 1, 30, json!([]), false).create();
    run(&home, &root, &[], true);
    fs::write(root.join("Travel/notes.txt"), b"local addition").unwrap();
    albums.remove();
    let mut deleted = revision(travel, 60);
    deleted["isDeleted"] = json!(true);
    let albums = listing(&mut server, json!([deleted]));
    run(&home, &root, &["--album", "Travel"], true);
    assert_eq!(
        fs::read(root.join("Trash/Family/Gone.jpg")).unwrap(),
        b"gone"
    );
    assert_eq!(
        fs::read(root.join("Trash/Family/Kept.jpg")).unwrap(),
        b"kept"
    );
    assert_eq!(
        (
            fs::read(&history).unwrap(),
            fs::metadata(&history).unwrap().modified().unwrap()
        ),
        retained
    );
    run(&home, &root, &["--album", "Travel"], true);
    run(&home, &root, &["--album", "1"], true);
    albums.remove();
    listing(
        &mut server,
        json!([revision(collection(2, "Travel", &key), 70)]),
    );
    page(&mut server, 2, 0, json!([]), false).create();
    assert_eq!(run(&home, &root, &["--album", "2"], false)["conflicts"], 1);
    assert_eq!(
        fs::read(root.join("Travel/notes.txt")).unwrap(),
        b"local addition"
    );
    assert!(!root.join("Travel-1").exists());
}

#[test]
fn export_discards_failed_downloads_and_services_other_albums() {
    for delete_album in [false, true] {
        let mut server = mockito::Server::new();
        let home = TestHome::new();
        home.seed(&server.url());
        let key = Key::generate();
        let albums = listing(
            &mut server,
            json!([collection(1, "First", &key), collection(2, "Second", &key)]),
        );
        let empty = page(&mut server, 1, 0, json!([]), false).create();
        let second_empty = page(&mut server, 2, 0, json!([]), false).create();
        let destination = tempfile::tempdir().unwrap();
        let root = destination.path().join("photos");
        run(&home, &root, &["-j", "1"], true);
        fs::write(root.join("First/Blocked.jpg"), b"unrelated").unwrap();
        albums.remove();
        empty.remove();
        let albums = listing(
            &mut server,
            json!([revision(collection(1, "First", &key), 40)]),
        );
        let (file, bytes) = source(10, &key, b"staged", "Blocked.jpg");
        let file = revision(file, 30);
        page(&mut server, 1, 0, json!([file]), false).create();
        let staged = download(&mut server, 10, &bytes, 1);
        assert_eq!(run(&home, &root, &["-j", "1"], false)["conflicts"], 1);
        let db = export_database(&home);
        assert_eq!(count(&db, "SELECT count(*) FROM temporaries"), 0);
        run(&home, &root, &["--album", "Second", "-j", "1"], true);
        assert_eq!(count(&db, "SELECT count(*) FROM pending WHERE file=10"), 1);
        albums.remove();
        second_empty.remove();
        let mut first = revision(collection(1, "First", &key), 60);
        if delete_album {
            first["isDeleted"] = json!(true);
        }
        listing(
            &mut server,
            json!([first, revision(collection(2, "Second", &key), 60)]),
        );
        if !delete_album {
            page(&mut server, 1, 30, json!([removed(file, 50)]), false).create();
        }
        let (new_file, new_bytes) = source(20, &key, b"new download", "New.jpg");
        page(&mut server, 2, 0, json!([revision(new_file, 50)]), false).create();
        let downloaded = download(&mut server, 20, &new_bytes, 1);
        let result = run(&home, &root, &["-j", "1"], true);
        assert_eq!(
            result["copies"],
            json!({"expected":1,"completed":1,"pending":0})
        );
        assert_eq!(count(&db, "SELECT count(*) FROM temporaries"), 0);
        assert_eq!(count(&db, "SELECT count(*) FROM pending"), 0);
        assert_eq!(
            fs::read(root.join("Second/New.jpg")).unwrap(),
            b"new download"
        );
        assert_eq!(
            fs::read(root.join("First/Blocked.jpg")).unwrap(),
            b"unrelated"
        );
        if delete_album {
            assert_eq!(
                read_json(&root.join("Trash/First/metadata.json"))["ente"]["albumID"],
                "1"
            );
        }
        staged.assert();
        downloaded.assert();
    }
}

#[test]
fn export_releases_replaced_and_cancelled_pending_names() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let key = Key::generate();
    let mut albums = listing(&mut server, json!([collection(1, "First", &key)]));
    let (base, bytes) = source(10, &key, b"original", "Original.jpg");
    page(&mut server, 1, 0, json!([base]), false).create();
    let downloaded = download(&mut server, 10, &bytes, 1);
    let destination = tempfile::tempdir().unwrap();
    let root = destination.path().join("photos");
    run(&home, &root, &[], true);
    let db = export_database(&home);
    for name in ["Blocked.jpg", "Another.jpg"] {
        fs::write(root.join("First").join(name), b"unrelated").unwrap();
    }
    let mut version = 10;
    for (name, complete) in [
        ("Blocked.jpg", false),
        ("Another.jpg", false),
        ("Original.jpg", true),
        ("Renamed.jpg", true),
        ("RENAMED.jpg", true),
    ] {
        albums.remove();
        albums = listing(
            &mut server,
            json!([revision(collection(1, "First", &key), version + 20)]),
        );
        page(
            &mut server,
            1,
            version,
            json!([public(
                base.clone(),
                &key,
                json!({"editedName":name}),
                version + 10
            )]),
            false,
        )
        .create();
        version += 10;
        run(&home, &root, &[], complete);
        if complete {
            assert_eq!(
                fs::read(root.join("First").join(name)).unwrap(),
                b"original"
            );
        } else {
            let pending: String = db
                .query_row(
                    "SELECT folded1 FROM pending WHERE album=1 AND file=10",
                    [],
                    |r| r.get(0),
                )
                .unwrap();
            assert_eq!(pending, name.to_lowercase());
        }
    }
    for name in ["Blocked album", "Another album"] {
        fs::create_dir(root.join(name)).unwrap();
        fs::write(root.join(name).join("notes"), b"unrelated").unwrap();
    }
    page(&mut server, 1, version, json!([]), false).create();
    for (index, name) in ["Blocked album", "Another album", "First"]
        .into_iter()
        .enumerate()
    {
        albums.remove();
        albums = listing(
            &mut server,
            json!([revision(collection(1, name, &key), 100 + index as i64)]),
        );
        run(&home, &root, &[], name == "First");
        if name != "First" {
            let pending: String = db
                .query_row(
                    "SELECT folded1 FROM pending WHERE owner='active:1'",
                    [],
                    |r| r.get(0),
                )
                .unwrap();
            assert_eq!(pending, name.to_lowercase());
        }
    }
    albums.remove();
    listing(
        &mut server,
        json!([revision(collection(1, "First", &key), 120)]),
    );
    let (new_file, new_bytes) = source(11, &key, b"new original", "Original.jpg");
    page(
        &mut server,
        1,
        version,
        json!([revision(new_file, 110)]),
        false,
    )
    .create();
    let new_download = download(&mut server, 11, &new_bytes, 1);
    run(&home, &root, &[], true);
    assert_eq!(
        fs::read(root.join("First/Original.jpg")).unwrap(),
        b"new original"
    );
    assert_eq!(
        fs::read(root.join("First/RENAMED.jpg")).unwrap(),
        b"original"
    );
    assert!(!root.join("First/Original-1.jpg").exists());
    downloaded.assert();
    new_download.assert();
}

#[test]
fn export_keeps_live_names_occupied_until_every_component_and_sidecar_moves() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let key = Key::generate();
    let albums = listing(&mut server, json!([collection(1, "Live", &key)]));
    let mut zip = zip::ZipWriter::new(std::io::Cursor::new(Vec::new()));
    for (name, bytes) in [
        ("image.heic", b"image".as_slice()),
        ("video.mov", b"video".as_slice()),
    ] {
        zip.start_file(
            name,
            zip::write::SimpleFileOptions::default()
                .compression_method(zip::CompressionMethod::Stored),
        )
        .unwrap();
        zip.write_all(bytes).unwrap();
    }
    let archive = zip.finish().unwrap().into_inner();
    let (mut base, bytes) = source(10, &key, &archive, "Motion.heic");
    let data = json!({"title":"Motion.heic","fileType":2,"creationTime":1_700_000_000_123_456i64,"hash":format!("{}:{}",b64::encode(&hash::hash(b"image",Some(64),None).unwrap()),b64::encode(&hash::hash(b"video",Some(64),None).unwrap()))});
    let encrypted = blob::encrypt_json(&data, &file_key(&base, &key)).unwrap();
    base["metadata"] = json!({"encryptedData":b64::encode(&encrypted.encrypted_data),"decryptionHeader":b64::encode(encrypted.decryption_header.as_bytes())});
    page(&mut server, 1, 0, json!([base]), false).create();
    let downloaded = download(&mut server, 10, &bytes, 1);
    let destination = tempfile::tempdir().unwrap();
    let root = destination.path().join("photos");
    run(&home, &root, &[], true);
    let adopted = TestHome::new();
    adopted.seed(&server.url());
    run(&adopted, &root, &["--adopt"], true);
    let db = export_database(&adopted);
    db.execute_batch(
        "CREATE TRIGGER stop_move BEFORE UPDATE ON pending WHEN json_extract(old.action,'$.Move.source.name')='Motion.heic' AND new.action='null' BEGIN SELECT RAISE(ABORT,'stop after image move'); END;",
    )
    .unwrap();
    albums.remove();
    let albums = listing(
        &mut server,
        json!([revision(collection(1, "Live", &key), 40)]),
    );
    let renamed = public(base.clone(), &key, json!({"editedName":"Renamed.heic"}), 30);
    page(&mut server, 1, 10, json!([renamed]), false).create();
    run_failure(&adopted, &root, &[], "stop after image move");
    assert_eq!(fs::read(root.join("Live/Renamed.heic")).unwrap(), b"image");
    assert_eq!(fs::read(root.join("Live/Motion.mov")).unwrap(), b"video");
    db.execute_batch("DROP TRIGGER stop_move;").unwrap();
    fs::write(root.join("Live/Renamed.mov"), b"unrelated").unwrap();
    albums.remove();
    let albums = listing(
        &mut server,
        json!([revision(collection(1, "Live", &key), 60)]),
    );
    let (contender, contender_bytes) = source(11, &key, b"contender", "Motion.heic");
    page(&mut server, 1, 30, json!([revision(contender, 50)]), false).create();
    let new_download = download(&mut server, 11, &contender_bytes, 1);
    run(&adopted, &root, &[], false);
    assert_eq!(
        fs::read(root.join("Live/Motion-1.heic")).unwrap(),
        b"contender"
    );
    fs::remove_file(root.join("Live/Renamed.mov")).unwrap();
    run(&adopted, &root, &[], true);
    albums.remove();
    let albums = listing(
        &mut server,
        json!([revision(collection(1, "Live", &key), 80)]),
    );
    let (later, later_bytes) = source(12, &key, b"new original", "Motion.heic");
    page(&mut server, 1, 50, json!([revision(later, 70)]), false).create();
    let later_download = download(&mut server, 12, &later_bytes, 1);
    run(&adopted, &root, &[], true);
    assert_component(&root, "Live", "Motion.heic", b"new original");
    assert_eq!(
        read_json(&root.join("Live/metadata/Motion.heic.json"))["ente"]["fileID"],
        "12"
    );
    assert_eq!(
        fs::read(root.join("Live/Motion-1.heic")).unwrap(),
        b"contender"
    );
    db.execute_batch(
        "CREATE TRIGGER stop_sidecar BEFORE UPDATE ON pending WHEN json_extract(old.action,'$.Remove.location.name')='metadata/Renamed.mov.json' AND new.action='null' BEGIN SELECT RAISE(ABORT,'stop after final sidecar removal'); END;",
    )
    .unwrap();
    albums.remove();
    listing(
        &mut server,
        json!([revision(collection(1, "Live", &key), 100)]),
    );
    page(
        &mut server,
        1,
        70,
        json!([public(base, &key, json!({"editedName":"RENAMED.heic"}), 90)]),
        false,
    )
    .create();
    run_failure(&adopted, &root, &[], "stop after final sidecar removal");
    db.execute_batch("DROP TRIGGER stop_sidecar;").unwrap();
    assert!(!root.join("Live/metadata/Renamed.mov.json").exists());
    assert_eq!(
        count(
            &db,
            "SELECT count(*) FROM json_records WHERE name='metadata/Renamed.mov.json' AND hash IS NOT NULL"
        ),
        1
    );
    fs::remove_file(root.join("Live/metadata/RENAMED.heic.json")).unwrap();
    run(&adopted, &root, &[], true);
    for (name, bytes) in [
        ("RENAMED.heic", b"image".as_slice()),
        ("RENAMED.mov", b"video".as_slice()),
    ] {
        assert_eq!(fs::read(root.join("Live").join(name)).unwrap(), bytes);
        assert_eq!(
            read_json(&root.join(format!("Live/metadata/{name}.json")))["title"],
            name
        );
    }
    downloaded.assert();
    new_download.assert();
    later_download.assert();
}

#[test]
fn export_stops_dispatch_and_joins_workers_after_a_fatal_transfer() {
    use std::sync::{Mutex, mpsc};
    use std::time::Duration;

    let mut server = mockito::Server::new();
    let mut slow_server = mockito::Server::new();
    let mut fatal_server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let key = Key::generate();
    listing(&mut server, json!([collection(1, "First", &key)]));
    let original = vec![73; 8 * 1024 * 1024];
    let (slow_file, slow_bytes) = source(10, &key, &original, "Slow.jpg");
    let (fatal_file, fatal_bytes) = source(11, &key, b"recovered", "Failed.jpg");
    let (next_file, next_bytes) = source(12, &key, b"next", "Next.jpg");
    page(
        &mut server,
        1,
        0,
        json!([slow_file, fatal_file, next_file]),
        false,
    )
    .create();
    let (started, reading) = mpsc::channel();
    let (fatal_release, fatal_wait) = mpsc::channel::<()>();
    let fatal_wait = Mutex::new(fatal_wait);
    let (release, held) = mpsc::channel::<()>();
    let held = Mutex::new(held);
    let response_bytes = slow_bytes.clone();
    let slow = slow_server
        .mock("GET", "/slow")
        .with_chunked_body(move |writer| {
            writer.write_all(&response_bytes[..64 * 1024])?;
            let _ = started.send(());
            let _ = held.lock().unwrap().recv();
            writer.write_all(&response_bytes[64 * 1024..])
        })
        .create();
    let fatal_response = fatal_server
        .mock("GET", "/fatal")
        .with_status(401)
        .with_body_from_request(move |_| {
            let _ = fatal_wait.lock().unwrap().recv();
            b"unauthorized".to_vec()
        })
        .create();
    let slow_url = server
        .mock("GET", "/files/download/v3/10")
        .with_body(json!({"url":format!("{}/slow",slow_server.url())}).to_string())
        .create();
    let fatal_url = server
        .mock("GET", "/files/download/v3/11")
        .with_body(json!({"url":format!("{}/fatal",fatal_server.url())}).to_string())
        .create();
    let undispatched = server
        .mock("GET", "/files/download/v3/12")
        .with_status(500)
        .expect(0)
        .create();
    let destination = tempfile::tempdir().unwrap();
    let root = destination.path().join("photos");
    let child = ExportChild::spawn(
        home.command(&[
            "photos",
            "export",
            root.to_str().unwrap(),
            "-j",
            "2",
            "--json",
        ])
        .env("TOKIO_WORKER_THREADS", "1"),
    )
    .unwrap();
    reading
        .recv_timeout(Duration::from_secs(60))
        .expect("the independent download never started");
    drop(fatal_release);
    let output = child.wait_with_output().unwrap();
    drop(release);
    let error = failure(&output);
    assert!(error.contains("401"));
    assert!(error.contains("cancelled"), "{error}");
    for line in error.lines().filter(|line| line.contains("401")) {
        assert_eq!(line.matches("401").count(), 1, "{line}");
    }
    assert_eq!(
        serde_json::from_slice::<Value>(&output.stdout).unwrap()["complete"],
        false
    );
    undispatched.assert();
    let lock = fs::File::options()
        .read(true)
        .write(true)
        .open(root.join("export.json"))
        .unwrap();
    lock.try_lock().unwrap();
    assert_eq!(fs::read_dir(root.join("First")).unwrap().count(), 1);
    assert!(!root.join("First/Slow.jpg").exists());
    drop(lock);
    slow_url.remove();
    fatal_url.remove();
    undispatched.remove();
    slow.assert();
    fatal_response.assert();
    download(&mut server, 10, &slow_bytes, 1);
    download(&mut server, 11, &fatal_bytes, 1);
    download(&mut server, 12, &next_bytes, 1);
    run(&home, &root, &["-j", "2"], true);
    assert_eq!(fs::read(root.join("First/Slow.jpg")).unwrap(), original);
    assert_eq!(
        fs::read(root.join("First/Failed.jpg")).unwrap(),
        b"recovered"
    );
    assert_eq!(fs::read(root.join("First/Next.jpg")).unwrap(), b"next");
}

#[test]
fn export_reports_shared_store_failure_and_joins_workers() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let key = Key::generate();
    let albums = listing(&mut server, json!([collection(1, "First", &key)]));
    let empty = page(&mut server, 1, 0, json!([]), false).create();
    let destination = tempfile::tempdir().unwrap();
    let root = destination.path().join("photos");
    run(&home, &root, &[], true);
    let db = export_database(&home);
    db.execute_batch(
        "CREATE TRIGGER fail_component BEFORE INSERT ON components BEGIN SELECT RAISE(ABORT,'injected shared store failure'); END;",
    )
    .unwrap();
    albums.remove();
    empty.remove();
    listing(
        &mut server,
        json!([revision(collection(1, "First", &key), 30)]),
    );
    let (file, bytes) = source(10, &key, b"original", "Original.jpg");
    page(&mut server, 1, 0, json!([file]), false).create();
    let downloaded = download(&mut server, 10, &bytes, 1);
    let child = ExportChild::spawn(
        home.command(&["photos", "export", root.to_str().unwrap(), "--json"])
            .env("TOKIO_WORKER_THREADS", "1"),
    )
    .unwrap();
    let output = child.wait_with_output().unwrap();
    assert!(failure(&output).contains("injected shared store failure"));
    assert_eq!(
        serde_json::from_slice::<Value>(&output.stdout).unwrap()["complete"],
        false
    );
    let lock = fs::OpenOptions::new()
        .read(true)
        .write(true)
        .open(root.join("export.json"))
        .unwrap();
    lock.try_lock().unwrap();
    drop(lock);
    db.execute_batch("DROP TRIGGER fail_component;").unwrap();
    run(&home, &root, &[], true);
    assert_eq!(
        fs::read(root.join("First/Original.jpg")).unwrap(),
        b"original"
    );
    downloaded.assert();
}

#[test]
fn export_cancels_pending_retention_when_selected_membership_returns() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let key = Key::generate();
    let mut albums = listing(&mut server, json!([collection(1, "First", &key)]));
    let (base, bytes) = source(10, &key, b"original", "Original.jpg");
    page(&mut server, 1, 0, json!([base]), false).create();
    let downloaded = download(&mut server, 10, &bytes, 1);
    let destination = tempfile::tempdir().unwrap();
    let root = destination.path().join("photos");
    run(&home, &root, &[], true);
    let db = export_database(&home);
    fs::create_dir_all(root.join("Trash/First")).unwrap();
    fs::write(root.join("Trash/First/notes"), b"unrelated album").unwrap();
    let mut version = 10;
    for (step, remove, complete) in [
        (0, true, false),
        (1, false, true),
        (2, true, true),
        (3, false, true),
        (4, true, false),
        (5, false, true),
    ] {
        if step == 2 {
            fs::remove_file(root.join("Trash/First/notes")).unwrap();
            fs::remove_dir(root.join("Trash/First")).unwrap();
        }
        if step == 4 {
            fs::write(root.join("Trash/First/Original-1.jpg"), b"unrelated file").unwrap();
        }
        albums.remove();
        albums = listing(
            &mut server,
            json!([revision(collection(1, "First", &key), version + 30)]),
        );
        let next = if remove {
            removed(base.clone(), version + 20)
        } else {
            revision(base.clone(), version + 20)
        };
        page(&mut server, 1, version, json!([next]), false).create();
        version += 20;
        run(&home, &root, &[], complete);
        if !complete {
            assert_eq!(count(&db, "SELECT count(*) FROM pending"), 1);
            assert_eq!(
                count(&db, "SELECT count(*) FROM pending WHERE retained=1"),
                1
            );
            assert_eq!(
                fs::read(root.join("First/Original.jpg")).unwrap(),
                b"original"
            );
        }
        if !remove {
            assert_eq!(count(&db, "SELECT count(*) FROM pending"), 0);
            assert_eq!(
                count(&db, "SELECT count(*) FROM pending WHERE retained=1"),
                0
            );
            assert_eq!(
                fs::read(root.join("First/Original.jpg")).unwrap(),
                b"original"
            );
        }
    }
    assert_eq!(
        fs::read(root.join("Trash/First/Original.jpg")).unwrap(),
        b"original"
    );
    assert_eq!(
        fs::read(root.join("Trash/First/Original-1.jpg")).unwrap(),
        b"unrelated file"
    );
    downloaded.assert();
}

#[test]
fn export_preserves_pending_names_when_a_later_source_refresh_is_fatal() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let key = Key::generate();
    let albums = listing(
        &mut server,
        json!([collection(1, "First", &key), collection(2, "Second", &key)]),
    );
    let first_empty = page(&mut server, 1, 0, json!([]), false).create();
    page(&mut server, 2, 0, json!([]), false).create();
    let destination = tempfile::tempdir().unwrap();
    let root = destination.path().join("photos");
    run(&home, &root, &["-j", "1"], true);
    fs::write(root.join("First/Blocked.jpg"), b"unrelated").unwrap();
    albums.remove();
    first_empty.remove();
    let albums = listing(
        &mut server,
        json!([
            revision(collection(1, "First", &key), 40),
            collection(2, "Second", &key)
        ]),
    );
    let (file, bytes) = source(10, &key, b"completed original", "Blocked.jpg");
    page(&mut server, 1, 0, json!([revision(file, 30)]), false).create();
    let downloaded = download(&mut server, 10, &bytes, 2);
    run(&home, &root, &["-j", "1"], false);
    let db = export_database(&home);
    let saved: String = db
        .query_row("SELECT name1 FROM pending WHERE file=10", [], |r| r.get(0))
        .unwrap();
    assert_eq!(count(&db, "SELECT count(*) FROM temporaries"), 0);
    albums.remove();
    listing(
        &mut server,
        json!([
            revision(collection(1, "First", &key), 60),
            revision(collection(2, "Second", &key), 60)
        ]),
    );
    let first_success = page(&mut server, 1, 30, json!([]), false)
        .expect(1)
        .create();
    let second_fatal = page(&mut server, 2, 0, json!([]), false)
        .with_status(401)
        .expect(1)
        .create();
    let output = home.run(&[
        "photos",
        "export",
        root.to_str().unwrap(),
        "-j",
        "1",
        "--json",
    ]);
    assert!(failure(&output).contains("401"));
    assert_eq!(
        serde_json::from_slice::<Value>(&output.stdout).unwrap()["complete"],
        false
    );
    first_success.assert();
    second_fatal.assert();
    assert_eq!(
        fs::read(root.join("First/Blocked.jpg")).unwrap(),
        b"unrelated"
    );
    assert_eq!(
        db.query_row("SELECT name1 FROM pending WHERE file=10", [], |r| r
            .get::<_, String>(0))
            .unwrap(),
        saved
    );
    second_fatal.remove();
    page(&mut server, 2, 0, json!([]), false).create();
    fs::remove_file(root.join("First/Blocked.jpg")).unwrap();
    run(&home, &root, &["-j", "1"], true);
    assert_eq!(count(&db, "SELECT count(*) FROM temporaries"), 0);
    assert_eq!(
        fs::read(root.join("First/Blocked.jpg")).unwrap(),
        b"completed original"
    );
    downloaded.assert();
}

fn original_fixture(
    key: &Key,
    bytes: &[u8],
    live: bool,
    hashed: bool,
    version: i64,
) -> (Value, Vec<u8>) {
    let name = if live { "Motion.heic" } else { "Photo.jpg" };
    let original = if live {
        let mut zip = zip::ZipWriter::new(std::io::Cursor::new(Vec::new()));
        for name in ["image.heic", "video.mov"] {
            zip.start_file(
                name,
                zip::write::SimpleFileOptions::default()
                    .compression_method(zip::CompressionMethod::Stored),
            )
            .unwrap();
            zip.write_all(bytes).unwrap();
        }
        zip.finish().unwrap().into_inner()
    } else {
        bytes.to_vec()
    };
    let (mut remote, encrypted) = source(10, key, &original, name);
    let mut metadata = json!({"title":name,"fileType":if live {2} else {0},"creationTime":1_700_000_000_123_456i64});
    if hashed {
        let hash = b64::encode(&hash::hash(bytes, Some(64), None).unwrap());
        metadata["hash"] = json!(if live { format!("{hash}:{hash}") } else { hash });
    }
    let metadata = blob::encrypt_json(&metadata, &file_key(&remote, key)).unwrap();
    remote["metadata"] = json!({"encryptedData":b64::encode(&metadata.encrypted_data),"decryptionHeader":b64::encode(metadata.decryption_header.as_bytes())});
    (revision(remote, version), encrypted)
}

fn assert_component(root: &Path, folder: &str, name: &str, bytes: &[u8]) {
    assert_eq!(fs::read(root.join(folder).join(name)).unwrap(), bytes);
    let record = read_json(&root.join(folder).join(format!("metadata/{name}.json")));
    let component = record["ente"]["components"]
        .as_array()
        .unwrap()
        .iter()
        .find(|component| component["path"] == name)
        .unwrap();
    assert_eq!(component["size"], bytes.len());
    assert_eq!(
        component["hash"],
        b64::encode(&hash::hash(bytes, Some(64), None).unwrap())
    );
}

#[test]
fn export_interrupted_replacement_never_binds_old_bytes_to_new_verification() {
    for (live, hashed) in [(false, true), (false, false), (true, true)] {
        for remove_after in [false, true] {
            let mut server = mockito::Server::new();
            let home = TestHome::new();
            home.seed(&server.url());
            let key = Key::generate();
            let albums = listing(
                &mut server,
                json!([collection(1, "First", &key), collection(2, "Second", &key)]),
            );
            let (old, bytes) = original_fixture(&key, b"old", live, hashed, 10);
            for album in [1, 2] {
                page(&mut server, album, 0, json!([old]), false).create();
            }
            let fetched = download(&mut server, 10, &bytes, 1);
            let destination = tempfile::tempdir().unwrap();
            let root = destination.path().join("photos");
            run(&home, &root, &[], true);
            fetched.assert();
            fetched.remove();
            let name = if live { "Motion.heic" } else { "Photo.jpg" };
            let before = fs::metadata(root.join("Second").join(name))
                .unwrap()
                .modified()
                .unwrap();
            let db = export_database(&home);
            db.execute_batch(
                "CREATE TRIGGER stop_second BEFORE INSERT ON pending WHEN new.album=2 AND json_type(new.action,'$.Publish.output.Media') IS NOT NULL BEGIN SELECT RAISE(ABORT,'stop before second publication'); END;",
            )
            .unwrap();
            albums.remove();
            let albums = listing(
                &mut server,
                json!([
                    revision(collection(1, "First", &key), 40),
                    revision(collection(2, "Second", &key), 40)
                ]),
            );
            let (new, bytes) = original_fixture(&key, b"new", live, hashed, 30);
            for album in [1, 2] {
                page(&mut server, album, 10, json!([new]), false).create();
            }
            let fetched = download(&mut server, 10, &bytes, 1);
            run_failure(&home, &root, &[], "stop before second publication");
            assert_eq!(fs::read(root.join("First").join(name)).unwrap(), b"new");
            assert_eq!(fs::read(root.join("Second").join(name)).unwrap(), b"old");
            assert_eq!(
                fs::metadata(root.join("Second").join(name))
                    .unwrap()
                    .modified()
                    .unwrap(),
                before
            );
            assert_component(&root, "Second", name, b"old");
            if live {
                assert_component(&root, "Second", "Motion.mov", b"old");
            }
            db.execute_batch("DROP TRIGGER stop_second;").unwrap();
            if remove_after {
                albums.remove();
                listing(
                    &mut server,
                    json!([
                        revision(collection(1, "First", &key), 60),
                        revision(collection(2, "Second", &key), 60)
                    ]),
                );
                for album in [1, 2] {
                    page(
                        &mut server,
                        album,
                        30,
                        json!([removed(new.clone(), 50)]),
                        false,
                    )
                    .create();
                }
                run(&home, &root, &[], true);
                for (folder, bytes) in [("Trash/First", b"new"), ("Trash/Second", b"old")] {
                    assert_component(&root, folder, name, bytes);
                    if live {
                        assert_component(&root, folder, "Motion.mov", bytes);
                    }
                }
                fs::remove_file(root.join("Trash/First").join(name)).unwrap();
                if live {
                    fs::remove_file(root.join("Trash/First/Motion.mov")).unwrap();
                }
                fetched.assert();
                fetched.remove();
                listing(
                    &mut server,
                    json!([revision(collection(3, "Restored", &key), 80)]),
                );
                let restored = revision(if hashed { old.clone() } else { new.clone() }, 70);
                page(&mut server, 3, 0, json!([restored]), false).create();
                let restore_get = download(&mut server, 10, &bytes, usize::from(!hashed));
                run(&home, &root, &["--album", "Restored"], true);
                let expected = if hashed { b"old" } else { b"new" };
                assert_component(&root, "Restored", name, expected);
                if live {
                    assert_component(&root, "Restored", "Motion.mov", expected);
                }
                restore_get.assert();
            } else {
                run(&home, &root, &[], true);
                for folder in ["First", "Second"] {
                    assert_component(&root, folder, name, b"new");
                    if live {
                        assert_component(&root, folder, "Motion.mov", b"new");
                    }
                }
            }
            if !remove_after {
                fetched.assert();
            }
        }
    }
}

#[test]
#[cfg(target_os = "linux")]
fn export_adoption_ignores_unrelated_non_utf8_entries_but_rejects_claimed_paths() {
    use std::os::unix::ffi::OsStringExt;
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let key = Key::generate();
    listing(&mut server, json!([collection(1, "First", &key)]));
    let (file, bytes) = original_fixture(&key, b"original", false, true, 10);
    page(&mut server, 1, 0, json!([file]), false).create();
    let fetched = download(&mut server, 10, &bytes, 1);
    let destination = tempfile::tempdir().unwrap();
    let root = destination.path().join("photos");
    run(&home, &root, &[], true);
    let unrelated = root.join(std::ffi::OsString::from_vec(b"note-\xff".to_vec()));
    let directory = root.join(std::ffi::OsString::from_vec(b"folder-\xfe".to_vec()));
    let trash = root
        .join("Trash")
        .join(std::ffi::OsString::from_vec(b"folder-\xfd".to_vec()));
    fs::write(&unrelated, b"unrelated").unwrap();
    for directory in [&directory, &trash] {
        fs::create_dir_all(directory).unwrap();
        fs::write(directory.join("metadata.json"), br#"{"title":"unrelated"}"#).unwrap();
    }
    let adopted = TestHome::new();
    adopted.seed(&server.url());
    run(&adopted, &root, &["--adopt"], true);
    assert_component(&root, "First", "Photo.jpg", b"original");
    assert_eq!(fs::read(&unrelated).unwrap(), b"unrelated");
    fs::copy(
        root.join("First/metadata.json"),
        directory.join("metadata.json"),
    )
    .unwrap();
    let rejected = TestHome::new();
    rejected.seed(&server.url());
    let output = rejected.run(&[
        "photos",
        "export",
        root.to_str().unwrap(),
        "--adopt",
        "--json",
    ]);
    assert!(failure(&output).contains("claimed Ente album path is not UTF-8"));
    assert_component(&root, "First", "Photo.jpg", b"original");
    fetched.assert();
}

#[test]
fn export_missing_move_endpoints_require_active_repair_or_retained_recovery() {
    for retaining in [false, true] {
        let mut server = mockito::Server::new();
        let home = TestHome::new();
        home.seed(&server.url());
        let key = Key::generate();
        let albums = listing(&mut server, json!([collection(1, "First", &key)]));
        let (file, bytes) = original_fixture(&key, b"original", false, true, 10);
        page(&mut server, 1, 0, json!([file]), false).create();
        let fetched = download(&mut server, 10, &bytes, if retaining { 1 } else { 2 });
        let destination = tempfile::tempdir().unwrap();
        let root = destination.path().join("photos");
        run(&home, &root, &[], true);
        let db = export_database(&home);
        db.execute_batch(
            "CREATE TRIGGER stop_move BEFORE UPDATE ON pending WHEN json_extract(old.action,'$.Move.source.name')='Photo.jpg' AND new.action='null' BEGIN SELECT RAISE(ABORT,'stop after media move'); END;",
        )
        .unwrap();
        albums.remove();
        listing(
            &mut server,
            json!([revision(collection(1, "First", &key), 40)]),
        );
        let changed = if retaining {
            removed(file, 30)
        } else {
            public(file, &key, json!({"editedName":"Renamed.jpg"}), 30)
        };
        page(&mut server, 1, 10, json!([changed]), false).create();
        run_failure(&home, &root, &[], "stop after media move");
        let moved = if retaining {
            "Trash/First/Photo.jpg"
        } else {
            "First/Renamed.jpg"
        };
        assert_eq!(fs::read(root.join(moved)).unwrap(), b"original");
        fs::remove_file(root.join(moved)).unwrap();
        assert!(!root.join("First/Photo.jpg").exists());
        db.execute_batch("DROP TRIGGER stop_move;").unwrap();
        if retaining {
            run(&home, &root, &[], false);
            assert!(!root.join("Trash/First/metadata/Photo.jpg.json").exists());
            fs::write(root.join(moved), b"original").unwrap();
            run(&home, &root, &[], true);
            assert_component(&root, "Trash/First", "Photo.jpg", b"original");
        } else {
            run(&home, &root, &[], true);
            assert_component(&root, "First", "Renamed.jpg", b"original");
        }
        fetched.assert();
    }
}

#[test]
#[cfg(unix)]
fn export_failed_album_move_blocks_retention_until_recovery() {
    use std::os::unix::fs::PermissionsExt;
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let key = Key::generate();
    let albums = listing(
        &mut server,
        json!([
            collection(1, "Family", &key),
            collection(2, "Healthy", &key)
        ]),
    );
    let (file, bytes) = source(10, &key, b"retained", "Photo.jpg");
    let (healthy, healthy_bytes) = source(20, &key, b"healthy", "Good.jpg");
    page(&mut server, 1, 0, json!([file]), false).create();
    page(&mut server, 2, 0, json!([healthy]), false).create();
    let fetched = download(&mut server, 10, &bytes, 1);
    let healthy_get = download(&mut server, 20, &healthy_bytes, 1);
    let destination = tempfile::tempdir().unwrap();
    let root = destination.path().join("photos");
    run(&home, &root, &[], true);
    albums.remove();
    listing(
        &mut server,
        json!([
            revision(collection(1, "Kin", &key), 40),
            revision(collection(2, "Healthy", &key), 40)
        ]),
    );
    page(&mut server, 1, 10, json!([removed(file, 30)]), false).create();
    page(
        &mut server,
        2,
        10,
        json!([public(healthy, &key, json!({"caption":"independent"}), 30)]),
        false,
    )
    .create();
    fs::set_permissions(&root, fs::Permissions::from_mode(0o500)).unwrap();
    let output = home.run(&["photos", "export", root.to_str().unwrap(), "--json"]);
    fs::set_permissions(&root, fs::Permissions::from_mode(0o700)).unwrap();
    failure(&output);
    let result: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(result["complete"], false);
    assert_eq!(result["copies"]["completed"], 1);
    assert_eq!(
        read_json(&root.join("Healthy/metadata/Good.jpg.json"))["description"],
        "independent"
    );
    assert_eq!(
        fs::read(root.join("Family/Photo.jpg")).unwrap(),
        b"retained"
    );
    assert!(!root.join("Trash/Kin/metadata/Photo.jpg.json").exists());
    run(&home, &root, &[], true);
    assert_component(&root, "Trash/Kin", "Photo.jpg", b"retained");
    assert!(!root.join("Kin/Photo.jpg").exists());
    fetched.assert();
    healthy_get.assert();
}

#[test]
fn export_first_publication_requires_ownership_and_recovers_renamed_bytes() {
    for media in [false, true] {
        for after_rename in [false, true] {
            let mut server = mockito::Server::new();
            let home = TestHome::new();
            home.seed(&server.url());
            let key = Key::generate();
            let albums = listing(&mut server, json!([collection(1, "First", &key)]));
            let empty = page(&mut server, 1, 0, json!([]), false).create();
            let destination = tempfile::tempdir().unwrap();
            let root = destination.path().join("photos");
            run(&home, &root, &[], true);
            let db = export_database(&home);
            let output = if media { "Media" } else { "Json" };
            let (operation, record, cleared) = if after_rename {
                ("UPDATE", "old", "AND new.action='null'")
            } else {
                ("INSERT", "new", "")
            };
            db.execute_batch(&format!(
                "CREATE TRIGGER stop_publication BEFORE {operation} ON pending WHEN {record}.file=10 AND json_type({record}.action,'$.Publish.output.{output}') IS NOT NULL {cleared} BEGIN SELECT RAISE(ABORT,'publication interruption'); END;",
            ))
            .unwrap();
            albums.remove();
            empty.remove();
            listing(
                &mut server,
                json!([revision(collection(1, "First", &key), 40)]),
            );
            let (file, bytes) = original_fixture(&key, b"original", false, true, 30);
            page(&mut server, 1, 0, json!([file]), false).create();
            let fetched = download(
                &mut server,
                10,
                &bytes,
                if media && !after_rename { 3 } else { 1 },
            );
            run_failure(&home, &root, &[], "publication interruption");
            assert_eq!(
                count(&db, "SELECT count(*) FROM components"),
                i64::from(!media)
            );
            assert_eq!(
                count(
                    &db,
                    "SELECT count(*) FROM json_records WHERE role!='' AND folder IS NOT NULL"
                ),
                0
            );
            db.execute_batch("DROP TRIGGER stop_publication;").unwrap();
            let path = root.join(if media {
                "First/Photo.jpg"
            } else {
                "First/metadata/Photo.jpg.json"
            });
            if after_rename {
                assert!(path.is_file());
            } else {
                fs::create_dir_all(path.parent().unwrap()).unwrap();
                fs::write(&path, b"unrelated").unwrap();
                assert!(run(&home, &root, &[], false)["conflicts"].as_i64().unwrap() > 0);
                assert_eq!(fs::read(&path).unwrap(), b"unrelated");
                fs::remove_file(&path).unwrap();
            }
            run(&home, &root, &[], true);
            assert_component(&root, "First", "Photo.jpg", b"original");
            fetched.assert();
        }
    }
}

#[test]
fn export_removal_accounts_for_first_media_before_acknowledgement() {
    for (live, after_rename) in [(false, false), (true, false), (false, true), (true, true)] {
        let mut server = mockito::Server::new();
        let home = TestHome::new();
        home.seed(&server.url());
        let key = Key::generate();
        let albums = listing(&mut server, json!([collection(1, "First", &key)]));
        let empty = page(&mut server, 1, 0, json!([]), false).create();
        let destination = tempfile::tempdir().unwrap();
        let root = destination.path().join("photos");
        run(&home, &root, &[], true);
        let db = export_database(&home);
        let role = if live {
            if after_rename { "image" } else { "video" }
        } else {
            "original"
        };
        let (operation, record, cleared) = if after_rename {
            ("UPDATE", "old", "AND new.action='null'")
        } else {
            ("INSERT", "new", "")
        };
        db.execute_batch(&format!(
            "CREATE TRIGGER stop_component BEFORE {operation} ON pending WHEN json_extract({record}.action,'$.Publish.output.Media.role')='{role}' {cleared} BEGIN SELECT RAISE(ABORT,'stop first publication'); END;",
        ))
        .unwrap();
        albums.remove();
        empty.remove();
        let albums = listing(
            &mut server,
            json!([revision(collection(1, "First", &key), 40)]),
        );
        let (file, bytes) = original_fixture(&key, b"original", live, true, 30);
        page(&mut server, 1, 0, json!([file]), false).create();
        let fetched = download(&mut server, 10, &bytes, 1);
        run_failure(&home, &root, &[], "stop first publication");
        assert_eq!(
            count(
                &db,
                "SELECT count(*) FROM json_records WHERE role!='' AND folder IS NOT NULL"
            ),
            0
        );
        if after_rename {
            assert_eq!(count(&db, "SELECT count(*) FROM components"), 0);
            assert_eq!(
                count(
                    &db,
                    "SELECT count(*) FROM json_records WHERE role!='' AND folder IS NULL"
                ),
                if live { 2 } else { 1 }
            );
        }
        let unrelated = root.join(if live {
            "First/Motion.mov"
        } else {
            "First/Photo.jpg"
        });
        if live || !after_rename {
            fs::write(&unrelated, b"unrelated").unwrap();
        }
        db.execute_batch("DROP TRIGGER stop_component;").unwrap();
        albums.remove();
        listing(
            &mut server,
            json!([revision(collection(1, "First", &key), 60)]),
        );
        page(&mut server, 1, 30, json!([removed(file, 50)]), false).create();
        run(&home, &root, &[], true);
        if live || after_rename {
            assert_component(
                &root,
                "Trash/First",
                if live { "Motion.heic" } else { "Photo.jpg" },
                b"original",
            );
        } else {
            assert!(!root.join("Trash/First/metadata/Photo.jpg.json").exists());
        }
        if live {
            assert!(!root.join("Trash/First/Motion.mov").exists());
            assert!(!root.join("Trash/First/metadata/Motion.mov.json").exists());
            assert_eq!(read_json(&root.join("Trash/First/metadata/Motion.heic.json"))["ente"]["components"].as_array().unwrap().len(), 2);
        }
        if live || !after_rename {
            assert_eq!(fs::read(unrelated).unwrap(), b"unrelated");
        }
        fetched.assert();
    }
}

#[test]
fn export_converts_ordinary_and_live_layouts_without_losing_old_originals() {
    for (old_live, adopt) in [(false, false), (true, false), (true, true)] {
        let mut server = mockito::Server::new();
        let original_home = TestHome::new();
        original_home.seed(&server.url());
        let key = Key::generate();
        let albums = listing(&mut server, json!([collection(1, "First", &key)]));
        let (old, old_bytes) = original_fixture(&key, b"old", old_live, true, 10);
        page(&mut server, 1, 0, json!([old]), false).create();
        let old_get = download(&mut server, 10, &old_bytes, 1);
        let destination = tempfile::tempdir().unwrap();
        let root = destination.path().join("photos");
        run(&original_home, &root, &[], true);
        let adopted = TestHome::new();
        let home = if adopt {
            adopted.seed(&server.url());
            run(&adopted, &root, &["--adopt"], true);
            &adopted
        } else {
            &original_home
        };
        old_get.assert();
        old_get.remove();
        let db = export_database(home);
        albums.remove();
        listing(
            &mut server,
            json!([revision(collection(1, "First", &key), 40)]),
        );
        let (new, bytes) = original_fixture(&key, b"new", !old_live, true, 30);
        page(&mut server, 1, 10, json!([new]), false).create();
        let denied = server
            .mock("GET", "/files/download/v3/10")
            .with_status(403)
            .expect(1)
            .create();
        run(home, &root, &[], false);
        assert_component(
            &root,
            "First",
            if old_live { "Motion.heic" } else { "Photo.jpg" },
            b"old",
        );
        if old_live {
            assert_component(&root, "First", "Motion.mov", b"old");
        }
        assert!(!root.join("Trash").exists());
        denied.assert();
        denied.remove();
        let boundary = if old_live {
            "json_type(old.action,'$.Publish.output.Media') IS NOT NULL AND old.retained=0"
        } else {
            "json_type(old.action,'$.Move') IS NOT NULL AND old.retained=1"
        };
        db.execute_batch(&format!(
            "CREATE TRIGGER stop_conversion BEFORE UPDATE ON pending WHEN {boundary} AND new.action='null' BEGIN SELECT RAISE(ABORT,'conversion interruption'); END;",
        ))
        .unwrap();
        let fetched = download(&mut server, 10, &bytes, if old_live { 1 } else { 2 });
        run_failure(home, &root, &[], "conversion interruption");
        db.execute_batch("DROP TRIGGER stop_conversion;").unwrap();
        run(home, &root, &[], true);
        run(home, &root, &[], true);
        assert_component(
            &root,
            "Trash/First",
            if old_live { "Motion.heic" } else { "Photo.jpg" },
            b"old",
        );
        assert_component(
            &root,
            "First",
            if old_live { "Photo.jpg" } else { "Motion.heic" },
            b"new",
        );
        if old_live {
            assert_component(&root, "Trash/First", "Motion.mov", b"old");
            for path in [
                "Motion.heic",
                "Motion.mov",
                "metadata/Motion.heic.json",
                "metadata/Motion.mov.json",
            ] {
                assert!(!root.join("First").join(path).exists());
            }
        } else {
            assert_component(&root, "First", "Motion.mov", b"new");
            assert!(!root.join("First/Photo.jpg").exists());
            assert!(!root.join("First/metadata/Photo.jpg.json").exists());
        }
        assert!(
            !root
                .join("Trash/First")
                .join(if old_live {
                    "Motion-1.heic"
                } else {
                    "Photo-1.jpg"
                })
                .exists()
        );
        fetched.assert();
    }
}

struct CrossAlbumPublication {
    db: rusqlite::Connection,
    albums: mockito::Mock,
    fetched: mockito::Mock,
    server: mockito::ServerGuard,
    home: TestHome,
    key: Key,
    root: tempfile::TempDir,
}

fn interrupted_cross_album_publication(owned: bool, downloads: usize) -> CrossAlbumPublication {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let key = Key::generate();
    let albums = listing(
        &mut server,
        json!([collection(1, "First", &key), collection(2, "Second", &key)]),
    );
    let empty_first = page(&mut server, 1, 0, json!([]), false).create();
    let empty_second = page(&mut server, 2, 0, json!([]), false).create();
    let destination = tempfile::tempdir().unwrap();
    let root = destination.path();
    run(&home, root, &[], true);
    let db = export_database(&home);
    fs::write(root.join("First/Photo.jpg"), b"unrelated first").unwrap();
    albums.remove();
    empty_first.remove();
    empty_second.remove();
    let albums = listing(
        &mut server,
        json!([
            revision(collection(1, "First", &key), 40),
            revision(collection(2, "Second", &key), 40)
        ]),
    );
    let (old, old_bytes) = original_fixture(&key, b"old", false, true, 30);
    let cursor = if owned {
        for album in [1, 2] {
            page(&mut server, album, 0, json!([old]), false).create();
        }
        let fetched = download(&mut server, 10, &old_bytes, 1);
        run(&home, root, &[], false);
        fetched.assert();
        fetched.remove();
        30
    } else {
        0
    };
    db.execute_batch(
        "CREATE TRIGGER stop_ack BEFORE UPDATE ON pending WHEN old.album=2 AND json_type(old.action,'$.Publish.output.Media') IS NOT NULL AND new.action='null' BEGIN SELECT RAISE(ABORT,'stop after cross-album rename'); END;",
    )
    .unwrap();
    albums.remove();
    let albums = listing(
        &mut server,
        json!([
            revision(collection(1, "First", &key), 60),
            revision(collection(2, "Second", &key), 60)
        ]),
    );
    let (file, bytes) = original_fixture(&key, b"new", false, true, 50);
    for album in [1, 2] {
        page(&mut server, album, cursor, json!([file]), false).create();
    }
    let fetched = download(&mut server, 10, &bytes, downloads);
    run_failure(&home, root, &[], "stop after cross-album rename");

    assert_eq!(fs::read(root.join("Second/Photo.jpg")).unwrap(), b"new");
    db.execute_batch("DROP TRIGGER stop_ack;").unwrap();
    CrossAlbumPublication {
        server,
        home,
        key,
        root: destination,
        db,
        albums,
        fetched,
    }
}

#[test]
fn export_recovers_cross_album_publication_after_album_rename() {
    let mut fixture = interrupted_cross_album_publication(false, 1);
    let root = fixture.root.path();
    fixture.albums.remove();
    listing(
        &mut fixture.server,
        json!([revision(collection(2, "Renamed", &fixture.key), 80)]),
    );
    page(&mut fixture.server, 2, 50, json!([]), false).create();
    run(&fixture.home, root, &["--album", "Renamed"], true);
    assert_component(root, "Renamed", "Photo.jpg", b"new");
    assert!(!root.join("Second").exists());
    assert_eq!(
        fs::read(root.join("First/Photo.jpg")).unwrap(),
        b"unrelated first"
    );
    fixture.fetched.assert();
}

#[test]
fn export_repairs_missing_or_changed_cross_album_publications() {
    for (owned, missing) in [(false, true), (false, false), (true, true), (true, false)] {
        let mut fixture = interrupted_cross_album_publication(owned, 2);
        let root = fixture.root.path();
        let photo = root.join("Second/Photo.jpg");
        if missing {
            fs::remove_file(&photo).unwrap();
        } else {
            fs::write(&photo, b"wrong").unwrap();
        }
        fixture.albums.remove();
        listing(
            &mut fixture.server,
            json!([revision(collection(2, "Renamed", &fixture.key), 80)]),
        );
        page(&mut fixture.server, 2, 50, json!([]), false).create();
        if !missing && !owned {
            let result = run(&fixture.home, root, &["--album", "Renamed"], false);
            assert!(result["conflicts"].as_i64().unwrap() > 0);
            assert_eq!(fs::read(root.join("Renamed/Photo.jpg")).unwrap(), b"wrong");
            fs::remove_file(root.join("Renamed/Photo.jpg")).unwrap();
        }
        run(&fixture.home, root, &["--album", "Renamed"], true);
        assert_component(root, "Renamed", "Photo.jpg", b"new");
        assert!(!root.join("Second").exists());
        assert_eq!(
            fs::read(root.join("First/Photo.jpg")).unwrap(),
            b"unrelated first"
        );
        fixture.fetched.assert();
    }
}

#[test]
fn export_preserves_an_excluded_temporary_after_its_source_album_is_deleted() {
    let mut fixture = interrupted_cross_album_publication(false, 2);
    let root = fixture.root.path();
    let pending: String = fixture
        .db
        .query_row(
            "SELECT action FROM pending WHERE album=2 AND file=10",
            [],
            |r| r.get(0),
        )
        .unwrap();
    let action: Value = serde_json::from_str(&pending).unwrap();
    assert_eq!(action["Publish"]["temporary"]["folder"], "active:1");
    assert_eq!(
        action["Publish"]["destination"],
        json!({"folder":"active:2","name":"Photo.jpg"})
    );
    let temporary = root
        .join("First")
        .join(action["Publish"]["temporary"]["name"].as_str().unwrap());
    assert!(!temporary.exists());
    fs::rename(root.join("Second/Photo.jpg"), &temporary).unwrap();
    fixture.albums.remove();
    let mut deleted = revision(collection(1, "First", &fixture.key), 70);
    deleted["isDeleted"] = json!(true);
    let deleted = listing(&mut fixture.server, json!([deleted]));
    run(&fixture.home, root, &["--album", "First"], true);
    assert!(!root.join("First/metadata.json").exists());
    assert_eq!(fs::read(&temporary).unwrap(), b"new");
    let unchanged: String = fixture
        .db
        .query_row(
            "SELECT action FROM pending WHERE album=2 AND file=10",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(unchanged, pending);
    deleted.remove();
    listing(
        &mut fixture.server,
        json!([revision(collection(2, "Renamed", &fixture.key), 80)]),
    );
    page(&mut fixture.server, 2, 50, json!([]), false).create();
    run(&fixture.home, root, &["--album", "Renamed"], true);
    assert_component(root, "Renamed", "Photo.jpg", b"new");
    assert!(!temporary.exists());
    run(&fixture.home, root, &["--album", "First"], true);
    assert_eq!(
        count(
            &fixture.db,
            "SELECT count(*) FROM albums WHERE key='active:1'"
        ),
        0
    );
    assert_eq!(
        fs::read(root.join("First/Photo.jpg")).unwrap(),
        b"unrelated first"
    );
    fixture.fetched.assert();
}

#[test]
fn export_resumed_retention_preserves_original_hashes_after_local_edits() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let key = Key::generate();
    let albums = listing(&mut server, json!([collection(1, "First", &key)]));
    let (file, bytes) = original_fixture(&key, b"original", false, false, 10);
    page(&mut server, 1, 0, json!([file]), false).create();
    let fetched = download(&mut server, 10, &bytes, 2);
    let destination = tempfile::tempdir().unwrap();
    let root = destination.path().join("photos");
    run(&home, &root, &[], true);
    let db = export_database(&home);
    let original_hash =
        read_json(&root.join("First/metadata/Photo.jpg.json"))["ente"]["components"][0]["hash"]
            .clone();
    fs::remove_file(root.join("First/metadata/Photo.jpg.json")).unwrap();
    db.execute_batch(
        "CREATE TRIGGER stop_sidecar BEFORE UPDATE ON pending WHEN json_extract(old.action,'$.Remove.location.name')='metadata/Photo.jpg.json' AND new.action='null' BEGIN SELECT RAISE(ABORT,'stop retention acknowledgement'); END;",
    )
    .unwrap();
    albums.remove();
    let albums = listing(
        &mut server,
        json!([revision(collection(1, "First", &key), 40)]),
    );
    page(
        &mut server,
        1,
        10,
        json!([removed(file.clone(), 30)]),
        false,
    )
    .create();
    run_failure(&home, &root, &[], "stop retention acknowledgement");
    assert_eq!(
        count(
            &db,
            "SELECT count(*) FROM json_records WHERE role='original' AND name='metadata/Photo.jpg.json'"
        ),
        1
    );
    assert!(!root.join("Trash/First/metadata/Photo.jpg.json").exists());
    fs::write(root.join("Trash/First/Photo.jpg"), b"local edit").unwrap();
    db.execute_batch("DROP TRIGGER stop_sidecar;").unwrap();
    run(&home, &root, &[], true);
    assert_eq!(
        fs::read(root.join("Trash/First/Photo.jpg")).unwrap(),
        b"local edit"
    );
    assert_eq!(
        read_json(&root.join("Trash/First/metadata/Photo.jpg.json"))["ente"]["components"][0]["hash"],
        original_hash
    );
    albums.remove();
    listing(
        &mut server,
        json!([revision(collection(1, "First", &key), 60)]),
    );
    page(&mut server, 1, 30, json!([revision(file, 50)]), false).create();
    run(&home, &root, &[], true);
    assert_component(&root, "First", "Photo.jpg", b"original");
    assert_eq!(
        fs::read(root.join("Trash/First/Photo.jpg")).unwrap(),
        b"local edit"
    );
    fetched.assert();
}

#[test]
#[cfg(unix)]
fn export_reports_selected_cleanup_failures_without_changing_completed_counts() {
    use std::os::unix::fs::PermissionsExt;
    for selected_owner in [false, true] {
        let mut server = mockito::Server::new();
        let home = TestHome::new();
        home.seed(&server.url());
        let key = Key::generate();
        listing(
            &mut server,
            json!([collection(1, "First", &key), collection(2, "Second", &key)]),
        );
        let (file, bytes) = original_fixture(&key, b"original", false, true, 10);
        for album in [1, 2] {
            page(&mut server, album, 0, json!([file]), false).create();
        }
        let fetched = download(&mut server, 10, &bytes, 1);
        let destination = tempfile::tempdir().unwrap();
        let root = destination.path().join("photos");
        run(&home, &root, &[], true);
        let db = export_database(&home);
        fs::write(root.join("First/.ente-cleanup.part"), b"disposable").unwrap();
        fs::write(root.join("Second/metadata/Photo.jpg.json"), b"changed").unwrap();
        db.execute_batch(
            "CREATE TRIGGER own_cleanup AFTER UPDATE ON json_records WHEN new.folder='active:2' AND new.role='original' BEGIN INSERT INTO temporaries VALUES('.ente-cleanup.part','active:1',1,10); END;",
        )
        .unwrap();
        let options: &[&str] = if selected_owner {
            &[]
        } else {
            &["--album", "Second"]
        };
        let mut args = vec!["photos", "export", root.to_str().unwrap(), "--json"];
        args.extend_from_slice(options);
        fs::set_permissions(root.join("First"), fs::Permissions::from_mode(0o500)).unwrap();
        let output = home.run(&args);
        fs::set_permissions(root.join("First"), fs::Permissions::from_mode(0o700)).unwrap();
        assert_eq!(
            output.status.success(),
            !selected_owner,
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        let result: Value = serde_json::from_slice(&output.stdout).unwrap();
        assert_eq!(result["complete"], !selected_owner);
        assert_eq!(result["copies"]["pending"], 0);
        assert_eq!(
            result["copies"]["completed"],
            if selected_owner { 2 } else { 1 }
        );
        assert_eq!(result["failures"].as_i64().unwrap() > 0, selected_owner);
        assert_eq!(count(&db, "SELECT count(*) FROM temporaries"), 1);
        assert_eq!(
            fs::read(root.join("First/.ente-cleanup.part")).unwrap(),
            b"disposable"
        );
        assert_component(&root, "Second", "Photo.jpg", b"original");
        db.execute_batch("DROP TRIGGER own_cleanup;").unwrap();
        run(&home, &root, &[], true);
        assert_eq!(count(&db, "SELECT count(*) FROM temporaries"), 0);
        fetched.assert();
    }
}

#[test]
fn export_leaves_unselected_pending_and_temporary_rows_untouched() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let key = Key::generate();
    let albums = listing(
        &mut server,
        json!([collection(1, "First", &key), collection(2, "Second", &key)]),
    );
    let empty = page(&mut server, 1, 0, json!([]), false).create();
    page(&mut server, 2, 0, json!([]), false).create();
    let destination = tempfile::tempdir().unwrap();
    let root = destination.path().join("photos");
    run(&home, &root, &[], true);
    let db = export_database(&home);
    db.execute_batch(
        "CREATE TRIGGER stop_ack BEFORE UPDATE ON pending WHEN old.file=10 AND json_type(old.action,'$.Publish.output.Media') IS NOT NULL AND new.action='null' BEGIN SELECT RAISE(ABORT,'publication acknowledgement'); END;",
    )
    .unwrap();
    empty.remove();
    albums.remove();
    let albums = listing(
        &mut server,
        json!([revision(collection(1, "First", &key), 40)]),
    );
    let (file, bytes) = original_fixture(&key, b"original", false, true, 30);
    page(&mut server, 1, 0, json!([file]), false).create();
    let fetched = download(&mut server, 10, &bytes, 1);
    run_failure(&home, &root, &[], "publication acknowledgement");
    db.execute_batch("DROP TRIGGER stop_ack;").unwrap();
    let pending: String = db
        .query_row("SELECT action FROM pending WHERE file=10", [], |r| r.get(0))
        .unwrap();
    for index in 0..3 {
        let name = format!(".ente-disposable-{index}.part");
        fs::write(root.join("First").join(&name), b"unselected").unwrap();
        db.execute(
            "INSERT INTO temporaries VALUES(?1,'active:1',1,?2)",
            rusqlite::params![name, 100 + index],
        )
        .unwrap();
    }
    albums.remove();
    listing(
        &mut server,
        json!([revision(collection(2, "Renamed", &key), 60)]),
    );
    let (other, other_bytes) = source(20, &key, b"independent", "Other.jpg");
    page(&mut server, 2, 0, json!([revision(other, 50)]), false).create();
    let other_get = download(&mut server, 20, &other_bytes, 1);
    let result = run(&home, &root, &["--album", "Renamed", "-j", "1"], true);
    assert_eq!(result["failures"], 0);
    assert_eq!(count(&db, "SELECT count(*) FROM temporaries"), 4);
    assert_eq!(
        db.query_row("SELECT action FROM pending WHERE file=10", [], |r| r
            .get::<_, String>(0))
            .unwrap(),
        pending
    );
    for index in 0..3 {
        assert_eq!(
            fs::read(root.join(format!("First/.ente-disposable-{index}.part"))).unwrap(),
            b"unselected"
        );
    }
    run(&home, &root, &["--album", "First"], true);
    assert_component(&root, "First", "Photo.jpg", b"original");
    assert_eq!(count(&db, "SELECT count(*) FROM temporaries"), 0);
    fetched.assert();
    other_get.assert();
}

#[test]
fn export_automatically_retries_saved_selected_album_and_file_failures() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let key = Key::generate();
    let good_album = collection(1, "First", &key);
    let mut first = good_album.clone();
    first["encryptedKey"] = json!("invalid");
    let mut second = collection(2, "Second", &key);
    second["encryptedKey"] = json!("invalid");
    let albums = listing(
        &mut server,
        json!([first, second, collection(3, "Third", &key)]),
    );
    let (good_file, bytes) = original_fixture(&key, b"original", false, true, 10);
    let mut broken = good_file.clone();
    broken["metadata"]["encryptedData"] = json!("invalid");
    let first_page = page(&mut server, 3, 0, json!([broken]), false)
        .expect(1)
        .create();
    let destination = tempfile::tempdir().unwrap();
    let root = destination.path().join("photos");
    run(&home, &root, &[], false);
    let db = database(&home);
    db.execute(
        "UPDATE photos_collections SET record=json_set(record,'$.failure','saved failure') WHERE id IN (1,2)",
        [],
    )
    .unwrap();
    let mut saved: Value = serde_json::from_str(
        &db.query_row(
            "SELECT record FROM photos_collections WHERE id=1",
            [],
            |r| r.get::<_, String>(0),
        )
        .unwrap(),
    )
    .unwrap();
    saved["remote"] = good_album;
    db.execute(
        "UPDATE photos_collections SET record=?1 WHERE id=1",
        [saved.to_string()],
    )
    .unwrap();
    let mut saved = record(&db, 3, 10);
    saved["remote"] = good_file;
    db.execute(
        "UPDATE photos_files SET record=?1 WHERE collection_id=3 AND id=10",
        [saved.to_string()],
    )
    .unwrap();
    albums.remove();
    listing(&mut server, json!([]));
    page(&mut server, 1, 0, json!([]), false).create();
    let fetched = download(&mut server, 10, &bytes, 1);
    run(&home, &root, &["--album", "1", "--album", "3"], true);
    assert_component(&root, "Third", "Photo.jpg", b"original");
    assert!(record(&db, 3, 10)["documents"].is_object());
    assert_eq!(
        db.query_row(
            "SELECT json_extract(record,'$.failure') FROM photos_collections WHERE id=2",
            [],
            |r| r.get::<_, String>(0)
        )
        .unwrap(),
        "saved failure"
    );
    db.execute(
        "INSERT INTO photos_files SELECT 1,id,name,updated_at,record,decrypt_failed FROM photos_files WHERE collection_id=3 AND id=10",
        [],
    )
    .unwrap();
    db.execute(
        "UPDATE photos_files SET record=json_set(record,'$.documents',NULL,'$.key',NULL,'$.failure','saved failure'),decrypt_failed=1 WHERE id=10",
        [],
    )
    .unwrap();
    run(&home, &root, &["--album", "1", "--album", "3"], true);
    for album in [1, 3] {
        assert!(record(&db, album, 10)["documents"].is_object());
    }
    assert_component(&root, "First", "Photo.jpg", b"original");
    assert!(
        !home
            .run(&["photos", "export", root.to_str().unwrap(), "--retry-failed"])
            .status
            .success()
    );
    first_page.assert();
    fetched.assert();
}

#[test]
fn export_recovers_empty_initial_directories_without_claiming_unrelated_contents() {
    for scenario in ["active", "retained", "removed"] {
        let retained = scenario == "retained";
        let mut server = mockito::Server::new();
        let home = TestHome::new();
        home.seed(&server.url());
        let key = Key::generate();
        let album = collection(1, "First", &key);
        let initial = listing(
            &mut server,
            if retained { json!([album]) } else { json!([]) },
        );
        let (file, bytes) = source(10, &key, b"original", "Photo.jpg");
        if retained {
            page(&mut server, 1, 0, json!([file]), false).create();
        }
        let fetched = download(&mut server, 10, &bytes, usize::from(retained));
        let destination = tempfile::tempdir().unwrap();
        let root = destination.path().join("photos");
        run(&home, &root, &[], true);
        let db = export_database(&home);
        if scenario == "removed" {
            db.execute_batch(
                "CREATE TRIGGER stop_directory BEFORE INSERT ON temporaries WHEN new.file IS NULL BEGIN SELECT RAISE(ABORT,'directory acknowledged before metadata'); END;",
            )
            .unwrap();
        } else {
            db.execute_batch(&format!(
                "CREATE TRIGGER stop_directory BEFORE INSERT ON albums WHEN new.retained={} BEGIN SELECT RAISE(ABORT,'directory before acknowledgement'); END;",
                i64::from(retained),
            ))
            .unwrap();
        }
        initial.remove();
        let current = listing(&mut server, json!([revision(album.clone(), 40)]));
        if retained {
            page(&mut server, 1, 10, json!([removed(file, 30)]), false).create();
        } else {
            page(&mut server, 1, 0, json!([]), false).create();
        }
        run_failure(
            &home,
            &root,
            &[],
            if scenario == "removed" {
                "directory acknowledged before metadata"
            } else {
                "directory before acknowledgement"
            },
        );
        db.execute_batch("DROP TRIGGER stop_directory;").unwrap();
        let folder = root.join(if retained { "Trash/First" } else { "First" });
        assert_eq!(fs::read_dir(&folder).unwrap().count(), 0);
        if scenario == "removed" {
            assert_eq!(
                count(&db, "SELECT count(*) FROM albums WHERE id=1 AND retained=0"),
                1
            );
            let cached: String = db
                .query_row(
                    "SELECT value FROM json_records WHERE owner='active:1' AND folder IS NULL",
                    [],
                    |r| r.get(0),
                )
                .unwrap();
            let cached: Value = serde_json::from_str(&cached).unwrap();
            assert_eq!(cached["ente"]["albumID"], "1");
            assert_eq!(cached["title"], "First");
            current.remove();
            let mut deleted = revision(album, 60);
            deleted["isDeleted"] = json!(true);
            listing(&mut server, json!([deleted]));
            run(&home, &root, &[], true);
            assert!(!folder.exists());
            let history = root.join("Trash/First/metadata.json");
            assert_eq!(read_json(&history), cached);
            assert_eq!(fs::read_dir(history.parent().unwrap()).unwrap().count(), 1);
            let bytes = fs::read(&history).unwrap();
            let rerun = run(&home, &root, &[], true);
            assert_eq!(
                rerun["changes"],
                json!({"exported":0,"metadataUpdated":0,"renamed":0,"retained":0})
            );
            assert_eq!(fs::read(&history).unwrap(), bytes);
            fetched.assert();
            continue;
        }
        let notes = folder.join("notes.txt");
        fs::write(&notes, b"unrelated").unwrap();
        let result = run(&home, &root, &[], false);
        assert!(result["conflicts"].as_i64().unwrap() > 0);
        assert_eq!(fs::read(&notes).unwrap(), b"unrelated");
        assert!(!folder.join("metadata.json").exists());
        assert_eq!(
            db.query_row(
                "SELECT count(*) FROM albums WHERE id=1 AND retained=?1",
                [retained],
                |r| r.get::<_, i64>(0)
            )
            .unwrap(),
            0
        );
        assert_eq!(
            count(
                &db,
                "SELECT count(*) FROM pending WHERE json_type(action,'$.Directory') IS NOT NULL"
            ),
            1
        );
        fs::remove_file(notes).unwrap();
        run(&home, &root, &[], true);
        assert_eq!(
            read_json(&folder.join("metadata.json"))["ente"]["albumID"],
            "1"
        );
        if retained {
            assert_component(&root, "Trash/First", "Photo.jpg", b"original");
        }
        fetched.assert();
    }
}

#[test]
fn export_reports_completion_progress_before_the_command_finishes() {
    use std::sync::{Mutex, mpsc};
    use std::time::{Duration, Instant};

    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let key = Key::generate();
    listing(&mut server, json!([collection(1, "Album", &key)]));
    let (first, first_bytes) = source(10, &key, b"first", "First.jpg");
    let (second, second_bytes) = source(11, &key, b"second", "Second.jpg");
    page(&mut server, 1, 0, json!([first, second]), false).create();
    let fetched = download(&mut server, 10, &first_bytes, 1);
    let url = server
        .mock("GET", "/files/download/v3/11")
        .with_body(json!({"url":format!("{}/slow",server.url())}).to_string())
        .expect(1)
        .create();
    let (started, reading) = mpsc::channel();
    let (release, receiver) = mpsc::channel::<()>();
    let receiver = Mutex::new(receiver);
    let slow = server
        .mock("GET", "/slow")
        .with_body_from_request(move |_| {
            let _ = started.send(());
            let _ = receiver.lock().unwrap().recv();
            second_bytes.clone()
        })
        .expect(1)
        .create();
    let destination = tempfile::tempdir().unwrap();
    let root = destination.path().join("photos");
    let diagnostics = destination.path().join("stderr");
    let mut child = ExportChild::spawn(
        home.command(&[
            "photos",
            "export",
            root.to_str().unwrap(),
            "-j",
            "1",
            "--json",
        ])
        .stderr(fs::File::create(&diagnostics).unwrap()),
    )
    .unwrap();
    reading
        .recv_timeout(Duration::from_secs(60))
        .expect("second download never started");
    let deadline = Instant::now() + Duration::from_secs(60);
    while !fs::read_to_string(&diagnostics)
        .unwrap()
        .contains("Completed 1/2 selected copies.")
    {
        assert!(
            child.try_wait().unwrap().is_none(),
            "export exited before reporting progress"
        );
        assert!(
            Instant::now() < deadline,
            "progress was not reported while the response was held"
        );
        std::thread::sleep(Duration::from_millis(10));
    }
    assert!(child.try_wait().unwrap().is_none());
    drop(release);
    let output = child.wait_with_output().unwrap();
    assert!(output.status.success());
    assert_eq!(
        serde_json::from_slice::<Value>(&output.stdout).unwrap()["copies"]["completed"],
        2
    );
    fetched.assert();
    url.assert();
    slow.assert();
}

#[test]
fn export_only_file_metadata_does_not_break_common_commands() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let key = Key::generate();
    listing(
        &mut server,
        json!([
            collection(1, "Affected", &key),
            collection(2, "Healthy", &key)
        ]),
    );
    let (file, _) = source(10, &key, b"unused", "Original.jpg");
    let file = public(
        file,
        &key,
        json!({
            "editedName":"Export metadata.jpg", "cameraMake":17, "cameraModel":17,
            "uploaderName":17, "mediaType":"broken", "mvi":"broken"
        }),
        10,
    );
    let (healthy, bytes) = source(20, &key, b"healthy", "Healthy.jpg");
    page(&mut server, 1, 0, json!([file]), false).create();
    page(&mut server, 2, 0, json!([healthy]), false).create();
    let no_download = server
        .mock("GET", "/files/download/v3/10")
        .expect(0)
        .create();
    let downloaded = download(&mut server, 20, &bytes, 1);
    let listed = home.json(&["photos", "file", "list"]);
    assert_eq!(listed.as_array().unwrap().len(), 2);
    let viewed = home.json(&["photos", "file", "view", "Export metadata.jpg", "--offline"]);
    assert_eq!(viewed["id"], "10");
    assert_eq!(viewed["name"], "Export metadata.jpg");
    let destination = tempfile::tempdir().unwrap();
    let root = destination.path().join("photos");
    let output = home.run(&["photos", "export", root.to_str().unwrap(), "--json"]);
    let error = failure(&output);
    assert!(
        error.contains("file:1:10: invalid public file metadata"),
        "{error}"
    );
    let result: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(result["complete"], false);
    assert_eq!(
        result["copies"],
        json!({"expected":2,"completed":1,"pending":1})
    );
    assert_eq!(result["failures"], 1);
    assert_component(&root, "Healthy", "Healthy.jpg", b"healthy");
    assert!(!root.join("Affected/Export metadata.jpg").exists());
    no_download.assert();
    downloaded.assert();
}

#[test]
fn export_only_album_metadata_preserves_common_commands_and_favorites() {
    for (document, value, cause) in [
        (
            "magicMetadata",
            json!({"order":"broken"}),
            "invalid album private metadata",
        ),
        (
            "sharedMagicMetadata",
            json!({"order":"broken","mute":"broken"}),
            "invalid album sharee metadata",
        ),
        (
            "pubMagicMetadata",
            json!({"asc":"broken","coverID":"broken","layout":17,"caption":17}),
            "invalid album public metadata",
        ),
    ] {
        let mut server = mockito::Server::new();
        let home = TestHome::new();
        home.seed(&server.url());
        let key = Key::generate();
        let mut favorites = collection(5, "Favorites", &key);
        favorites["type"] = json!("favorites");
        let encrypted = blob::encrypt_json(&value, &key).unwrap();
        favorites[document] = json!({"data":b64::encode(&encrypted.encrypted_data),"header":b64::encode(encrypted.decryption_header.as_bytes())});
        listing(
            &mut server,
            json!([collection(1, "Healthy", &key), favorites]),
        );
        let (file, bytes) = source(10, &key, b"original", "Photo.jpg");
        page(&mut server, 1, 0, json!([file]), false).create();
        let memberships = page(&mut server, 5, 0, json!([file]), false)
            .expect(1)
            .create();
        let downloaded = download(&mut server, 10, &bytes, 1);
        let albums = home.json(&["photos", "album", "list"]);
        assert_eq!(albums.as_array().unwrap().len(), 2);
        let viewed = home.json(&["photos", "album", "view", "Favorites", "--offline"]);
        assert_eq!(viewed["id"], "5");
        assert_eq!(viewed["name"], "Favorites");
        let destination = tempfile::tempdir().unwrap();
        let root = destination.path().join("photos");
        let output = home.run(&[
            "photos",
            "export",
            root.to_str().unwrap(),
            "--album",
            "Healthy",
            "--json",
        ]);
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(!String::from_utf8_lossy(&output.stderr).contains("album:5"));
        let sidecar = root.join("Healthy/metadata/Photo.jpg.json");
        let mut metadata = read_json(&sidecar);
        assert_eq!(metadata["favorited"], true);
        metadata["favorited"] = json!(false);
        fs::write(&sidecar, serde_json::to_vec(&metadata).unwrap()).unwrap();
        let output = home.run(&["photos", "export", root.to_str().unwrap(), "--json"]);
        let error = failure(&output);
        assert!(error.contains(&format!("album:5: {cause}")), "{error}");
        assert!(!error.contains("favorite state is incomplete"), "{error}");
        let result: Value = serde_json::from_slice(&output.stdout).unwrap();
        assert_eq!(result["complete"], false);
        assert_eq!(result["failures"], 1);
        assert_eq!(result["changes"]["metadataUpdated"], 1);
        assert_eq!(read_json(&sidecar)["favorited"], true);
        assert_component(&root, "Healthy", "Photo.jpg", b"original");
        assert!(!root.join("Favorites").exists());
        memberships.assert();
        downloaded.assert();
    }
}
