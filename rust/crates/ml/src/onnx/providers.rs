use ort::{
    ep::{CPU, ExecutionProviderDispatch},
    session::{Session, builder::GraphOptimizationLevel},
};
use std::path::{Path, PathBuf};

#[cfg(target_os = "android")]
use ort::ep::XNNPACK;
#[cfg(any(target_os = "ios", target_os = "macos"))]
use ort::ep::{
    CoreML,
    coreml::{ComputeUnits, ModelFormat, SpecializationStrategy},
};
#[cfg(any(target_os = "android", target_os = "linux", target_os = "windows"))]
use ort::ep::{
    WebGPU,
    webgpu::{DawnBackendType, PreferredLayout},
};
#[cfg(target_os = "android")]
use std::num::NonZeroUsize;

#[cfg(any(target_os = "ios", target_os = "macos"))]
use super::coreml_cache;
#[cfg(any(
    target_os = "android",
    target_os = "ios",
    target_os = "linux",
    target_os = "macos",
    target_os = "windows"
))]
use super::golden_test;
#[cfg(any(
    target_os = "android",
    target_os = "ios",
    target_os = "linux",
    target_os = "macos",
    target_os = "windows"
))]
use super::model_file_label;
#[cfg(any(target_os = "android", target_os = "linux", target_os = "windows"))]
use super::webgpu;
use super::{AccelerationValidation, session_load_error};
use crate::error::MlResult;

#[cfg(any(target_os = "ios", target_os = "macos"))]
const ENABLE_PERSISTENT_COREML_CACHE: bool = true;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum ExecutionMode {
    PlatformDefault,
    CpuAccelerated,
    CpuOnly,
}

// Identifies the successful attempt's preferred provider, not its registered
// fallback providers, for result attribution.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[allow(dead_code)] // Accelerated variants are constructed only on their target OS.
pub(super) enum ExecutionProvider {
    CoreMl,
    WebGpu,
    Xnnpack,
    Cpu,
}

#[derive(Debug)]
pub(super) struct ProviderPlan {
    providers: Vec<ExecutionProvider>,
    next: usize,
    selected: Option<ExecutionProvider>,
}

impl ProviderPlan {
    pub(super) fn new(
        mode: ExecutionMode,
        model_path: &str,
        validation: AccelerationValidation,
    ) -> Self {
        let providers = match mode {
            ExecutionMode::PlatformDefault => platform_default_providers(model_path, validation),
            ExecutionMode::CpuAccelerated => cpu_accelerated_providers(),
            ExecutionMode::CpuOnly => vec![ExecutionProvider::Cpu],
        };
        Self::from_providers(providers)
    }

    fn from_providers(providers: Vec<ExecutionProvider>) -> Self {
        Self {
            providers,
            next: 0,
            selected: None,
        }
    }

    fn next_provider(&mut self) -> Option<ExecutionProvider> {
        let provider = self.providers.get(self.next).copied()?;
        self.next += 1;
        Some(provider)
    }

    fn select(&mut self, provider: ExecutionProvider) {
        self.selected = Some(provider);
    }

    pub(super) fn selected_provider(&self) -> Option<ExecutionProvider> {
        self.selected
    }

    pub(super) fn has_fallback(&self) -> bool {
        self.next < self.providers.len()
    }

    fn retain_last_provider_for_retry(&mut self) {
        self.selected = None;
        self.next = self.providers.len().saturating_sub(1);
    }
}

pub(super) fn run_provider_plan<T, E>(
    plan: &mut ProviderPlan,
    mut attempt: impl FnMut(ExecutionProvider) -> Result<T, E>,
) -> Result<T, Vec<E>> {
    plan.selected = None;

    let mut errors = Vec::new();
    while let Some(provider) = plan.next_provider() {
        match attempt(provider) {
            Ok(value) => {
                plan.select(provider);
                return Ok(value);
            }
            Err(error) => errors.push(error),
        }
    }

    plan.retain_last_provider_for_retry();
    Err(errors)
}

