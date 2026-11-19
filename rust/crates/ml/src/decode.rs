use ente_image::{
    BoundedDecodeOptions, BoundedDecodedImage, ImageError, ImageInput,
    decode::{decode_image_from_bytes, decode_image_from_path},
    decode_bounded,
};

use crate::{
    error::{MlError, MlResult},
    indexing::ImageSource,
};

pub(crate) fn decode_image(
    source: &ImageSource,
    options: BoundedDecodeOptions,
    subject: &str,
) -> MlResult<BoundedDecodedImage> {
    let input = match source {
        ImageSource::Path(path) => ImageInput::Path(path),
        ImageSource::Bytes(bytes) => ImageInput::Bytes(bytes),
    };
    match decode_bounded(input, options) {
        Err(ImageError::Decode(reason)) => {
            log::info!("Rust ML bounded decode refused: {subject} reason={reason}");
            let image = match source {
                ImageSource::Path(path) => decode_image_from_path(path)?,
                ImageSource::Bytes(bytes) => decode_image_from_bytes(bytes)?,
            };
            Ok(BoundedDecodedImage {
                original_dimensions: image.dimensions.clone(),
                image,
            })
        }
        result => result.map_err(MlError::from),
    }
}
