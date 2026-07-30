use crate::ml::{
    error::{MlError, MlResult},
    onnx,
    postprocess::l2_normalize,
    runtime::MlRuntimeView,
    types::FaceResult,
};

use super::FACE_INPUT_SIZE;

const FACE_INPUT_CHANNELS: i64 = 3;

pub(crate) fn run_face_embedding(
    runtime: &MlRuntimeView<'_>,
    aligned_faces: Vec<Vec<f32>>,
    face_results: &mut [FaceResult],
) -> MlResult<()> {
    if aligned_faces.is_empty() {
        return Ok(());
    }
    if aligned_faces.len() != face_results.len() {
        return Err(MlError::Postprocess(format!(
            "aligned faces count ({}) does not match face result count ({})",
            aligned_faces.len(),
            face_results.len()
        )));
    }

    let face_input_size = FACE_INPUT_SIZE as i64;
    let expected_input_len = (face_input_size * face_input_size * FACE_INPUT_CHANNELS) as usize;
    let mut face_embedding = runtime.face_embedding_session()?;
    for (aligned, face_result) in aligned_faces.into_iter().zip(face_results.iter_mut()) {
        if aligned.len() != expected_input_len {
            return Err(MlError::Preprocess(format!(
                "aligned face tensor length {} does not match expected {}",
                aligned.len(),
                expected_input_len
            )));
        }

        let (shape, mut embedding) = onnx::run_f32(
            &mut face_embedding,
            aligned,
            [1, face_input_size, face_input_size, FACE_INPUT_CHANNELS],
        )?;
        if shape.first() != Some(&1) || embedding.is_empty() {
            return Err(MlError::Postprocess(format!(
                "invalid single-face embedding tensor shape {:?} for data length {}",
                shape,
                embedding.len()
            )));
        }
        l2_normalize(&mut embedding, f32::EPSILON);
        face_result.embedding = embedding;
    }

    Ok(())
}
