//! `cv::morphologyEx(MORPH_ERODE | MORPH_OPEN | MORPH_CLOSE)`.
//!
//! OpenCV resolves the default border value per sub-operation: erode pads with
//! 255 and dilate with 0, so neither operation eats into the image from the
//! frame; both pads are the identity of their own reduction. Only non-zero
//! structuring-element entries take part, the anchor is the element centre,
//! and open/close are the two orderings of the erode/dilate pair.
//!
//! Shape of the computation: element rows are contiguous runs, and an ellipse
//! repeats most of its run extents, so each distinct extent is reduced once
//! per source row into a small ring of reduced rows, and an output row is the
//! reduction of at most `kernel.height` of those.

use rayon::prelude::*;

use crate::ml::document_scan::OpResult;
use crate::ml::document_scan::image::ImageU8;

/// Below this many pixels the rayon split costs more than the work it saves.
const PARALLEL_MIN_PIXELS: usize = 200_000;

/// One structuring-element row: `[x0, x1)` relative to the anchor.
struct Run {
    dy: i64,
    x0: i64,
    x1: i64,
}

fn runs(kernel: &ImageU8) -> OpResult<Vec<Run>> {
    if kernel.channels != 1 {
        return Err("morphology: the structuring element must be single channel".to_string());
    }
    let (kw, kh) = (kernel.width as i64, kernel.height as i64);
    let (ax, ay) = (kw / 2, kh / 2);
    let mut out = Vec::new();
    for i in 0..kh {
        let row = &kernel.data[(i * kw) as usize..((i + 1) * kw) as usize];
        let mut j = 0i64;
        while j < kw {
            if row[j as usize] == 0 {
                j += 1;
                continue;
            }
            let start = j;
            while j < kw && row[j as usize] != 0 {
                j += 1;
            }
            out.push(Run {
                dy: i - ay,
                x0: start - ax,
                x1: j - ax,
            });
        }
    }
    Ok(out)
}

fn fold_min(out: &mut [u8], src: &[u8]) {
    for (o, &v) in out.iter_mut().zip(src.iter()) {
        *o = (*o).min(v);
    }
}

fn fold_max(out: &mut [u8], src: &[u8]) {
    for (o, &v) in out.iter_mut().zip(src.iter()) {
        *o = (*o).max(v);
    }
}

fn fold(out: &mut [u8], src: &[u8], erode: bool) {
    if erode {
        fold_min(out, src);
    } else {
        fold_max(out, src);
    }
}

/// Reduction of one source row over the window `[x + x0, x + x1)`, with `pad`
/// outside the row. `ext` is scratch holding the row shifted to `x0` and
/// padded on both sides, so the fold below reads contiguous slices.
#[allow(clippy::too_many_arguments)]
fn reduce_row(
    src_row: &[u8],
    w: usize,
    cn: usize,
    c: usize,
    x0: i64,
    x1: i64,
    pad: u8,
    erode: bool,
    ext: &mut Vec<u8>,
    out: &mut [u8],
) {
    let len = (x1 - x0) as usize;
    ext.clear();
    ext.resize(w + len - 1, pad);
    let lo = (-x0).max(0).min(ext.len() as i64) as usize;
    let hi = (w as i64 - x0).clamp(lo as i64, ext.len() as i64) as usize;
    if lo < hi {
        let first = (lo as i64 + x0) as usize;
        if cn == 1 {
            ext[lo..hi].copy_from_slice(&src_row[first..first + (hi - lo)]);
        } else {
            for (i, slot) in ext[lo..hi].iter_mut().enumerate() {
                *slot = src_row[(first + i) * cn + c];
            }
        }
    }
    out.copy_from_slice(&ext[..w]);
    for j in 1..len {
        fold(out, &ext[j..j + w], erode);
    }
}

/// Reduced-row cache for one band of output rows.
struct Bands<'a> {
    src: &'a [u8],
    w: usize,
    h: i64,
    cn: usize,
    widths: &'a [(i64, i64)],
    taps: &'a [(i64, usize)],
    pad: u8,
    erode: bool,
    ring_rows: usize,
}

