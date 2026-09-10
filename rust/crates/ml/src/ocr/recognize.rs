use std::path::Path;
use std::sync::{Mutex, OnceLock, PoisonError};

use super::OcrError;
use super::cancel::RequestGuard;
use super::dictionary::load_dictionary;
use super::tensor::{BgrNormalization, prepare_crops, write_bgr_planes};
use crate::cv;
use crate::cv::image::ImageU8;
use crate::error::{MlError, MlResult};
use crate::onnx::{
    BorrowedFloatTensor, FloatTensorData, PreparedF32Input, with_prepared_float_output,
};

use super::session::{OcrModel, OcrSession};
const REC_VOCABULARY_SIZE: usize = 18385;
const REC_HEIGHT: i32 = 48;
const REC_BASE_WIDTH: i32 = 320;
const REC_MAX_WIDTH: i32 = 7168;
const REC_BATCH_COLUMNS: usize = 7168;
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
    session: Mutex<OcrSession>,
    dictionary: LazyDictionary,
}

impl TextRecognizer {
    pub(crate) fn new(model_path: &str, dictionary_path: &str) -> Self {
        Self {
            session: Mutex::new(OcrSession::new(model_path, OcrModel::Recognition)),
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
        recognize_in_batches(crops, request, |batch, layout| {
            self.infer_batch(batch, layout, dictionary)
        })
    }

    fn infer_batch(
        &self,
        batch: &[&ImageU8],
        layout: &BatchLayout,
        dictionary: &[String],
    ) -> MlResult<Vec<Recognition>> {
        let input = PreparedF32Input::new(prepare_crops(|| layout.tensor(batch))?);
        let count = batch.len();
        let input_shape = [
            count as i64,
            3,
            i64::from(REC_HEIGHT),
            i64::from(layout.target_width),
        ];
        let mut session = self.session.lock().unwrap_or_else(PoisonError::into_inner);
        let (recognized, _usage) = session.run(input_shape, |session| {
            with_prepared_float_output(session, &input, input_shape, |shape, values| match values {
                BorrowedFloatTensor::F32(values) => {
                    decode_output(shape, values, layout, dictionary)
                }
                BorrowedFloatTensor::F16(values) => {
                    decode_output(shape, values, layout, dictionary)
                }
            })
        })?;
        Ok(recognized)
    }
}

fn decode_output<'a, T>(
    shape: &[i64],
    values: &'a [T],
    layout: &BatchLayout,
    dictionary: &[String],
) -> MlResult<Vec<Recognition>>
where
    &'a [T]: FloatTensorData,
{
    let compact = shape.get(2) == Some(&2);
    let values_per_step = if compact { 2 } else { dictionary.len() };
    let output = SequenceOutput::new(shape, values, layout.content_widths.len(), values_per_step)?;
    layout
        .content_widths
        .iter()
        .zip(output.sequences())
        .map(|(&content_width, logits)| {
            let padding_scale = layout.padding_scale(content_width);
            if compact {
                let best = compact_steps(logits, dictionary.len())?;
                Ok(decode_steps(&best, dictionary, padding_scale))
            } else {
                Ok(ctc_decode(
                    logits,
                    output.vocabulary,
                    dictionary,
                    padding_scale,
                ))
            }
        })
        .collect()
}

fn compact_steps<'a, T>(values: &'a [T], vocabulary: usize) -> MlResult<Vec<StepBest>>
where
    &'a [T]: FloatTensorData,
{
    values
        .as_chunks::<2>()
        .0
        .iter()
        .map(|step| {
            let step = step.as_slice();
            let index = step.value(0);
            let probability = step.value(1);
            if !index.is_finite()
                || index < 0.0
                || index >= vocabulary as f32
                || index.fract() != 0.0
                || !probability.is_finite()
                || probability < 0.0
            {
                return Err(MlError::CorruptModel(format!(
                    "text recognizer produced invalid index/probability [{index}, {probability}]"
                )));
            }
            Ok(StepBest {
                index: index as usize,
                probability,
            })
        })
        .collect()
}

