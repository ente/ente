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

#[cfg(test)]
#[derive(Debug, PartialEq, Eq)]
struct ModelRuntimeSnapshot {
    path: String,
    session_loaded: bool,
    has_load_state: bool,
}

#[derive(Debug)]
struct ModelRuntime {
    model: Model,
    session: Mutex<Option<onnx::OnnxSession>>,
}

pub(crate) struct MlRuntimeView<'a> {
    runtime: &'a MlRuntime,
    model_paths: &'a ModelPaths,
    provider_usage: Cell<onnx::ProviderUsage>,
}

impl ModelRuntime {
    fn new(model: Model) -> Self {
        Self {
            model,
            session: Mutex::new(None),
        }
    }

    fn lock_session(&self) -> MutexGuard<'_, Option<onnx::OnnxSession>> {
        match self.session.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        }
    }

    #[cfg(test)]
    fn snapshot(&self) -> ModelRuntimeSnapshot {
        let session = self.lock_session();
        match session.as_ref() {
            Some(session) => ModelRuntimeSnapshot {
                path: session.model_path().to_string(),
                session_loaded: session.is_loaded(),
                has_load_state: session.has_load_state(),
            },
            None => ModelRuntimeSnapshot {
                path: String::new(),
                session_loaded: false,
                has_load_state: false,
            },
        }
    }

    fn configure_if_requested(&self, path: &str) {
        if path.trim().is_empty() {
            return;
        }
        let mut session = self.lock_session();
        self.configure_locked(&mut session, path);
    }

    fn sync_indexing_residency(&self, path: &str) {
        let mut session = self.lock_session();
        if path.trim().is_empty() {
            *session = None;
            return;
        }

        self.configure_locked(&mut session, path);
    }

    fn release_residency(&self) {
        let mut session = self.lock_session();
        if let Some(session) = session.as_mut() {
            session.unload();
        }
    }

    fn run<T>(
        &self,
        path: &str,
        operation: impl FnMut(&mut onnx::SessionHandle) -> onnx::SessionRunResult<T>,
    ) -> MlResult<(T, onnx::ProviderUsage)> {
        if path.trim().is_empty() {
            return Err(MlError::InvalidRequest(self.model.missing_path_error()));
        }

        let mut session = self.lock_session();
        self.configure_locked(&mut session, path);
        session
            .as_mut()
            .expect("non-empty model path must configure a session")
            .run(operation)
    }

    fn configure_locked(&self, session: &mut Option<onnx::OnnxSession>, path: &str) {
        if session
            .as_ref()
            .is_some_and(|session| session.model_path() == path)
        {
            return;
        }
        *session = Some(onnx::OnnxSession::new(
            path,
            self.model.namespace(),
            default_execution_mode(self.model),
        ));
    }
}

#[derive(Debug)]
struct MlRuntime {
    models: [ModelRuntime; Model::COUNT],
}

static GLOBAL_RUNTIME: Lazy<MlRuntime> = Lazy::new(MlRuntime::new);

impl MlRuntime {
    fn new() -> Self {
        Self {
            models: Model::ALL.map(ModelRuntime::new),
        }
    }

    fn model(&self, model: Model) -> &ModelRuntime {
        &self.models[model.index()]
    }

    fn configure_requested_models(&self, model_paths: &ModelPaths) {
        for model in Model::ALL {
            self.model(model)
                .configure_if_requested(model_paths.get(model));
        }
    }

    fn prepare_indexing_models(&self, model_paths: &ModelPaths) {
        for model in Model::INDEXING {
            self.model(model)
                .sync_indexing_residency(model_paths.get(model));
        }
    }

    fn release_indexing_models(&self) {
        for model in Model::INDEXING {
            self.model(model).release_residency();
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
            .model(model)
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
    fn configure_requested_models_preserves_unrequested_models() {
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
            runtime.model(Model::ClipText).snapshot().path,
            "clip_text.onnx"
        );
        assert_eq!(
            runtime.model(Model::FaceDetection).snapshot().path,
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
            runtime.model(Model::ClipText).snapshot(),
            ModelRuntimeSnapshot {
                path: "clip_text.onnx".to_string(),
                session_loaded: false,
                has_load_state: false,
            }
        );
        assert_eq!(
            runtime.model(Model::FaceDetection).snapshot(),
            ModelRuntimeSnapshot {
                path: "face.onnx".to_string(),
                session_loaded: false,
                has_load_state: false,
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
            runtime.model(Model::FaceDetection).snapshot(),
            unloaded_snapshot("face.onnx")
        );
        assert_eq!(
            runtime.model(Model::FaceEmbedding).snapshot(),
            unloaded_snapshot("embed.onnx")
        );
        assert_eq!(
            runtime.model(Model::ClipImage).snapshot(),
            unloaded_snapshot("clip.onnx")
        );
    }

    #[test]
    fn disabling_an_indexing_model_clears_its_runtime() {
        let runtime = MlRuntime::new();
        runtime.prepare_indexing_models(&ModelPaths {
            clip_image: "clip.onnx".to_string(),
            ..ModelPaths::default()
        });

        runtime.prepare_indexing_models(&ModelPaths::default());

        assert_eq!(
            runtime.model(Model::ClipImage).snapshot(),
            unloaded_snapshot("")
        );
    }

    #[test]
    fn changing_model_path_discards_stale_session_state() {
        let runtime = MlRuntime::new();
        let model_runtime = runtime.model(Model::ClipText);
        let first_path = "first.onnx";
        let second_path = "second.onnx";
        model_runtime.configure_if_requested(first_path);
        model_runtime
            .lock_session()
            .as_mut()
            .unwrap()
            .initialize_load_state();

        assert!(model_runtime.snapshot().has_load_state);

        model_runtime.configure_if_requested(first_path);

        assert!(model_runtime.snapshot().has_load_state);

        model_runtime.configure_if_requested(second_path);

        assert_eq!(model_runtime.snapshot(), unloaded_snapshot(second_path));
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

    fn unloaded_snapshot(path: &str) -> ModelRuntimeSnapshot {
        ModelRuntimeSnapshot {
            path: path.to_string(),
            session_loaded: false,
            has_load_state: false,
        }
    }
}
