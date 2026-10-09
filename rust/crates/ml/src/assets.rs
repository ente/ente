use std::fs;
use std::path::{Path, PathBuf};

use ente_assets::{
    Asset, AssetDownloadProgress, AssetFile, AssetStore,
    download::{CancellationToken, Error as DownloadError},
};

use super::models::{self, Model, ModelPaths};

const MODELS: &str = "models";

const RETIRED_MODEL_KEYS: &[&str] = &[];

const RETIRED_LEGACY_MODEL_FILES: &[&str] = &[
    "clip-image-vit-32-float32.onnx",
    "clip-text-vit-32-uint8.onnx",
    "mobileclip_s2_image.onnx",
    "mobileclip_s2_image_opset18_rgba_sim.onnx",
    "mobileclip_s2_image_opset18_rgba_opt.onnx",
    "mobileclip_s2_text_int32.onnx",
    "yolov5s_face_640_640_dynamic.onnx",
    "yolov5s_face_opset18_rgba_opt.onnx",
    "yolov5s_face_opset18_rgba_opt_nosplits.onnx",
    "mobilefacenet_opset15.onnx",
];

pub struct ClipTextPaths {
    pub model: PathBuf,
    pub vocab: PathBuf,
}

fn model_asset(model: Model) -> Asset {
    let spec = model_asset_spec(model);
    #[expect(
        clippy::expect_used,
        reason = "The built-in model catalog has valid asset keys and checksums"
    )]
    Asset::files(
        model_key(spec.key),
        spec.files
            .iter()
            .map(|file| AssetFile {
                name: file.name.to_string(),
                url: format!("https://models.ente.com/{}", file.name),
                size: file.size,
                sha256: file.sha256.to_string(),
            })
            .collect(),
    )
    .expect("valid Photos model catalog")
}

pub fn indexing_assets(run_faces: bool, run_clip: bool, run_pets: bool) -> Vec<Asset> {
    models::selected_indexing_models(run_faces, run_clip, run_pets)
        .map(model_asset)
        .collect()
}

pub fn indexing_model_paths(
    store: &AssetStore,
    run_faces: bool,
    run_clip: bool,
    run_pets: bool,
) -> ModelPaths {
    let mut model_paths = ModelPaths::default();
    for model in models::selected_indexing_models(run_faces, run_clip, run_pets) {
        *model_paths.get_mut(model) = model_path(store, model);
    }
    model_paths
}

pub fn clip_text_paths(store: &AssetStore) -> ClipTextPaths {
    let asset = clip_text_asset();
    let files = model_asset_spec(Model::ClipText).files;
    ClipTextPaths {
        #[expect(
            clippy::expect_used,
            reason = "The filename and asset come from the same CLIP catalog entry"
        )]
        model: store
            .file_path(&asset, files[0].name)
            .expect("CLIP text model file"),
        #[expect(
            clippy::expect_used,
            reason = "The filename and asset come from the same CLIP catalog entry"
        )]
        vocab: store
            .file_path(&asset, files[1].name)
            .expect("CLIP text vocabulary file"),
    }
}

pub fn clip_text_asset() -> Asset {
    model_asset(Model::ClipText)
}

pub async fn ensure_indexing_models(
    store: &AssetStore,
    legacy_dir: &Path,
    run_faces: bool,
    run_clip: bool,
    run_pets: bool,
) -> Result<ModelPaths, DownloadError> {
    ensure_mobile_models(
        store,
        legacy_dir,
        &indexing_assets(run_faces, run_clip, run_pets),
        |_| {},
    )
    .await?;
    Ok(indexing_model_paths(store, run_faces, run_clip, run_pets))
}

pub async fn ensure_clip_text(
    store: &AssetStore,
    legacy_dir: &Path,
) -> Result<ClipTextPaths, DownloadError> {
    ensure_mobile_models(store, legacy_dir, &[clip_text_asset()], |_| {}).await?;
    Ok(clip_text_paths(store))
}

