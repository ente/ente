mod cmyk;
mod pdf;
#[cfg(test)]
mod test_profile;

use std::fmt;

use jpeg_encoder::EncodingError;
use moxcms::CmsError;

pub use pdf::{PageSize, PdfX4Writer};

#[derive(Debug)]
pub enum Error {
    InvalidProfile(CmsError),
    NotCmykProfile,
    InvalidPageSize,
    InvalidDimensions { width: u16, height: u16, len: usize },
    NoPages,
    TooLarge,
    Convert(CmsError),
    Encode(EncodingError),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidProfile(_) => f.write_str("invalid output profile"),
            Self::NotCmykProfile => f.write_str("output profile is not a CMYK profile"),
            Self::InvalidPageSize => f.write_str("page size must be positive"),
            Self::InvalidDimensions { width, height, len } => {
                write!(f, "{len} bytes is not a {width}x{height} RGBA image")
            }
            Self::NoPages => f.write_str("a PDF needs at least one page"),
            Self::TooLarge => f.write_str("PDF is too large for its cross-reference table"),
            Self::Convert(_) => f.write_str("CMYK conversion failed"),
            Self::Encode(_) => f.write_str("JPEG encoding failed"),
        }
    }
}

impl std::error::Error for Error {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::InvalidProfile(e) | Self::Convert(e) => Some(e),
            Self::Encode(e) => Some(e),
            Self::NotCmykProfile
            | Self::InvalidPageSize
            | Self::InvalidDimensions { .. }
            | Self::NoPages
            | Self::TooLarge => None,
        }
    }
}
