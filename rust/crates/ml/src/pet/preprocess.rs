use crate::{
    error::{MlError, MlResult},
    types::DecodedImage,
};

use super::{PET_EMBEDDING_CHANNELS, PET_EMBEDDING_INPUT_SIZE, PET_SPECIES_CAT};

const IMAGENET_MEAN: [f32; 3] = [0.485, 0.456, 0.406];
const IMAGENET_STD: [f32; 3] = [0.229, 0.224, 0.225];

pub(super) struct IndexedEmbeddingBatch {
    pub(super) indices: Vec<usize>,
    pub(super) input: Vec<f32>,
}

impl IndexedEmbeddingBatch {
    pub(super) fn new(item_capacity: usize, floats_per_item: usize) -> Self {
        Self {
            indices: Vec::with_capacity(item_capacity),
            input: Vec::with_capacity(item_capacity * floats_per_item),
        }
    }

    pub(super) fn is_empty(&self) -> bool {
        self.indices.is_empty()
    }
}

pub(crate) struct PetFaceEmbeddingInputs {
    pub(super) dog: IndexedEmbeddingBatch,
    pub(super) cat: IndexedEmbeddingBatch,
}

impl PetFaceEmbeddingInputs {
    pub(super) fn new(dog_capacity: usize, cat_capacity: usize) -> Self {
        let floats_per_face =
            PET_EMBEDDING_INPUT_SIZE * PET_EMBEDDING_INPUT_SIZE * PET_EMBEDDING_CHANNELS;
        Self {
            dog: IndexedEmbeddingBatch::new(dog_capacity, floats_per_face),
            cat: IndexedEmbeddingBatch::new(cat_capacity, floats_per_face),
        }
    }

    pub(super) fn batch_mut(&mut self, class_id: u8) -> &mut IndexedEmbeddingBatch {
        if class_id == PET_SPECIES_CAT {
            &mut self.cat
        } else {
            &mut self.dog
        }
    }
}

#[derive(Clone, Copy)]
pub(super) struct PixelCrop {
    pub(super) x: u32,
    pub(super) y: u32,
    pub(super) width: u32,
    pub(super) height: u32,
}

// Match the Python pipeline's ImageNet-normalized CHW input.
pub(super) struct PetEmbeddingPreprocessor {
    crop_resizer: RgbCropResizer,
}

impl PetEmbeddingPreprocessor {
    pub(super) fn new() -> Self {
        Self {
            crop_resizer: RgbCropResizer::new(PET_EMBEDDING_INPUT_SIZE as u32),
        }
    }

    pub(super) fn append(
        &mut self,
        decoded: &DecodedImage,
        box_xyxy: &[f32; 4],
        output: &mut Vec<f32>,
    ) -> MlResult<()> {
        let crop = relative_crop(decoded, box_xyxy)?;
        let resized = self.crop_resizer.resize(decoded, crop)?;
        append_imagenet_tensor(resized, output);
        Ok(())
    }
}

fn relative_crop(decoded: &DecodedImage, box_xyxy: &[f32; 4]) -> MlResult<PixelCrop> {
    let img_w = decoded.dimensions.width;
    let img_h = decoded.dimensions.height;

    let max_x = if img_w > 0 { img_w - 1 } else { 0 };
    let max_y = if img_h > 0 { img_h - 1 } else { 0 };
    let x1 = (box_xyxy[0] * img_w as f32)
        .round()
        .clamp(0.0, max_x as f32) as u32;
    let y1 = (box_xyxy[1] * img_h as f32)
        .round()
        .clamp(0.0, max_y as f32) as u32;
    let x2 = (box_xyxy[2] * img_w as f32)
        .round()
        .clamp(0.0, img_w as f32) as u32;
    let y2 = (box_xyxy[3] * img_h as f32)
        .round()
        .clamp(0.0, img_h as f32) as u32;

    let width = x2.saturating_sub(x1);
    let height = y2.saturating_sub(y1);

    if width == 0 || height == 0 {
        return Err(MlError::Image("crop region has zero area".to_string()));
    }

    Ok(PixelCrop {
        x: x1,
        y: y1,
        width,
        height,
    })
}

