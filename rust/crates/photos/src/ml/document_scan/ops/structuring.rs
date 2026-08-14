//! `cv::getStructuringElement(MORPH_ELLIPSE, Size(k, k))`.

use super::saturate_i32_f64;
use crate::ml::document_scan::OpResult;
use crate::ml::document_scan::image::ImageU8;

/// Element values are 0/1, and a 1x1 element degrades to `MORPH_RECT`.
pub(crate) fn get_structuring_element_ellipse(ksize: i32) -> OpResult<ImageU8> {
    if ksize <= 0 {
        return Err(format!(
            "get_structuring_element_ellipse: invalid ksize {ksize}"
        ));
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
                let dx = saturate_i32_f64(c as f64 * (((r * r - dy * dy) as f64) * inv_r2).sqrt());
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
