//! Generation and verification of the committed golden self-test data.
//!
//! Regeneration (`render_golden_data`) runs the production models on the CPU
//! execution provider and is invoked manually via the `ml_goldens` developer
//! tool's `generate` command.
//! Verification (`verify_goldens_against_pins`) is metadata-only and runs as
//! a plain unit test in every CI pass.

use std::collections::BTreeMap;
use std::path::Path;

use ort::value::ValueType;

use crate::ml::{clip, golden, golden_data::GOLDEN_ENTRIES, onnx};

pub use crate::ml::golden::GoldenMetric;

/// One fixed seed for all noise inputs. Inputs need not differ across models
/// (each model's input is shaped and consumed independently), and each entry
/// stores its seed, so the device never depends on this constant.
const GOLDEN_NOISE_SEED: u64 = 0x0060_1DE2_5EED_2026;

const GENERATED_FILE_HEADER: &str = "\
//! GENERATED FILE — do not edit by hand.
//!
//! Regenerate with:
//!   cargo run -p ente-photos --example ml_goldens -- generate
//!
//! TODO: the pet models are CPU-only and therefore have no golden entries
//! yet; they must get entries here before they are moved off CPU-only
//! execution (see `MlRuntime::new` in runtime.rs).

use crate::ml::golden::{GoldenEntry, GoldenInput, GoldenMetric};

