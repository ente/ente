//! `cv::cvtColor(COLOR_BGR2Lab)` and `cv::cvtColor(COLOR_Lab2BGR)` on
//! `CV_8UC3`.
//!
//! OpenCV's 8-bit Lab is bit-exact and never takes a float path: both
//! directions are table lookups plus fixed-point dot products, so all the
//! precision lives in the tables. They are recomputed here from the same
//! formulas, in the same arithmetic:
//!
//! * every table formula is evaluated in 32-bit float and rounded half to
//!   even;
//! * `cbrt` is OpenCV's own `f32_cbrt` soft-float approximation (a quartic
//!   rational with error under 2^-24, not a correctly rounded cube root). At
//!   the 2^15 table scale that one-ULP difference reaches the output, so it
//!   is reproduced instead of calling `f32::cbrt`;
//! * the gamma helpers use `powf` in f64; OpenCV rounds its soft-double `pow`
//!   result to `float` before the table rounding sees it, and double
//!   precision is well past that rounding step.

use std::sync::OnceLock;

use crate::ml::document_scan::OpResult;
use crate::ml::document_scan::image::ImageU8;

const LAB_SHIFT: i32 = 12;
const LAB_SHIFT2: i32 = 15;
const GAMMA_SHIFT: i32 = 3;
const INV_GAMMA_SHIFT: i32 = 12;
const INV_GAMMA_TAB_SIZE: usize = 1 << 12;
const LAB_CBRT_TAB_SIZE_B: usize = 256 * 3 / 2 * (1 << GAMMA_SHIFT);
const BASE_SHIFT: i32 = 14;
const LAB_BASE: i32 = 1 << BASE_SHIFT;
const LUT_BASE: i32 = 1 << 14;
const MIN_AB_VALUE: i32 = -8145;
const AB_TO_XZ_LEN: usize = (LAB_BASE as usize) * 9 / 4;
const LAB2RGB_SHIFT: i32 = LAB_SHIFT + (BASE_SHIFT - INV_GAMMA_SHIFT);

// OpenCV gives these matrices as raw IEEE-754 bit patterns precisely so that
// decimal text cannot round-trip them wrong; they are carried over the same
// way.
const SRGB2XYZ_D65: [f64; 9] = [
    f64::from_bits(0x3fda65a14488c60d),
    f64::from_bits(0x3fd6e297396d0918),
    f64::from_bits(0x3fc71819d2391d58),
    f64::from_bits(0x3fcb38cda6e75ff6),
    f64::from_bits(0x3fe6e297396d0918),
    f64::from_bits(0x3fb279aae6c8f755),
    f64::from_bits(0x3f93cc4ac6cdaf4b),
    f64::from_bits(0x3fbe836eb4e98138),
    f64::from_bits(0x3fee68427418d691),
];

const XYZ2SRGB_D65: [f64; 9] = [
    f64::from_bits(0x4009ec804102ff8f),
    f64::from_bits(0xbff8982a9930be0e),
    f64::from_bits(0xbfdfe7ff583a53b9),
    f64::from_bits(0xbfef042528ae74f3),
    f64::from_bits(0x3ffe040f23897204),
    f64::from_bits(0x3fa546d3f9e7b80b),
    f64::from_bits(0x3fac7de5082cf52c),
    f64::from_bits(0xbfca1e14bdfd2631),
    f64::from_bits(0x3ff0eabef06b3786),
];

const D65: [f64; 3] = [
    f64::from_bits(0x3fee6a22b3892ee8),
    1.0,
    f64::from_bits(0x3ff16b8950763a19),
];

const LTHRESH: f32 = 216.0 / 24389.0;
const LSCALE: f32 = 841.0 / 108.0;
const LBIAS: f32 = 16.0 / 116.0;

const GAMMA_THRESHOLD: f64 = 809.0 / 20000.0;
const GAMMA_INV_THRESHOLD: f64 = 7827.0 / 2500000.0;
const GAMMA_LOW_SCALE: f64 = 323.0 / 25.0;
const GAMMA_POWER: f64 = 12.0 / 5.0;
const GAMMA_XSHIFT: f64 = 11.0 / 200.0;

