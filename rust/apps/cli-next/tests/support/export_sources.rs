use super::files::{collection, page, remote_file};
use super::*;
use ente_core::crypto::{Nonce, hash, secretbox};
use std::path::Path;

#[path = "export_maintenance.rs"]
mod maintenance;

#[test]
fn export_rejects_zero_jobs_before_creating_storage() {
    let home = TestHome::new();
    let unused = home.dir.path().join("unused");
    let destination = home.dir.path().join("photos");
    let output = home
        .command(&[
            "photos",
            "export",
            destination.to_str().unwrap(),
            "--jobs",
            "0",
        ])
        .env("ENTE_CLI_HOME", &unused)
        .output()
        .unwrap();
    assert!(failure(&output).contains("invalid value '0'"));
    assert!(output.stdout.is_empty());
    assert!(!unused.exists());
    assert!(!destination.exists());
}

#[test]
fn export_rejects_wrong_accounts_and_unsupported_roots_before_refresh() {
    let mut server = mockito::Server::new();
    let albums = server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(json!({"collections":[]}).to_string())
        .expect(1)
        .create();
    let home = TestHome::new();
    home.seed(&server.url());
    let destination = tempfile::tempdir().unwrap();
    let root = destination.path().join("photos");
    run(&home, &root, &[], true);
    let root_path = root.join("export.json");
    let original = fs::read(&root_path).unwrap();
    let wrong = TestHome::new();
    wrong.seed(&server.url());
    let mut state = wrong.read_vault();
    state["accounts"][0]["identity"]["master_key"] = json!(vec![1u8; 32]);
    wrong.write_vault(&state);
    assert!(
        failure(&wrong.run(&["photos", "export", root.to_str().unwrap(), "--adopt"]))
            .contains("another source account")
    );
    assert_eq!(fs::read(&root_path).unwrap(), original);
    for (field, value) in [("version", json!(2)), ("format", json!("other-export"))] {
        let mut record: Value = serde_json::from_slice(&original).unwrap();
        record[field] = value;
        let unsupported = serde_json::to_vec(&record).unwrap();
        fs::write(&root_path, &unsupported).unwrap();
        assert!(
            failure(&home.run(&["photos", "export", root.to_str().unwrap()]))
                .contains("unsupported export format")
        );
        assert_eq!(fs::read(&root_path).unwrap(), unsupported);
    }
    fs::write(&root_path, b"{malformed").unwrap();
    assert!(
        failure(&home.run(&["photos", "export", root.to_str().unwrap()]))
            .contains("invalid export.json")
    );
    assert_eq!(fs::read_dir(&root).unwrap().count(), 1);
    albums.assert();
}

#[test]
fn export_preserves_failed_records_and_advances_the_page_atomically() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let destination = tempfile::tempdir().unwrap();
    let root = destination.path().join("photos");
    let key = Key::generate();
    let albums = server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(
            json!({"collections":[collection(1,"First",&key),collection(2,"Second",&key)]})
                .to_string(),
        )
        .expect_at_least(1)
        .create();
    let (good, encrypted) = source(10, &key, b"good", "Good.jpg");
    let (mut broken, broken_bytes) = source(11, &key, b"broken", "Broken.jpg");
    let mut repaired = broken.clone();
    broken["metadata"]["encryptedData"] = json!("invalid ciphertext");
    let first = page(&mut server, 1, 0, json!([good, broken]), true)
        .expect(1)
        .create();
    let (later, later_bytes) = source(12, &key, b"later", "Later.jpg");
    let mut later = later;
    later["updationTime"] = json!(15);
    let last = page(&mut server, 1, 10, json!([later]), false)
        .expect(1)
        .create();
    page(&mut server, 2, 0, json!([broken]), false)
        .expect(1)
        .create();
    let good_download = download(&mut server, 10, &encrypted, 1);
    let later_download = download(&mut server, 12, &later_bytes, 1);
    let initial = run(&home, &root, &[], false);
    assert_eq!(
        initial["copies"],
        json!({"expected":4,"completed":2,"pending":2})
    );
    assert_eq!(initial["failures"], 2);
    assert_eq!(fs::read(root.join("First/Good.jpg")).unwrap(), b"good");
    assert_eq!(fs::read(root.join("First/Later.jpg")).unwrap(), b"later");
    let db = database(&home);
    let failed = record(&db, 1, 11);
    assert!(failed["documents"].is_null());
    assert_eq!(
        db.query_row(
            "SELECT files_cursor FROM photos_collections WHERE id=1",
            [],
            |r| r.get::<_, i64>(0)
        )
        .unwrap(),
        15
    );
    run(&home, &root, &[], false);
    db.execute(
        "UPDATE photos_files SET record=json_set(record,'$.failure','saved failure') WHERE id=11",
        [],
    )
    .unwrap();
    run(&home, &root, &["--album", "First"], false);
    assert_ne!(record(&db, 1, 11)["failure"], "saved failure");
    assert_eq!(record(&db, 2, 11)["failure"], "saved failure");
    first.assert();
    last.assert();

    let previous_input = record(&db, 1, 11)["input_hash"].clone();
    albums.remove();
    let mut changed = collection(1, "First", &key);
    changed["updationTime"] = json!(40);
    let changed_albums = server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(json!({"collections":[changed]}).to_string())
        .create();
    repaired["updationTime"] = json!(30);
    page(&mut server, 1, 15, json!([repaired]), false).create();
    let repaired_download = download(&mut server, 11, &broken_bytes, 1);
    run(&home, &root, &["--album", "First"], true);
    assert_ne!(record(&db, 1, 11)["input_hash"], previous_input);
    assert!(record(&db, 1, 11)["documents"].is_object());
    assert_eq!(fs::read(root.join("First/Broken.jpg")).unwrap(), b"broken");
    good_download.assert();
    later_download.assert();
    repaired_download.assert();
    changed_albums.remove();
    let mut second = collection(2, "Second", &key);
    second["updationTime"] = json!(50);
    server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(json!({"collections":[second]}).to_string())
        .create();
    let mut removed = broken;
    removed["updationTime"] = json!(50);
    removed["isDeleted"] = json!(true);
    page(&mut server, 2, 10, json!([removed]), false).create();
    let result = run(&home, &root, &["--album", "Second"], true);
    assert_eq!(result["copies"]["expected"], 0);
    assert_eq!(result["failures"], 0);
    assert_eq!(
        db.query_row(
            "SELECT count(*) FROM photos_files WHERE collection_id=2 AND id=11",
            [],
            |r| r.get::<_, i64>(0)
        )
        .unwrap(),
        0
    );
    assert!(!root.join("Second/Broken.jpg").exists());
    assert_eq!(
        run(&home, &root, &["--album", "Second"], true)["failures"],
        0
    );
}

