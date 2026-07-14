mod color_management;
pub mod decode;
pub mod error;
pub mod image_compression;
pub mod types;

pub use error::{ImageError, ImageResult};
pub use types::{DecodedImage, Dimensions};
