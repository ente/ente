use super::engine::{Catalog, Engine};
use super::*;
use ente_photos::files;
use std::{collections::BTreeMap, path::PathBuf};

const USER: i64 = 1580559962386471;
const FAMILY: i64 = 1580559962386473;
const PAIR: i64 = 10000066;
const PHOTO: i64 = 10000062;

fn new_engine(server: &mockito::ServerGuard, producer: &str) -> (Engine, BTreeMap<i64, Vec<u8>>) {
    let fixtures = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/export-adoption");
    let manifest = read_json(&fixtures.join("desktop-manifest.json"));
    let albums = [
        (FAMILY, "Family"),
        (1580559962386472, "Travel"),
        (1580559962386474, "Live Pair"),
    ]
    .into_iter()
    .map(|(id, name)| (id, name.into()))
    .collect();
    let mut engine = Engine::new(
        server,
        Catalog {
            user: USER,
            key: Key::generate(),
            albums,
            files: BTreeMap::new(),
            failed_album: None,
        },
    );
    write_fixture(&engine.root(), producer);
    let mut files = BTreeMap::new();
    let mut downloads = BTreeMap::new();
    let mut records = BTreeMap::new();
    for (identity, name) in manifest["fileExportNames"].as_object().unwrap() {
        let ids: Vec<i64> = identity.split('_').map(|s| s.parse().unwrap()).collect();
        let (id, album) = (ids[0], ids[1]);
        let record = records.entry(id).or_insert_with(|| {
                let folder = engine.root().join(&engine.catalog.albums[&album]);
                let exported = name.as_str().unwrap();
                let (original,kind,digest) = if exported.starts_with('{') {
                    let pair: Value = serde_json::from_str(exported).unwrap();
                    let image = fs::read(folder.join(pair["image"].as_str().unwrap())).unwrap();
                    let video = fs::read(folder.join(pair["video"].as_str().unwrap())).unwrap();
                    let mut zip = zip::ZipWriter::new(std::io::Cursor::new(Vec::new()));
                    for (name,bytes) in [("image.jpg",&image),("video.mov",&video)] {
                        zip.start_file(name,zip::write::SimpleFileOptions::default().compression_method(zip::CompressionMethod::Stored)).unwrap();
                        zip.write_all(bytes).unwrap();
                    }
                    (zip.finish().unwrap().into_inner(),2,format!("{}:{}",digest(&image),digest(&video)))
                } else {
                    let bytes = fs::read(folder.join(exported)).unwrap();
                    (bytes.clone(),if exported.ends_with(".mov") {1} else {0},digest(&bytes))
                };
                let name = match id {
                    PHOTO | 10000064 => "Photo.jpg",
                    10000063 => "Live.jpg",
                    10000065 => "Live.mov",
                    PAIR => "Pair.jpg",
                    _ => unreachable!(),
                };
                let (mut remote,encrypted) = source(id,&engine.catalog.key,&original,name);
                remote["ownerID"] = json!(USER);
                let metadata = blob::encrypt_json(&json!({"title":name,"fileType":kind,"hash":digest,"creationTime":1_700_000_000_000_000i64}),&file_key(&remote,&engine.catalog.key)).unwrap();
                remote["metadata"] = json!({"encryptedData":b64::encode(&metadata.encrypted_data),"decryptionHeader":b64::encode(metadata.decryption_header.as_bytes())});
                downloads.insert(id,encrypted);
                remote
            });
        files.insert((album, id), record.clone());
    }
    engine.catalog.files = files;
    (engine, downloads)
}

fn rename(engine: &mut Engine, album: i64, file: i64, name: &str) {
    let previous = engine.catalog.files[&(album, file)].clone();
    engine.catalog.files.insert(
        (album, file),
        public(
            previous,
            &engine.catalog.key,
            json!({"editedName":name}),
            200,
        ),
    );
}

fn digest(bytes: &[u8]) -> String {
    b64::encode(&hash::hash(bytes, Some(64), None).unwrap())
}

fn write_fixture(root: &Path, producer: &str) {
    let fixtures = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/export-adoption");
    let manifest = read_json(&fixtures.join("desktop-manifest.json"));
    fs::create_dir_all(root).unwrap();
    if producer == "desktop" {
        fs::write(
            root.join("export_status.json"),
            serde_json::to_vec(&manifest).unwrap(),
        )
        .unwrap();
    }
    for (id, name) in manifest["collectionExportNames"].as_object().unwrap() {
        let folder = root.join(name.as_str().unwrap());
        fs::create_dir_all(&folder).unwrap();
        if producer == "go" {
            fs::create_dir_all(folder.join(".meta")).unwrap();
            let mut album = read_json(&fixtures.join("go-album.json"));
            album["id"] = json!(id.parse::<i64>().unwrap());
            album["albumName"] = name.clone();
            fs::write(
                folder.join(".meta/album_meta.json"),
                serde_json::to_vec(&album).unwrap(),
            )
            .unwrap();
        } else {
            fs::create_dir_all(folder.join("metadata")).unwrap();
        }
    }
    for (key, value) in manifest["fileExportNames"].as_object().unwrap() {
        let ids: Vec<_> = key.split('_').collect();
        let id = ids[0].parse::<i64>().unwrap();
        let folder = root.join(manifest["collectionExportNames"][ids[1]].as_str().unwrap());
        let value = value.as_str().unwrap();
        let parts = if value.starts_with('{') {
            let pair: Value = serde_json::from_str(value).unwrap();
            vec![
                pair["image"].as_str().unwrap().to_owned(),
                pair["video"].as_str().unwrap().to_owned(),
            ]
        } else {
            vec![value.to_owned()]
        };
        let mut hashes = Vec::new();
        for (index, name) in parts.iter().enumerate() {
            let bytes = format!("export fixture {id} component {index}").into_bytes();
            hashes.push(digest(&bytes));
            fs::write(folder.join(name), bytes).unwrap();
            if producer == "desktop" {
                let mut sidecar = read_json(&fixtures.join("desktop-file.json"));
                sidecar["title"] = json!(name);
                fs::write(
                    folder.join(format!("metadata/{name}.json")),
                    serde_json::to_vec(&sidecar).unwrap(),
                )
                .unwrap();
            }
        }
        if producer == "go" {
            let mut sidecar = read_json(&fixtures.join("go-file.json"));
            sidecar["title"] = json!(parts[0]);
            sidecar["info"]["id"] = json!(id);
            sidecar["info"]["fileNames"] = json!(parts);
            sidecar["info"]["hash"] = json!(hashes.join(":"));
            fs::write(
                folder.join(format!(".meta/{}.json", parts[0])),
                serde_json::to_vec(&sidecar).unwrap(),
            )
            .unwrap();
        }
    }
}