fn recognize_in_batches(
    crops: &[&ImageU8],
    request: &RequestGuard<'_>,
    mut infer_batch: impl FnMut(&[&ImageU8], &BatchLayout) -> MlResult<Vec<Recognition>>,
) -> Result<Vec<Recognition>, OcrError> {
    let mut results: Vec<Option<Recognition>> = vec![None; crops.len()];
    for indices in ascending_aspect_order(crops).chunks(REC_BATCH_SIZE) {
        request.check()?;
        let batch: Vec<&ImageU8> = indices.iter().map(|&index| crops[index]).collect();
        let layout = BatchLayout::new(&batch)?;
        let initial_width = if batch.len() * layout.target_width as usize <= REC_BATCH_COLUMNS {
            layout.target_width
        } else {
            REC_BASE_WIDTH
        };
        let mut start = 0;
        while start < batch.len() {
            request.check()?;
            let mut end = start;
            let mut target_width = initial_width;
            for &content_width in &layout.content_widths[start..] {
                let next_width = target_width.max(content_width);
                if (end - start + 1) * next_width as usize > REC_BATCH_COLUMNS {
                    break;
                }
                target_width = next_width;
                end += 1;
            }
            let split = &batch[start..end];
            let split_layout = BatchLayout {
                target_width,
                content_widths: layout.content_widths[start..end].to_vec(),
            };
            let recognized = infer_batch(split, &split_layout)?;
            if recognized.len() != split.len() {
                return Err(MlError::CorruptModel(format!(
                    "text recognizer decoded {} crops out of {}",
                    recognized.len(),
                    split.len()
                ))
                .into());
            }
            for (&index, recognition) in indices[start..end].iter().zip(recognized) {
                results[index] = Some(recognition);
            }
            start = end;
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
    fn new(batch: &[&ImageU8]) -> MlResult<Self> {
        for crop in batch {
            let expected = usize::try_from(crop.width)
                .ok()
                .zip(usize::try_from(crop.height).ok())
                .and_then(|(width, height)| width.checked_mul(height))
                .and_then(|pixels| pixels.checked_mul(3));
            if crop.width <= 0
                || crop.height <= 0
                || crop.channels != 3
                || expected != Some(crop.data.len())
            {
                return Err(MlError::Preprocess(format!(
                    "invalid text crop {}x{}x{} with {} bytes",
                    crop.width,
                    crop.height,
                    crop.channels,
                    crop.data.len()
                )));
            }
        }
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
        Ok(Self {
            target_width,
            content_widths,
        })
    }

    fn padding_scale(&self, content_width: i32) -> f32 {
        self.target_width as f32 / content_width as f32
    }

    fn tensor(&self, batch: &[&ImageU8]) -> MlResult<Vec<f32>> {
        let columns = batch.len().checked_mul(self.target_width as usize);
        if !(REC_BASE_WIDTH..=REC_MAX_WIDTH).contains(&self.target_width)
            || batch.is_empty()
            || batch.len() > REC_BATCH_SIZE
            || batch.len() != self.content_widths.len()
            || columns.is_none_or(|columns| columns > REC_BATCH_COLUMNS)
        {
            return Err(MlError::Preprocess(
                "text recognition batch exceeds its tensor budget".to_string(),
            ));
        }
        let plane = self.target_width as usize * REC_HEIGHT as usize;
        let mut tensor = Vec::new();
        let length = batch.len() * 3 * plane;
        tensor.try_reserve_exact(length).map_err(|error| {
            MlError::Preprocess(format!("cannot allocate text recognition input: {error}"))
        })?;
        tensor.resize(length, 0.0f32);
        let slots = tensor.chunks_exact_mut(3 * plane);
        for ((crop, &content_width), slot) in batch.iter().zip(&self.content_widths).zip(slots) {
            let resized = cv::resize_u8(
                crop,
                content_width,
                content_height(crop),
                cv::Interp::Bilinear,
            )
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
    ((f64::from(REC_HEIGHT) * max_wh_ratio).trunc() as i32).clamp(1, REC_MAX_WIDTH)
}

fn content_width(crop: &ImageU8, target_width: i32) -> i32 {
    let scaled =
        (f64::from(REC_HEIGHT) * f64::from(crop.width) / f64::from(crop.height)).ceil() as i32;
    scaled.min(target_width)
}

fn content_height(crop: &ImageU8) -> i32 {
    ((f64::from(REC_MAX_WIDTH) * f64::from(crop.height) / f64::from(crop.width)).round() as i32)
        .clamp(1, REC_HEIGHT)
}

#[derive(Debug)]
struct SequenceOutput<'a, T> {
    steps: usize,
    vocabulary: usize,
    values: &'a [T],
}

impl<'a, T> SequenceOutput<'a, T> {
    fn new(shape: &[i64], values: &'a [T], count: usize, vocabulary: usize) -> MlResult<Self> {
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

    fn sequences(&self) -> impl Iterator<Item = &'a [T]> {
        self.values.chunks_exact(self.steps * self.vocabulary)
    }
}

fn ctc_decode<'a, T>(
    logits: &'a [T],
    vocabulary: usize,
    dictionary: &[String],
    padding_scale: f32,
) -> Recognition
where
    &'a [T]: FloatTensorData,
{
    let best = best_per_step(logits, vocabulary);
    decode_steps(&best, dictionary, padding_scale)
}

fn decode_steps(best: &[StepBest], dictionary: &[String], padding_scale: f32) -> Recognition {
    let spans: Vec<CharacterSpan> = character_runs(best)
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

fn best_per_step<'a, T>(logits: &'a [T], vocabulary: usize) -> Vec<StepBest>
where
    &'a [T]: FloatTensorData,
{
    if vocabulary == 0 {
        return Vec::new();
    }
    logits.chunks_exact(vocabulary).map(argmax).collect()
}

fn argmax<'a, T>(step: &'a [T]) -> StepBest
where
    &'a [T]: FloatTensorData,
{
    let mut maxima = [f32::NEG_INFINITY; 8];
    let (chunks, remainder) = step.as_chunks::<8>();
    for chunk in chunks {
        for (lane, maximum) in maxima.iter_mut().enumerate() {
            *maximum = maximum.max(chunk.as_slice().value(lane));
        }
    }
    let mut maximum = maxima.into_iter().fold(f32::NEG_INFINITY, f32::max);
    for index in 0..remainder.len() {
        maximum = maximum.max(remainder.value(index));
    }
    if maximum > f32::NEG_INFINITY {
        for index in 0..step.len() {
            let probability = step.value(index);
            if probability == maximum {
                return StepBest { index, probability };
            }
        }
    }
    StepBest {
        index: 0,
        probability: f32::NEG_INFINITY,
    }
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
    fn compact_output_preserves_text_confidences_and_character_spans() {
        let sequences = [
            [(1, 0.9), (1, 0.7), (0, 0.8), (1, 0.6), (2, 0.5), (3, 0.9)],
            [(0, 0.9), (0, 0.8), (0, 0.7), (0, 0.6), (0, 0.5), (0, 0.9)],
        ];
        let full: Vec<_> = sequences
            .iter()
            .flat_map(|steps| logits(4, steps))
            .collect();
        let compact: Vec<_> = sequences
            .iter()
            .flatten()
            .flat_map(|&(index, probability)| [index as f32, probability])
            .collect();
        let layout = BatchLayout {
            target_width: 320,
            content_widths: vec![160, 320],
        };
        let expected = decode_output(&[2, 6, 4], &full, &layout, &dictionary()).unwrap();
        let actual = decode_output(&[2, 6, 2], &compact, &layout, &dictionary()).unwrap();
        assert_eq!(actual, expected);
        assert_eq!(actual[0].text, "aabc");
        assert_eq!(actual[1], Recognition::default());
    }

    #[test]
    fn compact_output_rejects_invalid_indices_probabilities_and_shapes() {
        let layout = BatchLayout {
            target_width: 320,
            content_widths: vec![320],
        };
        for values in [
            [-1.0, 0.9],
            [4.0, 0.9],
            [1.5, 0.9],
            [f32::NAN, 0.9],
            [f32::INFINITY, 0.9],
            [1.0, f32::NAN],
            [1.0, f32::INFINITY],
            [1.0, -0.1],
        ] {
            assert!(decode_output(&[1, 1, 2], &values, &layout, &dictionary()).is_err());
        }
        for shape in [[2, 1, 2], [1, 0, 2], [1, 2, 2]] {
            assert!(decode_output(&shape, &[1.0, 0.9], &layout, &dictionary()).is_err());
        }
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
        let layout = BatchLayout::new(&crops.iter().collect::<Vec<_>>()).unwrap();
        assert_eq!(layout.target_width, 400);
        assert_eq!(layout.content_widths, [100, 400, 112]);
        assert_close(layout.padding_scale(100), 4.0);

        let narrow = [solid(10, 48, [0; 3])];
        let layout = BatchLayout::new(&narrow.iter().collect::<Vec<_>>()).unwrap();
        assert_eq!(layout.target_width, 320);
        assert_eq!(layout.content_widths, [10]);
    }

    #[test]
    fn batch_tensor_left_aligns_each_crop_and_zero_pads_the_rest() {
        let crops = [solid(100, 48, [10, 20, 30]), solid(400, 48, [0; 3])];
        let layout = BatchLayout::new(&crops.iter().collect::<Vec<_>>()).unwrap();
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
        let ok = SequenceOutput::new(&[1, 2, 4], &[0.0f32; 8], 1, 4).unwrap();
        assert_eq!((ok.steps, ok.vocabulary), (2, 4));
        assert_eq!(ok.sequences().count(), 1);
        for shape in [[1, 2, 5], [2, 2, 4], [1, 0, 4]] {
            let error = SequenceOutput::new(&shape, &[0.0f32; 8], 1, 4).unwrap_err();
            assert!(matches!(error, MlError::CorruptModel(_)), "{error}");
        }
        let short = SequenceOutput::new(&[1, 2, 4], &[0.0f32; 7], 1, 4).unwrap_err();
        assert!(matches!(short, MlError::CorruptModel(_)), "{short}");
    }

    #[test]
    fn crop_preparation_preserves_resized_batch_values() {
        let crops: Vec<_> = [(79, 11), (12, 160), (611, 53)]
            .into_iter()
            .map(|(width, height)| {
                let pixels = (0..width * height * 3)
                    .map(|index| (index * 37 % 256) as u8)
                    .collect();
                ImageU8::new(width, height, 3, pixels).unwrap()
            })
            .collect();
        let batch = crops.iter().collect::<Vec<_>>();
        let layout = BatchLayout::new(&batch).unwrap();
        let parallel = rayon::ThreadPoolBuilder::new()
            .num_threads(4)
            .build()
            .unwrap();
        let expected = parallel.install(|| layout.tensor(&batch)).unwrap();
        let prepared = prepare_crops(|| layout.tensor(&batch)).unwrap();
        assert_eq!(prepared, expected);
    }

    #[test]
    fn argmax_matches_scalar_for_lane_boundaries_ties_and_both_precisions() {
        fn reference(values: impl FloatTensorData) -> StepBest {
            let mut best = StepBest {
                index: 0,
                probability: f32::NEG_INFINITY,
            };
            for index in 0..values.len() {
                let probability = values.value(index);
                if probability > best.probability {
                    best = StepBest { index, probability };
                }
            }
            best
        }

        fn check<'a, T>(values: &'a [T])
        where
            &'a [T]: FloatTensorData,
        {
            let expected = reference(values);
            let actual = argmax(values);
            assert_eq!(actual.index, expected.index);
            assert_eq!(actual.probability.to_bits(), expected.probability.to_bits());
        }

        let mut state = 37u32;
        for len in (0..40).chain([191, 320, REC_VOCABULARY_SIZE]) {
            let mut values: Vec<f32> = (0..len)
                .map(|_| {
                    state = state.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
                    (state >> 16) as f32 / 65536.0 - 0.5
                })
                .collect();
            for first in 0..len.min(17) {
                for last in [first, len / 2, len - 1] {
                    values[first] = 1.0;
                    values[last] = 1.0;
                    check(values.as_slice());
                    let half_values: Vec<_> =
                        values.iter().map(|&v| half::f16::from_f32(v)).collect();
                    check(half_values.as_slice());
                    values[first] = -0.25;
                    values[last] = -0.25;
                }
            }
            check(values.as_slice());
        }
        for values in [
            vec![],
            vec![-0.0, 0.0, -0.0, 0.0, -0.0, 0.0, -0.0, 0.0, 0.0],
            vec![f32::NEG_INFINITY; 19],
            vec![f32::NAN; 19],
            vec![f32::NAN, 0.25, f32::INFINITY, f32::INFINITY],
        ] {
            check(values.as_slice());
            let half_values: Vec<_> = values.iter().map(|&v| half::f16::from_f32(v)).collect();
            check(half_values.as_slice());
        }
    }

    #[test]
    fn borrowed_outputs_preserve_ties_blanks_and_half_precision_confidences() {
        let values = [
            0.0, 0.75, 0.75, 0.0, 0.0, 0.5, 0.0, 0.0, 0.875, 0.0, 0.0, 0.0, 0.0, 0.625, 0.0, 0.0,
        ];
        let half_values = values.map(half::f16::from_f32);
        let layout = BatchLayout {
            target_width: 320,
            content_widths: vec![320],
        };
        let full = decode_output(&[1, 4, 4], &values, &layout, &dictionary()).unwrap();
        let half = decode_output(&[1, 4, 4], &half_values, &layout, &dictionary()).unwrap();
        assert_eq!(full, half);
        assert_eq!(full[0].text, "aa");
        assert_span(&full[0].spans[0], "a", 0.625, 0.0, 0.5);
        assert_span(&full[0].spans[1], "a", 0.625, 0.75, 1.0);
        assert_eq!(full[0].confidence, 0.625);
    }

    #[test]
    fn crops_are_batched_by_ascending_aspect_and_restored_to_input_order() {
        let widths = [80, 10, 60, 30, 70, 20, 50, 40];
        let crops: Vec<ImageU8> = widths.iter().map(|&w| solid(w, 10, [0; 3])).collect();
        let registry = RequestRegistry::default();
        let request = registry.begin(None);
        let mut batches = Vec::new();

        let results =
            recognize_in_batches(&crops.iter().collect::<Vec<_>>(), &request, |batch, _| {
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
        let expected: Vec<String> = widths.iter().map(ToString::to_string).collect();
        assert_eq!(texts, expected);
    }

    #[test]
    fn a_cancelled_request_stops_before_the_first_batch() {
        let crop = solid(4, 4, [0; 3]);
        let registry = RequestRegistry::default();
        let request = registry.begin(Some("cancelled"));
        registry.cancel("cancelled");

        let error = recognize_in_batches(&[&crop], &request, |_, _| unreachable!()).unwrap_err();

        assert!(matches!(error, OcrError::Cancelled), "{error}");
    }

    fn legacy_tensor(batch: &[&ImageU8]) -> Vec<f32> {
        let ratio = batch
            .iter()
            .map(|crop| aspect(crop))
            .fold(320.0 / 48.0, f64::max);
        let width = (48.0 * ratio).trunc() as usize;
        let plane = width * 48;
        let mut tensor = vec![0.0; batch.len() * 3 * plane];
        for (crop, slot) in batch.iter().zip(tensor.chunks_exact_mut(3 * plane)) {
            let content_width = ((48 * crop.width) as f64 / crop.height as f64).ceil() as i32;
            let resized = cv::resize_u8(
                crop,
                content_width.min(width as i32),
                48,
                cv::Interp::Bilinear,
            )
            .unwrap();
            for (y, row) in resized
                .data
                .chunks_exact(resized.width as usize * 3)
                .enumerate()
            {
                for (x, pixel) in row.as_chunks::<3>().0.iter().enumerate() {
                    for channel in 0..3 {
                        slot[channel * plane + y * width + x] =
                            (pixel[2 - channel] as f32 / 255.0 - 0.5) / 0.5;
                    }
                }
            }
        }
        tensor
    }

    #[test]
    fn bounded_batches_preserve_resized_pixels_and_input_order() {
        for (sizes, expected_shapes) in [
            (vec![(79, 11), (12, 160), (611, 53)], vec![(3, 553)]),
            (
                vec![
                    (1381, 48),
                    (1200, 48),
                    (287, 10),
                    (1300, 48),
                    (1100, 48),
                    (1350, 48),
                ],
                vec![(5, 1378), (1, 1381)],
            ),
            (
                vec![(7167, 48), (7168, 48), (6281, 48)],
                vec![(1, 6281), (1, 7167), (1, 7168)],
            ),
            (
                vec![
                    (7168, 48),
                    (79, 13),
                    (99, 20),
                    (320, 48),
                    (200, 50),
                    (120, 30),
                ],
                vec![(5, 320), (1, 7168)],
            ),
        ] {
            let crops: Vec<_> = sizes
                .into_iter()
                .map(|(width, height)| {
                    ImageU8::new(
                        width,
                        height,
                        3,
                        (0..width * height * 3)
                            .map(|index| (index * 37 % 256) as u8)
                            .collect(),
                    )
                    .unwrap()
                })
                .collect();
            let references: Vec<_> = crops.iter().collect();
            let order = ascending_aspect_order(&references);
            let sorted: Vec<_> = order.iter().map(|&index| references[index]).collect();
            let expected = legacy_tensor(&sorted);
            let original_layout = BatchLayout::new(&sorted).unwrap();
            let original_width = original_layout.target_width as usize;
            let mut expected_rows = expected.chunks_exact(original_width);
            let registry = RequestRegistry::default();
            let request = registry.begin(None);
            let mut shapes = Vec::new();
            let results = recognize_in_batches(&references, &request, |batch, layout| {
                assert!(batch.len() <= REC_BATCH_SIZE);
                assert!(batch.len() * layout.target_width as usize <= REC_BATCH_COLUMNS);
                shapes.push((batch.len(), layout.target_width));
                let tensor = layout.tensor(batch)?;
                for row in tensor.chunks_exact(layout.target_width as usize) {
                    let expected = expected_rows.next().unwrap();
                    assert_eq!(row, &expected[..row.len()]);
                    assert!(expected[row.len()..].iter().all(|&value| value == 0.0));
                }
                Ok(batch
                    .iter()
                    .map(|crop| Recognition {
                        text: crop.width.to_string(),
                        ..Recognition::default()
                    })
                    .collect())
            })
            .unwrap();
            assert!(expected_rows.next().is_none());
            assert_eq!(shapes, expected_shapes);
            assert_eq!(
                results
                    .iter()
                    .map(|result| result.text.clone())
                    .collect::<Vec<_>>(),
                crops
                    .iter()
                    .map(|crop| crop.width.to_string())
                    .collect::<Vec<_>>()
            );
        }
    }

    #[test]
    fn oversized_outlier_does_not_expand_narrow_crops_or_delay_cancellation() {
        let narrow = solid(320, 48, [127; 3]);
        let outlier = solid(4096, 1, [0; 3]);
        let crops = [&outlier, &narrow, &narrow, &narrow, &narrow, &narrow];
        for cancel in [false, true] {
            let registry = RequestRegistry::default();
            let request = registry.begin(Some("mixed"));
            let mut shapes = Vec::new();
            let result = recognize_in_batches(&crops, &request, |batch, layout| {
                shapes.push((batch.len(), layout.target_width));
                assert_eq!(
                    layout.tensor(batch)?.len(),
                    batch.len() * 3 * 48 * layout.target_width as usize
                );
                if cancel {
                    registry.cancel("mixed");
                }
                Ok(vec![Recognition::default(); batch.len()])
            });
            if cancel {
                assert!(matches!(result, Err(OcrError::Cancelled)));
                assert_eq!(shapes, [(5, 320)]);
            } else {
                assert_eq!(result.unwrap().len(), crops.len());
                assert_eq!(shapes, [(5, 320), (1, 7168)]);
            }
        }
    }

    #[test]
    fn oversized_crops_fit_proportionally_and_keep_all_columns_with_vertical_padding() {
        for (width, height, resized_height) in [
            (7168, 48, 48),
            (7169, 48, 48),
            (8192, 48, 42),
            (14336, 48, 24),
            (4096, 1, 2),
            (200000, 1, 1),
        ] {
            let mut crop = solid(width, height, [0; 3]);
            for row in crop.data.chunks_exact_mut(width as usize * 3) {
                row[width as usize / 2 * 3..].fill(255);
            }
            let layout = BatchLayout::new(&[&crop]).unwrap();
            assert_eq!(layout.target_width, REC_MAX_WIDTH);
            assert_eq!(layout.content_widths, [REC_MAX_WIDTH]);
            assert_eq!(content_height(&crop), resized_height);
            assert_eq!(layout.padding_scale(REC_MAX_WIDTH), 1.0);
            let tensor = layout.tensor(&[&crop]).unwrap();
            assert_eq!(tensor.len(), 3 * 48 * 7168);
            let top = (48 - resized_height) as usize / 2;
            for plane in tensor.as_chunks::<{ 48 * 7168 }>().0 {
                for (y, row) in plane.as_chunks::<7168>().0.iter().enumerate() {
                    if (top..top + resized_height as usize).contains(&y) {
                        assert_eq!(row[0], -1.0);
                        assert_eq!(row[7167], 1.0);
                    } else {
                        assert!(row.iter().all(|&value| value == 0.0));
                    }
                }
            }
        }
    }

    #[test]
    fn invalid_crop_geometry_is_rejected_before_tensor_allocation() {
        for (width, height, channels, len) in [
            (0, 48, 3, 0),
            (320, -1, 3, 0),
            (1, 1, 4, 4),
            (1, 1, 3, 2),
            (i32::MAX, i32::MAX, 3, 0),
        ] {
            let crop = ImageU8 {
                width,
                height,
                channels,
                data: vec![0; len],
            };
            assert!(matches!(
                BatchLayout::new(&[&crop]),
                Err(MlError::Preprocess(_))
            ));
        }
        let geometry = ImageU8 {
            width: i32::MAX,
            height: 1,
            channels: 3,
            data: Vec::new(),
        };
        assert_eq!(target_width(aspect(&geometry)), REC_MAX_WIDTH);
        assert_eq!(content_width(&geometry, REC_MAX_WIDTH), REC_MAX_WIDTH);
        assert_eq!(content_height(&geometry), 1);
    }

    #[test]
    fn vertical_padding_keeps_character_spans_on_the_original_quad_in_both_orientations() {
        use super::super::characters::character_boxes;
        use super::super::{Orientation, Point};

        let crop = solid(4096, 1, [0; 3]);
        let layout = BatchLayout::new(&[&crop]).unwrap();
        let values = logits(4, &[(0, 1.0), (1, 0.9), (0, 1.0), (0, 1.0)]);
        let results = decode_output(&[1, 4, 4], &values, &layout, &dictionary()).unwrap();
        assert_span(&results[0].spans[0], "a", 0.9, 0.25, 0.5);
        for rotated in [false, true] {
            for orientation in [Orientation::Horizontal, Orientation::Vertical] {
                let (width, height) = match orientation {
                    Orientation::Horizontal => (4096.0, 1.0),
                    Orientation::Vertical => (1.0, 4096.0),
                };
                let quad = [
                    Point::new(0.0, 0.0),
                    Point::new(width, 0.0),
                    Point::new(width, height),
                    Point::new(0.0, height),
                ];
                let boxes = character_boxes(&quad, &results[0].spans, orientation, rotated);
                assert_eq!(boxes.len(), 1);
                let (start, end) = if rotated {
                    (2048.0, 3072.0)
                } else {
                    (1024.0, 2048.0)
                };
                let points = boxes[0].points;
                match orientation {
                    Orientation::Horizontal => {
                        assert_eq!(points[0], Point::new(start, 0.0));
                        assert_eq!(points[2], Point::new(end, 1.0));
                    }
                    Orientation::Vertical => {
                        assert_eq!(points[0], Point::new(0.0, start));
                        assert_eq!(points[2], Point::new(1.0, end));
                    }
                }
            }
        }
    }

    #[test]
    fn extreme_aspect_batches_are_bounded_and_cancellation_stops_the_next_split() {
        let crop = solid(4096, 1, [0; 3]);
        let crops = [&crop; 6];
        let layout = BatchLayout::new(&crops).unwrap();
        assert!(matches!(layout.tensor(&crops), Err(MlError::Preprocess(_))));
        let registry = RequestRegistry::default();
        let request = registry.begin(None);
        let mut calls = 0;
        recognize_in_batches(&crops, &request, |batch, layout| {
            calls += 1;
            assert_eq!(batch.len(), 1);
            assert_eq!(layout.tensor(batch)?.len(), 3 * 48 * 7168);
            Ok(vec![Recognition::default()])
        })
        .unwrap();
        assert_eq!(calls, 6);

        let request = registry.begin(Some("split"));
        calls = 0;
        let error = recognize_in_batches(&crops, &request, |_, _| {
            calls += 1;
            registry.cancel("split");
            Ok(vec![Recognition::default()])
        })
        .unwrap_err();
        assert_eq!(calls, 1);
        assert!(matches!(error, OcrError::Cancelled));
    }
}
