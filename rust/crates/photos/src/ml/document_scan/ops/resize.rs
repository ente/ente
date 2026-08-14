//! `cv::resize` for `INTER_LINEAR`, `INTER_AREA` and `INTER_CUBIC`.
//!
//! The three paths OpenCV can take are all reproduced, because they round
//! differently:
//!
//! * the **generic separable** path (`INTER_LINEAR`, `INTER_CUBIC`, and
//!   `INTER_AREA` when the image grows) builds per-column and per-row
//!   coefficient tables from half-pixel centres, quantised to
//!   `INTER_RESIZE_COEF_SCALE = 2048` for 8-bit input. The 8-bit vertical
//!   pass is the hand-shifted `(((b*(S>>4))>>16) + ... + 2) >> 2` expression,
//!   not a rounded float; the cubic one rounds through float.
//! * the **area-fast** path, taken only when both scale factors are integral,
//!   sums whole source blocks and divides by the block area.
//! * the **general area** path, which builds decimation tables and
//!   accumulates rows in `float`.
//!
//! Both scale factors come from `1.0 / ((double)dst / src)`, which is not the
//! same double as `src / dst`; half-pixel cases are sensitive to that.

use rayon::prelude::*;

use super::{cv_ceil_f64, cv_floor_f64, saturate_i16_f32, saturate_u8_f32};
use crate::ml::document_scan::OpResult;
use crate::ml::document_scan::image::{Image, ImageF32, ImageRef, ImageU8};

const INTER_RESIZE_COEF_SCALE: i32 = 2048;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub(crate) enum Interp {
    Linear,
    Area,
    Cubic,
}

/// `interpolateCubic` with `A = -0.75`. Every multiply-add is fused, because
/// OpenCV's compiler contracts these expressions and the coefficients are
/// then quantised to a `short`: a one-ULP difference in a coefficient flips
/// the quantised tap often enough to be visible in the output.
fn interpolate_cubic(x: f32) -> [f32; 4] {
    const A: f32 = -0.75;
    let x1 = x + 1.0;
    let y = 1.0 - x;
    let c0 = A
        .mul_add(x1, -5.0 * A)
        .mul_add(x1, 8.0 * A)
        .mul_add(x1, -4.0 * A);
    let c1 = (A + 2.0).mul_add(x, -(A + 3.0)) * x;
    let c1 = c1.mul_add(x, 1.0);
    let c2 = (A + 2.0).mul_add(y, -(A + 3.0)) * y;
    let c2 = c2.mul_add(y, 1.0);
    let c3 = 1.0 - c0 - c1 - c2;
    [c0, c1, c2, c3]
}

fn coefficients(interp: Interp, f: f32) -> [f32; 4] {
    match interp {
        Interp::Cubic => interpolate_cubic(f),
        _ => [1.0 - f, f, 0.0, 0.0],
    }
}

/// Clamp into `[0, len - 1]`.
fn clip(x: i32, len: i32) -> i32 {
    if x >= 0 {
        if x < len { x } else { len - 1 }
    } else {
        0
    }
}

struct XTable {
    /// Source offsets in channel-expanded units, one per destination column.
    xofs: Vec<i32>,
    /// `ksize` coefficients per destination column, replicated per channel.
    alpha: Vec<f32>,
    xmin: i32,
    xmax: i32,
}

