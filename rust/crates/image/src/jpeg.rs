use std::{fs::File, io::Read};

use image::{DynamicImage, ImageBuffer, metadata::Orientation};
use zune_jpeg::{
    JpegDecoder, ScanlineReadStatus,
    errors::DecodeErrors,
    zune_core::{bytestream::ZCursor, colorspace::ColorSpace, options::DecoderOptions},
};

use crate::{
    BoundedDecodeOptions, BoundedDecodedImage, Dimensions, ImageError, ImageInput, ImageResult,
    bounded::{MAX_SOURCE_PIXELS, oriented_output, target_dimensions, too_large},
    color_management::IccConverter,
    resample::Downsampler,
};

pub(crate) const SIGNATURE: &[u8] = b"\xff\xd8\xff";
const START_OF_IMAGE: &[u8] = b"\xff\xd8";
const END_OF_IMAGE: &[u8] = b"\xff\xd9";
const MAX_STRIPE_ROWS: usize = 36;
const HEADER_PARSING_BYTES: u64 = 16 * 1024 * 1024;
const DECODER_BYTES: u64 = 1024 * 1024;
const DECODER_BYTES_PER_COLUMN: u64 = 1024;
const METADATA_COPIES: u64 = 16;

struct ScanHeader {
    components: u8,
    end: usize,
}

pub(crate) fn decode(
    input: ImageInput<'_>,
    options: BoundedDecodeOptions,
) -> ImageResult<BoundedDecodedImage> {
    match input {
        ImageInput::Bytes(bytes) => {
            let scan = first_scan(bytes)?;
            let end = scan_data_end(bytes, &scan)?;
            if bytes[end..].starts_with(END_OF_IMAGE) {
                return decode_bytes(&bytes[..end + END_OF_IMAGE.len()], &scan, 0, options);
            }
            let mut terminated = input_buffer(end as u64, options.max_memory_bytes)?;
            terminated.extend_from_slice(&bytes[..end]);
            terminated.extend_from_slice(END_OF_IMAGE);
            decode_bytes(&terminated, &scan, terminated.capacity() as u64, options)
        }
        ImageInput::Path(path) => {
            let read_error =
                |error| ImageError::Decode(format!("failed to read image file '{path}': {error}"));
            let file = File::open(path).map_err(read_error)?;
            let length = file.metadata().map_err(read_error)?.len();
            let mut bytes = input_buffer(length, options.max_memory_bytes)?;
            file.take(length)
                .read_to_end(&mut bytes)
                .map_err(read_error)?;
            let scan = first_scan(&bytes)?;
            bytes.truncate(scan_data_end(&bytes, &scan)?);
            bytes.extend_from_slice(END_OF_IMAGE);
            decode_bytes(&bytes, &scan, bytes.capacity() as u64, options)
        }
    }
}

fn input_buffer(input_bytes: u64, max_memory_bytes: u64) -> ImageResult<Vec<u8>> {
    let length = input_bytes.saturating_add(END_OF_IMAGE.len() as u64);
    if length.saturating_add(HEADER_PARSING_BYTES) > max_memory_bytes {
        return Err(too_large());
    }
    let mut buffer = Vec::new();
    buffer
        .try_reserve_exact(usize::try_from(length).map_err(|_| too_large())?)
        .map_err(|_| too_large())?;
    Ok(buffer)
}

fn first_scan(bytes: &[u8]) -> ImageResult<ScanHeader> {
    next_scan(bytes, START_OF_IMAGE.len()).ok_or_else(|| unsupported("malformed header segments"))
}

fn scan_data_end(bytes: &[u8], scan: &ScanHeader) -> ImageResult<usize> {
    let end = bytes
        .get(scan.end..)
        .and_then(|data| {
            data.windows(2)
                .position(|pair| pair[0] == 0xff && !matches!(pair[1], 0x00 | 0xd0..=0xd7 | 0xff))
        })
        .map_or(bytes.len(), |position| scan.end + position);
    if next_scan(bytes, end).is_some() {
        return Err(unsupported("more than one scan"));
    }
    Ok(end)
}

fn decode_bytes(
    bytes: &[u8],
    scan: &ScanHeader,
    owned_input_bytes: u64,
    options: BoundedDecodeOptions,
) -> ImageResult<BoundedDecodedImage> {
    let retained_bytes = owned_input_bytes
        .saturating_add(METADATA_COPIES.saturating_mul(scan.end as u64))
        .saturating_add(HEADER_PARSING_BYTES);
    if retained_bytes > options.max_memory_bytes {
        return Err(too_large());
    }
    let mut decoder = JpegDecoder::new_with_options(
        ZCursor::new(bytes),
        DecoderOptions::default()
            .set_strict_mode(false)
            .set_max_width(usize::from(u16::MAX))
            .set_max_height(usize::from(u16::MAX)),
    );
    decoder.decode_headers().map_err(jpeg_error)?;
    if decoder.inner_reader().position().ok() != Some(scan.end as u64) {
        return Err(unsupported("malformed header segments"));
    }
    let info = decoder
        .info()
        .ok_or_else(|| ImageError::Decode("JPEG headers were not decoded".into()))?;
    if !info.sof.is_sequential_dct() {
        return Err(unsupported(&format!("{:?}", info.sof)));
    }
    if scan.components != info.components {
        return Err(unsupported("components are in separate scans"));
    }
    let source = Dimensions {
        width: u32::from(info.width),
        height: u32::from(info.height),
    };
    if u64::from(source.width) * u64::from(source.height) > MAX_SOURCE_PIXELS {
        return Err(too_large());
    }
    let color = match decoder
        .input_colorspace()
        .ok_or_else(|| ImageError::Decode("JPEG headers were not decoded".into()))?
    {
        color @ (ColorSpace::RGB | ColorSpace::RGBA | ColorSpace::Luma | ColorSpace::LumaA) => {
            color
        }
        _ => ColorSpace::RGB,
    };
    decoder.set_options(decoder.options().jpeg_set_out_colorspace(color));
    let target = target_dimensions(&source, options.max_side);
    if required_bytes(retained_bytes, &source, &target) > options.max_memory_bytes {
        return Err(too_large());
    }
    let orientation = decoder
        .exif()
        .and_then(|exif| Orientation::from_exif_chunk(exif))
        .unwrap_or(Orientation::NoTransforms);
    let profile = decoder.icc_profile();
    let mut converter = IccConverter::new(profile.as_deref());
    let mut output = Downsampler::new(source.clone(), target.clone(), false)?;
    let row_bytes = source.width as usize * color.num_components();
    let mut rows_buffer = vec![0; row_bytes * MAX_STRIPE_ROWS];
    let mut session = decoder.scanline_output();
    let ended_early = || ImageError::Decode("JPEG ended before all rows were decoded".into());
    let mut y = 0;
    loop {
        match session
            .read_scanlines(&mut rows_buffer, row_bytes)
            .map_err(jpeg_error)?
        {
            ScanlineReadStatus::RowsProcessed { rows } => {
                let rgb = rows_rgb(
                    &rows_buffer[..rows * row_bytes],
                    source.width,
                    rows as u32,
                    color,
                    &mut converter,
                )?;
                for row in rgb.chunks_exact(source.width as usize * 3) {
                    output.push_row(row, 0, y, 1);
                    y += 1;
                }
            }
            ScanlineReadStatus::Complete => break,
            _ => return Err(ended_early()),
        }
    }
    if y != source.height {
        return Err(ended_early());
    }
    session.finish().map_err(jpeg_error)?;
    oriented_output(output.finish(), source, target, orientation)
}

