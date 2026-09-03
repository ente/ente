use std::ops::{Add, Mul, Sub};

const INSIDE_EPSILON: f32 = 1e-3;
const PARALLEL_EPSILON: f32 = 1e-6;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Point {
    pub x: f32,
    pub y: f32,
}

impl Point {
    pub(crate) fn new(x: f32, y: f32) -> Self {
        Self { x, y }
    }

    pub(crate) fn distance(self, other: Point) -> f32 {
        (self.x - other.x).hypot(self.y - other.y)
    }
}

impl Add for Point {
    type Output = Point;

    fn add(self, other: Point) -> Point {
        Point::new(self.x + other.x, self.y + other.y)
    }
}

impl Sub for Point {
    type Output = Point;

    fn sub(self, other: Point) -> Point {
        Point::new(self.x - other.x, self.y - other.y)
    }
}

impl Mul<f32> for Point {
    type Output = Point;

    fn mul(self, factor: f32) -> Point {
        Point::new(self.x * factor, self.y * factor)
    }
}

fn cross(a: Point, b: Point) -> f32 {
    a.x * b.y - a.y * b.x
}

fn edges(quad: &[Point; 4]) -> [(Point, Point); 4] {
    [
        (quad[0], quad[1]),
        (quad[1], quad[2]),
        (quad[2], quad[3]),
        (quad[3], quad[0]),
    ]
}

pub(crate) fn order_corners(mut corners: [Point; 4]) -> [Point; 4] {
    corners.sort_by(|a, b| a.x.total_cmp(&b.x));
    let [tl, bl] = top_then_bottom(corners[0], corners[1]);
    let [tr, br] = top_then_bottom(corners[2], corners[3]);
    [tl, tr, br, bl]
}

fn top_then_bottom(a: Point, b: Point) -> [Point; 2] {
    if a.y <= b.y { [a, b] } else { [b, a] }
}

pub(crate) fn edge_lengths(quad: &[Point; 4]) -> [f32; 4] {
    edges(quad).map(|(a, b)| a.distance(b))
}

pub(crate) fn min_edge(quad: &[Point; 4]) -> f32 {
    edge_lengths(quad).into_iter().fold(f32::INFINITY, f32::min)
}

pub(crate) fn perimeter(quad: &[Point; 4]) -> f32 {
    edge_lengths(quad).iter().sum()
}

fn signed_area(quad: &[Point; 4]) -> f32 {
    edges(quad).iter().map(|&(a, b)| cross(a, b)).sum::<f32>() / 2.0
}

pub(crate) fn area(quad: &[Point; 4]) -> f32 {
    signed_area(quad).abs()
}

pub(crate) fn min_area_rect(points: &[(i32, i32)]) -> Option<[Point; 4]> {
    if points.len() < 3 {
        return None;
    }
    let pts: Vec<imageproc::point::Point<i32>> = points
        .iter()
        .map(|&(x, y)| imageproc::point::Point::new(x, y))
        .collect();
    let rect = imageproc::geometry::min_area_rect(&pts);
    Some(rect.map(|p| Point::new(p.x as f32, p.y as f32)))
}

struct Line {
    origin: Point,
    direction: Point,
}

fn intersect(a: &Line, b: &Line) -> Option<Point> {
    let denominator = cross(a.direction, b.direction);
    if denominator.abs() <= PARALLEL_EPSILON {
        return None;
    }
    let t = cross(b.origin - a.origin, b.direction) / denominator;
    Some(a.origin + a.direction * t)
}

pub(crate) fn unclip(quad: &[Point; 4], ratio: f32) -> [Point; 4] {
    if min_edge(quad) <= 0.0 {
        return *quad;
    }
    let distance = area(quad) * ratio / perimeter(quad);
    let outward = if signed_area(quad) >= 0.0 { 1.0 } else { -1.0 };
    let lines = edges(quad).map(|(a, b)| {
        let direction = b - a;
        let normal = Point::new(direction.y, -direction.x) * (outward / a.distance(b));
        Line {
            origin: a + normal * distance,
            direction,
        }
    });
    let corners = std::array::from_fn(|i| {
        let incoming = &lines[(i + 3) % 4];
        let outgoing = &lines[i];
        intersect(incoming, outgoing).unwrap_or(outgoing.origin)
    });
    order_corners(corners)
}

