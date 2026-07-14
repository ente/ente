use crate::ml::{
    error::{MlError, MlResult},
    onnx, preprocess,
    runtime::MlRuntimeView,
    types::{DecodedImage, PetBodyDetection, PetFaceDetection},
};

const INPUT_WIDTH: f32 = 640.0;
const INPUT_HEIGHT: f32 = 640.0;

// Pet face detection thresholds (from Python config)
const PET_FACE_IOU_THRESHOLD: f32 = 0.5;
const PET_FACE_MIN_SCORE: f32 = 0.3;

// Body detection thresholds
const BODY_IOU_THRESHOLD: f32 = 0.5;
const BODY_MIN_SCORE: f32 = 0.3;

// COCO class IDs (used by body detection)
const COCO_CAT: u8 = 15;
const COCO_DOG: u8 = 16;

// Species IDs used across both Rust and Dart:
//   0 = dog (face detection class_id=0, COCO_DOG=16)
//   1 = cat (face detection class_id=1, COCO_CAT=15)
// Dart maps COCO → species via: cocoClass == 15 ? 1 : 0

/// Run pet face detection using YOLOv5-face model with 3 keypoints.
///
/// Output format per row: [x, y, w, h, obj_conf, lx, ly, rx, ry, nx, ny, ...]
/// 3 keypoints: left_eye, right_eye, nose (6 values for coords).
///
/// This mirrors `pet_pipeline/detection.py` `FaceDetector.detect()`.
pub fn run_pet_face_detection(
    runtime: &MlRuntimeView<'_>,
    decoded: &DecodedImage,
) -> MlResult<Vec<PetFaceDetection>> {
    let (input, scaled_width, scaled_height, pad_left, pad_top) =
        preprocess::preprocess_yolo(decoded)?;

    let mut pet_face_detection = runtime.pet_face_detection_session()?;
    let (output_shape, output_data) = onnx::run_f32(
        &mut pet_face_detection,
        input,
        [1, 3, INPUT_HEIGHT as i64, INPUT_WIDTH as i64],
    )?;

    // Row format: [x, y, w, h, conf, lm_x1, lm_y1, lm_x2, lm_y2, lm_x3, lm_y3, cls0, cls1]
    // row_len = 4 + 1 + 6 + 2 = 13 for 2-class model
    // Use the output shape's last dimension to determine row length reliably.
    let row_len = if output_shape.len() >= 2 {
        *output_shape.last().unwrap() as usize
    } else if output_shape.len() == 1 {
        // Flat output: total_elements, must infer row_len.
        // Prefer 13 (2-class model) as the expected format, then fall back.
        let total = output_data.len();
        let inferred = if total % 13 == 0 {
            13
        } else if total % 12 == 0 {
            12
        } else if total % 11 == 0 {
            11
        } else {
            return Err(MlError::Postprocess(format!(
                "unexpected pet face detector output size: {} (shape: {:?})",
                total, output_shape
            )));
        };
        // Warn if the total is ambiguously divisible by multiple candidates.
        let candidates = [11usize, 12, 13];
        let valid_count = candidates.iter().filter(|&&c| total % c == 0).count();
        if valid_count > 1 {
            eprintln!(
                "[ml][pet] WARNING: flat output len={total} is divisible by {valid_count} row-length candidates; using {inferred}. \
                 Prefer a model with 2D output shape for reliability."
            );
        }
        inferred
    } else {
        return Err(MlError::Postprocess(
            "pet face detector output shape is empty".to_string(),
        ));
    };
    if row_len < 11 || output_data.len() < row_len {
        return Err(MlError::Postprocess(format!(
            "pet face detector row_len={} too small or output too short (len={})",
            row_len,
            output_data.len()
        )));
    }

    let detection_rows = output_data.len() / row_len;
    let mut detections = Vec::with_capacity(detection_rows);

    for i in 0..detection_rows {
        let start = i * row_len;
        let row = &output_data[start..(start + row_len)];
        let score = row[4];
        if score < PET_FACE_MIN_SCORE {
            continue;
        }

        let x_min_abs = row[0] - row[2] / 2.0;
        let y_min_abs = row[1] - row[3] / 2.0;
        let x_max_abs = row[0] + row[2] / 2.0;
        let y_max_abs = row[1] + row[3] / 2.0;

        let mut box_xyxy = [
            x_min_abs / INPUT_WIDTH,
            y_min_abs / INPUT_HEIGHT,
            x_max_abs / INPUT_WIDTH,
            y_max_abs / INPUT_HEIGHT,
        ];

        // 3 keypoints: left_eye, right_eye, nose
        let mut keypoints = [
            [row[5] / INPUT_WIDTH, row[6] / INPUT_HEIGHT],
            [row[7] / INPUT_WIDTH, row[8] / INPUT_HEIGHT],
            [row[9] / INPUT_WIDTH, row[10] / INPUT_HEIGHT],
        ];

        correct_for_maintained_aspect_ratio_3kp(
            &mut box_xyxy,
            &mut keypoints,
            scaled_width,
            scaled_height,
            pad_left,
            pad_top,
        );

        // For a 2-class model (row_len >= 13): row[11] = cat score,
        // row[12] = dog score.  Pick argmax and map to 0=dog, 1=cat.
        // For a 1-class model (row_len == 12): row[11] is the single class
        // score; class is always 0 (dog).
        let class_id: u8 = if row_len >= 13 {
            if row[12] > row[11] { 0 } else { 1 }
        } else {
            0
        };

        detections.push(PetFaceDetection {
            score,
            box_xyxy,
            keypoints,
            class_id,
        });
    }

    Ok(naive_nms_pet_face(detections, PET_FACE_IOU_THRESHOLD))
}