pub(super) struct RgbCropResizer {
    output_size: u32,
    resized: Vec<u8>,
}

impl RgbCropResizer {
    pub(super) fn new(output_size: u32) -> Self {
        assert!(output_size > 0);
        let output_len = (output_size as usize)
            .checked_mul(output_size as usize)
            .and_then(|pixels| pixels.checked_mul(3))
            .expect("RGB crop output dimensions overflow");
        Self {
            output_size,
            resized: vec![0; output_len],
        }
    }

    pub(super) fn resize(&mut self, decoded: &DecodedImage, crop: PixelCrop) -> MlResult<&[u8]> {
        let source = RgbRegion::new(
            decoded,
            PixelCrop {
                x: 0,
                y: 0,
                width: decoded.dimensions.width,
                height: decoded.dimensions.height,
            },
        )?;
        self.render(&source, crop, |x, y| (x, y))
    }

    pub(super) fn resize_rotated(
        &mut self,
        decoded: &DecodedImage,
        region: PixelCrop,
        crop: PixelCrop,
        angle_rad: f64,
        center: [f64; 2],
    ) -> MlResult<&[u8]> {
        let source = RgbRegion::new(decoded, region)?;
        let cos = angle_rad.cos();
        let sin = angle_rad.sin();
        self.render(&source, crop, |x, y| {
            let dx = x - center[0];
            let dy = y - center[1];
            (
                cos * dx + sin * dy + center[0],
                -sin * dx + cos * dy + center[1],
            )
        })
    }

    fn render<'a>(
        &'a mut self,
        source: &RgbRegion<'_>,
        crop: PixelCrop,
        transform: impl Fn(f64, f64) -> (f64, f64),
    ) -> MlResult<&'a [u8]> {
        source.validate_crop(crop)?;

        let output_size = self.output_size;
        let x_scale = f64::from(crop.width) / f64::from(output_size);
        let y_scale = f64::from(crop.height) / f64::from(output_size);
        let min_x = f64::from(crop.x);
        let min_y = f64::from(crop.y);
        let max_x = min_x + f64::from(crop.width - 1);
        let max_y = min_y + f64::from(crop.height - 1);

        for output_y in 0..output_size {
            let crop_y = (min_y + (f64::from(output_y) + 0.5) * y_scale - 0.5).clamp(min_y, max_y);
            for output_x in 0..output_size {
                let crop_x =
                    (min_x + (f64::from(output_x) + 0.5) * x_scale - 0.5).clamp(min_x, max_x);
                let (source_x, source_y) = transform(crop_x, crop_y);
                let pixel = source.sample_bilinear(source_x, source_y);
                let output_index =
                    (output_y as usize * output_size as usize + output_x as usize) * 3;
                self.resized[output_index..output_index + 3].copy_from_slice(&pixel);
            }
        }

        Ok(&self.resized)
    }
}

struct RgbRegion<'a> {
    rgb: &'a [u8],
    image_width: usize,
    x: u32,
    y: u32,
    width: u32,
    height: u32,
}

impl<'a> RgbRegion<'a> {
    fn new(decoded: &'a DecodedImage, region: PixelCrop) -> MlResult<Self> {
        let image_width = decoded.dimensions.width;
        let image_height = decoded.dimensions.height;
        if region.width == 0
            || region.height == 0
            || region.width > image_width
            || region.height > image_height
            || region.x > image_width - region.width
            || region.y > image_height - region.height
        {
            return Err(MlError::Image(
                "RGB region extends beyond source image".to_string(),
            ));
        }
        let expected_len = (image_width as usize)
            .checked_mul(image_height as usize)
            .and_then(|pixels| pixels.checked_mul(3))
            .ok_or_else(|| MlError::Image("RGB source dimensions overflow".to_string()))?;
        if decoded.rgb.len() < expected_len {
            return Err(MlError::Image(
                "RGB source buffer is shorter than its dimensions".to_string(),
            ));
        }

        Ok(Self {
            rgb: &decoded.rgb,
            image_width: image_width as usize,
            x: region.x,
            y: region.y,
            width: region.width,
            height: region.height,
        })
    }

