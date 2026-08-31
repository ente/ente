use crate::cv::OpResult;
use crate::cv::image::ImageU8;

pub(crate) fn rotate_u8(src: &ImageU8, degrees: i32) -> OpResult<ImageU8> {
    let cn = src.channels as usize;
    let (w, h) = (src.width as usize, src.height as usize);
    let degrees = degrees.rem_euclid(360);
    let (out_w, out_h) = match degrees {
        0 | 180 => (src.width, src.height),
        90 | 270 => (src.height, src.width),
        other => {
            return Err(format!(
                "Only 0, 90, 180, 270 degrees are supported, got {other}"
            ));
        }
    };

    let mut data = vec![0u8; src.data.len()];
    let move_px = |dst: &mut [u8], d: usize, s: usize| match cn {
        1 => dst[d] = src.data[s],
        3 => {
            dst[d] = src.data[s];
            dst[d + 1] = src.data[s + 1];
            dst[d + 2] = src.data[s + 2];
        }
        _ => dst[d..d + cn].copy_from_slice(&src.data[s..s + cn]),
    };

    match degrees {
        0 => data.copy_from_slice(&src.data),
        180 => {
            for y in 0..h {
                for x in 0..w {
                    let s = ((h - 1 - y) * w + (w - 1 - x)) * cn;
                    let d = (y * w + x) * cn;
                    move_px(&mut data, d, s);
                }
            }
        }
        _ => {
            let ow = out_w as usize;
            let oh = out_h as usize;
            for y in 0..oh {
                for x in 0..ow {
                    let (sx, sy) = if degrees == 90 {
                        (y, h - 1 - x)
                    } else {
                        (w - 1 - y, x)
                    };
                    move_px(&mut data, (y * ow + x) * cn, (sy * w + sx) * cn);
                }
            }
        }
    }
    ImageU8::new(out_w, out_h, src.channels, data)
}
