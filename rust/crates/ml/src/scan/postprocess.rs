use super::OpResult;
use super::color::ColorMode;
use super::detection::size_trunc;
use crate::cv;
use crate::cv::image::{ImageF32, ImageRef, ImageU8};

pub(crate) fn enhance_captured_image(img: &ImageU8, color_mode: ColorMode) -> OpResult<ImageU8> {
    match color_mode {
        ColorMode::Color => multi_scale_retinex_on_l(img),
        ColorMode::Grayscale => enhance_grayscale_image(img),
    }
}

const SHADOW_MAP_LONG_EDGE: f64 = 256.0;
const SHADOW_KERNEL_FRAC: f64 = 1.0 / 16.0;
const SHADOW_MAX_GAIN: f32 = 2.8;
const SHADOW_PAPER_PERCENTILE: f64 = 0.90;

fn remove_shadows(channel: &ImageU8) -> OpResult<ImageU8> {
    let (width, height) = channel.size();
    let long_edge = width.max(height) as f64;
    let (map_w, map_h) = if long_edge > SHADOW_MAP_LONG_EDGE {
        let scale = SHADOW_MAP_LONG_EDGE / long_edge;
        size_trunc(width as f64 * scale, height as f64 * scale)
    } else {
        (width, height)
    };
    let small = cv::resize_area(ImageRef::U8(channel), map_w, map_h)?.into_u8()?;

    let k = ((map_w.max(map_h) as f64 * SHADOW_KERNEL_FRAC) as i32).max(3) | 1;
    let kernel = cv::ellipse_kernel(k)?;
    let closed = cv::morphology_close(&small, &kernel)?;

    let closed_f = cv::u8_to_f32(&closed)?;
    let map_small = cv::box_filter_f32(&cv::box_filter_f32(&closed_f, k, k)?, k, k)?;

    let paper = cv::percentile_f32(&map_small, SHADOW_PAPER_PERCENTILE)?;
    if paper < 1.0 {
        return Ok(channel.clone());
    }
    let map = cv::resize_bilinear(ImageRef::F32(&map_small), width, height)?.into_f32()?;

    let knee = paper / SHADOW_MAX_GAIN;
    let mut out = ImageU8::zeros(width, height, 1)?;
    cv::pointwise3(
        &mut out.data,
        1,
        &channel.data,
        1,
        &map.data,
        1,
        |out, src, map| {
            for ((o, &v), &m) in out.iter_mut().zip(src).zip(map) {
                let m = m.max(1.0);
                let gain = if m >= knee {
                    paper / m
                } else {
                    1.0 + (SHADOW_MAX_GAIN - 1.0) * (m / knee)
                };
                *o = cv::saturate_u8_f32(v as f32 * gain);
            }
        },
    );
    Ok(out)
}

