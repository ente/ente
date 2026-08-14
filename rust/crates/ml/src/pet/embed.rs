use crate::{
    error::{MlError, MlResult},
    models::Model,
    onnx,
    postprocess::l2_normalize,
    runtime::MlRuntimeView,
    types::{DecodedImage, PetBodyResult, PetFaceResult},
};

use super::{
    COCO_CAT, PET_EMBEDDING_CHANNELS, PET_EMBEDDING_INPUT_SIZE, PET_SPECIES_CAT, PET_SPECIES_DOG,
    preprocess::{IndexedEmbeddingBatch, PetEmbeddingPreprocessor, PetFaceEmbeddingInputs},
};

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

        let input = onnx::PreparedF32Input::new(batch.input);
        let input_shape = [
            batch.indices.len() as i64,
            PET_EMBEDDING_CHANNELS as i64,
            PET_EMBEDDING_INPUT_SIZE as i64,
            PET_EMBEDDING_INPUT_SIZE as i64,
        ];
        let model = if species == PET_SPECIES_DOG {
            Model::PetFaceEmbeddingDog
        } else {
            Model::PetFaceEmbeddingCat
        };
        let (shape, output) =
            runtime.run(model, |session| onnx::run_f32(session, &input, input_shape))?;

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

pub(crate) fn run_pet_body_embedding(
    runtime: &MlRuntimeView<'_>,
    file_id: i64,
    decoded: &DecodedImage,
    body_results: &mut [PetBodyResult],
) -> MlResult<()> {
    if body_results.is_empty() {
        return Ok(());
    }

    let per_body_len = PET_EMBEDDING_INPUT_SIZE * PET_EMBEDDING_INPUT_SIZE * PET_EMBEDDING_CHANNELS;

    let cat_count = body_results
        .iter()
        .filter(|result| result.detection.coco_class == COCO_CAT)
        .count();
    let dog_count = body_results.len() - cat_count;
    let mut dog_batch = IndexedEmbeddingBatch::new(dog_count, per_body_len);
    let mut cat_batch = IndexedEmbeddingBatch::new(cat_count, per_body_len);
    let mut preprocessor = PetEmbeddingPreprocessor::new();
    let mut skipped_count = 0;
    let mut first_error = None;

    for (i, body_result) in body_results.iter().enumerate() {
        let batch = if body_result.detection.coco_class == COCO_CAT {
            &mut cat_batch
        } else {
            &mut dog_batch
        };
        let original_len = batch.input.len();
        match preprocessor.append(decoded, &body_result.detection.box_xyxy, &mut batch.input) {
            Ok(()) => batch.indices.push(i),
            Err(error) => {
                batch.input.truncate(original_len);
                skipped_count += 1;
                first_error.get_or_insert(error);
            }
        }
    }

    if let Some(error) = first_error {
        log::warn!(
            "skipped {skipped_count} invalid pet body crop(s): file_id={file_id} first_error={error}"
        );
    }

    for (is_cat, batch) in [(false, dog_batch), (true, cat_batch)] {
        if batch.is_empty() {
            continue;
        }

        let input = onnx::PreparedF32Input::new(batch.input);
        let input_shape = [
            batch.indices.len() as i64,
            PET_EMBEDDING_CHANNELS as i64,
            PET_EMBEDDING_INPUT_SIZE as i64,
            PET_EMBEDDING_INPUT_SIZE as i64,
        ];
        let model = if is_cat {
            Model::PetBodyEmbeddingCat
        } else {
            Model::PetBodyEmbeddingDog
        };
        let (shape, output) =
            runtime.run(model, |session| onnx::run_f32(session, &input, input_shape))?;

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
