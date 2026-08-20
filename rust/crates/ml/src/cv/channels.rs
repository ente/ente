use crate::cv::OpResult;
use crate::cv::image::ImageU8;

// 15-bit fixed-point BT.601 luma weights.
const GRAY_SHIFT: i32 = 15;
const RY15: i32 = 9798;
const GY15: i32 = 19235;
const BY15: i32 = 3735;

fn require_channels(src: &ImageU8, channels: i32, op: &str) -> OpResult<()> {
    if src.channels != channels {
        return Err(format!(
            "{op}: expected {channels} channel(s), got {}",
            src.channels
        ));
    }
    Ok(())
}

pub(crate) fn gray_to_bgr(src: &ImageU8) -> OpResult<ImageU8> {
    require_channels(src, 1, "gray_to_bgr")?;
    let mut data = vec![0u8; src.data.len() * 3];
    super::pointwise(&mut data, 3, &src.data, 1, |data, srcd| {
        for (out, &v) in data.chunks_exact_mut(3).zip(srcd.iter()) {
            out[0] = v;
            out[1] = v;
            out[2] = v;
        }
    });
    ImageU8::new(src.width, src.height, 3, data)
}

pub(crate) fn bgr_to_gray(src: &ImageU8) -> OpResult<ImageU8> {
    require_channels(src, 3, "bgr_to_gray")?;
    let round = 1i32 << (GRAY_SHIFT - 1);
    let mut data = vec![0u8; src.data.len() / 3];
    super::pointwise(&mut data, 1, &src.data, 3, |data, srcd| {
        for (out, px) in data.iter_mut().zip(srcd.chunks_exact(3)) {
            let sum = px[0] as i32 * BY15 + px[1] as i32 * GY15 + px[2] as i32 * RY15;
            *out = ((sum + round) >> GRAY_SHIFT) as u8;
        }
    });
    ImageU8::new(src.width, src.height, 1, data)
}

pub(crate) fn split_u8(src: &ImageU8) -> OpResult<Vec<ImageU8>> {
    let cn = src.channels as usize;
    let mut planes = Vec::with_capacity(cn);
    for c in 0..cn {
        let mut data = vec![0u8; src.data.len() / cn];
        super::pointwise(&mut data, 1, &src.data, cn, |data, srcd| {
            for (out, px) in data.iter_mut().zip(srcd.chunks_exact(cn)) {
                *out = px[c];
            }
        });
        planes.push(ImageU8::new(src.width, src.height, 1, data)?);
    }
    Ok(planes)
}

pub(crate) fn merge_u8(channels: &[ImageU8]) -> OpResult<ImageU8> {
    let first = channels
        .first()
        .ok_or_else(|| "merge_u8: no input planes".to_string())?;
    for plane in channels {
        if plane.channels != 1 {
            return Err("merge_u8: every input plane must be single-channel".to_string());
        }
        if plane.width != first.width || plane.height != first.height {
            return Err("merge_u8: input planes have different sizes".to_string());
        }
    }
    let cn = channels.len();
    let mut data = vec![0u8; first.data.len() * cn];
    for (c, plane) in channels.iter().enumerate() {
        for (i, &v) in plane.data.iter().enumerate() {
            data[i * cn + c] = v;
        }
    }
    ImageU8::new(first.width, first.height, cn as i32, data)
}
