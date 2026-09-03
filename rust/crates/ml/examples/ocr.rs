#[allow(dead_code)]
#[path = "../tests/support/mod.rs"]
mod support;

use std::path::{Path, PathBuf};
use std::time::Instant;

use anyhow::{Context, Result, bail};
use ente_assets::AssetStore;
use ente_image::decode::decode_image_from_path;
use ente_ml::ocr::{
    CropDebug, DetectRegionsRequest, DetectTextRequest, OcrEngine, OcrModelPaths, Orientation,
    Point, ProbabilityMap, RegionDetectionDebug, TextBlock, TextDetectionDebug,
    TextDetectionResult, TextRegion, assets,
};
use image::{GrayImage, Rgb, RgbImage};
use imageproc::drawing::draw_line_segment_mut;
use support::ml_indexing::{asset_cache_dir, load_onnx_runtime, run_with_large_stack};

const BLOCK_COLOR: Rgb<u8> = Rgb([255, 0, 0]);
const CHARACTER_COLOR: Rgb<u8> = Rgb([0, 0, 255]);

struct Options {
    regions: bool,
    all_confidences: bool,
    dump_dir: Option<PathBuf>,
    images: Vec<String>,
}

struct OcrLogger;

impl log::Log for OcrLogger {
    fn enabled(&self, metadata: &log::Metadata<'_>) -> bool {
        metadata.level() <= log::Level::Info && metadata.target().starts_with("ente_ml::ocr")
    }

    fn log(&self, record: &log::Record<'_>) {
        if self.enabled(record.metadata()) {
            eprintln!("{}", record.args());
        }
    }

    fn flush(&self) {}
}

static LOGGER: OcrLogger = OcrLogger;

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    let options = parse_args(std::env::args().skip(1))?;
    install_logger();
    load_onnx_runtime().await?;
    let store = AssetStore::new(asset_cache_dir()?);
    let paths = assets::ensure_models(&store).await?;
    run_with_large_stack("ocr", move || run(options, paths))
}

fn install_logger() {
    if log::set_logger(&LOGGER).is_ok() {
        log::set_max_level(log::LevelFilter::Info);
    }
}

fn usage() -> &'static str {
    "usage: cargo run -p ente-ml --example ocr -- [--regions] [--all-confidences] \
     [--dump-dir DIR] <image>..."
}

fn parse_args(mut args: impl Iterator<Item = String>) -> Result<Options> {
    let mut options = Options {
        regions: false,
        all_confidences: false,
        dump_dir: None,
        images: Vec::new(),
    };
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--regions" => options.regions = true,
            "--all-confidences" => options.all_confidences = true,
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
        let outcome = if options.regions {
            detect_regions(&engine, image_path, options.dump_dir.as_deref())
        } else {
            detect_text(
                &engine,
                image_path,
                options.all_confidences,
                options.dump_dir.as_deref(),
            )
        };
        if let Err(error) = outcome {
            failures += 1;
            eprintln!("{image_path}: {error:#}");
        }
    }
    if failures > 0 {
        bail!("{failures} image(s) failed");
    }
    Ok(())
}

fn detect_text(
    engine: &OcrEngine,
    image_path: &str,
    all_confidences: bool,
    dump_dir: Option<&Path>,
) -> Result<()> {
    let request = DetectTextRequest {
        image_path: image_path.to_string(),
        include_all_confidence_scores: all_confidences,
        request_id: None,
    };
    let started = Instant::now();
    match dump_dir {
        None => {
            let result = engine.detect_text(&request)?;
            print_text_result(image_path, &result, None, started.elapsed().as_millis());
        }
        Some(dir) => {
            let debug = engine.detect_text_debug(&request)?;
            print_text_result(
                image_path,
                &debug.result,
                Some((debug.working_width, debug.working_height)),
                started.elapsed().as_millis(),
            );
            let target = dump_target(dir, image_path)?;
            dump_text(&target, image_path, &debug)?;
        }
    }
    Ok(())
}

fn print_text_result(
    image_path: &str,
    result: &TextDetectionResult,
    working: Option<(u32, u32)>,
    elapsed_ms: u128,
) {
    let working = working
        .map(|(width, height)| format!(", working {width}x{height}"))
        .unwrap_or_default();
    println!(
        "{image_path}: decoded {}x{}{working}, {elapsed_ms}ms",
        result.image_width, result.image_height
    );
    for block in &result.blocks {
        println!("  {}", format_block(block));
    }
    println!("  blocks: {}", result.blocks.len());
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
        let target = dump_target(dir, image_path)?;
        dump_regions(&target, image_path, &debug)?;
    }
    Ok(())
}

fn format_block(block: &TextBlock) -> String {
    format!(
        "[{:.3}] {}  {}",
        block.confidence,
        block.text,
        format_points(&block.points)
    )
}

fn format_region(region: &TextRegion) -> String {
    format!(
        "[{:.3}] {}",
        region.confidence,
        format_points(&region.points)
    )
}

