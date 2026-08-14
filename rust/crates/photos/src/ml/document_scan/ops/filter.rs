//! Separable neighbourhood filters: `cv::GaussianBlur` and `cv::boxFilter`.
//!
//! Both reproduce the accumulation OpenCV performs, not merely the
//! mathematical definition:
//!
//! * `GaussianBlur` on `CV_8U` takes the bit-exact fixed-point branch: the
//!   kernel is a `ufixedpoint16` (8 fractional bits, taps summing to exactly
//!   256), the horizontal pass accumulates in u16 and the vertical pass in
//!   u32, so every value is an integer.
//! * `boxFilter` on `CV_32F` runs `RowSum<float, double>` +
//!   `ColumnSum<double, float>`: an O(1)-per-pixel sliding sum whose *order*
//!   of double-precision additions is part of the result. The three-tap and
//!   five-tap row branches sum directly instead of sliding, and the column
//!   accumulator is carried across output rows.

use rayon::prelude::*;

use super::border_interpolate_reflect101;
use crate::ml::document_scan::OpResult;
use crate::ml::document_scan::image::{ImageF32, ImageU8};

/// Writes `src_row` into `ext` surrounded by its `BORDER_REFLECT_101` columns,
/// so a tap can then be read as a contiguous slice. `ext_idx[j]` is the source
/// column of extended column `j`, and the `anchor` middle columns are the row
/// itself — copied in one block, because a per-column copy of one to three
/// elements costs more than the filtering it feeds.
fn extend_row<T: Copy>(
    src_row: &[T],
    ext_idx: &[usize],
    cn: usize,
    w: usize,
    anchor: usize,
    ext: &mut [T],
) {
    ext[anchor * cn..(anchor + w) * cn].copy_from_slice(src_row);
    for j in (0..anchor).chain(anchor + w..ext_idx.len()) {
        let sx = ext_idx[j];
        for c in 0..cn {
            ext[j * cn + c] = src_row[sx * cn + c];
        }
    }
}

/// Rows per rayon task: one band per worker, or the whole image when it is too
/// small for the split to pay for itself.
fn band_rows(pixels: usize, height: usize) -> usize {
    if pixels < 200_000 {
        return height;
    }
    (height / rayon::current_num_threads().max(1)).max(1)
}

// ---------------------------------------------------------------------------
// Gaussian blur
// ---------------------------------------------------------------------------

/// The fixed-point Gaussian taps for `sigma <= 0`: OpenCV's hard-coded
/// small-kernel table scaled by 2^8; taps sum to exactly 256.
fn fixed_gaussian_kernel(n: i32) -> OpResult<Vec<u32>> {
    if n <= 0 || n % 2 == 0 {
        return Err(format!(
            "gaussian_blur_u8: ksize must be positive and odd, got {n}"
        ));
    }
    Ok(match n {
        1 => vec![256],
        3 => vec![64, 128, 64],
        5 => vec![16, 64, 96, 64, 16],
        7 => vec![8, 28, 56, 72, 56, 28, 8],
        // Past the small-kernel table OpenCV derives taps from
        // sigma = 0.3*((n-1)*0.5 - 1) + 0.8. The pipeline never asks for
        // those sizes; the taps are derived in f64 and renormalized onto the
        // same total of 256.
        _ => {
            let sigma = ((n - 1) as f64 * 0.5 - 1.0) * 0.3 + 0.8;
            let scale2x = -0.5 / (sigma * sigma);
            let raw: Vec<f64> = (0..n)
                .map(|i| {
                    let x = i as f64 - (n - 1) as f64 * 0.5;
                    (scale2x * x * x).exp()
                })
                .collect();
            let total: f64 = raw.iter().sum();
            let mut taps: Vec<u32> = raw
                .iter()
                .map(|v| (v / total * 256.0).round_ties_even() as u32)
                .collect();
            let rounded: u32 = taps.iter().sum();
            let mid = (n / 2) as usize;
            taps[mid] = taps[mid] + 256 - rounded;
            taps
        }
    })
}

