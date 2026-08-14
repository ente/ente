//! Unit tests for the pure-math pieces, plus the fill_poly golden-mask
//! differential (120 polygon masks rendered once by OpenCV 4.9, committed
//! under `tests/data/document_scan/fill_poly_goldens/` — the oracle for the
//! <= 4.10 LINE_8 rasterization rule this port implements).

use std::path::{Path, PathBuf};

use serde_json::Value;

use super::contour_orientation::find_quad_from_contour_orientation;
use super::geometry::{ImageSize, Point, Quad, create_quad, norm};
use super::min_area_rect::{convex_hull, min_area_rect};
use super::ops;
use super::perspective::{EstimatedDimensions, estimate_real_dimensions};

fn assert_close(a: f64, b: f64, eps: f64) {
    assert!((a - b).abs() <= eps, "expected {a} ~= {b} (eps {eps})");
}

#[test]
fn convex_hull_of_square_with_interior_points() {
    let points = vec![
        Point::new(0.0, 0.0),
        Point::new(5.0, 5.0),
        Point::new(10.0, 0.0),
        Point::new(10.0, 10.0),
        Point::new(0.0, 10.0),
        Point::new(2.0, 3.0),
    ];
    let hull = convex_hull(&points);
    assert_eq!(hull.len(), 4);
    for corner in [
        Point::new(0.0, 0.0),
        Point::new(10.0, 0.0),
        Point::new(10.0, 10.0),
        Point::new(0.0, 10.0),
    ] {
        assert!(hull.contains(&corner), "hull {hull:?} misses {corner:?}");
    }
}

#[test]
fn convex_hull_drops_collinear_points() {
    let points = vec![
        Point::new(0.0, 0.0),
        Point::new(5.0, 0.0),
        Point::new(10.0, 0.0),
        Point::new(10.0, 10.0),
        Point::new(0.0, 10.0),
    ];
    let hull = convex_hull(&points);
    assert_eq!(hull.len(), 4);
    assert!(!hull.contains(&Point::new(5.0, 0.0)));
}

#[test]
fn convex_hull_deduplicates_keeping_first_occurrence() {
    let points = vec![
        Point::new(1.0, 1.0),
        Point::new(1.0, 1.0),
        Point::new(2.0, 2.0),
    ];
    let hull = convex_hull(&points);
    assert_eq!(hull.len(), 2);
}

#[test]
fn min_area_rect_of_axis_aligned_box() {
    let polygon = vec![
        Point::new(10.0, 20.0),
        Point::new(60.0, 20.0),
        Point::new(60.0, 90.0),
        Point::new(10.0, 90.0),
        Point::new(35.0, 55.0),
    ];
    let rect = min_area_rect(&polygon, None, None).expect("rect");
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
    let polygon = vec![
        Point::new(-30.0, -30.0),
        Point::new(500.0, -30.0),
        Point::new(500.0, 500.0),
        Point::new(-30.0, 500.0),
    ];
    let rect = min_area_rect(&polygon, Some(256), Some(256)).expect("rect");
    for p in &rect {
        assert!((0.0..=255.0).contains(&p.x), "x out of bounds: {p:?}");
        assert!((0.0..=255.0).contains(&p.y), "y out of bounds: {p:?}");
    }
}

#[test]
fn min_area_rect_needs_three_points() {
    assert!(min_area_rect(&[Point::new(0.0, 0.0), Point::new(1.0, 1.0)], None, None).is_none());
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

// ---------------------------------------------------------------------------
// fill_poly goldens
// ---------------------------------------------------------------------------

fn goldens_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/data/document_scan/fill_poly_goldens")
}

struct Golden {
    id: String,
    category: String,
    width: i32,
    height: i32,
    value: f64,
    nonzero: usize,
    polygon: Vec<(i32, i32)>,
    mask: Vec<u8>,
}

