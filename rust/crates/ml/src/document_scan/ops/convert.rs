//! `Mat::convertTo` between 8-bit and 32-bit float.

use super::saturate_u8_f32;
use crate::document_scan::OpResult;
use crate::document_scan::image::{ImageF32, ImageU8};

/// `convertTo(CV_32F)` with the default alpha/beta: a widening cast.
pub(crate) fn u8_to_f32(src: &ImageU8) -> OpResult<ImageF32> {
    let mut data = vec![0.0f32; src.data.len()];
    super::pointwise(&mut data, 1, &src.data, 1, |o, s| {
        for (o, &v) in o.iter_mut().zip(s) {
            *o = v as f32;
        }
    });
    ImageF32::new(src.width, src.height, src.channels, data)
}

/// `convertTo(CV_8U)` with the default alpha/beta: `saturate_cast<uchar>`.
pub(crate) fn f32_to_u8(src: &ImageF32) -> OpResult<ImageU8> {
    let mut data = vec![0u8; src.data.len()];
    super::pointwise(&mut data, 1, &src.data, 1, |o, s| {
        for (o, &v) in o.iter_mut().zip(s) {
            *o = saturate_u8_f32(v);
        }
    });
    ImageU8::new(src.width, src.height, src.channels, data)
}

/// `convertTo(CV_8U, alpha)`. OpenCV's scaled 8u->8u path works in `float`.
pub(crate) fn u8_saturating_scale(src: &ImageU8, alpha: f64) -> OpResult<ImageU8> {
    let a = alpha as f32;
    ImageU8::new(
        src.width,
        src.height,
        src.channels,
        src.data
            .iter()
            .map(|&v| saturate_u8_f32(v as f32 * a))
            .collect(),
    )
}
