use crate::{
    error::{MlError, MlResult},
    models::Model,
    onnx,
    postprocess::{NmsDetection, greedy_non_max_suppression},
    preprocess::{YOLO_INPUT_SIZE, YoloInput},
    runtime::MlRuntimeView,
    types::{PetBodyDetection, PetFaceDetection},
};

use super::{COCO_CAT, COCO_DOG, PET_SPECIES_CAT, PET_SPECIES_DOG};

// These thresholds match the Python pipeline.
const PET_FACE_IOU_THRESHOLD: f32 = 0.5;
const PET_FACE_MIN_SCORE: f32 = 0.3;

const BODY_IOU_THRESHOLD: f32 = 0.5;
const BODY_MIN_SCORE: f32 = 0.3;

impl NmsDetection for PetFaceDetection {
    fn score(&self) -> f32 {
        self.score
    }

    fn box_xyxy(&self) -> &[f32; 4] {
        &self.box_xyxy
    }

    fn same_class(&self, other: &Self) -> bool {
        self.class_id == other.class_id
    }
}

impl NmsDetection for PetBodyDetection {
    fn score(&self) -> f32 {
        self.score
    }

    fn box_xyxy(&self) -> &[f32; 4] {
        &self.box_xyxy
    }

    fn same_class(&self, other: &Self) -> bool {
        self.coco_class == other.coco_class
    }
}

pub(crate) fn run_pet_face_detection(
    runtime: &MlRuntimeView<'_>,
    input: &YoloInput,
) -> MlResult<Vec<PetFaceDetection>> {
    runtime.run(Model::PetFaceDetection, |session| {
        onnx::with_prepared_float_output(
            session,
            &input.tensor,
            [1, 3, YOLO_INPUT_SIZE as i64, YOLO_INPUT_SIZE as i64],
            |output_shape, output_data| {
                postprocess_pet_face_detections(output_shape, output_data, input)
            },
        )
    })
}

fn postprocess_pet_face_detections(
    output_shape: &[i64],
    output_data: onnx::BorrowedFloatTensor<'_>,
    input: &YoloInput,
) -> MlResult<Vec<PetFaceDetection>> {
    match output_data {
        onnx::BorrowedFloatTensor::F32(data) => {
            postprocess_pet_face_tensor(output_shape, data, input)
        }
        onnx::BorrowedFloatTensor::F16(data) => {
            postprocess_pet_face_tensor(output_shape, data, input)
        }
    }
}

