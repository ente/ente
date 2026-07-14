use crate::ml::{
    error::{MlError, MlResult},
    onnx, preprocess,
    runtime::MlRuntimeView,
    types::{DecodedImage, FaceDetection},
};

const INPUT_WIDTH: f32 = 640.0;
const INPUT_HEIGHT: f32 = 640.0;
const IOU_THRESHOLD: f32 = 0.4;
const MIN_SCORE_THRESHOLD: f32 = 0.5;

pub fn run_face_detection(
    runtime: &MlRuntimeView<'_>,
    decoded: &DecodedImage,
) -> MlResult<Vec<FaceDetection>> {
    let (input, scaled_width, scaled_height, pad_left, pad_top) =
        preprocess::preprocess_yolo(decoded)?;
    let mut face_detection = runtime.face_detection_session()?;
    let output_data = onnx::run_f32_data(
        &mut face_detection,
        input,
        [1, 3, INPUT_HEIGHT as i64, INPUT_WIDTH as i64],
    )?;

    let row_len = 16usize;
    if output_data.len() < row_len {
        return Err(MlError::Postprocess(
            "unexpected face detector output size".to_string(),
        ));
    }

    let detection_rows = output_data.len() / row_len;
    let mut detections = Vec::with_capacity(detection_rows);
    for i in 0..detection_rows {
        let start = i * row_len;
        let row = &output_data[start..(start + row_len)];
        let score = row[4];
        if score < MIN_SCORE_THRESHOLD {
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
        let mut keypoints = [
            [row[5] / INPUT_WIDTH, row[6] / INPUT_HEIGHT],
            [row[7] / INPUT_WIDTH, row[8] / INPUT_HEIGHT],
            [row[9] / INPUT_WIDTH, row[10] / INPUT_HEIGHT],
            [row[11] / INPUT_WIDTH, row[12] / INPUT_HEIGHT],
            [row[13] / INPUT_WIDTH, row[14] / INPUT_HEIGHT],
        ];

        correct_for_maintained_aspect_ratio(
            &mut box_xyxy,
            &mut keypoints,
            scaled_width,
            scaled_height,
            pad_left,
            pad_top,
        );

        detections.push(FaceDetection {
            score,
            box_xyxy,
            keypoints,
        });
    }

    Ok(naive_non_max_suppression(detections, IOU_THRESHOLD))
}

fn correct_for_maintained_aspect_ratio(
    box_xyxy: &mut [f32; 4],
    keypoints: &mut [[f32; 2]; 5],
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

    for point in keypoints.iter_mut() {
        point[0] = transform_x(point[0]);
        point[1] = transform_y(point[1]);
    }
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
