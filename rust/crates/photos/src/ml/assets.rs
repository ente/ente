use std::fs;
use std::path::{Path, PathBuf};

use ente_assets::{Asset, AssetFile, AssetStore, AssetStoreError};

use super::runtime::ModelPaths;

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

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Model {
    FaceDetection,
    FaceEmbedding,
    ClipImage,
    ClipText,
    PetFaceDetection,
    PetFaceEmbeddingDog,
    PetFaceEmbeddingCat,
    PetBodyDetection,
    PetBodyEmbeddingDog,
    PetBodyEmbeddingCat,
}

const ALL_MODELS: [Model; 10] = [
    Model::FaceDetection,
    Model::FaceEmbedding,
    Model::ClipImage,
    Model::ClipText,
    Model::PetFaceDetection,
    Model::PetFaceEmbeddingDog,
    Model::PetFaceEmbeddingCat,
    Model::PetBodyDetection,
    Model::PetBodyEmbeddingDog,
    Model::PetBodyEmbeddingCat,
];

pub struct ClipTextPaths {
    pub model: PathBuf,
    pub vocab: PathBuf,
}

pub fn model_asset(model: Model) -> Asset {
    let spec = model.spec();
    Asset::files(
        model_key(spec.key),
        spec.files
            .iter()
            .map(|file| AssetFile {
                name: file.name.to_string(),
                url: format!("https://models.ente.com/{}", file.name),
                sha256: file.sha256.to_string(),
            })
            .collect(),
    )
    .expect("valid Photos model catalog")
}

pub fn indexing_models(run_faces: bool, run_clip: bool, run_pets: bool) -> Vec<Model> {
    let mut models = Vec::new();
    if run_faces {
        models.extend([Model::FaceDetection, Model::FaceEmbedding]);
    }
    if run_clip {
        models.push(Model::ClipImage);
    }
    if run_pets {
        models.extend([
            Model::PetFaceDetection,
            Model::PetFaceEmbeddingDog,
            Model::PetFaceEmbeddingCat,
            Model::PetBodyDetection,
            Model::PetBodyEmbeddingDog,
            Model::PetBodyEmbeddingCat,
        ]);
    }
    models
}

pub fn indexing_model_paths(
    store: &AssetStore,
    run_faces: bool,
    run_clip: bool,
    run_pets: bool,
) -> ModelPaths {
    ModelPaths {
        face_detection: model_path_if(store, Model::FaceDetection, run_faces),
        face_embedding: model_path_if(store, Model::FaceEmbedding, run_faces),
        clip_image: model_path_if(store, Model::ClipImage, run_clip),
        clip_text: String::new(),
        pet_face_detection: model_path_if(store, Model::PetFaceDetection, run_pets),
        pet_face_embedding_dog: model_path_if(store, Model::PetFaceEmbeddingDog, run_pets),
        pet_face_embedding_cat: model_path_if(store, Model::PetFaceEmbeddingCat, run_pets),
        pet_body_detection: model_path_if(store, Model::PetBodyDetection, run_pets),
        pet_body_embedding_dog: model_path_if(store, Model::PetBodyEmbeddingDog, run_pets),
        pet_body_embedding_cat: model_path_if(store, Model::PetBodyEmbeddingCat, run_pets),
    }
}

pub fn clip_text_paths(store: &AssetStore) -> ClipTextPaths {
    let asset = model_asset(Model::ClipText);
    let files = Model::ClipText.spec().files;
    ClipTextPaths {
        model: store
            .file_path(&asset, files[0].name)
            .expect("CLIP text model file"),
        vocab: store
            .file_path(&asset, files[1].name)
            .expect("CLIP text vocabulary file"),
    }
}

pub fn remove_model_at_path(store: &AssetStore, path: &Path) -> Result<bool, AssetStoreError> {
    for model in ALL_MODELS {
        let asset = model_asset(model);
        if model
            .spec()
            .files
            .iter()
            .filter_map(|file| store.file_path(&asset, file.name))
            .any(|candidate| candidate == path)
        {
            store.remove(&asset)?;
            return Ok(true);
        }
    }
    Ok(false)
}

