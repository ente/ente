use ort::{
    ep::{CPU, ExecutionProviderDispatch},
    session::{Session, builder::GraphOptimizationLevel},
    value::{Tensor, TensorElementType, TensorRef, ValueType},
};
use std::{
    cell::OnceCell,
    path::{Path, PathBuf},
};

use half::prelude::{HalfFloatSliceExt, HalfFloatVecExt};

#[cfg(target_os = "ios")]
use ort::ep::{
    CoreML,
    coreml::{ComputeUnits, ModelFormat, SpecializationStrategy},
};
#[cfg(target_os = "android")]
use ort::ep::{
    WebGPU, XNNPACK,
    webgpu::{DawnBackendType, PreferredLayout},
};
#[cfg(target_os = "android")]
use std::num::NonZeroUsize;

use crate::ml::error::{MlError, MlResult};
use crate::ml::events;
use crate::ml::golden;
#[cfg(any(target_os = "android", target_os = "ios"))]
use crate::ml::runtime::rt_log;
#[cfg(target_os = "android")]
use crate::ml::webgpu;

#[cfg(any(target_os = "ios", test))]
const COREML_CACHE_SCHEMA: &str = "ort-1_27-mlprogram-all-default-v1";
const COREML_CACHE_COMPLETE_MARKER: &str = ".ente-cache-complete";
/// The name ONNX Runtime's CoreML EP gives the compiled model it stores
/// inside each generated MLProgram package directory in the cache
/// (`model.mm` `CompileOrReadCachedModel`).
const COREML_CACHE_COMPILED_MODEL: &str = "compiled_model.mlmodelc";
/// The weight blob file name inside an ORT-generated `.mlpackage`
/// (`model_builder.cc` writes `@model_path/weights/weight.bin`).
const COREML_PACKAGE_WEIGHT_BLOB: &str = "weight.bin";
#[cfg(target_os = "ios")]
const ENABLE_PERSISTENT_COREML_CACHE: bool = true;

/// An f32 model input that can be borrowed by multiple sessions.
///
/// The FP16 representation is created lazily and retained so that a shared
/// preprocessing result only pays the conversion cost once.
pub(crate) struct PreparedF32Input {
    f32_data: Vec<f32>,
    f16_data: OnceCell<Vec<half::f16>>,
}