pub(crate) static GOLDEN_ENTRIES: &[GoldenEntry] = &[
";

/// A production model to generate a golden entry for.
pub struct GoldenModelSpec {
    pub model_path: String,
    /// SHA-256 of the model file as pinned in the asset lock; embedded into
    /// the generated entry so that CI can detect a content change without
    /// re-running inference.
    pub sha256: String,
    pub input: GoldenSpecInput,
    /// `CosineDistance` for embedding outputs and a relative-L2 variant for
    /// raw tensor outputs.
    pub metric: GoldenMetric,
}

pub enum GoldenSpecInput {
    /// Deterministic noise seeded from the model file name.
    SeededNoise,
    /// A fixed phrase tokenized with the production CLIP tokenizer.
    ClipText { phrase: String, vocab_path: String },
}

/// Measured separation between a zero-input warm-up and the committed golden
/// when both are run consecutively on one CPU session.
pub struct ZeroGoldenSeparation {
    pub model_file: String,
    pub metric_label: &'static str,
    pub golden_distance: f64,
    pub zero_distance: f64,
    pub threshold: f64,
}

/// Renders the complete contents of `golden_data.rs` for the given models.
pub fn render_golden_data(models: &[GoldenModelSpec]) -> Result<String, String> {
    let mut source = String::from(GENERATED_FILE_HEADER);
    for spec in models {
        source.push_str(&render_entry(spec)?);
    }
    source.push_str("];\n");
    Ok(source)
}

/// Runs the production self-test sequence on CPU and measures whether a
/// stale zero-input result would be rejected by the committed golden.
pub fn measure_zero_golden_separation(model_path: &str) -> Result<ZeroGoldenSeparation, String> {
    let model_file = model_file_name(model_path)?;
    let entry = golden::lookup(model_path)
        .ok_or_else(|| format!("{model_file}: no committed golden entry"))?;
    let mut session = build_cpu_session(model_path)?;
    let golden_input = golden::prepare_input(entry)
        .map_err(|error| format!("{model_file}: preparing golden input: {error}"))?;
    let zero_input = golden_input.zeroed();

    let zero_output = onnx::run_golden_tensor(&mut session, entry.input_shape, &zero_input)
        .map_err(|error| format!("{model_file}: zero-input CPU inference failed: {error}"))?;
    golden::validate_output(entry, &zero_output)
        .map_err(|error| format!("{model_file}: invalid zero-input output: {error}"))?;

    let golden_output = onnx::run_golden_tensor(&mut session, entry.input_shape, &golden_input)
        .map_err(|error| format!("{model_file}: golden CPU inference failed: {error}"))?;
    let golden_distance = golden::compare_output(entry, &golden_output)
        .map_err(|error| format!("{model_file}: golden output rejected: {error}"))?;
    let zero_distance = golden::output_distance(entry, &zero_output)
        .map_err(|error| format!("{model_file}: measuring zero-input output: {error}"))?;

    Ok(ZeroGoldenSeparation {
        model_file: model_file.to_string(),
        metric_label: entry.metric.label(),
        golden_distance,
        zero_distance,
        threshold: entry.metric.threshold(),
    })
}

/// A production model as pinned in the asset lock
/// (`infra/ml/test/ml_indexing/assets.json`).
pub struct PinnedModel {
    pub file_name: String,
    pub sha256: String,
}

/// Cheaply verifies that the committed goldens correspond exactly to the
/// pinned production models, by file name and content hash. Returns
/// human-readable failures; empty means consistent.
///
/// Deliberately metadata-only (no model downloads, no inference) so it runs
/// as a plain unit test in every CI pass. This catches the two realistic
/// ways goldens go stale — a model update (new file name) and a content
/// change under an unchanged name — but not numeric drift of the CPU
/// execution provider itself; the wide on-device thresholds absorb that.
pub fn verify_goldens_against_pins(pins: &[PinnedModel]) -> Vec<String> {
    let mut failures = Vec::new();

    let pinned: BTreeMap<&str, &str> = pins
        .iter()
        .map(|pin| (pin.file_name.as_str(), pin.sha256.as_str()))
        .collect();
    let committed: BTreeMap<&str, &str> = GOLDEN_ENTRIES
        .iter()
        .map(|entry| (entry.model_file, entry.model_sha256))
        .collect();

    for (file_name, pinned_sha) in &pinned {
        match committed.get(file_name) {
            None => failures.push(format!(
                "{file_name}: no committed golden entry; regenerate golden_data.rs"
            )),
            Some(committed_sha) if committed_sha != pinned_sha => failures.push(format!(
                "{file_name}: model content changed (pinned sha256 {pinned_sha}, golden \
                 generated from {committed_sha}); regenerate golden_data.rs"
            )),
            Some(_) => {}
        }
    }
    for file_name in committed.keys() {
        if !pinned.contains_key(file_name) {
            failures.push(format!(
                "{file_name}: committed golden entry does not correspond to any pinned \
                 production model; regenerate golden_data.rs"
            ));
        }
    }

    failures
}

fn render_entry(spec: &GoldenModelSpec) -> Result<String, String> {
    let file_name = model_file_name(&spec.model_path)?;
    let mut session = build_cpu_session(&spec.model_path)?;
    let input_shape = static_input_shape(&mut session, file_name)?;
    let element_count: i64 = input_shape.iter().product();
    let element_count = usize::try_from(element_count)
        .map_err(|_| format!("{file_name}: invalid input shape {input_shape:?}"))?;

    let (input_source, prepared_input) = match &spec.input {
        GoldenSpecInput::SeededNoise => (
            format!("GoldenInput::SeededF32 {{ seed: {GOLDEN_NOISE_SEED:#x} }}"),
            golden::PreparedGoldenInput::F32(golden::seeded_noise(
                GOLDEN_NOISE_SEED,
                element_count,
            )),
        ),
        GoldenSpecInput::ClipText { phrase, vocab_path } => {
            let token_ids = clip::tokenize_clip_text(phrase, vocab_path)
                .map_err(|error| format!("{file_name}: tokenizing golden phrase: {error}"))?;
            if token_ids.len() != element_count {
                return Err(format!(
                    "{file_name}: tokenized phrase has {} ids but the model input shape \
                     {input_shape:?} expects {element_count}",
                    token_ids.len()
                ));
            }
            (
                format!("GoldenInput::I32 {{ data: &{token_ids:?} }}"),
                golden::PreparedGoldenInput::I32(token_ids),
            )
        }
    };

    let output = onnx::run_golden_tensor(&mut session, &input_shape, &prepared_input)
        .map_err(|error| format!("{file_name}: CPU inference failed: {error}"))?;
    if output.is_empty() {
        return Err(format!("{file_name}: model produced an empty output"));
    }
    if !output.iter().copied().all(f32::is_finite) {
        return Err(format!(
            "{file_name}: CPU output contains non-finite values; cannot be used as a golden"
        ));
    }
    let sample = golden::sample_output(&output);

    let mut entry = String::new();
    entry.push_str("    GoldenEntry {\n");
    entry.push_str(&format!("        model_file: \"{file_name}\",\n"));
    entry.push_str(&format!("        model_sha256: \"{}\",\n", spec.sha256));
    entry.push_str(&format!("        input: {input_source},\n"));
    entry.push_str(&format!("        input_shape: &{input_shape:?},\n"));
    entry.push_str(&format!(
        "        metric: GoldenMetric::{:?},\n",
        spec.metric
    ));
    entry.push_str(&format!("        output_len: {},\n", output.len()));
    entry.push_str("        expected_sample: &[\n");
    for chunk in sample.chunks(8) {
        let values: Vec<String> = chunk.iter().map(|value| format!("{value:?}")).collect();
        entry.push_str(&format!("            {},\n", values.join(", ")));
    }
    entry.push_str("        ],\n");
    entry.push_str("    },\n");
    Ok(entry)
}

fn model_file_name(model_path: &str) -> Result<&str, String> {
    Path::new(model_path)
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| format!("cannot derive model file name from '{model_path}'"))
}

