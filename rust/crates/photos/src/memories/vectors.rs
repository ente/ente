use super::input::ClipVectors;
use crate::ml_store::{Index, MlStore, Result, SearchParams};

impl ClipVectors for MlStore {
    fn matches(&self, query: &[f32], min_similarity: f32) -> Result<Vec<(i64, f32)>> {
        let params = SearchParams {
            limit: None,
            max_distance: Some(1.0 - min_similarity),
            exact: true,
            allowed_keys: None,
        };
        Ok(self
            .search(Index::Clip, query, &params)?
            .into_iter()
            .filter_map(|found| Some((found.key.parse().ok()?, 1.0 - found.distance)))
            .collect())
    }

    fn vector(&self, file_id: i64) -> Result<Option<Vec<f32>>> {
        self.get_vector(Index::Clip, &file_id.to_string())
    }
}

#[cfg(test)]
mod tests {
    use crate::memories::input::ClipVectors;
    use crate::ml_db::{CLIP_EMBEDDING_DIMENSIONS, ClipEmbedding};
    use crate::ml_store::MlStore;

    fn clip(file_id: i64, values: [f64; 2]) -> ClipEmbedding {
        let mut embedding = vec![0.0; CLIP_EMBEDDING_DIMENSIONS];
        embedding[..2].copy_from_slice(&values);
        ClipEmbedding {
            file_id,
            embedding,
            version: 1,
        }
    }

    #[test]
    fn matches_report_cosine_similarity_down_to_the_minimum_and_vectors_come_back_by_file_id() {
        let directory = tempfile::tempdir().unwrap();
        let store = MlStore::open(directory.path().join("ente.ml.db")).unwrap();
        store
            .put_clip(&[
                clip(1, [1.0, 0.0]),
                clip(2, [0.6, 0.8]),
                clip(3, [0.0, 1.0]),
            ])
            .unwrap();
        store.fill_clip_index(false).unwrap();
        let mut query = vec![0.0; CLIP_EMBEDDING_DIMENSIONS];
        query[0] = 1.0;

        let mut matches = store.matches(&query, 0.5).unwrap();
        matches.sort_by_key(|&(file_id, _)| file_id);

        assert_eq!(
            matches
                .iter()
                .map(|&(file_id, _)| file_id)
                .collect::<Vec<_>>(),
            [1, 2]
        );
        assert!((matches[0].1 - 1.0).abs() < 1e-3);
        assert!((matches[1].1 - 0.6).abs() < 1e-2);
        let vector = store.vector(3).unwrap().unwrap();
        assert!(vector[1] > 0.99 && vector[0].abs() < 1e-6);
        assert_eq!(store.vector(4).unwrap(), None);
    }
}