fn build_x_table(
    src_width: i32,
    dst_width: i32,
    cn: i32,
    scale_x: f64,
    inv_scale_x: f64,
    interp: Interp,
    ksize: i32,
) -> XTable {
    let area_mode = interp == Interp::Area;
    let ksize2 = ksize / 2;
    let mut xofs = vec![0i32; (dst_width * cn) as usize];
    let mut alpha = vec![0.0f32; (dst_width * cn * ksize) as usize];
    let mut xmin = 0;
    let mut xmax = dst_width;

    for dx in 0..dst_width {
        let (mut sx, mut fx);
        if !area_mode {
            let f = ((dx as f64 + 0.5) * scale_x - 0.5) as f32;
            sx = cv_floor_f64(f as f64) as i32;
            fx = f - sx as f32;
        } else {
            sx = cv_floor_f64(dx as f64 * scale_x) as i32;
            let f = ((dx + 1) as f64 - (sx + 1) as f64 * inv_scale_x) as f32;
            fx = if f <= 0.0 { 0.0 } else { f - f.floor() };
        }

        // The border fixups are skipped for INTER_CUBIC: its horizontal pass
        // clamps taps itself, so the true coefficients (which extrapolate
        // past the edge) are kept.
        let clamp_ends = interp != Interp::Cubic;
        if sx < ksize2 - 1 {
            xmin = dx + 1;
            if sx < 0 && clamp_ends {
                fx = 0.0;
                sx = 0;
            }
        }
        if sx + ksize2 >= src_width {
            xmax = xmax.min(dx);
            if sx >= src_width - 1 && clamp_ends {
                fx = 0.0;
                sx = src_width - 1;
            }
        }

        let base = sx * cn;
        for k in 0..cn {
            xofs[(dx * cn + k) as usize] = base + k;
        }
        let cbuf = coefficients(interp, fx);
        let row = (dx * cn * ksize) as usize;
        alpha[row..row + ksize as usize].copy_from_slice(&cbuf[..ksize as usize]);
        for k in ksize as usize..(cn * ksize) as usize {
            alpha[row + k] = alpha[row + k - ksize as usize];
        }
    }
    XTable {
        xofs,
        alpha,
        xmin,
        xmax,
    }
}

fn build_y_table(
    dst_height: i32,
    scale_y: f64,
    inv_scale_y: f64,
    interp: Interp,
    ksize: i32,
) -> (Vec<i32>, Vec<f32>) {
    let area_mode = interp == Interp::Area;
    let mut yofs = vec![0i32; dst_height as usize];
    let mut beta = vec![0.0f32; (dst_height * ksize) as usize];
    for dy in 0..dst_height {
        let (sy, fy);
        if !area_mode {
            let f = ((dy as f64 + 0.5) * scale_y - 0.5) as f32;
            sy = cv_floor_f64(f as f64) as i32;
            fy = f - sy as f32;
        } else {
            sy = cv_floor_f64(dy as f64 * scale_y) as i32;
            let f = ((dy + 1) as f64 - (sy + 1) as f64 * inv_scale_y) as f32;
            fy = if f <= 0.0 { 0.0 } else { f - f.floor() };
        }
        yofs[dy as usize] = sy;
        let cbuf = coefficients(interp, fy);
        let row = (dy * ksize) as usize;
        beta[row..row + ksize as usize].copy_from_slice(&cbuf[..ksize as usize]);
    }
    (yofs, beta)
}

// ---------------------------------------------------------------------------
// Generic separable path
// ---------------------------------------------------------------------------

/// The horizontal pass for one source row, 8-bit input.
#[allow(clippy::too_many_arguments)]
fn hresize_u8(
    src_row: &[u8],
    out: &mut [i32],
    table: &XTable,
    ialpha: &[i16],
    cn: i32,
    swidth_e: i32,
    dwidth_e: i32,
    ksize: i32,
) {
    let cn = cn as usize;
    if ksize == 2 {
        let xmax = (table.xmax * cn as i32) as usize;
        for dx in 0..xmax {
            let sx = table.xofs[dx] as usize;
            let a0 = ialpha[dx * 2] as i32;
            let a1 = ialpha[dx * 2 + 1] as i32;
            out[dx] = src_row[sx] as i32 * a0 + src_row[sx + cn] as i32 * a1;
        }
        for dx in xmax..dwidth_e as usize {
            out[dx] = src_row[table.xofs[dx] as usize] as i32 * INTER_RESIZE_COEF_SCALE;
        }
        return;
    }
    // Cubic: the tail taps are clamped by stepping whole pixels, which is
    // what OpenCV does for its out-of-image columns.
    let mut dx = 0usize;
    let mut limit = (table.xmin * cn as i32) as usize;
    loop {
        while dx < limit {
            let sx = table.xofs[dx] - cn as i32;
            let mut v = 0i32;
            for j in 0..4 {
                let mut sxj = sx + j * cn as i32;
                if sxj < 0 || sxj >= swidth_e {
                    while sxj < 0 {
                        sxj += cn as i32;
                    }
                    while sxj >= swidth_e {
                        sxj -= cn as i32;
                    }
                }
                v = v.wrapping_add(
                    (src_row[sxj as usize] as i32).wrapping_mul(ialpha[dx * 4 + j as usize] as i32),
                );
            }
            out[dx] = v;
            dx += 1;
        }
        if limit == dwidth_e as usize {
            break;
        }
        let xmax = (table.xmax * cn as i32) as usize;
        while dx < xmax {
            let sx = table.xofs[dx] as usize;
            let a = &ialpha[dx * 4..dx * 4 + 4];
            out[dx] = (src_row[sx - cn] as i32)
                .wrapping_mul(a[0] as i32)
                .wrapping_add((src_row[sx] as i32).wrapping_mul(a[1] as i32))
                .wrapping_add((src_row[sx + cn] as i32).wrapping_mul(a[2] as i32))
                .wrapping_add((src_row[sx + cn * 2] as i32).wrapping_mul(a[3] as i32));
            dx += 1;
        }
        limit = dwidth_e as usize;
    }
}