fn multi_scale_retinex_on_l(bgr: &ImageU8) -> OpResult<ImageU8> {
    let lab = cv::bgr_to_lab(bgr)?;
    let mut lab_channels = cv::split_u8(&lab)?;
    let l = remove_shadows(&lab_channels[0])?;

    let l_float_raw = cv::u8_to_f32(&l)?;
    let l_float = cv::add_f32_scalar(&l_float_raw, 1.0)?;

    let scale_factor = 2.0;
    let small_w = l_float.width as f64 / scale_factor;
    let small_h = l_float.height as f64 / scale_factor;
    let (small_cols, small_rows) = size_trunc(small_w, small_h);

    let l_small = cv::resize_area(ImageRef::F32(&l_float), small_cols, small_rows)?.into_f32()?;

    let log_l_small = cv::log_f32(&l_small)?;

    let max_dim_small = small_w.max(small_h);
    let kernel_sizes = [
        max_dim_small / 80.0,
        max_dim_small / 10.0,
        max_dim_small / 2.0,
    ];

    let weight = 1.0 / kernel_sizes.len() as f64;
    let mut retinex_small = ImageF32::zeros(l_small.width, l_small.height, 1)?;

    for ks in kernel_sizes {
        let k = (ks as i32).max(3) | 1;
        let blur_log = cv::box_filter_f32(&log_l_small, k, k)?;
        let diff = cv::subtract_f32(&log_l_small, &blur_log)?;
        retinex_small = cv::add_weighted_f32(&retinex_small, 1.0, &diff, weight, 0.0)?;
    }

    let (min_val, max_val) = cv::min_max_loc_f32(&retinex_small)?;
    let mut retinex_norm_small = cv::subtract_f32_scalar(&retinex_small, min_val)?;

    let range = max_val - min_val;
    if range > 1e-6 {
        retinex_norm_small =
            cv::multiply_f32_scalar(&retinex_norm_small, [1.0 / range, 0.0, 0.0, 0.0])?;
    }

    let retinex_norm = cv::resize_bicubic(
        ImageRef::F32(&retinex_norm_small),
        l_float.width,
        l_float.height,
    )?
    .into_f32()?;

    let l_original_float = cv::u8_to_f32(&l)?;

    let mean_l = cv::mean_f32(&l_original_float)?;
    let amplitude = 60.0;

    let corrected_l = cv::multiply_f32_scalar(&retinex_norm, [amplitude, 0.0, 0.0, 0.0])?;
    let corrected_l = cv::add_f32_scalar(&corrected_l, mean_l - amplitude / 2.0)?;

    let alpha = 0.6;
    let corrected_l =
        cv::add_weighted_f32(&l_original_float, 1.0 - alpha, &corrected_l, alpha, 0.0)?;

    let p_low_orig = percentile_l(&l_original_float, 0.001)?;
    let p_low = percentile_l(&corrected_l, 0.001)?;
    let p_high = percentile_l(&corrected_l, 0.995)?;

    let target_low = p_low.min(p_low_orig);
    let target_high = 245.0;
    let scale = (target_high - target_low) / (p_high - p_low + 1e-6);

    let shifted = cv::subtract_f32_scalar(&corrected_l, p_low)?;
    let stretched = cv::multiply_f32_scalar(&shifted, [scale, 0.0, 0.0, 0.0])?;
    let offset = cv::add_f32_scalar(&stretched, target_low)?;

    let clamped_high = cv::min_f32_scalar(&offset, 255.0)?;
    let clamped = cv::max_f32_scalar(&clamped_high, 0.0)?;

    lab_channels[0] = cv::f32_to_u8(&clamped)?;

    let merged = cv::merge_u8(&lab_channels)?;
    cv::lab_to_bgr(&merged)
}

pub(crate) fn percentile_l(l: &ImageF32, p: f64) -> OpResult<f64> {
    let hist = cv::hist_256_f32(l)?;
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
        3 => cv::bgr_to_gray(img)?,
        1 => img.clone(),
        other => {
            return Err(format!(
                "grayscale enhancement expects a 1- or 3-channel image, got {other}"
            ));
        }
    };
    let gray = remove_shadows(&gray)?;

    let max_dim = gray.width.max(gray.height) as f64;

    let img_float_raw = cv::u8_to_f32(&gray)?;
    let img_float = cv::add_f32_scalar(&img_float_raw, 1.0)?;
    let log_img = cv::log_f32(&img_float)?;

    let kernel_sizes = [max_dim / 6.0, max_dim / 50.0];
    let weight = 1.0 / kernel_sizes.len() as f64;
    let mut retinex = ImageF32::zeros(gray.width, gray.height, 1)?;

    for kernel_size in kernel_sizes {
        let (kw, kh) = size_trunc(kernel_size, kernel_size);
        let blur_raw = cv::box_filter_f32(&img_float, kw, kh)?;
        let blur = cv::add_f32_scalar(&blur_raw, 1.0)?;
        let log_blur = cv::log_f32(&blur)?;
        let diff = cv::subtract_f32(&log_img, &log_blur)?;
        retinex = cv::add_weighted_f32(&retinex, 1.0, &diff, weight, 0.0)?;
    }

    let retinex_exp = cv::exp_f32(&retinex)?;

    let p_low = cv::percentile_f32(&retinex_exp, 0.004)? as f64;
    let p_high = cv::percentile_f32(&retinex_exp, 0.99)? as f64;

    let normalized = cv::subtract_f32_scalar(&retinex_exp, p_low)?;
    let scale = if p_high > p_low {
        255.0 / (p_high - p_low)
    } else {
        1.0
    };
    let scaled = cv::multiply_f32_scalar(&normalized, [scale, 0.0, 0.0, 0.0])?;
    let clamped_high = cv::min_f32_scalar(&scaled, 255.0)?;
    let clamped = cv::max_f32_scalar(&clamped_high, 0.0)?;

    let result8u = cv::f32_to_u8(&clamped)?;

    let hist = cv::hist_256_u8(&result8u)?;
    let mut mode_val = 220usize;
    let mut mode_count = 0.0f64;
    for (i, &c) in hist.iter().enumerate().take(256).skip(180) {
        if c > mode_count {
            mode_count = c;
            mode_val = i;
        }
    }

    let stretched8u = if mode_val >= 254 {
        let gray_f = cv::u8_to_f32(&gray)?;
        let g_low = cv::percentile_f32(&gray_f, 0.01)? as f64;
        let g_high = cv::percentile_f32(&gray_f, 0.99)? as f64;

        let shifted = cv::subtract_f32_scalar(&gray_f, g_low)?;
        let scaled =
            cv::multiply_f32_scalar(&shifted, [255.0 / (g_high - g_low + 1e-6), 0.0, 0.0, 0.0])?;
        let min_clamped = cv::min_f32_scalar(&scaled, 255.0)?;
        let max_clamped = cv::max_f32_scalar(&min_clamped, 0.0)?;
        cv::f32_to_u8(&max_clamped)?
    } else {
        let stretched_f = cv::u8_to_f32(&result8u)?;
        let multiplied =
            cv::multiply_f32_scalar(&stretched_f, [255.0 / mode_val as f64, 0.0, 0.0, 0.0])?;
        let min_clamped = cv::min_f32_scalar(&multiplied, 255.0)?;
        cv::f32_to_u8(&min_clamped)?
    };

    let denoised = cv::bilateral_filter_u8(&stretched8u, 9, 20.0, 10.0)?;
    cv::gray_to_bgr(&denoised)
}

