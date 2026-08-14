use std::any::Any;
use std::panic::{AssertUnwindSafe, catch_unwind};

use ente_assets::AssetStore;
use ente_photos::ml::document_scan;
use flutter_rust_bridge::frb;

#[frb(sync)]
pub fn mask_side() -> i32 {
    document_scan::MASK_SIDE
}

#[derive(Clone, Copy, Debug)]
pub struct RustPoint {
    pub x: f64,
    pub y: f64,
}

#[derive(Clone, Copy, Debug)]
pub struct RustQuad {
    pub top_left: RustPoint,
    pub top_right: RustPoint,
    pub bottom_right: RustPoint,
    pub bottom_left: RustPoint,
}

#[derive(Clone, Copy, Debug)]
pub enum RustColorMode {
    Color,
    Grayscale,
}

#[derive(Clone, Copy, Debug)]
pub enum RustOutputFormat {
    Png,
    Jpeg,
}

#[derive(Clone, Copy, Debug)]
pub struct RustDimensionsMm {
    pub width_mm: f64,
    pub height_mm: f64,
}

#[derive(Clone, Copy, Debug)]
pub struct RustCameraIntrinsics {
    pub focal_length_mm: f32,
    pub sensor_width_mm: f32,
}

#[derive(Clone, Copy, Debug)]
pub struct RustOpticalMeasures {
    pub camera_intrinsics: RustCameraIntrinsics,
    /// Millimetres; `None` when the capture carries no calibrated distance.
    pub subject_distance_mm: Option<f32>,
}

/// Geometry of a YUV_420_888 frame as the platform camera API reports it.
#[derive(Clone, Copy, Debug)]
pub struct RustPlaneLayout {
    pub width: i32,
    pub height: i32,
    pub y_row_stride: i32,
    pub uv_row_stride: i32,
    pub uv_pixel_stride: i32,
}

#[derive(Clone, Debug)]
pub struct RustScanOptions {
    /// `None` means "let the pipeline decide".
    pub color_mode_override: Option<RustColorMode>,
    /// `None` means the default budget of 2 000 000 pixels.
    pub max_pixels: Option<u32>,
    /// Applied to the extracted page as the last step. Must be a multiple of
    /// 90.
    pub rotation_degrees: i32,
    pub output_format: RustOutputFormat,
    /// `None` reproduces a capture with no camera metadata (e.g. a gallery
    /// import).
    pub optical_measures: Option<RustOpticalMeasures>,
}

#[derive(Clone, Debug)]
pub struct RustReprocessOptions {
    /// In the coordinate space of the decoded source image — the same space
    /// `RustScanResult.quad` is reported in.
    pub quad: RustQuad,
    /// Must be a multiple of 90.
    pub rotation_degrees: i32,
    pub color_mode: RustColorMode,
    pub optical_measures: Option<RustOpticalMeasures>,
    /// `None` means the default budget of 2 000 000 pixels.
    pub max_pixels: Option<u32>,
    /// `None` means the default quality of 75. Reprocess output is always
    /// JPEG.
    pub jpeg_quality: Option<u8>,
}

#[derive(Clone, Debug)]
pub struct RustScanResult {
    /// Corners in the coordinate space of the decoded source image (after
    /// EXIF orientation, before `rotation_degrees`). `None` when nothing was
    /// detected, in which case the whole frame is returned instead.
    pub quad: Option<RustQuad>,
    pub color_mode: RustColorMode,
    pub output_width: u32,
    pub output_height: u32,
    /// Size of the decoded source image — the coordinate space `quad` lives
    /// in.
    pub source_width: u32,
    pub source_height: u32,
    /// `Some` only when optical measures with a subject distance let the
    /// estimate resolve to a physical size.
    pub estimated_dims_mm: Option<RustDimensionsMm>,
    pub processed_image: Vec<u8>,
    pub processed_format: RustOutputFormat,
}

#[derive(Clone, Copy, Debug)]
pub enum RustScanErrorKind {
    InvalidInput,
    ModelLoad,
    Codec,
    Pipeline,
    /// A panic inside the scanner, caught at the FFI boundary.
    Internal,
}

