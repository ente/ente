use ente_image::{ImageError, image_compression::compress_image_bytes_to_jpeg};

pub const ATTACHMENT_IMAGE_MAX_LONG_EDGE: u32 = 512;
pub const ATTACHMENT_IMAGE_JPEG_QUALITY: u8 = 85;

pub fn compress_attachment_image(image_bytes: &[u8]) -> Result<Vec<u8>, ImageError> {
    compress_image_bytes_to_jpeg(
        image_bytes,
        ATTACHMENT_IMAGE_MAX_LONG_EDGE,
        ATTACHMENT_IMAGE_JPEG_QUALITY,
    )
}

#[cfg(test)]
mod tests {
    use ente_image::{
        decode::decode_image_from_bytes,
        image_compression::{EncodedImageFormat, encode_rgb},
    };

    use super::{
        ATTACHMENT_IMAGE_JPEG_QUALITY, ATTACHMENT_IMAGE_MAX_LONG_EDGE, compress_attachment_image,
    };

    #[test]
    fn compress_attachment_image_uses_ensu_defaults() {
        let rgb = vec![180; 2000 * 1000 * 3];
        let input = encode_rgb(&rgb, 2000, 1000, EncodedImageFormat::Jpeg { quality: 95 })
            .expect("test JPEG input should encode");

        let output = compress_attachment_image(&input).expect("attachment image should compress");
        let decoded = decode_image_from_bytes(&output).expect("output should decode");

        assert_eq!(decoded.dimensions.width, ATTACHMENT_IMAGE_MAX_LONG_EDGE);
        assert_eq!(decoded.dimensions.height, 256);
        assert!(output.len() < input.len());
    }

    #[test]
    fn compression_quality_default_is_85() {
        assert_eq!(ATTACHMENT_IMAGE_JPEG_QUALITY, 85);
    }
}
