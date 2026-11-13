use image::GrayImage;
use imageproc::contours::BorderType;

use crate::cv::OpResult;
use crate::cv::image::{Contour, ImageU8};

pub(crate) fn find_contours(src: &ImageU8) -> OpResult<Vec<Contour>> {
    if src.channels != 1 {
        return Err(format!(
            "find_contours: expected a single-channel image, got {}",
            src.channels
        ));
    }
    let img = GrayImage::from_raw(src.width as u32, src.height as u32, src.data.clone())
        .ok_or_else(|| "find_contours: source buffer mismatch".to_string())?;
    Ok(imageproc::contours::find_contours::<i32>(&img)
        .into_iter()
        .map(|c| {
            let area = imageproc::geometry::contour_area(&c.points);
            let outer = c.border_type == BorderType::Outer;
            Contour {
                points: c.points.into_iter().map(|p| (p.x, p.y)).collect(),
                area,
                outer,
            }
        })
        .collect())
}
