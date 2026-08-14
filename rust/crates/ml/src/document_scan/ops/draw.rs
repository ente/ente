//! Polygon rasterisation, reproducing OpenCV's `drawing.cpp`.
//!
//! Both entry points first stroke the polygon outline with the 8-connected
//! Bresenham line walker and then fill it, exactly as `fillConvexPoly` and
//! `fillPoly` do; the boundary pixels of the result come from the stroke, not
//! from the scanline pass, so the stroke cannot be skipped. All coordinates
//! are `XY_SHIFT` fixed-point (`shift = 0` at every call site here).
//!
//! `fill_poly` implements OpenCV's <= 4.10 LINE_8 scanline rule (half-pixel
//! edge bias in `CollectPolyEdges`, `delta = 0` in `FillEdgeCollection`);
//! OpenCV changed the rule in 4.11. The <= 4.10 rule is what the pipeline was
//! validated against and is pinned by the golden-mask tests.

use super::saturate_u8_f64;
use crate::document_scan::OpResult;
use crate::document_scan::image::ImageU8;

const XY_SHIFT: i32 = 16;
const XY_ONE: i64 = 1 << XY_SHIFT;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct P64 {
    x: i64,
    y: i64,
}

struct Canvas {
    width: i32,
    height: i32,
    data: Vec<u8>,
}

impl Canvas {
    fn new(width: i32, height: i32) -> OpResult<Self> {
        let image = ImageU8::zeros(width, height, 1)?;
        Ok(Self {
            width,
            height,
            data: image.data,
        })
    }

    fn set(&mut self, x: i32, y: i32, color: u8) {
        if x >= 0 && y >= 0 && x < self.width && y < self.height {
            self.data[y as usize * self.width as usize + x as usize] = color;
        }
    }

    /// Horizontal line, inclusive on both ends.
    fn hline(&mut self, y: i32, x1: i32, x2: i32, color: u8) {
        if y < 0 || y >= self.height || x1 > x2 {
            return;
        }
        let row = y as usize * self.width as usize;
        self.data[row + x1 as usize..row + x2 as usize + 1].fill(color);
    }

    fn into_image(self) -> OpResult<ImageU8> {
        ImageU8::new(self.width, self.height, 1, self.data)
    }
}

/// `cv::clipLine(Size2l, Point2l&, Point2l&)`.
fn clip_line(width: i64, height: i64, p1: &mut P64, p2: &mut P64) -> bool {
    if width <= 0 || height <= 0 {
        return false;
    }
    let right = width - 1;
    let bottom = height - 1;
    let (mut x1, mut y1, mut x2, mut y2) = (p1.x, p1.y, p2.x, p2.y);

    let code = |x: i64, y: i64| -> i32 {
        i32::from(x < 0)
            + i32::from(x > right) * 2
            + i32::from(y < 0) * 4
            + i32::from(y > bottom) * 8
    };
    let mut c1 = code(x1, y1);
    let mut c2 = code(x2, y2);

    if (c1 & c2) == 0 && (c1 | c2) != 0 {
        if c1 & 12 != 0 {
            let a = if c1 < 8 { 0 } else { bottom };
            x1 += ((a - y1) as f64 * (x2 - x1) as f64 / (y2 - y1) as f64) as i64;
            y1 = a;
            c1 = i32::from(x1 < 0) + i32::from(x1 > right) * 2;
        }
        if c2 & 12 != 0 {
            let a = if c2 < 8 { 0 } else { bottom };
            x2 += ((a - y2) as f64 * (x2 - x1) as f64 / (y2 - y1) as f64) as i64;
            y2 = a;
            c2 = i32::from(x2 < 0) + i32::from(x2 > right) * 2;
        }
        if (c1 & c2) == 0 && (c1 | c2) != 0 {
            if c1 != 0 {
                let a = if c1 == 1 { 0 } else { right };
                y1 += ((a - x1) as f64 * (y2 - y1) as f64 / (x2 - x1) as f64) as i64;
                x1 = a;
                c1 = 0;
            }
            if c2 != 0 {
                let a = if c2 == 1 { 0 } else { right };
                y2 += ((a - x2) as f64 * (y2 - y1) as f64 / (x2 - x1) as f64) as i64;
                x2 = a;
                c2 = 0;
            }
        }
    }

    *p1 = P64 { x: x1, y: y1 };
    *p2 = P64 { x: x2, y: y2 };
    (c1 | c2) == 0
}