#[derive(Clone, Debug)]
pub struct RustScanError {
    pub kind: RustScanErrorKind,
    pub message: String,
}

/// A loaded segmentation model plus the pipeline built around it. `Send +
/// Sync`; all methods take `&self`, so one session serves both the live
/// preview stream and capture processing.
#[frb(opaque)]
pub struct ScannerSession {
    inner: document_scan::ScannerSession,
}

impl ScannerSession {
    /// Ensures a verified segmentation model in the asset store rooted at
    /// `assets_dir` (downloading it on first use) and loads it.
    pub async fn create(assets_dir: String) -> Result<ScannerSession, RustScanError> {
        let store = AssetStore::new(assets_dir);
        let model_path = document_scan::ensure_segmentation_model(&store)
            .await
            .map_err(|error| RustScanError {
                kind: RustScanErrorKind::ModelLoad,
                message: error.to_string(),
            })?;
        catch_panic(|| {
            let inner = document_scan::ScannerSession::new(&model_path.to_string_lossy())?;
            Ok(ScannerSession { inner })
        })
    }

    /// Live document detection on a tightly packed RGBA preview frame
    /// (`width * height * 4` bytes).
    ///
    /// The returned quad is in mask space ([`mask_side`] squared), already
    /// rotated by `rotation_degrees`: rotate the overlay quad, not the frame.
    pub fn live_detect_rgba(
        &self,
        rgba: Vec<u8>,
        width: u32,
        height: u32,
        rotation_degrees: i32,
    ) -> Result<Option<RustQuad>, RustScanError> {
        catch_panic(AssertUnwindSafe(|| {
            let quad = self
                .inner
                .live_detect_rgba(&rgba, width, height, rotation_degrees)?;
            Ok(quad.map(to_api_quad))
        }))
    }

    /// Live document detection on an iOS BGRA8888 preview frame with
    /// `row_stride` bytes per row. The frame is repacked to RGBA here; Dart
    /// passes the camera buffer through unchanged.
    ///
    /// Quad semantics as in [`Self::live_detect_rgba`].
    pub fn live_detect_bgra(
        &self,
        bgra: Vec<u8>,
        row_stride: i32,
        width: u32,
        height: u32,
        rotation_degrees: i32,
    ) -> Result<Option<RustQuad>, RustScanError> {
        catch_panic(AssertUnwindSafe(|| {
            let rgba = bgra_to_rgba(&bgra, row_stride, width, height)?;
            let quad = self
                .inner
                .live_detect_rgba(&rgba, width, height, rotation_degrees)?;
            Ok(quad.map(to_api_quad))
        }))
    }

    /// Live document detection on YUV_420_888 camera planes. Both planar I420
    /// (`uv_pixel_stride == 1`) and interleaved NV21/NV12
    /// (`uv_pixel_stride == 2`) layouts are accepted.
    ///
    /// Quad semantics as in [`Self::live_detect_rgba`].
    pub fn live_detect_yuv420(
        &self,
        y: Vec<u8>,
        u: Vec<u8>,
        v: Vec<u8>,
        layout: RustPlaneLayout,
        rotation_degrees: i32,
    ) -> Result<Option<RustQuad>, RustScanError> {
        catch_panic(AssertUnwindSafe(|| {
            let quad = self.inner.live_detect_yuv420(
                &y,
                &u,
                &v,
                to_plane_layout(layout),
                rotation_degrees,
            )?;
            Ok(quad.map(to_api_quad))
        }))
    }

    /// The full capture pipeline on a captured or imported still: decode
    /// (EXIF applied), segment, detect the quad, pick the color mode,
    /// extract, enhance, encode.
    pub fn process_capture(
        &self,
        image_bytes: Vec<u8>,
        options: RustScanOptions,
    ) -> Result<RustScanResult, RustScanError> {
        catch_panic(AssertUnwindSafe(|| {
            let result = self
                .inner
                .process_capture(&image_bytes, &to_scan_options(&options))?;
            Ok(to_api_scan_result(result))
        }))
    }