fn hresize_f32(
    src_row: &[f32],
    out: &mut [f32],
    table: &XTable,
    cn: i32,
    swidth_e: i32,
    dwidth_e: i32,
    ksize: i32,
) {
    let alpha = &table.alpha;
    let cn = cn as usize;
    if ksize == 2 {
        let xmax = (table.xmax * cn as i32) as usize;
        for dx in 0..xmax {
            let sx = table.xofs[dx] as usize;
            out[dx] = src_row[sx].mul_add(alpha[dx * 2], src_row[sx + cn] * alpha[dx * 2 + 1]);
        }
        for dx in xmax..dwidth_e as usize {
            out[dx] = src_row[table.xofs[dx] as usize];
        }
        return;
    }
    let mut dx = 0usize;
    let mut limit = (table.xmin * cn as i32) as usize;
    loop {
        while dx < limit {
            let sx = table.xofs[dx] - cn as i32;
            let mut v = 0.0f32;
            for j in 0..4 {
                let mut sxj = sx + j * cn as i32;
                if sxj < 0 || sxj >= swidth_e {
                    while sxj < 0 {
                        sxj += cn as i32;
                    }
                    while sxj >= swidth_e {
                        sxj -= cn as i32;
                    }
                }
                v += src_row[sxj as usize] * alpha[dx * 4 + j as usize];
            }
            out[dx] = v;
            dx += 1;
        }
        if limit == dwidth_e as usize {
            break;
        }
        let xmax = (table.xmax * cn as i32) as usize;
        while dx < xmax {
            let sx = table.xofs[dx] as usize;
            let a = &alpha[dx * 4..dx * 4 + 4];
            out[dx] = src_row[sx - cn].mul_add(
                a[0],
                src_row[sx].mul_add(
                    a[1],
                    src_row[sx + cn].mul_add(a[2], src_row[sx + cn * 2] * a[3]),
                ),
            );
            dx += 1;
        }
        limit = dwidth_e as usize;
    }
}

/// Row cache: the horizontal pass runs once per source row, whichever
/// destination rows need it.
struct RowCache<T> {
    entries: Vec<(i32, Vec<T>)>,
    spare: Vec<Vec<T>>,
}

impl<T: Copy + Default> RowCache<T> {
    fn new(ksize: usize) -> Self {
        Self {
            entries: Vec::with_capacity(ksize + 1),
            spare: Vec::with_capacity(ksize + 1),
        }
    }

    fn retain(&mut self, want: &[i32]) {
        let mut i = 0;
        while i < self.entries.len() {
            if want.contains(&self.entries[i].0) {
                i += 1;
            } else {
                let (_, buf) = self.entries.swap_remove(i);
                self.spare.push(buf);
            }
        }
    }

    fn get_or_insert(&mut self, sy: i32, len: usize, fill: impl FnOnce(&mut [T])) -> usize {
        if let Some(index) = self.entries.iter().position(|(s, _)| *s == sy) {
            return index;
        }
        let mut buf = self.spare.pop().unwrap_or_else(|| vec![T::default(); len]);
        buf.resize(len, T::default());
        fill(&mut buf);
        self.entries.push((sy, buf));
        self.entries.len() - 1
    }
}

