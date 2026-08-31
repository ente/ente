use super::OpResult;
use super::color::ColorMode;
use super::contour_orientation::find_quad_from_contour_orientation;
use super::geometry::{ImageSize, Point, Quad, create_quad};
use super::mask::Mask;
use super::perspective::estimate_real_dimensions;
use super::postprocess::enhance_captured_image;
use super::quad_score::score_quad_against_probmap;
use crate::cv;
use crate::cv::image::{Contour, ImageU8};

const THRESHOLDS: [f64; 7] = [0.5, 0.7, 0.75, 0.8, 0.85, 0.9, 0.95];
const LIVE_THRESHOLDS: [f64; 1] = [0.9];

pub(crate) fn size_trunc(width: f64, height: f64) -> (i32, i32) {
    (width as i32, height as i32)
}

pub(crate) fn detect_document_quad(
    mask: &Mask,
    original_size: ImageSize,
    is_live_analysis: bool,
) -> OpResult<Option<Quad>> {
    let prob_image = mask.prob_image()?;
    let thresholds: &[f64] = if is_live_analysis {
        &LIVE_THRESHOLDS
    } else {
        &THRESHOLDS
    };

    let mut vertices =
        find_quad_from_orientation_with_adaptive_threshold(&prob_image, original_size, thresholds)?;

    if vertices.is_none() && !is_live_analysis {
        // Fallback: min-area rectangle of the biggest contour.
        if let Some(biggest) = biggest_contour(&refine_mask(&mask.binary_image()?)?)? {
            vertices = min_area_rect(&biggest.points, mask.width, mask.height);
        }
    }

    Ok(match vertices {
        Some(v) if v.len() == 4 => Some(create_quad(&v)),
        _ => None,
    })
}

fn find_quad_from_orientation_with_adaptive_threshold(
    prob_image: &ImageU8,
    original_size: ImageSize,
    thresholds: &[f64],
) -> OpResult<Option<Vec<Point>>> {
    let probmap_smooth = cv::gaussian_blur_u8(prob_image, 3)?;

    let kernel = cv::ellipse_kernel(5)?;
    let prob_float = prob_image.to_f32();
    let mut best_quad: Option<Vec<Point>> = None;
    let mut best_score = 0.0f64;

    for &thr in thresholds {
        let bin = cv::threshold_binary_u8(&probmap_smooth, thr * 255.0, 255.0)?;
        let closed = cv::morphology_close(&bin, &kernel)?;

        if let Some(quad) = find_quad_from_orientation(&closed, original_size, &kernel)?
            && is_valid_quad(&quad)
        {
            let score = score_quad_against_probmap(&quad, &prob_float, 0.02)?;
            if score > best_score {
                best_score = score;
                best_quad = Some(quad);
            }
        }
    }

    Ok(best_quad)
}

/// Deliberately no upper bound: edge-touching documents put corners past the mask edge.
pub(crate) fn is_valid_quad(quad: &[Point]) -> bool {
    quad.iter().all(|p| p.x >= 0.0 && p.y >= 0.0)
}

fn find_quad_from_orientation(
    closed: &ImageU8,
    original_size: ImageSize,
    kernel: &ImageU8,
) -> OpResult<Option<Vec<Point>>> {
    let opened = cv::morphology_open(closed, kernel)?;
    let Some(contour) = biggest_contour(&opened)? else {
        return Ok(None);
    };

    let scale_x = original_size.width / opened.width as f64;
    let scale_y = original_size.height / opened.height as f64;

    let scaled: Vec<Point> = contour
        .points
        .iter()
        .map(|&(x, y)| Point::new(x as f64 * scale_x, y as f64 * scale_y))
        .collect();

    Ok(find_quad_from_contour_orientation(&scaled).map(|corners| {
        corners
            .iter()
            .map(|p| Point::new(p.x / scale_x, p.y / scale_y))
            .collect()
    }))
}

pub(crate) fn min_area_rect(points: &[(i32, i32)], width: i32, height: i32) -> Option<Vec<Point>> {
    if points.len() < 3 {
        return None;
    }
    let pts: Vec<imageproc::point::Point<i32>> = points
        .iter()
        .map(|&(x, y)| imageproc::point::Point::new(x, y))
        .collect();
    let rect = imageproc::geometry::min_area_rect(&pts);
    if imageproc::geometry::contour_area(&rect) == 0.0 {
        return None;
    }
    Some(
        rect.iter()
            .map(|p| {
                Point::new(
                    (p.x as f64).clamp(0.0, width as f64 - 1.0),
                    (p.y as f64).clamp(0.0, height as f64 - 1.0),
                )
            })
            .collect(),
    )
}

