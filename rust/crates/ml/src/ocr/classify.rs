use std::sync::{Mutex, PoisonError};

use super::tensor::{BgrNormalization, write_bgr_planes};
use crate::cv;
use crate::cv::image::ImageU8;
use crate::error::{MlError, MlResult};
use crate::onnx::{ExecutionMode, OnnxSession, PreparedF32Input, SessionRunError, run_f32};

const MODEL_NAMESPACE: &str = "ocr-classification";
const BATCH_SIZE: usize = 6;
const INPUT_HEIGHT: i32 = 48;
const INPUT_WIDTH: i32 = 192;
const CLASS_COUNT: usize = 2;
const ROTATION_THRESHOLD: f32 = 0.9;

#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct AngleScores {
    pub(crate) p0: f32,
    pub(crate) p180: f32,
}

impl AngleScores {
    fn needs_rotation(self) -> bool {
        self.p180 > self.p0 && self.p180 > ROTATION_THRESHOLD
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct AngleDecision {
    pub(crate) rotated: bool,
    pub(crate) scores: AngleScores,
}

pub(crate) struct AngleClassifier {
    session: Mutex<OnnxSession>,
}

impl AngleClassifier {
    pub(crate) fn new(model_path: &str) -> Self {
        Self {
            session: Mutex::new(
                OnnxSession::new(model_path, MODEL_NAMESPACE, ExecutionMode::CpuAccelerated)
                    .with_unvalidated_acceleration(),
            ),
        }
    }

    pub(crate) fn classify(&self, crops: &mut [ImageU8]) -> MlResult<Vec<AngleDecision>> {
        classify_in_batches(crops, |batch| self.score_batch(batch))
    }

    fn score_batch(&self, batch: &[ImageU8]) -> MlResult<Vec<AngleScores>> {
        let input = PreparedF32Input::new(batch_tensor(batch)?);
        let count = batch.len() as i64;
        let expected_shape = [count, CLASS_COUNT as i64];
        let mut session = self.session.lock().unwrap_or_else(PoisonError::into_inner);
        let (values, _usage) = session.run(|session| {
            let (shape, values) = run_f32(
                session,
                &input,
                [count, 3, i64::from(INPUT_HEIGHT), i64::from(INPUT_WIDTH)],
            )?;
            if shape != expected_shape {
                return Err(SessionRunError::from(MlError::CorruptModel(format!(
                    "angle classifier produced output shape {shape:?}, expected {expected_shape:?}"
                ))));
            }
            Ok(values)
        })?;
        Ok(values
            .as_chunks::<CLASS_COUNT>()
            .0
            .iter()
            .map(|&[p0, p180]| AngleScores { p0, p180 })
            .collect())
    }
}

fn classify_in_batches(
    crops: &mut [ImageU8],
    mut score_batch: impl FnMut(&[ImageU8]) -> MlResult<Vec<AngleScores>>,
) -> MlResult<Vec<AngleDecision>> {
    let mut decisions = Vec::with_capacity(crops.len());
    for batch in crops.chunks_mut(BATCH_SIZE) {
        let scores = score_batch(batch)?;
        if scores.len() != batch.len() {
            return Err(MlError::CorruptModel(format!(
                "angle classifier scored {} crops out of {}",
                scores.len(),
                batch.len()
            )));
        }
        for (crop, scores) in batch.iter_mut().zip(scores) {
            decisions.push(apply_decision(crop, scores)?);
        }
    }
    Ok(decisions)
}

fn apply_decision(crop: &mut ImageU8, scores: AngleScores) -> MlResult<AngleDecision> {
    let rotated = scores.needs_rotation();
    if rotated {
        *crop = cv::rotate_u8(crop, 180).map_err(MlError::Postprocess)?;
    }
    Ok(AngleDecision { rotated, scores })
}

fn batch_tensor(batch: &[ImageU8]) -> MlResult<Vec<f32>> {
    let plane = (INPUT_WIDTH * INPUT_HEIGHT) as usize;
    let mut tensor = vec![0.0f32; batch.len() * 3 * plane];
    for (crop, slot) in batch.iter().zip(tensor.chunks_exact_mut(3 * plane)) {
        write_crop_planes(crop, slot)?;
    }
    Ok(tensor)
}

fn write_crop_planes(crop: &ImageU8, slot: &mut [f32]) -> MlResult<()> {
    let width = resized_width(crop.width, crop.height);
    let resized = cv::resize_u8(crop, width, INPUT_HEIGHT, cv::Interp::Bilinear)
        .map_err(MlError::Preprocess)?;
    write_bgr_planes(
        &resized,
        slot,
        INPUT_WIDTH as usize,
        BgrNormalization::CENTERED,
    )
}

fn resized_width(width: i32, height: i32) -> i32 {
    let scaled = (INPUT_HEIGHT as f32 * width as f32 / height as f32).ceil() as i32;
    scaled.min(INPUT_WIDTH)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn solid(width: i32, height: i32, rgb: [u8; 3]) -> ImageU8 {
        let data = std::iter::repeat_n(rgb, (width * height) as usize)
            .flatten()
            .collect();
        ImageU8::new(width, height, 3, data).unwrap()
    }

    fn scores(p0: f32, p180: f32) -> AngleScores {
        AngleScores { p0, p180 }
    }

    #[test]
    fn a_crop_narrower_than_the_input_is_left_aligned_and_zero_padded_per_plane() {
        let crop = solid(100, 48, [10, 20, 30]);
        let plane = (INPUT_WIDTH * INPUT_HEIGHT) as usize;

        let tensor = batch_tensor(std::slice::from_ref(&crop)).unwrap();

        assert_eq!(tensor.len(), 3 * plane);
        let centered = |value: f32| (value / 255.0 - 0.5) / 0.5;
        let expected = [centered(30.0), centered(20.0), centered(10.0)];
        for (channel, expected) in expected.into_iter().enumerate() {
            let values = &tensor[channel * plane..(channel + 1) * plane];
            for y in 0..INPUT_HEIGHT as usize {
                let row = &values[y * INPUT_WIDTH as usize..(y + 1) * INPUT_WIDTH as usize];
                assert!(
                    row[..100].iter().all(|&v| (v - expected).abs() <= 1e-6),
                    "channel {channel} row {y} content"
                );
                assert!(
                    row[100..].iter().all(|&v| v == 0.0),
                    "channel {channel} row {y} padding"
                );
            }
        }
    }

    #[test]
    fn rotation_needs_the_flipped_class_to_win_with_high_confidence() {
        assert!(!scores(0.95, 0.05).needs_rotation());
        assert!(scores(0.05, 0.95).needs_rotation());
        assert!(!scores(0.15, 0.85).needs_rotation());
    }

    #[test]
    fn decisions_rotate_only_flagged_crops_in_place() {
        let mut crop = ImageU8::new(2, 1, 3, vec![1, 2, 3, 4, 5, 6]).unwrap();

        let kept = apply_decision(&mut crop, scores(0.8, 0.2)).unwrap();
        assert!(!kept.rotated);
        assert_eq!(crop.data, [1, 2, 3, 4, 5, 6]);

        let flipped = apply_decision(&mut crop, scores(0.02, 0.98)).unwrap();
        assert!(flipped.rotated);
        assert_eq!(flipped.scores, scores(0.02, 0.98));
        assert_eq!(crop.data, [4, 5, 6, 1, 2, 3]);
    }

    #[test]
    fn seven_crops_are_scored_in_two_ordered_batches() {
        let mut crops: Vec<ImageU8> = (1..=7).map(|w| solid(w, 1, [w as u8; 3])).collect();
        let mut batch_sizes = Vec::new();

        let decisions = classify_in_batches(&mut crops, |batch| {
            batch_sizes.push(batch.len());
            Ok(batch
                .iter()
                .map(|crop| scores(1.0 - crop.width as f32 / 100.0, crop.width as f32 / 100.0))
                .collect())
        })
        .unwrap();

        assert_eq!(batch_sizes, [6, 1]);
        let p180: Vec<f32> = decisions.iter().map(|d| d.scores.p180).collect();
        assert_eq!(p180, [0.01, 0.02, 0.03, 0.04, 0.05, 0.06, 0.07]);
        assert!(decisions.iter().all(|d| !d.rotated));
    }

    #[test]
    fn a_short_score_list_is_reported_as_a_corrupt_model() {
        let mut crops = vec![solid(4, 4, [0; 3]), solid(4, 4, [0; 3])];

        let error = classify_in_batches(&mut crops, |_| Ok(vec![scores(1.0, 0.0)])).unwrap_err();

        assert!(matches!(error, MlError::CorruptModel(_)), "{error}");
    }
}
