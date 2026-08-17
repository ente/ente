use crate::{
    error::{MlError, MlResult},
    models::Model,
    onnx,
    postprocess::{NmsDetection, greedy_non_max_suppression},
    preprocess::{YOLO_INPUT_SIZE, YoloInput},
    runtime::MlRuntimeView,
    types::FaceDetection,
};

const IOU_THRESHOLD: f32 = 0.4;
const MIN_SCORE_THRESHOLD: f32 = 0.5;

impl NmsDetection for FaceDetection {
    fn score(&self) -> f32 {
        self.score
    }

    fn box_xyxy(&self) -> &[f32; 4] {
        &self.box_xyxy
    }
}

pub(crate) fn run_face_detection(
    runtime: &MlRuntimeView<'_>,
    input: &YoloInput,
) -> MlResult<Vec<FaceDetection>> {
    runtime.run(Model::FaceDetection, |session| {
        onnx::with_prepared_float_output(
            session,
            &input.tensor,
            [1, 3, YOLO_INPUT_SIZE as i64, YOLO_INPUT_SIZE as i64],
            |_output_shape, output_data| postprocess_face_detections(output_data, input),
        )
    })
}

fn postprocess_face_detections(
    output_data: onnx::BorrowedFloatTensor<'_>,
    input: &YoloInput,
) -> MlResult<Vec<FaceDetection>> {
    match output_data {
        onnx::BorrowedFloatTensor::F32(data) => postprocess_face_tensor(data, input),
        onnx::BorrowedFloatTensor::F16(data) => postprocess_face_tensor(data, input),
    }
}

fn postprocess_face_tensor<T: onnx::FloatTensorData>(
    output_data: T,
    input: &YoloInput,
) -> MlResult<Vec<FaceDetection>> {
    let row_len = 16usize;
    if output_data.len() < row_len {
        return Err(MlError::Postprocess(
            "unexpected face detector output size".to_string(),
        ));
    }

    let detection_rows = output_data.len() / row_len;
    let mut detections = Vec::new();
    for i in 0..detection_rows {
        let start = i * row_len;
        let score = output_data.value(start + 4);
        if score < MIN_SCORE_THRESHOLD {
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
            [
                output_data.value(start + 11) / YOLO_INPUT_SIZE as f32,
                output_data.value(start + 12) / YOLO_INPUT_SIZE as f32,
            ],
            [
                output_data.value(start + 13) / YOLO_INPUT_SIZE as f32,
                output_data.value(start + 14) / YOLO_INPUT_SIZE as f32,
            ],
        ];

        input.correct_box_and_keypoints(&mut box_xyxy, &mut keypoints);

        detections.push(FaceDetection {
            score,
            box_xyxy,
            keypoints,
        });
    }

    Ok(greedy_non_max_suppression(detections, IOU_THRESHOLD))
}

#[cfg(test)]
mod tests {
    use crate::postprocess::MAX_DETECTIONS_PER_IMAGE;

    use super::{FaceDetection, IOU_THRESHOLD, greedy_non_max_suppression};

    #[test]
    fn face_nms_retains_the_highest_scoring_hundred_detections() {
        let detections = (0..=MAX_DETECTIONS_PER_IMAGE)
            .map(|index| FaceDetection {
                score: index as f32,
                box_xyxy: separated_box(index),
                keypoints: [[0.0; 2]; 5],
            })
            .collect();

        let retained = greedy_non_max_suppression(detections, IOU_THRESHOLD);

        assert_eq!(retained.len(), MAX_DETECTIONS_PER_IMAGE);
        assert_eq!(retained.first().unwrap().score, 100.0);
        assert_eq!(retained.last().unwrap().score, 1.0);
    }

    #[test]
    fn face_nms_suppresses_lower_scoring_overlaps() {
        let retained = greedy_non_max_suppression(
            vec![
                FaceDetection {
                    score: 0.8,
                    box_xyxy: [0.0, 0.0, 1.0, 1.0],
                    keypoints: [[0.0; 2]; 5],
                },
                FaceDetection {
                    score: 0.9,
                    box_xyxy: [0.0, 0.0, 1.0, 1.0],
                    keypoints: [[0.0; 2]; 5],
                },
            ],
            IOU_THRESHOLD,
        );

        assert_eq!(retained.len(), 1);
        assert_eq!(retained[0].score, 0.9);
    }

    fn separated_box(index: usize) -> [f32; 4] {
        let x = index as f32 * 2.0;
        [x, 0.0, x + 1.0, 1.0]
    }
}
