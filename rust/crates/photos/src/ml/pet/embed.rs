use crate::ml::{
    error::{MlError, MlResult},
    onnx,
    runtime::MlRuntimeView,
    types::{DecodedImage, PetBodyResult, PetFaceResult},
};

use super::preprocess::{extract_crop, preprocess_pet_embedding};

const FACE_EMBED_INPUT_SIZE: i64 = 224;
const BODY_EMBED_INPUT_SIZE: i64 = 224;
const FACE_EMBED_CHANNELS: i64 = 3;
const BODY_EMBED_CHANNELS: i64 = 3;

/// Run pet face embedding on aligned face inputs.
///
/// The species parameter (0=dog, 1=cat) selects the model to use.
///
/// Input per face: CHW float32 of shape [1, 3, 224, 224], ImageNet-normalized.
/// Output: L2-normalized embedding vector (128-d for BYOL).
///
/// This mirrors `pet_pipeline/embedding.py` `Embedder.embed_face()`.
/// Run pet face embedding using each face's own `class_id` to select the model.
///
/// Faces are grouped by species and batched per model to avoid running the
/// wrong embedding model on any detection.
pub fn run_pet_face_embedding(
    runtime: &MlRuntimeView<'_>,
    aligned_faces: &[Vec<f32>],
    face_results: &mut [PetFaceResult],
) -> MlResult<()> {
    if aligned_faces.is_empty() {
        return Ok(());
    }
    if aligned_faces.len() != face_results.len() {
        return Err(MlError::Postprocess(format!(
            "aligned pet faces count ({}) does not match face result count ({})",
            aligned_faces.len(),
            face_results.len()
        )));
    }

    let per_face_len =
        (FACE_EMBED_INPUT_SIZE * FACE_EMBED_INPUT_SIZE * FACE_EMBED_CHANNELS) as usize;

    // Group indices by species (class_id from detection).
    let mut dog_indices = Vec::new();
    let mut cat_indices = Vec::new();
    for (i, fr) in face_results.iter().enumerate() {
        if fr.detection.class_id == 1 {
            cat_indices.push(i);
        } else {
            dog_indices.push(i);
        }
    }

    // Process each species batch.
    for (species, indices) in [(0u8, &dog_indices), (1u8, &cat_indices)] {
        if indices.is_empty() {
            continue;
        }

        let mut input = Vec::with_capacity(per_face_len * indices.len());
        for &idx in indices {
            let aligned = &aligned_faces[idx];
            if aligned.len() != per_face_len {
                return Err(MlError::Preprocess(format!(
                    "aligned pet face tensor length {} does not match expected {}",
                    aligned.len(),
                    per_face_len
                )));
            }
            input.extend_from_slice(aligned);
        }

        let mut session = if species == 0 {
            runtime.pet_face_embedding_dog_session()?
        } else {
            runtime.pet_face_embedding_cat_session()?
        };

        let (shape, output) = onnx::run_f32(
            &mut session,
            input,
            [
                indices.len() as i64,
                FACE_EMBED_CHANNELS,
                FACE_EMBED_INPUT_SIZE,
                FACE_EMBED_INPUT_SIZE,
            ],
        )?;

        if shape.is_empty() {
            return Err(MlError::Postprocess(
                "pet face embedding output shape is empty".to_string(),
            ));
        }
        let batch = shape[0] as usize;
        if batch != indices.len() {
            return Err(MlError::Postprocess(format!(
                "pet face embedding batch mismatch: output={batch}, expected={}",
                indices.len()
            )));
        }
        let embedding_size = output.len() / batch;
        if embedding_size == 0 || output.len() != batch * embedding_size {
            return Err(MlError::Postprocess(format!(
                "pet face embedding output not evenly divisible: len={}, batch={batch}",
                output.len()
            )));
        }

        for (batch_idx, &orig_idx) in indices.iter().enumerate() {
            let start = batch_idx * embedding_size;
            let mut embedding = output[start..(start + embedding_size)].to_vec();
            normalize_embedding(&mut embedding);
            face_results[orig_idx].face_embedding = embedding;
            face_results[orig_idx].species = species;
        }
    }

    Ok(())
}

