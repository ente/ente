use std::path::Path;
use std::sync::{Mutex, OnceLock, PoisonError};

use super::OcrError;
use super::cancel::RequestGuard;
use super::dictionary::load_dictionary;
use super::tensor::{BgrNormalization, write_bgr_planes};
use crate::cv;
use crate::cv::image::ImageU8;
use crate::error::{MlError, MlResult};
use crate::onnx::{ExecutionMode, OnnxSession, PreparedF32Input, SessionRunError, run_f32};

const MODEL_NAMESPACE: &str = "ocr-recognition";
const REC_VOCABULARY_SIZE: usize = 18385;
const REC_HEIGHT: i32 = 48;
const REC_BASE_WIDTH: i32 = 320;
const REC_BATCH_SIZE: usize = 6;
const BLANK_INDEX: usize = 0;
const MIN_SPAN: f32 = 1e-3;

#[derive(Clone, Debug, PartialEq)]
pub(crate) struct CharacterSpan {
    pub(crate) text: String,
    pub(crate) confidence: f32,
    pub(crate) start: f32,
    pub(crate) end: f32,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub(crate) struct Recognition {
    pub(crate) text: String,
    pub(crate) confidence: f32,
    pub(crate) spans: Vec<CharacterSpan>,
}

struct LazyDictionary {
    path: String,
    entries: OnceLock<Vec<String>>,
}

impl LazyDictionary {
    fn new(path: &str) -> Self {
        Self {
            path: path.to_string(),
            entries: OnceLock::new(),
        }
    }

    fn entries(&self) -> MlResult<&[String]> {
        if let Some(entries) = self.entries.get() {
            return Ok(entries);
        }
        let loaded = load_dictionary(Path::new(&self.path), REC_VOCABULARY_SIZE)?;
        Ok(self.entries.get_or_init(|| loaded))
    }
}

pub(crate) struct TextRecognizer {
    session: Mutex<OnnxSession>,
    dictionary: LazyDictionary,
}

impl TextRecognizer {
    pub(crate) fn new(model_path: &str, dictionary_path: &str) -> Self {
        Self {
            session: Mutex::new(
                OnnxSession::new(model_path, MODEL_NAMESPACE, ExecutionMode::CpuAccelerated)
                    .with_unvalidated_acceleration(),
            ),
            dictionary: LazyDictionary::new(dictionary_path),
        }
    }

    pub(crate) fn recognize(
        &self,
        crops: &[&ImageU8],
        request: &RequestGuard<'_>,
    ) -> Result<Vec<Recognition>, OcrError> {
        if crops.is_empty() {
            return Ok(Vec::new());
        }
        let dictionary = self.dictionary.entries()?;
        recognize_in_batches(crops, request, |batch| self.infer_batch(batch, dictionary))
    }

