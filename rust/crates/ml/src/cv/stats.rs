use crate::cv::OpResult;
use crate::cv::image::{ImageF32, ImageU8};

fn sum_channel0(src: &ImageF32) -> f64 {
    let cn = src.channels as usize;
    if cn == 1 {
        src.data.iter().map(|&v| v as f64).sum()
    } else {
        src.data.chunks_exact(cn).map(|px| px[0] as f64).sum()
    }
}

pub(crate) fn mean_f32(src: &ImageF32) -> OpResult<f64> {
    Ok(sum_channel0(src) / src.pixels() as f64)
}

pub(crate) fn mean_u8c3_masked(src: &ImageU8, mask: &ImageU8) -> OpResult<[f64; 3]> {
    if src.channels != 3 {
        return Err(format!(
            "mean_u8c3_masked: expected a 3-channel image, got {}",
            src.channels
        ));
    }
    if mask.channels != 1 || mask.width != src.width || mask.height != src.height {
        return Err("mean_u8c3_masked: mask must be single-channel and the same size".to_string());
    }
    let mut sums = [0i64; 3];
    let mut count = 0i64;
    for (px, &m) in src.data.as_chunks::<3>().0.iter().zip(mask.data.iter()) {
        if m != 0 {
            sums[0] += px[0] as i64;
            sums[1] += px[1] as i64;
            sums[2] += px[2] as i64;
            count += 1;
        }
    }
    if count == 0 {
        return Ok([0.0; 3]);
    }
    Ok(sums.map(|s| s as f64 / count as f64))
}

pub(crate) fn min_max_loc_f32(src: &ImageF32) -> OpResult<(f64, f64)> {
    let mut min_val = f32::INFINITY;
    let mut max_val = f32::NEG_INFINITY;
    for &v in &src.data {
        if v < min_val {
            min_val = v;
        }
        if v > max_val {
            max_val = v;
        }
    }
    Ok((min_val as f64, max_val as f64))
}

pub(crate) fn hist_256_u8(src: &ImageU8) -> OpResult<Vec<f64>> {
    let cn = src.channels as usize;
    let mut bins = [0u32; 256];
    for px in src.data.chunks_exact(cn) {
        bins[px[0] as usize] += 1;
    }
    Ok(bins.iter().map(|&c| c as f64).collect())
}

pub(crate) fn hist_256_f32(src: &ImageF32) -> OpResult<Vec<f64>> {
    let cn = src.channels as usize;
    let mut bins = [0u32; 256];
    for px in src.data.chunks_exact(cn) {
        let v = px[0] as f64;
        if (0.0..256.0).contains(&v) {
            bins[v as usize] += 1;
        }
    }
    Ok(bins.iter().map(|&c| c as f64).collect())
}

fn nth(values: &mut [f32], p: f64) -> f32 {
    let index = ((values.len() as f64 * p) as usize).min(values.len() - 1);
    let (_, value, _) = values.select_nth_unstable_by(index, f32::total_cmp);
    *value
}

pub(crate) fn percentile_f32(src: &ImageF32, p: f64) -> OpResult<f32> {
    let mut values = src.data.clone();
    if values.is_empty() {
        return Err("percentile_f32: empty image".to_string());
    }
    Ok(nth(&mut values, p))
}

pub(crate) fn percentile_pair_f32(src: &ImageF32, low: f64, high: f64) -> OpResult<(f32, f32)> {
    let mut values = src.data.clone();
    if values.is_empty() {
        return Err("percentile_pair_f32: empty image".to_string());
    }
    Ok((nth(&mut values, low), nth(&mut values, high)))
}
