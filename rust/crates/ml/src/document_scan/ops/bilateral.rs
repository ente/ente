//! `cv::bilateralFilter(src, dst, d, sigmaColor, sigmaSpace)` on `CV_8UC1` and
//! `CV_8UC3` with the default `BORDER_REFLECT_101`.
//!
//! OpenCV builds three tables and every one of them is part of the result:
//!
//! * the color weights `exp(i*i*gauss_color_coeff)` over `cn*256` entries.
//!   All but the last vector lane group come from OpenCV's *vectorised*
//!   `v_exp`, a cephes polynomial that lands one ULP away from `expf` on
//!   about one entry in ten, so it is reproduced here;
//! * the space weights `exp(r*r*gauss_space_coeff)`, where `r*r` is the square
//!   of `sqrt(i*i + j*j)` and not `i*i + j*j` — the round trip through the
//!   square root moves the argument;
//! * the offset table, whose scan order over `i, j` in `-radius..=radius`
//!   (skipping `sqrt(i*i + j*j) > radius`) *is* the order in which each output
//!   pixel's `float` numerator and denominator are accumulated.
//!
//! OpenCV walks a row in `BLOCK`-pixel vector iterations and finishes the
//! remainder scalar; the two differ in more than speed (the vector body uses
//! fused multiply-adds, and the 13-tap single-channel element is visited out
//! of table order), so both are reproduced.

use super::{border_interpolate_reflect101, saturate_i32_f64};
use crate::document_scan::OpResult;
use crate::document_scan::image::ImageU8;
use rayon::prelude::*;

/// Vector float lanes on the 128-bit baseline.
const LANES: usize = 4;
/// Pixels per vector iteration.
const BLOCK: usize = 16;

/// The cephes exponential OpenCV's `v_exp(v_float32)` evaluates, with the
/// fused multiply-adds the intrinsic emits.
fn v_exp_f32(x: f32) -> f32 {
    const C1: f32 = -0.693_359_4;
    const C2: f32 = 0.000_212_194_44;
    const P: [f32; 6] = [
        0.000_198_756_91,
        0.001_398_199_9,
        0.008_333_452,
        0.041_665_796,
        0.166_666_66,
        0.5,
    ];

    let mut x = x.clamp(-88.376_26, 89.0);
    let mut mm = std::f32::consts::LOG2_E.mul_add(x, 0.5).floor() as i32;
    let e = mm as f32;
    mm = (mm + 0x7f) << 23;
    x = e.mul_add(C1, x);
    x = e.mul_add(C2, x);
    let xx = x * x;
    let mut y = x.mul_add(P[0], P[1]);
    for p in &P[2..] {
        y = y.mul_add(x, *p);
    }
    y = y.mul_add(xx, x) + 1.0;
    y * f32::from_bits(mm as u32)
}

struct Plan {
    radius: usize,
    stride: usize,
    /// Border-extended source, `radius` pixels on every side.
    temp: Vec<u8>,
    color_weight: Vec<f32>,
    space_weight: Vec<f32>,
    /// Tap offsets, rebased so index `0` is the window's top-left corner.
    tap_ofs: Vec<usize>,
    /// Tap visiting order inside a vector iteration.
    vector_order: Vec<usize>,
}

