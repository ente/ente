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

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum AccelerationValidation {
    GoldenRequired,
    Unvalidated,
}

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
    model_path: String,
    model_namespace: String,
    mode: ExecutionMode,
    validation: AccelerationValidation,
    provider_plan: Option<ProviderPlan>,
    session: Option<Session>,
    first_run_canary: Option<webgpu::ArmedCanary>,
}

impl OnnxSession {
    pub(crate) fn new(model_path: &str, model_namespace: &str, mode: ExecutionMode) -> Self {
        Self {
            model_path: model_path.to_string(),
            model_namespace: model_namespace.to_string(),
            mode,
            validation: AccelerationValidation::GoldenRequired,
            provider_plan: None,
            session: None,
            first_run_canary: None,
        }
    }

    /// Only for models whose output is not indexed and so cannot
    /// silently poison stored data.
    pub(crate) fn with_unvalidated_acceleration(mut self) -> Self {
        self.validation = AccelerationValidation::Unvalidated;
        self
    }

    pub(crate) fn model_path(&self) -> &str {
        &self.model_path
    }

    pub(crate) fn unload(&mut self) {
        self.provider_plan = None;
        self.session = None;
        self.leave_first_run_canary_armed();
    }

    #[cfg(test)]
    pub(crate) fn is_loaded(&self) -> bool {
        self.session.is_some()
    }

    #[cfg(test)]
    pub(crate) fn has_load_state(&self) -> bool {
        self.provider_plan.is_some() || self.session.is_some() || self.first_run_canary.is_some()
    }

    #[cfg(test)]
    pub(crate) fn initialize_load_state(&mut self) {
        self.provider_plan = Some(ProviderPlan::new(
            self.mode,
            &self.model_path,
            self.validation,
        ));
    }

