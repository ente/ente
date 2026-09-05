use std::time::Instant;

use ente_assets::download::CancellationToken;
use ente_assets::{Asset, AssetFile, AssetStore};

use super::OcrModelPaths;
use crate::error::{MlError, MlResult};

const MODEL_BASE_URL: &str = "https://models.ente.com/PP-OCRv5";
const MODELS: &str = "models";

struct OcrModelFile {
    key: &'static str,
    name: &'static str,
    size: u64,
    sha256: &'static str,
}

const DETECTION: OcrModelFile = OcrModelFile {
    key: "ppocrv5_det",
    name: "det.onnx",
    size: 4_748_769,
    sha256: "d7fe3ea74652890722c0f4d02458b7261d9f5ae6c92904d05707c9eb155c7924",
};

const CLASSIFICATION: OcrModelFile = OcrModelFile {
    key: "ppocrv5_cls",
    name: "cls.onnx",
    size: 582_663,
    sha256: "f4bb53707100c5f3d59ba834eb05bb400369f20aed35d4b26807b1bfadd2a70e",
};

const RECOGNITION: OcrModelFile = OcrModelFile {
    key: "ppocrv5_rec",
    name: "rec.onnx",
    size: 16_517_247,
    sha256: "bf66820f48fa99f779974c4df78e5274a9d8e0458c4137e8c5357e40e2c3faf2",
};

const DICTIONARY: OcrModelFile = OcrModelFile {
    key: "ppocrv5_dict",
    name: "ppocrv5_dict.txt",
    size: 74_012,
    sha256: "d1979e9f794c464c0d2e0b70a7fe14dd978e9dc644c0e71f14158cdf8342af1b",
};

const CATALOG: [&OcrModelFile; 4] = [&DETECTION, &CLASSIFICATION, &RECOGNITION, &DICTIONARY];

impl OcrModelFile {
    fn url(&self) -> String {
        format!("{MODEL_BASE_URL}/{}", self.name)
    }

    fn asset(&self) -> Asset {
        Asset::file(
            vec![MODELS.to_string(), self.key.to_string()],
            AssetFile {
                name: self.name.to_string(),
                url: self.url(),
                size: self.size,
                sha256: self.sha256.to_string(),
            },
        )
        .expect("valid OCR model catalog")
    }

    fn path(&self, store: &AssetStore) -> String {
        store
            .file_path(&self.asset(), self.name)
            .expect("OCR model file")
            .to_string_lossy()
            .into_owned()
    }
}

pub fn model_assets() -> Vec<Asset> {
    CATALOG.iter().map(|file| file.asset()).collect()
}

pub async fn ensure_models(store: &AssetStore) -> MlResult<OcrModelPaths> {
    let missing: Vec<(&OcrModelFile, Asset)> = CATALOG
        .iter()
        .map(|file| (*file, file.asset()))
        .filter(|(_, asset)| !store.is_downloaded(asset))
        .collect();
    if missing.is_empty() {
        log::info!("ocr models: using cached copies");
    } else {
        for (file, _) in &missing {
            log::info!(
                "ocr models: downloading {} ({} bytes) from {}",
                file.name,
                file.size,
                file.url()
            );
        }
        let start = Instant::now();
        let assets: Vec<Asset> = missing.iter().map(|(_, asset)| asset.clone()).collect();
        store
            .download(&assets, |_| {}, CancellationToken::default())
            .await
            .map_err(|error| MlError::Runtime(format!("ocr model download failed: {error}")))?;
        log::info!(
            "ocr models: downloaded {} file(s) in {}ms",
            assets.len(),
            start.elapsed().as_millis()
        );
    }
    Ok(OcrModelPaths {
        detection: DETECTION.path(store),
        classification: CLASSIFICATION.path(store),
        recognition: RECOGNITION.path(store),
        dictionary: DICTIONARY.path(store),
    })
}

#[cfg(test)]
mod tests {
    use std::path::Path;

    use super::*;

    #[test]
    fn catalog_directories_do_not_collide_with_the_indexing_catalog() {
        let store = AssetStore::new(Path::new("cache"));
        let clip_text = crate::assets::clip_text_asset();
        let others: Vec<_> = crate::assets::indexing_assets(true, true, true)
            .iter()
            .chain(std::iter::once(&clip_text))
            .map(|asset| store.asset_dir(asset))
            .collect();
        assert!(!others.is_empty());
        for asset in model_assets() {
            let dir = store.asset_dir(&asset);
            for other in &others {
                assert_ne!(&dir, other);
                assert!(!dir.starts_with(other), "{}", dir.display());
                assert!(!other.starts_with(&dir), "{}", other.display());
            }
        }
    }
}
