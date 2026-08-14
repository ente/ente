use ort::session::Session;
use std::{fmt, path::Path};

use crate::error::{MlError, MlResult};

mod coreml_cache;
mod golden_test;
pub use golden_test::tooling as golden_tooling;
mod providers;
mod tensor;
mod webgpu;

pub(crate) fn set_webgpu_enabled(enabled: bool) {
    webgpu::set_enabled(enabled);
}

pub(crate) use ort::session::Session as SessionHandle;
pub(crate) use providers::ExecutionMode;
use tensor::run_golden_tensor;
pub(crate) use tensor::{
    BorrowedFloatTensor, FloatTensorData, PreparedF32Input, run_f32, run_i32_f32,
    with_prepared_float_output,
};

use providers::{ExecutionProvider, ProviderPlan};

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) struct ProviderUsage {
    pub(crate) coreml: bool,
    pub(crate) webgpu: bool,
}

impl ProviderUsage {
    fn from_provider(provider: ExecutionProvider) -> Self {
        Self {
            coreml: provider == ExecutionProvider::CoreMl,
            webgpu: provider == ExecutionProvider::WebGpu,
        }
    }

    pub(crate) fn merge(self, other: Self) -> Self {
        Self {
            coreml: self.coreml || other.coreml,
            webgpu: self.webgpu || other.webgpu,
        }
    }
}

#[derive(Debug)]
pub(crate) struct OnnxSession {
    mode: ExecutionMode,
    provider_plan: Option<ProviderPlan>,
    session: Option<Session>,
}

impl OnnxSession {
    pub(crate) fn new(mode: ExecutionMode) -> Self {
        Self {
            mode,
            provider_plan: None,
            session: None,
        }
    }

    pub(crate) fn clear(&mut self) {
        self.provider_plan = None;
        self.session = None;
    }

    #[cfg(test)]
    pub(crate) fn is_loaded(&self) -> bool {
        self.session.is_some()
    }

    pub(crate) fn run<T>(
        &mut self,
        model_path: &str,
        model_namespace: &str,
        mut operation: impl FnMut(&mut Session) -> SessionRunResult<T>,
    ) -> MlResult<(T, ProviderUsage)> {
        loop {
            self.ensure_loaded(model_path, model_namespace)?;

            let execution_provider = self
                .provider_plan
                .as_ref()
                .and_then(ProviderPlan::selected_provider)
                .expect("loaded session must have a selected execution provider");
            let session = self
                .session
                .as_mut()
                .expect("session must be loaded before model execution");
            match operation(session) {
                Ok(value) => {
                    return Ok((value, ProviderUsage::from_provider(execution_provider)));
                }
                Err(error) => {
                    if self.retry_after_provider_failure(&error) {
                        continue;
                    }
                    return Err(error.into_ml_error());
                }
            }
        }
    }

    fn ensure_loaded(&mut self, model_path: &str, model_namespace: &str) -> MlResult<()> {
        if self.session.is_some() {
            return Ok(());
        }

        let provider_plan = self
            .provider_plan
            .get_or_insert_with(|| ProviderPlan::new(self.mode, model_path));
        let model_name = model_file_label(model_path);
        log::info!("loading {model_name} with {:?} execution", self.mode);
        let started_at = std::time::Instant::now();
        let session = build_next_session(model_path, provider_plan, model_namespace)?;
        let execution_provider = provider_plan
            .selected_provider()
            .expect("successful session build must select an execution provider");
        log::info!(
            "loaded {model_name} with {execution_provider:?} in {:?}",
            started_at.elapsed()
        );
        self.session = Some(session);
        Ok(())
    }

    fn retry_after_provider_failure(&mut self, error: &SessionRunError) -> bool {
        if !error.is_retryable()
            || !self
                .provider_plan
                .as_ref()
                .is_some_and(ProviderPlan::has_fallback)
        {
            return false;
        }

        self.session = None;
        log::warn!(
            "execution provider failed, retrying model with the next provider fallback: {error}"
        );
        true
    }
}

#[derive(Debug)]
pub(crate) enum SessionRunError {
    Retryable(MlError),
    Terminal(MlError),
}

pub(crate) type SessionRunResult<T> = Result<T, SessionRunError>;

impl SessionRunError {
    fn retryable(error: MlError) -> Self {
        Self::Retryable(error)
    }

