//! Sampling without low-pass filtering; downstream calibration depends on that.

use fast_image_resize::{
    FilterType, PixelType, ResizeAlg, ResizeOptions, Resizer,
    images::{Image as FirImage, ImageRef as FirImageRef},
};

use crate::cv::OpResult;
use crate::cv::image::{Image, ImageF32, ImageRef, ImageU8};

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub(crate) enum Interp {
    Bilinear,
    Area,
    Bicubic,
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
    let src = FirImageRef::new(src_size.0 as u32, src_size.1 as u32, src_bytes, pixel_type)
        .map_err(|e| format!("resize: bad source: {e}"))?;
    let mut dst = FirImage::new(width as u32, height as u32, pixel_type);
    Resizer::new()
        .resize(&src, &mut dst, Some(&ResizeOptions::new().resize_alg(alg)))
        .map_err(|e| format!("resize failed: {e}"))?;
    Ok(dst.into_vec())
}

pub(crate) fn resize(
    src: ImageRef<'_>,
    width: i32,
    height: i32,
    interp: Interp,
) -> OpResult<Image> {
    let (sw, sh) = src.size();
    if width <= 0 || height <= 0 {
        return Err(format!("resize: invalid destination size {width}x{height}"));
    }
    if width == sw && height == sh {
        return Ok(match src {
            ImageRef::U8(i) => Image::U8(i.clone()),
            ImageRef::F32(i) => Image::F32(i.clone()),
        });
    }

    let alg = match interp {
        Interp::Bilinear => ResizeAlg::Interpolation(FilterType::Bilinear),
        Interp::Bicubic => ResizeAlg::Interpolation(FilterType::CatmullRom),
        Interp::Area if width >= sw && height >= sh => {
            ResizeAlg::Interpolation(FilterType::Bilinear)
        }
        Interp::Area => ResizeAlg::Convolution(FilterType::Box),
    };

    match src {
        ImageRef::U8(s) => {
            let data = run(
                &s.data,
                s.size(),
                pixel_type(s.channels, false)?,
                width,
                height,
                alg,
            )?;
            Ok(Image::U8(ImageU8::new(width, height, s.channels, data)?))
        }
        ImageRef::F32(s) => {
            let bytes: Vec<u8> = s.data.iter().flat_map(|v| v.to_ne_bytes()).collect();
            let out = run(
                &bytes,
                (s.width, s.height),
                pixel_type(s.channels, true)?,
                width,
                height,
                alg,
            )?;
            let data: Vec<f32> = out
                .chunks_exact(4)
                .map(|b| f32::from_ne_bytes([b[0], b[1], b[2], b[3]]))
                .collect();
            Ok(Image::F32(ImageF32::new(width, height, s.channels, data)?))
        }
    }
}
