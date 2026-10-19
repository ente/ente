use std::collections::{HashMap, HashSet};
use std::sync::OnceLock;

use ente_photos::ml_db;
pub use ente_photos::ml_db::{
    ClipEmbedding, ClusterSummary, EmbeddingVector, FaceDbInfoForClustering, FaceRow,
    FaceWithoutEmbedding, FdStatus, PreviewInfo,
};
use ente_photos::ml_store;
pub use ente_photos::ml_store::{FillOutcome, FillState, Index};
use flutter_rust_bridge::frb;

use super::vecdb_api::{
    VecDbKeyMatches, VecDbMatch, VecDbStats, to_api_key_matches, to_api_matches, to_api_stats,
};

static BACKEND: OnceLock<bool> = OnceLock::new();

#[frb(sync)]
pub fn decide_ml_db_backend(prefer_rust: bool) -> bool {
    *BACKEND.get_or_init(|| prefer_rust)
}

#[frb]
pub enum MlDbError {
    Downgrade { message: String },
    Index { message: String },
    Other { message: String },
}

impl From<ml_db::Error> for MlDbError {
    fn from(error: ml_db::Error) -> Self {
        let message = ente_core::error::chain(&error);
        match error {
            ml_db::Error::Downgrade { .. } => Self::Downgrade { message },
            _ => Self::Other { message },
        }
    }
}

impl From<ml_store::Error> for MlDbError {
    fn from(error: ml_store::Error) -> Self {
        match error {
            ml_store::Error::Database(error) => Self::from(error),
            ml_store::Error::Index(_) => Self::Index {
                message: ente_core::error::chain(&error),
            },
            other => Self::Other {
                message: ente_core::error::chain(&other),
            },
        }
    }
}

#[frb(mirror(FaceRow))]
pub struct _FaceRow {
    pub file_id: i64,
    pub face_id: String,
    pub detection_json: String,
    pub embedding: Vec<f64>,
    pub score: f64,
    pub blur: f64,
    pub is_sideways: bool,
    pub image_height: i64,
    pub image_width: i64,
    pub ml_version: i64,
}

#[frb(mirror(FaceWithoutEmbedding))]
pub struct _FaceWithoutEmbedding {
    pub face_id: String,
    pub file_id: i64,
    pub score: f64,
    pub detection_json: String,
    pub blur: f64,
}

#[frb(mirror(FaceDbInfoForClustering))]
pub struct _FaceDbInfoForClustering {
    pub face_id: String,
    pub cluster_id: Option<String>,
    pub embedding_bytes: Vec<u8>,
    pub face_score: f64,
    pub blur_value: f64,
    pub is_sideways: bool,
}

#[frb(mirror(ClipEmbedding))]
pub struct _ClipEmbedding {
    pub file_id: i64,
    pub embedding: Vec<f64>,
    pub version: i64,
}

#[frb(mirror(EmbeddingVector))]
pub struct _EmbeddingVector {
    pub file_id: i64,
    pub embedding: Vec<f32>,
}

#[frb(mirror(ClusterSummary))]
pub struct _ClusterSummary {
    pub avg: Vec<u8>,
    pub count: i64,
}

#[frb(mirror(FdStatus))]
pub struct _FdStatus {
    pub file_id: i64,
    pub user_id: i64,
    pub data_type: String,
    pub size: i64,
    pub object_id: Option<String>,
    pub object_nonce: Option<String>,
    pub updated_at: i64,
}

#[frb(mirror(PreviewInfo))]
pub struct _PreviewInfo {
    pub object_id: String,
    pub object_size: i64,
}

#[frb(mirror(Index))]
pub enum _Index {
    Clip,
    ClusterCentroid,
}

#[frb(mirror(FillState))]
pub enum _FillState {
    Filled,
    Filling,
    Stale,
}

#[frb(mirror(FillOutcome))]
pub enum _FillOutcome {
    Completed,
    AlreadyFilled,
    Superseded,
}

pub struct FillReport {
    pub outcome: FillOutcome,
    pub rows: u32,
    pub indexed: u32,
    pub skipped: u32,
    pub resumed: bool,
}

impl From<ml_store::FillReport> for FillReport {
    fn from(report: ml_store::FillReport) -> Self {
        Self {
            outcome: report.outcome,
            rows: report.rows as u32,
            indexed: report.indexed as u32,
            skipped: report.skipped as u32,
            resumed: report.resumed,
        }
    }
}

