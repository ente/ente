//! Binarized segmentation mask.

use super::OpResult;
use super::image::ImageU8;

/// The u8 probability map quantized (`round(p*255)`) and binarized at
/// `>= 128` into a 0/255 single-channel image.
pub(crate) struct Mask {
    pub width: i32,
    pub height: i32,
    binary: Vec<u8>,
}

impl Mask {
    /// `probmap` is the u8 quantized probability map, row-major.
    pub(crate) fn from_probmap(probmap: &[u8], width: i32, height: i32) -> Self {
        let binary = probmap
            .iter()
            .map(|&v| if v >= 128 { 255u8 } else { 0u8 })
            .collect();
        Self {
            width,
            height,
            binary,
        }
    }

    /// A fresh buffer per call: both detection and color analysis rebuild the
    /// mask image independently.
    pub(crate) fn to_image(&self) -> OpResult<ImageU8> {
        ImageU8::new(self.width, self.height, 1, self.binary.clone())
    }
}
