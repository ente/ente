use super::*;
use crate::export_process::ExportChild;
use ente_core::crypto::hash;
use std::{
    path::Path,
    time::{Duration, UNIX_EPOCH},
};

#[cfg(unix)]
#[path = "export_resources.rs"]
mod resources;

#[test]
fn export_selection_reuses_independent_album_copies() -> TestResult {
    Museum::run(|museum| {
        tokio::runtime::Runtime::new()?.block_on(async {
            let origin = museum.endpoint();
            let objects = museum.object_store();
            let (account, home, _) = export_account(origin).await;
            let destination = tempfile::tempdir()?;
            let root = destination.path().join("photos");
            let (family, family_key) = create_album(origin, &account, "Family", "album").await;
            let (travel, travel_key) = create_album(origin, &account, "Travel", "folder").await;
            let (work, work_key) = create_album(origin, &account, "Work", "album").await;
            let (empty, _) = create_album(origin, &account, "Trash", "album").await;
            let original = b"unmodified original bytes";
            let (file, key) = upload_fixture(
                origin,
                &account,
                family,
                &family_key,
                original,
                metadata("A.jpg", original),
            )
            .await;
            place(
                origin,
                &account,
                travel,
                &travel_key,
                file,
                &key,
                "add-files",
            )
            .await;
            upload_fixture(
                origin,
                &account,
                work,
                &work_key,
                b"work",
                metadata("Work.jpg", b"work"),
            )
            .await;
            let initial_reads = objects.reads();
            let result = export(&home, &root, &["--album", "Family"]);
            assert_eq!(result["copies"]["completed"], 1);
            assert_eq!(objects.reads(), initial_reads + 1);
            assert!(!root.join("Travel").exists());
            let result = export(&home, &root, &["--album", "Family", "--album", "Travel"]);
            assert_eq!(result["copies"]["expected"], 2);
            assert_eq!(objects.reads(), initial_reads + 1);
            assert_eq!(fs::read(root.join("Travel/A.jpg"))?, original);
            #[cfg(unix)]
            {
                use std::os::unix::fs::MetadataExt;
                assert_ne!(
                    fs::metadata(root.join("Travel/A.jpg"))?.ino(),
                    fs::metadata(root.join("Family/A.jpg"))?.ino()
                );
            }
            let travel_time = fs::metadata(root.join("Travel/A.jpg"))?.modified()?;
            export(&home, &root, &["--album", "Family"]);
            assert_eq!(
                fs::metadata(root.join("Travel/A.jpg"))?.modified()?,
                travel_time
            );
            let scoped = export(
                &home,
                &root,
                &[
                    "--album",
                    "Family",
                    "--album",
                    "Family",
                    "--album",
                    "Travel",
                    "--album",
                    "Work",
                    "--album",
                    &empty.to_string(),
                    "--exclude-album",
                    "Work",
                ],
            );
            assert_eq!(scoped["copies"]["expected"], 2);
            assert!(root.join("Trash-1/metadata.json").exists());
            assert_eq!(
                read_json(&root.join("Trash-1/metadata.json"))["ente"]["albumID"],
                empty.to_string()
            );
            assert!(!root.join("Work").exists());
            export(&home, &root, &[]);
            assert_eq!(objects.reads(), initial_reads + 2);
            assert_eq!(fs::read(root.join("Work/Work.jpg"))?, b"work");
            Ok(())
        })
    })
}

#[test]
fn export_metadata_updates_and_repairs_preserve_source_values() -> TestResult {
    Museum::run(|museum| {
        tokio::runtime::Runtime::new()?.block_on(async {
            let origin = museum.endpoint();
            let objects = museum.object_store();
            let (account, home, _) = export_account(origin).await;
            let destination = tempfile::tempdir()?;
            let root = destination.path().join("photos");
            let (family, family_key) = create_album(origin, &account, "Family", "album").await;
            let (travel, travel_key) = create_album(origin, &account, "Travel", "folder").await;
            let original = b"unmodified original bytes";
            let (file, key) = upload_fixture(origin, &account, family, &family_key, original, metadata("A.jpg", original)).await;
            place(origin, &account, travel, &travel_key, file, &key, "add-files").await;
            let initial_reads = objects.reads();
            export(&home, &root, &["--album", "Family"]);
            let (favorites,favorites_key)=create_album(origin,&account,"Favorites","favorites").await;
            let original_time=fs::metadata(root.join("Family/A.jpg"))?.modified()?;
            assert_eq!(original_time,UNIX_EPOCH+Duration::from_micros(1_700_000_001_123_456));
            let sidecar=root.join("Family/metadata/A.jpg.json");
            let sidecar_time=fs::metadata(&sidecar)?.modified()?;
            let record=read_json(&sidecar);
            assert_eq!(record["ente"]["creationTime"],"2023-11-14T22:13:20.123456Z");
            assert_eq!(record["photoTakenTime"]["timestamp"],"1700000000");
            assert_eq!(record["photoTakenTime"]["formatted"],"Nov 14, 2023, 10:13:20 PM UTC");
            assert_eq!(record["ente"]["components"][0]["size"],original.len());
            assert_eq!(record["ente"]["modificationTime"],"2023-11-14T22:13:21.123456Z");
            assert_eq!(record["modificationTime"]["timestamp"],"1700000001");
            for field in ["deviceFolder","localID","editedName","editedTime","updationTime","pubMagicMetadata"] {
                assert!(record.get(field).is_none());
                assert!(record["ente"].get(field).is_none());
            }
            assert_eq!(fs::read(root.join("Family/A.jpg"))?,original);
            let unchanged=export(&home,&root,&["--album","Family"]);
            assert_eq!(unchanged["changes"],json!({"exported":0,"metadataUpdated":0,"renamed":0,"retained":0}));
            assert_eq!(fs::metadata(&sidecar)?.modified()?,sidecar_time);
            assert_eq!(fs::metadata(root.join("Family/A.jpg"))?.modified()?,original_time);
            let before_locale=fs::read(&sidecar)?;
            let localized=success(home.command(&["photos","export",root.to_str().unwrap(),"--album","Family","--json"]).env("LC_ALL","tr_TR.UTF-8").env("TZ","Pacific/Honolulu").output()?);
            assert_eq!(serde_json::from_slice::<Value>(&localized.stdout)?["changes"],json!({"exported":0,"metadataUpdated":0,"renamed":0,"retained":0}));
            assert_eq!(fs::read(&sidecar)?,before_locale);
            assert_eq!(fs::metadata(&sidecar)?.modified()?,sidecar_time);
            fs::File::options().write(true).open(root.join("Family/A.jpg"))?.set_modified(UNIX_EPOCH+Duration::from_secs(99))?;
            export(&home,&root,&["--album","Family"]);
            assert_eq!(fs::metadata(root.join("Family/A.jpg"))?.modified()?,original_time);
            #[cfg(unix)] {
                use std::os::unix::fs::MetadataExt;
                let before=fs::metadata(root.join("Family/A.jpg"))?;
                export(&home,&root,&["--album","Family"]);
                let after=fs::metadata(root.join("Family/A.jpg"))?;
                assert_eq!((before.ctime(),before.ctime_nsec()),(after.ctime(),after.ctime_nsec()));
            }
            export(&home, &root, &["--album", "Travel"]);
            place(origin,&account,favorites,&favorites_key,file,&key,"add-files").await;
            let mut edited_metadata=json!({"editedName":"Renamed.jpg","editedTime":1_700_000_002_654_321i64,"caption":"","lat":0,"long":0,"dateTime":"2023:11:15 03:43:22","offsetTime":"+05:30","w":4096,"h":3072,"cameraMake":"Example","cameraModel":"Camera","uploaderName":"Guest","mediaType":1,"mvi":123});
            for (version,lat,long) in [(1,0,77),(2,12,0),(3,0,0)] {
                edited_metadata["lat"]=json!(lat);
                edited_metadata["long"]=json!(long);
                edit_file(origin,&account,file,&key,version,edited_metadata.clone()).await;
                export(&home,&root,&["--album","Family"]);
                let record=read_json(&root.join("Family/metadata/Renamed.jpg.json"));
                assert_eq!(record["description"],"");
                assert_eq!(record["favorited"],true);
                assert_eq!(record["ente"]["creationTime"],"2023-11-14T22:13:22.654321Z");
                assert_eq!(record["ente"]["name"],"Renamed.jpg");
                assert_eq!(record["photoTakenTime"]["timestamp"],"1700000002");
                assert!(!record.to_string().contains("2023-11-14T22:13:20.123456Z"));
                assert!(!record.to_string().contains("not portable"));
                for (field,value) in [("localDateTime",json!("2023:11:15 03:43:22")),("utcOffset",json!("+05:30")),("width",json!(4096)),("height",json!(3072)),("cameraMake",json!("Example")),("cameraModel",json!("Camera")),("uploaderName",json!("Guest")),("panorama",json!(true)),("motionPhotoVideoOffset",json!(123))] { assert_eq!(record["ente"][field],value); }
                if lat==0 && long==0 {
                    assert!(record.get("geoData").is_none());
                    assert!(record["ente"].get("location").is_none());
                } else {
                    assert_eq!(record["geoData"],json!({"latitude":lat as f64,"longitude":long as f64}));
                    assert_eq!(record["ente"]["location"],record["geoData"]);
                }
            }
            assert!(root.join("Travel/A.jpg").exists());
            fs::write(root.join("Family/metadata/Renamed.jpg.json"),b"{\"custom\":true}")?;
            export(&home,&root,&["--album","Family"]);
            assert!(read_json(&root.join("Family/metadata/Renamed.jpg.json")).get("custom").is_none());
            fs::write(root.join("Family/Renamed.jpg"),vec![0;original.len()])?;
            let db=export_database(&home);
            let baseline: String=db.query_row("SELECT hash FROM components WHERE folder=?1",[format!("active:{family}")],|r|r.get(0))?;
            let state=home.read_vault();
            let saved=&state["accounts"][0];
            let replica=rusqlite::Connection::open(home.dir.path().join("accounts").join(saved["storage_id"].as_str().unwrap()).join("data.db"))?;
            let db_key: Vec<u8>=serde_json::from_value(saved["db_key"].clone())?;
            let hex: String=db_key.iter().map(|byte|format!("{byte:02x}")).collect();
            replica.pragma_update(None,"key",format!("x'{hex}'"))?;
            let before: i64=replica.query_row("SELECT files_cursor FROM photos_collections WHERE id=?1",[family],|r|r.get(0))?;
            edited_metadata["caption"]=json!("source advanced");
            edit_file(origin,&account,file,&key,4,edited_metadata).await;
            let output=home.run(&["photos","export",root.to_str().unwrap(),"--json"]);
            assert!(failure(&output).contains("locally changed media"));
            let result: Value=serde_json::from_slice(&output.stdout)?;
            assert_eq!(result["complete"],false);
            assert_eq!(result["conflicts"],1);
            assert_eq!(fs::read(root.join("Family/Renamed.jpg"))?,vec![0;original.len()]);
            assert_eq!(read_json(&root.join("Travel/metadata/Renamed.jpg.json"))["description"],"source advanced");
            let after: i64=replica.query_row("SELECT files_cursor FROM photos_collections WHERE id=?1",[family],|r|r.get(0))?;
            assert!(after>before);
            assert_eq!(db.query_row("SELECT hash FROM components WHERE folder=?1",[format!("active:{family}")],|r|r.get::<_,String>(0))?,baseline);
            fs::rename(root.join("Family/Renamed.jpg"),destination.path().join("local-edit.jpg"))?;
            export(&home,&root,&[]);
            assert_eq!(fs::read(root.join("Family/Renamed.jpg"))?,original);
            assert_eq!(objects.reads(),initial_reads+1);
            Ok(())
        })
    })
}

