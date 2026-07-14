use std::{
    ops::{Deref, DerefMut},
    sync::{Mutex, MutexGuard},
};

use once_cell::sync::Lazy;
use ort::session::Session;

use crate::ml::{
    error::{MlError, MlResult},
    onnx,
};

/// Log to Android logcat or stderr.
fn rt_log(msg: &str) {
    #[cfg(target_os = "android")]
    {
        unsafe extern "C" {
            unsafe fn __android_log_write(
                prio: std::ffi::c_int,
                tag: *const std::ffi::c_char,
                text: *const std::ffi::c_char,
            ) -> std::ffi::c_int;
        }
        use std::ffi::CString;
        let tag = CString::new("ml_rt").unwrap();
        let cmsg = CString::new(msg).unwrap_or_else(|_| CString::new("(invalid)").unwrap());
        unsafe {
            __android_log_write(4, tag.as_ptr(), cmsg.as_ptr());
        }
    }
    #[cfg(not(target_os = "android"))]
    {
        eprintln!("[ml][rt] {msg}");
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ExecutionProviderPolicy {
    pub prefer_coreml: bool,
    pub prefer_nnapi: bool,
    pub prefer_xnnpack: bool,
    pub allow_cpu_fallback: bool,
}

impl Default for ExecutionProviderPolicy {
    fn default() -> Self {
        Self {
            prefer_coreml: true,
            prefer_nnapi: true,
            prefer_xnnpack: false,
            allow_cpu_fallback: true,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ModelPaths {
    pub face_detection: String,
    pub face_embedding: String,
    pub clip_image: String,
    pub clip_text: String,
    pub pet_face_detection: String,
    pub pet_face_embedding_dog: String,
    pub pet_face_embedding_cat: String,
    pub pet_body_detection: String,
    pub pet_body_embedding_dog: String,
    pub pet_body_embedding_cat: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MlRuntimeConfig {
    pub model_paths: ModelPaths,
    pub provider_policy: ExecutionProviderPolicy,
}

#[derive(Debug)]
struct ModelSlotState {
    path: String,
    requested_policy: ExecutionProviderPolicy,
    fell_back_to_cpu: bool,
    pin_count: usize,
    session: Option<Session>,
}

#[derive(Debug)]
struct ModelSlot {
    state: Mutex<ModelSlotState>,
}

pub struct ModelSessionGuard<'a> {
    state: MutexGuard<'a, ModelSlotState>,
}

pub struct MlRuntimeView<'a> {
    runtime: &'a MlRuntime,
    config: &'a MlRuntimeConfig,
}

impl Deref for ModelSessionGuard<'_> {
    type Target = Session;

    fn deref(&self) -> &Self::Target {
        self.state
            .session
            .as_ref()
            .expect("session must be loaded before creating ModelSessionGuard")
    }
}

impl DerefMut for ModelSessionGuard<'_> {
    fn deref_mut(&mut self) -> &mut Self::Target {
        self.state
            .session
            .as_mut()
            .expect("session must be loaded before creating ModelSessionGuard")
    }
}

impl ModelSlot {
    fn new() -> Self {
        Self {
            state: Mutex::new(ModelSlotState {
                path: String::new(),
                requested_policy: ExecutionProviderPolicy::default(),
                fell_back_to_cpu: false,
                pin_count: 0,
                session: None,
            }),
        }
    }

    fn lock_state(&self) -> MutexGuard<'_, ModelSlotState> {
        match self.state.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        }
    }

    fn configure_if_requested(&self, path: &str, policy: &ExecutionProviderPolicy) {
        if path.trim().is_empty() {
            return;
        }
        let mut state = self.lock_state();
        Self::set_config_locked(&mut state, path, policy);
    }

    fn sync_indexing_residency(&self, path: &str, policy: &ExecutionProviderPolicy) {
        let mut state = self.lock_state();
        if path.trim().is_empty() {
            Self::reset_slot_locked(&mut state);
            return;
        }

        Self::set_config_locked(&mut state, path, policy);
        state.pin_count = 1;
    }

    fn release_residency(&self) {
        let mut state = self.lock_state();
        if state.pin_count > 0 {
            state.pin_count -= 1;
        }
        if state.pin_count == 0 {
            Self::clear_transient_runtime_state_locked(&mut state);
        }
    }

    fn force_cpu_fallback_if_configured(&self, path: &str) {
        if path.trim().is_empty() {
            return;
        }

        let mut state = self.lock_state();
        if state.path != path {
            return;
        }
        if !state.requested_policy.allow_cpu_fallback {
            return;
        }
        if cpu_only_policy(&state.requested_policy) == state.requested_policy
            || state.fell_back_to_cpu
        {
            return;
        }

        state.fell_back_to_cpu = true;
        state.session = None;
    }

    fn session_guard_for(
        &self,
        path: &str,
        policy: &ExecutionProviderPolicy,
        error_msg: &str,
    ) -> MlResult<ModelSessionGuard<'_>> {
        if path.trim().is_empty() {
            return Err(MlError::InvalidRequest(error_msg.to_string()));
        }

        let mut state = self.lock_state();
        Self::set_config_locked(&mut state, path, policy);
        Self::ensure_loaded_locked(&mut state, error_msg)?;
        Ok(ModelSessionGuard { state })
    }

    fn set_config_locked(state: &mut ModelSlotState, path: &str, policy: &ExecutionProviderPolicy) {
        if state.path == path && state.requested_policy == *policy {
            return;
        }
        state.path = path.to_string();
        state.requested_policy = policy.clone();
        state.fell_back_to_cpu = false;
        state.session = None;
    }

    fn clear_transient_runtime_state_locked(state: &mut ModelSlotState) {
        state.fell_back_to_cpu = false;
        state.session = None;
    }

    fn reset_slot_locked(state: &mut ModelSlotState) {
        state.path.clear();
        state.pin_count = 0;
        Self::clear_transient_runtime_state_locked(state);
    }

    fn ensure_loaded_locked(state: &mut ModelSlotState, error_msg: &str) -> MlResult<()> {
        if state.path.trim().is_empty() {
            return Err(MlError::InvalidRequest(error_msg.to_string()));
        }
        if state.session.is_some() {
            return Ok(());
        }

        let model_name = state.path.rsplit('/').next().unwrap_or(&state.path);
        rt_log(&format!("loading {model_name}"));
        let t = std::time::Instant::now();
        let session = onnx::build_session(&state.path, &effective_policy(state))?;
        rt_log(&format!("loaded {model_name} in {:?}", t.elapsed()));
        state.session = Some(session);
        Ok(())
    }
}