    fn is_retryable(&self) -> bool {
        matches!(self, Self::Retryable(_))
    }

    fn into_ml_error(self) -> MlError {
        match self {
            Self::Retryable(error) | Self::Terminal(error) => error,
        }
    }
}

impl fmt::Display for SessionRunError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Retryable(error) | Self::Terminal(error) => error.fmt(formatter),
        }
    }
}

impl From<MlError> for SessionRunError {
    fn from(error: MlError) -> Self {
        Self::Terminal(error)
    }
}

impl From<SessionRunError> for MlError {
    fn from(error: SessionRunError) -> Self {
        error.into_ml_error()
    }
}

impl<R> From<ort::Error<R>> for SessionRunError {
    fn from(error: ort::Error<R>) -> Self {
        let error = MlError::Ort(error.to_string());
        if is_execution_provider_run_failure(&error) {
            Self::Retryable(error)
        } else {
            Self::Terminal(error)
        }
    }
}

fn build_next_session(
    model_path: &str,
    plan: &mut ProviderPlan,
    model_namespace: &str,
) -> MlResult<Session> {
    let result = providers::run_provider_plan(plan, |execution_provider| {
        let attempt = providers::provider_attempt(execution_provider, model_path, model_namespace);
        if attempt.uses_webgpu() {
            #[cfg(any(target_os = "android", target_os = "linux", target_os = "windows"))]
            {
                return build_webgpu_session_with_canary(model_path, model_namespace, attempt)
                    .map_err(|error| format!("{error}"));
            }
            #[cfg(not(any(target_os = "android", target_os = "linux", target_os = "windows")))]
            unreachable!("WebGPU provider attempts are not constructed on this platform");
        }

        let coreml_cache_dir = attempt.coreml_cache_dir().map(Path::to_path_buf);
        match build_and_validate_session(model_path, attempt) {
            Ok(session) => {
                if let Some(cache_dir) = coreml_cache_dir {
                    coreml_cache::finalize(&cache_dir, model_path);
                }
                Ok(session)
            }
            Err(error) => {
                if let Some(cache_dir) = coreml_cache_dir
                    && let Err(cleanup_error) = coreml_cache::invalidate(&cache_dir)
                {
                    log::warn!(
                        "failed to invalidate CoreML cache for '{}' after session construction failed: {cleanup_error}",
                        model_file_label(model_path)
                    );
                }
                Err(format!("{error}"))
            }
        }
    });

    let errors = match result {
        Ok(session) => return Ok(session),
        Err(errors) => errors,
    };

    if has_protobuf_parse_failure(&errors) {
        return Err(MlError::CorruptModel(model_path.to_string()));
    }

    Err(MlError::Ort(format!(
        "failed to create ONNX session for model '{model_path}' across EP fallbacks: {}",
        errors.join(" | ")
    )))
}

fn build_cpu_session(model_path: &str) -> MlResult<Session> {
    let mut plan = ProviderPlan::new(ExecutionMode::CpuOnly, model_path);
    build_next_session(model_path, &mut plan, "golden-tooling")
}

fn is_execution_provider_run_failure(error: &MlError) -> bool {
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
        || normalized.contains("ep error")
}

// A CoreML self-test failure is treated as construction failure so the caller
// invalidates the possibly corrupt persistent cache. WebGPU validation stays
// inside its crash-canary window instead.
fn build_and_validate_session(
    model_path: &str,
    attempt: providers::ProviderAttempt,
) -> MlResult<Session> {
    #[cfg(any(
        target_os = "android",
        target_os = "ios",
        target_os = "linux",
        target_os = "macos",
        target_os = "windows"
    ))]
    let execution_provider = attempt.execution_provider();

    #[cfg_attr(not(any(target_os = "ios", target_os = "macos")), allow(unused_mut))]
    let mut session = match providers::build_session(model_path, attempt) {
        Ok(session) => session,
        Err(error) => {
            #[cfg(any(
                target_os = "android",
                target_os = "ios",
                target_os = "linux",
                target_os = "macos",
                target_os = "windows"
            ))]
            record_provider_attempt_failure(
                execution_provider,
                model_path,
                "session construction",
                &error,
            );
            return Err(error);
        }
    };

    #[cfg(any(target_os = "ios", target_os = "macos"))]
    if execution_provider == ExecutionProvider::CoreMl {
        run_session_self_test(model_path, &mut session, "CoreML")?;
    }

    Ok(session)
}

