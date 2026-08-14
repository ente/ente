//! Pointwise float arithmetic.
//!
//! Working precision follows OpenCV's `arithm_op`: array-array operations run
//! in the source depth (`float`), add/subtract/min/max against a scalar also
//! run in `float` (the scalar is narrowed), while multiply against a scalar
//! and `addWeighted` promote to `double` and narrow the result.

use rayon::prelude::*;

use crate::ml::document_scan::OpResult;
use crate::ml::document_scan::image::ImageF32;

/// Below this many elements the rayon split costs more than the work it saves.
const PARALLEL_MIN_ELEMS: usize = 200_000;

/// Fills `out` from `src` chunk by chunk, in parallel for large planes. Every
/// operation here is pointwise, so the split cannot change a single result.
fn fill<T: Send + Sync + Copy>(
    out: &mut [f32],
    src: &[T],
    chunk: usize,
    f: impl Fn(&mut [f32], &[T]) + Send + Sync,
) {
    if out.len() >= PARALLEL_MIN_ELEMS {
        out.par_chunks_mut(chunk)
            .zip(src.par_chunks(chunk))
            .for_each(|(o, s)| f(o, s));
    } else {
        f(out, src);
    }
}

/// Chunk length that keeps a chunk's first element on channel 0.
fn chunk_len(channels: i32) -> usize {
    65536 * channels as usize
}

fn same_geometry(a: &ImageF32, b: &ImageF32, op: &str) -> OpResult<()> {
    if !a.same_geometry(b) {
        return Err(format!("{op}: operands have different geometry"));
    }
    Ok(())
}

fn map1(a: &ImageF32, f: impl Fn(f32) -> f32 + Send + Sync) -> OpResult<ImageF32> {
    let mut data = vec![0.0f32; a.data.len()];
    fill(&mut data, &a.data, chunk_len(a.channels), |o, s| {
        for (o, &v) in o.iter_mut().zip(s.iter()) {
            *o = f(v);
        }
    });
    ImageF32::new(a.width, a.height, a.channels, data)
}

/// Two operands of identical geometry, elementwise.
fn map2(
    a: &ImageF32,
    b: &ImageF32,
    op: &str,
    f: impl Fn(f32, f32) -> f32 + Send + Sync,
) -> OpResult<ImageF32> {
    same_geometry(a, b, op)?;
    let mut data = vec![0.0f32; a.data.len()];
    let chunk = chunk_len(a.channels);
    if data.len() >= PARALLEL_MIN_ELEMS {
        data.par_chunks_mut(chunk)
            .zip(a.data.par_chunks(chunk))
            .zip(b.data.par_chunks(chunk))
            .for_each(|((o, x), y)| {
                for ((o, &x), &y) in o.iter_mut().zip(x.iter()).zip(y.iter()) {
                    *o = f(x, y);
                }
            });
    } else {
        for ((o, &x), &y) in data.iter_mut().zip(a.data.iter()).zip(b.data.iter()) {
            *o = f(x, y);
        }
    }
    ImageF32::new(a.width, a.height, a.channels, data)
}

/// Per-channel scalar as OpenCV unrolls it: `Scalar(v)` fills only `val[0]`.
fn map_scalar(
    a: &ImageF32,
    scalar: [f64; 4],
    f: impl Fn(f32, f64) -> f32 + Send + Sync,
) -> OpResult<ImageF32> {
    let cn = a.channels as usize;
    if cn > 4 {
        return Err("scalar operations support at most 4 channels".to_string());
    }
    let mut data = vec![0.0f32; a.data.len()];
    fill(&mut data, &a.data, chunk_len(a.channels), |o, s| {
        for (i, (o, &v)) in o.iter_mut().zip(s.iter()).enumerate() {
            *o = f(v, scalar[i % cn]);
        }
    });
    ImageF32::new(a.width, a.height, a.channels, data)
}

pub(crate) fn multiply_f32(a: &ImageF32, b: &ImageF32) -> OpResult<ImageF32> {
    map2(a, b, "multiply_f32", |x, y| x * y)
}

pub(crate) fn multiply_f32_scalar(a: &ImageF32, scalar: [f64; 4]) -> OpResult<ImageF32> {
    map_scalar(a, scalar, |v, s| (v as f64 * s) as f32)
}

pub(crate) fn add_f32_scalar(a: &ImageF32, scalar: f64) -> OpResult<ImageF32> {
    map_scalar(a, [scalar, 0.0, 0.0, 0.0], |v, s| v + s as f32)
}

pub(crate) fn subtract_f32_scalar(a: &ImageF32, scalar: f64) -> OpResult<ImageF32> {
    map_scalar(a, [scalar, 0.0, 0.0, 0.0], |v, s| v - s as f32)
}

pub(crate) fn subtract_f32(a: &ImageF32, b: &ImageF32) -> OpResult<ImageF32> {
    map2(a, b, "subtract_f32", |x, y| x - y)
}

pub(crate) fn add_weighted_f32(
    a: &ImageF32,
    alpha: f64,
    b: &ImageF32,
    beta: f64,
    gamma: f64,
) -> OpResult<ImageF32> {
    map2(a, b, "add_weighted_f32", |x, y| {
        (x as f64 * alpha + y as f64 * beta + gamma) as f32
    })
}

pub(crate) fn min_f32_scalar(a: &ImageF32, scalar: f64) -> OpResult<ImageF32> {
    map_scalar(a, [scalar, 0.0, 0.0, 0.0], |v, s| {
        let s = s as f32;
        if v < s { v } else { s }
    })
}

pub(crate) fn max_f32_scalar(a: &ImageF32, scalar: f64) -> OpResult<ImageF32> {
    map_scalar(a, [scalar, 0.0, 0.0, 0.0], |v, s| {
        let s = s as f32;
        if v > s { v } else { s }
    })
}

pub(crate) fn log_f32(a: &ImageF32) -> OpResult<ImageF32> {
    map1(a, |v| (v as f64).ln() as f32)
}

pub(crate) fn exp_f32(a: &ImageF32) -> OpResult<ImageF32> {
    map1(a, |v| (v as f64).exp() as f32)
}

/// `cv::magnitude`: `sqrt(x*x + y*y)` in `float`.
pub(crate) fn magnitude_f32(x: &ImageF32, y: &ImageF32) -> OpResult<ImageF32> {
    map2(x, y, "magnitude_f32", |a, b| (a * a + b * b).sqrt())
}
