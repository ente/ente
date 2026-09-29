use thiserror::Error;

use super::appearance::render_document;
use super::boundary::{SearchBudget, canonical, locate, refine_capture, refine_capture_region};
use super::codec;
use super::page::{
    RenderPlan, SourceExtent, points, quarter_turns, rotate_mask_quad, validate_quad,
};
use super::segmentation::{MASK_SIDE, ProbabilityMap, Segmenter};
use super::yuv::{PlaneLayout, bgra_to_bgr, yuv420_to_bgr};
use super::{ColorMode, Point, Quad};
use crate::cv::image::ImageU8;

const DEFAULT_MAX_PIXELS: u32 = 2_000_000;
const DEFAULT_JPEG_QUALITY: u8 = 75;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct CaptureRegion {
    pub normalized_quad: Quad,
    pub frame_width: u32,
    pub frame_height: u32,
}

impl CaptureRegion {
    fn in_source(self, source: SourceExtent) -> Result<Quad, ScanError> {
        let frame = SourceExtent::new(to_i32(self.frame_width)?, to_i32(self.frame_height)?)
            .map_err(ScanError::InvalidInput)?;
        validate_quad(
            self.normalized_quad,
            SourceExtent::new(1, 1).map_err(ScanError::InvalidInput)?,
        )
        .map_err(ScanError::InvalidInput)?;
        let sx = source.width / frame.width;
        let sy = source.height / frame.height;
        let scale = sx.min(sy);
        let width = frame.width * scale;
        let height = frame.height * scale;
        let mut corners = points(self.normalized_quad);
        let tolerance = 1.5 / MASK_SIDE as f64;
        for side in 0..4 {
            let next = (side + 1) % 4;
            for edge in [0.0, 1.0] {
                if sx <= sy
                    && (corners[side].x - edge).abs() <= tolerance
                    && (corners[next].x - edge).abs() <= tolerance
                {
                    corners[side].x = edge;
                    corners[next].x = edge;
                }
                if sy <= sx
                    && (corners[side].y - edge).abs() <= tolerance
                    && (corners[next].y - edge).abs() <= tolerance
                {
                    corners[side].y = edge;
                    corners[next].y = edge;
                }
            }
        }
        let quad = canonical(
            corners.map(|p| Point {
                x: (source.width - width) / 2.0 + p.x * width,
                y: (source.height - height) / 2.0 + p.y * height,
            }),
            source,
        );
        validate_quad(quad, source).map_err(ScanError::InvalidInput)?;
        Ok(quad)
    }
}

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
        self.process_capture_with_region(image_bytes, max_pixels, None)
    }

    pub fn process_capture_with_region(
        &self,
        image_bytes: &[u8],
        max_pixels: Option<u32>,
        region: Option<CaptureRegion>,
    ) -> Result<ScanResult, ScanError> {
        let start = std::time::Instant::now();
        let result = self.process_capture_inner(image_bytes, max_pixels, region);
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
        region: Option<CaptureRegion>,
    ) -> Result<ScanResult, ScanError> {
        let budget = max_pixels.unwrap_or(DEFAULT_MAX_PIXELS);
        validate_budget(budget)?;
        let bgr = codec::decode_bgr(image_bytes)?;
        let extent = SourceExtent::new(bgr.width, bgr.height).map_err(ScanError::InvalidInput)?;
        let quad = if let Some(region) = region {
            Some(
                refine_capture_region(&bgr, region.in_source(extent)?)
                    .map_err(ScanError::Pipeline)?,
            )
        } else {
            let mask = self.segment(&bgr)?;
            let detection = locate(&mask, extent, SearchBudget::Capture);
            log::debug!(
                "capture detection: {}, evidence {:.3}",
                detection.reason,
                detection.confidence
            );
            match detection.quad {
                Some(quad) => refine_capture(
                    &bgr,
                    quad.in_source(extent),
                    quad.needs_complete_source_support,
                )
                .map_err(ScanError::Pipeline)?,
                None => None,
            }
        };
        if let Some(quad) = quad {
            let plan = RenderPlan::new(quad, extent, 0, budget).map_err(ScanError::Pipeline)?;
            let mut page = plan.render(&bgr).map_err(ScanError::Pipeline)?;
            drop(bgr);
            let mode = render_document(&mut page.image, page.valid.as_deref(), None)
                .map_err(ScanError::Pipeline)?;
            finish(Some(quad), mode, extent, page.image, DEFAULT_JPEG_QUALITY)
        } else {
            let plan = RenderPlan::new(extent.full_frame(), extent, 0, budget)
                .map_err(ScanError::Pipeline)?;
            if plan.width == bgr.width && plan.height == bgr.height {
                finish(None, ColorMode::Color, extent, bgr, DEFAULT_JPEG_QUALITY)
            } else {
                let page = plan.render(&bgr).map_err(ScanError::Pipeline)?;
                drop(bgr);
                finish(
                    None,
                    ColorMode::Color,
                    extent,
                    page.image,
                    DEFAULT_JPEG_QUALITY,
                )
            }
        }
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
    use crate::scan::page::quad_from_points;

    fn document_source() -> Result<ImageU8, ScanError> {
        let mut data = vec![30; 120 * 80 * 3];
        for y in 20..60 {
            for x in 30..90 {
                for channel in 0..3 {
                    data[(y * 120 + x) * 3 + channel] = 210 + ((x + y + channel) % 10) as u8;
                }
            }
        }
        ImageU8::new(120, 80, 3, data).map_err(ScanError::Codec)
    }

    fn centered_region(width: u32, height: u32) -> CaptureRegion {
        CaptureRegion {
            normalized_quad: quad_from_points([
                Point { x: 0.25, y: 0.25 },
                Point { x: 0.75, y: 0.25 },
                Point { x: 0.75, y: 0.75 },
                Point { x: 0.25, y: 0.75 },
            ]),
            frame_width: width,
            frame_height: height,
        }
    }

    #[test]
    fn capture_region_is_rendered_without_redetection_and_survives_reprocessing()
    -> Result<(), ScanError> {
        let session = ScannerSession {
            segmenter: Segmenter::unavailable_for_render_tests(),
        };
        let source = document_source()?;
        let bytes = codec::encode_jpeg(source, 90)?;
        let region = centered_region(120, 80);
        let result = session.process_capture_with_region(&bytes, Some(4_000_000), Some(region))?;
        let expected_quad = result.quad.expect("supported page must be cropped");
        assert!((result.output_width as i32 - 60).abs() <= 2);
        assert!((result.output_height as i32 - 40).abs() <= 2);
        let decoded = codec::decode_bgr(&result.processed_image)?;
        assert_eq!(
            (decoded.width as u32, decoded.height as u32),
            (result.output_width, result.output_height)
        );
        let rotated = session.reprocess(
            &bytes,
            &ReprocessOptions {
                quad: expected_quad,
                rotation_degrees: 90,
                color_mode: result.color_mode,
                max_pixels: Some(4_000_000),
            },
        )?;
        assert_eq!(rotated.quad, result.quad);
        assert_eq!(
            (rotated.output_width, rotated.output_height),
            (result.output_height, result.output_width)
        );
        Ok(())
    }

    #[test]
    fn capture_region_survives_missing_still_edges_and_allows_manual_adjustment()
    -> Result<(), ScanError> {
        let session = ScannerSession {
            segmenter: Segmenter::unavailable_for_render_tests(),
        };
        let source = ImageU8::new(120, 80, 3, vec![180; 120 * 80 * 3]).map_err(ScanError::Codec)?;
        let bytes = codec::encode_jpeg(source, 90)?;
        let region = centered_region(120, 80);
        let extent = SourceExtent::new(120, 80).map_err(ScanError::InvalidInput)?;
        let mapped_quad = region.in_source(extent)?;
        let result = session.process_capture_with_region(&bytes, None, Some(region))?;
        assert_eq!(result.quad, Some(mapped_quad));
        assert_eq!((result.output_width, result.output_height), (60, 40));
        let adjusted = session.reprocess(
            &bytes,
            &ReprocessOptions {
                quad: extent.full_frame(),
                rotation_degrees: 0,
                color_mode: result.color_mode,
                max_pixels: None,
            },
        )?;
        assert_eq!((adjusted.output_width, adjusted.output_height), (120, 80));
        Ok(())
    }

    #[test]
    fn capture_region_maps_centered_preview_to_different_still_aspects() -> Result<(), ScanError> {
        for (frame, source, expected) in [
            ((300, 400), (1200, 1600), (300.0, 400.0, 900.0, 1200.0)),
            ((900, 1600), (1200, 1600), (375.0, 400.0, 825.0, 1200.0)),
            ((400, 300), (1600, 900), (500.0, 225.0, 1100.0, 675.0)),
        ] {
            let region = centered_region(frame.0, frame.1);
            let quad = region.in_source(
                SourceExtent::new(source.0, source.1).map_err(ScanError::InvalidInput)?,
            )?;
            assert_eq!(
                quad.top_left,
                Point {
                    x: expected.0,
                    y: expected.1
                }
            );
            assert_eq!(
                quad.bottom_right,
                Point {
                    x: expected.2,
                    y: expected.3
                }
            );
        }
        Ok(())
    }

    #[test]
    fn capture_region_preserves_output_across_cyclic_corner_orders() -> Result<(), ScanError> {
        let session = ScannerSession {
            segmenter: Segmenter::unavailable_for_render_tests(),
        };
        let bytes = codec::encode_jpeg(document_source()?, 90)?;
        let region = centered_region(120, 80);
        let expected = session.process_capture_with_region(&bytes, None, Some(region))?;
        let corners = points(region.normalized_quad);
        for start in 1..4 {
            let shifted = CaptureRegion {
                normalized_quad: quad_from_points(std::array::from_fn(|i| {
                    corners[(i + start) % 4]
                })),
                ..region
            };
            assert_eq!(
                session.process_capture_with_region(&bytes, None, Some(shifted))?,
                expected
            );
        }
        Ok(())
    }

    #[test]
    fn capture_region_preserves_preview_edges_inside_wider_photos() -> Result<(), ScanError> {
        let session = ScannerSession {
            segmenter: Segmenter::unavailable_for_render_tests(),
        };
        for scale in [1, 10] {
            for source_width in [110, 160] {
                let width = source_width * scale;
                let height = 80 * scale;
                let mut data = vec![30; width * height * 3];
                for y in 20 * scale..60 * scale {
                    for x in 70 * scale..150.min(source_width) * scale {
                        data[(y * width + x) * 3..(y * width + x + 1) * 3].fill(210);
                    }
                }
                let source =
                    ImageU8::new(width as i32, height as i32, 3, data).map_err(ScanError::Codec)?;
                let bytes = codec::encode_jpeg(source, 95)?;
                let wider = source_width == 160;
                for edge in [0.996, 1.0, 1.004] {
                    let region = CaptureRegion {
                        normalized_quad: quad_from_points([
                            Point {
                                x: if wider { 1.0 / 3.0 } else { 70.0 / 110.0 },
                                y: 0.25,
                            },
                            Point { x: edge, y: 0.25 },
                            Point { x: edge, y: 0.75 },
                            Point {
                                x: if wider { 1.0 / 3.0 } else { 70.0 / 110.0 },
                                y: 0.75,
                            },
                        ]),
                        frame_width: if wider { 60 } else { 110 },
                        frame_height: 80,
                    };
                    let result = session.process_capture_with_region(&bytes, None, Some(region))?;
                    let quad = result.quad.expect("captured region must remain cropped");
                    if wider {
                        assert_eq!(
                            quad,
                            region.in_source(
                                SourceExtent::new(width as i32, height as i32)
                                    .map_err(ScanError::InvalidInput)?
                            )?
                        );
                    } else {
                        assert_eq!(quad.top_right.x, width as f64);
                        assert_eq!(quad.bottom_right.x, width as f64);
                    }
                    assert!((result.output_width as i32 - 40 * scale as i32).abs() <= 3);
                    assert!((result.output_height as i32 - 40 * scale as i32).abs() <= 3);
                }
            }
        }
        Ok(())
    }

    #[test]
    fn invalid_capture_regions_fail_instead_of_silently_saving_a_full_photo()
    -> Result<(), ScanError> {
        let source = SourceExtent::new(120, 80).map_err(ScanError::InvalidInput)?;
        let region = centered_region(120, 80);
        for invalid in [
            CaptureRegion {
                frame_width: 0,
                ..region
            },
            CaptureRegion {
                frame_height: u32::MAX,
                ..region
            },
            CaptureRegion {
                normalized_quad: Quad {
                    top_left: Point {
                        x: f64::NAN,
                        y: 0.25,
                    },
                    ..region.normalized_quad
                },
                ..region
            },
            CaptureRegion {
                normalized_quad: Quad {
                    top_left: region.normalized_quad.bottom_right,
                    ..region.normalized_quad
                },
                ..region
            },
        ] {
            assert!(matches!(
                invalid.in_source(source),
                Err(ScanError::InvalidInput(_))
            ));
        }
        Ok(())
    }

    #[test]
    fn capture_region_uses_exif_oriented_source_coordinates() -> Result<(), ScanError> {
        let session = ScannerSession {
            segmenter: Segmenter::unavailable_for_render_tests(),
        };
        let source = document_source()?;
        let jpeg = codec::encode_jpeg(source, 90)?;
        for (orientation, width, height) in [(1, 120, 80), (3, 120, 80), (6, 80, 120), (8, 80, 120)]
        {
            let exif = [
                b'E',
                b'x',
                b'i',
                b'f',
                0,
                0,
                b'M',
                b'M',
                0,
                42,
                0,
                0,
                0,
                8,
                0,
                1,
                1,
                18,
                0,
                3,
                0,
                0,
                0,
                1,
                0,
                orientation,
                0,
                0,
                0,
                0,
                0,
                0,
            ];
            let mut bytes = jpeg[..2].to_vec();
            bytes.extend([0xff, 0xe1, 0, (exif.len() + 2) as u8]);
            bytes.extend(exif);
            bytes.extend(&jpeg[2..]);
            let region = centered_region(width, height);
            let capture = session.process_capture_with_region(&bytes, None, Some(region))?;
            assert_eq!(
                (capture.source_width, capture.source_height),
                (width, height)
            );
            assert!((capture.output_width as i32 - width as i32 / 2).abs() <= 2);
            assert!((capture.output_height as i32 - height as i32 / 2).abs() <= 2);
            let expected = session.reprocess(
                &bytes,
                &ReprocessOptions {
                    quad: capture.quad.expect("oriented page must be cropped"),
                    rotation_degrees: 0,
                    color_mode: capture.color_mode,
                    max_pixels: None,
                },
            )?;
            assert_eq!(capture, expected);
        }
        Ok(())
    }

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
