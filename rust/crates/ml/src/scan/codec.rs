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

pub(crate) fn encode_jpeg(image: &ImageU8, quality: u8) -> Result<Vec<u8>, ScanError> {
    if image.channels != 3 {
        return Err(ScanError::Codec(format!(
            "cannot encode a {}-channel image",
            image.channels
        )));
    }
    let mut rgb = image.data.clone();
    for px in rgb.as_chunks_mut::<3>().0 {
        px.swap(0, 2);
    }
    encode_rgb(
        &rgb,
        image.width as u32,
        image.height as u32,
        EncodedImageFormat::Jpeg { quality },
    )
    .map_err(|err| ScanError::Codec(err.to_string()))
}
