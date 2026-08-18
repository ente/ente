use image::{Rgb, RgbImage};
use imageproc::geometric_transformations::{Interpolation, Projection, warp_into};

use crate::cv::OpResult;
use crate::cv::image::ImageU8;

pub(crate) fn warp_perspective(
    src: &ImageU8,
    src_corners: [(f64, f64); 4],
    dst_corners: [(f64, f64); 4],
    width: i32,
    height: i32,
) -> OpResult<ImageU8> {
    if width <= 0 || height <= 0 {
        return Err(format!(
            "warp_perspective: invalid destination size {width}x{height}"
        ));
    }
    if src.channels != 3 {
        return Err(format!(
            "warp_perspective: expected a 3-channel image, got {}",
            src.channels
        ));
    }
    let narrow = |c: [(f64, f64); 4]| c.map(|(x, y)| (x as f32, y as f32));
    let projection = Projection::from_control_points(narrow(src_corners), narrow(dst_corners))
        .ok_or_else(|| "warp_perspective: the corner pairs are degenerate".to_string())?;

    let source = RgbImage::from_raw(src.width as u32, src.height as u32, src.data.clone())
        .ok_or_else(|| "warp_perspective: source buffer mismatch".to_string())?;
    let mut out = RgbImage::new(width as u32, height as u32);
    warp_into(
        &source,
        &projection,
        Interpolation::Bilinear,
        Rgb([0, 0, 0]),
        &mut out,
    );
    ImageU8::new(width, height, 3, out.into_raw())
}
