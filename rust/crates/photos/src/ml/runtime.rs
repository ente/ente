use std::{
    cell::Cell,
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
pub(crate) fn rt_log(msg: &str) {
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

#[derive(Debug)]
struct ModelSlotState {
    path: String,
    fallback_execution_mode: Option<onnx::ExecutionMode>,
    execution_provider: Option<onnx::ExecutionProvider>,
    pin_count: usize,
    session: Option<Session>,
}

#[derive(Debug)]
struct ModelSlot {
    default_execution_mode: onnx::ExecutionMode,
    coreml_cache_namespace: &'static str,
    state: Mutex<ModelSlotState>,
}

pub(crate) struct ModelSessionGuard<'a> {
    state: MutexGuard<'a, ModelSlotState>,
}

/// Which accelerated execution providers were behind the sessions used through
/// a [`MlRuntimeView`]. ORed over every session guard the view hands out, so a
/// result produced through the view can be attributed to the providers that
/// actually computed (any part of) it.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) struct UsedProviders {
    pub(crate) coreml: bool,
    pub(crate) webgpu: bool,
}

impl UsedProviders {
    fn record(&mut self, provider: onnx::ExecutionProvider) {
        match provider {
            onnx::ExecutionProvider::CoreMl => self.coreml = true,
            onnx::ExecutionProvider::WebGpu => self.webgpu = true,
            onnx::ExecutionProvider::Xnnpack | onnx::ExecutionProvider::Cpu => {}
        }
    }
}

