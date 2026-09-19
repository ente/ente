mod migrations;
mod queries;
mod schema;
pub(crate) mod vector_encoding;

use std::num::NonZeroUsize;
use std::path::Path;

use crate::db::{self, Database, OpenOptions};

pub use queries::clip::{
    CLIP_EMBEDDING_BYTES_LENGTH, CLIP_EMBEDDING_DIMENSIONS, CLIP_ML_VERSION, ClipEmbedding,
    ClipRow, EmbeddingVector,
};
pub use queries::clusters::{ClusterCentroidRow, ClusterSummary};
pub use queries::faces::{FACE_ML_VERSION, FaceDbInfoForClustering, FaceRow, FaceWithoutEmbedding};
pub use queries::filedata::{FdStatus, PreviewInfo};
pub use queries::persons::PersonToClusterIdToFaceIds;
pub use queries::pets::{
    PET_ML_VERSION, PetBodyRow, PetBodyVectorRow, PetFaceRow, PetFaceVectorRow, PetRowsForFiles,
};

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Database(#[from] db::Error),
    #[error("currentVersion({current}) cannot be greater than toVersion({target})")]
    Downgrade { current: i64, target: i64 },
    #[error("{0}")]
    Invalid(String),
}

pub type Result<T> = std::result::Result<T, Error>;

pub struct MlDb {
    db: Database,
}

impl MlDb {
    pub fn open(path: impl AsRef<Path>) -> Result<Self> {
        Ok(Self {
            db: Database::open(
                path,
                OpenOptions {
                    reader_count: const { NonZeroUsize::new(2).unwrap() },
                },
                |connection| {
                    connection.execute_batch(
                        "PRAGMA synchronous = NORMAL; PRAGMA journal_size_limit = 6291456;",
                    )?;
                    migrations::migrate(connection, &schema::MIGRATION_SCRIPTS)
                },
            )?,
        })
    }

    pub fn clear_non_pet_tables(&self) -> Result<()> {
        self.execute_statements([
            schema::DELETE_FACES,
            schema::DELETE_FACE_CLUSTERS,
            schema::DELETE_CLUSTER_PERSON,
            schema::DELETE_CLUSTER_SUMMARY,
            schema::DELETE_CLUSTER_CENTROID_VECTOR_ID_MAPPING,
            schema::DELETE_NOT_PERSON_FEEDBACK,
            schema::DELETE_CLIP_EMBEDDINGS,
            schema::DELETE_FILE_DATA,
        ])
    }

