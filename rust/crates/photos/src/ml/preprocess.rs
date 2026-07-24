use fast_image_resize::{
    FilterType, PixelType, ResizeAlg, ResizeOptions, Resizer,
    images::{Image as FirImage, ImageRef as FirImageRef},
};

use crate::ml::{
    clip::CLIP_IMAGE_INPUT_SIZE,
    error::{MlError, MlResult},
    onnx::PreparedF32Input,
    types::DecodedImage,
};

pub(crate) const YOLO_INPUT_SIZE: usize = 640;
const PAD_VALUE: f32 = 114.0;
const NORMALIZATION_SCALE: f32 = 1.0 / 255.0;

pub(crate) struct YoloInput {
    pub(crate) tensor: PreparedF32Input,
    pub(crate) scaled_width: usize,
    pub(crate) scaled_height: usize,
    pub(crate) pad_left: usize,
    pub(crate) pad_top: usize,
}

impl YoloInput {
    pub(crate) fn correct_box(&self, box_xyxy: &mut [f32; 4]) {
        if self.has_identity_geometry() {
            return;
        }
        self.correct_box_with_padding(box_xyxy);
    }

    pub(crate) fn correct_box_and_keypoints<const N: usize>(
        &self,
        box_xyxy: &mut [f32; 4],
        keypoints: &mut [[f32; 2]; N],
    ) {
        if self.has_identity_geometry() {
            return;
        }

        self.correct_box_with_padding(box_xyxy);
        for point in keypoints {
            point[0] = self.original_x(point[0]);
            point[1] = self.original_y(point[1]);
        }
    }

    fn has_identity_geometry(&self) -> bool {
        self.scaled_width == YOLO_INPUT_SIZE
            && self.scaled_height == YOLO_INPUT_SIZE
            && self.pad_left == 0
            && self.pad_top == 0
    }

    fn correct_box_with_padding(&self, box_xyxy: &mut [f32; 4]) {
        box_xyxy[0] = self.original_x(box_xyxy[0]);
        box_xyxy[1] = self.original_y(box_xyxy[1]);
        box_xyxy[2] = self.original_x(box_xyxy[2]);
        box_xyxy[3] = self.original_y(box_xyxy[3]);
    }

    fn original_x(&self, x: f32) -> f32 {
        ((x * YOLO_INPUT_SIZE as f32 - self.pad_left as f32) / self.scaled_width as f32)
            .clamp(0.0, 1.0)
    }

    fn original_y(&self, y: f32) -> f32 {
        ((y * YOLO_INPUT_SIZE as f32 - self.pad_top as f32) / self.scaled_height as f32)
            .clamp(0.0, 1.0)
    }
}