#[cfg(unix)]
#[test]
fn export_metadata_failure_does_not_block_an_independent_album() -> TestResult {
    Museum::run(|museum| {
        tokio::runtime::Runtime::new()?.block_on(async {
            let origin = museum.endpoint();
            let (account, home, _) = export_account(origin).await;
            let destination = tempfile::tempdir()?;
            let root = destination.path().join("photos");
            use std::os::unix::fs::PermissionsExt;
            let (family, family_key) = create_album(origin, &account, "Family", "album").await;
            upload_fixture(
                origin,
                &account,
                family,
                &family_key,
                b"family",
                metadata("A.jpg", b"family"),
            )
            .await;
            let (work, work_key) = create_album(origin, &account, "Work", "album").await;
            upload_fixture(
                origin,
                &account,
                work,
                &work_key,
                b"work",
                metadata("Work.jpg", b"work"),
            )
            .await;
            export(&home, &root, &[]);
            fs::write(
                root.join("Family/metadata/A.jpg.json"),
                b"{\"custom\":true}",
            )?;
            fs::write(
                root.join("Work/metadata/Work.jpg.json"),
                b"{\"custom\":true}",
            )?;
            let protected = root.join("Work/metadata");
            let permissions = fs::metadata(&protected)?.permissions();
            fs::set_permissions(&protected, fs::Permissions::from_mode(0o500))?;
            let output = home.run(&["photos", "export", root.to_str().unwrap(), "--json"]);
            fs::set_permissions(&protected, permissions)?;
            assert!(
                failure(&output)
                    .to_lowercase()
                    .contains("permission denied")
            );
            let result: Value = serde_json::from_slice(&output.stdout)?;
            assert_eq!(
                result["copies"],
                json!({"expected":2,"completed":1,"pending":1})
            );
            assert_eq!(result["failures"], 1);
            assert!(
                read_json(&root.join("Family/metadata/A.jpg.json"))
                    .get("custom")
                    .is_none()
            );
            export(&home, &root, &["--album", "Work"]);
            Ok(())
        })
    })
}

#[test]
fn export_retention_restoration_and_album_removal_preserve_history() -> TestResult {
    Museum::run(|museum| {
        tokio::runtime::Runtime::new()?.block_on(async {
            let origin = museum.endpoint();
            let objects = museum.object_store();
            let (account, home, email) = export_account(origin).await;
            let destination = tempfile::tempdir()?;
            let root = destination.path().join("photos");
            let (family, family_key) = create_album(origin, &account, "Family", "album").await;
            let (travel, travel_key) = create_album(origin, &account, "Travel", "folder").await;
            let original = b"unmodified original bytes";
            let (file, key) = upload_fixture(origin, &account, family, &family_key, original, metadata("Renamed.jpg", original)).await;
            place(origin, &account, travel, &travel_key, file, &key, "add-files").await;
            let initial_reads = objects.reads();
            export(&home, &root, &["--album", "Family"]);
            export(&home, &root, &["--album", "Travel"]);
            move_file(origin,&account,family,(travel,&travel_key),(file,&key)).await;
            let result=export(&home,&root,&["--album","Family"]);
            assert_eq!(result["changes"]["retained"],1);
            let retained=root.join("Trash/Family/Renamed.jpg");
            assert_eq!(fs::read(&retained)?,original);
            let retained_record=fs::read(root.join("Trash/Family/metadata/Renamed.jpg.json"))?;
            let retained_time=fs::metadata(&retained)?.modified()?;
            assert_eq!(export(&home,&root,&["--album","Family"])["changes"]["retained"],0);
            place(origin,&account,family,&family_key,file,&key,"add-files").await;
            export(&home,&root,&["--album","Family"]);
            assert_eq!(objects.reads(),initial_reads+1);
            assert_eq!(fs::read(root.join("Trash/Family/metadata/Renamed.jpg.json"))?,retained_record);
            assert_eq!(fs::metadata(&retained)?.modified()?,retained_time);
            fs::remove_dir_all(root.join("Trash"))?;
            export(&home,&root,&["--album","Family"]);
            assert!(!root.join("Trash").exists());
            move_file(origin,&account,family,(travel,&travel_key),(file,&key)).await;
            export(&home,&root,&["--album","Family"]);
            assert_eq!(read_json(&root.join("Trash/Family/metadata.json"))["ente"]["albumID"],family.to_string());
            assert_eq!(fs::read(root.join("Trash/Family/Renamed-1.jpg"))?,original);
            let recovery=TestHome::new();
            login(&recovery,"photos",&email,&["--host",origin]);
            export(&recovery,&root,&["--adopt","--album","Family"]);
            place(origin,&account,family,&family_key,file,&key,"add-files").await;
            export(&home,&root,&["--album","Family"]);
            fs::write(root.join("Family/notes.txt"),b"local notes")?;
            let encrypted=secretbox::encrypt(b"Family renamed",&family_key);
            request(origin,&account,reqwest::Method::POST,"/collections/rename",json!({"collectionID":family,"encryptedName":b64::encode(&encrypted.encrypted_data),"nameDecryptionNonce":b64::encode(encrypted.nonce.as_bytes())})).await;
            export(&home,&root,&["--album",&family.to_string()]);
            assert_eq!(fs::read(root.join("Family renamed/notes.txt"))?,b"local notes");
            move_file(origin,&account,family,(travel,&travel_key),(file,&key)).await;
            request(origin,&account,reqwest::Method::DELETE,&format!("/collections/v3/{family}?collectionID={family}&keepFiles=true"),json!({})).await;
            export(&home,&root,&["--album",&family.to_string()]);
            assert_eq!(fs::read(root.join("Family renamed/notes.txt"))?,b"local notes");
            assert!(root.join("Trash/Family/Renamed-2.jpg").exists());
            fs::remove_dir_all(root.join("Trash"))?;
            export(&home,&root,&["--album",&family.to_string()]);
            assert!(!root.join("Trash").exists());
            Ok(())
        })
    })
}

