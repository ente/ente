use std::io::Cursor;

use image::{DynamicImage, ImageDecoder, ImageFormat, ImageReader, Limits};

pub(crate) const MAX_BYTES: usize = 1024 * 1024;

pub(crate) fn png(data: &[u8]) -> Option<Vec<u8>> {
    let format = image::guess_format(data).ok()?;
    if !matches!(
        format,
        ImageFormat::Png
            | ImageFormat::Jpeg
            | ImageFormat::Gif
            | ImageFormat::WebP
            | ImageFormat::Ico
    ) {
        return None;
    }
    if format == ImageFormat::Ico {
        validate_ico(data)?;
    }
    let mut limits = Limits::default();
    limits.max_image_width = Some(1024);
    limits.max_image_height = Some(1024);
    limits.max_alloc = Some(16 * 1024 * 1024);
    let mut reader = ImageReader::with_format(Cursor::new(data), format);
    reader.limits(limits.clone());
    let mut decoder = reader.into_decoder().ok()?;
    limits.reserve(decoder.total_bytes()).ok()?;
    decoder.set_limits(limits).ok()?;
    let orientation = decoder.orientation().ok()?;
    let mut image = DynamicImage::from_decoder(decoder).ok()?;
    image.apply_orientation(orientation);
    let mut output = Cursor::new(Vec::new());
    image.write_to(&mut output, ImageFormat::Png).ok()?;
    let output = output.into_inner();
    (output.len() <= MAX_BYTES).then_some(output)
}

fn validate_ico(data: &[u8]) -> Option<()> {
    let count = data.get(4..6)?;
    let count = usize::from(u16::from_le_bytes([count[0], count[1]]));
    let directory = data.get(6..6 + count * 16)?;
    let mut budget = MAX_BYTES;
    for entry in directory.as_chunks::<16>().0 {
        let length = u32::from_le_bytes([entry[8], entry[9], entry[10], entry[11]]) as usize;
        if length < 8 {
            return None;
        }
        let offset = u32::from_le_bytes([entry[12], entry[13], entry[14], entry[15]]) as usize;
        let payload = data.get(offset..offset.checked_add(length)?)?;
        if payload.starts_with(b"\x89PNG\r\n\x1a\n") {
            validate_png(payload, &mut budget)?;
        }
    }
    Some(())
}