fn required_bytes(retained_bytes: u64, source: &Dimensions, target: &Dimensions) -> u64 {
    let oriented_copy = u64::from(target.width) * u64::from(target.height) * 3;
    retained_bytes
        .saturating_add(Downsampler::bytes(source, target, false))
        .saturating_add(oriented_copy)
        .saturating_add(DECODER_BYTES + u64::from(source.width) * DECODER_BYTES_PER_COLUMN)
}

fn next_scan(bytes: &[u8], mut offset: usize) -> Option<ScanHeader> {
    loop {
        if *bytes.get(offset)? != 0xff {
            return None;
        }
        while *bytes.get(offset)? == 0xff {
            offset += 1;
        }
        let marker = bytes[offset];
        let length = usize::from(u16::from_be_bytes([
            *bytes.get(offset + 1)?,
            *bytes.get(offset + 2)?,
        ]));
        if length < 2 || matches!(marker, 0x00 | 0x01 | 0xd0..=0xd9) {
            return None;
        }
        let end = offset + 1 + length;
        if marker == 0xda {
            return Some(ScanHeader {
                components: *bytes.get(offset + 3)?,
                end,
            });
        }
        offset = end;
    }
}

fn rows_rgb(
    bytes: &[u8],
    width: u32,
    rows: u32,
    color: ColorSpace,
    converter: &mut IccConverter<'_>,
) -> ImageResult<Vec<u8>> {
    let invalid = || ImageError::Decode("invalid JPEG row layout".into());
    let data = bytes.to_vec();
    let image = match color {
        ColorSpace::Luma => {
            DynamicImage::ImageLuma8(ImageBuffer::from_raw(width, rows, data).ok_or_else(invalid)?)
        }
        ColorSpace::LumaA => {
            DynamicImage::ImageLumaA8(ImageBuffer::from_raw(width, rows, data).ok_or_else(invalid)?)
        }
        ColorSpace::RGB => {
            DynamicImage::ImageRgb8(ImageBuffer::from_raw(width, rows, data).ok_or_else(invalid)?)
        }
        ColorSpace::RGBA => {
            DynamicImage::ImageRgba8(ImageBuffer::from_raw(width, rows, data).ok_or_else(invalid)?)
        }
        _ => return Err(invalid()),
    };
    Ok(converter.apply(image).into_rgb8().into_raw())
}

fn unsupported(reason: &str) -> ImageError {
    ImageError::Decode(format!("unsupported JPEG for bounded decoding: {reason}"))
}

fn jpeg_error(error: DecodeErrors) -> ImageError {
    ImageError::Decode(error.to_string())
}

#[cfg(test)]
mod tests {
    use image::{ExtendedColorType, ImageEncoder, codecs::jpeg::JpegEncoder};
    use jpeg_encoder::{ColorType, Encoder, JpegColorType, SamplingFactor};

    use super::*;
    use crate::{
        bounded::tests::{fixtures_dir, options},
        color_management::tests::{
            localized_text, lookup_table, lookup_table_with_inputs, profile_with_tag,
        },
        decode::decode_image_from_bytes,
        decode_bounded,
        memory_budget::MemoryBudget,
        resample::tests::area_reference,
    };

    fn encode(
        pixels: &[u8],
        width: u32,
        height: u32,
        color: ExtendedColorType,
        icc_profile: Option<Vec<u8>>,
        exif: Option<Vec<u8>>,
    ) -> Vec<u8> {
        let mut bytes = Vec::new();
        let mut encoder = JpegEncoder::new_with_quality(&mut bytes, 90);
        if let Some(profile) = icc_profile {
            encoder.set_icc_profile(profile).unwrap();
        }
        if let Some(exif) = exif {
            encoder.set_exif_metadata(exif).unwrap();
        }
        encoder.write_image(pixels, width, height, color).unwrap();
        bytes
    }

    fn encode_layout(
        pixels: &[u8],
        width: u16,
        height: u16,
        color: ColorType,
        configure: impl FnOnce(&mut Encoder<&mut Vec<u8>>),
    ) -> Vec<u8> {
        let mut bytes = Vec::new();
        let mut encoder = Encoder::new(&mut bytes, 90);
        configure(&mut encoder);
        encoder.encode(pixels, width, height, color).unwrap();
        bytes
    }

    fn rgb(width: u32, height: u32) -> Vec<u8> {
        (0..width * height * 3)
            .map(|i| ((i * 37 + 11) % 256) as u8)
            .collect()
    }

