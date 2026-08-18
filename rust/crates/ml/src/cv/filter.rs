use crate::cv::OpResult;
use crate::cv::image::{ImageF32, ImageU8};

use super::reflect101;

fn gaussian_taps(n: i32) -> OpResult<&'static [u32]> {
    Ok(match n {
        1 => &[256],
        3 => &[64, 128, 64],
        5 => &[16, 64, 96, 64, 16],
        7 => &[8, 28, 56, 72, 56, 28, 8],
        _ => return Err(format!("gaussian_blur_u8: unsupported ksize {n}")),
    })
}

pub(crate) fn gaussian_blur_u8(src: &ImageU8, ksize: i32) -> OpResult<ImageU8> {
    if src.channels != 1 {
        return Err("gaussian_blur_u8: expected a single-channel image".to_string());
    }
    let kw = if src.width == 1 { 1 } else { ksize };
    let kh = if src.height == 1 { 1 } else { ksize };
    if kw == 1 && kh == 1 {
        return Ok(src.clone());
    }
    let kx = gaussian_taps(kw)?;
    let ky = gaussian_taps(kh)?;
    let (w, h) = (src.width as usize, src.height as usize);
    let (ax, ay) = ((kw / 2) as i64, (kh / 2) as i64);

    let mut hsum = vec![0u16; w * h];
    for y in 0..h {
        let row = &src.data[y * w..(y + 1) * w];
        let out = &mut hsum[y * w..(y + 1) * w];
        for (x, o) in out.iter_mut().enumerate() {
            let mut acc = 0u16;
            for (t, &tap) in kx.iter().enumerate() {
                let sx = reflect101(x as i64 + t as i64 - ax, src.width) as usize;
                acc += tap as u16 * row[sx] as u16;
            }
            *o = acc;
        }
    }
    let mut out = vec![0u8; w * h];
    let mut acc = vec![0u32; w];
    for y in 0..h {
        let dst = &mut out[y * w..(y + 1) * w];
        acc.iter_mut().for_each(|a| *a = 0);
        for (t, &tap) in ky.iter().enumerate() {
            let sy = reflect101(y as i64 + t as i64 - ay, src.height) as usize;
            for (a, &v) in acc.iter_mut().zip(&hsum[sy * w..(sy + 1) * w]) {
                *a += tap * v as u32;
            }
        }
        for (d, &a) in dst.iter_mut().zip(acc.iter()) {
            *d = ((a + (1 << 15)) >> 16).min(255) as u8;
        }
    }
    ImageU8::new(src.width, src.height, 1, out)
}

pub(crate) fn box_filter_f32(src: &ImageF32, kw: i32, kh: i32) -> OpResult<ImageF32> {
    if kw <= 0 || kh <= 0 {
        return Err(format!("box_filter_f32: invalid kernel {kw}x{kh}"));
    }
    if src.channels != 1 {
        return Err("box_filter_f32: expected a single-channel image".to_string());
    }
    let (w, h) = (src.width as usize, src.height as usize);
    let (ax, ay) = ((kw / 2) as i64, (kh / 2) as i64);
    let scale = 1.0 / (kw as f64 * kh as f64);

    let mut hsum = vec![0.0f64; w * h];
    let ext_idx: Vec<usize> = (0..w + kw as usize - 1)
        .map(|j| reflect101(j as i64 - ax, src.width) as usize)
        .collect();
    let mut ext = vec![0.0f64; w + kw as usize - 1];
    for y in 0..h {
        let row = &src.data[y * w..(y + 1) * w];
        for (e, &sx) in ext.iter_mut().zip(ext_idx.iter()) {
            *e = row[sx] as f64;
        }
        let out = &mut hsum[y * w..(y + 1) * w];
        let mut s: f64 = ext[..kw as usize].iter().sum();
        out[0] = s;
        for x in 1..w {
            s += ext[x + kw as usize - 1] - ext[x - 1];
            out[x] = s;
        }
    }

    let mut out = vec![0.0f32; w * h];
    let mut col = vec![0.0f64; w];
    for t in 0..kh as usize - 1 {
        let sy = reflect101(t as i64 - ay, src.height) as usize;
        for (c, &v) in col.iter_mut().zip(&hsum[sy * w..(sy + 1) * w]) {
            *c += v;
        }
    }
    for y in 0..h {
        let enter = reflect101(y as i64 + kh as i64 - 1 - ay, src.height) as usize;
        for (c, &v) in col.iter_mut().zip(&hsum[enter * w..(enter + 1) * w]) {
            *c += v;
        }
        let dst = &mut out[y * w..(y + 1) * w];
        for (d, &c) in dst.iter_mut().zip(col.iter()) {
            *d = (c * scale) as f32;
        }
        let leave = reflect101(y as i64 - ay, src.height) as usize;
        for (c, &v) in col.iter_mut().zip(&hsum[leave * w..(leave + 1) * w]) {
            *c -= v;
        }
    }
    ImageF32::new(src.width, src.height, 1, out)
}
