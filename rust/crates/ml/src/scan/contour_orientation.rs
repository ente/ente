use super::geometry::{Point, average};

const SMOOTH_WINDOW: i32 = 5;
const MIN_SIDE_LENGTH_RATIO: f64 = 0.02;

#[derive(Clone, Copy, Debug)]
struct Line {
    p: Point,
    d: Point,
}

#[derive(Clone, Copy, Debug)]
struct ContourSegment {
    start: usize,
    end: usize,
    angle: f64,
    length: f64,
}

pub(crate) fn find_quad_from_contour_orientation(contour: &[Point]) -> Option<Vec<Point>> {
    let max_angle_var = 5.0f64.to_radians();
    let merge_angle = 7.0f64.to_radians();

    if contour.len() < 20 {
        return None;
    }

    let angles = compute_smoothed_angles(contour, SMOOTH_WINDOW);

    let perimeter: f64 = contour
        .windows(2)
        .map(|w| (w[1].x - w[0].x).hypot(w[1].y - w[0].y))
        .sum();

    let min_length = perimeter * MIN_SIDE_LENGTH_RATIO;
    let segments = extract_segments(contour, &angles, max_angle_var, min_length);
    let merged = merge_segments(&segments, merge_angle);
    let dominant = select_dominant_segments(&merged, 4, 25.0f64.to_radians());

    if dominant.len() != 4 {
        return None;
    }

    let lines: Vec<Line> = dominant
        .iter()
        .map(|s| {
            let points: Vec<Point> = if s.start < s.end {
                contour[s.start..s.end].to_vec()
            } else {
                let mut v = contour[s.start..].to_vec();
                v.extend_from_slice(&contour[..s.end]);
                v
            };
            fit_line(&points)
        })
        .collect();

    let mut corners = Vec::with_capacity(4);
    for i in 0..4 {
        corners.push(intersect_lines(lines[i], lines[(i + 1) % 4])?);
    }
    Some(corners)
}

fn normalize_angle(a: f64) -> f64 {
    let mut x = a;
    while x <= -std::f64::consts::PI {
        x += 2.0 * std::f64::consts::PI;
    }
    while x > std::f64::consts::PI {
        x -= 2.0 * std::f64::consts::PI;
    }
    x
}

fn angle_diff(a: f64, b: f64) -> f64 {
    normalize_angle(a - b).abs()
}

fn angle_mean(a: f64, b: f64) -> f64 {
    let x = a.cos() + b.cos();
    let y = a.sin() + b.sin();
    y.atan2(x)
}

fn fit_line(points: &[Point]) -> Line {
    let cx = average(points.iter().map(|p| p.x));
    let cy = average(points.iter().map(|p| p.y));

    let mut xx = 0.0;
    let mut xy = 0.0;
    let mut yy = 0.0;
    for p in points {
        let dx = p.x - cx;
        let dy = p.y - cy;
        xx += dx * dx;
        xy += dx * dy;
        yy += dy * dy;
    }

    let theta = 0.5 * (2.0 * xy).atan2(xx - yy);
    Line {
        p: Point::new(cx, cy),
        d: Point::new(theta.cos(), theta.sin()),
    }
}

fn intersect_lines(l1: Line, l2: Line) -> Option<Point> {
    let x1 = l1.p.x;
    let y1 = l1.p.y;
    let x2 = x1 + l1.d.x;
    let y2 = y1 + l1.d.y;

    let x3 = l2.p.x;
    let y3 = l2.p.y;
    let x4 = x3 + l2.d.x;
    let y4 = y3 + l2.d.y;

    let denom = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4);
    if denom.abs() < 1e-6 {
        return None;
    }

    let px = ((x1 * y2 - y1 * x2) * (x3 - x4) - (x1 - x2) * (x3 * y4 - y3 * x4)) / denom;
    let py = ((x1 * y2 - y1 * x2) * (y3 - y4) - (y1 - y2) * (x3 * y4 - y3 * x4)) / denom;
    Some(Point::new(px, py))
}

