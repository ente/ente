mod cache;
mod chapters;
mod input;
mod library;
mod report;
mod state;

use std::fs;
use std::path::Path;

pub use input::{RewindFile, RewindFileType, RewindRequest};
pub use report::{RewindReport, Totals};
pub use state::{REWIND_VERSION, RewindState, RewindStatus};

use library::Library;

use crate::ml_store::MlStore;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Database(#[from] crate::ml_db::Error),
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error(transparent)]
    Json(#[from] serde_json::Error),
    #[error("year {0} is not supported")]
    UnsupportedYear(i32),
}

pub type Result<T> = std::result::Result<T, Error>;

pub fn compute_rewind(request: &RewindRequest, store: Option<&MlStore>) -> Result<RewindState> {
    let library = Library::of_year(request)?;
    let ml_coverage = store.map(|store| library.ml_coverage(store)).transpose()?;
    Ok(RewindState::evaluate(request, &library, ml_coverage))
}

pub fn refresh_rewind(
    request: &RewindRequest,
    store: Option<&MlStore>,
    cache_directory: &Path,
) -> Result<RewindState> {
    let clear_count_before = cache::clear_count(cache_directory);
    if let Some(state) =
        cache::read_final(cache_directory, request.year, request.local_gallery_mode)
    {
        return Ok(state);
    }
    let state = compute_rewind(request, store)?;
    cache::publish(cache_directory, state, clear_count_before)
}

pub fn load_rewind(
    cache_directory: &Path,
    year: i32,
    local_gallery_mode: bool,
) -> Option<RewindState> {
    cache::read(cache_directory, year, local_gallery_mode)
}

pub fn clear_rewind(cache_directory: &Path) -> Result<()> {
    cache::clear(cache_directory)
}