// The durable canary remains armed through construction and self-test, so
// crashes and soft failures both count toward quarantine.
#[cfg(any(target_os = "android", target_os = "linux", target_os = "windows"))]
fn build_webgpu_session_with_canary(
    model_path: &str,
    model_namespace: &str,
    attempt: providers::ProviderAttempt,
) -> MlResult<Session> {
    // Fail closed: without a durable failure record, a crash during the
    // attempt would go unnoticed and the crash loop protection would be lost.
    let canary = match webgpu::arm_canary(model_path, model_namespace) {
        Ok(canary) => canary,
        Err(error) => {
            let error = MlError::Ort(format!("failed to arm WebGPU crash canary: {error}"));
            record_provider_attempt_failure(
                ExecutionProvider::WebGpu,
                model_path,
                "crash-canary setup",
                &error,
            );
            return Err(error);
        }
    };
    #[cfg(target_os = "android")]
    {
        match webgpu::check_adapter() {
            webgpu::AdapterCheck::Allowed => {}
            webgpu::AdapterCheck::Denied => {
                canary.disarm();
                return Err(MlError::Ort(
                    "WebGPU skipped: GPU adapter is not on the allowlist".to_string(),
                ));
            }
            webgpu::AdapterCheck::Failed => {
                let error = MlError::Ort("WebGPU skipped: Vulkan adapter probe failed".to_string());
                record_provider_attempt_failure(
                    ExecutionProvider::WebGpu,
                    model_path,
                    "adapter probe",
                    &error,
                );
                return Err(error);
            }
        }
    }
    let mut session = match providers::build_session(model_path, attempt) {
        Ok(session) => session,
        Err(error) => {
            record_provider_attempt_failure(
                ExecutionProvider::WebGpu,
                model_path,
                "session construction",
                &error,
            );
            return Err(error);
        }
    };
    run_session_self_test(model_path, &mut session, "WebGPU")?;
    canary.disarm();
    Ok(session)
}

#[cfg(any(
    target_os = "android",
    target_os = "ios",
    target_os = "linux",
    target_os = "macos",
    target_os = "windows"
))]
fn record_provider_attempt_failure(
    provider: ExecutionProvider,
    model_path: &str,
    stage: &str,
    error: &MlError,
) {
    if let Some(message) = provider_attempt_failure_message(provider, model_path, stage, error) {
        log::warn!("{message}");
    }
}

#[cfg(any(
    target_os = "android",
    target_os = "ios",
    target_os = "linux",
    target_os = "macos",
    target_os = "windows",
    test
))]
fn provider_attempt_failure_message(
    provider: ExecutionProvider,
    model_path: &str,
    stage: &str,
    error: &MlError,
) -> Option<String> {
    let provider_label = match provider {
        ExecutionProvider::CoreMl => "CoreML",
        ExecutionProvider::WebGpu => "WebGPU",
        ExecutionProvider::Xnnpack => "XNNPACK",
        ExecutionProvider::Cpu => return None,
    };
    Some(format!(
        "{provider_label} {stage} failed for '{}': {error}; falling back to the next execution provider",
        model_file_label(model_path)
    ))
}

