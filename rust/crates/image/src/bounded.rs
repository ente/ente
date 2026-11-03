use std::{
    fs::File,
    io::{BufRead, BufReader, Cursor, Seek},
};

use crate::{DecodedImage, Dimensions, ImageError, ImageResult};

const MAX_SIDE: u32 = 6000;

pub enum ImageInput<'a> {
    Path(&'a str),
    Bytes(&'a [u8]),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct BoundedDecodeOptions {
    pub max_side: u32,
    pub max_memory_bytes: u64,
}

impl Default for BoundedDecodeOptions {
    fn default() -> Self {
        Self {
            max_side: MAX_SIDE,
            max_memory_bytes: 512 * 1024 * 1024,
        }
    }
}

#[derive(Clone, Debug)]
pub struct BoundedDecodedImage {
    pub image: DecodedImage,
    pub original_dimensions: Dimensions,
}

enum Format {
    Png,
    Heif,
}

pub fn decode_bounded(
    input: ImageInput<'_>,
    options: BoundedDecodeOptions,
) -> ImageResult<BoundedDecodedImage> {
    if !(1..=MAX_SIDE).contains(&options.max_side) {
        return Err(ImageError::Postprocess(format!(
            "maximum side must be between 1 and {MAX_SIDE}"
        )));
    }
    match input {
        ImageInput::Path(path) => {
            let file = File::open(path).map_err(|error| {
                ImageError::Decode(format!("failed to open image file '{path}': {error}"))
            })?;
            let mut reader = BufReader::new(file);
            let header = reader
                .fill_buf()
                .map_err(|error| ImageError::Decode(error.to_string()))?;
            decode_format(sniff(header), reader, input, options)
        }
        ImageInput::Bytes(bytes) => decode_format(sniff(bytes), Cursor::new(bytes), input, options),
    }
}

fn sniff(header: &[u8]) -> Option<Format> {
    if header.starts_with(crate::png::SIGNATURE) {
        Some(Format::Png)
    } else if has_heif_brand(header) {
        Some(Format::Heif)
    } else {
        None
    }
}

fn has_heif_brand(header: &[u8]) -> bool {
    let Some((size, rest)) = header.split_first_chunk::<4>() else {
        return false;
    };
    let Some((kind, rest)) = rest.split_first_chunk::<4>() else {
        return false;
    };
    if kind != b"ftyp" {
        return false;
    }
    let (box_size, header_size, brands) = if *size == [0, 0, 0, 1] {
        let Some((large_size, brands)) = rest.split_first_chunk::<8>() else {
            return false;
        };
        (u64::from_be_bytes(*large_size), 16, brands)
    } else {
        (u64::from(u32::from_be_bytes(*size)), 8, rest)
    };
    let length = usize::try_from(box_size.saturating_sub(header_size))
        .unwrap_or(usize::MAX)
        .min(brands.len());
    brands[..length]
        .as_chunks::<4>()
        .0
        .iter()
        .enumerate()
        .any(|(index, brand)| index != 1 && matches!(brand, b"heic" | b"heix" | b"mif1"))
}

fn decode_format<R: BufRead + Seek>(
    format: Option<Format>,
    reader: R,
    input: ImageInput<'_>,
    options: BoundedDecodeOptions,
) -> ImageResult<BoundedDecodedImage> {
    match format {
        Some(Format::Png) => crate::png::decode(reader, options),
        Some(Format::Heif) => crate::heif::decode(input, options),
        None => Err(ImageError::Decode(
            "unsupported format for bounded decoding: only PNG and HEIC are supported".into(),
        )),
    }
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

pub(crate) fn too_large() -> ImageError {
    image::ImageError::Limits(image::error::LimitError::from_kind(
        image::error::LimitErrorKind::InsufficientMemory,
    ))
    .into()
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::{
        decode::decode_image_from_bytes,
        image_compression::{EncodedImageFormat, encode_rgb},
    };

    pub(crate) fn options(max_side: u32) -> BoundedDecodeOptions {
        BoundedDecodeOptions {
            max_side,
            ..BoundedDecodeOptions::default()
        }
    }

    fn encode(format: EncodedImageFormat) -> Vec<u8> {
        encode_rgb(&[100; 12 * 8 * 3], 12, 8, format).unwrap()
    }

    #[test]
    fn rejects_max_side_outside_supported_range() {
        let png = encode(EncodedImageFormat::Png);
        assert!(decode_bounded(ImageInput::Bytes(&png), options(MAX_SIDE)).is_ok());
        for max_side in [0, MAX_SIDE + 1] {
            assert!(matches!(
                decode_bounded(ImageInput::Bytes(&png), options(max_side)),
                Err(ImageError::Postprocess(_))
            ));
        }
    }

    #[test]
    fn rejects_unsupported_formats_from_bytes_and_paths_without_affecting_existing_decode() {
        let jpeg = encode(EncodedImageFormat::Jpeg { quality: 90 });
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
            b"GIF89a\x01\0\x01\0\0\0\0;",
            b"\0\0\0\x14ftypisom\0\0\0\0isom",
            b"\0\0\0\x10ftypisomheic",
            b"not an image",
            b"",
        ] {
            std::fs::write(&path, bytes).unwrap();
            for input in [
                ImageInput::Bytes(bytes),
                ImageInput::Path(path.to_str().unwrap()),
            ] {
                assert!(matches!(
                    decode_bounded(input, options(MAX_SIDE)),
                    Err(ImageError::Decode(message)) if message.contains("unsupported format")
                ));
            }
        }
    }

    #[test]
    fn heif_brands_route_to_the_heif_decoder() {
        for bytes in [
            &b"\0\0\0\x18ftypheic\0\0\0\0mif1heic"[..],
            b"\0\0\0\x18ftypmiaf\0\0\0\0mif1heic",
            b"\0\0\0\x01ftyp\0\0\0\0\0\0\0\x18heic\0\0\0\0",
        ] {
            assert!(matches!(
                decode_bounded(ImageInput::Bytes(bytes), options(MAX_SIDE)),
                Err(ImageError::Decode(message)) if !message.contains("unsupported format")
            ));
        }
    }
}
