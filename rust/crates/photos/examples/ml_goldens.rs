//! Developer tooling for the committed ML self-test data.
//!
//!   cargo run -p ente-photos --example ml_goldens -- generate
//!   cargo run -p ente-photos --example ml_goldens -- validate-zero-separation

#[allow(dead_code)]
#[path = "../tests/support/mod.rs"]
mod support;

use anyhow::{Context, Result, bail};
use ente_photos::ml::golden_tooling::{
    GoldenMetric, GoldenModelSpec, GoldenSpecInput, measure_zero_golden_separation,
    render_golden_data,
};
use support::ml_indexing::{GoldenTestAssets, run_with_large_stack};

const CLIP_TEXT_GOLDEN_PHRASE: &str = "a photo of a dog playing on a sunny beach";

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let command = args.next();
    if args.next().is_some() {
        bail!(usage());
    }

    match command.as_deref() {
        Some("generate") => run_with_large_stack("generate_goldens", generate),
        Some("validate-zero-separation") => {
            run_with_large_stack("validate_zero_separation", validate_zero_separation)
        }
        _ => bail!(usage()),
    }
    Ok(())
}

fn usage() -> &'static str {
    "usage: cargo run -p ente-photos --example ml_goldens -- \
     <generate|validate-zero-separation>"
}

fn production_model_specs(assets: &GoldenTestAssets) -> Vec<GoldenModelSpec> {
    vec![
        GoldenModelSpec {
            model_path: assets.face_detection.path.to_string_lossy().into_owned(),
            sha256: assets.face_detection.sha256.clone(),
            input: GoldenSpecInput::SeededNoise,
            metric: GoldenMetric::DetectorRelativeL2 {
                row_len: 16,
                confidence_offset: 4,
            },
        },
        GoldenModelSpec {
            model_path: assets.face_embedding.path.to_string_lossy().into_owned(),
            sha256: assets.face_embedding.sha256.clone(),
            input: GoldenSpecInput::SeededNoise,
            metric: GoldenMetric::CosineDistance,
        },
        GoldenModelSpec {
            model_path: assets.clip_image.path.to_string_lossy().into_owned(),
            sha256: assets.clip_image.sha256.clone(),
            input: GoldenSpecInput::SeededNoise,
            metric: GoldenMetric::CosineDistance,
        },
        GoldenModelSpec {
            model_path: assets.clip_text.path.to_string_lossy().into_owned(),
            sha256: assets.clip_text.sha256.clone(),
            input: GoldenSpecInput::ClipText {
                phrase: CLIP_TEXT_GOLDEN_PHRASE.to_string(),
                vocab_path: assets.clip_text_vocab.to_string_lossy().into_owned(),
            },
            metric: GoldenMetric::CosineDistance,
        },
    ]
}

fn generate() -> Result<()> {
    let assets = GoldenTestAssets::load()?;
    let source = render_golden_data(&production_model_specs(&assets))
        .map_err(|error| anyhow::anyhow!("generating goldens: {error}"))?;
    let path = GoldenTestAssets::golden_data_path()?;
    std::fs::write(&path, source).with_context(|| format!("write {}", path.display()))?;

    let rustfmt = std::process::Command::new("rustfmt")
        .args(["--edition", "2024"])
        .arg(&path)
        .status()
        .with_context(|| format!("run rustfmt on {}", path.display()))?;
    if !rustfmt.success() {
        bail!("rustfmt failed on {}", path.display());
    }
    println!("wrote {}", path.display());
    Ok(())
}

fn validate_zero_separation() -> Result<()> {
    let assets = GoldenTestAssets::load()?;
    for model_path in [
        &assets.face_detection.path,
        &assets.face_embedding.path,
        &assets.clip_image.path,
        &assets.clip_text.path,
    ] {
        let separation = measure_zero_golden_separation(&model_path.to_string_lossy())
            .map_err(|error| anyhow::anyhow!(error))?;
        println!(
            "{}: metric={}, golden_distance={:.9}, zero_distance={:.9}, threshold={:.9}, \
             threshold_margin={:.1}x",
            separation.model_file,
            separation.metric_label,
            separation.golden_distance,
            separation.zero_distance,
            separation.threshold,
            separation.zero_distance / separation.threshold,
        );
        if separation.zero_distance <= separation.threshold {
            bail!(
                "{}: zero-input output is not separated from the golden ({} {:.9} <= threshold \
                 {:.9})",
                separation.model_file,
                separation.metric_label,
                separation.zero_distance,
                separation.threshold,
            );
        }
    }
    Ok(())
}
