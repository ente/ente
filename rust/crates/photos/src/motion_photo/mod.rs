mod ftyp;
mod xmp;

use ftyp::find_largest_ftyp_segment;
use std::collections::HashMap;
use std::fmt::{Display, Formatter};
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::path::{Component, Path, PathBuf};

const BUFFER_SIZE: usize = 64 * 1024;
const MAX_VIDEO_BYTES_SIZE: usize = 64 * 1024 * 1024;

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
    VideoTooLarge,
    XmpTooLarge,
}

impl Display for MotionPhotoError {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io(err) => write!(f, "io error: {err}"),
            Self::Xml(err) => write!(f, "xmp parse error: {err}"),
            Self::InvalidIndex => write!(f, "invalid video index"),
            Self::InvalidFileName => write!(f, "invalid output file name"),
            Self::VideoNotFound => write!(f, "unable to find video index"),
            Self::VideoTooLarge => write!(
                f,
                "video exceeds {MAX_VIDEO_BYTES_SIZE} byte limit; use file extraction"
            ),
            Self::XmpTooLarge => write!(f, "xmp exceeds {} byte limit", xmp::MAX_XMP_SIZE),
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
    let mut file = File::open(file_path)?;
    let size = file_size(&file)?;
    get_motion_video_index(&mut file, size)
}

fn file_size(file: &File) -> Result<usize, MotionPhotoError> {
    usize::try_from(file.metadata()?.len()).map_err(|_| MotionPhotoError::InvalidIndex)
}

fn get_motion_video_index<R: Read + Seek>(
    reader: &mut R,
    size: usize,
) -> Result<Option<VideoIndex>, MotionPhotoError> {
    reader.rewind()?;
    if let Some(index) = find_largest_ftyp_segment(&mut *reader, size)? {
        return Ok(Some(index));
    }

    reader.rewind()?;
    match xmp::extract_xmp(reader.take(size as u64)) {
        Ok(data) => Ok(extract_video_index_from_xmp(&data, size)),
        Err(MotionPhotoError::Xml(_)) => Ok(None),
        // None clears existing motion-photo tags.
        Err(err) => Err(err),
    }
}

pub fn extract_motion_video_from_path<P: AsRef<Path>>(
    file_path: P,
    index: Option<VideoIndex>,
) -> Result<Option<Vec<u8>>, MotionPhotoError> {
    let mut file = File::open(file_path)?;
    let size = file_size(&file)?;
    let index = resolve_video_index(&mut file, size, index)?;
    let length = index.end - index.start;
    if length > MAX_VIDEO_BYTES_SIZE {
        return Err(MotionPhotoError::VideoTooLarge);
    }
    file.seek(SeekFrom::Start(index.start as u64))?;
    let mut video = vec![0; length];
    file.read_exact(&mut video)?;
    Ok(Some(video))
}

fn resolve_video_index<R: Read + Seek>(
    reader: &mut R,
    size: usize,
    index: Option<VideoIndex>,
) -> Result<VideoIndex, MotionPhotoError> {
    let index = match index {
        Some(index) => index,
        None => get_motion_video_index(reader, size)?.ok_or(MotionPhotoError::VideoNotFound)?,
    };
    if index.start >= index.end || index.end > size {
        return Err(MotionPhotoError::InvalidIndex);
    }
    Ok(index)
}

pub fn extract_motion_video_file_from_path<P: AsRef<Path>, Q: AsRef<Path>>(
    file_path: P,
    destination_directory: Q,
    file_name: &str,
    index: Option<VideoIndex>,
) -> Result<Option<PathBuf>, MotionPhotoError> {
    validate_output_file_name(file_name)?;

    let mut source = File::open(file_path)?;
    let size = file_size(&source)?;
    let index = resolve_video_index(&mut source, size, index)?;
    source.seek(SeekFrom::Start(index.start as u64))?;
    fs::create_dir_all(destination_directory.as_ref())?;
    let output = destination_directory.as_ref().join(file_name);
    // Copy forward before truncating: output may alias the source.
    let mut destination = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(false)
        .open(&output)?;
    let length = index.end - index.start;
    copy_video(&mut source, &mut destination, length)?;
    destination.set_len(length as u64)?;
    Ok(Some(output))
}

