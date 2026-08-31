//! L, a and b are all scaled onto 0..255 (a and b biased by 128); the
//! pipeline's chroma and luminance thresholds are calibrated in these units.

use std::sync::OnceLock;

use crate::cv::OpResult;
use crate::cv::image::ImageU8;

const LAB_SHIFT: i32 = 12;
const LAB_SHIFT2: i32 = 15;
const GAMMA_SHIFT: i32 = 3;
const INV_GAMMA_SHIFT: i32 = 12;
const INV_GAMMA_TAB_SIZE: usize = 1 << 12;
const LAB_CBRT_TAB_SIZE: usize = 256 * 3 / 2 * (1 << GAMMA_SHIFT);
const BASE_SHIFT: i32 = 14;
const LAB_BASE: i32 = 1 << BASE_SHIFT;
const MIN_AB_VALUE: i32 = -8145;
const AB_TO_XZ_LEN: usize = (LAB_BASE as usize) * 9 / 4;
const LAB2RGB_SHIFT: i32 = LAB_SHIFT + (BASE_SHIFT - INV_GAMMA_SHIFT);

const SRGB2XYZ_D65: [f64; 9] = [
    0.412453, 0.35758, 0.180423, 0.212671, 0.71516, 0.072169, 0.019334, 0.119193, 0.950227,
];
const XYZ2SRGB_D65: [f64; 9] = [
    3.240479, -1.53715, -0.498535, -0.969256, 1.875991, 0.041556, 0.055648, -0.204043, 1.057311,
];
const D65: [f64; 3] = [0.950456, 1.0, 1.088754];

const LTHRESH: f32 = 216.0 / 24389.0;
const LSCALE: f32 = 841.0 / 108.0;
const LBIAS: f32 = 16.0 / 116.0;

const GAMMA_THRESHOLD: f64 = 809.0 / 20000.0;
const GAMMA_INV_THRESHOLD: f64 = 7827.0 / 2500000.0;
const GAMMA_LOW_SCALE: f64 = 323.0 / 25.0;
const GAMMA_POWER: f64 = 12.0 / 5.0;
const GAMMA_XSHIFT: f64 = 11.0 / 200.0;

#[inline]
fn descale(x: i32, n: i32) -> i32 {
    (x + (1 << (n - 1))) >> n
}

#[inline]
fn round_i32(x: f64) -> i32 {
    x.round_ties_even() as i32
}

#[inline]
fn saturate_u8(x: i32) -> u8 {
    x.clamp(0, 255) as u8
}

fn apply_gamma(x: f64) -> f64 {
    if x <= GAMMA_THRESHOLD {
        x / GAMMA_LOW_SCALE
    } else {
        ((x + GAMMA_XSHIFT) / (1.0 + GAMMA_XSHIFT)).powf(GAMMA_POWER)
    }
}

fn apply_inv_gamma(x: f64) -> f64 {
    if x <= GAMMA_INV_THRESHOLD {
        x * GAMMA_LOW_SCALE
    } else {
        x.powf(1.0 / GAMMA_POWER) * (1.0 + GAMMA_XSHIFT) - GAMMA_XSHIFT
    }
}

struct LabTabs {
    srgb_gamma: [u16; 256],
    lab_cbrt: [u16; LAB_CBRT_TAB_SIZE],
    srgb_inv_gamma: Box<[u16]>,
    lab_to_yf: [u16; 512],
    ab_to_xz: Box<[i32]>,
    fwd_coeffs: [i32; 9],
    inv_coeffs: [i32; 9],
}