fn extract_segments(
    contour: &[Point],
    angles: &[f64],
    max_angle_var: f64,
    min_length: f64,
) -> Vec<ContourSegment> {
    let n = contour.len();
    let mut result = Vec::new();

    let start_index = find_best_start_index(angles);

    let segment_length = |s: usize, e: usize| -> f64 {
        let mut len = 0.0;
        let mut i = s;
        while i != e {
            let j = (i + 1) % n;
            len += (contour[j].x - contour[i].x).hypot(contour[j].y - contour[i].y);
            i = j;
        }
        len
    };

    let mut start = start_index;
    let mut ref_angle = angles[start_index];

    let mut steps = 1usize;
    while steps <= n {
        let idx = (start_index + steps) % n;
        if steps < n && angle_diff(angles[idx], ref_angle) < max_angle_var {
            ref_angle = angle_mean(ref_angle, angles[idx]);
        } else {
            let len = segment_length(start, idx);
            if len >= min_length {
                result.push(ContourSegment {
                    start,
                    end: idx,
                    angle: ref_angle,
                    length: len,
                });
            }
            start = idx;
            ref_angle = angles[idx];
        }
        steps += 1;
    }

    result
}

fn find_best_start_index(angles: &[f64]) -> usize {
    let n = angles.len();
    let mut best_index = 0usize;
    let mut best_delta = 0.0;
    for i in 0..n {
        let j = (i + 1) % n;
        let d = angle_diff(angles[i], angles[j]);
        if d > best_delta {
            best_delta = d;
            best_index = j;
        }
    }
    best_index
}

fn compute_smoothed_angles(contour: &[Point], window: i32) -> Vec<f64> {
    let n = contour.len();
    let ni = n as i32;

    let mut angles = vec![0.0f64; n];
    for i in 0..n {
        let p0 = contour[(i + n - 1) % n];
        let p1 = contour[(i + 1) % n];
        angles[i] = (p1.y - p0.y).atan2(p1.x - p0.x);
    }

    let cos_a: Vec<f64> = angles.iter().map(|a| a.cos()).collect();
    let sin_a: Vec<f64> = angles.iter().map(|a| a.sin()).collect();

    let mut smooth = vec![0.0f64; n];
    let mut sx = 0.0;
    let mut sy = 0.0;
    for k in -window..=window {
        let idx = ((k + ni) % ni) as usize;
        sx += cos_a[idx];
        sy += sin_a[idx];
    }
    smooth[0] = sy.atan2(sx);

    for (i, out) in smooth.iter_mut().enumerate().skip(1) {
        let ii = i as i32;
        let out_idx = ((ii - window - 1 + ni) % ni) as usize;
        let in_idx = ((ii + window) % ni) as usize;
        sx -= cos_a[out_idx];
        sy -= sin_a[out_idx];
        sx += cos_a[in_idx];
        sy += sin_a[in_idx];
        *out = sy.atan2(sx);
    }
    smooth
}

fn merge_segments(segments: &[ContourSegment], angle_threshold: f64) -> Vec<ContourSegment> {
    if segments.is_empty() {
        return Vec::new();
    }
    if segments.len() <= 4 {
        return segments.to_vec();
    }

    let mut merged: Vec<ContourSegment> = Vec::new();
    let mut cur = segments[0];
    for p in &segments[1..] {
        if angle_diff(p.angle, cur.angle) < angle_threshold {
            cur = ContourSegment {
                start: cur.start,
                end: p.end,
                angle: angle_mean(cur.angle, p.angle),
                length: cur.length + p.length,
            };
        } else {
            merged.push(cur);
            cur = *p;
        }
    }
    merged.push(cur);
    merged
}

fn select_dominant_segments(
    segments: &[ContourSegment],
    max_count: usize,
    min_angle_separation: f64,
) -> Vec<ContourSegment> {
    let mut sorted = segments.to_vec();
    sorted.sort_by(|a, b| b.length.total_cmp(&a.length));

    let mut selected: Vec<ContourSegment> = Vec::new();
    for p in &sorted {
        let too_close = selected
            .iter()
            .any(|s| angle_diff(p.angle, s.angle) < min_angle_separation);
        if !too_close {
            selected.push(*p);
            if selected.len() == max_count {
                break;
            }
        }
    }

    selected.sort_by_key(|s| s.start);
    selected
}

#[cfg(test)]
mod tests {
    use super::find_quad_from_contour_orientation;
    use crate::scan::geometry::{Point, norm};

    #[test]
    fn contour_orientation_recovers_a_rotated_rectangle() {
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
        let quad =
            find_quad_from_contour_orientation(&contour).expect("quad from contour orientation");
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
}
