use ente_image::decode::decode_image_from_bytes;
use ente_image::image_compression::{EncodedImageFormat, encode_rgb};

use super::scanner::ScanError;
use crate::cv::image::ImageU8;

pub(crate) fn decode_bgr(bytes: &[u8]) -> Result<ImageU8, ScanError> {
    let decoded = decode_image_from_bytes(bytes)
        .map_err(|err| ScanError::Codec(format!("failed to decode image: {err}")))?;
    let width = i32::try_from(decoded.dimensions.width)
        .map_err(|_| ScanError::Codec("image width does not fit in i32".to_string()))?;
    let height = i32::try_from(decoded.dimensions.height)
        .map_err(|_| ScanError::Codec("image height does not fit in i32".to_string()))?;

    let mut bgr = decoded.rgb;
    for px in bgr.as_chunks_mut::<3>().0 {
        px.swap(0, 2);
    }
    ImageU8::new(width, height, 3, bgr).map_err(ScanError::Codec)
}

pub(crate) fn encode_jpeg(mut image: ImageU8, quality: u8) -> Result<Vec<u8>, ScanError> {
    if image.channels != 3 {
        return Err(ScanError::Codec(format!(
            "cannot encode a {}-channel image",
            image.channels
        )));
    }
    for px in image.data.as_chunks_mut::<3>().0 {
        px.swap(0, 2);
    }
    encode_rgb(
        &image.data,
        image.width as u32,
        image.height as u32,
        EncodedImageFormat::Jpeg { quality },
    )
    .map_err(|err| ScanError::Codec(err.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scan::segmentation::prepare_input;

    #[test]
    fn exif_orientation_is_applied_before_model_preparation() -> Result<(), ScanError> {
        let source = ImageU8::new(
            37,
            21,
            3,
            (0..37 * 21 * 3)
                .map(|i| ((i * 37 + i / 13 * 17) % 256) as u8)
                .collect(),
        )
        .map_err(ScanError::Codec)?;
        let jpeg = encode_jpeg(source, 90)?;
        let upright = decode_bgr(&jpeg)?;
        let tiff = [
            b'E', b'x', b'i', b'f', 0, 0, b'M', b'M', 0, 42, 0, 0, 0, 8, 0, 1, 1, 18, 0, 3, 0, 0,
            0, 1, 0, 6, 0, 0, 0, 0, 0, 0,
        ];
        let mut rotated_jpeg = jpeg[..2].to_vec();
        rotated_jpeg.extend([0xff, 0xe1, 0, (tiff.len() + 2) as u8]);
        rotated_jpeg.extend(tiff);
        rotated_jpeg.extend(&jpeg[2..]);
        let decoded = decode_bgr(&rotated_jpeg)?;
        assert_eq!((decoded.width, decoded.height), (21, 37));
        let expected = crate::cv::rotate_u8(&upright, 90).map_err(ScanError::Pipeline)?;
        assert_eq!(decoded, expected);
        assert_eq!(
            prepare_input(&decoded).map_err(ScanError::Pipeline)?,
            prepare_input(&expected).map_err(ScanError::Pipeline)?
        );
        Ok(())
    }
}
