use std::{
    fs::File,
    io::{BufRead, BufReader, Cursor, Seek},
};

use image::metadata::Orientation;

use crate::{DecodedImage, Dimensions, ImageError, ImageResult};

const MAX_SIDE: u32 = 6000;
pub(crate) const MAX_SOURCE_PIXELS: u64 = 500_000_000;
const TRANSPOSE_TILE: usize = 16;

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
    Jpeg,
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
    } else if header.starts_with(crate::jpeg::SIGNATURE) {
        Some(Format::Jpeg)
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
        Some(Format::Jpeg) => crate::jpeg::decode(input, options),
        None => Err(ImageError::Decode(
            "unsupported format for bounded decoding: only PNG, HEIC and JPEG are supported".into(),
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

pub(crate) fn oriented_output(
    rgb: Vec<u8>,
    source: Dimensions,
    target: Dimensions,
    orientation: Orientation,
) -> ImageResult<BoundedDecodedImage> {
    if rgb.len() as u64 != u64::from(target.width) * u64::from(target.height) * 3 {
        return Err(ImageError::Postprocess(
            "invalid bounded image buffer".into(),
        ));
    }
    let rgb = oriented(rgb, &target, orientation);
    let swaps_sides = matches!(
        orientation,
        Orientation::Rotate90
            | Orientation::Rotate270
            | Orientation::Rotate90FlipH
            | Orientation::Rotate270FlipH
    );
    let oriented_dimensions = |dimensions: Dimensions| {
        if swaps_sides {
            Dimensions {
                width: dimensions.height,
                height: dimensions.width,
            }
        } else {
            dimensions
        }
    };
    Ok(BoundedDecodedImage {
        image: DecodedImage {
            dimensions: oriented_dimensions(target),
            rgb,
        },
        original_dimensions: oriented_dimensions(source),
    })
}

fn oriented(mut rgb: Vec<u8>, dimensions: &Dimensions, orientation: Orientation) -> Vec<u8> {
    let (width, height) = (dimensions.width as usize, dimensions.height as usize);
    let pixels = rgb.as_chunks_mut::<3>().0;
    match orientation {
        Orientation::NoTransforms => {}
        Orientation::Rotate180 => pixels.reverse(),
        Orientation::FlipHorizontal => {
            for row in pixels.chunks_exact_mut(width) {
                row.reverse();
            }
        }
        Orientation::FlipVertical => {
            let (top, bottom) = pixels.split_at_mut(height / 2 * width);
            for (upper, lower) in top
                .chunks_exact_mut(width)
                .zip(bottom.rchunks_exact_mut(width))
            {
                upper.swap_with_slice(lower);
            }
        }
        Orientation::Rotate90 => return transposed(pixels, width, height, true, false),
        Orientation::Rotate270 => return transposed(pixels, width, height, false, true),
        Orientation::Rotate90FlipH => return transposed(pixels, width, height, false, false),
        Orientation::Rotate270FlipH => return transposed(pixels, width, height, true, true),
    }
    rgb
}

fn transposed(
    pixels: &[[u8; 3]],
    width: usize,
    height: usize,
    mirror_columns: bool,
    mirror_rows: bool,
) -> Vec<u8> {
    let mut output = vec![[0; 3]; pixels.len()];
    for tile_y in (0..height).step_by(TRANSPOSE_TILE) {
        let tile_rows = tile_y..(tile_y + TRANSPOSE_TILE).min(height);
        for tile_x in (0..width).step_by(TRANSPOSE_TILE) {
            for x in tile_x..(tile_x + TRANSPOSE_TILE).min(width) {
                let output_y = if mirror_rows { width - 1 - x } else { x };
                let output_row = &mut output[output_y * height..(output_y + 1) * height];
                for y in tile_rows.clone() {
                    let output_x = if mirror_columns { height - 1 - y } else { y };
                    output_row[output_x] = pixels[y * width + x];
                }
            }
        }
    }
    output.into_flattened()
}

pub(crate) fn too_large() -> ImageError {
    image::ImageError::Limits(image::error::LimitError::from_kind(
        image::error::LimitErrorKind::InsufficientMemory,
    ))
    .into()
}

#[cfg(test)]
pub(crate) mod tests {
    use std::path::{Path, PathBuf};

    use super::*;
    use crate::image_compression::{EncodedImageFormat, encode_rgb};

    pub(crate) fn options(max_side: u32) -> BoundedDecodeOptions {
        BoundedDecodeOptions {
            max_side,
            ..BoundedDecodeOptions::default()
        }
    }

    pub(crate) fn fixtures_dir() -> Option<PathBuf> {
        if let Some(path) = std::env::var_os("ENTE_TEST_FIXTURES_DIR") {
            return Some(PathBuf::from(path));
        }
        let manifest_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
        let repo_root = manifest_dir.parent()?.parent()?.parent()?;
        Some(repo_root.parent()?.join("test-fixtures"))
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
    fn rejects_unsupported_formats_from_bytes_and_paths() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("image.png");
        for bytes in [
            &b"GIF89a\x01\0\x01\0\0\0\0;"[..],
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
    fn orientations_match_the_image_crate() {
        for (width, height) in [(1, 1), (1, 7), (7, 1), (2, 3), (31, 33), (64, 32), (70, 45)] {
            let rgb = (0..width * height * 3)
                .map(|i| (i * 7 % 251) as u8)
                .collect::<Vec<_>>();
            let dimensions = Dimensions { width, height };
            for exif in 1..=8 {
                let orientation = Orientation::from_exif(exif).unwrap();
                let mut expected = image::DynamicImage::ImageRgb8(
                    image::RgbImage::from_raw(width, height, rgb.clone()).unwrap(),
                );
                expected.apply_orientation(orientation);
                let decoded = oriented_output(
                    rgb.clone(),
                    dimensions.clone(),
                    dimensions.clone(),
                    orientation,
                )
                .unwrap();
                let label = format!("{width}x{height} orientation {exif}");
                assert_eq!(
                    decoded.image.dimensions,
                    Dimensions {
                        width: expected.width(),
                        height: expected.height()
                    },
                    "{label}"
                );
                assert_eq!(
                    decoded.original_dimensions, decoded.image.dimensions,
                    "{label}"
                );
                assert_eq!(
                    decoded.image.rgb,
                    expected.into_rgb8().into_raw(),
                    "{label}"
                );
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