    fn infer_batch(&self, batch: &[&ImageU8], dictionary: &[String]) -> MlResult<Vec<Recognition>> {
        let layout = BatchLayout::new(batch);
        let input = PreparedF32Input::new(layout.tensor(batch)?);
        let count = batch.len();
        let input_shape = [
            count as i64,
            3,
            i64::from(REC_HEIGHT),
            i64::from(layout.target_width),
        ];
        let mut session = self.session.lock().unwrap_or_else(PoisonError::into_inner);
        let (output, _usage) = session.run(|session| {
            let (shape, values) = run_f32(session, &input, input_shape)?;
            SequenceOutput::new(&shape, values, count, dictionary.len())
                .map_err(SessionRunError::from)
        })?;
        Ok(layout
            .content_widths
            .iter()
            .zip(output.sequences())
            .map(|(&content_width, logits)| {
                ctc_decode(
                    logits,
                    output.vocabulary,
                    dictionary,
                    layout.padding_scale(content_width),
                )
            })
            .collect())
    }
}

fn recognize_in_batches(
    crops: &[&ImageU8],
    request: &RequestGuard<'_>,
    mut infer_batch: impl FnMut(&[&ImageU8]) -> MlResult<Vec<Recognition>>,
) -> Result<Vec<Recognition>, OcrError> {
    let mut results: Vec<Option<Recognition>> = vec![None; crops.len()];
    for indices in ascending_aspect_order(crops).chunks(REC_BATCH_SIZE) {
        request.check()?;
        let batch: Vec<&ImageU8> = indices.iter().map(|&index| crops[index]).collect();
        let recognized = infer_batch(&batch)?;
        if recognized.len() != batch.len() {
            return Err(MlError::CorruptModel(format!(
                "text recognizer decoded {} crops out of {}",
                recognized.len(),
                batch.len()
            ))
            .into());
        }
        for (&index, recognition) in indices.iter().zip(recognized) {
            results[index] = Some(recognition);
        }
    }
    results
        .into_iter()
        .collect::<Option<Vec<_>>>()
        .ok_or_else(|| MlError::CorruptModel("text recognizer skipped a crop".to_string()).into())
}

fn ascending_aspect_order(crops: &[&ImageU8]) -> Vec<usize> {
    let mut order: Vec<usize> = (0..crops.len()).collect();
    order.sort_by(|&a, &b| aspect(crops[a]).total_cmp(&aspect(crops[b])));
    order
}

fn aspect(crop: &ImageU8) -> f64 {
    f64::from(crop.width) / f64::from(crop.height)
}

struct BatchLayout {
    target_width: i32,
    content_widths: Vec<i32>,
}

impl BatchLayout {
    fn new(batch: &[&ImageU8]) -> Self {
        let base_ratio = f64::from(REC_BASE_WIDTH) / f64::from(REC_HEIGHT);
        let max_wh_ratio = batch
            .iter()
            .map(|crop| aspect(crop))
            .fold(base_ratio, f64::max);
        let target_width = target_width(max_wh_ratio);
        let content_widths = batch
            .iter()
            .map(|crop| content_width(crop, target_width))
            .collect();
        Self {
            target_width,
            content_widths,
        }
    }

    fn padding_scale(&self, content_width: i32) -> f32 {
        self.target_width as f32 / content_width as f32
    }

    fn tensor(&self, batch: &[&ImageU8]) -> MlResult<Vec<f32>> {
        let plane = (self.target_width * REC_HEIGHT) as usize;
        let mut tensor = vec![0.0f32; batch.len() * 3 * plane];
        let slots = tensor.chunks_exact_mut(3 * plane);
        for ((crop, &content_width), slot) in batch.iter().zip(&self.content_widths).zip(slots) {
            let resized = cv::resize_u8(crop, content_width, REC_HEIGHT, cv::Interp::Bilinear)
                .map_err(MlError::Preprocess)?;
            write_bgr_planes(
                &resized,
                slot,
                self.target_width as usize,
                BgrNormalization::CENTERED,
            )?;
        }
        Ok(tensor)
    }
}

fn target_width(max_wh_ratio: f64) -> i32 {
    ((f64::from(REC_HEIGHT) * max_wh_ratio).trunc() as i32).max(1)
}

fn content_width(crop: &ImageU8, target_width: i32) -> i32 {
    let scaled = (f64::from(REC_HEIGHT * crop.width) / f64::from(crop.height)).ceil() as i32;
    scaled.min(target_width)
}

#[derive(Debug)]
struct SequenceOutput {
    steps: usize,
    vocabulary: usize,
    values: Vec<f32>,
}

impl SequenceOutput {
    fn new(shape: &[i64], values: Vec<f32>, count: usize, vocabulary: usize) -> MlResult<Self> {
        match *shape {
            [n, steps, v]
                if n == count as i64
                    && steps > 0
                    && v == vocabulary as i64
                    && values.len() == count * steps as usize * vocabulary =>
            {
                Ok(Self {
                    steps: steps as usize,
                    vocabulary,
                    values,
                })
            }
            _ => Err(MlError::CorruptModel(format!(
                "text recognizer produced output shape {shape:?} with {} values, expected [{count}, T, {vocabulary}]",
                values.len()
            ))),
        }
    }