fn snapshot(root: &Path) -> BTreeMap<PathBuf, (Vec<u8>, std::time::SystemTime)> {
    fn visit(
        root: &Path,
        path: &Path,
        result: &mut BTreeMap<PathBuf, (Vec<u8>, std::time::SystemTime)>,
    ) {
        for entry in fs::read_dir(path).unwrap() {
            let entry = entry.unwrap();
            let path = entry.path();
            let metadata = fs::symlink_metadata(&path).unwrap();
            if metadata.is_dir() {
                visit(root, &path, result);
            } else if metadata.is_file() {
                result.insert(
                    path.strip_prefix(root).unwrap().to_owned(),
                    (fs::read(&path).unwrap(), metadata.modified().unwrap()),
                );
            }
        }
    }
    let mut result = BTreeMap::new();
    visit(root, root, &mut result);
    result
}

#[test]
fn adoption_reuses_captured_producer_shapes_and_converts_current_names() {
    for producer in ["go", "desktop"] {
        let mut server = mockito::Server::new();
        let (mut engine, downloads) = new_engine(&server, producer);
        let requests: Vec<_> = downloads
            .iter()
            .map(|(id, bytes)| download(&mut server, *id, bytes, 0))
            .collect();
        let root = engine.root();
        if producer == "desktop" {
            fs::rename(root.join("Family"), root.join("Family(1)")).unwrap();
            fs::rename(
                root.join("Family(1)/Photo.jpg"),
                root.join("Family(1)/Photo(1).jpg"),
            )
            .unwrap();
            fs::rename(
                root.join("Family(1)/metadata/Photo.jpg.json"),
                root.join("Family(1)/metadata/Photo(1).jpg.json"),
            )
            .unwrap();
            let mut manifest = read_json(&root.join("export_status.json"));
            manifest["collectionExportNames"][FAMILY.to_string()] = json!("Family(1)");
            let key = manifest["fileExportNames"]
                .as_object()
                .unwrap()
                .keys()
                .find(|key| key.starts_with(&format!("{PHOTO}_{FAMILY}_")))
                .unwrap()
                .clone();
            manifest["fileExportNames"][key] = json!("Photo(1).jpg");
            fs::write(
                root.join("export_status.json"),
                serde_json::to_vec(&manifest).unwrap(),
            )
            .unwrap();
            fs::write(
                root.join("Family(1)/metadata/Photo(1).jpg.json"),
                b"broken JSON",
            )
            .unwrap();
        } else {
            engine.catalog.albums.insert(FAMILY, "Renamed".into());
            rename(&mut engine, FAMILY, PHOTO, "Portrait.jpg");
        }
        let result = engine.run(true, &[]).unwrap();
        assert!(result.complete, "{}", result.json);
        assert_eq!(result.expected, 6);
        if producer == "desktop" {
            assert_component(
                &root,
                "Family(1)",
                "Photo(1).jpg",
                format!("export fixture {PHOTO} component 0").as_bytes(),
            );
            assert_eq!(
                read_json(&root.join("Family(1)/metadata.json"))["title"],
                "Family"
            );
            assert_eq!(
                read_json(&root.join("Family(1)/metadata/Photo(1).jpg.json"))["ente"]["name"],
                "Photo.jpg"
            );
            let before = snapshot(&root);
            assert!(engine.run(false, &[]).unwrap().complete);
            assert_eq!(snapshot(&root), before);
            engine.catalog.albums.insert(FAMILY, "Renamed".into());
            rename(&mut engine, FAMILY, PHOTO, "Portrait.jpg");
            assert!(engine.run(false, &[]).unwrap().complete);
            assert!(!root.join("Family(1)").exists());
        }
        assert!(!root.join("Family").exists());
        assert!(root.join("Renamed/Portrait.jpg").is_file());
        assert!(root.join("Renamed/Live-1.jpg").is_file());
        assert!(root.join("Renamed/Live.mov").is_file());
        assert_eq!(
            read_json(&root.join("Renamed/metadata/Portrait.jpg.json"))["ente"]["fileID"],
            PHOTO.to_string()
        );
        assert_eq!(count(&engine.db(), "SELECT count(*) FROM components"), 8);
        assert_eq!(count(&engine.db(), "SELECT bound FROM export"), 1);
        assert!(!root.join("export_status.json").exists());
        assert!(!root.join("Renamed/.meta").exists());
        let before = snapshot(&root);
        assert!(engine.run(false, &[]).unwrap().complete);
        assert_eq!(snapshot(&root), before);
        engine.database = "recovered.db".into();
        assert!(engine.run(true, &[]).unwrap().complete);
        for request in requests {
            request.assert();
        }
    }
}