#[test]
fn export_adopts_relocated_output_and_verifies_later_selections() -> TestResult {
    Museum::run(|museum| {
        tokio::runtime::Runtime::new()?.block_on(async {
            let origin = museum.endpoint();
            let objects = museum.object_store();
            let (account, home, email) = export_account(origin).await;
            let destination = tempfile::tempdir()?;
            let root = destination.path().join("photos");
            let (travel, travel_key) = create_album(origin, &account, "Travel", "album").await;
            upload_fixture(
                origin,
                &account,
                travel,
                &travel_key,
                b"travel",
                metadata("A.jpg", b"travel"),
            )
            .await;
            let (work, work_key) = create_album(origin, &account, "Work", "album").await;
            upload_fixture(
                origin,
                &account,
                work,
                &work_key,
                b"work",
                metadata("Work.jpg", b"work"),
            )
            .await;
            export(&home, &root, &[]);
            let root_bytes = fs::read(root.join("export.json"))?;
            let relocated = destination.path().join("relocated");
            fs::rename(&root, &relocated)?;
            let fresh = TestHome::new();
            login(&fresh, "photos", &email, &["--host", origin]);
            assert!(
                failure(&fresh.run(&["photos", "export", relocated.to_str().unwrap()]))
                    .contains("--adopt")
            );
            let reads = objects.reads();
            export(&fresh, &relocated, &["--adopt", "--album", "Travel"]);
            assert_eq!(objects.reads(), reads);
            assert_eq!(fs::read(relocated.join("export.json"))?, root_bytes);
            fs::write(relocated.join("Work/Work.jpg"), b"xxxx")?;
            let output = fresh.run(&[
                "photos",
                "export",
                relocated.to_str().unwrap(),
                "--album",
                "Work",
                "--json",
            ]);
            assert!(failure(&output).contains("locally changed media"));
            assert_eq!(
                serde_json::from_slice::<Value>(&output.stdout)?["conflicts"],
                1
            );
            assert_eq!(fs::read(relocated.join("Work/Work.jpg"))?, b"xxxx");
            assert_eq!(objects.reads(), reads);
            fs::remove_file(relocated.join("Work/Work.jpg"))?;
            export(&fresh, &relocated, &["--album", "Work"]);
            assert_eq!(objects.reads(), reads + 1);
            assert_eq!(fs::read(relocated.join("Work/Work.jpg"))?, b"work");
            Ok(())
        })
    })
}

#[test]
fn export_restores_a_trashed_original_from_retained_output() -> TestResult {
    Museum::run(|museum| {
        tokio::runtime::Runtime::new()?.block_on(async {
            let origin = museum.endpoint();
            let objects = museum.object_store();
            let (account, home, _) = export_account(origin).await;
            let destination = tempfile::tempdir()?;
            let root = destination.path().join("photos");
            let (work, work_key) = create_album(origin, &account, "Work", "album").await;
            let (work_file, work_file_key) = upload_fixture(
                origin,
                &account,
                work,
                &work_key,
                b"work",
                metadata("Work.jpg", b"work"),
            )
            .await;
            export(&home, &root, &[]);
            request(
                origin,
                &account,
                reqwest::Method::POST,
                "/files/trash",
                json!({"items":[{"fileID":work_file,"collectionID":work}]}),
            )
            .await;
            let trashed = export(&home, &root, &["--album", "Work"]);
            assert_eq!(trashed["copies"]["expected"], 0);
            assert_eq!(trashed["changes"]["retained"], 1);
            assert!(!root.join("Work/Work.jpg").exists());
            assert!(!root.join("Work/metadata/Work.jpg.json").exists());
            assert_eq!(fs::read(root.join("Trash/Work/Work.jpg"))?, b"work");
            assert_eq!(
                read_json(&root.join("Trash/Work/metadata/Work.jpg.json"))["ente"]["fileID"],
                work_file.to_string()
            );
            place(
                origin,
                &account,
                work,
                &work_key,
                work_file,
                &work_file_key,
                "restore-files",
            )
            .await;
            let reads = objects.reads();
            let restored = export(&home, &root, &["--album", "Work"]);
            assert_eq!(
                restored["copies"],
                json!({"expected":1,"completed":1,"pending":0})
            );
            assert_eq!(fs::read(root.join("Work/Work.jpg"))?, b"work");
            assert_eq!(
                read_json(&root.join("Work/metadata/Work.jpg.json"))["ente"]["fileID"],
                work_file.to_string()
            );
            assert_eq!(objects.reads(), reads);
            Ok(())
        })
    })
}

#[test]
fn export_destination_conflicts_do_not_block_other_jobs() -> TestResult {
    Museum::run(|museum| {
        tokio::runtime::Runtime::new()?.block_on(async {
            let origin = museum.endpoint();
            let objects = museum.object_store();
            let email = format!("export-staging-{}@example.org", Uuid::new_v4());
            let account = create_account(origin, &email).await;
            let home = TestHome::new();
            login(&home, "photos", &email, &["--host", origin]);
            let (blocked, blocked_key) = create_album(origin, &account, "Blocked", "album").await;
            let (healthy, healthy_key) = create_album(origin, &account, "Healthy", "album").await;
            let destination = tempfile::tempdir()?;
            let root = destination.path().join("export");
            export(&home, &root, &[]);
            let total = 4;
            for index in 0..total {
                let name = format!("{index}.jpg");
                upload_fixture(
                    origin,
                    &account,
                    blocked,
                    &blocked_key,
                    b"original",
                    metadata(&name, b"original"),
                )
                .await;
                fs::write(root.join("Blocked").join(name), b"unrelated")?;
            }
            let (file, key) = upload_fixture(
                origin,
                &account,
                healthy,
                &healthy_key,
                b"healthy",
                metadata("Healthy.jpg", b"healthy"),
            )
            .await;
            export(&home, &root, &["--album", "Healthy"]);
            let reads = objects.reads();
            edit_file(
                origin,
                &account,
                file,
                &key,
                1,
                json!({"caption":"updated despite other conflicts"}),
            )
            .await;
            let output = home.run(&[
                "photos",
                "export",
                root.to_str().unwrap(),
                "--jobs",
                "2",
                "--json",
            ]);
            assert!(failure(&output).contains("unrelated occupant"));
            let result: Value = serde_json::from_slice(&output.stdout)?;
            assert_eq!(result["copies"]["completed"], 1);
            assert_eq!(result["copies"]["pending"], total);
            assert_eq!(objects.reads(), reads + total);
            assert_eq!(
                read_json(&root.join("Healthy/metadata/Healthy.jpg.json"))["description"],
                "updated despite other conflicts"
            );
            let db = export_database(&home);
            let staged: i64 = db.query_row("SELECT count(*) FROM temporaries", [], |r| r.get(0))?;
            assert_eq!(staged, 0);
            for index in 0..total {
                let path = root.join("Blocked").join(format!("{index}.jpg"));
                assert_eq!(fs::read(&path)?, b"unrelated");
                fs::remove_file(path)?;
            }
            assert_eq!(
                export(&home, &root, &["--jobs", "1"])["copies"]["completed"],
                total + 1
            );
            assert_eq!(objects.reads(), reads + 2 * total);
            assert_eq!(
                db.query_row("SELECT count(*) FROM temporaries", [], |r| r
                    .get::<_, i64>(0))?,
                0
            );
            Ok(())
        })
    })
}

