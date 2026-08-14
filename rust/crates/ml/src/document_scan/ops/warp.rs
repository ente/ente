//! `cv::getPerspectiveTransform` + `cv::warpPerspective(INTER_LINEAR,
//! BORDER_CONSTANT 0)`, folded into one operation.
//!
//! Three pieces are replicated exactly, not approximated:
//!
//! * the corner pairs are narrowed to `f32` first, then the 8x8 system is
//!   solved by OpenCV's own Gaussian-elimination `LUImpl` in `f64` — pivot
//!   order and the `-1/pivot` scaling included — and the 3x3 result is
//!   inverted with the analytic cofactor formula `cv::invert` uses for small
//!   matrices;
//! * the destination is walked in blocks and the projective coordinates are
//!   rebuilt from the block origin, so the last bit of every mapped
//!   coordinate depends on the block width;
//! * the map is quantised to `INTER_BITS = 5` and the bilinear weights are
//!   exactly `(32-i)*(32-j)*32` and friends, applied as
//!   `(acc + (1 << 14)) >> 15`.

use rayon::prelude::*;

use super::saturate_i32_f64;
use crate::document_scan::OpResult;
use crate::document_scan::image::ImageU8;

const INTER_BITS: i32 = 5;
const INTER_TAB_SIZE: i32 = 1 << INTER_BITS;
const INTER_REMAP_COEF_BITS: i32 = 15;

/// Gaussian elimination with partial pivoting (`eps = DBL_EPSILON`), solving
/// `a * x = b` in place. Returns false if singular.
fn lu_solve8(a: &mut [[f64; 8]; 8], b: &mut [f64; 8]) -> bool {
    let m = 8;
    for i in 0..m {
        let mut k = i;
        for j in i + 1..m {
            if a[j][i].abs() > a[k][i].abs() {
                k = j;
            }
        }
        if a[k][i].abs() < f64::EPSILON {
            return false;
        }
        if k != i {
            // OpenCV swaps only columns `i..m`; the earlier ones are never
            // read again, so exchanging whole rows is the same computation.
            a.swap(i, k);
            b.swap(i, k);
        }
        let d = -1.0 / a[i][i];
        for j in i + 1..m {
            let alpha = a[j][i] * d;
            for k in i + 1..m {
                a[j][k] += alpha * a[i][k];
            }
            b[j] += alpha * b[i];
        }
    }
    for i in (0..m).rev() {
        let mut s = b[i];
        for (coeff, x) in a[i].iter().zip(b.iter()).skip(i + 1) {
            s -= coeff * x;
        }
        b[i] = s / a[i][i];
    }
    true
}

/// `cv::getPerspectiveTransform(src, dst, DECOMP_LU)` on `f32` corner pairs.
fn perspective_transform(src: [(f32, f32); 4], dst: [(f32, f32); 4]) -> OpResult<[f64; 9]> {
    let mut a = [[0.0f64; 8]; 8];
    let mut b = [0.0f64; 8];
    for i in 0..4 {
        let (sx, sy) = (src[i].0 as f64, src[i].1 as f64);
        let (dx, dy) = (dst[i].0 as f64, dst[i].1 as f64);
        a[i][0] = sx;
        a[i + 4][3] = sx;
        a[i][1] = sy;
        a[i + 4][4] = sy;
        a[i][2] = 1.0;
        a[i + 4][5] = 1.0;
        a[i][6] = -sx * dx;
        a[i][7] = -sy * dx;
        a[i + 4][6] = -sx * dy;
        a[i + 4][7] = -sy * dy;
        b[i] = dx;
        b[i + 4] = dy;
    }
    if !lu_solve8(&mut a, &mut b) {
        return Err("warp_perspective: the corner pairs are degenerate".to_string());
    }
    Ok([b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], 1.0])
}

/// The 3x3 branch of `cv::invert(DECOMP_LU)`: cofactors over `det3`.
fn invert3(m: &[f64; 9]) -> OpResult<[f64; 9]> {
    let d = m[0] * (m[4] * m[8] - m[5] * m[7]) - m[1] * (m[3] * m[8] - m[5] * m[6])
        + m[2] * (m[3] * m[7] - m[4] * m[6]);
    if d == 0.0 {
        return Err("warp_perspective: the transform is not invertible".to_string());
    }
    let t = [
        m[4] * m[8] - m[5] * m[7],
        m[2] * m[7] - m[1] * m[8],
        m[1] * m[5] - m[2] * m[4],
        m[5] * m[6] - m[3] * m[8],
        m[0] * m[8] - m[2] * m[6],
        m[2] * m[3] - m[0] * m[5],
        m[3] * m[7] - m[4] * m[6],
        m[1] * m[6] - m[0] * m[7],
        m[0] * m[4] - m[1] * m[3],
    ];
    let d = 1.0 / d;
    Ok(t.map(|v| v * d))
}