#[test]
fn adoption_preserves_desktop_paths_for_names_changed_before_takeover() {
    let server = mockito::Server::new();
    let (mut engine, _) = new_engine(&server, "desktop");
    let root = engine.root();
    let original = fs::read(root.join("Family/Photo.jpg")).unwrap();
    engine.catalog.albums.insert(FAMILY, "Renamed".into());
    rename(&mut engine, FAMILY, PHOTO, "Portrait.jpg");
    assert!(engine.run(true, &[]).unwrap().complete);
    assert_eq!(fs::read(root.join("Family/Photo.jpg")).unwrap(), original);
    assert_eq!(
        read_json(&root.join("Family/metadata.json"))["title"],
        "Renamed"
    );
    assert_eq!(
        read_json(&root.join("Family/metadata/Photo.jpg.json"))["ente"]["name"],
        "Portrait.jpg"
    );
    let before = snapshot(&root);
    assert!(engine.run(false, &[]).unwrap().complete);
    assert_eq!(snapshot(&root), before);
}

#[test]
fn adoption_preflight_refuses_corrupt_media_scope_and_metadata_blockers_without_writes() {
    for producer in ["go", "desktop"] {
        let server = mockito::Server::new();
        let (mut engine, _) = new_engine(&server, producer);
        let root = engine.root();
        let before = snapshot(&root);
        assert!(
            engine
                .run(true, &["Family"])
                .err()
                .unwrap()
                .to_string()
                .contains("exactly")
        );
        assert_eq!(snapshot(&root), before);
        fs::write(root.join("Family/Photo.jpg"), b"local edit").unwrap();
        fs::write(root.join("Travel/Photo.jpg"), b"second edit").unwrap();
        let before = snapshot(&root);
        let error = engine.run(true, &[]).err().unwrap().to_string();
        assert!(error.contains("2 failing items"), "{error}");
        assert_eq!(snapshot(&root), before);
        assert!(!root.join("export.json").exists());
        assert_eq!(count(&engine.db(), "SELECT count(*) FROM albums"), 0);
        write_fixture(&root, producer);
        fs::write(root.join("Family/metadata.json"), b"user media").unwrap();
        let before = snapshot(&root);
        assert!(engine.run(true, &[]).is_err());
        assert_eq!(snapshot(&root), before);
    }
}

#[test]
fn adoption_preserves_partial_pairs_and_restores_missing_originals() {
    for producer in ["go", "desktop"] {
        let mut server = mockito::Server::new();
        let (mut engine, downloads) = new_engine(&server, producer);
        let root = engine.root();
        let survivor = fs::read(root.join("Family/Pair.jpg")).unwrap();
        let original = fs::read(root.join("Family/Photo.jpg")).unwrap();
        let sidecar = if producer == "desktop" {
            Some(fs::read(root.join("Family/metadata/Photo.jpg.json")).unwrap())
        } else {
            None
        };
        fs::remove_file(root.join("Family/Photo.jpg")).unwrap();
        fs::remove_file(root.join("Family/Pair.mov")).unwrap();
        fs::remove_file(root.join("Live Pair/Pair.jpg")).unwrap();
        fs::remove_file(root.join("Live Pair/Pair.mov")).unwrap();
        let ordinary = download(&mut server, PHOTO, &downloads[&PHOTO], 1);
        let requested = download(&mut server, PAIR, &downloads[&PAIR], 1);
        let result = engine.run(true, &[]).unwrap();
        assert!(result.complete, "{producer}: {}", result.json);
        requested.assert();
        ordinary.assert();
        assert_eq!(fs::read(root.join("Family/Photo.jpg")).unwrap(), original);
        if let Some(sidecar) = sidecar {
            assert_eq!(
                fs::read(root.join("Trash/Family/metadata/Photo.jpg.json")).unwrap(),
                sidecar
            );
        }
        assert_eq!(
            fs::read(root.join("Trash/Family/Pair.jpg")).unwrap(),
            survivor
        );
        assert!(
            root.join(if producer == "go" {
                "Trash/Family/.meta/Pair.jpg.json"
            } else {
                "Trash/Family/metadata/Pair.jpg.json"
            })
            .is_file()
        );
        assert_eq!(
            fs::read(root.join("Family/Pair.mov")).unwrap(),
            fs::read(root.join("Live Pair/Pair.mov")).unwrap()
        );
    }
    let server = mockito::Server::new();
    let (mut engine, _) = new_engine(&server, "go");
    let root = engine.root();
    fs::remove_file(root.join("Family/Pair.mov")).unwrap();
    let sidecar = root.join("Family/.meta/Pair.jpg.json");
    let mut value = read_json(&sidecar);
    value["info"]["hash"] = json!(format!(
        "{}:{}",
        value["info"]["hash"]
            .as_str()
            .unwrap()
            .split(':')
            .next()
            .unwrap(),
        digest(b"stale video")
    ));
    fs::write(&sidecar, serde_json::to_vec(&value).unwrap()).unwrap();
    let before = snapshot(&root);
    assert!(
        engine
            .run(true, &[])
            .err()
            .unwrap()
            .to_string()
            .contains("video component")
    );
    assert_eq!(snapshot(&root), before);
}