/// `LineIterator` with connectivity 8 and `leftToRight = true`.
fn draw_line(canvas: &mut Canvas, from: (i32, i32), to: (i32, i32), color: u8) {
    let (w, h) = (canvas.width, canvas.height);
    let mut pt1 = from;
    let mut pt2 = to;

    let outside = |p: (i32, i32)| (p.0 as u32) >= (w as u32) || (p.1 as u32) >= (h as u32);
    if outside(pt1) || outside(pt2) {
        let mut a = P64 {
            x: pt1.0 as i64,
            y: pt1.1 as i64,
        };
        let mut b = P64 {
            x: pt2.0 as i64,
            y: pt2.1 as i64,
        };
        if !clip_line(w as i64, h as i64, &mut a, &mut b) {
            return;
        }
        pt1 = (a.x as i32, a.y as i32);
        pt2 = (b.x as i32, b.y as i32);
    }

    let mut delta_x = 1i32;
    let mut delta_y = 1i32;
    let mut dx = pt2.0 - pt1.0;
    let mut dy = pt2.1 - pt1.1;

    if dx < 0 {
        dx = -dx;
        dy = -dy;
        pt1 = pt2;
    }
    if dy < 0 {
        dy = -dy;
        delta_y = -1;
    }
    let vert = dy > dx;
    if vert {
        std::mem::swap(&mut dx, &mut dy);
        std::mem::swap(&mut delta_x, &mut delta_y);
    }

    let mut err = dx - (dy + dy);
    let plus_delta = dx + dx;
    let minus_delta = -(dy + dy);
    let mut minus_shift = delta_x;
    let mut plus_shift = 0i32;
    let mut minus_step = 0i32;
    let mut plus_step = delta_y;
    let count = dx + 1;
    if vert {
        std::mem::swap(&mut plus_step, &mut plus_shift);
        std::mem::swap(&mut minus_step, &mut minus_shift);
    }

    let mut p = pt1;
    for _ in 0..count {
        canvas.set(p.0, p.1, color);
        let mask = if err < 0 { -1i32 } else { 0 };
        err += minus_delta + (plus_delta & mask);
        p.0 += minus_shift + (plus_shift & mask);
        p.1 += minus_step + (plus_step & mask);
    }
}

struct ConvexEdge {
    idx: i32,
    di: i32,
    x: i64,
    dx: i64,
    ye: i32,
}

/// `FillConvexPoly(img, v, npts, color, LINE_8, shift = 0)`.
fn fill_convex_poly_impl(canvas: &mut Canvas, v: &[(i32, i32)], color: u8) {
    let npts = v.len() as i32;
    let vx = |i: i32| v[i as usize].0 as i64;
    let vy = |i: i32| v[i as usize].1 as i64;
    let delta1 = XY_ONE >> 1;
    let delta2 = XY_ONE >> 1;

    let mut imin = 0i32;
    let mut edges = npts;
    let mut p0 = P64 {
        x: vx(npts - 1) << XY_SHIFT,
        y: vy(npts - 1) << XY_SHIFT,
    };
    let (mut xmin, mut xmax) = (vx(0), vx(0));
    let (mut ymin, mut ymax) = (vy(0), vy(0));

    for i in 0..npts {
        let (px, py) = (vx(i), vy(i));
        if py < ymin {
            ymin = py;
            imin = i;
        }
        ymax = ymax.max(py);
        xmax = xmax.max(px);
        xmin = xmin.min(px);

        let p = P64 {
            x: px << XY_SHIFT,
            y: py << XY_SHIFT,
        };
        draw_line(
            canvas,
            ((p0.x >> XY_SHIFT) as i32, (p0.y >> XY_SHIFT) as i32),
            ((p.x >> XY_SHIFT) as i32, (p.y >> XY_SHIFT) as i32),
            color,
        );
        p0 = p;
    }

    if npts < 3
        || xmax < 0
        || ymax < 0
        || xmin >= canvas.width as i64
        || ymin >= canvas.height as i64
    {
        return;
    }
    ymax = ymax.min(canvas.height as i64 - 1);

    let mut y = ymin as i32;
    let mut edge = [
        ConvexEdge {
            idx: imin,
            di: 1,
            x: -XY_ONE,
            dx: 0,
            ye: y,
        },
        ConvexEdge {
            idx: imin,
            di: npts - 1,
            x: -XY_ONE,
            dx: 0,
            ye: y,
        },
    ];

    loop {
        for e in edge.iter_mut() {
            if y < e.ye {
                continue;
            }
            let di = e.di;
            let mut idx0 = e.idx;
            let mut idx = idx0 + di;
            if idx >= npts {
                idx -= npts;
            }
            loop {
                let more = edges > 0;
                edges -= 1;
                if !more {
                    break;
                }
                let ty = vy(idx) as i32;
                if ty > y {
                    let xs = vx(idx0) << XY_SHIFT;
                    let xe = vx(idx) << XY_SHIFT;
                    e.ye = ty;
                    e.dx = ((xe - xs) * 2 + (ty as i64 - y as i64)) / (2 * (ty as i64 - y as i64));
                    e.x = xs;
                    e.idx = idx;
                    break;
                }
                idx0 = idx;
                idx += di;
                if idx >= npts {
                    idx -= npts;
                }
            }
        }

        if edges < 0 {
            break;
        }

        if y >= 0 {
            let (left, right) = if edge[0].x > edge[1].x {
                (1, 0)
            } else {
                (0, 1)
            };
            let mut xx1 = (edge[left].x + delta1) >> XY_SHIFT;
            let mut xx2 = (edge[right].x + delta2) >> XY_SHIFT;
            if xx2 >= 0 && xx1 < canvas.width as i64 {
                xx1 = xx1.max(0);
                xx2 = xx2.min(canvas.width as i64 - 1);
                canvas.hline(y, xx1 as i32, xx2 as i32, color);
            }
        }

        edge[0].x += edge[0].dx;
        edge[1].x += edge[1].dx;
        y += 1;
        if y as i64 > ymax {
            break;
        }
    }
}

