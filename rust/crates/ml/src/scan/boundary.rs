use super::page::{SourceExtent, area, cross, distance, points, quad_from_points, validate_quad};
use super::segmentation::ProbabilityMap;
use super::{OpResult, Point, Quad};
use crate::cv::image::ImageU8;

#[derive(Clone, Copy)]
pub(super) enum SearchBudget {
    Live,
    Capture,
}

#[derive(Clone, Copy)]
pub(super) struct MaskQuad {
    pub corners: Quad,
    pub needs_complete_source_support: bool,
    extent: SourceExtent,
}

impl MaskQuad {
    pub fn in_source(self, source: SourceExtent) -> Quad {
        quad_from_points(points(self.corners).map(|p| Point {
            x: p.x * source.width / self.extent.width,
            y: p.y * source.height / self.extent.height,
        }))
    }
}

pub(super) struct Detection {
    pub quad: Option<MaskQuad>,
    pub confidence: f64,
    pub reason: &'static str,
}

#[derive(Clone, Copy)]
struct Line {
    nx: f64,
    ny: f64,
    offset: f64,
}

impl Line {
    fn through(a: Point, b: Point) -> Self {
        let length = distance(a, b);
        let nx = (b.y - a.y) / length;
        let ny = (a.x - b.x) / length;
        Self {
            nx,
            ny,
            offset: nx * a.x + ny * a.y,
        }
    }

    fn residual(self, p: Point) -> f64 {
        self.nx * p.x + self.ny * p.y - self.offset
    }

    fn intersection(self, other: Self) -> Option<Point> {
        let determinant = self.nx * other.ny - self.ny * other.nx;
        if determinant.abs() < 1e-4 {
            return None;
        }
        Some(Point {
            x: (self.offset * other.ny - self.ny * other.offset) / determinant,
            y: (self.nx * other.offset - self.offset * other.nx) / determinant,
        })
    }
}

fn fit_line(samples: &[Point], initial: Line, scale: f64) -> Line {
    let mut line = initial;
    for _ in 0..3 {
        let mut sx = 0.0;
        let mut sy = 0.0;
        let mut weight = 0.0;
        for &p in samples {
            let w = (1.0 + (line.residual(p) / scale).powi(2)).recip();
            sx += p.x * w;
            sy += p.y * w;
            weight += w;
        }
        if weight < 2.0 {
            return initial;
        }
        let center = Point {
            x: sx / weight,
            y: sy / weight,
        };
        let mut xx = 0.0;
        let mut yy = 0.0;
        let mut xy = 0.0;
        for &p in samples {
            let w = (1.0 + (line.residual(p) / scale).powi(2)).recip();
            xx += (p.x - center.x).powi(2) * w;
            yy += (p.y - center.y).powi(2) * w;
            xy += (p.x - center.x) * (p.y - center.y) * w;
        }
        let angle = 0.5 * (2.0 * xy).atan2(xx - yy);
        let nx = -angle.sin();
        let ny = angle.cos();
        line = Line {
            nx,
            ny,
            offset: nx * center.x + ny * center.y,
        };
    }
    line
}

fn convex_hull(mut boundary: Vec<Point>) -> Vec<Point> {
    boundary.sort_by(|a, b| a.x.total_cmp(&b.x).then(a.y.total_cmp(&b.y)));
    boundary.dedup_by(|a, b| a.x == b.x && a.y == b.y);
    let mut hull: Vec<Point> = Vec::new();
    for &p in &boundary {
        while hull.len() >= 2 && cross(hull[hull.len() - 2], hull[hull.len() - 1], p) <= 0.0 {
            hull.pop();
        }
        hull.push(p);
    }
    let lower = hull.len();
    for &p in boundary.iter().rev().skip(1) {
        while hull.len() > lower && cross(hull[hull.len() - 2], hull[hull.len() - 1], p) <= 0.0 {
            hull.pop();
        }
        hull.push(p);
    }
    hull.pop();
    hull
}

fn simplify(mut hull: Vec<Point>, count: usize) -> Vec<Point> {
    while hull.len() > count {
        let Some(index) = (0..hull.len()).min_by(|&a, &b| {
            let loss = |i| {
                cross(
                    hull[(i + hull.len() - 1) % hull.len()],
                    hull[i],
                    hull[(i + 1) % hull.len()],
                )
                .abs()
            };
            loss(a).total_cmp(&loss(b)).then(a.cmp(&b))
        }) else {
            break;
        };
        hull.remove(index);
    }
    hull
}

fn canonical(mut p: [Point; 4], extent: SourceExtent) -> Quad {
    if area(&p) < 0.0 {
        p.reverse();
    }
    let first = (0..4)
        .min_by(|&a, &b| {
            let pa = p[a];
            let pb = p[b];
            (pa.x / extent.width + pa.y / extent.height)
                .total_cmp(&(pb.x / extent.width + pb.y / extent.height))
                .then(pa.x.total_cmp(&pb.x))
                .then(pa.y.total_cmp(&pb.y))
        })
        .unwrap_or(0);
    quad_from_points(std::array::from_fn(|i| p[(i + first) % 4]))
}

struct Component {
    pixels: Vec<usize>,
    boundary: Vec<Point>,
}

fn background_regions(map: &ProbabilityMap, cutoff: f32) -> Vec<usize> {
    let mut labels = vec![0; map.values.len()];
    let mut touches_frame = vec![true];
    let mut queue = Vec::new();
    for seed in 0..map.values.len() {
        if map.values[seed] >= cutoff || labels[seed] != 0 {
            continue;
        }
        let label = touches_frame.len();
        touches_frame.push(false);
        labels[seed] = label;
        queue.clear();
        queue.push(seed);
        let mut cursor = 0;
        while cursor < queue.len() {
            let index = queue[cursor];
            cursor += 1;
            let x = index % map.width;
            let y = index / map.width;
            touches_frame[label] |= x == 0 || y == 0 || x + 1 == map.width || y + 1 == map.height;
            for dy in -1isize..=1 {
                for dx in -1isize..=1 {
                    let nx = x as isize + dx;
                    let ny = y as isize + dy;
                    if nx < 0 || ny < 0 || nx >= map.width as isize || ny >= map.height as isize {
                        continue;
                    }
                    let neighbor = ny as usize * map.width + nx as usize;
                    if map.values[neighbor] < cutoff && labels[neighbor] == 0 {
                        labels[neighbor] = label;
                        queue.push(neighbor);
                    }
                }
            }
        }
    }
    for label in &mut labels {
        if touches_frame[*label] {
            *label = 0;
        }
    }
    labels
}

fn components(map: &ProbabilityMap, cutoff: f32, count: usize, outer_only: bool) -> Vec<Component> {
    let background = outer_only.then(|| background_regions(map, cutoff));
    let mut visited = vec![false; map.values.len()];
    let mut components = Vec::new();
    for seed in 0..map.values.len() {
        if visited[seed] || map.values[seed] < cutoff {
            continue;
        }
        let exterior = if seed < map.width {
            0
        } else {
            background
                .as_ref()
                .map_or(0, |regions| regions[seed - map.width])
        };
        let mut queue = vec![seed];
        visited[seed] = true;
        let mut cursor = 0;
        let mut boundary = Vec::new();
        while cursor < queue.len() {
            let index = queue[cursor];
            cursor += 1;
            let x = index % map.width;
            let y = index / map.width;
            for (dx, dy) in [(-1isize, 0isize), (1, 0), (0, -1), (0, 1)] {
                let nx = x as isize + dx;
                let ny = y as isize + dy;
                if nx < 0 || ny < 0 || nx >= map.width as isize || ny >= map.height as isize {
                    boundary.push(Point {
                        x: x as f64 + 0.5 + dx as f64 * 0.5,
                        y: y as f64 + 0.5 + dy as f64 * 0.5,
                    });
                    continue;
                }
                let neighbor = ny as usize * map.width + nx as usize;
                if map.values[neighbor] < cutoff {
                    if background
                        .as_ref()
                        .is_some_and(|regions| regions[neighbor] != exterior)
                    {
                        continue;
                    }
                    let t = ((map.values[index] - cutoff)
                        / (map.values[index] - map.values[neighbor]))
                        as f64;
                    boundary.push(Point {
                        x: x as f64 + 0.5 + dx as f64 * t,
                        y: y as f64 + 0.5 + dy as f64 * t,
                    });
                } else if !visited[neighbor] {
                    visited[neighbor] = true;
                    queue.push(neighbor);
                }
            }
        }
        if queue.len() >= 64 && queue.len() * 500 >= map.values.len() {
            components.push(Component {
                pixels: queue,
                boundary,
            });
        }
    }
    components.sort_by(|a, b| {
        b.pixels
            .len()
            .cmp(&a.pixels.len())
            .then(a.pixels[0].cmp(&b.pixels[0]))
    });
    components.truncate(count);
    components
}

