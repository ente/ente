use std::{
    cell::Cell,
    sync::{Mutex, MutexGuard},
};

use once_cell::sync::Lazy;

use crate::{
    error::{MlError, MlResult},
    models::{Model, ModelPaths},
    onnx,
};

#[derive(Debug)]
struct ModelSlotState {
    path: String,
    onnx_session: onnx::OnnxSession,
}

#[cfg(test)]
#[derive(Debug, PartialEq, Eq)]
struct ModelSlotSnapshot {
    path: String,
    session_loaded: bool,
}

#[derive(Debug)]
struct ModelSlot {
    model: Model,
    state: Mutex<ModelSlotState>,
}

pub(crate) struct MlRuntimeView<'a> {
    runtime: &'a MlRuntime,
    model_paths: &'a ModelPaths,
    provider_usage: Cell<onnx::ProviderUsage>,
}

impl ModelSlot {
    fn new(model: Model) -> Self {
        Self {
            model,
            state: Mutex::new(ModelSlotState {
                path: String::new(),
                onnx_session: onnx::OnnxSession::new(default_execution_mode(model)),
            }),
        }
    }

    fn lock_state(&self) -> MutexGuard<'_, ModelSlotState> {
        match self.state.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        }
    }

    #[cfg(test)]
    fn snapshot(&self) -> ModelSlotSnapshot {
        let state = self.lock_state();
        ModelSlotSnapshot {
            path: state.path.clone(),
            session_loaded: state.onnx_session.is_loaded(),
        }
    }

    fn configure_if_requested(&self, path: &str) {
        if path.trim().is_empty() {
            return;
        }
        let mut state = self.lock_state();
        Self::set_config_locked(&mut state, path);
    }

    fn sync_indexing_residency(&self, path: &str) {
        let mut state = self.lock_state();
        if path.trim().is_empty() {
            Self::reset_slot_locked(&mut state);
            return;
        }

        Self::set_config_locked(&mut state, path);
    }

    fn release_residency(&self) {
        let mut state = self.lock_state();
        state.onnx_session.clear();
    }

    fn run<T>(
        &self,
        path: &str,
        operation: impl FnMut(&mut onnx::SessionHandle) -> onnx::SessionRunResult<T>,
    ) -> MlResult<(T, onnx::ProviderUsage)> {
        if path.trim().is_empty() {
            return Err(MlError::InvalidRequest(self.model.missing_path_error()));
        }

        let mut state = self.lock_state();
        Self::set_config_locked(&mut state, path);
        let ModelSlotState { path, onnx_session } = &mut *state;
        onnx_session.run(path, self.model.namespace(), operation)
    }

    fn set_config_locked(state: &mut ModelSlotState, path: &str) {
        if state.path == path {
            return;
        }
        state.path = path.to_string();
        state.onnx_session.clear();
    }

    fn reset_slot_locked(state: &mut ModelSlotState) {
        state.path.clear();
        state.onnx_session.clear();
    }
}

#[derive(Debug)]
struct MlRuntime {
    slots: [ModelSlot; Model::COUNT],
}

static GLOBAL_RUNTIME: Lazy<MlRuntime> = Lazy::new(MlRuntime::new);

impl MlRuntime {
    fn new() -> Self {
        Self {
            slots: Model::ALL.map(ModelSlot::new),
        }
    }

    fn slot(&self, model: Model) -> &ModelSlot {
        &self.slots[model.index()]
    }

    fn configure_requested_models(&self, model_paths: &ModelPaths) {
        for model in Model::ALL {
            self.slot(model)
                .configure_if_requested(model_paths.get(model));
        }
    }

    fn prepare_indexing_models(&self, model_paths: &ModelPaths) {
        for model in Model::INDEXING {
            self.slot(model)
                .sync_indexing_residency(model_paths.get(model));
        }
    }

    fn release_indexing_models(&self) {
        for model in Model::INDEXING {
            self.slot(model).release_residency();
        }
    }
}

impl<'a> MlRuntimeView<'a> {
    pub(crate) fn provider_usage(&self) -> onnx::ProviderUsage {
        self.provider_usage.get()
    }

    pub(crate) fn run<T>(
        &self,
        model: Model,
        operation: impl FnMut(&mut onnx::SessionHandle) -> onnx::SessionRunResult<T>,
    ) -> MlResult<T> {
        let (value, provider_usage) = self
            .runtime
            .slot(model)
            .run(self.model_paths.get(model), operation)?;
        self.provider_usage
            .set(self.provider_usage.get().merge(provider_usage));
        Ok(value)
    }
}

