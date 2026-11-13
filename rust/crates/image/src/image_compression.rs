use fast_image_resize::{
    FilterType, PixelType, ResizeAlg, ResizeOptions, Resizer,
    images::{Image as FirImage, ImageRef as FirImageRef},
};
use image::{
    ColorType, ImageEncoder,
    codecs::{jpeg::JpegEncoder, png::PngEncoder},
};

use crate::{
    decode::decode_image_from_bytes,
    error::{ImageError, ImageResult},
    types::DecodedImage,
};

pub const FACE_THUMBNAIL_JPEG_QUALITY: u8 = 90;
pub const FACE_THUMBNAIL_MIN_DIMENSION: u32 = 512;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EncodedImageFormat {
    Jpeg { quality: u8 },
    Png,
}

pub fn compress_image_bytes_to_jpeg(
    image_bytes: &[u8],
    max_long_edge: u32,
    quality: u8,
) -> ImageResult<Vec<u8>> {
    let decoded = decode_image_from_bytes(image_bytes)?;
    compress_decoded_to_jpeg(&decoded, max_long_edge, quality)
}

pub fn compress_decoded_to_jpeg(
    decoded: &DecodedImage,
    max_long_edge: u32,
    quality: u8,
) -> ImageResult<Vec<u8>> {
    if max_long_edge == 0 {
        return Err(ImageError::Postprocess(
            "max long edge must be greater than zero".to_string(),
        ));
    }
    if decoded.dimensions.width == 0 || decoded.dimensions.height == 0 {
        return Err(ImageError::Postprocess(
            "cannot compress image with zero width or height".to_string(),
        ));
    }

    let (width, height) = target_dimensions(
        decoded.dimensions.width,
        decoded.dimensions.height,
        max_long_edge,
    )?;

    if width == decoded.dimensions.width && height == decoded.dimensions.height {
        return encode_rgb(
            &decoded.rgb,
            width,
            height,
            EncodedImageFormat::Jpeg { quality },
        );
    }

    let resized = resize_rgb(decoded, width, height)?;
    encode_rgb(
        resized.buffer(),
        width,
        height,
        EncodedImageFormat::Jpeg { quality },
    )
}

pub fn encode_rgb(
    rgb_bytes: &[u8],
    width: u32,
    height: u32,
    format: EncodedImageFormat,
) -> ImageResult<Vec<u8>> {
    if width == 0 || height == 0 {
        return Err(ImageError::Postprocess(
            "cannot encode image with zero width or height".to_string(),
        ));
    }

    let expected_len = width as usize * height as usize * 3;
    if rgb_bytes.len() != expected_len {
        return Err(ImageError::Postprocess(format!(
            "invalid RGB buffer length {}, expected {} for {}x{}",
            rgb_bytes.len(),
            expected_len,
            width,
            height
        )));
    }

    let mut encoded = Vec::new();
    match format {
        EncodedImageFormat::Jpeg { quality } => {
            JpegEncoder::new_with_quality(&mut encoded, quality)
                .write_image(rgb_bytes, width, height, ColorType::Rgb8.into())
                .map_err(|e| ImageError::Postprocess(format!("failed to encode JPEG: {e}")))?;
        }
        EncodedImageFormat::Png => {
            PngEncoder::new(&mut encoded)
                .write_image(rgb_bytes, width, height, ColorType::Rgb8.into())
                .map_err(|e| ImageError::Postprocess(format!("failed to encode PNG: {e}")))?;
        }
    }
    Ok(encoded)
}

fn target_dimensions(width: u32, height: u32, max_long_edge: u32) -> ImageResult<(u32, u32)> {
    if width == 0 || height == 0 || max_long_edge == 0 {
        return Err(ImageError::Postprocess(
            "cannot compute resize dimensions with zero input".to_string(),
        ));
    }

    let long_edge = width.max(height);
    if long_edge <= max_long_edge {
        return Ok((width, height));
    }

    let scaled_width = scaled_dimension(width, long_edge, max_long_edge)?;
    let scaled_height = scaled_dimension(height, long_edge, max_long_edge)?;
    Ok((scaled_width, scaled_height))
}

fn scaled_dimension(
    value: u32,
    original_long_edge: u32,
    target_long_edge: u32,
) -> ImageResult<u32> {
    if original_long_edge == 0 {
        return Err(ImageError::Postprocess(
            "cannot scale with zero long edge".to_string(),
        ));
    }

    let numerator = u128::from(value) * u128::from(target_long_edge);
    let denominator = u128::from(original_long_edge);
    let rounded = (numerator + (denominator / 2)) / denominator;
    u32::try_from(rounded.max(1))
        .map_err(|_| ImageError::Postprocess("scaled dimension exceeds u32".to_string()))
}