#[test]
fn export_reevaluates_saved_metadata_without_an_upstream_change() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let key = Key::generate();
    server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(json!({"collections":[collection(1,"First",&key)]}).to_string())
        .create();
    let (file, bytes) = source(10, &key, b"original", "Good.jpg");
    let page = page(&mut server, 1, 0, json!([file]), false)
        .expect(1)
        .create();
    let downloaded = download(&mut server, 10, &bytes, 1);
    let destination = tempfile::tempdir().unwrap();
    let root = destination.path().join("photos");
    run(&home, &root, &[], true);
    let db = database(&home);
    let before = record(&db, 1, 10);
    let mut docs: Value = serde_json::from_slice(
        &ente_core::b64::decode(before["documents"]["public"].as_str().unwrap()).unwrap(),
    )
    .unwrap();
    docs["caption"] = json!("reevaluated stored caption");
    let mut updated = before;
    updated["documents"]["public"] =
        json!(ente_core::b64::encode(&serde_json::to_vec(&docs).unwrap()));
    db.execute(
        "UPDATE photos_files SET record=?1 WHERE collection_id=1 AND id=10",
        [updated.to_string()],
    )
    .unwrap();
    run(&home, &root, &["--album", "First"], true);
    assert_eq!(
        read_json(&root.join("First/metadata/Good.jpg.json"))["description"],
        "reevaluated stored caption"
    );

    page.assert();
    downloaded.assert();
}

#[test]
fn export_retries_saved_file_decryption_when_the_album_key_changes() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let key = Key::generate();
    let wrong_key = Key::generate();
    let albums = server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(json!({"collections":[collection(1,"First",&wrong_key)]}).to_string())
        .create();
    let (file, bytes) = source(10, &key, b"original", "Original.jpg");
    let received = page(&mut server, 1, 0, json!([file]), false)
        .expect(1)
        .create();
    let destination = tempfile::tempdir().unwrap();
    let root = destination.path().join("photos");
    run(&home, &root, &[], false);
    let db = database(&home);
    let failed = record(&db, 1, 10);
    assert!(failed["documents"].is_null());
    albums.remove();
    let mut changed = collection(1, "First", &key);
    changed["updationTime"] = json!(20);
    server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(json!({"collections":[changed]}).to_string())
        .create();
    page(&mut server, 1, 10, json!([]), false)
        .expect(1)
        .create();
    let downloaded = download(&mut server, 10, &bytes, 1);
    run(&home, &root, &[], true);
    assert_ne!(record(&db, 1, 10)["input_hash"], failed["input_hash"]);
    assert!(record(&db, 1, 10)["documents"].is_object());
    assert_eq!(
        fs::read(root.join("First/Original.jpg")).unwrap(),
        b"original"
    );
    received.assert();
    downloaded.assert();
}

