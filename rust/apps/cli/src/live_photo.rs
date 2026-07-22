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
        let (kind, extension) = parse_entry_name(file.name())?;
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
    for entry in [image, video] {
        let mut input = archive.by_index(entry.index)?;
        let path = parent.join(format!("{base}.{}", entry.extension));
        let mut output = fs::File::create(&path).await?;
        let mut buffer = [0; 64 * 1024];
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

    use zip::{CompressionMethod, ZipWriter, write::SimpleFileOptions};

    use super::{extract_live_photo, parse_entry_name};

    fn archive(entries: &[(&str, &[u8])]) -> Vec<u8> {
        let mut writer = ZipWriter::new(Cursor::new(Vec::new()));
        for (name, data) in entries {
            writer
                .start_file(
                    *name,
                    SimpleFileOptions::default().compression_method(CompressionMethod::Deflated),
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
    async fn extracts_image_and_video() {
        let data = archive(&[("image.jpg", b"image"), ("video.mov", b"video")]);
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

    #[tokio::test]
    async fn rejects_excessive_expansion() {
        let oversized = vec![0; super::MAX_EXPANDED_OVERHEAD as usize + 1024 * 1024];
        let data = archive(&[("image.jpg", &oversized), ("video.mov", b"video")]);
        assert!(
            extract_live_photo(&data, Path::new("photo.zip"))
                .await
                .is_err()
        );
    }
}