pub(crate) fn preprocess_yolo(decoded: &DecodedImage) -> MlResult<YoloInput> {
    if decoded.dimensions.width == 0 || decoded.dimensions.height == 0 {
        return Err(MlError::Preprocess(
            "image dimensions cannot be zero".to_string(),
        ));
    }

    let src_w = decoded.dimensions.width as f32;
    let src_h = decoded.dimensions.height as f32;
    let scale = (YOLO_INPUT_SIZE as f32 / src_w).min(YOLO_INPUT_SIZE as f32 / src_h);
    let scaled_width = (src_w * scale).round().clamp(1.0, YOLO_INPUT_SIZE as f32) as u32;
    let scaled_height = (src_h * scale).round().clamp(1.0, YOLO_INPUT_SIZE as f32) as u32;

    let src_image = FirImageRef::new(
        decoded.dimensions.width,
        decoded.dimensions.height,
        decoded.rgb.as_slice(),
        PixelType::U8x3,
    )
    .map_err(|e| MlError::Preprocess(format!("failed to create FIR source image: {e}")))?;

    let mut resized_image = FirImage::new(scaled_width, scaled_height, PixelType::U8x3);
    let mut resizer = Resizer::new();
    let options = ResizeOptions::new().resize_alg(ResizeAlg::Interpolation(FilterType::Bilinear));
    resizer
        .resize(&src_image, &mut resized_image, Some(&options))
        .map_err(|e| MlError::Preprocess(format!("failed to resize YOLO image input: {e}")))?;

    let scaled_width_usize = scaled_width as usize;
    let scaled_height_usize = scaled_height as usize;
    let pad_left = (YOLO_INPUT_SIZE.saturating_sub(scaled_width_usize)) / 2;
    let pad_top = (YOLO_INPUT_SIZE.saturating_sub(scaled_height_usize)) / 2;

    let pad_norm = PAD_VALUE * NORMALIZATION_SCALE;
    let mut output = vec![pad_norm; 3 * YOLO_INPUT_SIZE * YOLO_INPUT_SIZE];
    let green_offset = YOLO_INPUT_SIZE * YOLO_INPUT_SIZE;
    let blue_offset = 2 * YOLO_INPUT_SIZE * YOLO_INPUT_SIZE;
    let resized = resized_image.buffer();

    for y in 0..scaled_height_usize {
        for x in 0..scaled_width_usize {
            let src_idx = (y * scaled_width_usize + x) * 3;
            let dst_x = x + pad_left;
            let dst_y = y + pad_top;
            let dst_idx = dst_y * YOLO_INPUT_SIZE + dst_x;

            output[dst_idx] = resized[src_idx] as f32 * NORMALIZATION_SCALE;
            output[dst_idx + green_offset] = resized[src_idx + 1] as f32 * NORMALIZATION_SCALE;
            output[dst_idx + blue_offset] = resized[src_idx + 2] as f32 * NORMALIZATION_SCALE;
        }
    }

    Ok(YoloInput {
        tensor: PreparedF32Input::new(output),
        scaled_width: scaled_width_usize,
        scaled_height: scaled_height_usize,
        pad_left,
        pad_top,
    })
}

pub(crate) fn preprocess_clip(decoded: &DecodedImage) -> MlResult<Vec<f32>> {
    if decoded.dimensions.width == 0 || decoded.dimensions.height == 0 {
        return Err(MlError::Preprocess(
            "image dimensions cannot be zero".to_string(),
        ));
    }

    let src_w = decoded.dimensions.width as f32;
    let src_h = decoded.dimensions.height as f32;
    let scale = (CLIP_IMAGE_INPUT_SIZE as f32 / src_w).max(CLIP_IMAGE_INPUT_SIZE as f32 / src_h);
    let scaled_width = (src_w * scale).round().max(CLIP_IMAGE_INPUT_SIZE as f32) as u32;
    let scaled_height = (src_h * scale).round().max(CLIP_IMAGE_INPUT_SIZE as f32) as u32;

    let src_image = FirImageRef::new(
        decoded.dimensions.width,
        decoded.dimensions.height,
        decoded.rgb.as_slice(),
        PixelType::U8x3,
    )
    .map_err(|e| MlError::Preprocess(format!("failed to create FIR source image: {e}")))?;

    let start_x = (scaled_width.saturating_sub(CLIP_IMAGE_INPUT_SIZE as u32) / 2) as f64;
    let start_y = (scaled_height.saturating_sub(CLIP_IMAGE_INPUT_SIZE as u32) / 2) as f64;
    let horizontal_scale = decoded.dimensions.width as f64 / scaled_width as f64;
    let vertical_scale = decoded.dimensions.height as f64 / scaled_height as f64;
    let crop_left = start_x * horizontal_scale;
    let crop_top = start_y * vertical_scale;
    let crop_width = CLIP_IMAGE_INPUT_SIZE as f64 * horizontal_scale;
    let crop_height = CLIP_IMAGE_INPUT_SIZE as f64 * vertical_scale;

    let mut resized_image = FirImage::new(
        CLIP_IMAGE_INPUT_SIZE as u32,
        CLIP_IMAGE_INPUT_SIZE as u32,
        PixelType::U8x3,
    );
    let mut resizer = Resizer::new();
    let options = ResizeOptions::new()
        .resize_alg(ResizeAlg::Convolution(FilterType::Bilinear))
        .crop(crop_left, crop_top, crop_width, crop_height);
    resizer
        .resize(&src_image, &mut resized_image, Some(&options))
        .map_err(|e| MlError::Preprocess(format!("failed to resize CLIP image input: {e}")))?;

    let resized = resized_image.buffer();

    let mut output = vec![0f32; 3 * CLIP_IMAGE_INPUT_SIZE * CLIP_IMAGE_INPUT_SIZE];
    let green_offset = CLIP_IMAGE_INPUT_SIZE * CLIP_IMAGE_INPUT_SIZE;
    let blue_offset = 2 * CLIP_IMAGE_INPUT_SIZE * CLIP_IMAGE_INPUT_SIZE;

    for y in 0..CLIP_IMAGE_INPUT_SIZE {
        for x in 0..CLIP_IMAGE_INPUT_SIZE {
            let src_idx = (y * CLIP_IMAGE_INPUT_SIZE + x) * 3;
            let dst_idx = y * CLIP_IMAGE_INPUT_SIZE + x;
            output[dst_idx] = resized[src_idx] as f32 * NORMALIZATION_SCALE;
            output[dst_idx + green_offset] = resized[src_idx + 1] as f32 * NORMALIZATION_SCALE;
            output[dst_idx + blue_offset] = resized[src_idx + 2] as f32 * NORMALIZATION_SCALE;
        }
    }

    Ok(output)
}

