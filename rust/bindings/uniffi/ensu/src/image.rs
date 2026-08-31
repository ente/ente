use ente_ensu::image;
use thiserror::Error;

#[derive(Debug, Error, uniffi::Error)]
pub enum ImageError {
    #[error("{detail}")]
    Other { detail: String },
}

#[uniffi::export]
pub fn compress_attachment_image(data: Vec<u8>) -> Result<Vec<u8>, ImageError> {
    image::compress_attachment_image(&data).map_err(|error| ImageError::Other {
        detail: ente_core::error::chain(&error),
    })
}
