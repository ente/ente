//! The 75/200 thresholds used downstream are calibrated against this exact
//! gradient scaling: integer `|dx| + |dy|` of a 3x3 Sobel with replicated
//! borders, thresholds floored, the low one compared strictly.

use crate::cv::OpResult;
use crate::cv::image::ImageU8;

const CANNY_SHIFT: i32 = 15;
/// `(int)(tan(22.5 deg) * (1 << CANNY_SHIFT) + 0.5)`.
const TG22: i32 = 13573;

const MAYBE: u8 = 0;
const NO: u8 = 1;
const EDGE: u8 = 2;

fn sobel_planes(src: &[u8], w: usize, h: usize, cn: usize, c: usize) -> (Vec<i16>, Vec<i16>) {
    let mut h_diff = vec![0i16; w * h];
    let mut h_smooth = vec![0i16; w * h];
    for y in 0..h {
        let row = &src[y * w * cn..(y + 1) * w * cn];
        let at = |x: usize| row[x * cn + c] as i16;
        let (d, s) = (
            &mut h_diff[y * w..(y + 1) * w],
            &mut h_smooth[y * w..(y + 1) * w],
        );
        for x in 0..w {
            let left = at(x.saturating_sub(1));
            let right = at((x + 1).min(w - 1));
            d[x] = right - left;
            s[x] = left + 2 * at(x) + right;
        }
    }

    let mut dx = vec![0i16; w * h];
    let mut dy = vec![0i16; w * h];
    for y in 0..h {
        let up = y.saturating_sub(1) * w;
        let down = (y + 1).min(h - 1) * w;
        let here = y * w;
        for x in 0..w {
            dx[here + x] = h_diff[up + x] + 2 * h_diff[here + x] + h_diff[down + x];
            dy[here + x] = h_smooth[down + x] - h_smooth[up + x];
        }
    }
    (dx, dy)
}

fn floor_threshold(t: f64) -> i32 {
    t.floor().clamp(i32::MIN as f64, i32::MAX as f64) as i32
}

pub(crate) fn canny(src: &ImageU8, threshold1: f64, threshold2: f64) -> OpResult<ImageU8> {
    let (w, h) = (src.width as usize, src.height as usize);
    let cn = src.channels as usize;

    let (low_thresh, high_thresh) = if threshold1 > threshold2 {
        (threshold2, threshold1)
    } else {
        (threshold1, threshold2)
    };
    let low = floor_threshold(low_thresh);
    let high = floor_threshold(high_thresh);

    let (mut dx, mut dy) = sobel_planes(&src.data, w, h, cn, 0);
    let mut norm: Vec<i32> = dx
        .iter()
        .zip(dy.iter())
        .map(|(&x, &y)| (x as i32).abs() + (y as i32).abs())
        .collect();
    for c in 1..cn {
        let (cdx, cdy) = sobel_planes(&src.data, w, h, cn, c);
        for i in 0..w * h {
            let m = (cdx[i] as i32).abs() + (cdy[i] as i32).abs();
            if m > norm[i] {
                norm[i] = m;
                dx[i] = cdx[i];
                dy[i] = cdy[i];
            }
        }
    }

    let step = w + 2;
    let mut mag = vec![0i32; step * (h + 2)];
    for y in 0..h {
        mag[(y + 1) * step + 1..(y + 1) * step + 1 + w].copy_from_slice(&norm[y * w..(y + 1) * w]);
    }
    let mut map = vec![NO; step * (h + 2)];
    let mut stack: Vec<usize> = Vec::new();

    for y in 0..h {
        for x in 0..w {
            let p = (y + 1) * step + x + 1;
            let m = mag[p];
            if m > low {
                let (xs, ys) = (dx[y * w + x] as i32, dy[y * w + x] as i32);
                let ax = xs.abs();
                let ay = ys.abs() << CANNY_SHIFT;
                let tg22x = ax * TG22;
                let keep = if ay < tg22x {
                    m > mag[p - 1] && m >= mag[p + 1]
                } else if ay > tg22x + (ax << (CANNY_SHIFT + 1)) {
                    m > mag[p - step] && m >= mag[p + step]
                } else {
                    let s: isize = if (xs ^ ys) < 0 { -1 } else { 1 };
                    let up = (p as isize - step as isize - s) as usize;
                    let down = (p as isize + step as isize + s) as usize;
                    m > mag[up] && m > mag[down]
                };
                if keep {
                    if m > high {
                        map[p] = EDGE;
                        stack.push(p);
                    } else {
                        map[p] = MAYBE;
                    }
                    continue;
                }
            }
            map[p] = NO;
        }
    }

    let offsets = [
        -(step as isize) - 1,
        -(step as isize),
        -(step as isize) + 1,
        -1,
        1,
        step as isize - 1,
        step as isize,
        step as isize + 1,
    ];
    while let Some(p) = stack.pop() {
        for offset in offsets {
            let q = (p as isize + offset) as usize;
            if map[q] == MAYBE {
                map[q] = EDGE;
                stack.push(q);
            }
        }
    }

    let mut out = vec![0u8; w * h];
    for y in 0..h {
        let row = &map[(y + 1) * step + 1..(y + 1) * step + 1 + w];
        for (o, &v) in out[y * w..(y + 1) * w].iter_mut().zip(row.iter()) {
            *o = if v == EDGE { 255 } else { 0 };
        }
    }
    ImageU8::new(src.width, src.height, 1, out)
}