#[allow(clippy::too_many_arguments)]
fn resize_generic_u8(
    src: &ImageU8,
    dst_width: i32,
    dst_height: i32,
    scale_x: f64,
    scale_y: f64,
    inv_scale_x: f64,
    inv_scale_y: f64,
    interp: Interp,
) -> OpResult<ImageU8> {
    let cn = src.channels;
    let ksize = if interp == Interp::Cubic { 4 } else { 2 };
    let ksize2 = ksize / 2;
    let table = build_x_table(
        src.width,
        dst_width,
        cn,
        scale_x,
        inv_scale_x,
        interp,
        ksize,
    );
    let (yofs, beta) = build_y_table(dst_height, scale_y, inv_scale_y, interp, ksize);

    let ialpha: Vec<i16> = table
        .alpha
        .iter()
        .map(|&v| saturate_i16_f32(v * INTER_RESIZE_COEF_SCALE as f32))
        .collect();
    let ibeta: Vec<i16> = beta
        .iter()
        .map(|&v| saturate_i16_f32(v * INTER_RESIZE_COEF_SCALE as f32))
        .collect();

    let swidth_e = src.width * cn;
    let dwidth_e = dst_width * cn;
    let src_row_len = swidth_e as usize;
    let mut out = vec![0u8; (dwidth_e * dst_height) as usize];
    let mut cache: RowCache<i32> = RowCache::new(ksize as usize);

    for dy in 0..dst_height {
        let sy0 = yofs[dy as usize];
        let want: Vec<i32> = (0..ksize)
            .map(|k| clip(sy0 - ksize2 + 1 + k, src.height))
            .collect();
        cache.retain(&want);
        let mut slots = [0usize; 4];
        for (k, &sy) in want.iter().enumerate() {
            slots[k] = cache.get_or_insert(sy, dwidth_e as usize, |buf| {
                let row = &src.data[sy as usize * src_row_len..(sy as usize + 1) * src_row_len];
                hresize_u8(row, buf, &table, &ialpha, cn, swidth_e, dwidth_e, ksize);
            });
        }

        let b = &ibeta[(dy * ksize) as usize..(dy * ksize + ksize) as usize];
        let dst_row = &mut out[(dy * dwidth_e) as usize..(dy * dwidth_e + dwidth_e) as usize];
        if ksize == 2 {
            let (b0, b1) = (b[0] as i32, b[1] as i32);
            let (s0, s1) = (&cache.entries[slots[0]].1, &cache.entries[slots[1]].1);
            for (x, d) in dst_row.iter_mut().enumerate() {
                *d = ((((b0 * (s0[x] >> 4)) >> 16) + ((b1 * (s1[x] >> 4)) >> 16) + 2) >> 2) as u8;
            }
        } else {
            // The 8-bit cubic column pass leaves fixed point: the
            // coefficients are pre-scaled to `float` and the four taps
            // accumulate innermost first through fused multiply-adds, then
            // round to nearest even.
            let s: Vec<&Vec<i32>> = slots.iter().map(|&i| &cache.entries[i].1).collect();
            let scale = 1.0f32 / (INTER_RESIZE_COEF_SCALE as f32 * INTER_RESIZE_COEF_SCALE as f32);
            let bf = [
                b[0] as f32 * scale,
                b[1] as f32 * scale,
                b[2] as f32 * scale,
                b[3] as f32 * scale,
            ];
            for (x, d) in dst_row.iter_mut().enumerate() {
                let acc = (s[0][x] as f32).mul_add(
                    bf[0],
                    (s[1][x] as f32).mul_add(
                        bf[1],
                        (s[2][x] as f32).mul_add(bf[2], s[3][x] as f32 * bf[3]),
                    ),
                );
                *d = saturate_u8_f32(acc);
            }
        }
    }
    ImageU8::new(dst_width, dst_height, cn, out)
}

