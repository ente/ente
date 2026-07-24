use ente_photos::ml::{
    error::MlError as SharedMlError, indexing as shared_indexing, runtime::ModelPaths,
    types as shared_types,
};

#[derive(Clone, Debug)]
pub struct RustModelPaths {
    pub face_detection: String,
    pub face_embedding: String,
    pub clip_image: String,
    pub clip_text: String,
    pub pet_face_detection: String,
    pub pet_face_embedding_dog: String,
    pub pet_face_embedding_cat: String,
    pub pet_body_detection: String,
    pub pet_body_embedding_dog: String,
    pub pet_body_embedding_cat: String,
}

#[derive(Clone, Debug)]
pub struct AnalyzeImageRequest {
    pub file_id: i64,
    pub image_path: String,
    pub run_faces: bool,
    pub run_clip: bool,
    pub run_pets: bool,
    pub model_paths: RustModelPaths,
}

#[derive(Clone, Debug)]
pub enum RustMlError {
    InvalidRequest(String),
    Decode(String),
    Preprocess(String),
    Ort(String),
    CorruptModel(String),
    Postprocess(String),
    Runtime(String),
}

#[derive(Clone, Debug)]
pub struct RustDimensions {
    pub width: i32,
    pub height: i32,
}

#[derive(Clone, Debug)]
pub struct RustDetection {
    pub score: f32,
    pub box_xyxy: Vec<f32>,
    pub all_keypoints: Vec<Vec<f32>>,
}

#[derive(Clone, Debug)]
pub struct RustAlignmentResult {
    pub affine_matrix: Vec<Vec<f32>>,
    pub center: Vec<f32>,
    pub size: f32,
    pub rotation: f32,
}

#[derive(Clone, Debug)]
pub struct RustFaceResult {
    pub detection: RustDetection,
    pub blur_value: f32,
    pub alignment: RustAlignmentResult,
    pub embedding: Vec<f32>,
    pub face_id: String,
}

#[derive(Clone, Debug)]
pub struct RustClipResult {
    pub embedding: Vec<f32>,
}

#[derive(Clone, Debug)]
pub struct RustPetFaceDetectionResult {
    pub score: f64,
    pub box_xyxy: Vec<f64>,
    /// 3 keypoints: [left_eye, right_eye, nose], each as [x, y]
    pub keypoints: Vec<Vec<f64>>,
}

#[derive(Clone, Debug)]
pub struct RustPetAlignmentResult {
    pub center: Vec<f64>,
    pub angle: f64,
    pub crop_size: f64,
}

#[derive(Clone, Debug)]
pub struct RustPetFaceResult {
    pub detection: RustPetFaceDetectionResult,
    pub alignment: RustPetAlignmentResult,
    /// 0 = dog, 1 = cat
    pub species: u8,
    pub face_embedding: Vec<f64>,
    pub pet_face_id: String,
}

#[derive(Clone, Debug)]
pub struct RustPetBodyResult {
    pub box_xyxy: Vec<f64>,
    pub score: f64,
    /// COCO class: 15 = cat, 16 = dog
    pub coco_class: u8,
    pub pet_body_id: String,
    pub body_embedding: Vec<f64>,
}

#[derive(Clone, Debug)]
pub struct AnalyzeImageResult {
    pub file_id: i64,
    pub decoded_image_size: RustDimensions,
    pub faces: Option<Vec<RustFaceResult>>,
    pub clip: Option<RustClipResult>,
    pub pet_faces: Option<Vec<RustPetFaceResult>>,
    pub pet_bodies: Option<Vec<RustPetBodyResult>>,
    /// True when any model that contributed to this result ran on the
    /// respective accelerated execution provider.
    pub used_coreml: bool,
    pub used_webgpu: bool,
}

#[derive(Clone, Debug)]
pub struct RunClipTextRequest {
    pub text: String,
    pub model_path: String,
    pub vocab_path: String,
}

#[derive(Clone, Debug)]
pub struct RunClipTextResult {
    pub embedding: Vec<f64>,
}

/// Configures process-wide ML execution behavior. `enable_webgpu` opts
/// Android into the WebGPU execution provider (off by default, and only
/// honored on Android 12+); it has no effect on other platforms. Call this
/// before the runtime creates its first session.
pub fn set_ml_execution_config(enable_webgpu: bool) {
    shared_indexing::set_ml_execution_config(enable_webgpu);
}

pub fn init_ml_runtime(model_paths: RustModelPaths) {
    shared_indexing::init_ml_runtime(to_model_paths(&model_paths));
}

pub fn release_ml_runtime() {
    shared_indexing::release_ml_runtime();
}

pub fn analyze_image_rust(req: AnalyzeImageRequest) -> Result<AnalyzeImageResult, RustMlError> {
    let shared_req = shared_indexing::AnalyzeImageRequest {
        file_id: req.file_id,
        image_path: req.image_path,
        run_faces: req.run_faces,
        run_clip: req.run_clip,
        run_pets: req.run_pets,
        model_paths: to_model_paths(&req.model_paths),
    };

    shared_indexing::analyze_image(shared_req)
        .map(to_api_analyze_image_result)
        .map_err(RustMlError::from)
}

pub fn run_clip_text_rust(req: RunClipTextRequest) -> Result<RunClipTextResult, RustMlError> {
    let shared_req = shared_indexing::RunClipTextRequest {
        text: req.text,
        model_path: req.model_path,
        vocab_path: req.vocab_path,
    };

    shared_indexing::run_clip_text(shared_req)
        .map(|result| RunClipTextResult {
            embedding: result
                .embedding
                .into_iter()
                .map(|value| value as f64)
                .collect(),
        })
        .map_err(RustMlError::from)
}