fn supported_fit(p: [Point; 4], boundary: &[Point], extent: SourceExtent) -> Option<[Point; 4]> {
    let initial = std::array::from_fn::<_, 4, _>(|i| Line::through(p[i], p[(i + 1) % 4]));
    let mut sides: [Vec<Point>; 4] = std::array::from_fn(|_| Vec::new());
    let band = extent.width.hypot(extent.height) * 0.025;
    for &point in boundary {
        let side = (0..4)
            .min_by(|&a, &b| {
                initial[a]
                    .residual(point)
                    .abs()
                    .total_cmp(&initial[b].residual(point).abs())
            })
            .unwrap_or(0);
        if initial[side].residual(point).abs() < band {
            sides[side].push(point);
        }
    }
    let mut lines = initial;
    for i in 0..4 {
        if sides[i].len() < 4 {
            return None;
        }
        lines[i] = fit_line(&sides[i], initial[i], (band / 4.0).max(0.5));
        let along = |p: Point| lines[i].ny * p.x - lines[i].nx * p.y;
        let lo = sides[i]
            .iter()
            .map(|&p| along(p))
            .fold(f64::INFINITY, f64::min);
        let hi = sides[i]
            .iter()
            .map(|&p| along(p))
            .fold(f64::NEG_INFINITY, f64::max);
        if hi - lo < distance(p[i], p[(i + 1) % 4]) * 0.55 {
            return None;
        }
    }
    let mut fitted = p;
    for i in 0..4 {
        fitted[i] = lines[(i + 3) % 4].intersection(lines[i])?;
    }
    if (0..4).any(|i| distance(fitted[i], p[i]) > band * 2.0) {
        return None;
    }
    Some(fitted)
}

fn evidence(
    map: &ProbabilityMap,
    component: &Component,
    p: [Point; 4],
    live: bool,
) -> Option<(f64, bool)> {
    let extent = SourceExtent {
        width: map.width as f64,
        height: map.height as f64,
    };
    validate_quad(quad_from_points(p), extent).ok()?;
    let lines = std::array::from_fn::<_, 4, _>(|i| Line::through(p[i], p[(i + 1) % 4]));
    let inside = |q: Point| (0..4).all(|i| cross(p[i], p[(i + 1) % 4], q) >= -0.1);
    let captured = component
        .pixels
        .iter()
        .filter(|&&i| {
            inside(Point {
                x: (i % map.width) as f64 + 0.5,
                y: (i / map.width) as f64 + 0.5,
            })
        })
        .count() as f64
        / component.pixels.len() as f64;
    if captured < if live { 0.93 } else { 0.90 } {
        return None;
    }
    let mut mass = 0.0;
    let mut count = 0usize;
    for y in (0..map.height).step_by(2) {
        for x in (0..map.width).step_by(2) {
            if inside(Point {
                x: x as f64 + 0.5,
                y: y as f64 + 0.5,
            }) {
                mass += map.values[y * map.width + x] as f64;
                count += 1;
            }
        }
    }
    if count == 0 {
        return None;
    }
    let purity = mass / count as f64;
    if purity < if live { 0.78 } else { 0.68 } {
        return None;
    }
    let mut residuals: Vec<f64> = component
        .boundary
        .iter()
        .map(|&p| {
            lines
                .iter()
                .map(|line| line.residual(p).abs())
                .fold(f64::INFINITY, f64::min)
        })
        .collect();
    residuals.sort_by(f64::total_cmp);
    let residual = residuals[residuals.len() * 4 / 5];
    let thickness =
        (area(&p) / (0..4).map(|i| distance(p[i], p[(i + 1) % 4])).sum::<f64>()).max(1.0);
    let tolerance = (thickness * if live { 0.065 } else { 0.085 }).max(1.2);
    if residual > tolerance && (live || !sustained_sides(&component.boundary, p, tolerance)) {
        return None;
    }
    let fill = component.pixels.len() as f64 / area(&p);
    if !(0.76..=1.16).contains(&fill) {
        return None;
    }
    Some((
        purity
            * captured
            * (1.0 - 0.15 * (residual / tolerance).min(1.0))
            * (component.pixels.len() as f64 / map.values.len() as f64).sqrt(),
        residual > tolerance,
    ))
}

fn sustained_sides(boundary: &[Point], p: [Point; 4], tolerance: f64) -> bool {
    let lines = std::array::from_fn::<_, 4, _>(|side| Line::through(p[side], p[(side + 1) % 4]));
    let mut straight_sides = 0;
    for side in 0..4 {
        let a = p[side];
        let b = p[(side + 1) % 4];
        let line = lines[side];
        let length_squared = (b.x - a.x).powi(2) + (b.y - a.y).powi(2);
        let mut bins: [Vec<f64>; 16] = std::array::from_fn(|_| Vec::new());
        for &point in boundary {
            let along =
                ((point.x - a.x) * (b.x - a.x) + (point.y - a.y) * (b.y - a.y)) / length_squared;
            let residual = line.residual(point).abs();
            if (0.0..1.0).contains(&along)
                && lines
                    .iter()
                    .all(|other| residual <= other.residual(point).abs())
            {
                bins[(along * 16.0) as usize].push(residual);
            }
        }
        let mut touched = 0;
        let mut straight = 0;
        for mut bin in bins {
            if bin.is_empty() {
                continue;
            }
            bin.sort_by(f64::total_cmp);
            touched += usize::from(bin[0] <= tolerance);
            straight += usize::from(bin[bin.len() / 2] <= tolerance);
        }
        if touched < 12 {
            return false;
        }
        straight_sides += usize::from(straight >= 12);
    }
    straight_sides >= 3
}

fn supporting_intersections(hull: &[Point], indices: [usize; 4]) -> Option<[Point; 4]> {
    let edges = indices.map(|i| [hull[i], hull[(i + 1) % hull.len()]]);
    let lines = edges.map(|[a, b]| Line::through(a, b));
    let mut p = [Point { x: 0.0, y: 0.0 }; 4];
    for i in 0..4 {
        p[i] = lines[(i + 3) % 4].intersection(lines[i])?;
    }
    let hull_area = (0..hull.len())
        .map(|i| {
            let a = hull[i];
            let b = hull[(i + 1) % hull.len()];
            a.x * b.y - a.y * b.x
        })
        .sum::<f64>()
        * 0.5;
    if area(&p) <= 0.0 || hull_area / area(&p) < 0.90 {
        return None;
    }
    let mut missing_corners = 0;
    for i in 0..4 {
        let next = (i + 1) % 4;
        let length = distance(p[i], p[next]);
        if distance(edges[i][0], edges[i][1]) < length * 0.60 {
            return None;
        }
        let missing_area = cross(edges[(i + 3) % 4][1], p[i], edges[i][0]).abs() * 0.5;
        if missing_area > area(&p) * 0.01 {
            missing_corners += 1;
        }
    }
    (missing_corners <= 1).then_some(p)
}

pub(super) fn locate(map: &ProbabilityMap, frame: SourceExtent, budget: SearchBudget) -> Detection {
    let detection = locate_with_boundaries(map, frame, budget, false);
    if detection.quad.is_some() || matches!(budget, SearchBudget::Live) {
        detection
    } else {
        locate_with_boundaries(map, frame, budget, true)
    }
}

fn locate_with_boundaries(
    map: &ProbabilityMap,
    frame: SourceExtent,
    budget: SearchBudget,
    outer_only: bool,
) -> Detection {
    let live = matches!(budget, SearchBudget::Live);
    let extent = SourceExtent {
        width: map.width as f64,
        height: map.height as f64,
    };
    let mut best = Detection {
        quad: None,
        confidence: 0.0,
        reason: "insufficient supported page boundary",
    };
    let cutoffs: &[f32] = if live { &[0.5] } else { &[0.5, 0.35, 0.7] };
    let component_groups = cutoffs
        .iter()
        .map(|&cutoff| components(map, cutoff, if live { 2 } else { 4 }, outer_only))
        .collect::<Vec<_>>();
    let largest = component_groups
        .iter()
        .flatten()
        .map(|c| c.pixels.len())
        .max()
        .unwrap_or(0);
    for group in component_groups {
        for component in group {
            if component.pixels.len() * 2 < largest {
                continue;
            }
            let boundary_source: Vec<_> = component
                .boundary
                .iter()
                .map(|p| Point {
                    x: p.x * frame.width / extent.width,
                    y: p.y * frame.height / extent.height,
                })
                .collect();
            let hull_source = convex_hull(boundary_source);
            if hull_source.len() < 4 {
                continue;
            }
            let supporting_hull = simplify(hull_source.clone(), 6)
                .into_iter()
                .map(|p| Point {
                    x: p.x * extent.width / frame.width,
                    y: p.y * extent.height / frame.height,
                })
                .collect::<Vec<_>>();
            let simplified = simplify(hull_source, if live { 4 } else { 6 });
            let mut candidates = Vec::new();
            for a in 0..simplified.len() - 3 {
                for b in a + 1..simplified.len() - 2 {
                    for c in b + 1..simplified.len() - 1 {
                        for d in c + 1..simplified.len() {
                            let candidate =
                                [simplified[a], simplified[b], simplified[c], simplified[d]].map(
                                    |p| Point {
                                        x: p.x * extent.width / frame.width,
                                        y: p.y * extent.height / frame.height,
                                    },
                                );
                            candidates.push(candidate);
                        }
                    }
                }
            }
            if supporting_hull.len() > 4 {
                for a in 0..supporting_hull.len() - 3 {
                    for b in a + 1..supporting_hull.len() - 2 {
                        for c in b + 1..supporting_hull.len() - 1 {
                            for d in c + 1..supporting_hull.len() {
                                if let Some(candidate) =
                                    supporting_intersections(&supporting_hull, [a, b, c, d])
                                {
                                    candidates.push(candidate);
                                }
                            }
                        }
                    }
                }
            }
            for candidate in candidates {
                let Some(candidate) = supported_fit(candidate, &component.boundary, extent) else {
                    continue;
                };
                let quad = canonical(candidate, extent);
                let Some((confidence, needs_complete_source_support)) =
                    evidence(map, &component, points(quad), live)
                else {
                    continue;
                };
                let needs_complete_source_support = needs_complete_source_support || outer_only;
                if best.quad.is_none_or(|current| {
                    if current.needs_complete_source_support != needs_complete_source_support {
                        !needs_complete_source_support
                    } else {
                        confidence > best.confidence
                    }
                }) {
                    best = Detection {
                        quad: Some(MaskQuad {
                            corners: quad,
                            needs_complete_source_support,
                            extent,
                        }),
                        confidence,
                        reason: "four supported sides",
                    };
                }
            }
        }
    }
    best
}

