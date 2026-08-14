use rayon::prelude::*;

use super::reflect101;
use crate::cv::OpResult;
use crate::cv::image::ImageU8;

pub(crate) fn bilateral_filter_u8(
    src: &ImageU8,
    d: i32,
    sigma_color: f64,
    sigma_space: f64,
) -> OpResult<ImageU8> {
    if src.channels != 1 {
        return Err("bilateral_filter_u8: expected a single-channel image".to_string());
    }
    if sigma_color <= 1e-6 || sigma_space <= 1e-6 {
        return Ok(src.clone());
    }
    let radius = if d <= 0 {
        (sigma_space * 1.5).round() as i32
    } else {
        d / 2
    }
    .max(1) as usize;
    let (w, h) = (src.width as usize, src.height as usize);

    let stride = w + 2 * radius;
    let mut temp = vec![0u8; stride * (h + 2 * radius)];
    let cols: Vec<usize> = (0..stride)
        .map(|x| reflect101(x as i64 - radius as i64, src.width) as usize)
        .collect();
    for (y, trow) in temp.chunks_exact_mut(stride).enumerate() {
        let sy = reflect101(y as i64 - radius as i64, src.height) as usize;
        let srow = &src.data[sy * w..(sy + 1) * w];
        for (t, &sx) in trow.iter_mut().zip(cols.iter()) {
            *t = srow[sx];
        }
    }

    let color_coeff = -0.5 / (sigma_color * sigma_color);
    let space_coeff = -0.5 / (sigma_space * sigma_space);
    let color_weight: Vec<f32> = (0..256)
        .map(|i| ((i * i) as f64 * color_coeff).exp() as f32)
        .collect();

    let ir = radius as i64;
    let mut taps = Vec::new();
    for i in -ir..=ir {
        for j in -ir..=ir {
            let r2 = (i * i + j * j) as f64;
            if r2 > (ir * ir) as f64 {
                continue;
            }
            taps.push((
                ((i + ir) as usize * stride + (j + ir) as usize),
                (r2 * space_coeff).exp() as f32,
            ));
        }
    }

    let mut out = vec![0u8; w * h];
    out.par_chunks_exact_mut(w)
        .enumerate()
        .for_each(|(y, dst)| {
            let win = &temp[y * stride..];
            let centre = radius * stride + radius;
            for (x, d) in dst.iter_mut().enumerate() {
                let mid = win[centre + x] as i32;
                let mut sum = 0.0f32;
                let mut wsum = 0.0f32;
                for &(off, sw) in &taps {
                    let val = win[off + x];
                    let weight = sw * color_weight[(val as i32 - mid).unsigned_abs() as usize];
                    wsum += weight;
                    sum += val as f32 * weight;
                }
                *d = (sum / wsum).round_ties_even() as u8;
            }
        });
    ImageU8::new(src.width, src.height, 1, out)
}
