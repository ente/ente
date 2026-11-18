use crate::{
    clip::{run_clip_image, run_clip_text_query, tokenize_clip_text as tokenize_clip_text_impl},
    diagnostics::{AnalysisContext, AnalysisOperation, AnalysisStage, log_public_ml_error},
    error::{MlError, MlResult},
    face::{
        run_face_alignment, run_face_detection, run_face_embedding,
        thumbnail::{FaceBox, generate_face_thumbnails},
    },
    models::{self, Model, ModelPaths},
    onnx,
    pet::{
        run_pet_body_detection, run_pet_body_embedding, run_pet_face_alignment,
        run_pet_face_detection, run_pet_face_embedding,
    },
    preprocess, runtime,
    types::{self, ClipResult, Dimensions, FaceResult, PetBodyResult, PetFaceResult},
};
use ente_image::{
    BoundedDecodeOptions, BoundedDecodedImage, ImageError, ImageInput,
    decode::{decode_image_from_bytes, decode_image_from_path},
    decode_bounded,
};

#[derive(Clone, Debug)]
pub enum ImageSource {
    Path(String),
    Bytes(Vec<u8>),
}

#[derive(Clone, Debug)]
pub struct AnalyzeImageRequest {
    pub file_id: i64,
    pub source: ImageSource,
    pub run_faces: bool,
    pub run_clip: bool,
    pub run_pets: bool,
    pub generate_face_crops: bool,
    pub model_paths: ModelPaths,
}