#[cfg(any(
    target_os = "android",
    target_os = "ios",
    target_os = "linux",
    target_os = "macos",
    target_os = "windows"
))]
fn run_session_self_test(
    model_path: &str,
    session: &mut Session,
    provider_label: &str,
) -> MlResult<()> {
    let model_file = model_file_label(model_path);
    let Some(entry) = golden_test::lookup(model_path) else {
        return Err(MlError::Ort(format!(
            "golden self-test entry missing for '{model_file}'"
        )));
    };
    let golden_input = golden_test::prepare_input(entry).map_err(|reason| {
        MlError::Ort(format!(
            "golden self-test input invalid for '{model_file}': {reason}"
        ))
    })?;
    let zero_input = golden_input.zeroed();

    // Warm up pipeline creation and the first dispatch with an input that is
    // deliberately different from the golden. If a later dispatch reuses
    // this result, the golden comparison below rejects the session.
    let zero_output = match run_golden_tensor(session, entry.input_shape, &zero_input) {
        Ok(output) => output,
        Err(error) => {
            log::warn!(
                "{provider_label} zero-input warm-up inference failed for '{model_file}': \
                 {error}; falling back to the next execution provider"
            );
            return Err(error.into());
        }
    };
    if let Err(reason) = golden_test::validate_output(entry, &zero_output) {
        log::error!(
            "{provider_label} zero-input warm-up failed for '{model_file}': {reason}; \
             falling back to the next execution provider"
        );
        return Err(MlError::Ort(format!(
            "zero-input warm-up failed for '{model_file}': {reason}"
        )));
    }
    log::info!("{provider_label} zero-input warm-up for '{model_file}' passed");

    let golden_output = match run_golden_tensor(session, entry.input_shape, &golden_input) {
        Ok(output) => output,
        Err(error) => {
            // Surface inference failures too: without this, a provider that
            // cannot execute the golden input would fall back invisibly (the
            // session-build error is swallowed once the next attempt succeeds).
            log::warn!(
                "{provider_label} golden self-test inference failed for '{model_file}': \
                 {error}; falling back to the next execution provider"
            );
            return Err(error.into());
        }
    };
    match golden_test::compare_output(entry, &golden_output) {
        Ok(distance) => {
            log::info!(
                "{provider_label} golden self-test for '{model_file}' passed \
                 ({} {distance:.2e})",
                entry.metric.label()
            );
            Ok(())
        }
        Err(reason) => {
            log::error!(
                "{provider_label} golden self-test failed for '{model_file}': {reason}; \
                 falling back to the next execution provider"
            );
            Err(MlError::Ort(format!(
                "golden self-test failed for '{model_file}': {reason}"
            )))
        }
    }
}

fn model_file_label(model_path: &str) -> &str {
    Path::new(model_path)
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or(model_path)
}

fn has_protobuf_parse_failure(errors: &[String]) -> bool {
    errors.iter().any(|error| {
        error
            .to_ascii_lowercase()
            .contains("protobuf parsing failed")
    })
}

#[cfg(test)]
mod tests {
    use super::{
        ExecutionProvider, SessionRunError, has_protobuf_parse_failure,
        is_execution_provider_run_failure, provider_attempt_failure_message,
    };

    #[test]
    fn provider_failure_detection_is_limited_to_ort_execution_errors() {
        assert!(is_execution_provider_run_failure(&super::MlError::Ort(
            "WebGPU EP error: VK_ERROR_DEVICE_LOST".to_string()
        )));
        assert!(!is_execution_provider_run_failure(&super::MlError::Ort(
            "invalid tensor shape".to_string()
        )));
        assert!(!is_execution_provider_run_failure(
            &super::MlError::Postprocess("WebGPU".to_string())
        ));
    }

    #[test]
    fn typed_run_errors_control_retryability() {
        let retryable =
            SessionRunError::retryable(super::MlError::Ort("non-finite output".to_string()));
        assert!(retryable.is_retryable());

        let terminal = SessionRunError::from(super::MlError::Ort(
            "WebGPU text from a typed terminal error".to_string(),
        ));
        assert!(!terminal.is_retryable());
    }

    #[test]
    fn detects_protobuf_parse_failure() {
        assert!(has_protobuf_parse_failure(&[String::from(
            "Load model failed:Protobuf parsing failed.",
        )]));
    }

    #[test]
    fn ignores_other_onnx_errors() {
        assert!(!has_protobuf_parse_failure(&[String::from(
            "Load model failed: missing initializer",
        )]));
    }

    #[test]
    fn reports_accelerated_provider_attempt_failures_with_model_context() {
        let error = super::MlError::Ort("provider registration failed".to_string());
        let message = provider_attempt_failure_message(
            ExecutionProvider::CoreMl,
            "/models/face.onnx",
            "session construction",
            &error,
        )
        .unwrap();

        assert!(message.contains("CoreML session construction failed"));
        assert!(message.contains("'face.onnx'"));
        assert!(message.contains("provider registration failed"));
        assert!(message.contains("falling back"));
    }

    #[test]
    fn does_not_report_final_cpu_construction_failure_as_a_fallback() {
        let error = super::MlError::Ort("session construction failed".to_string());

        assert!(
            provider_attempt_failure_message(
                ExecutionProvider::Cpu,
                "/models/face.onnx",
                "session construction",
                &error,
            )
            .is_none()
        );
    }
}
