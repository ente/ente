use image::{Rgb, RgbImage};

use crate::ml::{
    error::{MlError, MlResult},
    types::{DecodedImage, PetAlignmentResult, PetFaceDetection, PetFaceResult, to_face_id},
};

use super::{
    PET_EMBEDDING_INPUT_SIZE, PET_SPECIES_CAT,
    preprocess::{PetFaceEmbeddingInputs, PixelCrop, RgbCropResizer, append_imagenet_tensor},
};

/// Minimum eye distance in pixels below which alignment is skipped.
const MIN_EYE_DISTANCE: f32 = 5.0;
/// Angle threshold in degrees; below this, skip rotation and just crop.
const ANGLE_SKIP_DEG: f32 = 1.0;
/// Expand factor applied to each side of the bounding box when cropping.
const CROP_EXPAND: f32 = 0.1;

/// Run pet face alignment using 3-point landmarks (left_eye, right_eye, nose).
///
/// Mirrors `pet_pipeline/detection.py` `_align_face()`:
///   1. Skip if eye distance < 5 px
///   2. If angle < 1°, crop bounding box directly (no rotation)
///   3. Otherwise rotate around face center, then crop with 10% expand
///   4. Resize to 224×224
///   5. Apply ImageNet normalization (CHW)
pub(crate) fn run_pet_face_alignment(
    file_id: i64,
    decoded: &DecodedImage,
    detections: Vec<PetFaceDetection>,
) -> MlResult<(PetFaceEmbeddingInputs, Vec<PetFaceResult>)> {
    let img_w = decoded.dimensions.width;
    let img_h = decoded.dimensions.height;
    let img_wf = img_w as f32;
    let img_hf = img_h as f32;

    let cat_capacity = detections
        .iter()
        .filter(|detection| detection.class_id == PET_SPECIES_CAT)
        .count();
    let dog_capacity = detections.len() - cat_capacity;
    let mut aligned_inputs = PetFaceEmbeddingInputs::new(dog_capacity, cat_capacity);
    let mut face_results = Vec::with_capacity(detections.len());
    let mut crop_resizer = RgbCropResizer::new(PET_EMBEDDING_INPUT_SIZE as u32);

    for detection in detections {
        // Convert relative keypoints to absolute
        let left_eye = [
            detection.keypoints[0][0] * img_wf,
            detection.keypoints[0][1] * img_hf,
        ];
        let right_eye = [
            detection.keypoints[1][0] * img_wf,
            detection.keypoints[1][1] * img_hf,
        ];

        let dx = right_eye[0] - left_eye[0];
        let dy = right_eye[1] - left_eye[1];
        let eye_dist = (dx * dx + dy * dy).sqrt();

        // Skip if eyes are too close together
        if eye_dist < MIN_EYE_DISTANCE {
            continue;
        }

        // Absolute bounding box (clamped to image bounds on both sides)
        let max_xf = (img_w as f32 - 1.0).max(0.0);
        let max_yf = (img_h as f32 - 1.0).max(0.0);
        let box_x1 = (detection.box_xyxy[0] * img_wf).clamp(0.0, max_xf) as i32;
        let box_y1 = (detection.box_xyxy[1] * img_hf).clamp(0.0, max_yf) as i32;
        let box_x2 = (detection.box_xyxy[2] * img_wf).clamp(0.0, img_wf) as i32;
        let box_y2 = (detection.box_xyxy[3] * img_hf).clamp(0.0, img_hf) as i32;

        let angle_deg = dy.atan2(dx).to_degrees();
        let angle_rad = dy.atan2(dx);

        let aligned_rgb = if angle_deg.abs() < ANGLE_SKIP_DEG {
            // No rotation needed — just crop the bounding box directly
            let cx1 = box_x1.max(0) as u32;
            let cy1 = box_y1.max(0) as u32;
            let cx2 = (box_x2 as u32).min(img_w);
            let cy2 = (box_y2 as u32).min(img_h);
            let crop_w = cx2.saturating_sub(cx1);
            let crop_h = cy2.saturating_sub(cy1);
            if crop_w == 0 || crop_h == 0 {
                continue;
            }
            crop_and_resize_decoded(&mut crop_resizer, decoded, cx1, cy1, crop_w, crop_h)?
        } else {
            // Rotate only a padded region around the face, not the full image.
            let bw = (box_x2 - box_x1) as f32;
            let bh = (box_y2 - box_y1) as f32;
            let pad = (bw.max(bh) * (CROP_EXPAND + 0.5)).ceil() as i32;

            let region_x1 = (box_x1 - pad).max(0) as u32;
            let region_y1 = (box_y1 - pad).max(0) as u32;
            let region_x2 = ((box_x2 + pad) as u32).min(img_w);
            let region_y2 = ((box_y2 + pad) as u32).min(img_h);
            let region_w = region_x2.saturating_sub(region_x1);
            let region_h = region_y2.saturating_sub(region_y1);
            if region_w == 0 || region_h == 0 {
                continue;
            }

            let region = RgbRegion::new(decoded, region_x1, region_y1, region_w, region_h)?;

            // Face center relative to the extracted region
            let local_cx = (box_x1 + box_x2) as f64 / 2.0 - region_x1 as f64;
            let local_cy = (box_y1 + box_y2) as f64 / 2.0 - region_y1 as f64;

            // Crop coordinates relative to the region
            let nx1 = (box_x1 as f32 - bw * CROP_EXPAND - region_x1 as f32).max(0.0) as u32;
            let ny1 = (box_y1 as f32 - bh * CROP_EXPAND - region_y1 as f32).max(0.0) as u32;
            let nx2 =
                (box_x2 as f32 + bw * CROP_EXPAND - region_x1 as f32).min(region_w as f32) as u32;
            let ny2 =
                (box_y2 as f32 + bh * CROP_EXPAND - region_y1 as f32).min(region_h as f32) as u32;
            let crop_w = nx2.saturating_sub(nx1);
            let crop_h = ny2.saturating_sub(ny1);
            if crop_w == 0 || crop_h == 0 {
                continue;
            }
            let rotated_crop = rotate_crop_around_center(
                &region,
                angle_rad as f64,
                local_cx,
                local_cy,
                PixelCrop {
                    x: nx1,
                    y: ny1,
                    width: crop_w,
                    height: crop_h,
                },
            );
            crop_and_resize_rgb(&mut crop_resizer, &rotated_crop, 0, 0, crop_w, crop_h)?
        };

        let result_index = face_results.len();
        let batch = aligned_inputs.batch_mut(detection.class_id);
        append_imagenet_tensor(aligned_rgb, &mut batch.input);
        batch.indices.push(result_index);

        let base_id = to_face_id(file_id, detection.box_xyxy);
        let pet_face_id = format!("{base_id}_c{}", detection.class_id);

        let center_x = (left_eye[0] + right_eye[0]) / 2.0;
        let center_y = (left_eye[1] + right_eye[1]) / 2.0;
        let box_w = (box_x2 - box_x1) as f32;
        let box_h = (box_y2 - box_y1) as f32;
        let crop_size = box_w.max(box_h) * (1.0 + 2.0 * CROP_EXPAND);

        let alignment = PetAlignmentResult {
            center: [center_x, center_y],
            angle: angle_rad,
            crop_size,
        };

        face_results.push(PetFaceResult {
            species: detection.class_id,
            detection,
            face_embedding: Vec::new(),
            pet_face_id,
            alignment,
        });
    }

    Ok((aligned_inputs, face_results))
}

