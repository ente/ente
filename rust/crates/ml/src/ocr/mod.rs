pub mod assets;
mod cancel;
mod characters;
mod classify;
mod crop;
mod detect;
mod dictionary;
mod geometry;
mod recognize;
mod source;
mod tensor;

pub use crop::Orientation;
pub use detect::ProbabilityMap;
pub use geometry::Point;

use std::time::Instant;

use thiserror::Error;

use cancel::{RequestGuard, RequestRegistry};
use characters::character_boxes;
use classify::AngleClassifier;
use crop::{TextCrop, crop_text};
use detect::{DetectionCandidate, TextDetector};
use geometry::scale_points;
use recognize::{Recognition, TextRecognizer};
use source::{FULL_TEXT_CAP, REGIONS_CAP, SourceImage, load_source};

use crate::cv;
use crate::cv::image::ImageU8;
use crate::error::{MlError, MlResult};

const REGION_MIN_SCORE: f32 = 0.5;
const MAX_REGIONS: usize = 1000;
const MIN_BLOCK_CONFIDENCE: f32 = 0.8;
const MIN_BLOCK_CONFIDENCE_WITH_ALL_SCORES: f32 = 0.5;
const RETRY_BELOW_CONFIDENCE: f32 = 0.65;

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
    pub text: String,
    pub confidence: f32,
}