pub async fn ensure_mobile_models(
    store: &AssetStore,
    legacy_dir: &Path,
    assets: &[Asset],
    on_progress: impl FnMut(AssetDownloadProgress) + Send,
) -> Result<(), DownloadError> {
    store
        .download_with_staged_import(
            assets,
            on_progress,
            CancellationToken::default(),
            |asset, staging| {
                for model in Model::ALL {
                    if model_asset(model) == *asset {
                        import_mobile_model(legacy_dir, staging, model_asset_spec(model).files)?;
                        break;
                    }
                }
                Ok(())
            },
        )
        .await
}

pub fn is_clip_text_available(store: &AssetStore, legacy_dir: &Path, include_vocab: bool) -> bool {
    let spec = model_asset_spec(Model::ClipText);
    let files = if include_vocab {
        spec.files
    } else {
        &spec.files[..1]
    };
    files.iter().all(|file| {
        store
            .file_path(&clip_text_asset(), file.name)
            .is_some_and(|path| path.is_file())
            || store
                .staged_file_path(&clip_text_asset(), file.name)
                .is_some_and(|path| path.is_file())
            || legacy_mobile_paths(legacy_dir, file.name)
                .iter()
                .any(|path| path.is_file())
    })
}

fn import_mobile_model(
    legacy_dir: &Path,
    staging: &Path,
    files: &[ModelAssetFile],
) -> Result<(), ente_assets::download::Error> {
    for name in RETIRED_LEGACY_MODEL_FILES {
        for path in legacy_mobile_paths(legacy_dir, name) {
            remove_file_if_exists(&path)?;
            remove_file_if_exists(&path.with_extension("temp"))?;
            remove_file_if_exists(&path.with_extension("temp.resume.json"))?;
        }
    }
    for file in files {
        let destination = staging.join(file.name);
        for source in legacy_mobile_paths(legacy_dir, file.name) {
            remove_file_if_exists(&source.with_extension("temp"))?;
            remove_file_if_exists(&source.with_extension("temp.resume.json"))?;
            if !source.is_file() {
                continue;
            }
            if destination.exists() {
                remove_file_if_exists(&source)?;
            } else {
                fs::create_dir_all(staging)?;
                fs::rename(source, &destination)?;
            }
        }
    }
    Ok(())
}

fn legacy_mobile_paths(legacy_dir: &Path, name: &str) -> [PathBuf; 2] {
    ["com", "io"].map(|domain| {
        let name = format!("models.ente.{domain}/{name}")
            .chars()
            .map(|character| {
                if character.is_ascii_alphanumeric() {
                    character
                } else {
                    '_'
                }
            })
            .collect::<String>();
        legacy_dir.join(name)
    })
}

pub fn migrate_desktop_models(store: &AssetStore, legacy_dir: &Path) -> Vec<String> {
    let mut warnings = Vec::new();
    if legacy_dir.exists() {
        for model in Model::ALL {
            if let Err(error) = migrate_desktop_model(store, legacy_dir, model) {
                warnings.push(format!(
                    "Failed to migrate {}: {error}",
                    model_asset_spec(model).key
                ));
            }
        }
        for name in RETIRED_LEGACY_MODEL_FILES {
            if let Err(error) = remove_file_if_exists(&legacy_dir.join(name)) {
                warnings.push(format!("Failed to remove retired model {name}: {error}"));
            }
        }
        let _ = fs::remove_dir(legacy_dir);
    }

    let retired_keys = RETIRED_MODEL_KEYS
        .iter()
        .map(|key| model_key(key))
        .collect::<Vec<_>>();
    if let Err(error) = store.remove_keys(&retired_keys) {
        warnings.push(format!("Failed to remove retired model assets: {error}"));
    }
    warnings
}