/// Run pet body embedding on cropped body regions.
///
/// Each body's own `coco_class` (16=dog, 15=cat) selects the embedding model,
/// so mixed-species images get the correct model per detection.
/// Bodies are grouped by species and batched per model.
///
/// This mirrors `pet_pipeline/embedding.py` `Embedder.embed_body()`.
pub fn run_pet_body_embedding(
    runtime: &MlRuntimeView<'_>,
    decoded: &DecodedImage,
    body_results: &mut [PetBodyResult],
) -> MlResult<()> {
    if body_results.is_empty() {
        return Ok(());
    }

    let per_body_len =
        (BODY_EMBED_INPUT_SIZE * BODY_EMBED_INPUT_SIZE * BODY_EMBED_CHANNELS) as usize;

    // Preprocess all crops and group by species.
    // Skip detections whose crop is invalid (e.g. zero-area edge boxes)
    // rather than aborting the whole image.
    let mut dog_indices = Vec::new();
    let mut cat_indices = Vec::new();
    let mut preprocessed: Vec<Option<Vec<f32>>> = Vec::with_capacity(body_results.len());
    for (i, body_result) in body_results.iter().enumerate() {
        let crop = extract_crop(decoded, &body_result.detection.box_xyxy).and_then(
            |(crop_data, crop_w, crop_h)| preprocess_pet_embedding(&crop_data, crop_w, crop_h),
        );
        match crop {
            Ok(input) => {
                preprocessed.push(Some(input));
                if body_result.detection.coco_class == 15 {
                    cat_indices.push(i);
                } else {
                    dog_indices.push(i);
                }
            }
            Err(_) => {
                preprocessed.push(None);
            }
        }
    }

    // Process each species batch.
    for (is_cat, indices) in [(false, &dog_indices), (true, &cat_indices)] {
        if indices.is_empty() {
            continue;
        }

        let mut input = Vec::with_capacity(per_body_len * indices.len());
        for &idx in indices {
            input.extend_from_slice(preprocessed[idx].as_ref().unwrap());
        }

        let mut session = if is_cat {
            runtime.pet_body_embedding_cat_session()?
        } else {
            runtime.pet_body_embedding_dog_session()?
        };

        let (shape, output) = onnx::run_f32(
            &mut session,
            input,
            [
                indices.len() as i64,
                BODY_EMBED_CHANNELS,
                BODY_EMBED_INPUT_SIZE,
                BODY_EMBED_INPUT_SIZE,
            ],
        )?;

        if shape.is_empty() {
            return Err(MlError::Postprocess(
                "pet body embedding output shape is empty".to_string(),
            ));
        }
        let batch = shape[0] as usize;
        if batch != indices.len() {
            return Err(MlError::Postprocess(format!(
                "pet body embedding batch mismatch: output={batch}, expected={}",
                indices.len()
            )));
        }
        let embedding_size = output.len() / batch;
        if embedding_size == 0 || output.len() != batch * embedding_size {
            return Err(MlError::Postprocess(format!(
                "pet body embedding output not evenly divisible: len={}, batch={batch}",
                output.len()
            )));
        }

        for (batch_idx, &orig_idx) in indices.iter().enumerate() {
            let start = batch_idx * embedding_size;
            let mut embedding = output[start..(start + embedding_size)].to_vec();
            normalize_embedding(&mut embedding);
            body_results[orig_idx].body_embedding = embedding;
        }
    }

    Ok(())
}

fn normalize_embedding(embedding: &mut [f32]) {
    let mut norm = 0.0f32;
    for value in embedding.iter() {
        norm += value * value;
    }
    let norm = norm.sqrt();
    if norm <= 1e-12 {
        return;
    }
    for value in embedding.iter_mut() {
        *value /= norm;
    }
}
