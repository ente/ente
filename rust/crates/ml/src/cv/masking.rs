use crate::cv::OpResult;
use crate::cv::image::{ImageF32, ImageU8};

pub(crate) fn threshold_binary_u8(src: &ImageU8, thresh: f64, maxval: f64) -> OpResult<ImageU8> {
    let ithresh = thresh.floor() as i64;
    let imaxval = maxval.round_ties_even().clamp(0.0, 255.0) as u8;
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

pub(crate) fn in_range_u8(src: &ImageU8, lower: f64, upper: f64) -> OpResult<ImageU8> {
    if src.channels != 1 {
        return Err("in_range_u8: expected a single-channel image".to_string());
    }
    let lo = lower.round_ties_even().clamp(0.0, 255.0) as u8;
    let hi = upper.round_ties_even().clamp(0.0, 255.0) as u8;
    ImageU8::new(
        src.width,
        src.height,
        1,
        src.data
            .iter()
            .map(|&v| if lo <= v && v <= hi { 255 } else { 0 })
            .collect(),
    )
}

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

pub(crate) fn count_non_zero(src: &ImageU8) -> OpResult<i32> {
    if src.channels != 1 {
        return Err(format!(
            "count_non_zero: expected a single-channel image, got {}",
            src.channels
        ));
    }
    Ok(src.data.iter().filter(|&&v| v != 0).count() as i32)
}

pub(crate) fn copy_to_masked(src: &ImageU8, dst: &ImageU8, mask: &ImageU8) -> OpResult<ImageU8> {
    if !src.same_geometry(dst) {
        return Err("copy_to_masked: source and destination geometry differ".to_string());
    }
    if mask.channels != 1 || mask.width != src.width || mask.height != src.height {
        return Err("copy_to_masked: mask must be single-channel and the same size".to_string());
    }
    let cn = src.channels as usize;
    let mut out = dst.data.clone();
    super::pointwise3(&mut out, cn, &src.data, cn, &mask.data, 1, |o, s, m| {
        for (i, &m) in m.iter().enumerate() {
            if m != 0 {
                o[i * cn..(i + 1) * cn].copy_from_slice(&s[i * cn..(i + 1) * cn]);
            }
        }
    });
    ImageU8::new(src.width, src.height, src.channels, out)
}
