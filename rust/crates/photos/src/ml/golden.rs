//! Golden-output self-tests for accelerated ONNX execution providers.
//!
//! GPU drivers and execution providers can produce numerically wrong output
//! while reporting success (for example, finite garbage from stale pipeline
//! state, or fp16 overflow). Wrong embeddings would be persisted server-side
//! and silently poison search and clustering, so before an accelerated
//! session (WebGPU on Android, CoreML on iOS) is trusted, it must reproduce a
//! committed golden output for a fixed input within a cosine-distance
//! threshold. The golden outputs are generated on the CPU execution provider
//! by `cargo run -p ente-photos --example ml_goldens -- generate`
//! and committed in `golden_data.rs`. A cheap unit test in `golden_tooling`
//! keeps the committed entries pinned (by file name and content hash) to the
//! production models in `infra/ml/test/ml_indexing/assets.json`, so a model
//! update cannot ship without regenerating the goldens.
//!
//! Inputs are deterministic seeded noise (token ids for CLIP text): the
//! models are pure tensor programs without data-dependent control flow, so
//! any fixed input exercises the same kernels as a real photo, and a shared
//! generation function makes device and generator inputs bit-identical.

use crate::ml::golden_data::GOLDEN_ENTRIES;

// All thresholds are deliberately loose (a false rejection silently degrades
// the device to CPU) and unvalidated against real accelerated hardware;
// tighten them once field measurements exist. Corrupted output measures ~1.0
// on the cosine and coordinate metrics, and orders of magnitude higher on
// the confidence group (its expected norm is tiny).

/// Maximum cosine distance between an accelerated session's embedding output
/// and the CPU golden. Healthy fp16 divergence is around 1e-3.
pub(crate) const COSINE_DISTANCE_THRESHOLD: f64 = 0.025;

/// Maximum relative L2 error for the detector's non-confidence outputs (box
/// coordinates, landmarks), whose absolute values are consumed directly.
/// Well-conditioned: healthy fp16 divergence is around 1e-3.
pub(crate) const RELATIVE_L2_THRESHOLD: f64 = 0.1;

/// Maximum relative L2 error for the detector's confidence group. All its
/// values are tiny background sigmoid outputs (samples <= ~2e-3), whose
/// relative error is roughly the absolute drift of the underlying logit, so
/// healthy fp16 pipelines can plausibly measure O(0.1..1) here (a full
/// flush-to-zero is exactly 1.0 and functionally harmless), while defects
/// that inflate confidences measure >= ~45 against the tiny expected norm.
/// Deliberately loose within that gap, pending real-hardware measurements.
pub(crate) const CONFIDENCE_RELATIVE_L2_THRESHOLD: f64 = 2.0;

/// Reference outputs are compared on a deterministic strided sample capped at
/// this many elements, so large detector outputs stay small in the committed
/// golden data. Embedding outputs fit entirely below the cap.
const MAX_REFERENCE_SAMPLES: usize = 4096;

/// The fixed input for a golden self-test.
pub enum GoldenInput {
    /// Uniform [0, 1) noise from [`seeded_noise`], sized to `input_shape`.
    SeededF32 { seed: u64 },
    /// Pre-tokenized CLIP text token ids.
    I32 { data: &'static [i32] },
}

/// How a model's output is compared against its golden output.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GoldenMetric {
    /// For embedding outputs, which downstream code consumes via cosine
    /// similarity; scale differences are irrelevant there.
    CosineDistance,
    /// For detector rows whose confidence values are much smaller than their
    /// coordinates. Confidence and all remaining values are compared
    /// separately so coordinate magnitudes cannot hide score corruption.
    DetectorRelativeL2 {
        row_len: usize,
        confidence_offset: usize,
    },
}