    pub(crate) fn run<T>(
        &mut self,
        mut operation: impl FnMut(&mut Session) -> SessionRunResult<T>,
    ) -> MlResult<(T, ProviderUsage)> {
        loop {
            self.ensure_loaded()?;

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
                    self.disarm_first_run_canary();
                    return Ok((value, ProviderUsage::from_provider(execution_provider)));
                }
                Err(error) => {
                    if error.is_retryable() {
                        self.leave_first_run_canary_armed();
                    } else {
                        self.disarm_first_run_canary();
                    }
                    if self.retry_after_provider_failure(&error) {
                        continue;
                    }
                    return Err(error.into_ml_error());
                }
            }
        }
    }

    fn ensure_loaded(&mut self) -> MlResult<()> {
        if self.session.is_some() {
            return Ok(());
        }

        let model_path = self.model_path.as_str();
        let model_namespace = self.model_namespace.as_str();
        let provider_plan = self
            .provider_plan
            .get_or_insert_with(|| ProviderPlan::new(self.mode, model_path, self.validation));
        let model_name = model_file_label(model_path);
        log::info!("loading {model_name} with {:?} execution", self.mode);
        let started_at = std::time::Instant::now();
        let loaded =
            build_next_session(model_path, provider_plan, model_namespace, self.validation)?;
        let execution_provider = provider_plan
            .selected_provider()
            .expect("successful session build must select an execution provider");
        log::info!(
            "loaded {model_name} with {execution_provider:?} in {:?}",
            started_at.elapsed()
        );
        self.session = Some(loaded.session);
        self.first_run_canary = loaded.first_run_canary;
        Ok(())
    }

    fn disarm_first_run_canary(&mut self) {
        if let Some(canary) = self.first_run_canary.take() {
            canary.disarm();
        }
    }

    fn leave_first_run_canary_armed(&mut self) {
        self.first_run_canary = None;
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

struct LoadedSession {
    session: Session,
    first_run_canary: Option<webgpu::ArmedCanary>,
}

impl LoadedSession {
    fn new(session: Session) -> Self {
        Self {
            session,
            first_run_canary: None,
        }
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

    fn from_inference_error(error: ort::Error) -> Self {
        match error.code() {
            ort::ErrorCode::GenericFailure
            | ort::ErrorCode::RuntimeException
            | ort::ErrorCode::ExecutionProviderFailure => Self::Retryable(error.into()),
            _ => Self::Terminal(error.into()),
        }
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
        Self::Terminal(error.into())
    }
}

fn session_load_error<R>(model_path: &str, error: ort::Error<R>) -> MlError {
    match error.code() {
        ort::ErrorCode::InvalidProtobuf => MlError::CorruptModel(model_path.to_string()),
        _ => error.into(),
    }
}

fn build_next_session(
    model_path: &str,
    plan: &mut ProviderPlan,
    model_namespace: &str,
    validation: AccelerationValidation,
) -> MlResult<LoadedSession> {
    let result = providers::run_provider_plan(plan, |execution_provider| {
        let attempt = providers::provider_attempt(execution_provider, model_path, model_namespace);
        if attempt.execution_provider() == ExecutionProvider::WebGpu {
            #[cfg(any(target_os = "android", target_os = "linux", target_os = "windows"))]
            {
                return build_webgpu_session_with_canary(
                    model_path,
                    model_namespace,
                    attempt,
                    validation,
                );
            }
            #[cfg(not(any(target_os = "android", target_os = "linux", target_os = "windows")))]
            unreachable!("WebGPU provider attempts are not constructed on this platform");
        }

        let coreml_cache_dir = attempt.coreml_cache_dir().map(Path::to_path_buf);
        match build_and_validate_session(model_path, attempt, validation) {
            Ok(session) => {
                if let Some(cache_dir) = coreml_cache_dir {
                    coreml_cache::finalize(&cache_dir, model_path);
                }
                Ok(LoadedSession::new(session))
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
                Err(error)
            }
        }
    });

    let errors = match result {
        Ok(session) => return Ok(session),
        Err(errors) => errors,
    };

    if errors
        .iter()
        .any(|error| matches!(error, MlError::CorruptModel(_)))
    {
        return Err(MlError::CorruptModel(model_path.to_string()));
    }

    Err(MlError::Ort(format!(
        "failed to create ONNX session for model '{model_path}' across EP fallbacks: {}",
        errors
            .iter()
            .map(ToString::to_string)
            .collect::<Vec<_>>()
            .join(" | ")
    )))
}

fn build_cpu_session(model_path: &str) -> MlResult<Session> {
    let mut plan = ProviderPlan::new(
        ExecutionMode::CpuOnly,
        model_path,
        AccelerationValidation::GoldenRequired,
    );
    build_next_session(
        model_path,
        &mut plan,
        "golden-tooling",
        AccelerationValidation::GoldenRequired,
    )
    .map(|loaded| loaded.session)
}

// A CoreML self-test failure is treated as construction failure so the caller
// invalidates the possibly corrupt persistent cache. WebGPU validation stays
// inside its crash-canary window instead.
fn build_and_validate_session(
    model_path: &str,
    attempt: providers::ProviderAttempt,
    _validation: AccelerationValidation,
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
    if execution_provider == ExecutionProvider::CoreMl
        && _validation == AccelerationValidation::GoldenRequired
    {
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
    validation: AccelerationValidation,
) -> MlResult<LoadedSession> {
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
    let first_run_canary = if validation == AccelerationValidation::GoldenRequired {
        run_session_self_test(model_path, &mut session, "WebGPU")?;
        canary.disarm();
        None
    } else {
        Some(canary)
    };
    Ok(LoadedSession {
        session,
        first_run_canary,
    })
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

#[cfg(test)]
mod tests {
    use super::{ExecutionMode, ExecutionProvider, OnnxSession, provider_attempt_failure_message};

    fn first_run_canary(temp: &tempfile::TempDir) -> super::webgpu::ArmedCanary {
        let model = temp.path().join("model.onnx");
        super::webgpu::arm_canary(&model.to_string_lossy(), "scanner").unwrap()
    }

    fn has_canary(temp: &tempfile::TempDir) -> bool {
        std::fs::read_dir(temp.path()).unwrap().next().is_some()
    }

    #[test]
    fn successful_first_run_disarms_the_canary() {
        let temp = tempfile::tempdir().unwrap();
        let mut session = OnnxSession::new("model.onnx", "scanner", ExecutionMode::CpuOnly);
        session.first_run_canary = Some(first_run_canary(&temp));

        session.disarm_first_run_canary();

        assert!(!has_canary(&temp));
    }

    #[test]
    fn retryable_first_run_failure_leaves_the_canary_armed() {
        let temp = tempfile::tempdir().unwrap();
        let mut session = OnnxSession::new("model.onnx", "scanner", ExecutionMode::CpuOnly);
        session.first_run_canary = Some(first_run_canary(&temp));

        session.leave_first_run_canary_armed();

        assert!(has_canary(&temp));
    }

    #[test]
    fn unload_preserves_model_identity_and_armed_canary() {
        let temp = tempfile::tempdir().unwrap();
        let mut session = OnnxSession::new(
            "/models/document.onnx",
            "document-segmentation",
            ExecutionMode::CpuOnly,
        );
        session.initialize_load_state();
        session.first_run_canary = Some(first_run_canary(&temp));

        session.unload();

        assert_eq!(session.model_path, "/models/document.onnx");
        assert_eq!(session.model_namespace, "document-segmentation");
        assert!(!session.is_loaded());
        assert!(!session.has_load_state());
        assert!(has_canary(&temp));
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
