use super::engine::{Catalog, Engine};
use super::*;
use std::collections::BTreeMap;

fn new_engine(server: &mockito::ServerGuard, key: Key, record: Value) -> Engine {
    let id = record["id"].as_i64().unwrap();
    Engine::new(
        server,
        Catalog {
            user: 9007199254740993,
            key,
            albums: BTreeMap::from([(1, "First".into()), (2, "Second".into())]),
            files: BTreeMap::from([((1, id), record.clone()), ((2, id), record)]),
            failed_album: None,
        },
    )
}

fn run(engine: &mut Engine, complete: bool) -> Value {
    let result = engine.run(false, &[]).unwrap();
    assert_eq!(result.complete, complete);
    result.json
}

#[test]
fn engine_preserves_local_media_and_restores_missing_copies() {
    let mut server = mockito::Server::new();
    let key = Key::generate();
    let (file, bytes) = original_fixture(&key, b"original", false, true, 10);
    let fetched = download(&mut server, 10, &bytes, 1);
    let mut engine = new_engine(&server, key, file.clone());
    run(&mut engine, true);
    let root = engine.root();
    let photo = root.join("First/Photo.jpg");
    let sidecar = root.join("First/metadata/Photo.jpg.json");
    let baseline = fs::read(&sidecar).unwrap();
    let hash = read_json(&sidecar)["ente"]["components"][0]["hash"].clone();
    fs::write(&photo, b"embedded EXIF edit").unwrap();
    fs::write(
        root.join("Second/metadata/Photo.jpg.json"),
        b"{\"custom\":true}",
    )
    .unwrap();
    let changed = public(
        file,
        &engine.catalog.key,
        json!({"caption":"current caption"}),
        30,
    );
    engine.catalog.files = BTreeMap::from([((1, 10), changed.clone()), ((2, 10), changed)]);
    for _ in 0..2 {
        let result = run(&mut engine, false);
        assert_eq!(result["conflicts"], 1);
        assert_eq!(
            result["copies"],
            json!({"expected":2,"completed":1,"pending":1})
        );
        assert_eq!(fs::read(&photo).unwrap(), b"embedded EXIF edit");
        assert_eq!(fs::read(&sidecar).unwrap(), baseline);
        assert_eq!(
            engine
                .db()
                .query_row(
                    "SELECT hash FROM components WHERE folder='active:1'",
                    [],
                    |r| r.get::<_, String>(0),
                )
                .unwrap(),
            hash.as_str().unwrap()
        );
        let metadata = read_json(&root.join("Second/metadata/Photo.jpg.json"));
        assert_eq!(metadata["description"], "current caption");
        assert!(metadata.get("custom").is_none());
    }
    fs::remove_file(&photo).unwrap();
    run(&mut engine, true);
    assert_component(&root, "First", "Photo.jpg", b"original");
    fs::write(&photo, b"local edit before removal").unwrap();
    engine.catalog.files.retain(|(album, _), _| *album != 1);
    run(&mut engine, true);
    assert_eq!(
        fs::read(root.join("Trash/First/Photo.jpg")).unwrap(),
        b"local edit before removal"
    );
    assert_eq!(
        read_json(&root.join("Trash/First/metadata/Photo.jpg.json"))["ente"]["components"][0]["hash"],
        hash
    );
    assert_component(&root, "Second", "Photo.jpg", b"original");
    engine.catalog.files.clear();
    run(&mut engine, true);
    assert_component(&root, "Trash/Second", "Photo.jpg", b"original");
    run(&mut engine, true);
    assert_eq!(
        count(
            &engine.db(),
            "SELECT count(*) FROM placements WHERE retained=1"
        ),
        2
    );
    fetched.assert();
}