fn model_asset_spec(model: Model) -> ModelAssetSpec {
    match model {
        Model::FaceDetection => ModelAssetSpec {
            key: "yolov5s_face_640_640_static_b1",
            files: &[ModelAssetFile {
                name: "yolov5s_face_640_640_static_b1.onnx",
                size: 32_355_091,
                sha256: "e047647409403d52696035ecd445792173e50d7fbdcccac97b958a585db9aa3d",
            }],
        },
        Model::FaceEmbedding => ModelAssetSpec {
            key: "mobilefacenet_portable_static_b1",
            files: &[ModelAssetFile {
                name: "mobilefacenet_portable_static_b1.onnx",
                size: 5_278_803,
                sha256: "0763fc33f54e138476194da95987e133b3e976075a6b1d3e1b2caedb251b1a36",
            }],
        },
        Model::ClipImage => ModelAssetSpec {
            key: "mobileclip_s2_image_gelu_opset20",
            files: &[ModelAssetFile {
                name: "mobileclip_s2_image_gelu_opset20.onnx",
                size: 143_057_352,
                sha256: "205a430af825e501c5138e5bb9abea942482a7a4fd4a680e98e47cf0830dce7e",
            }],
        },
        Model::ClipText => ModelAssetSpec {
            key: "mobileclip_s2_text_opset18_quant",
            files: &[
                ModelAssetFile {
                    name: "mobileclip_s2_text_opset18_quant.onnx",
                    size: 67_144_712,
                    sha256: "d92f33dfcff83077fc2e0d3414250710efbb51795dfd89767bdbefb5fdc47322",
                },
                ModelAssetFile {
                    name: "bpe_simple_vocab_16e6.txt",
                    size: 3_194_984,
                    sha256: "67603cfda2e032ad77b5f8808af37789d590db664b26df8705d2bf8b3c553fc8",
                },
            ],
        },
        Model::PetFaceDetection => ModelAssetSpec {
            key: "yolov5s_pet_face_fp16_V2",
            files: &[ModelAssetFile {
                name: "yolov5s_pet_face_fp16_V2.onnx",
                size: 14_758_020,
                sha256: "7876d97992eeb5f3a9f3b35eff5e0e133012928172a8b005093108d8c3ad2d1c",
            }],
        },
        Model::PetFaceEmbeddingDog => ModelAssetSpec {
            key: "dog_face_embedding128",
            files: &[ModelAssetFile {
                name: "dog_face_embedding128.onnx",
                size: 4_141_071,
                sha256: "fb04d781eb1f7adf6ce3432dc0c5873f16cc051b5c98c14c754afb39e2b92462",
            }],
        },
        Model::PetFaceEmbeddingCat => ModelAssetSpec {
            key: "cat_face_embedding128",
            files: &[ModelAssetFile {
                name: "cat_face_embedding128.onnx",
                size: 4_141_071,
                sha256: "32b10694a27f6404d2beaddbd64f07ad555f72dccb12ee60a7afe5dcf6aad6cd",
            }],
        },
        Model::PetBodyDetection => ModelAssetSpec {
            key: "yolov5s_object_fp16",
            files: &[ModelAssetFile {
                name: "yolov5s_object_fp16.onnx",
                size: 14_987_107,
                sha256: "113f0c18632eb2c4f6deebcd40eb01c676492e9b43923c2d336e1b4012fce9ef",
            }],
        },
        Model::PetBodyEmbeddingDog => ModelAssetSpec {
            key: "dog_body_embedding192",
            files: &[ModelAssetFile {
                name: "dog_body_embedding192.onnx",
                size: 4_569_361,
                sha256: "1d85aa20358137e30f11c2d0baa9a2248b9997928d501fe15365d1fc57522770",
            }],
        },
        Model::PetBodyEmbeddingCat => ModelAssetSpec {
            key: "cat_body_embedding192",
            files: &[ModelAssetFile {
                name: "cat_body_embedding192.onnx",
                size: 4_569_361,
                sha256: "62fb5891e61be69a96510d8ec56e7525a9541b0283e54574d27c86c9b4a26ddf",
            }],
        },
    }
}

struct ModelAssetSpec {
    key: &'static str,
    files: &'static [ModelAssetFile],
}

struct ModelAssetFile {
    name: &'static str,
    size: u64,
    sha256: &'static str,
}

