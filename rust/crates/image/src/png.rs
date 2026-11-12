use std::io::{BufRead, Seek};

use image::{DynamicImage, ImageBuffer, metadata::Orientation};

use crate::{
    BoundedDecodeOptions, BoundedDecodedImage, DecodedImage, Dimensions, ImageError, ImageResult,
    bounded::{target_dimensions, too_large},
    color_management::IccConverter,
    resample::Downsampler,
};

pub(crate) const SIGNATURE: &[u8] = b"\x89PNG\r\n\x1a\n";
const DECODER_BYTES: usize = 32 * 1024 * 1024;
const MAX_ROW_BYTES: u64 = 4 * 1024 * 1024;
const MAX_SOURCE_HEIGHT: u32 = 512 * 1024;
const MAX_SOURCE_PIXELS: u64 = 256_000_000;
pub(crate) const ADAM7: [(u32, u32, u32, u32); 7] = [
    (0, 0, 8, 8),
    (4, 0, 8, 8),
    (0, 4, 4, 8),
    (2, 0, 4, 4),
    (0, 2, 2, 4),
    (1, 0, 2, 2),
    (0, 1, 1, 2),
];

pub(crate) fn decode<R: BufRead + Seek>(
    input: R,
    options: BoundedDecodeOptions,
) -> ImageResult<BoundedDecodedImage> {
    let mut decoder = ::png::Decoder::new_with_limits(
        input,
        ::png::Limits {
            bytes: DECODER_BYTES,
        },
    );
    decoder.set_ignore_text_chunk(true);
    decoder.set_transformations(::png::Transformations::EXPAND);
    let header = decoder.read_header_info().map_err(png_error)?;
    let source = Dimensions {
        width: header.width,
        height: header.height,
    };
    let interlaced = header.interlaced;
    let row_bytes = u64::from(source.width) * 8;
    if row_bytes > MAX_ROW_BYTES
        || source.height > MAX_SOURCE_HEIGHT
        || u64::from(source.width) * u64::from(source.height) > MAX_SOURCE_PIXELS
    {
        return Err(too_large());
    }
    let target = target_dimensions(&source, options.max_side);
    let oriented_copy = u64::from(target.width) * u64::from(target.height) * 3;
    let required = Downsampler::bytes(&source, &target, interlaced)
        .saturating_add(oriented_copy)
        .saturating_add(row_bytes * 4 + DECODER_BYTES as u64);
    if required > options.max_memory_bytes {
        return Err(too_large());
    }
    let mut output = Downsampler::new(source.clone(), target.clone(), interlaced)?;
    let mut reader = decoder.read_info().map_err(png_error)?;
    let profile = reader.info().icc_profile.clone();
    let mut converter = IccConverter::new(profile.as_deref());
    let orientation = reader
        .info()
        .exif_metadata
        .as_deref()
        .and_then(Orientation::from_exif_chunk)
        .unwrap_or(Orientation::NoTransforms);
    let (color, depth) = reader.output_color_type();
    let plain = [(0, 0, 1, 1)];
    let passes = if interlaced { &ADAM7[..] } else { &plain[..] };
    for &(left, top, step_x, step_y) in passes {
        if left >= source.width || top >= source.height {
            continue;
        }
        let width = (source.width - left).div_ceil(step_x);
        for y in (top..source.height).step_by(step_y as usize) {
            let row = reader
                .next_interlaced_row()
                .map_err(png_error)?
                .ok_or_else(|| {
                    ImageError::Decode("PNG ended before all rows were decoded".into())
                })?;
            let rgb = row_rgb(row.data(), width, color, depth, &mut converter)?;
            output.push_row(&rgb, left, y, step_x);
        }
        output.finish_pass();
    }
    if reader.next_interlaced_row().map_err(png_error)?.is_some() {
        return Err(ImageError::Decode("PNG contains unexpected rows".into()));
    }
    reader.finish().map_err(png_error)?;
    let rgb = output.finish();
    let buffer = image::RgbImage::from_raw(target.width, target.height, rgb)
        .ok_or_else(|| ImageError::Postprocess("invalid bounded PNG buffer".into()))?;
    let mut image = DynamicImage::ImageRgb8(buffer);
    image.apply_orientation(orientation);
    let image = image.into_rgb8();
    let original_dimensions = match orientation {
        Orientation::Rotate90
        | Orientation::Rotate270
        | Orientation::Rotate90FlipH
        | Orientation::Rotate270FlipH => Dimensions {
            width: source.height,
            height: source.width,
        },
        _ => source,
    };
    Ok(BoundedDecodedImage {
        image: DecodedImage {
            dimensions: Dimensions {
                width: image.width(),
                height: image.height(),
            },
            rgb: image.into_raw(),
        },
        original_dimensions,
    })
}

