use std::path::Path;

use ente_ml::error::MlError;
use ente_ml::ocr;
use flutter_rust_bridge::frb;

#[derive(Clone, Debug)]
pub struct RustOcrModelPaths {
    pub detection: String,
    pub classification: String,
    pub recognition: String,
    pub dictionary: String,
}

#[derive(Clone, Copy, Debug)]
pub struct RustOcrPoint {
    pub x: f64,
    pub y: f64,
}

#[derive(Clone, Debug)]
pub struct RustCharacterBox {
    pub text: String,
    pub confidence: f64,
    pub points: Vec<RustOcrPoint>,
}

#[derive(Clone, Debug)]
pub struct RustTextBlock {
    pub text: String,
    pub confidence: f64,
    pub points: Vec<RustOcrPoint>,
    pub characters: Vec<RustCharacterBox>,
}

#[derive(Clone, Debug)]
pub struct RustTextDetectionResult {
    pub blocks: Vec<RustTextBlock>,
    pub image_width: u32,
    pub image_height: u32,
}

#[derive(Clone, Debug)]
pub struct RustTextRegion {
    pub confidence: f64,
    pub points: Vec<RustOcrPoint>,
}

#[derive(Clone, Debug)]
pub struct RustTextRegionDetectionResult {
    pub regions: Vec<RustTextRegion>,
    pub image_width: u32,
    pub image_height: u32,
}

#[derive(Clone, Debug)]
pub enum RustOcrError {
    ImageNotFound { message: String },
    InvalidImage { message: String },
    Cancelled,
    CorruptModel { message: String },
    Other { message: String },
}

#[frb(opaque)]
pub struct OcrEngine {
    inner: ocr::OcrEngine,
}

impl OcrEngine {
    pub fn create(paths: RustOcrModelPaths) -> Result<OcrEngine, RustOcrError> {
        ocr::OcrEngine::new(to_model_paths(paths))
            .map(|inner| OcrEngine { inner })
            .map_err(|error| {
                let error = RustOcrError::from(ocr::OcrError::Ml(error));
                log::log!(
                    error.log_level(),
                    "Rust OCR create failed: {}",
                    error.description()
                );
                error
            })
    }

    pub fn detect_text(
        &self,
        image_path: String,
        include_all_confidence_scores: bool,
        request_id: Option<String>,
    ) -> Result<RustTextDetectionResult, RustOcrError> {
        let request = ocr::DetectTextRequest {
            image_path,
            include_all_confidence_scores,
            request_id,
        };
        self.inner
            .detect_text(&request)
            .map(to_api_text_detection_result)
            .map_err(|error| logged_failure("detect_text", &request.image_path, error))
    }

    pub fn detect_text_regions(
        &self,
        image_path: String,
        request_id: Option<String>,
    ) -> Result<RustTextRegionDetectionResult, RustOcrError> {
        let request = ocr::DetectRegionsRequest {
            image_path,
            request_id,
        };
        self.inner
            .detect_text_regions(&request)
            .map(to_api_text_region_detection_result)
            .map_err(|error| logged_failure("detect_text_regions", &request.image_path, error))
    }

    #[frb(sync)]
    pub fn cancel(&self, request_id: String) {
        self.inner.cancel(&request_id);
    }
}

impl RustOcrError {
    fn log_level(&self) -> log::Level {
        match self {
            Self::ImageNotFound { .. } | Self::InvalidImage { .. } | Self::Cancelled => {
                log::Level::Warn
            }
            Self::CorruptModel { .. } | Self::Other { .. } => log::Level::Error,
        }
    }

    fn description(&self) -> String {
        match self {
            Self::ImageNotFound { .. } => "image not found".to_string(),
            Self::InvalidImage { message } => format!("invalid image: {message}"),
            Self::Cancelled => "cancelled".to_string(),
            Self::CorruptModel { message } => format!("corrupt model: {message}"),
            Self::Other { message } => message.clone(),
        }
    }
}

impl From<ocr::OcrError> for RustOcrError {
    fn from(value: ocr::OcrError) -> Self {
        match value {
            error @ ocr::OcrError::ImageNotFound(_) => Self::ImageNotFound {
                message: error.to_string(),
            },
            ocr::OcrError::Cancelled => Self::Cancelled,
            ocr::OcrError::Ml(MlError::Decode(message) | MlError::Image(message)) => {
                Self::InvalidImage { message }
            }
            ocr::OcrError::Ml(MlError::CorruptModel(message)) => Self::CorruptModel { message },
            ocr::OcrError::Ml(
                error @ (MlError::InvalidRequest(_)
                | MlError::Preprocess(_)
                | MlError::Ort(_)
                | MlError::Postprocess(_)
                | MlError::Runtime(_)),
            ) => Self::Other {
                message: error.to_string(),
            },
        }
    }
}

fn logged_failure(operation: &str, image_path: &str, error: ocr::OcrError) -> RustOcrError {
    let error = RustOcrError::from(error);
    log::log!(
        error.log_level(),
        "Rust OCR {operation} failed for {}: {}",
        image_file_name(image_path),
        error.description()
    );
    error
}

fn image_file_name(image_path: &str) -> String {
    Path::new(image_path)
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_default()
}

fn to_model_paths(paths: RustOcrModelPaths) -> ocr::OcrModelPaths {
    ocr::OcrModelPaths {
        detection: paths.detection,
        classification: paths.classification,
        recognition: paths.recognition,
        dictionary: paths.dictionary,
    }
}

fn to_api_points(points: &[ocr::Point; 4]) -> Vec<RustOcrPoint> {
    points
        .iter()
        .map(|point| RustOcrPoint {
            x: f64::from(point.x),
            y: f64::from(point.y),
        })
        .collect()
}

fn to_api_text_detection_result(result: ocr::TextDetectionResult) -> RustTextDetectionResult {
    RustTextDetectionResult {
        blocks: result.blocks.into_iter().map(to_api_text_block).collect(),
        image_width: result.image_width,
        image_height: result.image_height,
    }
}

fn to_api_text_block(block: ocr::TextBlock) -> RustTextBlock {
    RustTextBlock {
        text: block.text,
        confidence: f64::from(block.confidence),
        points: to_api_points(&block.points),
        characters: block
            .characters
            .into_iter()
            .map(to_api_character_box)
            .collect(),
    }
}

fn to_api_character_box(character: ocr::CharacterBox) -> RustCharacterBox {
    RustCharacterBox {
        text: character.text,
        confidence: f64::from(character.confidence),
        points: to_api_points(&character.points),
    }
}

fn to_api_text_region_detection_result(
    result: ocr::TextRegionDetectionResult,
) -> RustTextRegionDetectionResult {
    RustTextRegionDetectionResult {
        regions: result.regions.into_iter().map(to_api_text_region).collect(),
        image_width: result.image_width,
        image_height: result.image_height,
    }
}

fn to_api_text_region(region: ocr::TextRegion) -> RustTextRegion {
    RustTextRegion {
        confidence: f64::from(region.confidence),
        points: to_api_points(&region.points),
    }
}
