use crate::{
    error::MlResult,
    types::{DecodedImage, PetAlignmentResult, PetFaceDetection, PetFaceResult, to_face_id},
};

use super::{
    PET_EMBEDDING_INPUT_SIZE, PET_SPECIES_CAT,
    preprocess::{PetFaceEmbeddingInputs, PixelCrop, RgbCropResizer, append_imagenet_tensor},
};

const MIN_EYE_DISTANCE: f32 = 5.0;
const ANGLE_SKIP_DEG: f32 = 1.0;
const CROP_EXPAND: f32 = 0.1;

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

        if eye_dist < MIN_EYE_DISTANCE {
            continue;
        }

        let max_xf = (img_w as f32 - 1.0).max(0.0);
        let max_yf = (img_h as f32 - 1.0).max(0.0);
        let box_x1 = (detection.box_xyxy[0] * img_wf).clamp(0.0, max_xf) as i32;
        let box_y1 = (detection.box_xyxy[1] * img_hf).clamp(0.0, max_yf) as i32;
        let box_x2 = (detection.box_xyxy[2] * img_wf).clamp(0.0, img_wf) as i32;
        let box_y2 = (detection.box_xyxy[3] * img_hf).clamp(0.0, img_hf) as i32;

        let angle_deg = dy.atan2(dx).to_degrees();
        let angle_rad = dy.atan2(dx);

        let aligned_rgb = if angle_deg.abs() < ANGLE_SKIP_DEG {
            let cx1 = box_x1.max(0) as u32;
            let cy1 = box_y1.max(0) as u32;
            let cx2 = (box_x2 as u32).min(img_w);
            let cy2 = (box_y2 as u32).min(img_h);
            let crop_w = cx2.saturating_sub(cx1);
            let crop_h = cy2.saturating_sub(cy1);
            if crop_w == 0 || crop_h == 0 {
                continue;
            }
            crop_resizer.resize(
                decoded,
                PixelCrop {
                    x: cx1,
                    y: cy1,
                    width: crop_w,
                    height: crop_h,
                },
            )?
        } else {
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

            let local_cx = (box_x1 + box_x2) as f64 / 2.0 - region_x1 as f64;
            let local_cy = (box_y1 + box_y2) as f64 / 2.0 - region_y1 as f64;

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
            crop_resizer.resize_rotated(
                decoded,
                PixelCrop {
                    x: region_x1,
                    y: region_y1,
                    width: region_w,
                    height: region_h,
                },
                PixelCrop {
                    x: nx1,
                    y: ny1,
                    width: crop_w,
                    height: crop_h,
                },
                angle_rad as f64,
                [local_cx, local_cy],
            )?
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