fn postprocess_pet_face_tensor<T: onnx::FloatTensorData>(
    output_shape: &[i64],
    output_data: T,
    input: &YoloInput,
) -> MlResult<Vec<PetFaceDetection>> {
    let row_len = if output_shape.len() >= 2 {
        *output_shape.last().unwrap() as usize
    } else if output_shape.len() == 1 {
        let total = output_data.len();
        if total.is_multiple_of(13) {
            13
        } else if total.is_multiple_of(12) {
            12
        } else if total.is_multiple_of(11) {
            11
        } else {
            return Err(MlError::Postprocess(format!(
                "unexpected pet face detector output size: {} (shape: {:?})",
                total, output_shape
            )));
        }
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
    let mut detections = Vec::new();

    // Row: x, y, width, height, score, left eye, right eye, nose, classes.
    for i in 0..detection_rows {
        let start = i * row_len;
        let score = output_data.value(start + 4);
        if score < PET_FACE_MIN_SCORE {
            continue;
        }

        let x = output_data.value(start);
        let y = output_data.value(start + 1);
        let width = output_data.value(start + 2);
        let height = output_data.value(start + 3);
        let x_min_abs = x - width / 2.0;
        let y_min_abs = y - height / 2.0;
        let x_max_abs = x + width / 2.0;
        let y_max_abs = y + height / 2.0;

        let mut box_xyxy = [
            x_min_abs / YOLO_INPUT_SIZE as f32,
            y_min_abs / YOLO_INPUT_SIZE as f32,
            x_max_abs / YOLO_INPUT_SIZE as f32,
            y_max_abs / YOLO_INPUT_SIZE as f32,
        ];

        let mut keypoints = [
            [
                output_data.value(start + 5) / YOLO_INPUT_SIZE as f32,
                output_data.value(start + 6) / YOLO_INPUT_SIZE as f32,
            ],
            [
                output_data.value(start + 7) / YOLO_INPUT_SIZE as f32,
                output_data.value(start + 8) / YOLO_INPUT_SIZE as f32,
            ],
            [
                output_data.value(start + 9) / YOLO_INPUT_SIZE as f32,
                output_data.value(start + 10) / YOLO_INPUT_SIZE as f32,
            ],
        ];

        input.correct_box_and_keypoints(&mut box_xyxy, &mut keypoints);

        // Two-class rows are [cat, dog]; one-class rows are dog-only.
        let class_id: u8 = if row_len >= 13 {
            if output_data.value(start + 12) > output_data.value(start + 11) {
                PET_SPECIES_DOG
            } else {
                PET_SPECIES_CAT
            }
        } else {
            PET_SPECIES_DOG
        };

        detections.push(PetFaceDetection {
            score,
            box_xyxy,
            keypoints,
            class_id,
        });
    }

    Ok(greedy_non_max_suppression(
        detections,
        PET_FACE_IOU_THRESHOLD,
    ))
}

pub(crate) fn run_pet_body_detection(
    runtime: &MlRuntimeView<'_>,
    input: &YoloInput,
) -> MlResult<Vec<PetBodyDetection>> {
    runtime.run(Model::PetBodyDetection, |session| {
        onnx::with_prepared_float_output(
            session,
            &input.tensor,
            [1, 3, YOLO_INPUT_SIZE as i64, YOLO_INPUT_SIZE as i64],
            |_output_shape, output_data| postprocess_pet_body_detections(output_data, input),
        )
    })
}

fn postprocess_pet_body_detections(
    output_data: onnx::BorrowedFloatTensor<'_>,
    input: &YoloInput,
) -> MlResult<Vec<PetBodyDetection>> {
    match output_data {
        onnx::BorrowedFloatTensor::F32(data) => postprocess_pet_body_tensor(data, input),
        onnx::BorrowedFloatTensor::F16(data) => postprocess_pet_body_tensor(data, input),
    }
}

fn postprocess_pet_body_tensor<T: onnx::FloatTensorData>(
    output_data: T,
    input: &YoloInput,
) -> MlResult<Vec<PetBodyDetection>> {
    // YOLOv5 output format: [x, y, w, h, obj_conf, cls0, cls1, ..., cls79]
    let row_len = 85usize;
    if output_data.len() < row_len {
        return Ok(Vec::new());
    }

    let detection_rows = output_data.len() / row_len;
    let mut detections = Vec::new();

    for i in 0..detection_rows {
        let start = i * row_len;
        let Some((class_id, class_score)) = winning_pet_body_class(output_data, start) else {
            continue;
        };

        let x = output_data.value(start);
        let y = output_data.value(start + 1);
        let width = output_data.value(start + 2);
        let height = output_data.value(start + 3);
        let x_min_abs = x - width / 2.0;
        let y_min_abs = y - height / 2.0;
        let x_max_abs = x + width / 2.0;
        let y_max_abs = y + height / 2.0;

        let mut box_xyxy = [
            x_min_abs / YOLO_INPUT_SIZE as f32,
            y_min_abs / YOLO_INPUT_SIZE as f32,
            x_max_abs / YOLO_INPUT_SIZE as f32,
            y_max_abs / YOLO_INPUT_SIZE as f32,
        ];

        input.correct_box(&mut box_xyxy);

        detections.push(PetBodyDetection {
            score: class_score,
            box_xyxy,
            coco_class: class_id,
        });
    }

    Ok(greedy_non_max_suppression(detections, BODY_IOU_THRESHOLD))
}

fn winning_pet_body_class<T: onnx::FloatTensorData>(
    output_data: T,
    row_start: usize,
) -> Option<(u8, f32)> {
    let obj_conf = output_data.value(row_start + 4);

    let cat_logit = output_data.value(row_start + 5 + COCO_CAT as usize);
    let dog_logit = output_data.value(row_start + 5 + COCO_DOG as usize);
    let best_pet_logit = if dog_logit.total_cmp(&cat_logit).is_ge() {
        dog_logit
    } else {
        cat_logit
    };
    if best_pet_logit * obj_conf < BODY_MIN_SCORE {
        return None;
    }

    // A sufficiently strong pet score still needs to win against every other
    // COCO class. Keep the original total ordering and tie behaviour here.
    let mut best_cls = 0u8;
    let mut best_logit = output_data.value(row_start + 5);
    for class in 1u8..80 {
        let logit = output_data.value(row_start + 5 + class as usize);
        if logit.total_cmp(&best_logit).is_ge() {
            best_cls = class;
            best_logit = logit;
        }
    }
    if best_cls != COCO_CAT && best_cls != COCO_DOG {
        return None;
    }

    Some((best_cls, best_logit * obj_conf))
}

#[cfg(test)]
mod tests {
    use crate::postprocess::{MAX_DETECTIONS_PER_IMAGE, greedy_non_max_suppression};

    use super::{
        BODY_IOU_THRESHOLD, BODY_MIN_SCORE, COCO_CAT, COCO_DOG, PET_FACE_IOU_THRESHOLD,
        PET_SPECIES_CAT, PET_SPECIES_DOG, PetBodyDetection, PetFaceDetection,
        winning_pet_body_class,
    };

    #[test]
    fn pet_nms_retains_the_highest_scoring_hundred_detections() {
        let faces = (0..=MAX_DETECTIONS_PER_IMAGE)
            .map(|index| PetFaceDetection {
                score: index as f32,
                box_xyxy: separated_box(index),
                keypoints: [[0.0; 2]; 3],
                class_id: PET_SPECIES_DOG,
            })
            .collect();
        let bodies = (0..=MAX_DETECTIONS_PER_IMAGE)
            .map(|index| PetBodyDetection {
                score: index as f32,
                box_xyxy: separated_box(index),
                coco_class: COCO_DOG,
            })
            .collect();

        let retained_faces = greedy_non_max_suppression(faces, PET_FACE_IOU_THRESHOLD);
        let retained_bodies = greedy_non_max_suppression(bodies, BODY_IOU_THRESHOLD);

        assert_eq!(retained_faces.len(), MAX_DETECTIONS_PER_IMAGE);
        assert_eq!(retained_faces.first().unwrap().score, 100.0);
        assert_eq!(retained_faces.last().unwrap().score, 1.0);
        assert_eq!(retained_bodies.len(), MAX_DETECTIONS_PER_IMAGE);
        assert_eq!(retained_bodies.first().unwrap().score, 100.0);
        assert_eq!(retained_bodies.last().unwrap().score, 1.0);
    }

    #[test]
    fn pet_nms_only_suppresses_overlaps_within_the_same_class() {
        let retained_faces = greedy_non_max_suppression(
            vec![
                PetFaceDetection {
                    score: 0.8,
                    box_xyxy: [0.0, 0.0, 1.0, 1.0],
                    keypoints: [[0.0; 2]; 3],
                    class_id: PET_SPECIES_DOG,
                },
                PetFaceDetection {
                    score: 0.9,
                    box_xyxy: [0.0, 0.0, 1.0, 1.0],
                    keypoints: [[0.0; 2]; 3],
                    class_id: PET_SPECIES_DOG,
                },
                PetFaceDetection {
                    score: 0.7,
                    box_xyxy: [0.0, 0.0, 1.0, 1.0],
                    keypoints: [[0.0; 2]; 3],
                    class_id: PET_SPECIES_CAT,
                },
            ],
            PET_FACE_IOU_THRESHOLD,
        );
        let retained_bodies = greedy_non_max_suppression(
            vec![
                PetBodyDetection {
                    score: 0.8,
                    box_xyxy: [0.0, 0.0, 1.0, 1.0],
                    coco_class: COCO_DOG,
                },
                PetBodyDetection {
                    score: 0.9,
                    box_xyxy: [0.0, 0.0, 1.0, 1.0],
                    coco_class: COCO_DOG,
                },
                PetBodyDetection {
                    score: 0.7,
                    box_xyxy: [0.0, 0.0, 1.0, 1.0],
                    coco_class: COCO_CAT,
                },
            ],
            BODY_IOU_THRESHOLD,
        );

        assert_eq!(
            retained_faces
                .iter()
                .map(|detection| (detection.score, detection.class_id))
                .collect::<Vec<_>>(),
            vec![(0.9, PET_SPECIES_DOG), (0.7, PET_SPECIES_CAT)]
        );
        assert_eq!(
            retained_bodies
                .iter()
                .map(|detection| (detection.score, detection.coco_class))
                .collect::<Vec<_>>(),
            vec![(0.9, COCO_DOG), (0.7, COCO_CAT)]
        );
    }

    #[test]
    fn pet_body_class_prefilter_matches_full_scan() {
        let mut rows = Vec::new();

        rows.push(body_row(0.9, &[(COCO_CAT, 0.2), (COCO_DOG, 0.1)]));
        rows.push(body_row(0.9, &[(COCO_CAT, 0.8), (COCO_DOG, 0.7)]));
        rows.push(body_row(0.9, &[(COCO_CAT, 0.8), (3, 0.9)]));
        rows.push(body_row(1.0, &[(COCO_CAT, BODY_MIN_SCORE)]));
        rows.push(body_row(
            1.0,
            &[(COCO_CAT, BODY_MIN_SCORE), (COCO_DOG, BODY_MIN_SCORE)],
        ));
        rows.push(body_row(1.0, &[(COCO_DOG, 0.8), (79, 0.8)]));

        for row in rows {
            assert_eq!(winning_pet_body_class(row.as_slice(), 0), full_scan(&row));

            let f16_row = row
                .iter()
                .copied()
                .map(half::f16::from_f32)
                .collect::<Vec<_>>();
            let converted_row = f16_row
                .iter()
                .map(|value| value.to_f32())
                .collect::<Vec<_>>();
            assert_eq!(
                winning_pet_body_class(f16_row.as_slice(), 0),
                full_scan(&converted_row),
            );
        }
    }

    fn body_row(object_confidence: f32, scores: &[(u8, f32)]) -> Vec<f32> {
        let mut row = vec![0.0; 85];
        row[4] = object_confidence;
        for &(class, score) in scores {
            row[5 + class as usize] = score;
        }
        row
    }

    fn full_scan(row: &[f32]) -> Option<(u8, f32)> {
        let (best_class, best_logit) = row[5..85]
            .iter()
            .enumerate()
            .max_by(|a, b| a.1.total_cmp(b.1))
            .unwrap();
        let best_class = best_class as u8;
        if best_class != COCO_CAT && best_class != COCO_DOG {
            return None;
        }

        let score = best_logit * row[4];
        (score >= BODY_MIN_SCORE).then_some((best_class, score))
    }

    fn separated_box(index: usize) -> [f32; 4] {
        let x = index as f32 * 2.0;
        [x, 0.0, x + 1.0, 1.0]
    }
}
