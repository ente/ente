use crate::ml::{
    clip::{run_clip_image, run_clip_text_query, tokenize_clip_text as tokenize_clip_text_impl},
    error::{MlError, MlResult},
    face::{run_face_alignment, run_face_detection, run_face_embedding},
    pet::{
        run_pet_body_detection, run_pet_body_embedding, run_pet_face_alignment,
        run_pet_face_detection, run_pet_face_embedding,
    },
    preprocess,
    runtime::{self, ModelPaths},
    types::{self, ClipResult, Dimensions, FaceResult, PetBodyResult, PetFaceResult},
    webgpu,
};
use ente_image::decode::decode_image_from_path;

#[derive(Clone, Debug)]
pub struct AnalyzeImageRequest {
    pub file_id: i64,
    pub image_path: String,
    pub run_faces: bool,
    pub run_clip: bool,
    pub run_pets: bool,
    pub model_paths: ModelPaths,
}

#[derive(Clone, Debug)]
pub struct AnalyzeImageResult {
    pub file_id: i64,
    pub decoded_image_size: Dimensions,
    pub faces: Option<Vec<FaceResult>>,
    pub clip: Option<ClipResult>,
    pub pet_faces: Option<Vec<PetFaceResult>>,
    pub pet_bodies: Option<Vec<PetBodyResult>>,
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
    pub embedding: Vec<f32>,
}

/// Configures process-wide ML execution behavior. Must be called before the
/// first session is created to take effect for that session.
///
/// `enable_webgpu` is the app-side eligibility decision for Android. Rust
/// additionally applies its durable crash canary before attempting the WebGPU
/// execution provider. It has no effect on other platforms.
pub fn set_ml_execution_config(enable_webgpu: bool) {
    webgpu::set_enabled(enable_webgpu);
}

pub fn init_ml_runtime(model_paths: ModelPaths) {
    runtime::prepare_runtime(&model_paths);
}

pub fn release_ml_runtime() {
    runtime::release_runtime();
}

pub fn analyze_image(req: AnalyzeImageRequest) -> MlResult<AnalyzeImageResult> {
    validate_request_model_paths(&req)?;

    let AnalyzeImageRequest {
        file_id,
        image_path,
        run_faces,
        run_clip,
        run_pets,
        model_paths,
    } = req;

    runtime::with_runtime(&model_paths, |runtime| {
        let mut decoded = decode_image_from_path(&image_path)?;
        let dims = decoded.dimensions.clone();
        let detector_input = (run_faces || run_pets)
            .then(|| preprocess::preprocess_yolo(&decoded))
            .transpose()?;

        let faces = if run_faces {
            let detections = run_face_detection(
                runtime,
                detector_input
                    .as_ref()
                    .expect("detector input is prepared when face indexing is enabled"),
            )?;
            if detections.is_empty() {
                Some(Vec::new())
            } else {
                let (aligned, mut face_results) =
                    run_face_alignment(file_id, &mut decoded, detections)?;
                run_face_embedding(runtime, aligned, &mut face_results)?;
                Some(face_results)
            }
        } else {
            None
        };

        let clip = if run_clip {
            Some(run_clip_image(runtime, &decoded)?)
        } else {
            None
        };

        let (pet_faces, pet_bodies) = if run_pets {
            let detector_input = detector_input
                .as_ref()
                .expect("detector input is prepared when pet indexing is enabled");
            let pet_face_detections = run_pet_face_detection(runtime, detector_input)?;
            let body_detections = run_pet_body_detection(runtime, detector_input)?;

            let pet_face_results = if !pet_face_detections.is_empty() {
                let (aligned, mut pet_results) =
                    run_pet_face_alignment(file_id, &decoded, pet_face_detections)?;
                run_pet_face_embedding(runtime, aligned, &mut pet_results)?;
                pet_results
            } else {
                Vec::new()
            };

            let mut body_results: Vec<PetBodyResult> = body_detections
                .into_iter()
                .map(|det| {
                    let base_id = types::to_face_id(file_id, det.box_xyxy);
                    let pet_body_id = format!("{base_id}_c{}", det.coco_class);
                    PetBodyResult {
                        pet_body_id,
                        detection: det,
                        body_embedding: Vec::new(),
                    }
                })
                .collect();

            if !body_results.is_empty() {
                run_pet_body_embedding(runtime, &decoded, &mut body_results)?;
            }

            (Some(pet_face_results), Some(body_results))
        } else {
            (None, None)
        };

        let used_providers = runtime.used_providers();
        Ok(AnalyzeImageResult {
            file_id,
            decoded_image_size: dims,
            faces,
            clip,
            pet_faces,
            pet_bodies,
            used_coreml: used_providers.coreml,
            used_webgpu: used_providers.webgpu,
        })
    })
}

