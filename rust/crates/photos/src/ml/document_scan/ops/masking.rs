//! Thresholding, masking and the boolean/counting operations.

use super::{cv_floor_f64, saturate_i32_f64};
use crate::ml::document_scan::OpResult;
use crate::ml::document_scan::image::{ImageF32, ImageU8};

/// `threshold(THRESH_BINARY)` on 8U. OpenCV floors the threshold to an integer
/// and rounds `maxval`, then compares strictly greater.
pub(crate) fn threshold_binary_u8(src: &ImageU8, thresh: f64, maxval: f64) -> OpResult<ImageU8> {
    let ithresh = cv_floor_f64(thresh);
    let imaxval = saturate_i32_f64(maxval).clamp(0, 255) as u8;
    ImageU8::new(
        src.width,
        src.height,
        src.channels,
        src.data
            .iter()
            .map(|&v| if v as i64 > ithresh { imaxval } else { 0 })
            .collect(),
    )
}

/// `threshold(THRESH_BINARY)` on 32F: the bounds are narrowed to `float` and
/// the comparison is strictly greater, so NaN maps to 0.
pub(crate) fn threshold_binary_f32(src: &ImageF32, thresh: f64, maxval: f64) -> OpResult<ImageF32> {
    let t = thresh as f32;
    let m = maxval as f32;
    ImageF32::new(
        src.width,
        src.height,
        src.channels,
        src.data
            .iter()
            .map(|&v| if v > t { m } else { 0.0 })
            .collect(),
    )
}

/// `cv::inRange` with scalar bounds: inclusive on both ends. The bounds are
/// rounded to `int` first; a range that cannot contain any value of the source
/// type is replaced by an empty one.
pub(crate) fn in_range_u8(src: &ImageU8, lower: f64, upper: f64) -> OpResult<ImageU8> {
    let cn = src.channels as usize;
    if cn > 4 {
        return Err("in_range_u8: at most 4 channels are supported".to_string());
    }
    // `Scalar(v)` sets only val[0]; the remaining channels get 0.
    let mut lo = [0u8; 4];
    let mut hi = [0u8; 4];
    for c in 0..cn {
        let (mut l, mut u) = if c == 0 {
            (saturate_i32_f64(lower), saturate_i32_f64(upper))
        } else {
            (0, 0)
        };
        if l > u || l > 255 || u < 0 {
            l = 1;
            u = 0;
        }
        lo[c] = l.clamp(0, 255) as u8;
        hi[c] = u.clamp(0, 255) as u8;
    }
    let data: Vec<u8> = src
        .data
        .chunks_exact(cn)
        .map(|px| {
            let inside = px
                .iter()
                .enumerate()
                .all(|(c, &v)| lo[c] <= v && v <= hi[c]);
            if inside { 255u8 } else { 0u8 }
        })
        .collect();
    ImageU8::new(src.width, src.height, 1, data)
}

/// `cv::bitwise_and` without a mask: byte-wise AND.
pub(crate) fn bitwise_and_u8(a: &ImageU8, b: &ImageU8) -> OpResult<ImageU8> {
    if !a.same_geometry(b) {
        return Err("bitwise_and_u8: operands have different geometry".to_string());
    }
    ImageU8::new(
        a.width,
        a.height,
        a.channels,
        a.data
            .iter()
            .zip(b.data.iter())
            .map(|(&x, &y)| x & y)
            .collect(),
    )
}

/// `cv::countNonZero`: single-channel only, counts elements that are not 0.
pub(crate) fn count_non_zero(src: &ImageU8) -> OpResult<i32> {
    if src.channels != 1 {
        return Err(format!(
            "count_non_zero: expected a single-channel image, got {}",
            src.channels
        ));
    }
    Ok(src.data.iter().filter(|&&v| v != 0).count() as i32)
}

/// `Mat::copyTo(dst, mask)`: copy where the mask is non-zero, leave the rest
/// of `dst` untouched.
pub(crate) fn copy_to_masked(src: &ImageU8, dst: &ImageU8, mask: &ImageU8) -> OpResult<ImageU8> {
    if !src.same_geometry(dst) {
        return Err("copy_to_masked: source and destination geometry differ".to_string());
    }
    if mask.channels != 1 || mask.width != src.width || mask.height != src.height {
        return Err("copy_to_masked: mask must be single-channel and the same size".to_string());
    }
    let cn = src.channels as usize;
    let mut out = dst.data.clone();
    // Pointwise over three aligned buffers: output pixel i is either dst's or
    // src's, decided by mask pixel i alone.
    super::pointwise3(&mut out, cn, &src.data, cn, &mask.data, 1, |o, s, m| {
        for (i, &m) in m.iter().enumerate() {
            if m != 0 {
                o[i * cn..(i + 1) * cn].copy_from_slice(&s[i * cn..(i + 1) * cn]);
            }
        }
    });
    ImageU8::new(src.width, src.height, src.channels, out)
}