fn model_path(store: &AssetStore, model: Model) -> String {
    let asset = model_asset(model);
    #[expect(
        clippy::expect_used,
        reason = "The filename and asset come from the same model catalog entry"
    )]
    store
        .file_path(&asset, model_asset_spec(model).files[0].name)
        .expect("model file")
        .to_string_lossy()
        .into_owned()
}

fn model_key(key: &str) -> Vec<String> {
    vec![MODELS.to_string(), key.to_string()]
}

fn migrate_desktop_model(
    store: &AssetStore,
    legacy_dir: &Path,
    model: Model,
) -> Result<(), String> {
    let spec = model_asset_spec(model);
    let asset = model_asset(model);
    let legacy_files = spec
        .files
        .iter()
        .map(|file| (file, legacy_dir.join(file.name)))
        .collect::<Vec<_>>();
    let states = legacy_files
        .iter()
        .map(|(file, path)| match fs::symlink_metadata(path) {
            Ok(metadata) => Ok(Some(
                metadata.file_type().is_file() && metadata.len() == file.size,
            )),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(error) => Err(error),
        })
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| error.to_string())?;

    if states.iter().all(Option::is_none) {
        return Ok(());
    }
    if store.is_downloaded(&asset) || !states.iter().all(|state| *state == Some(true)) {
        return legacy_files
            .iter()
            .try_for_each(|(_, path)| remove_file_if_exists(path))
            .map_err(|error| error.to_string());
    }

    store.remove(&asset).map_err(|error| error.to_string())?;
    let destination = store.asset_dir(&asset);
    fs::create_dir_all(&destination).map_err(|error| error.to_string())?;
    legacy_files
        .iter()
        .try_for_each(|(file, source)| fs::rename(source, destination.join(file.name)))
        .map_err(|error| error.to_string())
}

fn remove_file_if_exists(path: &Path) -> std::io::Result<()> {
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error),
    }
}

#[cfg(test)]
mod tests {
    use tempfile::TempDir;

    use super::*;

    const MOBILE_TEST_FILES: &[ModelAssetFile] = &[
        ModelAssetFile {
            name: "mobileclip_s2_text_opset18_quant.onnx",
            size: 5,
            sha256: "9372c470eeadd5ecd9c3c74c2b3cb633f8e2f2fad799250a0f70d652b6b825e4",
        },
        ModelAssetFile {
            name: "bpe_simple_vocab_16e6.txt",
            size: 5,
            sha256: "273e2549599ddf859b4c24385dfb4dcc23e8e66994c2c176b90c602f77a795c0",
        },
    ];

    fn mobile_test_asset() -> Asset {
        Asset::files(
            model_key("mobileclip_s2_text_opset18_quant"),
            MOBILE_TEST_FILES
                .iter()
                .map(|file| AssetFile {
                    name: file.name.to_string(),
                    url: ":".to_string(),
                    size: file.size,
                    sha256: file.sha256.to_string(),
                })
                .collect(),
        )
        .unwrap()
    }

    async fn acquire_mobile_test_pair(
        store: &AssetStore,
        root: &Path,
    ) -> Result<(), ente_assets::download::Error> {
        store
            .download_with_staged_import(
                &[mobile_test_asset()],
                |_| {},
                CancellationToken::default(),
                |_, staging| import_mobile_model(root, staging, MOBILE_TEST_FILES),
            )
            .await
    }

