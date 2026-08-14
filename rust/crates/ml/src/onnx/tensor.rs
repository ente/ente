use std::cell::OnceCell;

use half::prelude::{HalfFloatSliceExt, HalfFloatVecExt};
use ort::{
    session::Session,
    value::{Tensor, TensorElementType, TensorRef, ValueType},
};

use crate::error::{MlError, MlResult};

use super::{SessionRunError, SessionRunResult, golden_test};

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

pub(super) fn run_golden_tensor(
    session: &mut Session,
    input_shape: &[i64],
    input: &golden_test::PreparedGoldenInput,
) -> SessionRunResult<Vec<f32>> {
    let outputs = match input {
        golden_test::PreparedGoldenInput::F32(data) => {
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
        golden_test::PreparedGoldenInput::I32(data) => {
            let input_tensor = TensorRef::<i32>::from_array_view((input_shape, data.as_slice()))?;
            session.run(ort::inputs![input_tensor])?
        }
    };

    if outputs.len() == 0 {
        return Err(MlError::Ort("missing first output tensor".to_string()).into());
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

fn ensure_finite_f32(data: &[f32]) -> SessionRunResult<()> {
    if data.iter().copied().all(f32::is_finite) {
        return Ok(());
    }
    Err(SessionRunError::retryable(MlError::Ort(
        "model produced non-finite output values".to_string(),
    )))
}

fn ensure_finite_f16(data: &[half::f16]) -> SessionRunResult<()> {
    if data.iter().all(|value| value.is_finite()) {
        return Ok(());
    }
    Err(SessionRunError::retryable(MlError::Ort(
        "model produced non-finite output values".to_string(),
    )))
}

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

pub(crate) fn run_f32<const N: usize>(
    session: &mut Session,
    input: &PreparedF32Input,
    input_shape: [i64; N],
) -> SessionRunResult<(Vec<i64>, Vec<f32>)> {
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
        return Err(MlError::Ort("missing first output tensor".to_string()).into());
    }
    let output = &outputs[0];

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

pub(crate) fn with_prepared_float_output<const N: usize, T>(
    session: &mut Session,
    input: &PreparedF32Input,
    input_shape: [i64; N],
    consume: impl FnOnce(&[i64], BorrowedFloatTensor<'_>) -> MlResult<T>,
) -> SessionRunResult<T> {
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
        return Err(MlError::Ort("missing first output tensor".to_string()).into());
    }
    let output = &outputs[0];
    if let Ok((tensor_shape, tensor_data)) = output.try_extract_tensor::<f32>() {
        ensure_finite_f32(tensor_data)?;
        consume(tensor_shape, BorrowedFloatTensor::F32(tensor_data)).map_err(Into::into)
    } else {
        let (tensor_shape, tensor_data) = output.try_extract_tensor::<half::f16>()?;
        ensure_finite_f16(tensor_data)?;
        consume(tensor_shape, BorrowedFloatTensor::F16(tensor_data)).map_err(Into::into)
    }
}

pub(crate) fn run_i32_f32<const N: usize>(
    session: &mut Session,
    input: &[i32],
    input_shape: [i64; N],
) -> SessionRunResult<(Vec<i64>, Vec<f32>)> {
    let input_tensor = TensorRef::<i32>::from_array_view((input_shape, input))?;
    let outputs = session.run(ort::inputs![input_tensor])?;
    if outputs.len() == 0 {
        return Err(MlError::Ort("missing first output tensor".to_string()).into());
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
    use super::{ensure_finite_f16, ensure_finite_f32};

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
            assert!(error.is_retryable());
        }
        let error = ensure_finite_f16(&[half::f16::NAN]).unwrap_err();
        assert!(error.to_string().contains("non-finite"));
        assert!(error.is_retryable());
    }
}
