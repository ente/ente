use ente_ml::{
    ModelPaths as SharedModelPaths, assets, error::MlError, indexing as shared_indexing,
    types as shared_types,
};
use napi::bindgen_prelude::*;
use napi_derive::napi;

mod log;
pub use log::init_logging;

#[napi]
pub fn init_ort(dylib_path: String) -> Result<()> {
    ort::init_from(&dylib_path)
        .map_err(|error| {
            Error::from_reason(format!(
                "Runtime: failed to load ONNX Runtime library from '{dylib_path}': {error}"
            ))
        })?
        .commit();
    Ok(())
}

#[napi]
pub fn set_ml_execution_config(enable_webgpu: bool) {
    shared_indexing::set_ml_execution_config(enable_webgpu);
}

#[napi]
pub fn init_ml_runtime(model_paths: ModelPaths) {
    shared_indexing::init_ml_runtime(to_shared_model_paths(&model_paths));
}

#[napi]
pub fn release_ml_runtime() {
    shared_indexing::release_ml_runtime();
}

#[napi(object)]
pub struct ModelPaths {
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

#[napi(object)]
pub struct ClipTextModelPaths {
    pub model_path: String,
    pub vocab_path: String,
}

#[napi]
pub struct AssetStore {
    inner: ente_assets::AssetStore,
}

#[napi]
impl AssetStore {
    #[napi(constructor)]
    pub fn new(assets_dir: String, legacy_models_dir: String) -> Self {
        let inner = ente_assets::AssetStore::new(assets_dir);
        for warning in
            assets::migrate_desktop_models(&inner, std::path::Path::new(&legacy_models_dir))
        {
            ::log::warn!("Photos model migration: {warning}");
        }
        Self { inner }
    }

    #[napi]
    pub async fn indexing_model_paths(
        &self,
        run_faces: bool,
        run_clip: bool,
        run_pets: bool,
    ) -> Result<ModelPaths> {
        let model_assets = assets::indexing_assets(run_faces, run_clip, run_pets);
        self.inner
            .download(
                &model_assets,
                |_| {},
                ente_assets::download::CancellationToken::default(),
            )
            .await
            .map_err(asset_error_to_napi)?;
        Ok(to_napi_model_paths(assets::indexing_model_paths(
            &self.inner,
            run_faces,
            run_clip,
            run_pets,
        )))
    }

    #[napi]
    pub async fn clip_text_model_paths(&self) -> Result<ClipTextModelPaths> {
        let asset = assets::clip_text_asset();
        self.inner
            .download(
                std::slice::from_ref(&asset),
                |_| {},
                ente_assets::download::CancellationToken::default(),
            )
            .await
            .map_err(asset_error_to_napi)?;
        let paths = assets::clip_text_paths(&self.inner);
        Ok(ClipTextModelPaths {
            model_path: paths.model.to_string_lossy().into_owned(),
            vocab_path: paths.vocab.to_string_lossy().into_owned(),
        })
    }
}

#[napi(object)]
pub struct AnalyzeImageRequest {
    pub file_id: i64,
    pub image_bytes: Buffer,
    pub run_faces: bool,
    pub run_clip: bool,
    pub run_pets: bool,
    pub generate_face_crops: bool,
    pub model_paths: ModelPaths,
}

#[napi(object)]
pub struct Dimensions {
    pub width: u32,
    pub height: u32,
}

#[napi(object)]
pub struct FaceDetection {
    pub score: f64,
    pub box_xyxy: Vec<f64>,
    pub keypoints: Vec<Vec<f64>>,
}

#[napi(object)]
pub struct FaceResult {
    pub face_id: String,
    pub detection: FaceDetection,
    pub blur_value: f64,
    pub embedding: Float32Array,
}

#[napi(object)]
pub struct ClipResult {
    pub embedding: Float32Array,
}

#[napi(object)]
pub struct PetFaceResult {
    pub pet_face_id: String,
    pub score: f64,
    pub box_xyxy: Vec<f64>,
    pub keypoints: Vec<Vec<f64>>,
    pub species: u32,
    pub face_embedding: Float32Array,
}

#[napi(object)]
pub struct PetBodyResult {
    pub pet_body_id: String,
    pub score: f64,
    pub box_xyxy: Vec<f64>,
    pub coco_class: u32,
    pub body_embedding: Float32Array,
}

#[napi(object)]
pub struct AnalyzeImageResult {
    pub file_id: i64,
    pub decoded_image_size: Dimensions,
    pub faces: Option<Vec<FaceResult>>,
    pub face_crops: Option<Vec<Option<Buffer>>>,
    pub clip: Option<ClipResult>,
    pub pet_faces: Option<Vec<PetFaceResult>>,
    pub pet_bodies: Option<Vec<PetBodyResult>>,
    pub used_coreml: bool,
    pub used_webgpu: bool,
}

pub struct AnalyzeImageTask {
    req: Option<shared_indexing::AnalyzeImageRequest>,
}

impl Task for AnalyzeImageTask {
    // Retain MlError until resolve, where the JS thread can assign Error.name.
    type Output = std::result::Result<shared_indexing::AnalyzeImageResult, MlError>;
    type JsValue = AnalyzeImageResult;

