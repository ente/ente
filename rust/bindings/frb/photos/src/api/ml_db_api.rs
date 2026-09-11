use std::collections::{HashMap, HashSet};
use std::sync::OnceLock;

use ente_photos::db;
use ente_photos::ml_db;
pub use ente_photos::ml_db::{
    ClipEmbedding, ClipRow, ClusterCentroidRow, ClusterSummary, EmbeddingVector,
    FaceDbInfoForClustering, FaceRow, FaceWithoutEmbedding, FdStatus, PetBodyRow, PetBodyVectorRow,
    PetFaceRow, PetFaceVectorRow, PetRowsForFiles, PreviewInfo,
};
use flutter_rust_bridge::frb;

static BACKEND: OnceLock<bool> = OnceLock::new();

#[frb(sync)]
pub fn decide_ml_db_backend(prefer_rust: bool) -> bool {
    *BACKEND.get_or_init(|| prefer_rust)
}

#[frb]
pub enum MlDbError {
    Downgrade { message: String },
    Other { message: String },
}

impl From<ml_db::Error> for MlDbError {
    fn from(error: ml_db::Error) -> Self {
        let message = ente_core::error::chain(&error);
        match error {
            ml_db::Error::Database(db::Error::Downgrade { .. }) => Self::Downgrade { message },
            _ => Self::Other { message },
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

#[frb(mirror(PetFaceRow))]
pub struct _PetFaceRow {
    pub file_id: i64,
    pub pet_face_id: String,
    pub detection_json: String,
    pub face_vector_id: Option<i64>,
    pub species: i64,
    pub face_score: f64,
    pub image_height: i64,
    pub image_width: i64,
    pub ml_version: i64,
}

#[frb(mirror(PetBodyRow))]
pub struct _PetBodyRow {
    pub file_id: i64,
    pub pet_body_id: String,
    pub detection_json: String,
    pub body_vector_id: Option<i64>,
    pub species: i64,
    pub score: f64,
    pub image_height: i64,
    pub image_width: i64,
    pub ml_version: i64,
}

#[frb(mirror(PetFaceVectorRow))]
pub struct _PetFaceVectorRow {
    pub pet_face_id: String,
    pub face_vector_id: Option<i64>,
    pub species: i64,
}

#[frb(mirror(PetBodyVectorRow))]
pub struct _PetBodyVectorRow {
    pub pet_body_id: String,
    pub body_vector_id: Option<i64>,
    pub species: i64,
}

#[frb(mirror(PetRowsForFiles))]
pub struct _PetRowsForFiles {
    pub faces: Vec<PetFaceVectorRow>,
    pub bodies: Vec<PetBodyVectorRow>,
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

#[frb(mirror(ClipRow))]
pub struct _ClipRow {
    pub file_id: i64,
    pub embedding: Vec<u8>,
}

#[frb(mirror(ClusterSummary))]
pub struct _ClusterSummary {
    pub avg: Vec<u8>,
    pub count: i64,
}

#[frb(mirror(ClusterCentroidRow))]
pub struct _ClusterCentroidRow {
    pub cluster_id: String,
    pub avg: Vec<u8>,
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

#[frb(opaque)]
pub struct MlDb {
    inner: ml_db::MlDb,
}

impl MlDb {
    pub fn open(path: String) -> Result<MlDb, MlDbError> {
        Ok(Self {
            inner: ml_db::MlDb::open(path)?,
        })
    }

    pub fn clear_non_pet_tables(&self) -> Result<(), MlDbError> {
        Ok(self.inner.clear_non_pet_tables()?)
    }

    pub fn clear_pet_tables(&self) -> Result<(), MlDbError> {
        Ok(self.inner.clear_pet_tables()?)
    }

    pub fn bulk_insert_faces(&self, faces: Vec<FaceRow>) -> Result<(), MlDbError> {
        Ok(self.inner.bulk_insert_faces(&faces)?)
    }

    pub fn face_indexed_file_ids(
        &self,
        minimum_ml_version: i64,
    ) -> Result<HashMap<i64, i64>, MlDbError> {
        Ok(self.inner.face_indexed_file_ids(minimum_ml_version)?)
    }

    pub fn get_face_indexed_file_count(&self, minimum_ml_version: i64) -> Result<i64, MlDbError> {
        Ok(self.inner.get_face_indexed_file_count(minimum_ml_version)?)
    }

    pub fn get_face_embeddings_for_cluster(
        &self,
        cluster_id: String,
        limit: Option<i64>,
    ) -> Result<Vec<Vec<u8>>, MlDbError> {
        Ok(self
            .inner
            .get_face_embeddings_for_cluster(&cluster_id, limit)?)
    }

    pub fn get_face_embeddings_for_clusters(
        &self,
        cluster_ids: Vec<String>,
        limit: Option<i64>,
    ) -> Result<HashMap<String, Vec<Vec<u8>>>, MlDbError> {
        Ok(self
            .inner
            .get_face_embeddings_for_clusters(&cluster_ids, limit)?)
    }

    pub fn get_cover_face_for_person(
        &self,
        recent_file_id: i64,
        person_id: Option<String>,
        avatar_face_id: Option<String>,
        cluster_id: Option<String>,
    ) -> Result<Option<FaceRow>, MlDbError> {
        Ok(self.inner.get_cover_face_for_person(
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
        Ok(self.inner.get_faces_for_given_file_id(file_upload_id)?)
    }

    pub fn get_file_ids_to_faces_without_embedding(
        &self,
    ) -> Result<HashMap<i64, Vec<FaceWithoutEmbedding>>, MlDbError> {
        Ok(self.inner.get_file_ids_to_faces_without_embedding()?)
    }

    pub fn get_face_info_for_clustering(
        &self,
        max_faces: i64,
        offset: i64,
        batch_size: i64,
    ) -> Result<Vec<FaceDbInfoForClustering>, MlDbError> {
        Ok(self
            .inner
            .get_face_info_for_clustering(max_faces, offset, batch_size)?)
    }

    pub fn get_face_embedding_rows_for_faces(
        &self,
        face_ids: Vec<String>,
    ) -> Result<Vec<(String, Vec<u8>)>, MlDbError> {
        Ok(self.inner.get_face_embedding_rows_for_faces(&face_ids)?)
    }

    pub fn get_total_face_count(&self) -> Result<i64, MlDbError> {
        Ok(self.inner.get_total_face_count()?)
    }

    pub fn get_errored_face_count(&self) -> Result<i64, MlDbError> {
        Ok(self.inner.get_errored_face_count()?)
    }

    pub fn get_errored_file_ids(&self) -> Result<Vec<i64>, MlDbError> {
        Ok(self.inner.get_errored_file_ids()?.into_iter().collect())
    }

    pub fn prune_resolved_face_error_results(&self, file_ids: Vec<i64>) -> Result<(), MlDbError> {
        Ok(self.inner.prune_resolved_face_error_results(&file_ids)?)
    }

    pub fn get_file_ids_with_error_results(
        &self,
        file_ids: Vec<i64>,
    ) -> Result<Vec<i64>, MlDbError> {
        Ok(self
            .inner
            .get_file_ids_with_error_results(&file_ids)?
            .into_iter()
            .collect())
    }

    pub fn delete_face_index_for_files(&self, file_ids: Vec<i64>) -> Result<(), MlDbError> {
        Ok(self.inner.delete_face_index_for_files(&file_ids)?)
    }

    pub fn delete_unclustered_face_index_for_files(
        &self,
        file_ids: Vec<i64>,
    ) -> Result<(), MlDbError> {
        Ok(self
            .inner
            .delete_unclustered_face_index_for_files(&file_ids)?)
    }

    pub fn get_clustered_or_faceless_file_count(&self) -> Result<i64, MlDbError> {
        Ok(self.inner.get_clustered_or_faceless_file_count()?)
    }

    pub fn get_unclustered_face_count(&self) -> Result<i64, MlDbError> {
        Ok(self.inner.get_unclustered_face_count()?)
    }

    pub fn get_all_file_ids_of_face_ids_not_in_any_cluster(&self) -> Result<Vec<i64>, MlDbError> {
        Ok(self
            .inner
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
            .get_all_files_associated_with_all_clusters(except_clusters.as_deref())?
            .into_iter()
            .collect())
    }

    pub fn get_fully_indexed_file_ids(&self, include_pets: bool) -> Result<Vec<i64>, MlDbError> {
        Ok(self
            .inner
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
            .update_face_id_to_cluster_id(&face_id_to_cluster_id)?)
    }

    pub fn cluster_id_to_face_count(&self) -> Result<HashMap<String, i64>, MlDbError> {
        Ok(self.inner.cluster_id_to_face_count()?)
    }

    pub fn get_bad_face_singleton_cluster_ids(&self) -> Result<HashSet<String>, MlDbError> {
        Ok(self.inner.get_bad_face_singleton_cluster_ids()?)
    }

    pub fn get_cluster_to_face_ids(
        &self,
        cluster_ids: HashSet<String>,
    ) -> Result<HashMap<String, Vec<String>>, MlDbError> {
        Ok(self.inner.get_cluster_to_face_ids(&cluster_ids)?)
    }

    pub fn get_cluster_id_for_face_id(&self, face_id: String) -> Result<Option<String>, MlDbError> {
        Ok(self.inner.get_cluster_id_for_face_id(&face_id)?)
    }

    pub fn get_all_cluster_id_to_face_ids(
        &self,
    ) -> Result<HashMap<String, Vec<String>>, MlDbError> {
        Ok(self.inner.get_all_cluster_id_to_face_ids()?)
    }

    pub fn get_face_ids_for_cluster(&self, cluster_id: String) -> Result<Vec<String>, MlDbError> {
        Ok(self.inner.get_face_ids_for_cluster(&cluster_id)?)
    }

    pub fn get_face_ids_for_cluster_ordered_by_score(
        &self,
        cluster_id: String,
        limit: i64,
    ) -> Result<Vec<String>, MlDbError> {
        Ok(self
            .inner
            .get_face_ids_for_cluster_ordered_by_score(&cluster_id, limit)?)
    }

    pub fn get_blur_values_for_cluster(&self, cluster_id: String) -> Result<Vec<f64>, MlDbError> {
        Ok(self.inner.get_blur_values_for_cluster(&cluster_id)?)
    }

    pub fn get_face_ids_to_cluster_ids(
        &self,
        face_ids: Vec<String>,
    ) -> Result<HashMap<String, Option<String>>, MlDbError> {
        Ok(self.inner.get_face_ids_to_cluster_ids(&face_ids)?)
    }

    pub fn get_file_id_to_cluster_ids(&self) -> Result<HashMap<i64, HashSet<String>>, MlDbError> {
        Ok(self.inner.get_file_id_to_cluster_ids()?)
    }

    pub fn force_update_cluster_ids(
        &self,
        face_id_to_cluster_id: HashMap<String, String>,
    ) -> Result<(), MlDbError> {
        Ok(self
            .inner
            .force_update_cluster_ids(&face_id_to_cluster_id)?)
    }

    pub fn remove_face_id_to_cluster_id(
        &self,
        face_id_to_cluster_id: HashMap<String, String>,
    ) -> Result<(), MlDbError> {
        Ok(self
            .inner
            .remove_face_id_to_cluster_id(&face_id_to_cluster_id)?)
    }

    pub fn get_file_id_to_cluster_id_set_for_cluster(
        &self,
        cluster_ids: HashSet<String>,
    ) -> Result<HashMap<i64, HashSet<String>>, MlDbError> {
        Ok(self
            .inner
            .get_file_id_to_cluster_id_set_for_cluster(&cluster_ids)?)
    }

    pub fn get_file_ids_of_cluster_id(&self, cluster_id: String) -> Result<Vec<i64>, MlDbError> {
        Ok(self.inner.get_file_ids_of_cluster_id(&cluster_id)?)
    }

    pub fn get_cluster_centroid_vector_id_map(
        &self,
        cluster_ids: Vec<String>,
        create_if_missing: bool,
    ) -> Result<HashMap<String, i64>, MlDbError> {
        Ok(self
            .inner
            .get_cluster_centroid_vector_id_map(&cluster_ids, create_if_missing)?)
    }

    pub fn delete_cluster_centroid_vector_id_mapping(
        &self,
        cluster_id: String,
    ) -> Result<(), MlDbError> {
        Ok(self
            .inner
            .delete_cluster_centroid_vector_id_mapping(&cluster_id)?)
    }

    pub fn clear_cluster_centroid_vector_id_mappings(&self) -> Result<(), MlDbError> {
        Ok(self.inner.clear_cluster_centroid_vector_id_mappings()?)
    }

    pub fn upsert_cluster_summary_rows(
        &self,
        summary: HashMap<String, ClusterSummary>,
    ) -> Result<(), MlDbError> {
        Ok(self.inner.upsert_cluster_summary_rows(&summary)?)
    }

    pub fn delete_cluster_summary_row(&self, cluster_id: String) -> Result<(), MlDbError> {
        Ok(self.inner.delete_cluster_summary_row(&cluster_id)?)
    }

    pub fn get_all_cluster_summary(
        &self,
        min_cluster_size: Option<i64>,
    ) -> Result<HashMap<String, ClusterSummary>, MlDbError> {
        Ok(self.inner.get_all_cluster_summary(min_cluster_size)?)
    }

    pub fn get_cluster_to_cluster_summary(
        &self,
        cluster_ids: Vec<String>,
    ) -> Result<HashMap<String, ClusterSummary>, MlDbError> {
        Ok(self.inner.get_cluster_to_cluster_summary(&cluster_ids)?)
    }

    pub fn count_cluster_summaries(&self) -> Result<i64, MlDbError> {
        Ok(self.inner.count_cluster_summaries()?)
    }

    pub fn get_cluster_summary_page(
        &self,
        before_cluster_id: Option<String>,
        limit: i64,
    ) -> Result<Vec<ClusterCentroidRow>, MlDbError> {
        Ok(self
            .inner
            .get_cluster_summary_page(before_cluster_id.as_deref(), limit)?)
    }

    pub fn reset_cluster_tables(&self, faces: bool) -> Result<(), MlDbError> {
        Ok(self.inner.reset_cluster_tables(faces)?)
    }

    pub fn get_clusters_for_memory_lane(
        &self,
        assigned: HashSet<String>,
    ) -> Result<HashSet<String>, MlDbError> {
        Ok(self.inner.get_clusters_for_memory_lane(&assigned)?)
    }

    pub fn get_clusters_with_three_or_more_not_person_feedback(
        &self,
    ) -> Result<HashSet<String>, MlDbError> {
        Ok(self
            .inner
            .get_clusters_with_three_or_more_not_person_feedback()?)
    }

    pub fn get_person_ignored_clusters(
        &self,
        person_id: String,
    ) -> Result<HashSet<String>, MlDbError> {
        Ok(self.inner.get_person_ignored_clusters(&person_id)?)
    }

    pub fn get_person_to_rejected_suggestions(
        &self,
    ) -> Result<HashMap<String, HashSet<String>>, MlDbError> {
        Ok(self.inner.get_person_to_rejected_suggestions()?)
    }

    pub fn get_person_cluster_ids(&self, person_id: String) -> Result<HashSet<String>, MlDbError> {
        Ok(self.inner.get_person_cluster_ids(&person_id)?)
    }

    pub fn get_persons_cluster_ids(
        &self,
        person_ids: Vec<String>,
    ) -> Result<HashSet<String>, MlDbError> {
        Ok(self.inner.get_persons_cluster_ids(&person_ids)?)
    }

    pub fn get_person_to_cluster_id_to_face_ids(
        &self,
    ) -> Result<HashMap<String, HashMap<String, HashSet<String>>>, MlDbError> {
        Ok(self.inner.get_person_to_cluster_id_to_face_ids()?)
    }

    pub fn get_person_to_cluster_ids(&self) -> Result<HashMap<String, HashSet<String>>, MlDbError> {
        Ok(self.inner.get_person_to_cluster_ids()?)
    }

    pub fn get_face_id_to_person_id_for_faces(
        &self,
        face_ids: Vec<String>,
    ) -> Result<HashMap<String, String>, MlDbError> {
        Ok(self.inner.get_face_id_to_person_id_for_faces(&face_ids)?)
    }

    pub fn get_cluster_id_to_face_ids_for_person(
        &self,
        person_id: String,
    ) -> Result<HashMap<String, HashSet<String>>, MlDbError> {
        Ok(self
            .inner
            .get_cluster_id_to_face_ids_for_person(&person_id)?)
    }

    pub fn get_face_ids_for_person(&self, person_id: String) -> Result<HashSet<String>, MlDbError> {
        Ok(self.inner.get_face_ids_for_person(&person_id)?)
    }

    pub fn get_face_ids_for_person_ordered_by_score(
        &self,
        person_id: String,
        limit: i64,
    ) -> Result<Vec<String>, MlDbError> {
        Ok(self
            .inner
            .get_face_ids_for_person_ordered_by_score(&person_id, limit)?)
    }

    pub fn remove_person(&self, person_id: String) -> Result<(), MlDbError> {
        Ok(self.inner.remove_person(&person_id)?)
    }

    pub fn assign_cluster_to_person(
        &self,
        person_id: String,
        cluster_id: String,
    ) -> Result<(), MlDbError> {
        Ok(self
            .inner
            .assign_cluster_to_person(&person_id, &cluster_id)?)
    }

    pub fn bulk_assign_cluster_to_person_id(
        &self,
        cluster_to_person_id: HashMap<String, String>,
    ) -> Result<(), MlDbError> {
        Ok(self
            .inner
            .bulk_assign_cluster_to_person_id(&cluster_to_person_id)?)
    }

    pub fn capture_not_person_feedback(
        &self,
        person_id: String,
        cluster_id: String,
    ) -> Result<(), MlDbError> {
        Ok(self
            .inner
            .capture_not_person_feedback(&person_id, &cluster_id)?)
    }

    pub fn bulk_capture_not_person_feedback(
        &self,
        cluster_to_person_id: HashMap<String, String>,
    ) -> Result<(), MlDbError> {
        Ok(self
            .inner
            .bulk_capture_not_person_feedback(&cluster_to_person_id)?)
    }

    pub fn remove_not_person_feedback(
        &self,
        person_id: String,
        cluster_id: String,
    ) -> Result<(), MlDbError> {
        Ok(self
            .inner
            .remove_not_person_feedback(&person_id, &cluster_id)?)
    }

    pub fn remove_cluster_to_person(
        &self,
        person_id: String,
        cluster_id: String,
    ) -> Result<(), MlDbError> {
        Ok(self
            .inner
            .remove_cluster_to_person(&person_id, &cluster_id)?)
    }

    pub fn get_file_id_to_cluster_id_set(
        &self,
        person_id: String,
    ) -> Result<HashMap<i64, HashSet<String>>, MlDbError> {
        Ok(self.inner.get_file_id_to_cluster_id_set(&person_id)?)
    }

    pub fn get_cluster_id_to_person_id(&self) -> Result<HashMap<String, String>, MlDbError> {
        Ok(self.inner.get_cluster_id_to_person_id()?)
    }

    pub fn drop_faces_feedback_tables(&self) -> Result<(), MlDbError> {
        Ok(self.inner.drop_faces_feedback_tables()?)
    }

    pub fn get_file_ids_of_person_id(&self, person_id: String) -> Result<Vec<i64>, MlDbError> {
        Ok(self.inner.get_file_ids_of_person_id(&person_id)?)
    }

    pub fn get_all_clip_vectors(&self) -> Result<Vec<EmbeddingVector>, MlDbError> {
        Ok(self.inner.get_all_clip_vectors()?)
    }

    pub fn clip_indexed_file_with_version(&self) -> Result<HashMap<i64, i64>, MlDbError> {
        Ok(self.inner.clip_indexed_file_with_version()?)
    }

    pub fn get_clip_indexed_file_count(&self, minimum_ml_version: i64) -> Result<i64, MlDbError> {
        Ok(self.inner.get_clip_indexed_file_count(minimum_ml_version)?)
    }

    pub fn get_clip_vectorizable_file_count(
        &self,
        minimum_ml_version: i64,
    ) -> Result<i64, MlDbError> {
        Ok(self
            .inner
            .get_clip_vectorizable_file_count(minimum_ml_version)?)
    }

    pub fn insert_clip_rows(&self, embeddings: Vec<ClipEmbedding>) -> Result<(), MlDbError> {
        Ok(self.inner.insert_clip_rows(&embeddings)?)
    }

    pub fn delete_clip_rows(&self, file_ids: Vec<i64>) -> Result<(), MlDbError> {
        Ok(self.inner.delete_clip_rows(&file_ids)?)
    }

    pub fn delete_all_clip_rows(&self) -> Result<(), MlDbError> {
        Ok(self.inner.delete_all_clip_rows()?)
    }

    pub fn count_clip_rows(&self) -> Result<i64, MlDbError> {
        Ok(self.inner.count_clip_rows()?)
    }

    pub fn get_clip_rows_page(&self, limit: i64, offset: i64) -> Result<Vec<ClipRow>, MlDbError> {
        Ok(self.inner.get_clip_rows_page(limit, offset)?)
    }

    pub fn bulk_insert_pet_faces(&self, pet_faces: Vec<PetFaceRow>) -> Result<(), MlDbError> {
        Ok(self.inner.bulk_insert_pet_faces(&pet_faces)?)
    }

    pub fn bulk_insert_pet_bodies(&self, pet_bodies: Vec<PetBodyRow>) -> Result<(), MlDbError> {
        Ok(self.inner.bulk_insert_pet_bodies(&pet_bodies)?)
    }

    pub fn update_pet_face_vector_ids(
        &self,
        pet_face_id_to_vector_id: HashMap<String, i64>,
    ) -> Result<(), MlDbError> {
        Ok(self
            .inner
            .update_pet_face_vector_ids(&pet_face_id_to_vector_id)?)
    }

    pub fn update_pet_body_vector_ids(
        &self,
        pet_body_id_to_vector_id: HashMap<String, i64>,
    ) -> Result<(), MlDbError> {
        Ok(self
            .inner
            .update_pet_body_vector_ids(&pet_body_id_to_vector_id)?)
    }

    pub fn get_pet_faces_for_file_id(
        &self,
        file_upload_id: i64,
    ) -> Result<Vec<PetFaceRow>, MlDbError> {
        Ok(self.inner.get_pet_faces_for_file_id(file_upload_id)?)
    }

    pub fn get_pet_bodies_for_file_id(
        &self,
        file_upload_id: i64,
    ) -> Result<Vec<PetBodyRow>, MlDbError> {
        Ok(self.inner.get_pet_bodies_for_file_id(file_upload_id)?)
    }

    pub fn pet_indexed_file_ids(
        &self,
        minimum_ml_version: i64,
    ) -> Result<HashMap<i64, i64>, MlDbError> {
        Ok(self.inner.pet_indexed_file_ids(minimum_ml_version)?)
    }

    pub fn get_pet_indexed_file_count(&self, minimum_ml_version: i64) -> Result<i64, MlDbError> {
        Ok(self.inner.get_pet_indexed_file_count(minimum_ml_version)?)
    }

    pub fn get_pet_rows_for_files(&self, file_ids: Vec<i64>) -> Result<PetRowsForFiles, MlDbError> {
        Ok(self.inner.get_pet_rows_for_files(&file_ids)?)
    }

    pub fn delete_pet_rows_for_files(
        &self,
        file_ids: Vec<i64>,
        pet_face_ids: Vec<String>,
        pet_body_ids: Vec<String>,
    ) -> Result<(), MlDbError> {
        Ok(self
            .inner
            .delete_pet_rows_for_files(&file_ids, &pet_face_ids, &pet_body_ids)?)
    }

    pub fn get_pet_face_vector_id_map(
        &self,
        pet_face_ids: Vec<String>,
        create_if_missing: bool,
    ) -> Result<HashMap<String, i64>, MlDbError> {
        Ok(self
            .inner
            .get_pet_face_vector_id_map(&pet_face_ids, create_if_missing)?)
    }

    pub fn get_pet_body_vector_id_map(
        &self,
        pet_body_ids: Vec<String>,
        create_if_missing: bool,
    ) -> Result<HashMap<String, i64>, MlDbError> {
        Ok(self
            .inner
            .get_pet_body_vector_id_map(&pet_body_ids, create_if_missing)?)
    }

    pub fn put_repeated_text_embedding_cache(
        &self,
        query: String,
        embedding: Vec<f64>,
    ) -> Result<(), MlDbError> {
        Ok(self
            .inner
            .put_repeated_text_embedding_cache(&query, &embedding)?)
    }

    pub fn get_repeated_text_embedding_cache(
        &self,
        query: String,
    ) -> Result<Option<Vec<f32>>, MlDbError> {
        Ok(self.inner.get_repeated_text_embedding_cache(&query)?)
    }

    pub fn put_face_id_cached_for_person_or_cluster(
        &self,
        person_or_cluster_id: String,
        face_id: String,
    ) -> Result<(), MlDbError> {
        Ok(self
            .inner
            .put_face_id_cached_for_person_or_cluster(&person_or_cluster_id, &face_id)?)
    }

    pub fn get_face_id_used_for_person_or_cluster(
        &self,
        person_or_cluster_id: String,
    ) -> Result<Option<String>, MlDbError> {
        Ok(self
            .inner
            .get_face_id_used_for_person_or_cluster(&person_or_cluster_id)?)
    }

    pub fn remove_face_id_cached_for_person_or_cluster(
        &self,
        person_or_cluster_id: String,
    ) -> Result<(), MlDbError> {
        Ok(self
            .inner
            .remove_face_id_cached_for_person_or_cluster(&person_or_cluster_id)?)
    }

    pub fn put_fd_status(&self, fd_status_list: Vec<FdStatus>) -> Result<(), MlDbError> {
        Ok(self.inner.put_fd_status(&fd_status_list)?)
    }

    pub fn get_file_ids_vid_preview(&self) -> Result<HashMap<i64, PreviewInfo>, MlDbError> {
        Ok(self.inner.get_file_ids_vid_preview()?)
    }

    pub fn get_file_ids_with_fd_data(
        &self,
        data_type: Option<String>,
    ) -> Result<Vec<i64>, MlDbError> {
        Ok(self
            .inner
            .get_file_ids_with_fd_data(data_type.as_deref())?
            .into_iter()
            .collect())
    }
}
