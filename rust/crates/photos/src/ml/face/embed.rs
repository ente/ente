use crate::ml::{
    error::{MlError, MlResult},
    onnx,
    runtime::MlRuntimeView,
    types::FaceResult,
};

const FACE_INPUT_WIDTH: i64 = 112;
const FACE_INPUT_HEIGHT: i64 = 112;
const FACE_INPUT_CHANNELS: i64 = 3;

pub fn run_face_embedding(
    runtime: &MlRuntimeView<'_>,
    aligned_faces: &[Vec<f32>],
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

    let per_face_len = (FACE_INPUT_WIDTH * FACE_INPUT_HEIGHT * FACE_INPUT_CHANNELS) as usize;
    let mut input = Vec::with_capacity(per_face_len * aligned_faces.len());
    for aligned in aligned_faces {
        if aligned.len() != per_face_len {
            return Err(MlError::Preprocess(format!(
                "aligned face tensor length {} does not match expected {}",
                aligned.len(),
                per_face_len
            )));
        }
        input.extend_from_slice(aligned);
    }

    let mut face_embedding = runtime.face_embedding_session()?;
    let (shape, output) = onnx::run_f32(
        &mut face_embedding,
        input,
        [
            aligned_faces.len() as i64,
            FACE_INPUT_HEIGHT,
            FACE_INPUT_WIDTH,
            FACE_INPUT_CHANNELS,
        ],
    )?;
    if shape.is_empty() {
        return Err(MlError::Postprocess(
            "face embedding output shape is empty".to_string(),
        ));
    }
    let batch = shape[0] as usize;
    if batch != face_results.len() {
        return Err(MlError::Postprocess(format!(
            "face embedding batch mismatch: output={batch}, expected={}",
            face_results.len()
        )));
    }
    let embedding_size = output.len() / batch;
    if embedding_size == 0 || output.len() != batch * embedding_size {
        return Err(MlError::Postprocess(format!(
            "invalid face embedding tensor shape {:?} for data length {}",
            shape,
            output.len()
        )));
    }

    for (face_index, face_result) in face_results.iter_mut().enumerate() {
        let start = face_index * embedding_size;
        let mut embedding = output[start..(start + embedding_size)].to_vec();
        normalize_embedding(&mut embedding);
        face_result.embedding = embedding;
    }

    Ok(())
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
