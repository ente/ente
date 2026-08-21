//! Sampling without low-pass filtering; downstream calibration depends on that.

use fast_image_resize::{
    FilterType, PixelType, ResizeAlg, ResizeOptions, Resizer,
    images::{Image as FirImage, ImageRef as FirImageRef},
};

use crate::cv::OpResult;
use crate::cv::image::{ImageF32, ImageU8};

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub(crate) enum Interp {
    Bilinear,
    Area,
    Bicubic,
}

impl Interp {
    fn alg(self, upscaling: bool) -> ResizeAlg {
        match self {
            Interp::Bilinear => ResizeAlg::Interpolation(FilterType::Bilinear),
            Interp::Bicubic => ResizeAlg::Interpolation(FilterType::CatmullRom),
            Interp::Area if upscaling => ResizeAlg::Interpolation(FilterType::Bilinear),
            Interp::Area => ResizeAlg::Convolution(FilterType::Box),
        }
    }
}

fn pixel_type(channels: i32, is_f32: bool) -> OpResult<PixelType> {
    Ok(match (is_f32, channels) {
        (false, 1) => PixelType::U8,
        (false, 3) => PixelType::U8x3,
        (true, 1) => PixelType::F32,
        (true, 3) => PixelType::F32x3,
        (is_f32, n) => {
            return Err(format!(
                "resize: unsupported {n}-channel {} image",
                if is_f32 { "f32" } else { "u8" }
            ));
        }
    })
}

fn run(
    src_bytes: &[u8],
    src_size: (i32, i32),
    pixel_type: PixelType,
    width: i32,
    height: i32,
    alg: ResizeAlg,
) -> OpResult<Vec<u8>> {
    if width <= 0 || height <= 0 {
        return Err(format!("resize: invalid destination size {width}x{height}"));
    }
    let src = FirImageRef::new(src_size.0 as u32, src_size.1 as u32, src_bytes, pixel_type)
        .map_err(|e| format!("resize: bad source: {e}"))?;
    let mut dst = FirImage::new(width as u32, height as u32, pixel_type);
    Resizer::new()
        .resize(&src, &mut dst, Some(&ResizeOptions::new().resize_alg(alg)))
        .map_err(|e| format!("resize failed: {e}"))?;
    Ok(dst.into_vec())
}

pub(crate) fn resize_u8(
    src: &ImageU8,
    width: i32,
    height: i32,
    interp: Interp,
) -> OpResult<ImageU8> {
    if width == src.width && height == src.height {
        return Ok(src.clone());
    }
    let data = run(
        &src.data,
        (src.width, src.height),
        pixel_type(src.channels, false)?,
        width,
        height,
        interp.alg(width >= src.width && height >= src.height),
    )?;
    ImageU8::new(width, height, src.channels, data)
}

pub(crate) fn resize_f32(
    src: &ImageF32,
    width: i32,
    height: i32,
    interp: Interp,
) -> OpResult<ImageF32> {
    if width == src.width && height == src.height {
        return Ok(src.clone());
    }
    let bytes: Vec<u8> = src.data.iter().flat_map(|v| v.to_ne_bytes()).collect();
    let out = run(
        &bytes,
        (src.width, src.height),
        pixel_type(src.channels, true)?,
        width,
        height,
        interp.alg(width >= src.width && height >= src.height),
    )?;
    let data = out
        .chunks_exact(4)
        .map(|b| f32::from_ne_bytes([b[0], b[1], b[2], b[3]]))
        .collect();
    ImageF32::new(width, height, src.channels, data)
}