fn build_tabs() -> LabTabs {
    let mut srgb_gamma = [0u16; 256];
    let int_scale = (255 * (1 << GAMMA_SHIFT)) as f64;
    for (i, out) in srgb_gamma.iter_mut().enumerate() {
        *out = round_i32(int_scale * apply_gamma(i as f64 / 255.0)) as u16;
    }

    let mut srgb_inv_gamma = vec![0u16; INV_GAMMA_TAB_SIZE];
    for (i, out) in srgb_inv_gamma.iter_mut().enumerate() {
        let x = i as f64 / INV_GAMMA_TAB_SIZE as f64;
        *out = round_i32(255.0 * apply_inv_gamma(x)) as u16;
    }

    let mut lab_cbrt = [0u16; LAB_CBRT_TAB_SIZE];
    let cb_tab_scale = 1.0f32 / (255.0 * (1 << GAMMA_SHIFT) as f32);
    let lshift2 = (1 << LAB_SHIFT2) as f32;
    for (i, out) in lab_cbrt.iter_mut().enumerate() {
        let x = cb_tab_scale * i as f32;
        let f = if x < LTHRESH {
            x.mul_add(LSCALE, LBIAS)
        } else {
            x.cbrt()
        };
        *out = round_i32((lshift2 * f) as f64) as u16;
    }

    let mut lab_to_yf = [0u16; 512];
    for i in 0..256i32 {
        const LUT_BASE: i32 = 1 << 14;
        let (y, ify) = if i <= 20 {
            (
                round_i32((i * LUT_BASE * 20 * 9) as f64 / (17 * 29 * 29 * 29) as f64),
                round_i32(LUT_BASE as f64 * (16.0 / 116.0 + (i * 5) as f64 / (3 * 17 * 29) as f64)),
            )
        } else {
            let fy =
                (i * 100 * LUT_BASE) as f64 / (255 * 116) as f64 + (16 * LUT_BASE) as f64 / 116.0;
            (
                round_i32(fy * fy * fy / (LUT_BASE * LUT_BASE) as f64),
                round_i32(fy),
            )
        };
        lab_to_yf[i as usize * 2] = y as u16;
        lab_to_yf[i as usize * 2 + 1] = ify as u16;
    }

    let mut ab_to_xz = vec![0i32; AB_TO_XZ_LEN];
    let bias = LAB_BASE * 16 / 116 * 108 / 841;
    for (k, out) in ab_to_xz.iter_mut().enumerate() {
        let i = k as i32 + MIN_AB_VALUE;
        *out = if i <= 3390 {
            i * 108 / 841 - bias
        } else {
            i * i / LAB_BASE * i / LAB_BASE
        };
    }

    let lshift = (1 << LAB_SHIFT) as f64;
    let mut fwd_coeffs = [0i32; 9];
    let mut inv_coeffs = [0i32; 9];
    for i in 0..3 {
        let wp = D65[i];
        fwd_coeffs[i * 3 + 2] = round_i32(lshift * SRGB2XYZ_D65[i * 3] / wp);
        fwd_coeffs[i * 3 + 1] = round_i32(lshift * SRGB2XYZ_D65[i * 3 + 1] / wp);
        fwd_coeffs[i * 3] = round_i32(lshift * SRGB2XYZ_D65[i * 3 + 2] / wp);

        inv_coeffs[i] = round_i32(lshift * XYZ2SRGB_D65[i] * wp);
        inv_coeffs[i + 3] = round_i32(lshift * XYZ2SRGB_D65[i + 3] * wp);
        inv_coeffs[i + 6] = round_i32(lshift * XYZ2SRGB_D65[i + 6] * wp);
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

fn require_3ch(src: &ImageU8, op: &str) -> OpResult<()> {
    if src.channels != 3 {
        return Err(format!("{op}: expected 3 channel(s), got {}", src.channels));
    }
    Ok(())
}

pub(crate) fn bgr_to_lab(src: &ImageU8) -> OpResult<ImageU8> {
    require_3ch(src, "bgr_to_lab")?;
    let t = tabs();
    let c = t.fwd_coeffs;
    let l_scale = (116 * 255 + 50) / 100;
    let l_shift = -((16 * 255 * (1 << LAB_SHIFT2) + 50) / 100);
    let ab_shift = 128 * (1 << LAB_SHIFT2);

    let mut data = vec![0u8; src.data.len()];
    super::pointwise(&mut data, 3, &src.data, 3, |data, srcd| {
        for (out, px) in data
            .as_chunks_mut::<3>()
            .0
            .iter_mut()
            .zip(srcd.as_chunks::<3>().0.iter())
        {
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

pub(crate) fn lab_to_bgr(src: &ImageU8) -> OpResult<ImageU8> {
    require_3ch(src, "lab_to_bgr")?;
    let t = tabs();
    let c = t.inv_coeffs;
    let a_bias = 128 * LAB_BASE / 500;
    let b_bias = 128 * LAB_BASE / 200 - 1;
    let top = INV_GAMMA_TAB_SIZE as i32 - 1;

    let mut data = vec![0u8; src.data.len()];
    super::pointwise(&mut data, 3, &src.data, 3, |data, srcd| {
        for (out, px) in data
            .as_chunks_mut::<3>()
            .0
            .iter_mut()
            .zip(srcd.as_chunks::<3>().0.iter())
        {
            let y = t.lab_to_yf[px[0] as usize * 2] as i32;
            let ify = t.lab_to_yf[px[0] as usize * 2 + 1] as i32;

            let adiv = px[1] as i32 * LAB_BASE / 500 - a_bias;
            let bdiv = px[2] as i32 * LAB_BASE / 200 - b_bias;

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