/// Run pet body detection using YOLOv5n model.
///
/// Filters detections by COCO class 15 (cat) or 16 (dog).
/// Returns all qualifying detections after NMS.
///
/// This mirrors `pet_pipeline/detection.py` `BodyDetector.detect()`.
pub fn run_pet_body_detection(
    runtime: &MlRuntimeView<'_>,
    decoded: &DecodedImage,
) -> MlResult<Vec<PetBodyDetection>> {
    let (input, scaled_width, scaled_height, pad_left, pad_top) =
        preprocess::preprocess_yolo(decoded)?;

    let mut body_detection = runtime.pet_body_detection_session()?;
    let (_output_shape, output_data) = onnx::run_f32(
        &mut body_detection,
        input,
        [1, 3, INPUT_HEIGHT as i64, INPUT_WIDTH as i64],
    )?;

    // YOLOv5 output format: [x, y, w, h, obj_conf, cls0, cls1, ..., cls79]
    // Total columns: 4 + 1 + 80 = 85
    let row_len = 85usize;
    if output_data.len() < row_len {
        return Ok(Vec::new());
    }

    let detection_rows = output_data.len() / row_len;
    let mut detections = Vec::new();

    for i in 0..detection_rows {
        let start = i * row_len;
        let row = &output_data[start..(start + row_len)];
        let obj_conf = row[4];

        // Find the winning class across all 80 COCO classes and only
        // keep detections whose predicted class is cat (15) or dog (16).
        let class_logits = &row[5..85];
        let (best_cls, best_logit) = class_logits
            .iter()
            .enumerate()
            .max_by(|a, b| a.1.total_cmp(b.1))
            .unwrap();
        let best_cls = best_cls as u8;
        if best_cls != COCO_CAT && best_cls != COCO_DOG {
            continue;
        }
        let class_score = best_logit * obj_conf;
        if class_score < BODY_MIN_SCORE {
            continue;
        }
        let class_id = best_cls;

        let x_min_abs = row[0] - row[2] / 2.0;
        let y_min_abs = row[1] - row[3] / 2.0;
        let x_max_abs = row[0] + row[2] / 2.0;
        let y_max_abs = row[1] + row[3] / 2.0;

        let mut box_xyxy = [
            x_min_abs / INPUT_WIDTH,
            y_min_abs / INPUT_HEIGHT,
            x_max_abs / INPUT_WIDTH,
            y_max_abs / INPUT_HEIGHT,
        ];

        correct_box_for_aspect_ratio(
            &mut box_xyxy,
            scaled_width,
            scaled_height,
            pad_left,
            pad_top,
        );

        detections.push(PetBodyDetection {
            score: class_score,
            box_xyxy,
            coco_class: class_id,
        });
    }

    Ok(naive_nms_pet_body(detections, BODY_IOU_THRESHOLD))
}