    #[tokio::test]
    async fn mobile_legacy_pair_is_renamed_and_validated_without_network() {
        let root = TempDir::new().unwrap();
        let store = AssetStore::new(root.path());
        let bytes = [b"model", b"vocab"];
        #[cfg(unix)]
        let mut inodes = Vec::new();
        for (file, bytes) in MOBILE_TEST_FILES.iter().zip(bytes) {
            let path = &legacy_mobile_paths(root.path(), file.name)[0];
            fs::write(path, bytes).unwrap();
            fs::write(path.with_extension("temp"), b"partial").unwrap();
            fs::write(path.with_extension("temp.resume.json"), b"metadata").unwrap();
            #[cfg(unix)]
            {
                use std::os::unix::fs::MetadataExt;
                inodes.push(fs::metadata(path).unwrap().ino());
            }
        }
        fs::write(root.path().join("unrelated.temp"), b"unrelated").unwrap();
        let retired = root
            .path()
            .join("models_ente_io_mobilefacenet_opset15_onnx");
        fs::write(&retired, b"retired").unwrap();
        acquire_mobile_test_pair(&store, root.path()).await.unwrap();
        assert!(!retired.exists());
        for (index, file) in MOBILE_TEST_FILES.iter().enumerate() {
            let path = store.file_path(&mobile_test_asset(), file.name).unwrap();
            assert_eq!(fs::read(&path).unwrap(), bytes[index]);
            #[cfg(unix)]
            {
                use std::os::unix::fs::MetadataExt;
                assert_eq!(fs::metadata(path).unwrap().ino(), inodes[index]);
            }
            for source in legacy_mobile_paths(root.path(), file.name) {
                assert!(!source.exists());
                assert!(!source.with_extension("temp").exists());
                assert!(!source.with_extension("temp.resume.json").exists());
            }
        }
        assert_eq!(
            fs::read(root.path().join("unrelated.temp")).unwrap(),
            b"unrelated"
        );
        fs::write(
            store
                .file_path(&mobile_test_asset(), MOBILE_TEST_FILES[0].name)
                .unwrap(),
            b"trusted",
        )
        .unwrap();
        acquire_mobile_test_pair(&AssetStore::new(root.path()), root.path())
            .await
            .unwrap();
        assert_eq!(
            fs::read(
                store
                    .file_path(&mobile_test_asset(), MOBILE_TEST_FILES[0].name)
                    .unwrap()
            )
            .unwrap(),
            b"trusted"
        );
    }

    #[tokio::test]
    async fn mobile_cleanup_handles_retired_artifacts_without_current_legacy_models() {
        let root = TempDir::new().unwrap();
        let store = AssetStore::new(root.path());
        let retired = RETIRED_LEGACY_MODEL_FILES
            .iter()
            .flat_map(|name| legacy_mobile_paths(root.path(), name))
            .flat_map(|path| {
                [
                    path.with_extension("temp"),
                    path.with_extension("temp.resume.json"),
                    path,
                ]
            })
            .collect::<Vec<_>>();
        for path in &retired {
            fs::write(path, b"retired").unwrap();
        }
        let preserved = [
            root.path().join("models_ente_com_memory_music_mp3"),
            legacy_mobile_paths(root.path(), "mobilefacenet_portable_static_b1.onnx")[0].clone(),
            root.path().join("models/det_fixed_v1/det_fixed_v1.onnx"),
        ];
        fs::create_dir_all(preserved[2].parent().unwrap()).unwrap();
        for path in &preserved {
            fs::write(path, b"preserved").unwrap();
        }

        for _ in 0..2 {
            assert!(acquire_mobile_test_pair(&store, root.path()).await.is_err());
            assert!(retired.iter().all(|path| !path.exists()));
            for path in &preserved {
                assert_eq!(fs::read(path).unwrap(), b"preserved");
            }
        }
    }

    #[tokio::test]
    async fn either_lone_mobile_member_survives_failure_and_is_reused() {
        for first in [0, 1] {
            let root = TempDir::new().unwrap();
            let store = AssetStore::new(root.path());
            let bytes = [b"model", b"vocab"];
            let source = &legacy_mobile_paths(root.path(), MOBILE_TEST_FILES[first].name)[0];
            fs::write(source, bytes[first]).unwrap();
            assert!(acquire_mobile_test_pair(&store, root.path()).await.is_err());
            assert!(!source.exists());
            assert!(!store.is_downloaded(&mobile_test_asset()));
            let remaining = 1 - first;
            fs::write(
                &legacy_mobile_paths(root.path(), MOBILE_TEST_FILES[remaining].name)[0],
                bytes[remaining],
            )
            .unwrap();
            acquire_mobile_test_pair(&AssetStore::new(root.path()), root.path())
                .await
                .unwrap();
            for (file, bytes) in MOBILE_TEST_FILES.iter().zip(bytes) {
                assert_eq!(
                    fs::read(store.file_path(&mobile_test_asset(), file.name).unwrap()).unwrap(),
                    bytes
                );
            }
        }
    }

