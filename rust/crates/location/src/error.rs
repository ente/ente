use std::borrow::Cow;

use thiserror::Error;

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Debug, Error)]
pub enum Error {
    #[error("failed to read location asset")]
    Io(#[from] std::io::Error),
    #[error("invalid {section}: {reason}")]
    InvalidData {
        section: &'static str,
        reason: Cow<'static, str>,
    },
    #[error("coordinate is outside the valid latitude/longitude range")]
    InvalidCoordinate,
    #[error("map point {0} has an invalid coordinate")]
    InvalidMapPoint(usize),
    #[error("minimum marker distance must be finite and positive")]
    InvalidMarkerDistance,
    #[error("map viewport is invalid")]
    InvalidViewport,
}

impl Error {
    pub(crate) fn invalid(section: &'static str, reason: impl Into<Cow<'static, str>>) -> Self {
        Self::InvalidData {
            section,
            reason: reason.into(),
        }
    }
}
