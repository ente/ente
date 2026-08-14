//! Reductions, histograms and the pixel sort.

use crate::ml::document_scan::OpResult;
use crate::ml::document_scan::image::{ImageF32, ImageU8};

/// `sum32f` for a single-channel buffer.
///
/// The accumulation order is OpenCV's, not a plain left fold: eight
/// consecutive floats per step are widened into four `double` lane
/// accumulators, and only the remainder is summed by the scalar loop (which
/// adds groups of four in `float` before widening). The order is part of the
/// result at f64 precision.
fn sum_f32_c1(data: &[f32]) -> f64 {
    let len = data.len();
    let mut lanes = [0.0f64; 4];
    let mut i = 0usize;
    while i + 8 <= len {
        lanes[0] += data[i] as f64 + data[i + 4] as f64;
        lanes[1] += data[i + 1] as f64 + data[i + 5] as f64;
        lanes[2] += data[i + 2] as f64 + data[i + 6] as f64;
        lanes[3] += data[i + 3] as f64 + data[i + 7] as f64;
        i += 8;
    }
    let mut sum = 0.0f64;
    for lane in lanes {
        sum += lane;
    }
    while i + 4 <= len {
        sum += (data[i] + data[i + 1] + data[i + 2] + data[i + 3]) as f64;
        i += 4;
    }
    while i < len {
        sum += data[i] as f64;
        i += 1;
    }
    sum
}

fn sum_channel0(src: &ImageF32) -> f64 {
    let cn = src.channels as usize;
    if cn == 1 {
        return sum_f32_c1(&src.data);
    }
    // For other channel counts OpenCV folds each channel serially in `double`.
    let mut sum = 0.0f64;
    for px in src.data.chunks_exact(cn) {
        sum += px[0] as f64;
    }
    sum
}

/// `cv::sum(...)[0]`.
pub(crate) fn sum_f32(src: &ImageF32) -> OpResult<f64> {
    Ok(sum_channel0(src))
}

/// `cv::mean(...)[0]`: the same accumulator scaled by `1/pixels`.
pub(crate) fn mean_f32(src: &ImageF32) -> OpResult<f64> {
    Ok(sum_channel0(src) * (1.0 / src.pixels() as f64))
}

/// `cv::mean(src, mask)` on 8UC3: exact integer sums over the masked pixels.
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
    for (px, &m) in src.data.chunks_exact(3).zip(mask.data.iter()) {
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
    let scale = 1.0 / count as f64;
    Ok([
        sums[0] as f64 * scale,
        sums[1] as f64 * scale,
        sums[2] as f64 * scale,
    ])
}

/// `cv::minMaxLoc` values only. Strict comparisons starting from +/-infinity,
/// so NaN never becomes the extremum.
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

/// `calcHist` with 256 uniform bins over [0,256) on channel 0.
pub(crate) fn hist_256_u8(src: &ImageU8) -> OpResult<Vec<f64>> {
    let cn = src.channels as usize;
    let mut bins = [[0u32; 256]; 4];
    for (i, px) in src.data.chunks_exact(cn).enumerate() {
        bins[i & 3][px[0] as usize] += 1;
    }
    Ok(counts_to_hist(&bins))
}

/// Four interleaved bin sets break the store-to-load chain a single set of
/// counters creates. Bin contents are exact integers either way.
fn counts_to_hist(bins: &[[u32; 256]; 4]) -> Vec<f64> {
    (0..256)
        .map(|i| {
            (bins[0][i] as u64 + bins[1][i] as u64 + bins[2][i] as u64 + bins[3][i] as u64) as f64
        })
        .collect()
}

/// Same, on 32F: the bin is `cvFloor(v)` and values outside [0,256) are
/// dropped rather than clamped.
pub(crate) fn hist_256_f32(src: &ImageF32) -> OpResult<Vec<f64>> {
    let cn = src.channels as usize;
    let mut bins = [[0u32; 256]; 4];
    for (i, px) in src.data.chunks_exact(cn).enumerate() {
        let v = px[0] as f64;
        if !(0.0..256.0).contains(&v) {
            continue;
        }
        let idx = (v.floor() as i64).clamp(0, 255) as usize;
        bins[i & 3][idx] += 1;
    }
    Ok(counts_to_hist(&bins))
}

/// The strictly increasing `f32 -> u32` map `f32::total_cmp` compares through,
/// shifted so that the unsigned order matches. Sorting the keys and inverting
/// therefore yields exactly the `total_cmp` order, NaN payloads included.
fn sort_key(v: f32) -> u32 {
    let bits = v.to_bits();
    let flip = ((bits as i32 >> 31) as u32) >> 1;
    (bits ^ flip) ^ 0x8000_0000
}

fn from_sort_key(key: u32) -> f32 {
    f32::from_bits(if key & 0x8000_0000 != 0 {
        key ^ 0x8000_0000
    } else {
        !key
    })
}

/// `reshape(1,1)` + `cv::sort(SORT_ASCENDING)`.
pub(crate) fn sort_pixels_ascending_f32(src: &ImageF32) -> OpResult<Vec<f32>> {
    // A total order over the whole plane, so any correct sort reproduces it.
    // Below the crossover the comparison sort wins; above it, an LSD radix
    // pass over the key above is roughly three times faster at 2 megapixels.
    if src.data.len() < 4096 {
        let mut values = src.data.clone();
        values.sort_by(f32::total_cmp);
        return Ok(values);
    }

    let mut keys: Vec<u32> = src.data.iter().map(|&v| sort_key(v)).collect();
    let mut scratch = vec![0u32; keys.len()];
    let mut counts = [[0u32; 256]; 4];
    for &k in &keys {
        for (pass, count) in counts.iter_mut().enumerate() {
            count[((k >> (pass * 8)) & 0xff) as usize] += 1;
        }
    }
    for (pass, count) in counts.iter().enumerate() {
        let mut offset = 0u32;
        let mut start = [0u32; 256];
        for (bin, slot) in start.iter_mut().enumerate() {
            *slot = offset;
            offset += count[bin];
        }
        for &k in &keys {
            let bin = ((k >> (pass * 8)) & 0xff) as usize;
            scratch[start[bin] as usize] = k;
            start[bin] += 1;
        }
        std::mem::swap(&mut keys, &mut scratch);
    }
    Ok(keys.into_iter().map(from_sort_key).collect())
}
