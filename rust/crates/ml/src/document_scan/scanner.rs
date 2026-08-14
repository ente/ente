//! The public document-scanning API.
//!
//! Everything a call needs hangs off the [`ScannerSession`] handle; there is
//! no global mutable state. All methods take `&self` and the session is
//! `Send + Sync`, so a bridge can share one handle across threads. Errors are
//! the closed [`ScanError`] enum; panics are not caught here (an FFI bridge
//! wanting panic isolation wraps these calls itself).

use thiserror::Error;

use super::codec;
use super::color::{ColorMode, auto_color_mode, quad_to_image};
use super::detection::{detect_document_quad, extract_document, resize_for_max_pixels};
use super::geometry::{ImageSize, Quad};
use super::image::ImageU8;
use super::mask::Mask;
use super::ops;
use super::perspective::{EstimatedDimensions, OpticalMeasures, estimate_real_dimensions};
use super::segmentation::{MASK_SIDE, Segmenter};
use super::yuv::{PlaneLayout, rgba_to_bgr, yuv420_to_bgr};

/// Default pixel budget of the processed page.
const DEFAULT_MAX_PIXELS: u32 = 2_000_000;
/// Default JPEG quality of the processed page.
const DEFAULT_JPEG_QUALITY: u8 = 75;

/// Everything that can go wrong, as a closed set a caller can switch on.
#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub enum ScanError {
    /// A caller-supplied buffer, size or parameter is not usable.
    #[error("invalid input: {0}")]
    InvalidInput(String),
    /// The ONNX model could not be loaded.
    #[error("model load: {0}")]
    ModelLoad(String),
    /// The image bytes could not be decoded, or the result not encoded.
    #[error("codec: {0}")]
    Codec(String),
    /// Inference or an image operation failed.
    #[error("pipeline: {0}")]
    Pipeline(String),
}

/// Container the processed image is returned in. `Jpeg` is what the app
/// stores; `Png` is lossless.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OutputFormat {
    Png,
    Jpeg,
}

/// Physical page size, in millimetres.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct DimensionsMm {
    pub width_mm: f64,
    pub height_mm: f64,
}

/// Options for [`ScannerSession::process_capture`].
#[derive(Debug, Clone, PartialEq)]
pub struct ScanOptions {
    /// `None` means "let the pipeline decide".
    pub color_mode_override: Option<ColorMode>,
    /// `None` means the default budget of 2 000 000 pixels.
    pub max_pixels: Option<u32>,
    /// Applied to the extracted page as the last step. Must be a multiple of
    /// 90.
    pub rotation_degrees: i32,
    pub output_format: OutputFormat,
    /// `None` reproduces a capture with no camera metadata (e.g. a gallery
    /// import). With a subject distance present, the result carries a
    /// physical page size estimate.
    pub optical_measures: Option<OpticalMeasures>,
}

impl Default for ScanOptions {
    fn default() -> Self {
        Self {
            color_mode_override: None,
            max_pixels: None,
            rotation_degrees: 0,
            output_format: OutputFormat::Jpeg,
            optical_measures: None,
        }
    }
}

/// Options for [`ScannerSession::reprocess`]. The caller already knows the
/// quad and the color mode; no inference happens on this path.
#[derive(Debug, Clone, PartialEq)]
pub struct ReprocessOptions {
    /// In the coordinate space of the decoded source image — the same space
    /// [`ScanResult::quad`] is reported in.
    pub quad: Quad,
    /// Must be a multiple of 90.
    pub rotation_degrees: i32,
    pub color_mode: ColorMode,
    pub optical_measures: Option<OpticalMeasures>,
    /// `None` means the default budget of 2 000 000 pixels.
    pub max_pixels: Option<u32>,
    /// `None` means the default quality of 75. Reprocess output is always
    /// JPEG.
    pub jpeg_quality: Option<u8>,
}

