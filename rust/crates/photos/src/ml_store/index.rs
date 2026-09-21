use std::fs;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::sync::{PoisonError, RwLock, RwLockReadGuard, RwLockWriteGuard};

use ente_vecdb::{VecDb, VecDbError, validate_key};

use super::{Error, IndexResult, Result, state};
use crate::ml_db::{CLIP_EMBEDDING_DIMENSIONS, MlDb};

pub const CLUSTER_CENTROID_DIMENSIONS: usize = 192;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Index {
    Clip,
    ClusterCentroid,
}

impl Index {
    pub const ALL: [Self; 2] = [Self::Clip, Self::ClusterCentroid];

    pub fn dims(self) -> usize {
        match self {
            Self::Clip => CLIP_EMBEDDING_DIMENSIONS,
            Self::ClusterCentroid => CLUSTER_CENTROID_DIMENSIONS,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::Clip => "clip",
            Self::ClusterCentroid => "cluster_centroid",
        }
    }

    pub(super) fn position(self) -> usize {
        match self {
            Self::Clip => 0,
            Self::ClusterCentroid => 1,
        }
    }

    pub(super) fn accepts(self, key: &str, vector: &[f32]) -> bool {
        if let Err(error) = validate_key(key) {
            log::warn!("skipping {} vector {key:?}: {error}", self.name());
            return false;
        }
        if vector.is_empty() {
            return false;
        }
        if vector.len() != self.dims() {
            log::warn!(
                "skipping {} vector {key}: {} values, expected {}",
                self.name(),
                vector.len(),
                self.dims()
            );
            return false;
        }
        if let Some(position) = vector.iter().position(|value| !value.is_finite()) {
            log::warn!(
                "skipping {} vector {key}: non-finite value at {position}",
                self.name()
            );
            return false;
        }
        true
    }
}

pub(super) fn db_stem(db_path: &Path) -> Result<String> {
    db_path
        .file_stem()
        .map(|stem| stem.to_string_lossy().into_owned())
        .ok_or_else(|| Error::InvalidArgument(format!("{} has no file name", db_path.display())))
}

pub(super) struct Slot {
    index: Index,
    path: PathBuf,
    handle: RwLock<Option<VecDb>>,
}

impl Slot {
    pub(super) fn new(index: Index, db_path: &Path, db_stem: &str) -> Self {
        Self {
            index,
            path: db_path.with_file_name(format!("{db_stem}.vecdb.{}", index.name())),
            handle: RwLock::new(None),
        }
    }

    pub(super) fn with_open<T>(
        &self,
        db: &MlDb,
        operation: impl Fn(&VecDb) -> IndexResult<T>,
    ) -> Result<T> {
        if let Some(outcome) = self.with_open_handle(&operation) {
            return outcome;
        }
        let mut handle = self.write_handle();
        *handle = None;
        let vecdb = handle.insert(self.open(db)?);
        operation(vecdb).map_err(Into::into)
    }

    pub(super) fn release(&self) -> Result<()> {
        match self.write_handle().take() {
            Some(vecdb) => vecdb.flush().map_err(Into::into),
            None => Ok(()),
        }
    }

    pub(super) fn purge(&self) -> Result<()> {
        let mut handle = self.write_handle();
        *handle = None;
        VecDb::purge(&self.path).map_err(Into::into)
    }

    pub(super) fn with_open_handle<T>(
        &self,
        operation: &impl Fn(&VecDb) -> IndexResult<T>,
    ) -> Option<Result<T>> {
        self.read_handle()
            .as_ref()
            .and_then(|vecdb| unless_closed(operation(vecdb)))
    }

    fn open(&self, db: &MlDb) -> Result<VecDb> {
        if self.files_are_missing() {
            state::invalidate_lost_index(db, self.index, &self.path)?;
        }
        match VecDb::open(&self.path, self.index.dims(), None) {
            Err(error) if is_unusable(&error) => {
                log::warn!("{}: {error}; purging the index", self.path.display());
                state::mark_stale(db, self.index)?;
                VecDb::purge(&self.path)?;
                VecDb::open(&self.path, self.index.dims(), None).map_err(Into::into)
            }
            opened => opened.map_err(Into::into),
        }
    }

