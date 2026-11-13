use crate::{onnx, preprocess::YOLO_INPUT_SIZE};

pub(crate) const MAX_DETECTIONS_PER_IMAGE: usize = 100;

#[derive(Clone, Copy)]
pub(crate) struct YoloOutputRow<T> {
    output: T,
    start: usize,
}

impl<T: onnx::FloatTensorData> YoloOutputRow<T> {
    pub(crate) fn new(output: T, start: usize) -> Self {
        Self { output, start }
    }

    pub(crate) fn value(self, offset: usize) -> f32 {
        self.output.value(self.start + offset)
    }

    pub(crate) fn confidence(self) -> f32 {
        self.value(4)
    }

    pub(crate) fn box_xyxy(self) -> [f32; 4] {
        let x = self.value(0);
        let y = self.value(1);
        let width = self.value(2);
        let height = self.value(3);
        let x_min_abs = x - width / 2.0;
        let y_min_abs = y - height / 2.0;
        let x_max_abs = x + width / 2.0;
        let y_max_abs = y + height / 2.0;

        [
            x_min_abs / YOLO_INPUT_SIZE as f32,
            y_min_abs / YOLO_INPUT_SIZE as f32,
            x_max_abs / YOLO_INPUT_SIZE as f32,
            y_max_abs / YOLO_INPUT_SIZE as f32,
        ]
    }

    pub(crate) fn keypoint(self, offset: usize) -> [f32; 2] {
        [
            self.value(offset) / YOLO_INPUT_SIZE as f32,
            self.value(offset + 1) / YOLO_INPUT_SIZE as f32,
        ]
    }
}

pub(crate) trait NmsDetection {
    fn score(&self) -> f32;
    fn box_xyxy(&self) -> &[f32; 4];
    fn same_class(&self, _other: &Self) -> bool {
        true
    }
}

pub(crate) fn greedy_non_max_suppression<D: NmsDetection>(
    mut detections: Vec<D>,
    iou_threshold: f32,
) -> Vec<D> {
    detections.sort_by(|a, b| b.score().total_cmp(&a.score()));

    let mut retained = Vec::with_capacity(detections.len().min(MAX_DETECTIONS_PER_IMAGE));
    for detection in detections {
        if retained.iter().any(|existing: &D| {
            existing.same_class(&detection)
                && calculate_iou(existing.box_xyxy(), detection.box_xyxy()) >= iou_threshold
        }) {
            continue;
        }

        retained.push(detection);
        if retained.len() == MAX_DETECTIONS_PER_IMAGE {
            break;
        }
    }

    retained
}

fn calculate_iou(a: &[f32; 4], b: &[f32; 4]) -> f32 {
    let area_a = (a[2] - a[0]).max(0.0) * (a[3] - a[1]).max(0.0);
    let area_b = (b[2] - b[0]).max(0.0) * (b[3] - b[1]).max(0.0);

    let intersection_min_x = a[0].max(b[0]);
    let intersection_min_y = a[1].max(b[1]);
    let intersection_max_x = a[2].min(b[2]);
    let intersection_max_y = a[3].min(b[3]);

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

pub(crate) fn l2_normalize(embedding: &mut [f32], zero_threshold: f32) {
    let mut norm = 0.0f32;
    for value in embedding.iter() {
        norm += value * value;
    }
    let norm = norm.sqrt();
    if norm <= zero_threshold {
        return;
    }
    for value in embedding.iter_mut() {
        *value /= norm;
    }
}

#[cfg(test)]
mod tests {
    use super::{YoloOutputRow, l2_normalize};

    #[test]
    fn yolo_output_row_decodes_shared_fields_from_its_start_offset() {
        let output = [99.0, 99.0, 320.0, 320.0, 128.0, 256.0, 0.75, 160.0, 480.0];
        let row = YoloOutputRow::new(output.as_slice(), 2);

        assert_eq!(row.confidence(), 0.75);
        assert_eq!(row.box_xyxy(), [0.4, 0.3, 0.6, 0.7]);
        assert_eq!(row.keypoint(5), [0.25, 0.75]);
    }

    #[test]
    fn l2_normalization_preserves_the_existing_arithmetic() {
        let mut embedding = [3.0, 4.0];

        l2_normalize(&mut embedding, f32::EPSILON);

        assert_eq!(embedding, [0.6, 0.8]);
    }

    #[test]
    fn l2_normalization_honors_the_callers_zero_threshold() {
        let mut embedding = [1e-13];

        l2_normalize(&mut embedding, 1e-12);

        assert_eq!(embedding, [1e-13]);
    }
}