#[cfg(test)]
mod tests {
    use fast_image_resize::{
        FilterType, PixelType, ResizeAlg, ResizeOptions, Resizer,
        images::{Image as FirImage, ImageRef as FirImageRef},
    };

    use super::{YOLO_INPUT_SIZE, YoloInput, preprocess_clip};
    use crate::ml::{
        clip::CLIP_IMAGE_INPUT_SIZE,
        error::{MlError, MlResult},
        onnx::PreparedF32Input,
        types::{DecodedImage, Dimensions},
    };

    #[test]
    fn yolo_geometry_matches_the_previous_letterbox_correction() {
        let input = YoloInput {
            tensor: PreparedF32Input::new(Vec::new()),
            scaled_width: YOLO_INPUT_SIZE,
            scaled_height: 320,
            pad_left: 0,
            pad_top: 160,
        };
        let mut actual_box = [0.1, 0.25, 0.9, 0.75];
        let mut actual_keypoints = [[0.2, 0.3], [0.5, 0.5], [0.8, 0.7]];
        let mut expected_box = actual_box;
        let mut expected_keypoints = actual_keypoints;

        legacy_correct_geometry(
            &mut expected_box,
            &mut expected_keypoints,
            input.scaled_width,
            input.scaled_height,
            input.pad_left,
            input.pad_top,
        );
        input.correct_box_and_keypoints(&mut actual_box, &mut actual_keypoints);

        assert_eq!(actual_box, expected_box);
        assert_eq!(actual_keypoints, expected_keypoints);
    }

    #[test]
    fn yolo_identity_geometry_does_not_round_coordinates() {
        let input = YoloInput {
            tensor: PreparedF32Input::new(Vec::new()),
            scaled_width: YOLO_INPUT_SIZE,
            scaled_height: YOLO_INPUT_SIZE,
            pad_left: 0,
            pad_top: 0,
        };
        let expected_box = [0.123_456_7, 0.234_567_8, 0.765_432_1, 0.876_543_2];
        let expected_keypoints = [[0.111_111_1, 0.222_222_2]];
        let mut actual_box = expected_box;
        let mut actual_keypoints = expected_keypoints;

        input.correct_box_and_keypoints(&mut actual_box, &mut actual_keypoints);

        assert_eq!(actual_box, expected_box);
        assert_eq!(actual_keypoints, expected_keypoints);
    }

