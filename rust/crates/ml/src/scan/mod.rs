mod codec;
mod color;
mod contour_orientation;
mod detection;
mod geometry;
mod mask;
mod perspective;
mod postprocess;
mod quad_score;
mod scanner;
mod segmentation;
mod yuv;

pub use color::ColorMode;
pub use geometry::{Point, Quad};
pub use scanner::{ReprocessOptions, ScanError, ScanOptions, ScanResult, ScannerSession};
pub use segmentation::MASK_SIDE;
pub use yuv::PlaneLayout;

use std::path::PathBuf;

use ente_assets::download::CancellationToken;
use ente_assets::{Asset, AssetFile, AssetStore};

pub const SEGMENTATION_MODEL_SHA256: &str =
    "36b8eeadd42592af496bf2e125a6aad9bebcbca1bda2ac19fa22e108574217a3";

// Temporary dev hosting; will move to models.ente.com.
const SEGMENTATION_MODEL_URL: &str = "https://entedevassets.priem.dev/document_segmentation.onnx";
const SEGMENTATION_MODEL_FILE: &str = "document_segmentation.onnx";

fn segmentation_model_asset() -> Asset {
    Asset::file(
        vec!["models".to_string(), "document_segmentation".to_string()],
        AssetFile {
            name: SEGMENTATION_MODEL_FILE.to_string(),
            url: SEGMENTATION_MODEL_URL.to_string(),
            sha256: SEGMENTATION_MODEL_SHA256.to_string(),
        },
    )
    .expect("valid segmentation model asset")
}

pub async fn ensure_segmentation_model(
    store: &AssetStore,
) -> Result<PathBuf, ente_assets::download::Error> {
    let asset = segmentation_model_asset();
    if store.is_downloaded(&asset) {
        log::info!("segmentation model: using cached copy");
    } else {
        log::info!("segmentation model: downloading from {SEGMENTATION_MODEL_URL}");
        let start = std::time::Instant::now();
        store
            .download(
                std::slice::from_ref(&asset),
                |_| {},
                CancellationToken::default(),
            )
            .await?;
        log::info!(
            "segmentation model: downloaded in {}ms",
            start.elapsed().as_millis()
        );
    }
    Ok(store
        .file_path(&asset, SEGMENTATION_MODEL_FILE)
        .expect("segmentation model file"))
}

pub(crate) use crate::cv::OpResult;