/// `CV_DESCALE(x, n)`. The shift is arithmetic; `x` is signed in the inverse
/// direction.
#[inline]
fn descale(x: i32, n: i32) -> i32 {
    (x + (1 << (n - 1))) >> n
}

#[inline]
fn cv_round_f32(x: f32) -> i32 {
    x.round_ties_even() as i32
}

#[inline]
fn cv_round_f64(x: f64) -> i32 {
    x.round_ties_even() as i32
}

#[inline]
fn saturate_u8(x: i32) -> u8 {
    x.clamp(0, 255) as u8
}

/// OpenCV's `f32_cbrt`: scale the argument into `[0.125, 1)`, evaluate a
/// quartic rational in `double`, then take the top 23 mantissa bits of that
/// `double` unrounded next to the reconstructed exponent.
fn soft_cbrt(x: f32) -> f32 {
    let bits = x.to_bits();
    if bits & 0x7fff_ffff == 0 {
        return 0.0;
    }
    let sign = bits >> 31;
    let ex = ((bits >> 23) & 0xff) as i32 - 127;
    let mut shx = ex % 3;
    shx -= if shx >= 0 { 3 } else { 0 };
    let ex = (ex - shx) / 3 - 1;
    let fr = f64::from_bits((((shx + 1023) as u64) << 52) | ((bits & 0x007f_ffff) as u64) << 29);

    const A1: f64 = f64::from_bits(0x4046a09e6653ba70);
    const A2: f64 = f64::from_bits(0x406808f46c6116e0);
    const A3: f64 = f64::from_bits(0x405dca97439cae14);
    const A4: f64 = f64::from_bits(0x402add70d2827500);
    const A5: f64 = f64::from_bits(0x3fc4f15f83f55d2d);
    const A6: f64 = f64::from_bits(0x402d9e20660edb21);
    const A7: f64 = f64::from_bits(0x4062ff15c0285815);
    const A8: f64 = f64::from_bits(0x406510d06a8112ce);
    const A9: f64 = f64::from_bits(0x4040fecbc9e2c375);

    let num = (((A1 * fr + A2) * fr + A3) * fr + A4) * fr + A5;
    let den = (((A6 * fr + A7) * fr + A8) * fr + A9) * fr + 1.0;
    let fr = num / den;

    let mantissa = ((fr.to_bits() & 0x000f_ffff_ffff_ffff) >> 29) as u32;
    f32::from_bits((sign << 31) | (((ex + 127) as u32) << 23) | mantissa)
}

fn apply_gamma(x: f32) -> f32 {
    let xd = x as f64;
    let v = if xd <= GAMMA_THRESHOLD {
        xd / GAMMA_LOW_SCALE
    } else {
        ((xd + GAMMA_XSHIFT) / (1.0 + GAMMA_XSHIFT)).powf(GAMMA_POWER)
    };
    v as f32
}

fn apply_inv_gamma(x: f32) -> f32 {
    let xd = x as f64;
    let v = if xd <= GAMMA_INV_THRESHOLD {
        xd * GAMMA_LOW_SCALE
    } else {
        xd.powf(1.0 / GAMMA_POWER) * (1.0 + GAMMA_XSHIFT) - GAMMA_XSHIFT
    };
    v as f32
}

struct LabTabs {
    srgb_gamma: [u16; 256],
    lab_cbrt: [u16; LAB_CBRT_TAB_SIZE_B],
    srgb_inv_gamma: Box<[u16]>,
    lab_to_yf: [u16; 512],
    ab_to_xz: Box<[i32]>,
    /// Forward coefficients for `blueIdx == 0`: index `k` already belongs to
    /// input channel `k`, so a BGR pixel is consumed in storage order.
    fwd_coeffs: [i32; 9],
    /// Inverse coefficients for `blueIdx == 0`: rows are R, G, B.
    inv_coeffs: [i32; 9],
}