impl GoldenMetric {
    pub fn label(self) -> &'static str {
        match self {
            Self::CosineDistance => "cosine distance",
            Self::DetectorRelativeL2 { .. } => "detector channel relative L2 error",
        }
    }

    /// The loosest accepted distance; separation checks must measure beyond
    /// this. [`compare_output`] applies the per-group thresholds.
    pub fn threshold(self) -> f64 {
        match self {
            Self::CosineDistance => COSINE_DISTANCE_THRESHOLD,
            Self::DetectorRelativeL2 { .. } => CONFIDENCE_RELATIVE_L2_THRESHOLD,
        }
    }
}

/// A committed golden record for one model file.
pub struct GoldenEntry {
    /// The model's canonical file name; entries are keyed by file name so
    /// that a model update (which changes the file name) can never silently
    /// reuse a stale golden: the lookup misses and the accelerated provider
    /// is denied.
    pub model_file: &'static str,
    /// SHA-256 of the model file's contents, copied from the asset lock
    /// (`infra/ml/test/ml_indexing/assets.json`) at generation time. Not
    /// checked on device; a cheap unit test in `golden_tooling` compares it
    /// against the asset lock so that a model content change — even under an
    /// unchanged file name — fails CI until the goldens are regenerated.
    pub model_sha256: &'static str,
    pub input: GoldenInput,
    pub input_shape: &'static [i64],
    pub metric: GoldenMetric,
    /// Length of the model's full first output, used to derive the sample
    /// stride and to reject outputs of unexpected shape.
    pub output_len: usize,
    /// Strided sample of the CPU-generated first output.
    pub expected_sample: &'static [f32],
}

/// Finds the golden entry for a model path. `None` means the model must not
/// run on an accelerated execution provider.
pub fn lookup(model_path: &str) -> Option<&'static GoldenEntry> {
    let file_name = std::path::Path::new(model_path).file_name()?.to_str()?;
    GOLDEN_ENTRIES
        .iter()
        .find(|entry| matches_model_file(file_name, entry.model_file))
}

/// The app stores downloaded models under URL-derived sanitized names (see
/// `RemoteAssetsService._urlToFileName` in the photos app): the protocol is
/// stripped and every character outside `[A-Za-z0-9_]` — including dots —
/// becomes `_`, e.g. `models_ente_com_yolov5s_face_640_640_static_b1_onnx`.
/// An entry therefore matches when the sanitized on-disk name equals the
/// sanitized canonical name, or ends with it at an `_` boundary (the URL host
/// prefix). Exact canonical names (tests, tooling) also match.
fn matches_model_file(file_name: &str, model_file: &str) -> bool {
    if file_name == model_file {
        return true;
    }
    let sanitized_name = sanitize_file_name(file_name);
    let sanitized_model = sanitize_file_name(model_file);
    sanitized_name == sanitized_model
        || sanitized_name
            .strip_suffix(&sanitized_model)
            .is_some_and(|prefix| prefix.ends_with('_'))
}

fn sanitize_file_name(value: &str) -> String {
    value
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() || character == '_' {
                character
            } else {
                '_'
            }
        })
        .collect()
}

/// A golden input materialized for one inference run. Built identically by
/// the on-device self-test and the golden generator.
pub enum PreparedGoldenInput {
    F32(Vec<f32>),
    I32(Vec<i32>),
}

impl PreparedGoldenInput {
    /// A zero-filled input with the same element type and length.
    pub fn zeroed(&self) -> Self {
        match self {
            Self::F32(data) => Self::F32(vec![0.0; data.len()]),
            Self::I32(data) => Self::I32(vec![0; data.len()]),
        }
    }
}

/// Materializes the entry's fixed input tensor data.
pub fn prepare_input(entry: &GoldenEntry) -> Result<PreparedGoldenInput, String> {
    let element_count: i64 = entry.input_shape.iter().product();
    let element_count = usize::try_from(element_count)
        .map_err(|_| format!("invalid golden input shape {:?}", entry.input_shape))?;
    match &entry.input {
        GoldenInput::SeededF32 { seed } => {
            Ok(PreparedGoldenInput::F32(seeded_noise(*seed, element_count)))
        }
        GoldenInput::I32 { data } => {
            if data.len() != element_count {
                return Err(format!(
                    "golden token count {} does not match input shape {:?}",
                    data.len(),
                    entry.input_shape
                ));
            }
            Ok(PreparedGoldenInput::I32(data.to_vec()))
        }
    }
}