#[test]
fn adoption_history_resumes_after_media_move_and_keeps_the_full_scope() {
    let mut server = mockito::Server::new();
    let (mut engine, downloads) = new_engine(&server, "desktop");
    let root = engine.root();
    engine.catalog.files.remove(&(FAMILY, PAIR));
    fs::create_dir_all(root.join("Trash/Family")).unwrap();
    fs::write(root.join("Trash/Family/Pair.jpg"), b"existing trash").unwrap();
    fs::write(root.join("Family/user.txt"), b"unrelated").unwrap();
    let manifest = fs::read(root.join("export_status.json")).unwrap();
    fs::write(root.join("Trash/Family/metadata"), b"block sidecar move").unwrap();
    assert!(engine.prepare(engine.options(true, &[])).is_err());
    assert_eq!(count(&engine.db(), "SELECT count(*) FROM albums"), 0);
    assert_eq!(fs::read(root.join("export_status.json")).unwrap(), manifest);
    assert!(!root.join("Family/Pair.jpg").exists());
    assert!(root.join("Trash/Family/Pair-1.jpg").is_file());
    assert_eq!(count(&engine.db(), "SELECT bound FROM export"), 0);
    let before = snapshot(&root);
    assert!(
        engine
            .run(false, &[])
            .err()
            .unwrap()
            .is::<ente_photos_export::AdoptionRequired>()
    );
    assert!(engine.run(true, &["Family"]).is_err());
    assert_eq!(snapshot(&root), before);
    fs::remove_file(root.join("Trash/Family/metadata")).unwrap();
    let export = engine.prepare(engine.options(true, &[])).unwrap();
    drop(export);
    fs::write(root.join("Family/Photo.jpg"), b"edit after acceptance").unwrap();
    let result = engine.run(false, &[]).unwrap();
    assert!(!result.complete);
    assert_eq!(
        fs::read(root.join("Family/Photo.jpg")).unwrap(),
        b"edit after acceptance"
    );
    assert_eq!(fs::read(root.join("export_status.json")).unwrap(), manifest);
    assert!(root.join("Trash/Family/Pair.mov").is_file());
    assert!(root.join("Trash/Family/metadata/Pair.jpg.json").is_file());
    assert_eq!(
        fs::read(root.join("Trash/Family/Pair.jpg")).unwrap(),
        b"existing trash"
    );
    assert!(root.join("Live Pair/Pair.jpg").is_file());
    assert_eq!(
        fs::read(root.join("Family/user.txt")).unwrap(),
        b"unrelated"
    );
    fs::remove_file(root.join("Family/Photo.jpg")).unwrap();
    let downloaded = download(&mut server, PHOTO, &downloads[&PHOTO], 1);
    assert!(engine.run(false, &[]).unwrap().complete);
    downloaded.assert();
    assert!(!root.join("export_status.json").exists());
    assert_eq!(count(&engine.db(), "SELECT bound FROM export"), 1);
}

#[test]
fn adoption_replays_recorded_moves_without_rehashing_every_album() {
    for (producer, directory) in [("go", false), ("desktop", true)] {
        let server = mockito::Server::new();
        let (mut engine, _) = new_engine(&server, producer);
        let root = engine.root();
        let export = engine.prepare(engine.options(true, &[])).unwrap();
        drop(export);
        rename(&mut engine, FAMILY, PHOTO, "Portrait.jpg");
        if directory {
            engine.catalog.albums.insert(FAMILY, "Renamed".into());
        }
        let export = engine.prepare(engine.options(false, &[])).unwrap();
        let db = engine.db();
        if directory {
            db.execute_batch(&format!("CREATE TRIGGER interrupt_album BEFORE UPDATE ON albums WHEN old.id={FAMILY} AND new.path='Renamed' BEGIN SELECT RAISE(ABORT,'interrupt after directory rename'); END;")).unwrap();
        } else {
            db.execute_batch("CREATE TRIGGER interrupt_component BEFORE UPDATE ON components WHEN old.name='Photo.jpg' AND new.name='Portrait.jpg' BEGIN SELECT RAISE(ABORT,'interrupt after component rename'); END;").unwrap();
        }
        assert!(!engine.execute(export).unwrap().complete);
        let folder = if directory { "Renamed" } else { "Family" };
        assert!(root.join(folder).is_dir());
        db.execute_batch(if directory {
            "DROP TRIGGER interrupt_album"
        } else {
            "DROP TRIGGER interrupt_component"
        })
        .unwrap();
        drop(db);
        fs::write(root.join("Travel/Photo.jpg"), b"late independent edit").unwrap();
        let result = engine.run(false, &[]).unwrap();
        assert!(!result.complete);
        assert!(root.join(format!("{folder}/Portrait.jpg")).is_file());
        assert_eq!(
            fs::read(root.join("Travel/Photo.jpg")).unwrap(),
            b"late independent edit"
        );
        assert_eq!(
            read_json(&root.join(format!("{folder}/metadata/Portrait.jpg.json")))["ente"]["fileID"],
            PHOTO.to_string()
        );
    }
}