fn search_params(
    limit: Option<u32>,
    max_distance: Option<f32>,
    exact: bool,
    allowed_keys: Option<Vec<String>>,
) -> ml_store::SearchParams {
    ml_store::SearchParams {
        limit: limit.map(|value| value as usize),
        max_distance,
        exact,
        allowed_keys,
    }
}

#[frb(opaque)]
pub struct MlStore {
    inner: ml_store::MlStore,
}

impl MlStore {
    pub fn open(path: String) -> Result<MlStore, MlDbError> {
        Ok(Self {
            inner: ml_store::MlStore::open(path)?,
        })
    }

    pub fn release(&self) -> Result<(), MlDbError> {
        Ok(self.inner.release()?)
    }

    pub fn fill_state(&self, index: Index) -> Result<FillState, MlDbError> {
        Ok(self.inner.fill_state(index)?)
    }

    pub fn fill_clip_index(&self, force: bool) -> Result<FillReport, MlDbError> {
        Ok(self.inner.fill_clip_index(force)?.into())
    }

    pub fn fill_cluster_centroid_index(&self, force: bool) -> Result<FillReport, MlDbError> {
        Ok(self.inner.fill_cluster_centroid_index(force)?.into())
    }

    pub fn put_clip(&self, embeddings: Vec<ClipEmbedding>) -> Result<(), MlDbError> {
        Ok(self.inner.put_clip(&embeddings)?)
    }

    pub fn delete_clip(&self, file_ids: Vec<i64>) -> Result<(), MlDbError> {
        Ok(self.inner.delete_clip(&file_ids)?)
    }

    pub fn delete_all_clip(&self) -> Result<(), MlDbError> {
        Ok(self.inner.delete_all_clip()?)
    }

    pub fn cluster_summary_update(
        &self,
        summary: HashMap<String, ClusterSummary>,
    ) -> Result<(), MlDbError> {
        Ok(self.inner.cluster_summary_update(&summary)?)
    }

    pub fn delete_cluster_summary(&self, cluster_id: String) -> Result<(), MlDbError> {
        Ok(self.inner.delete_cluster_summary(&cluster_id)?)
    }

    pub fn drop_clusters_and_person_table(&self, faces: bool) -> Result<(), MlDbError> {
        Ok(self.inner.drop_clusters_and_person_table(faces)?)
    }

    pub fn clear_all(&self) -> Result<(), MlDbError> {
        Ok(self.inner.clear_all()?)
    }

    pub fn search(
        &self,
        index: Index,
        query: Vec<f32>,
        limit: Option<u32>,
        max_distance: Option<f32>,
        exact: bool,
        allowed_keys: Option<Vec<String>>,
    ) -> Result<Vec<VecDbMatch>, MlDbError> {
        let params = search_params(limit, max_distance, exact, allowed_keys);
        Ok(to_api_matches(self.inner.search(index, &query, &params)?))
    }

    pub fn bulk_search(
        &self,
        index: Index,
        queries: Vec<Vec<f32>>,
        limit: Option<u32>,
        max_distance: Option<f32>,
        exact: bool,
        allowed_keys: Option<Vec<String>>,
    ) -> Result<Vec<Vec<VecDbMatch>>, MlDbError> {
        let params = search_params(limit, max_distance, exact, allowed_keys);
        Ok(self
            .inner
            .bulk_search(index, &queries, &params)?
            .into_iter()
            .map(to_api_matches)
            .collect())
    }

    pub fn bulk_search_stored(
        &self,
        index: Index,
        keys: Vec<String>,
        count: u32,
        max_distance: Option<f32>,
        exact: bool,
        restrict_to_input: bool,
    ) -> Result<Vec<VecDbKeyMatches>, MlDbError> {
        Ok(self
            .inner
            .bulk_search_stored(
                index,
                &keys,
                count as usize,
                max_distance,
                exact,
                restrict_to_input,
            )?
            .into_iter()
            .map(to_api_key_matches)
            .collect())
    }

    pub fn get_vector(&self, index: Index, key: String) -> Result<Option<Vec<f32>>, MlDbError> {
        Ok(self.inner.get_vector(index, &key)?)
    }

    pub fn contains(&self, index: Index, key: String) -> Result<bool, MlDbError> {
        Ok(self.inner.contains(index, &key)?)
    }

