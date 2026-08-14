//! Enhancement of the extracted page: multi-scale retinex on L for color,
//! a separate retinex + normalization path for grayscale.

use super::OpResult;
use super::color::ColorMode;
use super::detection::size_trunc;
use super::image::{ImageF32, ImageRef, ImageU8};
use super::ops;

pub(crate) fn enhance_captured_image(img: &ImageU8, color_mode: ColorMode) -> OpResult<ImageU8> {
    match color_mode {
        ColorMode::Color => multi_scale_retinex_on_l(img),
        ColorMode::Grayscale => enhance_grayscale_image(img),
    }
}

fn multi_scale_retinex_on_l(bgr: &ImageU8) -> OpResult<ImageU8> {
    let lab = ops::cvt_color_bgr_lab(bgr)?;
    let mut lab_channels = ops::split_u8(&lab)?;
    let l = lab_channels[0].clone();

    let l_float_raw = ops::u8_to_f32(&l)?;
    let l_float = ops::add_f32_scalar(&l_float_raw, 1.0)?;

    let scale_factor = 2.0;
    // The small size keeps its untruncated components: the resize truncates
    // them, but `max_dim_small` below uses the untruncated values.
    let small_w = l_float.width as f64 / scale_factor;
    let small_h = l_float.height as f64 / scale_factor;
    let (small_cols, small_rows) = size_trunc(small_w, small_h);

    let l_small =
        ops::resize_inter_area(ImageRef::F32(&l_float), small_cols, small_rows)?.into_f32()?;

    // log(L) once, on the small image.
    let log_l_small = ops::log_f32(&l_small)?;

    let max_dim_small = small_w.max(small_h);
    let kernel_sizes = [
        max_dim_small / 80.0,
        max_dim_small / 10.0,
        max_dim_small / 2.0,
    ];

    let weight = 1.0 / kernel_sizes.len() as f64;
    let mut retinex_small = ImageF32::zeros(l_small.width, l_small.height, 1)?;

    for ks in kernel_sizes {
        // Odd-kernel forcing happens ONLY in the color path.
        let k = (ks as i32).max(3) | 1;
        let blur_log = ops::box_filter_f32(&log_l_small, k, k)?;
        let diff = ops::subtract_f32(&log_l_small, &blur_log)?;
        retinex_small = ops::add_weighted_f32(&retinex_small, 1.0, &diff, weight, 0.0)?;
    }

    let (min_val, max_val) = ops::min_max_loc_f32(&retinex_small)?;
    let mut retinex_norm_small = ops::subtract_f32_scalar(&retinex_small, min_val)?;

    let range = max_val - min_val;
    if range > 1e-6 {
        retinex_norm_small =
            ops::multiply_f32_scalar(&retinex_norm_small, [1.0 / range, 0.0, 0.0, 0.0])?;
    }

    let retinex_norm = ops::resize_inter_cubic(
        ImageRef::F32(&retinex_norm_small),
        l_float.width,
        l_float.height,
    )?
    .into_f32()?;

    let l_original_float = ops::u8_to_f32(&l)?;

    let mean_l = ops::mean_f32(&l_original_float)?;
    let amplitude = 60.0;

    let corrected_l = ops::multiply_f32_scalar(&retinex_norm, [amplitude, 0.0, 0.0, 0.0])?;
    let corrected_l = ops::add_f32_scalar(&corrected_l, mean_l - amplitude / 2.0)?;

    let alpha = 0.6;
    let corrected_l =
        ops::add_weighted_f32(&l_original_float, 1.0 - alpha, &corrected_l, alpha, 0.0)?;

    let p_low_orig = percentile_l(&l_original_float, 0.001)?;
    let p_low = percentile_l(&corrected_l, 0.001)?;
    let p_high = percentile_l(&corrected_l, 0.995)?;

    let target_low = p_low.min(p_low_orig);
    let target_high = 245.0;
    let scale = (target_high - target_low) / (p_high - p_low + 1e-6);

    let shifted = ops::subtract_f32_scalar(&corrected_l, p_low)?;
    let stretched = ops::multiply_f32_scalar(&shifted, [scale, 0.0, 0.0, 0.0])?;
    let offset = ops::add_f32_scalar(&stretched, target_low)?;

    let clamped_high = ops::min_f32_scalar(&offset, 255.0)?;
    let clamped = ops::max_f32_scalar(&clamped_high, 0.0)?;

    lab_channels[0] = ops::f32_to_u8(&clamped)?;

    let merged = ops::merge_u8(&lab_channels)?;
    ops::cvt_color_lab_bgr(&merged)
}