fn brightness(source: &ImageU8, x: f64, y: f64) -> Option<f64> {
    if x < 0.0 || y < 0.0 || x >= source.width as f64 || y >= source.height as f64 {
        return None;
    }
    let offset = ((y as usize) * source.width as usize + x as usize) * 3;
    Some(
        (source.data[offset] as f64
            + 2.0 * source.data[offset + 1] as f64
            + source.data[offset + 2] as f64)
            / 4.0,
    )
}

struct ColorEdgeScores {
    values: [[f64; 91]; 48],
    supported: [bool; 48],
}

impl ColorEdgeScores {
    fn supported_positions(&self) -> usize {
        self.supported
            .iter()
            .filter(|&&supported| supported)
            .count()
    }
}

fn color_edge_scores(source: &ImageU8, edge: [Point; 2], band: f64) -> ColorEdgeScores {
    let line = Line::through(edge[0], edge[1]);
    let sample = |x: f64, y: f64| -> Option<[f64; 3]> {
        if x < 0.0 || y < 0.0 || x >= source.width as f64 || y >= source.height as f64 {
            return None;
        }
        let offset = ((y as usize) * source.width as usize + x as usize) * 3;
        Some(std::array::from_fn(|channel| {
            source.data[offset + channel] as f64
        }))
    };
    let mut supported = [false; 48];
    let values = std::array::from_fn(|i| {
        let t = (i as f64 + 1.0) / 49.0;
        let center = Point {
            x: edge[0].x + (edge[1].x - edge[0].x) * t,
            y: edge[0].y + (edge[1].y - edge[0].y) * t,
        };
        std::array::from_fn(|step| {
            let offset = (step as f64 - 45.0) * band / 30.0;
            let Some(a) = sample(
                center.x + line.nx * (offset - 1.25),
                center.y + line.ny * (offset - 1.25),
            ) else {
                return 0.0;
            };
            let Some(b) = sample(
                center.x + line.nx * (offset + 1.25),
                center.y + line.ny * (offset + 1.25),
            ) else {
                return 0.0;
            };
            let delta = std::array::from_fn::<_, 3, _>(|i| a[i] - b[i]);
            let dot =
                |a: [f64; 3], b: [f64; 3]| (a[0] * b[0] + 2.0 * a[1] * b[1] + a[2] * b[2]) / 4.0;
            let energy = dot(delta, delta);
            let penalty = 1.0 + 0.25 * (offset / band).powi(2);
            if energy < 9.0 {
                return 0.0;
            }
            let Some(inner) = sample(
                center.x + line.nx * (offset - 0.5),
                center.y + line.ny * (offset - 0.5),
            ) else {
                return 0.0;
            };
            let Some(outer) = sample(
                center.x + line.nx * (offset + 0.5),
                center.y + line.ny * (offset + 0.5),
            ) else {
                return 0.0;
            };
            let fine = std::array::from_fn::<_, 3, _>(|i| inner[i] - outer[i]);
            let wide = [2.5, 4.0, 6.0].map(|reach| {
                let a = sample(
                    center.x + line.nx * (offset - reach),
                    center.y + line.ny * (offset - reach),
                )?;
                let b = sample(
                    center.x + line.nx * (offset + reach),
                    center.y + line.ny * (offset + reach),
                )?;
                Some(std::array::from_fn::<_, 3, _>(|i| a[i] - b[i]))
            });
            let [Some(a), Some(b), Some(c)] = wide else {
                return 0.0;
            };
            let agrees = |wide: [f64; 3], minimum: f64| {
                let wide_energy = dot(wide, wide);
                wide_energy >= minimum && dot(delta, wide) >= 0.7 * (energy * wide_energy).sqrt()
            };
            if (15..76).contains(&step)
                && energy >= (6.0 * penalty).powi(2)
                && [a, b, c].into_iter().all(|wide| agrees(wide, 36.0))
            {
                supported[i] = true;
            }
            if [a, b].into_iter().all(|wide| agrees(wide, 9.0)) {
                (1.0 + dot(fine, fine).sqrt()) / penalty
            } else {
                0.0
            }
        })
    });
    ColorEdgeScores { values, supported }
}

fn refine_color_edges(
    p: [Point; 4],
    scores: &[ColorEdgeScores; 4],
    band: f64,
) -> Option<[Point; 4]> {
    let mut lines = std::array::from_fn::<_, 4, _>(|i| Line::through(p[i], p[(i + 1) % 4]));
    for i in 0..4 {
        let available = scores[i].supported_positions();
        if available < 32 {
            return None;
        }
        let mut best = None;
        let mut best_score = 0.0;
        for start in 0..91 {
            for end in 0..91 {
                let mut supported = 0;
                let mut strength = 0.0;
                let mut weighted_support = 0.0;
                for (position, row) in scores[i].values.iter().enumerate() {
                    let t = (position as f64 + 1.0) / 49.0;
                    let offset = (start as f64 * (1.0 - t) + end as f64 * t).round() as usize;
                    let score = row[offset];
                    supported += usize::from(score > 0.0);
                    strength += score / (score + 16.0);
                    if score > 0.0 {
                        weighted_support +=
                            (1.0 + 0.25 * ((offset as f64 - 45.0) / 30.0).powi(2)).recip();
                    }
                }
                let score = weighted_support + strength * 0.1;
                if supported >= 32 && supported * 5 >= available * 4 && score > best_score {
                    best_score = score;
                    best = Some((start, end));
                }
            }
        }
        let (start, end) = best?;
        let mut samples = Vec::new();
        for (position, row) in scores[i].values.iter().enumerate() {
            let t = (position as f64 + 1.0) / 49.0;
            let index = (start as f64 * (1.0 - t) + end as f64 * t).round() as usize;
            if row[index] == 0.0 {
                continue;
            }
            let offset = (index as f64 - 45.0) * band / 30.0;
            samples.push(Point {
                x: p[i].x + (p[(i + 1) % 4].x - p[i].x) * t + lines[i].nx * offset,
                y: p[i].y + (p[(i + 1) % 4].y - p[i].y) * t + lines[i].ny * offset,
            });
        }
        if samples.len() < 32 {
            return None;
        }
        lines[i] = fit_line(&samples, lines[i], band);
    }
    let mut refined = p;
    for i in 0..4 {
        refined[i] = lines[(i + 3) % 4].intersection(lines[i])?;
        if distance(refined[i], p[i]) > band * 1.5 {
            return None;
        }
    }
    Some(refined)
}

fn source_color(source: &ImageU8, x: f64, y: f64) -> Option<[u8; 3]> {
    if x < 0.0 || y < 0.0 || x >= source.width as f64 || y >= source.height as f64 {
        return None;
    }
    let index = (y as usize * source.width as usize + x as usize) * 3;
    Some([
        source.data[index],
        source.data[index + 1],
        source.data[index + 2],
    ])
}

fn printed_band_color(source: &ImageU8, p: [Point; 4], side: usize, band: f64) -> Option<[u8; 3]> {
    let a = p[side];
    let b = p[(side + 1) % 4];
    let line = Line::through(a, b);
    let reach =
        (band * 12.0).min(distance(a, p[(side + 3) % 4]).min(distance(b, p[(side + 2) % 4])) / 4.0);
    let mut profile = [[0_u8; 3]; 14];
    for (index, profile_color) in profile.iter_mut().enumerate() {
        let depth = index as i32 - 1;
        let offset = if depth < 0 {
            band
        } else {
            -(depth as f64) * reach / 12.0
        };
        let mut colors = [[0_u8; 3]; 16];
        for (i, color) in colors.iter_mut().enumerate() {
            let t = 0.2 + 0.6 * i as f64 / 15.0;
            let x = a.x + (b.x - a.x) * t + line.nx * offset;
            let y = a.y + (b.y - a.y) * t + line.ny * offset;
            *color = source_color(source, x, y)?;
        }
        *profile_color = std::array::from_fn(|channel| {
            let mut values = colors.map(|color| color[channel]);
            values.sort_unstable();
            values[8]
        });
    }
    (0..3)
        .any(|channel| {
            let change = profile[0][channel].abs_diff(profile[13][channel]);
            change >= 32
                && profile.windows(2).any(|pair| {
                    let step = pair[0][channel].abs_diff(pair[1][channel]);
                    step >= 24 && step as u16 * 2 >= change as u16
                })
        })
        .then_some(profile[0])
}