fn plan(src: &ImageU8, d: i32, sigma_color: f64, sigma_space: f64) -> Plan {
    let cn = src.channels as usize;
    let (w, h) = (src.width as usize, src.height as usize);

    let gauss_color_coeff = (-0.5 / (sigma_color * sigma_color)) as f32;
    let gauss_space_coeff = (-0.5 / (sigma_space * sigma_space)) as f32;
    let radius = if d <= 0 {
        saturate_i32_f64(sigma_space * 1.5)
    } else {
        d / 2
    }
    .max(1) as usize;

    let stride = (w + 2 * radius) * cn;
    let mut temp = vec![0u8; stride * (h + 2 * radius)];
    let cols: Vec<usize> = (0..w + 2 * radius)
        .map(|x| border_interpolate_reflect101(x as i64 - radius as i64, src.width) as usize)
        .collect();
    temp.par_chunks_exact_mut(stride)
        .enumerate()
        .for_each(|(y, trow)| {
            let sy = border_interpolate_reflect101(y as i64 - radius as i64, src.height) as usize;
            let srow = &src.data[sy * w * cn..(sy + 1) * w * cn];
            for (x, &sx) in cols.iter().enumerate() {
                trow[x * cn..x * cn + cn].copy_from_slice(&srow[sx * cn..sx * cn + cn]);
            }
        });

    // `(float)(i*i)` is exact up to i = 4095, so only the exponential itself
    // separates the vectorised head of this table from its scalar last lanes.
    let entries = 256 * cn;
    let color_weight: Vec<f32> = (0..entries)
        .map(|i| {
            let arg = ((i * i) as f32) * gauss_color_coeff;
            if i + LANES < entries {
                v_exp_f32(arg)
            } else {
                arg.exp()
            }
        })
        .collect();

    let ir = radius as i64;
    let mut space_weight = Vec::new();
    let mut tap_ofs = Vec::new();
    for i in -ir..=ir {
        for j in -ir..=ir {
            let r = ((i * i + j * j) as f64).sqrt();
            if r > radius as f64 {
                continue;
            }
            space_weight.push(((r * r) * gauss_space_coeff as f64).exp() as f32);
            tap_ofs.push((i + ir) as usize * stride + (j + ir) as usize * cn);
        }
    }

    // The single-channel vector body unrolls a 5x5 element row by row rather
    // than tap by tap, which reorders the sum. Every other element size, and
    // every three-channel element, runs the taps in table order.
    let vector_order = if cn == 1 && space_weight.len() == 13 {
        vec![0, 12, 1, 2, 3, 9, 10, 11, 4, 5, 6, 7, 8]
    } else {
        (0..space_weight.len()).collect()
    };

    Plan {
        radius,
        stride,
        temp,
        color_weight,
        space_weight,
        tap_ofs,
        vector_order,
    }
}

/// One output row of a single-channel image. `win` spans the `2*radius + 1`
/// padded rows the row needs, `mid` is its centre line.
fn row_gray(p: &Plan, win: &[u8], mid: &[u8], head: usize, dst: &mut [u8]) {
    let lut = &p.color_weight[..];
    for (t, out) in dst[..head].chunks_exact_mut(BLOCK).enumerate() {
        let x0 = t * BLOCK;
        let mid: &[u8; BLOCK] = mid[x0..x0 + BLOCK].try_into().expect("block");
        let mut sum = [0.0f32; BLOCK];
        let mut wsum = [0.0f32; BLOCK];
        for &k in &p.vector_order {
            let ofs = p.tap_ofs[k] + x0;
            let tap: &[u8; BLOCK] = win[ofs..ofs + BLOCK].try_into().expect("block");
            let sw = p.space_weight[k];
            for i in 0..BLOCK {
                let val = tap[i];
                let w = sw * lut[(val as i32 - mid[i] as i32).unsigned_abs() as usize];
                wsum[i] += w;
                sum[i] = (val as f32).mul_add(w, sum[i]);
            }
        }
        for i in 0..BLOCK {
            out[i] = (sum[i] / wsum[i]).round_ties_even() as u8;
        }
    }

    // OpenCV's scalar tail: no fusion, and always table order.
    let n = dst.len() - head;
    let mut sum = [0.0f32; BLOCK];
    let mut wsum = [0.0f32; BLOCK];
    for (k, &sw) in p.space_weight.iter().enumerate() {
        let ofs = p.tap_ofs[k] + head;
        for i in 0..n {
            let val = win[ofs + i];
            let w = sw * lut[(val as i32 - mid[head + i] as i32).unsigned_abs() as usize];
            wsum[i] += w;
            sum[i] += val as f32 * w;
        }
    }
    for i in 0..n {
        dst[head + i] = (sum[i] / wsum[i]).round_ties_even() as u8;
    }
}