/// The processed page and everything the caller needs to reason about it.
#[derive(Debug, Clone, PartialEq)]
pub struct ScanResult {
    /// Corners in the coordinate space of the decoded source image (after
    /// EXIF orientation, before `rotation_degrees`). `None` when nothing was
    /// detected, in which case the whole frame is returned instead.
    pub quad: Option<Quad>,
    pub color_mode: ColorMode,
    pub output_width: u32,
    pub output_height: u32,
    /// Size of the decoded source image, after EXIF orientation and before
    /// `rotation_degrees` — the coordinate space [`ScanResult::quad`] lives
    /// in.
    pub source_width: u32,
    pub source_height: u32,
    /// `Some` only when the estimate resolves to a physical size, which
    /// requires optical measures including a subject distance. Already
    /// snapped to a standard paper format and still in the unrotated source
    /// frame, so a caller applying a 90/270 degree rotation must swap the two
    /// values.
    pub estimated_dims_mm: Option<DimensionsMm>,
    pub processed_image: Vec<u8>,
    pub processed_format: OutputFormat,
}

/// A loaded segmentation model plus the pipeline built around it.
pub struct ScannerSession {
    segmenter: Segmenter,
}

impl ScannerSession {
    /// Loads the segmentation model from `model_path`. The caller is expected
    /// to have verified the file against
    /// [`SEGMENTATION_MODEL_SHA256`](super::SEGMENTATION_MODEL_SHA256).
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

    fn segment(&self, bgr: &ImageU8) -> Result<Mask, ScanError> {
        let probmap = self
            .segmenter
            .probability_map_u8(bgr)
            .map_err(ScanError::Pipeline)?;
        Ok(Mask::from_probmap(&probmap, MASK_SIDE, MASK_SIDE))
    }

    /// Live document detection on a tightly packed RGBA preview frame
    /// (`width * height * 4` bytes).
    ///
    /// The returned quad is in **mask space** (256x256), already rotated by
    /// `rotation_degrees`: the caller rotates the overlay quad, not the
    /// frame, and the mask is square so the rotation stays inside it.
    pub fn live_detect_rgba(
        &self,
        rgba: &[u8],
        width: u32,
        height: u32,
        rotation_degrees: i32,
    ) -> Result<Option<Quad>, ScanError> {
        let bgr =
            rgba_to_bgr(rgba, to_i32(width)?, to_i32(height)?).map_err(ScanError::InvalidInput)?;
        self.live_detect(&bgr, rotation_degrees)
    }

    /// Live document detection on YUV_420_888 camera planes. Both planar I420
    /// (`uv_pixel_stride == 1`) and interleaved NV21/NV12
    /// (`uv_pixel_stride == 2`, where `u` and `v` are two views into one
    /// buffer) layouts are accepted.
    ///
    /// Quad semantics as in [`Self::live_detect_rgba`].
    pub fn live_detect_yuv420(
        &self,
        y: &[u8],
        u: &[u8],
        v: &[u8],
        layout: PlaneLayout,
        rotation_degrees: i32,
    ) -> Result<Option<Quad>, ScanError> {
        let bgr = yuv420_to_bgr(y, u, v, layout).map_err(ScanError::InvalidInput)?;
        self.live_detect(&bgr, rotation_degrees)
    }

    fn live_detect(&self, bgr: &ImageU8, rotation_degrees: i32) -> Result<Option<Quad>, ScanError> {
        let mask = self.segment(bgr)?;
        let original_size = ImageSize::new(bgr.width as f64, bgr.height as f64);
        let quad_in_mask =
            detect_document_quad(&mask, original_size, true).map_err(ScanError::Pipeline)?;
        let mask_size = ImageSize::new(mask.width as f64, mask.height as f64);
        Ok(quad_in_mask.map(|q| q.rotate90(rotation_degrees / 90, mask_size)))
    }