pub(super) struct ProviderAttempt {
    providers: Vec<ExecutionProviderDispatch>,
    disable_intra_op_spinning: bool,
    coreml_cache_dir: Option<PathBuf>,
    execution_provider: ExecutionProvider,
}

impl ProviderAttempt {
    fn cpu_only() -> Self {
        Self {
            providers: vec![CPU::default().with_arena_allocator(true).build()],
            disable_intra_op_spinning: false,
            coreml_cache_dir: None,
            execution_provider: ExecutionProvider::Cpu,
        }
    }

    pub(super) fn coreml_cache_dir(&self) -> Option<&Path> {
        self.coreml_cache_dir.as_deref()
    }

    pub(super) fn execution_provider(&self) -> ExecutionProvider {
        self.execution_provider
    }
}

pub(super) fn provider_attempt(
    provider: ExecutionProvider,
    _model_path: &str,
    _model_namespace: &str,
) -> ProviderAttempt {
    match provider {
        ExecutionProvider::Cpu => ProviderAttempt::cpu_only(),
        #[cfg(any(target_os = "ios", target_os = "macos"))]
        ExecutionProvider::CoreMl => {
            let (coreml_provider, coreml_cache_dir) =
                coreml_provider(_model_path, _model_namespace);
            ProviderAttempt {
                providers: vec![
                    coreml_provider,
                    CPU::default().with_arena_allocator(true).build(),
                ],
                disable_intra_op_spinning: false,
                coreml_cache_dir,
                execution_provider: ExecutionProvider::CoreMl,
            }
        }
        #[cfg(any(target_os = "android", target_os = "linux", target_os = "windows"))]
        ExecutionProvider::WebGpu => ProviderAttempt {
            providers: webgpu_attempt_providers(),
            disable_intra_op_spinning: true,
            coreml_cache_dir: None,
            execution_provider: ExecutionProvider::WebGpu,
        },
        #[cfg(target_os = "android")]
        ExecutionProvider::Xnnpack => xnnpack_attempt(),
        #[allow(unreachable_patterns)]
        _ => unreachable!("provider is not available on this platform"),
    }
}

pub(super) fn build_session(model_path: &str, attempt: ProviderAttempt) -> MlResult<Session> {
    let mut builder = Session::builder()?
        .with_optimization_level(GraphOptimizationLevel::All)?
        .with_intra_threads(1)?
        .with_inter_threads(1)?;

    if attempt.disable_intra_op_spinning {
        builder = builder.with_intra_op_spinning(false)?;
    }
    builder = builder.with_execution_providers(attempt.providers)?;

    let session = builder
        .commit_from_file(model_path)
        .map_err(|error| session_load_error(model_path, error))?;
    Ok(session)
}

#[cfg(any(target_os = "ios", target_os = "macos"))]
fn platform_default_providers(
    model_path: &str,
    validation: AccelerationValidation,
) -> Vec<ExecutionProvider> {
    let mut providers = Vec::new();
    if accelerated_provider_allowed(model_path, "CoreML", validation) {
        providers.push(ExecutionProvider::CoreMl);
    }
    providers.push(ExecutionProvider::Cpu);
    providers
}

#[cfg(target_os = "android")]
fn platform_default_providers(
    model_path: &str,
    validation: AccelerationValidation,
) -> Vec<ExecutionProvider> {
    let mut providers = Vec::new();
    if webgpu::attempt_permitted(model_path)
        && accelerated_provider_allowed(model_path, "WebGPU", validation)
    {
        providers.push(ExecutionProvider::WebGpu);
    }
    providers.push(ExecutionProvider::Xnnpack);
    providers.push(ExecutionProvider::Cpu);
    providers
}

#[cfg(any(target_os = "linux", target_os = "windows"))]
fn platform_default_providers(
    model_path: &str,
    validation: AccelerationValidation,
) -> Vec<ExecutionProvider> {
    let mut providers = Vec::new();
    if webgpu::attempt_permitted(model_path)
        && accelerated_provider_allowed(model_path, "WebGPU", validation)
    {
        providers.push(ExecutionProvider::WebGpu);
    }
    providers.push(ExecutionProvider::Cpu);
    providers
}