#[test]
fn export_keeps_unresolved_output_and_rejects_ambiguous_adoption() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let destination = tempfile::tempdir().unwrap();
    let root = destination.path().join("photos");
    let key = Key::generate();
    let albums = server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(json!({"collections":[collection(1,"First",&key)]}).to_string())
        .create();
    let (good, encrypted) = source(10, &key, b"good", "Good.jpg");
    page(&mut server, 1, 0, json!([good]), false).create();
    download(&mut server, 10, &encrypted, 1);
    run(&home, &root, &[], true);
    let before = fs::read(root.join("First/metadata/Good.jpg.json")).unwrap();
    let mut broken = good;
    broken["updationTime"] = json!(30);
    broken["pubMagicMetadata"]["data"] = json!("broken");
    albums.remove();
    let mut album = collection(1, "First", &key);
    album["updationTime"] = json!(40);
    server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(json!({"collections":[album]}).to_string())
        .create();
    page(&mut server, 1, 10, json!([broken]), false).create();
    run(&home, &root, &[], false);
    assert_eq!(
        fs::read(root.join("First/metadata/Good.jpg.json")).unwrap(),
        before
    );
    assert_eq!(fs::read(root.join("First/Good.jpg")).unwrap(), b"good");
    let unassociated = root.join("First/unassociated.jpg");
    fs::write(&unassociated, b"keep me").unwrap();
    fs::create_dir(root.join("Other")).unwrap();
    fs::copy(
        root.join("First/metadata.json"),
        root.join("Other/metadata.json"),
    )
    .unwrap();
    let fresh = TestHome::new();
    fresh.seed(&server.url());
    let output = fresh.run(&[
        "photos",
        "export",
        root.to_str().unwrap(),
        "--adopt",
        "--json",
    ]);
    assert!(failure(&output).contains("active album ID"));
    assert!(output.stdout.is_empty());
    assert_eq!(fs::read(unassociated).unwrap(), b"keep me");
    assert_eq!(
        fs::read(root.join("First/metadata/Good.jpg.json")).unwrap(),
        before
    );
}

#[test]
fn export_releases_a_deleted_album_reservation_before_its_first_association() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let destination = tempfile::tempdir().unwrap();
    let root = destination.path().join("photos");
    let empty = server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(json!({"collections":[]}).to_string())
        .create();
    run(&home, &root, &[], true);
    empty.remove();
    fs::create_dir(root.join("Family")).unwrap();
    let unrelated = root.join("Family/notes.txt");
    fs::write(&unrelated, b"unrelated").unwrap();
    let key = Key::generate();
    let album = collection(1, "Family", &key);
    let albums = server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(json!({"collections":[album]}).to_string())
        .create();
    page(&mut server, 1, 0, json!([]), false).create();
    assert_eq!(run(&home, &root, &["--album", "1"], false)["conflicts"], 1);
    let db = export_database(&home);
    let reservation = || {
        db.query_row(
            "SELECT name1 FROM pending WHERE owner='active:1'",
            [],
            |r| r.get::<_, String>(0),
        )
        .unwrap()
    };
    let pending = reservation();
    assert_eq!(pending, "Family");
    assert_eq!(
        run(&home, &root, &["--album", "Family"], false)["conflicts"],
        1
    );
    run(&home, &root, &["--exclude-album", "Family"], true);
    assert_eq!(reservation(), pending);
    assert_eq!(fs::read(&unrelated).unwrap(), b"unrelated");
    assert!(!root.join("Family/metadata.json").exists());
    albums.remove();
    let malformed = server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body("{")
        .create();
    failure(&home.run(&["photos", "export", root.to_str().unwrap(), "--album", "1"]));
    assert_eq!(reservation(), pending);
    malformed.remove();
    let mut deleted = album;
    deleted["updationTime"] = json!(30);
    deleted["isDeleted"] = json!(true);
    let deletion = server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(json!({"collections":[deleted]}).to_string())
        .create();
    for selector in ["1", "Family"] {
        assert_eq!(
            run(&home, &root, &["--exclude-album", selector], true)["copies"]["expected"],
            0
        );
        assert_eq!(reservation(), pending);
    }
    run(&home, &root, &["--album", "1"], true);
    assert_eq!(fs::read(&unrelated).unwrap(), b"unrelated");
    assert!(!root.join("Family/metadata.json").exists());
    assert!(!root.join("Trash").exists());
    deletion.remove();
    fs::remove_file(unrelated).unwrap();
    fs::remove_dir(root.join("Family")).unwrap();
    let mut replacement = collection(2, "Family", &key);
    replacement["updationTime"] = json!(40);
    server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(json!({"collections":[replacement]}).to_string())
        .create();
    page(&mut server, 2, 0, json!([]), false).create();
    run(&home, &root, &[], true);
    assert_eq!(
        read_json(&root.join("Family/metadata.json"))["ente"]["albumID"],
        "2"
    );
    assert!(!root.join("Family-1").exists());
}