/// Deterministic uniform [0, 1) noise shared by the on-device self-test and
/// the golden generator. xorshift64*; must never change without regenerating
/// `golden_data.rs`.
pub fn seeded_noise(seed: u64, len: usize) -> Vec<f32> {
    let mut state = seed.max(1);
    (0..len)
        .map(|_| {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            let value = state.wrapping_mul(0x2545_F491_4F6C_DD1D);
            // Use the top 24 bits for an exactly representable f32 in [0, 1).
            (value >> 40) as f32 / (1u32 << 24) as f32
        })
        .collect()
}

/// The deterministic sample of a full output that golden entries store and
/// self-tests compare against.
pub fn sample_output(output: &[f32]) -> Vec<f32> {
    let stride = sample_stride(output.len());
    output.iter().copied().step_by(stride).collect()
}

fn sample_stride(output_len: usize) -> usize {
    output_len.div_ceil(MAX_REFERENCE_SAMPLES).max(1)
}

/// Compares a session's full first output against a golden entry using the
/// entry's metric. Returns the measured distance, or a description of why the
/// output is rejected.
pub fn compare_output(entry: &GoldenEntry, output: &[f32]) -> Result<f64, String> {
    let distances = measure_output(entry, output)?;
    match distances {
        OutputDistances::Cosine(distance) => ensure_within_threshold(
            "output cosine distance",
            distance,
            COSINE_DISTANCE_THRESHOLD,
        ),
        OutputDistances::Detector {
            confidence,
            remaining,
        } => {
            ensure_within_threshold(
                "detector confidence relative L2 error",
                confidence,
                CONFIDENCE_RELATIVE_L2_THRESHOLD,
            )?;
            ensure_within_threshold(
                "detector remaining-output relative L2 error",
                remaining,
                RELATIVE_L2_THRESHOLD,
            )?;
            Ok(confidence.max(remaining))
        }
    }
}

/// Measures an output's distance from the committed golden without applying
/// the acceptance threshold. Useful for checking that a warm-up input's
/// output is well separated from the golden output.
pub fn output_distance(entry: &GoldenEntry, output: &[f32]) -> Result<f64, String> {
    Ok(match measure_output(entry, output)? {
        OutputDistances::Cosine(distance) => distance,
        OutputDistances::Detector {
            confidence,
            remaining,
        } => confidence.max(remaining),
    })
}

/// Validates the properties required of the zero-input warm-up output. The
/// warm-up has no numeric golden, but it must still produce a complete finite
/// tensor before the session can proceed to the golden comparison.
pub fn validate_output(entry: &GoldenEntry, output: &[f32]) -> Result<(), String> {
    if output.len() != entry.output_len {
        return Err(format!(
            "output length {} does not match golden length {}",
            output.len(),
            entry.output_len
        ));
    }

    if let Some(bad) = output.iter().find(|value| !value.is_finite()) {
        return Err(format!("output contains non-finite values ({bad})"));
    }
    Ok(())
}

enum OutputDistances {
    Cosine(f64),
    Detector { confidence: f64, remaining: f64 },
}

fn measure_output(entry: &GoldenEntry, output: &[f32]) -> Result<OutputDistances, String> {
    validate_output(entry, output)?;

    let sample = sample_output(output);
    if sample.len() != entry.expected_sample.len() {
        return Err(format!(
            "output sample length {} does not match golden sample length {}",
            sample.len(),
            entry.expected_sample.len()
        ));
    }

    match entry.metric {
        GoldenMetric::CosineDistance => Ok(OutputDistances::Cosine(cosine_distance(
            &sample,
            entry.expected_sample,
        )?)),
        GoldenMetric::DetectorRelativeL2 {
            row_len,
            confidence_offset,
        } => {
            let (confidence_distance, remaining_distance) = detector_relative_l2_errors(
                &sample,
                entry.expected_sample,
                entry.output_len,
                row_len,
                confidence_offset,
            )?;
            Ok(OutputDistances::Detector {
                confidence: confidence_distance,
                remaining: remaining_distance,
            })
        }
    }
}