pub fn export_rewind_request(request: &RewindRequest, path: &Path) -> Result<()> {
    fs::write(path, serde_json::to_vec_pretty(request)?)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::fs;

    use ente_exif::DateTime;
    use tempfile::TempDir;

    use super::{
        REWIND_VERSION, RewindFile, RewindFileType, RewindReport, RewindRequest, RewindState,
        RewindStatus, Totals, cache, clear_rewind, compute_rewind, load_rewind, refresh_rewind,
    };
    use crate::ml_db::{
        CLIP_EMBEDDING_DIMENSIONS, CLIP_ML_VERSION, ClipEmbedding, FACE_ML_VERSION, FaceRow,
    };
    use crate::ml_store::{CLUSTER_CENTROID_DIMENSIONS, MlStore};

    const BEFORE_NEW_YEAR: &str = "2026-12-20T10:00:00";
    const AFTER_NEW_YEAR: &str = "2027-01-02T10:00:00";

    fn micros(date_time: &str) -> i64 {
        DateTime::parse(&format!("{date_time}Z"))
            .and_then(DateTime::unix_micros)
            .unwrap()
    }

    fn file(id: i64, date_time: &str) -> RewindFile {
        RewindFile {
            id,
            creation_time: micros(date_time),
            local_date_time: None,
            utc_offset_seconds: 0,
            file_type: RewindFileType::Image,
        }
    }

    fn photos(count: i64) -> Vec<RewindFile> {
        (1..=count)
            .map(|id| file(id, "2026-06-01T12:00:00"))
            .collect()
    }

    fn request(now: &str, files: Vec<RewindFile>) -> RewindRequest {
        RewindRequest {
            year: 2026,
            now: micros(now),
            utc_offset_seconds: 0,
            season_start: micros("2026-12-05T00:00:00"),
            installed_at: micros("2024-03-01T00:00:00"),
            local_gallery_mode: false,
            files,
        }
    }

    fn indexed_store(file_ids: impl IntoIterator<Item = i64>) -> (TempDir, MlStore) {
        let directory = tempfile::tempdir().unwrap();
        let store = MlStore::open(directory.path().join("ente.ml.db")).unwrap();
        for file_id in file_ids {
            store
                .db()
                .bulk_insert_faces(&[FaceRow {
                    file_id,
                    face_id: format!("{file_id}_face"),
                    detection_json: "{}".to_string(),
                    embedding: vec![0.1; CLUSTER_CENTROID_DIMENSIONS],
                    score: 0.9,
                    blur: 300.0,
                    is_sideways: false,
                    image_height: 100,
                    image_width: 100,
                    ml_version: FACE_ML_VERSION,
                }])
                .unwrap();
            store
                .put_clip(&[ClipEmbedding {
                    file_id,
                    embedding: vec![0.5; CLIP_EMBEDDING_DIMENSIONS],
                    version: CLIP_ML_VERSION,
                }])
                .unwrap();
        }
        (directory, store)
    }

    fn totals(state: &RewindState) -> Option<Totals> {
        match &state.status {
            RewindStatus::Ready { report } => report.totals,
            RewindStatus::WaitingForMl => None,
        }
    }

    #[test]
    fn the_year_follows_each_photos_own_wall_clock() {
        let mut new_years_day_in_tokyo = file(1, "2026-12-31T16:00:00");
        new_years_day_in_tokyo.local_date_time = Some("2027-01-01T01:00:00.000".to_string());
        let mut new_years_day_by_offset = file(2, "2025-12-31T23:30:00");
        new_years_day_by_offset.utc_offset_seconds = 3600;
        let mut last_evening_in_new_york = file(3, "2027-01-01T03:00:00");
        last_evening_in_new_york.local_date_time = Some("2026-12-31T22:00:00-05:00".to_string());
        let files = vec![
            new_years_day_in_tokyo,
            new_years_day_by_offset,
            last_evening_in_new_york,
            file(4, "2025-12-31T23:59:59"),
            file(5, "2027-01-01T00:00:00"),
        ];

        let state = compute_rewind(&request(BEFORE_NEW_YEAR, files), None).unwrap();

        assert_eq!(totals(&state), Some(Totals { files: 2 }));
    }

    #[test]
    fn without_ml_the_rewind_is_ready_and_freezes_once_the_year_has_ended() {
        let before = compute_rewind(&request(BEFORE_NEW_YEAR, photos(3)), None).unwrap();
        assert_eq!(totals(&before), Some(Totals { files: 3 }));
        assert_eq!(before.ml_coverage, None);
        assert!(!before.is_final);

        let mut late_in_new_york = request("2027-01-01T04:00:00", photos(3));
        late_in_new_york.utc_offset_seconds = -5 * 3600;
        assert!(!compute_rewind(&late_in_new_york, None).unwrap().is_final);

        let after = compute_rewind(&request(AFTER_NEW_YEAR, photos(3)), None).unwrap();
        assert!(after.is_final);
    }

    #[test]
    fn with_ml_the_rewind_waits_until_ninety_percent_of_the_year_is_indexed() {
        let mut files = photos(10);
        let mut document = file(11, "2026-06-01T12:00:00");
        document.file_type = RewindFileType::Other;
        files.push(document);
        files.push(file(12, "2025-06-01T12:00:00"));

        let (_directory, store) = indexed_store(1..=8);
        let waiting =
            compute_rewind(&request(BEFORE_NEW_YEAR, files.clone()), Some(&store)).unwrap();
        assert_eq!(waiting.status, RewindStatus::WaitingForMl);
        assert_eq!(waiting.ml_coverage, Some(0.8));
        assert!(!waiting.is_final);

        let (_directory, store) = indexed_store(1..=9);
        let ready = compute_rewind(&request(BEFORE_NEW_YEAR, files.clone()), Some(&store)).unwrap();
        assert_eq!(totals(&ready), Some(Totals { files: 11 }));
        assert_eq!(ready.ml_coverage, Some(0.9));
        assert!(!ready.is_final);

        let frozen = compute_rewind(&request(AFTER_NEW_YEAR, files), Some(&store)).unwrap();
        assert!(frozen.is_final);
    }

    #[test]
    fn after_new_year_unfinished_indexing_shows_the_rewind_unless_installed_this_season() {
        let (_directory, store) = indexed_store(1..=5);

        let fallback = compute_rewind(&request(AFTER_NEW_YEAR, photos(10)), Some(&store)).unwrap();
        assert_eq!(totals(&fallback), Some(Totals { files: 10 }));
        assert_eq!(fallback.ml_coverage, Some(0.5));
        assert!(!fallback.is_final);

        let mut new_install = request(AFTER_NEW_YEAR, photos(10));
        new_install.installed_at = new_install.season_start;
        let waiting = compute_rewind(&new_install, Some(&store)).unwrap();
        assert_eq!(waiting.status, RewindStatus::WaitingForMl);
        assert!(!waiting.is_final);
    }

    #[test]
    fn a_year_without_photos_has_no_totals() {
        let (_directory, store) = indexed_store([]);
        let state = compute_rewind(&request(BEFORE_NEW_YEAR, Vec::new()), Some(&store)).unwrap();
        assert_eq!(state.ml_coverage, Some(1.0));
        assert_eq!(
            state.status,
            RewindStatus::Ready {
                report: RewindReport { totals: None },
            }
        );
    }

    #[test]
    fn the_cache_keeps_the_latest_state_until_it_is_final() {
        let directory = tempfile::tempdir().unwrap();
        let cache = directory.path().join("rewind");

        let first = refresh_rewind(&request(BEFORE_NEW_YEAR, photos(2)), None, &cache).unwrap();
        assert_eq!(load_rewind(&cache, 2026, false), Some(first));

        let second = refresh_rewind(&request(BEFORE_NEW_YEAR, photos(3)), None, &cache).unwrap();
        assert_eq!(totals(&second), Some(Totals { files: 3 }));
        assert_eq!(load_rewind(&cache, 2026, false), Some(second));

        let frozen = refresh_rewind(&request(AFTER_NEW_YEAR, photos(4)), None, &cache).unwrap();
        assert!(frozen.is_final);
        let later =
            refresh_rewind(&request("2027-01-10T10:00:00", photos(5)), None, &cache).unwrap();
        assert_eq!(later, frozen);
        assert_eq!(load_rewind(&cache, 2026, false), Some(frozen));
    }

    #[test]
    fn the_cache_ignores_other_modes_versions_and_unreadable_files() {
        let directory = tempfile::tempdir().unwrap();
        let cache = directory.path().join("rewind");
        let frozen = refresh_rewind(&request(AFTER_NEW_YEAR, photos(2)), None, &cache).unwrap();

        assert_eq!(load_rewind(&cache, 2026, true), None);
        assert_eq!(load_rewind(&cache, 2025, false), None);

        let mut offline = request(AFTER_NEW_YEAR, photos(3));
        offline.local_gallery_mode = true;
        let replaced = refresh_rewind(&offline, None, &cache).unwrap();
        assert_ne!(replaced, frozen);
        assert_eq!(load_rewind(&cache, 2026, false), None);

        let mut outdated = replaced;
        outdated.version = REWIND_VERSION + 1;
        fs::write(
            cache.join("2026.json"),
            serde_json::to_vec(&outdated).unwrap(),
        )
        .unwrap();
        assert_eq!(load_rewind(&cache, 2026, true), None);

        fs::write(cache.join("2026.json"), b"{").unwrap();
        assert_eq!(load_rewind(&cache, 2026, true), None);
        assert!(refresh_rewind(&offline, None, &cache).unwrap().is_final);

        clear_rewind(&cache).unwrap();
        assert!(!cache.exists());
        clear_rewind(&cache).unwrap();
    }

    #[test]
    fn a_refresh_that_overlaps_a_clear_leaves_the_cache_cleared() {
        let directory = tempfile::tempdir().unwrap();
        let cache_directory = directory.path().join("rewind");
        refresh_rewind(&request(BEFORE_NEW_YEAR, photos(1)), None, &cache_directory).unwrap();

        let clear_count_before = cache::clear_count(&cache_directory);
        let state = compute_rewind(&request(BEFORE_NEW_YEAR, photos(2)), None).unwrap();
        clear_rewind(&cache_directory).unwrap();

        let published =
            cache::publish(&cache_directory, state.clone(), clear_count_before).unwrap();
        assert_eq!(published, state);
        assert!(!cache_directory.exists());
    }

    #[test]
    fn clearing_a_parent_directory_cancels_a_refresh_into_a_child_directory() {
        let directory = tempfile::tempdir().unwrap();
        let root = directory.path().join("rewind");
        let account = root.join("1");
        refresh_rewind(&request(BEFORE_NEW_YEAR, photos(1)), None, &account).unwrap();

        let clear_count_before = cache::clear_count(&account);
        let state = compute_rewind(&request(BEFORE_NEW_YEAR, photos(2)), None).unwrap();
        clear_rewind(&root).unwrap();

        let published = cache::publish(&account, state.clone(), clear_count_before).unwrap();
        assert_eq!(published, state);
        assert!(!root.exists());
    }

    #[test]
    fn clearing_a_sibling_directory_does_not_cancel_a_refresh() {
        let directory = tempfile::tempdir().unwrap();
        let root = directory.path().join("rewind");
        let account = root.join("1");
        let sibling = root.join("2");
        refresh_rewind(&request(BEFORE_NEW_YEAR, photos(1)), None, &sibling).unwrap();

        let clear_count_before = cache::clear_count(&account);
        let state = compute_rewind(&request(BEFORE_NEW_YEAR, photos(2)), None).unwrap();
        clear_rewind(&sibling).unwrap();

        cache::publish(&account, state.clone(), clear_count_before).unwrap();
        assert_eq!(load_rewind(&account, 2026, false), Some(state));
    }
}