pub(crate) fn warp_perspective(
    src: &ImageU8,
    src_corners: [(f64, f64); 4],
    dst_corners: [(f64, f64); 4],
    width: i32,
    height: i32,
) -> OpResult<ImageU8> {
    if width <= 0 || height <= 0 {
        return Err(format!(
            "warp_perspective: invalid destination size {width}x{height}"
        ));
    }
    let narrow = |c: [(f64, f64); 4]| c.map(|(x, y)| (x as f32, y as f32));
    let forward = perspective_transform(narrow(src_corners), narrow(dst_corners))?;
    let m = invert3(&forward)?;

    let cn = src.channels as usize;
    let (sw, sh) = (src.width, src.height);
    let sstep = sw as usize * cn;
    let mut out = vec![0u8; width as usize * height as usize * cn];

    // OpenCV's block geometry. Only the block *width* reaches the arithmetic,
    // through the `x` origin the row start is built from, but it is derived
    // from both dimensions.
    const BLOCK_SZ: i32 = 32;
    let bh0 = (BLOCK_SZ / 2).min(height);
    let bw0 = (BLOCK_SZ * BLOCK_SZ / bh0).min(width);

    let width1 = (sw - 1).max(0);
    let height1 = (sh - 1).max(0);

    // Destination rows are independent: the block origin each row's
    // projective coordinates are rebuilt from depends only on (bx, dy).
    let row_len = width as usize * cn;
    out.par_chunks_mut(row_len)
        .enumerate()
        .for_each(|(dy, row)| {
            let dy = dy as i32;
            for bx in (0..width).step_by(bw0 as usize) {
                let bw = bw0.min(width - bx);
                let x0 = m[0] * bx as f64 + m[1] * dy as f64 + m[2];
                let y0 = m[3] * bx as f64 + m[4] * dy as f64 + m[5];
                let w0 = m[6] * bx as f64 + m[7] * dy as f64 + m[8];
                for x1 in 0..bw {
                    let w = w0 + m[6] * x1 as f64;
                    let w = if w != 0.0 {
                        INTER_TAB_SIZE as f64 / w
                    } else {
                        0.0
                    };
                    let fx = ((x0 + m[0] * x1 as f64) * w)
                        .max(i32::MIN as f64)
                        .min(i32::MAX as f64);
                    let fy = ((y0 + m[3] * x1 as f64) * w)
                        .max(i32::MIN as f64)
                        .min(i32::MAX as f64);
                    let xq = saturate_i32_f64(fx);
                    let yq = saturate_i32_f64(fy);
                    let sx = (xq >> INTER_BITS).clamp(i16::MIN as i32, i16::MAX as i32);
                    let sy = (yq >> INTER_BITS).clamp(i16::MIN as i32, i16::MAX as i32);
                    let fi = yq & (INTER_TAB_SIZE - 1);
                    let fj = xq & (INTER_TAB_SIZE - 1);
                    let w00 = (INTER_TAB_SIZE - fi) * (INTER_TAB_SIZE - fj) * INTER_TAB_SIZE;
                    let w01 = (INTER_TAB_SIZE - fi) * fj * INTER_TAB_SIZE;
                    let w10 = fi * (INTER_TAB_SIZE - fj) * INTER_TAB_SIZE;
                    let w11 = fi * fj * INTER_TAB_SIZE;

                    let dst = &mut row[((bx + x1) as usize) * cn..][..cn];
                    if (sx as u32) < width1 as u32 && (sy as u32) < height1 as u32 {
                        let base = sy as usize * sstep + sx as usize * cn;
                        for (c, d) in dst.iter_mut().enumerate() {
                            let acc = src.data[base + c] as i32 * w00
                                + src.data[base + cn + c] as i32 * w01
                                + src.data[base + sstep + c] as i32 * w10
                                + src.data[base + sstep + cn + c] as i32 * w11;
                            *d = ((acc + (1 << (INTER_REMAP_COEF_BITS - 1)))
                                >> INTER_REMAP_COEF_BITS)
                                .clamp(0, 255) as u8;
                        }
                    } else if sx >= sw || sx + 1 < 0 || sy >= sh || sy + 1 < 0 {
                        // Fully outside: BORDER_CONSTANT 0, which `out`
                        // already is.
                    } else {
                        let sample = |x: i32, y: i32, c: usize| -> i32 {
                            if x < 0 || y < 0 || x >= sw || y >= sh {
                                0
                            } else {
                                src.data[y as usize * sstep + x as usize * cn + c] as i32
                            }
                        };
                        for (c, d) in dst.iter_mut().enumerate() {
                            let acc = sample(sx, sy, c) * w00
                                + sample(sx + 1, sy, c) * w01
                                + sample(sx, sy + 1, c) * w10
                                + sample(sx + 1, sy + 1, c) * w11;
                            *d = ((acc + (1 << (INTER_REMAP_COEF_BITS - 1)))
                                >> INTER_REMAP_COEF_BITS)
                                .clamp(0, 255) as u8;
                        }
                    }
                }
            }
        });
    ImageU8::new(width, height, src.channels, out)
}