    fn validate_crop(&self, crop: PixelCrop) -> MlResult<()> {
        if crop.width == 0 || crop.height == 0 {
            return Err(MlError::Image("crop dimensions cannot be zero".to_string()));
        }
        if crop.width > self.width
            || crop.height > self.height
            || crop.x > self.width - crop.width
            || crop.y > self.height - crop.height
        {
            return Err(MlError::Image(
                "crop region extends beyond source image".to_string(),
            ));
        }
        Ok(())
    }

    fn sample_bilinear(&self, x: f64, y: f64) -> [u8; 3] {
        let x = x.clamp(0.0, f64::from(self.width - 1));
        let y = y.clamp(0.0, f64::from(self.height - 1));
        let x0 = x.floor() as u32;
        let y0 = y.floor() as u32;
        let x1 = (x0 + 1).min(self.width - 1);
        let y1 = (y0 + 1).min(self.height - 1);
        let x_weight = (x - x.floor()) as f32;
        let y_weight = (y - y.floor()) as f32;

        let top_left = self.get_pixel(x0, y0);
        let top_right = self.get_pixel(x1, y0);
        let bottom_left = self.get_pixel(x0, y1);
        let bottom_right = self.get_pixel(x1, y1);
        let mut output = [0; 3];
        for channel in 0..3 {
            let value = top_left[channel] as f32 * (1.0 - x_weight) * (1.0 - y_weight)
                + top_right[channel] as f32 * x_weight * (1.0 - y_weight)
                + bottom_left[channel] as f32 * (1.0 - x_weight) * y_weight
                + bottom_right[channel] as f32 * x_weight * y_weight;
            output[channel] = value.round().clamp(0.0, 255.0) as u8;
        }
        output
    }

    fn get_pixel(&self, x: u32, y: u32) -> [u8; 3] {
        let pixel = ((self.y + y) as usize * self.image_width + (self.x + x) as usize) * 3;
        [self.rgb[pixel], self.rgb[pixel + 1], self.rgb[pixel + 2]]
    }
}

pub(super) fn append_imagenet_tensor(resized: &[u8], output: &mut Vec<f32>) {
    let pixel_count = PET_EMBEDDING_INPUT_SIZE * PET_EMBEDDING_INPUT_SIZE;
    let start = output.len();
    output.resize(start + 3 * pixel_count, 0.0);
    let tensor = &mut output[start..];

    for index in 0..pixel_count {
        let source = index * 3;
        tensor[index] = (resized[source] as f32 / 255.0 - IMAGENET_MEAN[0]) / IMAGENET_STD[0];
        tensor[pixel_count + index] =
            (resized[source + 1] as f32 / 255.0 - IMAGENET_MEAN[1]) / IMAGENET_STD[1];
        tensor[2 * pixel_count + index] =
            (resized[source + 2] as f32 / 255.0 - IMAGENET_MEAN[2]) / IMAGENET_STD[2];
    }
}

#[cfg(test)]
mod tests {
    use fast_image_resize::{
        FilterType, PixelType, ResizeAlg, ResizeOptions, Resizer,
        images::{CroppedImage, Image as FirImage, ImageRef as FirImageRef},
    };

    use super::{PixelCrop, RgbCropResizer};
    use crate::types::{DecodedImage, Dimensions};

    #[test]
    fn crop_resize_matches_a_materialized_crop() {
        let width = 6u32;
        let height = 5u32;
        let decoded = DecodedImage {
            dimensions: Dimensions { width, height },
            rgb: (0..(width * height * 3))
                .map(|value| (value % 251) as u8)
                .collect(),
        };
        let crop = PixelCrop {
            x: 1,
            y: 1,
            width: 4,
            height: 3,
        };

        let direct = RgbCropResizer::new(7)
            .resize(&decoded, crop)
            .unwrap()
            .to_vec();

        let mut materialized = Vec::new();
        for row in crop.y..crop.y + crop.height {
            let start = ((row * width + crop.x) * 3) as usize;
            let end = start + (crop.width * 3) as usize;
            materialized.extend_from_slice(&decoded.rgb[start..end]);
        }
        let materialized = DecodedImage {
            dimensions: Dimensions {
                width: crop.width,
                height: crop.height,
            },
            rgb: materialized,
        };
        let baseline = RgbCropResizer::new(7)
            .resize(
                &materialized,
                PixelCrop {
                    x: 0,
                    y: 0,
                    width: crop.width,
                    height: crop.height,
                },
            )
            .unwrap()
            .to_vec();

        assert_eq!(direct, baseline);
    }