fn build_cpu_session(model_path: &str) -> Result<ort::session::Session, String> {
    onnx::build_session(model_path, onnx::ExecutionMode::CpuOnly, "golden-tooling")
        .map(|(session, _)| session)
        .map_err(|error| format!("building CPU session for '{model_path}': {error}"))
}

/// The first input's static shape. Golden inputs require fully static shapes
/// so that device and generator tensors are identical.
fn static_input_shape(
    session: &mut ort::session::Session,
    file_name: &str,
) -> Result<Vec<i64>, String> {
    let input = session
        .inputs()
        .first()
        .ok_or_else(|| format!("{file_name}: model has no inputs"))?;
    let ValueType::Tensor { shape, .. } = input.dtype() else {
        return Err(format!("{file_name}: first input is not a tensor"));
    };
    if shape.iter().any(|&dim| dim <= 0) {
        return Err(format!(
            "{file_name}: input shape {shape:?} has dynamic dimensions; golden self-tests \
             require static input shapes"
        ));
    }
    Ok(shape.to_vec())
}

#[cfg(test)]
mod tests {
    use super::{PinnedModel, verify_goldens_against_pins};
    use crate::ml::golden_data::GOLDEN_ENTRIES;

    /// Loads the pinned production models from the asset lock. Restricted to
    /// `.onnx` files: other pinned model assets (the CLIP vocabulary) are
    /// model inputs, not models, and get no golden entries.
    fn pinned_production_models() -> Vec<PinnedModel> {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../../infra/ml/test/ml_indexing/assets.json");
        let contents = std::fs::read_to_string(&path)
            .unwrap_or_else(|error| panic!("read {}: {error}", path.display()));
        let lock: serde_json::Value = serde_json::from_str(&contents).expect("parse assets.json");
        lock["models"]
            .as_object()
            .expect("assets.json has a models object")
            .values()
            .map(|model| PinnedModel {
                file_name: model["file_name"].as_str().expect("file_name").to_string(),
                sha256: model["sha256"].as_str().expect("sha256").to_string(),
            })
            .filter(|pin| pin.file_name.ends_with(".onnx"))
            .collect()
    }

    /// The CI guard against stale goldens: a model update (new file name) or
    /// a content change under an unchanged name in the asset lock fails this
    /// test until `golden_data.rs` is regenerated with the `ml_goldens`
    /// developer tool.
    #[test]
    fn committed_goldens_are_pinned_to_the_production_models() {
        let pins = pinned_production_models();
        assert!(!pins.is_empty(), "no pinned .onnx models in assets.json");

        let failures = verify_goldens_against_pins(&pins);
        assert!(
            failures.is_empty(),
            "committed golden self-test data is stale ({} finding(s)):\n{}",
            failures.len(),
            failures.join("\n")
        );
    }

    #[test]
    fn reports_missing_content_changed_and_stale_entries() {
        let matching: Vec<PinnedModel> = GOLDEN_ENTRIES
            .iter()
            .map(|entry| PinnedModel {
                file_name: entry.model_file.to_string(),
                sha256: entry.model_sha256.to_string(),
            })
            .collect();
        assert!(verify_goldens_against_pins(&matching).is_empty());

        // A pinned model without an entry, a content change under an
        // unchanged name, and a dropped pin leaving a stale entry.
        let mut pins = matching;
        pins[0].sha256 = "f".repeat(64);
        let stale = pins.pop().unwrap();
        pins.push(PinnedModel {
            file_name: "brand_new_model.onnx".to_string(),
            sha256: "a".repeat(64),
        });

        let failures = verify_goldens_against_pins(&pins);
        assert_eq!(failures.len(), 3, "{failures:?}");
        assert!(
            failures
                .iter()
                .any(|failure| failure.contains("brand_new_model.onnx")
                    && failure.contains("no committed golden entry")),
            "{failures:?}"
        );
        assert!(
            failures
                .iter()
                .any(|failure| failure.contains("model content changed")),
            "{failures:?}"
        );
        assert!(
            failures
                .iter()
                .any(|failure| failure.contains(&stale.file_name)
                    && failure.contains("does not correspond to any pinned")),
            "{failures:?}"
        );
    }
}
