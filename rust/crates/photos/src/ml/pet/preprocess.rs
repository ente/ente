use fast_image_resize::{
    FilterType, PixelType, ResizeAlg, ResizeOptions, Resizer,
    images::{CroppedImage, Image as FirImage, ImageRef as FirImageRef},
};

use crate::ml::{
    error::{MlError, MlResult},
    types::DecodedImage,
};

use super::{PET_EMBEDDING_CHANNELS, PET_EMBEDDING_INPUT_SIZE, PET_SPECIES_CAT};

// ImageNet normalization constants
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

/// Preprocess a cropped pet face/body image for embedding extraction.
///
/// Steps:
///   1. Resize to 224x224 using bilinear interpolation
///   2. Normalize using ImageNet mean/std
///   3. Output CHW layout as float32
///
/// This mirrors the Python pipeline's preprocessing:
/// ```python
/// img = cv2.resize(crop, (224, 224))
/// img = img / 255.0
/// img = (img - IMAGENET_MEAN) / IMAGENET_STD
/// img = img.transpose(2, 0, 1)  # HWC -> CHW
/// ```
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
        let resized = self.crop_resizer.resize(
            &decoded.rgb,
            decoded.dimensions.width,
            decoded.dimensions.height,
            crop,
        )?;
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
        return Err(MlError::Preprocess("crop region has zero area".to_string()));
    }

    Ok(PixelCrop {
        x: x1,
        y: y1,
        width,
        height,
    })
}

/// Resizes row-strided crop views while retaining FIR's internal workspace.
pub(super) struct RgbCropResizer {
    resizer: Resizer,
    resized: FirImage<'static>,
    options: ResizeOptions,
}

impl RgbCropResizer {
    pub(super) fn new(output_size: u32) -> Self {
        Self {
            resizer: Resizer::new(),
            resized: FirImage::new(output_size, output_size, PixelType::U8x3),
            options: ResizeOptions::new()
                .resize_alg(ResizeAlg::Interpolation(FilterType::Bilinear)),
        }
    }

    pub(super) fn resize(
        &mut self,
        rgb: &[u8],
        source_width: u32,
        source_height: u32,
        crop: PixelCrop,
    ) -> MlResult<&[u8]> {
        if crop.width == 0 || crop.height == 0 {
            return Err(MlError::Preprocess(
                "crop dimensions cannot be zero".to_string(),
            ));
        }
        if crop.x > source_width.saturating_sub(crop.width)
            || crop.y > source_height.saturating_sub(crop.height)
        {
            return Err(MlError::Preprocess(
                "crop region extends beyond source image".to_string(),
            ));
        }

        let source = FirImageRef::new(source_width, source_height, rgb, PixelType::U8x3)
            .map_err(|e| MlError::Preprocess(format!("failed to create FIR source image: {e}")))?;
        let source = CroppedImage::new(&source, crop.x, crop.y, crop.width, crop.height)
            .map_err(|e| MlError::Preprocess(format!("failed to create FIR crop view: {e}")))?;
        self.resizer
            .resize(&source, &mut self.resized, Some(&self.options))
            .map_err(|e| MlError::Preprocess(format!("failed to resize RGB crop: {e}")))?;

        Ok(self.resized.buffer())
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
    use super::{PixelCrop, RgbCropResizer};

    #[test]
    fn cropped_view_resize_matches_a_materialized_crop() {
        let width = 6u32;
        let height = 5u32;
        let rgb = (0..(width * height * 3))
            .map(|value| (value % 251) as u8)
            .collect::<Vec<_>>();
        let crop = PixelCrop {
            x: 1,
            y: 1,
            width: 4,
            height: 3,
        };

        let direct = RgbCropResizer::new(7)
            .resize(&rgb, width, height, crop)
            .unwrap()
            .to_vec();

        let mut materialized = Vec::new();
        for row in crop.y..crop.y + crop.height {
            let start = ((row * width + crop.x) * 3) as usize;
            let end = start + (crop.width * 3) as usize;
            materialized.extend_from_slice(&rgb[start..end]);
        }
        let baseline = RgbCropResizer::new(7)
            .resize(
                &materialized,
                crop.width,
                crop.height,
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
}