    #[tokio::test]
    async fn mobile_import_uses_the_staged_checksum_before_publication() {
        let root = TempDir::new().unwrap();
        let store = AssetStore::new(root.path());
        for (file, bytes) in MOBILE_TEST_FILES.iter().zip([b"wrong", b"vocab"]) {
            fs::write(&legacy_mobile_paths(root.path(), file.name)[0], bytes).unwrap();
        }
        assert!(acquire_mobile_test_pair(&store, root.path()).await.is_err());
        assert!(!store.is_downloaded(&mobile_test_asset()));
        assert!(!store.asset_dir(&mobile_test_asset()).exists());
    }

    #[tokio::test]
    async fn mobile_legacy_file_beats_rust_resume_data() {
        let root = TempDir::new().unwrap();
        let store = AssetStore::new(root.path());
        let asset = mobile_test_asset();
        let staged = store
            .staged_file_path(&asset, MOBILE_TEST_FILES[0].name)
            .unwrap();
        let partial = PathBuf::from(format!("{}.tmp", staged.display()));
        let metadata = PathBuf::from(format!("{}.tmp.partial.json", staged.display()));
        fs::create_dir_all(staged.parent().unwrap()).unwrap();
        fs::write(&partial, b"rust partial").unwrap();
        fs::write(&metadata, b"rust metadata").unwrap();
        for (file, bytes) in MOBILE_TEST_FILES.iter().zip([b"model", b"vocab"]) {
            fs::write(&legacy_mobile_paths(root.path(), file.name)[0], bytes).unwrap();
        }
        acquire_mobile_test_pair(&store, root.path()).await.unwrap();
        assert_eq!(
            fs::read(store.file_path(&asset, MOBILE_TEST_FILES[0].name).unwrap()).unwrap(),
            b"model"
        );
        assert!(!partial.exists());
        assert!(!metadata.exists());
    }

    #[tokio::test]
    async fn mobile_import_removes_duplicate_legacy_domains() {
        let root = TempDir::new().unwrap();
        let store = AssetStore::new(root.path());
        for (file, bytes) in MOBILE_TEST_FILES.iter().zip([b"model", b"vocab"]) {
            for path in legacy_mobile_paths(root.path(), file.name) {
                fs::write(path, bytes).unwrap();
            }
        }
        acquire_mobile_test_pair(&store, root.path()).await.unwrap();
        for file in MOBILE_TEST_FILES {
            for path in legacy_mobile_paths(root.path(), file.name) {
                assert!(!path.exists());
            }
        }
    }

    #[tokio::test]
    async fn mobile_ensure_returns_only_the_requested_published_paths() {
        let root = TempDir::new().unwrap();
        let store = AssetStore::new(root.path());
        let retired = root
            .path()
            .join("models_ente_io_mobilefacenet_opset15_onnx");
        fs::write(&retired, b"retired").unwrap();
        for model in models::selected_indexing_models(true, false, false) {
            fs::create_dir_all(store.asset_dir(&model_asset(model))).unwrap();
            fs::write(model_path(&store, model), b"trusted published bytes").unwrap();
        }
        let paths = ensure_indexing_models(&store, root.path(), true, false, false)
            .await
            .unwrap();
        assert_eq!(
            fs::read(paths.face_detection).unwrap(),
            b"trusted published bytes"
        );
        assert_eq!(
            fs::read(paths.face_embedding).unwrap(),
            b"trusted published bytes"
        );
        assert!(paths.clip_image.is_empty());
        assert!(paths.pet_face_detection.is_empty());
        assert!(!store.asset_dir(&clip_text_asset()).exists());
        assert_eq!(fs::read(retired).unwrap(), b"retired");
    }

