use std::cell::RefCell;
use std::collections::HashMap;

use super::input::{ClipVectors, MlInputs, PhotoSignals};
use super::text_embeddings::{NOSTALGIA, TextEmbedding};
use crate::ml_store::Result;

const ANY_SIMILARITY: f32 = -1.0;

pub(super) struct Signals<'m> {
    clip: &'m dyn ClipVectors,
    face_weights: &'m HashMap<i64, u32>,
    nostalgia: HashMap<i64, f32>,
    unit_vectors: RefCell<HashMap<i64, Option<Vec<f32>>>>,
}

impl<'m> Signals<'m> {
    pub(super) fn load(ml: &'m MlInputs<'_>) -> Result<Self> {
        let nostalgia = ml
            .clip
            .matches(&query(&NOSTALGIA), ANY_SIMILARITY)?
            .into_iter()
            .collect();
        Ok(Self {
            clip: ml.clip,
            face_weights: &ml.face_weights,
            nostalgia,
            unit_vectors: RefCell::default(),
        })
    }

    pub(super) fn matches(
        &self,
        embedding: &TextEmbedding,
        min_similarity: f32,
    ) -> Result<Vec<(i64, f32)>> {
        self.clip.matches(&query(embedding), min_similarity)
    }

    fn load_unit_vector(&self, file_id: i64) -> Result<()> {
        if self.unit_vectors.borrow().contains_key(&file_id) {
            return Ok(());
        }
        let vector = self.clip.vector(file_id)?.map(unit);
        self.unit_vectors.borrow_mut().insert(file_id, vector);
        Ok(())
    }
}

impl PhotoSignals for Signals<'_> {
    fn face_weight(&self, file_id: i64) -> u32 {
        self.face_weights.get(&file_id).copied().unwrap_or(0)
    }

    fn nostalgia(&self, file_id: i64) -> Option<f32> {
        self.nostalgia.get(&file_id).copied()
    }

    fn similarity(&self, file_id: i64, other_file_id: i64) -> Result<Option<f32>> {
        self.load_unit_vector(file_id)?;
        self.load_unit_vector(other_file_id)?;
        let unit_vectors = self.unit_vectors.borrow();
        let (Some(Some(vector)), Some(Some(other))) =
            (unit_vectors.get(&file_id), unit_vectors.get(&other_file_id))
        else {
            return Ok(None);
        };
        Ok(Some(vector.iter().zip(other).map(|(a, b)| a * b).sum()))
    }
}

fn query(embedding: &TextEmbedding) -> Vec<f32> {
    embedding.iter().copied().map(f32::from).collect()
}

fn unit(mut vector: Vec<f32>) -> Vec<f32> {
    let norm = vector.iter().map(|value| value * value).sum::<f32>().sqrt();
    if norm > 0.0 {
        for value in &mut vector {
            *value /= norm;
        }
    }
    vector
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use super::Signals;
    use crate::memories::input::{ClipVectors, MlInputs, PeopleInputs, PhotoSignals};
    use crate::ml_store::Result;

    struct Clip;

    impl ClipVectors for Clip {
        fn matches(&self, _: &[f32], _: f32) -> Result<Vec<(i64, f32)>> {
            Ok(vec![(1, 0.4), (2, -0.1)])
        }

        fn vector(&self, file_id: i64) -> Result<Option<Vec<f32>>> {
            Ok(match file_id {
                1 => Some(vec![3.0, 4.0]),
                2 => Some(vec![6.0, 8.0]),
                3 => Some(vec![4.0, -3.0]),
                _ => None,
            })
        }
    }

    #[test]
    fn photos_get_nostalgia_from_one_scan_and_compare_by_cosine_similarity() {
        let ml = MlInputs {
            clip: &Clip,
            face_weights: HashMap::from([(1, 12)]),
            people: PeopleInputs::default(),
        };

        let signals = Signals::load(&ml).unwrap();

        assert_eq!(
            [1, 2, 3].map(|file_id| signals.nostalgia(file_id)),
            [Some(0.4), Some(-0.1), None]
        );
        assert_eq!([1, 2].map(|file_id| signals.face_weight(file_id)), [12, 0]);
        let similarity = |a, b| signals.similarity(a, b).unwrap();
        assert!(similarity(1, 2).is_some_and(|value| (value - 1.0).abs() < 1e-6));
        assert!(similarity(1, 3).is_some_and(|value| value.abs() < 1e-6));
        assert_eq!(similarity(1, 4), None);
    }
}