/// Render a crop of an image rotated around a center point using bilinear
/// interpolation with BORDER_REPLICATE behaviour.
fn rotate_crop_around_center(
    source: &RgbRegion<'_>,
    angle_rad: f64,
    cx: f64,
    cy: f64,
    crop: PixelCrop,
) -> RgbImage {
    let cos_a = angle_rad.cos();
    let sin_a = angle_rad.sin();

    // Build forward rotation matrix (output -> input):
    //   x_in = cos_a * (x_out - cx) + sin_a * (y_out - cy) + cx
    //   y_in = -sin_a * (x_out - cx) + cos_a * (y_out - cy) + cy

    let mut output = RgbImage::new(crop.width, crop.height);
    let w_f = source.width as f64;
    let h_f = source.height as f64;

    for crop_y in 0..crop.height {
        let out_y = crop.y + crop_y;
        for crop_x in 0..crop.width {
            let out_x = crop.x + crop_x;
            let dx = out_x as f64 - cx;
            let dy = out_y as f64 - cy;
            let src_x = cos_a * dx + sin_a * dy + cx;
            let src_y = -sin_a * dx + cos_a * dy + cy;

            // BORDER_REPLICATE: clamp to valid range
            let sx = src_x.max(0.0).min(w_f - 1.0);
            let sy = src_y.max(0.0).min(h_f - 1.0);

            // Bilinear interpolation
            let x0 = sx.floor() as u32;
            let y0 = sy.floor() as u32;
            let x1 = (x0 + 1).min(source.width - 1);
            let y1 = (y0 + 1).min(source.height - 1);
            let fx = (sx - sx.floor()) as f32;
            let fy = (sy - sy.floor()) as f32;

            let p00 = source.get_pixel(x0, y0);
            let p10 = source.get_pixel(x1, y0);
            let p01 = source.get_pixel(x0, y1);
            let p11 = source.get_pixel(x1, y1);

            let mut px = [0u8; 3];
            for c in 0..3 {
                let v = p00[c] as f32 * (1.0 - fx) * (1.0 - fy)
                    + p10[c] as f32 * fx * (1.0 - fy)
                    + p01[c] as f32 * (1.0 - fx) * fy
                    + p11[c] as f32 * fx * fy;
                px[c] = v.round().clamp(0.0, 255.0) as u8;
            }
            output.put_pixel(crop_x, crop_y, Rgb(px));
        }
    }

    output
}

