use thiserror::Error;

use super::appearance::render_document;
use super::boundary::{SearchBudget, locate, refine_capture};
use super::codec;
use super::page::{RenderPlan, SourceExtent, quarter_turns, rotate_mask_quad};
use super::segmentation::{MASK_SIDE, ProbabilityMap, Segmenter};
use super::yuv::{PlaneLayout, bgra_to_bgr, yuv420_to_bgr};
use super::{ColorMode, Quad};
use crate::cv::image::ImageU8;

const DEFAULT_MAX_PIXELS: u32 = 2_000_000;
const DEFAULT_JPEG_QUALITY: u8 = 75;

#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub enum ScanError {
    #[error("invalid input: {0}")]
    InvalidInput(String),
    #[error("model load: {0}")]
    ModelLoad(String),
    #[error("codec: {0}")]
    Codec(String),
    #[error("pipeline: {0}")]
    Pipeline(String),
}

#[derive(Debug, Clone, PartialEq)]
pub struct ReprocessOptions {
    pub quad: Quad,
    pub rotation_degrees: i32,
    pub color_mode: ColorMode,
    pub max_pixels: Option<u32>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ScanResult {
    pub quad: Option<Quad>,
    pub color_mode: ColorMode,
    pub output_width: u32,
    pub output_height: u32,
    pub source_width: u32,
    pub source_height: u32,
    pub processed_image: Vec<u8>,
}

pub struct ScannerSession {
    segmenter: Segmenter,
}

impl ScannerSession {
    pub fn new(model_path: &str) -> Result<Self, ScanError> {
        let start = std::time::Instant::now();
        let result = Self::load(model_path);
        match &result {
            Ok(_) => log::info!(
                "session ready: {} loaded in {}ms",
                basename(model_path),
                start.elapsed().as_millis()
            ),
            Err(error) => log::error!("session init failed: {error}"),
        }
        result
    }

    fn load(model_path: &str) -> Result<Self, ScanError> {
        if !std::path::Path::new(model_path).is_file() {
            return Err(ScanError::ModelLoad(format!(
                "no model file at {model_path}"
            )));
        }
        Ok(Self {
            segmenter: Segmenter::new(model_path)?,
        })
    }

    fn segment(&self, bgr: &ImageU8) -> Result<ProbabilityMap, ScanError> {
        self.segmenter
            .probability_map(bgr)
            .map_err(ScanError::Pipeline)
    }

    pub fn live_detect_bgra(
        &self,
        bgra: &[u8],
        row_stride: u32,
        width: u32,
        height: u32,
        rotation_degrees: i32,
    ) -> Result<Option<Quad>, ScanError> {
        let bgr = bgra_to_bgr(bgra, to_i32(row_stride)?, to_i32(width)?, to_i32(height)?)
            .map_err(ScanError::InvalidInput)?;
        let frame = SourceExtent::new(bgr.width, bgr.height).map_err(ScanError::InvalidInput)?;
        self.live_detect(&bgr, frame, rotation_degrees)
    }

    pub fn live_detect_yuv420(
        &self,
        y: &[u8],
        u: &[u8],
        v: &[u8],
        layout: PlaneLayout,
        rotation_degrees: i32,
    ) -> Result<Option<Quad>, ScanError> {
        let bgr = yuv420_to_bgr(y, u, v, layout, MASK_SIDE, MASK_SIDE)
            .map_err(ScanError::InvalidInput)?;
        let frame =
            SourceExtent::new(layout.width, layout.height).map_err(ScanError::InvalidInput)?;
        self.live_detect(&bgr, frame, rotation_degrees)
    }

    fn live_detect(
        &self,
        bgr: &ImageU8,
        frame_size: SourceExtent,
        rotation_degrees: i32,
    ) -> Result<Option<Quad>, ScanError> {
        let turns = quarter_turns(rotation_degrees).map_err(ScanError::InvalidInput)?;
        let mask = self.segment(bgr)?;
        let detection = locate(&mask, frame_size, SearchBudget::Live);
        log::debug!(
            "live detection: {}, evidence {:.3}",
            detection.reason,
            detection.confidence
        );
        Ok(detection
            .quad
            .map(|quad| rotate_mask_quad(quad.corners, turns, MASK_SIDE as f64)))
    }

    pub fn process_capture(
        &self,
        image_bytes: &[u8],
        max_pixels: Option<u32>,
    ) -> Result<ScanResult, ScanError> {
        let start = std::time::Instant::now();
        let result = self.process_capture_inner(image_bytes, max_pixels);
        match &result {
            Ok(scan) => log::info!(
                "capture: {}x{} -> {}x{} {:?}, quad {}, {}ms",
                scan.source_width,
                scan.source_height,
                scan.output_width,
                scan.output_height,
                scan.color_mode,
                if scan.quad.is_some() { "found" } else { "none" },
                start.elapsed().as_millis()
            ),
            Err(error) => log::error!("capture failed: {error}"),
        }
        result
    }