    pub fn stats(&self, index: Index) -> Result<VecDbStats, MlDbError> {
        Ok(to_api_stats(self.inner.stats(index)?))
    }

    pub fn bulk_insert_faces(&self, faces: Vec<FaceRow>) -> Result<(), MlDbError> {
        Ok(self.inner.db().bulk_insert_faces(&faces)?)
    }

    pub fn face_indexed_file_ids(
        &self,
        minimum_ml_version: i64,
    ) -> Result<HashMap<i64, i64>, MlDbError> {
        Ok(self.inner.db().face_indexed_file_ids(minimum_ml_version)?)
    }

    pub fn get_face_indexed_file_count(&self, minimum_ml_version: i64) -> Result<i64, MlDbError> {
        Ok(self
            .inner
            .db()
            .get_face_indexed_file_count(minimum_ml_version)?)
    }

    pub fn get_face_embeddings_for_cluster(
        &self,
        cluster_id: String,
        limit: Option<i64>,
    ) -> Result<Vec<Vec<u8>>, MlDbError> {
        Ok(self
            .inner
            .db()
            .get_face_embeddings_for_cluster(&cluster_id, limit)?)
    }

    pub fn get_face_embeddings_for_clusters(
        &self,
        cluster_ids: Vec<String>,
        limit: Option<i64>,
    ) -> Result<HashMap<String, Vec<Vec<u8>>>, MlDbError> {
        Ok(self
            .inner
            .db()
            .get_face_embeddings_for_clusters(&cluster_ids, limit)?)
    }

    pub fn get_cover_face_for_person(
        &self,
        recent_file_id: i64,
        person_id: Option<String>,
        avatar_face_id: Option<String>,
        cluster_id: Option<String>,
    ) -> Result<Option<FaceRow>, MlDbError> {
        Ok(self.inner.db().get_cover_face_for_person(
            recent_file_id,
            person_id.as_deref(),
            avatar_face_id.as_deref(),
            cluster_id.as_deref(),
        )?)
    }

    pub fn get_faces_for_given_file_id(
        &self,
        file_upload_id: i64,
    ) -> Result<Vec<FaceRow>, MlDbError> {
        Ok(self
            .inner
            .db()
            .get_faces_for_given_file_id(file_upload_id)?)
    }

    pub fn get_file_ids_to_faces_without_embedding(
        &self,
    ) -> Result<HashMap<i64, Vec<FaceWithoutEmbedding>>, MlDbError> {
        Ok(self.inner.db().get_file_ids_to_faces_without_embedding()?)
    }

    pub fn get_face_info_for_clustering(
        &self,
        max_faces: i64,
        offset: i64,
        batch_size: i64,
    ) -> Result<Vec<FaceDbInfoForClustering>, MlDbError> {
        Ok(self
            .inner
            .db()
            .get_face_info_for_clustering(max_faces, offset, batch_size)?)
    }

    pub fn get_face_embedding_rows_for_faces(
        &self,
        face_ids: Vec<String>,
    ) -> Result<Vec<(String, Vec<u8>)>, MlDbError> {
        Ok(self
            .inner
            .db()
            .get_face_embedding_rows_for_faces(&face_ids)?)
    }

    pub fn get_total_face_count(&self) -> Result<i64, MlDbError> {
        Ok(self.inner.db().get_total_face_count()?)
    }

    pub fn get_errored_face_count(&self) -> Result<i64, MlDbError> {
        Ok(self.inner.db().get_errored_face_count()?)
    }

    pub fn get_errored_file_ids(&self) -> Result<Vec<i64>, MlDbError> {
        Ok(self
            .inner
            .db()
            .get_errored_file_ids()?
            .into_iter()
            .collect())
    }

    pub fn prune_resolved_face_error_results(&self, file_ids: Vec<i64>) -> Result<(), MlDbError> {
        Ok(self
            .inner
            .db()
            .prune_resolved_face_error_results(&file_ids)?)
    }

    pub fn get_file_ids_with_error_results(
        &self,
        file_ids: Vec<i64>,
    ) -> Result<Vec<i64>, MlDbError> {
        Ok(self
            .inner
            .db()
            .get_file_ids_with_error_results(&file_ids)?
            .into_iter()
            .collect())
    }

