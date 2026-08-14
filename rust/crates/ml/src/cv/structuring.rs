use crate::cv::OpResult;
use crate::cv::image::ImageU8;

pub(crate) fn ellipse_kernel(ksize: i32) -> OpResult<ImageU8> {
    if ksize <= 0 {
        return Err(format!("ellipse_kernel: invalid ksize {ksize}"));
    }
    let mut element = ImageU8::zeros(ksize, ksize, 1)?;
    let rect = ksize == 1;
    let r = ksize / 2;
    let inv_r2 = if r != 0 {
        1.0 / (r as f64 * r as f64)
    } else {
        0.0
    };
    let c = ksize / 2;

    for i in 0..ksize {
        let (mut j1, mut j2) = (0i32, 0i32);
        if rect {
            j2 = ksize;
        } else {
            let dy = i - r;
            if dy.abs() <= r {
                let dx = (c as f64 * (((r * r - dy * dy) as f64) * inv_r2).sqrt()).round_ties_even()
                    as i32;
                j1 = (c - dx).max(0);
                j2 = (c + dx + 1).min(ksize);
            }
        }
        let row = (i * ksize) as usize;
        for j in j1.max(0)..j2 {
            element.data[row + j as usize] = 1;
        }
    }
    Ok(element)
}