#[test]
fn adoption_requires_initial_presence_and_never_treats_a_failed_refresh_as_history() {
    let server = mockito::Server::new();
    let (mut engine, _) = new_engine(&server, "go");
    let root = engine.root();
    engine.catalog.failed_album = Some(FAMILY);
    let before = snapshot(&root);
    assert!(engine.run(true, &[]).is_err());
    assert_eq!(snapshot(&root), before);
    assert!(!root.join("Trash").exists());
    engine.catalog.failed_album = None;
    for (name, _) in snapshot(&root) {
        if !name.to_string_lossy().ends_with(".json") {
            fs::remove_file(root.join(name)).unwrap();
        }
    }
    let before = snapshot(&root);
    assert!(
        engine
            .run(true, &[])
            .err()
            .unwrap()
            .to_string()
            .contains("at least one")
    );
    assert_eq!(snapshot(&root), before);
}

#[test]
fn adoption_hashless_verification_downloads_once_per_source_and_keeps_scope_per_invocation() {
    let mut server = mockito::Server::new();
    let (mut engine, downloads) = new_engine(&server, "desktop");
    for ((_, id), remote) in &mut engine.catalog.files {
        if ![PHOTO, PAIR].contains(id) {
            continue;
        }
        let (_, documents) = files::decrypt(
            &serde_json::from_value(remote.clone()).unwrap(),
            &engine.catalog.key,
        )
        .unwrap();
        let mut metadata: Value = serde_json::from_slice(&documents.original).unwrap();
        metadata.as_object_mut().unwrap().remove("hash");
        let metadata =
            blob::encrypt_json(&metadata, &file_key(remote, &engine.catalog.key)).unwrap();
        remote["metadata"] = json!({"encryptedData":b64::encode(&metadata.encrypted_data),"decryptionHeader":b64::encode(metadata.decryption_header.as_bytes())});
    }
    let ordinary = download(&mut server, PHOTO, &downloads[&PHOTO], 2);
    let failed = server
        .mock("GET", format!("/files/download/v3/{PAIR}").as_str())
        .with_status(404)
        .expect(1)
        .create();
    let before = snapshot(&engine.root());
    let error = engine.run(true, &[]).err().unwrap().to_string();
    assert!(error.contains("1 failing items"), "{error}");
    assert_eq!(snapshot(&engine.root()), before);
    assert!(!engine.root().join("export.json").exists());
    failed.assert();
    drop(failed);
    let url = server
        .mock("GET", format!("/files/download/v3/{PAIR}").as_str())
        .with_body(json!({"url":format!("{}/comparison",server.url())}).to_string())
        .expect(1)
        .create();
    let db_path = engine.directory.path().join(&engine.database);
    let bytes = downloads[&PAIR].clone();
    let live = server
        .mock("GET", "/comparison")
        .with_body_from_request(move |_| {
            let db = rusqlite::Connection::open(&db_path).unwrap();
            db.busy_timeout(std::time::Duration::ZERO).unwrap();
            db.execute_batch("BEGIN IMMEDIATE; ROLLBACK;").unwrap();
            assert_eq!(count(&db, "SELECT count(*) FROM albums"), 0);
            bytes.clone()
        })
        .expect(1)
        .create();
    engine.catalog.albums.insert(99, "Other".into());
    assert!(engine.run(true, &[]).unwrap().complete);
    ordinary.assert();
    live.assert();
    url.assert();
    assert!(fs::read_dir(engine.root()).unwrap().all(|entry| {
        let entry = entry.unwrap();
        entry.file_type().unwrap().is_dir() || entry.file_name() == "export.json"
    }));
    assert!(!engine.root().join("Other").exists());
    assert!(engine.run(false, &["Family"]).unwrap().complete);
    assert!(!engine.root().join("Other").exists());
    assert!(engine.run(true, &[]).unwrap().complete);
    assert!(engine.root().join("Other/metadata.json").exists());
}

#[test]
fn adoption_relocates_an_unavailable_go_album_named_trash_without_inventing_native_history() {
    for keep_unknown in [false, true] {
        let server = mockito::Server::new();
        let (mut engine, _) = new_engine(&server, "go");
        let root = engine.root();
        fs::rename(root.join("Family"), root.join("Trash")).unwrap();
        let path = root.join("Trash/.meta/album_meta.json");
        let mut album = read_json(&path);
        album["albumName"] = json!("Trash");
        fs::write(path, serde_json::to_vec(&album).unwrap()).unwrap();
        engine.catalog.albums.remove(&FAMILY);
        engine
            .catalog
            .files
            .retain(|(album, _), _| *album != FAMILY);
        if keep_unknown {
            fs::write(root.join("Trash/user.txt"), b"keep").unwrap();
        }
        fs::write(root.join("Trash/Photo.jpg"), b"historical local edit").unwrap();
        assert!(engine.run(true, &[]).unwrap().complete);
        assert_eq!(
            fs::read(root.join("Trash/Trash-1/Photo.jpg")).unwrap(),
            b"historical local edit"
        );
        if keep_unknown {
            assert_eq!(fs::read(root.join("Trash-1/user.txt")).unwrap(), b"keep");
        } else {
            assert!(!root.join("Trash-1").exists());
        }
        assert!(root.join("Trash/Trash-1/.meta/Photo.jpg.json").is_file());
        assert!(!root.join("Trash/Trash-1/metadata.json").exists());
        assert!(!root.join("Trash-1/.meta/album_meta.json").exists());
        assert_eq!(
            count(
                &engine.db(),
                &format!("SELECT count(*) FROM placements WHERE album={FAMILY}")
            ),
            0
        );
    }
}