#[test]
fn export_clears_deleted_adopted_album_rename_reservations() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let destination = tempfile::tempdir().unwrap();
    let root = destination.path().join("photos");
    let key = Key::generate();
    let albums = server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(json!({"collections":[collection(1,"First",&key)]}).to_string())
        .create();
    let (file, encrypted) = source(10, &key, b"original", "Original.jpg");
    page(&mut server, 1, 0, json!([file]), false).create();
    page(&mut server, 1, 10, json!([]), false).create();
    let downloaded = download(&mut server, 10, &encrypted, 1);
    run(&home, &root, &[], true);
    let fresh = TestHome::new();
    fresh.seed(&server.url());
    run(&fresh, &root, &["--adopt"], true);
    let db = export_database(&fresh);
    let owner: String = db
        .query_row(
            "SELECT key FROM albums WHERE id=1 AND retained=0",
            [],
            |r| r.get(0),
        )
        .unwrap();
    fs::create_dir(root.join("Blocked")).unwrap();
    let unrelated = root.join("Blocked/notes.txt");
    fs::write(&unrelated, b"unrelated rename target").unwrap();
    albums.remove();
    let mut renamed = collection(1, "Blocked", &key);
    renamed["updationTime"] = json!(30);
    let rename = server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(json!({"collections":[renamed]}).to_string())
        .create();
    assert_eq!(run(&fresh, &root, &[], false)["conflicts"], 2);
    let reservation = || {
        db.query_row("SELECT name1 FROM pending WHERE owner=?1", [&owner], |r| {
            r.get::<_, String>(0)
        })
        .unwrap()
    };
    let pending = reservation();
    assert_eq!(pending, "Blocked");
    assert_eq!(
        fs::read(root.join("First/Original.jpg")).unwrap(),
        b"original"
    );
    rename.remove();
    let mut deleted = renamed;
    deleted["updationTime"] = json!(40);
    deleted["isDeleted"] = json!(true);
    let deletion = server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(json!({"collections":[deleted]}).to_string())
        .create();
    run(&fresh, &root, &["--exclude-album", "1"], true);
    assert_eq!(reservation(), pending);
    fs::create_dir_all(root.join("Trash/First")).unwrap();
    let retained_blocker = root.join("Trash/First/notes.txt");
    fs::write(&retained_blocker, b"unrelated retention target").unwrap();
    run(&fresh, &root, &["--album", "1"], false);
    let retained = || {
        db.query_row(
            "SELECT name1 FROM pending WHERE owner='retained:1'",
            [],
            |r| r.get::<_, String>(0),
        )
        .unwrap()
    };
    let pending_retention = retained();
    assert!(root.join("First/metadata.json").exists());
    assert_eq!(pending_retention, "First");
    run(&fresh, &root, &["--album", "1"], false);
    assert_eq!(retained(), pending_retention);
    assert!(!root.join("Trash/First-1").exists());
    assert_eq!(
        fs::read(root.join("First/Original.jpg")).unwrap(),
        b"original"
    );
    assert_eq!(
        fs::read(&retained_blocker).unwrap(),
        b"unrelated retention target"
    );
    assert_eq!(fs::read(&unrelated).unwrap(), b"unrelated rename target");
    fs::remove_file(retained_blocker).unwrap();
    fs::remove_dir(root.join("Trash/First")).unwrap();
    run(&fresh, &root, &["--album", "1"], true);
    assert_eq!(
        fs::read(root.join("Trash/First/Original.jpg")).unwrap(),
        b"original"
    );
    assert_eq!(
        read_json(&root.join("Trash/First/metadata/Original.jpg.json"))["ente"]["fileID"],
        "10"
    );
    deletion.remove();
    fs::remove_file(unrelated).unwrap();
    fs::remove_dir(root.join("Blocked")).unwrap();
    let mut replacement = collection(2, "Blocked", &key);
    replacement["updationTime"] = json!(50);
    server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(json!({"collections":[replacement]}).to_string())
        .create();
    page(&mut server, 2, 0, json!([]), false).create();
    run(&fresh, &root, &[], true);
    assert_eq!(
        read_json(&root.join("Blocked/metadata.json"))["ente"]["albumID"],
        "2"
    );
    assert!(!root.join("Blocked-1").exists());
    downloaded.assert();
}