    #[test]
    fn crop_resize_stays_close_to_fir() {
        for (width, height, output_size, crop) in [
            (
                19,
                13,
                7,
                PixelCrop {
                    x: 2,
                    y: 3,
                    width: 14,
                    height: 8,
                },
            ),
            (
                7,
                5,
                13,
                PixelCrop {
                    x: 1,
                    y: 1,
                    width: 5,
                    height: 3,
                },
            ),
            (
                101,
                3,
                17,
                PixelCrop {
                    x: 1,
                    y: 0,
                    width: 99,
                    height: 3,
                },
            ),
        ] {
            let decoded = test_image(width, height);
            let actual = RgbCropResizer::new(output_size)
                .resize(&decoded, crop)
                .unwrap()
                .to_vec();
            let expected = fir_resize(&decoded.rgb, width, height, crop, output_size);
            assert_max_delta(&actual, &expected, 1);
        }
    }

    #[test]
    fn zero_angle_region_matches_global_crop() {
        let width = 23;
        let height = 17;
        let decoded = test_image(width, height);
        let region = PixelCrop {
            x: 3,
            y: 2,
            width: 17,
            height: 13,
        };
        let local_crop = PixelCrop {
            x: 4,
            y: 3,
            width: 9,
            height: 7,
        };
        let global_crop = PixelCrop {
            x: region.x + local_crop.x,
            y: region.y + local_crop.y,
            ..local_crop
        };

        let direct = RgbCropResizer::new(11)
            .resize(&decoded, global_crop)
            .unwrap()
            .to_vec();
        let rotated = RgbCropResizer::new(11)
            .resize_rotated(&decoded, region, local_crop, 0.0, [8.5, 6.5])
            .unwrap()
            .to_vec();

        assert_eq!(direct, rotated);
    }

    #[test]
    fn fused_rotation_stays_close_to_two_pass_pipeline() {
        let width = 41;
        let height = 31;
        let decoded = smooth_test_image(width, height);
        let region = PixelCrop {
            x: 4,
            y: 3,
            width: 33,
            height: 25,
        };
        let crop = PixelCrop {
            x: 8,
            y: 6,
            width: 17,
            height: 13,
        };
        let angle = 0.27;
        let center_x = 16.5;
        let center_y = 12.5;

        let actual = RgbCropResizer::new(19)
            .resize_rotated(&decoded, region, crop, angle, [center_x, center_y])
            .unwrap()
            .to_vec();
        let rotated =
            materialize_rotated_crop(&decoded.rgb, width, region, crop, angle, center_x, center_y);
        let expected = fir_resize(
            &rotated,
            crop.width,
            crop.height,
            PixelCrop {
                x: 0,
                y: 0,
                width: crop.width,
                height: crop.height,
            },
            19,
        );

        assert_max_delta(&actual, &expected, 1);
    }

    #[test]
    fn extreme_aspect_ratio_has_fixed_output() {
        let width = 100_000;
        let decoded = test_image(width, 1);
        let mut resizer = RgbCropResizer::new(224);
        let capacity = resizer.resized.capacity();
        let resized = resizer
            .resize(
                &decoded,
                PixelCrop {
                    x: 0,
                    y: 0,
                    width,
                    height: 1,
                },
            )
            .unwrap()
            .to_vec();

        assert_eq!(resized.len(), 224 * 224 * 3);
        assert_eq!(resizer.resized.capacity(), capacity);
    }

    fn fir_resize(
        rgb: &[u8],
        width: u32,
        height: u32,
        crop: PixelCrop,
        output_size: u32,
    ) -> Vec<u8> {
        let source = FirImageRef::new(width, height, rgb, PixelType::U8x3).unwrap();
        let source = CroppedImage::new(&source, crop.x, crop.y, crop.width, crop.height).unwrap();
        let mut output = FirImage::new(output_size, output_size, PixelType::U8x3);
        let options =
            ResizeOptions::new().resize_alg(ResizeAlg::Interpolation(FilterType::Bilinear));
        Resizer::new()
            .resize(&source, &mut output, Some(&options))
            .unwrap();
        output.into_vec()
    }

