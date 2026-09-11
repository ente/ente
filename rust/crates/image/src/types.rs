#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Dimensions {
    pub width: u32,
    pub height: u32,
}

// 8-bit sRGB with EXIF orientation applied. ICC conversion is best-effort;
// absent, unusable, or PQ/HLG profiles leave decoded values unchanged.
#[derive(Clone, Debug)]
pub struct DecodedImage {
    pub dimensions: Dimensions,
    // Tightly packed row-major RGB triples (`3 * width * height` bytes).
    pub rgb: Vec<u8>,
}
