//! `cv::findContours(RETR_LIST, CHAIN_APPROX_NONE)` on an 8-bit image, with
//! the `cv::contourArea` carried alongside each contour.
//!
//! This is the Suzuki-Abe border following OpenCV performs, reproduced rather
//! than reinvented because the downstream quad fit consumes the point
//! sequence: which pixel a border starts from, which way it is walked and
//! where it stops all change the point subsets lines are fitted to.
//!
//! The pieces that are semantics, not detail:
//!
//! * the image is padded by one zero pixel on every side and binarised to
//!   0/1, and every emitted point is shifted back by (-1, -1);
//! * the raster scan starts an OUTER border at the first `prev == 0, p == 1`
//!   transition and a HOLE border at `p == 0, prev >= 1` (the marked value
//!   `0x82` is negative as a signed byte, which is what stops a hole from
//!   being found twice) — hence the signed cell type;
//! * the neighbour walk uses the chain-code order below, starts at direction
//!   4 for an outer border and 0 for a hole, and searches from `s+1` upward
//!   with the `s < 15` clamp;
//! * a visited pixel is marked `2`, and `0x82` when the walk leaves it to the
//!   "right", which keeps the scan from re-entering a finished border;
//! * `CHAIN_APPROX_NONE` emits a point at every step, starting at the origin.

use crate::ml::document_scan::OpResult;
use crate::ml::document_scan::image::{Contour, ImageU8};

const DELTAS: [(i32, i32); 8] = [
    (1, 0),
    (1, -1),
    (0, -1),
    (-1, -1),
    (-1, 0),
    (-1, 1),
    (0, 1),
    (1, 1),
];

/// An unvisited foreground pixel.
const BLACK: i8 = 1;
/// Visited.
const NEW: i8 = 2;
/// Visited, and the border left it to the right.
const RIGHT: i8 = 0x82u8 as i8;
/// Everything except the black bit.
const FLAGS: i32 = -2;

fn delta(s: i32, step: usize) -> isize {
    let (dx, dy) = DELTAS[(s & 7) as usize];
    dx as isize + dy as isize * step as isize
}

fn fetch_contour(
    img: &mut [i8],
    step: usize,
    start: usize,
    origin: (i32, i32),
    is_hole: bool,
) -> Vec<(i32, i32)> {
    let mut points = Vec::new();
    let i0 = start;
    let mut pt = origin;

    let mut s_end: i32 = if is_hole { 0 } else { 4 };
    let mut s = s_end;
    let mut i1;
    loop {
        s = (s - 1) & 7;
        i1 = (i0 as isize + delta(s, step)) as usize;
        if img[i1] != 0 || s == s_end {
            break;
        }
    }

    if s == s_end {
        // Single-pixel border.
        img[i0] = RIGHT;
        points.push(pt);
        return points;
    }

    let mut i3 = i0;
    loop {
        s_end = s;
        s = s.min(15);
        let mut i4 = i3;
        while s < 15 {
            s += 1;
            i4 = (i3 as isize + delta(s, step)) as usize;
            if img[i4] != 0 {
                break;
            }
        }
        s &= 7;

        if ((s - 1) as u32) < (s_end as u32) {
            img[i3] = RIGHT;
        } else if img[i3] == BLACK {
            img[i3] = NEW;
        }

        points.push(pt);
        let (dx, dy) = DELTAS[s as usize];
        pt = (pt.0 + dx, pt.1 + dy);

        if i4 == i0 && i3 == i1 {
            break;
        }
        i3 = i4;
        s = (s + 4) & 7;
    }
    points
}

/// `cv::contourArea(contour, false)`: the shoelace sum in `f64` over `f32`
/// coordinates, halved and made positive.
fn contour_area(points: &[(i32, i32)]) -> f64 {
    if points.is_empty() {
        return 0.0;
    }
    let mut a00 = 0.0f64;
    let mut prev = points[points.len() - 1];
    for &p in points {
        a00 += prev.0 as f64 * p.1 as f64 - prev.1 as f64 * p.0 as f64;
        prev = p;
    }
    (a00 * 0.5).abs()
}

/// One scanner step: scans on from `pt` and appends the next border, or
/// reports that the image is exhausted.
fn find_next(
    img: &mut [i8],
    step: usize,
    height: usize,
    pt: &mut (usize, usize),
    lnbd: &mut (usize, usize),
    out: &mut Vec<Contour>,
) -> bool {
    let width = step - 1;
    let (mut x, mut y) = *pt;
    let mut last_pos = *lnbd;
    let mut prev = img[y * step + x - 1];

    while y < height {
        while x < width {
            let mut p = prev;
            while x < width {
                p = img[y * step + x];
                if p != prev {
                    break;
                }
                x += 1;
            }
            if x >= width {
                break;
            }

            // RETR_LIST branch: no parent search, the border marker never
            // changes.
            let mut is_hole = false;
            let mut start = true;
            if !(prev == 0 && p == BLACK) {
                if p != 0 || prev < 1 {
                    start = false;
                } else {
                    if (prev as i32) & FLAGS != 0 {
                        last_pos.0 = x - 1;
                    }
                    is_hole = true;
                }
            }

            if start {
                last_pos.0 = x - usize::from(is_hole);
                let start_idx = y * step + x - usize::from(is_hole);
                let origin = ((x - usize::from(is_hole)) as i32 - 1, y as i32 - 1);
                let points = fetch_contour(img, step, start_idx, origin, is_hole);
                let area = contour_area(&points);
                out.push(Contour { points, area });
                *pt = (x + 1, y);
                *lnbd = last_pos;
                return true;
            }

            prev = p;
            if (prev as i32) & FLAGS != 0 {
                last_pos.0 = x;
            }
            x += 1;
        }
        last_pos = (0, y + 1);
        x = 1;
        prev = 0;
        y += 1;
    }
    false
}

pub(crate) fn find_contours(src: &ImageU8) -> OpResult<Vec<Contour>> {
    if src.channels != 1 {
        return Err(format!(
            "find_contours: expected a single-channel image, got {}",
            src.channels
        ));
    }
    let (w, h) = (src.width as usize, src.height as usize);
    let step = w + 2;
    let mut img = vec![0i8; step * (h + 2)];
    for y in 0..h {
        let src_row = &src.data[y * w..(y + 1) * w];
        let dst_row = &mut img[(y + 1) * step + 1..(y + 1) * step + 1 + w];
        for (d, &s) in dst_row.iter_mut().zip(src_row.iter()) {
            *d = i8::from(s != 0);
        }
    }

    let mut out = Vec::new();
    let mut pt = (1usize, 1usize);
    let mut lnbd = (0usize, 1usize);
    while find_next(&mut img, step, h + 1, &mut pt, &mut lnbd, &mut out) {}
    // OpenCV's RETR_LIST tree walk reports borders in reverse discovery order.
    out.reverse();
    Ok(out)
}