fn effective_policy(state: &ModelSlotState) -> ExecutionProviderPolicy {
    if state.fell_back_to_cpu && state.requested_policy.allow_cpu_fallback {
        cpu_only_policy(&state.requested_policy)
    } else {
        state.requested_policy.clone()
    }
}

fn cpu_only_policy(policy: &ExecutionProviderPolicy) -> ExecutionProviderPolicy {
    ExecutionProviderPolicy {
        prefer_coreml: false,
        prefer_nnapi: false,
        prefer_xnnpack: false,
        allow_cpu_fallback: policy.allow_cpu_fallback,
    }
}

#[derive(Debug)]
pub struct MlRuntime {
    face_detection: ModelSlot,
    face_embedding: ModelSlot,
    clip_image: ModelSlot,
    clip_text: ModelSlot,
    pet_face_detection: ModelSlot,
    pet_face_embedding_dog: ModelSlot,
    pet_face_embedding_cat: ModelSlot,
    pet_body_detection: ModelSlot,
    pet_body_embedding_dog: ModelSlot,
    pet_body_embedding_cat: ModelSlot,
}

static GLOBAL_RUNTIME: Lazy<MlRuntime> = Lazy::new(MlRuntime::new);

fn pet_policy() -> ExecutionProviderPolicy {
    // Pet models use CPU-only to avoid NNAPI/CoreML driver issues with
    // FP16 models on some devices.
    // TODO: Make pet EP policy configurable so hardware acceleration can be
    // re-enabled once driver issues are resolved.
    ExecutionProviderPolicy {
        prefer_coreml: false,
        prefer_nnapi: false,
        prefer_xnnpack: false,
        allow_cpu_fallback: true,
    }
}