#[derive(Clone, Copy)]
struct PolyEdge {
    y0: i32,
    y1: i32,
    x: i64,
    dx: i64,
    next: Option<usize>,
}

/// `CollectPolyEdges(img, v, count, edges, color, LINE_8, shift = 0)`.
fn collect_poly_edges(canvas: &mut Canvas, v: &[(i32, i32)], edges: &mut Vec<PolyEdge>, color: u8) {
    let count = v.len();
    let mut pt0 = P64 {
        x: (v[count - 1].0 as i64) << XY_SHIFT,
        y: v[count - 1].1 as i64,
    };

    for vertex in v.iter() {
        let pt1 = P64 {
            x: (vertex.0 as i64) << XY_SHIFT,
            y: vertex.1 as i64,
        };
        let mut pt0c = pt0;
        let mut pt1c = pt1;

        let mut t0 = P64 {
            x: (pt0.x + (XY_ONE >> 1)) >> XY_SHIFT,
            y: pt0.y,
        };
        let mut t1 = P64 {
            x: (pt1.x + (XY_ONE >> 1)) >> XY_SHIFT,
            y: pt1.y,
        };
        draw_line(
            canvas,
            (t0.x as i32, t0.y as i32),
            (t1.x as i32, t1.y as i32),
            color,
        );

        let (w, h) = (canvas.width as i64, canvas.height as i64);
        let outside = |p: P64| p.x < 0 || p.x >= w || p.y < 0 || p.y >= h;
        if outside(t0) || outside(t1) {
            clip_line(w, h, &mut t0, &mut t1);
            // Clipped endpoints give a more accurate edge.
            if t0.y != t1.y {
                pt0c.y = t0.y;
                pt1c.y = t1.y;
                pt0c.x = t0.x << XY_SHIFT;
                pt1c.x = t1.x << XY_SHIFT;
            }
        } else {
            pt0c.x += XY_ONE >> 1;
            pt1c.x += XY_ONE >> 1;
        }

        if pt0.y != pt1.y {
            let dx = (pt1c.x - pt0c.x) / (pt1c.y - pt0c.y);
            let edge = if pt0.y < pt1.y {
                PolyEdge {
                    y0: pt0.y as i32,
                    y1: pt1.y as i32,
                    x: pt0c.x + (pt0.y - pt0c.y) * dx,
                    dx,
                    next: None,
                }
            } else {
                PolyEdge {
                    y0: pt1.y as i32,
                    y1: pt0.y as i32,
                    x: pt1c.x + (pt1.y - pt1c.y) * dx,
                    dx,
                    next: None,
                }
            };
            edges.push(edge);
        }
        pt0 = pt1;
    }
}