pub(crate) struct MlRuntimeView<'a> {
    runtime: &'a MlRuntime,
    model_paths: &'a ModelPaths,
    used_providers: Cell<UsedProviders>,
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
    fn new(
        default_execution_mode: onnx::ExecutionMode,
        coreml_cache_namespace: &'static str,
    ) -> Self {
        Self {
            default_execution_mode,
            coreml_cache_namespace,
            state: Mutex::new(ModelSlotState {
                path: String::new(),
                fallback_execution_mode: None,
                execution_provider: None,
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

    fn advance_provider_fallback_if_configured(&self, path: &str) -> bool {
        if path.trim().is_empty() {
            return false;
        }

        let mut state = self.lock_state();
        if state.path != path {
            return false;
        }
        let current_mode = state
            .fallback_execution_mode
            .unwrap_or(self.default_execution_mode);
        let Some(fallback_mode) = current_mode.fallback() else {
            return false;
        };

        state.fallback_execution_mode = Some(fallback_mode);
        state.execution_provider = None;
        state.session = None;
        true
    }

    fn session_guard_for(&self, path: &str, error_msg: &str) -> MlResult<ModelSessionGuard<'_>> {
        if path.trim().is_empty() {
            return Err(MlError::InvalidRequest(error_msg.to_string()));
        }

        let mut state = self.lock_state();
        Self::set_config_locked(&mut state, path);
        self.ensure_loaded_locked(&mut state, error_msg)?;
        Ok(ModelSessionGuard { state })
    }

    fn set_config_locked(state: &mut ModelSlotState, path: &str) {
        if state.path == path {
            return;
        }
        state.path = path.to_string();
        state.fallback_execution_mode = None;
        state.execution_provider = None;
        state.session = None;
    }

    fn clear_transient_runtime_state_locked(state: &mut ModelSlotState) {
        state.fallback_execution_mode = None;
        state.execution_provider = None;
        state.session = None;
    }

    fn reset_slot_locked(state: &mut ModelSlotState) {
        state.path.clear();
        state.pin_count = 0;
        Self::clear_transient_runtime_state_locked(state);
    }

    fn effective_execution_mode(&self, state: &ModelSlotState) -> onnx::ExecutionMode {
        state
            .fallback_execution_mode
            .unwrap_or(self.default_execution_mode)
    }

    fn ensure_loaded_locked(&self, state: &mut ModelSlotState, error_msg: &str) -> MlResult<()> {
        if state.path.trim().is_empty() {
            return Err(MlError::InvalidRequest(error_msg.to_string()));
        }
        if state.session.is_some() {
            return Ok(());
        }

        let execution_mode = self.effective_execution_mode(state);
        let model_name = state.path.rsplit('/').next().unwrap_or(&state.path);
        rt_log(&format!(
            "loading {model_name} with {execution_mode:?} execution"
        ));
        let t = std::time::Instant::now();
        let (session, execution_provider) =
            onnx::build_session(&state.path, execution_mode, self.coreml_cache_namespace)?;
        rt_log(&format!("loaded {model_name} in {:?}", t.elapsed()));
        state.execution_provider = Some(execution_provider);
        state.session = Some(session);
        Ok(())
    }
}

impl ModelSessionGuard<'_> {
    fn execution_provider(&self) -> onnx::ExecutionProvider {
        self.state
            .execution_provider
            .expect("a loaded session must record its execution provider")
    }
}

#[derive(Debug)]
struct MlRuntime {
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

impl MlRuntime {
    fn new() -> Self {
        let platform_default = onnx::ExecutionMode::PlatformDefault;
        let cpu_only = onnx::ExecutionMode::CpuOnly;

        Self {
            face_detection: ModelSlot::new(platform_default, "face-detection"),
            face_embedding: ModelSlot::new(platform_default, "face-embedding"),
            clip_image: ModelSlot::new(platform_default, "clip-image"),
            // The quantized CLIP text graph is heavily partitioned by both
            // CoreML and WebGPU, making their mixed CPU/GPU execution slower
            // than running the complete model on CPU.
            clip_text: ModelSlot::new(cpu_only, "clip-text"),
            // Pet models previously had device-specific FP16 driver failures.
            // Keep them CPU-only until they have been validated on the GPU
            // execution providers of supported iOS and Android devices.
            pet_face_detection: ModelSlot::new(cpu_only, "pet-face-detection"),
            pet_face_embedding_dog: ModelSlot::new(cpu_only, "pet-face-embedding-dog"),
            pet_face_embedding_cat: ModelSlot::new(cpu_only, "pet-face-embedding-cat"),
            pet_body_detection: ModelSlot::new(cpu_only, "pet-body-detection"),
            pet_body_embedding_dog: ModelSlot::new(cpu_only, "pet-body-embedding-dog"),
            pet_body_embedding_cat: ModelSlot::new(cpu_only, "pet-body-embedding-cat"),
        }
    }

    fn configure_requested_models(&self, model_paths: &ModelPaths) {
        self.face_detection
            .configure_if_requested(&model_paths.face_detection);
        self.face_embedding
            .configure_if_requested(&model_paths.face_embedding);
        self.clip_image
            .configure_if_requested(&model_paths.clip_image);
        self.clip_text
            .configure_if_requested(&model_paths.clip_text);
        self.pet_face_detection
            .configure_if_requested(&model_paths.pet_face_detection);
        self.pet_face_embedding_dog
            .configure_if_requested(&model_paths.pet_face_embedding_dog);
        self.pet_face_embedding_cat
            .configure_if_requested(&model_paths.pet_face_embedding_cat);
        self.pet_body_detection
            .configure_if_requested(&model_paths.pet_body_detection);
        self.pet_body_embedding_dog
            .configure_if_requested(&model_paths.pet_body_embedding_dog);
        self.pet_body_embedding_cat
            .configure_if_requested(&model_paths.pet_body_embedding_cat);
    }

    fn prepare_indexing_models(&self, model_paths: &ModelPaths) {
        self.face_detection
            .sync_indexing_residency(&model_paths.face_detection);
        self.face_embedding
            .sync_indexing_residency(&model_paths.face_embedding);
        self.clip_image
            .sync_indexing_residency(&model_paths.clip_image);
        self.pet_face_detection
            .sync_indexing_residency(&model_paths.pet_face_detection);
        self.pet_face_embedding_dog
            .sync_indexing_residency(&model_paths.pet_face_embedding_dog);
        self.pet_face_embedding_cat
            .sync_indexing_residency(&model_paths.pet_face_embedding_cat);
        self.pet_body_detection
            .sync_indexing_residency(&model_paths.pet_body_detection);
        self.pet_body_embedding_dog
            .sync_indexing_residency(&model_paths.pet_body_embedding_dog);
        self.pet_body_embedding_cat
            .sync_indexing_residency(&model_paths.pet_body_embedding_cat);
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

    fn advance_provider_fallbacks_for_requested_models(&self, model_paths: &ModelPaths) -> bool {
        let mut advanced = false;
        advanced |= self
            .face_detection
            .advance_provider_fallback_if_configured(&model_paths.face_detection);
        advanced |= self
            .face_embedding
            .advance_provider_fallback_if_configured(&model_paths.face_embedding);
        advanced |= self
            .clip_image
            .advance_provider_fallback_if_configured(&model_paths.clip_image);
        advanced |= self
            .clip_text
            .advance_provider_fallback_if_configured(&model_paths.clip_text);
        advanced |= self
            .pet_face_detection
            .advance_provider_fallback_if_configured(&model_paths.pet_face_detection);
        advanced |= self
            .pet_face_embedding_dog
            .advance_provider_fallback_if_configured(&model_paths.pet_face_embedding_dog);
        advanced |= self
            .pet_face_embedding_cat
            .advance_provider_fallback_if_configured(&model_paths.pet_face_embedding_cat);
        advanced |= self
            .pet_body_detection
            .advance_provider_fallback_if_configured(&model_paths.pet_body_detection);
        advanced |= self
            .pet_body_embedding_dog
            .advance_provider_fallback_if_configured(&model_paths.pet_body_embedding_dog);
        advanced |= self
            .pet_body_embedding_cat
            .advance_provider_fallback_if_configured(&model_paths.pet_body_embedding_cat);
        advanced
    }

    fn view<'a>(&'a self, model_paths: &'a ModelPaths) -> MlRuntimeView<'a> {
        MlRuntimeView {
            runtime: self,
            model_paths,
            used_providers: Cell::new(UsedProviders::default()),
        }
    }
}

impl<'a> MlRuntimeView<'a> {
    /// The accelerated providers behind every session used through this view
    /// so far (since creation or the last [`Self::reset_used_providers`]).
    pub(crate) fn used_providers(&self) -> UsedProviders {
        self.used_providers.get()
    }

    fn reset_used_providers(&self) {
        self.used_providers.set(UsedProviders::default());
    }

    fn tracked_session(
        &self,
        slot: &'a ModelSlot,
        path: &str,
        error_msg: &str,
    ) -> MlResult<ModelSessionGuard<'a>> {
        let guard = slot.session_guard_for(path, error_msg)?;
        let mut used = self.used_providers.get();
        used.record(guard.execution_provider());
        self.used_providers.set(used);
        Ok(guard)
    }

    pub(crate) fn face_detection_session(&self) -> MlResult<ModelSessionGuard<'_>> {
        self.tracked_session(
            &self.runtime.face_detection,
            &self.model_paths.face_detection,
            "missing model path: faceDetectionModelPath is required when runFaces is true",
        )
    }

    pub(crate) fn face_embedding_session(&self) -> MlResult<ModelSessionGuard<'_>> {
        self.tracked_session(
            &self.runtime.face_embedding,
            &self.model_paths.face_embedding,
            "missing model path: faceEmbeddingModelPath is required when runFaces is true",
        )
    }

    pub(crate) fn clip_image_session(&self) -> MlResult<ModelSessionGuard<'_>> {
        self.tracked_session(
            &self.runtime.clip_image,
            &self.model_paths.clip_image,
            "missing model path: clipImageModelPath is required when runClip is true",
        )
    }

    pub(crate) fn clip_text_session(&self) -> MlResult<ModelSessionGuard<'_>> {
        self.tracked_session(
            &self.runtime.clip_text,
            &self.model_paths.clip_text,
            "missing model path: clipTextModelPath is required when running clip text",
        )
    }

    pub(crate) fn pet_face_detection_session(&self) -> MlResult<ModelSessionGuard<'_>> {
        self.tracked_session(
            &self.runtime.pet_face_detection,
            &self.model_paths.pet_face_detection,
            "missing model path: petFaceDetectionModelPath is required when runPets is true",
        )
    }

    pub(crate) fn pet_face_embedding_dog_session(&self) -> MlResult<ModelSessionGuard<'_>> {
        self.tracked_session(
            &self.runtime.pet_face_embedding_dog,
            &self.model_paths.pet_face_embedding_dog,
            "missing model path: petFaceEmbeddingDogModelPath is required",
        )
    }

    pub(crate) fn pet_face_embedding_cat_session(&self) -> MlResult<ModelSessionGuard<'_>> {
        self.tracked_session(
            &self.runtime.pet_face_embedding_cat,
            &self.model_paths.pet_face_embedding_cat,
            "missing model path: petFaceEmbeddingCatModelPath is required",
        )
    }

    pub(crate) fn pet_body_detection_session(&self) -> MlResult<ModelSessionGuard<'_>> {
        self.tracked_session(
            &self.runtime.pet_body_detection,
            &self.model_paths.pet_body_detection,
            "missing model path: petBodyDetectionModelPath is required when runPets is true",
        )
    }

    pub(crate) fn pet_body_embedding_dog_session(&self) -> MlResult<ModelSessionGuard<'_>> {
        self.tracked_session(
            &self.runtime.pet_body_embedding_dog,
            &self.model_paths.pet_body_embedding_dog,
            "missing model path: petBodyEmbeddingDogModelPath is required",
        )
    }

    pub(crate) fn pet_body_embedding_cat_session(&self) -> MlResult<ModelSessionGuard<'_>> {
        self.tracked_session(
            &self.runtime.pet_body_embedding_cat,
            &self.model_paths.pet_body_embedding_cat,
            "missing model path: petBodyEmbeddingCatModelPath is required",
        )
    }
}