#[test]
fn adoption_bounds_failure_examples() {
    let server = mockito::Server::new();
    let (mut engine, _) = new_engine(&server, "desktop");
    let root = engine.root();
    let path = root.join("export_status.json");
    let mut manifest = read_json(&path);
    for id in 100..113 {
        let mut remote = engine.catalog.files[&(FAMILY, PHOTO)].clone();
        remote["id"] = json!(id);
        engine.catalog.files.insert((FAMILY, id), remote);
        let name = format!("Bad-{id}.jpg");
        fs::write(root.join("Family").join(&name), b"bad original").unwrap();
        manifest["fileExportNames"][format!("{id}_{FAMILY}_100")] = json!(name);
    }
    fs::write(&path, serde_json::to_vec(&manifest).unwrap()).unwrap();
    let before = snapshot(&root);
    let error = engine.run(true, &[]).err().unwrap().to_string();
    assert!(error.contains("13 failing items"), "{error}");
    assert!(error.contains("3 more omitted"), "{error}");
    assert_eq!(snapshot(&root), before);

    manifest["collectionExportNames"][FAMILY.to_string()] = json!("../outside");
    fs::write(&path, serde_json::to_vec(&manifest).unwrap()).unwrap();
    let before = snapshot(&root);
    let error = engine.run(true, &[]).err().unwrap().to_string();
    assert!(error.contains("1 failing items"), "{error}");
    assert!(
        !error.contains("file has no valid album mapping"),
        "{error}"
    );
    assert_eq!(snapshot(&root), before);

    manifest["fileExportNames"]["900_77_100"] = json!("Missing.jpg");
    fs::write(&path, serde_json::to_vec(&manifest).unwrap()).unwrap();
    let before = snapshot(&root);
    let error = engine.run(true, &[]).err().unwrap().to_string();
    assert!(error.contains("2 failing items"), "{error}");
    assert!(error.contains("file has no valid album mapping"), "{error}");
    assert_eq!(snapshot(&root), before);
}

#[test]
fn adoption_rejects_missing_album_identity_wrong_account_and_escaping_paths() {
    for case in ["orphan", "account", "escape"] {
        let server = mockito::Server::new();
        let (mut engine, _) = new_engine(&server, "go");
        let root = engine.root();
        match case {
            "orphan" => {
                fs::remove_file(root.join("Travel/.meta/album_meta.json")).unwrap();
            }
            "account" => {
                let path = root.join("Family/.meta/album_meta.json");
                let mut value = read_json(&path);
                value["accountOwnerIDs"] = json!([42]);
                fs::write(path, serde_json::to_vec(&value).unwrap()).unwrap();
            }
            _ => {
                let path = root.join("Family/.meta/Photo.jpg.json");
                let mut value = read_json(&path);
                value["info"]["fileNames"] = json!(["../outside.jpg"]);
                fs::write(path, serde_json::to_vec(&value).unwrap()).unwrap();
            }
        }
        let before = snapshot(&root);
        let error = engine.run(true, &[]).err().unwrap().to_string();
        assert_eq!(snapshot(&root), before);
        if case == "orphan" {
            assert!(error.contains("without album_meta.json"), "{error}");
        }
    }
}

#[test]
fn adoption_preserves_unknown_meta_files_and_records_empty_go_albums() {
    let server = mockito::Server::new();
    let (mut engine, _) = new_engine(&server, "go");
    let root = engine.root();
    fs::create_dir(root.join("Personal")).unwrap();
    fs::write(root.join("Personal/.meta"), b"keep unrelated file").unwrap();
    fs::create_dir_all(root.join("Empty/.meta")).unwrap();
    let mut album = read_json(&root.join("Family/.meta/album_meta.json"));
    album["id"] = json!(77);
    album["albumName"] = json!("Empty");
    fs::write(
        root.join("Empty/.meta/album_meta.json"),
        serde_json::to_vec(&album).unwrap(),
    )
    .unwrap();
    fs::write(root.join("Empty/.meta/user.txt"), b"keep").unwrap();
    engine.catalog.albums.insert(77, "Empty".into());
    assert!(engine.run(true, &[]).unwrap().complete);
    assert_eq!(
        read_json(&root.join("Empty/metadata.json"))["ente"]["albumID"],
        "77"
    );
    assert_eq!(
        fs::read(root.join("Empty/.meta/user.txt")).unwrap(),
        b"keep"
    );
    assert_eq!(
        fs::read(root.join("Personal/.meta")).unwrap(),
        b"keep unrelated file"
    );
}

#[test]
fn adoption_retains_accepted_bytes_when_the_source_layout_changes_before_conversion() {
    for producer in ["go", "desktop"] {
        let mut server = mockito::Server::new();
        let (mut engine, _) = new_engine(&server, producer);
        let root = engine.root();
        let original = fs::read(root.join("Family/Photo.jpg")).unwrap();
        let export = engine.prepare(engine.options(true, &[])).unwrap();
        drop(export);
        let (mut replacement, encrypted) =
            original_fixture(&engine.catalog.key, b"new Live component", true, true, 300);
        replacement["id"] = json!(PHOTO);
        replacement["ownerID"] = json!(USER);
        engine.catalog.files.insert((FAMILY, PHOTO), replacement);
        let requested = download(&mut server, PHOTO, &encrypted, 1);
        assert!(engine.run(true, &[]).unwrap().complete);
        requested.assert();
        assert_eq!(
            fs::read(root.join("Trash/Family/Photo.jpg")).unwrap(),
            original
        );
        assert_component(&root, "Family", "Motion.heic", b"new Live component");
        assert_component(&root, "Family", "Motion.mov", b"new Live component");
    }
}