fn edge_continues_beyond_content(
    source: &ImageU8,
    corner: Point,
    neighbor: Point,
    band: f64,
    outside_sign: f64,
    content: [u8; 3],
) -> bool {
    let length = distance(corner, neighbor);
    let beyond = |amount: f64| Point {
        x: corner.x + (corner.x - neighbor.x) * amount / length,
        y: corner.y + (corner.y - neighbor.y) * amount / length,
    };
    let edge = [beyond(band), beyond(band * 3.0)];
    let line = Line::through(edge[0], edge[1]);
    let scores = color_edge_scores(source, edge, band / 2.0);
    (0..91).any(|step| {
        if scores.values.iter().filter(|row| row[step] >= 4.0).count() < 40 {
            return false;
        }
        let offset = (step as f64 - 45.0) * band / 60.0;
        let mut background = [[0_u8; 3]; 16];
        for (i, color) in background.iter_mut().enumerate() {
            let center = beyond(band * (1.0 + 2.0 * i as f64 / 15.0));
            let x = center.x + line.nx * (offset + outside_sign * band);
            let y = center.y + line.ny * (offset + outside_sign * band);
            let Some(value) = source_color(source, x, y) else {
                return false;
            };
            *color = value;
        }
        if !(0..3).any(|channel| {
            let mut values = background.map(|color| color[channel]);
            values.sort_unstable();
            let reference = values[8];
            let mut deviations = values.map(|value| value.abs_diff(reference));
            deviations.sort_unstable();
            let difference = content[channel].abs_diff(reference);
            difference >= 24 && difference as u16 > 3 * deviations[8] as u16
        }) {
            return false;
        }
        let mut deltas = [[0.0; 3]; 48];
        for (i, delta) in deltas.iter_mut().enumerate() {
            let center = beyond(band * (1.0 + 2.0 * (i as f64 + 1.0) / 49.0));
            let sample = |offset: f64| {
                source_color(
                    source,
                    center.x + line.nx * offset,
                    center.y + line.ny * offset,
                )
            };
            let (Some(a), Some(b)) = (sample(offset - 1.25), sample(offset + 1.25)) else {
                return false;
            };
            *delta = std::array::from_fn(|channel| a[channel] as f64 - b[channel] as f64);
        }
        let reference = std::array::from_fn(|channel| {
            let mut values = deltas.map(|delta| delta[channel]);
            values.sort_by(f64::total_cmp);
            values[24]
        });
        let dot = |a: [f64; 3], b: [f64; 3]| a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
        (0..48)
            .filter(|&i| {
                scores.values[i][step] >= 4.0
                    && dot(deltas[i], reference)
                        > 0.9 * (dot(deltas[i], deltas[i]) * dot(reference, reference)).sqrt()
            })
            .count()
            >= 40
    })
}

fn cuts_printed_content(source: &ImageU8, p: [Point; 4], band: f64) -> bool {
    let support = |edge: [Point; 2]| {
        color_edge_scores(source, edge, band / 2.0)
            .values
            .iter()
            .filter(|row| row.iter().any(|&score| score >= 4.0))
            .count()
    };
    (0..4).any(|side| {
        let Some(content) = printed_band_color(source, p, side, band) else {
            return false;
        };
        let first =
            edge_continues_beyond_content(source, p[side], p[(side + 3) % 4], band, 1.0, content);
        let second = edge_continues_beyond_content(
            source,
            p[(side + 1) % 4],
            p[(side + 2) % 4],
            band,
            -1.0,
            content,
        );
        (first && second) || ((first || second) && support([p[side], p[(side + 1) % 4]]) < 32)
    })
}