pub fn migrate_desktop_models(store: &AssetStore, legacy_dir: &Path) -> Vec<String> {
    let mut warnings = Vec::new();
    if legacy_dir.exists() {
        for model in ALL_MODELS {
            if let Err(error) = migrate_desktop_model(store, legacy_dir, model) {
                warnings.push(format!("Failed to migrate {}: {error}", model.spec().key));
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

impl Model {
    fn spec(self) -> ModelSpec {
        match self {
            Self::FaceDetection => ModelSpec {
                key: "yolov5s_face_640_640_static_b1",
                files: &[ModelFileSpec {
                    name: "yolov5s_face_640_640_static_b1.onnx",
                    size: 32_355_091,
                    sha256: "e047647409403d52696035ecd445792173e50d7fbdcccac97b958a585db9aa3d",
                }],
            },
            Self::FaceEmbedding => ModelSpec {
                key: "mobilefacenet_portable_static_b1",
                files: &[ModelFileSpec {
                    name: "mobilefacenet_portable_static_b1.onnx",
                    size: 5_278_803,
                    sha256: "0763fc33f54e138476194da95987e133b3e976075a6b1d3e1b2caedb251b1a36",
                }],
            },
            Self::ClipImage => ModelSpec {
                key: "mobileclip_s2_image_gelu_opset20",
                files: &[ModelFileSpec {
                    name: "mobileclip_s2_image_gelu_opset20.onnx",
                    size: 143_057_352,
                    sha256: "205a430af825e501c5138e5bb9abea942482a7a4fd4a680e98e47cf0830dce7e",
                }],
            },
            Self::ClipText => ModelSpec {
                key: "mobileclip_s2_text_opset18_quant",
                files: &[
                    ModelFileSpec {
                        name: "mobileclip_s2_text_opset18_quant.onnx",
                        size: 67_144_712,
                        sha256: "d92f33dfcff83077fc2e0d3414250710efbb51795dfd89767bdbefb5fdc47322",
                    },
                    ModelFileSpec {
                        name: "bpe_simple_vocab_16e6.txt",
                        size: 3_194_984,
                        sha256: "67603cfda2e032ad77b5f8808af37789d590db664b26df8705d2bf8b3c553fc8",
                    },
                ],
            },
            Self::PetFaceDetection => ModelSpec {
                key: "yolov5s_pet_face_fp16_V2",
                files: &[ModelFileSpec {
                    name: "yolov5s_pet_face_fp16_V2.onnx",
                    size: 14_758_020,
                    sha256: "7876d97992eeb5f3a9f3b35eff5e0e133012928172a8b005093108d8c3ad2d1c",
                }],
            },
            Self::PetFaceEmbeddingDog => ModelSpec {
                key: "dog_face_embedding128",
                files: &[ModelFileSpec {
                    name: "dog_face_embedding128.onnx",
                    size: 4_141_071,
                    sha256: "fb04d781eb1f7adf6ce3432dc0c5873f16cc051b5c98c14c754afb39e2b92462",
                }],
            },
            Self::PetFaceEmbeddingCat => ModelSpec {
                key: "cat_face_embedding128",
                files: &[ModelFileSpec {
                    name: "cat_face_embedding128.onnx",
                    size: 4_141_071,
                    sha256: "32b10694a27f6404d2beaddbd64f07ad555f72dccb12ee60a7afe5dcf6aad6cd",
                }],
            },
            Self::PetBodyDetection => ModelSpec {
                key: "yolov5s_object_fp16",
                files: &[ModelFileSpec {
                    name: "yolov5s_object_fp16.onnx",
                    size: 14_987_107,
                    sha256: "113f0c18632eb2c4f6deebcd40eb01c676492e9b43923c2d336e1b4012fce9ef",
                }],
            },
            Self::PetBodyEmbeddingDog => ModelSpec {
                key: "dog_body_embedding192",
                files: &[ModelFileSpec {
                    name: "dog_body_embedding192.onnx",
                    size: 4_569_361,
                    sha256: "1d85aa20358137e30f11c2d0baa9a2248b9997928d501fe15365d1fc57522770",
                }],
            },
            Self::PetBodyEmbeddingCat => ModelSpec {
                key: "cat_body_embedding192",
                files: &[ModelFileSpec {
                    name: "cat_body_embedding192.onnx",
                    size: 4_569_361,
                    sha256: "62fb5891e61be69a96510d8ec56e7525a9541b0283e54574d27c86c9b4a26ddf",
                }],
            },
        }
    }
}

struct ModelSpec {
    key: &'static str,
    files: &'static [ModelFileSpec],
}

struct ModelFileSpec {
    name: &'static str,
    size: u64,
    sha256: &'static str,
}

fn model_path_if(store: &AssetStore, model: Model, enabled: bool) -> String {
    if !enabled {
        return String::new();
    }
    let asset = model_asset(model);
    store
        .file_path(&asset, model.spec().files[0].name)
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
    let spec = model.spec();
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

    #[test]
    fn catalog_keys_are_unique_and_prefix_free() {
        let root = Path::new("assets");
        let store = AssetStore::new(root);
        let paths = ALL_MODELS
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
    fn retired_keys_are_not_in_the_catalog() {
        for key in RETIRED_MODEL_KEYS {
            assert!(ALL_MODELS.iter().all(|model| model.spec().key != *key));
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
            let sha256 = model["sha256"].as_str().unwrap();
            let catalog_file = ALL_MODELS
                .iter()
                .flat_map(|model| model.spec().files)
                .find(|file| file.name == name)
                .unwrap_or_else(|| panic!("{name} is missing from the Photos model catalog"));
            assert_eq!(catalog_file.sha256, sha256, "{name}");
        }
    }

    #[test]
    fn migrates_complete_legacy_models_and_prunes_retired_files() {
        let temp = TempDir::new().unwrap();
        let legacy = temp.path().join("models");
        fs::create_dir(&legacy).unwrap();
        create_legacy_file(&legacy, &Model::FaceEmbedding.spec().files[0]);
        fs::write(legacy.join(RETIRED_LEGACY_MODEL_FILES[0]), b"retired").unwrap();
        let store = AssetStore::new(temp.path().join("assets"));

        assert!(migrate_desktop_models(&store, &legacy).is_empty());

        let asset = model_asset(Model::FaceEmbedding);
        assert!(store.is_downloaded(&asset));
        assert_eq!(
            fs::metadata(model_path_if(&store, Model::FaceEmbedding, true))
                .unwrap()
                .len(),
            Model::FaceEmbedding.spec().files[0].size
        );
        assert!(!legacy.join(RETIRED_LEGACY_MODEL_FILES[0]).exists());
    }

    #[test]
    fn rejects_partial_or_wrong_sized_legacy_models() {
        let temp = TempDir::new().unwrap();
        let legacy = temp.path().join("models");
        fs::create_dir(&legacy).unwrap();
        create_legacy_file(&legacy, &Model::ClipText.spec().files[0]);
        fs::write(
            legacy.join(Model::FaceDetection.spec().files[0].name),
            b"truncated",
        )
        .unwrap();
        let store = AssetStore::new(temp.path().join("assets"));

        assert!(migrate_desktop_models(&store, &legacy).is_empty());

        assert!(!store.is_downloaded(&model_asset(Model::ClipText)));
        assert!(!store.is_downloaded(&model_asset(Model::FaceDetection)));
        assert!(!legacy.exists());
    }

    fn create_legacy_file(directory: &Path, file: &ModelFileSpec) {
        let handle = fs::File::create(directory.join(file.name)).unwrap();
        handle.set_len(file.size).unwrap();
    }
}
