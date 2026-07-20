use ort::{
    ep::{CPU, ExecutionProviderDispatch, XNNPACK},
    session::{Session, builder::GraphOptimizationLevel},
    value::{Tensor, TensorElementType, ValueType},
};

// Temporarily disabled on Rust side to avoid iOS duplicate ObjC class collisions
// (`CoreMLExecution`) while Dart ONNXRuntime is still linked in production.
// Re-enable once iOS uses a single shared ORT runtime.
// #[cfg(target_vendor = "apple")]
// use ort::ep::CoreML;
#[cfg(target_os = "android")]
use ort::ep::NNAPI;

use crate::ml::{
    error::{MlError, MlResult},
    runtime::ExecutionProviderPolicy,
};

pub fn build_session(model_path: &str, policy: &ExecutionProviderPolicy) -> MlResult<Session> {
    let primary_providers = providers_for_policy(policy, true);
    let mut attempts = vec![primary_providers];

    if policy.allow_cpu_fallback && policy.prefer_xnnpack {
        let providers_without_xnnpack = providers_for_policy(policy, false);
        attempts.push(providers_without_xnnpack);
    }

    if policy.allow_cpu_fallback {
        let cpu_only_policy = ExecutionProviderPolicy {
            prefer_coreml: false,
            prefer_nnapi: false,
            prefer_xnnpack: false,
            allow_cpu_fallback: true,
        };
        let cpu_only_providers = providers_for_policy(&cpu_only_policy, false);
        attempts.push(cpu_only_providers);
    }

    let mut errors = Vec::new();
    for providers in attempts {
        if providers.is_empty() {
            continue;
        }

        match build_session_with_providers(model_path, providers) {
            Ok(session) => return Ok(session),
            Err(error) => errors.push(format!("{error}")),
        }
    }

    if errors.is_empty() {
        return Err(MlError::InvalidRequest(
            "no supported execution provider selected for this platform while CPU fallback is disabled"
                .to_string(),
        ));
    }

    if has_protobuf_parse_failure(&errors) {
        return Err(MlError::CorruptModel(model_path.to_string()));
    }

    Err(MlError::Ort(format!(
        "failed to create ONNX session for model '{model_path}' across EP fallbacks: {}",
        errors.join(" | ")
    )))
}

fn has_protobuf_parse_failure(errors: &[String]) -> bool {
    errors.iter().any(|error| {
        error
            .to_ascii_lowercase()
            .contains("protobuf parsing failed")
    })
}

fn providers_for_policy(
    policy: &ExecutionProviderPolicy,
    include_xnnpack: bool,
) -> Vec<ExecutionProviderDispatch> {
    let mut providers: Vec<ExecutionProviderDispatch> = Vec::new();

    // Temporarily disabled on Rust side. Keep this block for easy re-enable.
    // #[cfg(target_vendor = "apple")]
    // if policy.prefer_coreml {
    //     providers.push(CoreML::default().build());
    // }

    #[cfg(target_os = "android")]
    if policy.prefer_nnapi {
        // Prefer NNAPI accelerators and let ORT handle CPU fallback via the added CPU EP.
        providers.push(NNAPI::default().with_disable_cpu(true).build());
    }

    if policy.allow_cpu_fallback {
        if include_xnnpack && policy.prefer_xnnpack {
            providers.push(XNNPACK::default().build());
        }
        providers.push(CPU::default().with_arena_allocator(true).build());
    }

    providers
}

fn build_session_with_providers(
    model_path: &str,
    providers: Vec<ExecutionProviderDispatch>,
) -> MlResult<Session> {
    let mut builder = Session::builder()?
        .with_optimization_level(GraphOptimizationLevel::All)?
        .with_intra_threads(1)?
        .with_inter_threads(1)?;

    builder = builder.with_execution_providers(providers)?;

    let session = builder.commit_from_file(model_path)?;
    Ok(session)
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
pub fn run_f32<const N: usize>(
    session: &mut Session,
    input: Vec<f32>,
    input_shape: [i64; N],
) -> MlResult<(Vec<i64>, Vec<f32>)> {
    let outputs = if session_expects_f16(session) {
        let f16_input: Vec<half::f16> = input.into_iter().map(half::f16::from_f32).collect();
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
        Ok((shape, data))
    } else {
        let (tensor_shape, tensor_data) = output.try_extract_tensor::<half::f16>()?;
        let shape = tensor_shape.iter().copied().collect::<Vec<_>>();
        let data = tensor_data
            .iter()
            .map(|v: &half::f16| v.to_f32())
            .collect::<Vec<_>>();
        Ok((shape, data))
    }
}

pub fn run_f32_data<const N: usize>(
    session: &mut Session,
    input: Vec<f32>,
    input_shape: [i64; N],
) -> MlResult<Vec<f32>> {
    let outputs = if session_expects_f16(session) {
        let f16_input: Vec<half::f16> = input.into_iter().map(half::f16::from_f32).collect();
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
    if let Ok((_tensor_shape, tensor_data)) = output.try_extract_tensor::<f32>() {
        Ok(tensor_data.to_vec())
    } else {
        let (_tensor_shape, tensor_data) = output.try_extract_tensor::<half::f16>()?;
        Ok(tensor_data
            .iter()
            .map(|v: &half::f16| v.to_f32())
            .collect::<Vec<_>>())
    }
}

pub fn run_i32_f32<const N: usize>(
    session: &mut Session,
    input: Vec<i32>,
    input_shape: [i64; N],
) -> MlResult<(Vec<i64>, Vec<f32>)> {
    let input_tensor = Tensor::<i32>::from_array((input_shape, input))?;
    let outputs = session.run(ort::inputs![input_tensor])?;
    if outputs.len() == 0 {
        return Err(MlError::Ort("missing first output tensor".to_string()));
    }
    let output = &outputs[0];
    let (tensor_shape, tensor_data) = output.try_extract_tensor::<f32>()?;
    let shape = tensor_shape.iter().copied().collect::<Vec<_>>();
    let data = tensor_data.to_vec();
    Ok((shape, data))
}

#[cfg(test)]
mod tests {
    use super::has_protobuf_parse_failure;

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
}