fn ensure_within_threshold(label: &str, distance: f64, threshold: f64) -> Result<f64, String> {
    if distance > threshold {
        return Err(format!(
            "{label} {distance:.6} exceeds threshold {threshold}"
        ));
    }
    Ok(distance)
}

fn detector_relative_l2_errors(
    actual_sample: &[f32],
    expected_sample: &[f32],
    output_len: usize,
    row_len: usize,
    confidence_offset: usize,
) -> Result<(f64, f64), String> {
    if row_len == 0 || confidence_offset >= row_len {
        return Err(format!(
            "invalid detector layout: row length {row_len}, confidence offset {confidence_offset}"
        ));
    }
    if !output_len.is_multiple_of(row_len) {
        return Err(format!(
            "detector output length {output_len} is not divisible by row length {row_len}"
        ));
    }

    let stride = sample_stride(output_len);
    let mut actual_confidences = Vec::new();
    let mut expected_confidences = Vec::new();
    let mut actual_remaining = Vec::new();
    let mut expected_remaining = Vec::new();
    for (sample_index, (&actual, &expected)) in
        actual_sample.iter().zip(expected_sample).enumerate()
    {
        let output_index = sample_index * stride;
        if output_index % row_len == confidence_offset {
            actual_confidences.push(actual);
            expected_confidences.push(expected);
        } else {
            actual_remaining.push(actual);
            expected_remaining.push(expected);
        }
    }
    if actual_confidences.is_empty() {
        return Err("detector golden sample contains no confidence values".to_string());
    }
    if actual_remaining.is_empty() {
        return Err("detector golden sample contains no non-confidence values".to_string());
    }

    Ok((
        relative_l2_error(&actual_confidences, &expected_confidences)?,
        relative_l2_error(&actual_remaining, &expected_remaining)?,
    ))
}

fn cosine_distance(actual_sample: &[f32], expected_sample: &[f32]) -> Result<f64, String> {
    let mut dot = 0.0f64;
    let mut actual_norm_squared = 0.0f64;
    let mut expected_norm_squared = 0.0f64;
    for (actual, expected) in actual_sample.iter().zip(expected_sample) {
        let actual = f64::from(*actual);
        let expected = f64::from(*expected);
        dot += actual * expected;
        actual_norm_squared += actual * actual;
        expected_norm_squared += expected * expected;
    }

    let denominator = (actual_norm_squared * expected_norm_squared).sqrt();
    if denominator <= f64::MIN_POSITIVE {
        return Err("output or golden sample is a zero vector".to_string());
    }
    Ok(1.0 - (dot / denominator).clamp(-1.0, 1.0))
}

fn relative_l2_error(actual_sample: &[f32], expected_sample: &[f32]) -> Result<f64, String> {
    let mut error_squared = 0.0f64;
    let mut expected_norm_squared = 0.0f64;
    for (actual, expected) in actual_sample.iter().zip(expected_sample) {
        let actual = f64::from(*actual);
        let expected = f64::from(*expected);
        let difference = actual - expected;
        error_squared += difference * difference;
        expected_norm_squared += expected * expected;
    }

    if expected_norm_squared.sqrt() <= f64::MIN_POSITIVE {
        return Err("golden sample is a zero vector".to_string());
    }
    Ok((error_squared / expected_norm_squared).sqrt())
}

#[cfg(test)]
mod tests {
    use super::{
        COSINE_DISTANCE_THRESHOLD, GOLDEN_ENTRIES, GoldenEntry, GoldenInput, GoldenMetric,
        PreparedGoldenInput, compare_output, matches_model_file, seeded_noise, validate_output,
    };