#[cfg(unix)]
#[test]
fn adoption_rejects_symlinks_while_detecting_orphaned_go_records() {
    for directory in [false, true] {
        let server = mockito::Server::new();
        let (mut engine, _) = new_engine(&server, "go");
        let root = engine.root();
        fs::remove_file(root.join("Travel/.meta/album_meta.json")).unwrap();
        let source = root.join(if directory {
            "Travel/.meta"
        } else {
            "Travel/.meta/Photo.jpg.json"
        });
        let outside = engine.directory.path().join("outside");
        fs::rename(&source, &outside).unwrap();
        std::os::unix::fs::symlink(&outside, &source).unwrap();
        let before = snapshot(&root);
        let error = engine.run(true, &[]).err().unwrap().to_string();
        assert!(error.contains("symlink"), "{error}");
        assert_eq!(snapshot(&root), before);
        assert_eq!(fs::read_link(&source).unwrap(), outside);
    }
}

#[test]
fn adoption_recovers_native_paths_and_live_ownership_with_an_unchanged_manifest() {
    let mut server = mockito::Server::new();
    let (mut engine, downloads) = new_engine(&server, "desktop");
    let root = engine.root();
    let manifest = fs::read(root.join("export_status.json")).unwrap();
    engine.catalog.files.remove(&(FAMILY, PHOTO));
    let export = engine.prepare(engine.options(true, &[])).unwrap();
    drop(export);
    engine.catalog.albums.insert(FAMILY, "Renamed".into());
    rename(&mut engine, FAMILY, PAIR, "Photo.jpg");
    let (mut remote, _) = source(90, &engine.catalog.key, b"new original", "Pending.jpg");
    remote["ownerID"] = json!(USER);
    engine.catalog.files.insert((FAMILY, 90), remote);
    let failed = server
        .mock("GET", "/files/download/v3/90")
        .with_status(404)
        .expect(1)
        .create();
    assert!(!engine.run(true, &[]).unwrap().complete);
    failed.assert();
    assert_eq!(fs::read(root.join("export_status.json")).unwrap(), manifest);
    let original = fs::read(root.join("Renamed/Photo.jpg")).unwrap();
    assert_eq!(
        read_json(&root.join("Renamed/metadata/Photo.jpg.json"))["ente"]["fileID"],
        PAIR.to_string()
    );
    fs::remove_file(root.join("Renamed/metadata/Photo.mov.json")).unwrap();
    let path = root.join("Renamed/metadata/Live.mov.json");
    fs::write(path, b"unfinished legacy common JSON").unwrap();
    engine.catalog.files.remove(&(FAMILY, 90));
    engine.database = "recovered.db".into();
    assert!(
        engine
            .run(false, &[])
            .err()
            .unwrap()
            .is::<ente_photos_export::AdoptionRequired>()
    );
    let requests: Vec<_> = downloads
        .iter()
        .map(|(id, bytes)| download(&mut server, *id, bytes, 0))
        .collect();
    assert!(engine.run(true, &[]).unwrap().complete);
    assert_eq!(fs::read(root.join("Renamed/Photo.jpg")).unwrap(), original);
    assert_eq!(
        read_json(&root.join("Renamed/metadata/Photo.mov.json"))["ente"]["fileID"],
        PAIR.to_string()
    );
    assert_eq!(
        read_json(&root.join("Renamed/metadata/Live.mov.json"))["ente"]["fileID"],
        "10000065"
    );
    assert!(!root.join("export_status.json").exists());
    assert_eq!(
        fs::read_dir(root.join("Trash/Family"))
            .unwrap()
            .filter_map(Result::ok)
            .filter(|e| e.path().extension().is_some_and(|x| x == "jpg"))
            .count(),
        1
    );
    for request in requests {
        request.assert();
    }
}

#[test]
fn adoption_cleanup_waits_for_new_files_and_resumes_after_its_final_database_write() {
    let mut server = mockito::Server::new();
    let (mut engine, _) = new_engine(&server, "go");
    let root = engine.root();
    let (mut remote, encrypted) = source(90, &engine.catalog.key, b"new original", "New.jpg");
    remote["ownerID"] = json!(USER);
    engine.catalog.files.insert((FAMILY, 90), remote);
    engine.catalog.albums.insert(99, "Other".into());
    let failed = server
        .mock("GET", "/files/download/v3/90")
        .with_status(404)
        .expect(1)
        .create();
    assert!(!engine.run(true, &[]).unwrap().complete);
    failed.assert();
    assert!(root.join("Family/.meta/album_meta.json").is_file());
    assert!(root.join("Family/.meta/Photo.jpg.json").is_file());
    assert!(root.join("Family/metadata/Photo.jpg.json").is_file());
    drop(failed);
    let requested = download(&mut server, 90, &encrypted, 1);
    engine.db().execute_batch("CREATE TRIGGER stop_completion BEFORE UPDATE OF bound ON export WHEN new.bound=1 BEGIN SELECT RAISE(ABORT,'interrupt after cleanup'); END;").unwrap();
    assert!(!engine.run(false, &[]).unwrap().complete);
    requested.assert();
    assert!(!root.join("Family/.meta").exists());
    assert!(!root.join("Other").exists());
    assert_eq!(count(&engine.db(), "SELECT bound FROM export"), 0);
    assert_eq!(
        count(&engine.db(), "SELECT count(*) FROM albums WHERE retained=0"),
        3
    );
    engine
        .db()
        .execute_batch("DROP TRIGGER stop_completion")
        .unwrap();
    assert!(
        engine
            .run(false, &["Family"])
            .err()
            .unwrap()
            .to_string()
            .contains("exactly")
    );
    assert!(engine.run(false, &[]).unwrap().complete);
    assert!(!root.join("Other").exists());
    assert!(engine.run(true, &[]).unwrap().complete);
    assert!(root.join("Other/metadata.json").is_file());
}

