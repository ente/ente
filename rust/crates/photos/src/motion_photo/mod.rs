mod ftyp;
mod xmp;

use ftyp::find_largest_ftyp_segment;
use std::collections::HashMap;
use std::fmt::{Display, Formatter};
use std::fs;
use std::path::{Component, Path, PathBuf};

const ITEM_LENGTH_OFFSET_KEY: &str = "Item:Length";
const GCAMERA_MOTION_PHOTO: &str = "GCamera:MotionPhoto";
const ITEM_MIME_TYPE: &str = "Item:Mime";
const FILE_OFFSET_KEYS: [&str; 2] = [ITEM_LENGTH_OFFSET_KEY, "GCamera:MicroVideoOffset"];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VideoIndex {
    pub start: usize,
    pub end: usize,
}

#[derive(Debug)]
pub enum MotionPhotoError {
    Io(std::io::Error),
    Xml(String),
    InvalidIndex,
    InvalidFileName,
    VideoNotFound,
}

impl Display for MotionPhotoError {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io(err) => write!(f, "io error: {err}"),
            Self::Xml(err) => write!(f, "xmp parse error: {err}"),
            Self::InvalidIndex => write!(f, "invalid video index"),
            Self::InvalidFileName => write!(f, "invalid output file name"),
            Self::VideoNotFound => write!(f, "unable to find video index"),
        }
    }
}

impl std::error::Error for MotionPhotoError {}

impl From<std::io::Error> for MotionPhotoError {
    fn from(value: std::io::Error) -> Self {
        Self::Io(value)
    }
}

pub fn get_motion_video_index_from_path<P: AsRef<Path>>(
    file_path: P,
) -> Result<Option<VideoIndex>, MotionPhotoError> {
    let bytes = fs::read(file_path)?;
    Ok(get_motion_video_index(&bytes))
}

fn get_motion_video_index(bytes: &[u8]) -> Option<VideoIndex> {
    if let Some(index) = find_largest_ftyp_segment(bytes) {
        return Some(index);
    }

    extract_video_index_from_xmp(bytes)
}

pub fn extract_motion_video_from_path<P: AsRef<Path>>(
    file_path: P,
    index: Option<VideoIndex>,
) -> Result<Option<Vec<u8>>, MotionPhotoError> {
    let bytes = fs::read(file_path)?;
    extract_motion_video(&bytes, index).map(Some)
}

fn extract_motion_video(
    bytes: &[u8],
    index: Option<VideoIndex>,
) -> Result<Vec<u8>, MotionPhotoError> {
    let video_index = index.or_else(|| get_motion_video_index(bytes));
    let video_index = match video_index {
        Some(value) => value,
        None => return Err(MotionPhotoError::VideoNotFound),
    };

    if video_index.start >= video_index.end || video_index.end > bytes.len() {
        return Err(MotionPhotoError::InvalidIndex);
    }

    Ok(bytes[video_index.start..video_index.end].to_vec())
}

pub fn extract_motion_video_file_from_path<P: AsRef<Path>, Q: AsRef<Path>>(
    file_path: P,
    destination_directory: Q,
    file_name: &str,
    index: Option<VideoIndex>,
) -> Result<Option<PathBuf>, MotionPhotoError> {
    validate_output_file_name(file_name)?;

    let video = match extract_motion_video_from_path(file_path, index)? {
        Some(data) => data,
        None => return Ok(None),
    };
    fs::create_dir_all(destination_directory.as_ref())?;
    let output = destination_directory.as_ref().join(file_name);
    fs::write(&output, video)?;
    Ok(Some(output))
}

fn validate_output_file_name(file_name: &str) -> Result<(), MotionPhotoError> {
    if file_name.is_empty() || file_name.contains('/') || file_name.contains('\\') {
        return Err(MotionPhotoError::InvalidFileName);
    }

    let mut components = Path::new(file_name).components();
    match (components.next(), components.next()) {
        (Some(Component::Normal(name)), None) if name.to_str() == Some(file_name) => Ok(()),
        _ => Err(MotionPhotoError::InvalidFileName),
    }
}