    pub fn delete_face_index_for_files(&self, file_ids: Vec<i64>) -> Result<(), MlDbError> {
        Ok(self.inner.db().delete_face_index_for_files(&file_ids)?)
    }

    pub fn delete_unclustered_face_index_for_files(
        &self,
        file_ids: Vec<i64>,
    ) -> Result<(), MlDbError> {
        Ok(self
            .inner
            .db()
            .delete_unclustered_face_index_for_files(&file_ids)?)
    }

    pub fn get_clustered_or_faceless_file_count(&self) -> Result<i64, MlDbError> {
        Ok(self.inner.db().get_clustered_or_faceless_file_count()?)
    }

    pub fn get_unclustered_face_count(&self) -> Result<i64, MlDbError> {
        Ok(self.inner.db().get_unclustered_face_count()?)
    }

    pub fn get_all_file_ids_of_face_ids_not_in_any_cluster(&self) -> Result<Vec<i64>, MlDbError> {
        Ok(self
            .inner
            .db()
            .get_all_file_ids_of_face_ids_not_in_any_cluster()?
            .into_iter()
            .collect())
    }

    pub fn get_all_files_associated_with_all_clusters(
        &self,
        except_clusters: Option<Vec<String>>,
    ) -> Result<Vec<i64>, MlDbError> {
        Ok(self
            .inner
            .db()
            .get_all_files_associated_with_all_clusters(except_clusters.as_deref())?
            .into_iter()
            .collect())
    }

    pub fn get_fully_indexed_file_ids(&self, include_pets: bool) -> Result<Vec<i64>, MlDbError> {
        Ok(self
            .inner
            .db()
            .get_fully_indexed_file_ids(include_pets)?
            .into_iter()
            .collect())
    }

    pub fn update_face_id_to_cluster_id(
        &self,
        face_id_to_cluster_id: HashMap<String, String>,
    ) -> Result<(), MlDbError> {
        Ok(self
            .inner
            .db()
            .update_face_id_to_cluster_id(&face_id_to_cluster_id)?)
    }

    pub fn cluster_id_to_face_count(&self) -> Result<HashMap<String, i64>, MlDbError> {
        Ok(self.inner.db().cluster_id_to_face_count()?)
    }

    pub fn get_bad_face_singleton_cluster_ids(&self) -> Result<HashSet<String>, MlDbError> {
        Ok(self.inner.db().get_bad_face_singleton_cluster_ids()?)
    }

    pub fn get_cluster_to_face_ids(
        &self,
        cluster_ids: HashSet<String>,
    ) -> Result<HashMap<String, Vec<String>>, MlDbError> {
        Ok(self.inner.db().get_cluster_to_face_ids(&cluster_ids)?)
    }

    pub fn get_cluster_id_for_face_id(&self, face_id: String) -> Result<Option<String>, MlDbError> {
        Ok(self.inner.db().get_cluster_id_for_face_id(&face_id)?)
    }

    pub fn get_all_cluster_id_to_face_ids(
        &self,
    ) -> Result<HashMap<String, Vec<String>>, MlDbError> {
        Ok(self.inner.db().get_all_cluster_id_to_face_ids()?)
    }

    pub fn get_face_ids_for_cluster(&self, cluster_id: String) -> Result<Vec<String>, MlDbError> {
        Ok(self.inner.db().get_face_ids_for_cluster(&cluster_id)?)
    }

    pub fn get_face_ids_for_cluster_ordered_by_score(
        &self,
        cluster_id: String,
        limit: i64,
    ) -> Result<Vec<String>, MlDbError> {
        Ok(self
            .inner
            .db()
            .get_face_ids_for_cluster_ordered_by_score(&cluster_id, limit)?)
    }

    pub fn get_blur_values_for_cluster(&self, cluster_id: String) -> Result<Vec<f64>, MlDbError> {
        Ok(self.inner.db().get_blur_values_for_cluster(&cluster_id)?)
    }

    pub fn get_face_ids_to_cluster_ids(
        &self,
        face_ids: Vec<String>,
    ) -> Result<HashMap<String, Option<String>>, MlDbError> {
        Ok(self.inner.db().get_face_ids_to_cluster_ids(&face_ids)?)
    }

    pub fn get_file_id_to_cluster_ids(&self) -> Result<HashMap<i64, HashSet<String>>, MlDbError> {
        Ok(self.inner.db().get_file_id_to_cluster_ids()?)
    }

