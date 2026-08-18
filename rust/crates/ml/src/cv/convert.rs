use super::saturate_u8_f32;
use crate::cv::OpResult;
use crate::cv::image::{ImageF32, ImageU8};

pub(crate) fn u8_to_f32(src: &ImageU8) -> OpResult<ImageF32> {
    let mut data = vec![0.0f32; src.data.len()];
    super::pointwise(&mut data, 1, &src.data, 1, |o, s| {
        for (o, &v) in o.iter_mut().zip(s) {
            *o = v as f32;
        }
    });
    ImageF32::new(src.width, src.height, src.channels, data)
}

pub(crate) fn f32_to_u8(src: &ImageF32) -> OpResult<ImageU8> {
    let mut data = vec![0u8; src.data.len()];
    super::pointwise(&mut data, 1, &src.data, 1, |o, s| {
        for (o, &v) in o.iter_mut().zip(s) {
            *o = saturate_u8_f32(v);
        }
    });
    ImageU8::new(src.width, src.height, src.channels, data)
}
