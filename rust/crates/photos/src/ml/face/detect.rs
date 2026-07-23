use crate::ml::{
    error::{MlError, MlResult},
    onnx,
    preprocess::{YOLO_INPUT_SIZE, YoloInput},
    runtime::MlRuntimeView,
    types::FaceDetection,
};

const IOU_THRESHOLD: f32 = 0.4;
const MIN_SCORE_THRESHOLD: f32 = 0.5;

pub(crate) fn run_face_detection(
    runtime: &MlRuntimeView<'_>,
    input: &YoloInput,
) -> MlResult<Vec<FaceDetection>> {
    let mut face_detection = runtime.face_detection_session()?;
    onnx::with_prepared_float_output(
        &mut face_detection,
        &input.tensor,
        [1, 3, YOLO_INPUT_SIZE as i64, YOLO_INPUT_SIZE as i64],
        |_output_shape, output_data| postprocess_face_detections(output_data, input),
    )
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

    Ok(naive_non_max_suppression(detections, IOU_THRESHOLD))
}

fn naive_non_max_suppression(
    mut detections: Vec<FaceDetection>,
    iou_threshold: f32,
) -> Vec<FaceDetection> {
    detections.sort_by(|a, b| b.score.total_cmp(&a.score));

    let mut suppressed = vec![false; detections.len()];
    for i in 0..detections.len() {
        if suppressed[i] {
            continue;
        }

        for j in (i + 1)..detections.len() {
            if suppressed[j] {
                continue;
            }
            let iou = calculate_iou(&detections[i], &detections[j]);
            if iou >= iou_threshold {
                suppressed[j] = true;
            }
        }
    }

    detections
        .into_iter()
        .enumerate()
        .filter_map(|(index, detection)| (!suppressed[index]).then_some(detection))
        .collect()
}

fn calculate_iou(a: &FaceDetection, b: &FaceDetection) -> f32 {
    let area_a =
        (a.box_xyxy[2] - a.box_xyxy[0]).max(0.0) * (a.box_xyxy[3] - a.box_xyxy[1]).max(0.0);
    let area_b =
        (b.box_xyxy[2] - b.box_xyxy[0]).max(0.0) * (b.box_xyxy[3] - b.box_xyxy[1]).max(0.0);

    let intersection_min_x = a.box_xyxy[0].max(b.box_xyxy[0]);
    let intersection_min_y = a.box_xyxy[1].max(b.box_xyxy[1]);
    let intersection_max_x = a.box_xyxy[2].min(b.box_xyxy[2]);
    let intersection_max_y = a.box_xyxy[3].min(b.box_xyxy[3]);

    let intersection_width = intersection_max_x - intersection_min_x;
    let intersection_height = intersection_max_y - intersection_min_y;
    if intersection_width < 0.0 || intersection_height < 0.0 {
        return 0.0;
    }

    let intersection_area = intersection_width * intersection_height;
    let union_area = area_a + area_b - intersection_area;
    if union_area <= 0.0 {
        return 0.0;
    }
    intersection_area / union_area
}