impl MlRuntime {
    fn new() -> Self {
        Self {
            face_detection: ModelSlot::new(),
            face_embedding: ModelSlot::new(),
            clip_image: ModelSlot::new(),
            clip_text: ModelSlot::new(),
            pet_face_detection: ModelSlot::new(),
            pet_face_embedding_dog: ModelSlot::new(),
            pet_face_embedding_cat: ModelSlot::new(),
            pet_body_detection: ModelSlot::new(),
            pet_body_embedding_dog: ModelSlot::new(),
            pet_body_embedding_cat: ModelSlot::new(),
        }
    }

    fn configure_requested_models(&self, config: &MlRuntimeConfig) {
        let shared_policy = &config.provider_policy;
        let pet_policy = pet_policy();

        self.face_detection
            .configure_if_requested(&config.model_paths.face_detection, shared_policy);
        self.face_embedding
            .configure_if_requested(&config.model_paths.face_embedding, shared_policy);
        self.clip_image
            .configure_if_requested(&config.model_paths.clip_image, shared_policy);
        self.clip_text
            .configure_if_requested(&config.model_paths.clip_text, shared_policy);
        self.pet_face_detection
            .configure_if_requested(&config.model_paths.pet_face_detection, &pet_policy);
        self.pet_face_embedding_dog
            .configure_if_requested(&config.model_paths.pet_face_embedding_dog, &pet_policy);
        self.pet_face_embedding_cat
            .configure_if_requested(&config.model_paths.pet_face_embedding_cat, &pet_policy);
        self.pet_body_detection
            .configure_if_requested(&config.model_paths.pet_body_detection, &pet_policy);
        self.pet_body_embedding_dog
            .configure_if_requested(&config.model_paths.pet_body_embedding_dog, &pet_policy);
        self.pet_body_embedding_cat
            .configure_if_requested(&config.model_paths.pet_body_embedding_cat, &pet_policy);
    }

    fn prepare_indexing_models(&self, config: &MlRuntimeConfig) -> MlResult<()> {
        let shared_policy = &config.provider_policy;
        let pet_policy = pet_policy();

        self.face_detection
            .sync_indexing_residency(&config.model_paths.face_detection, shared_policy);
        self.face_embedding
            .sync_indexing_residency(&config.model_paths.face_embedding, shared_policy);
        self.clip_image
            .sync_indexing_residency(&config.model_paths.clip_image, shared_policy);
        self.pet_face_detection
            .sync_indexing_residency(&config.model_paths.pet_face_detection, &pet_policy);
        self.pet_face_embedding_dog
            .sync_indexing_residency(&config.model_paths.pet_face_embedding_dog, &pet_policy);
        self.pet_face_embedding_cat
            .sync_indexing_residency(&config.model_paths.pet_face_embedding_cat, &pet_policy);
        self.pet_body_detection
            .sync_indexing_residency(&config.model_paths.pet_body_detection, &pet_policy);
        self.pet_body_embedding_dog
            .sync_indexing_residency(&config.model_paths.pet_body_embedding_dog, &pet_policy);
        self.pet_body_embedding_cat
            .sync_indexing_residency(&config.model_paths.pet_body_embedding_cat, &pet_policy);

        Ok(())
    }