/// `FillEdgeCollection`. `nodes[0]` stands in for the stack-allocated list
/// head, so a `next` of `Some(0)` never occurs and `None` is the null link.
fn fill_edge_collection(canvas: &mut Canvas, mut collected: Vec<PolyEdge>, color: u8) {
    let total = collected.len();
    if total < 2 {
        return;
    }

    let mut y_max = i32::MIN;
    let mut y_min = i32::MAX;
    let mut x_max = -1i64;
    let mut x_min = i64::MAX;
    for e in &collected {
        let x1 = e.x + (e.y1 - e.y0) as i64 * e.dx;
        y_min = y_min.min(e.y0);
        y_max = y_max.max(e.y1);
        x_min = x_min.min(e.x).min(x1);
        x_max = x_max.max(e.x).max(x1);
    }
    if y_max < 0
        || y_min >= canvas.height
        || x_max < 0
        || x_min >= (canvas.width as i64) << XY_SHIFT
    {
        return;
    }

    collected.sort_by(|a, b| (a.y0, a.x, a.dx).cmp(&(b.y0, b.x, b.dx)));

    // Index 0 is the list head; the trailing sentinel keeps `e` in range.
    let mut nodes: Vec<PolyEdge> = Vec::with_capacity(total + 2);
    nodes.push(PolyEdge {
        y0: i32::MAX,
        y1: 0,
        x: 0,
        dx: 0,
        next: None,
    });
    nodes.extend(collected);
    nodes.push(PolyEdge {
        y0: i32::MAX,
        y1: 0,
        x: 0,
        dx: 0,
        next: None,
    });

    // Non-antialiased branch; this rasterizer only ever draws LINE_8.
    let delta = 0i64;
    let mut i = 0usize;
    let mut e = 1usize;
    y_max = y_max.min(canvas.height);

    let mut y = nodes[e].y0;
    while y < y_max {
        let mut draw = false;
        let clipline = y < 0;
        let mut prelast = 0usize;
        let mut last = nodes[0].next;

        while last.is_some() || nodes[e].y0 == y {
            if let Some(l) = last
                && nodes[l].y1 == y
            {
                // The edge ends here: unlink it.
                nodes[prelast].next = nodes[l].next;
                last = nodes[l].next;
                continue;
            }
            let keep_prelast = prelast;
            if last.is_some_and(|l| nodes[e].y0 > y || nodes[l].x < nodes[e].x) {
                prelast = last.expect("checked above");
                last = nodes[prelast].next;
            } else if i < total {
                nodes[prelast].next = Some(e);
                nodes[e].next = last;
                prelast = e;
                i += 1;
                e = i + 1;
            } else {
                break;
            }

            if draw {
                if !clipline {
                    let (a, b) = (nodes[keep_prelast].x, nodes[prelast].x);
                    let (x1, x2) = if a > b {
                        ((b + delta) >> XY_SHIFT, a >> XY_SHIFT)
                    } else {
                        ((a + delta) >> XY_SHIFT, b >> XY_SHIFT)
                    };
                    if x1 < canvas.width as i64 && x2 >= 0 {
                        let x1 = x1.max(0) as i32;
                        let x2 = x2.min(canvas.width as i64 - 1) as i32;
                        canvas.hline(y, x1, x2, color);
                    }
                }
                nodes[keep_prelast].x += nodes[keep_prelast].dx;
                nodes[prelast].x += nodes[prelast].dx;
            }
            draw = !draw;
        }

        // Bubble-sort the active list by x.
        let mut keep_prelast: Option<usize> = None;
        loop {
            let mut prelast = 0usize;
            let mut last = nodes[0].next;
            let mut last_exchange: Option<usize> = None;
            while last != keep_prelast && last.is_some_and(|l| nodes[l].next.is_some()) {
                let l = last.expect("checked above");
                let te = nodes[l].next.expect("checked above");
                if nodes[l].x > nodes[te].x {
                    nodes[prelast].next = Some(te);
                    nodes[l].next = nodes[te].next;
                    nodes[te].next = Some(l);
                    prelast = te;
                    last_exchange = Some(prelast);
                } else {
                    prelast = l;
                    last = Some(te);
                }
            }
            if last_exchange.is_none() {
                break;
            }
            keep_prelast = last_exchange;
            if keep_prelast == nodes[0].next || keep_prelast == Some(0) {
                break;
            }
        }

        y += 1;
    }
}

/// `cv::fillConvexPoly(mask, pts, Scalar(value), LINE_8, 0)` on a zeroed mask.
pub(crate) fn fill_convex_poly(
    width: i32,
    height: i32,
    polygon: &[(i32, i32)],
    value: f64,
) -> OpResult<ImageU8> {
    let mut canvas = Canvas::new(width, height)?;
    if !polygon.is_empty() {
        fill_convex_poly_impl(&mut canvas, polygon, saturate_u8_f64(value));
    }
    canvas.into_image()
}

/// `cv::fillPoly(mask, {pts}, Scalar(value), LINE_8, 0)` on a zeroed mask.
pub(crate) fn fill_poly(
    width: i32,
    height: i32,
    polygon: &[(i32, i32)],
    value: f64,
) -> OpResult<ImageU8> {
    let mut canvas = Canvas::new(width, height)?;
    let color = saturate_u8_f64(value);
    let mut edges: Vec<PolyEdge> = Vec::new();
    if !polygon.is_empty() {
        collect_poly_edges(&mut canvas, polygon, &mut edges, color);
    }
    fill_edge_collection(&mut canvas, edges, color);
    canvas.into_image()
}
