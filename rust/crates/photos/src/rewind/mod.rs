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
    Badge, BusiestDay, ColourOfTheYear, CrowdFavourite, Favourites, Finale, Globe, GlobePlace,
    LikedPhoto, Mosaic, NewFace, NewFaces, PeopleRace, Places, RacePerson, RewindBadge, RewindCity,
    RewindColour, RewindReport, Scrapbook, Spots, Totals, Tour, TourStop, Warp, WeeklyHabit,
};
pub use state::{REWIND_VERSION, RewindState, RewindStatus};

use clip::Clip;
use library::Library;
use people::People;
use state::{MlReadiness, has_enough_ml};

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
    let readiness = MlReadiness::of(request, &library, store)?;
    RewindState::evaluate(request, &library, store, cities, &readiness, previous)
}

pub fn rewind_has_enough_ml(request: &RewindRequest, store: &MlStore) -> Result<bool> {
    let library = Library::of_year(request)?;
    Ok(has_enough_ml(library.ml_coverage(store)?))
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

pub fn rewind_badge_signals(request: &RewindRequest, store: Option<&MlStore>) -> Result<String> {
    let library = Library::of_year(request)?;
    let ml_coverage = store.map(|store| library.ml_coverage(store)).transpose()?;
    let people = store
        .map(|store| People::load(request, &library, store))
        .transpose()?;
    let clip = store.map(|store| Clip::load(&library, store)).transpose()?;
    let signals = chapters::badge_signals(
        request,
        &library,
        people.as_ref(),
        clip.as_ref(),
        ml_coverage,
    );
    Ok(serde_json::to_string_pretty(&signals)?)
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use tempfile::TempDir;

    use super::fixtures::{
        BEFORE_NEW_YEAR, NoCities, appear, daily_photos, located, photo, request_at,
    };
    use super::library::MICROS_PER_DAY;
    use super::{
        Mosaic, REWIND_VERSION, RewindColour, RewindFile, RewindFileType, RewindReport,
        RewindRequest, RewindState, RewindStatus, compute_rewind, decode_rewind_state,
        encode_rewind_request, encode_rewind_state, rewind_has_enough_ml,
    };
    use crate::ml_db::{
        CLIP_EMBEDDING_DIMENSIONS, CLIP_ML_VERSION, ClipEmbedding, FACE_ML_VERSION, FaceRow,
    };
    use crate::ml_store::{CLUSTER_CENTROID_DIMENSIONS, MlStore};

    const AFTER_NEW_YEAR: &str = "2027-01-02T10:00:00";

    fn a_day_earlier(request: &RewindRequest) -> RewindRequest {
        let mut earlier = request.clone();
        earlier.now -= MICROS_PER_DAY;
        earlier
    }

    fn unclustered_face(store: &MlStore, file_id: i64, embedding: Vec<f64>) {
        store
            .db()
            .bulk_insert_faces(&[FaceRow {
                file_id,
                face_id: format!("{file_id}_unclustered"),
                detection_json: "{}".to_string(),
                embedding,
                score: 0.9,
                blur: 300.0,
                is_sideways: false,
                image_height: 100,
                image_width: 100,
                ml_version: FACE_ML_VERSION,
            }])
            .unwrap();
    }

    fn cluster_indexed_faces(store: &MlStore, file_ids: impl IntoIterator<Item = i64>) {
        let clusters: HashMap<String, String> = file_ids
            .into_iter()
            .map(|id| (format!("{id}_face"), format!("cluster_{id}")))
            .collect();
        store.db().update_face_id_to_cluster_id(&clusters).unwrap();
    }

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
            RewindStatus::Ready { report } => report.totals.as_ref().map(|totals| totals.files),
            RewindStatus::NothingToShow => None,
        }
    }

    fn colour(state: &RewindState) -> Option<RewindColour> {
        match &state.status {
            RewindStatus::Ready { report } => report.colour.as_ref().map(|colour| colour.colour),
            RewindStatus::NothingToShow => None,
        }
    }

    fn new_face_clusters(state: &RewindState) -> Option<Vec<String>> {
        match &state.status {
            RewindStatus::Ready { report } => report.new_faces.as_ref().map(|new_faces| {
                new_faces
                    .faces
                    .iter()
                    .filter_map(|face| face.cluster_id.clone())
                    .collect()
            }),
            RewindStatus::NothingToShow => None,
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
        let first =
            compute_rewind(&a_day_earlier(&after_new_year), None, Some(&NoCities), None).unwrap();
        assert!(!first.is_final);

        let without_cities = compute_rewind(&after_new_year, None, None, Some(&first)).unwrap();
        assert_eq!(total_files(&without_cities), Some(3));
        assert!(!without_cities.is_final);

        let after = compute_rewind(&after_new_year, None, Some(&NoCities), Some(&first)).unwrap();
        assert!(after.is_final);
    }

    #[test]
    fn a_first_report_after_new_year_freezes_only_a_day_later_with_the_same_photos() {
        let after_new_year = request_at(AFTER_NEW_YEAR, photos(3));
        let first =
            compute_rewind(&a_day_earlier(&after_new_year), None, Some(&NoCities), None).unwrap();
        assert!(matches!(first.status, RewindStatus::Ready { .. }));
        assert!(!first.is_final);

        let mut an_hour_later = a_day_earlier(&after_new_year);
        an_hour_later.now += MICROS_PER_DAY / 24;
        let same_day = compute_rewind(&an_hour_later, None, Some(&NoCities), Some(&first)).unwrap();
        assert!(!same_day.is_final);

        let filled_in = compute_rewind(
            &request_at(AFTER_NEW_YEAR, photos(5)),
            None,
            Some(&NoCities),
            Some(&first),
        )
        .unwrap();
        assert_eq!(total_files(&filled_in), Some(5));
        assert!(!filled_in.is_final);

        let settled = compute_rewind(&after_new_year, None, Some(&NoCities), Some(&first)).unwrap();
        assert!(settled.is_final);
    }

    #[test]
    fn with_ml_the_ml_chapters_wait_until_ninety_percent_of_the_year_is_indexed() {
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
        assert_eq!(total_files(&waiting), Some(11));
        assert_eq!(waiting.ml_coverage, Some(0.8));
        assert!(waiting.ml_chapters_pending);
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
        assert!(!ready.ml_chapters_pending);
        assert!(!ready.is_final);

        let after_new_year = request_at(AFTER_NEW_YEAR, files);
        let first = compute_rewind(
            &a_day_earlier(&after_new_year),
            Some(&store),
            Some(&NoCities),
            None,
        )
        .unwrap();
        let older_unindexed =
            compute_rewind(&after_new_year, Some(&store), Some(&NoCities), Some(&first)).unwrap();
        assert!(!older_unindexed.is_final);

        let (_directory, store) = indexed_store((1..=9).chain([12]));
        cluster_indexed_faces(&store, (1..=9).chain([12]));
        let frozen =
            compute_rewind(&after_new_year, Some(&store), Some(&NoCities), Some(&first)).unwrap();
        assert!(frozen.is_final);
    }

    #[test]
    fn enough_ml_means_ninety_percent_of_the_year_is_indexed() {
        let mut files = photos(10);
        files.push(photo(11, "2025-06-01T12:00:00"));
        let request = request_at(BEFORE_NEW_YEAR, files);

        let (_directory, store) = indexed_store(1..=8);
        assert!(!rewind_has_enough_ml(&request, &store).unwrap());

        let (_directory, store) = indexed_store(1..=9);
        assert!(rewind_has_enough_ml(&request, &store).unwrap());
    }

    #[test]
    fn new_faces_wait_until_earlier_years_are_indexed() {
        let mut files = daily_photos(1, "2026-01-01T12:00:00", 240);
        files.extend(daily_photos(301, "2025-06-01T12:00:00", 10));
        let request = request_at(AFTER_NEW_YEAR, files);

        let (_directory, store) = indexed_store(1..=240);
        appear(&store, "partner", None, 1..=120);
        appear(&store, "baby", None, 121..=240);
        let first = compute_rewind(
            &a_day_earlier(&request),
            Some(&store),
            Some(&NoCities),
            None,
        )
        .unwrap();
        let unsure = compute_rewind(&request, Some(&store), Some(&NoCities), Some(&first)).unwrap();
        assert!(matches!(unsure.status, RewindStatus::Ready { .. }));
        assert_eq!(new_face_clusters(&unsure), None);
        assert!(!unsure.is_final);

        let (_directory, store) = indexed_store((1..=240).chain(301..=310));
        appear(&store, "partner", None, (1..=120).chain(301..=310));
        appear(&store, "baby", None, 121..=240);
        cluster_indexed_faces(&store, (1..=240).chain(301..=310));
        let known = compute_rewind(&request, Some(&store), Some(&NoCities), Some(&first)).unwrap();
        assert_eq!(new_face_clusters(&known), Some(vec!["baby".to_string()]));
        assert!(known.is_final);
    }

    #[test]
    fn new_faces_wait_for_clustered_faces_after_the_ml_chapters_appear() {
        let mut files = daily_photos(1, "2026-01-01T12:00:00", 240);
        files.extend(daily_photos(301, "2025-06-01T12:00:00", 10));
        let request = request_at(BEFORE_NEW_YEAR, files);

        let (_directory, store) = indexed_store(1..=240);
        appear(&store, "partner", None, 1..=120);
        appear(&store, "baby", None, 121..=240);
        let shown = compute_rewind(&request, Some(&store), None, None).unwrap();
        assert!(!shown.ml_chapters_pending);
        assert_eq!(new_face_clusters(&shown), None);

        let (_directory, store) = indexed_store((1..=240).chain(301..=310));
        appear(&store, "partner", None, (1..=120).chain(301..=310));
        appear(&store, "baby", None, 121..=240);
        let mut before_clustering = request.clone();
        before_clustering.just_clustered = false;
        let unclustered =
            compute_rewind(&before_clustering, Some(&store), None, Some(&shown)).unwrap();
        assert!(!unclustered.ml_chapters_pending);
        assert_eq!(new_face_clusters(&unclustered), None);

        let clustered = compute_rewind(&request, Some(&store), None, Some(&unclustered)).unwrap();
        assert_eq!(
            new_face_clusters(&clustered),
            Some(vec!["baby".to_string()])
        );
    }

    #[test]
    fn ml_chapters_wait_until_faces_are_clustered() {
        let files = daily_photos(1, "2026-01-01T12:00:00", 60);
        let (_directory, store) = indexed_store(1..=60);
        let mut before_clustering = request_at(AFTER_NEW_YEAR, files.clone());
        before_clustering.just_clustered = false;

        let waiting = compute_rewind(
            &a_day_earlier(&before_clustering),
            Some(&store),
            Some(&NoCities),
            None,
        )
        .unwrap();
        assert_eq!(total_files(&waiting), Some(60));
        assert_eq!(colour(&waiting), None);
        assert!(waiting.ml_chapters_pending);
        assert!(!waiting.is_final);

        let just_clustered = compute_rewind(
            &request_at(AFTER_NEW_YEAR, files),
            Some(&store),
            Some(&NoCities),
            Some(&waiting),
        )
        .unwrap();
        assert_eq!(colour(&just_clustered), Some(RewindColour::CherryBomb));
        assert!(!just_clustered.ml_chapters_pending);
        assert!(!just_clustered.is_final);

        cluster_indexed_faces(&store, 1..=60);
        let already_clustered = compute_rewind(
            &before_clustering,
            Some(&store),
            Some(&NoCities),
            Some(&waiting),
        )
        .unwrap();
        assert_eq!(colour(&already_clustered), Some(RewindColour::CherryBomb));
        assert!(!already_clustered.ml_chapters_pending);
        assert!(already_clustered.is_final);
    }

    #[test]
    fn faces_after_the_year_do_not_hold_back_the_report() {
        let mut files = daily_photos(1, "2026-01-01T12:00:00", 60);
        files.push(photo(99, "2027-01-01T12:00:00"));
        let (_directory, store) = indexed_store(1..=60);
        cluster_indexed_faces(&store, 1..=60);
        unclustered_face(&store, 99, vec![0.1; CLUSTER_CENTROID_DIMENSIONS]);
        let mut request = request_at(AFTER_NEW_YEAR, files);
        request.just_clustered = false;

        let first = compute_rewind(
            &a_day_earlier(&request),
            Some(&store),
            Some(&NoCities),
            None,
        )
        .unwrap();
        assert_eq!(colour(&first), Some(RewindColour::CherryBomb));
        assert!(!first.ml_chapters_pending);
        let settled =
            compute_rewind(&request, Some(&store), Some(&NoCities), Some(&first)).unwrap();
        assert!(settled.is_final);
    }

    #[test]
    fn faces_the_clustering_skips_do_not_hold_back_the_report() {
        let files = daily_photos(1, "2026-01-01T12:00:00", 60);
        let (_directory, store) = indexed_store(1..=60);
        cluster_indexed_faces(&store, 1..=60);
        let mut invalid = vec![0.1; CLUSTER_CENTROID_DIMENSIONS];
        invalid[5] = f64::NAN;
        unclustered_face(&store, 7, invalid);
        let mut request = request_at(BEFORE_NEW_YEAR, files);
        request.just_clustered = false;

        let state = compute_rewind(&request, Some(&store), None, None).unwrap();
        assert_eq!(colour(&state), Some(RewindColour::CherryBomb));
        assert!(!state.ml_chapters_pending);

        unclustered_face(&store, 8, vec![0.1; CLUSTER_CENTROID_DIMENSIONS]);
        let waiting = compute_rewind(&request, Some(&store), None, None).unwrap();
        assert!(waiting.ml_chapters_pending);
    }

    #[test]
    fn new_faces_stay_once_shown_while_new_photos_wait_for_clustering() {
        let mut files = daily_photos(1, "2026-01-01T12:00:00", 240);
        files.extend(daily_photos(301, "2025-06-01T12:00:00", 10));
        let (_directory, store) = indexed_store((1..=240).chain(301..=310));
        appear(&store, "partner", None, (1..=120).chain(301..=310));
        appear(&store, "baby", None, 121..=240);
        let shown = compute_rewind(
            &request_at(BEFORE_NEW_YEAR, files.clone()),
            Some(&store),
            None,
            None,
        )
        .unwrap();
        assert_eq!(new_face_clusters(&shown), Some(vec!["baby".to_string()]));

        files.push(photo(241, "2026-12-30T12:00:00"));
        let (_directory, store) = indexed_store((1..=241).chain(301..=310));
        appear(&store, "partner", None, (1..=120).chain(301..=310));
        appear(&store, "baby", None, 121..=240);
        let mut before_clustering = request_at(BEFORE_NEW_YEAR, files);
        before_clustering.just_clustered = false;
        let unseen = compute_rewind(&before_clustering, Some(&store), None, None).unwrap();
        assert_eq!(new_face_clusters(&unseen), None);
        let still_shown =
            compute_rewind(&before_clustering, Some(&store), None, Some(&shown)).unwrap();
        assert_eq!(
            new_face_clusters(&still_shown),
            Some(vec!["baby".to_string()])
        );
    }

    #[test]
    fn unfinished_indexing_keeps_the_rewind_from_freezing() {
        let (_directory, store) = indexed_store(1..=5);
        let request = request_at(AFTER_NEW_YEAR, photos(10));
        let first = compute_rewind(
            &a_day_earlier(&request),
            Some(&store),
            Some(&NoCities),
            None,
        )
        .unwrap();

        let state = compute_rewind(&request, Some(&store), Some(&NoCities), Some(&first)).unwrap();
        assert_eq!(total_files(&state), Some(10));
        assert_eq!(state.ml_coverage, Some(0.5));
        assert!(state.ml_chapters_pending);
        assert!(!state.is_final);
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
    fn the_rewind_shows_while_indexing_catches_up() {
        let (_directory, store) = indexed_store(1..=9);
        let more_photos = request_at(BEFORE_NEW_YEAR, photos(15));

        let catching_up = compute_rewind(&more_photos, Some(&store), None, None).unwrap();
        assert_eq!(total_files(&catching_up), Some(15));
        assert!(catching_up.ml_chapters_pending);

        let without_ml = compute_rewind(&more_photos, None, None, None).unwrap();
        assert!(!without_ml.ml_chapters_pending);
        let switched_on =
            compute_rewind(&more_photos, Some(&store), None, Some(&without_ml)).unwrap();
        assert_eq!(total_files(&switched_on), Some(15));
        assert!(switched_on.ml_chapters_pending);
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

        let four_photos = request_at(AFTER_NEW_YEAR, photos(4));
        let first =
            compute_rewind(&a_day_earlier(&four_photos), None, Some(&NoCities), None).unwrap();
        let frozen = compute_rewind(&four_photos, None, Some(&NoCities), Some(&first)).unwrap();
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
    fn older_mosaic_caches_keep_the_ml_chapters_when_ml_coverage_drops() {
        let (_directory, store) = indexed_store(1..=200);
        let mut files = daily_photos(1, "2026-01-01T12:00:00", 200);
        let ready = compute_rewind(
            &request_at("2026-11-17T10:00:00", files.clone()),
            Some(&store),
            None,
            None,
        )
        .unwrap();
        assert!(!ready.is_final);
        let shown_colour = colour(&ready);
        assert!(shown_colour.is_some());
        let mut cache = serde_json::to_value(&ready).unwrap();
        let mosaic = cache["status"]["Ready"]["report"]["mosaic"]
            .as_object_mut()
            .unwrap();
        mosaic.remove("cluster_id");
        mosaic.remove("cluster_face_ids");
        let bytes = serde_json::to_vec(&cache).unwrap();
        let previous = decode_rewind_state(&bytes, 2026, false);

        files.extend(daily_photos(201, "2026-07-20T12:00:00", 100));
        let refreshed = compute_rewind(
            &request_at("2026-11-18T10:00:00", files),
            Some(&store),
            None,
            previous.as_ref(),
        )
        .unwrap();
        assert_eq!(refreshed.ml_coverage, Some(200.0 / 300.0));
        assert!(
            matches!(refreshed.status, RewindStatus::Ready { .. }),
            "{:?}",
            refreshed.status
        );
        assert_eq!(colour(&refreshed), shown_colour);
    }

    #[test]
    fn a_final_result_is_kept_unless_ml_was_switched_off() {
        let (_directory, store) = indexed_store(1..=60);
        cluster_indexed_faces(&store, 1..=60);
        let request = request_at(AFTER_NEW_YEAR, daily_photos(1, "2026-01-01T12:00:00", 60));

        let earlier_without_ml =
            compute_rewind(&a_day_earlier(&request), None, Some(&NoCities), None).unwrap();
        let without_ml =
            compute_rewind(&request, None, Some(&NoCities), Some(&earlier_without_ml)).unwrap();
        assert!(without_ml.is_final);
        assert_eq!(
            compute_rewind(&request, Some(&store), Some(&NoCities), Some(&without_ml)).unwrap(),
            without_ml
        );

        let earlier_with_ml = compute_rewind(
            &a_day_earlier(&request),
            Some(&store),
            Some(&NoCities),
            None,
        )
        .unwrap();
        let with_ml = compute_rewind(
            &request,
            Some(&store),
            Some(&NoCities),
            Some(&earlier_with_ml),
        )
        .unwrap();
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
    fn ml_chapters_stay_once_shown_and_otherwise_wait_for_ninety_percent() {
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
        assert!(!latched.ml_chapters_pending);
        let still_latched =
            compute_rewind(&after_new_year, Some(&store), None, Some(&latched)).unwrap();
        assert_eq!(colour(&still_latched), Some(RewindColour::CherryBomb));

        let unseen = compute_rewind(&after_new_year, Some(&store), None, None).unwrap();
        assert!(matches!(unseen.status, RewindStatus::Ready { .. }));
        assert_eq!(colour(&unseen), None);
        assert!(unseen.ml_chapters_pending);
        let after_unseen =
            compute_rewind(&after_new_year, Some(&store), None, Some(&unseen)).unwrap();
        assert_eq!(colour(&after_unseen), None);
    }

    #[test]
    fn an_unnamed_mosaic_face_keeps_the_ml_chapters_once_shown() {
        let report = RewindReport {
            mosaic: Some(Mosaic {
                file_ids: vec![1],
                me_person_id: None,
                me_face_ids: Vec::new(),
                top_person_id: None,
                top_face_ids: Vec::new(),
                cluster_id: Some("stranger".to_string()),
                cluster_face_ids: vec!["1_stranger".to_string()],
            }),
            ..RewindReport::default()
        };
        assert!(report.shows_ml_chapters());
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