    fn entry_with_metric(
        metric: GoldenMetric,
        expected_sample: &'static [f32],
        output_len: usize,
    ) -> GoldenEntry {
        GoldenEntry {
            model_file: "model.onnx",
            model_sha256: "0000000000000000000000000000000000000000000000000000000000000000",
            input: GoldenInput::SeededF32 { seed: 7 },
            input_shape: &[1, 4],
            metric,
            output_len,
            expected_sample,
        }
    }

    fn entry_for(expected_sample: &'static [f32], output_len: usize) -> GoldenEntry {
        entry_with_metric(GoldenMetric::CosineDistance, expected_sample, output_len)
    }

    /// Downloaded models are stored under URL-derived sanitized names; the
    /// canonical name must match both those and its plain form.
    #[test]
    fn matches_canonical_and_app_sanitized_model_file_names() {
        const CANONICAL: &str = "yolov5s_face_640_640_static_b1.onnx";
        assert!(matches_model_file(CANONICAL, CANONICAL));
        assert!(matches_model_file(
            "models_ente_com_yolov5s_face_640_640_static_b1_onnx",
            CANONICAL
        ));
        assert!(matches_model_file(
            "models_ente_io_yolov5s_face_640_640_static_b1_onnx",
            CANONICAL
        ));

        assert!(!matches_model_file(
            "models_ente_com_mobileclip_s2_image_gelu_opset20_onnx",
            CANONICAL
        ));
        // A different model whose name merely contains the canonical name
        // without an underscore boundary must not match.
        assert!(!matches_model_file(
            "models_ente_com_xyolov5s_face_640_640_static_b1_onnx",
            CANONICAL
        ));
    }

    /// No committed entry may match another entry's on-device name, otherwise
    /// a model could be validated against the wrong golden.
    #[test]
    fn committed_entries_are_unambiguous_for_app_sanitized_names() {
        for entry in GOLDEN_ENTRIES {
            let device_name = format!(
                "models_ente_com_{}",
                super::sanitize_file_name(entry.model_file)
            );
            let matching = GOLDEN_ENTRIES
                .iter()
                .filter(|candidate| matches_model_file(&device_name, candidate.model_file))
                .count();
            assert_eq!(matching, 1, "ambiguous golden entry for {device_name}");
        }
    }

    #[test]
    fn seeded_noise_is_deterministic_and_in_unit_range() {
        let first = seeded_noise(42, 1000);
        let second = seeded_noise(42, 1000);
        assert_eq!(first, second);
        assert!(first.iter().all(|value| (0.0..1.0).contains(value)));
        assert_ne!(first, seeded_noise(43, 1000));
        // Not degenerate: values actually vary.
        assert!(first.iter().any(|value| *value > 0.9));
        assert!(first.iter().any(|value| *value < 0.1));
    }

    #[test]
    fn zeroed_input_preserves_type_and_length() {
        let f32_input = PreparedGoldenInput::F32(vec![1.0, 2.0, 3.0]);
        let i32_input = PreparedGoldenInput::I32(vec![1, 2]);

        let PreparedGoldenInput::F32(f32_zeroes) = f32_input.zeroed() else {
            panic!("f32 input changed type");
        };
        let PreparedGoldenInput::I32(i32_zeroes) = i32_input.zeroed() else {
            panic!("i32 input changed type");
        };
        assert_eq!(f32_zeroes, vec![0.0; 3]);
        assert_eq!(i32_zeroes, vec![0; 2]);
    }

    #[test]
    fn accepts_output_close_to_golden() {
        static EXPECTED: [f32; 4] = [0.5, -1.0, 2.0, 0.25];
        let entry = entry_for(&EXPECTED, 4);
        let output = [0.5001, -0.9999, 2.0002, 0.2501];

        let distance = compare_output(&entry, &output).unwrap();
        assert!(distance < COSINE_DISTANCE_THRESHOLD);
    }