    pub fn force_update_cluster_ids(
        &self,
        face_id_to_cluster_id: HashMap<String, String>,
    ) -> Result<(), MlDbError> {
        Ok(self
            .inner
            .db()
            .force_update_cluster_ids(&face_id_to_cluster_id)?)
    }

    pub fn remove_face_id_to_cluster_id(
        &self,
        face_id_to_cluster_id: HashMap<String, String>,
    ) -> Result<(), MlDbError> {
        Ok(self
            .inner
            .db()
            .remove_face_id_to_cluster_id(&face_id_to_cluster_id)?)
    }

    pub fn get_file_id_to_cluster_id_set_for_cluster(
        &self,
        cluster_ids: HashSet<String>,
    ) -> Result<HashMap<i64, HashSet<String>>, MlDbError> {
        Ok(self
            .inner
            .db()
            .get_file_id_to_cluster_id_set_for_cluster(&cluster_ids)?)
    }

    pub fn get_file_ids_of_cluster_id(&self, cluster_id: String) -> Result<Vec<i64>, MlDbError> {
        Ok(self.inner.db().get_file_ids_of_cluster_id(&cluster_id)?)
    }

    pub fn get_all_cluster_summary(
        &self,
        min_cluster_size: Option<i64>,
    ) -> Result<HashMap<String, ClusterSummary>, MlDbError> {
        Ok(self.inner.db().get_all_cluster_summary(min_cluster_size)?)
    }

    pub fn get_cluster_to_cluster_summary(
        &self,
        cluster_ids: Vec<String>,
    ) -> Result<HashMap<String, ClusterSummary>, MlDbError> {
        Ok(self
            .inner
            .db()
            .get_cluster_to_cluster_summary(&cluster_ids)?)
    }

    pub fn get_clusters_for_memory_lane(
        &self,
        assigned: HashSet<String>,
    ) -> Result<HashSet<String>, MlDbError> {
        Ok(self.inner.db().get_clusters_for_memory_lane(&assigned)?)
    }

    pub fn get_clusters_with_three_or_more_not_person_feedback(
        &self,
    ) -> Result<HashSet<String>, MlDbError> {
        Ok(self
            .inner
            .db()
            .get_clusters_with_three_or_more_not_person_feedback()?)
    }

    pub fn get_person_ignored_clusters(
        &self,
        person_id: String,
    ) -> Result<HashSet<String>, MlDbError> {
        Ok(self.inner.db().get_person_ignored_clusters(&person_id)?)
    }

    pub fn get_person_to_rejected_suggestions(
        &self,
    ) -> Result<HashMap<String, HashSet<String>>, MlDbError> {
        Ok(self.inner.db().get_person_to_rejected_suggestions()?)
    }

    pub fn get_person_cluster_ids(&self, person_id: String) -> Result<HashSet<String>, MlDbError> {
        Ok(self.inner.db().get_person_cluster_ids(&person_id)?)
    }

    pub fn get_persons_cluster_ids(
        &self,
        person_ids: Vec<String>,
    ) -> Result<HashSet<String>, MlDbError> {
        Ok(self.inner.db().get_persons_cluster_ids(&person_ids)?)
    }

    pub fn get_person_to_cluster_id_to_face_ids(
        &self,
    ) -> Result<HashMap<String, HashMap<String, HashSet<String>>>, MlDbError> {
        Ok(self.inner.db().get_person_to_cluster_id_to_face_ids()?)
    }

    pub fn get_person_to_cluster_ids(&self) -> Result<HashMap<String, HashSet<String>>, MlDbError> {
        Ok(self.inner.db().get_person_to_cluster_ids()?)
    }

    pub fn get_face_id_to_person_id_for_faces(
        &self,
        face_ids: Vec<String>,
    ) -> Result<HashMap<String, String>, MlDbError> {
        Ok(self
            .inner
            .db()
            .get_face_id_to_person_id_for_faces(&face_ids)?)
    }

    pub fn get_cluster_id_to_face_ids_for_person(
        &self,
        person_id: String,
    ) -> Result<HashMap<String, HashSet<String>>, MlDbError> {
        Ok(self
            .inner
            .db()
            .get_cluster_id_to_face_ids_for_person(&person_id)?)
    }

