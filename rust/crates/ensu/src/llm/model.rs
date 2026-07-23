use llama_cpp_2::model::LlamaModel;
use serde::{Deserialize, Serialize};
use std::path::Path;
use std::sync::Arc;

use super::{Error, backend};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelLoadParams {
    pub model_path: String,
    pub n_gpu_layers: Option<i32>,
    pub use_mmap: Option<bool>,
    pub use_mlock: Option<bool>,
}

pub struct Model {
    model: LlamaModel,
}

pub type ModelRef = Arc<Model>;

impl Model {
    pub fn load(params: ModelLoadParams) -> Result<ModelRef, Error> {
        let backend = backend()?;
        let mut model_params = llama_cpp_2::model::params::LlamaModelParams::default();

        if let Some(n_gpu_layers) = params.n_gpu_layers {
            let layers = u32::try_from(n_gpu_layers)
                .map_err(|_| Error::InvalidInput("n_gpu_layers must be >= 0".to_string()))?;
            model_params = model_params.with_n_gpu_layers(layers);
        }

        if let Some(use_mlock) = params.use_mlock {
            model_params = model_params.with_use_mlock(use_mlock);
        }

        let model =
            LlamaModel::load_from_file(backend, Path::new(&params.model_path), &model_params)
                .map_err(|err| Error::Llama {
                    op: "Failed to load model",
                    message: err.to_string(),
                })?;

        Ok(Arc::new(Model { model }))
    }

    pub(super) fn model(&self) -> &LlamaModel {
        &self.model
    }
}

pub fn init_backend() -> Result<(), Error> {
    backend().map(|_| ())
}
