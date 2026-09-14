use std::collections::HashMap;

use ente_vecdb::VecDb;

use super::fill::decode_centroid;
use super::{Error, FillState, Index, IndexResult, MlStore, Result, Species, state};
use crate::ml_db::{ClipEmbedding, ClusterSummary, PetRowsForFiles};

#[derive(Clone, Debug, PartialEq)]
pub struct PetEmbedding {
    pub id: String,
    pub species: Species,
    pub embedding: Vec<f32>,
}

type Vectors = (Vec<String>, Vec<Vec<f32>>);

impl MlStore {
    pub fn put_clip(&self, embeddings: &[ClipEmbedding]) -> Result<()> {
        if embeddings.is_empty() {
            return Ok(());
        }
        let _mutations = self.lock_mutations();
        self.db.insert_clip_rows(embeddings)?;
        if self.index_is_stale(Index::Clip)? {
            return Ok(());
        }
        let (keys, vectors) = clip_vectors(embeddings);
        self.index_write(Index::Clip, |vecdb| vecdb.bulk_add(&keys, &vectors))
    }

    pub fn delete_clip(&self, file_ids: &[i64]) -> Result<()> {
        if file_ids.is_empty() {
            return Ok(());
        }
        let _mutations = self.lock_mutations();
        self.db.delete_clip_rows(file_ids)?;
        if self.index_is_stale(Index::Clip)? {
            return Ok(());
        }
        let keys: Vec<String> = file_ids.iter().map(ToString::to_string).collect();
        self.index_write(Index::Clip, |vecdb| vecdb.bulk_remove(&keys))
    }

    pub fn delete_all_clip(&self) -> Result<()> {
        let _mutations = self.lock_mutations();
        self.db.delete_all_clip_rows()?;
        self.reset_index(Index::Clip)
    }

    pub fn cluster_summary_update(&self, summary: &HashMap<String, ClusterSummary>) -> Result<()> {
        if summary.is_empty() {
            return Ok(());
        }
        let _mutations = self.lock_mutations();
        self.db.upsert_cluster_summary_rows(summary)?;
        if self.index_is_stale(Index::ClusterCentroid)? {
            return Ok(());
        }
        let (keys, vectors) = centroid_vectors(summary);
        self.index_write(Index::ClusterCentroid, |vecdb| {
            vecdb.bulk_add(&keys, &vectors)
        })
    }

    pub fn delete_cluster_summary(&self, cluster_id: &str) -> Result<()> {
        let _mutations = self.lock_mutations();
        self.db.delete_cluster_summary_row(cluster_id)?;
        if self.index_is_stale(Index::ClusterCentroid)? {
            return Ok(());
        }
        self.index_write(Index::ClusterCentroid, |vecdb| vecdb.remove(cluster_id))
    }

    pub fn drop_clusters_and_person_table(&self, faces: bool) -> Result<()> {
        let _mutations = self.lock_mutations();
        self.db.reset_cluster_tables(faces)?;
        self.reset_index(Index::ClusterCentroid)
    }

    pub fn store_pet_face_embeddings(&self, embeddings: &[PetEmbedding]) -> Result<()> {
        self.store_pet_embeddings(embeddings, Index::PetFace)
    }

    pub fn store_pet_body_embeddings(&self, embeddings: &[PetEmbedding]) -> Result<()> {
        self.store_pet_embeddings(embeddings, Index::PetBody)
    }

    pub fn delete_pet_data_for_files(&self, file_ids: &[i64]) -> Result<()> {
        if file_ids.is_empty() {
            return Ok(());
        }
        let _mutations = self.lock_mutations();
        let rows = self.db.get_pet_rows_for_files(file_ids)?;
        for (index, keys) in pet_keys(&rows) {
            if let Err(error) = self.with_index(index, |vecdb| vecdb.bulk_remove(&keys)) {
                log::warn!(
                    "failed to remove {} vectors from {}: {error}",
                    keys.len(),
                    index.name()
                );
            }
        }
        let face_ids: Vec<String> = rows.faces.into_iter().map(|row| row.pet_face_id).collect();
        let body_ids: Vec<String> = rows.bodies.into_iter().map(|row| row.pet_body_id).collect();
        self.db
            .delete_pet_rows_for_files(file_ids, &face_ids, &body_ids)?;
        Ok(())
    }