fn build_tabs() -> LabTabs {
    let mut srgb_gamma = [0u16; 256];
    let int_scale = (255 * (1 << GAMMA_SHIFT)) as f32;
    for (i, out) in srgb_gamma.iter_mut().enumerate() {
        let x = i as f32 / 255.0;
        *out = cv_round_f32(int_scale * apply_gamma(x)) as u16;
    }

    let mut srgb_inv_gamma = vec![0u16; INV_GAMMA_TAB_SIZE];
    let inv_scale = 1.0f32 / INV_GAMMA_TAB_SIZE as f32;
    for (i, out) in srgb_inv_gamma.iter_mut().enumerate() {
        let x = inv_scale * i as f32;
        *out = cv_round_f32(255.0 * apply_inv_gamma(x)) as u16;
    }

    let mut lab_cbrt = [0u16; LAB_CBRT_TAB_SIZE_B];
    let cb_tab_scale = 1.0f32 / (255.0 * (1 << GAMMA_SHIFT) as f32);
    let lshift2 = (1 << LAB_SHIFT2) as f32;
    for (i, out) in lab_cbrt.iter_mut().enumerate() {
        let x = cb_tab_scale * i as f32;
        let f = if x < LTHRESH {
            x.mul_add(LSCALE, LBIAS)
        } else {
            soft_cbrt(x)
        };
        *out = cv_round_f32(lshift2 * f) as u16;
    }

    let mut lab_to_yf = [0u16; 512];
    for i in 0..256i32 {
        let (y, ify) = if i <= 20 {
            (
                cv_round_f32((i * LUT_BASE * 20 * 9) as f32 / (17 * 29 * 29 * 29) as f32),
                cv_round_f32(
                    LUT_BASE as f32 * (16.0f32 / 116.0 + (i * 5) as f32 / (3 * 17 * 29) as f32),
                ),
            )
        } else {
            let fy =
                (i * 100 * LUT_BASE) as f32 / (255 * 116) as f32 + (16 * LUT_BASE) as f32 / 116.0;
            (
                cv_round_f32(fy * fy * fy / (LUT_BASE * LUT_BASE) as f32),
                cv_round_f32(fy),
            )
        };
        lab_to_yf[i as usize * 2] = y as u16;
        lab_to_yf[i as usize * 2 + 1] = ify as u16;
    }

    // Integer division truncates toward zero, which matters: `i` starts
    // negative.
    let mut ab_to_xz = vec![0i32; AB_TO_XZ_LEN];
    let bias = LUT_BASE * 16 / 116 * 108 / 841;
    for (k, out) in ab_to_xz.iter_mut().enumerate() {
        let i = k as i32 + MIN_AB_VALUE;
        *out = if i <= 3390 {
            i * 108 / 841 - bias
        } else {
            i * i / LUT_BASE * i / LUT_BASE
        };
    }

    let lshift = (1 << LAB_SHIFT) as f64;
    let mut fwd_coeffs = [0i32; 9];
    let mut inv_coeffs = [0i32; 9];
    for i in 0..3 {
        let wp = D65[i];
        fwd_coeffs[i * 3 + 2] = cv_round_f64(lshift * SRGB2XYZ_D65[i * 3] / wp);
        fwd_coeffs[i * 3 + 1] = cv_round_f64(lshift * SRGB2XYZ_D65[i * 3 + 1] / wp);
        fwd_coeffs[i * 3] = cv_round_f64(lshift * SRGB2XYZ_D65[i * 3 + 2] / wp);

        inv_coeffs[i] = cv_round_f64(lshift * XYZ2SRGB_D65[i] * wp);
        inv_coeffs[i + 3] = cv_round_f64(lshift * XYZ2SRGB_D65[i + 3] * wp);
        inv_coeffs[i + 6] = cv_round_f64(lshift * XYZ2SRGB_D65[i + 6] * wp);
    }

    LabTabs {
        srgb_gamma,
        lab_cbrt,
        srgb_inv_gamma: srgb_inv_gamma.into_boxed_slice(),
        lab_to_yf,
        ab_to_xz: ab_to_xz.into_boxed_slice(),
        fwd_coeffs,
        inv_coeffs,
    }
}

fn tabs() -> &'static LabTabs {
    static TABS: OnceLock<LabTabs> = OnceLock::new();
    TABS.get_or_init(build_tabs)
}

fn require_bgr_or_lab(src: &ImageU8, op: &str) -> OpResult<()> {
    if src.channels != 3 {
        return Err(format!("{op}: expected 3 channel(s), got {}", src.channels));
    }
    Ok(())
}