pub(crate) fn ensure_runtime(model_paths: &ModelPaths) {
    GLOBAL_RUNTIME.configure_requested_models(model_paths);
}

pub(crate) fn prepare_runtime(model_paths: &ModelPaths) {
    GLOBAL_RUNTIME.prepare_indexing_models(model_paths);
}

pub(crate) fn with_runtime<F, R>(model_paths: &ModelPaths, func: F) -> MlResult<R>
where
    F: for<'a> Fn(&MlRuntimeView<'a>) -> MlResult<R>,
{
    ensure_runtime(model_paths);

    let runtime_view = GLOBAL_RUNTIME.view(model_paths);
    let mut result = func(&runtime_view);
    loop {
        match result {
            Ok(value) => return Ok(value),
            Err(error) => {
                if !should_retry_execution_provider_runtime(&error)
                    || !GLOBAL_RUNTIME.advance_provider_fallbacks_for_requested_models(model_paths)
                {
                    return Err(error);
                }

                crate::ml::events::record(
                    crate::ml::events::Severity::Warning,
                    format!(
                        "execution provider failed, retrying with the next provider fallback: \
                         {error}"
                    ),
                );
                // Drop provider attributions from the failed attempt; only the
                // retry that produces the returned value should count.
                runtime_view.reset_used_providers();
                result = func(&runtime_view);
            }
        }
    }
}

