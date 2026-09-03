pub mod assets;
mod cancel;
mod classify;
mod crop;
mod detect;
mod dictionary;
mod geometry;
mod source;
mod tensor;

pub use crop::Orientation;
pub use detect::ProbabilityMap;
pub use dictionary::load_dictionary;
pub use geometry::Point;

use std::time::Instant;

use thiserror::Error;

use cancel::RequestRegistry;
use classify::{AngleClassifier, AngleDecision};
use crop::crop_text;
use detect::{DetectionCandidate, TextDetector};
use geometry::scale_points;
use source::{REGIONS_CAP, SourceImage, load_source};

use crate::cv::image::ImageU8;
use crate::error::{MlError, MlResult};

const REGION_MIN_SCORE: f32 = 0.5;
const MAX_REGIONS: usize = 1000;

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

#[derive(Clone, Debug, PartialEq)]
pub struct RegionDetectionDebug {
    pub result: TextRegionDetectionResult,
    pub working_width: u32,
    pub working_height: u32,
    pub probability_map: ProbabilityMap,
}

#[derive(Clone, Debug, PartialEq)]
pub struct CropDebug {
    pub width: u32,
    pub height: u32,
    pub rgb: Vec<u8>,
    pub orientation: Orientation,
    pub rotated: bool,
    pub p0: f32,
    pub p180: f32,
}

#[derive(Clone, Debug, PartialEq)]
pub struct CropDetectionDebug {
    pub image_width: u32,
    pub image_height: u32,
    pub candidates: Vec<TextRegion>,
    pub crops: Vec<CropDebug>,
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

pub struct OcrEngine {
    detector: TextDetector,
    classifier: Option<AngleClassifier>,
    requests: RequestRegistry,
}

impl OcrEngine {
    pub fn new(paths: OcrModelPaths) -> MlResult<Self> {
        if paths.detection.is_empty() {
            return Err(MlError::InvalidRequest(
                "OCR detection model path is empty".to_string(),
            ));
        }
        let classifier =
            (!paths.classification.is_empty()).then(|| AngleClassifier::new(&paths.classification));
        Ok(Self {
            detector: TextDetector::new(&paths.detection),
            classifier,
            requests: RequestRegistry::default(),
        })
    }

    fn classifier(&self) -> MlResult<&AngleClassifier> {
        self.classifier.as_ref().ok_or_else(|| {
            MlError::InvalidRequest("OCR classification model path is empty".to_string())
        })
    }

    pub fn detect_text_regions(
        &self,
        req: &DetectRegionsRequest,
    ) -> Result<TextRegionDetectionResult, OcrError> {
        self.detect_text_regions_debug(req)
            .map(|debug| debug.result)
    }

    pub fn detect_text_regions_debug(
        &self,
        req: &DetectRegionsRequest,
    ) -> Result<RegionDetectionDebug, OcrError> {
        let started = Instant::now();
        let request = self.requests.begin(req.request_id.as_deref());
        let source = load_source(&req.image_path, REGIONS_CAP)?;
        request.check()?;
        let detection_started = Instant::now();
        let detection = self.detector.detect(&source.working)?;
        let detection_ms = detection_started.elapsed().as_millis();
        request.check()?;
        let regions = regions_in_decoded_pixels(&detection.candidates, &source);
        log::info!(
            "ocr detect_text_regions: {}x{} -> {}x{}, det {} boxes in {detection_ms}ms, kept {}, total {}ms",
            source.decoded_width,
            source.decoded_height,
            source.working.width,
            source.working.height,
            detection.candidates.len(),
            regions.len(),
            started.elapsed().as_millis()
        );
        Ok(RegionDetectionDebug {
            result: TextRegionDetectionResult {
                regions,
                image_width: source.decoded_width,
                image_height: source.decoded_height,
            },
            working_width: source.working.width as u32,
            working_height: source.working.height as u32,
            probability_map: detection.probability_map,
        })
    }

    pub fn detect_and_crop_debug(
        &self,
        req: &DetectRegionsRequest,
    ) -> Result<CropDetectionDebug, OcrError> {
        let classifier = self.classifier()?;
        let started = Instant::now();
        let request = self.requests.begin(req.request_id.as_deref());
        let source = load_source(&req.image_path, REGIONS_CAP)?;
        request.check()?;
        let detection_started = Instant::now();
        let detection = self.detector.detect(&source.working)?;
        let detection_ms = detection_started.elapsed().as_millis();
        request.check()?;
        let (mut images, orientations) = crop_candidates(&source.working, &detection.candidates)?;
        request.check()?;
        let classification_started = Instant::now();
        let decisions = classifier.classify(&mut images)?;
        let classification_ms = classification_started.elapsed().as_millis();
        request.check()?;
        let crops = crop_debug_entries(images, orientations, &decisions);
        log::info!(
            "ocr detect_and_crop_debug: {}x{} -> {}x{}, det {} boxes in {detection_ms}ms, cls {} crops in {classification_ms}ms, rotated {}, total {}ms",
            source.decoded_width,
            source.decoded_height,
            source.working.width,
            source.working.height,
            detection.candidates.len(),
            crops.len(),
            decisions.iter().filter(|d| d.rotated).count(),
            started.elapsed().as_millis()
        );
        Ok(CropDetectionDebug {
            image_width: source.decoded_width,
            image_height: source.decoded_height,
            candidates: candidates_in_decoded_pixels(&detection.candidates, &source),
            crops,
        })
    }