#[test]
fn engine_checks_previous_bytes_before_source_and_layout_replacement() {
    for (before_live, after_live, hashed) in [
        (false, false, true),
        (false, false, false),
        (true, true, true),
        (false, true, true),
        (true, false, true),
    ] {
        let mut server = mockito::Server::new();
        let key = Key::generate();
        let (old, bytes) = original_fixture(&key, b"old", before_live, hashed, 10);
        let fetched = download(&mut server, 10, &bytes, 1);
        let mut engine = new_engine(&server, key, old);
        run(&mut engine, true);
        fetched.assert();
        fetched.remove();
        let root = engine.root();
        let name = if before_live {
            "Motion.mov"
        } else {
            "Photo.jpg"
        };
        let photo = root.join("First").join(name);
        let modified = fs::metadata(&photo).unwrap().modified().unwrap();
        let baseline = fs::read(root.join("First/metadata").join(format!("{name}.json"))).unwrap();
        fs::write(&photo, b"bad").unwrap();
        fs::File::options()
            .write(true)
            .open(&photo)
            .unwrap()
            .set_modified(modified)
            .unwrap();
        run(&mut engine, true);
        let (new, bytes) = original_fixture(&engine.catalog.key, b"new", after_live, hashed, 30);
        engine.catalog.files = BTreeMap::from([((1, 10), new.clone()), ((2, 10), new)]);
        let fetched = download(&mut server, 10, &bytes, 1);
        let result = run(&mut engine, false);
        assert_eq!(result["conflicts"], 1);
        assert_eq!(result["copies"]["completed"], 1);
        assert_eq!(fs::read(&photo).unwrap(), b"bad");
        assert_eq!(fs::metadata(&photo).unwrap().modified().unwrap(), modified);
        assert_eq!(
            fs::read(root.join("First/metadata").join(format!("{name}.json"))).unwrap(),
            baseline
        );
        if before_live {
            assert_component(&root, "First", "Motion.heic", b"old");
        }
        assert!(!root.join("Trash/First").exists());
        let names: &[&str] = if after_live {
            &["Motion.heic", "Motion.mov"]
        } else {
            &["Photo.jpg"]
        };
        for name in names {
            assert_component(&root, "Second", name, b"new");
        }
        if before_live == after_live {
            fs::write(&photo, b"old").unwrap();
        } else {
            fs::remove_file(&photo).unwrap();
        }
        run(&mut engine, true);
        for name in names {
            assert_component(&root, "First", name, b"new");
        }
        if before_live != after_live {
            assert!(!root.join("Trash/First").join(name).exists());
            assert_eq!(
                read_json(
                    &root
                        .join("Trash/First/metadata")
                        .join(format!("{name}.json"))
                )["ente"]["components"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .find(|component| component["path"] == name)
                    .unwrap()["hash"],
                b64::encode(&hash::hash(b"old", Some(64), None).unwrap())
            );
            if before_live {
                assert_component(&root, "Trash/First", "Motion.heic", b"old");
            }
        }
        fetched.assert();
    }
}

#[test]
fn engine_restores_a_new_layout_after_missing_interrupted_retention() {
    for old_live in [false, true] {
        let mut server = mockito::Server::new();
        let key = Key::generate();
        let (old, bytes) = original_fixture(&key, b"old", old_live, true, 10);
        let fetched = download(&mut server, 10, &bytes, 1);
        let mut engine = new_engine(&server, key, old);
        run(&mut engine, true);
        fetched.assert();
        fetched.remove();
        let db = engine.db();
        db.execute_batch("CREATE TRIGGER stop_retention BEFORE UPDATE ON pending WHEN old.album=1 AND old.retained=1 AND json_type(old.action,'$.Move') IS NOT NULL AND new.action='null' BEGIN SELECT RAISE(ABORT,'stop after retention move'); END;").unwrap();
        let (new, bytes) = original_fixture(&engine.catalog.key, b"new", !old_live, true, 30);
        engine.catalog.files = BTreeMap::from([((1, 10), new.clone()), ((2, 10), new)]);
        let fetched = download(&mut server, 10, &bytes, 2);
        run(&mut engine, false);
        let root = engine.root();
        let old_name = if old_live { "Motion.heic" } else { "Photo.jpg" };
        fs::remove_file(root.join("Trash/First").join(old_name)).unwrap();
        db.execute_batch("DROP TRIGGER stop_retention;").unwrap();
        if old_live {
            fs::write(root.join("First/Motion.mov"), b"local edit").unwrap();
            assert_eq!(run(&mut engine, false)["conflicts"], 1);
            assert_eq!(
                fs::read(root.join("First/Motion.mov")).unwrap(),
                b"local edit"
            );
            assert!(!root.join("First/Photo.jpg").exists());
            fs::remove_file(root.join("First/Motion.mov")).unwrap();
        }
        run(&mut engine, true);
        let new_names: &[&str] = if old_live {
            &["Photo.jpg"]
        } else {
            &["Motion.heic", "Motion.mov"]
        };
        for folder in ["First", "Second"] {
            for name in new_names {
                assert_component(&root, folder, name, b"new");
            }
        }
        assert!(!root.join("Trash/First").join(old_name).exists());
        assert_eq!(
            read_json(
                &root
                    .join("Trash/First/metadata")
                    .join(format!("{old_name}.json"))
            )["ente"]["components"][0]["hash"],
            b64::encode(&hash::hash(b"old", Some(64), None).unwrap())
        );
        assert_eq!(run(&mut engine, true)["changes"]["retained"], 0);
        assert_eq!(
            count(
                &db,
                "SELECT count(*) FROM placements WHERE album=1 AND retained=1"
            ),
            1
        );
        fetched.assert();
    }
}

#[test]
fn engine_checks_both_live_components_when_only_one_source_component_changes() {
    let mut server = mockito::Server::new();
    let key = Key::generate();
    let (old, bytes) = original_fixture(&key, b"old", true, true, 10);
    let fetched = download(&mut server, 10, &bytes, 1);
    let mut engine = new_engine(&server, key, old);
    run(&mut engine, true);
    fetched.assert();
    fetched.remove();
    let root = engine.root();
    let photo = root.join("First/Motion.heic");
    let modified = fs::metadata(&photo).unwrap().modified().unwrap();
    fs::write(&photo, b"bad").unwrap();
    fs::File::options()
        .write(true)
        .open(&photo)
        .unwrap()
        .set_modified(modified)
        .unwrap();
    let mut archive = zip::ZipWriter::new(std::io::Cursor::new(Vec::new()));
    for (name, bytes) in [("image.heic", b"old"), ("video.mov", b"new")] {
        archive
            .start_file(name, zip::write::SimpleFileOptions::default())
            .unwrap();
        archive.write_all(bytes).unwrap();
    }
    let archive = archive.finish().unwrap().into_inner();
    let (mut new, bytes) = source(10, &engine.catalog.key, &archive, "Motion.heic");
    let image = b64::encode(&hash::hash(b"old", Some(64), None).unwrap());
    let video = b64::encode(&hash::hash(b"new", Some(64), None).unwrap());
    let metadata = blob::encrypt_json(
        &json!({"title":"Motion.heic","fileType":2,"creationTime":1_700_000_000_123_456i64,"hash":format!("{image}:{video}")}),
        &file_key(&new, &engine.catalog.key),
    ).unwrap();
    new["metadata"] = json!({"encryptedData":b64::encode(&metadata.encrypted_data),"decryptionHeader":b64::encode(metadata.decryption_header.as_bytes())});
    let new = revision(new, 30);
    engine.catalog.files = BTreeMap::from([((1, 10), new.clone()), ((2, 10), new)]);
    let fetched = download(&mut server, 10, &bytes, 1);
    assert_eq!(run(&mut engine, false)["conflicts"], 1);
    assert_eq!(fs::read(&photo).unwrap(), b"bad");
    assert_component(&root, "First", "Motion.mov", b"old");
    assert_component(&root, "Second", "Motion.heic", b"old");
    assert_component(&root, "Second", "Motion.mov", b"new");
    fs::write(&photo, b"old").unwrap();
    run(&mut engine, true);
    assert_component(&root, "First", "Motion.heic", b"old");
    assert_component(&root, "First", "Motion.mov", b"new");
    fetched.assert();
}

#[test]
fn engine_recovery_checks_live_siblings_before_acknowledging_publication() {
    let mut server = mockito::Server::new();
    let key = Key::generate();
    let (old, bytes) = original_fixture(&key, b"old", true, true, 10);
    let fetched = download(&mut server, 10, &bytes, 1);
    let mut engine = new_engine(&server, key, old);
    run(&mut engine, true);
    fetched.assert();
    fetched.remove();
    let db = engine.db();
    db.execute_batch("CREATE TRIGGER stop_ack BEFORE UPDATE ON pending WHEN old.album=1 AND json_extract(old.action,'$.Publish.output.Media.role')='image' AND new.action='null' BEGIN SELECT RAISE(ABORT,'stop after image publication'); END;").unwrap();
    let (new, bytes) = original_fixture(&engine.catalog.key, b"new", true, true, 30);
    engine.catalog.files = BTreeMap::from([((1, 10), new.clone()), ((2, 10), new)]);
    let fetched = download(&mut server, 10, &bytes, 2);
    run(&mut engine, false);
    let root = engine.root();
    assert_eq!(fs::read(root.join("First/Motion.heic")).unwrap(), b"new");
    fs::write(root.join("First/Motion.mov"), b"edited video").unwrap();
    let pending: String = db
        .query_row(
            "SELECT action FROM pending WHERE album=1 AND file=10",
            [],
            |r| r.get(0),
        )
        .unwrap();
    db.execute_batch("DROP TRIGGER stop_ack;").unwrap();
    let result = run(&mut engine, false);
    assert_eq!(result["conflicts"], 1);
    assert_eq!(
        fs::read(root.join("First/Motion.mov")).unwrap(),
        b"edited video"
    );
    assert_eq!(
        db.query_row(
            "SELECT action FROM pending WHERE album=1 AND file=10",
            [],
            |r| r.get::<_, String>(0)
        )
        .unwrap(),
        pending
    );
    assert_component(&root, "Second", "Motion.heic", b"new");
    assert_component(&root, "Second", "Motion.mov", b"new");
    fs::remove_file(root.join("First/Motion.mov")).unwrap();
    run(&mut engine, true);
    assert_component(&root, "First", "Motion.heic", b"new");
    assert_component(&root, "First", "Motion.mov", b"new");
    fetched.assert();
}

#[test]
fn engine_recovery_preserves_edits_at_either_move_endpoint() {
    for (moved, removed) in [(false, false), (true, false), (false, true), (true, true)] {
        let mut server = mockito::Server::new();
        let key = Key::generate();
        let (file, bytes) = original_fixture(&key, b"original", false, true, 10);
        let fetched = download(&mut server, 10, &bytes, 1);
        let mut engine = new_engine(&server, key, file.clone());
        run(&mut engine, true);
        let db = engine.db();
        db.execute_batch("CREATE TRIGGER stop_move BEFORE UPDATE ON pending WHEN old.album=1 AND json_type(old.action,'$.Move') IS NOT NULL AND new.action='null' BEGIN SELECT RAISE(ABORT,'stop after media move'); END;").unwrap();
        let renamed = public(
            file,
            &engine.catalog.key,
            json!({"editedName":"Renamed.jpg"}),
            30,
        );
        engine.catalog.files = BTreeMap::from([((1, 10), renamed.clone()), ((2, 10), renamed)]);
        run(&mut engine, false);
        let root = engine.root();
        let old = root.join("First/Photo.jpg");
        let new = root.join("First/Renamed.jpg");
        if !moved {
            fs::rename(&new, &old).unwrap();
        }
        let changed = if moved { &new } else { &old };
        fs::write(changed, b"local edit").unwrap();
        db.execute_batch("DROP TRIGGER stop_move;").unwrap();
        if removed {
            engine.catalog.files.retain(|(album, _), _| *album != 1);
            run(&mut engine, true);
            assert_eq!(
                fs::read(root.join("Trash/First/Photo.jpg")).unwrap(),
                b"local edit"
            );
            assert_eq!(
                read_json(&root.join("Trash/First/metadata/Photo.jpg.json"))["ente"]["components"]
                    [0]["hash"],
                b64::encode(&hash::hash(b"original", Some(64), None).unwrap())
            );
            assert_component(&root, "Second", "Renamed.jpg", b"original");
            fetched.assert();
            continue;
        }
        let result = run(&mut engine, false);
        assert_eq!(result["conflicts"], 1);
        assert_eq!(fs::read(changed).unwrap(), b"local edit");
        assert_component(&root, "Second", "Renamed.jpg", b"original");
        assert_eq!(
            read_json(&root.join("First/metadata/Photo.jpg.json"))["ente"]["components"][0]["hash"],
            b64::encode(&hash::hash(b"original", Some(64), None).unwrap())
        );
        fs::write(changed, b"original").unwrap();
        run(&mut engine, true);
        assert_component(&root, "First", "Renamed.jpg", b"original");
        fetched.assert();
    }
}