    /// Re-renders a page from its source bytes with a known quad and color
    /// mode — the manual corner-adjustment and export path. Runs no
    /// inference; the output is always JPEG.
    pub fn reprocess(
        &self,
        source_bytes: Vec<u8>,
        options: RustReprocessOptions,
    ) -> Result<RustScanResult, RustScanError> {
        catch_panic(AssertUnwindSafe(|| {
            let result = self
                .inner
                .reprocess(&source_bytes, &to_reprocess_options(&options))?;
            Ok(to_api_scan_result(result))
        }))
    }
}

fn catch_panic<T>(body: impl FnOnce() -> Result<T, RustScanError>) -> Result<T, RustScanError> {
    catch_unwind(AssertUnwindSafe(body)).unwrap_or_else(|panic| {
        Err(RustScanError {
            kind: RustScanErrorKind::Internal,
            message: panic_message(&panic),
        })
    })
}

fn panic_message(panic: &Box<dyn Any + Send>) -> String {
    if let Some(message) = panic.downcast_ref::<&str>() {
        (*message).to_string()
    } else if let Some(message) = panic.downcast_ref::<String>() {
        message.clone()
    } else {
        "unknown panic".to_string()
    }
}

fn bgra_to_rgba(
    bgra: &[u8],
    row_stride: i32,
    width: u32,
    height: u32,
) -> Result<Vec<u8>, RustScanError> {
    let invalid = |message: String| RustScanError {
        kind: RustScanErrorKind::InvalidInput,
        message,
    };
    if width == 0 || height == 0 {
        return Err(invalid(format!("empty frame: {width}x{height}")));
    }
    let width = width as usize;
    let height = height as usize;
    let row_stride = usize::try_from(row_stride)
        .map_err(|_| invalid(format!("negative row stride {row_stride}")))?;
    let row_bytes = width
        .checked_mul(4)
        .ok_or_else(|| invalid(format!("width {width} overflows")))?;
    if row_stride < row_bytes {
        return Err(invalid(format!(
            "row stride {row_stride} is less than {row_bytes} bytes per row"
        )));
    }
    let required = (height - 1)
        .checked_mul(row_stride)
        .and_then(|bulk| bulk.checked_add(row_bytes))
        .ok_or_else(|| invalid(format!("frame {width}x{height} overflows")))?;
    if bgra.len() < required {
        return Err(invalid(format!(
            "buffer holds {} bytes, {required} required",
            bgra.len()
        )));
    }

    let mut rgba = vec![0u8; height * row_bytes];
    for (row_index, rgba_row) in rgba.chunks_exact_mut(row_bytes).enumerate() {
        let bgra_row = &bgra[row_index * row_stride..row_index * row_stride + row_bytes];
        for (rgba_px, bgra_px) in rgba_row.chunks_exact_mut(4).zip(bgra_row.chunks_exact(4)) {
            rgba_px[0] = bgra_px[2];
            rgba_px[1] = bgra_px[1];
            rgba_px[2] = bgra_px[0];
            rgba_px[3] = bgra_px[3];
        }
    }
    Ok(rgba)
}

impl From<document_scan::ScanError> for RustScanError {
    fn from(value: document_scan::ScanError) -> Self {
        let (kind, message) = match value {
            document_scan::ScanError::InvalidInput(message) => {
                (RustScanErrorKind::InvalidInput, message)
            }
            document_scan::ScanError::ModelLoad(message) => (RustScanErrorKind::ModelLoad, message),
            document_scan::ScanError::Codec(message) => (RustScanErrorKind::Codec, message),
            document_scan::ScanError::Pipeline(message) => (RustScanErrorKind::Pipeline, message),
        };
        RustScanError { kind, message }
    }
}

fn to_plane_layout(layout: RustPlaneLayout) -> document_scan::PlaneLayout {
    document_scan::PlaneLayout {
        width: layout.width,
        height: layout.height,
        y_row_stride: layout.y_row_stride,
        uv_row_stride: layout.uv_row_stride,
        uv_pixel_stride: layout.uv_pixel_stride,
    }
}

