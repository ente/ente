use crate::ml::{
    error::{MlError, MlResult},
    onnx,
    postprocess::l2_normalize,
    runtime::MlRuntimeView,
    types::{DecodedImage, PetBodyResult, PetFaceResult},
};

use super::{
    COCO_CAT, PET_EMBEDDING_CHANNELS, PET_EMBEDDING_INPUT_SIZE, PET_SPECIES_CAT, PET_SPECIES_DOG,
    preprocess::{IndexedEmbeddingBatch, PetEmbeddingPreprocessor, PetFaceEmbeddingInputs},
};

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
pub(crate) fn run_pet_face_embedding(
    runtime: &MlRuntimeView<'_>,
    aligned_faces: PetFaceEmbeddingInputs,
    face_results: &mut [PetFaceResult],
) -> MlResult<()> {
    let aligned_count = aligned_faces.dog.indices.len() + aligned_faces.cat.indices.len();
    if aligned_count == 0 {
        return Ok(());
    }
    if aligned_count != face_results.len() {
        return Err(MlError::Postprocess(format!(
            "aligned pet faces count ({}) does not match face result count ({})",
            aligned_count,
            face_results.len()
        )));
    }

    let per_face_len = PET_EMBEDDING_INPUT_SIZE * PET_EMBEDDING_INPUT_SIZE * PET_EMBEDDING_CHANNELS;

    for (species, batch) in [
        (PET_SPECIES_DOG, aligned_faces.dog),
        (PET_SPECIES_CAT, aligned_faces.cat),
    ] {
        if batch.is_empty() {
            continue;
        }
        if batch.input.len() != per_face_len * batch.indices.len() {
            return Err(MlError::Preprocess(format!(
                "pet face batch tensor length {} does not match expected {}",
                batch.input.len(),
                per_face_len * batch.indices.len()
            )));
        }

        let mut session = if species == PET_SPECIES_DOG {
            runtime.pet_face_embedding_dog_session()?
        } else {
            runtime.pet_face_embedding_cat_session()?
        };

        let (shape, output) = onnx::run_f32(
            &mut session,
            batch.input,
            [
                batch.indices.len() as i64,
                PET_EMBEDDING_CHANNELS as i64,
                PET_EMBEDDING_INPUT_SIZE as i64,
                PET_EMBEDDING_INPUT_SIZE as i64,
            ],
        )?;

        let embedding_size =
            validate_embedding_batch_output("face", &shape, output.len(), batch.indices.len())?;

        for (batch_idx, &orig_idx) in batch.indices.iter().enumerate() {
            let start = batch_idx * embedding_size;
            let mut embedding = output[start..(start + embedding_size)].to_vec();
            l2_normalize(&mut embedding, 1e-12);
            face_results[orig_idx].face_embedding = embedding;
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
pub(crate) fn run_pet_body_embedding(
    runtime: &MlRuntimeView<'_>,
    decoded: &DecodedImage,
    body_results: &mut [PetBodyResult],
) -> MlResult<()> {
    if body_results.is_empty() {
        return Ok(());
    }

    let per_body_len = PET_EMBEDDING_INPUT_SIZE * PET_EMBEDDING_INPUT_SIZE * PET_EMBEDDING_CHANNELS;

    // Preprocess all crops and group by species.
    // Skip detections whose crop is invalid (e.g. zero-area edge boxes)
    // rather than aborting the whole image.
    let cat_count = body_results
        .iter()
        .filter(|result| result.detection.coco_class == COCO_CAT)
        .count();
    let dog_count = body_results.len() - cat_count;
    let mut dog_batch = IndexedEmbeddingBatch::new(dog_count, per_body_len);
    let mut cat_batch = IndexedEmbeddingBatch::new(cat_count, per_body_len);
    let mut preprocessor = PetEmbeddingPreprocessor::new();

    for (i, body_result) in body_results.iter().enumerate() {
        let batch = if body_result.detection.coco_class == COCO_CAT {
            &mut cat_batch
        } else {
            &mut dog_batch
        };
        let original_len = batch.input.len();
        if preprocessor
            .append(decoded, &body_result.detection.box_xyxy, &mut batch.input)
            .is_ok()
        {
            batch.indices.push(i);
        } else {
            batch.input.truncate(original_len);
        }
    }

    for (is_cat, batch) in [(false, dog_batch), (true, cat_batch)] {
        if batch.is_empty() {
            continue;
        }

        let mut session = if is_cat {
            runtime.pet_body_embedding_cat_session()?
        } else {
            runtime.pet_body_embedding_dog_session()?
        };

        let (shape, output) = onnx::run_f32(
            &mut session,
            batch.input,
            [
                batch.indices.len() as i64,
                PET_EMBEDDING_CHANNELS as i64,
                PET_EMBEDDING_INPUT_SIZE as i64,
                PET_EMBEDDING_INPUT_SIZE as i64,
            ],
        )?;

        let embedding_size =
            validate_embedding_batch_output("body", &shape, output.len(), batch.indices.len())?;

        for (batch_idx, &orig_idx) in batch.indices.iter().enumerate() {
            let start = batch_idx * embedding_size;
            let mut embedding = output[start..(start + embedding_size)].to_vec();
            l2_normalize(&mut embedding, 1e-12);
            body_results[orig_idx].body_embedding = embedding;
        }
    }

    Ok(())
}

fn validate_embedding_batch_output(
    kind: &str,
    shape: &[i64],
    output_len: usize,
    expected_batch: usize,
) -> MlResult<usize> {
    if shape.is_empty() {
        return Err(MlError::Postprocess(format!(
            "pet {kind} embedding output shape is empty"
        )));
    }

    let output_batch = shape[0] as usize;
    if output_batch != expected_batch {
        return Err(MlError::Postprocess(format!(
            "pet {kind} embedding batch mismatch: output={output_batch}, expected={expected_batch}"
        )));
    }

    let embedding_size = output_len / output_batch;
    if embedding_size == 0 || output_len != output_batch * embedding_size {
        return Err(MlError::Postprocess(format!(
            "pet {kind} embedding output not evenly divisible: len={output_len}, batch={output_batch}"
        )));
    }

    Ok(embedding_size)
}

#[cfg(test)]
mod tests {
    use super::validate_embedding_batch_output;

    #[test]
    fn validates_pet_embedding_batch_shape() {
        assert_eq!(
            validate_embedding_batch_output("face", &[2, 128], 256, 2).unwrap(),
            128
        );
    }

    #[test]
    fn rejects_uneven_pet_embedding_output() {
        let error = validate_embedding_batch_output("body", &[2, 128], 255, 2).unwrap_err();

        assert_eq!(
            error.to_string(),
            "postprocess error: pet body embedding output not evenly divisible: len=255, batch=2"
        );
    }
}