    fn assert_matches_full_decoder(bytes: &[u8], max_side: u32, label: &str) {
        let full = decode_image_from_bytes(bytes).unwrap();
        let bounded = decode_bounded(ImageInput::Bytes(bytes), options(max_side)).unwrap();
        assert_eq!(bounded.original_dimensions, full.dimensions, "{label}");
        assert_eq!(
            bounded.image.dimensions,
            target_dimensions(&full.dimensions, max_side),
            "{label}"
        );
        if bounded.image.dimensions == full.dimensions {
            assert_eq!(bounded.image.rgb, full.rgb, "{label}");
            return;
        }
        let expected = area_reference(
            &full.rgb,
            full.dimensions.width,
            full.dimensions.height,
            &bounded.image.dimensions,
        );
        assert_eq!(bounded.image.rgb.len(), expected.len(), "{label}");
        for (actual, expected) in bounded.image.rgb.iter().zip(expected) {
            assert!(
                actual.abs_diff(expected) <= 1,
                "{label}, max {max_side}: {actual} != {expected}"
            );
        }
    }

    fn marker(bytes: &[u8], marker: u8) -> usize {
        bytes
            .windows(2)
            .position(|window| window == [0xff, marker])
            .unwrap()
    }

    fn with_separate_scans(bytes: &[u8]) -> Vec<u8> {
        let sos = marker(bytes, 0xda);
        let components = usize::from(bytes[sos + 4]);
        let mut separate = bytes[..sos + 2].to_vec();
        separate.extend_from_slice(&[0, 8, 1]);
        separate.extend_from_slice(&bytes[sos + 5..sos + 7]);
        separate.extend_from_slice(&bytes[sos + 5 + 2 * components..]);
        separate
    }

    fn with_dimensions(bytes: &[u8], width: u16, height: u16) -> Vec<u8> {
        let mut patched = bytes.to_vec();
        let sof = patched
            .windows(2)
            .rposition(|window| window == [0xff, 0xc0])
            .unwrap();
        patched[sof + 5..sof + 7].copy_from_slice(&height.to_be_bytes());
        patched[sof + 7..sof + 9].copy_from_slice(&width.to_be_bytes());
        patched
    }

    #[test]
    fn streamed_rows_match_the_full_decoder_for_rgb_and_grayscale() {
        for (width, height) in [(1, 19), (19, 1), (2, 3), (13, 17), (31, 23), (40, 70)] {
            let pixels = rgb(width, height);
            let gray = pixels.iter().step_by(3).copied().collect::<Vec<_>>();
            for (color, data) in [
                (ExtendedColorType::Rgb8, &pixels),
                (ExtendedColorType::L8, &gray),
            ] {
                let bytes = encode(data, width, height, color, None, None);
                for max_side in [1, 2, 7, 13, 40, 6000] {
                    assert_matches_full_decoder(
                        &bytes,
                        max_side,
                        &format!("{width}x{height} {color:?}"),
                    );
                }
            }
        }
    }

    #[test]
    fn sides_longer_than_16384_match_the_full_decoder() {
        for (width, height) in [(16_400, 8), (8, 16_400)] {
            let bytes = encode(
                &rgb(width, height),
                width,
                height,
                ExtendedColorType::Rgb8,
                None,
                None,
            );
            assert_matches_full_decoder(&bytes, 6000, &format!("{width}x{height}"));
        }
    }

    #[test]
    fn subsampled_cmyk_and_restart_layouts_match_the_full_decoder() {
        let samplings = [
            SamplingFactor::F_1_1,
            SamplingFactor::F_2_1,
            SamplingFactor::F_1_2,
            SamplingFactor::F_2_2,
        ];
        for (width, height) in [(1, 19), (19, 1), (13, 17), (37, 53), (70, 41)] {
            let pixels = rgb(u32::from(width), u32::from(height));
            let cmyk = (0..usize::from(width) * usize::from(height) * 4)
                .map(|i| ((i * 53 + 7) % 256) as u8)
                .collect::<Vec<_>>();
            for sampling in samplings {
                let bytes = encode_layout(&pixels, width, height, ColorType::Rgb, |encoder| {
                    encoder.set_sampling_factor(sampling)
                });
                for max_side in [7, 6000] {
                    assert_matches_full_decoder(
                        &bytes,
                        max_side,
                        &format!("{width}x{height} {sampling:?}"),
                    );
                }
            }
            for (label, bytes) in [
                (
                    "CMYK",
                    encode_layout(&cmyk, width, height, ColorType::Cmyk, |_| {}),
                ),
                (
                    "YCCK",
                    encode_layout(&cmyk, width, height, ColorType::CmykAsYcck, |encoder| {
                        encoder.set_sampling_factor(SamplingFactor::F_2_2)
                    }),
                ),
                (
                    "restart interval",
                    encode_layout(&pixels, width, height, ColorType::Rgb, |encoder| {
                        encoder.set_sampling_factor(SamplingFactor::F_2_2);
                        encoder.set_restart_interval(1);
                    }),
                ),
            ] {
                for max_side in [7, 6000] {
                    assert_matches_full_decoder(
                        &bytes,
                        max_side,
                        &format!("{width}x{height} {label}"),
                    );
                }
            }
        }
    }

    #[test]
    fn data_after_the_end_marker_is_ignored() {
        let bytes = encode_layout(&rgb(37, 53), 37, 53, ColorType::Rgb, |encoder| {
            encoder.set_sampling_factor(SamplingFactor::F_2_2)
        });
        let mut trailed = bytes.clone();
        trailed.extend_from_slice(&encode(
            &rgb(5, 5),
            5,
            5,
            ExtendedColorType::Rgb8,
            None,
            None,
        ));
        trailed.extend_from_slice(b"\0\0\0\x18ftypmp42 trailing video");
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("image.jpg");
        std::fs::write(&path, &trailed).unwrap();
        let expected = decode_bounded(ImageInput::Bytes(&bytes), options(6000)).unwrap();
        for input in [
            ImageInput::Bytes(&trailed),
            ImageInput::Path(path.to_str().unwrap()),
        ] {
            assert_eq!(
                decode_bounded(input, options(6000)).unwrap().image.rgb,
                expected.image.rgb
            );
        }
        assert_matches_full_decoder(&trailed, 6000, "trailing data");
    }

