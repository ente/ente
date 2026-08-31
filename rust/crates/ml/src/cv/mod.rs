mod bilateral;
mod canny;
mod channels;
mod contours;
mod draw;
mod filter;
pub(crate) mod image;
mod lab;
mod masking;
mod morph;
mod resize;
mod stats;
mod structuring;
mod transform;
mod warp;

use rayon::prelude::*;

pub(crate) type OpResult<T> = Result<T, String>;

pub(crate) use bilateral::bilateral_filter_u8;
pub(crate) use canny::canny;
pub(crate) use channels::{bgr_to_gray, gray_to_bgr, merge_u8, split_u8};
pub(crate) use contours::find_contours;
pub(crate) use draw::fill_poly;
pub(crate) use filter::{box_filter_f32, gaussian_blur_u8};
pub(crate) use lab::{bgr_to_lab, lab_to_bgr};
pub(crate) use masking::{
    bitwise_and_u8, copy_to_masked, count_non_zero, in_range_u8, threshold_binary_u8,
};
pub(crate) use morph::{morphology_close, morphology_erode, morphology_open};
pub(crate) use resize::{Interp, resize_f32, resize_u8};
pub(crate) use stats::{
    hist_256_f32, hist_256_u8, mean_f32, mean_u8c3_masked, min_max_loc_f32, percentile_f32,
    percentile_pair_f32,
};
pub(crate) use structuring::ellipse_kernel;
pub(crate) use transform::rotate_u8;
pub(crate) use warp::warp_perspective;

pub(crate) const PARALLEL_MIN_ELEMS: usize = 200_000;
const PIXELS_PER_CHUNK: usize = 65_536;

pub(crate) fn pointwise<T: Sync, U: Send>(
    out: &mut [U],
    out_stride: usize,
    src: &[T],
    src_stride: usize,
    f: impl Fn(&mut [U], &[T]) + Send + Sync,
) {
    if out.len() < PARALLEL_MIN_ELEMS {
        f(out, src);
        return;
    }
    out.par_chunks_mut(PIXELS_PER_CHUNK * out_stride)
        .zip(src.par_chunks(PIXELS_PER_CHUNK * src_stride))
        .for_each(|(o, s)| f(o, s));
}

pub(crate) fn pointwise3<T: Sync, V: Sync, U: Send>(
    out: &mut [U],
    out_stride: usize,
    a: &[T],
    a_stride: usize,
    b: &[V],
    b_stride: usize,
    f: impl Fn(&mut [U], &[T], &[V]) + Send + Sync,
) {
    if out.len() < PARALLEL_MIN_ELEMS {
        f(out, a, b);
        return;
    }
    out.par_chunks_mut(PIXELS_PER_CHUNK * out_stride)
        .zip(a.par_chunks(PIXELS_PER_CHUNK * a_stride))
        .zip(b.par_chunks(PIXELS_PER_CHUNK * b_stride))
        .for_each(|((o, a), b)| f(o, a, b));
}

pub(crate) fn saturate_u8_f32(v: f32) -> u8 {
    v.round_ties_even().clamp(0.0, 255.0) as u8
}

pub(crate) fn saturate_u8_f64(v: f64) -> u8 {
    v.round_ties_even().clamp(0.0, 255.0) as u8
}

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