    fn sequences(&self) -> impl Iterator<Item = &[f32]> {
        self.values.chunks_exact(self.steps * self.vocabulary)
    }
}

fn ctc_decode(
    logits: &[f32],
    vocabulary: usize,
    dictionary: &[String],
    padding_scale: f32,
) -> Recognition {
    let best = best_per_step(logits, vocabulary);
    let spans: Vec<CharacterSpan> = character_runs(&best)
        .iter()
        .filter_map(|run| run.span(best.len(), dictionary, padding_scale))
        .collect();
    Recognition {
        text: spans.iter().map(|span| span.text.as_str()).collect(),
        confidence: mean_confidence(&spans),
        spans,
    }
}

#[derive(Clone, Copy)]
struct StepBest {
    index: usize,
    probability: f32,
}

fn best_per_step(logits: &[f32], vocabulary: usize) -> Vec<StepBest> {
    if vocabulary == 0 {
        return Vec::new();
    }
    logits.chunks_exact(vocabulary).map(argmax).collect()
}

fn argmax(step: &[f32]) -> StepBest {
    let mut best = StepBest {
        index: 0,
        probability: f32::NEG_INFINITY,
    };
    for (index, &probability) in step.iter().enumerate() {
        if probability > best.probability {
            best = StepBest { index, probability };
        }
    }
    best
}

struct CharacterRun {
    index: usize,
    start: usize,
    end: usize,
    confidence: f32,
}

fn character_runs(best: &[StepBest]) -> Vec<CharacterRun> {
    let mut runs = Vec::new();
    let mut start = 0;
    while start < best.len() {
        let index = best[start].index;
        let end = start
            + best[start..]
                .iter()
                .take_while(|b| b.index == index)
                .count();
        if index != BLANK_INDEX {
            let total: f32 = best[start..end].iter().map(|b| b.probability).sum();
            runs.push(CharacterRun {
                index,
                start,
                end,
                confidence: total / (end - start) as f32,
            });
        }
        start = end;
    }
    runs
}

impl CharacterRun {
    fn span(
        &self,
        steps: usize,
        dictionary: &[String],
        padding_scale: f32,
    ) -> Option<CharacterSpan> {
        let text = dictionary.get(self.index)?.clone();
        let (start, end) = span_bounds(self.start, self.end, steps, padding_scale);
        Some(CharacterSpan {
            text,
            confidence: self.confidence,
            start,
            end,
        })
    }
}

fn span_bounds(run_start: usize, run_end: usize, steps: usize, scale: f32) -> (f32, f32) {
    let steps = steps as f32;
    let min_span = (scale / steps).max(MIN_SPAN);
    let mut start = (run_start as f32 / steps * scale).clamp(0.0, 1.0);
    let mut end = (run_end as f32 / steps * scale).clamp(start, 1.0);
    if end - start < min_span {
        end = (start + min_span).min(1.0);
        if end - start < min_span {
            start = (end - min_span).max(0.0);
        }
    }
    (start, end)
}

fn mean_confidence(spans: &[CharacterSpan]) -> f32 {
    if spans.is_empty() {
        return 0.0;
    }
    spans.iter().map(|span| span.confidence).sum::<f32>() / spans.len() as f32
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ocr::cancel::RequestRegistry;

    const TOLERANCE: f32 = 1e-6;

    fn dictionary() -> Vec<String> {
        ["blank", "a", "b", "c"].map(str::to_string).to_vec()
    }

    fn logits(vocabulary: usize, steps: &[(usize, f32)]) -> Vec<f32> {
        steps
            .iter()
            .flat_map(|&(index, probability)| {
                let mut row = vec![0.0f32; vocabulary];
                row[index] = probability;
                row
            })
            .collect()
    }

    fn solid(width: i32, height: i32, rgb: [u8; 3]) -> ImageU8 {
        let data = std::iter::repeat_n(rgb, (width * height) as usize)
            .flatten()
            .collect();
        ImageU8::new(width, height, 3, data).unwrap()
    }

    fn assert_close(actual: f32, expected: f32) {
        assert!(
            (actual - expected).abs() <= TOLERANCE,
            "{actual} != {expected}"
        );
    }

    fn assert_span(span: &CharacterSpan, text: &str, confidence: f32, start: f32, end: f32) {
        assert_eq!(span.text, text);
        assert_close(span.confidence, confidence);
        assert_close(span.start, start);
        assert_close(span.end, end);
    }

    #[test]
    fn blank_only_sequence_decodes_to_nothing() {
        let recognition = ctc_decode(
            &logits(4, &[(0, 0.9), (0, 0.8), (0, 0.7)]),
            4,
            &dictionary(),
            1.0,
        );
        assert_eq!(recognition, Recognition::default());
    }

    #[test]
    fn repeats_separated_by_a_blank_produce_two_characters() {
        let steps = [(1, 0.9), (1, 0.9), (0, 0.9), (1, 0.6)];
        let recognition = ctc_decode(&logits(4, &steps), 4, &dictionary(), 1.0);
        assert_eq!(recognition.text, "aa");
        assert_eq!(recognition.spans.len(), 2);
        assert_span(&recognition.spans[0], "a", 0.9, 0.0, 0.5);
        assert_span(&recognition.spans[1], "a", 0.6, 0.75, 1.0);
        assert_close(recognition.confidence, 0.75);
    }

    #[test]
    fn adjacent_repeats_collapse_into_one_run_with_the_mean_probability() {
        let steps = [(1, 0.9), (1, 0.7), (2, 0.5), (0, 0.9), (3, 0.3), (3, 0.5)];
        let recognition = ctc_decode(&logits(4, &steps), 4, &dictionary(), 1.0);
        assert_eq!(recognition.text, "abc");
        assert_span(&recognition.spans[0], "a", 0.8, 0.0, 2.0 / 6.0);
        assert_span(&recognition.spans[1], "b", 0.5, 2.0 / 6.0, 3.0 / 6.0);
        assert_span(&recognition.spans[2], "c", 0.4, 4.0 / 6.0, 1.0);
        assert_close(recognition.confidence, (0.8 + 0.5 + 0.4) / 3.0);
    }

    #[test]
    fn padded_spans_are_stretched_then_clamped_with_the_minimum_span() {
        let steps = [(1, 1.0), (0, 1.0), (0, 1.0), (2, 1.0)];
        let recognition = ctc_decode(&logits(4, &steps), 4, &dictionary(), 2.0);
        assert_eq!(recognition.text, "ab");
        assert_span(&recognition.spans[0], "a", 1.0, 0.0, 0.5);
        assert_span(&recognition.spans[1], "b", 1.0, 0.5, 1.0);
    }

    #[test]
    fn target_width_truncates_and_content_width_ceils() {
        assert_eq!(
            target_width(f64::from(REC_BASE_WIDTH) / f64::from(REC_HEIGHT)),
            320
        );
        assert_eq!(target_width(7.3), 350);
        assert_eq!(target_width(0.001), 1);
        assert_eq!(content_width(&solid(7, 3, [0; 3]), 400), 112);
        assert_eq!(content_width(&solid(1, 4096, [0; 3]), 320), 1);
        assert_eq!(content_width(&solid(1000, 48, [0; 3]), 320), 320);
    }

    #[test]
    fn batch_layout_uses_the_widest_aspect_but_never_less_than_the_base_width() {
        let crops = [
            solid(100, 48, [0; 3]),
            solid(400, 48, [0; 3]),
            solid(7, 3, [0; 3]),
        ];
        let layout = BatchLayout::new(&crops.iter().collect::<Vec<_>>());
        assert_eq!(layout.target_width, 400);
        assert_eq!(layout.content_widths, [100, 400, 112]);
        assert_close(layout.padding_scale(100), 4.0);

        let narrow = [solid(10, 48, [0; 3])];
        let layout = BatchLayout::new(&narrow.iter().collect::<Vec<_>>());
        assert_eq!(layout.target_width, 320);
        assert_eq!(layout.content_widths, [10]);
    }

    #[test]
    fn batch_tensor_left_aligns_each_crop_and_zero_pads_the_rest() {
        let crops = [solid(100, 48, [10, 20, 30]), solid(400, 48, [0; 3])];
        let layout = BatchLayout::new(&crops.iter().collect::<Vec<_>>());
        let tensor = layout.tensor(&crops.iter().collect::<Vec<_>>()).unwrap();
        let plane = 48 * 400;
        assert_eq!(tensor.len(), 2 * 3 * plane);
        let centered = |value: f32| (value / 255.0 - 0.5) / 0.5;
        for (channel, expected) in [centered(30.0), centered(20.0), centered(10.0)]
            .into_iter()
            .enumerate()
        {
            let row = &tensor[channel * plane + 47 * 400..channel * plane + 48 * 400];
            assert!(
                row[..100]
                    .iter()
                    .all(|&v| (v - expected).abs() <= TOLERANCE),
                "channel {channel}"
            );
            assert!(row[100..].iter().all(|&v| v == 0.0), "channel {channel}");
        }
    }

    #[test]
    fn sequence_output_requires_the_dictionary_vocabulary() {
        let ok = SequenceOutput::new(&[1, 2, 4], vec![0.0; 8], 1, 4).unwrap();
        assert_eq!((ok.steps, ok.vocabulary), (2, 4));
        assert_eq!(ok.sequences().count(), 1);
        for shape in [[1, 2, 5], [2, 2, 4], [1, 0, 4]] {
            let error = SequenceOutput::new(&shape, vec![0.0; 8], 1, 4).unwrap_err();
            assert!(matches!(error, MlError::CorruptModel(_)), "{error}");
        }
        let short = SequenceOutput::new(&[1, 2, 4], vec![0.0; 7], 1, 4).unwrap_err();
        assert!(matches!(short, MlError::CorruptModel(_)), "{short}");
    }

    #[test]
    fn crops_are_batched_by_ascending_aspect_and_restored_to_input_order() {
        let widths = [80, 10, 60, 30, 70, 20, 50, 40];
        let crops: Vec<ImageU8> = widths.iter().map(|&w| solid(w, 10, [0; 3])).collect();
        let registry = RequestRegistry::default();
        let request = registry.begin(None);
        let mut batches = Vec::new();

        let results = recognize_in_batches(&crops.iter().collect::<Vec<_>>(), &request, |batch| {
            batches.push(batch.iter().map(|crop| crop.width).collect::<Vec<_>>());
            Ok(batch
                .iter()
                .map(|crop| Recognition {
                    text: crop.width.to_string(),
                    ..Recognition::default()
                })
                .collect())
        })
        .unwrap();

        assert_eq!(batches, [vec![10, 20, 30, 40, 50, 60], vec![70, 80]]);
        let texts: Vec<String> = results.into_iter().map(|r| r.text).collect();
        let expected: Vec<String> = widths.iter().map(|w| w.to_string()).collect();
        assert_eq!(texts, expected);
    }

    #[test]
    fn a_cancelled_request_stops_before_the_first_batch() {
        let crop = solid(4, 4, [0; 3]);
        let registry = RequestRegistry::default();
        let request = registry.begin(Some("cancelled"));
        registry.cancel("cancelled");

        let error = recognize_in_batches(&[&crop], &request, |_| unreachable!()).unwrap_err();

        assert!(matches!(error, OcrError::Cancelled), "{error}");
    }
}
