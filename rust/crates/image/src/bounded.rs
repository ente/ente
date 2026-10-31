use std::{
    fs::File,
    io::{BufRead, BufReader, Cursor},
};

use crate::{DecodedImage, Dimensions, ImageError, ImageResult};

pub enum ImageInput<'a> {
    Path(&'a str),
    Bytes(&'a [u8]),
}

#[derive(Clone, Debug)]
pub struct BoundedDecodedImage {
    pub image: DecodedImage,
    pub original_dimensions: Dimensions,
}

pub fn decode_bounded(input: ImageInput<'_>, max_side: u32) -> ImageResult<BoundedDecodedImage> {
    decode_bounded_with_cancellation(input, max_side, || false)
}

pub fn decode_bounded_with_cancellation(
    input: ImageInput<'_>,
    max_side: u32,
    is_cancelled: impl Fn() -> bool,
) -> ImageResult<BoundedDecodedImage> {
    if max_side == 0 {
        return Err(ImageError::Postprocess(
            "maximum side must be greater than zero".into(),
        ));
    }
    let check_cancelled = || {
        if is_cancelled() {
            Err(ImageError::Cancelled)
        } else {
            Ok(())
        }
    };
    check_cancelled()?;
    match input {
        ImageInput::Path(path) => {
            let file = File::open(path).map_err(|error| {
                ImageError::Decode(format!("failed to open image file '{path}': {error}"))
            })?;
            let mut reader = BufReader::new(file);
            let header = reader
                .fill_buf()
                .map_err(|error| ImageError::Decode(error.to_string()))?;
            if header.starts_with(crate::png::SIGNATURE) {
                return crate::png::decode(reader, max_side, check_cancelled);
            }
        }
        ImageInput::Bytes(bytes) => {
            if bytes.starts_with(crate::png::SIGNATURE) {
                return crate::png::decode(Cursor::new(bytes), max_side, check_cancelled);
            }
        }
    }
    Err(ImageError::Decode(
        "unsupported format for bounded decoding: only PNG is currently supported".into(),
    ))
}

pub(crate) fn target_dimensions(source: &Dimensions, max_side: u32) -> Dimensions {
    let longest = source.width.max(source.height);
    if longest <= max_side {
        return source.clone();
    }
    let scale = |side| ((u64::from(side) * u64::from(max_side)) / u64::from(longest)).max(1) as u32;
    Dimensions {
        width: scale(source.width),
        height: scale(source.height),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        decode::decode_image_from_bytes,
        image_compression::{EncodedImageFormat, encode_rgb},
    };

    #[test]
    fn rejects_non_png_from_bytes_and_paths_without_affecting_existing_decode() {
        let jpeg = encode_rgb(
            &[100; 12 * 8 * 3],
            12,
            8,
            EncodedImageFormat::Jpeg { quality: 90 },
        )
        .unwrap();
        assert_eq!(
            decode_image_from_bytes(&jpeg).unwrap().dimensions,
            Dimensions {
                width: 12,
                height: 8
            }
        );
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("image.png");
        for bytes in [
            jpeg.as_slice(),
            b"\0\0\0\x18ftypheic\0\0\0\0",
            b"not an image",
            b"",
        ] {
            std::fs::write(&path, bytes).unwrap();
            for input in [
                ImageInput::Bytes(bytes),
                ImageInput::Path(path.to_str().unwrap()),
            ] {
                assert!(matches!(
                    decode_bounded(input, 6000),
                    Err(ImageError::Decode(message)) if message.contains("unsupported format")
                ));
            }
        }
    }
}
