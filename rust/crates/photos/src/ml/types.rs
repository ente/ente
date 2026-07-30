pub use ente_image::{DecodedImage, Dimensions};

#[derive(Clone, Debug)]
pub struct FaceDetection {
    pub score: f32,
    pub box_xyxy: [f32; 4],
    pub keypoints: [[f32; 2]; 5],
}

#[derive(Clone, Debug)]
pub struct AlignmentResult {
    pub affine_matrix: [[f32; 3]; 3],
    pub center: [f32; 2],
    pub size: f32,
    pub rotation: f32,
}

#[derive(Clone, Debug)]
pub struct FaceResult {
    pub detection: FaceDetection,
    pub blur_value: f32,
    pub alignment: AlignmentResult,
    pub embedding: Vec<f32>,
    pub face_id: String,
}

#[derive(Clone, Debug)]
pub struct ClipResult {
    pub embedding: Vec<f32>,
}

pub(crate) fn to_face_id(file_id: i64, box_xyxy: [f32; 4]) -> String {
    fn to_face_segment(v: f32) -> String {
        let clamped = v.clamp(0.0, 0.999_999);
        let fixed = format!("{clamped:.5}");
        fixed
            .split_once('.')
            .map(|(_, right)| right.to_string())
            .unwrap_or_else(|| "00000".to_string())
    }

    let x_min = to_face_segment(box_xyxy[0]);
    let y_min = to_face_segment(box_xyxy[1]);
    let x_max = to_face_segment(box_xyxy[2]);
    let y_max = to_face_segment(box_xyxy[3]);
    format!("{file_id}_{x_min}_{y_min}_{x_max}_{y_max}")
}

// ── Pet Recognition Types ──────────────────────────────────────────────

#[derive(Clone, Debug)]
pub struct PetFaceDetection {
    pub score: f32,
    pub box_xyxy: [f32; 4],
    /// 3 keypoints: [left_eye, right_eye, nose]
    pub keypoints: [[f32; 2]; 3],
    /// 0 = dog, 1 = cat (from class scores in detector output)
    pub class_id: u8,
}

#[derive(Clone, Debug)]
pub struct PetAlignmentResult {
    pub center: [f32; 2],
    pub angle: f32,
    pub crop_size: f32,
}

#[derive(Clone, Debug)]
pub struct PetFaceResult {
    pub detection: PetFaceDetection,
    /// 0 = dog, 1 = cat
    pub species: u8,
    pub face_embedding: Vec<f32>,
    pub pet_face_id: String,
    pub alignment: PetAlignmentResult,
}

#[derive(Clone, Debug)]
pub struct PetBodyDetection {
    pub score: f32,
    pub box_xyxy: [f32; 4],
    /// COCO class: 15 = cat, 16 = dog
    pub coco_class: u8,
}

#[derive(Clone, Debug)]
pub struct PetBodyResult {
    pub detection: PetBodyDetection,
    pub pet_body_id: String,
    pub body_embedding: Vec<f32>,
}