    #[test]
    fn icc_profiles_match_the_full_decoder() {
        let pixels = rgb(21, 13);
        let gray = pixels.iter().step_by(3).copied().collect::<Vec<_>>();
        for (color, data, profile) in [
            (
                ExtendedColorType::Rgb8,
                &pixels,
                moxcms::ColorProfile::new_display_p3(),
            ),
            (
                ExtendedColorType::L8,
                &gray,
                moxcms::ColorProfile::new_gray_with_gamma(1.8),
            ),
        ] {
            let bytes = encode(data, 21, 13, color, Some(profile.encode().unwrap()), None);
            assert_ne!(
                decode_image_from_bytes(&bytes).unwrap().rgb,
                decode_image_from_bytes(&encode(data, 21, 13, color, None, None))
                    .unwrap()
                    .rgb
            );
            for max_side in [5, 6000] {
                assert_matches_full_decoder(&bytes, max_side, &format!("{color:?}"));
            }
        }
    }

    #[test]
    fn profiles_that_expand_when_parsed_are_skipped_within_the_budget() {
        let pixels = rgb(64, 64);
        let unprofiled = decode_image_from_bytes(&encode(
            &pixels,
            64,
            64,
            ExtendedColorType::Rgb8,
            None,
            None,
        ))
        .unwrap();
        let lookup_tables = [
            *b"A2B0", *b"A2B1", *b"A2B2", *b"B2A0", *b"B2A1", *b"B2A2", *b"gamt",
        ];
        for profile in [
            profile_with_tag(&[*b"desc"], &localized_text(4096, 65_536)),
            profile_with_tag(&lookup_tables, &lookup_table(96, 4_000)),
            profile_with_tag(&lookup_tables, &lookup_table_with_inputs(96, 4_000)),
        ] {
            let bytes = encode(
                &pixels,
                64,
                64,
                ExtendedColorType::Rgb8,
                Some(profile),
                None,
            );
            let budget = MemoryBudget::new(4 * 1024 * 1024);
            let bounded =
                budget.enter(|| decode_bounded(ImageInput::Bytes(&bytes), options(6000)).unwrap());
            assert!(!budget.is_exceeded());
            assert_eq!(bounded.image.rgb, unprofiled.rgb);
            let budget = MemoryBudget::new(4 * 1024 * 1024);
            let full = budget.enter(|| decode_image_from_bytes(&bytes).unwrap());
            assert!(!budget.is_exceeded());
            assert_eq!(full.rgb, unprofiled.rgb);
        }
    }

    #[test]
    fn applies_all_exif_orientations_after_downsampling() {
        let pixels = rgb(16, 8);
        for orientation in 1..=8 {
            let mut exif = b"II\x2a\0\x08\0\0\0\x01\0\x12\x01\x03\0\x01\0\0\0".to_vec();
            exif.extend_from_slice(&[orientation, 0, 0, 0, 0, 0, 0, 0]);
            let bytes = encode(&pixels, 16, 8, ExtendedColorType::Rgb8, None, Some(exif));
            for max_side in [4, 6000] {
                assert_matches_full_decoder(
                    &bytes,
                    max_side,
                    &format!("orientation {orientation}"),
                );
            }
        }
    }

