use super::OpResult;
use super::color::ColorMode;
use super::detection::size_trunc;
use crate::cv;
use crate::cv::image::{ImageF32, ImageU8};

pub(crate) fn enhance_captured_image(img: &ImageU8, color_mode: ColorMode) -> OpResult<ImageU8> {
    match color_mode {
        ColorMode::Color => multi_scale_retinex_on_l(img),
        ColorMode::Grayscale => enhance_grayscale_image(img),
    }
}

fn clamp_255(v: f32) -> f32 {
    let v = if v < 255.0 { v } else { 255.0 };
    if v > 0.0 { v } else { 0.0 }
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
    let small = cv::resize_u8(channel, map_w, map_h, cv::Interp::Area)?;

    let k = ((map_w.max(map_h) as f64 * SHADOW_KERNEL_FRAC) as i32).max(3) | 1;
    let kernel = cv::ellipse_kernel(k)?;
    let closed = cv::morphology_close(&small, &kernel)?;

    let closed_f = closed.to_f32();
    let map_small = cv::box_filter_f32(&cv::box_filter_f32(&closed_f, k, k)?, k, k)?;

    let paper = cv::percentile_f32(&map_small, SHADOW_PAPER_PERCENTILE)?;
    if paper < 1.0 {
        return Ok(channel.clone());
    }
    let map = cv::resize_f32(&map_small, width, height, cv::Interp::Bilinear)?;

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

    let l_original_float = l.to_f32();
    let l_float = l_original_float.map(|v| v + 1.0);

    let scale_factor = 2.0;
    let small_w = l_float.width as f64 / scale_factor;
    let small_h = l_float.height as f64 / scale_factor;
    let (small_cols, small_rows) = size_trunc(small_w, small_h);

    let l_small = cv::resize_f32(&l_float, small_cols, small_rows, cv::Interp::Area)?;
    let log_l_small = l_small.map(f32::ln);

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
        let mut term = cv::box_filter_f32(&log_l_small, k, k)?;
        term.zip_mut(&log_l_small, |blurred, log_l| *blurred = log_l - *blurred)?;
        retinex_small.zip_mut(&term, |acc, detail| {
            *acc = (*acc as f64 + detail as f64 * weight) as f32
        })?;
    }

    let (min_val, max_val) = cv::min_max_loc_f32(&retinex_small)?;
    let range = max_val - min_val;
    let inv_range = if range > 1e-6 { 1.0 / range } else { 1.0 };
    retinex_small.map_mut(|v| ((v - min_val as f32) as f64 * inv_range) as f32);

    let retinex_norm = cv::resize_f32(
        &retinex_small,
        l_float.width,
        l_float.height,
        cv::Interp::Bicubic,
    )?;

    let mean_l = cv::mean_f32(&l_original_float)?;
    let amplitude = 60.0;
    let alpha = 0.6;
    let bias = (mean_l - amplitude / 2.0) as f32;

    let corrected_l = l_original_float.zip_map(&retinex_norm, |original, detail| {
        let corrected = (detail as f64 * amplitude) as f32 + bias;
        (original as f64 * (1.0 - alpha) + corrected as f64 * alpha) as f32
    })?;

    let p_low_orig = percentile_l(&l_original_float, 0.001)?;
    let p_low = percentile_l(&corrected_l, 0.001)?;
    let p_high = percentile_l(&corrected_l, 0.995)?;

    let target_low = p_low.min(p_low_orig);
    let target_high = 245.0;
    let scale = (target_high - target_low) / (p_high - p_low + 1e-6);

    lab_channels[0] = corrected_l
        .map_to_u8(|v| clamp_255(((v - p_low as f32) as f64 * scale) as f32 + target_low as f32));

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

    let gray_f = gray.to_f32();
    let img_float = gray_f.map(|v| v + 1.0);
    let log_img = img_float.map(f32::ln);

    let kernel_sizes = [max_dim / 6.0, max_dim / 50.0];
    let weight = 1.0 / kernel_sizes.len() as f64;
    let mut retinex = ImageF32::zeros(gray.width, gray.height, 1)?;

    for kernel_size in kernel_sizes {
        let k = (kernel_size as i32).max(3) | 1;
        let mut term = cv::box_filter_f32(&img_float, k, k)?;
        term.map_mut(|v| (v + 1.0).ln());
        term.zip_mut(&log_img, |log_blur, log_v| *log_blur = log_v - *log_blur)?;
        retinex.zip_mut(&term, |acc, detail| {
            *acc = (*acc as f64 + detail as f64 * weight) as f32
        })?;
    }

    retinex.map_mut(f32::exp);

    let (p_low, p_high) = cv::percentile_pair_f32(&retinex, 0.004, 0.99)?;
    let (p_low, p_high) = (p_low as f64, p_high as f64);
    let scale = if p_high > p_low {
        255.0 / (p_high - p_low)
    } else {
        1.0
    };
    let result8u = retinex.map_to_u8(|v| clamp_255(((v - p_low as f32) as f64 * scale) as f32));

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
        let (g_low, g_high) = cv::percentile_pair_f32(&gray_f, 0.01, 0.99)?;
        let (g_low, g_high) = (g_low as f64, g_high as f64);
        let scale = 255.0 / (g_high - g_low + 1e-6);
        gray_f.map_to_u8(|v| clamp_255(((v - g_low as f32) as f64 * scale) as f32))
    } else {
        let scale = 255.0 / mode_val as f64;
        result8u.to_f32().map_to_u8(|v| {
            let scaled = (v as f64 * scale) as f32;
            if scaled < 255.0 { scaled } else { 255.0 }
        })
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