    #[test]
    fn rejects_output_far_from_golden() {
        static EXPECTED: [f32; 4] = [0.5, -1.0, 2.0, 0.25];
        let entry = entry_for(&EXPECTED, 4);
        let output = [-0.5, 1.0, -2.0, 0.25];

        let error = compare_output(&entry, &output).unwrap_err();
        assert!(error.contains("cosine distance"), "{error}");
    }

    #[test]
    fn rejects_output_of_unexpected_length() {
        static EXPECTED: [f32; 4] = [0.5, -1.0, 2.0, 0.25];
        let entry = entry_for(&EXPECTED, 4);

        let error = compare_output(&entry, &[0.5, -1.0]).unwrap_err();
        assert!(error.contains("length"), "{error}");
    }

    #[test]
    fn rejects_non_finite_output() {
        static EXPECTED: [f32; 4] = [0.5, -1.0, 2.0, 0.25];
        let entry = entry_for(&EXPECTED, 4);

        let error = compare_output(&entry, &[0.5, f32::NAN, 2.0, 0.25]).unwrap_err();
        assert!(error.contains("non-finite"), "{error}");
    }

    #[test]
    fn warm_up_validation_checks_the_full_output_not_only_the_golden_sample() {
        static EXPECTED: [f32; 1] = [1.0];
        let entry = entry_for(&EXPECTED, 10_000);
        let mut output = vec![1.0; 10_000];
        // The committed golden would sample every third value for this output
        // length, so this index demonstrates that validation is full-tensor.
        output[9_998] = f32::INFINITY;

        let error = validate_output(&entry, &output).unwrap_err();
        assert!(error.contains("non-finite"), "{error}");
    }

    #[test]
    fn rejects_zero_output() {
        static EXPECTED: [f32; 4] = [0.5, -1.0, 2.0, 0.25];
        let entry = entry_for(&EXPECTED, 4);

        let error = compare_output(&entry, &[0.0; 4]).unwrap_err();
        assert!(error.contains("zero vector"), "{error}");
    }

    /// Cosine is scale-invariant by design (embedding consumers normalize),
    /// so the detector entries must use relative L2, which rejects
    /// magnitude-corrupted output.
    #[test]
    fn relative_l2_rejects_scale_corrupted_output_that_cosine_accepts() {
        static EXPECTED: [f32; 4] = [0.5, -1.0, 2.0, 0.25];
        let scaled = [1.0, -2.0, 4.0, 0.5];

        let cosine_entry = entry_for(&EXPECTED, 4);
        assert!(compare_output(&cosine_entry, &scaled).is_ok());

        let l2_entry = entry_with_metric(
            GoldenMetric::DetectorRelativeL2 {
                row_len: 2,
                confidence_offset: 1,
            },
            &EXPECTED,
            4,
        );
        let error = compare_output(&l2_entry, &scaled).unwrap_err();
        assert!(error.contains("relative L2"), "{error}");
    }

    #[test]
    fn relative_l2_accepts_output_close_to_golden() {
        static EXPECTED: [f32; 4] = [0.5, -1.0, 2.0, 0.25];
        let entry = entry_with_metric(
            GoldenMetric::DetectorRelativeL2 {
                row_len: 2,
                confidence_offset: 1,
            },
            &EXPECTED,
            4,
        );
        let output = [0.5001, -0.9999, 2.0002, 0.2501];

        let distance = compare_output(&entry, &output).unwrap();
        assert!(distance < super::RELATIVE_L2_THRESHOLD);
    }

    fn detector_entry(expected_sample: &'static [f32]) -> GoldenEntry {
        entry_with_metric(
            GoldenMetric::DetectorRelativeL2 {
                row_len: 16,
                confidence_offset: 4,
            },
            expected_sample,
            expected_sample.len(),
        )
    }