pub(crate) fn release_runtime() {
    GLOBAL_RUNTIME.release_indexing_models();
}

fn should_retry_execution_provider_runtime(error: &MlError) -> bool {
    cfg!(any(target_os = "ios", target_os = "android")) && is_execution_provider_failure(error)
}

fn is_execution_provider_failure(error: &MlError) -> bool {
    let MlError::Ort(message) = error else {
        return false;
    };
    let normalized = message.to_ascii_lowercase();
    normalized.contains("executionprovider")
        || normalized.contains("unknown allocation device")
        || normalized.contains("xnnpackexecutionprovider")
        || normalized.contains("coremlexecutionprovider")
        || normalized.contains("webgpu")
        || normalized.contains("wgpu")
        || normalized.contains("dawn")
        || normalized.contains("vulkan")
        || normalized.contains("vk_error")
        || normalized.contains("non-finite")
        || normalized.contains("ep error")
}

#[cfg(test)]
mod tests {
    use super::*;

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

        runtime.configure_requested_models(&ModelPaths {
            clip_text: "clip_text.onnx".to_string(),
            ..empty_paths()
        });

        runtime.configure_requested_models(&ModelPaths {
            face_detection: "face.onnx".to_string(),
            ..empty_paths()
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
            clip_text.fallback_execution_mode = Some(onnx::ExecutionMode::CpuOnly);
        }
        {
            let mut face_detection = runtime.face_detection.lock_state();
            face_detection.path = "face.onnx".to_string();
            face_detection.pin_count = 1;
            face_detection.fallback_execution_mode = Some(onnx::ExecutionMode::CpuOnly);
        }

        runtime.release_indexing_models();

        let clip_text = runtime.clip_text.lock_state();
        assert_eq!(clip_text.path, "clip_text.onnx");
        assert_eq!(clip_text.pin_count, 0);
        assert_eq!(
            clip_text.fallback_execution_mode,
            Some(onnx::ExecutionMode::CpuOnly)
        );

        let face_detection = runtime.face_detection.lock_state();
        assert_eq!(face_detection.pin_count, 0);
        assert_eq!(face_detection.fallback_execution_mode, None);
    }