#[test]
fn export_rejects_offline_early_and_reports_path_conflicts() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let destination = tempfile::tempdir().unwrap();
    let root = destination.path().join("photos");
    assert!(
        failure(&home.run(&["photos", "export", root.to_str().unwrap(), "--offline"]))
            .contains("requires network")
    );
    assert!(!root.exists());
    let key = Key::generate();
    let albums = server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(json!({"collections":[collection(1,"First",&key)]}).to_string())
        .create();
    let empty = page(&mut server, 1, 0, json!([]), false).create();
    run(&home, &root, &[], true);
    empty.remove();
    fs::write(root.join("First/Good.jpg"), b"unrelated").unwrap();
    let db = database(&home);
    db.execute("UPDATE photos_collections SET files_synced_to=NULL", [])
        .unwrap();
    let (good, encrypted) = source(10, &key, b"good", "Good.jpg");
    page(&mut server, 1, 0, json!([good]), false).create();
    let downloaded = download(&mut server, 10, &encrypted, if cfg!(unix) { 6 } else { 4 });
    #[cfg(unix)]
    {
        let target = destination.path().join("outside.jpg");
        fs::write(&target, b"outside export").unwrap();
        fs::remove_file(root.join("First/Good.jpg")).unwrap();
        std::os::unix::fs::symlink(&target, root.join("First/Good.jpg")).unwrap();
        assert_eq!(run(&home, &root, &[], false)["conflicts"], 1);
        assert_eq!(fs::read(&target).unwrap(), b"outside export");
        assert!(
            fs::symlink_metadata(root.join("First/Good.jpg"))
                .unwrap()
                .is_symlink()
        );
        fs::remove_file(root.join("First/Good.jpg")).unwrap();
        let external_metadata = tempfile::tempdir().unwrap();
        std::os::unix::fs::symlink(external_metadata.path(), root.join("First/metadata")).unwrap();
        assert_eq!(run(&home, &root, &[], false)["conflicts"], 1);
        assert_eq!(fs::read_dir(external_metadata.path()).unwrap().count(), 0);
        fs::remove_file(root.join("First/metadata")).unwrap();
        fs::write(root.join("First/Good.jpg"), b"unrelated").unwrap();
    }
    let result = run(&home, &root, &[], false);
    assert_eq!(result["conflicts"], 1);
    assert_eq!(result["copies"]["pending"], 1);
    assert_eq!(fs::read(root.join("First/Good.jpg")).unwrap(), b"unrelated");
    assert!(!root.join("First/Good-1.jpg").exists());
    let reservation = || {
        let db = export_database(&home);
        assert_eq!(
            db.query_row("SELECT count(*) FROM placements WHERE file=10", [], |r| r
                .get::<_, i64>(
                0
            ))
            .unwrap(),
            0
        );
        let record: String = db
            .query_row(
                "SELECT name1 FROM pending WHERE album=1 AND file=10",
                [],
                |r| r.get(0),
            )
            .unwrap();
        record
    };
    let allocated = reservation();
    assert_eq!(allocated, "Good.jpg");
    let unchanged = page(&mut server, 1, 10, json!([]), false).create();
    assert_eq!(run(&home, &root, &[], false)["conflicts"], 1);
    assert_eq!(reservation(), allocated);
    assert_eq!(fs::read(root.join("First/Good.jpg")).unwrap(), b"unrelated");
    unchanged.remove();
    let (mut contender, contender_bytes) = source(11, &key, b"contender", "Good.jpg");
    contender["updationTime"] = json!(20);
    page(&mut server, 1, 10, json!([contender]), false).create();
    page(&mut server, 1, 20, json!([]), false).create();
    let contender_download = download(&mut server, 11, &contender_bytes, 1);
    albums.remove();
    let mut changed = collection(1, "First", &key);
    changed["updationTime"] = json!(30);
    let albums = server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(json!({"collections":[changed]}).to_string())
        .create();
    let result = run(&home, &root, &[], false);
    assert_eq!(
        result["copies"],
        json!({"expected":2,"completed":1,"pending":1})
    );
    assert_eq!(result["conflicts"], 1);
    assert_eq!(reservation(), allocated);
    assert_eq!(fs::read(root.join("First/Good.jpg")).unwrap(), b"unrelated");
    assert_eq!(
        fs::read(root.join("First/Good-1.jpg")).unwrap(),
        b"contender"
    );
    assert_eq!(
        read_json(&root.join("First/metadata/Good-1.jpg.json"))["ente"]["fileID"],
        "11"
    );
    assert_eq!(
        run(&home, &root, &["--exclude-album", "First"], true)["copies"]["expected"],
        0
    );
    let export_db = export_database(&home);
    let pending: i64 = export_db
        .query_row("SELECT count(*) FROM temporaries WHERE file=10", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(pending, 0);
    drop(export_db);
    albums.remove();
    let mut renamed = collection(1, "Renamed", &key);
    renamed["updationTime"] = json!(40);
    server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(json!({"collections":[renamed]}).to_string())
        .create();
    fs::remove_file(root.join("First/Good.jpg")).unwrap();
    let unrelated_part = root.join("First/.ente-11111111111111111111111111111111.part");
    fs::write(&unrelated_part, b"unrelated temporary").unwrap();
    run(&home, &root, &[], true);
    assert_eq!(fs::read(root.join("Renamed/Good.jpg")).unwrap(), b"good");
    assert_eq!(
        fs::read(root.join("Renamed/Good-1.jpg")).unwrap(),
        b"contender"
    );
    assert_eq!(
        export_database(&home)
            .query_row("SELECT count(*) FROM pending", [], |r| r.get::<_, i64>(0))
            .unwrap(),
        0
    );
    assert_eq!(
        fs::read(root.join("Renamed/.ente-11111111111111111111111111111111.part")).unwrap(),
        b"unrelated temporary"
    );
    downloaded.assert();
    contender_download.assert();
}