    #[test]
    fn path_reads_match_bytes() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("image.png");
        let bytes = encode(&rgb(33, 18), 33, 18, ExtendedColorType::Rgb8, None, None);
        std::fs::write(&path, &bytes).unwrap();
        let from_path =
            decode_bounded(ImageInput::Path(path.to_str().unwrap()), options(10)).unwrap();
        let from_bytes = decode_bounded(ImageInput::Bytes(&bytes), options(10)).unwrap();
        assert_eq!(from_path.image.rgb, from_bytes.image.rgb);
        assert_eq!(from_path.image.dimensions, from_bytes.image.dimensions);
    }

    #[test]
    fn progressive_and_separate_scan_jpegs_are_rejected() {
        let pixels = rgb(24, 24);
        let progressive = encode_layout(&pixels, 24, 24, ColorType::Rgb, |encoder| {
            encoder.set_progressive(true)
        });
        let separate = with_separate_scans(&encode(
            &pixels,
            24,
            24,
            ExtendedColorType::Rgb8,
            None,
            None,
        ));
        let optimized = encode_layout(&pixels, 24, 24, ColorType::Rgb, |encoder| {
            encoder.set_optimized_huffman_tables(true)
        });
        let quadruple = encode_layout(&pixels, 24, 24, ColorType::Rgb, |encoder| {
            encoder.set_sampling_factor(SamplingFactor::F_4_1)
        });
        for bytes in [progressive, separate, optimized, quadruple] {
            assert!(matches!(
                decode_bounded(ImageInput::Bytes(&bytes), options(8)),
                Err(ImageError::Decode(message)) if message.contains("unsupported JPEG")
            ));
        }
    }

    #[test]
    fn progressive_jpegs_with_one_scan_are_rejected_before_buffering() {
        let mut bytes = with_dimensions(&plain_64(), 4000, 4000);
        let sof = marker(&bytes, 0xc0);
        bytes[sof + 1] = 0xc2;
        let sos = marker(&bytes, 0xda);
        let components = usize::from(bytes[sos + 4]);
        bytes[sos + 6 + 2 * components] = 0;
        let budget = MemoryBudget::new(4 * 1024 * 1024);
        let result = budget.enter(|| decode_bounded(ImageInput::Bytes(&bytes), options(8)));
        assert!(
            matches!(&result, Err(ImageError::Decode(message)) if message.contains("Progressive DCT")),
            "{result:?}"
        );
        assert!(!budget.is_exceeded());
    }

    #[test]
    fn separate_scan_jpegs_behind_unusual_header_bytes_are_rejected_before_buffering() {
        let large = with_dimensions(
            &with_separate_scans(&encode(
                &rgb(24, 24),
                24,
                24,
                ExtendedColorType::Rgb8,
                None,
                None,
            )),
            4000,
            4000,
        );
        let mut after_start = large[..2].to_vec();
        after_start.extend_from_slice(b"\xff\x01\x00\x07\xff\xda\x00\x0c\x03");
        after_start.extend_from_slice(&large[2..]);
        let sos = marker(&large, 0xda);
        let mut before_scan = large[..sos].to_vec();
        before_scan.extend_from_slice(b"\xff\x00\xda\x00\x08\x03");
        before_scan.extend_from_slice(&large[sos..]);
        for bytes in [large, after_start, before_scan] {
            let budget = MemoryBudget::new(4 * 1024 * 1024);
            let result = budget.enter(|| decode_bounded(ImageInput::Bytes(&bytes), options(6000)));
            assert!(
                matches!(&result, Err(ImageError::Decode(message)) if message.contains("unsupported JPEG")),
                "{result:?}"
            );
            assert!(!budget.is_exceeded());
        }
    }

    #[test]
    fn next_scan_accepts_only_contiguous_header_segments() {
        let bytes = encode(&rgb(8, 8), 8, 8, ExtendedColorType::Rgb8, None, None);
        let sos = marker(&bytes, 0xda);
        let scan = first_scan(&bytes).unwrap();
        assert_eq!(scan.components, 3);
        assert_eq!(scan.end, sos + 2 + 12);
        let gray = encode(&[90; 64], 8, 8, ExtendedColorType::L8, None, None);
        assert_eq!(first_scan(&gray).unwrap().components, 1);
        let filled =
            first_scan(b"\xff\xd8\xff\xe0\0\x04ab\xff\xff\xda\0\x0a\x02\x01\0\x02\x11\0\x3f\0")
                .unwrap();
        assert_eq!((filled.components, filled.end), (2, 21));
        for header in [
            &b"\xff\xd8\xff\xe0\0\x04ab\x12\xff\xda\0\x08\x01"[..],
            b"\xff\xd8\xff\0\xda\0\x08\x01",
            b"\xff\xd8\xff\x01\0\x07\xff\xda\0\x08\x01",
            b"\xff\xd8\xff\xd0\0\x04ab\xff\xda\0\x08\x01",
            b"\xff\xd8\xff\xd9\xff\xda\0\x08\x01",
            b"\xff\xd8\xff\xe0\0\x01\xff\xda\0\x08\x01",
            b"\xff\xd8\xff\xe0\0\x10\xff\xda",
            b"\xff\xd8\xff\xda\0\x08",
        ] {
            assert!(
                next_scan(header, START_OF_IMAGE.len()).is_none(),
                "{header:x?}"
            );
        }
    }

    #[test]
    fn missing_end_markers_decode_like_the_full_decoder() {
        let bytes = encode(&rgb(40, 70), 40, 70, ExtendedColorType::Rgb8, None, None);
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("image.jpg");
        for length in [bytes.len() - 2, bytes.len() - 1] {
            let truncated = &bytes[..length];
            std::fs::write(&path, truncated).unwrap();
            let full = decode_image_from_bytes(truncated).unwrap();
            for input in [
                ImageInput::Bytes(truncated),
                ImageInput::Path(path.to_str().unwrap()),
            ] {
                assert_eq!(
                    decode_bounded(input, options(6000)).unwrap().image.rgb,
                    full.rgb,
                    "length {length}"
                );
            }
        }
    }

    #[test]
    fn truncated_scans_decode_like_the_full_decoder_given_an_end_marker() {
        let bytes = encode(&rgb(40, 70), 40, 70, ExtendedColorType::Rgb8, None, None);
        for length in [marker(&bytes, 0xda) + 20, bytes.len() / 2, bytes.len() - 20] {
            let truncated = &bytes[..length];
            let terminated = [truncated, END_OF_IMAGE].concat();
            assert_eq!(
                decode_bounded(ImageInput::Bytes(truncated), options(6000))
                    .unwrap()
                    .image
                    .rgb,
                decode_image_from_bytes(&terminated).unwrap().rgb,
                "length {length}"
            );
        }
    }

    #[test]
    fn truncated_headers_and_invalid_jpegs_fail() {
        let bytes = encode(&rgb(40, 70), 40, 70, ExtendedColorType::Rgb8, None, None);
        for length in [3, 20, marker(&bytes, 0xda)] {
            assert!(
                matches!(
                    decode_bounded(ImageInput::Bytes(&bytes[..length]), options(8)),
                    Err(ImageError::Decode(_))
                ),
                "length {length}"
            );
        }
        assert!(matches!(
            decode_bounded(ImageInput::Bytes(b"\xff\xd8\xff\xe0garbage"), options(8)),
            Err(ImageError::Decode(_))
        ));
    }

    #[test]
    fn oversized_sources_and_budgets_are_too_large() {
        let bytes = encode(&rgb(16, 16), 16, 16, ExtendedColorType::Rgb8, None, None);
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("image.jpg");
        let oversized = with_dimensions(&bytes, 22_361, 22_361);
        std::fs::write(&path, &oversized).unwrap();
        for input in [
            ImageInput::Bytes(&oversized),
            ImageInput::Path(path.to_str().unwrap()),
        ] {
            assert!(matches!(
                decode_bounded(input, options(6000)),
                Err(ImageError::TooLarge(_))
            ));
        }
        let large = with_dimensions(&bytes, 22_360, 22_360);
        let small_budget = BoundedDecodeOptions {
            max_memory_bytes: 64 * 1024 * 1024,
            ..BoundedDecodeOptions::default()
        };
        assert!(matches!(
            decode_bounded(ImageInput::Bytes(&large), small_budget),
            Err(ImageError::TooLarge(_))
        ));
        std::fs::write(&path, &bytes).unwrap();
        assert!(matches!(
            decode_bounded(
                ImageInput::Path(path.to_str().unwrap()),
                BoundedDecodeOptions {
                    max_memory_bytes: bytes.len() as u64 - 1,
                    ..BoundedDecodeOptions::default()
                }
            ),
            Err(ImageError::TooLarge(_))
        ));
    }

    #[test]
    fn files_close_to_the_budget_are_rejected_before_reading() {
        let max_memory_bytes = 1024 * 1024;
        let mut bytes = encode(&rgb(16, 16), 16, 16, ExtendedColorType::Rgb8, None, None);
        bytes.resize(max_memory_bytes - END_OF_IMAGE.len(), 0);
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("padded.jpg");
        std::fs::write(&path, &bytes).unwrap();
        let budget = MemoryBudget::new(max_memory_bytes);
        let result = budget.enter(|| {
            decode_bounded(
                ImageInput::Path(path.to_str().unwrap()),
                BoundedDecodeOptions {
                    max_memory_bytes: max_memory_bytes as u64,
                    ..BoundedDecodeOptions::default()
                },
            )
        });
        assert!(matches!(result, Err(ImageError::TooLarge(_))));
        assert!(!budget.is_exceeded());
    }

    #[test]
    fn memory_estimate_covers_the_decode() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("image.jpg");
        let profile = moxcms::ColorProfile::new_display_p3().encode().unwrap();
        let wide = rgb(4000, 40);
        let mut files = [(1, 1, 1), (640, 480, 6000), (1200, 900, 300)]
            .map(|(width, height, max_side)| {
                let bytes = encode(
                    &rgb(width, height),
                    width,
                    height,
                    ExtendedColorType::Rgb8,
                    Some(profile.clone()),
                    None,
                );
                (bytes, max_side)
            })
            .to_vec();
        for sampling in [
            SamplingFactor::F_1_1,
            SamplingFactor::F_2_1,
            SamplingFactor::F_1_2,
            SamplingFactor::F_2_2,
        ] {
            files.push((
                encode_layout(&wide, 4000, 40, ColorType::Rgb, |encoder| {
                    encoder.set_sampling_factor(sampling)
                }),
                300,
            ));
        }
        for (bytes, max_side) in files {
            std::fs::write(&path, &bytes).unwrap();
            let mut decoder = JpegDecoder::new(ZCursor::new(&bytes));
            decoder.decode_headers().unwrap();
            let (width, height) = decoder.dimensions().unwrap();
            let source = Dimensions {
                width: width as u32,
                height: height as u32,
            };
            let target = target_dimensions(&source, max_side);
            let retained = bytes.len() as u64
                + END_OF_IMAGE.len() as u64
                + METADATA_COPIES * first_scan(&bytes).unwrap().end as u64;
            let budget = MemoryBudget::new(required_bytes(retained, &source, &target) as usize);
            let decoded = budget
                .enter(|| {
                    decode_bounded(ImageInput::Path(path.to_str().unwrap()), options(max_side))
                })
                .unwrap();
            assert_eq!(decoded.image.dimensions, target);
            assert!(!budget.is_exceeded(), "{source:?}");
        }
    }

    #[test]
    fn large_metadata_counts_towards_the_budget() {
        let profile = (0..2 * 1024 * 1024)
            .map(|i| (i * 31 % 251) as u8)
            .collect::<Vec<_>>();
        let bytes = encode(
            &[10, 20, 30],
            1,
            1,
            ExtendedColorType::Rgb8,
            Some(profile),
            None,
        );
        assert!(bytes.ends_with(END_OF_IMAGE));
        let source = Dimensions {
            width: 1,
            height: 1,
        };
        let retained = METADATA_COPIES * first_scan(&bytes).unwrap().end as u64;
        let estimate = required_bytes(retained, &source, &source);
        let budget = MemoryBudget::new(estimate as usize);
        assert!(
            budget
                .enter(|| decode_bounded(
                    ImageInput::Bytes(&bytes),
                    BoundedDecodeOptions::default()
                ))
                .is_ok()
        );
        assert!(!budget.is_exceeded());
        assert!(matches!(
            decode_bounded(
                ImageInput::Bytes(&bytes),
                BoundedDecodeOptions {
                    max_memory_bytes: 2 * 1024 * 1024,
                    ..BoundedDecodeOptions::default()
                }
            ),
            Err(ImageError::TooLarge(_))
        ));
    }

    fn plain_64() -> Vec<u8> {
        encode_layout(&rgb(64, 64), 64, 64, ColorType::Rgb, |encoder| {
            encoder.set_sampling_factor(SamplingFactor::F_2_2)
        })
    }

    #[test]
    fn scan_data_ends_at_the_first_marker_after_the_scan() {
        let scan = ScanHeader {
            components: 3,
            end: 0,
        };
        let data = b"\x12\xff\x00\x34\xff\xd3\x56\xff\xff\xd9\xff\xe1";
        assert_eq!(scan_data_end(data, &scan).unwrap(), 8);
        assert_eq!(scan_data_end(b"\x12\x34\xff", &scan).unwrap(), 3);
        assert_eq!(scan_data_end(b"\x12\x34", &scan).unwrap(), 2);
        assert_eq!(
            scan_data_end(b"\x12\xff\xe1\0\x04ab\xff\xd9", &scan).unwrap(),
            1
        );
        assert_eq!(
            scan_data_end(b"\x12\xff\xe1\0\x04ab\x99\xff\xda\0\x08\x01", &scan).unwrap(),
            1
        );
        for later_scan in [
            &b"\x12\xff\xda\0\x08\x01\x01\0\0\x3f\0"[..],
            b"\x12\xff\xe1\0\x04ab\xff\xff\xda\0\x08\x01\x01\0\0\x3f\0",
        ] {
            assert!(matches!(
                scan_data_end(later_scan, &scan),
                Err(ImageError::Decode(message)) if message.contains("more than one scan")
            ));
        }
        let beyond = ScanHeader {
            components: 3,
            end: 9,
        };
        assert_eq!(scan_data_end(b"\xff\xd8", &beyond).unwrap(), 2);
    }

    #[test]
    fn metadata_after_the_scan_is_not_kept_by_the_decoder() {
        let plain = plain_64();
        let mut bytes = plain[..plain.len() - END_OF_IMAGE.len()].to_vec();
        for sequence in 1..=64 {
            let mut chunk = b"ICC_PROFILE\0".to_vec();
            chunk.extend_from_slice(&[sequence, 64]);
            chunk.extend(std::iter::repeat_n(sequence, 65_000));
            bytes.extend_from_slice(&[0xff, 0xe2]);
            bytes.extend_from_slice(&u16::try_from(chunk.len() + 2).unwrap().to_be_bytes());
            bytes.extend_from_slice(&chunk);
        }
        bytes.extend_from_slice(END_OF_IMAGE);
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("image.jpg");
        std::fs::write(&path, &bytes).unwrap();
        let expected = decode_bounded(ImageInput::Bytes(&plain), options(6000)).unwrap();
        let source = Dimensions {
            width: 64,
            height: 64,
        };
        let header = METADATA_COPIES * first_scan(&bytes).unwrap().end as u64;
        for (file, owned) in [
            (None, plain.len() as u64),
            (
                Some(path.to_str().unwrap()),
                (bytes.len() + END_OF_IMAGE.len()) as u64,
            ),
        ] {
            let input = || file.map_or(ImageInput::Bytes(&bytes), ImageInput::Path);
            let estimate = required_bytes(owned + header, &source, &source);
            let admitted = estimate + HEADER_PARSING_BYTES;
            let limit = |max_memory_bytes| BoundedDecodeOptions {
                max_memory_bytes,
                ..BoundedDecodeOptions::default()
            };
            let budget = MemoryBudget::new(estimate as usize);
            let decoded = budget
                .enter(|| decode_bounded(input(), limit(admitted)))
                .unwrap();
            assert!(!budget.is_exceeded());
            assert_eq!(decoded.image.rgb, expected.image.rgb);
            assert!(matches!(
                decode_bounded(input(), limit(admitted - 1)),
                Err(ImageError::TooLarge(_))
            ));
        }
    }

    #[test]
    fn later_scans_are_rejected() {
        let plain = plain_64();
        let sos = marker(&plain, 0xda);
        let scan = &plain[sos..plain.len() - END_OF_IMAGE.len()];
        let mut repeated = plain[..plain.len() - END_OF_IMAGE.len()].to_vec();
        repeated.extend_from_slice(scan);
        repeated.extend_from_slice(END_OF_IMAGE);
        let mut behind_segment = plain[..plain.len() - END_OF_IMAGE.len()].to_vec();
        behind_segment.extend_from_slice(b"\xff\xfe\0\x05abc");
        behind_segment.extend_from_slice(scan);
        behind_segment.extend_from_slice(END_OF_IMAGE);
        for bytes in [repeated, behind_segment] {
            assert!(matches!(
                decode_bounded(ImageInput::Bytes(&bytes), options(6000)),
                Err(ImageError::Decode(message)) if message.contains("more than one scan")
            ));
        }
    }

    #[test]
    fn huffman_table_expansion_fits_the_header_allowance() {
        let plain = plain_64();
        let mut segment = Vec::new();
        for _ in 0..65_533 / 17 {
            segment.push(0x10);
            segment.extend_from_slice(&[0; 16]);
        }
        let mut bytes = plain[..START_OF_IMAGE.len()].to_vec();
        bytes.extend_from_slice(&[0xff, 0xc4]);
        bytes.extend_from_slice(&u16::try_from(segment.len() + 2).unwrap().to_be_bytes());
        bytes.extend_from_slice(&segment);
        bytes.extend_from_slice(&plain[START_OF_IMAGE.len()..]);
        let allowance =
            METADATA_COPIES * first_scan(&bytes).unwrap().end as u64 + HEADER_PARSING_BYTES;
        let budget = MemoryBudget::new(allowance as usize);
        let decoded = budget
            .enter(|| decode_bounded(ImageInput::Bytes(&bytes), BoundedDecodeOptions::default()))
            .unwrap();
        assert!(!budget.is_exceeded());
        assert_eq!(
            decoded.image.rgb,
            decode_bounded(ImageInput::Bytes(&plain), options(6000))
                .unwrap()
                .image
                .rgb
        );
        let budget = MemoryBudget::new(1024 * 1024);
        let result = budget.enter(|| {
            decode_bounded(
                ImageInput::Bytes(&bytes),
                BoundedDecodeOptions {
                    max_memory_bytes: allowance - 1,
                    ..BoundedDecodeOptions::default()
                },
            )
        });
        assert!(matches!(result, Err(ImageError::TooLarge(_))));
        assert!(!budget.is_exceeded());
    }

    fn eight_bit_lookup_table_profile(grid: usize, marker_value: u8) -> Vec<u8> {
        use moxcms::{
            ColorProfile, LutMultidimensionalType, LutStore, LutWarehouse, Matrix3d, ToneReprCurve,
            Vector3d,
        };
        let identity = || ToneReprCurve::Lut(vec![0, u16::MAX]);
        let mut table = Vec::with_capacity(grid * grid * grid * 3);
        for red in 0..grid {
            for green in 0..grid {
                for blue in 0..grid {
                    for value in [red, green, blue] {
                        table.push((value * 255 / (grid - 1)) as u8);
                    }
                }
            }
        }
        table[1] = marker_value;
        let mut grid_points = [0; 16];
        grid_points[..3].fill(grid as u8);
        let mut profile = ColorProfile::new_display_p3();
        profile.red_trc = None;
        profile.green_trc = None;
        profile.blue_trc = None;
        profile.lut_a_to_b_perceptual =
            Some(LutWarehouse::Multidimensional(LutMultidimensionalType {
                num_input_channels: 3,
                num_output_channels: 3,
                grid_points,
                clut: Some(LutStore::Store8(table)),
                a_curves: vec![identity(), identity(), identity()],
                b_curves: vec![identity(), identity(), identity()],
                m_curves: Vec::new(),
                matrix: Matrix3d::IDENTITY,
                bias: Vector3d::default(),
            }));
        profile.encode().unwrap()
    }

    fn tag(profile: &[u8], signature: [u8; 4]) -> Vec<u8> {
        let count = u32::from_be_bytes(profile[128..132].try_into().unwrap()) as usize;
        let entry = profile[132..132 + 12 * count]
            .as_chunks::<12>()
            .0
            .iter()
            .find(|entry| entry[..4] == signature)
            .unwrap();
        let offset = u32::from_be_bytes(entry[4..8].try_into().unwrap()) as usize;
        let size = u32::from_be_bytes(entry[8..12].try_into().unwrap()) as usize;
        profile[offset..offset + size].to_vec()
    }

    #[test]
    fn uncached_lookup_table_profiles_fit_the_estimate() {
        let lookup_tables = [
            *b"A2B0", *b"A2B1", *b"A2B2", *b"B2A0", *b"B2A1", *b"B2A2", *b"gamt",
        ];
        let shared = profile_with_tag(
            &lookup_tables,
            &tag(&eight_bit_lookup_table_profile(85, 0x6b), *b"A2B0"),
        );
        let pixels = rgb(64, 64);
        let unprofiled = decode_bounded(
            ImageInput::Bytes(&encode_layout(&pixels, 64, 64, ColorType::Rgb, |encoder| {
                encoder.set_sampling_factor(SamplingFactor::F_2_2);
            })),
            options(6000),
        )
        .unwrap();
        for profile in [eight_bit_lookup_table_profile(60, 0x5a), shared] {
            let bytes = encode_layout(&pixels, 64, 64, ColorType::Rgb, |encoder| {
                encoder.set_sampling_factor(SamplingFactor::F_2_2);
                encoder.add_icc_profile(&profile).unwrap();
            });
            let source = Dimensions {
                width: 64,
                height: 64,
            };
            let retained = METADATA_COPIES * first_scan(&bytes).unwrap().end as u64;
            let estimate = required_bytes(retained, &source, &source);
            let budget = MemoryBudget::new(estimate as usize);
            let decoded = budget
                .enter(|| {
                    decode_bounded(
                        ImageInput::Bytes(&bytes),
                        BoundedDecodeOptions {
                            max_memory_bytes: estimate + HEADER_PARSING_BYTES,
                            ..BoundedDecodeOptions::default()
                        },
                    )
                })
                .unwrap();
            assert!(!budget.is_exceeded());
            assert_ne!(decoded.image.rgb, unprofiled.image.rgb);
        }
    }

    #[test]
    fn rotated_images_with_expanding_profiles_fit_the_admitted_budget() {
        let lookup_tables = [
            *b"A2B0", *b"A2B1", *b"A2B2", *b"B2A0", *b"B2A1", *b"B2A2", *b"gamt",
        ];
        let mut exif = b"II\x2a\0\x08\0\0\0\x01\0\x12\x01\x03\0\x01\0\0\0".to_vec();
        exif.extend_from_slice(&[6, 0, 0, 0, 0, 0, 0, 0]);
        let image = |profile| {
            with_dimensions(
                &encode(
                    &rgb(16, 16),
                    16,
                    16,
                    ExtendedColorType::Rgb8,
                    profile,
                    Some(exif.clone()),
                ),
                500,
                5200,
            )
        };
        let unprofiled = decode_bounded(ImageInput::Bytes(&image(None)), options(6000)).unwrap();
        let bytes = image(Some(profile_with_tag(
            &lookup_tables,
            &lookup_table(4, 40_000),
        )));
        let source = Dimensions {
            width: 500,
            height: 5200,
        };
        let retained = METADATA_COPIES * first_scan(&bytes).unwrap().end as u64;
        let estimate = required_bytes(retained, &source, &source);
        let decode = |max_memory_bytes: u64| {
            let budget = MemoryBudget::new(max_memory_bytes as usize);
            let result = budget.enter(|| {
                decode_bounded(
                    ImageInput::Bytes(&bytes),
                    BoundedDecodeOptions {
                        max_memory_bytes,
                        ..BoundedDecodeOptions::default()
                    },
                )
            });
            assert!(!budget.is_exceeded(), "{max_memory_bytes}");
            result
        };
        assert!(matches!(decode(estimate), Err(ImageError::TooLarge(_))));
        let decoded = decode(estimate + HEADER_PARSING_BYTES).unwrap();
        assert_eq!(
            decoded.image.dimensions,
            Dimensions {
                width: 5200,
                height: 500
            }
        );
        assert_ne!(decoded.image.rgb, unprofiled.image.rgb);
    }

    #[test]
    fn jpeg_fixtures_match_the_full_decoder_when_present() {
        let Some(directory) = fixtures_dir().filter(|path| path.exists()) else {
            eprintln!("Skipping: external JPEG fixtures not present");
            return;
        };
        for name in [
            "ml/indexing/v1/files/people.jpeg",
            "ml/indexing/v1/files/man.jpeg",
            "ml/indexing/v1/files/singapore.jpg",
            "ml/indexing/v1/files/1343_rotate_90_cw.jpg",
            "ml/indexing/v1/files/IMG_pano.jpg",
            "media/motion-photos/v1/files/motionphoto.jpg",
            "media/motion-photos/v1/files/pixel_8.jpg",
        ] {
            let bytes = std::fs::read(directory.join(name)).unwrap();
            for max_side in [6000, 97] {
                assert_matches_full_decoder(&bytes, max_side, name);
            }
        }
        let progressive =
            std::fs::read(directory.join("ml/indexing/v1/files/starwatchers.jpg")).unwrap();
        assert!(matches!(
            decode_bounded(ImageInput::Bytes(&progressive), options(6000)),
            Err(ImageError::Decode(_))
        ));
    }

    struct Pattern {
        width: u16,
        height: u16,
    }

    impl jpeg_encoder::ImageBuffer for Pattern {
        fn get_jpeg_color_type(&self) -> JpegColorType {
            JpegColorType::Ycbcr
        }

        fn width(&self) -> u16 {
            self.width
        }

        fn height(&self) -> u16 {
            self.height
        }

        fn fill_buffers(&self, y: u16, buffers: &mut [Vec<u8>; 4]) {
            for x in 0..self.width {
                buffers[0].push((x % 251) as u8);
                buffers[1].push((y % 241) as u8);
                buffers[2].push(((x / 7 + y / 5) % 239) as u8);
            }
        }
    }

    #[test]
    #[ignore = "200 MP streaming memory regression; run in release mode"]
    fn streams_200_megapixels() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("large.jpg");
        let mut bytes = Vec::new();
        let mut encoder = Encoder::new(&mut bytes, 90);
        encoder.set_sampling_factor(SamplingFactor::F_2_2);
        encoder
            .encode_image(Pattern {
                width: 16_320,
                height: 12_240,
            })
            .unwrap();
        std::fs::write(&path, &bytes).unwrap();
        let limit = bytes.len() + 100 * 1024 * 1024;
        drop(bytes);
        let budget = MemoryBudget::new(limit);
        let output = budget
            .enter(|| decode_bounded(ImageInput::Path(path.to_str().unwrap()), options(6000)))
            .unwrap();
        assert!(!budget.is_exceeded());
        assert_eq!(
            output.image.dimensions,
            Dimensions {
                width: 6000,
                height: 4500
            }
        );
    }
}