fn default_execution_mode(model: Model) -> onnx::ExecutionMode {
    match model {
        Model::FaceDetection | Model::FaceEmbedding | Model::ClipImage => {
            onnx::ExecutionMode::PlatformDefault
        }
        // Accelerators heavily partition the quantized CLIP text graph.
        Model::ClipText => onnx::ExecutionMode::CpuOnly,
        // Pet models have device-specific FP16 failures.
        Model::PetFaceDetection
        | Model::PetFaceEmbeddingDog
        | Model::PetFaceEmbeddingCat
        | Model::PetBodyDetection
        | Model::PetBodyEmbeddingDog
        | Model::PetBodyEmbeddingCat => onnx::ExecutionMode::CpuOnly,
    }
}

pub(crate) fn prepare_runtime(model_paths: &ModelPaths) {
    GLOBAL_RUNTIME.prepare_indexing_models(model_paths);
}

pub(crate) fn with_runtime<R>(
    model_paths: &ModelPaths,
    func: impl FnOnce(&MlRuntimeView<'_>) -> MlResult<R>,
) -> MlResult<R> {
    GLOBAL_RUNTIME.configure_requested_models(model_paths);

    let runtime_view = MlRuntimeView {
        runtime: &GLOBAL_RUNTIME,
        model_paths,
        provider_usage: Cell::new(onnx::ProviderUsage::default()),
    };
    func(&runtime_view)
}

pub(crate) fn release_runtime() {
    GLOBAL_RUNTIME.release_indexing_models();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn configure_requested_models_preserves_unrequested_slots() {
        let runtime = MlRuntime::new();

        runtime.configure_requested_models(&ModelPaths {
            clip_text: "clip_text.onnx".to_string(),
            ..ModelPaths::default()
        });

        runtime.configure_requested_models(&ModelPaths {
            face_detection: "face.onnx".to_string(),
            ..ModelPaths::default()
        });

        assert_eq!(
            runtime.slot(Model::ClipText).snapshot().path,
            "clip_text.onnx"
        );
        assert_eq!(
            runtime.slot(Model::FaceDetection).snapshot().path,
            "face.onnx"
        );
    }

    #[test]
    fn runtime_accepts_single_use_operation() {
        let value = String::from("once");

        let result = with_runtime(&ModelPaths::default(), move |_| Ok(value));

        assert_eq!(result.unwrap(), "once");
    }

    #[test]
    fn release_indexing_models_preserves_clip_text_configuration() {
        let runtime = MlRuntime::new();
        let model_paths = ModelPaths {
            face_detection: "face.onnx".to_string(),
            clip_text: "clip_text.onnx".to_string(),
            ..ModelPaths::default()
        };

        runtime.configure_requested_models(&model_paths);
        runtime.release_indexing_models();

        assert_eq!(
            runtime.slot(Model::ClipText).snapshot(),
            ModelSlotSnapshot {
                path: "clip_text.onnx".to_string(),
                session_loaded: false,
            }
        );
        assert_eq!(
            runtime.slot(Model::FaceDetection).snapshot(),
            ModelSlotSnapshot {
                path: "face.onnx".to_string(),
                session_loaded: false,
            }
        );
    }

    #[test]
    fn prepare_indexing_models_configures_without_loading_sessions() {
        let runtime = MlRuntime::new();

        runtime.prepare_indexing_models(&ModelPaths {
            face_detection: "face.onnx".to_string(),
            face_embedding: "embed.onnx".to_string(),
            clip_image: "clip.onnx".to_string(),
            ..ModelPaths::default()
        });

        assert_eq!(
            runtime.slot(Model::FaceDetection).snapshot(),
            unloaded_snapshot("face.onnx")
        );
        assert_eq!(
            runtime.slot(Model::FaceEmbedding).snapshot(),
            unloaded_snapshot("embed.onnx")
        );
        assert_eq!(
            runtime.slot(Model::ClipImage).snapshot(),
            unloaded_snapshot("clip.onnx")
        );
    }

    #[test]
    fn disabling_an_indexing_model_resets_its_slot() {
        let runtime = MlRuntime::new();
        runtime.prepare_indexing_models(&ModelPaths {
            clip_image: "clip.onnx".to_string(),
            ..ModelPaths::default()
        });

        runtime.prepare_indexing_models(&ModelPaths::default());

        assert_eq!(
            runtime.slot(Model::ClipImage).snapshot(),
            unloaded_snapshot("")
        );
    }

    #[test]
    fn model_execution_modes_match_platform_policy() {
        let accelerated = [Model::FaceDetection, Model::FaceEmbedding, Model::ClipImage];

        for model in Model::ALL {
            let expected = if accelerated.contains(&model) {
                onnx::ExecutionMode::PlatformDefault
            } else {
                onnx::ExecutionMode::CpuOnly
            };
            assert_eq!(default_execution_mode(model), expected, "{model:?}");
        }
    }

    fn unloaded_snapshot(path: &str) -> ModelSlotSnapshot {
        ModelSlotSnapshot {
            path: path.to_string(),
            session_loaded: false,
        }
    }
}
