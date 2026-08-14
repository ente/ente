//! Unit tests for the pure-math pieces.

use super::contour_orientation::find_quad_from_contour_orientation;
use super::detection::min_area_rect;
use super::geometry::{ImageSize, Point, Quad, create_quad, norm};
use super::perspective::{EstimatedDimensions, estimate_real_dimensions};

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
    // Collinear points bound no area.
    assert!(min_area_rect(&[(0, 0), (5, 5), (10, 10)], 256, 256).is_none());
}

#[test]
fn create_quad_orders_corners_by_angle_from_centroid() {
    // Screen coordinates (y down): atan2 ascending starts at the top-left.
    let vertices = vec![
        Point::new(100.0, 100.0),
        Point::new(0.0, 100.0),
        Point::new(0.0, 0.0),
        Point::new(100.0, 0.0),
    ];
    let quad = create_quad(&vertices);
    assert_eq!(quad.top_left, Point::new(0.0, 0.0));
    assert_eq!(quad.top_right, Point::new(100.0, 0.0));
    assert_eq!(quad.bottom_right, Point::new(100.0, 100.0));
    assert_eq!(quad.bottom_left, Point::new(0.0, 100.0));
}

#[test]
fn create_quad_is_idempotent() {
    let quad = create_quad(&[
        Point::new(10.0, 12.0),
        Point::new(90.0, 8.0),
        Point::new(95.0, 70.0),
        Point::new(5.0, 74.0),
    ]);
    let again = create_quad(&quad.corners());
    assert_eq!(quad.top_left, again.top_left);
    assert_eq!(quad.top_right, again.top_right);
    assert_eq!(quad.bottom_right, again.bottom_right);
    assert_eq!(quad.bottom_left, again.bottom_left);
}

#[test]
fn scaled_to_maps_mask_space_to_image_space() {
    let quad = Quad {
        top_left: Point::new(0.0, 0.0),
        top_right: Point::new(128.0, 0.0),
        bottom_right: Point::new(128.0, 256.0),
        bottom_left: Point::new(0.0, 256.0),
    };
    let scaled = quad.scaled_to(256.0, 256.0, 1024.0, 512.0);
    assert_close(scaled.top_right.x, 512.0, 1e-9);
    assert_close(scaled.bottom_right.y, 512.0, 1e-9);
}

#[test]
fn norm_matches_hypot() {
    assert_close(norm(Point::new(0.0, 0.0), Point::new(3.0, 4.0)), 5.0, 1e-12);
}

#[test]
fn image_size_keeps_doubles() {
    let size = ImageSize::new(1024.0, 768.0);
    assert_close(size.width, 1024.0, 0.0);
    assert_close(size.height, 768.0, 0.0);
}

fn rect_quad(w: f64, h: f64) -> Quad {
    Quad {
        top_left: Point::new(0.0, 0.0),
        top_right: Point::new(w, 0.0),
        bottom_right: Point::new(w, h),
        bottom_left: Point::new(0.0, h),
    }
}

#[test]
fn estimate_real_dimensions_falls_back_for_parallel_sides() {
    // A perfect rectangle has both vanishing points at infinity, so the
    // average-sides fallback applies.
    let quad = rect_quad(400.0, 300.0);
    let dims = estimate_real_dimensions(&quad, 1000, 800, None);
    assert_eq!(
        dims,
        EstimatedDimensions::Ratio {
            width: 400.0,
            height: 300.0
        }
    );
}

#[test]
fn estimate_real_dimensions_falls_back_for_weak_perspective() {
    // Barely trapezoidal: f exceeds max(w,h)*1.2, so the fallback applies.
    let quad = Quad {
        top_left: Point::new(100.0, 100.0),
        top_right: Point::new(900.0, 100.0),
        bottom_right: Point::new(899.0, 700.0),
        bottom_left: Point::new(101.0, 700.0),
    };
    let dims = estimate_real_dimensions(&quad, 1000, 800, None);
    match dims {
        EstimatedDimensions::Ratio { width, height } => {
            assert_close(width, 799.0, 1e-9);
            assert_close(height, 600.0008333, 1e-6);
        }
        other => panic!("expected Ratio, got {other:?}"),
    }
}

#[test]
fn snap_to_standard_format_is_a_noop_for_ratio() {
    let dims = EstimatedDimensions::Ratio {
        width: 210.0,
        height: 297.0,
    };
    assert_eq!(dims.snap_to_standard_format(), dims);
}

#[test]
fn snap_to_standard_format_snaps_physical_to_a4() {
    let dims = EstimatedDimensions::Physical {
        width_mm: 208.0,
        height_mm: 294.0,
    };
    assert_eq!(
        dims.snap_to_standard_format(),
        EstimatedDimensions::Physical {
            width_mm: 210.0,
            height_mm: 297.0
        }
    );
}

#[test]
fn to_pixel_dimensions_preserves_area_and_ratio() {
    let quad = rect_quad(400.0, 300.0);
    let dims = estimate_real_dimensions(&quad, 1000, 800, None).snap_to_standard_format();
    let (w, h) = dims.to_pixel_dimensions(&quad);
    assert_close(w * h, 400.0 * 300.0, 1e-6);
    assert_close(h / w, 300.0 / 400.0, 1e-12);
}

#[test]
fn contour_orientation_recovers_a_rotated_rectangle() {
    // Dense sampling of a slightly rotated rectangle outline; the four fitted
    // sides must intersect back at the corners.
    let corners = [
        Point::new(40.0, 30.0),
        Point::new(220.0, 50.0),
        Point::new(200.0, 190.0),
        Point::new(20.0, 170.0),
    ];
    let mut contour = Vec::new();
    for i in 0..4 {
        let a = corners[i];
        let b = corners[(i + 1) % 4];
        let steps = 60;
        for s in 0..steps {
            let t = s as f64 / steps as f64;
            contour.push(Point::new(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t));
        }
    }
    let quad = find_quad_from_contour_orientation(&contour).expect("quad from contour orientation");
    assert_eq!(quad.len(), 4);
    for corner in corners {
        let best = quad
            .iter()
            .map(|p| norm(*p, corner))
            .fold(f64::INFINITY, f64::min);
        assert!(
            best < 1.0,
            "corner {corner:?} not recovered (min dist {best})"
        );
    }
}

#[test]
fn contour_orientation_rejects_short_contours() {
    let contour: Vec<Point> = (0..19).map(|i| Point::new(i as f64, 0.0)).collect();
    assert!(find_quad_from_contour_orientation(&contour).is_none());
}