#[test]
fn export_preserves_album_types_visibility_and_settings() -> TestResult {
    Museum::run(|museum| {
        tokio::runtime::Runtime::new()?.block_on(async {
            let origin = museum.endpoint();
            let email = format!("export-albums-{}@example.org", Uuid::new_v4());
            let account = create_account(origin, &email).await;
            let home = TestHome::new();
            login(&home, "photos", &email, &["--host", origin]);
            let cases = [
                ("Archive", "album", "album", 1, 0, "archived"),
                ("Private", "album", "album", 2, 0, "hidden"),
                ("Hidden", "album", "defaultHidden", 0, 1, "hidden"),
                ("Quick link", "album", "quicklink", 0, 2, "visible"),
                ("Folder", "folder", "folder", 0, 0, "visible"),
                ("Uncategorized", "uncategorized", "uncategorized", 0, 0, "visible"),
            ];
            for (name, kind, _, visibility, subtype, _) in cases {
                let (album, key) = create_album(origin, &account, name, kind).await;
                let (file, file_key) = upload_fixture(origin, &account, album, &key, name.as_bytes(), metadata("original.jpg", name.as_bytes())).await;
                set_album_metadata(origin, &account, album, &key, "magic-metadata", json!({"visibility":visibility,"subType":subtype,"order":7})).await;
                set_album_metadata(origin, &account, album, &key, "public-magic-metadata", json!({"asc":true,"coverID":file,"layout":"trip","caption":"album description"})).await;
                let private = blob::encrypt_json(&json!({"visibility":visibility}), &file_key)?;
                request(origin, &account, reqwest::Method::PUT, "/files/magic-metadata", json!({"metadataList":[{"id":file,"magicMetadata":{"version":1,"count":1,"data":b64::encode(&private.encrypted_data),"header":b64::encode(private.decryption_header.as_bytes())}}]})).await;
            }
            let destination = tempfile::tempdir()?;
            let root = destination.path().join("photos");
            let result = export(&home, &root, &[]);
            assert_eq!(result["copies"]["completed"], cases.len());
            for (name, _, kind, file_visibility, _, visibility) in cases {
                let folder = root.join(name);
                let album = read_json(&folder.join("metadata.json"));
                let file = read_json(&folder.join("metadata/original.jpg.json"));
                assert_eq!(fs::read(folder.join("original.jpg"))?, name.as_bytes());
                assert_eq!(album["ente"]["type"], kind);
                assert_eq!(album["ente"]["visibility"], visibility);
                assert_eq!(album["ente"]["displayOrder"], 7);
                assert_eq!(album["ente"]["sortOrder"], "ascending");
                assert_eq!(album["ente"]["description"], "album description");
                assert_eq!(album["ente"]["layout"], "trip");
                assert_eq!(album["ente"]["coverFileID"], file["ente"]["fileID"]);
                assert_eq!(file["ente"]["visibility"], ["visible", "archived", "hidden"][file_visibility]);
            }
            Ok(())
        })
    })
}

#[test]
fn export_resumes_a_live_pair_after_publication_failure() -> TestResult {
    Museum::run(|museum| {
        tokio::runtime::Runtime::new()?.block_on(async {
            let origin = museum.endpoint();
            let objects = museum.object_store();
            let email = format!("live-publication-{}@example.org", Uuid::new_v4());
            let account = create_account(origin, &email).await;
            let home = TestHome::new();
            login(&home, "photos", &email, &["--host", origin]);
            let (album, key) = create_album(origin, &account, "Live", "album").await;
            let destination = tempfile::tempdir()?;
            let root = destination.path().join("export");
            export(&home, &root, &[]);
            let db = export_database(&home);
            db.execute_batch(
                "CREATE TRIGGER fail_video_publication BEFORE UPDATE ON pending WHEN json_extract(new.action,'$.Publish.output.Media.role')='video' BEGIN SELECT RAISE(ABORT,'injected publication failure'); END;",
            )?;
            upload_live(origin, &account, album, &key, "Motion.heic", b"image", b"video").await;
            let output = home.run(&["photos", "export", root.to_str().unwrap(), "--json"]);
            assert!(failure(&output).contains("injected publication failure"));
            let result: Value = serde_json::from_slice(&output.stdout)?;
            assert_eq!(result["copies"]["pending"], 1);
            assert_eq!(fs::read(root.join("Live/Motion.heic"))?, b"image");
            assert!(!root.join("Live/Motion.mov").exists());
            assert!(!root.join("Live/metadata/Motion.heic.json").exists());
            assert_eq!(db.query_row("SELECT count(*) FROM temporaries", [], |r| r.get::<_, i64>(0))?, 0);
            let image_time = fs::metadata(root.join("Live/Motion.heic"))?.modified()?;
            let reads = objects.reads();
            db.execute_batch("DROP TRIGGER fail_video_publication;")?;
            export(&home, &root, &[]);
            assert_eq!(objects.reads(), reads + 1);
            assert_eq!(fs::metadata(root.join("Live/Motion.heic"))?.modified()?, image_time);
            assert_eq!(fs::read(root.join("Live/Motion.heic"))?, b"image");
            assert_eq!(fs::read(root.join("Live/Motion.mov"))?, b"video");
            for name in ["Motion.heic", "Motion.mov"] {
                assert!(root.join("Live/metadata").join(format!("{name}.json")).exists());
            }
            let sidecar = root.join("Live/metadata/Motion.mov.json");
            let mut record = read_json(&sidecar);
            record["ente"]["components"].as_array_mut().unwrap().reverse();
            fs::write(&sidecar, serde_json::to_vec(&record)?)?;
            let fresh = TestHome::new();
            fresh.write_vault(&home.read_vault());
            export(&fresh, &root, &["--adopt"]);
            assert_eq!(objects.reads(), reads + 1);
            assert_eq!(read_json(&sidecar)["ente"]["components"][0]["role"], "image");
            Ok(())
        })
    })
}

#[test]
fn export_adopts_live_sidecars_with_different_metadata() -> TestResult {
    Museum::run(|museum| {
        tokio::runtime::Runtime::new()?.block_on(async {
            let origin = museum.endpoint();
            let objects = museum.object_store();
            let email = format!("live-adoption-{}@example.org", Uuid::new_v4());
            let account = create_account(origin, &email).await;
            let home = TestHome::new();
            login(&home, "photos", &email, &["--host", origin]);
            let (active, active_key) = create_album(origin, &account, "Active", "album").await;
            let (unselected, unselected_key) =
                create_album(origin, &account, "Unselected", "album").await;
            let (history, history_key) = create_album(origin, &account, "History", "album").await;
            let mut zip = zip::ZipWriter::new(std::io::Cursor::new(Vec::new()));
            for (name, bytes) in [("image.heic", b"image"), ("video.mov", b"video")] {
                zip.start_file(
                    name,
                    zip::write::SimpleFileOptions::default()
                        .compression_method(zip::CompressionMethod::Stored),
                )?;
                zip.write_all(bytes)?;
            }
            let archive = zip.finish()?.into_inner();
            let mut data = metadata("Motion.heic", &archive);
            data["fileType"] = json!(2);
            data["hash"] = json!(format!("{}:{}", digest(b"image"), digest(b"video")));
            let (file, key) =
                upload_fixture(origin, &account, active, &active_key, &archive, data).await;
            for (album, album_key) in [(unselected, &unselected_key), (history, &history_key)] {
                place(origin, &account, album, album_key, file, &key, "add-files").await;
            }
            let destination = tempfile::tempdir()?;
            let root = destination.path().join("export");
            export(&home, &root, &[]);
            move_file(
                origin,
                &account,
                history,
                (active, &active_key),
                (file, &key),
            )
            .await;
            request(
                origin,
                &account,
                reqwest::Method::DELETE,
                &format!("/collections/v3/{history}?collectionID={history}&keepFiles=true"),
                json!({}),
            )
            .await;
            export(&home, &root, &[]);
            edit_file(
                origin,
                &account,
                file,
                &key,
                1,
                json!({"caption":"current remote caption","w":640}),
            )
            .await;
            let reads = objects.reads();
            let mut preserved = Vec::new();
            for folder in ["Active", "Unselected", "Trash/History"] {
                for (index, name) in ["Motion.heic", "Motion.mov"].into_iter().enumerate() {
                    let sidecar = root
                        .join(folder)
                        .join("metadata")
                        .join(format!("{name}.json"));
                    let mut record = read_json(&sidecar);
                    record["description"] = json!(format!("{folder} component {index}"));
                    record["ente"]["width"] = json!(1024 + index);
                    fs::write(&sidecar, serde_json::to_vec(&record)?)?;
                    if folder != "Active" {
                        preserved.push((
                            sidecar.clone(),
                            fs::read(&sidecar)?,
                            fs::metadata(&sidecar)?.modified()?,
                        ));
                    }
                    let media = root.join(folder).join(name);
                    preserved.push((
                        media.clone(),
                        fs::read(&media)?,
                        fs::metadata(&media)?.modified()?,
                    ));
                }
            }
            let fresh = TestHome::new();
            fresh.write_vault(&home.read_vault());
            export(&fresh, &root, &["--adopt", "--album", "Active"]);
            assert_eq!(objects.reads(), reads);
            for name in ["Motion.heic", "Motion.mov"] {
                let record = read_json(&root.join("Active/metadata").join(format!("{name}.json")));
                assert_eq!(record["description"], "current remote caption");
                assert_eq!(record["ente"]["width"], 640);
            }
            for (path, bytes, modified) in preserved {
                assert_eq!(fs::read(&path)?, bytes);
                assert_eq!(fs::metadata(path)?.modified()?, modified);
            }
            move_file(
                origin,
                &account,
                unselected,
                (active, &active_key),
                (file, &key),
            )
            .await;
            for name in ["Motion.heic", "Motion.mov"] {
                fs::remove_file(
                    root.join("Unselected/metadata")
                        .join(format!("{name}.json")),
                )?;
            }
            export(&fresh, &root, &["--album", "Unselected"]);
            for (index, name) in ["Motion.heic", "Motion.mov"].into_iter().enumerate() {
                let record = read_json(
                    &root
                        .join("Trash/Unselected/metadata")
                        .join(format!("{name}.json")),
                );
                assert_eq!(
                    record["description"],
                    format!("Unselected component {index}")
                );
                assert_eq!(record["ente"]["width"], 1024 + index);
            }
            for folder in ["Active", "Trash/History"] {
                let sidecar = root.join(folder).join("metadata/Motion.mov.json");
                let original = fs::read(&sidecar)?;
                for (pointer, value) in [
                    ("/ente/fileID", json!((file + 1).to_string())),
                    ("/ente/components/0/path", json!("Other.heic")),
                    ("/ente/components/0/size", json!(100)),
                    ("/ente/components/0/hash", json!(digest(b"other"))),
                    ("/ente/component", json!("image")),
                ] {
                    let mut record: Value = serde_json::from_slice(&original)?;
                    *record.pointer_mut(pointer).unwrap() = value;
                    fs::write(&sidecar, serde_json::to_vec(&record)?)?;
                    let ambiguous = TestHome::new();
                    ambiguous.write_vault(&home.read_vault());
                    let output = ambiguous.run(&[
                        "photos",
                        "export",
                        root.to_str().unwrap(),
                        "--adopt",
                        "--album",
                        "Active",
                    ]);
                    let error = failure(&output);
                    assert!(
                        error.contains("conflict:")
                            || error.contains("contradictory sidecar location"),
                        "{folder} {pointer}: {error}"
                    );
                    fs::write(&sidecar, &original)?;
                }
            }
            assert_eq!(objects.reads(), reads);
            Ok(())
        })
    })
}