    /// Background confidences flushed to zero measure exactly 1.0, below the
    /// deliberately loose confidence threshold: some fp16 pipelines flush
    /// subnormals, and a zeroed background score is functionally identical to
    /// a tiny one. An all-zero *output* is still rejected via the coordinate
    /// group.
    #[test]
    fn detector_metric_tolerates_fully_flushed_confidences() {
        static EXPECTED: [f32; 32] = [
            100.0, 100.0, 20.0, 20.0, 0.001, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0, 17.0, 18.0,
            19.0, 0.98, 200.0, 200.0, 40.0, 40.0, 0.002, 20.0, 21.0, 22.0, 23.0, 24.0, 25.0, 26.0,
            27.0, 28.0, 29.0, 0.99,
        ];
        let entry = detector_entry(&EXPECTED);
        let mut output = EXPECTED;
        for confidence in output.iter_mut().skip(4).step_by(16) {
            *confidence = 0.0;
        }

        let distance = compare_output(&entry, &output).unwrap();
        assert!(
            (distance - 1.0).abs() < 1e-9,
            "flushed confidences must measure exactly 1.0, got {distance}"
        );
    }

    #[test]
    fn detector_metric_rejects_all_one_confidences() {
        static EXPECTED: [f32; 32] = [
            100.0, 100.0, 20.0, 20.0, 0.001, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0, 17.0, 18.0,
            19.0, 0.98, 200.0, 200.0, 40.0, 40.0, 0.002, 20.0, 21.0, 22.0, 23.0, 24.0, 25.0, 26.0,
            27.0, 28.0, 29.0, 0.99,
        ];
        let entry = detector_entry(&EXPECTED);
        let mut output = EXPECTED;
        for confidence in output.iter_mut().skip(4).step_by(16) {
            *confidence = 1.0;
        }

        let error = compare_output(&entry, &output).unwrap_err();
        assert!(error.contains("detector confidence"), "{error}");
    }

    /// Coordinate corruption must fail even where the looser confidence
    /// threshold would accept it.
    #[test]
    fn detector_metric_keeps_the_strict_threshold_for_coordinates() {
        static EXPECTED: [f32; 32] = [
            100.0, 100.0, 20.0, 20.0, 0.001, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0, 17.0, 18.0,
            19.0, 0.98, 200.0, 200.0, 40.0, 40.0, 0.002, 20.0, 21.0, 22.0, 23.0, 24.0, 25.0, 26.0,
            27.0, 28.0, 29.0, 0.99,
        ];
        let entry = detector_entry(&EXPECTED);
        let mut output = EXPECTED;
        for (index, value) in output.iter_mut().enumerate() {
            if index % 16 != 4 {
                *value *= 1.25;
            }
        }

        let error = compare_output(&entry, &output).unwrap_err();
        assert!(error.contains("remaining"), "{error}");
    }

    /// A confidence-group deviation beyond the coordinate threshold must
    /// still be accepted (fp16 noise floor).
    #[test]
    fn detector_metric_tolerates_noise_floor_divergence_on_confidences() {
        static EXPECTED: [f32; 32] = [
            100.0, 100.0, 20.0, 20.0, 0.001, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0, 17.0, 18.0,
            19.0, 0.98, 200.0, 200.0, 40.0, 40.0, 0.002, 20.0, 21.0, 22.0, 23.0, 24.0, 25.0, 26.0,
            27.0, 28.0, 29.0, 0.99,
        ];
        let entry = detector_entry(&EXPECTED);
        let mut output = EXPECTED;
        for confidence in output.iter_mut().skip(4).step_by(16) {
            *confidence *= 1.15;
        }

        let distance = compare_output(&entry, &output).unwrap();
        assert!(
            distance > super::RELATIVE_L2_THRESHOLD,
            "distance {distance} must exceed the coordinate threshold to discriminate"
        );
    }

    #[test]
    fn samples_large_outputs_with_a_deterministic_stride() {
        let output: Vec<f32> = (0..10_000).map(|index| index as f32).collect();
        let sample = super::sample_output(&output);
        assert_eq!(sample.len(), output.len().div_ceil(3));
        assert_eq!(sample[0], 0.0);
        assert_eq!(sample[1], 3.0);
    }
}
