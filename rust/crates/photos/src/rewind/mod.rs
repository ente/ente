mod chapters;
mod clip;
#[cfg(test)]
mod fixtures;
mod geo;
mod input;
mod library;
mod people;
mod percentile;
mod queries;
mod ranking;
mod report;
mod state;

pub use input::{
    RewindFile, RewindFileType, RewindLocation, RewindPerson, RewindRequest, RewindVisibility,
};
pub use report::{
    Badge, BusiestDay, ColourOfTheYear, CrowdFavourite, Favourites, LikedPhoto, NewFace, NewFaces,
    PeopleRace, Places, RacePerson, RewindBadge, RewindCity, RewindColour, RewindReport, Scrapbook,
    Spots, Totals, WeeklyHabit,
};
pub use state::{REWIND_VERSION, RewindState, RewindStatus};

use library::Library;

use crate::memories::CityLookup;
use crate::ml_store::MlStore;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Database(#[from] crate::ml_db::Error),
    #[error(transparent)]
    Store(#[from] crate::ml_store::Error),
    #[error(transparent)]
    Json(#[from] serde_json::Error),
    #[error("year {0} is not supported")]
    UnsupportedYear(i32),
}

pub type Result<T> = std::result::Result<T, Error>;

pub fn compute_rewind(
    request: &RewindRequest,
    store: Option<&MlStore>,
    cities: Option<&dyn CityLookup>,
    previous: Option<&RewindState>,
) -> Result<RewindState> {
    let previous = previous.filter(|previous| previous.applies_to(request));
    let ml_switched_off =
        |previous: &RewindState| previous.ml_coverage.is_some() && store.is_none();
    if let Some(previous) =
        previous.filter(|previous| previous.is_final && !ml_switched_off(previous))
    {
        return Ok(previous.clone());
    }
    let library = Library::of_year(request)?;
    let ml_coverage = store.map(|store| library.ml_coverage(store)).transpose()?;
    let previous_report = previous
        .filter(|previous| previous.ml_coverage.is_some())
        .and_then(|previous| match &previous.status {
            RewindStatus::Ready { report } => Some(report.as_ref()),
            RewindStatus::WaitingForMl | RewindStatus::NothingToShow => None,
        });
    RewindState::evaluate(
        request,
        &library,
        store,
        cities,
        ml_coverage,
        previous_report.is_some(),
        previous_report.is_some_and(RewindReport::shows_ml_chapters),
    )
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
    use tempfile::TempDir;

    use super::fixtures::{BEFORE_NEW_YEAR, NoCities, daily_photos, located, photo, request_at};
    use super::{
        REWIND_VERSION, RewindColour, RewindFile, RewindFileType, RewindRequest, RewindState,
        RewindStatus, compute_rewind, decode_rewind_state, encode_rewind_request,
        encode_rewind_state,
    };
    use crate::ml_db::{
        CLIP_EMBEDDING_DIMENSIONS, CLIP_ML_VERSION, ClipEmbedding, FACE_ML_VERSION, FaceRow,
    };
    use crate::ml_store::{CLUSTER_CENTROID_DIMENSIONS, MlStore};

    const AFTER_NEW_YEAR: &str = "2027-01-02T10:00:00";

    fn photos(count: i64) -> Vec<RewindFile> {
        (1..=count)
            .map(|id| photo(id, "2026-06-01T12:00:00"))
            .collect()
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

    fn total_files(state: &RewindState) -> Option<u32> {
        match &state.status {
            RewindStatus::Ready { report } => report.totals.map(|totals| totals.files),
            RewindStatus::WaitingForMl | RewindStatus::NothingToShow => None,
        }
    }

    fn colour(state: &RewindState) -> Option<RewindColour> {
        match &state.status {
            RewindStatus::Ready { report } => report.colour.as_ref().map(|colour| colour.colour),
            RewindStatus::WaitingForMl | RewindStatus::NothingToShow => None,
        }
    }

    #[test]
    fn the_year_follows_each_photos_own_wall_clock() {
        let mut new_years_day_in_tokyo = photo(1, "2026-12-31T16:00:00");
        new_years_day_in_tokyo.local_date_time = Some("2027-01-01T01:00:00.000".to_string());
        let mut new_years_day_by_offset = photo(2, "2025-12-31T23:30:00");
        new_years_day_by_offset.utc_offset_seconds = 3600;
        let mut last_evening_in_new_york = photo(3, "2027-01-01T03:00:00");
        last_evening_in_new_york.local_date_time = Some("2026-12-31T22:00:00-05:00".to_string());
        let files = vec![
            new_years_day_in_tokyo,
            new_years_day_by_offset,
            last_evening_in_new_york,
            photo(4, "2025-12-31T23:59:59"),
            photo(5, "2027-01-01T00:00:00"),
        ];

        let state = compute_rewind(&request_at(BEFORE_NEW_YEAR, files), None, None, None).unwrap();

        assert_eq!(total_files(&state), Some(2));
    }

    #[test]
    fn without_ml_the_rewind_is_ready_and_freezes_once_the_year_has_ended() {
        let before =
            compute_rewind(&request_at(BEFORE_NEW_YEAR, photos(3)), None, None, None).unwrap();
        assert_eq!(total_files(&before), Some(3));
        assert_eq!(before.ml_coverage, None);
        assert!(!before.is_final);

        let mut late_in_new_york = request_at("2027-01-01T04:00:00", photos(3));
        late_in_new_york.utc_offset_seconds = -5 * 3600;
        assert!(
            !compute_rewind(&late_in_new_york, None, None, None)
                .unwrap()
                .is_final
        );

        let after_new_year = request_at(AFTER_NEW_YEAR, photos(3));
        let without_cities = compute_rewind(&after_new_year, None, None, None).unwrap();
        assert_eq!(total_files(&without_cities), Some(3));
        assert!(!without_cities.is_final);

        let after = compute_rewind(&after_new_year, None, Some(&NoCities), None).unwrap();
        assert!(after.is_final);
    }

    #[test]
    fn with_ml_the_rewind_waits_until_ninety_percent_of_the_year_is_indexed() {
        let mut files = photos(10);
        let mut document = photo(11, "2026-06-01T12:00:00");
        document.file_type = RewindFileType::Other;
        files.push(document);
        files.push(photo(12, "2025-06-01T12:00:00"));

        let (_directory, store) = indexed_store(1..=8);
        let waiting = compute_rewind(
            &request_at(BEFORE_NEW_YEAR, files.clone()),
            Some(&store),
            None,
            None,
        )
        .unwrap();
        assert_eq!(waiting.status, RewindStatus::WaitingForMl);
        assert_eq!(waiting.ml_coverage, Some(0.8));
        assert!(!waiting.is_final);

        let (_directory, store) = indexed_store(1..=9);
        let ready = compute_rewind(
            &request_at(BEFORE_NEW_YEAR, files.clone()),
            Some(&store),
            None,
            None,
        )
        .unwrap();
        assert_eq!(total_files(&ready), Some(11));
        assert_eq!(ready.ml_coverage, Some(0.9));
        assert!(!ready.is_final);

        let frozen = compute_rewind(
            &request_at(AFTER_NEW_YEAR, files),
            Some(&store),
            Some(&NoCities),
            None,
        )
        .unwrap();
        assert!(frozen.is_final);
    }

    #[test]
    fn after_new_year_unfinished_indexing_shows_the_rewind_unless_installed_this_season() {
        let (_directory, store) = indexed_store(1..=5);

        let fallback = compute_rewind(
            &request_at(AFTER_NEW_YEAR, photos(10)),
            Some(&store),
            None,
            None,
        )
        .unwrap();
        assert_eq!(total_files(&fallback), Some(10));
        assert_eq!(fallback.ml_coverage, Some(0.5));
        assert!(!fallback.is_final);

        let mut new_install = request_at(AFTER_NEW_YEAR, photos(10));
        new_install.installed_at = new_install.season_start;
        let waiting = compute_rewind(&new_install, Some(&store), None, None).unwrap();
        assert_eq!(waiting.status, RewindStatus::WaitingForMl);
        assert!(!waiting.is_final);
    }

    #[test]
    fn a_file_listed_more_than_once_counts_once() {
        let mut files = photos(10);
        files.push(photo(1, "2026-06-01T12:00:00"));
        files.push(photo(11, "2026-06-01T12:00:00"));
        files.push(photo(11, "2026-06-01T12:00:00"));

        let (_directory, store) = indexed_store(1..=10);
        let state = compute_rewind(
            &request_at(BEFORE_NEW_YEAR, files),
            Some(&store),
            None,
            None,
        )
        .unwrap();

        assert_eq!(total_files(&state), Some(11));
        assert_eq!(state.ml_coverage, Some(10.0 / 11.0));
    }

    #[test]
    fn a_year_without_photos_has_nothing_to_show_and_never_freezes() {
        let (_directory, store) = indexed_store([]);
        let state = compute_rewind(
            &request_at(BEFORE_NEW_YEAR, Vec::new()),
            Some(&store),
            None,
            None,
        )
        .unwrap();
        assert_eq!(state.ml_coverage, Some(1.0));
        assert_eq!(state.status, RewindStatus::NothingToShow);

        let after_new_year = compute_rewind(
            &request_at(AFTER_NEW_YEAR, Vec::new()),
            Some(&store),
            None,
            None,
        )
        .unwrap();
        assert_eq!(after_new_year.status, RewindStatus::NothingToShow);
        assert!(!after_new_year.is_final);
    }

    #[test]
    fn once_ready_with_ml_the_rewind_stays_ready_while_indexing_catches_up() {
        let (_directory, store) = indexed_store(1..=9);
        let ready = compute_rewind(
            &request_at(BEFORE_NEW_YEAR, photos(10)),
            Some(&store),
            None,
            None,
        )
        .unwrap();
        assert_eq!(total_files(&ready), Some(10));

        let more_photos = request_at(BEFORE_NEW_YEAR, photos(15));
        assert_eq!(
            compute_rewind(&more_photos, Some(&store), None, None)
                .unwrap()
                .status,
            RewindStatus::WaitingForMl
        );
        let still_ready = compute_rewind(&more_photos, Some(&store), None, Some(&ready)).unwrap();
        assert_eq!(total_files(&still_ready), Some(15));

        let after_new_year = compute_rewind(
            &request_at(AFTER_NEW_YEAR, photos(15)),
            Some(&store),
            None,
            Some(&still_ready),
        )
        .unwrap();
        assert!(!after_new_year.is_final);

        let nothing = compute_rewind(
            &request_at(BEFORE_NEW_YEAR, Vec::new()),
            Some(&store),
            None,
            None,
        )
        .unwrap();
        assert_eq!(
            compute_rewind(&more_photos, Some(&store), None, Some(&nothing))
                .unwrap()
                .status,
            RewindStatus::WaitingForMl
        );

        let without_ml =
            compute_rewind(&request_at(BEFORE_NEW_YEAR, photos(10)), None, None, None).unwrap();
        assert_eq!(total_files(&without_ml), Some(10));
        assert_eq!(
            compute_rewind(&more_photos, Some(&store), None, Some(&without_ml))
                .unwrap()
                .status,
            RewindStatus::WaitingForMl
        );
    }

    #[test]
    fn a_final_previous_result_is_kept_and_anything_else_is_recomputed() {
        let provisional =
            compute_rewind(&request_at(BEFORE_NEW_YEAR, photos(2)), None, None, None).unwrap();
        let next = compute_rewind(
            &request_at(BEFORE_NEW_YEAR, photos(3)),
            None,
            None,
            Some(&provisional),
        )
        .unwrap();
        assert_eq!(total_files(&next), Some(3));

        let frozen = compute_rewind(
            &request_at(AFTER_NEW_YEAR, photos(4)),
            None,
            Some(&NoCities),
            None,
        )
        .unwrap();
        assert!(frozen.is_final);
        let later = request_at("2027-01-10T10:00:00", photos(5));
        assert_eq!(
            compute_rewind(&later, None, None, Some(&frozen)).unwrap(),
            frozen
        );

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
            let recomputed = compute_rewind(request, None, None, Some(previous)).unwrap();
            assert_eq!(total_files(&recomputed), Some(5));
        }
    }

    #[test]
    fn states_decode_only_for_their_year_mode_and_version() {
        let state =
            compute_rewind(&request_at(BEFORE_NEW_YEAR, photos(2)), None, None, None).unwrap();
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
        let request = request_at(BEFORE_NEW_YEAR, photos(2));
        let bytes = encode_rewind_request(&request).unwrap();
        assert_eq!(
            serde_json::from_slice::<RewindRequest>(&bytes).unwrap(),
            request
        );
    }

    #[test]
    fn a_final_result_is_kept_unless_ml_was_switched_off() {
        let (_directory, store) = indexed_store(1..=60);
        let request = request_at(AFTER_NEW_YEAR, daily_photos(1, "2026-01-01T12:00:00", 60));

        let without_ml = compute_rewind(&request, None, Some(&NoCities), None).unwrap();
        assert!(without_ml.is_final);
        assert_eq!(
            compute_rewind(&request, Some(&store), Some(&NoCities), Some(&without_ml)).unwrap(),
            without_ml
        );

        let with_ml = compute_rewind(&request, Some(&store), Some(&NoCities), None).unwrap();
        assert!(with_ml.is_final);
        assert_eq!(colour(&with_ml), Some(RewindColour::CherryBomb));

        let switched_off = compute_rewind(&request, None, Some(&NoCities), Some(&with_ml)).unwrap();
        assert!(matches!(switched_off.status, RewindStatus::Ready { .. }));
        assert_eq!(switched_off.ml_coverage, None);
        assert_eq!(total_files(&switched_off), Some(60));
        assert_eq!(colour(&switched_off), None);
        assert!(switched_off.is_final);
    }

    #[test]
    fn ml_chapters_stay_once_shown_but_the_new_year_fallback_never_shows_them() {
        let (_directory, store) = indexed_store(1..=60);
        let indexed = daily_photos(1, "2026-01-01T12:00:00", 60);
        let ready = compute_rewind(
            &request_at(BEFORE_NEW_YEAR, indexed.clone()),
            Some(&store),
            None,
            None,
        )
        .unwrap();
        assert_eq!(colour(&ready), Some(RewindColour::CherryBomb));

        let mut more = indexed;
        more.extend(daily_photos(61, "2026-06-01T12:00:00", 40));
        let after_new_year = request_at(AFTER_NEW_YEAR, more);
        let latched = compute_rewind(&after_new_year, Some(&store), None, Some(&ready)).unwrap();
        assert_eq!(latched.ml_coverage, Some(0.6));
        assert_eq!(colour(&latched), Some(RewindColour::CherryBomb));
        let still_latched =
            compute_rewind(&after_new_year, Some(&store), None, Some(&latched)).unwrap();
        assert_eq!(colour(&still_latched), Some(RewindColour::CherryBomb));

        let fallback = compute_rewind(&after_new_year, Some(&store), None, None).unwrap();
        assert!(matches!(fallback.status, RewindStatus::Ready { .. }));
        assert_eq!(colour(&fallback), None);
        let after_fallback =
            compute_rewind(&after_new_year, Some(&store), None, Some(&fallback)).unwrap();
        assert_eq!(colour(&after_fallback), None);
    }

    #[test]
    fn offline_mode_reports_what_local_files_tell_without_likes_favourites_or_ml() {
        let mut files = Vec::new();
        for (first_id, latitude) in [(1, 52.0), (101, 52.1), (201, 52.2)] {
            files.extend(
                daily_photos(first_id, "2026-02-01T18:00:00", 70)
                    .into_iter()
                    .map(|file| located(file, latitude, 4.9)),
            );
        }
        let mut offline = request_at(BEFORE_NEW_YEAR, files);
        offline.local_gallery_mode = true;

        let state = compute_rewind(&offline, None, None, None).unwrap();

        let RewindStatus::Ready { report } = state.status else {
            panic!("expected a ready rewind, got {:?}", state.status);
        };
        assert!(report.spots.is_some());
        assert!(report.weekly_habit.is_some());
        assert!(report.badge.is_some());
        assert!(report.scrapbook.is_some());
        assert_eq!(report.busiest_day, None);
        assert_eq!(report.favourites, None);
        assert_eq!(report.crowd_favourite, None);
        assert_eq!(report.colour, None);
        assert_eq!(report.people_race, None);
        assert_eq!(report.places, None);
    }
}