#[test]
fn export_live_pairs_retry_and_reuse_without_rewriting_unchanged_output() -> TestResult {
    Museum::run(|museum| {
        tokio::runtime::Runtime::new()?.block_on(async {
            let origin = museum.endpoint();
            let objects = museum.object_store();
            let email = format!("live-export-{}@example.org", Uuid::new_v4());
            let account = create_account(origin, &email).await;
            let home = TestHome::new();
            login(&home, "photos", &email, &["--host", origin]);
            let (album, key) = create_album(origin, &account, "Live", "album").await;
            let (copy, copy_key) = create_album(origin, &account, "Copies", "album").await;
            let image = vec![61u8; stream::ENCRYPTION_CHUNK_SIZE + 17];
            let video = vec![92u8; stream::ENCRYPTION_CHUNK_SIZE * 2 + 31];
            let mut zip = zip::ZipWriter::new(std::io::Cursor::new(Vec::new()));
            for (name, bytes) in [("image.heic", &image), ("video.mov", &video)] {
                zip.start_file(
                    name,
                    zip::write::SimpleFileOptions::default()
                        .compression_method(zip::CompressionMethod::Stored),
                )?;
                zip.write_all(bytes)?;
            }
            let archive = zip.finish()?.into_inner();
            let mut data = metadata("Motion.heic", &archive);
            data["fileType"] = json!(2);
            data.as_object_mut().unwrap().remove("hash");
            data["imageHash"] = json!(digest(&image));
            data["videoHash"] = json!(digest(&video));
            let (file, file_key) =
                upload_fixture(origin, &account, album, &key, &archive, data).await;
            place(
                origin,
                &account,
                copy,
                &copy_key,
                file,
                &file_key,
                "add-files",
            )
            .await;
            let original = vec![0; stream::ENCRYPTION_CHUNK_SIZE + 100];
            upload_fixture(
                origin,
                &account,
                album,
                &key,
                &original,
                metadata("0.jpg", &original),
            )
            .await;
            let destination = tempfile::tempdir()?;
            let root = destination.path().join("export");
            objects.interrupt_reads(1);
            let result = export(&home, &root, &[]);
            assert_eq!(result["copies"]["completed"], 3);
            assert_eq!(objects.reads(), 3);
            for folder in ["Live", "Copies"] {
                assert_eq!(fs::read(root.join(folder).join("Motion.heic"))?, image);
                assert_eq!(fs::read(root.join(folder).join("Motion.mov"))?, video);
                let record = read_json(&root.join(folder).join("metadata/Motion.heic.json"));
                assert_eq!(record["ente"]["components"][0]["hash"], digest(&image));
                assert_eq!(record["ente"]["components"][1]["hash"], digest(&video));
            }
            let reads = objects.reads();
            export(&home, &root, &[]);
            let paths = [
                "export.json",
                "Live/metadata.json",
                "Live/0.jpg",
                "Live/metadata/0.jpg.json",
                "Live/Motion.heic",
                "Live/Motion.mov",
                "Live/metadata/Motion.heic.json",
                "Live/metadata/Motion.mov.json",
                "Copies/metadata.json",
                "Copies/Motion.heic",
                "Copies/Motion.mov",
                "Copies/metadata/Motion.heic.json",
                "Copies/metadata/Motion.mov.json",
            ];
            let unchanged: Vec<_> = paths
                .iter()
                .map(|path| {
                    let path = root.join(path);
                    (
                        fs::read(&path).unwrap(),
                        fs::metadata(&path).unwrap().modified().unwrap(),
                    )
                })
                .collect();
            let db = export_database(&home);
            for table in [
                "albums",
                "placements",
                "components",
                "json_records",
                "pending",
                "sources",
                "album_sources",
            ] {
                for action in ["INSERT", "UPDATE", "DELETE"] {
                    let timing = if ["sources", "album_sources"].contains(&table) {
                        "AFTER"
                    } else {
                        "BEFORE"
                    };
                    db.execute_batch(&format!(
                        "CREATE TRIGGER unchanged_{table}_{action} {timing} {action} ON {table} BEGIN SELECT RAISE(ABORT,'unchanged association write'); END;",
                    ))?;
                }
            }
            let result = success(
                home.command(&["photos", "export", root.to_str().unwrap(), "--json"])
                    .env("TOKIO_WORKER_THREADS", "1")
                    .output()?,
            );
            let result: Value = serde_json::from_slice(&result.stdout)?;
            assert_eq!(result["complete"], true);
            assert_eq!(
                result["copies"],
                json!({"expected":3,"completed":3,"pending":0})
            );
            assert_eq!(
                result["changes"],
                json!({"exported":0,"metadataUpdated":0,"renamed":0,"retained":0})
            );
            assert_eq!(objects.reads(), reads);
            for (path, before) in paths.iter().zip(unchanged) {
                let path = root.join(path);
                assert_eq!((fs::read(&path)?, fs::metadata(&path)?.modified()?), before);
            }
            for table in [
                "albums",
                "placements",
                "components",
                "json_records",
                "pending",
                "sources",
                "album_sources",
            ] {
                for action in ["INSERT", "UPDATE", "DELETE"] {
                    db.execute_batch(&format!("DROP TRIGGER unchanged_{table}_{action};"))?;
                }
            }
            for entry in fs::read_dir(root.join("Live"))? {
                let entry = entry?;
                if entry.file_type()?.is_file() && entry.file_name() != "metadata.json" {
                    fs::File::options()
                        .write(true)
                        .open(entry.path())?
                        .set_modified(UNIX_EPOCH + Duration::from_secs(19))?;
                }
            }
            export(&home, &root, &[]);
            assert_eq!(objects.reads(), reads);
            fs::remove_file(root.join("Live/Motion.mov"))?;
            export(&home, &root, &[]);
            assert_eq!(objects.reads(), reads);
            assert_eq!(fs::read(root.join("Live/Motion.mov"))?, video);
            Ok(())
        })
    })
}

#[test]
fn export_excludes_another_writer_while_downloads_are_running() -> TestResult {
    Museum::run(|museum| {
        tokio::runtime::Runtime::new()?.block_on(async {
            let origin = museum.endpoint();
            let objects = museum.object_store();
            let (account, home, email) = export_account(origin).await;
            let other = TestHome::new();
            login(&other, "photos", &email, &["--host", origin]);
            let (album, key) = create_album(origin, &account, "Album", "album").await;
            let names = ["First.jpg", "Second.jpg", "Third.jpg", "Fourth.jpg"];
            for name in names {
                upload_fixture(
                    origin,
                    &account,
                    album,
                    &key,
                    name.as_bytes(),
                    metadata(name, name.as_bytes()),
                )
                .await;
            }
            let destination = tempfile::tempdir()?;
            let root = destination.path().join("photos");
            let held = objects.hold_reads(0);
            let reads = objects.reads();
            let child = ExportChild::spawn(&mut home.command(&[
                "photos",
                "export",
                root.to_str().unwrap(),
                "-j",
                "2",
                "--json",
            ]))?;
            held.wait_for(2);
            std::thread::sleep(Duration::from_millis(500));
            assert_eq!(objects.reads() - reads, 2);
            let second = ExportChild::spawn(&mut other.command(&[
                "photos",
                "export",
                root.to_str().unwrap(),
                "--adopt",
            ]))?;
            assert!(failure(&second.wait_with_output()?).contains("another writer"));
            drop(held);
            let result: Value = serde_json::from_slice(&success(child.wait_with_output()?).stdout)?;
            assert_eq!(result["copies"]["completed"], 4);
            for name in names {
                assert_eq!(fs::read(root.join("Album").join(name))?, name.as_bytes());
            }
            Ok(())
        })
    })
}