fn row_rgb(
    bytes: &[u8],
    width: u32,
    color: ::png::ColorType,
    depth: ::png::BitDepth,
    converter: &mut IccConverter<'_>,
) -> ImageResult<Vec<u8>> {
    let invalid = || ImageError::Decode("invalid PNG row layout".into());
    let image = match depth {
        ::png::BitDepth::Eight => {
            let data = bytes.to_vec();
            match color {
                ::png::ColorType::Grayscale => DynamicImage::ImageLuma8(
                    ImageBuffer::from_raw(width, 1, data).ok_or_else(invalid)?,
                ),
                ::png::ColorType::GrayscaleAlpha => DynamicImage::ImageLumaA8(
                    ImageBuffer::from_raw(width, 1, data).ok_or_else(invalid)?,
                ),
                ::png::ColorType::Rgb => DynamicImage::ImageRgb8(
                    ImageBuffer::from_raw(width, 1, data).ok_or_else(invalid)?,
                ),
                ::png::ColorType::Rgba => DynamicImage::ImageRgba8(
                    ImageBuffer::from_raw(width, 1, data).ok_or_else(invalid)?,
                ),
                _ => return Err(invalid()),
            }
        }
        ::png::BitDepth::Sixteen => {
            let data = bytes
                .as_chunks::<2>()
                .0
                .iter()
                .map(|sample| u16::from_be_bytes([sample[0], sample[1]]))
                .collect::<Vec<_>>();
            match color {
                ::png::ColorType::Grayscale => DynamicImage::ImageLuma16(
                    ImageBuffer::from_raw(width, 1, data).ok_or_else(invalid)?,
                ),
                ::png::ColorType::GrayscaleAlpha => DynamicImage::ImageLumaA16(
                    ImageBuffer::from_raw(width, 1, data).ok_or_else(invalid)?,
                ),
                ::png::ColorType::Rgb => DynamicImage::ImageRgb16(
                    ImageBuffer::from_raw(width, 1, data).ok_or_else(invalid)?,
                ),
                ::png::ColorType::Rgba => DynamicImage::ImageRgba16(
                    ImageBuffer::from_raw(width, 1, data).ok_or_else(invalid)?,
                ),
                _ => return Err(invalid()),
            }
        }
        _ => return Err(invalid()),
    };
    Ok(converter.apply(image).into_rgb8().into_raw())
}

fn png_error(error: ::png::DecodingError) -> ImageError {
    if matches!(error, ::png::DecodingError::LimitsExceeded) {
        too_large()
    } else {
        ImageError::Decode(error.to_string())
    }
}

#[cfg(test)]
mod tests {
    use std::{
        borrow::Cow,
        fs::File,
        io::Write,
        time::{Duration, Instant},
    };

    use super::*;
    use crate::{
        ImageInput,
        bounded::tests::options,
        color_management::tests::{localized_text, profile_with_text},
        decode::decode_image_from_bytes,
        decode_bounded,
        memory_budget::MemoryBudget,
        resample::tests::area_reference,
    };