fn format_points(points: &[Point; 4]) -> String {
    points
        .iter()
        .map(|point| format!("({:.0},{:.0})", point.x, point.y))
        .collect::<Vec<_>>()
        .join(" ")
}

fn dump_target(dir: &Path, image_path: &str) -> Result<PathBuf> {
    let stem = Path::new(image_path)
        .file_stem()
        .and_then(|stem| stem.to_str())
        .with_context(|| format!("no file stem in {image_path}"))?;
    let target = dir.join(stem);
    std::fs::create_dir_all(&target).with_context(|| format!("create {}", target.display()))?;
    Ok(target)
}

fn dump_regions(target: &Path, image_path: &str, debug: &RegionDetectionDebug) -> Result<()> {
    probability_map_image(&debug.probability_map)?
        .save(target.join("probmap.png"))
        .context("write probmap.png")?;
    let mut canvas = decoded_canvas(image_path)?;
    let thickness = line_thickness(&canvas);
    for region in &debug.result.regions {
        draw_quad(&mut canvas, &region.points, thickness, BLOCK_COLOR);
    }
    canvas
        .save(target.join("overlay.png"))
        .context("write overlay.png")?;
    println!("  wrote {}", target.display());
    Ok(())
}

fn dump_text(target: &Path, image_path: &str, debug: &TextDetectionDebug) -> Result<()> {
    probability_map_image(&debug.probability_map)?
        .save(target.join("probmap.png"))
        .context("write probmap.png")?;
    block_overlay(image_path, &debug.result.blocks)?
        .save(target.join("overlay.png"))
        .context("write overlay.png")?;
    dump_crops(target, &debug.crops)?;
    println!("  wrote {}", target.display());
    Ok(())
}

fn dump_crops(target: &Path, crops: &[CropDebug]) -> Result<()> {
    let crops_dir = target.join("crops");
    std::fs::create_dir_all(&crops_dir)
        .with_context(|| format!("create {}", crops_dir.display()))?;
    for (index, crop) in crops.iter().enumerate() {
        println!("  {}", format_crop(index, crop));
        let name = crop_file_name(index, crop);
        crop_image(crop)?
            .save(crops_dir.join(&name))
            .with_context(|| format!("write {name}"))?;
    }
    Ok(())
}

fn orientation_label(orientation: Orientation) -> &'static str {
    match orientation {
        Orientation::Horizontal => "horizontal",
        Orientation::Vertical => "vertical",
    }
}

fn format_crop(index: usize, crop: &CropDebug) -> String {
    let rotated = if crop.rotated { " rotated" } else { "" };
    format!(
        "{index:03} {}x{} {}{rotated} [{:.3}] {}",
        crop.width,
        crop.height,
        orientation_label(crop.orientation),
        crop.confidence,
        crop.text
    )
}

fn crop_file_name(index: usize, crop: &CropDebug) -> String {
    let rotated = if crop.rotated { "_rot180" } else { "" };
    format!(
        "{index:03}_{}{rotated}_{:.2}.png",
        orientation_label(crop.orientation),
        crop.confidence
    )
}

fn crop_image(crop: &CropDebug) -> Result<RgbImage> {
    RgbImage::from_raw(crop.width, crop.height, crop.rgb.clone())
        .context("crop size does not match its buffer")
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

fn decoded_canvas(image_path: &str) -> Result<RgbImage> {
    let decoded = decode_image_from_path(image_path)?;
    RgbImage::from_raw(
        decoded.dimensions.width,
        decoded.dimensions.height,
        decoded.rgb,
    )
    .context("decoded image size does not match its buffer")
}

fn line_thickness(canvas: &RgbImage) -> u32 {
    (canvas.width().max(canvas.height()) / 800).clamp(1, 6)
}

fn block_overlay(image_path: &str, blocks: &[TextBlock]) -> Result<RgbImage> {
    let mut canvas = decoded_canvas(image_path)?;
    let thickness = line_thickness(&canvas);
    for character in blocks.iter().flat_map(|block| &block.characters) {
        draw_quad(&mut canvas, &character.points, thickness, CHARACTER_COLOR);
    }
    for block in blocks {
        draw_quad(&mut canvas, &block.points, thickness, BLOCK_COLOR);
    }
    Ok(canvas)
}

fn draw_quad(canvas: &mut RgbImage, points: &[Point; 4], thickness: u32, color: Rgb<u8>) {
    for index in 0..4 {
        let start = points[index];
        let end = points[(index + 1) % 4];
        for offset in 0..thickness {
            let shift = offset as f32;
            draw_line_segment_mut(
                canvas,
                (start.x + shift, start.y),
                (end.x + shift, end.y),
                color,
            );
            draw_line_segment_mut(
                canvas,
                (start.x, start.y + shift),
                (end.x, end.y + shift),
                color,
            );
        }
    }
}
