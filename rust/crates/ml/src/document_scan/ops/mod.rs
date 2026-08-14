//! The image operations the scanner pipeline is built from: pointwise
//! arithmetic, filters, morphology, color conversions, and wrappers around
//! `fast_image_resize`/`imageproc` for resizing, rasterization, contour
//! tracing and warping.

mod arith;
mod bilateral;
mod canny;
mod channels;
mod contours;
mod convert;
mod draw;
mod filter;
mod lab;
mod masking;
mod morph;
mod resize;
mod stats;
mod structuring;
mod transform;
mod warp;

use rayon::prelude::*;

use super::OpResult;
use super::image::{Image, ImageRef};

pub(crate) use arith::{
    add_f32_scalar, add_weighted_f32, exp_f32, log_f32, magnitude_f32, max_f32_scalar,
    min_f32_scalar, multiply_f32, multiply_f32_scalar, subtract_f32, subtract_f32_scalar,
};
pub(crate) use bilateral::bilateral_filter_u8;
pub(crate) use canny::canny;
pub(crate) use channels::{bgr_to_gray, bgr_to_rgb, gray_to_bgr, merge_u8, split_u8};
pub(crate) use contours::find_contours;
pub(crate) use convert::{f32_to_u8, u8_to_f32};
pub(crate) use draw::fill_poly;
pub(crate) use filter::{box_filter_f32, gaussian_blur_u8};
pub(crate) use lab::{bgr_to_lab, lab_to_bgr};
pub(crate) use masking::{
    bitwise_and_u8, copy_to_masked, count_non_zero, in_range_u8, threshold_binary_f32,
    threshold_binary_u8,
};
pub(crate) use morph::{morphology_close, morphology_erode, morphology_open};
pub(crate) use stats::{
    hist_256_f32, hist_256_u8, mean_f32, mean_u8c3_masked, min_max_loc_f32, percentile_f32, sum_f32,
};
pub(crate) use structuring::ellipse_kernel;
pub(crate) use transform::rotate_u8;
pub(crate) use warp::warp_perspective;

use resize::Interp;

pub(crate) fn resize_bilinear(src: ImageRef<'_>, width: i32, height: i32) -> OpResult<Image> {
    resize::resize(src, width, height, Interp::Bilinear)
}

pub(crate) fn resize_area(src: ImageRef<'_>, width: i32, height: i32) -> OpResult<Image> {
    resize::resize(src, width, height, Interp::Area)
}

pub(crate) fn resize_bicubic(src: ImageRef<'_>, width: i32, height: i32) -> OpResult<Image> {
    resize::resize(src, width, height, Interp::Bicubic)
}

/// Below this many pixels the rayon split costs more than the work it saves.
const PARALLEL_MIN_PIXELS: usize = 65_536;
/// Pixels per parallel chunk. Chunk boundaries land on pixel boundaries, so a
/// chunk's first element is always channel 0.
const PIXELS_PER_CHUNK: usize = 65_536;

/// Runs a pointwise fill over `out` in parallel for large planes.
///
/// `out_stride` and `src_stride` are elements per pixel on each side. Every
/// caller computes output pixel `i` from input pixel `i` alone, so splitting
/// the buffers on a pixel boundary cannot change a single result.
pub(crate) fn pointwise<T: Sync, U: Send>(
    out: &mut [U],
    out_stride: usize,
    src: &[T],
    src_stride: usize,
    f: impl Fn(&mut [U], &[T]) + Send + Sync,
) {
    if out.len() / out_stride.max(1) < PARALLEL_MIN_PIXELS {
        f(out, src);
        return;
    }
    out.par_chunks_mut(PIXELS_PER_CHUNK * out_stride)
        .zip(src.par_chunks(PIXELS_PER_CHUNK * src_stride))
        .for_each(|(o, s)| f(o, s));
}

/// [`pointwise`] with two aligned inputs.
pub(crate) fn pointwise3<T: Sync, V: Sync, U: Send>(
    out: &mut [U],
    out_stride: usize,
    a: &[T],
    a_stride: usize,
    b: &[V],
    b_stride: usize,
    f: impl Fn(&mut [U], &[T], &[V]) + Send + Sync,
) {
    if out.len() / out_stride.max(1) < PARALLEL_MIN_PIXELS {
        f(out, a, b);
        return;
    }
    out.par_chunks_mut(PIXELS_PER_CHUNK * out_stride)
        .zip(a.par_chunks(PIXELS_PER_CHUNK * a_stride))
        .zip(b.par_chunks(PIXELS_PER_CHUNK * b_stride))
        .for_each(|((o, a), b)| f(o, a, b));
}

/// Round half to even, then clamp into u8.
pub(crate) fn saturate_u8_f32(v: f32) -> u8 {
    v.round_ties_even().clamp(0.0, 255.0) as u8
}

/// Round half to even, then clamp into u8.
pub(crate) fn saturate_u8_f64(v: f64) -> u8 {
    v.round_ties_even().clamp(0.0, 255.0) as u8
}

/// Maps an out-of-range coordinate back inside `[0, len)` by mirroring
/// without repeating the edge pixel — the border rule of every filter in
/// this module.
pub(crate) fn reflect101(mut p: i64, len: i32) -> i64 {
    let len = len as i64;
    if p >= 0 && p < len {
        return p;
    }
    if len == 1 {
        return 0;
    }
    loop {
        if p < 0 {
            p = -p;
        } else {
            p = len - 1 - (p - len) - 1;
        }
        if p >= 0 && p < len {
            return p;
        }
    }
}
