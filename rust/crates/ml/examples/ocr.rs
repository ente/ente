#[allow(dead_code)]
#[path = "../tests/support/mod.rs"]
mod support;

use std::path::{Path, PathBuf};
use std::time::Instant;

use anyhow::{Context, Result, bail};
use ente_assets::AssetStore;
use ente_image::decode::decode_image_from_path;
use ente_ml::ocr::{
    DetectRegionsRequest, OcrEngine, OcrModelPaths, Point, ProbabilityMap, RegionDetectionDebug,
    TextRegion, assets,
};
use image::{GrayImage, Rgb, RgbImage};
use imageproc::drawing::draw_line_segment_mut;
use support::ml_indexing::{asset_cache_dir, load_onnx_runtime, run_with_large_stack};

const OVERLAY_COLOR: Rgb<u8> = Rgb([255, 0, 0]);

struct Options {
    dump_dir: Option<PathBuf>,
    images: Vec<String>,
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    let options = parse_args(std::env::args().skip(1))?;
    load_onnx_runtime().await?;
    let store = AssetStore::new(asset_cache_dir()?);
    let paths = assets::ensure_models(&store).await?;
    run_with_large_stack("ocr", move || run(options, paths))
}

fn usage() -> &'static str {
    "usage: cargo run -p ente-ml --example ocr -- [--regions] [--all-confidences] \
     [--dump-dir DIR] <image>..."
}

fn parse_args(mut args: impl Iterator<Item = String>) -> Result<Options> {
    let mut options = Options {
        dump_dir: None,
        images: Vec::new(),
    };
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--regions" | "--all-confidences" => {}
            "--dump-dir" => {
                let dir = args.next().context("--dump-dir needs a directory")?;
                options.dump_dir = Some(PathBuf::from(dir));
            }
            other if other.starts_with("--") => bail!("unknown option {other}\n{}", usage()),
            image => options.images.push(image.to_string()),
        }
    }
    if options.images.is_empty() {
        bail!(usage());
    }
    Ok(options)
}

fn run(options: Options, paths: OcrModelPaths) -> Result<()> {
    let engine = OcrEngine::new(paths)?;
    let mut failures = 0usize;
    for image_path in &options.images {
        match detect_regions(&engine, image_path, options.dump_dir.as_deref()) {
            Ok(()) => {}
            Err(error) => {
                failures += 1;
                eprintln!("{image_path}: {error:#}");
            }
        }
    }
    if failures > 0 {
        bail!("{failures} image(s) failed");
    }
    Ok(())
}

fn detect_regions(engine: &OcrEngine, image_path: &str, dump_dir: Option<&Path>) -> Result<()> {
    let started = Instant::now();
    let debug = engine.detect_text_regions_debug(&DetectRegionsRequest {
        image_path: image_path.to_string(),
        request_id: None,
    })?;
    let elapsed_ms = started.elapsed().as_millis();
    let result = &debug.result;
    println!(
        "{image_path}: decoded {}x{}, working {}x{}, probmap {}x{}, {} regions in {elapsed_ms}ms",
        result.image_width,
        result.image_height,
        debug.working_width,
        debug.working_height,
        debug.probability_map.width,
        debug.probability_map.height,
        result.regions.len()
    );
    for region in &result.regions {
        println!("  {}", format_region(region));
    }
    if let Some(dir) = dump_dir {
        dump(dir, image_path, &debug)?;
    }
    Ok(())
}

fn format_region(region: &TextRegion) -> String {
    let corners = region
        .points
        .iter()
        .map(|point| format!("({:.0},{:.0})", point.x, point.y))
        .collect::<Vec<_>>()
        .join(" ");
    format!("[{:.3}] {corners}", region.confidence)
}

fn dump(dir: &Path, image_path: &str, debug: &RegionDetectionDebug) -> Result<()> {
    let stem = Path::new(image_path)
        .file_stem()
        .and_then(|stem| stem.to_str())
        .with_context(|| format!("no file stem in {image_path}"))?;
    let target = dir.join(stem);
    std::fs::create_dir_all(&target).with_context(|| format!("create {}", target.display()))?;
    probability_map_image(&debug.probability_map)?
        .save(target.join("probmap.png"))
        .context("write probmap.png")?;
    overlay_image(image_path, &debug.result.regions)?
        .save(target.join("overlay.png"))
        .context("write overlay.png")?;
    println!("  wrote {}", target.display());
    Ok(())
}

fn probability_map_image(map: &ProbabilityMap) -> Result<GrayImage> {
    let pixels = map
        .values
        .iter()
        .map(|value| (value.clamp(0.0, 1.0) * 255.0).round() as u8)
        .collect();
    GrayImage::from_raw(map.width as u32, map.height as u32, pixels)
        .context("probability map size does not match its values")
}

fn overlay_image(image_path: &str, regions: &[TextRegion]) -> Result<RgbImage> {
    let decoded = decode_image_from_path(image_path)?;
    let mut canvas = RgbImage::from_raw(
        decoded.dimensions.width,
        decoded.dimensions.height,
        decoded.rgb,
    )
    .context("decoded image size does not match its buffer")?;
    let thickness = (canvas.width().max(canvas.height()) / 800).clamp(1, 6);
    for region in regions {
        draw_quad(&mut canvas, &region.points, thickness);
    }
    Ok(canvas)
}

fn draw_quad(canvas: &mut RgbImage, points: &[Point; 4], thickness: u32) {
    for index in 0..4 {
        let start = points[index];
        let end = points[(index + 1) % 4];
        for offset in 0..thickness {
            let shift = offset as f32;
            draw_line_segment_mut(
                canvas,
                (start.x + shift, start.y),
                (end.x + shift, end.y),
                OVERLAY_COLOR,
            );
            draw_line_segment_mut(
                canvas,
                (start.x, start.y + shift),
                (end.x, end.y + shift),
                OVERLAY_COLOR,
            );
        }
    }
}
