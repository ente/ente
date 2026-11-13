use image::RgbImage;
use imageproc::geometric_transformations::Projection;

use crate::cv::OpResult;
use crate::cv::image::ImageU8;

pub(crate) fn warp_rgb_perspective(
    source: &RgbImage,
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
    let narrow = |c: [(f64, f64); 4]| c.map(|(x, y)| (x as f32, y as f32));
    let projection = Projection::from_control_points(narrow(src_corners), narrow(dst_corners))
        .ok_or_else(|| "warp_perspective: the corner pairs are degenerate".to_string())?;
    let out = super::warp_rgb::warp(source, projection, width as u32, height as u32);
    ImageU8::new(width, height, 3, out.into_raw())
}