#[allow(clippy::too_many_arguments)]
fn resize_generic_f32(
    src: &ImageF32,
    dst_width: i32,
    dst_height: i32,
    scale_x: f64,
    scale_y: f64,
    inv_scale_x: f64,
    inv_scale_y: f64,
    interp: Interp,
) -> OpResult<ImageF32> {
    let cn = src.channels;
    let ksize = if interp == Interp::Cubic { 4 } else { 2 };
    let ksize2 = ksize / 2;
    let table = build_x_table(
        src.width,
        dst_width,
        cn,
        scale_x,
        inv_scale_x,
        interp,
        ksize,
    );
    let (yofs, beta) = build_y_table(dst_height, scale_y, inv_scale_y, interp, ksize);

    let swidth_e = src.width * cn;
    let dwidth_e = dst_width * cn;
    let src_row_len = swidth_e as usize;
    let mut out = vec![0.0f32; (dwidth_e * dst_height) as usize];
    let mut cache: RowCache<f32> = RowCache::new(ksize as usize);

    for dy in 0..dst_height {
        let sy0 = yofs[dy as usize];
        let want: Vec<i32> = (0..ksize)
            .map(|k| clip(sy0 - ksize2 + 1 + k, src.height))
            .collect();
        cache.retain(&want);
        let mut slots = [0usize; 4];
        for (k, &sy) in want.iter().enumerate() {
            slots[k] = cache.get_or_insert(sy, dwidth_e as usize, |buf| {
                let row = &src.data[sy as usize * src_row_len..(sy as usize + 1) * src_row_len];
                hresize_f32(row, buf, &table, cn, swidth_e, dwidth_e, ksize);
            });
        }

        let b = &beta[(dy * ksize) as usize..(dy * ksize + ksize) as usize];
        let dst_row = &mut out[(dy * dwidth_e) as usize..(dy * dwidth_e + dwidth_e) as usize];
        if ksize == 2 {
            let (s0, s1) = (&cache.entries[slots[0]].1, &cache.entries[slots[1]].1);
            for (x, d) in dst_row.iter_mut().enumerate() {
                *d = s0[x].mul_add(b[0], s1[x] * b[1]);
            }
        } else {
            let s: Vec<&Vec<f32>> = slots.iter().map(|&i| &cache.entries[i].1).collect();
            for (x, d) in dst_row.iter_mut().enumerate() {
                *d = s[0][x].mul_add(
                    b[0],
                    s[1][x].mul_add(b[1], s[2][x].mul_add(b[2], s[3][x] * b[3])),
                );
            }
        }
    }
    ImageF32::new(dst_width, dst_height, cn, out)
}

// ---------------------------------------------------------------------------
// INTER_AREA, integral scale factors
// ---------------------------------------------------------------------------

fn area_fast_offsets(
    src_width: i32,
    dst_width: i32,
    cn: i32,
    iscale_x: i32,
    iscale_y: i32,
) -> (Vec<i32>, Vec<i32>) {
    let srcstep = src_width * cn;
    let mut ofs = Vec::with_capacity((iscale_x * iscale_y) as usize);
    for sy in 0..iscale_y {
        for sx in 0..iscale_x {
            ofs.push(sy * srcstep + sx * cn);
        }
    }
    let mut xofs = vec![0i32; (dst_width * cn) as usize];
    for dx in 0..dst_width {
        let j = dx * cn;
        let sx = iscale_x * j;
        for k in 0..cn {
            xofs[(j + k) as usize] = sx + k;
        }
    }
    (ofs, xofs)
}

/// Sample type of a resized plane, with the accumulator OpenCV's area paths
/// use for it: `int` for 8-bit, `float` for float input. The general area
/// path always accumulates in `float`.
trait Sample: Copy + Default + Send + Sync {
    type Acc: Copy + Default + std::ops::Add<Output = Self::Acc>;
    fn widen(self) -> Self::Acc;
    fn acc_f32(acc: Self::Acc) -> f32;
    fn to_f32(self) -> f32;
    fn from_f32(v: f32) -> Self;
    /// `(sum + area/2) / area`: the integer rounding the 8-bit 2x2 block path
    /// uses instead of `cvRound(sum / area)`. Only ever selected for `u8`.
    fn block_mean_half_up(acc: Self::Acc, area: i32) -> Self;
}

impl Sample for u8 {
    type Acc = i32;
    fn widen(self) -> i32 {
        self as i32
    }
    fn acc_f32(acc: i32) -> f32 {
        acc as f32
    }
    fn to_f32(self) -> f32 {
        self as f32
    }
    fn from_f32(v: f32) -> u8 {
        saturate_u8_f32(v)
    }
    fn block_mean_half_up(acc: i32, area: i32) -> u8 {
        ((acc + area / 2) / area).clamp(0, 255) as u8
    }
}

impl Sample for f32 {
    type Acc = f32;
    fn widen(self) -> f32 {
        self
    }
    fn acc_f32(acc: f32) -> f32 {
        acc
    }
    fn to_f32(self) -> f32 {
        self
    }
    fn from_f32(v: f32) -> f32 {
        v
    }
    fn block_mean_half_up(acc: f32, area: i32) -> f32 {
        acc / area as f32
    }
}