    #[test]
    fn prepare_indexing_models_pins_without_loading_sessions() {
        let runtime = MlRuntime::new();

        runtime.prepare_indexing_models(&ModelPaths {
            face_detection: "face.onnx".to_string(),
            face_embedding: "embed.onnx".to_string(),
            clip_image: "clip.onnx".to_string(),
            ..empty_paths()
        });

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
        let slot = ModelSlot::new(onnx::ExecutionMode::PlatformDefault, "test-model");

        {
            let mut state = slot.lock_state();
            state.path = "pet.onnx".to_string();
            state.pin_count = 1;
            state.fallback_execution_mode = Some(onnx::ExecutionMode::CpuOnly);
        }

        slot.sync_indexing_residency("");

        let state = slot.lock_state();
        assert!(state.path.is_empty());
        assert_eq!(state.pin_count, 0);
        assert_eq!(state.fallback_execution_mode, None);
        assert!(state.session.is_none());
    }

    #[test]
    fn release_residency_resets_transient_cpu_fallback_for_any_slot() {
        let slot = ModelSlot::new(onnx::ExecutionMode::PlatformDefault, "test-model");

        {
            let mut state = slot.lock_state();
            state.path = "clip_text.onnx".to_string();
            state.pin_count = 1;
            state.fallback_execution_mode = Some(onnx::ExecutionMode::CpuOnly);
        }

        slot.release_residency();

        let state = slot.lock_state();
        assert_eq!(state.pin_count, 0);
        assert_eq!(state.fallback_execution_mode, None);
        assert!(state.session.is_none());
    }

    #[test]
    fn execution_provider_fallback_order_matches_platform_policy() {
        #[cfg(target_os = "android")]
        {
            assert_eq!(
                onnx::ExecutionMode::PlatformDefault.fallback(),
                Some(onnx::ExecutionMode::Xnnpack)
            );
            assert_eq!(
                onnx::ExecutionMode::Xnnpack.fallback(),
                Some(onnx::ExecutionMode::CpuOnly)
            );
        }
        #[cfg(not(target_os = "android"))]
        assert_eq!(
            onnx::ExecutionMode::PlatformDefault.fallback(),
            Some(onnx::ExecutionMode::CpuOnly)
        );
        assert_eq!(onnx::ExecutionMode::CpuOnly.fallback(), None);
    }

    #[test]
    fn model_execution_modes_match_platform_policy() {
        let runtime = MlRuntime::new();
        // Pet models stay CPU-only on every platform until they are
        // validated on the GPU execution providers.
        let expected_pet_mode = onnx::ExecutionMode::CpuOnly;

        assert_eq!(
            runtime.face_detection.default_execution_mode,
            onnx::ExecutionMode::PlatformDefault
        );
        assert_eq!(
            runtime.face_embedding.default_execution_mode,
            onnx::ExecutionMode::PlatformDefault
        );
        assert_eq!(
            runtime.clip_image.default_execution_mode,
            onnx::ExecutionMode::PlatformDefault
        );
        assert_eq!(
            runtime.clip_text.default_execution_mode,
            onnx::ExecutionMode::CpuOnly
        );
        assert_eq!(
            runtime.pet_face_detection.default_execution_mode,
            expected_pet_mode
        );
        assert_eq!(
            runtime.pet_face_embedding_dog.default_execution_mode,
            expected_pet_mode
        );
        assert_eq!(
            runtime.pet_face_embedding_cat.default_execution_mode,
            expected_pet_mode
        );
        assert_eq!(
            runtime.pet_body_detection.default_execution_mode,
            expected_pet_mode
        );
        assert_eq!(
            runtime.pet_body_embedding_dog.default_execution_mode,
            expected_pet_mode
        );
        assert_eq!(
            runtime.pet_body_embedding_cat.default_execution_mode,
            expected_pet_mode
        );
    }
}