    fn files_are_missing(&self) -> bool {
        matches!(fs::metadata(&self.path), Err(error) if error.kind() == ErrorKind::NotFound)
    }

    fn read_handle(&self) -> RwLockReadGuard<'_, Option<VecDb>> {
        self.handle.read().unwrap_or_else(PoisonError::into_inner)
    }

    fn write_handle(&self) -> RwLockWriteGuard<'_, Option<VecDb>> {
        self.handle.write().unwrap_or_else(PoisonError::into_inner)
    }
}

fn is_unusable(error: &VecDbError) -> bool {
    matches!(
        error,
        VecDbError::Corrupt(_)
            | VecDbError::DimensionMismatch { .. }
            | VecDbError::StorageMismatch { .. }
    )
}

fn unless_closed<T>(outcome: IndexResult<T>) -> Option<Result<T>> {
    match outcome {
        Err(VecDbError::Closed) => None,
        outcome => Some(outcome.map_err(Into::into)),
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;
    use std::fs;
    use std::path::Path;

    use ente_vecdb::{OpenCost, StorageKind, VecDb};

    use super::Index;
    use crate::db::Connection;
    use crate::ml_db::CLIP_EMBEDDING_DIMENSIONS;
    use crate::ml_store::tests::{
        DB_FILE, centroid, clips, index_path, live_count, lose_index_files, meta, one_hot, open,
    };
    use crate::ml_store::{Error, FillOutcome, FillReport, FillState, MlStore};

    #[test]
    fn index_positions_follow_the_all_order() {
        for (position, index) in Index::ALL.into_iter().enumerate() {
            assert_eq!(index.position(), position, "{}", index.name());
        }
    }

    #[test]
    fn index_files_are_named_after_the_database_stem() {
        let directory = tempfile::tempdir().unwrap();
        let store = MlStore::open(directory.path().join("ente.ml.offline.db")).unwrap();
        store.fill_clip_index(false).unwrap();
        assert_eq!(
            VecDb::open_cost(&directory.path().join("ente.ml.offline.vecdb.clip")),
            OpenCost::Ready
        );
        assert!(matches!(
            MlStore::open(directory.path().join("..")),
            Err(Error::InvalidArgument(_))
        ));
    }

    #[test]
    fn mismatched_index_header_is_purged_and_marked_stale() {
        let (directory, store) = open();
        store.fill_clip_index(false).unwrap();
        store.release().unwrap();
        let path = index_path(&directory, Index::Clip);
        VecDb::purge(&path).unwrap();
        let foreign =
            VecDb::open(&path, CLIP_EMBEDDING_DIMENSIONS, Some(StorageKind::F32)).unwrap();
        foreign
            .add("7", &one_hot(CLIP_EMBEDDING_DIMENSIONS, 7))
            .unwrap();
        foreign.flush().unwrap();
        drop(foreign);

        assert!(!store.contains(Index::Clip, "7").unwrap());
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Stale);
        assert_eq!(store.stats(Index::Clip).unwrap().storage, StorageKind::I8);
        assert_eq!(live_count(&store, Index::Clip), 0);
    }

    fn corrupt_header(path: &Path) {
        let mut bytes = fs::read(path).unwrap();
        for byte in &mut bytes[..4] {
            *byte ^= 0xFF;
        }
        fs::write(path, bytes).unwrap();
    }

    fn corrupt_log_body(path: &Path) {
        let mut bytes = fs::read(path).unwrap();
        let middle = bytes.len() / 2;
        for byte in &mut bytes[middle..middle + 64] {
            *byte ^= 0x5A;
        }
        fs::write(path, bytes).unwrap();
    }

    #[test]
    fn corrupt_index_files_are_purged_and_marked_stale() {
        let corruptions: [fn(&Path); 2] = [corrupt_header, corrupt_log_body];
        for corrupt in corruptions {
            let (directory, store) = open();
            store.db().insert_clip_rows(&clips(1..=50)).unwrap();
            store.fill_clip_index(false).unwrap();
            store.release().unwrap();
            corrupt(&index_path(&directory, Index::Clip));

            assert!(!store.contains(Index::Clip, "1").unwrap());
            assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Stale);
            assert_eq!(store.fill_clip_index(false).unwrap().indexed, 50);
            assert!(store.contains(Index::Clip, "1").unwrap());
            assert_eq!(live_count(&store, Index::Clip), 50);
        }
    }

    #[test]
    fn keys_vecdb_rejects_are_skipped_like_malformed_vectors() {
        let (_directory, store) = open();
        store.fill_cluster_centroid_index(false).unwrap();
        let long_id = "k".repeat(257);
        store
            .cluster_summary_update(&HashMap::from([
                centroid("", 1),
                centroid(&long_id, 2),
                centroid("c3", 3),
            ]))
            .unwrap();
        assert_eq!(store.db().count_cluster_summaries().unwrap(), 3);
        assert_eq!(live_count(&store, Index::ClusterCentroid), 1);
        assert!(store.contains(Index::ClusterCentroid, "c3").unwrap());
        assert_eq!(
            store.fill_cluster_centroid_index(true).unwrap(),
            FillReport {
                outcome: FillOutcome::Completed,
                rows: 3,
                indexed: 1,
                skipped: 2,
                resumed: false
            }
        );
        assert_eq!(live_count(&store, Index::ClusterCentroid), 1);
    }

    #[test]
    fn failed_invalidation_preserves_the_mismatched_index() {
        let (directory, store) = open();
        store.fill_clip_index(false).unwrap();
        store.release().unwrap();
        let path = index_path(&directory, Index::Clip);
        VecDb::purge(&path).unwrap();
        let foreign =
            VecDb::open(&path, CLIP_EMBEDDING_DIMENSIONS, Some(StorageKind::F32)).unwrap();
        foreign
            .add("7", &one_hot(CLIP_EMBEDDING_DIMENSIONS, 7))
            .unwrap();
        let connection = Connection::open(directory.path().join(DB_FILE)).unwrap();
        connection
            .execute_batch(
                "CREATE TRIGGER deny_meta_deletion BEFORE DELETE ON ml_store_meta
                 BEGIN SELECT RAISE(FAIL, 'metadata unavailable'); END;",
            )
            .unwrap();

        assert!(matches!(
            store.contains(Index::Clip, "7"),
            Err(Error::Database(_))
        ));
        assert!(foreign.contains("7").unwrap());
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Filled);
    }

    #[test]
    fn purged_handles_are_reopened_transparently() {
        let (directory, store) = open();
        store.fill_clip_index(false).unwrap();
        store.put_clip(&clips([1])).unwrap();
        VecDb::purge(&index_path(&directory, Index::Clip)).unwrap();
        assert!(!store.contains(Index::Clip, "1").unwrap());
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Stale);
        store.fill_clip_index(false).unwrap();
        store.put_clip(&clips([2])).unwrap();
        assert!(store.contains(Index::Clip, "1").unwrap());
        assert!(store.contains(Index::Clip, "2").unwrap());
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Filled);
    }

    #[test]
    fn lost_index_files_are_detected_by_reads() {
        let (directory, store) = open();
        store.db().insert_clip_rows(&clips(1..=3)).unwrap();
        store.fill_clip_index(false).unwrap();
        lose_index_files(&store, &index_path(&directory, Index::Clip));

        assert!(!store.contains(Index::Clip, "1").unwrap());
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Stale);
        assert_eq!(meta(&store, "clip.fill"), None);
        let report = store.fill_clip_index(false).unwrap();
        assert_eq!(report.outcome, FillOutcome::Completed);
        assert_eq!(report.indexed, 3);
        assert!(store.contains(Index::Clip, "1").unwrap());
        assert_eq!(live_count(&store, Index::Clip), 3);
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Filled);
    }
}