/// Whole source blocks, taken only when both scale factors are integral.
///
/// `half_up` selects the block-averaging rounding: the 8-bit 2x2 case rounds
/// halves away from zero (`(sum + 2) >> 2`), every other case goes through
/// `saturate_cast` and therefore rounds halves to even.
#[allow(clippy::too_many_arguments)]
fn area_fast<T: Sample>(
    data: &[T],
    src_width: i32,
    src_height: i32,
    cn: i32,
    dst_width: i32,
    dst_height: i32,
    iscale_x: i32,
    iscale_y: i32,
    half_up: bool,
) -> Vec<T> {
    let area = iscale_x * iscale_y;
    let scale = 1.0f32 / area as f32;
    let (ofs, xofs) = area_fast_offsets(src_width, dst_width, cn, iscale_x, iscale_y);
    let swidth_e = src_width * cn;
    let dwidth_e = dst_width * cn;
    let dwidth1 = (src_width / iscale_x) * cn;
    let mut out = vec![T::default(); (dwidth_e * dst_height) as usize];

    for dy in 0..dst_height {
        let sy0 = dy * iscale_y;
        let row_start = (dy * dwidth_e) as usize;
        if sy0 >= src_height {
            continue;
        }
        let w = if sy0 + iscale_y <= src_height {
            dwidth1
        } else {
            0
        };
        let base = (sy0 * swidth_e) as usize;
        for dx in 0..w as usize {
            let s = base + xofs[dx] as usize;
            let mut sum = T::Acc::default();
            let mut k = 0usize;
            while k + 4 <= area as usize {
                sum = sum
                    + data[s + ofs[k] as usize].widen()
                    + data[s + ofs[k + 1] as usize].widen()
                    + data[s + ofs[k + 2] as usize].widen()
                    + data[s + ofs[k + 3] as usize].widen();
                k += 4;
            }
            while k < area as usize {
                sum = sum + data[s + ofs[k] as usize].widen();
                k += 1;
            }
            out[row_start + dx] = if half_up {
                T::block_mean_half_up(sum, area)
            } else {
                T::from_f32(T::acc_f32(sum) * scale)
            };
        }
        for dx in w as usize..dwidth_e as usize {
            let sx0 = xofs[dx];
            let mut sum = T::Acc::default();
            let mut count = 0i32;
            for sy in 0..iscale_y {
                if sy0 + sy >= src_height {
                    break;
                }
                let row = ((sy0 + sy) * swidth_e + sx0) as usize;
                let mut sx = 0;
                while sx < iscale_x * cn {
                    if sx0 + sx >= swidth_e {
                        break;
                    }
                    sum = sum + data[row + sx as usize].widen();
                    count += 1;
                    sx += cn;
                }
            }
            out[row_start + dx] = if count == 0 {
                T::default()
            } else {
                T::from_f32(T::acc_f32(sum) / count as f32)
            };
        }
    }
    out
}

// ---------------------------------------------------------------------------
// INTER_AREA, fractional scale factors
// ---------------------------------------------------------------------------

#[derive(Clone, Copy)]
struct DecimateAlpha {
    di: i32,
    si: i32,
    alpha: f32,
}

fn compute_area_tab(ssize: i32, dsize: i32, cn: i32, scale: f64) -> Vec<DecimateAlpha> {
    let mut tab = Vec::new();
    for dx in 0..dsize {
        let fsx1 = dx as f64 * scale;
        let fsx2 = fsx1 + scale;
        let cell_width = scale.min(ssize as f64 - fsx1);

        let mut sx1 = cv_ceil_f64(fsx1) as i32;
        let mut sx2 = cv_floor_f64(fsx2) as i32;
        sx2 = sx2.min(ssize - 1);
        sx1 = sx1.min(sx2);

        if sx1 as f64 - fsx1 > 1e-3 {
            tab.push(DecimateAlpha {
                di: dx * cn,
                si: (sx1 - 1) * cn,
                alpha: ((sx1 as f64 - fsx1) / cell_width) as f32,
            });
        }
        for sx in sx1..sx2 {
            tab.push(DecimateAlpha {
                di: dx * cn,
                si: sx * cn,
                alpha: (1.0 / cell_width) as f32,
            });
        }
        if fsx2 - sx2 as f64 > 1e-3 {
            tab.push(DecimateAlpha {
                di: dx * cn,
                si: sx2 * cn,
                alpha: ((fsx2 - sx2 as f64).min(1.0).min(cell_width) / cell_width) as f32,
            });
        }
    }
    tab
}

