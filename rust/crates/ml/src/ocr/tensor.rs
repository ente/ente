use std::sync::OnceLock;

use rayon::{ThreadPool, ThreadPoolBuilder};

use crate::cv::image::ImageU8;
use crate::error::{MlError, MlResult};

pub(crate) fn prepare_crops<T: Send>(prepare: impl FnOnce() -> MlResult<T> + Send) -> MlResult<T> {
    static POOL: OnceLock<Option<ThreadPool>> = OnceLock::new();
    let pool = POOL.get_or_init(|| {
        ThreadPoolBuilder::new()
            .num_threads(1)
            .thread_name(|_| "ocr-crop-preparation".to_string())
            .build()
            .ok()
    });
    match pool {
        Some(pool) => pool.install(prepare),
        None => prepare(),
    }
}

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
    let plane = planes.len() / 3;
    let plane_height = plane.checked_div(plane_width).unwrap_or(0);
    let expected = width
        .checked_mul(height)
        .and_then(|size| size.checked_mul(3));
    if rgb.width <= 0
        || rgb.height <= 0
        || rgb.channels != 3
        || width > plane_width
        || height > plane_height
        || !planes.len().is_multiple_of(3)
        || plane_width == 0
        || !plane.is_multiple_of(plane_width)
        || expected != Some(rgb.data.len())
    {
        return Err(MlError::Preprocess(format!(
            "cannot write a {width}x{height}x{} image into {} values as {plane_width}-wide BGR planes",
            rgb.channels,
            planes.len()
        )));
    }
    let lookup: [[f32; 256]; 3] = std::array::from_fn(|channel| {
        std::array::from_fn(|value| normalization.apply(channel, value as u8))
    });
    let (blue, rest) = planes.split_at_mut(plane);
    let (green, red) = rest.split_at_mut(plane);
    let top = (plane_height - height) / 2 * plane_width;
    let bottom = top + height * plane_width;
    for channel in [&mut *blue, &mut *green, &mut *red] {
        channel[..top].fill(0.0);
        channel[bottom..].fill(0.0);
    }
    for (y, row) in rgb.data.chunks_exact(width * 3).enumerate() {
        let offset = top + y * plane_width;
        for (x, px) in row.as_chunks::<3>().0.iter().enumerate() {
            blue[offset + x] = lookup[0][px[2] as usize];
            green[offset + x] = lookup[1][px[1] as usize];
            red[offset + x] = lookup[2][px[0] as usize];
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
    fn preparation_keeps_the_callers_worker_pool_unchanged() {
        let caller = ThreadPoolBuilder::new().num_threads(4).build().unwrap();
        caller.install(|| {
            let values = prepare_crops(|| Ok(vec![rayon::current_num_threads() as f32])).unwrap();
            assert_eq!(values, [1.0]);
            assert_eq!(rayon::current_num_threads(), 4);
        });
    }

    #[test]
    fn preparation_reuses_the_worker_across_return_types() {
        let first = prepare_crops(|| Ok(std::thread::current().id())).unwrap();
        let second = prepare_crops(|| Ok(vec![std::thread::current().id()])).unwrap();
        assert_eq!(second, [first]);
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

    #[test]
    fn smaller_images_are_centered_vertically_with_zero_padding_on_every_side() {
        let rgb = ImageU8::new(1, 2, 3, vec![10, 20, 30, 40, 50, 60]).unwrap();
        for height in [4, 5] {
            let mut planes = vec![f32::NAN; 3 * 2 * height];
            write_bgr_planes(&rgb, &mut planes, 2, BgrNormalization::CENTERED).unwrap();
            for (channel, plane) in planes.chunks_exact(2 * height).enumerate() {
                for (y, row) in plane.as_chunks::<2>().0.iter().enumerate() {
                    let expected = match y {
                        1 => centered([30, 20, 10][channel]),
                        2 => centered([60, 50, 40][channel]),
                        _ => 0.0,
                    };
                    assert_eq!(*row, [expected, 0.0]);
                }
            }
        }
    }

    #[test]
    fn invalid_destination_planes_return_an_error() {
        let rgb = ImageU8::new(2, 2, 3, vec![0; 12]).unwrap();
        for (width, len) in [(0, 12), (1, 12), (2, 6), (2, 13), (3, 12)] {
            assert!(
                write_bgr_planes(&rgb, &mut vec![0.0; len], width, BgrNormalization::CENTERED,)
                    .is_err()
            );
        }
    }
}