    pub fn get_face_ids_for_person(&self, person_id: String) -> Result<HashSet<String>, MlDbError> {
        Ok(self.inner.db().get_face_ids_for_person(&person_id)?)
    }

    pub fn get_face_ids_for_person_ordered_by_score(
        &self,
        person_id: String,
        limit: i64,
    ) -> Result<Vec<String>, MlDbError> {
        Ok(self
            .inner
            .db()
            .get_face_ids_for_person_ordered_by_score(&person_id, limit)?)
    }

    pub fn remove_person(&self, person_id: String) -> Result<(), MlDbError> {
        Ok(self.inner.db().remove_person(&person_id)?)
    }

    pub fn assign_cluster_to_person(
        &self,
        person_id: String,
        cluster_id: String,
    ) -> Result<(), MlDbError> {
        Ok(self
            .inner
            .db()
            .assign_cluster_to_person(&person_id, &cluster_id)?)
    }

    pub fn bulk_assign_cluster_to_person_id(
        &self,
        cluster_to_person_id: HashMap<String, String>,
    ) -> Result<(), MlDbError> {
        Ok(self
            .inner
            .db()
            .bulk_assign_cluster_to_person_id(&cluster_to_person_id)?)
    }

    pub fn capture_not_person_feedback(
        &self,
        person_id: String,
        cluster_id: String,
    ) -> Result<(), MlDbError> {
        Ok(self
            .inner
            .db()
            .capture_not_person_feedback(&person_id, &cluster_id)?)
    }

    pub fn bulk_capture_not_person_feedback(
        &self,
        cluster_to_person_id: HashMap<String, String>,
    ) -> Result<(), MlDbError> {
        Ok(self
            .inner
            .db()
            .bulk_capture_not_person_feedback(&cluster_to_person_id)?)
    }

    pub fn remove_not_person_feedback(
        &self,
        person_id: String,
        cluster_id: String,
    ) -> Result<(), MlDbError> {
        Ok(self
            .inner
            .db()
            .remove_not_person_feedback(&person_id, &cluster_id)?)
    }

    pub fn remove_cluster_to_person(
        &self,
        person_id: String,
        cluster_id: String,
    ) -> Result<(), MlDbError> {
        Ok(self
            .inner
            .db()
            .remove_cluster_to_person(&person_id, &cluster_id)?)
    }

    pub fn get_file_id_to_cluster_id_set(
        &self,
        person_id: String,
    ) -> Result<HashMap<i64, HashSet<String>>, MlDbError> {
        Ok(self.inner.db().get_file_id_to_cluster_id_set(&person_id)?)
    }

    pub fn get_cluster_id_to_person_id(&self) -> Result<HashMap<String, String>, MlDbError> {
        Ok(self.inner.db().get_cluster_id_to_person_id()?)
    }

    pub fn drop_faces_feedback_tables(&self) -> Result<(), MlDbError> {
        Ok(self.inner.db().drop_faces_feedback_tables()?)
    }

    pub fn get_file_ids_of_person_id(&self, person_id: String) -> Result<Vec<i64>, MlDbError> {
        Ok(self.inner.db().get_file_ids_of_person_id(&person_id)?)
    }

    pub fn get_all_clip_vectors(&self) -> Result<Vec<EmbeddingVector>, MlDbError> {
        Ok(self.inner.db().get_all_clip_vectors()?)
    }

    pub fn clip_indexed_file_with_version(&self) -> Result<HashMap<i64, i64>, MlDbError> {
        Ok(self.inner.db().clip_indexed_file_with_version()?)
    }

    pub fn get_clip_indexed_file_count(&self, minimum_ml_version: i64) -> Result<i64, MlDbError> {
        Ok(self
            .inner
            .db()
            .get_clip_indexed_file_count(minimum_ml_version)?)
    }

    pub fn get_clip_vectorizable_file_count(
        &self,
        minimum_ml_version: i64,
    ) -> Result<i64, MlDbError> {
        Ok(self
            .inner
            .db()
            .get_clip_vectorizable_file_count(minimum_ml_version)?)
    }

    pub fn pet_indexed_file_ids(
        &self,
        minimum_ml_version: i64,
    ) -> Result<HashMap<i64, i64>, MlDbError> {
        Ok(self.inner.db().pet_indexed_file_ids(minimum_ml_version)?)
    }