/// `cv::GaussianBlur(src, dst, Size(k, k), 0, 0, BORDER_DEFAULT)`.
pub(crate) fn gaussian_blur_u8(src: &ImageU8, ksize: i32) -> OpResult<ImageU8> {
    // A one-pixel axis collapses its kernel: BORDER_DEFAULT is not
    // BORDER_CONSTANT, so `GaussianBlur` takes that shortcut.
    let kw = if src.width == 1 { 1 } else { ksize };
    let kh = if src.height == 1 { 1 } else { ksize };
    if kw == 1 && kh == 1 {
        return Ok(src.clone());
    }
    let kx = fixed_gaussian_kernel(kw)?;
    let ky = fixed_gaussian_kernel(kh)?;

    let cn = src.channels as usize;
    let (w, h) = (src.width as usize, src.height as usize);
    let (ax, ay) = ((kw / 2) as i64, (kh / 2) as i64);
    let row_len = w * cn;

    // The two passes are fused over a ring of `kh` horizontal rows: the whole
    // working set of an output row is a few kilobytes. Horizontal sums fit in
    // u16 (the taps total 256), the vertical accumulator needs u32.
    let ext_idx: Vec<usize> = (0..w + kw as usize - 1)
        .map(|j| border_interpolate_reflect101(j as i64 - ax, src.width) as usize)
        .collect();
    let ext_len = ext_idx.len() * cn;
    let kh_rows = kh as usize;

    let band = |b: usize, band_rows: usize, out_band: &mut [u8]| {
        let mut ring = vec![0u16; row_len * kh_rows];
        let mut cached: Vec<usize> = vec![usize::MAX; kh_rows];
        let mut ext = vec![0u8; ext_len];
        let mut acc = vec![0u32; row_len];
        for (i, dst_row) in out_band.chunks_mut(row_len).enumerate() {
            let y = b * band_rows + i;
            for (t, &tap) in ky.iter().enumerate() {
                let sy =
                    border_interpolate_reflect101(y as i64 + t as i64 - ay, src.height) as usize;
                let slot = sy % kh_rows;
                let row = &mut ring[slot * row_len..(slot + 1) * row_len];
                if cached[slot] != sy {
                    let src_row = &src.data[sy * row_len..(sy + 1) * row_len];
                    extend_row(src_row, &ext_idx, cn, w, ax as usize, &mut ext);
                    for (t, &tap) in kx.iter().enumerate() {
                        let tap = tap as u16;
                        let shifted = &ext[t * cn..t * cn + row_len];
                        if t == 0 {
                            for (o, &v) in row.iter_mut().zip(shifted.iter()) {
                                *o = tap * v as u16;
                            }
                        } else {
                            for (o, &v) in row.iter_mut().zip(shifted.iter()) {
                                *o += tap * v as u16;
                            }
                        }
                    }
                    cached[slot] = sy;
                }
                if t == 0 {
                    for (a, &v) in acc.iter_mut().zip(row.iter()) {
                        *a = tap * v as u32;
                    }
                } else {
                    for (a, &v) in acc.iter_mut().zip(row.iter()) {
                        *a += tap * v as u32;
                    }
                }
            }
            for (d, &a) in dst_row.iter_mut().zip(acc.iter()) {
                *d = ((a + (1 << 15)) >> 16).min(255) as u8;
            }
        }
    };

    let mut out = vec![0u8; row_len * h];
    let band_height = band_rows(w * h, h);
    if band_height >= h {
        band(0, h, &mut out);
    } else {
        out.par_chunks_mut(row_len * band_height)
            .enumerate()
            .for_each(|(b, out_band)| band(b, band_height, out_band));
    }
    ImageU8::new(src.width, src.height, src.channels, out)
}

// ---------------------------------------------------------------------------
// Box filter
// ---------------------------------------------------------------------------