fn copy_video<R: Read, W: Write>(
    source: &mut R,
    destination: &mut W,
    mut remaining: usize,
) -> io::Result<()> {
    let mut buffer = vec![0; BUFFER_SIZE];
    while remaining > 0 {
        let length = remaining.min(buffer.len());
        source.read_exact(&mut buffer[..length])?;
        destination.write_all(&buffer[..length])?;
        remaining -= length;
    }
    Ok(())
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
    let file = File::open(file_path)?;
    let size = file_size(&file)?;
    xmp::extract_xmp(file.take(size as u64))
}

fn extract_video_index_from_xmp(
    xmp_data: &HashMap<String, String>,
    size: usize,
) -> Option<VideoIndex> {
    for offset_key in FILE_OFFSET_KEYS {
        let Some(raw_offset) = xmp_data.get(offset_key) else {
            continue;
        };
        let Ok(offset_from_end) = raw_offset.parse::<usize>() else {
            continue;
        };

        if offset_from_end == 0 || offset_from_end > size {
            continue;
        }
        if offset_key == ITEM_LENGTH_OFFSET_KEY
            && offset_from_end < size - offset_from_end
            && !has_motion_photo_tags(xmp_data)
        {
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
    use std::io::Cursor;
    use tempfile::tempdir;

    fn get_motion_video_index(bytes: &[u8]) -> Option<VideoIndex> {
        super::get_motion_video_index(&mut Cursor::new(bytes), bytes.len()).expect("read index")
    }

    fn make_ftyp_box(brand: [u8; 4]) -> Vec<u8> {
        let mut buf = Vec::with_capacity(16);
        buf.extend_from_slice(&16u32.to_be_bytes());
        buf.extend_from_slice(b"ftyp");
        buf.extend_from_slice(&brand);
        buf.extend_from_slice(&0u32.to_be_bytes());
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
        bytes.extend_from_slice(&make_ftyp_box(*b"mp42"));
        bytes.extend_from_slice(&[1, 2, 3, 4]);

        let index = get_motion_video_index(&bytes).expect("video index should exist");
        assert_eq!(index.start, "jpeg-prefix".len());
        assert_eq!(index.end, bytes.len());
    }

    #[test]
    fn picks_largest_segment_when_multiple_ftyp_exist() {
        let mut bytes = b"jpeg-prefix".to_vec();
        let first_start = bytes.len();
        bytes.extend_from_slice(&make_ftyp_box(*b"mp42"));
        bytes.extend_from_slice(&[0xAA; 500]);
        let second_start = bytes.len();
        bytes.extend_from_slice(&make_ftyp_box(*b"isom"));
        bytes.extend_from_slice(&[0xBB; 50]);

        let index = get_motion_video_index(&bytes).expect("video index should exist");
        assert_eq!(index.start, first_start);
        assert_eq!(index.end, second_start);
        let mut bytes2 = b"jpeg-prefix".to_vec();
        bytes2.extend_from_slice(&make_ftyp_box(*b"mp42"));
        bytes2.extend_from_slice(&[0xCC; 50]);
        let second_start = bytes2.len();
        bytes2.extend_from_slice(&make_ftyp_box(*b"isom"));
        bytes2.extend_from_slice(&[0xDD; 500]);

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
            bytes.extend_from_slice(&make_ftyp_box(*brand));
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
            bytes.extend_from_slice(&make_ftyp_box(*brand));
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
        let mut bytes = make_ftyp_box(*b"mp42");
        bytes.extend_from_slice(b"moov-data-here");
        assert_eq!(get_motion_video_index(&bytes), None);
    }

    #[test]
    fn rejects_ftyp_with_implausible_box_size() {
        let mut bytes = b"jpeg-prefix-data".to_vec();
        bytes.extend_from_slice(&0u32.to_be_bytes());
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
        for offset in [8, usize::MAX] {
            let mut bytes = b"prefix-data".to_vec();
            bytes.extend_from_slice(xmp_with_offset(offset, "").as_bytes());
            bytes.extend_from_slice(b"small-tail");
            assert_eq!(get_motion_video_index(&bytes), None);
        }
    }

    #[test]
    fn extracts_video_bytes_for_valid_index() {
        let bytes = bytes_with_xmp_and_video(20, "GCamera:MotionPhoto=\"1\"");
        let temp = tempdir().unwrap();
        let image = temp.path().join("motion.jpg");
        fs::write(&image, bytes).unwrap();
        let video = extract_motion_video_from_path(&image, None)
            .unwrap()
            .unwrap();
        assert_eq!(video, vec![0xAB; 20]);
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
    fn file_extraction_rejects_invalid_input_before_creating_output() {
        let temp = tempdir().expect("temp dir");
        let image = temp.path().join("source.jpg");
        let output_dir = temp.path().join("out");
        fs::write(&image, b"still image").expect("write source");

        for index in [
            VideoIndex { start: 0, end: 0 },
            VideoIndex { start: 5, end: 3 },
            VideoIndex { start: 0, end: 12 },
        ] {
            assert!(matches!(
                extract_motion_video_file_from_path(&image, &output_dir, "clip.mp4", Some(index)),
                Err(MotionPhotoError::InvalidIndex)
            ));
            assert!(!output_dir.exists());
        }

        assert!(matches!(
            extract_motion_video_file_from_path(&image, &output_dir, "clip.mp4", None),
            Err(MotionPhotoError::VideoNotFound)
        ));
        assert!(!output_dir.exists());
    }

    #[test]
    fn file_extraction_preserves_selected_bytes_when_overwriting() {
        let temp = tempdir().expect("temp dir");
        let image = temp.path().join("source.jpg");
        let source: Vec<u8> = (0..BUFFER_SIZE * 3 + 19).map(|i| (i % 251) as u8).collect();
        fs::write(&image, &source).unwrap();
        fs::hard_link(&image, temp.path().join("hard.mp4")).unwrap();
        #[cfg(unix)]
        std::os::unix::fs::symlink(&image, temp.path().join("symbolic.mp4")).unwrap();

        for file_name in [
            "clip.mp4",
            "source.jpg",
            "hard.mp4",
            #[cfg(unix)]
            "symbolic.mp4",
        ] {
            for start in [0, 13] {
                fs::write(&image, &source).unwrap();
                fs::write(temp.path().join(file_name), &source).unwrap();
                let end = source.len() - 7;
                let output = extract_motion_video_file_from_path(
                    &image,
                    temp.path(),
                    file_name,
                    Some(VideoIndex { start, end }),
                )
                .unwrap()
                .unwrap();
                assert_eq!(fs::read(output).unwrap(), source[start..end]);
            }
        }
    }

    #[test]
    fn extracts_xmp_attributes() {
        let bytes = bytes_with_xmp_and_video(
            16,
            "GPano:ProjectionType=\"equirectangular\" GCamera:MotionPhoto=\"1\"",
        );
        let xmp = xmp::extract_xmp(bytes.as_slice()).expect("xmp must parse");
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

    #[test]
    fn file_extraction_streams_videos_above_the_byte_api_limit() {
        let temp = tempdir().unwrap();
        let image = temp.path().join("source.jpg");
        let length = MAX_VIDEO_BYTES_SIZE + 1;
        File::create(&image)
            .unwrap()
            .set_len(length as u64 + 1)
            .unwrap();
        let index = VideoIndex {
            start: 1,
            end: length + 1,
        };
        assert!(matches!(
            extract_motion_video_from_path(&image, Some(index.clone())),
            Err(MotionPhotoError::VideoTooLarge)
        ));
        let output =
            extract_motion_video_file_from_path(&image, temp.path(), "clip.mp4", Some(index))
                .unwrap()
                .unwrap();
        assert_eq!(fs::metadata(output).unwrap().len(), length as u64);
    }

    #[test]
    fn copying_is_bounded_and_rejects_short_input() {
        struct BoundedReader(Cursor<Vec<u8>>);
        impl Read for BoundedReader {
            fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
                assert!(buffer.len() <= BUFFER_SIZE);
                self.0.read(buffer)
            }
        }
        let length = BUFFER_SIZE * 3 + 5;
        let mut source = BoundedReader(Cursor::new(vec![7; length]));
        let mut output = Vec::new();
        copy_video(&mut source, &mut output, length).unwrap();
        assert_eq!(output, vec![7; length]);
        let error = copy_video(&mut Cursor::new([1; 3]), &mut io::sink(), 4).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::UnexpectedEof);
    }

    #[test]
    fn ftyp_takes_precedence_over_oversized_xmp() {
        let mut bytes = b"<x:xmpmeta>".to_vec();
        bytes.resize(xmp::MAX_XMP_SIZE + 1, b' ');
        assert!(matches!(
            super::get_motion_video_index(&mut Cursor::new(&bytes), bytes.len()),
            Err(MotionPhotoError::XmpTooLarge)
        ));
        let start = bytes.len();
        bytes.extend_from_slice(&make_ftyp_box(*b"mp42"));
        assert_eq!(
            get_motion_video_index(&bytes),
            Some(VideoIndex {
                start,
                end: bytes.len()
            })
        );
    }
}