fn to_scan_options(options: &RustScanOptions) -> document_scan::ScanOptions {
    document_scan::ScanOptions {
        color_mode_override: options.color_mode_override.map(to_color_mode),
        max_pixels: options.max_pixels,
        rotation_degrees: options.rotation_degrees,
        output_format: to_output_format(options.output_format),
        optical_measures: options.optical_measures.map(to_optical_measures),
    }
}

fn to_reprocess_options(options: &RustReprocessOptions) -> document_scan::ReprocessOptions {
    document_scan::ReprocessOptions {
        quad: to_quad(options.quad),
        rotation_degrees: options.rotation_degrees,
        color_mode: to_color_mode(options.color_mode),
        optical_measures: options.optical_measures.map(to_optical_measures),
        max_pixels: options.max_pixels,
        jpeg_quality: options.jpeg_quality,
    }
}

fn to_color_mode(mode: RustColorMode) -> document_scan::ColorMode {
    match mode {
        RustColorMode::Color => document_scan::ColorMode::Color,
        RustColorMode::Grayscale => document_scan::ColorMode::Grayscale,
    }
}

fn to_api_color_mode(mode: document_scan::ColorMode) -> RustColorMode {
    match mode {
        document_scan::ColorMode::Color => RustColorMode::Color,
        document_scan::ColorMode::Grayscale => RustColorMode::Grayscale,
    }
}

fn to_output_format(format: RustOutputFormat) -> document_scan::OutputFormat {
    match format {
        RustOutputFormat::Png => document_scan::OutputFormat::Png,
        RustOutputFormat::Jpeg => document_scan::OutputFormat::Jpeg,
    }
}

fn to_api_output_format(format: document_scan::OutputFormat) -> RustOutputFormat {
    match format {
        document_scan::OutputFormat::Png => RustOutputFormat::Png,
        document_scan::OutputFormat::Jpeg => RustOutputFormat::Jpeg,
    }
}

fn to_optical_measures(measures: RustOpticalMeasures) -> document_scan::OpticalMeasures {
    document_scan::OpticalMeasures {
        camera_intrinsics: document_scan::CameraIntrinsics {
            focal_length_mm: measures.camera_intrinsics.focal_length_mm,
            sensor_width_mm: measures.camera_intrinsics.sensor_width_mm,
        },
        subject_distance_mm: measures.subject_distance_mm,
    }
}

fn to_quad(quad: RustQuad) -> document_scan::Quad {
    document_scan::Quad {
        top_left: to_point(quad.top_left),
        top_right: to_point(quad.top_right),
        bottom_right: to_point(quad.bottom_right),
        bottom_left: to_point(quad.bottom_left),
    }
}

fn to_point(point: RustPoint) -> document_scan::Point {
    document_scan::Point {
        x: point.x,
        y: point.y,
    }
}

fn to_api_quad(quad: document_scan::Quad) -> RustQuad {
    RustQuad {
        top_left: to_api_point(quad.top_left),
        top_right: to_api_point(quad.top_right),
        bottom_right: to_api_point(quad.bottom_right),
        bottom_left: to_api_point(quad.bottom_left),
    }
}

fn to_api_point(point: document_scan::Point) -> RustPoint {
    RustPoint {
        x: point.x,
        y: point.y,
    }
}

fn to_api_scan_result(result: document_scan::ScanResult) -> RustScanResult {
    RustScanResult {
        quad: result.quad.map(to_api_quad),
        color_mode: to_api_color_mode(result.color_mode),
        output_width: result.output_width,
        output_height: result.output_height,
        source_width: result.source_width,
        source_height: result.source_height,
        estimated_dims_mm: result.estimated_dims_mm.map(|dims| RustDimensionsMm {
            width_mm: dims.width_mm,
            height_mm: dims.height_mm,
        }),
        processed_image: result.processed_image,
        processed_format: to_api_output_format(result.processed_format),
    }
}