    fn legacy_correct_geometry<const N: usize>(
        box_xyxy: &mut [f32; 4],
        keypoints: &mut [[f32; 2]; N],
        scaled_width: usize,
        scaled_height: usize,
        pad_left: usize,
        pad_top: usize,
    ) {
        let scaled_width = scaled_width as f32;
        let scaled_height = scaled_height as f32;
        let pad_left = pad_left as f32;
        let pad_top = pad_top as f32;
        let transform_x =
            |x: f32| ((x * YOLO_INPUT_SIZE as f32 - pad_left) / scaled_width).clamp(0.0, 1.0);
        let transform_y =
            |y: f32| ((y * YOLO_INPUT_SIZE as f32 - pad_top) / scaled_height).clamp(0.0, 1.0);

        box_xyxy[0] = transform_x(box_xyxy[0]);
        box_xyxy[1] = transform_y(box_xyxy[1]);
        box_xyxy[2] = transform_x(box_xyxy[2]);
        box_xyxy[3] = transform_y(box_xyxy[3]);
        for point in keypoints {
            point[0] = transform_x(point[0]);
            point[1] = transform_y(point[1]);
        }
    }

    #[test]
    fn direct_clip_crop_matches_resize_then_crop() {
        for (width, height) in [
            (256, 256),
            (257, 257),
            (101, 17),
            (17, 101),
            (513, 257),
            (257, 513),
            (403, 301),
            (301, 403),
        ] {
            let decoded = test_image(width, height);
            assert_eq!(
                preprocess_clip(&decoded).unwrap(),
                legacy_preprocess_clip(&decoded).unwrap(),
                "CLIP preprocessing changed for {width}x{height}"
            );
        }
    }

    fn test_image(width: u32, height: u32) -> DecodedImage {
        let mut rgb = Vec::with_capacity(width as usize * height as usize * 3);
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

    fn legacy_preprocess_clip(decoded: &DecodedImage) -> MlResult<Vec<f32>> {
        let src_w = decoded.dimensions.width as f32;
        let src_h = decoded.dimensions.height as f32;
        let scale =
            (CLIP_IMAGE_INPUT_SIZE as f32 / src_w).max(CLIP_IMAGE_INPUT_SIZE as f32 / src_h);
        let scaled_width = (src_w * scale).round().max(CLIP_IMAGE_INPUT_SIZE as f32) as u32;
        let scaled_height = (src_h * scale).round().max(CLIP_IMAGE_INPUT_SIZE as f32) as u32;
        let source = FirImageRef::new(
            decoded.dimensions.width,
            decoded.dimensions.height,
            &decoded.rgb,
            PixelType::U8x3,
        )
        .map_err(|error| MlError::Preprocess(error.to_string()))?;
        let mut resized = FirImage::new(scaled_width, scaled_height, PixelType::U8x3);
        let options = ResizeOptions::new().resize_alg(ResizeAlg::Convolution(FilterType::Bilinear));
        Resizer::new()
            .resize(&source, &mut resized, Some(&options))
            .map_err(|error| MlError::Preprocess(error.to_string()))?;

        let start_x = (scaled_width as usize - CLIP_IMAGE_INPUT_SIZE) / 2;
        let start_y = (scaled_height as usize - CLIP_IMAGE_INPUT_SIZE) / 2;
        let pixel_count = CLIP_IMAGE_INPUT_SIZE * CLIP_IMAGE_INPUT_SIZE;
        let mut output = vec![0.0; 3 * pixel_count];
        for y in 0..CLIP_IMAGE_INPUT_SIZE {
            for x in 0..CLIP_IMAGE_INPUT_SIZE {
                let source = ((start_y + y) * scaled_width as usize + start_x + x) * 3;
                let destination = y * CLIP_IMAGE_INPUT_SIZE + x;
                output[destination] = resized.buffer()[source] as f32 * super::NORMALIZATION_SCALE;
                output[pixel_count + destination] =
                    resized.buffer()[source + 1] as f32 * super::NORMALIZATION_SCALE;
                output[2 * pixel_count + destination] =
                    resized.buffer()[source + 2] as f32 * super::NORMALIZATION_SCALE;
            }
        }
        Ok(output)
    }
}