fn correct_box_for_aspect_ratio(
    box_xyxy: &mut [f32; 4],
    scaled_width: usize,
    scaled_height: usize,
    pad_left: usize,
    pad_top: usize,
) {
    if scaled_width == INPUT_WIDTH as usize
        && scaled_height == INPUT_HEIGHT as usize
        && pad_left == 0
        && pad_top == 0
    {
        return;
    }

    let scaled_width = scaled_width as f32;
    let scaled_height = scaled_height as f32;
    let pad_left = pad_left as f32;
    let pad_top = pad_top as f32;

    let transform_x =
        |x: f32| -> f32 { ((x * INPUT_WIDTH - pad_left) / scaled_width).clamp(0.0, 1.0) };
    let transform_y =
        |y: f32| -> f32 { ((y * INPUT_HEIGHT - pad_top) / scaled_height).clamp(0.0, 1.0) };

    box_xyxy[0] = transform_x(box_xyxy[0]);
    box_xyxy[1] = transform_y(box_xyxy[1]);
    box_xyxy[2] = transform_x(box_xyxy[2]);
    box_xyxy[3] = transform_y(box_xyxy[3]);
}

fn correct_for_maintained_aspect_ratio_3kp(
    box_xyxy: &mut [f32; 4],
    keypoints: &mut [[f32; 2]; 3],
    scaled_width: usize,
    scaled_height: usize,
    pad_left: usize,
    pad_top: usize,
) {
    correct_box_for_aspect_ratio(box_xyxy, scaled_width, scaled_height, pad_left, pad_top);

    if scaled_width == INPUT_WIDTH as usize
        && scaled_height == INPUT_HEIGHT as usize
        && pad_left == 0
        && pad_top == 0
    {
        return;
    }

    let transform_x = |x: f32| -> f32 {
        ((x * INPUT_WIDTH - pad_left as f32) / scaled_width as f32).clamp(0.0, 1.0)
    };
    let transform_y = |y: f32| -> f32 {
        ((y * INPUT_HEIGHT - pad_top as f32) / scaled_height as f32).clamp(0.0, 1.0)
    };

    for point in keypoints.iter_mut() {
        point[0] = transform_x(point[0]);
        point[1] = transform_y(point[1]);
    }
}

fn calculate_iou_4(a: &[f32; 4], b: &[f32; 4]) -> f32 {
    let area_a = (a[2] - a[0]).max(0.0) * (a[3] - a[1]).max(0.0);
    let area_b = (b[2] - b[0]).max(0.0) * (b[3] - b[1]).max(0.0);

    let ix1 = a[0].max(b[0]);
    let iy1 = a[1].max(b[1]);
    let ix2 = a[2].min(b[2]);
    let iy2 = a[3].min(b[3]);

    let iw = ix2 - ix1;
    let ih = iy2 - iy1;
    if iw < 0.0 || ih < 0.0 {
        return 0.0;
    }

    let inter = iw * ih;
    let union = area_a + area_b - inter;
    if union <= 0.0 { 0.0 } else { inter / union }
}

fn naive_nms_pet_face(
    mut detections: Vec<PetFaceDetection>,
    iou_threshold: f32,
) -> Vec<PetFaceDetection> {
    detections.sort_by(|a, b| b.score.total_cmp(&a.score));
    let n = detections.len();
    let mut suppressed = vec![false; n];
    for i in 0..n {
        if suppressed[i] {
            continue;
        }
        for j in (i + 1)..n {
            if suppressed[j] {
                continue;
            }
            // Only suppress within the same class so a dog and cat
            // occupying the same region are both retained.
            if detections[i].class_id == detections[j].class_id
                && calculate_iou_4(&detections[i].box_xyxy, &detections[j].box_xyxy)
                    >= iou_threshold
            {
                suppressed[j] = true;
            }
        }
    }
    detections
        .into_iter()
        .zip(suppressed)
        .filter_map(|(d, s)| if s { None } else { Some(d) })
        .collect()
}

fn naive_nms_pet_body(
    mut detections: Vec<PetBodyDetection>,
    iou_threshold: f32,
) -> Vec<PetBodyDetection> {
    detections.sort_by(|a, b| b.score.total_cmp(&a.score));
    let n = detections.len();
    let mut suppressed = vec![false; n];
    for i in 0..n {
        if suppressed[i] {
            continue;
        }
        for j in (i + 1)..n {
            if suppressed[j] {
                continue;
            }
            // Only suppress within the same COCO class so a dog and cat
            // occupying the same region are both retained.
            if detections[i].coco_class == detections[j].coco_class
                && calculate_iou_4(&detections[i].box_xyxy, &detections[j].box_xyxy)
                    >= iou_threshold
            {
                suppressed[j] = true;
            }
        }
    }
    detections
        .into_iter()
        .zip(suppressed)
        .filter_map(|(d, s)| if s { None } else { Some(d) })
        .collect()
}
