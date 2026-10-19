use std::ffi::OsStr;
use std::fs;
use std::io::{self, ErrorKind};
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
    legacy_prefix: PathBuf,
    handle: RwLock<Option<VecDb>>,
}

impl Slot {
    pub(super) fn new(index: Index, db_path: &Path, db_stem: &str) -> Self {
        Self {
            index,
            path: db_path.with_file_name(format!("{db_stem}.vecdb.{}", index.name())),
            legacy_prefix: db_path.with_file_name(format!("{db_stem}.vectordb.{}.", index.name())),
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

    pub(super) fn is_open(&self) -> bool {
        self.read_handle().as_ref().is_some_and(is_live)
    }

    pub(super) fn reopen(&self, db: &MlDb) -> Result<()> {
        let mut handle = self.write_handle();
        if handle.as_ref().is_some_and(is_live) {
            return Ok(());
        }
        *handle = None;
        *handle = Some(self.open(db)?);
        Ok(())
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

    pub(super) fn remove_legacy_files(&self) {
        remove_files_starting_with(&self.legacy_prefix);
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

fn is_live(vecdb: &VecDb) -> bool {
    !vecdb.is_closed()
}

fn unless_closed<T>(outcome: IndexResult<T>) -> Option<Result<T>> {
    match outcome {
        Err(VecDbError::Closed) => None,
        outcome => Some(outcome.map_err(Into::into)),
    }
}

fn remove_files_starting_with(prefix_path: &Path) {
    let Some(prefix) = prefix_path.file_name() else {
        return;
    };
    let directory = scan_directory(prefix_path);
    match fs::read_dir(directory) {
        Ok(entries) => {
            for entry in entries {
                remove_entry_starting_with(directory, prefix, entry);
            }
        }
        Err(error) => warn_unless_not_found(directory, &error),
    }
}

fn scan_directory(prefix_path: &Path) -> &Path {
    match prefix_path.parent() {
        Some(parent) if !parent.as_os_str().is_empty() => parent,
        _ => Path::new("."),
    }
}

fn remove_entry_starting_with(directory: &Path, prefix: &OsStr, entry: io::Result<fs::DirEntry>) {
    let path = match entry {
        Ok(entry) => entry.path(),
        Err(error) => {
            warn_unless_not_found(directory, &error);
            return;
        }
    };
    if !file_name_starts_with(&path, prefix) {
        return;
    }
    if let Err(error) = fs::remove_file(&path) {
        warn_unless_not_found(&path, &error);
    }
}

fn file_name_starts_with(path: &Path, prefix: &OsStr) -> bool {
    path.file_name().is_some_and(|name| {
        name.as_encoded_bytes()
            .starts_with(prefix.as_encoded_bytes())
    })
}

fn warn_unless_not_found(path: &Path, error: &io::Error) {
    if error.kind() != ErrorKind::NotFound {
        log::warn!(
            "{}: could not remove legacy usearch files: {error}",
            path.display()
        );
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;
    use std::fs;
    use std::path::Path;

    use ente_vecdb::{OpenCost, StorageKind, VecDb};

    use super::{Index, scan_directory};
    use crate::db::Connection;
    use crate::ml_db::CLIP_EMBEDDING_DIMENSIONS;
    use crate::ml_store::tests::{
        DB_FILE, all_exist, centroid, clips, create_usearch_files, index_path, live_count,
        lose_index_files, meta, one_hot, open, open_with_unusable_clip_index,
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
        assert!(matches!(
            store.fill_state(Index::Clip),
            Err(Error::Database(_))
        ));
        assert!(foreign.contains("7").unwrap());
        assert_eq!(meta(&store, "clip.fill").as_deref(), Some("filled"));
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
    fn completed_fills_remove_their_legacy_usearch_files() {
        let (directory, store) = open();
        let clip = create_usearch_files(&directory, "ente.ml.vectordb.clip.usearch");
        let centroid =
            create_usearch_files(&directory, "ente.ml.vectordb.cluster_centroid.usearch");
        let offline = create_usearch_files(&directory, "ente.ml.offline.vectordb.clip.usearch");

        assert_eq!(
            store.fill_clip_index(false).unwrap().outcome,
            FillOutcome::Completed
        );
        assert!(clip.iter().all(|path| !path.exists()));
        assert!(all_exist(&centroid));

        assert_eq!(
            store.fill_cluster_centroid_index(false).unwrap().outcome,
            FillOutcome::Completed
        );
        assert!(centroid.iter().all(|path| !path.exists()));
        assert!(all_exist(&offline));
    }

    #[test]
    fn fills_that_do_not_complete_leave_legacy_usearch_files_in_place() {
        let (directory, store) = open_with_unusable_clip_index();
        let clip = create_usearch_files(&directory, "ente.ml.vectordb.clip.usearch");
        assert!(matches!(store.fill_clip_index(false), Err(Error::Index(_))));
        assert!(all_exist(&clip));

        store.fill_cluster_centroid_index(false).unwrap();
        let centroid =
            create_usearch_files(&directory, "ente.ml.vectordb.cluster_centroid.usearch");
        assert_eq!(
            store.fill_cluster_centroid_index(false).unwrap().outcome,
            FillOutcome::AlreadyFilled
        );
        assert!(all_exist(&centroid));
    }

    #[test]
    fn legacy_usearch_removal_failures_do_not_fail_the_fill() {
        let (directory, store) = open();
        let blocker = directory.path().join("ente.ml.vectordb.clip.usearch");
        fs::create_dir(&blocker).unwrap();
        let sibling = directory.path().join("ente.ml.vectordb.clip.tmp.1.2");
        fs::write(&sibling, b"usearch").unwrap();
        assert_eq!(
            store.fill_clip_index(false).unwrap().outcome,
            FillOutcome::Completed
        );
        assert!(blocker.is_dir());
        assert!(!sibling.exists());
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Filled);
    }

    #[test]
    fn legacy_files_are_scanned_beside_the_prefix() {
        assert_eq!(
            scan_directory(Path::new("ente.ml.vectordb.clip.")),
            Path::new(".")
        );
        assert_eq!(
            scan_directory(Path::new("/data/ente.ml.vectordb.clip.")),
            Path::new("/data")
        );
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

    #[test]
    fn fill_state_alone_detects_lost_index_files() {
        let (directory, store) = open();
        store.db().insert_clip_rows(&clips(1..=3)).unwrap();
        store.fill_clip_index(false).unwrap();
        lose_index_files(&store, &index_path(&directory, Index::Clip));
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Stale);
        assert_eq!(meta(&store, "clip.fill"), None);

        store.fill_clip_index(false).unwrap();
        VecDb::purge(&index_path(&directory, Index::Clip)).unwrap();
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Stale);
        assert_eq!(meta(&store, "clip.fill"), None);
        assert_eq!(live_count(&store, Index::Clip), 0);
    }

    #[test]
    fn fill_state_alone_purges_an_unusable_index() {
        let (directory, store) = open();
        store.db().insert_clip_rows(&clips(1..=3)).unwrap();
        store.fill_clip_index(false).unwrap();
        store.release().unwrap();
        corrupt_header(&index_path(&directory, Index::Clip));

        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Stale);
        assert_eq!(meta(&store, "clip.fill"), None);
        assert_eq!(live_count(&store, Index::Clip), 0);
    }

    #[test]
    fn fill_state_keeps_a_live_handle_open() {
        let (_directory, store) = open();
        store.fill_clip_index(false).unwrap();
        store.put_clip(&clips([1, 2])).unwrap();
        let unflushed = store.stats(Index::Clip).unwrap();
        assert_ne!(unflushed.records_since_snapshot, 0);

        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Filled);
        assert_eq!(store.stats(Index::Clip).unwrap(), unflushed);
    }
}
