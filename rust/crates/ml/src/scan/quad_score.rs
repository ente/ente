use super::OpResult;
use super::geometry::Point;
use crate::cv;
use crate::cv::image::{ImageF32, ImageU8};

pub(crate) fn make_polygon_mask(width: i32, height: i32, polygon: &[Point]) -> OpResult<ImageU8> {
    let pts: Vec<(i32, i32)> = polygon.iter().map(|p| (p.x as i32, p.y as i32)).collect();
    cv::fill_poly(width, height, &pts, 1.0)
}

pub(crate) fn score_quad_against_probmap(
    quad: &[Point],
    probmap: &ImageF32,
    min_quad_area_ratio: f64,
) -> OpResult<f64> {
    let mask = make_polygon_mask(probmap.width, probmap.height, quad)?;

    let mut sum_masked = 0.0f64;
    let mut sum_mask = 0.0f64;
    for (&prob, &inside) in probmap.data.iter().zip(mask.data.iter()) {
        let inside = inside as f32;
        sum_masked += (prob * inside) as f64;
        sum_mask += inside as f64;
    }
    let mean_prob = sum_masked / sum_mask;
    let area_ratio = sum_mask / (probmap.height * probmap.width) as f64;

    Ok(if area_ratio < min_quad_area_ratio {
        0.0
    } else {
        mean_prob * (0.7 + 0.3 * area_ratio)
    })
}