#[test]
fn export_recovers_after_cancelled_and_killed_downloads() -> TestResult {
    Museum::run(|museum| {
        tokio::runtime::Runtime::new()?.block_on(async {
            let origin = museum.endpoint();
            let objects = museum.object_store();
            let (account, home, _) = export_account(origin).await;
            let (album, key) = create_album(origin, &account, "Album", "album").await;
            upload_fixture(
                origin,
                &account,
                album,
                &key,
                b"original",
                metadata("Photo.jpg", b"original"),
            )
            .await;
            let destination = tempfile::tempdir()?;
            let root = destination.path().join("photos");
            export(&home, &root, &[]);
            let unrelated = root.join("Album/.ente-11111111111111111111111111111111.part");
            fs::write(&unrelated, b"unassociated")?;
            let unchanged_root = fs::read(root.join("export.json"))?;
            for graceful in [true, false] {
                #[cfg(not(unix))]
                if graceful {
                    continue;
                }
                fs::remove_file(root.join("Album/Photo.jpg"))?;
                let held = objects.hold_reads(0);
                let mut child = ExportChild::spawn(
                    home.command(&["photos", "export", root.to_str().unwrap(), "--json"])
                        .env("TOKIO_WORKER_THREADS", "1"),
                )?;
                held.wait_for(1);
                if graceful {
                    assert!(
                        Command::new("kill")
                            .args(["-INT", &child.id().to_string()])
                            .status()?
                            .success()
                    );
                } else {
                    child.kill()?;
                }
                let interrupted = child.wait_with_output()?;
                let error = failure(&interrupted);
                if graceful {
                    assert!(error.contains("cancelled"), "{error}");
                    assert_eq!(
                        serde_json::from_slice::<Value>(&interrupted.stdout)?["complete"],
                        false
                    );
                }
                drop(held);
                export(&home, &root, &[]);
                assert_eq!(fs::read(root.join("Album/Photo.jpg"))?, b"original");
                assert_eq!(fs::read(&unrelated)?, b"unassociated");
                assert_eq!(fs::read(root.join("export.json"))?, unchanged_root);
            }
            Ok(())
        })
    })
}

#[test]
fn export_rejects_invalid_live_archives_and_component_hashes() -> TestResult {
    Museum::run(|museum| {
        tokio::runtime::Runtime::new()?.block_on(async {
            let origin = museum.endpoint();
            let email = format!("invalid-live-{}@example.org", Uuid::new_v4());
            let account = create_account(origin, &email).await;
            let home = TestHome::new();
            login(&home, "photos", &email, &["--host", origin]);
            let (album, key) = create_album(origin, &account, "Album", "album").await;
            let mut archives = vec![b"not a ZIP".to_vec()];
            for names in [
                vec!["image.jpg"],
                vec!["image.jpg", "image.png", "video.mov"],
                vec!["image.jpg", "video.mov", "other.jpg"],
                vec!["image/../outside.jpg", "video.mov"],
                vec!["image.jpg", "video.mov"],
            ] {
                let mut zip = zip::ZipWriter::new(std::io::Cursor::new(Vec::new()));
                for name in names {
                    zip.start_file(name, zip::write::SimpleFileOptions::default())?;
                    zip.write_all(b"component")?;
                }
                archives.push(zip.finish()?.into_inner());
            }
            let mut zip = zip::ZipWriter::new(std::io::Cursor::new(Vec::new()));
            for name in ["image.jpg", "video.mov"] {
                zip.start_file(
                    name,
                    zip::write::SimpleFileOptions::default()
                        .compression_method(zip::CompressionMethod::Deflated),
                )?;
                std::io::copy(
                    &mut std::io::Read::take(std::io::repeat(0), 9 * 1024 * 1024),
                    &mut zip,
                )?;
            }
            archives.push(zip.finish()?.into_inner());
            for (index, archive) in archives.iter().enumerate() {
                let mut data = metadata(&format!("Invalid-{index}.jpg"), archive);
                data["fileType"] = json!(2);
                data["hash"] = json!(format!(
                    "{}:{}",
                    digest(b"component"),
                    digest(if index == 5 {
                        b"wrong video"
                    } else {
                        b"component"
                    })
                ));
                upload_fixture(origin, &account, album, &key, archive, data).await;
            }
            upload_fixture(
                origin,
                &account,
                album,
                &key,
                b"independent",
                metadata("Good.jpg", b"independent"),
            )
            .await;
            let destination = tempfile::tempdir()?;
            let root = destination.path().join("export");
            let output = home.run(&["photos", "export", root.to_str().unwrap(), "--json"]);
            let error = failure(&output);
            assert!(
                error.contains("Live Photo archive expands beyond limit"),
                "{error}"
            );
            let result: Value = serde_json::from_slice(&output.stdout)?;
            assert_eq!(
                result["copies"],
                json!({"expected":8,"completed":1,"pending":7})
            );
            assert_eq!(result["failures"], 7);
            assert_eq!(fs::read(root.join("Album/Good.jpg"))?, b"independent");
            assert_eq!(fs::read_dir(root.join("Album/metadata"))?.count(), 1);
            for index in 0..archives.len() {
                assert!(!root.join(format!("Album/Invalid-{index}.jpg")).exists());
                assert!(!root.join(format!("Album/Invalid-{index}.mov")).exists());
            }
            assert!(!root.join("outside.jpg").exists());
            Ok(())
        })
    })
}

fn export(home: &TestHome, destination: &Path, options: &[&str]) -> Value {
    let mut args = vec!["photos", "export", destination.to_str().unwrap()];
    args.extend_from_slice(options);
    home.json(&args)
}
fn read_json(path: &Path) -> Value {
    serde_json::from_slice(&fs::read(path).unwrap()).unwrap()
}

fn export_database(home: &TestHome) -> rusqlite::Connection {
    let state = home.read_vault();
    let account = &state["accounts"][0];
    let directory = home
        .dir
        .path()
        .join("accounts")
        .join(account["storage_id"].as_str().unwrap())
        .join("exports");
    let path = fs::read_dir(directory)
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .find(|path| path.extension().is_some_and(|ext| ext == "db"))
        .unwrap();
    let key: Vec<u8> = serde_json::from_value(account["db_key"].clone()).unwrap();
    let hex: String = key.iter().map(|byte| format!("{byte:02x}")).collect();
    let db = rusqlite::Connection::open(path).unwrap();
    db.pragma_update(None, "key", format!("x'{hex}'")).unwrap();
    db
}
fn digest(bytes: &[u8]) -> String {
    b64::encode(&hash::hash(bytes, Some(64), None).unwrap())
}
fn metadata(name: &str, original: &[u8]) -> Value {
    json!({"title":name,"fileType":0,"creationTime":1_700_000_000_123_456i64,"modificationTime":1_700_000_001_123_456i64,"latitude":10.0,"longitude":20.0,"hash":digest(original),"deviceFolder":"not portable"})
}
async fn request(
    origin: &str,
    account: &AuthenticatedAccount,
    method: reqwest::Method,
    path: &str,
    body: Value,
) {
    let response = reqwest::Client::new()
        .request(method, format!("{origin}{path}"))
        .header("x-auth-token", b64::encode_url_safe(&account.secrets.token))
        .header("x-client-package", "io.ente.photos")
        .json(&body)
        .send()
        .await
        .unwrap();
    assert!(
        response.status().is_success(),
        "{path}: {} {}",
        response.status(),
        response.text().await.unwrap()
    );
}
async fn place(
    origin: &str,
    account: &AuthenticatedAccount,
    album: i64,
    album_key: &Key,
    file: i64,
    file_key: &Key,
    operation: &str,
) {
    let wrapped = secretbox::encrypt(file_key.as_bytes(), album_key);
    request(origin,account,reqwest::Method::POST,&format!("/collections/{operation}"),json!({"collectionID":album,"files":[{"id":file,"encryptedKey":b64::encode(&wrapped.encrypted_data),"keyDecryptionNonce":b64::encode(wrapped.nonce.as_bytes())}]})).await;
}
async fn move_file(
    origin: &str,
    account: &AuthenticatedAccount,
    from: i64,
    (to, album_key): (i64, &Key),
    (file, file_key): (i64, &Key),
) {
    let wrapped = secretbox::encrypt(file_key.as_bytes(), album_key);
    request(
        origin,
        account,
        reqwest::Method::POST,
        "/collections/move-files",
        json!({"fromCollectionID":from,"toCollectionID":to,"files":[{"id":file,"encryptedKey":b64::encode(&wrapped.encrypted_data),"keyDecryptionNonce":b64::encode(wrapped.nonce.as_bytes())}]}),
    )
    .await;
}
async fn edit_file(
    origin: &str,
    account: &AuthenticatedAccount,
    file: i64,
    key: &Key,
    version: i64,
    data: Value,
) {
    let encrypted = blob::encrypt_json(&data, key).unwrap();
    request(origin,account,reqwest::Method::PUT,"/files/public-magic-metadata",json!({"metadataList":[{"id":file,"magicMetadata":{"version":version,"count":data.as_object().unwrap().len(),"data":b64::encode(&encrypted.encrypted_data),"header":b64::encode(encrypted.decryption_header.as_bytes())}}]})).await;
}

