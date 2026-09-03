use super::Point;
use super::geometry::{
    clip_to_bounds, mean_inside_quad, min_area_rect, min_edge, order_corners, scale_points, unclip,
};
use crate::cv;
use crate::cv::image::{Contour, ImageU8};
use crate::error::{MlError, MlResult};

const BITMAP_THRESHOLD: f32 = 0.3;
const BOX_SCORE_THRESHOLD: f32 = 0.6;
const UNCLIP_RATIO: f32 = 1.5;
const MIN_BOX_SIDE: f32 = 3.0;
const MIN_UNCLIPPED_SIDE: f32 = MIN_BOX_SIDE + 2.0;
const MAX_CANDIDATES: usize = 1000;
const READING_LINE_TOLERANCE: f32 = 10.0;

#[derive(Clone, Debug, PartialEq)]
pub struct DetectionCandidate {
    pub points: [Point; 4],
    pub score: f32,
}

impl DetectionCandidate {
    fn scaled(self, scale_x: f32, scale_y: f32) -> Self {
        Self {
            points: scale_points(&self.points, scale_x, scale_y),
            score: self.score,
        }
    }

    fn top_left(&self) -> Point {
        self.points[0]
    }
}

struct ProbabilityMap<'a> {
    values: &'a [f32],
    width: usize,
    height: usize,
}

pub fn candidates_from_probability_map(
    values: &[f32],
    map_width: usize,
    map_height: usize,
    working_width: u32,
    working_height: u32,
) -> MlResult<Vec<DetectionCandidate>> {
    if map_width == 0 || map_height == 0 || values.len() != map_width * map_height {
        return Err(MlError::Postprocess(format!(
            "probability map has {} values for {map_width}x{map_height}",
            values.len()
        )));
    }
    let map = ProbabilityMap {
        values,
        width: map_width,
        height: map_height,
    };
    let scale_x = working_width as f32 / map_width as f32;
    let scale_y = working_height as f32 / map_height as f32;
    let candidates = largest_outer_contours(&map)?
        .iter()
        .filter_map(|contour| candidate_from_contour(contour, &map))
        .map(|candidate| candidate.scaled(scale_x, scale_y))
        .collect();
    Ok(candidates)
}

fn threshold_bitmap(map: &ProbabilityMap<'_>) -> MlResult<ImageU8> {
    let data = map
        .values
        .iter()
        .map(|&p| if p > BITMAP_THRESHOLD { 255 } else { 0 })
        .collect();
    ImageU8::new(map.width as i32, map.height as i32, 1, data).map_err(MlError::Postprocess)
}

fn largest_outer_contours(map: &ProbabilityMap<'_>) -> MlResult<Vec<Contour>> {
    let bitmap = threshold_bitmap(map)?;
    let mut contours: Vec<Contour> = cv::find_contours(&bitmap)
        .map_err(MlError::Postprocess)?
        .into_iter()
        .filter(|contour| contour.outer)
        .collect();
    contours.sort_by(|a, b| b.area.total_cmp(&a.area));
    contours.truncate(MAX_CANDIDATES);
    Ok(contours)
}

fn candidate_from_contour(
    contour: &Contour,
    map: &ProbabilityMap<'_>,
) -> Option<DetectionCandidate> {
    let rect = order_corners(min_area_rect(&contour.points)?);
    if min_edge(&rect) < MIN_BOX_SIDE {
        return None;
    }
    let score = mean_inside_quad(map.values, map.width, map.height, &rect);
    if score < BOX_SCORE_THRESHOLD {
        return None;
    }
    let expanded = unclip(&rect, UNCLIP_RATIO);
    if min_edge(&expanded) < MIN_UNCLIPPED_SIDE {
        return None;
    }
    let points = clip_to_bounds(&expanded, map.width as f32, map.height as f32);
    Some(DetectionCandidate { points, score })
}

