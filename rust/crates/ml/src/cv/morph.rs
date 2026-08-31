use rayon::prelude::*;

use crate::cv::image::ImageU8;
use crate::cv::{OpResult, PARALLEL_MIN_ELEMS};

fn morph(src: &ImageU8, kernel: &ImageU8, erode: bool) -> OpResult<ImageU8> {
    if src.channels != 1 || kernel.channels != 1 {
        return Err("morphology: image and kernel must be single-channel".to_string());
    }
    if kernel.width * kernel.height == 1 {
        return Ok(src.clone());
    }
    let pad: u8 = if erode { 255 } else { 0 };
    let (w, h) = (src.width as usize, src.height as usize);
    let (kw, kh) = (kernel.width as usize, kernel.height as usize);

    let pw = w + kw - 1;
    let mut padded = vec![pad; pw * (h + kh - 1)];
    for y in 0..h {
        padded[(y + kh / 2) * pw + kw / 2..(y + kh / 2) * pw + kw / 2 + w]
            .copy_from_slice(&src.data[y * w..(y + 1) * w]);
    }

    let offsets: Vec<usize> = (0..kh * kw)
        .filter(|&i| kernel.data[i] != 0)
        .map(|i| (i / kw) * pw + i % kw)
        .collect();
    if offsets.is_empty() {
        return ImageU8::new(src.width, src.height, 1, vec![pad; w * h]);
    }

    let mut out = vec![0u8; w * h];
    let row = |y: usize, dst: &mut [u8]| {
        let base = y * pw;
        dst.copy_from_slice(&padded[base + offsets[0]..base + offsets[0] + w]);
        for &off in &offsets[1..] {
            let src_slice = &padded[base + off..base + off + w];
            if erode {
                for (d, &s) in dst.iter_mut().zip(src_slice) {
                    *d = (*d).min(s);
                }
            } else {
                for (d, &s) in dst.iter_mut().zip(src_slice) {
                    *d = (*d).max(s);
                }
            }
        }
    };
    if w * h >= PARALLEL_MIN_ELEMS {
        out.par_chunks_mut(w)
            .enumerate()
            .for_each(|(y, dst)| row(y, dst));
    } else {
        for (y, dst) in out.chunks_mut(w).enumerate() {
            row(y, dst);
        }
    }
    ImageU8::new(src.width, src.height, 1, out)
}

pub(crate) fn morphology_erode(src: &ImageU8, kernel: &ImageU8) -> OpResult<ImageU8> {
    morph(src, kernel, true)
}

fn morphology_dilate(src: &ImageU8, kernel: &ImageU8) -> OpResult<ImageU8> {
    morph(src, kernel, false)
}

pub(crate) fn morphology_open(src: &ImageU8, kernel: &ImageU8) -> OpResult<ImageU8> {
    morphology_dilate(&morphology_erode(src, kernel)?, kernel)
}

pub(crate) fn morphology_close(src: &ImageU8, kernel: &ImageU8) -> OpResult<ImageU8> {
    morphology_erode(&morphology_dilate(src, kernel)?, kernel)
}