    /// The full capture pipeline on a captured or imported still: decode
    /// (EXIF applied), segment, detect the quad, pick the color mode,
    /// extract, enhance, encode.
    pub fn process_capture(
        &self,
        image_bytes: &[u8],
        options: &ScanOptions,
    ) -> Result<ScanResult, ScanError> {
        let start = std::time::Instant::now();
        let result = self.process_capture_inner(image_bytes, options);
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
        options: &ScanOptions,
    ) -> Result<ScanResult, ScanError> {
        let bgr = codec::decode_bgr(image_bytes)?;
        let max_pixels = options.max_pixels.unwrap_or(DEFAULT_MAX_PIXELS) as f64;

        let mask = self.segment(&bgr)?;
        let original_size = ImageSize::new(bgr.width as f64, bgr.height as f64);
        let quad_in_mask =
            detect_document_quad(&mask, original_size, false).map_err(ScanError::Pipeline)?;

        let Some(quad_in_mask) = quad_in_mask else {
            // Nothing detected: the whole frame is resized and rotated, and
            // the color mode keeps its Color initial value.
            let resized = resize_for_max_pixels(&bgr, max_pixels).map_err(ScanError::Pipeline)?;
            let page =
                ops::rotate_u8(&resized, options.rotation_degrees).map_err(ScanError::Pipeline)?;
            return finish(
                None,
                ColorMode::Color,
                None,
                &bgr,
                &page,
                options.output_format,
                DEFAULT_JPEG_QUALITY,
            );
        };

        let quad = quad_to_image(&quad_in_mask, &mask, bgr.size());
        let auto = auto_color_mode(&bgr, &mask, &quad).map_err(ScanError::Pipeline)?;
        let color_mode = options.color_mode_override.unwrap_or(auto);
        let page = extract_document(
            &bgr,
            &quad,
            options.rotation_degrees,
            color_mode,
            max_pixels,
            options.optical_measures,
        )
        .map_err(ScanError::Pipeline)?;

        finish(
            Some(quad),
            color_mode,
            physical_dims(&quad, &bgr, options.optical_measures),
            &bgr,
            &page,
            options.output_format,
            DEFAULT_JPEG_QUALITY,
        )
    }

    /// Re-renders a page from its source bytes with a known quad and color
    /// mode — the manual corner-adjustment and export path. Runs no
    /// inference; the output is always JPEG.
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
        let bgr = codec::decode_bgr(source_bytes)?;
        let page = extract_document(
            &bgr,
            &options.quad,
            options.rotation_degrees,
            options.color_mode,
            options.max_pixels.unwrap_or(DEFAULT_MAX_PIXELS) as f64,
            options.optical_measures,
        )
        .map_err(ScanError::Pipeline)?;

        finish(
            Some(options.quad),
            options.color_mode,
            physical_dims(&options.quad, &bgr, options.optical_measures),
            &bgr,
            &page,
            OutputFormat::Jpeg,
            options.jpeg_quality.unwrap_or(DEFAULT_JPEG_QUALITY),
        )
    }
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

/// Resolves to a physical size only when the optical measures carry a subject
/// distance.
fn physical_dims(
    quad: &Quad,
    source: &ImageU8,
    optical_measures: Option<OpticalMeasures>,
) -> Option<DimensionsMm> {
    match estimate_real_dimensions(quad, source.width, source.height, optical_measures)
        .snap_to_standard_format()
    {
        EstimatedDimensions::Physical {
            width_mm,
            height_mm,
        } => Some(DimensionsMm {
            width_mm,
            height_mm,
        }),
        EstimatedDimensions::Ratio { .. } => None,
    }
}

fn finish(
    quad: Option<Quad>,
    color_mode: ColorMode,
    estimated_dims_mm: Option<DimensionsMm>,
    source: &ImageU8,
    page: &ImageU8,
    format: OutputFormat,
    jpeg_quality: u8,
) -> Result<ScanResult, ScanError> {
    let processed_image = match format {
        OutputFormat::Png => codec::encode_png(page),
        OutputFormat::Jpeg => codec::encode_jpeg(page, jpeg_quality),
    }?;

    Ok(ScanResult {
        quad,
        color_mode,
        output_width: page.width as u32,
        output_height: page.height as u32,
        source_width: source.width as u32,
        source_height: source.height as u32,
        estimated_dims_mm,
        processed_image,
        processed_format: format,
    })
}