#[derive(Clone, Debug)]
pub struct AnalyzeImageResult {
    pub file_id: i64,
    pub decoded_image_size: Dimensions,
    pub faces: Option<Vec<FaceResult>>,
    pub face_crops: Option<Vec<Option<Vec<u8>>>>,
    pub clip: Option<ClipResult>,
    pub pet_faces: Option<Vec<PetFaceResult>>,
    pub pet_bodies: Option<Vec<PetBodyResult>>,
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

// Call before creating sessions; existing sessions keep their configuration.
pub fn set_ml_execution_config(enable_webgpu: bool) {
    onnx::set_webgpu_enabled(enable_webgpu);
}

pub fn set_kleidiai_enabled(enabled: bool) {
    onnx::set_kleidiai_enabled(enabled);
}

pub fn init_ml_runtime(model_paths: ModelPaths) {
    runtime::prepare_runtime(&model_paths);
}

pub fn release_ml_runtime() {
    runtime::release_runtime();
}

pub fn analyze_image(req: AnalyzeImageRequest) -> MlResult<AnalyzeImageResult> {
    let context = AnalysisContext {
        file_id: req.file_id,
        run_faces: req.run_faces,
        run_clip: req.run_clip,
        run_pets: req.run_pets,
    };
    let mut operation = AnalysisOperation::start(context);
    let result = analyze_image_inner(req, &mut operation);
    operation.finish(&result);
    result
}

fn analyze_image_inner(
    req: AnalyzeImageRequest,
    operation: &mut AnalysisOperation,
) -> MlResult<AnalyzeImageResult> {
    validate_request_model_paths(&req)?;

    let AnalyzeImageRequest {
        file_id,
        source,
        run_faces,
        run_clip,
        run_pets,
        generate_face_crops,
        model_paths,
    } = req;

    operation.set_stage(AnalysisStage::RuntimeSetup);
    runtime::with_runtime(&model_paths, |runtime| {
        operation.set_stage(AnalysisStage::DecodeImage);
        let BoundedDecodedImage {
            image: mut decoded,
            original_dimensions,
        } = decode_image(file_id, &source, BoundedDecodeOptions::default())?;
        let detector_input;
        let (face_input, pet_input) = if run_faces || run_pets {
            operation.set_stage(AnalysisStage::YoloPreprocess);
            detector_input = preprocess::preprocess_yolo(&decoded)?;
            (
                run_faces.then_some(&detector_input),
                run_pets.then_some(&detector_input),
            )
        } else {
            (None, None)
        };

        let faces = if let Some(detector_input) = face_input {
            operation.set_stage(AnalysisStage::FaceDetection);
            let detections = run_face_detection(runtime, detector_input)?;
            if detections.is_empty() {
                Some(Vec::new())
            } else {
                operation.set_stage(AnalysisStage::FaceAlignment);
                let (aligned, mut face_results) =
                    run_face_alignment(file_id, &mut decoded, detections)?;
                operation.set_stage(AnalysisStage::FaceEmbedding);
                run_face_embedding(runtime, aligned, &mut face_results)?;
                Some(face_results)
            }
        } else {
            None
        };

        let face_crops = if generate_face_crops {
            operation.set_stage(AnalysisStage::FaceCrops);
            faces.as_ref().map(|face_results| {
                face_results
                    .iter()
                    .map(|face| {
                        let [x_min, y_min, x_max, y_max] = face.detection.box_xyxy;
                        let face_box = FaceBox {
                            x: x_min,
                            y: y_min,
                            width: x_max - x_min,
                            height: y_max - y_min,
                        };
                        match generate_face_thumbnails(&decoded, std::slice::from_ref(&face_box)) {
                            Ok(mut crops) => crops.pop(),
                            Err(error) => {
                                log::warn!("skipping face crop for face {}: {error}", face.face_id);
                                None
                            }
                        }
                    })
                    .collect::<Vec<_>>()
            })
        } else {
            None
        };

        let clip = if run_clip {
            operation.set_stage(AnalysisStage::ClipEmbedding);
            Some(run_clip_image(runtime, &decoded)?)
        } else {
            None
        };

        let (pet_faces, pet_bodies) = if let Some(detector_input) = pet_input {
            operation.set_stage(AnalysisStage::PetFaceDetection);
            let pet_face_detections = run_pet_face_detection(runtime, detector_input)?;
            operation.set_stage(AnalysisStage::PetBodyDetection);
            let body_detections = run_pet_body_detection(runtime, detector_input)?;

            let pet_face_results = if !pet_face_detections.is_empty() {
                operation.set_stage(AnalysisStage::PetFaceAlignment);
                let (aligned, mut pet_results) =
                    run_pet_face_alignment(file_id, &decoded, pet_face_detections)?;
                operation.set_stage(AnalysisStage::PetFaceEmbedding);
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
                operation.set_stage(AnalysisStage::PetBodyEmbedding);
                run_pet_body_embedding(runtime, file_id, &decoded, &mut body_results)?;
            }

            (Some(pet_face_results), Some(body_results))
        } else {
            (None, None)
        };

        operation.set_stage(AnalysisStage::Finalize);
        let provider_usage = runtime.provider_usage();
        Ok(AnalyzeImageResult {
            file_id,
            decoded_image_size: original_dimensions,
            faces,
            face_crops,
            clip,
            pet_faces,
            pet_bodies,
            used_coreml: provider_usage.coreml,
            used_webgpu: provider_usage.webgpu,
        })
    })
}

fn decode_image(
    file_id: i64,
    source: &ImageSource,
    options: BoundedDecodeOptions,
) -> MlResult<BoundedDecodedImage> {
    let input = match source {
        ImageSource::Path(path) => ImageInput::Path(path),
        ImageSource::Bytes(bytes) => ImageInput::Bytes(bytes),
    };
    match decode_bounded(input, options) {
        Err(ImageError::Decode(reason)) => {
            log::info!("Rust ML bounded decode refused: file_id={file_id} reason={reason}");
            let image = match source {
                ImageSource::Path(path) => decode_image_from_path(path)?,
                ImageSource::Bytes(bytes) => decode_image_from_bytes(bytes)?,
            };
            Ok(BoundedDecodedImage {
                original_dimensions: image.dimensions.clone(),
                image,
            })
        }
        result => result.map_err(MlError::from),
    }
}

pub fn run_clip_text(req: RunClipTextRequest) -> MlResult<RunClipTextResult> {
    let result = (|| {
        let RunClipTextRequest {
            text,
            model_path,
            vocab_path,
        } = req;

        if model_path.trim().is_empty() {
            return Err(MlError::InvalidRequest(format!(
                "missing model path: {}",
                Model::ClipText.path_label()
            )));
        }
        if vocab_path.trim().is_empty() {
            return Err(MlError::InvalidRequest(
                "missing model path: clipTextVocabPath".to_string(),
            ));
        }

        let mut model_paths = ModelPaths::default();
        *model_paths.get_mut(Model::ClipText) = model_path;

        runtime::with_runtime(&model_paths, |runtime| {
            let clip = run_clip_text_query(runtime, &text, &vocab_path)?;
            Ok(RunClipTextResult {
                embedding: clip.embedding,
            })
        })
    })();
    if let Err(error) = &result {
        log_public_ml_error("run_clip_text", error);
    }
    result
}

pub fn tokenize_clip_text(text: &str, vocab_path: &str) -> MlResult<Vec<i32>> {
    let result = if vocab_path.trim().is_empty() {
        Err(MlError::InvalidRequest(
            "missing model path: clipTextVocabPath".to_string(),
        ))
    } else {
        tokenize_clip_text_impl(text, vocab_path)
    };
    if let Err(error) = &result {
        log_public_ml_error("tokenize_clip_text", error);
    }
    result
}

fn validate_request_model_paths(req: &AnalyzeImageRequest) -> MlResult<()> {
    let missing = models::selected_indexing_models(req.run_faces, req.run_clip, req.run_pets)
        .filter(|&model| req.model_paths.get(model).trim().is_empty())
        .map(Model::path_label)
        .collect::<Vec<_>>();
    if missing.is_empty() {
        return Ok(());
    }

    Err(MlError::InvalidRequest(format!(
        "missing required model paths: {}",
        missing.join(", ")
    )))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn request_with_models(run_faces: bool, run_clip: bool, run_pets: bool) -> AnalyzeImageRequest {
        AnalyzeImageRequest {
            file_id: 1,
            source: ImageSource::Bytes(Vec::new()),
            run_faces,
            run_clip,
            run_pets,
            generate_face_crops: false,
            model_paths: ModelPaths::default(),
        }
    }

    fn validation_error(req: &AnalyzeImageRequest) -> String {
        match validate_request_model_paths(req) {
            Err(MlError::InvalidRequest(message)) => message,
            other => panic!("expected an invalid request, got {other:?}"),
        }
    }

    fn encoded_image(width: u32, height: u32, format: image::ImageFormat) -> Vec<u8> {
        let img =
            image::RgbImage::from_fn(width, height, |x, y| image::Rgb([x as u8, y as u8, 128]));
        let mut bytes = std::io::Cursor::new(Vec::new());
        image::DynamicImage::ImageRgb8(img)
            .write_to(&mut bytes, format)
            .expect("image encoding succeeds");
        bytes.into_inner()
    }

    fn dimensions(width: u32, height: u32) -> Dimensions {
        Dimensions { width, height }
    }

    #[test]
    fn large_images_are_downsampled_and_keep_their_original_size() {
        let source = ImageSource::Bytes(encoded_image(6400, 8, image::ImageFormat::Png));
        let BoundedDecodedImage {
            image,
            original_dimensions,
        } = decode_image(1, &source, BoundedDecodeOptions::default()).unwrap();
        assert_eq!(image.dimensions, dimensions(6000, 7));
        assert_eq!(image.rgb.len(), 6000 * 7 * 3);
        assert_eq!(original_dimensions, dimensions(6400, 8));

        let req = AnalyzeImageRequest {
            source,
            ..request_with_models(false, false, false)
        };
        let result = analyze_image(req).unwrap();
        assert_eq!(result.decoded_image_size, dimensions(6400, 8));
    }

    #[test]
    fn formats_without_bounded_decoding_use_the_full_decoder() {
        let source = ImageSource::Bytes(encoded_image(6400, 8, image::ImageFormat::WebP));
        let BoundedDecodedImage {
            image,
            original_dimensions,
        } = decode_image(1, &source, BoundedDecodeOptions::default()).unwrap();
        assert_eq!(image.dimensions, dimensions(6400, 8));
        assert_eq!(original_dimensions, dimensions(6400, 8));
    }

    #[test]
    fn only_decode_failures_fall_back_to_the_full_decoder() {
        let bytes = encoded_image(512, 512, image::ImageFormat::Png);
        assert!(decode_image_from_bytes(&bytes).is_ok());
        let source = ImageSource::Bytes(bytes);
        let too_large = BoundedDecodeOptions {
            max_memory_bytes: 64 * 1024,
            ..BoundedDecodeOptions::default()
        };
        assert!(matches!(
            decode_image(1, &source, too_large),
            Err(MlError::Decode(_))
        ));
        let invalid = BoundedDecodeOptions {
            max_side: 0,
            ..BoundedDecodeOptions::default()
        };
        assert!(matches!(
            decode_image(1, &source, invalid),
            Err(MlError::Image(_))
        ));
    }

    #[test]
    fn analyze_image_decodes_from_bytes() {
        let req = AnalyzeImageRequest {
            file_id: 1,
            source: ImageSource::Bytes(encoded_image(64, 48, image::ImageFormat::Png)),
            run_faces: false,
            run_clip: false,
            run_pets: false,
            generate_face_crops: false,
            model_paths: ModelPaths::default(),
        };

        let result = analyze_image(req).expect("analysis without models succeeds");
        assert_eq!(result.decoded_image_size.width, 64);
        assert_eq!(result.decoded_image_size.height, 48);
        assert!(result.faces.is_none());
        assert!(result.face_crops.is_none());
        assert!(result.clip.is_none());
    }

    #[test]
    fn analyze_image_rejects_undecodable_bytes() {
        let req = AnalyzeImageRequest {
            file_id: 1,
            source: ImageSource::Bytes(vec![0u8; 16]),
            run_faces: false,
            run_clip: false,
            run_pets: false,
            generate_face_crops: false,
            model_paths: ModelPaths::default(),
        };

        match analyze_image(req) {
            Err(MlError::Decode(_)) => {}
            other => panic!("expected a decode error, got {other:?}"),
        }
    }

    #[test]
    fn request_validation_reports_required_models_in_catalog_order() {
        let req = request_with_models(true, true, true);

        assert_eq!(
            validation_error(&req),
            "missing required model paths: faceDetectionModelPath, faceEmbeddingModelPath, \
             clipImageModelPath, petFaceDetectionModelPath, petBodyDetectionModelPath, \
             petFaceEmbeddingDogModelPath, petFaceEmbeddingCatModelPath, \
             petBodyEmbeddingDogModelPath, petBodyEmbeddingCatModelPath"
        );
    }

    #[test]
    fn request_validation_uses_only_enabled_model_groups() {
        assert_eq!(
            validation_error(&request_with_models(true, false, false)),
            "missing required model paths: faceDetectionModelPath, faceEmbeddingModelPath"
        );
        assert_eq!(
            validation_error(&request_with_models(false, true, false)),
            "missing required model paths: clipImageModelPath"
        );
        assert_eq!(
            validation_error(&request_with_models(false, false, true)),
            "missing required model paths: petFaceDetectionModelPath, petBodyDetectionModelPath, \
             petFaceEmbeddingDogModelPath, petFaceEmbeddingCatModelPath, \
             petBodyEmbeddingDogModelPath, petBodyEmbeddingCatModelPath"
        );
    }

    #[test]
    fn request_validation_accepts_all_required_model_paths() {
        let mut req = request_with_models(true, true, true);
        for model in Model::INDEXING {
            *req.model_paths.get_mut(model) = format!("{}.onnx", model.namespace());
        }

        validate_request_model_paths(&req).unwrap();
    }
}