    fn release_indexing_models(&self) {
        self.face_detection.release_residency();
        self.face_embedding.release_residency();
        self.clip_image.release_residency();
        self.pet_face_detection.release_residency();
        self.pet_face_embedding_dog.release_residency();
        self.pet_face_embedding_cat.release_residency();
        self.pet_body_detection.release_residency();
        self.pet_body_embedding_dog.release_residency();
        self.pet_body_embedding_cat.release_residency();
    }

    fn force_cpu_only_for_requested_models(&self, config: &MlRuntimeConfig) {
        self.face_detection
            .force_cpu_fallback_if_configured(&config.model_paths.face_detection);
        self.face_embedding
            .force_cpu_fallback_if_configured(&config.model_paths.face_embedding);
        self.clip_image
            .force_cpu_fallback_if_configured(&config.model_paths.clip_image);
        self.clip_text
            .force_cpu_fallback_if_configured(&config.model_paths.clip_text);
        self.pet_face_detection
            .force_cpu_fallback_if_configured(&config.model_paths.pet_face_detection);
        self.pet_face_embedding_dog
            .force_cpu_fallback_if_configured(&config.model_paths.pet_face_embedding_dog);
        self.pet_face_embedding_cat
            .force_cpu_fallback_if_configured(&config.model_paths.pet_face_embedding_cat);
        self.pet_body_detection
            .force_cpu_fallback_if_configured(&config.model_paths.pet_body_detection);
        self.pet_body_embedding_dog
            .force_cpu_fallback_if_configured(&config.model_paths.pet_body_embedding_dog);
        self.pet_body_embedding_cat
            .force_cpu_fallback_if_configured(&config.model_paths.pet_body_embedding_cat);
    }

    fn view<'a>(&'a self, config: &'a MlRuntimeConfig) -> MlRuntimeView<'a> {
        MlRuntimeView {
            runtime: self,
            config,
        }
    }
}

impl MlRuntimeView<'_> {
    pub fn face_detection_session(&self) -> MlResult<ModelSessionGuard<'_>> {
        self.runtime.face_detection.session_guard_for(
            &self.config.model_paths.face_detection,
            &self.config.provider_policy,
            "missing model path: faceDetectionModelPath is required when runFaces is true",
        )
    }

    pub fn face_embedding_session(&self) -> MlResult<ModelSessionGuard<'_>> {
        self.runtime.face_embedding.session_guard_for(
            &self.config.model_paths.face_embedding,
            &self.config.provider_policy,
            "missing model path: faceEmbeddingModelPath is required when runFaces is true",
        )
    }

    pub fn clip_image_session(&self) -> MlResult<ModelSessionGuard<'_>> {
        self.runtime.clip_image.session_guard_for(
            &self.config.model_paths.clip_image,
            &self.config.provider_policy,
            "missing model path: clipImageModelPath is required when runClip is true",
        )
    }

    pub fn clip_text_session(&self) -> MlResult<ModelSessionGuard<'_>> {
        self.runtime.clip_text.session_guard_for(
            &self.config.model_paths.clip_text,
            &self.config.provider_policy,
            "missing model path: clipTextModelPath is required when running clip text",
        )
    }

    pub fn pet_face_detection_session(&self) -> MlResult<ModelSessionGuard<'_>> {
        self.runtime.pet_face_detection.session_guard_for(
            &self.config.model_paths.pet_face_detection,
            &pet_policy(),
            "missing model path: petFaceDetectionModelPath is required when runPets is true",
        )
    }

    pub fn pet_face_embedding_dog_session(&self) -> MlResult<ModelSessionGuard<'_>> {
        self.runtime.pet_face_embedding_dog.session_guard_for(
            &self.config.model_paths.pet_face_embedding_dog,
            &pet_policy(),
            "missing model path: petFaceEmbeddingDogModelPath is required",
        )
    }

    pub fn pet_face_embedding_cat_session(&self) -> MlResult<ModelSessionGuard<'_>> {
        self.runtime.pet_face_embedding_cat.session_guard_for(
            &self.config.model_paths.pet_face_embedding_cat,
            &pet_policy(),
            "missing model path: petFaceEmbeddingCatModelPath is required",
        )
    }

    pub fn pet_body_detection_session(&self) -> MlResult<ModelSessionGuard<'_>> {
        self.runtime.pet_body_detection.session_guard_for(
            &self.config.model_paths.pet_body_detection,
            &pet_policy(),
            "missing model path: petBodyDetectionModelPath is required when runPets is true",
        )
    }

    pub fn pet_body_embedding_dog_session(&self) -> MlResult<ModelSessionGuard<'_>> {
        self.runtime.pet_body_embedding_dog.session_guard_for(
            &self.config.model_paths.pet_body_embedding_dog,
            &pet_policy(),
            "missing model path: petBodyEmbeddingDogModelPath is required",
        )
    }

    pub fn pet_body_embedding_cat_session(&self) -> MlResult<ModelSessionGuard<'_>> {
        self.runtime.pet_body_embedding_cat.session_guard_for(
            &self.config.model_paths.pet_body_embedding_cat,
            &pet_policy(),
            "missing model path: petBodyEmbeddingCatModelPath is required",
        )
    }
}