pub(super) fn refine_capture(
    source: &ImageU8,
    quad: Quad,
    needs_complete_support: bool,
) -> OpResult<Option<Quad>> {
    let extent = SourceExtent::new(source.width, source.height)?;
    validate_quad(quad, extent)?;
    let scale = (640.0 / extent.width.max(extent.height)).min(1.0);
    let preview = crate::cv::resize_u8(
        source,
        (extent.width * scale).round().max(1.0) as i32,
        (extent.height * scale).round().max(1.0) as i32,
        crate::cv::Interp::Area,
    )?;
    let sx = preview.width as f64 / extent.width;
    let sy = preview.height as f64 / extent.height;
    let p = points(quad).map(|p| Point {
        x: p.x * sx,
        y: p.y * sy,
    });
    let band = (preview.width.min(preview.height) as f64 * 0.008).clamp(1.5, 5.0);
    let retain_content = |candidate: [Point; 4], source_quad: Quad| {
        if cuts_printed_content(&preview, candidate, band) {
            None
        } else {
            Some(source_quad)
        }
    };
    let mut lines = std::array::from_fn::<_, 4, _>(|i| Line::through(p[i], p[(i + 1) % 4]));
    let mut improved = 0;
    let mut supported = 0;
    for side in 0..4 {
        let line = lines[side];
        let edge_points = [p[side], p[(side + 1) % 4]];
        let border = edge_points.iter().all(|p| p.x.abs() < 1.0)
            || edge_points
                .iter()
                .all(|p| (p.x - preview.width as f64).abs() < 1.0)
            || edge_points.iter().all(|p| p.y.abs() < 1.0)
            || edge_points
                .iter()
                .all(|p| (p.y - preview.height as f64).abs() < 1.0);
        if border {
            supported += 1;
            continue;
        }
        let mut samples = Vec::new();
        let mut before = 0.0;
        let mut after = 0.0;
        for i in 0..48 {
            let t = (i as f64 + 1.0) / 49.0;
            let center = Point {
                x: p[side].x + (p[(side + 1) % 4].x - p[side].x) * t,
                y: p[side].y + (p[(side + 1) % 4].y - p[side].y) * t,
            };
            let gradient = |offset: f64| -> Option<f64> {
                let a = brightness(
                    &preview,
                    center.x + line.nx * (offset - 1.25),
                    center.y + line.ny * (offset - 1.25),
                )?;
                let b = brightness(
                    &preview,
                    center.x + line.nx * (offset + 1.25),
                    center.y + line.ny * (offset + 1.25),
                )?;
                Some((a - b).abs())
            };
            let mut strongest = gradient(0.0).unwrap_or(0.0);
            let base = strongest;
            let mut offset = 0.0;
            for step in -10..=10 {
                let candidate = step as f64 * band / 10.0;
                if let Some(value) = gradient(candidate) {
                    let penalized = value / (1.0 + 0.25 * (candidate / band).powi(2));
                    if penalized > strongest {
                        strongest = penalized;
                        offset = candidate;
                    }
                }
            }
            if strongest >= 6.0 {
                samples.push(Point {
                    x: center.x + line.nx * offset,
                    y: center.y + line.ny * offset,
                });
                before += base;
                after += strongest;
            }
        }
        if samples.len() < 32 {
            continue;
        }
        supported += 1;
        let fitted = fit_line(&samples, line, 0.75);
        if samples
            .iter()
            .filter(|&&p| fitted.residual(p).abs() < 1.0)
            .count()
            * 5
            < samples.len() * 4
        {
            continue;
        }
        if after <= before * 1.15 {
            continue;
        }
        lines[side] = fitted;
        improved += 1;
    }
    let color_samples = std::array::from_fn::<_, 4, _>(|side| {
        color_edge_scores(&preview, [p[side], p[(side + 1) % 4]], band * 3.0)
    });
    if (supported < 3 || needs_complete_support)
        && color_samples
            .iter()
            .any(|samples| samples.supported_positions() < 32)
    {
        return Ok(None);
    }
    if let Some(refined) = refine_color_edges(p, &color_samples, band * 3.0) {
        let source_refined = quad_from_points(refined.map(|p| Point {
            x: p.x / sx,
            y: p.y / sy,
        }));
        if validate_quad(source_refined, extent).is_ok() {
            return Ok(retain_content(refined, source_refined));
        }
    }
    if improved == 0 {
        return Ok(retain_content(p, quad));
    }
    let mut refined = p;
    for i in 0..4 {
        let Some(point) = lines[(i + 3) % 4].intersection(lines[i]) else {
            return Ok(retain_content(p, quad));
        };
        if distance(point, p[i]) > band * 1.5 {
            return Ok(retain_content(p, quad));
        }
        refined[i] = point;
    }
    let source_refined = quad_from_points(refined.map(|p| Point {
        x: p.x / sx,
        y: p.y / sy,
    }));
    if validate_quad(source_refined, extent).is_err() {
        return Ok(retain_content(p, quad));
    }
    Ok(retain_content(refined, source_refined))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn polygon_mask<const N: usize>(p: [Point; N]) -> OpResult<ProbabilityMap> {
        let mut values = Vec::new();
        for y in 0..256 {
            for x in 0..256 {
                let mut covered = 0;
                for dy in [0.125, 0.375, 0.625, 0.875] {
                    for dx in [0.125, 0.375, 0.625, 0.875] {
                        let q = Point {
                            x: x as f64 + dx,
                            y: y as f64 + dy,
                        };
                        if (0..N).all(|i| cross(p[i], p[(i + 1) % N], q) >= 0.0) {
                            covered += 1;
                        }
                    }
                }
                values.push(0.02 + 0.96 * covered as f32 / 16.0);
            }
        }
        ProbabilityMap::new(values, 256, 256)
    }

    #[test]
    fn enclosed_mask_hole_does_not_hide_a_partially_obscured_page() -> OpResult<()> {
        let p = [(40.0, 75.0), (220.0, 75.0), (220.0, 190.0), (40.0, 190.0)]
            .map(|(x, y)| Point { x, y });
        for hole in [false, true] {
            let mut mask = polygon_mask(p)?;
            for y in 177..190 {
                for x in 100..180 {
                    mask.values[y * 256 + x] = 0.02;
                }
            }
            if hole {
                for y in 82..92 {
                    for x in 116..160 {
                        mask.values[y * 256 + x] = 0.02;
                    }
                }
            }
            let quad = locate(&mask, SourceExtent::new(2304, 4096)?, SearchBudget::Capture)
                .quad
                .ok_or(format!("page rejected with enclosed hole: {hole}"))?;
            for (actual, expected) in points(quad.corners).into_iter().zip(p) {
                assert!(distance(actual, expected) < 2.0);
            }
            if hole {
                assert!(quad.needs_complete_source_support);
                let mut source = ImageU8::new(256, 256, 3, vec![30; 256 * 256 * 3])?;
                for y in 20..190 {
                    for x in 40..220 {
                        source.data[(y * 256 + x) * 3..(y * 256 + x + 1) * 3].fill(230);
                    }
                }
                assert!(refine_capture(&source, quad.corners, false)?.is_some());
                assert!(refine_capture(&source, quad.corners, true)?.is_none());
            }
        }
        Ok(())
    }

    #[test]
    fn outer_boundaries_keep_open_and_diagonal_channels() -> OpResult<()> {
        let mut values = vec![0.02; 100];
        for y in 1..9 {
            for x in 1..9 {
                values[y * 10 + x] = 0.98;
            }
        }
        for y in 3..7 {
            for x in 3..7 {
                values[y * 10 + x] = 0.02;
            }
        }
        values[44] = 0.98;
        let mask = ProbabilityMap::new(values, 10, 10)?;
        let regions = background_regions(&mask, 0.5);
        assert_eq!(regions[0], 0);
        assert_ne!(regions[33], 0);
        let mut open = mask;
        for y in 0..4 {
            open.values[y * 10 + 3] = 0.02;
        }
        let regions = background_regions(&open, 0.5);
        assert_eq!(regions[33], 0);
        assert_eq!(regions[66], 0);
        open.values[13] = 0.98;
        open.values[23] = 0.98;
        open.values[11] = 0.02;
        open.values[22] = 0.02;
        assert_eq!(background_regions(&open, 0.5)[33], 0);
        Ok(())
    }

    #[test]
    fn enclosing_rectangles_do_not_override_missing_foreground() -> OpResult<()> {
        let p = [(30.0, 30.0), (226.0, 30.0), (226.0, 226.0), (30.0, 226.0)]
            .map(|(x, y)| Point { x, y });
        for island in [false, true] {
            let mut mask = polygon_mask(p)?;
            for y in 50..206 {
                for x in 50..206 {
                    mask.values[y * 256 + x] = 0.02;
                }
            }
            if island {
                for y in 100..156 {
                    for x in 100..156 {
                        mask.values[y * 256 + x] = 0.98;
                    }
                }
            }
            let before = mask.values.clone();
            let found = components(&mask, 0.5, 4, true);
            assert_eq!(mask.values, before);
            assert_eq!(found.len(), if island { 2 } else { 1 });
            assert_eq!(found[0].pixels.len(), 196 * 196 - 156 * 156);
            if island {
                assert!(!found[1].boundary.is_empty());
            }
            for budget in [SearchBudget::Live, SearchBudget::Capture] {
                assert!(
                    locate(&mask, SourceExtent::new(1200, 1600)?, budget)
                        .quad
                        .is_none()
                );
            }
        }
        Ok(())
    }

    #[test]
    fn dominant_page_inside_a_separate_foreground_ring_keeps_its_boundary() -> OpResult<()> {
        let p = [(50.0, 50.0), (206.0, 50.0), (206.0, 206.0), (50.0, 206.0)]
            .map(|(x, y)| Point { x, y });
        let mut mask = polygon_mask(p)?;
        for y in 10..246 {
            for x in 10..246 {
                if !(12..244).contains(&x) || !(12..244).contains(&y) {
                    mask.values[y * 256 + x] = 0.98;
                }
            }
        }
        for budget in [SearchBudget::Live, SearchBudget::Capture] {
            let quad = locate_with_boundaries(&mask, SourceExtent::new(1200, 1600)?, budget, true)
                .quad
                .ok_or("separate enclosing component hid the page")?;
            for (actual, expected) in points(quad.corners).into_iter().zip(p) {
                assert!(distance(actual, expected) < 2.0);
            }
        }
        Ok(())
    }

    #[test]
    fn outer_boundaries_retain_frame_edges_without_exterior_pixels() -> OpResult<()> {
        for coordinates in [
            [(0.0, 0.0), (256.0, 0.0), (256.0, 256.0), (0.0, 256.0)],
            [(30.0, 0.0), (220.0, 0.0), (220.0, 226.0), (30.0, 226.0)],
            [(0.0, 30.0), (226.0, 30.0), (226.0, 226.0), (0.0, 226.0)],
        ] {
            let p = coordinates.map(|(x, y)| Point { x, y });
            for hole in [false, true] {
                let mut mask = polygon_mask(p)?;
                if hole {
                    for y in 90..110 {
                        for x in 90..110 {
                            mask.values[y * 256 + x] = 0.02;
                        }
                    }
                }
                let found = locate_with_boundaries(
                    &mask,
                    SourceExtent::new(1200, 1600)?,
                    SearchBudget::Capture,
                    true,
                )
                .quad
                .ok_or("frame-edge page rejected")?;
                for (actual, expected) in points(found.corners).into_iter().zip(p) {
                    assert!(distance(actual, expected) < 2.0);
                }
            }
        }
        Ok(())
    }

    #[test]
    fn cut_corner_recovers_intersection_of_supporting_sides() -> OpResult<()> {
        let map = polygon_mask(
            [
                (60.0, 30.0),
                (220.0, 30.0),
                (220.0, 230.0),
                (30.0, 230.0),
                (30.0, 70.0),
            ]
            .map(|(x, y)| Point { x, y }),
        )?;
        let expected = [(30.0, 30.0), (220.0, 30.0), (220.0, 230.0), (30.0, 230.0)]
            .map(|(x, y)| Point { x, y });
        for budget in [SearchBudget::Live, SearchBudget::Capture] {
            let found = locate(&map, SourceExtent::new(1200, 1600)?, budget)
                .quad
                .ok_or("folded page rejected")?;
            for (actual, expected) in points(found.corners).into_iter().zip(expected) {
                assert!(
                    distance(actual, expected) < 2.0,
                    "{actual:?} versus {expected:?}"
                );
            }
        }
        Ok(())
    }

    fn cut_corner(p: [Point; 4], corner: usize, fraction: f64) -> [Point; 5] {
        let interpolate = |a: Point, b: Point| Point {
            x: a.x + (b.x - a.x) * fraction,
            y: a.y + (b.y - a.y) * fraction,
        };
        [
            interpolate(p[corner], p[(corner + 1) % 4]),
            p[(corner + 1) % 4],
            p[(corner + 2) % 4],
            p[(corner + 3) % 4],
            interpolate(p[corner], p[(corner + 3) % 4]),
        ]
    }

    #[test]
    fn supporting_corners_survive_rotation_perspective_and_cut_size() -> OpResult<()> {
        let extent = SourceExtent::new(256, 256)?;
        for coordinates in [
            [(60.0, 40.0), (200.0, 40.0), (200.0, 216.0), (60.0, 216.0)],
            [(61.0, 52.0), (198.0, 40.0), (213.0, 203.0), (43.0, 215.0)],
        ] {
            for angle in [0.0_f64, 0.43, 1.28] {
                let p = coordinates.map(|(x, y)| Point {
                    x: 128.0 + (x - 128.0) * angle.cos() - (y - 128.0) * angle.sin(),
                    y: 128.0 + (x - 128.0) * angle.sin() + (y - 128.0) * angle.cos(),
                });
                for corner in 0..4 {
                    for fraction in [0.08, 0.18, 0.30] {
                        let map = polygon_mask(cut_corner(p, corner, fraction))?;
                        for budget in [SearchBudget::Live, SearchBudget::Capture] {
                            let found = locate(&map, SourceExtent::new(1200, 1600)?, budget)
                                .quad
                                .ok_or_else(|| {
                                format!("rejected angle {angle}, corner {corner}, cut {fraction}")
                            })?;
                            for (actual, expected) in points(found.corners)
                                .into_iter()
                                .zip(points(canonical(p, extent)))
                            {
                                assert!(
                                    distance(actual, expected) < 2.0,
                                    "angle {angle}, corner {corner}, cut {fraction}: {actual:?} versus {expected:?}"
                                );
                            }
                        }
                    }
                }
            }
        }
        Ok(())
    }

    #[test]
    fn large_missing_corners_and_regular_polygons_are_not_completed() -> OpResult<()> {
        let p = [(35.0, 25.0), (225.0, 25.0), (225.0, 235.0), (35.0, 235.0)]
            .map(|(x, y)| Point { x, y });
        let pentagon = std::array::from_fn::<_, 5, _>(|i| {
            let angle = i as f64 * std::f64::consts::TAU / 5.0;
            Point {
                x: 128.0 + angle.cos() * 95.0,
                y: 128.0 + angle.sin() * 95.0,
            }
        });
        let octagon = std::array::from_fn::<_, 8, _>(|i| {
            let angle = i as f64 * std::f64::consts::TAU / 8.0;
            Point {
                x: 128.0 + angle.cos() * 95.0,
                y: 128.0 + angle.sin() * 95.0,
            }
        });
        for map in [
            polygon_mask(cut_corner(p, 0, 0.60))?,
            polygon_mask(pentagon)?,
            polygon_mask(octagon)?,
            polygon_mask(
                [
                    (90.0, 25.0),
                    (170.0, 25.0),
                    (225.0, 80.0),
                    (225.0, 235.0),
                    (35.0, 235.0),
                    (35.0, 80.0),
                ]
                .map(|(x, y)| Point { x, y }),
            )?,
        ] {
            for budget in [SearchBudget::Live, SearchBudget::Capture] {
                assert!(
                    locate(&map, SourceExtent::new(1200, 1600)?, budget)
                        .quad
                        .is_none()
                );
            }
        }
        Ok(())
    }

    #[test]
    fn local_corner_obstruction_preserves_the_four_main_sides() -> OpResult<()> {
        let p = [(35.0, 25.0), (225.0, 25.0), (225.0, 235.0), (35.0, 235.0)]
            .map(|(x, y)| Point { x, y });
        let mut map = polygon_mask(p)?;
        for y in 25..65 {
            for x in 35..75 {
                map.values[y * 256 + x] = 0.02;
            }
        }
        for budget in [SearchBudget::Live, SearchBudget::Capture] {
            let found = locate(&map, SourceExtent::new(1200, 1600)?, budget)
                .quad
                .ok_or("obscured page rejected")?;
            for (actual, expected) in points(found.corners).into_iter().zip(p) {
                assert!(distance(actual, expected) < 2.0);
            }
        }
        Ok(())
    }

    #[test]
    fn completed_corner_still_requires_source_page_edges() -> OpResult<()> {
        let p = [(35.0, 25.0), (225.0, 25.0), (225.0, 235.0), (35.0, 235.0)]
            .map(|(x, y)| Point { x, y });
        let map = polygon_mask(cut_corner(p, 0, 0.25))?;
        let quad = locate(&map, SourceExtent::new(256, 256)?, SearchBudget::Capture)
            .quad
            .ok_or("cut page rejected")?
            .corners;
        let data = map
            .values
            .iter()
            .flat_map(|v| [if *v > 0.5 { 230 } else { 50 }; 3])
            .collect();
        let source = ImageU8::new(256, 256, 3, data)?;
        let refined =
            refine_capture(&source, quad, false)?.ok_or("visible supporting edges rejected")?;
        for (actual, expected) in points(refined).into_iter().zip(p) {
            assert!(distance(actual, expected) < 2.0);
        }
        let unsupported = ImageU8::new(256, 256, 3, vec![230; 256 * 256 * 3])?;
        assert!(refine_capture(&unsupported, quad, false)?.is_none());
        Ok(())
    }

    #[test]
    fn independent_convex_page_fixtures_recover_all_corners() -> OpResult<()> {
        let cases = [
            [(30.0, 20.0), (225.0, 20.0), (225.0, 235.0), (30.0, 235.0)],
            [(63.0, 40.0), (216.0, 17.0), (234.0, 212.0), (20.0, 238.0)],
            [(100.0, 8.0), (153.0, 14.0), (159.0, 240.0), (90.0, 246.0)],
            [(0.0, 20.0), (228.0, 30.0), (223.0, 238.0), (0.0, 246.0)],
            [(0.0, 0.0), (256.0, 0.0), (256.0, 256.0), (0.0, 256.0)],
        ];
        for coordinates in cases {
            let p = coordinates.map(|(x, y)| Point { x, y });
            let map = polygon_mask(p)?;
            for budget in [SearchBudget::Live, SearchBudget::Capture] {
                let found = locate(&map, SourceExtent::new(1200, 800)?, budget)
                    .quad
                    .ok_or("page rejected")?;
                for (actual, expected) in points(found.corners).into_iter().zip(p) {
                    assert!(
                        distance(actual, expected) < 2.0,
                        "{actual:?} versus {expected:?}"
                    );
                }
            }
        }
        Ok(())
    }

    #[test]
    fn noise_and_round_objects_do_not_become_pages() -> OpResult<()> {
        for round in [false, true] {
            let values = (0..256 * 256)
                .map(|i| {
                    let x = (i % 256) as f64 - 128.0;
                    let y = (i / 256) as f64 - 128.0;
                    if round && x * x + y * y < 90.0 * 90.0 {
                        0.98
                    } else if !round && i % 113 == 0 {
                        0.9
                    } else {
                        0.04
                    }
                })
                .collect();
            let map = ProbabilityMap::new(values, 256, 256)?;
            assert!(
                locate(&map, SourceExtent::new(1200, 800)?, SearchBudget::Capture)
                    .quad
                    .is_none()
            );
        }
        Ok(())
    }

    #[test]
    fn separate_components_are_not_enclosed_together() -> OpResult<()> {
        let mut map = polygon_mask(
            [(12.0, 40.0), (100.0, 40.0), (100.0, 220.0), (12.0, 220.0)]
                .map(|(x, y)| Point { x, y }),
        )?;
        for y in 70..180 {
            for x in 150..240 {
                map.values[y * 256 + x] = 0.98;
            }
        }
        for budget in [SearchBudget::Live, SearchBudget::Capture] {
            let found = locate(&map, SourceExtent::new(1200, 800)?, budget)
                .quad
                .ok_or("page rejected")?;
            assert!(points(found.corners).iter().all(|p| p.x < 110.0));
        }
        Ok(())
    }

    #[test]
    fn unsupported_dominant_region_does_not_promote_a_small_island() -> OpResult<()> {
        for foreground in [0.65, 0.98] {
            let mut map = polygon_mask(
                [
                    (213.0, 213.0),
                    (233.0, 213.0),
                    (233.0, 233.0),
                    (213.0, 233.0),
                ]
                .map(|(x, y)| Point { x, y }),
            )?;
            for y in 0..256 {
                for x in 0..256 {
                    if (x as f64 - 100.0).hypot(y as f64 - 100.0) < 75.0 {
                        map.values[y * 256 + x] = foreground;
                    }
                }
            }
            for budget in [SearchBudget::Live, SearchBudget::Capture] {
                assert!(
                    locate(&map, SourceExtent::new(1200, 800)?, budget)
                        .quad
                        .is_none(),
                    "foreground {foreground} yielded a minor interior crop"
                );
            }
        }
        Ok(())
    }

    #[test]
    fn isolated_small_pages_and_narrow_receipts_remain_detectable() -> OpResult<()> {
        for (width, height) in [(16.0, 16.0), (16.0, 40.0), (8.0, 190.0)] {
            let p =
                [(0.0, 0.0), (width, 0.0), (width, height), (0.0, height)].map(|(x, y)| Point {
                    x: x + 100.0,
                    y: y + 30.0,
                });
            let map = polygon_mask(p)?;
            for budget in [SearchBudget::Live, SearchBudget::Capture] {
                let found = locate(&map, SourceExtent::new(1200, 800)?, budget)
                    .quad
                    .ok_or("small page rejected")?;
                for (actual, expected) in points(found.corners).into_iter().zip(p) {
                    assert!(distance(actual, expected) < 2.0);
                }
            }
        }
        Ok(())
    }

    #[test]
    fn ordinary_supported_page_precedes_an_uncertain_competing_fit() -> OpResult<()> {
        let mut map = ProbabilityMap::new(vec![0.02; 256 * 256], 256, 256)?;
        for y in 20..180 {
            for x in 15..105 {
                map.values[y * 256 + x] = 0.75;
            }
        }
        for y in 40..200 {
            for x in 145..235 {
                map.values[y * 256 + x] = 0.98;
            }
        }
        for x in (150..230).step_by(6) {
            for xx in x..x + 2 {
                for y in 40..54 {
                    map.values[y * 256 + xx] = 0.02;
                }
            }
        }
        let found = locate(&map, SourceExtent::new(256, 256)?, SearchBudget::Capture)
            .quad
            .ok_or("supported page rejected")?;
        assert!(points(found.corners).iter().all(|point| point.x < 110.0));
        assert!(!found.needs_complete_source_support);
        let extent = SourceExtent::new(256, 256)?;
        let mut source = ImageU8::new(256, 256, 3, vec![50; 256 * 256 * 3])?;
        for y in 20..180 {
            for x in 15..105 {
                source.data[(y * 256 + x) * 3..(y * 256 + x + 1) * 3].fill(220);
                map.values[y * 256 + x] = 0.02;
            }
        }
        assert!(
            refine_capture(
                &source,
                found.in_source(extent),
                found.needs_complete_source_support
            )?
            .is_some()
        );
        let uncertain = locate(&map, extent, SearchBudget::Capture)
            .quad
            .ok_or("uncertain competing candidate was not exercised")?;
        assert!(uncertain.needs_complete_source_support);
        assert!(
            refine_capture(
                &source,
                uncertain.in_source(extent),
                uncertain.needs_complete_source_support
            )?
            .is_none()
        );
        Ok(())
    }

    #[test]
    fn local_boundary_irregularities_preserve_four_sustained_page_sides() -> OpResult<()> {
        let p = [(40.0, 30.0), (220.0, 30.0), (220.0, 230.0), (40.0, 230.0)]
            .map(|(x, y)| Point { x, y });
        let mut map = polygon_mask(p)?;
        for y in (40..220).step_by(8) {
            for yy in y..y + 2 {
                for x in (40..50).chain(210..220) {
                    map.values[yy * 256 + x] = 0.02;
                }
            }
        }
        for x in (50..210).step_by(8) {
            for xx in x..x + 2 {
                for y in (30..40).chain(220..230) {
                    map.values[y * 256 + xx] = 0.02;
                }
            }
        }
        let extent = SourceExtent::new(256, 256)?;
        let found = locate(&map, extent, SearchBudget::Capture)
            .quad
            .ok_or("page with four sustained sides rejected")?;
        for (actual, expected) in points(found.corners).into_iter().zip(p) {
            assert!(distance(actual, expected) < 4.0);
        }
        let mut source = ImageU8::new(256, 256, 3, vec![50; 256 * 256 * 3])?;
        for y in 30..230 {
            for x in 40..220 {
                source.data[(y * 256 + x) * 3..(y * 256 + x + 1) * 3].fill(220);
            }
        }
        assert!(
            refine_capture(
                &source,
                found.in_source(extent),
                found.needs_complete_source_support
            )?
            .is_some()
        );
        for y in 0..31 {
            for x in 40..220 {
                source.data[(y * 256 + x) * 3..(y * 256 + x + 1) * 3].fill(if y == 30 {
                    30
                } else {
                    220
                });
            }
        }
        assert!(
            refine_capture(
                &source,
                found.in_source(extent),
                found.needs_complete_source_support
            )?
            .is_none()
        );
        Ok(())
    }

    #[test]
    fn canonical_labels_survive_nonsquare_source_scaling() -> OpResult<()> {
        let p = [(0.4, 0.02), (0.9, 0.4), (0.6, 0.95), (0.1, 0.4)].map(|(x, y)| Point { x, y });
        let a = canonical(
            p,
            SourceExtent {
                width: 1.0,
                height: 1.0,
            },
        );
        let b = canonical(
            p.map(|p| Point {
                x: p.x * 2000.0,
                y: p.y * 500.0,
            }),
            SourceExtent::new(2000, 500)?,
        );
        for (a, b) in points(a).into_iter().zip(points(b)) {
            assert!((a.x - b.x / 2000.0).abs() < 1e-12 && (a.y - b.y / 500.0).abs() < 1e-12);
        }
        Ok(())
    }

    #[test]
    fn source_refinement_follows_long_page_edge_without_jumping_to_text() -> OpResult<()> {
        let mut source = ImageU8::new(400, 300, 3, vec![50; 400 * 300 * 3])?;
        for y in 40..260 {
            for x in 60..340 {
                source.data[(y * 400 + x) * 3..(y * 400 + x + 1) * 3].fill(235);
            }
        }
        for y in (55..250).step_by(12) {
            for x in 80..320 {
                source.data[(y * 400 + x) * 3..(y * 400 + x + 1) * 3].fill(30);
            }
        }
        let before = quad_from_points(
            [(58.0, 38.0), (342.0, 38.0), (342.0, 262.0), (58.0, 262.0)]
                .map(|(x, y)| Point { x, y }),
        );
        let after = refine_capture(&source, before, false)?.ok_or("source boundary rejected")?;
        let expected = [(60.0, 40.0), (340.0, 40.0), (340.0, 260.0), (60.0, 260.0)]
            .map(|(x, y)| Point { x, y });
        let before_error: f64 = points(before)
            .into_iter()
            .zip(expected)
            .map(|(a, b)| distance(a, b))
            .sum();
        let after_error: f64 = points(after)
            .into_iter()
            .zip(expected)
            .map(|(a, b)| distance(a, b))
            .sum();
        assert!(
            after_error < before_error,
            "before {before_error}, after {after_error}"
        );
        Ok(())
    }
}