pub(crate) fn biggest_contour(refined: &ImageU8) -> OpResult<Option<Contour>> {
    let blurred = cv::gaussian_blur_u8(refined, 5)?;
    let edges = cv::canny(&blurred, 75.0, 200.0)?;
    let contours = cv::find_contours(&edges)?;

    let mut biggest: Option<Contour> = None;
    let mut max_area = 0.0f64;
    for contour in contours {
        let area = contour.area.abs();
        if area > max_area {
            max_area = area;
            biggest = Some(contour);
        }
    }
    Ok(biggest)
}

fn refine_mask(original: &ImageU8) -> OpResult<ImageU8> {
    let binary_mask = cv::threshold_binary_u8(original, 128.0, 255.0)?;
    let kernel = cv::ellipse_kernel(5)?;
    let closed = cv::morphology_close(&binary_mask, &kernel)?;
    cv::morphology_open(&closed, &kernel)
}

pub(crate) fn resize_for_max_pixels(img: &ImageU8, max_pixels: f64) -> OpResult<ImageU8> {
    let orig_pixels = img.width as i64 * img.height as i64;
    if orig_pixels as f64 <= max_pixels {
        return Ok(img.clone());
    }
    let scale = (max_pixels / orig_pixels as f64).sqrt();
    let (width, height) = size_trunc(img.width as f64 * scale, img.height as f64 * scale);
    cv::resize_u8(img, width, height, cv::Interp::Area)
}

pub(crate) fn extract_document(
    input: &ImageU8,
    quad: &Quad,
    rotation_degrees: i32,
    color_mode: ColorMode,
    max_pixels: f64,
) -> OpResult<ImageU8> {
    let estimated = estimate_real_dimensions(quad, input.width, input.height);
    let (target_width, target_height) = estimated.to_pixel_dimensions(quad);

    let corners = quad.corners();
    let src_corners = [
        (corners[0].x, corners[0].y),
        (corners[1].x, corners[1].y),
        (corners[2].x, corners[2].y),
        (corners[3].x, corners[3].y),
    ];
    let dst_corners = [
        (0.0, 0.0),
        (target_width, 0.0),
        (target_width, target_height),
        (0.0, target_height),
    ];

    let (out_width, out_height) = size_trunc(target_width, target_height);
    let warped = cv::warp_perspective(input, src_corners, dst_corners, out_width, out_height)?;

    let resized = resize_for_max_pixels(&warped, max_pixels)?;
    let enhanced = enhance_captured_image(&resized, color_mode)?;
    cv::rotate_u8(&enhanced, rotation_degrees)
}

#[cfg(test)]
mod tests {
    use super::min_area_rect;

    fn assert_close(a: f64, b: f64, eps: f64) {
        assert!((a - b).abs() <= eps, "expected {a} ~= {b} (eps {eps})");
    }

    #[test]
    fn min_area_rect_of_axis_aligned_box() {
        let polygon = vec![(10, 20), (60, 20), (60, 90), (10, 90), (35, 55)];
        let rect = min_area_rect(&polygon, 256, 256).expect("rect");
        assert_eq!(rect.len(), 4);
        let xs: Vec<f64> = rect.iter().map(|p| p.x).collect();
        let ys: Vec<f64> = rect.iter().map(|p| p.y).collect();
        assert_close(xs.iter().cloned().fold(f64::INFINITY, f64::min), 10.0, 1e-9);
        assert_close(
            xs.iter().cloned().fold(f64::NEG_INFINITY, f64::max),
            60.0,
            1e-9,
        );
        assert_close(ys.iter().cloned().fold(f64::INFINITY, f64::min), 20.0, 1e-9);
        assert_close(
            ys.iter().cloned().fold(f64::NEG_INFINITY, f64::max),
            90.0,
            1e-9,
        );
    }

    #[test]
    fn min_area_rect_clips_to_image_bounds() {
        let polygon = vec![(-30, -30), (500, -30), (500, 500), (-30, 500)];
        let rect = min_area_rect(&polygon, 256, 256).expect("rect");
        for p in &rect {
            assert!((0.0..=255.0).contains(&p.x), "x out of bounds: {p:?}");
            assert!((0.0..=255.0).contains(&p.y), "y out of bounds: {p:?}");
        }
    }

    #[test]
    fn min_area_rect_rejects_degenerate_input() {
        assert!(min_area_rect(&[(0, 0), (1, 1)], 256, 256).is_none());
        assert!(min_area_rect(&[(0, 0), (5, 5), (10, 10)], 256, 256).is_none());
    }
}