/// Decimation tables plus a `float` row accumulator carried across the source
/// rows that feed one destination row.
#[allow(clippy::too_many_arguments)]
fn area_general<T: Sample>(
    data: &[T],
    src_width: i32,
    src_height: i32,
    cn: i32,
    dst_width: i32,
    dst_height: i32,
    scale_x: f64,
    scale_y: f64,
) -> Vec<T> {
    let xtab = compute_area_tab(src_width, dst_width, cn, scale_x);
    let ytab = compute_area_tab(src_height, dst_height, 1, scale_y);
    let swidth_e = src_width * cn;
    let dwidth_e = (dst_width * cn) as usize;
    let mut out = vec![T::default(); dwidth_e * dst_height as usize];

    // Which `ytab` entries feed each destination row. They are already
    // grouped and ordered by `di`, so a destination row's accumulation order
    // — the only thing that is not associative here — is untouched by
    // processing the rows in parallel.
    let mut spans: Vec<(usize, usize)> = vec![(0, 0); dst_height as usize];
    for (i, entry) in ytab.iter().enumerate() {
        let dy = entry.di as usize;
        let span = &mut spans[dy];
        if span.0 == span.1 {
            *span = (i, i + 1);
        } else {
            span.1 = i + 1;
        }
    }

    let band = (dst_height as usize / rayon::current_num_threads().max(1)).max(1);
    out.par_chunks_mut(dwidth_e * band)
        .enumerate()
        .for_each(|(b, out_band)| {
            let mut buf = vec![0.0f32; dwidth_e];
            let mut sum = vec![0.0f32; dwidth_e];
            for (i, out_row) in out_band.chunks_mut(dwidth_e).enumerate() {
                let (start, end) = spans[b * band + i];
                sum.iter_mut().for_each(|v| *v = 0.0);
                for entry in &ytab[start..end] {
                    let beta = entry.alpha;
                    let base = (entry.si * swidth_e) as usize;
                    buf.iter_mut().for_each(|v| *v = 0.0);
                    for t in &xtab {
                        let (di, si) = (t.di as usize, t.si as usize);
                        for c in 0..cn as usize {
                            buf[di + c] += data[base + si + c].to_f32() * t.alpha;
                        }
                    }
                    for dx in 0..dwidth_e {
                        sum[dx] += beta * buf[dx];
                    }
                }
                for (o, &s) in out_row.iter_mut().zip(sum.iter()) {
                    *o = T::from_f32(s);
                }
            }
        });
    out
}

// ---------------------------------------------------------------------------
// The single-channel INTER_LINEAR HAL path
// ---------------------------------------------------------------------------

/// OpenCV routes `INTER_LINEAR` through `cv_hal_resize` before its own code
/// runs, and the Arm HAL claims single-channel 8-bit planes for every scale
/// factor except a downscale of at most 2x in both axes. That HAL is a
/// different algorithm, not a faster spelling of the same one: coordinates
/// come from `f32` scale factors, the two taps are 7-bit weights obtained by
/// *truncating* `(1 - u) * 128`, and the passes run vertical-first through an
/// 8-bit temporary row.
fn linear_hal_applies(src: ImageRef<'_>, scale_x: f64, scale_y: f64, dw: i32, dh: i32) -> bool {
    let ImageRef::U8(img) = src else {
        return false;
    };
    img.channels == 1
        && img.width >= 8
        && img.height >= 2
        && dw >= 8
        && dh >= 8
        && (scale_x > 2.0 || scale_y > 2.0 || (scale_x < 1.0 && scale_y < 1.0))
}

/// Source index and 7-bit weight of the leading tap for each output position.
fn hal_taps(src_len: i32, dst_len: i32) -> Vec<(i32, i32)> {
    let ratio = (1.0 / (dst_len as f64 / src_len as f64)) as f32;
    (0..dst_len)
        .map(|j| {
            let f = (j as f32 + 0.5) * ratio - 0.5;
            let mut s = f.floor() as i32;
            let mut u = f - s as f32;
            if s < 0 {
                s = 0;
                u = 0.0;
            }
            if s >= src_len - 1 {
                s = src_len - 2;
                u = 1.0;
            }
            (s, ((1.0 - u) * 128.0) as i32)
        })
        .collect()
}

