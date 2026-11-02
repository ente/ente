mod bounded;
mod color_management;
pub mod decode;
pub mod error;
pub mod image_compression;
mod png;
pub mod types;

pub use bounded::{BoundedDecodedImage, ImageInput, decode_bounded};
pub use error::{ImageError, ImageResult};
pub use types::{DecodedImage, Dimensions};