pub fn sort_reading_order(candidates: &mut [DetectionCandidate]) {
    candidates.sort_by(|a, b| a.top_left().y.total_cmp(&b.top_left().y));
    let mut start = 0;
    while start < candidates.len() {
        let line_top = candidates[start].top_left().y;
        let end = start
            + candidates[start..]
                .iter()
                .take_while(|c| (c.top_left().y - line_top).abs() <= READING_LINE_TOLERANCE)
                .count();
        candidates[start..end].sort_by(|a, b| a.top_left().x.total_cmp(&b.top_left().x));
        start = end;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ocr::geometry::{edge_lengths, unclip};

    const BACKGROUND: f32 = 0.05;
    const FOREGROUND: f32 = 0.9;
    const CONTOUR_TOLERANCE: f32 = 1.5;
    const ROTATED_EDGE_TOLERANCE: f32 = 4.0;

    struct Canvas {
        width: usize,
        height: usize,
        values: Vec<f32>,
    }

    impl Canvas {
        fn new(width: usize, height: usize) -> Self {
            Self {
                width,
                height,
                values: vec![BACKGROUND; width * height],
            }
        }

        fn fill_rect(&mut self, x0: usize, y0: usize, x1: usize, y1: usize) {
            for y in y0..y1 {
                for x in x0..x1 {
                    self.values[y * self.width + x] = FOREGROUND;
                }
            }
        }

        fn fill_rotated_rect(&mut self, center: Point, width: f32, height: f32, degrees: f32) {
            let (sin, cos) = degrees.to_radians().sin_cos();
            for y in 0..self.height {
                for x in 0..self.width {
                    let dx = x as f32 - center.x;
                    let dy = y as f32 - center.y;
                    let along = dx * cos + dy * sin;
                    let across = -dx * sin + dy * cos;
                    if along.abs() <= width / 2.0 && across.abs() <= height / 2.0 {
                        self.values[y * self.width + x] = FOREGROUND;
                    }
                }
            }
        }

        fn candidates(&self) -> Vec<DetectionCandidate> {
            self.candidates_for(self.width as u32, self.height as u32)
        }

        fn candidates_for(
            &self,
            working_width: u32,
            working_height: u32,
        ) -> Vec<DetectionCandidate> {
            candidates_from_probability_map(
                &self.values,
                self.width,
                self.height,
                working_width,
                working_height,
            )
            .unwrap()
        }
    }

    fn traced_rect(x0: usize, y0: usize, x1: usize, y1: usize) -> [Point; 4] {
        let (left, top) = (x0 as f32, y0 as f32);
        let (right, bottom) = ((x1 - 1) as f32, (y1 - 1) as f32);
        [
            Point::new(left, top),
            Point::new(right, top),
            Point::new(right, bottom),
            Point::new(left, bottom),
        ]
    }

    fn assert_quads_close(actual: &[Point; 4], expected: &[Point; 4], tolerance: f32) {
        for (a, e) in actual.iter().zip(expected) {
            assert!(
                (a.x - e.x).abs() <= tolerance && (a.y - e.y).abs() <= tolerance,
                "expected {expected:?}, got {actual:?}"
            );
        }
    }

    fn center(candidate: &DetectionCandidate) -> Point {
        let sum = candidate
            .points
            .iter()
            .fold(Point::new(0.0, 0.0), |acc, &p| acc + p);
        sum * 0.25
    }

    fn candidate_at(x: f32, y: f32) -> DetectionCandidate {
        DetectionCandidate {
            points: [
                Point::new(x, y),
                Point::new(x + 50.0, y),
                Point::new(x + 50.0, y + 10.0),
                Point::new(x, y + 10.0),
            ],
            score: 0.9,
        }
    }

    #[test]
    fn axis_aligned_rectangle_yields_one_expanded_candidate() {
        let mut canvas = Canvas::new(200, 100);
        canvas.fill_rect(40, 30, 140, 70);
        let candidates = canvas.candidates();
        assert_eq!(candidates.len(), 1, "{candidates:?}");
        let expected = unclip(&traced_rect(40, 30, 140, 70), UNCLIP_RATIO);
        assert_quads_close(&candidates[0].points, &expected, CONTOUR_TOLERANCE);
        assert!((candidates[0].score - FOREGROUND).abs() <= 1e-3);
    }

    #[test]
    fn candidates_scale_to_working_image() {
        let mut canvas = Canvas::new(200, 100);
        canvas.fill_rect(40, 30, 140, 70);
        let candidates = canvas.candidates_for(400, 300);
        assert_eq!(candidates.len(), 1);
        let unscaled = &canvas.candidates()[0].points;
        for (scaled, base) in candidates[0].points.iter().zip(unscaled) {
            assert!((scaled.x - base.x * 2.0).abs() <= 1e-3);
            assert!((scaled.y - base.y * 3.0).abs() <= 1e-3);
        }
    }

    #[test]
    fn rotated_rectangle_yields_one_candidate_with_expanded_edges() {
        let (width, height, degrees) = (140.0, 40.0, 20.0f32);
        let mut canvas = Canvas::new(300, 200);
        canvas.fill_rotated_rect(Point::new(150.0, 100.0), width, height, degrees);
        let candidates = canvas.candidates();
        assert_eq!(candidates.len(), 1, "{candidates:?}");
        let candidate = &candidates[0];
        assert!(candidate.score > BOX_SCORE_THRESHOLD, "{}", candidate.score);
        let d = width * height * UNCLIP_RATIO / (2.0 * (width + height));
        let [top, right, bottom, left] = edge_lengths(&candidate.points);
        for (edge, expected) in [
            (top, width + 2.0 * d),
            (bottom, width + 2.0 * d),
            (right, height + 2.0 * d),
            (left, height + 2.0 * d),
        ] {
            assert!(
                (edge - expected).abs() <= ROTATED_EDGE_TOLERANCE,
                "edge {edge}, expected {expected}"
            );
        }
        let [tl, tr, _, _] = candidate.points;
        let angle = (tr.y - tl.y).atan2(tr.x - tl.x).to_degrees();
        assert!((angle - degrees).abs() <= 2.0, "angle {angle}");
    }

    #[test]
    fn separate_rectangles_yield_separate_candidates_and_specks_are_dropped() {
        let mut canvas = Canvas::new(200, 200);
        canvas.fill_rect(20, 20, 80, 50);
        canvas.fill_rect(120, 140, 180, 170);
        canvas.fill_rect(100, 100, 102, 102);
        let mut candidates = canvas.candidates();
        assert_eq!(candidates.len(), 2, "{candidates:?}");
        sort_reading_order(&mut candidates);
        let first = center(&candidates[0]);
        let second = center(&candidates[1]);
        assert!(
            (first.x - 49.5).abs() <= 2.0 && (first.y - 34.5).abs() <= 2.0,
            "{first:?}"
        );
        assert!(
            (second.x - 149.5).abs() <= 2.0 && (second.y - 154.5).abs() <= 2.0,
            "{second:?}"
        );
    }

    #[test]
    fn reading_order_sorts_lines_top_to_bottom_then_left_to_right() {
        let mut candidates = vec![
            candidate_at(200.0, 50.0),
            candidate_at(30.0, 150.0),
            candidate_at(20.0, 52.0),
            candidate_at(110.0, 47.0),
        ];
        sort_reading_order(&mut candidates);
        let order: Vec<(f32, f32)> = candidates
            .iter()
            .map(|c| (c.top_left().x, c.top_left().y))
            .collect();
        assert_eq!(
            order,
            [(20.0, 52.0), (110.0, 47.0), (200.0, 50.0), (30.0, 150.0)]
        );
    }

    #[test]
    fn reading_order_groups_lines_within_ten_pixels_of_the_first_box_inclusive() {
        let mut candidates = vec![
            candidate_at(100.0, 40.0),
            candidate_at(10.0, 50.0),
            candidate_at(5.0, 50.5),
        ];
        sort_reading_order(&mut candidates);
        let order: Vec<(f32, f32)> = candidates
            .iter()
            .map(|c| (c.top_left().x, c.top_left().y))
            .collect();
        assert_eq!(order, [(10.0, 50.0), (100.0, 40.0), (5.0, 50.5)]);
    }

    #[test]
    fn rejects_probability_map_with_wrong_length() {
        let error = candidates_from_probability_map(&[0.0; 10], 4, 4, 4, 4).unwrap_err();
        assert!(matches!(error, MlError::Postprocess(_)), "{error}");
    }
}