    fn fixture(info: ::png::Info<'_>, pixels: &[u8]) -> Vec<u8> {
        let mut bytes = Vec::new();
        let interlaced = info.interlaced;
        let width = info.width;
        let height = info.height;
        let pixel_bytes = info.color_type.samples()
            * if info.bit_depth == ::png::BitDepth::Sixteen {
                2
            } else {
                1
            };
        let mut writer = ::png::Encoder::with_info(&mut bytes, info)
            .unwrap()
            .write_header()
            .unwrap();
        if interlaced {
            let mut filtered = Vec::new();
            for (left, top, step_x, step_y) in ADAM7 {
                if left >= width || top >= height {
                    continue;
                }
                for y in (top..height).step_by(step_y as usize) {
                    filtered.push(0);
                    for x in (left..width).step_by(step_x as usize) {
                        let offset = (y * width + x) as usize * pixel_bytes;
                        filtered.extend_from_slice(&pixels[offset..offset + pixel_bytes]);
                    }
                }
            }
            let mut compressed = vec![0x78, 0x01];
            let mut blocks = filtered.chunks(u16::MAX as usize).peekable();
            while let Some(block) = blocks.next() {
                let length = u16::try_from(block.len()).unwrap();
                compressed.push(u8::from(blocks.peek().is_none()));
                compressed.extend_from_slice(&length.to_le_bytes());
                compressed.extend_from_slice(&(!length).to_le_bytes());
                compressed.extend_from_slice(block);
            }
            let (mut a, mut b) = (1u32, 0u32);
            for byte in filtered {
                a = (a + u32::from(byte)) % 65521;
                b = (b + a) % 65521;
            }
            compressed.extend_from_slice(&((b << 16) | a).to_be_bytes());
            writer.write_chunk(::png::chunk::IDAT, &compressed).unwrap();
        } else {
            writer.write_image_data(pixels).unwrap();
        }
        writer.finish().unwrap();
        bytes
    }

    fn header_only(width: u32, height: u32, interlaced: bool) -> Vec<u8> {
        let mut bytes = Vec::new();
        ::png::Encoder::with_info(&mut bytes, rgb_info(width, height, interlaced))
            .unwrap()
            .write_header()
            .unwrap()
            .finish()
            .unwrap();
        bytes
    }