/// Crop a region from an RGB image and resize to 224×224 using bilinear interpolation.
fn crop_and_resize_rgb<'a>(
    resizer: &'a mut RgbCropResizer,
    source: &RgbImage,
    x: u32,
    y: u32,
    w: u32,
    h: u32,
) -> MlResult<&'a [u8]> {
    let src_w = source.width();
    let src_h = source.height();
    // Clamp crop region to source bounds to avoid edge-replication artifacts.
    let clamped_w = w.min(src_w.saturating_sub(x));
    let clamped_h = h.min(src_h.saturating_sub(y));
    if clamped_w == 0 || clamped_h == 0 {
        return Err(MlError::Preprocess(
            "crop_and_resize_rgb: crop region extends beyond source image".to_string(),
        ));
    }
    resize_crop(
        resizer,
        source.as_raw(),
        src_w,
        src_h,
        PixelCrop {
            x,
            y,
            width: clamped_w,
            height: clamped_h,
        },
    )
}

/// Crop directly from decoded image bytes and resize — avoids building a
/// full-size RgbImage when no rotation is needed.
fn crop_and_resize_decoded<'a>(
    resizer: &'a mut RgbCropResizer,
    decoded: &DecodedImage,
    x: u32,
    y: u32,
    w: u32,
    h: u32,
) -> MlResult<&'a [u8]> {
    resize_crop(
        resizer,
        &decoded.rgb,
        decoded.dimensions.width,
        decoded.dimensions.height,
        PixelCrop {
            x,
            y,
            width: w,
            height: h,
        },
    )
}

fn resize_crop<'a>(
    resizer: &'a mut RgbCropResizer,
    rgb: &[u8],
    source_width: u32,
    source_height: u32,
    crop: PixelCrop,
) -> MlResult<&'a [u8]> {
    resizer.resize(rgb, source_width, source_height, crop)
}

/// A row-strided view into a rectangular region of the decoded RGB buffer.
struct RgbRegion<'a> {
    rgb: &'a [u8],
    image_width: usize,
    x: u32,
    y: u32,
    width: u32,
    height: u32,
}

impl<'a> RgbRegion<'a> {
    fn new(decoded: &'a DecodedImage, x: u32, y: u32, width: u32, height: u32) -> MlResult<Self> {
        if width == 0
            || height == 0
            || x > decoded.dimensions.width.saturating_sub(width)
            || y > decoded.dimensions.height.saturating_sub(height)
        {
            return Err(MlError::Preprocess(
                "RGB region extends beyond decoded image".to_string(),
            ));
        }
        let expected_len = (decoded.dimensions.width as usize)
            .checked_mul(decoded.dimensions.height as usize)
            .and_then(|pixels| pixels.checked_mul(3))
            .ok_or_else(|| MlError::Preprocess("decoded RGB dimensions overflow".to_string()))?;
        if decoded.rgb.len() < expected_len {
            return Err(MlError::Preprocess(
                "decoded RGB buffer is shorter than its dimensions".to_string(),
            ));
        }

        Ok(Self {
            rgb: &decoded.rgb,
            image_width: decoded.dimensions.width as usize,
            x,
            y,
            width,
            height,
        })
    }

    #[inline]
    fn get_pixel(&self, x: u32, y: u32) -> [u8; 3] {
        let pixel = ((self.y + y) as usize * self.image_width + (self.x + x) as usize) * 3;
        [self.rgb[pixel], self.rgb[pixel + 1], self.rgb[pixel + 2]]
    }
}

#[cfg(test)]
mod tests {
    use super::{PixelCrop, RgbRegion, rotate_crop_around_center};
    use crate::ml::types::{DecodedImage, Dimensions};

    #[test]
    fn cropped_rotation_matches_the_same_region_of_a_full_rotation() {
        let decoded = DecodedImage {
            dimensions: Dimensions {
                width: 11,
                height: 9,
            },
            rgb: (0..11 * 9 * 3).map(|value| (value % 251) as u8).collect(),
        };
        let source = RgbRegion::new(&decoded, 1, 1, 9, 7).unwrap();
        let crop = PixelCrop {
            x: 2,
            y: 1,
            width: 5,
            height: 4,
        };

        let full = rotate_crop_around_center(
            &source,
            0.37,
            4.25,
            3.75,
            PixelCrop {
                x: 0,
                y: 0,
                width: source.width,
                height: source.height,
            },
        );
        let cropped = rotate_crop_around_center(&source, 0.37, 4.25, 3.75, crop);

        for y in 0..crop.height {
            for x in 0..crop.width {
                assert_eq!(
                    cropped.get_pixel(x, y),
                    full.get_pixel(crop.x + x, crop.y + y)
                );
            }
        }
    }
}
