use crate::ml::{
    clip::tokenizer,
    error::{MlError, MlResult},
    onnx,
    runtime::MlRuntimeView,
    types::ClipResult,
};

const CLIP_TEXT_TOKEN_COUNT: usize = 77;

pub fn run_clip_text(runtime: &MlRuntimeView<'_>, token_ids: &[i32]) -> MlResult<ClipResult> {
    if token_ids.len() != CLIP_TEXT_TOKEN_COUNT {
        return Err(MlError::InvalidRequest(format!(
            "clip text expects exactly {CLIP_TEXT_TOKEN_COUNT} tokens, got {}",
            token_ids.len()
        )));
    }

    let mut clip_text = runtime.clip_text_session()?;
    let (shape, output) = onnx::run_i32_f32(
        &mut clip_text,
        token_ids.to_vec(),
        [1, CLIP_TEXT_TOKEN_COUNT as i64],
    )?;

    let mut embedding = if shape.len() == 2 {
        if shape[0] != 1 {
            return Err(MlError::Postprocess(format!(
                "unexpected CLIP text batch size in shape {:?}",
                shape
            )));
        }
        output
    } else if shape.len() == 1 {
        output
    } else {
        return Err(MlError::Postprocess(format!(
            "unsupported CLIP text output shape {:?}",
            shape
        )));
    };

    normalize_embedding(&mut embedding);
    Ok(ClipResult { embedding })
}

pub fn run_clip_text_query(
    runtime: &MlRuntimeView<'_>,
    query: &str,
    vocab_path: &str,
) -> MlResult<ClipResult> {
    let token_ids = tokenizer::tokenize_clip_text(query, vocab_path)?;
    run_clip_text(runtime, &token_ids)
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
