use super::ONLY_PHOTOS_UPLOAD_MESSAGE;
use crate::error::{Error, Result};

pub(crate) fn ensure_supported_photo_media_type(
    media_type: Option<&str>,
) -> Result<Option<String>> {
    let Some(media_type) = media_type.map(str::trim).filter(|value| !value.is_empty()) else {
        return Ok(None);
    };
    let normalized = media_type.to_ascii_lowercase();
    if matches!(
        normalized.as_str(),
        "image/jpeg" | "image/jpg" | "image/png" | "image/webp" | "image/heic" | "image/heif"
    ) {
        return Ok(Some(if normalized == "image/jpg" {
            "image/jpeg".to_owned()
        } else {
            normalized
        }));
    }

    Err(Error::InvalidInput(ONLY_PHOTOS_UPLOAD_MESSAGE.into()))
}

pub(crate) fn ensure_supported_photo_bytes(bytes: &[u8]) -> Result<&'static str> {
    if let Some(media_type) = supported_photo_media_type_for_bytes(bytes) {
        return Ok(media_type);
    }

    Err(Error::InvalidInput(ONLY_PHOTOS_UPLOAD_MESSAGE.into()))
}

pub(crate) fn supported_photo_media_type_for_bytes(bytes: &[u8]) -> Option<&'static str> {
    if bytes.starts_with(&[0xff, 0xd8, 0xff]) {
        return Some("image/jpeg");
    }
    if bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
        return Some("image/png");
    }
    if bytes.len() >= 12 && bytes.starts_with(b"RIFF") && &bytes[8..12] == b"WEBP" {
        return Some("image/webp");
    }
    if is_supported_heif_bytes(bytes) {
        return Some("image/heic");
    }
    None
}

fn is_supported_heif_bytes(bytes: &[u8]) -> bool {
    if bytes.len() < 12 || &bytes[4..8] != b"ftyp" {
        return false;
    }
    let brand = &bytes[8..12];
    brand == b"heic"
        || brand == b"heix"
        || brand == b"hevc"
        || brand == b"hevx"
        || brand == b"heim"
        || brand == b"heis"
        || brand == b"hevm"
        || brand == b"hevs"
        || brand == b"mif1"
        || brand == b"msf1"
}
