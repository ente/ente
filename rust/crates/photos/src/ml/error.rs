use thiserror::Error;

pub type MlResult<T> = Result<T, MlError>;

#[derive(Debug, Error)]
pub enum MlError {
    #[error("invalid request: {0}")]
    InvalidRequest(String),
    #[error("decode error: {0}")]
    Decode(String),
    #[error("preprocess error: {0}")]
    Preprocess(String),
    #[error("onnx runtime error: {0}")]
    Ort(String),
    #[error("corrupt model: {0}")]
    CorruptModel(String),
    #[error("postprocess error: {0}")]
    Postprocess(String),
    #[error("runtime error: {0}")]
    Runtime(String),
}

impl<R> From<ort::Error<R>> for MlError {
    fn from(value: ort::Error<R>) -> Self {
        MlError::Ort(value.to_string())
    }
}

impl From<image::ImageError> for MlError {
    fn from(value: image::ImageError) -> Self {
        MlError::Decode(value.to_string())
    }
}

impl From<ente_image::ImageError> for MlError {
    fn from(value: ente_image::ImageError) -> Self {
        match value {
            ente_image::ImageError::Decode(message) => MlError::Decode(message),
            ente_image::ImageError::Postprocess(message) => MlError::Postprocess(message),
        }
    }
}