    fn compute(&mut self) -> Result<Self::Output> {
        let req = self
            .req
            .take()
            .ok_or_else(|| Error::from_reason("Runtime: analyze task computed twice"))?;
        Ok(shared_indexing::analyze_image(req))
    }

    fn resolve(&mut self, env: Env, output: Self::Output) -> Result<Self::JsValue> {
        match output {
            Ok(output) => Ok(to_napi_analyze_image_result(output)),
            Err(error) => Err(ml_error_to_napi(&env, error)?),
        }
    }
}

#[napi(ts_return_type = "Promise<AnalyzeImageResult>")]
pub fn analyze_image(req: AnalyzeImageRequest) -> AsyncTask<AnalyzeImageTask> {
    AsyncTask::new(AnalyzeImageTask {
        req: Some(shared_indexing::AnalyzeImageRequest {
            file_id: req.file_id,
            source: shared_indexing::ImageSource::Bytes(req.image_bytes.to_vec()),
            run_faces: req.run_faces,
            run_clip: req.run_clip,
            run_pets: req.run_pets,
            generate_face_crops: req.generate_face_crops,
            model_paths: to_shared_model_paths(&req.model_paths),
        }),
    })
}

#[napi(object)]
pub struct RunClipTextRequest {
    pub text: String,
    pub model_path: String,
    pub vocab_path: String,
}

#[napi(object)]
pub struct RunClipTextResult {
    pub embedding: Float32Array,
}

pub struct RunClipTextTask {
    req: Option<shared_indexing::RunClipTextRequest>,
}

impl Task for RunClipTextTask {
    type Output = shared_indexing::RunClipTextResult;
    type JsValue = RunClipTextResult;

    fn compute(&mut self) -> Result<Self::Output> {
        let req = self
            .req
            .take()
            .ok_or_else(|| Error::from_reason("Runtime: clip text task computed twice"))?;
        shared_indexing::run_clip_text(req).map_err(|error| Error::from_reason(error.to_string()))
    }