fn run_failure(home: &TestHome, root: &Path, options: &[&str], cause: &str) -> Value {
    let mut args = vec!["photos", "export", root.to_str().unwrap(), "--json"];
    args.extend_from_slice(options);
    let output = home.run(&args);
    let error = failure(&output);
    assert!(error.contains(cause), "expected {cause:?}: {error}");
    let result: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(result["complete"], false);
    result
}

fn run(home: &TestHome, root: &Path, options: &[&str], complete: bool) -> Value {
    let mut args = vec!["photos", "export", root.to_str().unwrap(), "--json"];
    args.extend_from_slice(options);
    let output = home.run(&args);
    if complete {
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
    } else {
        failure(&output);
    }
    let result: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(result["complete"], complete);
    result
}
fn source(id: i64, collection: &Key, bytes: &[u8], name: &str) -> (Value, Vec<u8>) {
    let (mut remote, encrypted) = remote_file(id, collection, bytes);
    let key = secretbox::decrypt(
        &b64::decode(remote["encryptedKey"].as_str().unwrap()).unwrap(),
        &Nonce::try_from_slice(
            &b64::decode(remote["keyDecryptionNonce"].as_str().unwrap()).unwrap(),
        )
        .unwrap(),
        collection,
    )
    .unwrap();
    let key = Key::try_from_slice(&key).unwrap();
    let metadata=blob::encrypt_json(&json!({"title":name,"fileType":0,"creationTime":1_700_000_000_123_456i64,"hash":b64::encode(&hash::hash(bytes,Some(64),None).unwrap()),"newAdditiveField":{"opaque":"kept in replica"}}),&key).unwrap();
    remote["metadata"] = json!({"encryptedData":b64::encode(&metadata.encrypted_data),"decryptionHeader":b64::encode(metadata.decryption_header.as_bytes())});
    let public = blob::encrypt_json(&json!({}), &key).unwrap();
    remote["pubMagicMetadata"] = json!({"data":b64::encode(&public.encrypted_data),"header":b64::encode(public.decryption_header.as_bytes())});
    (remote, encrypted)
}
fn download(
    server: &mut mockito::ServerGuard,
    id: i64,
    bytes: &[u8],
    times: usize,
) -> mockito::Mock {
    server
        .mock("GET", format!("/files/download/v3/{id}").as_str())
        .with_body(json!({"url":format!("{}/media/{id}",server.url())}).to_string())
        .expect(times)
        .create();
    server
        .mock("GET", format!("/media/{id}").as_str())
        .with_body(bytes)
        .expect(times)
        .create()
}
fn database(home: &TestHome) -> rusqlite::Connection {
    let db = rusqlite::Connection::open(
        home.dir
            .path()
            .join("accounts/e6b355f0-5d4d-4fc3-b32c-a6c8f52b8210/data.db"),
    )
    .unwrap();
    db.pragma_update(None, "key", format!("x'{}'", "2a".repeat(32)))
        .unwrap();
    db
}
fn export_database(home: &TestHome) -> rusqlite::Connection {
    let directory = home
        .dir
        .path()
        .join("accounts/e6b355f0-5d4d-4fc3-b32c-a6c8f52b8210/exports");
    let path = fs::read_dir(directory)
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .find(|path| path.extension().is_some_and(|extension| extension == "db"))
        .unwrap();
    let db = rusqlite::Connection::open(path).unwrap();
    db.pragma_update(None, "key", format!("x'{}'", "2a".repeat(32)))
        .unwrap();
    db
}
fn record(db: &rusqlite::Connection, album: i64, file: i64) -> Value {
    let encoded: String = db
        .query_row(
            "SELECT record FROM photos_files WHERE collection_id=?1 AND id=?2",
            rusqlite::params![album, file],
            |r| r.get(0),
        )
        .unwrap();
    serde_json::from_str(&encoded).unwrap()
}
fn read_json(path: &Path) -> Value {
    serde_json::from_slice(&fs::read(path).unwrap()).unwrap()
}