fn linear_hal_u8c1(src: &ImageU8, dst_width: i32, dst_height: i32) -> Vec<u8> {
    let (sw, sh) = (src.width, src.height);
    let tx = hal_taps(sw, dst_width);
    let ty = hal_taps(sh, dst_height);
    let mut out = vec![0u8; (dst_width * dst_height) as usize];
    let mut row = vec![0i32; sw as usize];
    for dy in 0..dst_height {
        let (sy, wy) = ty[dy as usize];
        let top = &src.data[(sy * sw) as usize..(sy * sw + sw) as usize];
        let bottom = &src.data[((sy + 1) * sw) as usize..((sy + 1) * sw + sw) as usize];
        for ((r, &a), &b) in row.iter_mut().zip(top.iter()).zip(bottom.iter()) {
            *r = (a as i32 * wy + b as i32 * (128 - wy) + 64) >> 7;
        }
        let dst = &mut out[(dy * dst_width) as usize..(dy * dst_width + dst_width) as usize];
        for (d, &(sx, wx)) in dst.iter_mut().zip(tx.iter()) {
            let a = row[sx as usize];
            let b = row[sx as usize + 1];
            *d = ((a * wx + b * (128 - wx) + 64) >> 7) as u8;
        }
    }
    out
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

pub(crate) fn resize(
    src: ImageRef<'_>,
    width: i32,
    height: i32,
    interp: Interp,
) -> OpResult<Image> {
    let (sw, sh) = src.size();
    if width <= 0 || height <= 0 {
        return Err(format!("resize: invalid destination size {width}x{height}"));
    }
    if width == sw && height == sh {
        return Ok(match src {
            ImageRef::U8(i) => Image::U8(i.clone()),
            ImageRef::F32(i) => Image::F32(i.clone()),
        });
    }

    let inv_scale_x = width as f64 / sw as f64;
    let inv_scale_y = height as f64 / sh as f64;
    let scale_x = 1.0 / inv_scale_x;
    let scale_y = 1.0 / inv_scale_y;

    if interp == Interp::Area && scale_x >= 1.0 && scale_y >= 1.0 {
        let iscale_x = scale_x.round_ties_even() as i32;
        let iscale_y = scale_y.round_ties_even() as i32;
        let is_area_fast = (scale_x - iscale_x as f64).abs() < f64::EPSILON
            && (scale_y - iscale_y as f64).abs() < f64::EPSILON;
        return Ok(match src {
            ImageRef::U8(s) => {
                let data = if is_area_fast {
                    // The 8-bit 2x2 block average rounds halves up for 1, 3
                    // and 4 channels (a HAL claim in OpenCV).
                    let half_up = iscale_x == 2 && iscale_y == 2 && matches!(s.channels, 1 | 3 | 4);
                    area_fast(
                        &s.data, s.width, s.height, s.channels, width, height, iscale_x, iscale_y,
                        half_up,
                    )
                } else {
                    area_general(
                        &s.data, s.width, s.height, s.channels, width, height, scale_x, scale_y,
                    )
                };
                Image::U8(ImageU8::new(width, height, s.channels, data)?)
            }
            ImageRef::F32(s) => {
                let data = if is_area_fast {
                    area_fast(
                        &s.data, s.width, s.height, s.channels, width, height, iscale_x, iscale_y,
                        false,
                    )
                } else {
                    area_general(
                        &s.data, s.width, s.height, s.channels, width, height, scale_x, scale_y,
                    )
                };
                Image::F32(ImageF32::new(width, height, s.channels, data)?)
            }
        });
    }

    if interp == Interp::Linear && linear_hal_applies(src, scale_x, scale_y, width, height) {
        let ImageRef::U8(s) = src else {
            unreachable!("the HAL path is single-channel 8-bit only")
        };
        let data = linear_hal_u8c1(s, width, height);
        return Ok(Image::U8(ImageU8::new(width, height, 1, data)?));
    }

    Ok(match src {
        ImageRef::U8(s) => Image::U8(resize_generic_u8(
            s,
            width,
            height,
            scale_x,
            scale_y,
            inv_scale_x,
            inv_scale_y,
            interp,
        )?),
        ImageRef::F32(s) => Image::F32(resize_generic_f32(
            s,
            width,
            height,
            scale_x,
            scale_y,
            inv_scale_x,
            inv_scale_y,
            interp,
        )?),
    })
}