#[test]
fn adoption_defers_wholly_missing_hashless_originals_until_after_acceptance() {
    let mut server = mockito::Server::new();
    let (mut engine, downloads) = new_engine(&server, "go");
    let previous = engine.catalog.files[&(FAMILY, PHOTO)].clone();
    let (_, documents) = files::decrypt(
        &serde_json::from_value(previous.clone()).unwrap(),
        &engine.catalog.key,
    )
    .unwrap();
    let mut value: Value = serde_json::from_slice(&documents.original).unwrap();
    value.as_object_mut().unwrap().remove("hash");
    let encrypted = blob::encrypt_json(&value, &file_key(&previous, &engine.catalog.key)).unwrap();
    engine.catalog.files.get_mut(&(FAMILY, PHOTO)).unwrap()["metadata"] = json!({"encryptedData":b64::encode(&encrypted.encrypted_data),"decryptionHeader":b64::encode(encrypted.decryption_header.as_bytes())});
    fs::remove_file(engine.root().join("Family/Photo.jpg")).unwrap();
    let absent = download(&mut server, PHOTO, &downloads[&PHOTO], 0);
    let export = engine.prepare(engine.options(true, &[])).unwrap();
    absent.assert();
    assert_eq!(
        count(
            &engine.db(),
            &format!(
                "SELECT count(*) FROM components c JOIN placements p ON p.id=c.placement WHERE p.file={PHOTO}"
            )
        ),
        0
    );
    drop(absent);
    let requested = download(&mut server, PHOTO, &downloads[&PHOTO], 1);
    assert!(engine.execute(export).unwrap().complete);
    requested.assert();
}

#[test]
fn adoption_verifies_a_single_undeclared_live_survivor_before_preserving_it() {
    let mut server = mockito::Server::new();
    let (mut engine, downloads) = new_engine(&server, "go");
    let root = engine.root();
    let path = root.join("Family/.meta/Pair.jpg.json");
    let mut record = read_json(&path);
    record["info"]["fileNames"] = json!(["Pair.jpg"]);
    fs::write(path, serde_json::to_vec(&record).unwrap()).unwrap();
    fs::remove_file(root.join("Family/Pair.mov")).unwrap();
    let original = fs::read(root.join("Family/Pair.jpg")).unwrap();
    fs::write(root.join("Family/Pair.jpg"), b"edited survivor").unwrap();
    let before = snapshot(&root);
    assert!(engine.run(true, &[]).is_err());
    assert_eq!(snapshot(&root), before);
    fs::write(root.join("Family/Pair.jpg"), &original).unwrap();
    for (path, _) in snapshot(&root) {
        if !path.to_string_lossy().ends_with(".json")
            && path.as_path() != Path::new("Family/Pair.jpg")
        {
            fs::remove_file(root.join(path)).unwrap();
        }
    }
    let export = engine.prepare(engine.options(true, &[])).unwrap();
    assert_eq!(count(&engine.db(), "SELECT count(*) FROM components"), 0);
    let requests: Vec<_> = downloads
        .iter()
        .map(|(id, bytes)| download(&mut server, *id, bytes, 1))
        .collect();
    assert!(engine.execute(export).unwrap().complete);
    for request in requests {
        request.assert();
    }
    assert_eq!(
        fs::read(root.join("Trash/Family/Pair.jpg")).unwrap(),
        original
    );
    assert_eq!(fs::read(root.join("Family/Pair.jpg")).unwrap(), original);
}

#[test]
fn adoption_of_one_recorded_album_includes_new_photos_but_not_unrelated_albums() {
    let mut server = mockito::Server::new();
    let (mut engine, _) = new_engine(&server, "desktop");
    let root = engine.root();
    fs::remove_dir_all(root.join("Travel")).unwrap();
    fs::remove_dir_all(root.join("Live Pair")).unwrap();
    let path = root.join("export_status.json");
    let mut manifest = read_json(&path);
    manifest["collectionExportNames"]
        .as_object_mut()
        .unwrap()
        .retain(|id, _| id == &FAMILY.to_string());
    manifest["fileExportNames"]
        .as_object_mut()
        .unwrap()
        .retain(|id, _| id.split('_').nth(1) == Some(FAMILY.to_string().as_str()));
    fs::write(path, serde_json::to_vec(&manifest).unwrap()).unwrap();
    let (mut remote, encrypted) = source(90, &engine.catalog.key, b"new photo", "New.jpg");
    remote["ownerID"] = json!(USER);
    engine.catalog.files.insert((FAMILY, 90), remote);
    let requested = download(&mut server, 90, &encrypted, 1);
    let export = engine.prepare(engine.options(true, &["Family"])).unwrap();
    drop(export);
    assert!(engine.run(true, &[]).unwrap().complete);
    requested.assert();
    assert_component(&root, "Family", "New.jpg", b"new photo");
    assert!(!root.join("Travel").exists());
    assert!(!root.join("Live Pair").exists());
}
