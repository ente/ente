use super::OpResult;
use super::detection::resize_for_max_pixels;
use super::geometry::{Quad, norm};
use super::mask::Mask;
use crate::cv;
use crate::cv::image::{ImageF32, ImageRef, ImageU8};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ColorMode {
    Color,
    Grayscale,
}

const CHROMA_THRESHOLD: f64 = 17.5;
const PROPORTION_THRESHOLD: f64 = 0.0003;
const LUMINANCE_MIN: f64 = 40.0;
const LUMINANCE_MAX: f64 = 180.0;

pub(crate) fn auto_color_mode(img: &ImageU8, mask: &Mask, quad: &Quad) -> OpResult<ColorMode> {
    let resized_img = resize_for_max_pixels(img, 1024.0 * 768.0)?;
    let work_size = resized_img.size();

    let doc_mask = document_mask(mask, quad, img.size(), work_size)?;
    let white_balanced = apply_gray_world_to_document(&resized_img, &doc_mask)?;

    let lab = cv::bgr_to_lab(&white_balanced)?;
    let channels = cv::split_u8(&lab)?;
    let luminance = &channels[0];
    let a = &channels[1];
    let b = &channels[2];

    let chroma = chroma(a, b)?;

    let color_mask_f = cv::threshold_binary_f32(&chroma, CHROMA_THRESHOLD, 255.0)?;
    let color_mask = cv::f32_to_u8(&color_mask_f)?;

    let luminance_mask = cv::in_range_u8(luminance, LUMINANCE_MIN, LUMINANCE_MAX)?;

    let tmp = cv::bitwise_and_u8(&color_mask, &luminance_mask)?;
    let restricted_mask = cv::bitwise_and_u8(&tmp, &doc_mask)?;

    let colored_pixels = cv::count_non_zero(&restricted_mask)?;
    let total_pixels = cv::count_non_zero(&doc_mask)?;

    if total_pixels == 0 {
        return Ok(ColorMode::Grayscale);
    }
    let proportion = colored_pixels as f64 / total_pixels as f64;
    Ok(if proportion > PROPORTION_THRESHOLD {
        ColorMode::Color
    } else {
        ColorMode::Grayscale
    })
}

fn chroma(a: &ImageU8, b: &ImageU8) -> OpResult<ImageF32> {
    let a_float = cv::u8_to_f32(a)?;
    let b_float = cv::u8_to_f32(b)?;
    let a_shifted = cv::subtract_f32_scalar(&a_float, 128.0)?;
    let b_shifted = cv::subtract_f32_scalar(&b_float, 128.0)?;
    cv::magnitude_f32(&a_shifted, &b_shifted)
}

fn erode_border(mask: &ImageU8, quad: &Quad) -> OpResult<ImageU8> {
    let min_dim = quad
        .edges()
        .iter()
        .map(|&(from, to)| norm(from, to))
        .fold(f64::INFINITY, f64::min);
    let mut k = (min_dim * 0.02 + 0.5).floor() as i32;
    k = k.clamp(3, 15);
    if k % 2 == 0 {
        k += 1;
    }

    let kernel = cv::ellipse_kernel(k)?;
    cv::morphology_erode(mask, &kernel)
}

fn document_mask(
    mask: &Mask,
    quad: &Quad,
    orig_size: (i32, i32),
    work_size: (i32, i32),
) -> OpResult<ImageU8> {
    let mask_image = mask.to_image()?;
    let resized_mask =
        cv::resize_area(ImageRef::U8(&mask_image), work_size.0, work_size.1)?.into_u8()?;

    let resized_quad = quad.scaled_to(
        orig_size.0 as f64,
        orig_size.1 as f64,
        work_size.0 as f64,
        work_size.1 as f64,
    );

    let eroded_mask = erode_border(&resized_mask, &resized_quad)?;

    let pts: Vec<(i32, i32)> = resized_quad
        .corners()
        .iter()
        .map(|p| (p.x as i32, p.y as i32))
        .collect();
    let quad_mask = cv::fill_poly(eroded_mask.width, eroded_mask.height, &pts, 255.0)?;

    cv::bitwise_and_u8(&eroded_mask, &quad_mask)
}

pub(crate) fn apply_gray_world_to_document(img: &ImageU8, doc_mask: &ImageU8) -> OpResult<ImageU8> {
    assert_eq!(img.channels, 3, "gray-world expects an 8UC3 image");

    let non_zero = cv::count_non_zero(doc_mask)?;
    if non_zero == 0 {
        return Ok(img.clone());
    }

    let mean = cv::mean_u8c3_masked(img, doc_mask)?;
    let eps = 1e-6;
    let mean_b = if mean[0] < eps { eps } else { mean[0] };
    let mean_g = if mean[1] < eps { eps } else { mean[1] };
    let mean_r = if mean[2] < eps { eps } else { mean[2] };

    let mean_gray = (mean_b + mean_g + mean_r) / 3.0;
    let scales = [
        mean_gray / mean_b,
        mean_gray / mean_g,
        mean_gray / mean_r,
        0.0,
    ];

    let img_f = cv::u8_to_f32(img)?;
    let scaled_f = cv::multiply_f32_scalar(&img_f, scales)?;
    let scaled8 = cv::f32_to_u8(&scaled_f)?;

    cv::copy_to_masked(&scaled8, img, doc_mask)
}

pub(crate) fn quad_to_image(quad: &Quad, mask: &Mask, image_size: (i32, i32)) -> Quad {
    quad.scaled_to(
        mask.width as f64,
        mask.height as f64,
        image_size.0 as f64,
        image_size.1 as f64,
    )
}