    pub fn put_repeated_text_embedding_cache(
        &self,
        query: String,
        embedding: Vec<f64>,
    ) -> Result<(), MlDbError> {
        Ok(self
            .inner
            .db()
            .put_repeated_text_embedding_cache(&query, &embedding)?)
    }

    pub fn get_repeated_text_embedding_cache(
        &self,
        query: String,
    ) -> Result<Option<Vec<f32>>, MlDbError> {
        Ok(self.inner.db().get_repeated_text_embedding_cache(&query)?)
    }

    pub fn put_face_id_cached_for_person_or_cluster(
        &self,
        person_or_cluster_id: String,
        face_id: String,
    ) -> Result<(), MlDbError> {
        Ok(self
            .inner
            .db()
            .put_face_id_cached_for_person_or_cluster(&person_or_cluster_id, &face_id)?)
    }

    pub fn get_face_id_used_for_person_or_cluster(
        &self,
        person_or_cluster_id: String,
    ) -> Result<Option<String>, MlDbError> {
        Ok(self
            .inner
            .db()
            .get_face_id_used_for_person_or_cluster(&person_or_cluster_id)?)
    }

    pub fn remove_face_id_cached_for_person_or_cluster(
        &self,
        person_or_cluster_id: String,
    ) -> Result<(), MlDbError> {
        Ok(self
            .inner
            .db()
            .remove_face_id_cached_for_person_or_cluster(&person_or_cluster_id)?)
    }

    pub fn put_fd_status(&self, fd_status_list: Vec<FdStatus>) -> Result<(), MlDbError> {
        Ok(self.inner.db().put_fd_status(&fd_status_list)?)
    }

    pub fn get_file_ids_vid_preview(&self) -> Result<HashMap<i64, PreviewInfo>, MlDbError> {
        Ok(self.inner.db().get_file_ids_vid_preview()?)
    }

    pub fn get_file_ids_with_fd_data(
        &self,
        data_type: Option<String>,
    ) -> Result<Vec<i64>, MlDbError> {
        Ok(self
            .inner
            .db()
            .get_file_ids_with_fd_data(data_type.as_deref())?
            .into_iter()
            .collect())
    }
}

#[cfg(test)]
mod tests {
    use ente_vecdb::VecDbError;

    use super::{FillOutcome, FillReport, MlDbError, ml_db, ml_store};

    #[test]
    fn downgrade_errors_keep_the_bridge_variant_and_message() {
        let error = MlDbError::from(ml_db::Error::Downgrade {
            current: 16,
            target: 15,
        });
        assert!(matches!(
            error,
            MlDbError::Downgrade { message }
                if message == "currentVersion(16) cannot be greater than toVersion(15)"
        ));
    }

    #[test]
    fn other_errors_keep_the_bridge_variant_and_message() {
        let error = MlDbError::from(ml_db::Error::Invalid("invalid value".into()));
        assert!(matches!(
            error,
            MlDbError::Other { message } if message == "invalid value"
        ));
    }

    #[test]
    fn store_errors_wrapping_a_downgrade_keep_the_downgrade_variant() {
        let error = MlDbError::from(ml_store::Error::Database(ml_db::Error::Downgrade {
            current: 16,
            target: 15,
        }));
        assert!(matches!(
            error,
            MlDbError::Downgrade { message }
                if message == "currentVersion(16) cannot be greater than toVersion(15)"
        ));
    }

    #[test]
    fn store_index_errors_map_to_the_index_variant() {
        let error = MlDbError::from(ml_store::Error::Index(VecDbError::Closed));
        assert!(matches!(
            error,
            MlDbError::Index { message } if message == "vector db was deleted"
        ));
    }

    #[test]
    fn other_store_errors_map_to_the_other_variant() {
        let error = MlDbError::from(ml_store::Error::InvalidArgument("bad path".into()));
        assert!(matches!(
            error,
            MlDbError::Other { message } if message == "bad path"
        ));
    }

    #[test]
    fn fill_reports_keep_their_outcome_and_counts() {
        let report = FillReport::from(ml_store::FillReport {
            outcome: FillOutcome::Superseded,
            rows: 3,
            indexed: 2,
            skipped: 1,
            resumed: true,
        });
        assert_eq!(report.outcome, FillOutcome::Superseded);
        assert_eq!((report.rows, report.indexed, report.skipped), (3, 2, 1));
        assert!(report.resumed);
    }
}