#[cfg(test)]
mod benchmarks {
    use super::*;
    use std::time::Instant;

    #[test]
    #[ignore = "release stage performance measurements"]
    fn detection_without_inference() -> OpResult<()> {
        let p = [(50.0, 20.0), (226.0, 48.0), (207.0, 230.0), (18.0, 210.0)]
            .map(|(x, y)| Point { x, y });
        let values = (0..256 * 256)
            .map(|i| {
                let point = Point {
                    x: (i % 256) as f64 + 0.5,
                    y: (i / 256) as f64 + 0.5,
                };
                if (0..4).all(|j| cross(p[j], p[(j + 1) % 4], point) >= 0.0) {
                    0.98
                } else {
                    0.02
                }
            })
            .collect();
        let map = ProbabilityMap::new(values, 256, 256)?;
        let extent = SourceExtent::new(4000, 3000)?;
        for (name, budget) in [
            ("live", SearchBudget::Live),
            ("capture", SearchBudget::Capture),
        ] {
            let mut times = Vec::new();
            for _ in 0..101 {
                let start = Instant::now();
                assert!(locate(&map, extent, budget).quad.is_some());
                times.push(start.elapsed().as_secs_f64() * 1000.0);
            }
            let cold = times.remove(0);
            times.sort_by(f64::total_cmp);
            println!(
                "detect {name}: cold_ms={cold:.3}, median_ms={:.3}, p95_ms={:.3}",
                times[50], times[95]
            );
        }
        Ok(())
    }
}

