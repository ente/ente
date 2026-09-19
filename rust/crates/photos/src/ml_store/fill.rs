use std::num::NonZeroUsize;

use ente_vecdb::VecDb;

use super::{FillState, Index, MlStore, Result, state};
use crate::ml_db::MlDb;
use crate::ml_db::vector_encoding::{decode_evector, decode_f32};

const FILL_PAGE: NonZeroUsize = NonZeroUsize::new(1000).unwrap();

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FillOutcome {
    Completed,
    AlreadyFilled,
    Superseded,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct FillReport {
    pub outcome: FillOutcome,
    pub rows: usize,
    pub indexed: usize,
    pub skipped: usize,
    pub resumed: bool,
}

struct FillRow {
    key: String,
    blob: Vec<u8>,
}

trait FillSource {
    const INDEX: Index;

    fn read_page(db: &MlDb, after: Option<&str>, limit: NonZeroUsize) -> Result<Vec<FillRow>>;

    fn decode(key: &str, blob: &[u8]) -> Option<Vec<f32>>;

    #[cfg(test)]
    fn after_page(_store: &MlStore) {}
}

struct ClipSource;

impl FillSource for ClipSource {
    const INDEX: Index = Index::Clip;

    fn read_page(db: &MlDb, after: Option<&str>, limit: NonZeroUsize) -> Result<Vec<FillRow>> {
        let rows = db.get_clip_rows_before(clip_cursor(after), limit)?;
        Ok(rows
            .into_iter()
            .map(|row| FillRow {
                key: row.file_id.to_string(),
                blob: row.embedding,
            })
            .collect())
    }

    fn decode(key: &str, blob: &[u8]) -> Option<Vec<f32>> {
        let vector = decode_f32(blob);
        Index::Clip.accepts(key, &vector).then_some(vector)
    }
}

fn clip_cursor(after: Option<&str>) -> Option<i64> {
    let cursor = after?;
    let file_id = cursor.parse().ok();
    if file_id.is_none() {
        log::warn!("ignoring malformed clip fill cursor {cursor:?}");
    }
    file_id
}

struct ClusterCentroidSource;

impl FillSource for ClusterCentroidSource {
    const INDEX: Index = Index::ClusterCentroid;

    fn read_page(db: &MlDb, after: Option<&str>, limit: NonZeroUsize) -> Result<Vec<FillRow>> {
        let rows = db.get_cluster_summary_page(after, limit.get() as i64)?;
        Ok(rows
            .into_iter()
            .map(|row| FillRow {
                key: row.cluster_id,
                blob: row.avg,
            })
            .collect())
    }

    fn decode(key: &str, blob: &[u8]) -> Option<Vec<f32>> {
        decode_centroid(key, blob)
    }
}

pub(super) fn decode_centroid(cluster_id: &str, avg: &[u8]) -> Option<Vec<f32>> {
    match decode_evector(avg) {
        Ok(values) => {
            let vector: Vec<f32> = values.into_iter().map(|value| value as f32).collect();
            Index::ClusterCentroid
                .accepts(cluster_id, &vector)
                .then_some(vector)
        }
        Err(error) => {
            log::warn!("skipping cluster summary {cluster_id}: {error}");
            None
        }
    }
}

enum Start {
    Skip,
    Fresh,
    Resume { cursor: Option<String> },
}

impl MlStore {
    pub fn fill_clip_index(&self, force: bool) -> Result<FillReport> {
        self.fill::<ClipSource>(force)
    }

    pub fn fill_cluster_centroid_index(&self, force: bool) -> Result<FillReport> {
        self.fill::<ClusterCentroidSource>(force)
    }

    fn fill<S: FillSource>(&self, force: bool) -> Result<FillReport> {
        let _fill = self.lock_fill(S::INDEX);
        let mut report = FillReport {
            outcome: FillOutcome::AlreadyFilled,
            rows: 0,
            indexed: 0,
            skipped: 0,
            resumed: false,
        };
        let mut cursor = match self.start_fill(S::INDEX, force)? {
            Start::Skip => return Ok(report),
            Start::Fresh => None,
            Start::Resume { cursor } => {
                report.resumed = true;
                cursor
            }
        };
        loop {
            let _mutations = self.lock_mutations();
            if state::read(&self.db, S::INDEX)? != FillState::Filling {
                report.outcome = FillOutcome::Superseded;
                return Ok(report);
            }
            let page = S::read_page(&self.db, cursor.as_deref(), FILL_PAGE)?;
            let Some(last_key) = page.last().map(|row| row.key.clone()) else {
                report.outcome = self.finish_fill(S::INDEX)?;
                return Ok(report);
            };
            self.index_page::<S>(page, &mut report)?;
            state::set_cursor(&self.db, S::INDEX, &last_key)?;
            cursor = Some(last_key);
            drop(_mutations);
            #[cfg(test)]
            S::after_page(self);
        }
    }

    fn start_fill(&self, index: Index, force: bool) -> Result<Start> {
        let _mutations = self.lock_mutations();
        self.with_index(index, |_| Ok(()))?;
        match (force, state::read(&self.db, index)?) {
            (false, FillState::Filled) => Ok(Start::Skip),
            (false, FillState::Filling) => Ok(Start::Resume {
                cursor: state::cursor(&self.db, index)?,
            }),
            (true, _) | (false, FillState::Stale) => {
                state::mark_stale(&self.db, index)?;
                self.with_index(index, VecDb::reset)?;
                state::mark_filling(&self.db, index)?;
                Ok(Start::Fresh)
            }
        }
    }

    fn index_page<S: FillSource>(&self, page: Vec<FillRow>, report: &mut FillReport) -> Result<()> {
        report.rows += page.len();
        let mut keys = Vec::with_capacity(page.len());
        let mut vectors = Vec::with_capacity(page.len());
        for row in page {
            match S::decode(&row.key, &row.blob) {
                Some(vector) => {
                    keys.push(row.key);
                    vectors.push(vector);
                }
                None => report.skipped += 1,
            }
        }
        self.with_index(S::INDEX, |vecdb| vecdb.bulk_add(&keys, &vectors))?;
        report.indexed += keys.len();
        Ok(())
    }

    fn finish_fill(&self, index: Index) -> Result<FillOutcome> {
        self.with_index(index, VecDb::flush)?;
        if state::read(&self.db, index)? != FillState::Filling {
            return Ok(FillOutcome::Superseded);
        }
        state::mark_filled(&self.db, index)?;
        Ok(FillOutcome::Completed)
    }
}

#[cfg(test)]
mod tests {
    use std::cell::RefCell;
    use std::collections::HashMap;
    use std::num::NonZeroUsize;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::{TryLockError, mpsc};
    use std::thread;

    use tempfile::TempDir;

    use super::{ClipSource, FillOutcome, FillReport, FillRow, FillSource};
    use crate::ml_db::{ClipEmbedding, ClusterSummary, MlDb};
    use crate::ml_store::tests::{
        centroid, clips, empty, hot_position, index_path, live_count, lose_index_files, meta,
        nearest, one_hot, open, open_in, open_with_unusable_clip_index,
    };
    use crate::ml_store::{Error, FillState, Index, MlStore, Result};

    #[test]
    fn fill_spans_pages_reports_skips_and_repeats_as_noop() {
        let (_directory, store) = open();
        let mut rows = clips(1..=2500);
        rows.push(ClipEmbedding {
            file_id: 2501,
            embedding: vec![1.0, 2.0],
            version: 1,
        });
        rows.push(ClipEmbedding {
            file_id: 2502,
            embedding: vec![],
            version: 1,
        });
        store.db().insert_clip_rows(&rows).unwrap();

        let report = store.fill_clip_index(false).unwrap();
        assert_eq!(
            report,
            FillReport {
                outcome: FillOutcome::Completed,
                rows: 2502,
                indexed: 2500,
                skipped: 2,
                resumed: false
            }
        );
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Filled);
        assert_eq!(meta(&store, "clip.fill").as_deref(), Some("filled"));
        assert_eq!(meta(&store, "clip.cursor"), None);
        assert_eq!(live_count(&store, Index::Clip), 2500);
        assert!(store.contains(Index::Clip, "1").unwrap());
        assert!(store.contains(Index::Clip, "2500").unwrap());
        assert!(!store.contains(Index::Clip, "2501").unwrap());
        assert!(!store.contains(Index::Clip, "2502").unwrap());
        assert_eq!(
            store.fill_clip_index(false).unwrap(),
            empty(FillOutcome::AlreadyFilled)
        );
        assert_eq!(live_count(&store, Index::Clip), 2500);
    }

    #[test]
    fn interrupted_fill_resumes_after_the_cursor() {
        let (_directory, store) = open();
        store.fill_clip_index(false).unwrap();
        store.release().unwrap();
        store.db().insert_clip_rows(&clips(1..=2500)).unwrap();
        store.db().set_meta("clip.fill", "filling").unwrap();
        store.db().set_meta("clip.cursor", "1500").unwrap();
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Filling);

        let report = store.fill_clip_index(false).unwrap();
        assert_eq!(
            report,
            FillReport {
                outcome: FillOutcome::Completed,
                rows: 1499,
                indexed: 1499,
                skipped: 0,
                resumed: true
            }
        );
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Filled);
        assert_eq!(meta(&store, "clip.cursor"), None);
        assert!(store.contains(Index::Clip, "1").unwrap());
        assert!(store.contains(Index::Clip, "1499").unwrap());
        assert!(!store.contains(Index::Clip, "1500").unwrap());
        assert!(!store.contains(Index::Clip, "2500").unwrap());
        assert_eq!(live_count(&store, Index::Clip), 1499);
    }

    #[test]
    fn forced_fill_resets_the_index() {
        let (_directory, store) = open();
        store.fill_clip_index(false).unwrap();
        store.put_clip(&clips([1, 2, 3])).unwrap();
        store.db().delete_clip_rows(&[2]).unwrap();
        assert_eq!(
            store.fill_clip_index(false).unwrap(),
            empty(FillOutcome::AlreadyFilled)
        );
        assert!(store.contains(Index::Clip, "2").unwrap());

        let report = store.fill_clip_index(true).unwrap();
        assert_eq!(
            report,
            FillReport {
                outcome: FillOutcome::Completed,
                rows: 2,
                indexed: 2,
                skipped: 0,
                resumed: false
            }
        );
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Filled);
        assert!(!store.contains(Index::Clip, "2").unwrap());
        assert!(store.contains(Index::Clip, "3").unwrap());
        assert_eq!(live_count(&store, Index::Clip), 2);
    }

    #[test]
    fn centroid_fill_decodes_evectors_and_skips_malformed_rows() {
        let (_directory, store) = open();
        let mut summaries = HashMap::from([centroid("c1", 1), centroid("c2", 2)]);
        summaries.insert(
            "c3".to_string(),
            ClusterSummary {
                avg: vec![0x0A, 0x10, 0x00],
                count: 1,
            },
        );
        store.db().upsert_cluster_summary_rows(&summaries).unwrap();

        let report = store.fill_cluster_centroid_index(false).unwrap();
        assert_eq!(
            report,
            FillReport {
                outcome: FillOutcome::Completed,
                rows: 3,
                indexed: 2,
                skipped: 1,
                resumed: false
            }
        );
        assert_eq!(
            store.fill_state(Index::ClusterCentroid).unwrap(),
            FillState::Filled
        );
        assert_eq!(
            nearest(
                &store,
                Index::ClusterCentroid,
                &one_hot(Index::ClusterCentroid.dims(), 2)
            ),
            "c2"
        );
        assert!(!store.contains(Index::ClusterCentroid, "c3").unwrap());
        let stored = store
            .get_vector(Index::ClusterCentroid, "c1")
            .unwrap()
            .unwrap();
        assert_eq!(hot_position(&stored), Some(1));
    }

    #[test]
    fn non_finite_clip_rows_are_skipped_by_the_fill() {
        let (_directory, store) = open();
        let mut rows = clips([1, 2]);
        rows[1].embedding[0] = f64::NAN;
        store.db().insert_clip_rows(&rows).unwrap();

        let report = store.fill_clip_index(false).unwrap();
        assert_eq!(
            report,
            FillReport {
                outcome: FillOutcome::Completed,
                rows: 2,
                indexed: 1,
                skipped: 1,
                resumed: false
            }
        );
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Filled);
        assert!(store.contains(Index::Clip, "1").unwrap());
        assert!(!store.contains(Index::Clip, "2").unwrap());
        assert_eq!(live_count(&store, Index::Clip), 1);
    }

    #[test]
    fn lost_index_files_refill_on_a_non_forced_fill() {
        let (directory, store) = open();
        store.db().insert_clip_rows(&clips(1..=1500)).unwrap();
        store.fill_clip_index(false).unwrap();
        lose_index_files(&store, &index_path(&directory, Index::Clip));

        let report = store.fill_clip_index(false).unwrap();
        assert_eq!(
            report,
            FillReport {
                outcome: FillOutcome::Completed,
                rows: 1500,
                indexed: 1500,
                skipped: 0,
                resumed: false
            }
        );
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Filled);
        assert_eq!(live_count(&store, Index::Clip), 1500);
        assert!(store.contains(Index::Clip, "1").unwrap());
        assert!(store.contains(Index::Clip, "1500").unwrap());
    }

    #[test]
    fn failed_fill_keeps_the_filling_state_and_cursor() {
        let (_directory, store) = open_with_unusable_clip_index();
        store.db().insert_clip_rows(&clips(1..=5)).unwrap();
        store.db().set_meta("clip.fill", "filling").unwrap();
        store.db().set_meta("clip.cursor", "3").unwrap();
        assert!(matches!(store.fill_clip_index(false), Err(Error::Index(_))));
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Filling);
        assert_eq!(meta(&store, "clip.cursor").as_deref(), Some("3"));
    }

    struct SupersedingClipSource;

    impl FillSource for SupersedingClipSource {
        const INDEX: Index = Index::Clip;

        fn read_page(db: &MlDb, after: Option<&str>, limit: NonZeroUsize) -> Result<Vec<FillRow>> {
            if SUPERSEDING_READS.fetch_add(1, Ordering::SeqCst) == 1 {
                db.delete_meta("clip.fill")?;
            }
            ClipSource::read_page(db, after, limit)
        }

        fn decode(key: &str, blob: &[u8]) -> Option<Vec<f32>> {
            ClipSource::decode(key, blob)
        }
    }

    static SUPERSEDING_READS: AtomicUsize = AtomicUsize::new(0);

    #[test]
    fn fill_stops_as_superseded_when_the_state_changes_between_pages() {
        let (_directory, store) = open();
        store.db().insert_clip_rows(&clips(1..=2502)).unwrap();

        let report = store.fill::<SupersedingClipSource>(false).unwrap();
        assert_eq!(
            report,
            FillReport {
                outcome: FillOutcome::Superseded,
                rows: 2000,
                indexed: 2000,
                skipped: 0,
                resumed: false
            }
        );
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Stale);
        assert_eq!(meta(&store, "clip.fill"), None);
        assert_eq!(meta(&store, "clip.cursor").as_deref(), Some("503"));
        assert_eq!(live_count(&store, Index::Clip), 2000);
        assert!(store.contains(Index::Clip, "2502").unwrap());
        assert!(store.contains(Index::Clip, "503").unwrap());
        assert!(!store.contains(Index::Clip, "502").unwrap());
        assert!(!store.contains(Index::Clip, "1").unwrap());
    }

    #[test]
    fn concurrent_deletes_interleave_with_fill_pages() {
        let (_directory, store) = open();
        store.db().insert_clip_rows(&clips(1..=3000)).unwrap();
        let deleted = [5, 1500, 2999];
        thread::scope(|scope| {
            scope.spawn(|| store.fill_clip_index(false).unwrap());
            scope.spawn(|| store.delete_clip(&deleted).unwrap());
        });
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Filled);
        assert_eq!(store.db().count_clip_rows().unwrap(), 2997);
        assert_eq!(live_count(&store, Index::Clip), 2997);
        for file_id in deleted {
            assert!(!store.contains(Index::Clip, &file_id.to_string()).unwrap());
        }
        assert!(store.contains(Index::Clip, "1").unwrap());
        assert!(store.contains(Index::Clip, "3000").unwrap());
    }

    type PageHook = Option<Box<dyn FnMut(&MlStore)>>;

    thread_local! {
        static PAGE_HOOK: RefCell<PageHook> = const { RefCell::new(None) };
    }

    struct HookedClipSource;

    impl FillSource for HookedClipSource {
        const INDEX: Index = Index::Clip;

        fn read_page(db: &MlDb, after: Option<&str>, limit: NonZeroUsize) -> Result<Vec<FillRow>> {
            ClipSource::read_page(db, after, limit)
        }

        fn decode(key: &str, blob: &[u8]) -> Option<Vec<f32>> {
            ClipSource::decode(key, blob)
        }

        fn after_page(store: &MlStore) {
            PAGE_HOOK.with_borrow_mut(|hook| hook.as_mut().unwrap()(store));
        }
    }

    fn fill_losing_the_index_after_page(
        store: &MlStore,
        directory: &TempDir,
        page: usize,
    ) -> FillReport {
        let path = index_path(directory, Index::Clip);
        let mut pages = 0;
        PAGE_HOOK.set(Some(Box::new(move |store: &MlStore| {
            pages += 1;
            if pages == page {
                lose_index_files(store, &path);
            }
        })));
        let report = store.fill::<HookedClipSource>(false);
        PAGE_HOOK.take();
        report.unwrap()
    }

    #[test]
    fn fill_stops_when_its_index_is_lost_between_pages() {
        let (directory, store) = open();
        store.db().insert_clip_rows(&clips(1..=3500)).unwrap();

        let report = fill_losing_the_index_after_page(&store, &directory, 2);
        assert_eq!(report.outcome, FillOutcome::Superseded);
        assert_eq!(report.rows, 3000);
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Stale);
        assert_eq!(meta(&store, "clip.fill"), None);

        let report = store.fill_clip_index(false).unwrap();
        assert_eq!(
            report,
            FillReport {
                outcome: FillOutcome::Completed,
                rows: 3500,
                indexed: 3500,
                skipped: 0,
                resumed: false
            }
        );
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Filled);
        assert_eq!(live_count(&store, Index::Clip), 3500);
        assert!(store.contains(Index::Clip, "1").unwrap());
        assert!(store.contains(Index::Clip, "3500").unwrap());
    }

    #[test]
    fn fill_stops_when_its_index_is_lost_before_the_finishing_flush() {
        let (directory, store) = open();
        store.db().insert_clip_rows(&clips(1..=2500)).unwrap();

        let report = fill_losing_the_index_after_page(&store, &directory, 3);
        assert_eq!(report.outcome, FillOutcome::Superseded);
        assert_eq!(report.rows, 2500);
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Stale);
        assert_eq!(meta(&store, "clip.fill"), None);
        assert_eq!(live_count(&store, Index::Clip), 0);
    }

    #[test]
    fn forced_fill_waits_between_pages_while_mutations_continue() {
        let (directory, store) = open();
        let peer = open_in(&directory);
        store.put_clip(&clips(1..=5000)).unwrap();
        let (paused_tx, paused_rx) = mpsc::channel();
        let (resume_tx, resume_rx) = mpsc::channel();
        let (blocked_tx, blocked_rx) = mpsc::channel();

        let (first, forced, centroid, blocked) = thread::scope(|scope| {
            let first = scope.spawn(|| {
                let mut pages = 0;
                PAGE_HOOK.set(Some(Box::new(move |_: &MlStore| {
                    pages += 1;
                    if pages == 3 {
                        paused_tx.send(()).unwrap();
                        resume_rx.recv().unwrap();
                    }
                })));
                store.fill::<HookedClipSource>(false).unwrap()
            });
            paused_rx.recv().unwrap();
            let forced = scope.spawn(|| {
                let blocked = matches!(
                    peer.locks.fills[Index::Clip.position()].try_lock(),
                    Err(TryLockError::WouldBlock)
                );
                blocked_tx.send(blocked).unwrap();
                peer.fill_clip_index(true).unwrap()
            });
            let blocked = blocked_rx.recv().unwrap();
            let mutation = peer
                .delete_clip(&[2500])
                .and_then(|()| peer.put_clip(&clips([6000])));
            let centroid = peer.fill_cluster_centroid_index(false);
            resume_tx.send(()).unwrap();
            mutation.unwrap();
            (
                first.join().unwrap(),
                forced.join().unwrap(),
                centroid.unwrap(),
                blocked,
            )
        });

        assert!(blocked);
        assert_eq!(first.outcome, FillOutcome::Completed);
        assert_eq!(first.indexed, 5000);
        assert_eq!(forced.outcome, FillOutcome::Completed);
        assert_eq!(forced.indexed, 5000);
        assert_eq!(centroid.outcome, FillOutcome::Completed);
        assert_eq!(store.db().count_clip_rows().unwrap(), 5000);
        assert_eq!(live_count(&store, Index::Clip), 5000);
        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Filled);
        assert!(store.contains(Index::Clip, "6000").unwrap());
        assert!(!store.contains(Index::Clip, "2500").unwrap());
    }
}