fn resize_rgb(
    decoded: &DecodedImage,
    target_width: u32,
    target_height: u32,
) -> ImageResult<FirImage<'static>> {
    let source = FirImageRef::new(
        decoded.dimensions.width,
        decoded.dimensions.height,
        decoded.rgb.as_slice(),
        PixelType::U8x3,
    )
    .map_err(|e| ImageError::Postprocess(format!("failed to create resize source image: {e}")))?;

    let mut resized = FirImage::new(target_width, target_height, PixelType::U8x3);
    let mut resizer = Resizer::new();
    let options = ResizeOptions::new().resize_alg(ResizeAlg::Convolution(FilterType::Lanczos3));
    resizer
        .resize(&source, &mut resized, Some(&options))
        .map_err(|e| ImageError::Postprocess(format!("failed to resize image: {e}")))?;

    Ok(resized)
}

#[cfg(test)]
mod tests {
    use std::io::Cursor;

    use image::{DynamicImage, ImageFormat, RgbImage};

    use super::{
        EncodedImageFormat, FACE_THUMBNAIL_JPEG_QUALITY, compress_image_bytes_to_jpeg, encode_rgb,
        target_dimensions,
    };

    #[test]
    fn encode_rgb_jpeg_produces_valid_jpeg() {
        let rgb = vec![255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255];
        let encoded = encode_rgb(
            &rgb,
            2,
            2,
            EncodedImageFormat::Jpeg {
                quality: FACE_THUMBNAIL_JPEG_QUALITY,
            },
        )
        .expect("jpeg encoding should succeed");

        assert!(!encoded.is_empty());
        image::load_from_memory_with_format(&encoded, ImageFormat::Jpeg)
            .expect("encoded bytes should be valid JPEG");
    }

    #[test]
    fn encode_rgb_rejects_invalid_buffer_size() {
        let invalid_rgb = vec![0, 1, 2];
        let result = encode_rgb(
            &invalid_rgb,
            2,
            2,
            EncodedImageFormat::Jpeg {
                quality: FACE_THUMBNAIL_JPEG_QUALITY,
            },
        );

        assert!(result.is_err());
    }

    #[test]
    fn target_dimensions_cap_long_edge_without_upscaling() {
        assert_eq!(target_dimensions(2000, 1000, 1080).unwrap(), (1080, 540));
        assert_eq!(target_dimensions(400, 200, 1080).unwrap(), (400, 200));
    }

    #[test]
    fn compress_image_bytes_to_jpeg_caps_long_edge() {
        let input = png_bytes(2000, 1000);
        let encoded =
            compress_image_bytes_to_jpeg(&input, 1080, 85).expect("compression should succeed");
        let decoded = image::load_from_memory_with_format(&encoded, ImageFormat::Jpeg)
            .expect("compressed bytes should be valid JPEG");

        assert_eq!(decoded.width(), 1080);
        assert_eq!(decoded.height(), 540);
    }

    #[test]
    fn compress_image_bytes_to_jpeg_does_not_upscale() {
        let input = png_bytes(64, 32);
        let encoded =
            compress_image_bytes_to_jpeg(&input, 1080, 85).expect("compression should succeed");
        let decoded = image::load_from_memory_with_format(&encoded, ImageFormat::Jpeg)
            .expect("compressed bytes should be valid JPEG");

        assert_eq!(decoded.width(), 64);
        assert_eq!(decoded.height(), 32);
    }

    #[test]
    fn compress_image_bytes_to_jpeg_rejects_invalid_input() {
        let result = compress_image_bytes_to_jpeg(b"not an image", 1080, 85);

        assert!(result.is_err());
    }

    fn png_bytes(width: u32, height: u32) -> Vec<u8> {
        let image = RgbImage::from_fn(width, height, |x, y| {
            image::Rgb([(x % 255) as u8, (y % 255) as u8, ((x + y) % 255) as u8])
        });
        let mut encoded = Cursor::new(Vec::new());
        DynamicImage::ImageRgb8(image)
            .write_to(&mut encoded, ImageFormat::Png)
            .expect("test PNG encoding should succeed");
        encoded.into_inner()
    }
}