#[test]
#[cfg(unix)]
fn export_continues_when_failed_transfer_cleanup_becomes_unwritable() {
    use std::os::unix::fs::PermissionsExt;
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let key = Key::generate();
    server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(
            json!({"collections":[collection(1,"Blocked",&key),collection(2,"Healthy",&key)]})
                .to_string(),
        )
        .create();
    let (broken, mut encrypted) = source(
        10,
        &key,
        &vec![61; ente_core::crypto::stream::ENCRYPTION_CHUNK_SIZE + 20],
        "Broken.jpg",
    );
    let intact = encrypted.clone();
    encrypted.truncate(encrypted.len() - 1);
    let (good, original) = source(20, &key, b"good", "Good.jpg");
    page(&mut server, 1, 0, json!([broken]), false).create();
    page(&mut server, 2, 0, json!([good]), false).create();
    for id in [10, 20] {
        server
            .mock("GET", format!("/files/download/v3/{id}").as_str())
            .with_body(json!({"url":format!("{}/media/{id}",server.url())}).to_string())
            .create();
    }
    let destination = tempfile::tempdir().unwrap();
    let root = destination.path().join("photos");
    let protected = root.join("Blocked");
    let folder = protected.clone();
    let denied = server
        .mock("GET", "/media/10")
        .with_body_from_request(move |_| {
            fs::set_permissions(&folder, fs::Permissions::from_mode(0o500)).unwrap();
            encrypted.clone()
        })
        .create();
    let healthy = server.mock("GET", "/media/20").with_body(original).create();
    let output = home.run(&[
        "photos",
        "export",
        root.to_str().unwrap(),
        "--json",
        "--jobs",
        "1",
    ]);
    fs::set_permissions(&protected, fs::Permissions::from_mode(0o700)).unwrap();
    assert!(
        failure(&output)
            .to_lowercase()
            .contains("permission denied")
    );
    let result: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        result["copies"],
        json!({"expected":2,"completed":1,"pending":1})
    );
    assert_eq!(fs::read(root.join("Healthy/Good.jpg")).unwrap(), b"good");
    let db = export_database(&home);
    let partial: String = db
        .query_row(
            "SELECT a.path||'/'||t.name FROM temporaries t JOIN albums a ON a.key=t.folder WHERE t.album=1 AND t.file=10",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert!(root.join(&partial).is_file());
    denied.remove();
    let retry = server
        .mock("GET", "/media/10")
        .with_body(intact)
        .expect(1)
        .create();
    run(&home, &root, &[], true);
    assert!(!root.join(partial).exists());
    assert_eq!(
        db.query_row("SELECT count(*) FROM temporaries", [], |r| r
            .get::<_, i64>(0))
            .unwrap(),
        0
    );
    assert_eq!(
        fs::read(root.join("Blocked/Broken.jpg")).unwrap(),
        vec![61; ente_core::crypto::stream::ENCRYPTION_CHUNK_SIZE + 20]
    );
    healthy.assert();
    retry.assert();
}

#[test]
fn export_failed_stream_does_not_block_independent_album_or_advance_cursor() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let key = Key::generate();
    let destination = tempfile::tempdir().unwrap();
    let root = destination.path().join("photos");
    server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(
            json!({"collections":[collection(1,"Blocked",&key),collection(2,"Independent",&key)]})
                .to_string(),
        )
        .create();
    let (good, encrypted) = source(10, &key, b"good", "Good.jpg");
    let malformed = page(&mut server, 1, 0, json!([{ "id":"not an integer" }]), false).create();
    page(&mut server, 2, 0, json!([good]), false).create();
    let downloaded = download(&mut server, 10, &encrypted, 1);
    let result = run(&home, &root, &[], false);
    assert!(result["files"].is_null());
    assert!(result["copies"].is_null());
    assert_eq!(
        fs::read(root.join("Independent/Good.jpg")).unwrap(),
        b"good"
    );
    let db = database(&home);
    assert_eq!(
        db.query_row(
            "SELECT files_cursor FROM photos_collections WHERE id=1",
            [],
            |r| r.get::<_, i64>(0)
        )
        .unwrap(),
        0
    );
    malformed.remove();
    let stuck = page(&mut server, 1, 0, json!([]), true).create();
    run(&home, &root, &[], false);
    stuck.remove();
    page(&mut server, 1, 0, json!([good]), false).create();
    run(&home, &root, &[], true);
    downloaded.assert();
    assert_eq!(fs::read(root.join("Blocked/Good.jpg")).unwrap(), b"good");
}

