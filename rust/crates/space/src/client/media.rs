//! Photo media-type validation for Space uploads.
//!
//! Space posts accept photos only. These helpers normalize a client-declared
//! media type and sniff raw bytes by magic number, so a caller can reject
//! non-photo uploads before they reach the object store.

use super::ONLY_PHOTOS_UPLOAD_MESSAGE;
use crate::error::{Result, SpaceError};

/// Normalize a client-declared photo media type, rejecting anything that is not
/// a supported still image. `image/jpg` is folded to `image/jpeg`. Returns
/// `Ok(None)` when no media type was provided.
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

    Err(SpaceError::InvalidInput(ONLY_PHOTOS_UPLOAD_MESSAGE.into()))
}

/// Infer the media type of `bytes` from its magic number, erroring if it is not
/// a supported photo format.
pub(crate) fn ensure_supported_photo_bytes(bytes: &[u8]) -> Result<&'static str> {
    if let Some(media_type) = supported_photo_media_type_for_bytes(bytes) {
        return Ok(media_type);
    }

    Err(SpaceError::InvalidInput(ONLY_PHOTOS_UPLOAD_MESSAGE.into()))
}

/// Sniff `bytes` and return the matching photo media type, or `None` if the
/// leading bytes match no supported format.
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

/// Whether `bytes` is an ISOBMFF/HEIF container with a still-image brand we
/// accept (HEIC/HEIF and the related single-image and sequence brands).
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