fn load_goldens() -> (Vec<Golden>, String) {
    let dir = goldens_dir();
    let index_path = dir.join("index.json");
    let raw = std::fs::read_to_string(&index_path)
        .unwrap_or_else(|e| panic!("cannot read {}: {e}", index_path.display()));
    let root: Value = serde_json::from_str(&raw).expect("index.json parses");

    let version = root["opencv_version"]
        .as_str()
        .expect("index.json: opencv_version missing")
        .to_string();
    assert_eq!(
        root["op"].as_str(),
        Some("fill_poly"),
        "index.json: these goldens must be fill_poly renders"
    );

    let cases = root["cases"].as_array().expect("index.json: cases array");
    assert_eq!(
        root["case_count"].as_u64(),
        Some(cases.len() as u64),
        "index.json: case_count disagrees with the cases array"
    );

    let goldens = cases
        .iter()
        .map(|case| {
            let id = case["id"].as_str().expect("case id").to_string();
            let width = case["width"].as_i64().expect("case width") as i32;
            let height = case["height"].as_i64().expect("case height") as i32;
            let polygon = case["polygon"]
                .as_array()
                .expect("case polygon")
                .iter()
                .map(|p| {
                    let p = p.as_array().expect("polygon vertex");
                    (
                        p[0].as_i64().expect("vertex x") as i32,
                        p[1].as_i64().expect("vertex y") as i32,
                    )
                })
                .collect();
            let mask_path = dir.join(case["mask"].as_str().expect("case mask path"));
            let mask = std::fs::read(&mask_path)
                .unwrap_or_else(|e| panic!("cannot read {}: {e}", mask_path.display()));
            assert_eq!(
                mask.len(),
                (width * height) as usize,
                "{id}: mask file length disagrees with {width}x{height}"
            );
            Golden {
                id,
                category: case["category"]
                    .as_str()
                    .expect("case category")
                    .to_string(),
                width,
                height,
                value: case["value"].as_f64().expect("case value"),
                nonzero: case["nonzero"].as_u64().expect("case nonzero") as usize,
                polygon,
                mask,
            }
        })
        .collect();

    (goldens, version)
}

/// The goldens are only an oracle if they came from the parity target's
/// OpenCV (the <= 4.10 rasterization rule).
#[test]
fn goldens_were_rendered_by_the_parity_target_opencv() {
    let (goldens, version) = load_goldens();
    assert!(
        version.starts_with("4.9."),
        "goldens were rendered by OpenCV {version}, not the 4.9 parity target"
    );
    assert!(
        goldens.len() >= 120,
        "golden set shrank to {} cases",
        goldens.len()
    );

    let mut categories: Vec<&str> = goldens.iter().map(|g| g.category.as_str()).collect();
    categories.sort_unstable();
    categories.dedup();
    assert_eq!(
        categories,
        [
            "collinear",
            "concave",
            "convex",
            "degenerate",
            "offimage",
            "selfint"
        ],
        "golden set lost a polygon category"
    );

    let filled = goldens.iter().filter(|g| g.nonzero > 0).count();
    assert!(
        filled >= 90,
        "only {filled} goldens rasterise anything; the set has lost its discriminating power"
    );
}

#[test]
fn fill_poly_matches_the_opencv_49_goldens() {
    let (goldens, version) = load_goldens();
    let mut mismatched = Vec::new();

    for golden in &goldens {
        let got = ops::fill_poly(golden.width, golden.height, &golden.polygon, golden.value)
            .unwrap_or_else(|e| panic!("{}: fill_poly failed: {e}", golden.id));
        assert_eq!(
            (got.width, got.height, got.channels),
            (golden.width, golden.height, 1),
            "{}: unexpected output geometry",
            golden.id
        );
        assert_eq!(
            got.data.iter().filter(|&&v| v != 0).count(),
            golden.nonzero,
            "{}: index.json nonzero count disagrees with the mask it indexes",
            golden.id
        );
        if got.data != golden.mask {
            let differing = got
                .data
                .iter()
                .zip(&golden.mask)
                .filter(|(a, b)| a != b)
                .count();
            mismatched.push(format!(
                "{} ({}, {}x{}, {} px differ)",
                golden.id, golden.category, golden.width, golden.height, differing
            ));
        }
    }

    assert!(
        mismatched.is_empty(),
        "fill_poly differs from the OpenCV {version} goldens on {}/{} case(s): {}",
        mismatched.len(),
        goldens.len(),
        mismatched.join(", ")
    );
}