    #[test]
    fn mobile_clip_readiness_keeps_model_only_admission() {
        let root = TempDir::new().unwrap();
        let store = AssetStore::new(root.path());
        let files = model_asset_spec(Model::ClipText).files;
        fs::write(
            &legacy_mobile_paths(root.path(), files[0].name)[0],
            b"model",
        )
        .unwrap();
        assert!(is_clip_text_available(&store, root.path(), false));
        assert!(!is_clip_text_available(&store, root.path(), true));
        fs::write(
            &legacy_mobile_paths(root.path(), files[1].name)[0],
            b"vocab",
        )
        .unwrap();
        assert!(is_clip_text_available(&store, root.path(), true));
    }

    #[test]
    fn catalog_keys_are_unique_and_prefix_free() {
        let root = Path::new("assets");
        let store = AssetStore::new(root);
        let paths = Model::ALL
            .map(|model| store.asset_dir(&model_asset(model)))
            .to_vec();
        for (index, path) in paths.iter().enumerate() {
            assert!(path.starts_with(root));
            for other in &paths[index + 1..] {
                assert_ne!(path, other);
                assert!(!path.starts_with(other));
                assert!(!other.starts_with(path));
            }
        }
    }

    #[test]
    fn test_model_pins_match_the_catalog() {
        let path = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../../infra/ml/test/ml_indexing/assets.json");
        let contents = fs::read_to_string(&path).unwrap();
        let lock: serde_json::Value = serde_json::from_str(&contents).unwrap();
        for model in lock["models"].as_object().unwrap().values() {
            let name = model["file_name"].as_str().unwrap();
            let size = model["size"].as_u64().unwrap();
            let sha256 = model["sha256"].as_str().unwrap();
            let catalog_file = Model::ALL
                .iter()
                .flat_map(|model| model_asset_spec(*model).files)
                .find(|file| file.name == name)
                .unwrap_or_else(|| panic!("{name} is missing from the Photos model catalog"));
            assert_eq!(catalog_file.size, size, "{name}");
            assert_eq!(catalog_file.sha256, sha256, "{name}");
        }
    }

    #[test]
    fn migrates_complete_legacy_models_and_prunes_retired_files() {
        let temp = TempDir::new().unwrap();
        let legacy = temp.path().join("models");
        fs::create_dir(&legacy).unwrap();
        create_legacy_file(&legacy, &model_asset_spec(Model::FaceEmbedding).files[0]);
        fs::write(legacy.join(RETIRED_LEGACY_MODEL_FILES[0]), b"retired").unwrap();
        let store = AssetStore::new(temp.path().join("assets"));

        assert!(migrate_desktop_models(&store, &legacy).is_empty());

        let asset = model_asset(Model::FaceEmbedding);
        assert!(store.is_downloaded(&asset));
        assert_eq!(
            fs::metadata(model_path(&store, Model::FaceEmbedding))
                .unwrap()
                .len(),
            model_asset_spec(Model::FaceEmbedding).files[0].size
        );
        assert!(!legacy.join(RETIRED_LEGACY_MODEL_FILES[0]).exists());
    }

    #[test]
    fn rejects_partial_or_wrong_sized_legacy_models() {
        let temp = TempDir::new().unwrap();
        let legacy = temp.path().join("models");
        fs::create_dir(&legacy).unwrap();
        create_legacy_file(&legacy, &model_asset_spec(Model::ClipText).files[0]);
        fs::write(
            legacy.join(model_asset_spec(Model::FaceDetection).files[0].name),
            b"truncated",
        )
        .unwrap();
        let store = AssetStore::new(temp.path().join("assets"));

        assert!(migrate_desktop_models(&store, &legacy).is_empty());

        assert!(!store.is_downloaded(&model_asset(Model::ClipText)));
        assert!(!store.is_downloaded(&model_asset(Model::FaceDetection)));
        assert!(!legacy.exists());
    }

    fn create_legacy_file(directory: &Path, file: &ModelAssetFile) {
        let handle = fs::File::create(directory.join(file.name)).unwrap();
        handle.set_len(file.size).unwrap();
    }
}