pub fn ensure_runtime(config: &MlRuntimeConfig) -> MlResult<()> {
    GLOBAL_RUNTIME.configure_requested_models(config);
    Ok(())
}

pub fn prepare_runtime(config: &MlRuntimeConfig) -> MlResult<()> {
    GLOBAL_RUNTIME.prepare_indexing_models(config)
}

pub fn with_runtime<F, R>(config: &MlRuntimeConfig, func: F) -> MlResult<R>
where
    F: for<'a> Fn(&MlRuntimeView<'a>) -> MlResult<R>,
{
    ensure_runtime(config)?;

    let runtime_view = GLOBAL_RUNTIME.view(config);
    let first_result = func(&runtime_view);
    match first_result {
        Ok(result) => Ok(result),
        Err(first_error) => {
            if !should_retry_with_cpu_only_runtime(config, &first_error) {
                return Err(first_error);
            }

            rt_log(&format!(
                "execution provider failed, retrying with CPU-only runtime: {first_error}"
            ));
            GLOBAL_RUNTIME.force_cpu_only_for_requested_models(config);
            let runtime_view = GLOBAL_RUNTIME.view(config);
            func(&runtime_view)
        }
    }
}

pub fn release_runtime() -> MlResult<()> {
    GLOBAL_RUNTIME.release_indexing_models();
    Ok(())
}

fn should_retry_with_cpu_only_runtime(config: &MlRuntimeConfig, error: &MlError) -> bool {
    if !config.provider_policy.allow_cpu_fallback {
        return false;
    }
    if !is_execution_provider_failure(error) {
        return false;
    }
    cpu_only_policy(&config.provider_policy) != config.provider_policy
}

