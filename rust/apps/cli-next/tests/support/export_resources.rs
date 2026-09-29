use super::*;
use std::{
    io::{Read, Seek},
    time::Instant,
};

#[test]
#[ignore = "requires ENTE_EXPORT_TEST_VOLUME pointing to a disposable volume smaller than 512 MiB"]
fn export_recovers_after_real_disk_full() -> TestResult {
    let volume = std::env::var("ENTE_EXPORT_TEST_VOLUME")?;
    let destination = tempfile::tempdir_in(volume)?;
    Museum::run(|museum| {
        tokio::runtime::Runtime::new()?.block_on(async {
            let origin = museum.endpoint();
            let email = format!("export-full-{}@example.org", Uuid::new_v4());
            let account = create_account(origin, &email).await;
            let home = TestHome::new();
            login(&home, "photos", &email, &["--host", origin]);
            let (album, key) = create_album(origin, &account, "Album", "album").await;
            upload_fixture(
                origin,
                &account,
                album,
                &key,
                b"completed",
                metadata("Before.jpg", b"completed"),
            )
            .await;
            let root = destination.path().join("export");
            export(&home, &root, &[]);
            let prior_time = fs::metadata(root.join("Album/Before.jpg"))?.modified()?;
            let root_bytes = fs::read(root.join("export.json"))?;
            let size = 32 * 1024 * 1024;
            let mut data = metadata("After.bin", b"");
            data["hash"] = json!(repeat_hash(31, size));
            upload_reader(
                origin,
                &account,
                album,
                &key,
                std::io::repeat(31).take(size),
                data,
            )
            .await;
            let filler_path = destination.path().join("filler");
            let mut filler = fs::File::create(&filler_path)?;
            let block = vec![61; 64 * 1024];
            let mut full = false;
            for _ in 0..8192 {
                match filler.write_all(&block) {
                    Ok(()) => {}
                    Err(error) if error.kind() == std::io::ErrorKind::StorageFull => {
                        full = true;
                        break;
                    }
                    Err(error) => return Err(error.into()),
                }
            }
            assert!(full, "fixture volume did not fill within 512 MiB");
            filler.set_len(filler.metadata()?.len().saturating_sub(256 * 1024))?;
            filler.sync_all()?;
            let output = home.run(&["photos", "export", root.to_str().unwrap(), "--json"]);
            failure(&output);
            let result: Value = serde_json::from_slice(&output.stdout)?;
            assert_eq!(result["complete"], false);
            assert_eq!(result["copies"]["pending"], 1);
            assert_eq!(fs::read(root.join("Album/Before.jpg"))?, b"completed");
            assert_eq!(
                fs::metadata(root.join("Album/Before.jpg"))?.modified()?,
                prior_time
            );
            assert_eq!(fs::read(root.join("export.json"))?, root_bytes);
            drop(filler);
            fs::remove_file(filler_path)?;
            export(&home, &root, &[]);
            assert_eq!(fs::metadata(root.join("Album/After.bin"))?.len(), size);
            assert_eq!(
                b64::encode(&hash::hash_reader(
                    &mut fs::File::open(root.join("Album/After.bin"))?,
                    Some(64)
                )?),
                repeat_hash(31, size)
            );
            assert_eq!(
                fs::metadata(root.join("Album/Before.jpg"))?.modified()?,
                prior_time
            );
            Ok(())
        })
    })
}

#[test]
#[ignore = "resource check: run in release mode with at least 20 GiB free"]
fn export_large_original_and_live_photo_with_bounded_memory() -> TestResult {
    Museum::run(|museum| {
        tokio::runtime::Runtime::new()?.block_on(async {
            let origin = museum.endpoint();
            let email = format!("export-large-{}@example.org", Uuid::new_v4());
            let account = create_account(origin, &email).await;
            let home = TestHome::new();
            login(&home, "photos", &email, &["--host", origin]);
            let (album, key) = create_album(origin, &account, "Large", "album").await;
            let size = 2 * 1024 * 1024 * 1024 + 53;
            let original_hash = repeat_hash(29, size);
            let mut data = metadata("Original.bin", b"");
            data["hash"] = json!(original_hash);
            upload_reader(
                origin,
                &account,
                album,
                &key,
                std::io::repeat(29).take(size),
                data,
            )
            .await;
            let image_size = 16 * 1024 * 1024;
            let image_hash = repeat_hash(17, image_size);
            let video_hash = repeat_hash(73, size);
            let mut archive = zip::ZipWriter::new(tempfile::tempfile()?);
            for (name, byte, length) in [("image.heic", 17, image_size), ("video.mov", 73, size)] {
                archive.start_file(
                    name,
                    zip::write::SimpleFileOptions::default()
                        .large_file(true)
                        .compression_method(zip::CompressionMethod::Stored),
                )?;
                std::io::copy(&mut std::io::repeat(byte).take(length), &mut archive)?;
            }
            let mut archive = archive.finish()?;
            archive.rewind()?;
            let mut data = metadata("Motion.heic", b"");
            data["fileType"] = json!(2);
            data["hash"] = json!(format!("{image_hash}:{video_hash}"));
            upload_reader(origin, &account, album, &key, archive, data).await;
            let destination = tempfile::tempdir()?;
            let root = destination.path().join("export");
            let result = measure(&home, &root, "large media")?;
            assert_eq!(result["copies"]["completed"], 2);
            for (name, length, expected) in [
                ("Original.bin", size, original_hash),
                ("Motion.heic", image_size, image_hash),
                ("Motion.mov", size, video_hash),
            ] {
                let path = root.join("Large").join(name);
                assert_eq!(fs::metadata(&path)?.len(), length);
                let actual = b64::encode(&hash::hash_reader(&mut fs::File::open(path)?, Some(64))?);
                assert_eq!(actual, expected);
            }
            let reads = museum.object_store().reads();
            assert_eq!(reads, 2);
            assert_eq!(
                measure(&home, &root, "large media unchanged")?["changes"],
                json!({"exported":0,"metadataUpdated":0,"renamed":0,"retained":0})
            );
            assert_eq!(museum.object_store().reads(), reads);
            Ok(())
        })
    })
}