    pub fn clear_pet_tables(&self) -> Result<()> {
        self.execute_statements([
            schema::DELETE_PET_FACES,
            schema::DELETE_PET_BODIES,
            schema::DELETE_PET_FACE_VECTOR_ID_MAPPING,
            schema::DELETE_PET_BODY_VECTOR_ID_MAPPING,
        ])
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use std::collections::{HashMap, HashSet};
    use std::fmt::Debug;
    use std::path::Path;

    use super::queries::clip::tests::full_clip;
    use super::queries::{caches, clip, clusters, faces, filedata, persons, pets};
    use super::{Error, MlDb, schema};
    use crate::db::Connection;
    use tempfile::TempDir;

    type Query<T> = fn(&MlDb) -> Result<T, Error>;

    macro_rules! cases {
        ($($name:literal: $expected:expr => |$db:ident| $query:expr),* $(,)?) => {
            [$(($name, $expected, |$db| $query)),*]
        };
    }

    pub(crate) use super::queries::clusters::tests::deny_cluster_summary_inserts_after;
    pub(super) use cases;

    pub(super) fn open() -> (TempDir, MlDb) {
        let directory = tempfile::tempdir().unwrap();
        let db = MlDb::open(directory.path().join("ente.ml.db")).unwrap();
        (directory, db)
    }

    fn user_version(path: &Path) -> i64 {
        Connection::open(path)
            .unwrap()
            .pragma_query_value("user_version", |row| Ok(row.get(0)?))
            .unwrap()
    }

    pub(super) fn index_count(path: &Path) -> i64 {
        Connection::open(path)
            .unwrap()
            .query_row(
                "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'idx_fcClusterID'",
                (),
                |row| Ok(row.get(0)?),
            )
            .unwrap()
    }

    pub(super) fn check<T: PartialEq + Debug>(db: &MlDb, cases: &[(&str, T, Query<T>)]) {
        for (name, expected, query) in cases {
            assert_eq!(&query(db).unwrap(), expected, "{name}");
        }
    }

    fn strings_of<C: FromIterator<String>>(values: &[&str]) -> C {
        values.iter().map(ToString::to_string).collect()
    }

    pub(super) fn strings<const N: usize>(values: [&str; N]) -> Vec<String> {
        strings_of(&values)
    }

    pub(super) fn set<const N: usize>(values: [&str; N]) -> HashSet<String> {
        strings_of(&values)
    }

    pub(super) fn ids<const N: usize>(values: [i64; N]) -> HashSet<i64> {
        HashSet::from(values)
    }

    pub(super) fn pairs<V, const N: usize>(entries: [(&str, V); N]) -> HashMap<String, V> {
        entries
            .into_iter()
            .map(|(key, value)| (key.to_string(), value))
            .collect()
    }

    pub(super) fn map<const N: usize>(entries: [(&str, &str); N]) -> HashMap<String, String> {
        pairs(entries.map(|(key, value)| (key, value.to_string())))
    }

    pub(super) fn grouped<C: FromIterator<String>, const N: usize>(
        entries: [(&str, &[&str]); N],
    ) -> HashMap<String, C> {
        pairs(entries.map(|(key, values)| (key, strings_of(values))))
    }

    pub(super) fn grouped_by_file<const N: usize>(
        entries: [(i64, &[&str]); N],
    ) -> HashMap<i64, HashSet<String>> {
        entries
            .into_iter()
            .map(|(file_id, values)| (file_id, strings_of(values)))
            .collect()
    }

    pub(super) fn sorted<T: Ord>(mut values: Vec<T>) -> Vec<T> {
        values.sort();
        values
    }

    fn seeded_all() -> (TempDir, MlDb) {
        let (directory, db) = open();
        clip::tests::seed(&db);
        filedata::tests::seed(&db);
        caches::tests::seed(&db);
        faces::tests::seed(&db);
        clusters::tests::seed(&db);
        persons::tests::seed(&db);
        pets::tests::seed(&db);
        (directory, db)
    }

    #[test]
    fn clear_non_pet_tables_leaves_pets_and_caches() {
        let (_directory, db) = seeded_all();
        db.clear_non_pet_tables().unwrap();
        assert_eq!(db.get_total_face_count().unwrap(), 0);
        assert!(db.cluster_id_to_face_count().unwrap().is_empty());
        assert!(db.get_person_to_cluster_ids().unwrap().is_empty());
        assert!(db.get_person_to_rejected_suggestions().unwrap().is_empty());
        assert_eq!(db.count_cluster_summaries().unwrap(), 0);
        assert!(
            db.get_cluster_centroid_vector_id_map(&strings(["c1"]), false)
                .unwrap()
                .is_empty()
        );
        assert_eq!(db.count_clip_rows().unwrap(), 0);
        assert!(db.get_file_ids_with_fd_data(None).unwrap().is_empty());
        assert_eq!(db.get_pet_indexed_file_count(1).unwrap(), 2);
        assert_eq!(
            db.get_face_id_used_for_person_or_cluster("p1").unwrap(),
            Some("1_0".to_string())
        );
        assert_eq!(
            db.get_repeated_text_embedding_cache("dog").unwrap(),
            Some(vec![0.5f32, -1.0])
        );
    }

    #[test]
    fn clear_pet_tables_leaves_non_pet_tables() {
        let (directory, db) = seeded_all();
        let connection = Connection::open(directory.path().join("ente.ml.db")).unwrap();
        let row_count = |table: &str| -> i64 {
            connection
                .query_row(&format!("SELECT COUNT(*) FROM {table}"), (), |row| {
                    Ok(row.get(0)?)
                })
                .unwrap()
        };
        assert_eq!(row_count("pet_face_vector_id_map"), 2);
        assert_eq!(row_count("pet_body_vector_id_map"), 1);
        db.clear_pet_tables().unwrap();
        assert_eq!(row_count("pet_face_vector_id_map"), 0);
        assert_eq!(row_count("pet_body_vector_id_map"), 0);
        assert_eq!(db.get_pet_indexed_file_count(0).unwrap(), 0);
        assert_eq!(
            db.get_pet_rows_for_files(&[1, 2, 3]).unwrap().faces.len(),
            0
        );
        assert_eq!(db.get_total_face_count().unwrap(), 9);
        assert_eq!(db.cluster_id_to_face_count().unwrap().len(), 6);
        assert_eq!(db.get_person_cluster_ids("p1").unwrap().len(), 2);
        assert_eq!(db.count_clip_rows().unwrap(), 4);
        assert_eq!(
            db.get_file_ids_with_fd_data(None).unwrap(),
            HashSet::from([1, 2, 3])
        );
        assert_eq!(
            db.get_face_id_used_for_person_or_cluster("p1").unwrap(),
            Some("1_0".to_string())
        );
    }

    #[test]
    fn ml_connections_keep_existing_settings() {
        let (_directory, db) = open();
        let (synchronous, journal_size_limit): (i64, i64) = db
            .db
            .write(|connection| {
                Ok((
                    connection.pragma_query_value("synchronous", |row| Ok(row.get(0)?))?,
                    connection.pragma_query_value("journal_size_limit", |row| Ok(row.get(0)?))?,
                ))
            })
            .unwrap();
        assert_eq!(synchronous, 1);
        assert_eq!(journal_size_limit, 6291456);
    }

    #[test]
    fn ml_db_is_send_and_sync() {
        fn assert_send_sync<T: Send + Sync>() {}
        assert_send_sync::<MlDb>();
    }

    #[test]
    fn open_migrates_to_target_version_and_creates_all_tables() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("ente.ml.db");
        let _db = MlDb::open(&path).unwrap();
        assert_eq!(schema::MIGRATION_SCRIPTS.len(), 16);
        assert_eq!(user_version(&path), 16);
        let connection = Connection::open(&path).unwrap();
        for table in [
            "faces",
            "face_clusters",
            "cluster_person",
            "cluster_summary",
            "not_person_feedback",
            "clip",
            "filedata",
            "face_cache",
            "text_embeddings_cache",
            "cluster_centroid_vector_id_map",
            "pet_faces",
            "pet_bodies",
            "pet_face_vector_id_map",
            "pet_body_vector_id_map",
            "ml_store_meta",
        ] {
            let count: i64 = connection
                .query_row(
                    "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?",
                    [table],
                    |row| Ok(row.get(0)?),
                )
                .unwrap();
            assert_eq!(count, 1, "missing table {table}");
        }
        assert_eq!(index_count(&path), 1);
    }