#[cfg(test)]
mod source_evidence_tests {
    use super::*;

    #[test]
    fn biased_header_seed_cannot_remove_printed_content() -> OpResult<()> {
        let mut source = ImageU8::new(400, 600, 3, vec![180; 400 * 600 * 3])?;
        for y in 60..540 {
            for x in 60..340 {
                source.data[(y * 400 + x) * 3..(y * 400 + x + 1) * 3].fill(195);
            }
        }
        for y in 63..100 {
            for x in 65..335 {
                source.data[(y * 400 + x) * 3..(y * 400 + x + 1) * 3].fill(50);
            }
        }
        let biased = quad_from_points(
            [(60.0, 88.0), (340.0, 88.0), (340.0, 540.0), (60.0, 540.0)]
                .map(|(x, y)| Point { x, y }),
        );
        if let Some(refined) = refine_capture(&source, biased, false)? {
            assert!(
                refined.top_left.y <= 65.0 && refined.top_right.y <= 65.0,
                "printed header lost: {refined:?}"
            );
        }
        Ok(())
    }

    #[test]
    fn tilted_header_seeds_preserve_content_across_rotation_and_paper_tone() -> OpResult<()> {
        for (background, paper, ink) in [
            ([180; 3], [195; 3], [50; 3]),
            ([100; 3], [60; 3], [210; 3]),
            ([180; 3], [195; 3], [35, 130, 165]),
            ([100; 3], [60; 3], [190, 80, 130]),
        ] {
            let mut source = ImageU8::new(400, 600, 3, background.repeat(400 * 600))?;
            for y in 60..540 {
                for x in 60..340 {
                    source.data[(y * 400 + x) * 3..(y * 400 + x + 1) * 3].copy_from_slice(&paper);
                }
            }
            for y in 63..100 {
                for x in 65..335 {
                    source.data[(y * 400 + x) * 3..(y * 400 + x + 1) * 3].copy_from_slice(&ink);
                }
            }
            for y in 0..600 {
                for x in 0..400 {
                    for channel in 0..3 {
                        let index = (y * 400 + x) * 3 + channel;
                        source.data[index] = (source.data[index] as i32 + x as i32 / 20 - 10) as u8;
                    }
                }
            }
            for (left, right) in [(60.0, 88.0), (88.0, 60.0)] {
                for turns in 0..4 {
                    let rotated = crate::cv::rotate_u8(&source, turns * 90)?;
                    let rotate = |(x, y)| match turns {
                        0 => Point { x, y },
                        1 => Point { x: 600.0 - y, y: x },
                        2 => Point {
                            x: 400.0 - x,
                            y: 600.0 - y,
                        },
                        _ => Point { x: y, y: 400.0 - x },
                    };
                    let biased = canonical(
                        [(60.0, left), (340.0, right), (340.0, 540.0), (60.0, 540.0)].map(rotate),
                        SourceExtent::new(rotated.width, rotated.height)?,
                    );
                    let Some(refined) = refine_capture(&rotated, biased, false)? else {
                        continue;
                    };
                    let corners = points(refined);
                    for point in
                        [(66.0, 64.0), (334.0, 64.0), (334.0, 99.0), (66.0, 99.0)].map(rotate)
                    {
                        assert!(
                            (0..4).all(|side| {
                                cross(corners[side], corners[(side + 1) % 4], point)
                                    >= -distance(corners[side], corners[(side + 1) % 4]) * 1.5
                            }),
                            "printed header lost at rotation {turns}: {refined:?}"
                        );
                    }
                }
            }
        }
        Ok(())
    }

    #[test]
    fn plain_margins_and_folded_corners_remain_usable_on_textured_backgrounds() -> OpResult<()> {
        for folded in [false, true] {
            let mut source = ImageU8::new(400, 600, 3, vec![0; 400 * 600 * 3])?;
            for y in 0..600 {
                for x in 0..400 {
                    let paper = (60..340).contains(&x)
                        && (60..540).contains(&y)
                        && (!folded || x + y >= 160);
                    let value = if paper {
                        195 + y / 15
                    } else {
                        80 + (x * 31 + y * 17) % 80
                    };
                    source.data[(y * 400 + x) * 3..(y * 400 + x + 1) * 3].fill(value as u8);
                }
            }
            for turns in 0..4 {
                let rotated = crate::cv::rotate_u8(&source, turns * 90)?;
                let rotate = |(x, y)| match turns {
                    0 => Point { x, y },
                    1 => Point { x: 600.0 - y, y: x },
                    2 => Point {
                        x: 400.0 - x,
                        y: 600.0 - y,
                    },
                    _ => Point { x: y, y: 400.0 - x },
                };
                let seed = canonical(
                    [(60.0, 60.0), (340.0, 88.0), (340.0, 540.0), (60.0, 540.0)].map(rotate),
                    SourceExtent::new(rotated.width, rotated.height)?,
                );
                assert!(
                    refine_capture(&rotated, seed, false)?.is_some(),
                    "plain margin rejected: rotation {turns}, folded {folded}"
                );
            }
        }
        Ok(())
    }

