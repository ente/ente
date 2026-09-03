mod detect;
mod dictionary;
mod geometry;

pub use detect::{DetectionCandidate, candidates_from_probability_map, sort_reading_order};
pub use dictionary::load_dictionary;
pub use geometry::Point;

use thiserror::Error;

use crate::error::MlError;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct OcrModelPaths {
    pub detection: String,
    pub classification: String,
    pub recognition: String,
    pub dictionary: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DetectTextRequest {
    pub image_path: String,
    pub include_all_confidence_scores: bool,
    pub request_id: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DetectRegionsRequest {
    pub image_path: String,
    pub request_id: Option<String>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct TextBlock {
    pub text: String,
    pub confidence: f32,
    pub points: [Point; 4],
    pub characters: Vec<CharacterBox>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct CharacterBox {
    pub text: String,
    pub confidence: f32,
    pub points: [Point; 4],
}

#[derive(Clone, Debug, PartialEq)]
pub struct TextDetectionResult {
    pub blocks: Vec<TextBlock>,
    pub image_width: u32,
    pub image_height: u32,
}

#[derive(Clone, Debug, PartialEq)]
pub struct TextRegion {
    pub confidence: f32,
    pub points: [Point; 4],
}

#[derive(Clone, Debug, PartialEq)]
pub struct TextRegionDetectionResult {
    pub regions: Vec<TextRegion>,
    pub image_width: u32,
    pub image_height: u32,
}

#[derive(Debug, Error)]
pub enum OcrError {
    #[error("image not found: {0}")]
    ImageNotFound(String),
    #[error("cancelled")]
    Cancelled,
    #[error(transparent)]
    Ml(#[from] MlError),
}