#[derive(Clone, Copy)]
pub(crate) enum BorrowedFloatTensor<'a> {
    F32(&'a [f32]),
    F16(&'a [half::f16]),
}

pub(crate) trait FloatTensorData: Copy {
    fn len(self) -> usize;
    fn value(self, index: usize) -> f32;
}

impl FloatTensorData for &[f32] {
    fn len(self) -> usize {
        <[f32]>::len(self)
    }

    #[inline]
    fn value(self, index: usize) -> f32 {
        self[index]
    }
}

impl FloatTensorData for &[half::f16] {
    fn len(self) -> usize {
        <[half::f16]>::len(self)
    }

    #[inline]
    fn value(self, index: usize) -> f32 {
        self[index].to_f32()
    }
}

impl PreparedF32Input {
    pub(crate) fn new(data: Vec<f32>) -> Self {
        Self {
            f32_data: data,
            f16_data: OnceCell::new(),
        }
    }

    fn f16_data(&self) -> &[half::f16] {
        self.f16_data
            .get_or_init(|| Vec::<half::f16>::from_f32_slice(&self.f32_data))
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum ExecutionMode {
    PlatformDefault,
    #[cfg(target_os = "android")]
    Xnnpack,
    CpuOnly,
}

/// The preferred execution provider of the session attempt that succeeded.
///
/// Each accelerated session also registers the policy's fallback providers,
/// but this identifies the provider whose attempt produced the session. The
/// runtime aggregates it across the sessions used for a result so remotely
/// stored embeddings can be attributed to the providers that computed them.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[allow(dead_code)] // Accelerated variants are constructed only on their target OS.
pub(crate) enum ExecutionProvider {
    CoreMl,
    WebGpu,
    Xnnpack,
    Cpu,
}

impl ExecutionMode {
    pub(crate) fn fallback(self) -> Option<Self> {
        match self {
            #[cfg(target_os = "android")]
            Self::PlatformDefault => Some(Self::Xnnpack),
            #[cfg(not(target_os = "android"))]
            Self::PlatformDefault => Some(Self::CpuOnly),
            #[cfg(target_os = "android")]
            Self::Xnnpack => Some(Self::CpuOnly),
            Self::CpuOnly => None,
        }
    }
}

pub(crate) fn build_session(
    model_path: &str,
    mode: ExecutionMode,
    coreml_cache_namespace: &str,
) -> MlResult<(Session, ExecutionProvider)> {
    let attempts = provider_attempts(mode, model_path, coreml_cache_namespace);

    let mut errors = Vec::new();
    for attempt in attempts {
        let execution_provider = attempt.execution_provider;
        if attempt.uses_webgpu {
            #[cfg(target_os = "android")]
            {
                match build_webgpu_session_with_canary(model_path, coreml_cache_namespace, attempt)
                {
                    Ok(session) => return Ok((session, execution_provider)),
                    Err(error) => errors.push(format!("{error}")),
                }
                continue;
            }
            #[cfg(not(target_os = "android"))]
            unreachable!("WebGPU provider attempts are only constructed on Android");
        }

        let coreml_cache_dir = attempt.coreml_cache_dir.clone();
        match build_and_validate_session(model_path, attempt) {
            Ok(session) => {
                if let Some(cache_dir) = coreml_cache_dir {
                    finalize_coreml_cache(&cache_dir, model_path);
                }
                return Ok((session, execution_provider));
            }
            Err(error) => {
                if let Some(cache_dir) = coreml_cache_dir
                    && let Err(cleanup_error) = invalidate_coreml_cache(&cache_dir)
                {
                    events::record(
                        events::Severity::Warning,
                        format!(
                            "failed to invalidate CoreML cache for '{}' after session construction failed: {cleanup_error}",
                            model_file_label(model_path)
                        ),
                    );
                }
                errors.push(format!("{error}"));
            }
        }
    }

    if has_protobuf_parse_failure(&errors) {
        return Err(MlError::CorruptModel(model_path.to_string()));
    }

    Err(MlError::Ort(format!(
        "failed to create ONNX session for model '{model_path}' across EP fallbacks: {}",
        errors.join(" | ")
    )))
}

/// Builds a session for one provider attempt and, for CoreML attempts, runs
/// the golden self-test before the session is trusted. A self-test failure is
/// reported as a session-construction failure, so the caller invalidates the
/// CoreML cache (a corrupt compiled model would otherwise persist) and falls
/// through to the next attempt. WebGPU attempts do not take this path; they
/// are validated inside the crash-canary window.
fn build_and_validate_session(model_path: &str, attempt: ProviderAttempt) -> MlResult<Session> {
    #[cfg(any(target_os = "android", target_os = "ios"))]
    let execution_provider = attempt.execution_provider;

    #[cfg_attr(not(target_os = "ios"), allow(unused_mut))]
    let mut session = match build_session_with_providers(model_path, attempt) {
        Ok(session) => session,
        Err(error) => {
            #[cfg(any(target_os = "android", target_os = "ios"))]
            record_provider_attempt_failure(
                execution_provider,
                model_path,
                "session construction",
                &error,
            );
            return Err(error);
        }
    };

    #[cfg(target_os = "ios")]
    if execution_provider == ExecutionProvider::CoreMl {
        run_session_self_test(model_path, &mut session, "CoreML")?;
    }

    Ok(session)
}

/// Builds the WebGPU session under the durable crash canary. The canary is
/// armed before session construction and only disarmed after the session has
/// passed the golden self-test, so a driver crash anywhere in between is
/// recorded on disk. Soft failures (including self-test failures) return an
/// error with the canary left armed (the drop keeps the counted attempt), and
/// the caller falls through to the next execution provider.
#[cfg(target_os = "android")]
fn build_webgpu_session_with_canary(
    model_path: &str,
    model_namespace: &str,
    attempt: ProviderAttempt,
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
    // The adapter probe touches the Vulkan driver, so it runs inside the
    // armed canary window: a probe crash is recorded like any other WebGPU
    // crash.
    match webgpu::check_adapter() {
        webgpu::AdapterCheck::Allowed => {}
        webgpu::AdapterCheck::Denied => {
            // A completed probe that denies the adapter is a clean policy
            // decision rather than a failed attempt, so the canary is
            // disarmed.
            canary.disarm();
            return Err(MlError::Ort(
                "WebGPU skipped: GPU adapter is not on the allowlist".to_string(),
            ));
        }
        webgpu::AdapterCheck::Failed => {
            // The canary stays armed so the drop records a failed attempt:
            // a driver whose probe keeps failing quarantines like one that
            // keeps crashing, and cannot reset the consecutive-failure
            // counter of genuine crashes.
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
    let mut session = match build_session_with_providers(model_path, attempt) {
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

#[cfg(any(target_os = "android", target_os = "ios"))]
fn record_provider_attempt_failure(
    provider: ExecutionProvider,
    model_path: &str,
    stage: &str,
    error: &MlError,
) {
    if let Some(message) = provider_attempt_failure_message(provider, model_path, stage, error) {
        events::record(events::Severity::Warning, message);
    }
}

#[cfg(any(target_os = "android", target_os = "ios", test))]
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

/// Validates a freshly built accelerated session against the model's
/// committed golden output. An error means the session must not be used; the
/// caller falls through to the next execution provider attempt.
#[cfg(any(target_os = "android", target_os = "ios"))]
fn run_session_self_test(
    model_path: &str,
    session: &mut Session,
    provider_label: &str,
) -> MlResult<()> {
    let model_file = model_file_label(model_path);
    let Some(entry) = golden::lookup(model_path) else {
        // Attempts are only constructed for models with a golden entry, so
        // this is a defensive fail-closed path.
        return Err(MlError::Ort(format!(
            "golden self-test entry missing for '{model_file}'"
        )));
    };
    let golden_input = golden::prepare_input(entry).map_err(|reason| {
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
            events::record(
                events::Severity::Warning,
                format!(
                    "{provider_label} zero-input warm-up inference failed for '{model_file}': \
                     {error}; falling back to the next execution provider"
                ),
            );
            return Err(error);
        }
    };
    if let Err(reason) = golden::validate_output(entry, &zero_output) {
        events::record(
            events::Severity::Severe,
            format!(
                "{provider_label} zero-input warm-up failed for '{model_file}': {reason}; \
                 falling back to the next execution provider"
            ),
        );
        return Err(MlError::Ort(format!(
            "zero-input warm-up failed for '{model_file}': {reason}"
        )));
    }
    rt_log(&format!(
        "{provider_label} zero-input warm-up for '{model_file}' passed"
    ));

    let golden_output = match run_golden_tensor(session, entry.input_shape, &golden_input) {
        Ok(output) => output,
        Err(error) => {
            // Surface inference failures too: without this, a provider that
            // cannot execute the golden input would fall back invisibly (the
            // session-build error is swallowed once the next attempt succeeds).
            events::record(
                events::Severity::Warning,
                format!(
                    "{provider_label} golden self-test inference failed for '{model_file}': \
                     {error}; falling back to the next execution provider"
                ),
            );
            return Err(error);
        }
    };
    match golden::compare_output(entry, &golden_output) {
        Ok(distance) => {
            rt_log(&format!(
                "{provider_label} golden self-test for '{model_file}' passed \
                 ({} {distance:.2e})",
                entry.metric.label()
            ));
            Ok(())
        }
        Err(reason) => {
            events::record(
                events::Severity::Severe,
                format!(
                    "{provider_label} golden self-test failed for '{model_file}': {reason}; \
                     falling back to the next execution provider"
                ),
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

/// Runs one golden input through the session and extracts the first output as
/// f32. Shared with the golden generator so device and generator inference
/// are identical by construction.
pub(crate) fn run_golden_tensor(
    session: &mut Session,
    input_shape: &[i64],
    input: &golden::PreparedGoldenInput,
) -> MlResult<Vec<f32>> {
    let outputs = match input {
        golden::PreparedGoldenInput::F32(data) => {
            if session_expects_f16(session) {
                let input_tensor = Tensor::<half::f16>::from_array((
                    input_shape,
                    Vec::<half::f16>::from_f32_slice(data),
                ))?;
                session.run(ort::inputs![input_tensor])?
            } else {
                let input_tensor =
                    TensorRef::<f32>::from_array_view((input_shape, data.as_slice()))?;
                session.run(ort::inputs![input_tensor])?
            }
        }
        golden::PreparedGoldenInput::I32(data) => {
            let input_tensor = TensorRef::<i32>::from_array_view((input_shape, data.as_slice()))?;
            session.run(ort::inputs![input_tensor])?
        }
    };

    if outputs.len() == 0 {
        return Err(MlError::Ort("missing first output tensor".to_string()));
    }
    let output = &outputs[0];
    if let Ok((_, tensor_data)) = output.try_extract_tensor::<f32>() {
        Ok(tensor_data.to_vec())
    } else {
        let (_, tensor_data) = output.try_extract_tensor::<half::f16>()?;
        let mut data = vec![0.0; tensor_data.len()];
        tensor_data.convert_to_f32_slice(&mut data);
        Ok(data)
    }
}

fn has_protobuf_parse_failure(errors: &[String]) -> bool {
    errors.iter().any(|error| {
        error
            .to_ascii_lowercase()
            .contains("protobuf parsing failed")
    })
}

struct ProviderAttempt {
    providers: Vec<ExecutionProviderDispatch>,
    disable_intra_op_spinning: bool,
    coreml_cache_dir: Option<PathBuf>,
    uses_webgpu: bool,
    execution_provider: ExecutionProvider,
}

impl ProviderAttempt {
    fn cpu_only() -> Self {
        Self {
            providers: vec![CPU::default().with_arena_allocator(true).build()],
            disable_intra_op_spinning: false,
            coreml_cache_dir: None,
            uses_webgpu: false,
            execution_provider: ExecutionProvider::Cpu,
        }
    }
}

fn provider_attempts(
    mode: ExecutionMode,
    model_path: &str,
    coreml_cache_namespace: &str,
) -> Vec<ProviderAttempt> {
    match mode {
        ExecutionMode::PlatformDefault => {
            platform_default_attempts(model_path, coreml_cache_namespace)
        }
        #[cfg(target_os = "android")]
        ExecutionMode::Xnnpack => vec![xnnpack_attempt(), ProviderAttempt::cpu_only()],
        ExecutionMode::CpuOnly => vec![ProviderAttempt::cpu_only()],
    }
}

#[cfg(target_os = "ios")]
fn platform_default_attempts(
    model_path: &str,
    coreml_cache_namespace: &str,
) -> Vec<ProviderAttempt> {
    let mut attempts = Vec::new();
    if golden_entry_required(model_path, "CoreML") {
        let (coreml_provider, coreml_cache_dir) =
            coreml_provider(model_path, coreml_cache_namespace);
        attempts.push(ProviderAttempt {
            providers: vec![
                coreml_provider,
                CPU::default().with_arena_allocator(true).build(),
            ],
            disable_intra_op_spinning: false,
            coreml_cache_dir,
            uses_webgpu: false,
            execution_provider: ExecutionProvider::CoreMl,
        });
    }
    attempts.push(ProviderAttempt::cpu_only());
    attempts
}

#[cfg(target_os = "ios")]
fn coreml_provider(
    model_path: &str,
    cache_namespace: &str,
) -> (ExecutionProviderDispatch, Option<PathBuf>) {
    let mut provider = CoreML::default()
        .with_model_format(ModelFormat::MLProgram)
        .with_compute_units(ComputeUnits::All)
        .with_specialization_strategy(SpecializationStrategy::Default);

    let mut prepared_cache_dir = None;
    if ENABLE_PERSISTENT_COREML_CACHE {
        match prepare_coreml_cache_directory(model_path, cache_namespace) {
            Ok(cache_dir) => {
                provider = provider.with_model_cache_dir(cache_dir.to_string_lossy());
                prepared_cache_dir = Some(cache_dir);
            }
            Err(error) => {
                events::record(
                    events::Severity::Warning,
                    format!(
                        "failed to prepare persistent CoreML cache for '{}'; continuing without it: {error}",
                        model_file_label(model_path)
                    ),
                );
            }
        }
    } else {
        remove_persistent_coreml_cache(model_path);
    }

    (provider.build().error_on_failure(), prepared_cache_dir)
}

/// Deletes the entire persistent cache tree while the feature is disabled, so
/// flipping `ENABLE_PERSISTENT_COREML_CACHE` off in a release actually
/// returns the disk space instead of stranding the caches forever.
#[cfg(target_os = "ios")]
fn remove_persistent_coreml_cache(model_path: &str) {
    let Some(coreml_root) = coreml_cache_root(Path::new(model_path))
        .parent()
        .map(Path::to_path_buf)
    else {
        return;
    };
    match std::fs::remove_dir_all(&coreml_root) {
        Ok(()) => events::record(
            events::Severity::Info,
            "removed persistent CoreML cache (feature disabled)".to_string(),
        ),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => events::record(
            events::Severity::Warning,
            format!("failed to remove disabled persistent CoreML cache: {error}"),
        ),
    }
}

#[cfg(target_os = "android")]
fn platform_default_attempts(
    model_path: &str,
    _coreml_cache_namespace: &str,
) -> Vec<ProviderAttempt> {
    let mut attempts = Vec::new();
    if webgpu::attempt_permitted(model_path) && golden_entry_required(model_path, "WebGPU") {
        attempts.push(ProviderAttempt {
            // EP priority follows registration order. Unsupported WebGPU nodes
            // fall through to XNNPACK and then CPU in the same session.
            providers: vec![
                webgpu_provider(),
                xnnpack_provider().fail_silently(),
                CPU::default().with_arena_allocator(true).build(),
            ],
            disable_intra_op_spinning: true,
            coreml_cache_dir: None,
            uses_webgpu: true,
            execution_provider: ExecutionProvider::WebGpu,
        });
    }
    // Clean-session fallbacks for provider or driver failures that prevent
    // the primary session from being constructed at all.
    attempts.push(xnnpack_attempt());
    attempts.push(ProviderAttempt::cpu_only());
    attempts
}

/// Accelerated execution providers are only allowed for models with a
/// committed golden self-test entry (fail closed). A miss for a production
/// model means a model update shipped without regenerating `golden_data.rs`.
#[cfg(any(target_os = "android", target_os = "ios"))]
fn golden_entry_required(model_path: &str, provider_label: &str) -> bool {
    if golden::lookup(model_path).is_some() {
        return true;
    }
    events::record(
        events::Severity::Severe,
        format!(
            "no golden self-test entry for '{}'; {provider_label} disabled for this model",
            model_file_label(model_path)
        ),
    );
    false
}

#[cfg(target_os = "android")]
fn webgpu_provider() -> ExecutionProviderDispatch {
    WebGPU::default()
        .with_dawn_backend_type(DawnBackendType::Vulkan)
        .with_preferred_layout(PreferredLayout::NCHW)
        .build()
        .error_on_failure()
}

#[cfg(not(any(target_os = "ios", target_os = "android")))]
fn platform_default_attempts(
    _model_path: &str,
    _coreml_cache_namespace: &str,
) -> Vec<ProviderAttempt> {
    vec![ProviderAttempt::cpu_only()]
}

#[cfg(target_os = "ios")]
fn prepare_coreml_cache_directory(
    model_path: &str,
    cache_namespace: &str,
) -> std::io::Result<PathBuf> {
    let model_path = Path::new(model_path);
    let schema_root = coreml_cache_root(model_path);

    // Best effort: a prune failure must not cost this load its cache.
    if let Some(coreml_root) = schema_root.parent() {
        match prune_stale_coreml_schema_directories(coreml_root, COREML_CACHE_SCHEMA) {
            Ok(removed) => {
                for schema in removed {
                    events::record(
                        events::Severity::Info,
                        format!("removed stale CoreML cache schema '{schema}'"),
                    );
                }
            }
            Err(error) => events::record(
                events::Severity::Warning,
                format!("failed to prune stale CoreML cache schemas: {error}"),
            ),
        }
    }

    let model_cache_root = schema_root.join(sanitize_cache_component(cache_namespace));
    std::fs::create_dir_all(&model_cache_root)?;

    let cache_key = coreml_model_cache_key(model_path)?;
    prune_superseded_coreml_cache_directories(&model_cache_root, &cache_key)?;

    let cache_dir = model_cache_root.join(cache_key);
    prepare_coreml_cache_entry(&cache_dir)?;
    Ok(cache_dir)
}

/// A missing completion marker means the process stopped before ONNX Runtime
/// finished constructing the session. Recreate the directory so ORT cannot
/// mistake a partial model package for a valid cache hit.
#[cfg(any(target_os = "ios", test))]
fn prepare_coreml_cache_entry(cache_dir: &Path) -> std::io::Result<()> {
    if cache_dir.exists() && !coreml_cache_complete_marker(cache_dir).is_file() {
        std::fs::remove_dir_all(cache_dir)?;
    }
    std::fs::create_dir_all(cache_dir)
}

/// Runs after a session was built successfully from `cache_dir`: trims the
/// redundant generated-package weights, then marks the entry complete. Trim
/// failures are reported but do not fail the load; an untrimmed cache is
/// merely larger. Trimming before marking means a crash mid-trim leaves no
/// completion marker, so the next load rebuilds the entry from scratch.
fn finalize_coreml_cache(cache_dir: &Path, model_path: &str) {
    match trim_coreml_cache_weights(cache_dir) {
        Ok(0) => {}
        Ok(reclaimed) => events::record(
            events::Severity::Info,
            format!(
                "primed CoreML cache for '{}': trimmed {} MiB of generated package weights",
                model_file_label(model_path),
                reclaimed / (1024 * 1024)
            ),
        ),
        Err(error) => events::record(
            events::Severity::Warning,
            format!(
                "failed to trim CoreML cache weights for '{}': {error}",
                model_file_label(model_path)
            ),
        ),
    }

    if let Err(error) = mark_coreml_cache_complete(cache_dir) {
        events::record(
            events::Severity::Warning,
            format!(
                "failed to mark CoreML cache complete for '{}': {error}",
                model_file_label(model_path)
            ),
        );
    }
}

/// Truncates the weight blobs inside every cached generated package that
/// already contains a compiled model, returning the bytes reclaimed.
///
/// On a warm cache hit ONNX Runtime 1.27 only checks that the generated
/// MLProgram package directory exists and then loads
/// `compiled_model.mlmodelc` (`model_builder.cc` constructor, `model.mm`
/// `CompileOrReadCachedModel`), so the package's own weight copy is dead
/// bytes — roughly half the cache footprint. Packages without a compiled
/// model are left intact because ONNX Runtime would recompile from them.
/// Should a future runtime read the package weights again, session
/// construction fails, the caller invalidates the entry, and the next load
/// rebuilds it from the ONNX source.
fn trim_coreml_cache_weights(cache_dir: &Path) -> std::io::Result<u64> {
    let mut reclaimed = 0;
    // Layout per ORT 1.27: <cache_dir>/<model_hash>/<partition>/model is the
    // generated MLProgram package. `CompileOrReadCachedModel` strips the last
    // path component only for the NeuralNetwork format, so for MLProgram the
    // compiled model is stored INSIDE the package directory:
    // <partition>/model/compiled_model.mlmodelc.
    for model_hash_entry in std::fs::read_dir(cache_dir)? {
        let model_hash_entry = model_hash_entry?;
        if !model_hash_entry.file_type()?.is_dir() {
            continue;
        }
        for partition_entry in std::fs::read_dir(model_hash_entry.path())? {
            let partition_entry = partition_entry?;
            if !partition_entry.file_type()?.is_dir() {
                continue;
            }
            let package_dir = partition_entry.path().join("model");
            if !package_dir.is_dir() || !package_dir.join(COREML_CACHE_COMPILED_MODEL).exists() {
                continue;
            }
            reclaimed += truncate_weight_blobs(&package_dir)?;
        }
    }
    Ok(reclaimed)
}

/// Truncates `weight.bin` files under `dir`, never descending into
/// `.mlmodelc` bundles: the compiled model keeps its own `weights/weight.bin`
/// copy, and that one is exactly what warm loads read, so it must survive.
fn truncate_weight_blobs(dir: &Path) -> std::io::Result<u64> {
    let mut reclaimed = 0;
    for entry in std::fs::read_dir(dir)? {
        let entry = entry?;
        let file_type = entry.file_type()?;
        if file_type.is_dir() {
            if entry.path().extension() == Some(std::ffi::OsStr::new("mlmodelc")) {
                continue;
            }
            reclaimed += truncate_weight_blobs(&entry.path())?;
        } else if file_type.is_file() && entry.file_name() == COREML_PACKAGE_WEIGHT_BLOB {
            let size = entry.metadata()?.len();
            if size > 0 {
                std::fs::write(entry.path(), [])?;
                reclaimed += size;
            }
        }
    }
    Ok(reclaimed)
}

fn mark_coreml_cache_complete(cache_dir: &Path) -> std::io::Result<()> {
    std::fs::write(coreml_cache_complete_marker(cache_dir), [])
}

fn invalidate_coreml_cache(cache_dir: &Path) -> std::io::Result<()> {
    match std::fs::remove_dir_all(cache_dir) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error),
    }
}

fn coreml_cache_complete_marker(cache_dir: &Path) -> PathBuf {
    cache_dir.join(COREML_CACHE_COMPLETE_MARKER)
}

/// Keep generated CoreML artifacts in Library/Caches so iOS can evict them and
/// exclude them from backups. Model files are stored below Library/Application
/// Support; fall back to the process temporary directory for unusual layouts.
#[cfg(any(target_os = "ios", test))]
fn coreml_cache_root(model_path: &Path) -> PathBuf {
    let cache_base = model_path
        .ancestors()
        .find(|ancestor| ancestor.file_name().is_some_and(|name| name == "Library"))
        .map(|library| library.join("Caches"))
        .unwrap_or_else(std::env::temp_dir);

    cache_base
        .join("ente")
        .join("ml")
        .join("coreml")
        .join(COREML_CACHE_SCHEMA)
}

/// Include the filename and file metadata in the directory name because ONNX
/// Runtime's internal CoreML cache key does not necessarily change when only
/// model weights change.
#[cfg(any(target_os = "ios", test))]
fn coreml_model_cache_key(model_path: &Path) -> std::io::Result<String> {
    use std::time::UNIX_EPOCH;

    let metadata = std::fs::metadata(model_path)?;
    let modified = metadata
        .modified()?
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    Ok(format!(
        "{}-{}-{}-{}",
        sanitize_cache_component(
            model_path
                .file_name()
                .and_then(|name| name.to_str())
                .unwrap_or("model")
        ),
        metadata.len(),
        modified.as_secs(),
        modified.subsec_nanos()
    ))
}

#[cfg(any(target_os = "ios", test))]
fn sanitize_cache_component(value: &str) -> String {
    value
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() || matches!(character, '-' | '_' | '.') {
                character
            } else {
                '_'
            }
        })
        .collect()
}

/// Removes cache trees written under superseded `COREML_CACHE_SCHEMA`
/// versions, returning the names of the removed directories. Without this, a
/// schema bump (ORT upgrade or CoreML policy change) would orphan the
/// previous schema's caches — hundreds of MB — forever.
#[cfg(any(target_os = "ios", test))]
fn prune_stale_coreml_schema_directories(
    coreml_root: &Path,
    current_schema: &str,
) -> std::io::Result<Vec<String>> {
    let mut removed = Vec::new();
    let entries = match std::fs::read_dir(coreml_root) {
        Ok(entries) => entries,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(removed),
        Err(error) => return Err(error),
    };
    for entry in entries {
        let entry = entry?;
        if entry.file_name() == current_schema || !entry.file_type()?.is_dir() {
            continue;
        }
        std::fs::remove_dir_all(entry.path())?;
        removed.push(entry.file_name().to_string_lossy().into_owned());
    }
    Ok(removed)
}

/// Retain exactly one generated cache for each logical model slot. The active
/// directory is identity-specific so ONNX Runtime cannot reuse stale output.
#[cfg(any(target_os = "ios", test))]
fn prune_superseded_coreml_cache_directories(
    model_cache_root: &Path,
    current_cache_key: &str,
) -> std::io::Result<()> {
    for entry in std::fs::read_dir(model_cache_root)? {
        let entry = entry?;
        if entry.file_name() == current_cache_key || !entry.file_type()?.is_dir() {
            continue;
        }
        std::fs::remove_dir_all(entry.path())?;
    }
    Ok(())
}

#[cfg(target_os = "android")]
fn xnnpack_provider() -> ExecutionProviderDispatch {
    XNNPACK::default()
        .with_intra_op_num_threads(NonZeroUsize::new(4).expect("four is non-zero"))
        .build()
        .error_on_failure()
}

#[cfg(target_os = "android")]
fn xnnpack_attempt() -> ProviderAttempt {
    ProviderAttempt {
        providers: vec![
            xnnpack_provider(),
            CPU::default().with_arena_allocator(true).build(),
        ],
        disable_intra_op_spinning: true,
        coreml_cache_dir: None,
        uses_webgpu: false,
        execution_provider: ExecutionProvider::Xnnpack,
    }
}

fn build_session_with_providers(model_path: &str, attempt: ProviderAttempt) -> MlResult<Session> {
    let mut builder = Session::builder()?
        .with_optimization_level(GraphOptimizationLevel::All)?
        .with_intra_threads(1)?
        .with_inter_threads(1)?;

    if attempt.disable_intra_op_spinning {
        builder = builder.with_intra_op_spinning(false)?;
    }
    builder = builder.with_execution_providers(attempt.providers)?;

    let session = builder.commit_from_file(model_path)?;
    Ok(session)
}

/// Guard against execution providers that return NaN or infinity instead of
/// failing. The error message matches `is_execution_provider_failure` so the
/// runtime advances to the next execution provider fallback.
fn ensure_finite_f32(data: &[f32]) -> MlResult<()> {
    if data.iter().copied().all(f32::is_finite) {
        return Ok(());
    }
    Err(MlError::Ort(
        "model produced non-finite output values".to_string(),
    ))
}

fn ensure_finite_f16(data: &[half::f16]) -> MlResult<()> {
    if data.iter().all(|value| value.is_finite()) {
        return Ok(());
    }
    Err(MlError::Ort(
        "model produced non-finite output values".to_string(),
    ))
}

/// Returns true if the session's first input expects FP16 tensors.
fn session_expects_f16(session: &Session) -> bool {
    session
        .inputs()
        .first()
        .and_then(|i| match i.dtype() {
            ValueType::Tensor { ty, .. } => Some(*ty == TensorElementType::Float16),
            _ => None,
        })
        .unwrap_or(false)
}

/// Run inference accepting f32 data and returning f32 results.
/// Automatically converts inputs/outputs for FP16 models.
pub(crate) fn run_f32<const N: usize>(
    session: &mut Session,
    input: Vec<f32>,
    input_shape: [i64; N],
) -> MlResult<(Vec<i64>, Vec<f32>)> {
    let outputs = if session_expects_f16(session) {
        let f16_input = Vec::<half::f16>::from_f32_slice(&input);
        let input_tensor = Tensor::<half::f16>::from_array((input_shape, f16_input))?;
        session.run(ort::inputs![input_tensor])?
    } else {
        let input_tensor = Tensor::<f32>::from_array((input_shape, input))?;
        session.run(ort::inputs![input_tensor])?
    };

    if outputs.len() == 0 {
        return Err(MlError::Ort("missing first output tensor".to_string()));
    }
    let output = &outputs[0];

    // Extract output: try f32 first, fall back to f16 with conversion.
    if let Ok((tensor_shape, tensor_data)) = output.try_extract_tensor::<f32>() {
        let shape = tensor_shape.iter().copied().collect::<Vec<_>>();
        let data = tensor_data.to_vec();
        ensure_finite_f32(&data)?;
        Ok((shape, data))
    } else {
        let (tensor_shape, tensor_data) = output.try_extract_tensor::<half::f16>()?;
        let shape = tensor_shape.iter().copied().collect::<Vec<_>>();
        let mut data = vec![0.0; tensor_data.len()];
        tensor_data.convert_to_f32_slice(&mut data);
        ensure_finite_f32(&data)?;
        Ok((shape, data))
    }
}

/// Run inference using a reusable input and process the first output in place.
/// Both f32 and f16 outputs remain borrowed from ONNX Runtime; consumers
/// convert only the values they inspect.
pub(crate) fn with_prepared_float_output<const N: usize, T>(
    session: &mut Session,
    input: &PreparedF32Input,
    input_shape: [i64; N],
    consume: impl FnOnce(&[i64], BorrowedFloatTensor<'_>) -> MlResult<T>,
) -> MlResult<T> {
    let outputs = if session_expects_f16(session) {
        let input_tensor =
            TensorRef::<half::f16>::from_array_view((input_shape, input.f16_data()))?;
        session.run(ort::inputs![input_tensor])?
    } else {
        let input_tensor =
            TensorRef::<f32>::from_array_view((input_shape, input.f32_data.as_slice()))?;
        session.run(ort::inputs![input_tensor])?
    };

    if outputs.len() == 0 {
        return Err(MlError::Ort("missing first output tensor".to_string()));
    }
    let output = &outputs[0];
    if let Ok((tensor_shape, tensor_data)) = output.try_extract_tensor::<f32>() {
        ensure_finite_f32(tensor_data)?;
        consume(tensor_shape, BorrowedFloatTensor::F32(tensor_data))
    } else {
        let (tensor_shape, tensor_data) = output.try_extract_tensor::<half::f16>()?;
        ensure_finite_f16(tensor_data)?;
        consume(tensor_shape, BorrowedFloatTensor::F16(tensor_data))
    }
}

pub(crate) fn run_i32_f32<const N: usize>(
    session: &mut Session,
    input: &[i32],
    input_shape: [i64; N],
) -> MlResult<(Vec<i64>, Vec<f32>)> {
    let input_tensor = TensorRef::<i32>::from_array_view((input_shape, input))?;
    let outputs = session.run(ort::inputs![input_tensor])?;
    if outputs.len() == 0 {
        return Err(MlError::Ort("missing first output tensor".to_string()));
    }
    let output = &outputs[0];
    let (tensor_shape, tensor_data) = output.try_extract_tensor::<f32>()?;
    let shape = tensor_shape.iter().copied().collect::<Vec<_>>();
    let data = tensor_data.to_vec();
    ensure_finite_f32(&data)?;
    Ok((shape, data))
}

#[cfg(test)]
mod tests {
    use std::{io::Write, path::Path};

    use super::{
        ExecutionProvider, coreml_cache_root, coreml_model_cache_key, ensure_finite_f16,
        ensure_finite_f32, has_protobuf_parse_failure, invalidate_coreml_cache,
        mark_coreml_cache_complete, prepare_coreml_cache_entry, provider_attempt_failure_message,
        prune_stale_coreml_schema_directories, prune_superseded_coreml_cache_directories,
        sanitize_cache_component, trim_coreml_cache_weights,
    };

    #[test]
    fn accepts_finite_model_outputs() {
        assert!(ensure_finite_f32(&[0.0, -1.5, f32::MAX]).is_ok());
        assert!(ensure_finite_f16(&[half::f16::from_f32(0.25)]).is_ok());
    }

    #[test]
    fn rejects_non_finite_model_outputs() {
        for bad in [f32::NAN, f32::INFINITY, f32::NEG_INFINITY] {
            let error = ensure_finite_f32(&[1.0, bad]).unwrap_err();
            assert!(error.to_string().contains("non-finite"));
        }
        let error = ensure_finite_f16(&[half::f16::NAN]).unwrap_err();
        assert!(error.to_string().contains("non-finite"));
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

    #[test]
    fn places_coreml_cache_in_library_caches() {
        let model = Path::new(
            "/var/mobile/Containers/Data/Application/APP/Library/Application Support/assets/model.onnx",
        );

        assert_eq!(
            coreml_cache_root(model),
            Path::new(
                "/var/mobile/Containers/Data/Application/APP/Library/Caches/ente/ml/coreml/ort-1_27-mlprogram-all-default-v1"
            )
        );
    }

    #[test]
    fn coreml_cache_key_changes_when_model_file_changes() {
        let mut model = tempfile::NamedTempFile::new().unwrap();
        model.write_all(b"first").unwrap();
        model.flush().unwrap();
        let first_key = coreml_model_cache_key(model.path()).unwrap();

        model.write_all(b" version").unwrap();
        model.flush().unwrap();
        let second_key = coreml_model_cache_key(model.path()).unwrap();

        assert_ne!(first_key, second_key);
    }

    #[test]
    fn sanitizes_coreml_cache_component() {
        assert_eq!(
            sanitize_cache_component("model name.onnx"),
            "model_name.onnx"
        );
    }

    #[test]
    fn prunes_only_superseded_directories_for_one_model() {
        let root = tempfile::tempdir().unwrap();
        let old_cache = root.path().join("old");
        let current_cache = root.path().join("current");
        std::fs::create_dir(&old_cache).unwrap();
        std::fs::create_dir(&current_cache).unwrap();
        std::fs::write(root.path().join("marker"), b"keep").unwrap();

        prune_superseded_coreml_cache_directories(root.path(), "current").unwrap();

        assert!(!old_cache.exists());
        assert!(current_cache.exists());
        assert!(root.path().join("marker").exists());
    }

    #[test]
    fn prunes_stale_schema_directories_keeping_current_and_files() {
        let coreml_root = tempfile::tempdir().unwrap();
        let stale = coreml_root.path().join("ort-1_26-mlprogram-all-default-v1");
        let current = coreml_root.path().join("ort-1_27-mlprogram-all-default-v1");
        std::fs::create_dir(&stale).unwrap();
        std::fs::write(stale.join("cached"), b"stale").unwrap();
        std::fs::create_dir(&current).unwrap();
        std::fs::write(coreml_root.path().join("stray-file"), b"keep").unwrap();

        let removed = prune_stale_coreml_schema_directories(
            coreml_root.path(),
            "ort-1_27-mlprogram-all-default-v1",
        )
        .unwrap();

        assert_eq!(removed, vec!["ort-1_26-mlprogram-all-default-v1"]);
        assert!(!stale.exists());
        assert!(current.exists());
        assert!(coreml_root.path().join("stray-file").exists());
    }

    #[test]
    fn schema_pruning_treats_a_missing_root_as_empty() {
        let parent = tempfile::tempdir().unwrap();
        let removed =
            prune_stale_coreml_schema_directories(&parent.path().join("missing"), "current")
                .unwrap();
        assert!(removed.is_empty());
    }

    /// Mirrors the ORT 1.27 MLProgram cache layout: the generated package at
    /// `<cache_dir>/<model_hash>/<partition>/model/` holds its weights under
    /// `Data/com.microsoft.OnnxRuntime/weights/weight.bin`, and the compiled
    /// model is stored INSIDE the package directory as
    /// `model/compiled_model.mlmodelc` (which keeps its own
    /// `weights/weight.bin` copy).
    fn write_cache_partition(
        cache_dir: &Path,
        partition: &str,
        compiled: bool,
    ) -> std::path::PathBuf {
        let package_dir = cache_dir.join("modelhash").join(partition).join("model");
        let weights_dir = package_dir
            .join("Data")
            .join("com.microsoft.OnnxRuntime")
            .join("weights");
        std::fs::create_dir_all(&weights_dir).unwrap();
        let weight_blob = weights_dir.join("weight.bin");
        std::fs::write(&weight_blob, b"weights").unwrap();
        std::fs::write(package_dir.join("Manifest.json"), b"manifest").unwrap();
        if compiled {
            let compiled_weights_dir = package_dir.join("compiled_model.mlmodelc").join("weights");
            std::fs::create_dir_all(&compiled_weights_dir).unwrap();
            std::fs::write(compiled_weights_dir.join("weight.bin"), b"compiled-weights").unwrap();
        }
        weight_blob
    }

    #[test]
    fn trims_package_weights_only_where_a_compiled_model_exists() {
        let cache_dir = tempfile::tempdir().unwrap();
        let compiled_blob = write_cache_partition(cache_dir.path(), "0_static_mlprogram", true);
        let uncompiled_blob = write_cache_partition(cache_dir.path(), "1_static_mlprogram", false);
        mark_coreml_cache_complete(cache_dir.path()).unwrap();

        let reclaimed = trim_coreml_cache_weights(cache_dir.path()).unwrap();

        assert_eq!(reclaimed, b"weights".len() as u64);
        assert!(compiled_blob.exists());
        assert_eq!(std::fs::metadata(&compiled_blob).unwrap().len(), 0);
        // The package directory itself must survive: ONNX Runtime checks its
        // existence to decide the model is cached.
        let package_dir = compiled_blob.ancestors().nth(4).unwrap();
        assert!(package_dir.ends_with("model"));
        assert!(package_dir.is_dir());
        // The compiled model's own weight copy is what warm loads read; the
        // trim walk must never descend into the `.mlmodelc` bundle.
        assert_eq!(
            std::fs::read(
                package_dir
                    .join("compiled_model.mlmodelc")
                    .join("weights")
                    .join("weight.bin")
            )
            .unwrap(),
            b"compiled-weights".to_vec()
        );
        assert_eq!(std::fs::read(uncompiled_blob).unwrap(), b"weights".to_vec());
    }

    #[test]
    fn trimming_an_already_trimmed_cache_reclaims_nothing() {
        let cache_dir = tempfile::tempdir().unwrap();
        write_cache_partition(cache_dir.path(), "0_static_mlprogram", true);

        assert!(trim_coreml_cache_weights(cache_dir.path()).unwrap() > 0);
        assert_eq!(trim_coreml_cache_weights(cache_dir.path()).unwrap(), 0);
    }

    #[test]
    fn replaces_an_incomplete_coreml_cache_entry() {
        let root = tempfile::tempdir().unwrap();
        let cache_dir = root.path().join("current");
        std::fs::create_dir(&cache_dir).unwrap();
        let partial_artifact = cache_dir.join("partial.mlmodelc");
        std::fs::write(&partial_artifact, b"partial").unwrap();

        prepare_coreml_cache_entry(&cache_dir).unwrap();

        assert!(cache_dir.is_dir());
        assert!(!partial_artifact.exists());
    }

    #[test]
    fn preserves_a_completed_coreml_cache_entry() {
        let root = tempfile::tempdir().unwrap();
        let cache_dir = root.path().join("current");
        std::fs::create_dir(&cache_dir).unwrap();
        let artifact = cache_dir.join("model.mlmodelc");
        std::fs::write(&artifact, b"complete").unwrap();
        mark_coreml_cache_complete(&cache_dir).unwrap();

        prepare_coreml_cache_entry(&cache_dir).unwrap();

        assert!(artifact.exists());
    }

    #[test]
    fn invalidates_a_failed_coreml_cache_entry() {
        let root = tempfile::tempdir().unwrap();
        let cache_dir = root.path().join("current");
        std::fs::create_dir(&cache_dir).unwrap();

        invalidate_coreml_cache(&cache_dir).unwrap();

        assert!(!cache_dir.exists());
        invalidate_coreml_cache(&cache_dir).unwrap();
    }
}