/// `RowSum<float, double>::operator()` on one border-extended source row.
fn row_sum(ext: &[f32], out: &mut [f64], w: usize, cn: usize, kw: usize) {
    let width = (w - 1) * cn;
    match kw {
        3 => {
            for (i, o) in out.iter_mut().enumerate().take(width + cn) {
                *o = ext[i] as f64 + ext[i + cn] as f64 + ext[i + cn * 2] as f64;
            }
        }
        5 => {
            for (i, o) in out.iter_mut().enumerate().take(width + cn) {
                *o = ext[i] as f64
                    + ext[i + cn] as f64
                    + ext[i + cn * 2] as f64
                    + ext[i + cn * 3] as f64
                    + ext[i + cn * 4] as f64;
            }
        }
        _ => {
            let ksz_cn = kw * cn;
            for k in 0..cn {
                let mut s = 0.0f64;
                let mut i = 0;
                while i < ksz_cn {
                    s += ext[k + i] as f64;
                    i += cn;
                }
                out[k] = s;
                let mut i = 0;
                while i < width {
                    s += ext[k + i + ksz_cn] as f64 - ext[k + i] as f64;
                    out[k + i + cn] = s;
                    i += cn;
                }
            }
        }
    }
}

/// `cv::boxFilter(src, dst, -1, Size(kw, kh), Point(-1, -1), true, BORDER_DEFAULT)`.
pub(crate) fn box_filter_f32(
    src: &ImageF32,
    kernel_width: i32,
    kernel_height: i32,
) -> OpResult<ImageF32> {
    if kernel_width <= 0 || kernel_height <= 0 {
        return Err(format!(
            "box_filter_f32: invalid kernel {kernel_width}x{kernel_height}"
        ));
    }
    let cn = src.channels as usize;
    let (w, h) = (src.width as usize, src.height as usize);
    let (kw, kh) = (kernel_width as usize, kernel_height as usize);
    let (ax, ay) = ((kernel_width / 2) as i64, (kernel_height / 2) as i64);
    let row_len = w * cn;
    let scale = 1.0 / (kernel_width as f64 * kernel_height as f64);

    let ext_idx: Vec<usize> = (0..w + kw - 1)
        .map(|j| border_interpolate_reflect101(j as i64 - ax, src.width) as usize)
        .collect();
    let mut ext = vec![0.0f32; (w + kw - 1) * cn];

    let data = &src.data;
    let height = src.height;
    let fill = |t: usize, ext: &mut [f32], buf: &mut [f64]| {
        let sy = border_interpolate_reflect101(t as i64 - ay, height) as usize;
        let src_row = &data[sy * row_len..(sy + 1) * row_len];
        extend_row(src_row, &ext_idx, cn, w, ax as usize, ext);
        row_sum(ext, buf, w, cn, kw);
    };

    // Ring of `kh` row sums. Step `y` adds virtual row `y + kh - 1` and drops
    // virtual row `y`, so the slot written is the one freed at step `y - 1`.
    let mut ring: Vec<Vec<f64>> = (0..kh).map(|_| vec![0.0f64; row_len]).collect();
    let mut scratch = vec![0.0f64; row_len];
    let mut sum = vec![0.0f64; row_len];
    for t in 0..kh - 1 {
        let slot = &mut ring[t % kh];
        fill(t, &mut ext, slot);
        for (s, v) in sum.iter_mut().zip(slot.iter()) {
            *s += *v;
        }
    }

    let mut out = vec![0.0f32; row_len * h];
    for y in 0..h {
        fill(y + kh - 1, &mut ext, &mut scratch);
        let dst_row = &mut out[y * row_len..(y + 1) * row_len];
        if kh == 1 {
            for i in 0..row_len {
                let s = sum[i] + scratch[i];
                dst_row[i] = (s * scale) as f32;
                sum[i] = s - scratch[i];
            }
        } else {
            let old = &ring[y % kh];
            for i in 0..row_len {
                let s = sum[i] + scratch[i];
                dst_row[i] = (s * scale) as f32;
                sum[i] = s - old[i];
            }
            std::mem::swap(&mut ring[(y + kh - 1) % kh], &mut scratch);
        }
    }
    ImageF32::new(src.width, src.height, src.channels, out)
}