#[derive(Clone, Debug, PartialEq)]
pub struct TextDetectionDebug {
    pub result: TextDetectionResult,
    pub working_width: u32,
    pub working_height: u32,
    pub probability_map: ProbabilityMap,
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
    recognizer: Option<TextRecognizer>,
    missing_text_model_paths: Vec<&'static str>,
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
        let recognizer = (!paths.recognition.is_empty())
            .then(|| TextRecognizer::new(&paths.recognition, &paths.dictionary));
        Ok(Self {
            detector: TextDetector::new(&paths.detection),
            classifier,
            recognizer,
            missing_text_model_paths: missing_text_model_paths(&paths),
            requests: RequestRegistry::default(),
        })
    }

    fn text_models(&self) -> MlResult<(&AngleClassifier, &TextRecognizer)> {
        match (&self.classifier, &self.recognizer) {
            (Some(classifier), Some(recognizer)) if self.missing_text_model_paths.is_empty() => {
                Ok((classifier, recognizer))
            }
            _ => Err(MlError::InvalidRequest(format!(
                "OCR model paths are empty: {}",
                self.missing_text_model_paths.join(", ")
            ))),
        }
    }

    pub fn detect_text(&self, req: &DetectTextRequest) -> Result<TextDetectionResult, OcrError> {
        self.run_text_pipeline(req).map(TextPipeline::into_result)
    }

    pub fn detect_text_debug(
        &self,
        req: &DetectTextRequest,
    ) -> Result<TextDetectionDebug, OcrError> {
        self.run_text_pipeline(req).map(TextPipeline::into_debug)
    }

    fn run_text_pipeline(&self, req: &DetectTextRequest) -> Result<TextPipeline, OcrError> {
        let (classifier, recognizer) = self.text_models()?;
        let started = Instant::now();
        let request = self.requests.begin(req.request_id.as_deref());
        let source = load_source(&req.image_path, FULL_TEXT_CAP)?;
        request.check()?;
        let detection_started = Instant::now();
        let detection = self.detector.detect(&source.working)?;
        let detection_ms = detection_started.elapsed().as_millis();
        request.check()?;
        let crops = crop_candidates(&source.working, &detection.candidates)?;
        request.check()?;
        let recognition_started = Instant::now();
        let mut recognized = recognize_crops(recognizer, crops, &request)?;
        request.check()?;
        let retries = retry_low_confidence(classifier, recognizer, &mut recognized, &request)?;
        let recognition_ms = recognition_started.elapsed().as_millis();
        request.check()?;
        let blocks = text_blocks(
            &detection.candidates,
            &recognized,
            &source,
            min_block_confidence(req.include_all_confidence_scores),
        );
        log::info!(
            "ocr detect_text: {}x{} -> {}x{}, det {} boxes in {detection_ms}ms, rec {} crops in {recognition_ms}ms, cls retries {retries}, kept {}, total {}ms",
            source.decoded_width,
            source.decoded_height,
            source.working.width,
            source.working.height,
            detection.candidates.len(),
            recognized.len(),
            blocks.len(),
            started.elapsed().as_millis()
        );
        Ok(TextPipeline {
            image_width: source.decoded_width,
            image_height: source.decoded_height,
            working_width: source.working.width as u32,
            working_height: source.working.height as u32,
            probability_map: detection.probability_map,
            crops: recognized,
            blocks,
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

    pub fn cancel(&self, request_id: &str) {
        self.requests.cancel(request_id);
    }
}

fn missing_text_model_paths(paths: &OcrModelPaths) -> Vec<&'static str> {
    [
        ("classification", &paths.classification),
        ("recognition", &paths.recognition),
        ("dictionary", &paths.dictionary),
    ]
    .into_iter()
    .filter(|(_, path)| path.is_empty())
    .map(|(name, _)| name)
    .collect()
}

fn min_block_confidence(include_all_confidence_scores: bool) -> f32 {
    if include_all_confidence_scores {
        MIN_BLOCK_CONFIDENCE_WITH_ALL_SCORES
    } else {
        MIN_BLOCK_CONFIDENCE
    }
}

struct TextPipeline {
    image_width: u32,
    image_height: u32,
    working_width: u32,
    working_height: u32,
    probability_map: ProbabilityMap,
    crops: Vec<RecognizedCrop>,
    blocks: Vec<TextBlock>,
}

impl TextPipeline {
    fn into_result(self) -> TextDetectionResult {
        TextDetectionResult {
            blocks: self.blocks,
            image_width: self.image_width,
            image_height: self.image_height,
        }
    }

    fn into_debug(self) -> TextDetectionDebug {
        let crops = self
            .crops
            .into_iter()
            .map(RecognizedCrop::into_debug)
            .collect();
        TextDetectionDebug {
            result: TextDetectionResult {
                blocks: self.blocks,
                image_width: self.image_width,
                image_height: self.image_height,
            },
            working_width: self.working_width,
            working_height: self.working_height,
            probability_map: self.probability_map,
            crops,
        }
    }
}

struct RecognizedCrop {
    image: ImageU8,
    orientation: Orientation,
    rotated: bool,
    recognition: Recognition,
}

impl RecognizedCrop {
    fn upright(crop: TextCrop, recognition: Recognition) -> Self {
        Self {
            image: crop.image,
            orientation: crop.orientation,
            rotated: false,
            recognition,
        }
    }

    fn prefer_rotated(&mut self, image: ImageU8, recognition: Recognition) {
        if recognition.confidence > self.recognition.confidence {
            self.image = image;
            self.rotated = true;
            self.recognition = recognition;
        }
    }

    fn needs_retry(&self) -> bool {
        self.orientation == Orientation::Horizontal
            && self.recognition.confidence < RETRY_BELOW_CONFIDENCE
    }

    fn into_debug(self) -> CropDebug {
        CropDebug {
            width: self.image.width as u32,
            height: self.image.height as u32,
            rgb: self.image.data,
            orientation: self.orientation,
            rotated: self.rotated,
            text: self.recognition.text,
            confidence: self.recognition.confidence,
        }
    }
}

fn crop_candidates(
    working: &ImageU8,
    candidates: &[DetectionCandidate],
) -> MlResult<Vec<TextCrop>> {
    candidates
        .iter()
        .map(|candidate| crop_text(working, &candidate.points))
        .collect()
}

fn recognize_crops(
    recognizer: &TextRecognizer,
    crops: Vec<TextCrop>,
    request: &RequestGuard<'_>,
) -> Result<Vec<RecognizedCrop>, OcrError> {
    let flipped = crops
        .iter()
        .map(flipped_if_vertical)
        .collect::<MlResult<Vec<_>>>()?;
    let inputs: Vec<&ImageU8> = crops
        .iter()
        .zip(&flipped)
        .flat_map(|(crop, flipped)| std::iter::once(&crop.image).chain(flipped))
        .collect();
    let mut results = recognizer.recognize(&inputs, request)?.into_iter();
    crops
        .into_iter()
        .zip(flipped)
        .map(|(crop, flipped)| {
            let mut recognized = RecognizedCrop::upright(crop, next_recognition(&mut results)?);
            if let Some(image) = flipped {
                recognized.prefer_rotated(image, next_recognition(&mut results)?);
            }
            Ok(recognized)
        })
        .collect()
}

fn flipped_if_vertical(crop: &TextCrop) -> MlResult<Option<ImageU8>> {
    match crop.orientation {
        Orientation::Vertical => cv::rotate_u8(&crop.image, 180)
            .map(Some)
            .map_err(MlError::Preprocess),
        Orientation::Horizontal => Ok(None),
    }
}

fn next_recognition(results: &mut impl Iterator<Item = Recognition>) -> MlResult<Recognition> {
    results.next().ok_or_else(|| {
        MlError::CorruptModel("text recognizer returned fewer results than crops".to_string())
    })
}

fn retry_low_confidence(
    classifier: &AngleClassifier,
    recognizer: &TextRecognizer,
    crops: &mut [RecognizedCrop],
    request: &RequestGuard<'_>,
) -> Result<usize, OcrError> {
    let indices: Vec<usize> = crops
        .iter()
        .enumerate()
        .filter(|(_, crop)| crop.needs_retry())
        .map(|(index, _)| index)
        .collect();
    if indices.is_empty() {
        return Ok(0);
    }
    let mut images: Vec<ImageU8> = indices
        .iter()
        .map(|&index| crops[index].image.clone())
        .collect();
    let decisions = classifier.classify(&mut images)?;
    request.check()?;
    let flipped: Vec<(usize, ImageU8)> = indices
        .iter()
        .copied()
        .zip(images)
        .zip(decisions)
        .filter(|(_, decision)| decision.rotated)
        .map(|(flipped, _)| flipped)
        .collect();
    let inputs: Vec<&ImageU8> = flipped.iter().map(|(_, image)| image).collect();
    let results = recognizer.recognize(&inputs, request)?;
    for ((index, image), retry) in flipped.into_iter().zip(results) {
        crops[index].prefer_rotated(image, retry);
    }
    Ok(indices.len())
}

fn text_blocks(
    candidates: &[DetectionCandidate],
    crops: &[RecognizedCrop],
    source: &SourceImage,
    min_confidence: f32,
) -> Vec<TextBlock> {
    let (scale_x, scale_y) = decoded_scale(source);
    candidates
        .iter()
        .zip(crops)
        .filter(|(_, crop)| crop.recognition.confidence >= min_confidence)
        .map(|(candidate, crop)| TextBlock {
            text: crop.recognition.text.clone(),
            confidence: crop.recognition.confidence,
            points: scale_points(&candidate.points, scale_x, scale_y),
            characters: character_boxes(
                &candidate.points,
                &crop.recognition.spans,
                crop.orientation,
                crop.rotated,
            )
            .into_iter()
            .map(|character| CharacterBox {
                points: scale_points(&character.points, scale_x, scale_y),
                ..character
            })
            .collect(),
        })
        .collect()
}

fn regions_in_decoded_pixels(
    candidates: &[DetectionCandidate],
    source: &SourceImage,
) -> Vec<TextRegion> {
    let (scale_x, scale_y) = decoded_scale(source);
    candidates
        .iter()
        .filter(|candidate| candidate.score >= REGION_MIN_SCORE)
        .take(MAX_REGIONS)
        .map(|candidate| TextRegion {
            confidence: candidate.score,
            points: scale_points(&candidate.points, scale_x, scale_y),
        })
        .collect()
}

fn decoded_scale(source: &SourceImage) -> (f32, f32) {
    (
        source.decoded_width as f32 / source.working.width as f32,
        source.decoded_height as f32 / source.working.height as f32,
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use recognize::CharacterSpan;

    fn detector_only_engine() -> OcrEngine {
        OcrEngine::new(OcrModelPaths {
            detection: "missing/det.onnx".to_string(),
            classification: String::new(),
            recognition: String::new(),
            dictionary: String::new(),
        })
        .unwrap()
    }

    fn quad(x: f32, y: f32) -> [Point; 4] {
        [
            Point::new(x, y),
            Point::new(x + 10.0, y),
            Point::new(x + 10.0, y + 5.0),
            Point::new(x, y + 5.0),
        ]
    }

    fn recognized(text: &str, confidence: f32, rotated: bool) -> RecognizedCrop {
        RecognizedCrop {
            image: ImageU8::zeros(2, 1, 3).unwrap(),
            orientation: Orientation::Horizontal,
            rotated,
            recognition: Recognition {
                text: text.to_string(),
                confidence,
                spans: vec![CharacterSpan {
                    text: text.to_string(),
                    confidence,
                    start: 0.0,
                    end: 0.5,
                }],
            },
        }
    }

    #[test]
    fn engine_accepts_a_detector_only_path_set_without_loading_it() {
        let engine = detector_only_engine();
        assert_eq!(
            engine.missing_text_model_paths,
            ["classification", "recognition", "dictionary"]
        );
    }

    #[test]
    fn missing_image_is_reported_before_the_detector_is_touched() {
        let error = detector_only_engine()
            .detect_text_regions(&DetectRegionsRequest {
                image_path: "missing/image.jpg".to_string(),
                request_id: Some("r1".to_string()),
            })
            .unwrap_err();
        assert!(matches!(error, OcrError::ImageNotFound(_)), "{error}");
    }

    #[test]
    fn detect_text_names_the_missing_model_paths_before_reading_the_image() {
        let engine = OcrEngine::new(OcrModelPaths {
            detection: "missing/det.onnx".to_string(),
            classification: "missing/cls.onnx".to_string(),
            recognition: String::new(),
            dictionary: String::new(),
        })
        .unwrap();
        let error = engine
            .detect_text(&DetectTextRequest {
                image_path: "missing/image.jpg".to_string(),
                include_all_confidence_scores: false,
                request_id: None,
            })
            .unwrap_err();
        let OcrError::Ml(MlError::InvalidRequest(message)) = error else {
            panic!("{error}");
        };
        assert_eq!(
            message,
            "OCR model paths are empty: recognition, dictionary"
        );
    }

    #[test]
    fn regions_scale_from_working_to_decoded_pixels_and_drop_low_scores() {
        let source = SourceImage {
            decoded_width: 2000,
            decoded_height: 1000,
            working: ImageU8::zeros(1000, 500, 3).unwrap(),
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

    #[test]
    fn text_blocks_filter_by_confidence_and_scale_blocks_and_characters() {
        let source = SourceImage {
            decoded_width: 2000,
            decoded_height: 1000,
            working: ImageU8::zeros(1000, 500, 3).unwrap(),
        };
        let candidates = vec![
            DetectionCandidate {
                points: quad(100.0, 50.0),
                score: 0.9,
            },
            DetectionCandidate {
                points: quad(300.0, 50.0),
                score: 0.9,
            },
            DetectionCandidate {
                points: quad(500.0, 50.0),
                score: 0.9,
            },
        ];
        let crops = vec![
            recognized("hi", 0.95, false),
            recognized("lo", 0.6, false),
            recognized("flip", 0.85, true),
        ];

        let blocks = text_blocks(&candidates, &crops, &source, MIN_BLOCK_CONFIDENCE);

        assert_eq!(blocks.len(), 2);
        assert_eq!(blocks[0].text, "hi");
        assert_eq!(blocks[0].points[0], Point::new(200.0, 100.0));
        assert_eq!(blocks[0].points[2], Point::new(220.0, 110.0));
        assert_eq!(blocks[0].characters.len(), 1);
        assert_eq!(blocks[0].characters[0].text, "hi");
        assert_eq!(blocks[0].characters[0].points[0], Point::new(200.0, 100.0));
        assert_eq!(blocks[0].characters[0].points[1], Point::new(210.0, 100.0));
        assert_eq!(blocks[1].text, "flip");
        assert_eq!(blocks[1].characters[0].points[0], Point::new(1010.0, 100.0));
        assert_eq!(blocks[1].characters[0].points[1], Point::new(1020.0, 100.0));

        let lenient = text_blocks(&candidates, &crops, &source, min_block_confidence(true));
        assert_eq!(lenient.len(), 3);
    }

    #[test]
    fn a_rotated_result_replaces_the_upright_one_only_when_more_confident() {
        let mut crop = recognized("up", 0.7, false);
        let same = recognized("same", 0.7, false);
        crop.prefer_rotated(same.image, same.recognition);
        assert!(!crop.rotated);
        assert_eq!(crop.recognition.text, "up");

        let better = recognized("down", 0.9, false);
        crop.prefer_rotated(better.image, better.recognition);
        assert!(crop.rotated);
        assert_eq!(crop.recognition.text, "down");
    }

    #[test]
    fn only_low_confidence_horizontal_crops_are_retried() {
        assert!(recognized("a", 0.64, false).needs_retry());
        assert!(!recognized("a", 0.65, false).needs_retry());
        let mut vertical = recognized("a", 0.1, false);
        vertical.orientation = Orientation::Vertical;
        assert!(!vertical.needs_retry());
    }
}