#[test]
fn export_names_are_portable_and_stable() -> TestResult {
    Museum::run_async(|origin| async move {
        let email = format!("export-names-{}@example.org", Uuid::new_v4());
        let account = create_account(&origin, &email).await;
        let home = TestHome::new();
        login(&home, "photos", &email, &["--host", &origin]);
        let (album, key) = create_album(&origin, &account, "Names, commas", "album").await;
        create_album(&origin, &account, "Album:", "album").await;
        create_album(&origin, &account, "Album_", "album").await;
        let long_album = format!("{}.tail", "a".repeat(254));
        create_album(&origin, &account, &long_album, "album").await;
        let destination = tempfile::tempdir()?;
        let root = destination.path().join("photos");
        let cases = [
            ("IMG.jpg", Some(0), "IMG.jpg"),
            ("IMG.jpg", Some(0), "IMG-1.jpg"),
            ("IMG-1.jpg", Some(0), "IMG-1-1.jpg"),
            ("CON.jpg", Some(0), "CON-1.jpg"),
            ("CON.extra.jpg", Some(0), "CON-1.extra.jpg"),
            ("bad:name.jpg", Some(0), "bad_name.jpg"),
            ("bad_name.jpg", Some(0), "bad_name-1.jpg"),
            ("Straße.jpg", Some(0), "Straße.jpg"),
            ("STRASSE.jpg", Some(0), "STRASSE-1.jpg"),
            ("é.jpg", Some(0), "é.jpg"),
            ("e\u{301}.jpg", Some(0), "e\u{301}-1.jpg"),
            ("metadata.json", Some(0), "metadata-1.json"),
            ("same.jpg", Some(0), "same.jpg"),
            ("same.png", Some(0), "same.png"),
            ("same.mov", Some(1), "same-1.mov"),
            ("same.mp4", Some(1), "same-1.mp4"),
            ("same.raw", None, "same-2.raw"),
            ("same.other", None, "same-3.other"),
        ];
        for (name, kind, expected) in cases {
            let mut data = metadata(name, name.as_bytes());
            data["fileType"] = json!(kind);
            let (id, _) =
                upload_fixture(&origin, &account, album, &key, name.as_bytes(), data).await;
            export(&home, &root, &["--album", "Names, commas"]);
            let path = root.join("Names, commas").join(expected);
            assert_eq!(fs::read(&path)?, name.as_bytes());
            assert_eq!(
                read_json(
                    &root
                        .join("Names, commas/metadata")
                        .join(format!("{expected}.json"))
                )["ente"]["fileID"],
                id.to_string()
            );
        }
        let long = format!("{}.jpg", "あ".repeat(100));
        upload_fixture(
            &origin,
            &account,
            album,
            &key,
            b"long",
            metadata(&long, b"long"),
        )
        .await;
        export(&home, &root, &[]);
        let shortened = format!("{}.jpg", "あ".repeat(82));
        assert_eq!(
            fs::read(root.join("Names, commas").join(&shortened))?,
            b"long"
        );
        assert_eq!(
            read_json(&root.join("a".repeat(254)).join("metadata.json"))["title"],
            long_album
        );
        assert_eq!(
            read_json(&root.join("Album_/metadata.json"))["title"],
            "Album:"
        );
        assert_eq!(
            read_json(&root.join("Album_-1/metadata.json"))["title"],
            "Album_"
        );
        assert_eq!(
            export(&home, &root, &[])["changes"],
            json!({"exported":0,"metadataUpdated":0,"renamed":0,"retained":0})
        );
        let fresh = TestHome::new();
        fresh.write_vault(&home.read_vault());
        export(&fresh, &root, &["--adopt"]);
        for (name, _, expected) in cases {
            assert_eq!(
                fs::read(root.join("Names, commas").join(expected))?,
                name.as_bytes()
            );
        }
        let mut data = metadata("same.avi", b"new video");
        data["fileType"] = json!(1);
        upload_fixture(&origin, &account, album, &key, b"new video", data).await;
        export(&fresh, &root, &[]);
        assert_eq!(
            fs::read(root.join("Names, commas/same-1.avi"))?,
            b"new video"
        );
        assert_eq!(
            export(&fresh, &root, &[])["changes"],
            json!({"exported":0,"metadataUpdated":0,"renamed":0,"retained":0})
        );
        Ok(())
    })
}

#[test]
fn export_allocates_live_pairs_from_their_actual_extensions() -> TestResult {
    Museum::run(|museum| {
        tokio::runtime::Runtime::new()?.block_on(async {
            let origin = museum.endpoint();
            let objects = museum.object_store();
            let email = format!("live-names-{}@example.org", Uuid::new_v4());
            let account = create_account(origin, &email).await;
            let home = TestHome::new();
            login(&home, "photos", &email, &["--host", origin]);
            let (album, key) = create_album(origin, &account, "Live names", "album").await;
            let destination = tempfile::tempdir()?;
            let root = destination.path().join("photos");
            let folder = root.join("Live names");
            let long_video = format!("{}.mp4", "a".repeat(245));
            let long_image = format!("{}-1.png", "a".repeat(243));
            for (name, kind) in [
                ("pair.jpg", 0),
                ("same-image.png", 0),
                (&long_video, 1),
                (&long_image, 0),
            ] {
                let mut data = metadata(name, name.as_bytes());
                data["fileType"] = json!(kind);
                upload_fixture(origin, &account, album, &key, name.as_bytes(), data).await;
                export(&home, &root, &[]);
                assert_eq!(fs::read(folder.join(name))?, name.as_bytes());
            }
            let long_source = format!("{}.jpg", "a".repeat(246));
            let long_outputs = [
                format!("{}-2.jpeg", "a".repeat(243)),
                format!("{}-2.mov", "a".repeat(243)),
            ];
            let cases = [
                (
                    "pair.heic",
                    [".heic", ".mov"],
                    ["pair-1.heic", "pair-1.mov"],
                ),
                (
                    "same.heic",
                    [".jpg", ".JPG"],
                    ["same-1-image.jpg", "same-1-video.JPG"],
                ),
                ("absent.heic", ["", ""], ["absent-image", "absent-video"]),
                ("half.heic", ["", ".mov"], ["half", "half.mov"]),
                ("dotted..heic", ["", ".mov"], ["dotted", "dotted.mov"]),
                (
                    "metadata.heic",
                    ["", ".mov"],
                    ["metadata-1", "metadata-1.mov"],
                ),
                (
                    long_source.as_str(),
                    [".jpeg", ".mov"],
                    [long_outputs[0].as_str(), long_outputs[1].as_str()],
                ),
                (
                    "converted.heic",
                    [".j?g ", ".m:v"],
                    ["converted.j_g", "converted.m_v"],
                ),
            ];
            let mut snapshots = Vec::new();
            for (index, (name, extensions, paths)) in cases.into_iter().enumerate() {
                let image = format!("image {index}");
                let video = format!("video {index}");
                let id = upload_live_parts(
                    origin,
                    &account,
                    album,
                    &key,
                    name,
                    [
                        (extensions[0], image.as_bytes()),
                        (extensions[1], video.as_bytes()),
                    ],
                )
                .await;
                export(&home, &root, &[]);
                for (path, bytes) in paths.into_iter().zip([image.as_bytes(), video.as_bytes()]) {
                    let media = folder.join(path);
                    assert_eq!(fs::read(&media)?, bytes);
                    let sidecar = folder.join("metadata").join(format!("{path}.json"));
                    let record = read_json(&sidecar);
                    assert_eq!(record["ente"]["fileID"], id.to_string());
                    assert_eq!(record["ente"]["name"], name);
                    assert_eq!(record["ente"]["components"][0]["path"], paths[0]);
                    assert_eq!(record["ente"]["components"][1]["path"], paths[1]);
                    snapshots.push((media, bytes.to_vec()));
                    snapshots.push((sidecar.clone(), fs::read(sidecar)?));
                }
            }
            let reads = objects.reads();
            assert_eq!(
                export(&home, &root, &[])["changes"],
                json!({"exported":0,"metadataUpdated":0,"renamed":0,"retained":0})
            );
            let fresh = TestHome::new();
            fresh.write_vault(&home.read_vault());
            export(&fresh, &root, &["--adopt"]);
            assert_eq!(objects.reads(), reads);
            for (path, bytes) in snapshots {
                assert_eq!(fs::read(path)?, bytes);
            }
            upload_fixture(
                origin,
                &account,
                album,
                &key,
                b"later image",
                metadata("half.jpg", b"later image"),
            )
            .await;
            export(&fresh, &root, &[]);
            assert_eq!(fs::read(folder.join("half-1.jpg"))?, b"later image");
            Ok(())
        })
    })
}