/// One output row of a three-channel image. The color distance is the L1
/// distance over the channels (hence the `cn*256`-entry table), and the
/// reciprocal of `wsum` is taken once and multiplied in.
fn row_bgr(p: &Plan, win: &[u8], mid: &[u8], head: usize, dst: &mut [u8]) {
    let lut = &p.color_weight[..];
    for (t, out) in dst[..head * 3].chunks_exact_mut(BLOCK * 3).enumerate() {
        let x0 = t * BLOCK * 3;
        let mid: &[u8; BLOCK * 3] = mid[x0..x0 + BLOCK * 3].try_into().expect("block");
        let mut sum = [0.0f32; BLOCK * 3];
        let mut wsum = [0.0f32; BLOCK];
        for &k in &p.vector_order {
            let ofs = p.tap_ofs[k] + x0;
            let tap: &[u8; BLOCK * 3] = win[ofs..ofs + BLOCK * 3].try_into().expect("block");
            let sw = p.space_weight[k];
            for i in 0..BLOCK {
                let idx = (tap[3 * i] as i32 - mid[3 * i] as i32).unsigned_abs()
                    + (tap[3 * i + 1] as i32 - mid[3 * i + 1] as i32).unsigned_abs()
                    + (tap[3 * i + 2] as i32 - mid[3 * i + 2] as i32).unsigned_abs();
                let w = sw * lut[idx as usize];
                wsum[i] += w;
                for c in 0..3 {
                    sum[3 * i + c] = (tap[3 * i + c] as f32).mul_add(w, sum[3 * i + c]);
                }
            }
        }
        for i in 0..BLOCK {
            let inv = 1.0f32 / wsum[i];
            for c in 0..3 {
                out[3 * i + c] = (sum[3 * i + c] * inv).round_ties_even() as u8;
            }
        }
    }

    let n = dst.len() / 3 - head;
    let mut sum = [0.0f32; BLOCK * 3];
    let mut wsum = [0.0f32; BLOCK];
    for (k, &sw) in p.space_weight.iter().enumerate() {
        let ofs = p.tap_ofs[k] + head * 3;
        for i in 0..n {
            let (b, g, r) = (win[ofs + 3 * i], win[ofs + 3 * i + 1], win[ofs + 3 * i + 2]);
            let m = &mid[(head + i) * 3..(head + i) * 3 + 3];
            let idx = (b as i32 - m[0] as i32).unsigned_abs()
                + (g as i32 - m[1] as i32).unsigned_abs()
                + (r as i32 - m[2] as i32).unsigned_abs();
            let w = sw * lut[idx as usize];
            wsum[i] += w;
            sum[3 * i] += b as f32 * w;
            sum[3 * i + 1] += g as f32 * w;
            sum[3 * i + 2] += r as f32 * w;
        }
    }
    for i in 0..n {
        let inv = 1.0f32 / wsum[i];
        for c in 0..3 {
            dst[(head + i) * 3 + c] = (sum[3 * i + c] * inv).round_ties_even() as u8;
        }
    }
}

/// `cv::bilateralFilter(src, dst, d, sigmaColor, sigmaSpace)`.
pub(crate) fn bilateral_filter_u8(
    src: &ImageU8,
    d: i32,
    sigma_color: f64,
    sigma_space: f64,
) -> OpResult<ImageU8> {
    let cn = src.channels as usize;
    if cn != 1 && cn != 3 {
        return Err(format!(
            "bilateral_filter_u8: only 1- and 3-channel images are supported, got {}",
            src.channels
        ));
    }
    if sigma_color <= 1e-6 || sigma_space <= 1e-6 {
        return Ok(src.clone());
    }

    let p = plan(src, d, sigma_color, sigma_space);
    let (w, h) = (src.width as usize, src.height as usize);
    let row_len = w * cn;
    let window = (2 * p.radius + 1) * p.stride;
    let centre = p.radius * p.stride + p.radius * cn;
    // Where the vector iterations stop and OpenCV's scalar tail begins.
    let head = w - w % BLOCK;
    let mut out = vec![0u8; row_len * h];

    out.par_chunks_exact_mut(row_len)
        .enumerate()
        .for_each(|(y, dst)| {
            let win = &p.temp[y * p.stride..y * p.stride + window];
            let mid = &win[centre..centre + row_len];
            if cn == 1 {
                row_gray(&p, win, mid, head, dst);
            } else {
                row_bgr(&p, win, mid, head, dst);
            }
        });

    ImageU8::new(src.width, src.height, src.channels, out)
}