fn is_execution_provider_failure(error: &MlError) -> bool {
    let MlError::Ort(message) = error else {
        return false;
    };
    let normalized = message.to_ascii_lowercase();
    normalized.contains("executionprovider")
        || normalized.contains("unknown allocation device")
        || normalized.contains("xnnpackexecutionprovider")
        || normalized.contains("nnapiexecutionprovider")
        || normalized.contains("coremlexecutionprovider")
        || normalized.contains("ep error")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_policy() -> ExecutionProviderPolicy {
        ExecutionProviderPolicy {
            prefer_coreml: false,
            prefer_nnapi: false,
            prefer_xnnpack: false,
            allow_cpu_fallback: true,
        }
    }

    fn empty_paths() -> ModelPaths {
        ModelPaths {
            face_detection: String::new(),
            face_embedding: String::new(),
            clip_image: String::new(),
            clip_text: String::new(),
            pet_face_detection: String::new(),
            pet_face_embedding_dog: String::new(),
            pet_face_embedding_cat: String::new(),
            pet_body_detection: String::new(),
            pet_body_embedding_dog: String::new(),
            pet_body_embedding_cat: String::new(),
        }
    }

    #[test]
    fn configure_requested_models_preserves_unrequested_slots() {
        let runtime = MlRuntime::new();
        let policy = test_policy();

        runtime.configure_requested_models(&MlRuntimeConfig {
            model_paths: ModelPaths {
                clip_text: "clip_text.onnx".to_string(),
                ..empty_paths()
            },
            provider_policy: policy.clone(),
        });

        runtime.configure_requested_models(&MlRuntimeConfig {
            model_paths: ModelPaths {
                face_detection: "face.onnx".to_string(),
                ..empty_paths()
            },
            provider_policy: policy,
        });

        let clip_text = runtime.clip_text.lock_state();
        assert_eq!(clip_text.path, "clip_text.onnx");
    }

    #[test]
    fn release_indexing_models_keeps_clip_text_state() {
        let runtime = MlRuntime::new();

        {
            let mut clip_text = runtime.clip_text.lock_state();
            clip_text.path = "clip_text.onnx".to_string();
            clip_text.pin_count = 0;
            clip_text.fell_back_to_cpu = true;
        }
        {
            let mut face_detection = runtime.face_detection.lock_state();
            face_detection.path = "face.onnx".to_string();
            face_detection.pin_count = 1;
            face_detection.fell_back_to_cpu = true;
        }

        runtime.release_indexing_models();

        let clip_text = runtime.clip_text.lock_state();
        assert_eq!(clip_text.path, "clip_text.onnx");
        assert_eq!(clip_text.pin_count, 0);
        assert!(clip_text.fell_back_to_cpu);

        let face_detection = runtime.face_detection.lock_state();
        assert_eq!(face_detection.pin_count, 0);
        assert!(!face_detection.fell_back_to_cpu);
    }

    #[test]
    fn prepare_indexing_models_pins_without_loading_sessions() {
        let runtime = MlRuntime::new();

        runtime
            .prepare_indexing_models(&MlRuntimeConfig {
                model_paths: ModelPaths {
                    face_detection: "face.onnx".to_string(),
                    face_embedding: "embed.onnx".to_string(),
                    clip_image: "clip.onnx".to_string(),
                    ..empty_paths()
                },
                provider_policy: test_policy(),
            })
            .unwrap();

        let face_detection = runtime.face_detection.lock_state();
        assert_eq!(face_detection.pin_count, 1);
        assert!(face_detection.session.is_none());

        let face_embedding = runtime.face_embedding.lock_state();
        assert_eq!(face_embedding.pin_count, 1);
        assert!(face_embedding.session.is_none());

        let clip_image = runtime.clip_image.lock_state();
        assert_eq!(clip_image.pin_count, 1);
        assert!(clip_image.session.is_none());
    }

    #[test]
    fn sync_indexing_residency_clears_disabled_slots() {
        let slot = ModelSlot::new();

        {
            let mut state = slot.lock_state();
            state.path = "pet.onnx".to_string();
            state.pin_count = 1;
            state.fell_back_to_cpu = true;
        }

        slot.sync_indexing_residency("", &test_policy());

        let state = slot.lock_state();
        assert!(state.path.is_empty());
        assert_eq!(state.pin_count, 0);
        assert!(!state.fell_back_to_cpu);
        assert!(state.session.is_none());
    }

    #[test]
    fn release_residency_resets_transient_cpu_fallback_for_any_slot() {
        let slot = ModelSlot::new();

        {
            let mut state = slot.lock_state();
            state.path = "clip_text.onnx".to_string();
            state.requested_policy = test_policy();
            state.pin_count = 1;
            state.fell_back_to_cpu = true;
        }

        slot.release_residency();

        let state = slot.lock_state();
        assert_eq!(state.pin_count, 0);
        assert!(!state.fell_back_to_cpu);
        assert!(state.session.is_none());
    }
}