#[test]
fn export_refills_transfers_while_an_ordinary_original_is_held() -> TestResult {
    export_refills_transfers(false)
}

#[test]
fn export_refills_transfers_while_a_live_original_is_held() -> TestResult {
    export_refills_transfers(true)
}

fn export_refills_transfers(live: bool) -> TestResult {
    Museum::run(|museum| {
        tokio::runtime::Runtime::new()?.block_on(async {
            let origin = museum.endpoint();
            let objects = museum.object_store();
            let email = format!("skewed-export-{}@example.org", Uuid::new_v4());
            let account = create_account(origin, &email).await;
            let home = TestHome::new();
            login(&home, "photos", &email, &["--host", origin]);
            let small_count = 4;
            let (album, key) = create_album(
                origin,
                &account,
                if live { "Live" } else { "Ordinary" },
                "album",
            )
            .await;
            let large = vec![31u8; stream::ENCRYPTION_CHUNK_SIZE + 17];
            if live {
                upload_live(
                    origin,
                    &account,
                    album,
                    &key,
                    "IMG:1.heic",
                    &large,
                    b"video",
                )
                .await;
                let mut contender = metadata("IMG?1.mov", b"ordinary contender");
                contender["fileType"] = json!(1);
                upload_fixture(
                    origin,
                    &account,
                    album,
                    &key,
                    b"ordinary contender",
                    contender,
                )
                .await;
                upload_live(
                    origin,
                    &account,
                    album,
                    &key,
                    "IMG?1-1.heic",
                    b"small image",
                    b"small video",
                )
                .await;
            } else {
                upload_fixture(
                    origin,
                    &account,
                    album,
                    &key,
                    &large,
                    metadata("Slow.jpg", &large),
                )
                .await;
            }
            for index in 0..small_count {
                upload_fixture(
                    origin,
                    &account,
                    album,
                    &key,
                    b"independent",
                    metadata(&format!("Small-{index}.jpg"), b"independent"),
                )
                .await;
            }
            let held = objects.hold_reads(1024 * 1024);
            let destination = tempfile::tempdir()?;
            let root = destination.path().join("export");
            let folder = root.join(if live { "Live" } else { "Ordinary" });
            let child = ExportChild::spawn(&mut home.command(&[
                "photos",
                "export",
                root.to_str().unwrap(),
                "--album",
                &album.to_string(),
                "-j",
                "2",
                "--json",
            ]))?;
            held.wait_for(1);
            let last = folder.join(format!("Small-{}.jpg", small_count - 1));
            let deadline = std::time::Instant::now() + Duration::from_secs(60);
            while !last.exists() && std::time::Instant::now() < deadline {
                std::thread::sleep(Duration::from_millis(10));
            }
            assert!(last.exists(), "independent transfers did not make progress");
            assert!(
                !folder
                    .join(if live { "IMG_1-2.heic" } else { "Slow.jpg" })
                    .exists(),
                "a slow first transfer blocked later placements"
            );
            drop(held);
            success(child.wait_with_output()?);
            if live {
                assert_eq!(fs::read(folder.join("IMG_1-2.heic"))?, large);
                assert_eq!(fs::read(folder.join("IMG_1-2.mov"))?, b"video");
                assert_eq!(fs::read(folder.join("IMG_1-1.heic"))?, b"small image");
                assert_eq!(fs::read(folder.join("IMG_1-1.mov"))?, b"small video");
                assert_eq!(fs::read(folder.join("IMG_1.mov"))?, b"ordinary contender");
                assert!(!folder.join("IMG_1.heic").exists());
            } else {
                assert_eq!(fs::read(folder.join("Slow.jpg"))?, large);
            }
            assert_eq!(
                export(&home, &root, &["--album", &album.to_string()])["changes"],
                json!({"exported":0,"metadataUpdated":0,"renamed":0,"retained":0})
            );
            Ok(())
        })
    })
}

async fn upload_live(
    origin: &str,
    account: &AuthenticatedAccount,
    album: i64,
    key: &Key,
    name: &str,
    image: &[u8],
    video: &[u8],
) {
    upload_live_parts(
        origin,
        account,
        album,
        key,
        name,
        [(".heic", image), (".mov", video)],
    )
    .await;
}

async fn upload_live_parts(
    origin: &str,
    account: &AuthenticatedAccount,
    album: i64,
    key: &Key,
    name: &str,
    parts: [(&str, &[u8]); 2],
) -> i64 {
    let mut zip = zip::ZipWriter::new(std::io::Cursor::new(Vec::new()));
    for (role, (extension, bytes)) in ["image", "video"].into_iter().zip(parts) {
        zip.start_file(
            format!("{role}{extension}"),
            zip::write::SimpleFileOptions::default()
                .compression_method(zip::CompressionMethod::Stored),
        )
        .unwrap();
        zip.write_all(bytes).unwrap();
    }
    let archive = zip.finish().unwrap().into_inner();
    let mut data = metadata(name, &archive);
    data["fileType"] = json!(2);
    data["hash"] = json!(format!("{}:{}", digest(parts[0].1), digest(parts[1].1)));
    upload_fixture(origin, account, album, key, &archive, data)
        .await
        .0
}

async fn export_account(origin: &str) -> (AuthenticatedAccount, TestHome, String) {
    let email = format!("export-{}@example.org", Uuid::new_v4());
    let account = create_account(origin, &email).await;
    let home = TestHome::new();
    login(&home, "photos", &email, &["--host", origin]);
    (account, home, email)
}

#[test]
fn export_adopts_go_and_desktop_fixtures_with_a_real_source_account() -> TestResult {
    Museum::run(|museum| {
        tokio::runtime::Runtime::new()?.block_on(async {
            let origin = museum.endpoint();
            let objects = museum.object_store();
            let (account, home, _) = export_account(origin).await;
            let (album, key) = create_album(origin, &account, "Family", "album").await;
            let fixtures =
                Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/export-adoption");
            let bytes = b"adoption integration original".to_vec();
            let (file, _) = upload_fixture(
                origin,
                &account,
                album,
                &key,
                &bytes,
                metadata("Photo.jpg", &bytes),
            )
            .await;
            for producer in ["go", "desktop"] {
                let directory = tempfile::tempdir()?;
                let root = directory.path().join("photos");
                fs::create_dir_all(root.join("Family"))?;
                fs::write(root.join("Family/Photo.jpg"), &bytes)?;
                if producer == "go" {
                    fs::create_dir_all(root.join("Family/.meta"))?;
                    let mut record = read_json(&fixtures.join("go-album.json"));
                    record["id"] = json!(album);
                    record["ownerID"] = json!(account.user_id);
                    record["accountOwnerIDs"] = json!([account.user_id]);
                    fs::write(
                        root.join("Family/.meta/album_meta.json"),
                        serde_json::to_vec(&record)?,
                    )?;
                    let mut record = read_json(&fixtures.join("go-file.json"));
                    record["info"]["id"] = json!(file);
                    record["info"]["ownerID"] = json!(account.user_id);
                    record["info"]["hash"] = json!(digest(&bytes));
                    fs::write(
                        root.join("Family/.meta/Photo.jpg.json"),
                        serde_json::to_vec(&record)?,
                    )?;
                } else {
                    let mut record =
                        json!({"version":5,"collectionExportNames":{},"fileExportNames":{}});
                    record["collectionExportNames"][album.to_string()] = json!("Family");
                    record["fileExportNames"][format!("{file}_{album}_100")] = json!("Photo.jpg");
                    fs::write(
                        root.join("export_status.json"),
                        serde_json::to_vec(&record)?,
                    )?;
                }
                let reads = objects.reads();
                let output = home.run(&["photos", "export", root.to_str().unwrap()]);
                assert_eq!(
                    failure(&output),
                    "Error: This folder contains an export from the old CLI or Ente Desktop. Use --adopt if you want to take it over.\n"
                );
                let result = export(&home, &root, &["--adopt", "--album", "Family"]);
                assert_eq!(result["copies"]["completed"], 1);
                assert_eq!(objects.reads(), reads);
                assert_eq!(fs::read(root.join("Family/Photo.jpg"))?, bytes);
                assert_eq!(
                    read_json(&root.join("Family/metadata/Photo.jpg.json"))["ente"]["fileID"],
                    file.to_string()
                );
            }
            Ok(())
        })
    })
}