pub(crate) fn clip_to_bounds(quad: &[Point; 4], width: f32, height: f32) -> [Point; 4] {
    quad.map(|p| Point::new(p.x.clamp(0.0, width), p.y.clamp(0.0, height)))
}

pub(crate) fn scale_points(quad: &[Point; 4], scale_x: f32, scale_y: f32) -> [Point; 4] {
    quad.map(|p| Point::new(p.x * scale_x, p.y * scale_y))
}

fn contains(quad: &[Point; 4], point: Point) -> bool {
    let mut all_left = true;
    let mut all_right = true;
    for (a, b) in edges(quad) {
        let side = cross(b - a, point - a);
        all_left &= side >= -INSIDE_EPSILON;
        all_right &= side <= INSIDE_EPSILON;
    }
    all_left || all_right
}

fn pixel_bounds(coords: impl Iterator<Item = f32>, len: usize) -> (usize, usize) {
    let (min, max) = coords.fold((f32::INFINITY, f32::NEG_INFINITY), |(lo, hi), v| {
        (lo.min(v), hi.max(v))
    });
    let last = (len - 1) as f32;
    (
        min.floor().clamp(0.0, last) as usize,
        max.ceil().clamp(0.0, last) as usize,
    )
}

pub(crate) fn mean_inside_quad(
    values: &[f32],
    width: usize,
    height: usize,
    quad: &[Point; 4],
) -> f32 {
    if width == 0 || height == 0 {
        return 0.0;
    }
    let (min_x, max_x) = pixel_bounds(quad.iter().map(|p| p.x), width);
    let (min_y, max_y) = pixel_bounds(quad.iter().map(|p| p.y), height);
    let mut sum = 0.0f64;
    let mut count = 0usize;
    for y in min_y..=max_y {
        for x in min_x..=max_x {
            if contains(quad, Point::new(x as f32, y as f32)) {
                sum += f64::from(values[y * width + x]);
                count += 1;
            }
        }
    }
    if count == 0 {
        0.0
    } else {
        (sum / count as f64) as f32
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const TOLERANCE: f32 = 1e-3;

    fn rotated_quad() -> [Point; 4] {
        let (sin, cos) = 20.0f32.to_radians().sin_cos();
        let center = Point::new(150.0, 100.0);
        let corner = |along: f32, across: f32| {
            center + Point::new(along * cos - across * sin, along * sin + across * cos)
        };
        [
            corner(-70.0, -20.0),
            corner(70.0, -20.0),
            corner(70.0, 20.0),
            corner(-70.0, 20.0),
        ]
    }

    fn assert_close(actual: Point, expected: Point, tolerance: f32) {
        assert!(
            (actual.x - expected.x).abs() <= tolerance
                && (actual.y - expected.y).abs() <= tolerance,
            "expected {expected:?}, got {actual:?}"
        );
    }

    fn assert_quads_close(actual: &[Point; 4], expected: &[Point; 4], tolerance: f32) {
        for (a, e) in actual.iter().zip(expected) {
            assert_close(*a, *e, tolerance);
        }
    }

    fn distance_to_line(point: Point, a: Point, b: Point) -> f32 {
        cross(b - a, point - a).abs() / a.distance(b)
    }

    #[test]
    fn order_corners_recovers_shuffled_rotated_quad() {
        let [tl, tr, br, bl] = rotated_quad();
        assert_eq!(order_corners([br, tl, bl, tr]), [tl, tr, br, bl]);
        assert_eq!(order_corners([bl, br, tr, tl]), [tl, tr, br, bl]);
    }

    #[test]
    fn order_corners_handles_axis_aligned_ties() {
        let quad = [
            Point::new(139.0, 69.0),
            Point::new(40.0, 69.0),
            Point::new(139.0, 30.0),
            Point::new(40.0, 30.0),
        ];
        assert_eq!(
            order_corners(quad),
            [
                Point::new(40.0, 30.0),
                Point::new(139.0, 30.0),
                Point::new(139.0, 69.0),
                Point::new(40.0, 69.0),
            ]
        );
    }

    #[test]
    fn unclip_moves_rectangle_edges_outward_by_d() {
        let rect = [
            Point::new(10.0, 10.0),
            Point::new(50.0, 10.0),
            Point::new(50.0, 30.0),
            Point::new(10.0, 30.0),
        ];
        let expected = [
            Point::new(0.0, 0.0),
            Point::new(60.0, 0.0),
            Point::new(60.0, 40.0),
            Point::new(0.0, 40.0),
        ];
        assert_eq!(area(&rect), 800.0);
        assert_eq!(perimeter(&rect), 120.0);
        assert_quads_close(&unclip(&rect, 1.5), &expected, TOLERANCE);
    }

    #[test]
    fn unclip_moves_rotated_edges_outward_by_d() {
        let quad = rotated_quad();
        let d = area(&quad) * 1.5 / perimeter(&quad);
        let expanded = unclip(&quad, 1.5);
        for ((old_a, _), (new_a, new_b)) in edges(&quad).into_iter().zip(edges(&expanded)) {
            let moved = distance_to_line(old_a, new_a, new_b);
            assert!(
                (moved - d).abs() <= 1e-2,
                "edge moved {moved}, expected {d}"
            );
        }
        let lengths = edge_lengths(&expanded);
        let original = edge_lengths(&quad);
        for (new_len, old_len) in lengths.iter().zip(original) {
            assert!((new_len - old_len - 2.0 * d).abs() <= 1e-2);
        }
    }

    #[test]
    fn min_area_rect_of_axis_aligned_points() {
        let points = [
            (40, 30),
            (100, 30),
            (139, 30),
            (139, 69),
            (60, 69),
            (40, 69),
            (90, 50),
        ];
        let rect = order_corners(min_area_rect(&points).expect("rect"));
        assert_eq!(
            rect,
            [
                Point::new(40.0, 30.0),
                Point::new(139.0, 30.0),
                Point::new(139.0, 69.0),
                Point::new(40.0, 69.0),
            ]
        );
        assert!(min_area_rect(&[(0, 0), (1, 1)]).is_none());
    }

    #[test]
    fn clip_to_bounds_clamps_corners() {
        let quad = [
            Point::new(-5.0, -3.0),
            Point::new(120.0, -3.0),
            Point::new(120.0, 45.0),
            Point::new(-5.0, 45.0),
        ];
        assert_eq!(
            clip_to_bounds(&quad, 100.0, 40.0),
            [
                Point::new(0.0, 0.0),
                Point::new(100.0, 0.0),
                Point::new(100.0, 40.0),
                Point::new(0.0, 40.0),
            ]
        );
    }

    #[test]
    fn mean_inside_quad_averages_rasterised_pixels() {
        let width = 10;
        let height = 10;
        let mut values = vec![0.0f32; width * height];
        for y in 2..6 {
            for x in 2..6 {
                values[y * width + x] = 1.0;
            }
        }
        let exact = [
            Point::new(2.0, 2.0),
            Point::new(5.0, 2.0),
            Point::new(5.0, 5.0),
            Point::new(2.0, 5.0),
        ];
        assert!((mean_inside_quad(&values, width, height, &exact) - 1.0).abs() <= TOLERANCE);
        let whole = [
            Point::new(0.0, 0.0),
            Point::new(9.0, 0.0),
            Point::new(9.0, 9.0),
            Point::new(0.0, 9.0),
        ];
        assert!((mean_inside_quad(&values, width, height, &whole) - 0.16).abs() <= TOLERANCE);
        let outside = [
            Point::new(-20.0, -20.0),
            Point::new(-10.0, -20.0),
            Point::new(-10.0, -10.0),
            Point::new(-20.0, -10.0),
        ];
        assert_eq!(mean_inside_quad(&values, width, height, &outside), 0.0);
    }
}
