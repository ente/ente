use std::any::Any;
use std::panic::{AssertUnwindSafe, catch_unwind};

use ente_assets::AssetStore;
use ente_ml::indexing::set_ml_execution_config;
use ente_ml::scan;
use flutter_rust_bridge::frb;

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
pub struct RustPlaneLayout {
    pub width: i32,
    pub height: i32,
    pub y_row_stride: i32,
    pub uv_row_stride: i32,
    pub uv_pixel_stride: i32,
}

#[derive(Clone, Debug)]
pub struct RustReprocessOptions {
    /// Same space as `RustScanResult.quad`: the decoded source image.
    pub quad: RustQuad,
    /// Must be a multiple of 90.
    pub rotation_degrees: i32,
    pub color_mode: RustColorMode,
    pub max_pixels: Option<u32>,
}

#[derive(Clone, Debug)]
pub struct RustScanResult {
    /// Decoded-source coordinates (EXIF applied, before `rotation_degrees`); `None` when nothing was detected.
    pub quad: Option<RustQuad>,
    pub color_mode: RustColorMode,
    pub output_width: u32,
    pub output_height: u32,
    /// The size `quad` is relative to.
    pub source_width: u32,
    pub source_height: u32,
    /// JPEG-encoded.
    pub processed_image: Vec<u8>,
}

#[derive(Clone, Debug)]
pub enum RustScanError {
    Other { message: String },
}

#[frb(opaque)]
pub struct ScannerSession {
    inner: scan::ScannerSession,
}

impl ScannerSession {
    pub async fn create(assets_dir: String) -> Result<ScannerSession, RustScanError> {
        let store = AssetStore::new(assets_dir);
        let model_path = scan::ensure_segmentation_model(&store).await?;
        catch_panic(|| {
            set_ml_execution_config(true);
            let inner = scan::ScannerSession::new(&model_path.to_string_lossy())?;
            Ok(ScannerSession { inner })
        })
    }

    /// The returned quad is in mask space (256x256), already rotated by `rotation_degrees`.
    pub fn live_detect_bgra(
        &self,
        bgra: Vec<u8>,
        row_stride: i32,
        width: u32,
        height: u32,
        rotation_degrees: i32,
    ) -> Result<Option<RustQuad>, RustScanError> {
        catch_panic(|| {
            let row_stride = u32::try_from(row_stride).map_err(|_| RustScanError::Other {
                message: format!("negative row stride {row_stride}"),
            })?;
            let quad =
                self.inner
                    .live_detect_bgra(&bgra, row_stride, width, height, rotation_degrees)?;
            Ok(quad.map(to_api_quad))
        })
    }

    /// Quad semantics as in [`Self::live_detect_bgra`].
    pub fn live_detect_yuv420(
        &self,
        y: Vec<u8>,
        u: Vec<u8>,
        v: Vec<u8>,
        layout: RustPlaneLayout,
        rotation_degrees: i32,
    ) -> Result<Option<RustQuad>, RustScanError> {
        catch_panic(|| {
            let quad = self.inner.live_detect_yuv420(
                &y,
                &u,
                &v,
                to_plane_layout(layout),
                rotation_degrees,
            )?;
            Ok(quad.map(to_api_quad))
        })
    }

    pub fn process_capture(
        &self,
        image_bytes: Vec<u8>,
        max_pixels: Option<u32>,
    ) -> Result<RustScanResult, RustScanError> {
        catch_panic(|| {
            let result = self.inner.process_capture(&image_bytes, max_pixels)?;
            Ok(to_api_scan_result(result))
        })
    }

    pub fn reprocess(
        &self,
        source_bytes: Vec<u8>,
        options: RustReprocessOptions,
    ) -> Result<RustScanResult, RustScanError> {
        catch_panic(|| {
            let result = self
                .inner
                .reprocess(&source_bytes, &to_reprocess_options(&options))?;
            Ok(to_api_scan_result(result))
        })
    }
}

fn catch_panic<T>(body: impl FnOnce() -> Result<T, RustScanError>) -> Result<T, RustScanError> {
    catch_unwind(AssertUnwindSafe(body)).unwrap_or_else(|panic| {
        Err(RustScanError::Other {
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

impl From<scan::ScanError> for RustScanError {
    fn from(value: scan::ScanError) -> Self {
        Self::Other {
            message: value.to_string(),
        }
    }
}

fn to_plane_layout(layout: RustPlaneLayout) -> scan::PlaneLayout {
    scan::PlaneLayout {
        width: layout.width,
        height: layout.height,
        y_row_stride: layout.y_row_stride,
        uv_row_stride: layout.uv_row_stride,
        uv_pixel_stride: layout.uv_pixel_stride,
    }
}

fn to_reprocess_options(options: &RustReprocessOptions) -> scan::ReprocessOptions {
    scan::ReprocessOptions {
        quad: to_quad(options.quad),
        rotation_degrees: options.rotation_degrees,
        color_mode: to_color_mode(options.color_mode),
        max_pixels: options.max_pixels,
    }
}

fn to_color_mode(mode: RustColorMode) -> scan::ColorMode {
    match mode {
        RustColorMode::Color => scan::ColorMode::Color,
        RustColorMode::Grayscale => scan::ColorMode::Grayscale,
    }
}

fn to_api_color_mode(mode: scan::ColorMode) -> RustColorMode {
    match mode {
        scan::ColorMode::Color => RustColorMode::Color,
        scan::ColorMode::Grayscale => RustColorMode::Grayscale,
    }
}

fn to_quad(quad: RustQuad) -> scan::Quad {
    scan::Quad {
        top_left: to_point(quad.top_left),
        top_right: to_point(quad.top_right),
        bottom_right: to_point(quad.bottom_right),
        bottom_left: to_point(quad.bottom_left),
    }
}

fn to_point(point: RustPoint) -> scan::Point {
    scan::Point {
        x: point.x,
        y: point.y,
    }
}

fn to_api_quad(quad: scan::Quad) -> RustQuad {
    RustQuad {
        top_left: to_api_point(quad.top_left),
        top_right: to_api_point(quad.top_right),
        bottom_right: to_api_point(quad.bottom_right),
        bottom_left: to_api_point(quad.bottom_left),
    }
}

fn to_api_point(point: scan::Point) -> RustPoint {
    RustPoint {
        x: point.x,
        y: point.y,
    }
}

fn to_api_scan_result(result: scan::ScanResult) -> RustScanResult {
    RustScanResult {
        quad: result.quad.map(to_api_quad),
        color_mode: to_api_color_mode(result.color_mode),
        output_width: result.output_width,
        output_height: result.output_height,
        source_width: result.source_width,
        source_height: result.source_height,
        processed_image: result.processed_image,
    }
}
