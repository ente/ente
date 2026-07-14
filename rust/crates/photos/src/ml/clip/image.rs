use crate::ml::{
    error::{MlError, MlResult},
    onnx, preprocess,
    runtime::MlRuntimeView,
    types::{ClipResult, DecodedImage},
};

pub fn run_clip_image(runtime: &MlRuntimeView<'_>, decoded: &DecodedImage) -> MlResult<ClipResult> {
    let input = preprocess::preprocess_clip(decoded)?;
    let mut clip_image = runtime.clip_image_session()?;
    let (shape, output) = onnx::run_f32(&mut clip_image, input, [1, 3, 256, 256])?;

    let mut embedding = if shape.len() == 2 {
        if shape[0] != 1 {
            return Err(MlError::Postprocess(format!(
                "unexpected CLIP batch size in shape {:?}",
                shape
            )));
        }
        output
    } else if shape.len() == 1 {
        output
    } else {
        return Err(MlError::Postprocess(format!(
            "unsupported CLIP output shape {:?}",
            shape
        )));
    };
    normalize_embedding(&mut embedding);
    Ok(ClipResult { embedding })
}

fn normalize_embedding(embedding: &mut [f32]) {
    let mut norm = 0.0f32;
    for value in embedding.iter() {
        norm += value * value;
    }
    let norm = norm.sqrt();
    if norm <= f32::EPSILON {
        return;
    }
    for value in embedding.iter_mut() {
        *value /= norm;
    }
}