fn validate_png(data: &[u8], budget: &mut usize) -> Option<()> {
    let mut data = data.get(8..)?;
    loop {
        let header = data.get(..8)?;
        *budget = budget.checked_sub(12)?;
        let length = u32::from_be_bytes([header[0], header[1], header[2], header[3]]) as usize;
        data = data.get(length.checked_add(12)?..)?;
        if &header[4..8] == b"iCCP" {
            return None;
        }
        if &header[4..8] == b"IEND" {
            return (length == 0).then_some(());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::ImageEncoder;

    fn ico(entries: &[(u8, Vec<u8>)]) -> Result<Vec<u8>, Box<dyn std::error::Error>> {
        let mut output = vec![0, 0, 1, 0];
        output.extend_from_slice(&u16::try_from(entries.len())?.to_le_bytes());
        let mut offset = 6 + entries.len() * 16;
        for (size, bytes) in entries {
            output.extend_from_slice(&[*size, *size, 0, 0, 1, 0, 32, 0]);
            output.extend_from_slice(&u32::try_from(bytes.len())?.to_le_bytes());
            output.extend_from_slice(&u32::try_from(offset)?.to_le_bytes());
            offset += bytes.len();
        }
        for (_, bytes) in entries {
            output.extend_from_slice(bytes);
        }
        Ok(output)
    }

    fn png() -> Result<Vec<u8>, image::ImageError> {
        let image = DynamicImage::new_rgba8(2, 2);
        let mut bytes = Cursor::new(Vec::new());
        image.write_to(&mut bytes, ImageFormat::Png)?;
        Ok(bytes.into_inner())
    }

    #[test]
    fn rejects_truncated_images_html_and_svg() -> Result<(), image::ImageError> {
        let data = png()?;
        assert!(super::png(&data).is_some());
        for data in [
            &data[..20],
            b"<html>Not found</html>".as_slice(),
            b"<svg xmlns='http://www.w3.org/2000/svg'><path d='M0 0'/></svg>",
            b"",
        ] {
            assert!(super::png(data).is_none());
        }
        Ok(())
    }

    #[test]
    fn normalizes_supported_rasters_without_resizing() -> Result<(), Box<dyn std::error::Error>> {
        let pixels = image::RgbaImage::from_fn(128, 128, |x, y| {
            if (x + y) % 2 == 0 {
                image::Rgba([20, 80, 200, 255])
            } else {
                image::Rgba([0, 0, 0, 0])
            }
        });
        let image = DynamicImage::ImageRgba8(pixels);
        for encoding in [
            ImageFormat::Png,
            ImageFormat::Jpeg,
            ImageFormat::Gif,
            ImageFormat::WebP,
            ImageFormat::Ico,
        ] {
            let mut bytes = Cursor::new(Vec::new());
            if encoding == ImageFormat::Jpeg {
                DynamicImage::ImageRgb8(image.to_rgb8()).write_to(&mut bytes, encoding)?;
            } else {
                image.write_to(&mut bytes, encoding)?;
            }
            let output = super::png(bytes.get_ref()).ok_or("normalization failed")?;
            assert_eq!(image::guess_format(&output)?, ImageFormat::Png);
            let decoded = image::load_from_memory(&output)?;
            assert_eq!((decoded.width(), decoded.height()), (128, 128));
            if encoding != ImageFormat::Jpeg {
                assert_eq!(decoded.to_rgba8(), image.to_rgba8());
            }
        }
        Ok(())
    }

    #[test]
    fn emits_only_the_first_animation_frame() -> Result<(), Box<dyn std::error::Error>> {
        let first = image::RgbaImage::from_pixel(8, 8, image::Rgba([255, 0, 0, 255]));
        let second = image::RgbaImage::from_pixel(8, 8, image::Rgba([0, 255, 0, 255]));
        let mut input = Vec::new();
        image::codecs::gif::GifEncoder::new(&mut input)
            .encode_frames([image::Frame::new(first.clone()), image::Frame::new(second)])?;
        let output = super::png(&input).ok_or("animated image rejected")?;
        assert_eq!(image::guess_format(&output)?, ImageFormat::Png);
        assert_eq!(image::load_from_memory(&output)?.to_rgba8(), first);
        Ok(())
    }

    #[test]
    fn selects_a_larger_ico_entry_and_preserves_transparency()
    -> Result<(), Box<dyn std::error::Error>> {
        let small = DynamicImage::ImageRgba8(image::RgbaImage::from_pixel(
            16,
            16,
            image::Rgba([0, 255, 0, 255]),
        ));
        let large = DynamicImage::ImageRgba8(image::RgbaImage::from_pixel(
            128,
            128,
            image::Rgba([255, 0, 0, 80]),
        ));
        let mut entries = Vec::new();
        for image in [&small, &large] {
            let mut bytes = Cursor::new(Vec::new());
            image.write_to(&mut bytes, ImageFormat::Png)?;
            entries.push((u8::try_from(image.width())?, bytes.into_inner()));
        }
        let input = ico(&entries)?;
        let output = super::png(&input).ok_or("ICO rejected")?;
        assert_eq!(
            image::load_from_memory(&output)?.to_rgba8(),
            large.to_rgba8()
        );
        Ok(())
    }

    #[test]
    fn accepts_bitmap_backed_ico() -> Result<(), Box<dyn std::error::Error>> {
        let mut bitmap = Vec::new();
        for value in [40u32, 2, 4, 0x0020_0001, 0, 16, 0, 0, 0, 0] {
            bitmap.extend_from_slice(&value.to_le_bytes());
        }
        for _ in 0..4 {
            bitmap.extend_from_slice(&[255, 0, 0, 255]);
        }
        bitmap.extend_from_slice(&[0; 8]);
        let output = super::png(&ico(&[(2, bitmap)])?).ok_or("bitmap icon rejected")?;
        let image = image::load_from_memory(&output)?.to_rgba8();
        assert_eq!(
            image,
            image::RgbaImage::from_pixel(2, 2, image::Rgba([0, 0, 255, 255]))
        );
        Ok(())
    }

    #[test]
    fn rejects_profile_tagged_ico_before_decoding() -> Result<(), Box<dyn std::error::Error>> {
        let mut bytes = Vec::new();
        let mut encoder = image::codecs::png::PngEncoder::new(&mut bytes);
        encoder.set_icc_profile(vec![0; 128])?;
        encoder.write_image(&[0, 0, 255, 255], 1, 1, image::ExtendedColorType::Rgba8)?;
        assert!(super::png(&bytes).is_some());
        let icon = ico(&[(1, bytes)])?;
        assert!(validate_ico(&icon).is_none());
        assert!(super::png(&icon).is_none());
        Ok(())
    }

    #[test]
    fn rejects_incomplete_ico_directory_and_png_chunk_framing()
    -> Result<(), Box<dyn std::error::Error>> {
        assert!(validate_ico(&[0, 0, 1, 0, 1, 0]).is_none());
        let mut icon = ico(&[(2, png()?)])?;
        for length in 0..8u32 {
            let mut short = icon.clone();
            short[14..18].copy_from_slice(&length.to_le_bytes());
            assert!(validate_ico(&short).is_none());
        }
        icon[18..22].copy_from_slice(&u32::MAX.to_le_bytes());
        assert!(validate_ico(&icon).is_none());
        let truncated = ico(&[(2, b"\x89PNG\r\n\x1a\n\xff\xff\xff\xffIDAT".to_vec())])?;
        assert!(validate_ico(&truncated).is_none());
        let short = ico(&[(2, png()?[..20].to_vec())])?;
        assert!(validate_ico(&short).is_none());
        Ok(())
    }

    #[test]
    fn rejects_oversized_dimensions() -> Result<(), image::ImageError> {
        let image = DynamicImage::new_rgb8(1025, 1);
        let mut bytes = Cursor::new(Vec::new());
        image.write_to(&mut bytes, ImageFormat::Png)?;
        assert!(super::png(bytes.get_ref()).is_none());
        Ok(())
    }

    #[test]
    fn applies_orientation_before_removing_metadata() -> Result<(), Box<dyn std::error::Error>> {
        let mut bytes = Vec::new();
        let mut encoder = image::codecs::png::PngEncoder::new(&mut bytes);
        encoder.set_exif_metadata(
            b"II*\0\x08\0\0\0\x01\0\x12\x01\x03\0\x01\0\0\0\x06\0\0\0\0\0\0\0".to_vec(),
        )?;
        encoder.write_image(
            &[255, 0, 0, 255, 0, 255, 0, 255],
            2,
            1,
            image::ExtendedColorType::Rgba8,
        )?;
        let output = super::png(&bytes).ok_or("oriented image rejected")?;
        let image = image::load_from_memory(&output)?.to_rgba8();
        assert_eq!(image.dimensions(), (1, 2));
        assert_eq!(image.get_pixel(0, 0), &image::Rgba([255, 0, 0, 255]));
        assert_eq!(image.get_pixel(0, 1), &image::Rgba([0, 255, 0, 255]));
        Ok(())
    }

    #[test]
    fn rejects_png_output_exceeding_the_byte_limit() -> Result<(), image::ImageError> {
        let mut state = 1u32;
        let pixels = image::RgbImage::from_fn(768, 768, |_, _| {
            state ^= state << 13;
            state ^= state >> 17;
            state ^= state << 5;
            let bytes = state.to_le_bytes();
            image::Rgb([bytes[0], bytes[1], bytes[2]])
        });
        let mut bytes = Cursor::new(Vec::new());
        image::codecs::jpeg::JpegEncoder::new_with_quality(&mut bytes, 70)
            .encode_image(&DynamicImage::ImageRgb8(pixels))?;
        assert!(bytes.get_ref().len() <= MAX_BYTES);
        assert!(super::png(bytes.get_ref()).is_none());
        Ok(())
    }
}