    pub fn clear_all(&self) -> Result<()> {
        let _mutations = self.lock_mutations();
        self.db.clear_non_pet_tables()?;
        self.db.clear_pet_tables()?;
        self.db.clear_meta()?;
        for slot in &self.indexes {
            slot.purge()?;
        }
        Ok(())
    }

    fn store_pet_embeddings(
        &self,
        embeddings: &[PetEmbedding],
        index_of: fn(Species) -> Index,
    ) -> Result<()> {
        if embeddings.is_empty() {
            return Ok(());
        }
        let _mutations = self.lock_mutations();
        for (index, (keys, vectors)) in pet_vectors(embeddings, index_of) {
            self.index_write(index, |vecdb| vecdb.bulk_add(&keys, &vectors))?;
        }
        Ok(())
    }

    fn index_is_stale(&self, index: Index) -> Result<bool> {
        Ok(state::read(&self.db, index)? == FillState::Stale)
    }

    fn index_write<T>(
        &self,
        index: Index,
        operation: impl Fn(&VecDb) -> IndexResult<T>,
    ) -> Result<()> {
        let outcome = self.with_index(index, operation);
        if let Err(Error::Index(_)) = &outcome {
            state::mark_stale(&self.db, index)?;
        }
        outcome.map(drop)
    }

    fn reset_index(&self, index: Index) -> Result<()> {
        self.index_write(index, VecDb::reset)?;
        state::mark_filled(&self.db, index)
    }
}

fn clip_vectors(embeddings: &[ClipEmbedding]) -> Vectors {
    embeddings
        .iter()
        .filter_map(|embedding| {
            let key = embedding.file_id.to_string();
            let vector: Vec<f32> = embedding
                .embedding
                .iter()
                .map(|value| *value as f32)
                .collect();
            Index::Clip.accepts(&key, &vector).then_some((key, vector))
        })
        .unzip()
}

fn centroid_vectors(summary: &HashMap<String, ClusterSummary>) -> Vectors {
    summary
        .iter()
        .filter_map(|(cluster_id, summary)| {
            decode_centroid(cluster_id, &summary.avg).map(|vector| (cluster_id.clone(), vector))
        })
        .unzip()
}

fn pet_vectors(
    embeddings: &[PetEmbedding],
    index_of: fn(Species) -> Index,
) -> HashMap<Index, Vectors> {
    let mut grouped: HashMap<Index, Vectors> = HashMap::new();
    for embedding in embeddings {
        let index = index_of(embedding.species);
        if !index.accepts(&embedding.id, &embedding.embedding) {
            continue;
        }
        let (keys, vectors) = grouped.entry(index).or_default();
        keys.push(embedding.id.clone());
        vectors.push(embedding.embedding.clone());
    }
    grouped
}