pub fn tokenize_clip_text_rust(text: String, vocab_path: String) -> Result<Vec<i32>, String> {
    shared_indexing::tokenize_clip_text(&text, &vocab_path).map_err(|e| e.to_string())
}

/// A notable ML runtime event (execution provider fallback, golden self-test
/// failure) buffered by the Rust runtime for app-side logging. `severity` is
/// one of "info", "warning", or "severe".
#[derive(Clone, Debug)]
pub struct RustMlRuntimeEvent {
    pub severity: String,
    pub message: String,
}

/// Drains buffered ML runtime events. The buffer is process-wide, so drain
/// after ML operations and log each event at its severity.
pub fn take_ml_runtime_events() -> Vec<RustMlRuntimeEvent> {
    ente_photos::ml::events::take_events()
        .into_iter()
        .map(|event| RustMlRuntimeEvent {
            severity: event.severity.as_str().to_string(),
            message: event.message,
        })
        .collect()
}

fn to_model_paths(paths: &RustModelPaths) -> ModelPaths {
    ModelPaths {
        face_detection: paths.face_detection.clone(),
        face_embedding: paths.face_embedding.clone(),
        clip_image: paths.clip_image.clone(),
        clip_text: paths.clip_text.clone(),
        pet_face_detection: paths.pet_face_detection.clone(),
        pet_face_embedding_dog: paths.pet_face_embedding_dog.clone(),
        pet_face_embedding_cat: paths.pet_face_embedding_cat.clone(),
        pet_body_detection: paths.pet_body_detection.clone(),
        pet_body_embedding_dog: paths.pet_body_embedding_dog.clone(),
        pet_body_embedding_cat: paths.pet_body_embedding_cat.clone(),
    }
}

impl From<SharedMlError> for RustMlError {
    fn from(value: SharedMlError) -> Self {
        match value {
            SharedMlError::InvalidRequest(message) => RustMlError::InvalidRequest(message),
            SharedMlError::Decode(message) => RustMlError::Decode(message),
            SharedMlError::Preprocess(message) => RustMlError::Preprocess(message),
            SharedMlError::Ort(message) => RustMlError::Ort(message),
            SharedMlError::CorruptModel(message) => RustMlError::CorruptModel(message),
            SharedMlError::Postprocess(message) => RustMlError::Postprocess(message),
            SharedMlError::Runtime(message) => RustMlError::Runtime(message),
        }
    }
}

fn to_api_analyze_image_result(result: shared_indexing::AnalyzeImageResult) -> AnalyzeImageResult {
    AnalyzeImageResult {
        file_id: result.file_id,
        decoded_image_size: RustDimensions {
            width: result.decoded_image_size.width as i32,
            height: result.decoded_image_size.height as i32,
        },
        faces: result
            .faces
            .map(|faces| faces.into_iter().map(to_api_face_result).collect()),
        clip: result.clip.map(|clip| RustClipResult {
            embedding: clip.embedding,
        }),
        pet_faces: result
            .pet_faces
            .map(|faces| faces.into_iter().map(to_api_pet_face_result).collect()),
        pet_bodies: result
            .pet_bodies
            .map(|bodies| bodies.into_iter().map(to_api_pet_body_result).collect()),
        used_coreml: result.used_coreml,
        used_webgpu: result.used_webgpu,
    }
}

fn to_api_face_result(result: shared_types::FaceResult) -> RustFaceResult {
    RustFaceResult {
        detection: RustDetection {
            score: result.detection.score,
            box_xyxy: result.detection.box_xyxy.into_iter().collect(),
            all_keypoints: result
                .detection
                .keypoints
                .into_iter()
                .map(|point| point.into_iter().collect())
                .collect(),
        },
        blur_value: result.blur_value,
        alignment: RustAlignmentResult {
            affine_matrix: result
                .alignment
                .affine_matrix
                .into_iter()
                .map(|row| row.into_iter().collect())
                .collect(),
            center: result.alignment.center.into_iter().collect(),
            size: result.alignment.size,
            rotation: result.alignment.rotation,
        },
        embedding: result.embedding,
        face_id: result.face_id,
    }
}

fn to_api_pet_face_result(result: shared_types::PetFaceResult) -> RustPetFaceResult {
    RustPetFaceResult {
        detection: RustPetFaceDetectionResult {
            score: result.detection.score as f64,
            box_xyxy: result
                .detection
                .box_xyxy
                .into_iter()
                .map(|v| v as f64)
                .collect(),
            keypoints: result
                .detection
                .keypoints
                .into_iter()
                .map(|point| point.into_iter().map(|v| v as f64).collect())
                .collect(),
        },
        alignment: RustPetAlignmentResult {
            center: result
                .alignment
                .center
                .into_iter()
                .map(|v| v as f64)
                .collect(),
            angle: result.alignment.angle as f64,
            crop_size: result.alignment.crop_size as f64,
        },
        species: result.species,
        face_embedding: result
            .face_embedding
            .into_iter()
            .map(|v| v as f64)
            .collect(),
        pet_face_id: result.pet_face_id,
    }
}

fn to_api_pet_body_result(result: shared_types::PetBodyResult) -> RustPetBodyResult {
    RustPetBodyResult {
        box_xyxy: result
            .detection
            .box_xyxy
            .into_iter()
            .map(|v| v as f64)
            .collect(),
        score: result.detection.score as f64,
        coco_class: result.detection.coco_class,
        pet_body_id: result.pet_body_id,
        body_embedding: result
            .body_embedding
            .into_iter()
            .map(|v| v as f64)
            .collect(),
    }
}
