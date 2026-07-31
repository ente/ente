use crate::ml::{
    clip::tokenizer,
    error::{MlError, MlResult},
    onnx,
    runtime::MlRuntimeView,
    types::ClipResult,
};

use super::{CLIP_TEXT_TOKEN_COUNT, finish_embedding};

fn run_clip_text(runtime: &MlRuntimeView<'_>, token_ids: &[i32]) -> MlResult<ClipResult> {
    if token_ids.len() != CLIP_TEXT_TOKEN_COUNT {
        return Err(MlError::InvalidRequest(format!(
            "clip text expects exactly {CLIP_TEXT_TOKEN_COUNT} tokens, got {}",
            token_ids.len()
        )));
    }

    let mut clip_text = runtime.clip_text_session()?;
    let (shape, output) =
        onnx::run_i32_f32(&mut clip_text, token_ids, [1, CLIP_TEXT_TOKEN_COUNT as i64])?;

    finish_embedding("CLIP text", shape, output)
}

pub(crate) fn run_clip_text_query(
    runtime: &MlRuntimeView<'_>,
    query: &str,
    vocab_path: &str,
) -> MlResult<ClipResult> {
    let token_ids = tokenizer::tokenize_clip_text(query, vocab_path)?;
    run_clip_text(runtime, &token_ids)
}
