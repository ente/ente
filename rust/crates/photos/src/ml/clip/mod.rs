mod image;
mod text;
mod tokenizer;

pub(super) use image::run_clip_image;
pub(super) use text::run_clip_text_query;
pub(super) use tokenizer::tokenize_clip_text;

use crate::ml::{
    error::{MlError, MlResult},
    postprocess::l2_normalize,
    types::ClipResult,
};

pub(super) const CLIP_IMAGE_INPUT_SIZE: usize = 256;
pub(super) const CLIP_TEXT_TOKEN_COUNT: usize = 77;

pub(super) fn finish_embedding(
    name: &str,
    shape: Vec<i64>,
    output: Vec<f32>,
) -> MlResult<ClipResult> {
    let mut embedding = if shape.len() == 2 {
        if shape[0] != 1 {
            return Err(MlError::Postprocess(format!(
                "unexpected {name} batch size in shape {:?}",
                shape
            )));
        }
        output
    } else if shape.len() == 1 {
        output
    } else {
        return Err(MlError::Postprocess(format!(
            "unsupported {name} output shape {:?}",
            shape
        )));
    };

    l2_normalize(&mut embedding, f32::EPSILON);
    Ok(ClipResult { embedding })
}