    fn materialize_rotated_crop(
        rgb: &[u8],
        image_width: u32,
        region: PixelCrop,
        crop: PixelCrop,
        angle: f64,
        center_x: f64,
        center_y: f64,
    ) -> Vec<u8> {
        let cos = angle.cos();
        let sin = angle.sin();
        let mut output = Vec::with_capacity((crop.width * crop.height * 3) as usize);
        for y in crop.y..crop.y + crop.height {
            for x in crop.x..crop.x + crop.width {
                let dx = f64::from(x) - center_x;
                let dy = f64::from(y) - center_y;
                let source_x = cos * dx + sin * dy + center_x;
                let source_y = -sin * dx + cos * dy + center_y;
                output.extend_from_slice(&sample_region(
                    rgb,
                    image_width,
                    region,
                    source_x,
                    source_y,
                ));
            }
        }
        output
    }

    fn sample_region(rgb: &[u8], image_width: u32, region: PixelCrop, x: f64, y: f64) -> [u8; 3] {
        let x = x.clamp(0.0, f64::from(region.width - 1));
        let y = y.clamp(0.0, f64::from(region.height - 1));
        let x0 = x.floor() as u32;
        let y0 = y.floor() as u32;
        let x1 = (x0 + 1).min(region.width - 1);
        let y1 = (y0 + 1).min(region.height - 1);
        let x_weight = (x - x.floor()) as f32;
        let y_weight = (y - y.floor()) as f32;
        let pixel = |x: u32, y: u32| {
            let index = (((region.y + y) * image_width + region.x + x) * 3) as usize;
            [rgb[index], rgb[index + 1], rgb[index + 2]]
        };
        let top_left = pixel(x0, y0);
        let top_right = pixel(x1, y0);
        let bottom_left = pixel(x0, y1);
        let bottom_right = pixel(x1, y1);
        let mut output = [0; 3];
        for channel in 0..3 {
            let value = top_left[channel] as f32 * (1.0 - x_weight) * (1.0 - y_weight)
                + top_right[channel] as f32 * x_weight * (1.0 - y_weight)
                + bottom_left[channel] as f32 * (1.0 - x_weight) * y_weight
                + bottom_right[channel] as f32 * x_weight * y_weight;
            output[channel] = value.round().clamp(0.0, 255.0) as u8;
        }
        output
    }

    fn test_image(width: u32, height: u32) -> DecodedImage {
        let mut rgb = Vec::with_capacity((width * height * 3) as usize);
        for y in 0..height {
            for x in 0..width {
                rgb.push(((x * 17 + y * 29) % 256) as u8);
                rgb.push(((x * 47 + y * 11 + 31) % 256) as u8);
                rgb.push(((x * 7 + y * 53 + 97) % 256) as u8);
            }
        }
        DecodedImage {
            dimensions: Dimensions { width, height },
            rgb,
        }
    }

    fn smooth_test_image(width: u32, height: u32) -> DecodedImage {
        let mut rgb = Vec::with_capacity((width * height * 3) as usize);
        for y in 0..height {
            for x in 0..width {
                rgb.push((x * 2 + y * 3) as u8);
                rgb.push((x * 3 + y * 2 + 7) as u8);
                rgb.push((x + y * 4 + 11) as u8);
            }
        }
        DecodedImage {
            dimensions: Dimensions { width, height },
            rgb,
        }
    }

    fn assert_max_delta(actual: &[u8], expected: &[u8], allowed: u8) {
        assert_eq!(actual.len(), expected.len());
        let max_delta = actual
            .iter()
            .zip(expected)
            .map(|(&actual, &expected)| actual.abs_diff(expected))
            .max()
            .unwrap_or(0);
        assert!(
            max_delta <= allowed,
            "maximum pixel delta {max_delta} exceeds {allowed}"
        );
    }
}