    pub fn cancel(&self, request_id: &str) {
        self.requests.cancel(request_id);
    }
}

fn crop_candidates(
    working: &ImageU8,
    candidates: &[DetectionCandidate],
) -> MlResult<(Vec<ImageU8>, Vec<Orientation>)> {
    candidates
        .iter()
        .map(|candidate| {
            crop_text(working, &candidate.points).map(|crop| (crop.image, crop.orientation))
        })
        .collect()
}

fn crop_debug_entries(
    images: Vec<ImageU8>,
    orientations: Vec<Orientation>,
    decisions: &[AngleDecision],
) -> Vec<CropDebug> {
    images
        .into_iter()
        .zip(orientations)
        .zip(decisions)
        .map(|((image, orientation), decision)| CropDebug {
            width: image.width as u32,
            height: image.height as u32,
            rgb: image.data,
            orientation,
            rotated: decision.rotated,
            p0: decision.scores.p0,
            p180: decision.scores.p180,
        })
        .collect()
}

fn regions_in_decoded_pixels(
    candidates: &[DetectionCandidate],
    source: &SourceImage,
) -> Vec<TextRegion> {
    let to_region = decoded_region_of(source);
    candidates
        .iter()
        .filter(|candidate| candidate.score >= REGION_MIN_SCORE)
        .take(MAX_REGIONS)
        .map(to_region)
        .collect()
}

fn candidates_in_decoded_pixels(
    candidates: &[DetectionCandidate],
    source: &SourceImage,
) -> Vec<TextRegion> {
    candidates.iter().map(decoded_region_of(source)).collect()
}

fn decoded_region_of(source: &SourceImage) -> impl Fn(&DetectionCandidate) -> TextRegion {
    let scale_x = source.decoded_width as f32 / source.working.width as f32;
    let scale_y = source.decoded_height as f32 / source.working.height as f32;
    move |candidate| TextRegion {
        confidence: candidate.score,
        points: scale_points(&candidate.points, scale_x, scale_y),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn engine_requires_a_detection_model_path() {
        let error = OcrEngine::new(OcrModelPaths {
            detection: String::new(),
            classification: "cls.onnx".to_string(),
            recognition: "rec.onnx".to_string(),
            dictionary: "dict.txt".to_string(),
        })
        .err()
        .expect("empty detection path is rejected");
        assert!(matches!(error, MlError::InvalidRequest(_)), "{error}");
    }

    #[test]
    fn engine_accepts_a_detector_only_path_set_without_loading_it() {
        let engine = OcrEngine::new(OcrModelPaths {
            detection: "missing/det.onnx".to_string(),
            classification: String::new(),
            recognition: String::new(),
            dictionary: String::new(),
        });
        assert!(engine.is_ok());
    }

    #[test]
    fn missing_image_is_reported_before_the_detector_is_touched() {
        let engine = OcrEngine::new(OcrModelPaths {
            detection: "missing/det.onnx".to_string(),
            classification: String::new(),
            recognition: String::new(),
            dictionary: String::new(),
        })
        .unwrap();
        let error = engine
            .detect_text_regions(&DetectRegionsRequest {
                image_path: "missing/image.jpg".to_string(),
                request_id: Some("r1".to_string()),
            })
            .unwrap_err();
        assert!(matches!(error, OcrError::ImageNotFound(_)), "{error}");
    }

    #[test]
    fn regions_scale_from_working_to_decoded_pixels_and_drop_low_scores() {
        let source = SourceImage {
            decoded_width: 2000,
            decoded_height: 1000,
            working: crate::cv::image::ImageU8::zeros(1000, 500, 3).unwrap(),
        };
        let quad = |x: f32, y: f32| {
            [
                Point::new(x, y),
                Point::new(x + 10.0, y),
                Point::new(x + 10.0, y + 5.0),
                Point::new(x, y + 5.0),
            ]
        };
        let candidates = vec![
            DetectionCandidate {
                points: quad(100.0, 50.0),
                score: 0.9,
            },
            DetectionCandidate {
                points: quad(300.0, 50.0),
                score: 0.4,
            },
        ];

        let regions = regions_in_decoded_pixels(&candidates, &source);

        assert_eq!(regions.len(), 1);
        assert_eq!(regions[0].confidence, 0.9);
        assert_eq!(regions[0].points[0], Point::new(200.0, 100.0));
        assert_eq!(regions[0].points[2], Point::new(220.0, 110.0));
    }
}
