use super::OpResult;
use crate::cv::image::ImageU8;

pub(crate) struct Mask {
    pub width: i32,
    pub height: i32,
    binary: Vec<u8>,
}

impl Mask {
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

    pub(crate) fn to_image(&self) -> OpResult<ImageU8> {
        ImageU8::new(self.width, self.height, 1, self.binary.clone())
    }
}
