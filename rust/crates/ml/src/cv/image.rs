use rayon::prelude::*;

use super::{OpResult, PARALLEL_MIN_ELEMS, saturate_u8_f32};

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct ImageU8 {
    pub width: i32,
    pub height: i32,
    pub channels: i32,
    pub data: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq)]
pub(crate) struct ImageF32 {
    pub width: i32,
    pub height: i32,
    pub channels: i32,
    pub data: Vec<f32>,
}

fn check_len(width: i32, height: i32, channels: i32, len: usize) -> OpResult<()> {
    if width <= 0 || height <= 0 || channels <= 0 {
        return Err(format!(
            "invalid image geometry {width}x{height}x{channels}"
        ));
    }
    let expected = width as usize * height as usize * channels as usize;
    if len != expected {
        return Err(format!(
            "image buffer length {len} does not match {width}x{height}x{channels} ({expected})"
        ));
    }
    Ok(())
}

impl ImageU8 {
    pub(crate) fn new(width: i32, height: i32, channels: i32, data: Vec<u8>) -> OpResult<Self> {
        check_len(width, height, channels, data.len())?;
        Ok(Self {
            width,
            height,
            channels,
            data,
        })
    }

    pub(crate) fn zeros(width: i32, height: i32, channels: i32) -> OpResult<Self> {
        if width <= 0 || height <= 0 || channels <= 0 {
            return Err(format!(
                "invalid image geometry {width}x{height}x{channels}"
            ));
        }
        let len = width as usize * height as usize * channels as usize;
        Ok(Self {
            width,
            height,
            channels,
            data: vec![0u8; len],
        })
    }

    pub(crate) fn size(&self) -> (i32, i32) {
        (self.width, self.height)
    }

    pub(crate) fn same_geometry(&self, other: &ImageU8) -> bool {
        self.width == other.width && self.height == other.height && self.channels == other.channels
    }

    pub(crate) fn to_f32(&self) -> ImageF32 {
        ImageF32 {
            width: self.width,
            height: self.height,
            channels: self.channels,
            data: map_vec(&self.data, |v| v as f32),
        }
    }
}

fn map_vec<T: Copy + Sync, U: Send>(src: &[T], f: impl Fn(T) -> U + Send + Sync) -> Vec<U> {
    if src.len() >= PARALLEL_MIN_ELEMS {
        src.par_iter().map(|&v| f(v)).collect()
    } else {
        src.iter().map(|&v| f(v)).collect()
    }
}

fn zip_vec<T: Copy + Sync, U: Send>(
    a: &[T],
    b: &[T],
    f: impl Fn(T, T) -> U + Send + Sync,
) -> Vec<U> {
    if a.len() >= PARALLEL_MIN_ELEMS {
        a.par_iter()
            .zip(b.par_iter())
            .map(|(&x, &y)| f(x, y))
            .collect()
    } else {
        a.iter().zip(b.iter()).map(|(&x, &y)| f(x, y)).collect()
    }
}

impl ImageF32 {
    pub(crate) fn new(width: i32, height: i32, channels: i32, data: Vec<f32>) -> OpResult<Self> {
        check_len(width, height, channels, data.len())?;
        Ok(Self {
            width,
            height,
            channels,
            data,
        })
    }

    pub(crate) fn zeros(width: i32, height: i32, channels: i32) -> OpResult<Self> {
        if width <= 0 || height <= 0 || channels <= 0 {
            return Err(format!(
                "invalid image geometry {width}x{height}x{channels}"
            ));
        }
        let len = width as usize * height as usize * channels as usize;
        Ok(Self {
            width,
            height,
            channels,
            data: vec![0.0f32; len],
        })
    }

    pub(crate) fn pixels(&self) -> usize {
        self.width as usize * self.height as usize
    }

    pub(crate) fn same_geometry(&self, other: &ImageF32) -> bool {
        self.width == other.width && self.height == other.height && self.channels == other.channels
    }

    fn like(&self, data: Vec<f32>) -> ImageF32 {
        ImageF32 {
            width: self.width,
            height: self.height,
            channels: self.channels,
            data,
        }
    }

    fn require_same(&self, other: &ImageF32) -> OpResult<()> {
        if self.same_geometry(other) {
            return Ok(());
        }
        Err(format!(
            "elementwise op on {}x{}x{} and {}x{}x{}",
            self.width, self.height, self.channels, other.width, other.height, other.channels
        ))
    }

    pub(crate) fn map(&self, f: impl Fn(f32) -> f32 + Send + Sync) -> ImageF32 {
        self.like(map_vec(&self.data, f))
    }

    pub(crate) fn map_mut(&mut self, f: impl Fn(f32) -> f32 + Send + Sync) {
        if self.data.len() >= PARALLEL_MIN_ELEMS {
            self.data.par_iter_mut().for_each(|v| *v = f(*v));
        } else {
            self.data.iter_mut().for_each(|v| *v = f(*v));
        }
    }

    pub(crate) fn map_to_u8(&self, f: impl Fn(f32) -> f32 + Send + Sync) -> ImageU8 {
        ImageU8 {
            width: self.width,
            height: self.height,
            channels: self.channels,
            data: map_vec(&self.data, |v| saturate_u8_f32(f(v))),
        }
    }

    pub(crate) fn zip_map(
        &self,
        other: &ImageF32,
        f: impl Fn(f32, f32) -> f32 + Send + Sync,
    ) -> OpResult<ImageF32> {
        self.require_same(other)?;
        Ok(self.like(zip_vec(&self.data, &other.data, f)))
    }

    pub(crate) fn zip_mut(
        &mut self,
        other: &ImageF32,
        f: impl Fn(&mut f32, f32) + Send + Sync,
    ) -> OpResult<()> {
        self.require_same(other)?;
        if self.data.len() >= PARALLEL_MIN_ELEMS {
            self.data
                .par_iter_mut()
                .zip(other.data.par_iter())
                .for_each(|(a, &b)| f(a, b));
        } else {
            self.data
                .iter_mut()
                .zip(other.data.iter())
                .for_each(|(a, &b)| f(a, b));
        }
        Ok(())
    }
}

#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Contour {
    pub points: Vec<(i32, i32)>,
    pub area: f64,
}
