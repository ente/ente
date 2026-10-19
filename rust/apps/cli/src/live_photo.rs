use std::io::{Cursor, Read};
use std::path::Path;

use tokio::fs;
use tokio::io::AsyncWriteExt;
use zip::ZipArchive;

use crate::{Error, Result};

const MAX_EXPANDED_RATIO: u64 = 20;
const MAX_EXPANDED_OVERHEAD: u64 = 16 * 1024 * 1024;

struct Entry {
    index: usize,
    extension: String,
    size: u64,
}

pub(crate) async fn extract_live_photo(zip_data: &[u8], output_path: &Path) -> Result<()> {
    let mut archive = ZipArchive::new(Cursor::new(zip_data))?;
    if archive.len() != 2 {
        return Err(Error::Generic(
            "Live photo ZIP must contain one image and one video".into(),
        ));
    }

    let mut image = None;
    let mut video = None;
    for index in 0..archive.len() {
        let file = archive.by_index(index)?;
        let name = file.name()?;
        let (kind, extension) = parse_entry_name(&name)?;
        let entry = Entry {
            index,
            extension: extension.to_string(),
            size: file.size(),
        };
        let slot = if kind == "image" {
            &mut image
        } else {
            &mut video
        };
        if slot.replace(entry).is_some() {
            return Err(Error::Generic(format!(
                "Live photo ZIP contains multiple {kind} entries"
            )));
        }
    }

    let image = image.ok_or_else(|| Error::Generic("Live photo ZIP has no image".into()))?;
    let video = video.ok_or_else(|| Error::Generic("Live photo ZIP has no video".into()))?;
    let max_expanded = zip_data.len() as u64 * MAX_EXPANDED_RATIO + MAX_EXPANDED_OVERHEAD;
    if image.size + video.size > max_expanded {
        return Err(Error::Generic("Live photo ZIP expands beyond limit".into()));
    }

    let parent = output_path
        .parent()
        .ok_or_else(|| Error::Generic("Invalid output path".into()))?;
    let base = output_path
        .file_stem()
        .and_then(|name| name.to_str())
        .ok_or_else(|| Error::Generic("Invalid filename".into()))?;
    let mut expanded = 0;
    let mut buffer = vec![0; 64 * 1024];
    for entry in [image, video] {
        let mut input = archive.by_index(entry.index)?;
        let path = parent.join(format!("{base}.{}", entry.extension));
        let mut output = fs::File::create(&path).await?;
        loop {
            let count = input.read(&mut buffer)?;
            if count == 0 {
                break;
            }
            expanded += count as u64;
            if expanded > max_expanded {
                return Err(Error::Generic("Live photo ZIP expands beyond limit".into()));
            }
            output.write_all(&buffer[..count]).await?;
        }
        output.sync_all().await?;
        log::debug!("Extracted live photo component: {path:?}");
    }
    Ok(())
}

fn parse_entry_name(name: &str) -> Result<(&str, &str)> {
    let (kind, extension) = name
        .split_once('.')
        .ok_or_else(|| Error::Generic(format!("Invalid live photo entry: {name}")))?;
    if !matches!(kind, "image" | "video")
        || extension.is_empty()
        || extension.len() > 16
        || !extension.bytes().all(|byte| byte.is_ascii_alphanumeric())
    {
        return Err(Error::Generic(format!("Invalid live photo entry: {name}")));
    }
    Ok((kind, extension))
}

#[cfg(test)]
mod tests {
    use std::io::{Cursor, Write};
    use std::path::Path;

    use ente_core::{b64, crypto};
    use mockito::Server;
    use zip::{CompressionMethod, ZipWriter, write::SimpleFileOptions};

    use super::{extract_live_photo, parse_entry_name};
    use crate::api::client::AppClient;
    use crate::models::{account::App, file::RemoteFile};
    use crate::sync::DownloadManager;

    fn archive(entries: &[(&str, &[u8])], compression: CompressionMethod) -> Vec<u8> {
        let mut writer = ZipWriter::new(Cursor::new(Vec::new()));
        for (name, data) in entries {
            writer
                .start_file(
                    *name,
                    SimpleFileOptions::default().compression_method(compression),
                )
                .unwrap();
            writer.write_all(data).unwrap();
        }
        writer.finish().unwrap().into_inner()
    }

