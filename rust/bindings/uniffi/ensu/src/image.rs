use ente_ensu::image;
use thiserror::Error;

#[derive(Debug, Error, uniffi::Error)]
pub enum ImageError {
    #[error("{0}")]
    Message(String),
}

#[uniffi::export]
pub fn compress_attachment_image(data: Vec<u8>) -> Result<Vec<u8>, ImageError> {
    image::compress_attachment_image(&data).map_err(|e| ImageError::Message(e.to_string()))
}