#[cfg(not(any(
    target_os = "ios",
    target_os = "android",
    target_os = "linux",
    target_os = "macos",
    target_os = "windows"
)))]
fn platform_default_providers(
    _model_path: &str,
    _validation: AccelerationValidation,
) -> Vec<ExecutionProvider> {
    vec![ExecutionProvider::Cpu]
}

#[cfg(target_os = "android")]
fn cpu_accelerated_providers() -> Vec<ExecutionProvider> {
    vec![ExecutionProvider::Xnnpack, ExecutionProvider::Cpu]
}

#[cfg(not(target_os = "android"))]
fn cpu_accelerated_providers() -> Vec<ExecutionProvider> {
    vec![ExecutionProvider::Cpu]
}

// Missing goldens fail closed, usually indicating they were not regenerated
// after an update.
#[cfg(any(
    target_os = "android",
    target_os = "ios",
    target_os = "linux",
    target_os = "macos",
    target_os = "windows"
))]
fn accelerated_provider_allowed(
    model_path: &str,
    provider_label: &str,
    validation: AccelerationValidation,
) -> bool {
    if validation == AccelerationValidation::Unvalidated
        || golden_test::lookup(model_path).is_some()
    {
        return true;
    }
    log::error!(
        "no golden self-test entry for '{}'; {provider_label} disabled for this model",
        model_file_label(model_path)
    );
    false
}

#[cfg(any(target_os = "ios", target_os = "macos"))]
fn coreml_provider(
    model_path: &str,
    model_namespace: &str,
) -> (ExecutionProviderDispatch, Option<PathBuf>) {
    let mut provider = CoreML::default()
        .with_model_format(ModelFormat::MLProgram)
        .with_compute_units(ComputeUnits::All)
        .with_specialization_strategy(SpecializationStrategy::Default);

    let mut prepared_cache_dir = None;
    if ENABLE_PERSISTENT_COREML_CACHE {
        match coreml_cache::prepare_directory(model_path, model_namespace) {
            Ok(cache_dir) => {
                provider = provider.with_model_cache_dir(cache_dir.to_string_lossy());
                prepared_cache_dir = Some(cache_dir);
            }
            Err(error) => {
                log::warn!(
                    "failed to prepare persistent CoreML cache for '{}'; continuing without it: {error}",
                    model_file_label(model_path)
                );
            }
        }
    } else {
        coreml_cache::remove(model_path);
    }

    (provider.build().error_on_failure(), prepared_cache_dir)
}

#[cfg(any(target_os = "android", target_os = "linux", target_os = "windows"))]
fn webgpu_provider() -> ExecutionProviderDispatch {
    let provider = WebGPU::default().with_preferred_layout(PreferredLayout::NCHW);
    #[cfg(any(target_os = "android", target_os = "linux"))]
    let provider = provider.with_dawn_backend_type(DawnBackendType::Vulkan);
    #[cfg(target_os = "windows")]
    let provider = provider.with_dawn_backend_type(DawnBackendType::D3D12);
    provider.build().error_on_failure()
}

#[cfg(target_os = "android")]
fn webgpu_attempt_providers() -> Vec<ExecutionProviderDispatch> {
    vec![
        webgpu_provider(),
        xnnpack_provider().fail_silently(),
        CPU::default().with_arena_allocator(true).build(),
    ]
}

#[cfg(any(target_os = "linux", target_os = "windows"))]
fn webgpu_attempt_providers() -> Vec<ExecutionProviderDispatch> {
    vec![
        webgpu_provider(),
        CPU::default().with_arena_allocator(true).build(),
    ]
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
        execution_provider: ExecutionProvider::Xnnpack,
    }
}

#[cfg(test)]
mod tests {
    use super::{
        AccelerationValidation, ExecutionMode, ExecutionProvider, ProviderPlan, run_provider_plan,
    };

