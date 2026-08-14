//! Minimum-area bounding rectangle over integer angles.

use std::collections::HashSet;

use super::geometry::Point;

/// Monotone chain over points sorted by (x, y), dropping on `cross <= 0`
/// (collinear points are dropped as well).
pub(crate) fn convex_hull(points: &[Point]) -> Vec<Point> {
    // Deduplicate by exact bit equality, keeping the first occurrence.
    let mut seen: HashSet<(u64, u64)> = HashSet::new();
    let mut unique: Vec<Point> = Vec::with_capacity(points.len());
    for p in points {
        if seen.insert((p.x.to_bits(), p.y.to_bits())) {
            unique.push(*p);
        }
    }
    if unique.len() <= 3 {
        return unique;
    }

    let mut sorted = unique;
    sorted.sort_by(|a, b| a.x.total_cmp(&b.x).then(a.y.total_cmp(&b.y)));

    fn cross(o: Point, a: Point, b: Point) -> f64 {
        (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
    }

    let mut lower: Vec<Point> = Vec::new();
    for p in &sorted {
        while lower.len() >= 2 && cross(lower[lower.len() - 2], lower[lower.len() - 1], *p) <= 0.0 {
            lower.pop();
        }
        lower.push(*p);
    }

    let mut upper: Vec<Point> = Vec::new();
    for p in sorted.iter().rev() {
        while upper.len() >= 2 && cross(upper[upper.len() - 2], upper[upper.len() - 1], *p) <= 0.0 {
            upper.pop();
        }
        upper.push(*p);
    }

    lower.pop();
    upper.pop();
    lower.extend(upper);
    lower
}

/// Brute-force over 90 integer degrees; the best (strictly smaller) area
/// wins, so ties keep the smallest angle.
pub(crate) fn min_area_rect(
    polygon: &[Point],
    img_width: Option<i32>,
    img_height: Option<i32>,
) -> Option<Vec<Point>> {
    if polygon.len() < 3 {
        return None;
    }

    let hull = convex_hull(polygon);
    if hull.len() < 3 {
        return Some(hull);
    }

    let mut best_area = f64::INFINITY;
    let mut best_rect: Option<Vec<Point>> = None;

    for deg in 0..90 {
        let angle = (deg as f64).to_radians();
        let cos_a = angle.cos();
        let sin_a = angle.sin();

        let rotated: Vec<Point> = hull
            .iter()
            .map(|p| Point::new(p.x * cos_a - p.y * sin_a, p.x * sin_a + p.y * cos_a))
            .collect();

        let mut min_x = f64::INFINITY;
        let mut max_x = f64::NEG_INFINITY;
        let mut min_y = f64::INFINITY;
        let mut max_y = f64::NEG_INFINITY;
        for p in &rotated {
            if p.x < min_x {
                min_x = p.x;
            }
            if p.x > max_x {
                max_x = p.x;
            }
            if p.y < min_y {
                min_y = p.y;
            }
            if p.y > max_y {
                max_y = p.y;
            }
        }

        let area = (max_x - min_x) * (max_y - min_y);
        if area < best_area {
            best_area = area;
            let rect_rot = [
                Point::new(min_x, min_y),
                Point::new(max_x, min_y),
                Point::new(max_x, max_y),
                Point::new(min_x, max_y),
            ];
            best_rect = Some(
                rect_rot
                    .iter()
                    .map(|p| Point::new(p.x * cos_a + p.y * sin_a, -p.x * sin_a + p.y * cos_a))
                    .collect(),
            );
        }
    }

    let rect = best_rect?;

    // Clip into [0, w-1] x [0, h-1].
    if let (Some(w), Some(h)) = (img_width, img_height) {
        let w = w as f64 - 1.0;
        let h = h as f64 - 1.0;
        return Some(
            rect.iter()
                .map(|p| Point::new(p.x.clamp(0.0, w), p.y.clamp(0.0, h)))
                .collect(),
        );
    }

    Some(rect)
}