    fn process_capture_inner(
        &self,
        image_bytes: &[u8],
        max_pixels: Option<u32>,
    ) -> Result<ScanResult, ScanError> {
        let budget = max_pixels.unwrap_or(DEFAULT_MAX_PIXELS);
        validate_budget(budget)?;
        let bgr = codec::decode_bgr(image_bytes)?;
        let extent = SourceExtent::new(bgr.width, bgr.height).map_err(ScanError::InvalidInput)?;
        let mask = self.segment(&bgr)?;
        let detection = locate(&mask, extent, SearchBudget::Capture);
        log::debug!(
            "capture detection: {}, evidence {:.3}",
            detection.reason,
            detection.confidence
        );
        let quad = match detection.quad {
            Some(quad) => refine_capture(
                &bgr,
                quad.in_source(extent),
                quad.needs_complete_source_support,
            )
            .map_err(ScanError::Pipeline)?,
            None => None,
        };
        let Some(quad) = quad else {
            let plan = RenderPlan::new(extent.full_frame(), extent, 0, budget)
                .map_err(ScanError::Pipeline)?;
            if plan.width == bgr.width && plan.height == bgr.height {
                return finish(None, ColorMode::Color, extent, bgr, DEFAULT_JPEG_QUALITY);
            }
            let page = plan.render(&bgr).map_err(ScanError::Pipeline)?;
            drop(bgr);
            return finish(
                None,
                ColorMode::Color,
                extent,
                page.image,
                DEFAULT_JPEG_QUALITY,
            );
        };
        let plan = RenderPlan::new(quad, extent, 0, budget).map_err(ScanError::Pipeline)?;
        let mut page = plan.render(&bgr).map_err(ScanError::Pipeline)?;
        drop(bgr);
        let mode = render_document(&mut page.image, page.valid.as_deref(), None)
            .map_err(ScanError::Pipeline)?;
        finish(Some(quad), mode, extent, page.image, DEFAULT_JPEG_QUALITY)
    }

    pub fn reprocess(
        &self,
        source_bytes: &[u8],
        options: &ReprocessOptions,
    ) -> Result<ScanResult, ScanError> {
        let start = std::time::Instant::now();
        let result = self.reprocess_inner(source_bytes, options);
        match &result {
            Ok(scan) => log::info!(
                "reprocess: -> {}x{} in {}ms",
                scan.output_width,
                scan.output_height,
                start.elapsed().as_millis()
            ),
            Err(error) => log::error!("reprocess failed: {error}"),
        }
        result
    }

    fn reprocess_inner(
        &self,
        source_bytes: &[u8],
        options: &ReprocessOptions,
    ) -> Result<ScanResult, ScanError> {
        let budget = options.max_pixels.unwrap_or(DEFAULT_MAX_PIXELS);
        validate_budget(budget)?;
        quarter_turns(options.rotation_degrees).map_err(ScanError::InvalidInput)?;
        let bgr = codec::decode_bgr(source_bytes)?;
        let extent = SourceExtent::new(bgr.width, bgr.height).map_err(ScanError::InvalidInput)?;
        let plan = RenderPlan::new(options.quad, extent, options.rotation_degrees, budget)
            .map_err(ScanError::InvalidInput)?;
        let mut page = plan.render(&bgr).map_err(ScanError::Pipeline)?;
        drop(bgr);
        let mode = render_document(
            &mut page.image,
            page.valid.as_deref(),
            Some(options.color_mode),
        )
        .map_err(ScanError::Pipeline)?;
        finish(
            Some(options.quad),
            mode,
            extent,
            page.image,
            DEFAULT_JPEG_QUALITY,
        )
    }
}

fn validate_budget(budget: u32) -> Result<(), ScanError> {
    if budget == 0 {
        return Err(ScanError::InvalidInput(
            "pixel budget must be positive".to_owned(),
        ));
    }
    Ok(())
}

fn basename(path: &str) -> &str {
    std::path::Path::new(path)
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or(path)
}

fn to_i32(value: u32) -> Result<i32, ScanError> {
    i32::try_from(value)
        .map_err(|_| ScanError::InvalidInput(format!("{value} does not fit in i32")))
}

fn finish(
    quad: Option<Quad>,
    color_mode: ColorMode,
    source: SourceExtent,
    page: ImageU8,
    jpeg_quality: u8,
) -> Result<ScanResult, ScanError> {
    let output_width = page.width as u32;
    let output_height = page.height as u32;
    let processed_image = codec::encode_jpeg(page, jpeg_quality)?;

    Ok(ScanResult {
        quad,
        color_mode,
        output_width,
        output_height,
        source_width: source.width as u32,
        source_height: source.height as u32,
        processed_image,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reprocess_needs_no_model_and_repeated_original_rotations_do_not_accumulate_loss()
    -> Result<(), ScanError> {
        let session = ScannerSession {
            segmenter: Segmenter::unavailable_for_render_tests(),
        };
        let source = ImageU8::new(
            120,
            80,
            3,
            (0..120 * 80 * 3)
                .map(|i| ((i * 37 + i / 17 * 31) % 256) as u8)
                .collect(),
        )
        .map_err(ScanError::Codec)?;
        let bytes = codec::encode_jpeg(source, 90)?;
        let extent = SourceExtent::new(120, 80).map_err(ScanError::InvalidInput)?;
        let mut options = ReprocessOptions {
            quad: extent.full_frame(),
            rotation_degrees: 0,
            color_mode: ColorMode::Color,
            max_pixels: Some(6000),
        };
        let first = session.reprocess(&bytes, &options)?;
        assert_eq!(first, session.reprocess(&bytes, &options)?);
        for rotation in [90, 180, 270, 360] {
            options.rotation_degrees = rotation;
            let result = session.reprocess(&bytes, &options)?;
            assert_eq!((result.source_width, result.source_height), (120, 80));
            assert_eq!(result.quad, Some(options.quad));
            assert_eq!(result.color_mode, ColorMode::Color);
            assert!(result.output_width * result.output_height <= 6000);
            if rotation % 180 == 90 {
                assert_eq!(
                    (result.output_width, result.output_height),
                    (first.output_height, first.output_width)
                );
            }
            if rotation == 360 {
                assert_eq!(result.processed_image, first.processed_image);
            }
        }
        options.max_pixels = Some(0);
        assert!(matches!(
            session.reprocess(&bytes, &options),
            Err(ScanError::InvalidInput(_))
        ));
        Ok(())
    }
}
