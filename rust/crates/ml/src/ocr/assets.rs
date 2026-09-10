use std::time::Instant;

use ente_assets::download::CancellationToken;
use ente_assets::{Asset, AssetFile, AssetStore};

use super::OcrModelPaths;
use crate::error::{MlError, MlResult};

const MODELS: &str = "models";

struct OcrModelFile {
    key: &'static str,
    name: &'static str,
    url: &'static str,
    size: u64,
    sha256: &'static str,
}

const DETECTION: OcrModelFile = OcrModelFile {
    key: "ppocrv5_det_gpu_v1",
    name: "det.onnx",
    url: "https://entedevassets.priem.dev/det_opt.onnx",
    size: 4_750_896,
    sha256: "3e658f85236f1984e186070048d7cdc99ddbb84e12c91a6fd80922b85bd9487a",
};

const CLASSIFICATION: OcrModelFile = OcrModelFile {
    key: "ppocrv5_cls_gpu_v1",
    name: "cls.onnx",
    url: "https://entedevassets.priem.dev/cls_opt.onnx",
    size: 574_875,
    sha256: "8675903197a1bab7060e830e9bcc63d29c5cf7d372735338bd9501f829e94ed1",
};

const RECOGNITION: OcrModelFile = OcrModelFile {
    key: "ppocrv5_rec_gpu_v1",
    name: "rec.onnx",
    url: "https://entedevassets.priem.dev/rec_opt.onnx",
    size: 16_686_404,
    sha256: "667691bb173a94106b595aa87c7d176b53b68cf831b6ffa09569018754265e57",
};

const DICTIONARY: OcrModelFile = OcrModelFile {
    key: "ppocrv5_dict",
    name: "ppocrv5_dict.txt",
    url: "https://models.ente.com/PP-OCRv5/ppocrv5_dict.txt",
    size: 74_012,
    sha256: "d1979e9f794c464c0d2e0b70a7fe14dd978e9dc644c0e71f14158cdf8342af1b",
};

const CATALOG: [&OcrModelFile; 4] = [&DETECTION, &CLASSIFICATION, &RECOGNITION, &DICTIONARY];

impl OcrModelFile {
    fn asset(&self) -> Asset {
        #[expect(
            clippy::expect_used,
            reason = "The built-in OCR catalog has valid asset keys and checksums"
        )]
        Asset::file(
            vec![MODELS.to_string(), self.key.to_string()],
            AssetFile {
                name: self.name.to_string(),
                url: self.url.to_string(),
                size: self.size,
                sha256: self.sha256.to_string(),
            },
        )
        .expect("valid OCR model catalog")
    }

    fn path(&self, store: &AssetStore) -> String {
        #[expect(
            clippy::expect_used,
            reason = "The filename and asset come from the same OCR catalog entry"
        )]
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

pub fn is_detector_downloaded(store: &AssetStore) -> bool {
    store.is_downloaded(&DETECTION.asset())
}

pub async fn ensure_models(
    store: &AssetStore,
    include_recognizer: bool,
) -> MlResult<OcrModelPaths> {
    let files = if include_recognizer {
        &CATALOG[..]
    } else {
        &CATALOG[..1]
    };
    let missing: Vec<(&OcrModelFile, Asset)> = files
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
                file.url
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
        classification: if include_recognizer {
            CLASSIFICATION.path(store)
        } else {
            String::new()
        },
        recognition: if include_recognizer {
            RECOGNITION.path(store)
        } else {
            String::new()
        },
        dictionary: if include_recognizer {
            DICTIONARY.path(store)
        } else {
            String::new()
        },
    })
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::path::Path;

    use super::*;

    fn cache_model(store: &AssetStore, model: &OcrModelFile) {
        let asset = model.asset();
        fs::create_dir_all(store.asset_dir(&asset)).unwrap();
        fs::write(model.path(store), b"cached model").unwrap();
    }

    #[test]
    fn detector_availability_requires_the_published_file() {
        let root = tempfile::tempdir().unwrap();
        let store = AssetStore::new(root.path());
        assert!(!is_detector_downloaded(&store));

        fs::create_dir_all(store.asset_dir(&DETECTION.asset())).unwrap();
        assert!(!is_detector_downloaded(&store));

        cache_model(&store, &RECOGNITION);
        assert!(!is_detector_downloaded(&store));

        cache_model(&store, &DETECTION);
        assert!(is_detector_downloaded(&store));

        store.remove(&DETECTION.asset()).unwrap();
        assert!(!is_detector_downloaded(&store));
    }

    #[test]
    fn legacy_models_do_not_satisfy_the_optimized_catalog() {
        let root = tempfile::tempdir().unwrap();
        let store = AssetStore::new(root.path());
        for (model, legacy_key) in [
            (&DETECTION, "ppocrv5_det"),
            (&CLASSIFICATION, "ppocrv5_cls"),
            (&RECOGNITION, "ppocrv5_rec"),
        ] {
            let legacy = OcrModelFile {
                key: legacy_key,
                ..*model
            };
            cache_model(&store, &legacy);
            assert!(!store.is_downloaded(&model.asset()));
            assert_ne!(model.path(&store), legacy.path(&store));
        }
        assert!(!is_detector_downloaded(&store));
    }

    #[tokio::test]
    async fn cached_detector_can_be_prepared_without_recognition_models() {
        let root = tempfile::tempdir().unwrap();
        let store = AssetStore::new(root.path());
        cache_model(&store, &DETECTION);

        let paths = ensure_models(&store, false).await.unwrap();

        assert_eq!(paths.detection, DETECTION.path(&store));
        assert!(paths.classification.is_empty());
        assert!(paths.recognition.is_empty());
        assert!(paths.dictionary.is_empty());
        for model in [&CLASSIFICATION, &RECOGNITION, &DICTIONARY] {
            assert!(!store.is_downloaded(&model.asset()));
        }
    }

    #[tokio::test]
    async fn cached_full_models_can_be_prepared_after_detector_only() {
        let root = tempfile::tempdir().unwrap();
        let store = AssetStore::new(root.path());
        for model in CATALOG {
            cache_model(&store, model);
        }

        let detector_paths = ensure_models(&store, false).await.unwrap();
        let paths = ensure_models(&store, true).await.unwrap();

        assert_eq!(paths.detection, detector_paths.detection);
        assert_eq!(paths.classification, CLASSIFICATION.path(&store));
        assert_eq!(paths.recognition, RECOGNITION.path(&store));
        assert_eq!(paths.dictionary, DICTIONARY.path(&store));
        assert_eq!(fs::read(&paths.detection).unwrap(), b"cached model");
    }

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