#[test]
#[ignore = "resource check: builds a 2,000-record Museum library"]
fn export_many_records_unchanged_resource_check() -> TestResult {
    Museum::run(|museum| {
        tokio::runtime::Runtime::new()?.block_on(async {
            let origin = museum.endpoint();
            let email = format!("export-many-{}@example.org", Uuid::new_v4());
            let account = create_account(origin, &email).await;
            let home = TestHome::new();
            login(&home, "photos", &email, &["--host", origin]);
            let (album, key) = create_album(origin, &account, "Many", "album").await;
            for index in 0..2000 {
                let name = format!("{index}.jpg");
                upload_fixture(
                    origin,
                    &account,
                    album,
                    &key,
                    b"original",
                    metadata(&name, b"original"),
                )
                .await;
                // Each file needs two URLs; Museum allows 500 per minute.
                tokio::time::sleep(Duration::from_millis(300)).await;
                if index % 250 == 249 {
                    eprintln!("Prepared {} of 2,000 resource-fixture files", index + 1);
                }
            }
            let destination = tempfile::tempdir()?;
            let root = destination.path().join("export");
            assert_eq!(
                measure(&home, &root, "2,000 records initial")?["copies"]["completed"],
                2000
            );
            let mut observed = Vec::new();
            for directory in [root.join("Many"), root.join("Many/metadata")] {
                for entry in fs::read_dir(directory)? {
                    let entry = entry?;
                    if entry.file_type()?.is_file() {
                        observed.push((entry.path(), entry.metadata()?.modified()?));
                    }
                }
            }
            let reads = museum.object_store().reads();
            let result = measure(&home, &root, "2,000 records unchanged")?;
            assert_eq!(result["copies"]["completed"], 2000);
            assert_eq!(
                result["changes"],
                json!({"exported":0,"metadataUpdated":0,"renamed":0,"retained":0})
            );
            assert_eq!(museum.object_store().reads(), reads);
            for (path, modified) in observed {
                assert_eq!(fs::metadata(path)?.modified()?, modified);
            }
            Ok(())
        })
    })
}

fn repeat_hash(byte: u8, size: u64) -> String {
    b64::encode(&hash::hash_reader(&mut std::io::repeat(byte).take(size), Some(64)).unwrap())
}

fn measure(home: &TestHome, root: &Path, label: &str) -> TestResult<Value> {
    let started = Instant::now();
    let mut child = ExportChild::spawn(&mut home.command(&[
        "photos",
        "export",
        root.to_str().unwrap(),
        "--json",
    ]))?;
    let output_readers = [
        child
            .stdout
            .take()
            .map(|pipe| Box::new(pipe) as Box<dyn Read + Send>),
        child
            .stderr
            .take()
            .map(|pipe| Box::new(pipe) as Box<dyn Read + Send>),
    ]
    .map(|pipe| {
        std::thread::spawn(move || {
            let mut bytes = Vec::new();
            pipe.unwrap().read_to_end(&mut bytes).map(|_| bytes)
        })
    });
    let mut peak_kib = 0;
    while child.try_wait()?.is_none() {
        let sampled = Command::new("ps")
            .args(["-o", "rss=", "-p", &child.id().to_string()])
            .output()?;
        if sampled.status.success() {
            peak_kib = peak_kib.max(String::from_utf8(sampled.stdout)?.trim().parse::<u64>()?);
        }
        if started.elapsed() > Duration::from_secs(1800) {
            child.kill()?;
            child.wait()?;
            return Err("export resource check timed out".into());
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    let status = child.wait()?;
    let [stdout, stderr] = output_readers.map(|reader| reader.join().unwrap().unwrap());
    let result = success(std::process::Output {
        status,
        stdout,
        stderr,
    });
    eprintln!(
        "{label}: {:.3}s, peak sampled RSS {:.1} MiB",
        started.elapsed().as_secs_f64(),
        peak_kib as f64 / 1024.0
    );
    assert!(
        peak_kib < 512 * 1024,
        "export RSS exceeded 512 MiB: {peak_kib} KiB"
    );
    Ok(serde_json::from_slice(&result.stdout)?)
}