pub fn run_clip_text(req: RunClipTextRequest) -> MlResult<RunClipTextResult> {
    let RunClipTextRequest {
        text,
        model_path,
        vocab_path,
    } = req;

    if model_path.trim().is_empty() {
        return Err(MlError::InvalidRequest(
            "missing model path: clipTextModelPath".to_string(),
        ));
    }
    if vocab_path.trim().is_empty() {
        return Err(MlError::InvalidRequest(
            "missing model path: clipTextVocabPath".to_string(),
        ));
    }

    let model_paths = ModelPaths {
        face_detection: String::new(),
        face_embedding: String::new(),
        clip_image: String::new(),
        clip_text: model_path,
        pet_face_detection: String::new(),
        pet_face_embedding_dog: String::new(),
        pet_face_embedding_cat: String::new(),
        pet_body_detection: String::new(),
        pet_body_embedding_dog: String::new(),
        pet_body_embedding_cat: String::new(),
    };

    runtime::with_runtime(&model_paths, |runtime| {
        let clip = run_clip_text_query(runtime, &text, &vocab_path)?;
        Ok(RunClipTextResult {
            embedding: clip.embedding,
        })
    })
}

pub fn tokenize_clip_text(text: &str, vocab_path: &str) -> MlResult<Vec<i32>> {
    if vocab_path.trim().is_empty() {
        return Err(MlError::InvalidRequest(
            "missing model path: clipTextVocabPath".to_string(),
        ));
    }
    tokenize_clip_text_impl(text, vocab_path)
}

fn validate_request_model_paths(req: &AnalyzeImageRequest) -> MlResult<()> {
    let model_paths = &req.model_paths;

    let mut missing = Vec::new();
    if req.run_faces {
        if model_paths.face_detection.trim().is_empty() {
            missing.push("faceDetectionModelPath");
        }
        if model_paths.face_embedding.trim().is_empty() {
            missing.push("faceEmbeddingModelPath");
        }
    }
    if req.run_clip && model_paths.clip_image.trim().is_empty() {
        missing.push("clipImageModelPath");
    }
    if req.run_pets {
        if model_paths.pet_face_detection.trim().is_empty() {
            missing.push("petFaceDetectionModelPath");
        }
        if model_paths.pet_body_detection.trim().is_empty() {
            missing.push("petBodyDetectionModelPath");
        }
        if model_paths.pet_face_embedding_dog.trim().is_empty() {
            missing.push("petFaceEmbeddingDogModelPath");
        }
        if model_paths.pet_face_embedding_cat.trim().is_empty() {
            missing.push("petFaceEmbeddingCatModelPath");
        }
        if model_paths.pet_body_embedding_dog.trim().is_empty() {
            missing.push("petBodyEmbeddingDogModelPath");
        }
        if model_paths.pet_body_embedding_cat.trim().is_empty() {
            missing.push("petBodyEmbeddingCatModelPath");
        }
    }
    if missing.is_empty() {
        return Ok(());
    }

    Err(MlError::InvalidRequest(format!(
        "missing required model paths: {}",
        missing.join(", ")
    )))
}
