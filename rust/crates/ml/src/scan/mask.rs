use super::OpResult;
use crate::cv;
use crate::cv::image::ImageU8;

pub(crate) struct Mask {
    pub width: i32,
    pub height: i32,
    prob: Vec<u8>,
}

impl Mask {
    pub(crate) fn from_probmap(prob: Vec<u8>, width: i32, height: i32) -> Self {
        Self {
            width,
            height,
            prob,
        }
    }

    pub(crate) fn prob_image(&self) -> OpResult<ImageU8> {
        ImageU8::new(self.width, self.height, 1, self.prob.clone())
    }

    pub(crate) fn binary_image(&self) -> OpResult<ImageU8> {
        cv::threshold_binary_u8(&self.prob_image()?, 127.0, 255.0)
    }
}