#[cfg(test)]
mod tests {
    use super::remove_shadows;
    use crate::cv::image::ImageU8;

    fn background_mean(img: &ImageU8, x0: i32, x1: i32) -> f64 {
        let mut sum = 0.0;
        let mut count = 0.0;
        for y in 20..img.height - 20 {
            for x in x0..x1 {
                if x % 17 != 3 || y % 11 != 5 {
                    sum += img.data[(y * img.width + x) as usize] as f64;
                    count += 1.0;
                }
            }
        }
        sum / count
    }

    #[test]
    fn remove_shadows_lifts_shadowed_paper_and_keeps_text_dark() {
        let (w, h) = (400, 300);
        let mut data = vec![230u8; (w * h) as usize];
        for y in 0..h {
            for x in 0..w {
                let i = (y * w + x) as usize;
                if x % 17 == 3 && y % 11 == 5 {
                    data[i] = 40;
                }
                if x < w / 2 {
                    data[i] = (data[i] as f64 * 0.55) as u8;
                }
            }
        }
        let img = ImageU8::new(w, h, 1, data).unwrap();
        let out = remove_shadows(&img).unwrap();

        let shadow_bg = background_mean(&out, 20, w / 4);
        let lit_bg = background_mean(&out, 3 * w / 4, w - 20);
        assert!(
            (shadow_bg - lit_bg).abs() < 12.0,
            "shadowed paper {shadow_bg:.1} should match lit paper {lit_bg:.1}"
        );

        let mut min_shadow_half = 255u8;
        for y in 20..h - 20 {
            for x in 20..w / 4 {
                min_shadow_half = min_shadow_half.min(out.data[(y * w + x) as usize]);
            }
        }
        assert!(
            min_shadow_half < 90,
            "text in the lifted shadow should stay dark, got {min_shadow_half}"
        );
    }

    #[test]
    fn remove_shadows_is_near_identity_on_evenly_lit_paper() {
        let (w, h) = (400, 300);
        let mut data = vec![225u8; (w * h) as usize];
        for y in 0..h {
            for x in 0..w {
                if x % 17 == 3 && y % 11 == 5 {
                    data[(y * w + x) as usize] = 40;
                }
            }
        }
        let img = ImageU8::new(w, h, 1, data.clone()).unwrap();
        let out = remove_shadows(&img).unwrap();
        let mean_delta: f64 = out
            .data
            .iter()
            .zip(&data)
            .map(|(&a, &b)| (a as f64 - b as f64).abs())
            .sum::<f64>()
            / data.len() as f64;
        assert!(mean_delta < 4.0, "expected near-identity, got {mean_delta}");
    }
}