    #[test]
    fn reopen_is_idempotent_and_keeps_data() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("ente.ml.db");
        {
            let db = MlDb::open(&path).unwrap();
            db.insert_clip_rows(&[full_clip(1)]).unwrap();
        }
        let db = MlDb::open(&path).unwrap();
        assert_eq!(user_version(&path), 16);
        assert_eq!(db.count_clip_rows().unwrap(), 1);
    }

    #[test]
    fn open_refuses_downgrade() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("ente.ml.db");
        drop(MlDb::open(&path).unwrap());
        Connection::open(&path)
            .unwrap()
            .pragma_update("user_version", 17)
            .unwrap();
        match MlDb::open(&path) {
            Err(Error::Downgrade { current, target }) => {
                assert_eq!(current, 17);
                assert_eq!(target, 16);
            }
            other => panic!("expected downgrade error, got {:?}", other.err()),
        }
    }

    #[test]
    fn partial_migration_runs_remaining_scripts() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("ente.ml.db");
        {
            let connection = Connection::open(&path).unwrap();
            connection
                .execute_batch(crate::ml_db::schema::CREATE_FACES_TABLE)
                .unwrap();
            connection.pragma_update("user_version", 1).unwrap();
        }
        let db = MlDb::open(&path).unwrap();
        assert_eq!(user_version(&path), 16);
        assert_eq!(db.count_clip_rows().unwrap(), 0);
    }
}