pub fn extract_xmp_from_path<P: AsRef<Path>>(
    file_path: P,
) -> Result<HashMap<String, String>, MotionPhotoError> {
    let bytes = fs::read(file_path)?;
    xmp::extract_xmp(&bytes)
}

fn extract_video_index_from_xmp(bytes: &[u8]) -> Option<VideoIndex> {
    let xmp_data = xmp::extract_xmp(bytes).ok()?;
    let size = bytes.len();

    for offset_key in FILE_OFFSET_KEYS {
        let Some(raw_offset) = xmp_data.get(offset_key) else {
            continue;
        };
        let Ok(offset_from_end) = raw_offset.parse::<usize>() else {
            continue;
        };

        if offset_key == ITEM_LENGTH_OFFSET_KEY
            && offset_from_end + offset_from_end < size
            && !has_motion_photo_tags(&xmp_data)
        {
            continue;
        }

        if offset_from_end == 0 || offset_from_end > size {
            continue;
        }

        return Some(VideoIndex {
            start: size - offset_from_end,
            end: size,
        });
    }

    None
}

fn has_motion_photo_tags(xmp_data: &HashMap<String, String>) -> bool {
    if xmp_data.contains_key(GCAMERA_MOTION_PHOTO) {
        return true;
    }

    xmp_data
        .get(ITEM_MIME_TYPE)
        .map(|value| value.starts_with("video"))
        .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    /// Build a minimal ftyp box with the given major brand (16 bytes).
    fn make_ftyp_box(brand: &[u8; 4]) -> Vec<u8> {
        let mut buf = Vec::with_capacity(16);
        buf.extend_from_slice(&16u32.to_be_bytes()); // box size
        buf.extend_from_slice(b"ftyp");
        buf.extend_from_slice(brand);
        buf.extend_from_slice(&0u32.to_be_bytes()); // minor version
        buf
    }

    fn xmp_with_offset(offset: usize, extra_attributes: &str) -> String {
        format!(
            r#"<x:xmpmeta><rdf:RDF><rdf:Description xmlns:x="adobe:ns:meta/" xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" Item:Length="{offset}" {extra_attributes} /></rdf:RDF></x:xmpmeta>"#
        )
    }

    fn append_video_payload(mut bytes: Vec<u8>, payload_len: usize) -> Vec<u8> {
        bytes.extend(std::iter::repeat_n(0xAB, payload_len));
        bytes
    }

    fn bytes_with_xmp_and_video(offset: usize, extra_attributes: &str) -> Vec<u8> {
        let mut bytes = b"jpeg-prefix-data".to_vec();
        bytes.extend_from_slice(xmp_with_offset(offset, extra_attributes).as_bytes());
        append_video_payload(bytes, offset)
    }

    #[test]
    fn finds_ftyp_box_in_jpeg_like_file() {
        let mut bytes = b"jpeg-prefix".to_vec();
        bytes.extend_from_slice(&make_ftyp_box(b"mp42"));
        bytes.extend_from_slice(&[1, 2, 3, 4]);

        let index = get_motion_video_index(&bytes).expect("video index should exist");
        assert_eq!(index.start, "jpeg-prefix".len());
        assert_eq!(index.end, bytes.len());
    }

    #[test]
    fn picks_largest_segment_when_multiple_ftyp_exist() {
        // Scenario 1: first segment is larger (full video first, preview second)
        let mut bytes = b"jpeg-prefix".to_vec();
        let first_start = bytes.len();
        bytes.extend_from_slice(&make_ftyp_box(b"mp42"));
        bytes.extend_from_slice(&[0xAA; 500]); // large segment
        let second_start = bytes.len();
        bytes.extend_from_slice(&make_ftyp_box(b"isom"));
        bytes.extend_from_slice(&[0xBB; 50]); // small segment

        let index = get_motion_video_index(&bytes).expect("video index should exist");
        assert_eq!(index.start, first_start);
        assert_eq!(index.end, second_start);
        let extracted =
            extract_motion_video(&bytes, Some(index)).expect("video bytes should extract");
        assert_eq!(extracted.len(), second_start - first_start);

        // Scenario 2: second segment is larger (preview first, full video second)
        let mut bytes2 = b"jpeg-prefix".to_vec();
        bytes2.extend_from_slice(&make_ftyp_box(b"mp42"));
        bytes2.extend_from_slice(&[0xCC; 50]); // small segment
        let second_start = bytes2.len();
        bytes2.extend_from_slice(&make_ftyp_box(b"isom"));
        bytes2.extend_from_slice(&[0xDD; 500]); // large segment

        let index2 = get_motion_video_index(&bytes2).expect("video index should exist");
        assert_eq!(index2.start, second_start);
        assert_eq!(index2.end, bytes2.len());
    }

    #[test]
    fn detects_various_mp4_brands() {
        for brand in [
            b"isom", b"mp41", b"mp42", b"avc1", b"iso2", b"M4V ", b"qt  ",
        ] {
            let mut bytes = b"jpeg-prefix-data".to_vec();
            bytes.extend_from_slice(&make_ftyp_box(brand));
            bytes.extend_from_slice(&[0xDE, 0xAD]);
            let index = get_motion_video_index(&bytes)
                .unwrap_or_else(|| panic!("should detect brand {:?}", std::str::from_utf8(brand)));
            assert_eq!(index.start, b"jpeg-prefix-data".len());
        }
    }

    #[test]
    fn rejects_non_video_ftyp_brands() {
        for brand in [b"heic", b"heif", b"mif1", b"avif"] {
            let mut bytes = b"jpeg-prefix-data".to_vec();
            bytes.extend_from_slice(&make_ftyp_box(brand));
            bytes.extend_from_slice(&[0xDE, 0xAD]);
            assert_eq!(
                get_motion_video_index(&bytes),
                None,
                "brand {:?} should not be detected as video",
                std::str::from_utf8(brand)
            );
        }
    }

    #[test]
    fn detects_ftyp_with_larger_box_size() {
        let mut bytes = b"jpeg-prefix-data".to_vec();
        let box_start = bytes.len();
        // 28-byte ftyp box (like Pixel 6): size + "ftyp" + brand + version + compat brands
        bytes.extend_from_slice(&28u32.to_be_bytes());
        bytes.extend_from_slice(b"ftyp");
        bytes.extend_from_slice(b"isom");
        bytes.extend_from_slice(&0x00020000u32.to_be_bytes());
        bytes.extend_from_slice(b"isomiso2mp41");
        bytes.extend_from_slice(b"video-payload");

        let index = get_motion_video_index(&bytes).expect("should detect 28-byte ftyp box");
        assert_eq!(index.start, box_start);
    }

    #[test]
    fn rejects_ftyp_at_file_start() {
        let mut bytes = make_ftyp_box(b"mp42");
        bytes.extend_from_slice(b"moov-data-here");
        assert_eq!(get_motion_video_index(&bytes), None);
    }

    #[test]
    fn rejects_ftyp_with_implausible_box_size() {
        let mut bytes = b"jpeg-prefix-data".to_vec();
        bytes.extend_from_slice(&0u32.to_be_bytes()); // box size 0 (invalid)
        bytes.extend_from_slice(b"ftyp");
        bytes.extend_from_slice(b"mp42");
        bytes.extend_from_slice(&0u32.to_be_bytes());
        assert_eq!(get_motion_video_index(&bytes), None);
    }

    #[test]
    fn finds_xmp_offset_for_jpeg_like_file() {
        let bytes = bytes_with_xmp_and_video(24, "GCamera:MotionPhoto=\"1\"");
        let index = get_motion_video_index(&bytes).expect("video index should exist");
        assert_eq!(index.start, bytes.len() - 24);
        assert_eq!(index.end, bytes.len());
    }

    #[test]
    fn finds_xmp_offset_for_heic_like_file() {
        let mut bytes = b"heic-prefix-data".to_vec();
        bytes.extend_from_slice(xmp_with_offset(32, "Item:Mime=\"video/mp4\"").as_bytes());
        bytes = append_video_payload(bytes, 32);

        let index = get_motion_video_index(&bytes).expect("video index should exist");
        assert_eq!(index.start, bytes.len() - 32);
        assert_eq!(index.end, bytes.len());
    }

    #[test]
    fn returns_none_for_non_motion_file() {
        let bytes = b"plain-still-image-data-without-motion-video-or-xmp".to_vec();
        assert_eq!(get_motion_video_index(&bytes), None);
    }

    #[test]
    fn skips_invalid_item_length_without_motion_tags() {
        let mut bytes = b"prefix-data".to_vec();
        bytes.extend_from_slice(xmp_with_offset(8, "").as_bytes());
        bytes.extend_from_slice(b"small-tail");
        assert_eq!(get_motion_video_index(&bytes), None);
    }

    #[test]
    fn extracts_video_bytes_for_valid_index() {
        let bytes = bytes_with_xmp_and_video(20, "GCamera:MotionPhoto=\"1\"");
        let video = extract_motion_video(&bytes, None).expect("video bytes should extract");
        assert_eq!(video.len(), 20);
        assert!(video.iter().all(|byte| *byte == 0xAB));
    }

    #[test]
    fn extracts_video_file_to_output_basename() {
        let temp = tempdir().expect("temp dir");
        let image = temp.path().join("motion.jpg");
        let output_dir = temp.path().join("out");
        fs::write(
            &image,
            bytes_with_xmp_and_video(20, "GCamera:MotionPhoto=\"1\""),
        )
        .expect("write motion photo");

        let output = extract_motion_video_file_from_path(&image, &output_dir, "clip.mp4", None)
            .expect("extract motion video")
            .expect("motion video exists");

        assert_eq!(output, output_dir.join("clip.mp4"));
        assert_eq!(fs::read(output).expect("read output").len(), 20);
    }

    #[test]
    fn rejects_output_file_names_that_are_not_basenames() {
        let temp = tempdir().expect("temp dir");
        let image = temp.path().join("motion.jpg");
        let output_dir = temp.path().join("out");
        fs::write(
            &image,
            bytes_with_xmp_and_video(20, "GCamera:MotionPhoto=\"1\""),
        )
        .expect("write motion photo");

        for file_name in [
            "",
            ".",
            "..",
            "../escaped.mp4",
            "nested/escaped.mp4",
            "nested\\escaped.mp4",
            "/tmp/escaped.mp4",
        ] {
            let err = extract_motion_video_file_from_path(&image, &output_dir, file_name, None)
                .expect_err("invalid output file name should fail");
            assert!(matches!(err, MotionPhotoError::InvalidFileName));
        }

        assert!(!temp.path().join("escaped.mp4").exists());
        assert!(!output_dir.join("nested").exists());
    }

    #[test]
    fn extracts_xmp_attributes() {
        let bytes = bytes_with_xmp_and_video(
            16,
            "GPano:ProjectionType=\"equirectangular\" GCamera:MotionPhoto=\"1\"",
        );
        let xmp = xmp::extract_xmp(&bytes).expect("xmp must parse");
        assert_eq!(
            xmp.get("GPano:ProjectionType"),
            Some(&"equirectangular".to_string())
        );
        assert_eq!(xmp.get("GCamera:MotionPhoto"), Some(&"1".to_string()));
    }

    #[test]
    fn path_apis_work_for_various_file_types() {
        let temp = tempdir().expect("temp dir");
        let jpeg_motion = temp.path().join("motion.jpg");
        let heic_motion = temp.path().join("motion.heic");
        let non_motion = temp.path().join("normal.jpg");

        fs::write(
            &jpeg_motion,
            bytes_with_xmp_and_video(40, "GCamera:MotionPhoto=\"1\""),
        )
        .expect("write jpeg motion");

        fs::write(
            &heic_motion,
            bytes_with_xmp_and_video(28, "Item:Mime=\"video/mp4\""),
        )
        .expect("write heic motion");

        fs::write(&non_motion, b"non-motion-image").expect("write still");

        assert!(
            get_motion_video_index_from_path(&jpeg_motion)
                .expect("jpeg read")
                .is_some()
        );
        assert!(
            get_motion_video_index_from_path(&heic_motion)
                .expect("heic read")
                .is_some()
        );
        assert_eq!(
            get_motion_video_index_from_path(&non_motion).expect("still read"),
            None
        );
    }
}
