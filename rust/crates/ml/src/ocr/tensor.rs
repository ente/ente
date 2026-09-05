use crate::cv::image::ImageU8;
use crate::error::{MlError, MlResult};

#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct BgrNormalization {
    mean: [f32; 3],
    std: [f32; 3],
}

impl BgrNormalization {
    pub(crate) const IMAGENET: Self = Self {
        mean: [0.485, 0.456, 0.406],
        std: [0.229, 0.224, 0.225],
    };

    pub(crate) const CENTERED: Self = Self {
        mean: [0.5; 3],
        std: [0.5; 3],
    };

    fn apply(self, channel: usize, value: u8) -> f32 {
        (value as f32 / 255.0 - self.mean[channel]) / self.std[channel]
    }
}

pub(crate) fn write_bgr_planes(
    rgb: &ImageU8,
    planes: &mut [f32],
    plane_width: usize,
    normalization: BgrNormalization,
) -> MlResult<()> {
    let width = rgb.width as usize;
    let height = rgb.height as usize;
    let plane = plane_width * height;
    if rgb.channels != 3 || width > plane_width || planes.len() != 3 * plane {
        return Err(MlError::Preprocess(format!(
            "cannot write a {width}x{height}x{} image into {} values as {plane_width}-wide BGR planes",
            rgb.channels,
            planes.len()
        )));
    }
    let (blue, rest) = planes.split_at_mut(plane);
    let (green, red) = rest.split_at_mut(plane);
    for (y, row) in rgb.data.chunks_exact(width * 3).enumerate() {
        let offset = y * plane_width;
        for (x, px) in row.as_chunks::<3>().0.iter().enumerate() {
            blue[offset + x] = normalization.apply(0, px[2]);
            green[offset + x] = normalization.apply(1, px[1]);
            red[offset + x] = normalization.apply(2, px[0]);
        }
        let padding = offset + width..offset + plane_width;
        blue[padding.clone()].fill(0.0);
        green[padding.clone()].fill(0.0);
        red[padding].fill(0.0);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn centered(value: u8) -> f32 {
        (value as f32 / 255.0 - 0.5) / 0.5
    }

    #[test]
    fn planes_are_bgr_left_aligned_per_row_and_zero_padded() {
        let rgb = ImageU8::new(
            2,
            2,
            3,
            vec![10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120],
        )
        .unwrap();
        let mut planes = vec![f32::NAN; 3 * 3 * 2];

        write_bgr_planes(&rgb, &mut planes, 3, BgrNormalization::CENTERED).unwrap();

        let expected = [
            [30, 60, 0, 90, 120, 0],
            [20, 50, 0, 80, 110, 0],
            [10, 40, 0, 70, 100, 0],
        ];
        for (channel, values) in expected.into_iter().enumerate() {
            for (x, value) in values.into_iter().enumerate() {
                let expected = if x % 3 == 2 { 0.0 } else { centered(value) };
                let actual = planes[channel * 6 + x];
                assert!(
                    (actual - expected).abs() <= 1e-6,
                    "channel {channel} index {x}: {actual} != {expected}"
                );
            }
        }
    }

    #[test]
    fn imagenet_normalization_uses_the_bgr_channel_statistics() {
        let rgb = ImageU8::new(1, 1, 3, vec![10, 20, 30]).unwrap();
        let mut planes = vec![0.0f32; 3];

        write_bgr_planes(&rgb, &mut planes, 1, BgrNormalization::IMAGENET).unwrap();

        let expected = [
            (30.0 / 255.0 - 0.485) / 0.229,
            (20.0 / 255.0 - 0.456) / 0.224,
            (10.0 / 255.0 - 0.406) / 0.225,
        ];
        for (actual, expected) in planes.iter().zip(expected) {
            assert!((actual - expected).abs() <= 1e-6, "{planes:?}");
        }
    }
}
