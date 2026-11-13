use thiserror::Error;

pub type ImageResult<T> = Result<T, ImageError>;

#[derive(Debug, Error)]
pub enum ImageError {
    #[error("decode error: {0}")]
    Decode(String),
    #[error("image too large")]
    TooLarge(#[source] image::ImageError),
    #[error("postprocess error: {0}")]
    Postprocess(String),
}

impl From<image::ImageError> for ImageError {
    fn from(value: image::ImageError) -> Self {
        if matches!(
            &value,
            image::ImageError::Limits(error)
                if matches!(
                    error.kind(),
                    image::error::LimitErrorKind::DimensionError
                        | image::error::LimitErrorKind::InsufficientMemory
                )
        ) {
            Self::TooLarge(value)
        } else {
            Self::Decode(value.to_string())
        }
    }
}