impl Bands<'_> {
    /// Writes output rows `y0..y1` of channel `c` into `band` (which starts at
    /// output row `y0`).
    fn run(&self, c: usize, y0: i64, y1: i64, band: &mut [u8]) {
        let w = self.w;
        let row_len = w * self.cn;
        let mut ring: Vec<u8> = vec![0u8; self.ring_rows * self.widths.len() * w];
        let mut cached: Vec<i64> = vec![-1; self.ring_rows];
        let mut ext: Vec<u8> = Vec::new();
        let mut acc: Vec<u8> = vec![0u8; w];
        let mut selected: Vec<(usize, usize)> = Vec::with_capacity(self.taps.len());

        for dst_y in y0..y1 {
            selected.clear();
            for &(dy, slot) in self.taps {
                let sy = dst_y + dy;
                if sy < 0 || sy >= self.h {
                    continue;
                }
                let ring_slot = (sy as usize) % self.ring_rows;
                if cached[ring_slot] != sy {
                    let src_row = &self.src[(sy as usize) * row_len..(sy as usize + 1) * row_len];
                    for (k, &(x0, x1)) in self.widths.iter().enumerate() {
                        let start = (ring_slot * self.widths.len() + k) * w;
                        reduce_row(
                            src_row,
                            w,
                            self.cn,
                            c,
                            x0,
                            x1,
                            self.pad,
                            self.erode,
                            &mut ext,
                            &mut ring[start..start + w],
                        );
                    }
                    cached[ring_slot] = sy;
                }
                selected.push((ring_slot, slot));
            }

            let dst_row = &mut band[((dst_y - y0) as usize) * row_len..][..row_len];
            if selected.is_empty() {
                // Every element row fell outside the image: the whole output
                // row is the border value, which the buffer already holds.
                continue;
            }
            let reduced = |&(ring_slot, slot): &(usize, usize)| {
                let start = (ring_slot * self.widths.len() + slot) * w;
                &ring[start..start + w]
            };
            acc.copy_from_slice(reduced(&selected[0]));
            for pair in &selected[1..] {
                fold(&mut acc, reduced(pair), self.erode);
            }
            if self.cn == 1 {
                dst_row.copy_from_slice(&acc);
            } else {
                for (x, &v) in acc.iter().enumerate() {
                    dst_row[x * self.cn + c] = v;
                }
            }
        }
    }
}

fn morph(src: &ImageU8, kernel: &ImageU8, erode: bool) -> OpResult<ImageU8> {
    if kernel.width * kernel.height == 1 {
        return Ok(src.clone());
    }
    let element = runs(kernel)?;
    let (w, h) = (src.width as usize, src.height as usize);
    let cn = src.channels as usize;
    let pad: u8 = if erode { 255 } else { 0 };
    let row_len = w * cn;

    if element.is_empty() {
        return ImageU8::new(src.width, src.height, src.channels, vec![pad; row_len * h]);
    }

    // Distinct run extents, and the (dy, extent) pair each element row uses.
    let mut widths: Vec<(i64, i64)> = element.iter().map(|r| (r.x0, r.x1)).collect();
    widths.sort_unstable();
    widths.dedup();
    let taps: Vec<(i64, usize)> = element
        .iter()
        .map(|r| {
            (
                r.dy,
                widths.binary_search(&(r.x0, r.x1)).expect("cached run"),
            )
        })
        .collect();

    let bands = Bands {
        src: &src.data,
        w,
        h: h as i64,
        cn,
        widths: &widths,
        taps: &taps,
        pad,
        erode,
        ring_rows: kernel.height as usize,
    };

    let mut out = vec![pad; row_len * h];
    let parallel = w * h >= PARALLEL_MIN_PIXELS;
    for c in 0..cn {
        if parallel {
            // Each band keeps its own ring, so it re-reduces the `kh - 1`
            // source rows its neighbours also touch; the result is per-row
            // identical.
            let band_rows = (h / rayon::current_num_threads().max(1)).max(kernel.height as usize);
            out.par_chunks_mut(band_rows * row_len)
                .enumerate()
                .for_each(|(b, band)| {
                    let y0 = (b * band_rows) as i64;
                    let y1 = (y0 + (band.len() / row_len) as i64).min(h as i64);
                    bands.run(c, y0, y1, band);
                });
        } else {
            bands.run(c, 0, h as i64, &mut out);
        }
    }

    ImageU8::new(src.width, src.height, src.channels, out)
}

pub(crate) fn morphology_erode(src: &ImageU8, kernel: &ImageU8) -> OpResult<ImageU8> {
    morph(src, kernel, true)
}

pub(crate) fn morphology_dilate(src: &ImageU8, kernel: &ImageU8) -> OpResult<ImageU8> {
    morph(src, kernel, false)
}

pub(crate) fn morphology_open(src: &ImageU8, kernel: &ImageU8) -> OpResult<ImageU8> {
    morphology_dilate(&morphology_erode(src, kernel)?, kernel)
}

pub(crate) fn morphology_close(src: &ImageU8, kernel: &ImageU8) -> OpResult<ImageU8> {
    morphology_erode(&morphology_dilate(src, kernel)?, kernel)
}