/// Histogram percentile over 256 bins on [0,256): values outside that range
/// are NOT counted, but the denominator stays the full pixel count.
pub(crate) fn percentile_l(l: &ImageF32, p: f64) -> OpResult<f64> {
    let hist = ops::hist_256_f32(l)?;
    let total = l.pixels() as f64;
    let mut sum = 0.0;
    for (i, count) in hist.iter().enumerate() {
        sum += count;
        if sum / total >= p {
            return Ok(i as f64);
        }
    }
    Ok(255.0)
}

fn enhance_grayscale_image(img: &ImageU8) -> OpResult<ImageU8> {
    let gray = match img.channels {
        3 => ops::cvt_color_bgr_to_gray(img)?,
        1 => img.clone(),
        other => {
            return Err(format!(
                "grayscale enhancement expects a 1- or 3-channel image, got {other}"
            ));
        }
    };

    let max_dim = gray.width.max(gray.height) as f64;

    let img_float_raw = ops::u8_to_f32(&gray)?;
    let img_float = ops::add_f32_scalar(&img_float_raw, 1.0)?;
    let log_img = ops::log_f32(&img_float)?;

    // Kernel sizes stay f64 and are truncated; NO odd forcing here, unlike
    // the color path.
    let kernel_sizes = [max_dim / 6.0, max_dim / 50.0];
    let weight = 1.0 / kernel_sizes.len() as f64;
    let mut retinex = ImageF32::zeros(gray.width, gray.height, 1)?;

    for kernel_size in kernel_sizes {
        // The grayscale path blurs the LINEAR image and logs afterwards; the
        // color path blurs the log image.
        let (kw, kh) = size_trunc(kernel_size, kernel_size);
        let blur_raw = ops::box_filter_f32(&img_float, kw, kh)?;
        let blur = ops::add_f32_scalar(&blur_raw, 1.0)?;
        let log_blur = ops::log_f32(&blur)?;
        let diff = ops::subtract_f32(&log_img, &log_blur)?;
        retinex = ops::add_weighted_f32(&retinex, 1.0, &diff, weight, 0.0)?;
    }

    let retinex_exp = ops::exp_f32(&retinex)?;

    let sorted = ops::sort_pixels_ascending_f32(&retinex_exp)?;
    let n = sorted.len() as f64;
    let p_low = sorted[(n * 0.004) as usize] as f64;
    let p_high = sorted[(n * 0.99) as usize] as f64;

    let normalized = ops::subtract_f32_scalar(&retinex_exp, p_low)?;
    let scale = if p_high > p_low {
        255.0 / (p_high - p_low)
    } else {
        1.0
    };
    let scaled = ops::multiply_f32_scalar(&normalized, [scale, 0.0, 0.0, 0.0])?;
    let clamped_high = ops::min_f32_scalar(&scaled, 255.0)?;
    let clamped = ops::max_f32_scalar(&clamped_high, 0.0)?;

    let result8u = ops::f32_to_u8(&clamped)?;

    // Histogram mode in [180,255] as the background level estimate.
    let hist = ops::hist_256_u8(&result8u)?;
    let mut mode_val = 220usize;
    let mut mode_count = 0.0f64;
    for (i, &c) in hist.iter().enumerate().take(256).skip(180) {
        if c > mode_count {
            mode_count = c;
            mode_val = i;
        }
    }

    let stretched8u = if mode_val >= 254 {
        // Retinex over-amplified: normalize the ORIGINAL grayscale instead.
        let gray_f = ops::u8_to_f32(&gray)?;
        let gray_sorted = ops::sort_pixels_ascending_f32(&gray_f)?;
        let g_n = gray_sorted.len() as f64;
        let g_low = gray_sorted[(g_n * 0.01) as usize] as f64;
        let g_high = gray_sorted[(g_n * 0.99) as usize] as f64;

        let shifted = ops::subtract_f32_scalar(&gray_f, g_low)?;
        let scaled =
            ops::multiply_f32_scalar(&shifted, [255.0 / (g_high - g_low + 1e-6), 0.0, 0.0, 0.0])?;
        let min_clamped = ops::min_f32_scalar(&scaled, 255.0)?;
        let max_clamped = ops::max_f32_scalar(&min_clamped, 0.0)?;
        ops::f32_to_u8(&max_clamped)?
    } else {
        // Only the upper clamp is applied in this branch.
        let stretched_f = ops::u8_to_f32(&result8u)?;
        let multiplied =
            ops::multiply_f32_scalar(&stretched_f, [255.0 / mode_val as f64, 0.0, 0.0, 0.0])?;
        let min_clamped = ops::min_f32_scalar(&multiplied, 255.0)?;
        ops::f32_to_u8(&min_clamped)?
    };

    let denoised = ops::bilateral_filter_u8(&stretched8u, 9, 20.0, 10.0)?;
    ops::cvt_color_gray_to_bgr(&denoised)
}
