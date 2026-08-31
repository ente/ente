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
pub use scanner::{ReprocessOptions, ScanError, ScanResult, ScannerSession};
pub use segmentation::MASK_SIDE;
pub use yuv::PlaneLayout;

use std::path::PathBuf;

use ente_assets::download::CancellationToken;
use ente_assets::{Asset, AssetFile, AssetStore};

pub const SEGMENTATION_MODEL_SHA256: &str =
    "5ddcb87c70cb7674189e6fc148e84a490ca65b282276534210255a777d48a808";

const SEGMENTATION_MODEL_URL: &str = "https://models.ente.com/document_segmentation_opt.onnx";
const SEGMENTATION_MODEL_FILE: &str = "document_segmentation_opt.onnx";

fn segmentation_model_asset() -> Result<Asset, ScanError> {
    Asset::file(
        vec!["models".to_string(), "document_segmentation".to_string()],
        AssetFile {
            name: SEGMENTATION_MODEL_FILE.to_string(),
            url: SEGMENTATION_MODEL_URL.to_string(),
            sha256: SEGMENTATION_MODEL_SHA256.to_string(),
        },
    )
    .map_err(|error| ScanError::ModelLoad(error.to_string()))
}

pub async fn ensure_segmentation_model(store: &AssetStore) -> Result<PathBuf, ScanError> {
    let asset = segmentation_model_asset()?;
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
            .await
            .map_err(|error| ScanError::ModelLoad(error.to_string()))?;
        log::info!(
            "segmentation model: downloaded in {}ms",
            start.elapsed().as_millis()
        );
    }
    store
        .file_path(&asset, SEGMENTATION_MODEL_FILE)
        .ok_or_else(|| ScanError::ModelLoad(format!("asset declares no {SEGMENTATION_MODEL_FILE}")))
}

pub(crate) use crate::cv::OpResult;
