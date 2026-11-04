mod chapters;
mod input;
mod library;
mod report;
mod state;

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
    Json(#[from] serde_json::Error),
    #[error("year {0} is not supported")]
    UnsupportedYear(i32),
}

pub type Result<T> = std::result::Result<T, Error>;

pub fn compute_rewind(
    request: &RewindRequest,
    store: Option<&MlStore>,
    previous: Option<&RewindState>,
) -> Result<RewindState> {
    if let Some(previous) = previous.filter(|previous| previous.is_final_for(request)) {
        return Ok(previous.clone());
    }
    let library = Library::of_year(request)?;
    let ml_coverage = store.map(|store| library.ml_coverage(store)).transpose()?;
    Ok(RewindState::evaluate(request, &library, ml_coverage))
}

pub fn encode_rewind_state(state: &RewindState) -> Result<Vec<u8>> {
    Ok(serde_json::to_vec(state)?)
}

pub fn decode_rewind_state(
    bytes: &[u8],
    year: i32,
    local_gallery_mode: bool,
) -> Option<RewindState> {
    match serde_json::from_slice::<RewindState>(bytes) {
        Ok(state) => (state.version == REWIND_VERSION
            && state.year == year
            && state.local_gallery_mode == local_gallery_mode)
            .then_some(state),
        Err(error) => {
            log::warn!("ignoring an unreadable rewind state: {error}");
            None
        }
    }
}

pub fn encode_rewind_request(request: &RewindRequest) -> Result<Vec<u8>> {
    Ok(serde_json::to_vec_pretty(request)?)
}

#[cfg(test)]
mod tests {
    use ente_exif::DateTime;
    use tempfile::TempDir;

    use super::{
        REWIND_VERSION, RewindFile, RewindFileType, RewindReport, RewindRequest, RewindState,
        RewindStatus, Totals, compute_rewind, decode_rewind_state, encode_rewind_request,
        encode_rewind_state,
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

        let state = compute_rewind(&request(BEFORE_NEW_YEAR, files), None, None).unwrap();

        assert_eq!(totals(&state), Some(Totals { files: 2 }));
    }

    #[test]
    fn without_ml_the_rewind_is_ready_and_freezes_once_the_year_has_ended() {
        let before = compute_rewind(&request(BEFORE_NEW_YEAR, photos(3)), None, None).unwrap();
        assert_eq!(totals(&before), Some(Totals { files: 3 }));
        assert_eq!(before.ml_coverage, None);
        assert!(!before.is_final);

        let mut late_in_new_york = request("2027-01-01T04:00:00", photos(3));
        late_in_new_york.utc_offset_seconds = -5 * 3600;
        assert!(
            !compute_rewind(&late_in_new_york, None, None)
                .unwrap()
                .is_final
        );

        let after = compute_rewind(&request(AFTER_NEW_YEAR, photos(3)), None, None).unwrap();
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
            compute_rewind(&request(BEFORE_NEW_YEAR, files.clone()), Some(&store), None).unwrap();
        assert_eq!(waiting.status, RewindStatus::WaitingForMl);
        assert_eq!(waiting.ml_coverage, Some(0.8));
        assert!(!waiting.is_final);

        let (_directory, store) = indexed_store(1..=9);
        let ready =
            compute_rewind(&request(BEFORE_NEW_YEAR, files.clone()), Some(&store), None).unwrap();
        assert_eq!(totals(&ready), Some(Totals { files: 11 }));
        assert_eq!(ready.ml_coverage, Some(0.9));
        assert!(!ready.is_final);

        let frozen = compute_rewind(&request(AFTER_NEW_YEAR, files), Some(&store), None).unwrap();
        assert!(frozen.is_final);
    }

    #[test]
    fn after_new_year_unfinished_indexing_shows_the_rewind_unless_installed_this_season() {
        let (_directory, store) = indexed_store(1..=5);

        let fallback =
            compute_rewind(&request(AFTER_NEW_YEAR, photos(10)), Some(&store), None).unwrap();
        assert_eq!(totals(&fallback), Some(Totals { files: 10 }));
        assert_eq!(fallback.ml_coverage, Some(0.5));
        assert!(!fallback.is_final);

        let mut new_install = request(AFTER_NEW_YEAR, photos(10));
        new_install.installed_at = new_install.season_start;
        let waiting = compute_rewind(&new_install, Some(&store), None).unwrap();
        assert_eq!(waiting.status, RewindStatus::WaitingForMl);
        assert!(!waiting.is_final);
    }

    #[test]
    fn a_year_without_photos_has_no_totals() {
        let (_directory, store) = indexed_store([]);
        let state =
            compute_rewind(&request(BEFORE_NEW_YEAR, Vec::new()), Some(&store), None).unwrap();
        assert_eq!(state.ml_coverage, Some(1.0));
        assert_eq!(
            state.status,
            RewindStatus::Ready {
                report: RewindReport { totals: None },
            }
        );
    }

    #[test]
    fn a_final_previous_result_is_kept_and_anything_else_is_recomputed() {
        let provisional = compute_rewind(&request(BEFORE_NEW_YEAR, photos(2)), None, None).unwrap();
        let next = compute_rewind(
            &request(BEFORE_NEW_YEAR, photos(3)),
            None,
            Some(&provisional),
        )
        .unwrap();
        assert_eq!(totals(&next), Some(Totals { files: 3 }));

        let frozen = compute_rewind(&request(AFTER_NEW_YEAR, photos(4)), None, None).unwrap();
        assert!(frozen.is_final);
        let later = request("2027-01-10T10:00:00", photos(5));
        assert_eq!(compute_rewind(&later, None, Some(&frozen)).unwrap(), frozen);

        let mut offline = later.clone();
        offline.local_gallery_mode = true;
        let mut outdated = frozen.clone();
        outdated.version = REWIND_VERSION + 1;
        let mut last_year = frozen.clone();
        last_year.year = 2025;
        for (request, previous) in [
            (&offline, &frozen),
            (&later, &outdated),
            (&later, &last_year),
        ] {
            let recomputed = compute_rewind(request, None, Some(previous)).unwrap();
            assert_eq!(totals(&recomputed), Some(Totals { files: 5 }));
        }
    }

    #[test]
    fn states_decode_only_for_their_year_mode_and_version() {
        let state = compute_rewind(&request(BEFORE_NEW_YEAR, photos(2)), None, None).unwrap();
        let bytes = encode_rewind_state(&state).unwrap();
        assert_eq!(
            decode_rewind_state(&bytes, 2026, false),
            Some(state.clone())
        );
        assert_eq!(decode_rewind_state(&bytes, 2025, false), None);
        assert_eq!(decode_rewind_state(&bytes, 2026, true), None);

        let mut outdated = state;
        outdated.version = REWIND_VERSION + 1;
        let outdated = encode_rewind_state(&outdated).unwrap();
        assert_eq!(decode_rewind_state(&outdated, 2026, false), None);
        assert_eq!(decode_rewind_state(b"{", 2026, false), None);
    }

    #[test]
    fn requests_encode_as_the_harness_reads_them() {
        let request = request(BEFORE_NEW_YEAR, photos(2));
        let bytes = encode_rewind_request(&request).unwrap();
        assert_eq!(
            serde_json::from_slice::<RewindRequest>(&bytes).unwrap(),
            request
        );
    }
}