    #[test]
    fn construction_falls_through_and_selects_the_successful_provider() {
        let mut plan = accelerated_provider_plan();
        let mut attempted = Vec::new();

        let result = run_provider_plan(&mut plan, |provider| {
            attempted.push(provider);
            match provider {
                ExecutionProvider::Xnnpack => Ok("session"),
                _ => Err(provider),
            }
        });

        assert_eq!(result, Ok("session"));
        assert_eq!(
            attempted,
            [ExecutionProvider::WebGpu, ExecutionProvider::Xnnpack]
        );
        assert_eq!(plan.selected_provider(), Some(ExecutionProvider::Xnnpack));
        assert!(plan.has_fallback());
    }

    #[test]
    fn retry_resumes_strictly_after_the_provider_that_was_selected() {
        let mut plan = accelerated_provider_plan();
        run_provider_plan(&mut plan, |provider| match provider {
            ExecutionProvider::Xnnpack => Ok(()),
            _ => Err(()),
        })
        .unwrap();

        let mut attempted = Vec::new();
        let result = run_provider_plan(&mut plan, |provider| {
            attempted.push(provider);
            Ok::<_, ()>("fallback session")
        });

        assert_eq!(result, Ok("fallback session"));
        assert_eq!(attempted, [ExecutionProvider::Cpu]);
        assert_eq!(plan.selected_provider(), Some(ExecutionProvider::Cpu));
        assert!(!plan.has_fallback());
    }

    #[test]
    fn provider_attempts_are_bounded_and_preserve_each_failure() {
        let mut plan = accelerated_provider_plan();
        let mut attempted = Vec::new();

        let errors = run_provider_plan::<(), _>(&mut plan, |provider| {
            attempted.push(provider);
            Err(provider)
        })
        .unwrap_err();

        assert_eq!(
            attempted,
            [
                ExecutionProvider::WebGpu,
                ExecutionProvider::Xnnpack,
                ExecutionProvider::Cpu,
            ]
        );
        assert_eq!(errors, attempted);
        assert_eq!(plan.selected_provider(), None);
    }

    #[test]
    fn exhausted_cpu_is_retained_as_the_only_construction_retry() {
        let mut plan = ProviderPlan::new(
            ExecutionMode::CpuOnly,
            "model.onnx",
            AccelerationValidation::GoldenRequired,
        );
        let mut attempts = 0;

        let first = run_provider_plan::<(), _>(&mut plan, |provider| {
            attempts += 1;
            Err(provider)
        });

        assert_eq!(first, Err(vec![ExecutionProvider::Cpu]));
        assert_eq!(attempts, 1);
        assert_eq!(plan.selected_provider(), None);
        assert!(plan.has_fallback());

        let retry = run_provider_plan(&mut plan, |provider| {
            attempts += 1;
            Ok::<_, ExecutionProvider>(provider)
        });

        assert_eq!(retry, Ok(ExecutionProvider::Cpu));
        assert_eq!(attempts, 2);
        assert_eq!(plan.selected_provider(), Some(ExecutionProvider::Cpu));
        assert!(!plan.has_fallback());
    }

    #[test]
    fn cpu_accelerated_plan_ends_with_cpu_and_never_uses_gpu_providers() {
        let plan = ProviderPlan::new(
            ExecutionMode::CpuAccelerated,
            "model.onnx",
            AccelerationValidation::Unvalidated,
        );

        assert_eq!(plan.providers.last(), Some(&ExecutionProvider::Cpu));
        assert!(!plan.providers.iter().any(|provider| matches!(
            provider,
            ExecutionProvider::WebGpu | ExecutionProvider::CoreMl
        )));
    }

    fn accelerated_provider_plan() -> ProviderPlan {
        ProviderPlan::from_providers(vec![
            ExecutionProvider::WebGpu,
            ExecutionProvider::Xnnpack,
            ExecutionProvider::Cpu,
        ])
    }
}