    fn resolve(&mut self, _env: Env, output: Self::Output) -> Result<Self::JsValue> {
        Ok(RunClipTextResult {
            embedding: output.embedding.into(),
        })
    }
}

#[napi(ts_return_type = "Promise<RunClipTextResult>")]
pub fn run_clip_text(req: RunClipTextRequest) -> AsyncTask<RunClipTextTask> {
    AsyncTask::new(RunClipTextTask {
        req: Some(shared_indexing::RunClipTextRequest {
            text: req.text,
            model_path: req.model_path,
            vocab_path: req.vocab_path,
        }),
    })
}

#[napi]
pub fn tokenize_clip_text(text: String, vocab_path: String) -> Result<Vec<i32>> {
    shared_indexing::tokenize_clip_text(&text, &vocab_path)
        .map_err(|error| Error::from_reason(error.to_string()))
}

fn ml_error_to_napi(env: &Env, error: MlError) -> Result<Error> {
    let name = match &error {
        MlError::CorruptModel(_) => "ml_init",
        MlError::Decode(_) => "ml_decode",
        MlError::Image(_) => "ml_image",
        _ => return Ok(Error::from_reason(error.to_string())),
    };
    let mut value = env.create_error(Error::from_reason(error.to_string()))?;
    value.set_named_property("name", name)?;
    Ok(Error::from(value.into_unknown(env)?))
}

fn asset_error_to_napi(error: ente_assets::download::Error) -> Error {
    Error::from_reason(format!("Assets: {error}"))
}

fn to_shared_model_paths(paths: &ModelPaths) -> SharedModelPaths {
    SharedModelPaths {
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

fn to_napi_model_paths(paths: SharedModelPaths) -> ModelPaths {
    ModelPaths {
        face_detection: paths.face_detection,
        face_embedding: paths.face_embedding,
        clip_image: paths.clip_image,
        clip_text: paths.clip_text,
        pet_face_detection: paths.pet_face_detection,
        pet_face_embedding_dog: paths.pet_face_embedding_dog,
        pet_face_embedding_cat: paths.pet_face_embedding_cat,
        pet_body_detection: paths.pet_body_detection,
        pet_body_embedding_dog: paths.pet_body_embedding_dog,
        pet_body_embedding_cat: paths.pet_body_embedding_cat,
    }
}

fn to_napi_analyze_image_result(result: shared_indexing::AnalyzeImageResult) -> AnalyzeImageResult {
    AnalyzeImageResult {
        file_id: result.file_id,
        decoded_image_size: Dimensions {
            width: result.decoded_image_size.width,
            height: result.decoded_image_size.height,
        },
        faces: result
            .faces
            .map(|faces| faces.into_iter().map(to_napi_face_result).collect()),
        face_crops: result.face_crops.map(|crops| {
            crops
                .into_iter()
                .map(|crop| crop.map(Buffer::from))
                .collect()
        }),
        clip: result.clip.map(|clip| ClipResult {
            embedding: clip.embedding.into(),
        }),
        pet_faces: result
            .pet_faces
            .map(|faces| faces.into_iter().map(to_napi_pet_face_result).collect()),
        pet_bodies: result
            .pet_bodies
            .map(|bodies| bodies.into_iter().map(to_napi_pet_body_result).collect()),
        used_coreml: result.used_coreml,
        used_webgpu: result.used_webgpu,
    }
}

fn to_napi_face_result(result: shared_types::FaceResult) -> FaceResult {
    FaceResult {
        face_id: result.face_id,
        detection: FaceDetection {
            score: f64::from(result.detection.score),
            box_xyxy: result
                .detection
                .box_xyxy
                .into_iter()
                .map(f64::from)
                .collect(),
            keypoints: result
                .detection
                .keypoints
                .into_iter()
                .map(|point| point.into_iter().map(f64::from).collect())
                .collect(),
        },
        blur_value: f64::from(result.blur_value),
        embedding: result.embedding.into(),
    }
}

fn to_napi_pet_face_result(result: shared_types::PetFaceResult) -> PetFaceResult {
    PetFaceResult {
        pet_face_id: result.pet_face_id,
        score: f64::from(result.detection.score),
        box_xyxy: result
            .detection
            .box_xyxy
            .into_iter()
            .map(f64::from)
            .collect(),
        keypoints: result
            .detection
            .keypoints
            .into_iter()
            .map(|point| point.into_iter().map(f64::from).collect())
            .collect(),
        species: u32::from(result.species),
        face_embedding: result.face_embedding.into(),
    }
}

fn to_napi_pet_body_result(result: shared_types::PetBodyResult) -> PetBodyResult {
    PetBodyResult {
        pet_body_id: result.pet_body_id,
        score: f64::from(result.detection.score),
        box_xyxy: result
            .detection
            .box_xyxy
            .into_iter()
            .map(f64::from)
            .collect(),
        coco_class: u32::from(result.detection.coco_class),
        body_embedding: result.body_embedding.into(),
    }
}