fn pet_keys(rows: &PetRowsForFiles) -> HashMap<Index, Vec<String>> {
    let faces = rows.faces.iter().filter_map(|row| {
        Species::from_sql(row.species).map(|species| (Index::PetFace(species), &row.pet_face_id))
    });
    let bodies = rows.bodies.iter().filter_map(|row| {
        Species::from_sql(row.species).map(|species| (Index::PetBody(species), &row.pet_body_id))
    });
    let mut grouped: HashMap<Index, Vec<String>> = HashMap::new();
    for (index, id) in faces.chain(bodies) {
        grouped.entry(index).or_default().push(id.clone());
    }
    grouped
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use ente_vecdb::{OpenCost, SearchParams, VecDb, VecDbError};

    use crate::ml_db::tests::{deny_cluster_summary_inserts_after, seed_pet_rows};
    use crate::ml_db::{CLIP_EMBEDDING_DIMENSIONS, ClusterSummary, encode_evector};
    use crate::ml_store::tests::{
        DB_FILE, centroid, clips, empty, hot_position, index_path, live_count, meta, nearest,
        one_hot, open, open_with_unusable_index_dir, pet,
    };
    use crate::ml_store::{Error, FillOutcome, FillState, Index, Species};

    #[test]
    fn put_clip_round_trips_through_sql_and_index() {
        let (_directory, store) = open();
        assert_eq!(
            store.fill_clip_index(false).unwrap(),
            empty(FillOutcome::Completed)
        );
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Filled);
        store.put_clip(&[]).unwrap();
        store.put_clip(&clips([1, 2, 3])).unwrap();
        assert_eq!(store.db().count_clip_rows().unwrap(), 3);
        assert_eq!(live_count(&store, Index::Clip), 3);
        assert!(store.contains(Index::Clip, "2").unwrap());
        assert!(!store.contains(Index::Clip, "4").unwrap());
        let stored = store.get_vector(Index::Clip, "2").unwrap().unwrap();
        assert_eq!(stored.len(), CLIP_EMBEDDING_DIMENSIONS);
        assert_eq!(hot_position(&stored), Some(2));
        assert_eq!(store.get_vector(Index::Clip, "4").unwrap(), None);
        assert_eq!(
            nearest(&store, Index::Clip, &one_hot(CLIP_EMBEDDING_DIMENSIONS, 3)),
            "3"
        );

        let params = SearchParams {
            limit: Some(1),
            ..SearchParams::default()
        };
        let queries = [
            one_hot(CLIP_EMBEDDING_DIMENSIONS, 1),
            one_hot(CLIP_EMBEDDING_DIMENSIONS, 2),
        ];
        let found = store.bulk_search(Index::Clip, &queries, &params).unwrap();
        assert_eq!(found[0][0].key, "1");
        assert_eq!(found[1][0].key, "2");
        let stored_matches = store
            .bulk_search_stored(
                Index::Clip,
                &["1".to_string(), "9".to_string()],
                2,
                None,
                true,
                false,
            )
            .unwrap();
        assert_eq!(stored_matches.len(), 1);
        assert_eq!(stored_matches[0].key, "1");
        let neighbours: Vec<&str> = stored_matches[0]
            .matches
            .iter()
            .map(|found| found.key.as_str())
            .collect();
        assert_eq!(neighbours.len(), 2);
        assert!(neighbours.contains(&"2") && neighbours.contains(&"3"));
        assert!(matches!(
            store.search(Index::Clip, &[1.0; 3], &params),
            Err(Error::Index(VecDbError::DimensionMismatch { .. }))
        ));
    }

    #[test]
    fn delete_clip_removes_sql_rows_and_vectors() {
        let (_directory, store) = open();
        store.fill_clip_index(false).unwrap();
        store.put_clip(&clips([1, 2, 3])).unwrap();
        store.delete_clip(&[]).unwrap();
        store.delete_clip(&[1, 3, 9]).unwrap();
        assert_eq!(
            store.db().clip_indexed_file_with_version().unwrap(),
            HashMap::from([(2, 1)])
        );
        assert!(!store.contains(Index::Clip, "1").unwrap());
        assert!(store.contains(Index::Clip, "2").unwrap());
        assert_eq!(live_count(&store, Index::Clip), 1);
    }

    #[test]
    fn non_finite_clip_vectors_stay_out_of_the_index() {
        let (_directory, store) = open();
        store.fill_clip_index(false).unwrap();
        let mut rows = clips([1, 2]);
        rows[0].embedding[0] = f64::NAN;
        rows[1].embedding[0] = f64::MAX;
        store.put_clip(&rows).unwrap();
        assert_eq!(store.db().count_clip_rows().unwrap(), 2);
        assert!(!store.contains(Index::Clip, "1").unwrap());
        assert!(!store.contains(Index::Clip, "2").unwrap());
        assert_eq!(live_count(&store, Index::Clip), 0);
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Filled);
    }

    #[test]
    fn stale_indexes_are_skipped_by_writes() {
        let (_directory, store) = open();
        store.put_clip(&clips([1, 2])).unwrap();
        store.delete_clip(&[2]).unwrap();
        store
            .cluster_summary_update(&HashMap::from([centroid("c1", 1), centroid("c2", 2)]))
            .unwrap();
        store.delete_cluster_summary("c2").unwrap();
        assert_eq!(store.db().count_clip_rows().unwrap(), 1);
        assert_eq!(store.db().count_cluster_summaries().unwrap(), 1);
        assert!(!store.contains(Index::Clip, "1").unwrap());
        assert!(!store.contains(Index::ClusterCentroid, "c1").unwrap());
        assert_eq!(live_count(&store, Index::Clip), 0);
        assert_eq!(live_count(&store, Index::ClusterCentroid), 0);
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Stale);
        assert_eq!(
            store.fill_state(Index::ClusterCentroid).unwrap(),
            FillState::Stale
        );
    }

    #[test]
    fn cluster_summary_writes_go_through_while_filling() {
        let (_directory, store) = open();
        store.fill_cluster_centroid_index(false).unwrap();
        store
            .db()
            .set_meta("cluster_centroid.fill", "filling")
            .unwrap();
        let mut summaries = HashMap::from([centroid("c1", 1)]);
        summaries.insert(
            "short".to_string(),
            ClusterSummary {
                avg: encode_evector(&[1.0, 2.0]),
                count: 1,
            },
        );
        store.cluster_summary_update(&summaries).unwrap();
        store.cluster_summary_update(&HashMap::new()).unwrap();
        assert_eq!(store.db().count_cluster_summaries().unwrap(), 2);
        assert!(store.contains(Index::ClusterCentroid, "c1").unwrap());
        assert!(!store.contains(Index::ClusterCentroid, "short").unwrap());
        assert_eq!(
            store.fill_state(Index::ClusterCentroid).unwrap(),
            FillState::Filling
        );

        store.delete_cluster_summary("c1").unwrap();
        assert_eq!(store.db().count_cluster_summaries().unwrap(), 1);
        assert!(!store.contains(Index::ClusterCentroid, "c1").unwrap());
        assert_eq!(
            store.fill_state(Index::ClusterCentroid).unwrap(),
            FillState::Filling
        );
    }

    #[test]
    fn failed_cluster_summary_upserts_leave_sql_and_index_untouched() {
        let (directory, store) = open();
        store.fill_cluster_centroid_index(false).unwrap();
        let summaries: HashMap<String, ClusterSummary> = (0..=400)
            .map(|hot| centroid(&format!("c{hot:04}"), hot))
            .collect();
        deny_cluster_summary_inserts_after(&directory.path().join(DB_FILE), 400);

        assert!(matches!(
            store.cluster_summary_update(&summaries),
            Err(Error::Database(_))
        ));
        assert_eq!(store.db().count_cluster_summaries().unwrap(), 0);
        assert_eq!(live_count(&store, Index::ClusterCentroid), 0);
        assert_eq!(
            store.fill_state(Index::ClusterCentroid).unwrap(),
            FillState::Filled
        );
    }

    #[test]
    fn delete_all_clip_and_drop_clusters_leave_filled_empty_indexes() {
        let (_directory, store) = open();
        store.put_clip(&clips([1])).unwrap();
        store
            .db()
            .upsert_cluster_summary_rows(&HashMap::from([centroid("c1", 1)]))
            .unwrap();
        store.delete_all_clip().unwrap();
        store.drop_clusters_and_person_table(false).unwrap();
        for index in [Index::Clip, Index::ClusterCentroid] {
            assert_eq!(store.fill_state(index).unwrap(), FillState::Filled);
            assert_eq!(live_count(&store, index), 0);
        }
        assert_eq!(store.db().count_clip_rows().unwrap(), 0);
        assert_eq!(store.db().count_cluster_summaries().unwrap(), 0);

        store.put_clip(&clips([2])).unwrap();
        store
            .cluster_summary_update(&HashMap::from([centroid("c2", 2)]))
            .unwrap();
        assert_eq!(live_count(&store, Index::Clip), 1);
        assert_eq!(live_count(&store, Index::ClusterCentroid), 1);
        store.delete_all_clip().unwrap();
        store.drop_clusters_and_person_table(true).unwrap();
        for index in [Index::Clip, Index::ClusterCentroid] {
            assert_eq!(store.fill_state(index).unwrap(), FillState::Filled);
            assert_eq!(live_count(&store, index), 0);
        }
        assert_eq!(store.db().count_clip_rows().unwrap(), 0);
        assert_eq!(store.db().count_cluster_summaries().unwrap(), 0);
    }

    #[test]
    fn pet_embeddings_are_stored_searched_and_deleted_per_species() {
        let (_directory, store) = open();
        seed_pet_rows(store.db());
        let face_dims = Index::PetFace(Species::Dog).dims();
        let body_dims = Index::PetBody(Species::Dog).dims();
        store
            .store_pet_face_embeddings(&[
                pet("1_pet_0", Species::Dog, 1, face_dims),
                pet("2_pet_0", Species::Cat, 2, face_dims),
                pet("bad", Species::Dog, 3, face_dims / 2),
            ])
            .unwrap();
        store
            .store_pet_body_embeddings(&[pet("1_body_0", Species::Dog, 1, body_dims)])
            .unwrap();
        store.store_pet_body_embeddings(&[]).unwrap();
        assert_eq!(
            nearest(&store, Index::PetFace(Species::Dog), &one_hot(face_dims, 1)),
            "1_pet_0"
        );
        assert!(
            store
                .contains(Index::PetFace(Species::Cat), "2_pet_0")
                .unwrap()
        );
        assert!(!store.contains(Index::PetFace(Species::Dog), "bad").unwrap());
        assert_eq!(live_count(&store, Index::PetFace(Species::Dog)), 1);
        assert!(
            store
                .contains(Index::PetBody(Species::Dog), "1_body_0")
                .unwrap()
        );

        store.delete_pet_data_for_files(&[]).unwrap();
        store.delete_pet_data_for_files(&[1]).unwrap();
        assert!(
            !store
                .contains(Index::PetFace(Species::Dog), "1_pet_0")
                .unwrap()
        );
        assert!(
            !store
                .contains(Index::PetBody(Species::Dog), "1_body_0")
                .unwrap()
        );
        assert!(
            store
                .contains(Index::PetFace(Species::Cat), "2_pet_0")
                .unwrap()
        );
        assert!(store.db().get_pet_faces_for_file_id(1).unwrap().is_empty());
        assert!(store.db().get_pet_bodies_for_file_id(1).unwrap().is_empty());
        assert_eq!(store.db().get_pet_indexed_file_count(1).unwrap(), 1);
    }

    #[test]
    fn clear_all_removes_rows_meta_and_index_files() {
        let (directory, store) = open();
        store.fill_clip_index(false).unwrap();
        store.fill_cluster_centroid_index(false).unwrap();
        store.put_clip(&clips([1])).unwrap();
        store
            .cluster_summary_update(&HashMap::from([centroid("c1", 1)]))
            .unwrap();
        store
            .store_pet_face_embeddings(&[pet(
                "p",
                Species::Cat,
                1,
                Index::PetFace(Species::Cat).dims(),
            )])
            .unwrap();

        store.clear_all().unwrap();
        for index in Index::ALL {
            assert_eq!(
                VecDb::open_cost(&index_path(&directory, index)),
                OpenCost::Absent,
                "{}",
                index.name()
            );
        }
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Stale);
        assert_eq!(
            store.fill_state(Index::ClusterCentroid).unwrap(),
            FillState::Stale
        );
        assert_eq!(meta(&store, "clip.fill"), None);
        assert_eq!(meta(&store, "cluster_centroid.fill"), None);
        assert_eq!(store.db().count_clip_rows().unwrap(), 0);
        assert_eq!(store.db().count_cluster_summaries().unwrap(), 0);
        assert!(!store.contains(Index::Clip, "1").unwrap());
        assert!(!store.contains(Index::PetFace(Species::Cat), "p").unwrap());
        assert_eq!(live_count(&store, Index::Clip), 0);
        assert_eq!(
            store.fill_clip_index(false).unwrap(),
            empty(FillOutcome::Completed)
        );
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Filled);
    }

    #[test]
    fn index_write_failure_marks_the_index_stale() {
        let (_directory, store) = open_with_unusable_index_dir();
        store.db().set_meta("clip.fill", "filled").unwrap();
        assert!(matches!(store.put_clip(&clips([1])), Err(Error::Index(_))));
        assert_eq!(store.db().count_clip_rows().unwrap(), 1);
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Stale);
        store.put_clip(&clips([2])).unwrap();
        assert_eq!(store.db().count_clip_rows().unwrap(), 2);
    }
}
