mod fill;
mod index;
mod lock;
mod state;
mod writes;

use std::path::Path;
use std::sync::{Arc, MutexGuard, PoisonError};

use ente_vecdb::{VecDb, VecDbError};

use crate::ml_db::MlDb;

pub use ente_vecdb::{KeyMatches, Match, SearchParams, Stats};
pub use fill::{FillOutcome, FillReport};
pub use index::{
    CLUSTER_CENTROID_DIMENSIONS, Index, PET_BODY_DIMENSIONS, PET_FACE_DIMENSIONS, Species,
};
pub use state::FillState;
pub use writes::PetEmbedding;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Database(#[from] crate::ml_db::Error),
    #[error(transparent)]
    Index(#[from] VecDbError),
    #[error("{0}")]
    InvalidArgument(String),
}

pub type Result<T> = std::result::Result<T, Error>;

type IndexResult<T> = std::result::Result<T, VecDbError>;

pub struct MlStore {
    db: MlDb,
    locks: Arc<lock::Locks>,
    indexes: [index::Slot; Index::ALL.len()],
}

impl MlStore {
    pub fn open(db_path: impl AsRef<Path>, index_dir: impl AsRef<Path>) -> Result<Self> {
        let db_path = db_path.as_ref();
        let db_stem = index::db_stem(db_path)?;
        let db = MlDb::open(db_path)?;
        Ok(Self {
            db,
            locks: lock::for_database(db_path),
            indexes: Index::ALL.map(|index| index::Slot::new(index, index_dir.as_ref(), &db_stem)),
        })
    }

    pub fn db(&self) -> &MlDb {
        &self.db
    }

    pub fn release(&self) -> Result<()> {
        let mut outcome = Ok(());
        for slot in &self.indexes {
            outcome = outcome.and(slot.release());
        }
        outcome
    }

    pub fn fill_state(&self, index: Index) -> Result<FillState> {
        state::read(&self.db, index)
    }

    pub fn search(&self, index: Index, query: &[f32], params: &SearchParams) -> Result<Vec<Match>> {
        self.read_index(index, |vecdb| vecdb.search(query, params))
    }

    pub fn bulk_search(
        &self,
        index: Index,
        queries: &[Vec<f32>],
        params: &SearchParams,
    ) -> Result<Vec<Vec<Match>>> {
        self.read_index(index, |vecdb| vecdb.bulk_search(queries, params))
    }

    pub fn bulk_search_stored(
        &self,
        index: Index,
        keys: &[String],
        count: usize,
        max_distance: Option<f32>,
        exact: bool,
        restrict_to_input: bool,
    ) -> Result<Vec<KeyMatches>> {
        self.read_index(index, |vecdb| {
            vecdb.bulk_search_stored(keys, count, max_distance, exact, restrict_to_input)
        })
    }

    pub fn get_vector(&self, index: Index, key: &str) -> Result<Option<Vec<f32>>> {
        self.read_index(index, |vecdb| vecdb.get(key))
    }

    pub fn contains(&self, index: Index, key: &str) -> Result<bool> {
        self.read_index(index, |vecdb| vecdb.contains(key))
    }

    pub fn stats(&self, index: Index) -> Result<Stats> {
        self.read_index(index, VecDb::stats)
    }

    fn lock_mutations(&self) -> MutexGuard<'_, ()> {
        self.locks
            .mutations
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
    }

    fn lock_fill(&self, index: Index) -> MutexGuard<'_, ()> {
        self.locks.fills[index.position()]
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
    }

    fn with_index<T>(
        &self,
        index: Index,
        operation: impl Fn(&VecDb) -> IndexResult<T>,
    ) -> Result<T> {
        self.indexes[index.position()].with_open(&self.db, operation)
    }

    fn read_index<T>(
        &self,
        index: Index,
        operation: impl Fn(&VecDb) -> IndexResult<T>,
    ) -> Result<T> {
        let slot = &self.indexes[index.position()];
        if let Some(outcome) = slot.with_open_handle(&operation) {
            return outcome;
        }
        let _mutations = self.lock_mutations();
        slot.with_open(&self.db, operation)
    }
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::path::{Path, PathBuf};

    use ente_vecdb::{OpenCost, SearchParams, VecDb};
    use tempfile::TempDir;

    use super::{FillOutcome, FillReport, FillState, Index, MlStore, PetEmbedding, Species};
    use crate::ml_db::{CLIP_EMBEDDING_DIMENSIONS, ClipEmbedding, ClusterSummary, encode_evector};

    pub(super) const DB_FILE: &str = "ente.ml.db";

    pub(super) fn open() -> (TempDir, MlStore) {
        let directory = tempfile::tempdir().unwrap();
        let store = open_in(&directory);
        (directory, store)
    }

    pub(super) fn open_in(directory: &TempDir) -> MlStore {
        MlStore::open(directory.path().join(DB_FILE), directory.path()).unwrap()
    }

    pub(super) fn open_with_unusable_index_dir() -> (TempDir, MlStore) {
        let directory = tempfile::tempdir().unwrap();
        let blocker = directory.path().join("indexes");
        fs::write(&blocker, b"not a directory").unwrap();
        let store = MlStore::open(directory.path().join(DB_FILE), &blocker).unwrap();
        (directory, store)
    }

    pub(super) fn index_path(directory: &TempDir, index: Index) -> PathBuf {
        directory
            .path()
            .join(format!("ente.ml.vecdb.{}", index.name()))
    }

    pub(super) fn one_hot(dims: usize, hot: usize) -> Vec<f32> {
        let mut vector = vec![0.0; dims];
        vector[hot % dims] = 1.0;
        vector
    }

    pub(super) fn clip(file_id: i64) -> ClipEmbedding {
        ClipEmbedding {
            file_id,
            embedding: one_hot(CLIP_EMBEDDING_DIMENSIONS, file_id as usize)
                .into_iter()
                .map(f64::from)
                .collect(),
            version: 1,
        }
    }

    pub(super) fn clips(file_ids: impl IntoIterator<Item = i64>) -> Vec<ClipEmbedding> {
        file_ids.into_iter().map(clip).collect()
    }

    pub(super) fn centroid(cluster_id: &str, hot: usize) -> (String, ClusterSummary) {
        let values: Vec<f64> = one_hot(Index::ClusterCentroid.dims(), hot)
            .into_iter()
            .map(f64::from)
            .collect();
        let summary = ClusterSummary {
            avg: encode_evector(&values),
            count: 1,
        };
        (cluster_id.to_string(), summary)
    }

    pub(super) fn pet(id: &str, species: Species, hot: usize, dims: usize) -> PetEmbedding {
        PetEmbedding {
            id: id.to_string(),
            species,
            embedding: one_hot(dims, hot),
        }
    }

    pub(super) fn nearest(store: &MlStore, index: Index, query: &[f32]) -> String {
        let params = SearchParams {
            limit: Some(1),
            ..SearchParams::default()
        };
        store.search(index, query, &params).unwrap()[0].key.clone()
    }

    pub(super) fn live_count(store: &MlStore, index: Index) -> usize {
        store.stats(index).unwrap().live_count
    }

    pub(super) fn meta(store: &MlStore, key: &str) -> Option<String> {
        store.db().get_meta(key).unwrap()
    }

    pub(super) fn hot_position(vector: &[f32]) -> Option<usize> {
        vector.iter().position(|value| *value > 0.99)
    }

    pub(super) fn empty(outcome: FillOutcome) -> FillReport {
        FillReport {
            outcome,
            rows: 0,
            indexed: 0,
            skipped: 0,
            resumed: false,
        }
    }

    pub(super) fn lose_index_files(store: &MlStore, path: &Path) {
        store.release().unwrap();
        VecDb::purge(path).unwrap();
    }

    #[test]
    fn open_creates_no_index_files_and_fillable_indexes_start_stale() {
        let (directory, store) = open();
        let names: Vec<String> = fs::read_dir(directory.path())
            .unwrap()
            .map(|entry| entry.unwrap().file_name().to_string_lossy().into_owned())
            .collect();
        assert!(
            names.iter().all(|name| name.starts_with(DB_FILE)),
            "{names:?}"
        );
        for index in Index::ALL {
            assert_eq!(
                VecDb::open_cost(&index_path(&directory, index)),
                OpenCost::Absent
            );
        }
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Stale);
        assert_eq!(
            store.fill_state(Index::ClusterCentroid).unwrap(),
            FillState::Stale
        );
        assert_eq!(
            store.fill_state(Index::PetFace(Species::Dog)).unwrap(),
            FillState::Filled
        );
        assert_eq!(
            store.fill_state(Index::PetBody(Species::Cat)).unwrap(),
            FillState::Filled
        );
    }

    #[test]
    fn release_flushes_and_reopened_stores_keep_data() {
        let (directory, store) = open();
        store.fill_clip_index(false).unwrap();
        store.put_clip(&clips([1, 2])).unwrap();
        store.release().unwrap();
        assert_eq!(
            VecDb::open_cost(&index_path(&directory, Index::Clip)),
            OpenCost::Ready
        );
        assert!(store.contains(Index::Clip, "1").unwrap());
        store.release().unwrap();
        drop(store);

        let reopened = open_in(&directory);
        assert_eq!(reopened.fill_state(Index::Clip).unwrap(), FillState::Filled);
        assert!(reopened.contains(Index::Clip, "2").unwrap());
        assert_eq!(live_count(&reopened, Index::Clip), 2);
    }

    #[test]
    fn getters_reopen_after_another_store_clears_and_repopulates() {
        let (directory, writer) = open();
        let contains_reader = open_in(&directory);
        let vector_reader = open_in(&directory);
        writer.fill_clip_index(false).unwrap();
        writer.put_clip(&clips([1])).unwrap();
        assert!(contains_reader.contains(Index::Clip, "1").unwrap());
        assert!(
            vector_reader
                .get_vector(Index::Clip, "1")
                .unwrap()
                .is_some()
        );

        writer.clear_all().unwrap();
        writer.put_clip(&clips([2])).unwrap();
        writer.fill_clip_index(false).unwrap();

        assert!(contains_reader.contains(Index::Clip, "2").unwrap());
        let vector = vector_reader.get_vector(Index::Clip, "2").unwrap().unwrap();
        assert_eq!(hot_position(&vector), Some(2));
        assert!(!contains_reader.contains(Index::Clip, "1").unwrap());
        assert!(
            vector_reader
                .get_vector(Index::Clip, "1")
                .unwrap()
                .is_none()
        );
    }

    #[test]
    fn ml_store_is_send_and_sync() {
        fn assert_send_sync<T: Send + Sync>() {}
        assert_send_sync::<MlStore>();
    }
}