/// `cv::cvtColor(src, dst, COLOR_BGR2Lab)`.
pub(crate) fn cvt_color_bgr_lab(src: &ImageU8) -> OpResult<ImageU8> {
    require_bgr_or_lab(src, "cvt_color_bgr_lab")?;
    let t = tabs();
    let c = t.fwd_coeffs;
    let l_scale = (116 * 255 + 50) / 100;
    let l_shift = -((16 * 255 * (1 << LAB_SHIFT2) + 50) / 100);
    let ab_shift = 128 * (1 << LAB_SHIFT2);

    let mut data = vec![0u8; src.data.len()];
    super::pointwise(&mut data, 3, &src.data, 3, |data, srcd| {
        for (out, px) in data.chunks_exact_mut(3).zip(srcd.chunks_exact(3)) {
            let v0 = t.srgb_gamma[px[0] as usize] as i32;
            let v1 = t.srgb_gamma[px[1] as usize] as i32;
            let v2 = t.srgb_gamma[px[2] as usize] as i32;
            let fx =
                t.lab_cbrt[descale(v0 * c[0] + v1 * c[1] + v2 * c[2], LAB_SHIFT) as usize] as i32;
            let fy =
                t.lab_cbrt[descale(v0 * c[3] + v1 * c[4] + v2 * c[5], LAB_SHIFT) as usize] as i32;
            let fz =
                t.lab_cbrt[descale(v0 * c[6] + v1 * c[7] + v2 * c[8], LAB_SHIFT) as usize] as i32;

            out[0] = saturate_u8(descale(l_scale * fy + l_shift, LAB_SHIFT2));
            out[1] = saturate_u8(descale(500 * (fx - fy) + ab_shift, LAB_SHIFT2));
            out[2] = saturate_u8(descale(200 * (fy - fz) + ab_shift, LAB_SHIFT2));
        }
    });
    ImageU8::new(src.width, src.height, 3, data)
}

/// `cv::cvtColor(src, dst, COLOR_Lab2BGR)`.
pub(crate) fn cvt_color_lab_bgr(src: &ImageU8) -> OpResult<ImageU8> {
    require_bgr_or_lab(src, "cvt_color_lab_bgr")?;
    let t = tabs();
    let c = t.inv_coeffs;
    let a_bias = 128 * LAB_BASE / 500;
    let b_bias = 128 * LAB_BASE / 200 - 1;
    let top = INV_GAMMA_TAB_SIZE as i32 - 1;

    let mut data = vec![0u8; src.data.len()];
    super::pointwise(&mut data, 3, &src.data, 3, |data, srcd| {
        for (out, px) in data.chunks_exact_mut(3).zip(srcd.chunks_exact(3)) {
            let y = t.lab_to_yf[px[0] as usize * 2] as i32;
            let ify = t.lab_to_yf[px[0] as usize * 2 + 1] as i32;

            // `aa*BASE/500` and `bb*BASE/200` as reciprocal multiplications.
            let adiv = ((5 * px[1] as i32 * 53687 + (1 << 7)) >> 13) - a_bias;
            let bdiv = ((px[2] as i32 * 41943 + (1 << 4)) >> 9) - b_bias;

            let x = t.ab_to_xz[(ify + adiv - MIN_AB_VALUE) as usize];
            let z = t.ab_to_xz[(ify - bdiv - MIN_AB_VALUE) as usize];

            let r = descale(c[0] * x + c[1] * y + c[2] * z, LAB2RGB_SHIFT).clamp(0, top);
            let g = descale(c[3] * x + c[4] * y + c[5] * z, LAB2RGB_SHIFT).clamp(0, top);
            let b = descale(c[6] * x + c[7] * y + c[8] * z, LAB2RGB_SHIFT).clamp(0, top);

            out[0] = saturate_u8(t.srgb_inv_gamma[b as usize] as i32);
            out[1] = saturate_u8(t.srgb_inv_gamma[g as usize] as i32);
            out[2] = saturate_u8(t.srgb_inv_gamma[r as usize] as i32);
        }
    });
    ImageU8::new(src.width, src.height, 3, data)
}
