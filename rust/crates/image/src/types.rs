#[derive(Clone, Debug, PartialEq)]
pub struct Dimensions {
    pub width: u32,
    pub height: u32,
}

/// Decoded pixels normalized to this crate's output contract: 8-bit RGB in
/// the sRGB color space, with EXIF orientation applied.
///
/// Embedded ICC profiles are converted to sRGB on a best-effort basis: images
/// without a profile are assumed to already be sRGB, and images whose profile
/// cannot be applied (unparseable data, unsupported layouts, or PQ/HLG
/// transfer curves that would need tone mapping) keep their decoded pixel
/// values.
#[derive(Clone, Debug)]
pub struct DecodedImage {
    pub dimensions: Dimensions,
    /// Tightly packed row-major RGB triples (`3 * width * height` bytes).
    pub rgb: Vec<u8>,
}
