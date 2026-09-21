use std::collections::HashMap;

use ente_vecdb::VecDb;

use super::fill::decode_centroid;
use super::{Error, FillState, Index, IndexResult, MlStore, Result, state};
use crate::ml_db::{ClipEmbedding, ClusterSummary};

#[derive(Default)]
struct IndexBatch {
    keys: Vec<String>,
    vectors: Vec<Vec<f32>>,
    rejected_keys: Vec<String>,
}

impl FromIterator<(String, Option<Vec<f32>>)> for IndexBatch {
    fn from_iter<I: IntoIterator<Item = (String, Option<Vec<f32>>)>>(entries: I) -> Self {
        let mut batch = Self::default();
        for (key, vector) in entries {
            match vector {
                Some(vector) => {
                    batch.keys.push(key);
                    batch.vectors.push(vector);
                }
                None => batch.rejected_keys.push(key),
            }
        }
        batch
    }
}

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
        self.apply_batch(Index::Clip, &clip_batch(embeddings))
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
        self.apply_batch(Index::ClusterCentroid, &centroid_batch(summary))
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

    fn index_is_stale(&self, index: Index) -> Result<bool> {
        Ok(state::read(&self.db, index)? == FillState::Stale)
    }

    fn apply_batch(&self, index: Index, batch: &IndexBatch) -> Result<()> {
        self.index_write(index, |vecdb| {
            vecdb.bulk_remove(&batch.rejected_keys)?;
            vecdb.bulk_add(&batch.keys, &batch.vectors)
        })
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

fn clip_batch(embeddings: &[ClipEmbedding]) -> IndexBatch {
    embeddings
        .iter()
        .map(|embedding| {
            let key = embedding.file_id.to_string();
            let vector: Vec<f32> = embedding
                .embedding
                .iter()
                .map(|value| *value as f32)
                .collect();
            let accepted = Index::Clip.accepts(&key, &vector).then_some(vector);
            (key, accepted)
        })
        .collect()
}

fn centroid_batch(summary: &HashMap<String, ClusterSummary>) -> IndexBatch {
    summary
        .iter()
        .map(|(cluster_id, summary)| {
            (
                cluster_id.clone(),
                decode_centroid(cluster_id, &summary.avg),
            )
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use ente_vecdb::{OpenCost, SearchParams, VecDb, VecDbError};

    use crate::ml_db::tests::deny_cluster_summary_inserts_after;
    use crate::ml_db::vector_encoding::encode_evector;
    use crate::ml_db::{CLIP_EMBEDDING_DIMENSIONS, ClusterSummary};
    use crate::ml_store::tests::{
        DB_FILE, centroid, clips, empty, hot_position, index_path, live_count, meta, nearest,
        one_hot, open, open_with_unusable_clip_index,
    };
    use crate::ml_store::{Error, FillOutcome, FillState, Index};

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
    fn empty_clip_markers_are_stored_in_sql_and_kept_out_of_the_index() {
        let (_directory, store) = open();
        store.fill_clip_index(false).unwrap();
        store.put_clip(&clips([1])).unwrap();
        let mut marker = clips([2]);
        marker[0].embedding = vec![];
        store.put_clip(&marker).unwrap();

        assert_eq!(
            store.db().clip_indexed_file_with_version().unwrap(),
            HashMap::from([(1, 1), (2, 1)])
        );
        assert!(store.contains(Index::Clip, "1").unwrap());
        assert!(!store.contains(Index::Clip, "2").unwrap());
        assert_eq!(live_count(&store, Index::Clip), 1);
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Filled);
    }

    #[test]
    fn rejected_clip_embeddings_evict_previously_indexed_vectors() {
        let (_directory, store) = open();
        store.fill_clip_index(false).unwrap();
        store.put_clip(&clips([1, 2, 3, 4])).unwrap();
        let mut replacements = clips([1, 2, 3]);
        replacements[0].embedding = vec![];
        replacements[1].embedding = vec![1.0, 2.0];
        replacements[2].embedding[0] = f64::NAN;
        store.put_clip(&replacements).unwrap();

        assert_eq!(store.db().count_clip_rows().unwrap(), 4);
        for file_id in ["1", "2", "3"] {
            assert!(!store.contains(Index::Clip, file_id).unwrap(), "{file_id}");
        }
        assert!(store.contains(Index::Clip, "4").unwrap());
        assert_eq!(live_count(&store, Index::Clip), 1);
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Filled);
        let refill = store.fill_clip_index(true).unwrap();
        assert_eq!((refill.indexed, refill.skipped), (1, 3));
    }

    #[test]
    fn rejected_centroids_evict_previously_indexed_vectors() {
        let (_directory, store) = open();
        store.fill_cluster_centroid_index(false).unwrap();
        store
            .cluster_summary_update(&HashMap::from([centroid("c1", 1), centroid("c2", 2)]))
            .unwrap();
        let malformed = ClusterSummary {
            avg: encode_evector(&[1.0, 2.0]),
            count: 1,
        };
        store
            .cluster_summary_update(&HashMap::from([("c1".to_string(), malformed)]))
            .unwrap();

        assert_eq!(store.db().count_cluster_summaries().unwrap(), 2);
        assert!(!store.contains(Index::ClusterCentroid, "c1").unwrap());
        assert!(store.contains(Index::ClusterCentroid, "c2").unwrap());
        assert_eq!(live_count(&store, Index::ClusterCentroid), 1);
        assert_eq!(
            store.fill_state(Index::ClusterCentroid).unwrap(),
            FillState::Filled
        );
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
    fn clear_all_removes_rows_meta_and_index_files() {
        let (directory, store) = open();
        store.fill_clip_index(false).unwrap();
        store.fill_cluster_centroid_index(false).unwrap();
        store.put_clip(&clips([1])).unwrap();
        store
            .cluster_summary_update(&HashMap::from([centroid("c1", 1)]))
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
        assert_eq!(live_count(&store, Index::Clip), 0);
        assert_eq!(
            store.fill_clip_index(false).unwrap(),
            empty(FillOutcome::Completed)
        );
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Filled);
    }

    #[test]
    fn index_write_failure_marks_the_index_stale() {
        let (_directory, store) = open_with_unusable_clip_index();
        store.db().set_meta("clip.fill", "filled").unwrap();
        assert!(matches!(store.put_clip(&clips([1])), Err(Error::Index(_))));
        assert_eq!(store.db().count_clip_rows().unwrap(), 1);
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Stale);
        store.put_clip(&clips([2])).unwrap();
        assert_eq!(store.db().count_clip_rows().unwrap(), 2);
    }
}