    fn rgb_info(width: u32, height: u32, interlaced: bool) -> ::png::Info<'static> {
        let mut info = ::png::Info::with_size(width, height);
        info.color_type = ::png::ColorType::Rgb;
        info.bit_depth = ::png::BitDepth::Eight;
        info.interlaced = interlaced;
        info
    }

    #[test]
    fn streamed_rows_match_area_reference_including_adam7_and_thin_images() {
        for (width, height) in [(1, 19), (19, 1), (2, 3), (13, 17), (31, 23)] {
            let pixels = (0..width * height * 3)
                .map(|i| ((i * 37 + 11) % 256) as u8)
                .collect::<Vec<_>>();
            for interlaced in [false, true] {
                let bytes = fixture(rgb_info(width, height, interlaced), &pixels);
                assert_eq!(decode_image_from_bytes(&bytes).unwrap().rgb, pixels);
                for max_side in [1, 2, 7, 13, 40] {
                    let decoded =
                        decode_bounded(ImageInput::Bytes(&bytes), options(max_side)).unwrap();
                    let reference =
                        area_reference(&pixels, width, height, &decoded.image.dimensions);
                    assert_eq!(decoded.original_dimensions, Dimensions { width, height });
                    assert!(
                        decoded
                            .image
                            .dimensions
                            .width
                            .max(decoded.image.dimensions.height)
                            <= max_side
                    );
                    for (actual, expected) in decoded.image.rgb.iter().zip(reference) {
                        assert!(
                            actual.abs_diff(expected) <= 1,
                            "{width}x{height}, max {max_side}, interlaced {interlaced}: {actual} != {expected}"
                        );
                    }
                }
            }
        }
    }

    #[test]
    fn apng_returns_the_default_image() {
        let mut bytes = Vec::new();
        let mut encoder = ::png::Encoder::new(&mut bytes, 4, 2);
        encoder.set_color(::png::ColorType::Rgb);
        encoder.set_animated(2, 0).unwrap();
        let mut writer = encoder.write_header().unwrap();
        writer.write_image_data(&[80; 4 * 2 * 3]).unwrap();
        writer.write_image_data(&[120; 4 * 2 * 3]).unwrap();
        writer.finish().unwrap();
        let output = decode_bounded(ImageInput::Bytes(&bytes), options(2)).unwrap();
        assert_eq!(output.image.rgb, [80; 2 * 3]);
    }

    #[test]
    fn color_types_depths_and_icc_match_existing_decoder_before_downsampling() {
        for color in [
            ::png::ColorType::Grayscale,
            ::png::ColorType::GrayscaleAlpha,
            ::png::ColorType::Rgb,
            ::png::ColorType::Rgba,
        ] {
            for depth in [::png::BitDepth::Eight, ::png::BitDepth::Sixteen] {
                for interlaced in [false, true] {
                    let mut info = rgb_info(9, 7, interlaced);
                    info.color_type = color;
                    info.bit_depth = depth;
                    let profile = if matches!(
                        color,
                        ::png::ColorType::Grayscale | ::png::ColorType::GrayscaleAlpha
                    ) {
                        moxcms::ColorProfile::new_gray_with_gamma(1.8)
                    } else {
                        moxcms::ColorProfile::new_display_p3()
                    };
                    info.icc_profile = Some(Cow::Owned(profile.encode().unwrap()));
                    let count = 9
                        * 7
                        * color.samples()
                        * if depth == ::png::BitDepth::Sixteen {
                            2
                        } else {
                            1
                        };
                    let pixels = (0..count)
                        .map(|i| ((i * 71) % 256) as u8)
                        .collect::<Vec<_>>();
                    let bytes = fixture(info, &pixels);
                    let full = decode_image_from_bytes(&bytes).unwrap();
                    for max_side in [4, 6000] {
                        let bounded =
                            decode_bounded(ImageInput::Bytes(&bytes), options(max_side)).unwrap();
                        if max_side == 6000 {
                            assert_eq!(bounded.image.rgb, full.rgb);
                        } else {
                            let expected =
                                area_reference(&full.rgb, 9, 7, &bounded.image.dimensions);
                            assert_eq!(bounded.image.rgb.len(), expected.len());
                            for (actual, expected) in bounded.image.rgb.iter().zip(expected) {
                                assert!(
                                    actual.abs_diff(expected) <= 1,
                                    "{color:?} {depth:?} {interlaced}: {actual} != {expected}"
                                );
                            }
                        }
                    }
                }
            }
        }
    }

    #[test]
    fn streamed_rows_preserve_pixels_for_ignored_icc_profiles() {
        let mut pq = moxcms::ColorProfile::new_display_p3_pq();
        pq.cicp = None;
        let mut hlg = moxcms::ColorProfile::new_bt2020_hlg();
        hlg.cicp = None;
        let pixels = (0..9 * 7 * 3).map(|i| (i * 71) as u8).collect::<Vec<_>>();
        for profile in [
            None,
            Some(b"invalid ICC profile".to_vec()),
            Some(moxcms::ColorProfile::new_srgb().encode().unwrap()),
            Some(
                moxcms::ColorProfile::new_gray_with_gamma(1.8)
                    .encode()
                    .unwrap(),
            ),
            Some(pq.encode().unwrap()),
            Some(hlg.encode().unwrap()),
        ] {
            for interlaced in [false, true] {
                let mut info = rgb_info(9, 7, interlaced);
                info.icc_profile = profile.clone().map(Cow::Owned);
                let bytes = fixture(info, &pixels);
                for max_side in [4, 6000] {
                    let bounded =
                        decode_bounded(ImageInput::Bytes(&bytes), options(max_side)).unwrap();
                    let expected = area_reference(&pixels, 9, 7, &bounded.image.dimensions);
                    assert_eq!(bounded.image.rgb.len(), expected.len());
                    for (actual, expected) in bounded.image.rgb.iter().zip(expected) {
                        assert!(actual.abs_diff(expected) <= 1);
                    }
                }
            }
        }
    }

    #[test]
    fn profiles_with_excessive_localized_text_are_skipped_within_the_budget() {
        let pixels = (0..64 * 64 * 3).map(|i| (i * 71) as u8).collect::<Vec<_>>();
        let mut info = rgb_info(64, 64, false);
        info.icc_profile = Some(Cow::Owned(profile_with_text(
            &[*b"desc"],
            &localized_text(4096, 65_536),
        )));
        let bytes = fixture(info, &pixels);
        let budget = MemoryBudget::new(4 * 1024 * 1024);
        let bounded =
            budget.enter(|| decode_bounded(ImageInput::Bytes(&bytes), options(6000)).unwrap());
        assert!(!budget.is_exceeded());
        assert_eq!(bounded.image.rgb, pixels);
        let budget = MemoryBudget::new(4 * 1024 * 1024);
        let full = budget.enter(|| decode_image_from_bytes(&bytes).unwrap());
        assert!(!budget.is_exceeded());
        assert_eq!(full.rgb, pixels);
    }

    #[test]
    fn expands_packed_palette_transparency_and_grayscale() {
        for color in [::png::ColorType::Indexed, ::png::ColorType::Grayscale] {
            let mut info = rgb_info(8, 1, false);
            info.color_type = color;
            info.bit_depth = ::png::BitDepth::One;
            if color == ::png::ColorType::Indexed {
                info.palette = Some(Cow::Owned(vec![200, 20, 10, 10, 40, 220]));
                info.trns = Some(Cow::Owned(vec![0, 255]));
            }
            let bytes = fixture(info, &[0b10101010]);
            let full = decode_image_from_bytes(&bytes).unwrap();
            let bounded = decode_bounded(ImageInput::Bytes(&bytes), options(4)).unwrap();
            assert_eq!(
                bounded.image.rgb,
                area_reference(&full.rgb, 8, 1, &bounded.image.dimensions)
            );
        }
    }

    #[test]
    fn applies_all_exif_orientations_after_downsampling() {
        let pixels = (0..8 * 4 * 3).map(|i| (i * 7) as u8).collect::<Vec<_>>();
        for orientation in 1..=8 {
            let mut info = rgb_info(8, 4, true);
            let mut exif = b"II\x2a\0\x08\0\0\0\x01\0\x12\x01\x03\0\x01\0\0\0".to_vec();
            exif.extend_from_slice(&[orientation, 0, 0, 0, 0, 0, 0, 0]);
            info.exif_metadata = Some(Cow::Owned(exif));
            let bytes = fixture(info, &pixels);
            let full = decode_image_from_bytes(&bytes).unwrap();
            let bounded = decode_bounded(ImageInput::Bytes(&bytes), options(4)).unwrap();
            assert_eq!(bounded.original_dimensions, full.dimensions);
            let expected = area_reference(
                &full.rgb,
                full.dimensions.width,
                full.dimensions.height,
                &bounded.image.dimensions,
            );
            assert_eq!(bounded.image.rgb, expected);
        }
    }

    #[test]
    fn path_sniffs_content_and_matches_bytes() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("image.jpg");
        let bytes = fixture(rgb_info(11, 5, true), &[70; 11 * 5 * 3]);
        std::fs::write(&path, &bytes).unwrap();
        let from_path =
            decode_bounded(ImageInput::Path(path.to_str().unwrap()), options(6)).unwrap();
        let from_bytes = decode_bounded(ImageInput::Bytes(&bytes), options(6)).unwrap();
        assert_eq!(from_path.image.rgb, from_bytes.image.rgb);
        assert_eq!(from_path.image.dimensions, from_bytes.image.dimensions);
    }

    #[test]
    fn invalid_and_truncated_pngs_fail_without_fallback() {
        let bytes = fixture(rgb_info(8, 4, false), &[80; 8 * 4 * 3]);
        for length in [8, 20, bytes.len() / 2, bytes.len() - 1] {
            assert!(
                decode_bounded(ImageInput::Bytes(&bytes[..length]), options(4)).is_err(),
                "length {length}"
            );
        }
        let mut corrupt = bytes.clone();
        let idat = corrupt
            .windows(4)
            .position(|window| window == b"IDAT")
            .unwrap();
        corrupt[idat + 6] ^= 0x55;
        assert!(decode_bounded(ImageInput::Bytes(&corrupt), options(4)).is_err());
        assert!(decode_bounded(ImageInput::Bytes(&bytes), options(0)).is_err());
    }

    #[test]
    fn oversized_source_rows_and_output_buffers_are_rejected() {
        let mut bytes = Vec::new();
        let info = rgb_info(MAX_ROW_BYTES as u32 / 8 + 1, 1, false);
        ::png::Encoder::with_info(&mut bytes, info)
            .unwrap()
            .write_header()
            .unwrap()
            .finish()
            .unwrap();
        assert!(matches!(
            decode_bounded(ImageInput::Bytes(&bytes), options(6000)),
            Err(ImageError::TooLarge(_))
        ));
        assert!(matches!(
            decode_bounded(
                ImageInput::Bytes(&header_only(8000, 8000, true)),
                BoundedDecodeOptions::default()
            ),
            Err(ImageError::TooLarge(_))
        ));
        let plain = header_only(8000, 8000, false);
        assert!(matches!(
            decode_bounded(
                ImageInput::Bytes(&plain),
                BoundedDecodeOptions {
                    max_memory_bytes: 64 * 1024 * 1024,
                    ..BoundedDecodeOptions::default()
                }
            ),
            Err(ImageError::TooLarge(_))
        ));
        assert!(matches!(
            decode_bounded(ImageInput::Bytes(&plain), BoundedDecodeOptions::default()),
            Err(ImageError::Decode(_))
        ));
    }

    #[test]
    fn oversized_source_dimensions_are_rejected_before_image_data() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("oversized.png");
        for (width, height) in [
            (1, 524_289),
            (1, u32::MAX),
            (16_000, 16_001),
            (65_536, 65_536),
        ] {
            for interlaced in [false, true] {
                let mut bytes = Vec::new();
                ::png::Encoder::with_info(&mut bytes, rgb_info(width, height, interlaced))
                    .unwrap()
                    .write_header()
                    .unwrap()
                    .finish()
                    .unwrap();
                std::fs::write(&path, &bytes).unwrap();
                for input in [
                    ImageInput::Bytes(&bytes),
                    ImageInput::Path(path.to_str().unwrap()),
                ] {
                    let result = decode_bounded(input, options(1));
                    assert!(
                        matches!(result, Err(ImageError::TooLarge(_))),
                        "{width}x{height}, interlaced {interlaced}: {result:?}"
                    );
                }
            }
        }
    }

    #[test]
    fn source_dimension_limits_allow_boundary_headers() {
        for (width, height) in [(1, 524_288), (524_288, 1), (16_000, 16_000)] {
            for interlaced in [false, true] {
                let mut bytes = Vec::new();
                ::png::Encoder::with_info(&mut bytes, rgb_info(width, height, interlaced))
                    .unwrap()
                    .write_header()
                    .unwrap()
                    .finish()
                    .unwrap();
                let result = decode_bounded(ImageInput::Bytes(&bytes), options(1));
                assert!(
                    matches!(result, Err(ImageError::Decode(_))),
                    "{width}x{height}, interlaced {interlaced}: {result:?}"
                );
            }
        }
    }

    #[test]
    #[ignore = "ICC streaming performance regression; run in release mode"]
    fn profiled_png_decode_avoids_per_row_setup_cost() {
        let pixels = (0..256 * 1024 * 6)
            .map(|index| ((index * 71) % 256) as u8)
            .collect::<Vec<_>>();
        for interlaced in [false, true] {
            let mut info = rgb_info(256, 1024, interlaced);
            info.bit_depth = ::png::BitDepth::Sixteen;
            info.icc_profile = Some(Cow::Owned(
                moxcms::ColorProfile::new_display_p3().encode().unwrap(),
            ));
            let bytes = fixture(info, &pixels);
            let start = Instant::now();
            let full = decode_image_from_bytes(&bytes).unwrap();
            let full_time = start.elapsed();
            for max_side in [1024, 128] {
                let start = Instant::now();
                let bounded = decode_bounded(ImageInput::Bytes(&bytes), options(max_side)).unwrap();
                let bounded_time = start.elapsed();
                if max_side == 1024 {
                    assert_eq!(bounded.image.rgb, full.rgb);
                } else {
                    let expected = area_reference(&full.rgb, 256, 1024, &bounded.image.dimensions);
                    assert_eq!(bounded.image.rgb.len(), expected.len());
                    for (actual, expected) in bounded.image.rgb.iter().zip(expected) {
                        assert!(actual.abs_diff(expected) <= 1);
                    }
                }
                println!(
                    "interlaced {interlaced}, max_side {max_side}: bounded {bounded_time:?}, full {full_time:?}"
                );
                assert!(
                    bounded_time <= (full_time * 20).max(Duration::from_millis(100)),
                    "bounded decode took {bounded_time:?}, full decode took {full_time:?}"
                );
            }
        }
    }

    #[test]
    #[ignore = "200 MP streaming memory regression; run in release mode"]
    fn streams_200_megapixels() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("large.png");
        let mut encoder = ::png::Encoder::new(File::create(&path).unwrap(), 20_000, 10_000);
        encoder.set_color(::png::ColorType::Rgb);
        encoder.set_depth(::png::BitDepth::Eight);
        let mut writer = encoder.write_header().unwrap();
        let mut stream = writer.stream_writer().unwrap();
        let row = vec![128u8; 20_000 * 3];
        for _ in 0..10_000 {
            stream.write_all(&row).unwrap();
        }
        stream.finish().unwrap();
        writer.finish().unwrap();
        let output =
            decode_bounded(ImageInput::Path(path.to_str().unwrap()), options(6000)).unwrap();
        assert_eq!(
            output.image.dimensions,
            Dimensions {
                width: 6000,
                height: 3000
            }
        );
        assert!(output.image.rgb.iter().all(|&value| value == 128));
    }
}