#[test]
fn export_page_and_recognized_failures_roll_back_together_on_storage_failure() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let key = Key::generate();
    server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(json!({"collections":[collection(1,"First",&key)]}).to_string())
        .create();
    let empty = page(&mut server, 1, 0, json!([]), false).create();
    let destination = tempfile::tempdir().unwrap();
    let root = destination.path().join("photos");
    run(&home, &root, &[], true);
    empty.remove();
    let db = database(&home);
    db.execute_batch(
        "UPDATE photos_collections SET files_synced_to=NULL; CREATE TRIGGER fail_second BEFORE INSERT ON photos_files WHEN new.id=11 BEGIN SELECT RAISE(ABORT,'fixture storage failure'); END;",
    )
    .unwrap();
    let (good, encrypted) = source(10, &key, b"good", "Good.jpg");
    let (mut broken, _) = source(11, &key, b"broken", "Broken.jpg");
    broken["metadata"]["encryptedData"] = json!("broken");
    page(&mut server, 1, 0, json!([good, broken]), false).create();
    let result = run_failure(&home, &root, &[], "fixture storage failure");
    assert_eq!(result["failures"], 2);
    assert!(result["files"].is_null());
    assert_eq!(
        db.query_row("SELECT count(*) FROM photos_files", [], |r| r
            .get::<_, i64>(0))
            .unwrap(),
        0
    );
    assert_eq!(
        db.query_row(
            "SELECT files_cursor FROM photos_collections WHERE id=1",
            [],
            |r| r.get::<_, i64>(0)
        )
        .unwrap(),
        0
    );
    db.execute_batch("DROP TRIGGER fail_second;").unwrap();
    download(&mut server, 10, &encrypted, 1);
    let result = run(&home, &root, &[], false);
    assert_eq!(result["copies"]["completed"], 1);
    assert_eq!(result["copies"]["pending"], 1);
    assert_eq!(
        db.query_row(
            "SELECT files_cursor FROM photos_collections WHERE id=1",
            [],
            |r| r.get::<_, i64>(0)
        )
        .unwrap(),
        10
    );
    assert!(!record(&db, 1, 11)["remote"].is_null());
    assert!(record(&db, 1, 11)["documents"].is_null());
}

#[test]
fn export_saves_interpretation_failures_and_omits_unknown_field_values_from_diagnostics() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let key = Key::generate();
    server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(json!({"collections":[collection(1,"First",&key)]}).to_string())
        .create();
    let (good, encrypted) = source(10, &key, b"good", "Good.jpg");
    let (mut invalid, _) = source(11, &key, b"invalid", "Invalid.jpg");
    let file_key = secretbox::decrypt(
        &b64::decode(invalid["encryptedKey"].as_str().unwrap()).unwrap(),
        &Nonce::try_from_slice(
            &b64::decode(invalid["keyDecryptionNonce"].as_str().unwrap()).unwrap(),
        )
        .unwrap(),
        &key,
    )
    .unwrap();
    let private = blob::encrypt_json(
        &json!({"visibility":99}),
        &Key::try_from_slice(&file_key).unwrap(),
    )
    .unwrap();
    invalid["magicMetadata"] = json!({"data":b64::encode(&private.encrypted_data),"header":b64::encode(private.decryption_header.as_bytes())});
    page(&mut server, 1, 0, json!([good, invalid]), false).create();
    download(&mut server, 10, &encrypted, 1);
    let destination = tempfile::tempdir().unwrap();
    let root = destination.path().join("photos");
    let output = home.run(&["photos", "export", root.to_str().unwrap(), "--json"]);
    let diagnostics = failure(&output);
    assert!(diagnostics.contains("newAdditiveField"));
    assert!(!diagnostics.contains("kept in replica"));
    let result: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        result["copies"],
        json!({"expected":2,"completed":1,"pending":1})
    );
    let db = database(&home);
    let failure = record(&db, 1, 11);
    assert!(!failure["documents"].is_null());
    let original: Vec<u8> = ente_core::b64::decode(
        record(&db, 1, 10)["documents"]["original"]
            .as_str()
            .unwrap(),
    )
    .unwrap();
    let future_reader: Value = serde_json::from_slice(&original).unwrap();
    assert_eq!(
        future_reader["newAdditiveField"]["opaque"],
        "kept in replica"
    );
    run(&home, &root, &[], false);
    assert_eq!(record(&db, 1, 11), failure);
}

#[test]
fn export_does_not_reuse_a_copy_with_a_different_current_source_hash() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let key = Key::generate();
    let albums = server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(json!({"collections":[collection(1,"First",&key)]}).to_string())
        .create();
    let (first, first_bytes) = source(10, &key, b"old original", "Original.jpg");
    page(&mut server, 1, 0, json!([first]), false).create();
    let downloaded = download(&mut server, 10, &first_bytes, 1);
    let destination = tempfile::tempdir().unwrap();
    let root = destination.path().join("photos");
    run(&home, &root, &[], true);
    downloaded.assert();
    downloaded.remove();
    albums.remove();
    let mut album = collection(1, "First", &key);
    album["updationTime"] = json!(40);
    server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(json!({"collections":[album]}).to_string())
        .create();
    let (mut current, current_bytes) = source(10, &key, b"new original", "Original.jpg");
    current["updationTime"] = json!(30);
    page(&mut server, 1, 10, json!([current]), false).create();
    let downloaded = download(&mut server, 10, &current_bytes, 1);
    run(&home, &root, &[], true);
    downloaded.assert();
    assert_eq!(
        fs::read(root.join("First/Original.jpg")).unwrap(),
        b"new original"
    );
}