    #[test]
    fn validates_entry_names() {
        assert_eq!(parse_entry_name("image.heic").unwrap(), ("image", "heic"));
        assert_eq!(parse_entry_name("video.mov").unwrap(), ("video", "mov"));
        assert!(parse_entry_name("thumbnail.jpg").is_err());
        assert!(parse_entry_name("image.jpg.exe").is_err());
        assert!(parse_entry_name("video../clip").is_err());
    }

    #[tokio::test]
    async fn extracts_stored_and_deflated_components() {
        for compression in [CompressionMethod::Stored, CompressionMethod::Deflated] {
            let data = archive(
                &[("image.jpg", b"image"), ("video.mov", b"video")],
                compression,
            );
            let directory =
                std::env::temp_dir().join(format!("ente-live-photo-test-{}", uuid::Uuid::new_v4()));
            std::fs::create_dir(&directory).unwrap();

            extract_live_photo(&data, &directory.join("photo.zip"))
                .await
                .unwrap();
            assert_eq!(
                std::fs::read(directory.join("photo.jpg")).unwrap(),
                b"image"
            );
            assert_eq!(
                std::fs::read(directory.join("photo.mov")).unwrap(),
                b"video"
            );

            std::fs::remove_dir_all(directory).unwrap();
        }
    }

    #[tokio::test]
    async fn download_preserves_invalid_live_photo_archive() {
        let data = archive(&[("image.jpg", b"image")], CompressionMethod::Deflated);
        let collection_key = crypto::Key::generate();
        let file_key = crypto::Key::generate();
        let encrypted_key = crypto::secretbox::encrypt(file_key.as_bytes(), &collection_key);
        let mut encrypted_data = Vec::new();
        let header =
            crypto::stream::encrypt_file(&mut data.as_slice(), &mut encrypted_data, &file_key)
                .unwrap();
        let file_id = uuid::Uuid::new_v4().as_u64_pair().0 as i64;
        let file: RemoteFile = serde_json::from_value(serde_json::json!({
            "id": file_id,
            "collectionID": 1,
            "ownerID": 1,
            "encryptedKey": b64::encode(&encrypted_key.encrypted_data),
            "keyDecryptionNonce": b64::encode(encrypted_key.nonce.as_bytes()),
            "file": { "decryptionHeader": b64::encode(header.as_bytes()) },
            "thumbnail": { "decryptionHeader": "" },
            "metadata": { "encryptedData": "", "decryptionHeader": "" },
            "isDeleted": false,
            "updatedAt": 0
        }))
        .unwrap();
        let mut server = Server::new_async().await;
        let url_mock = server
            .mock("GET", format!("/files/download/v3/{file_id}").as_str())
            .with_body(serde_json::json!({ "url": format!("{}/object", server.url()) }).to_string())
            .create_async()
            .await;
        let download_mock = server
            .mock("GET", "/object")
            .with_body(encrypted_data)
            .create_async()
            .await;
        let client = AppClient::new(Some(server.url()), App::Photos).unwrap();
        let mut manager = DownloadManager::new(client).unwrap();
        manager.set_collection_keys([(1, collection_key.as_bytes().to_vec())].into());
        let directory =
            std::env::temp_dir().join(format!("ente-live-photo-test-{}", uuid::Uuid::new_v4()));
        let destination = directory.join("photo.zip");

        manager.download_file(&file, &destination).await.unwrap();

        url_mock.assert_async().await;
        download_mock.assert_async().await;
        assert_eq!(std::fs::read(destination).unwrap(), data);
        std::fs::remove_dir_all(directory).unwrap();
    }

    #[tokio::test]
    async fn rejects_excessive_expansion() {
        let oversized = vec![0; super::MAX_EXPANDED_OVERHEAD as usize + 1024 * 1024];
        let data = archive(
            &[("image.jpg", &oversized), ("video.mov", b"video")],
            CompressionMethod::Deflated,
        );
        assert!(
            extract_live_photo(&data, Path::new("photo.zip"))
                .await
                .is_err()
        );
    }
}