    #[test]
    fn curled_printed_header_keeps_background_above_its_outer_edge() -> OpResult<()> {
        let mut source = ImageU8::new(400, 600, 3, vec![0; 400 * 600 * 3])?;
        for y in 0..600 {
            for x in 0..400 {
                let top = 82.0 - 22.0 * ((x as f64 - 200.0) / 140.0).powi(2);
                let color = if (60..340).contains(&x) && (y as f64) >= top && y < 540 {
                    if y < 112 {
                        [35, 90, 50]
                    } else {
                        [135, 200, 175]
                    }
                } else {
                    [70 + ((x * 13 + y * 7) % 24) as u8; 3]
                };
                source.data[(y * 400 + x) * 3..(y * 400 + x + 1) * 3].copy_from_slice(&color);
            }
        }
        let seed = quad_from_points(
            [(60.0, 72.0), (340.0, 72.0), (340.0, 540.0), (60.0, 540.0)]
                .map(|(x, y)| Point { x, y }),
        );
        assert!(refine_capture(&source, seed, false)?.is_some());
        Ok(())
    }

    #[test]
    fn broad_printed_panel_does_not_displace_a_supported_outer_page() -> OpResult<()> {
        let mut source = ImageU8::new(400, 300, 3, vec![180; 400 * 300 * 3])?;
        for y in 40..260 {
            for x in 60..340 {
                source.data[(y * 400 + x) * 3..(y * 400 + x + 1) * 3].fill(195);
            }
        }
        for y in 45..255 {
            for x in 65..335 {
                source.data[(y * 400 + x) * 3..(y * 400 + x + 1) * 3].fill(90);
            }
        }
        for y in [100, 150, 200] {
            for x in 62..65 {
                source.data[(y * 400 + x) * 3..(y * 400 + x + 1) * 3].fill(30);
            }
        }
        let quad = quad_from_points(
            [(60.0, 40.0), (340.0, 40.0), (340.0, 260.0), (60.0, 260.0)]
                .map(|(x, y)| Point { x, y }),
        );
        let refined = refine_capture(&source, quad, false)?.ok_or("page rejected")?;
        for (actual, expected) in points(refined).into_iter().zip(points(quad)) {
            assert!(
                distance(actual, expected) < 2.0,
                "{actual:?} vs {expected:?}"
            );
        }
        Ok(())
    }

    #[test]
    fn sustained_chromatic_edges_refine_displaced_page_corners() -> OpResult<()> {
        let mut source = ImageU8::new(400, 300, 3, [80, 140, 200].repeat(400 * 300))?;
        let expected = [(80.0, 40.0), (315.0, 60.0), (340.0, 245.0), (60.0, 265.0)]
            .map(|(x, y)| Point { x, y });
        for y in 0..300 {
            for x in 0..400 {
                let point = Point {
                    x: x as f64,
                    y: y as f64,
                };
                if (0..4).all(|i| cross(expected[i], expected[(i + 1) % 4], point) >= 0.0) {
                    source.data[(y * 400 + x) * 3..(y * 400 + x + 1) * 3]
                        .copy_from_slice(&[40, 160, 200]);
                }
            }
        }
        let displaced = quad_from_points(
            [(84.0, 45.0), (312.0, 66.0), (344.0, 250.0), (66.0, 260.0)]
                .map(|(x, y)| Point { x, y }),
        );
        let refined = refine_capture(&source, displaced, false)?.ok_or("page rejected")?;
        for (actual, expected) in points(refined).into_iter().zip(expected) {
            assert!(
                distance(actual, expected) < 2.0,
                "{actual:?} vs {expected:?}"
            );
        }
        Ok(())
    }

    #[test]
    fn color_edge_rejects_thin_strokes_without_a_background_step() -> OpResult<()> {
        let mut source = ImageU8::new(400, 300, 3, vec![220; 400 * 300 * 3])?;
        for x in 60..340 {
            source.data[(100 * 400 + x) * 3..(100 * 400 + x + 1) * 3].fill(30);
        }
        let edge = [Point { x: 60.0, y: 100.0 }, Point { x: 340.0, y: 100.0 }];
        assert!(color_edge_scores(&source, edge, 7.2).supported_positions() < 32);
        for y in 100..300 {
            for x in 0..400 {
                source.data[(y * 400 + x) * 3..(y * 400 + x + 1) * 3].fill(150);
            }
        }
        assert!(color_edge_scores(&source, edge, 7.2).supported_positions() >= 32);
        Ok(())
    }

    #[test]
    fn chromatic_edges_support_pages_with_equal_luminance() -> OpResult<()> {
        let mut source = ImageU8::new(400, 300, 3, [80, 140, 200].repeat(400 * 300))?;
        for y in 40..260 {
            for x in 60..340 {
                source.data[(y * 400 + x) * 3..(y * 400 + x + 1) * 3]
                    .copy_from_slice(&[200, 140, 80]);
            }
        }
        let quad = quad_from_points(
            [(60.0, 40.0), (340.0, 40.0), (340.0, 260.0), (60.0, 260.0)]
                .map(|(x, y)| Point { x, y }),
        );
        assert!(refine_capture(&source, quad, false)?.is_some());
        Ok(())
    }

    #[test]
    fn nearby_page_edges_support_a_modestly_displaced_mask() -> OpResult<()> {
        let mut source = ImageU8::new(400, 300, 3, vec![160; 400 * 300 * 3])?;
        for y in 40..260 {
            for x in 60..340 {
                source.data[(y * 400 + x) * 3..(y * 400 + x + 1) * 3].fill(220);
            }
        }
        for offset in [-5.0, 5.0] {
            let quad = quad_from_points([
                Point {
                    x: 60.0 + offset,
                    y: 40.0 + offset,
                },
                Point {
                    x: 340.0 - offset,
                    y: 40.0 + offset,
                },
                Point {
                    x: 340.0 - offset,
                    y: 260.0 - offset,
                },
                Point {
                    x: 60.0 + offset,
                    y: 260.0 - offset,
                },
            ]);
            assert!(
                refine_capture(&source, quad, false)?.is_some(),
                "offset {offset}"
            );
        }
        Ok(())
    }

    #[test]
    fn visible_but_non_straight_edges_keep_the_detected_page() -> OpResult<()> {
        let mut source = ImageU8::new(400, 300, 3, vec![190; 400 * 300 * 3])?;
        for y in 0..300 {
            for x in 0..400 {
                let horizontal = (x as f64 / 12.0).sin() * 3.5;
                let vertical = (y as f64 / 12.0).sin() * 3.5;
                if x as f64 >= 60.0 + vertical
                    && (x as f64) < 340.0 + vertical
                    && y as f64 >= 40.0 + horizontal
                    && (y as f64) < 260.0 + horizontal
                {
                    source.data[(y * 400 + x) * 3..(y * 400 + x + 1) * 3].fill(210);
                }
            }
        }
        let quad = quad_from_points(
            [(60.0, 40.0), (340.0, 40.0), (340.0, 260.0), (60.0, 260.0)]
                .map(|(x, y)| Point { x, y }),
        );
        assert_eq!(refine_capture(&source, quad, false)?, Some(quad));
        Ok(())
    }

    #[test]
    fn isolated_strong_edge_segments_do_not_support_an_interior_crop() -> OpResult<()> {
        let mut source = ImageU8::new(400, 300, 3, vec![235; 400 * 300 * 3])?;
        for (x0, y0, x1, y1) in [
            (130, 40, 240, 50),
            (330, 110, 340, 190),
            (130, 250, 240, 260),
            (60, 110, 70, 190),
        ] {
            for y in y0..y1 {
                for x in x0..x1 {
                    source.data[(y * 400 + x) * 3..(y * 400 + x + 1) * 3].fill(35);
                }
            }
        }
        let quad = quad_from_points(
            [(60.0, 40.0), (340.0, 40.0), (340.0, 260.0), (60.0, 260.0)]
                .map(|(x, y)| Point { x, y }),
        );
        assert!(refine_capture(&source, quad, false)?.is_none());
        Ok(())
    }

    #[test]
    fn unsupported_interior_text_regions_fall_back_to_the_whole_image() -> OpResult<()> {
        let mut source = ImageU8::new(400, 300, 3, vec![235; 400 * 300 * 3])?;
        for y in (35..270).step_by(15) {
            for x in 40..360 {
                source.data[(y * 400 + x) * 3..(y * 400 + x + 1) * 3].fill(35);
            }
        }
        let quad = quad_from_points(
            [(70.0, 50.0), (315.0, 65.0), (295.0, 250.0), (60.0, 240.0)]
                .map(|(x, y)| Point { x, y }),
        );
        assert!(refine_capture(&source, quad, false)?.is_none());
        Ok(())
    }

    #[test]
    fn low_contrast_pages_and_actual_image_borders_remain_supported() -> OpResult<()> {
        let mut source = ImageU8::new(400, 300, 3, vec![200; 400 * 300 * 3])?;
        for y in 40..260 {
            for x in 60..340 {
                source.data[(y * 400 + x) * 3..(y * 400 + x + 1) * 3].fill(208);
            }
        }
        let quad = quad_from_points(
            [(60.0, 40.0), (340.0, 40.0), (340.0, 260.0), (60.0, 260.0)]
                .map(|(x, y)| Point { x, y }),
        );
        assert!(refine_capture(&source, quad, false)?.is_some());
        let extent = SourceExtent::new(400, 300)?;
        assert!(refine_capture(&source, extent.full_frame(), false)?.is_some());
        Ok(())
    }
}
