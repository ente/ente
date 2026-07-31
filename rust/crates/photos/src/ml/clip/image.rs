use crate::ml::{
    error::MlResult,
    onnx, preprocess,
    runtime::MlRuntimeView,
    types::{ClipResult, DecodedImage},
};

use super::{CLIP_IMAGE_INPUT_SIZE, finish_embedding};

pub(crate) fn run_clip_image(
    runtime: &MlRuntimeView<'_>,
    decoded: &DecodedImage,
) -> MlResult<ClipResult> {
    let input = preprocess::preprocess_clip(decoded)?;
    let mut clip_image = runtime.clip_image_session()?;
    let (shape, output) = onnx::run_f32(
        &mut clip_image,
        input,
        [
            1,
            3,
            CLIP_IMAGE_INPUT_SIZE as i64,
            CLIP_IMAGE_INPUT_SIZE as i64,
        ],
    )?;

    finish_embedding("CLIP", shape, output)
}
