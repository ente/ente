use std::collections::HashMap;

use ente_exif::DateTime;
use ente_location::{CityMatch, Coordinate, CountryCode};
use tempfile::TempDir;

use super::input::{
    RewindFile, RewindFileType, RewindLocation, RewindPerson, RewindRequest, RewindVisibility,
};
use crate::memories::CityLookup;
use crate::ml_db::{
    CLIP_EMBEDDING_DIMENSIONS, CLIP_ML_VERSION, ClipEmbedding, FACE_ML_VERSION, FaceRow,
};
use crate::ml_store::{CLUSTER_CENTROID_DIMENSIONS, MlStore};

pub(super) const BEFORE_NEW_YEAR: &str = "2026-12-20T10:00:00";

pub(super) struct NoCities;

impl CityLookup for NoCities {
    fn group_cities(&self, _coordinates: &[Coordinate]) -> Vec<CityMatch> {
        Vec::new()
    }

    fn urban_centers(&self, coordinates: &[Coordinate]) -> Vec<Option<u32>> {
        vec![None; coordinates.len()]
    }

    fn countries(&self, coordinates: &[Coordinate]) -> Vec<Option<CountryCode>> {
        vec![None; coordinates.len()]
    }

    fn country_name(&self, _country: CountryCode) -> Option<String> {
        None
    }
}

pub(super) fn micros(date_time: &str) -> i64 {
    DateTime::parse(&format!("{date_time}Z"))
        .and_then(DateTime::unix_micros)
        .unwrap()
}

pub(super) fn photo(id: i64, date_time: &str) -> RewindFile {
    RewindFile {
        id,
        creation_time: micros(date_time),
        local_date_time: None,
        utc_offset_seconds: 0,
        file_type: RewindFileType::Image,
        location: None,
        visibility: RewindVisibility::Visible,
        is_favourite: false,
        is_junk: false,
        is_screenshot: false,
        shared_album_ids: Vec::new(),
        like_count: 0,
    }
}

pub(super) fn located(mut file: RewindFile, latitude: f64, longitude: f64) -> RewindFile {
    file.location = Some(RewindLocation {
        latitude,
        longitude,
    });
    file
}

pub(super) fn daily_photos(first_id: i64, first_day: &str, days: i64) -> Vec<RewindFile> {
    let start = micros(first_day);
    (0..days)
        .map(|day| {
            let mut file = photo(first_id + day, first_day);
            file.creation_time = start + day * 86_400_000_000;
            file
        })
        .collect()
}

pub(super) fn request_at(now: &str, files: Vec<RewindFile>) -> RewindRequest {
    RewindRequest {
        year: 2026,
        now: micros(now),
        utc_offset_seconds: 0,
        season_start: micros("2026-12-05T00:00:00"),
        installed_at: micros("2024-03-01T00:00:00"),
        local_gallery_mode: false,
        files,
        people: Vec::new(),
        me_person_id: None,
    }
}

pub(super) fn request(files: Vec<RewindFile>) -> RewindRequest {
    request_at(BEFORE_NEW_YEAR, files)
}

pub(super) fn person(id: &str) -> RewindPerson {
    RewindPerson {
        id: id.to_string(),
        is_ignored: false,
        is_hidden_from_memories: false,
    }
}

pub(super) fn store() -> (TempDir, MlStore) {
    let directory = tempfile::tempdir().unwrap();
    let store = MlStore::open(directory.path().join("ente.ml.db")).unwrap();
    (directory, store)
}

pub(super) fn face_row(face_id: &str, score: f64, size: f64) -> FaceRow {
    FaceRow {
        file_id: face_id.split_once('_').unwrap().0.parse().unwrap(),
        face_id: face_id.to_string(),
        detection_json: format!(
            r#"{{"box":{{"x":0.1,"y":0.1,"width":{size},"height":{size}}},"landmarks":[]}}"#
        ),
        embedding: vec![0.1; CLUSTER_CENTROID_DIMENSIONS],
        score,
        blur: 300.0,
        is_sideways: false,
        image_height: 100,
        image_width: 100,
        ml_version: FACE_ML_VERSION,
    }
}

pub(super) fn add_faces(store: &MlStore, faces: &[(FaceRow, &str)]) {
    let rows: Vec<FaceRow> = faces.iter().map(|(face, _)| face.clone()).collect();
    store.db().bulk_insert_faces(&rows).unwrap();
    let clusters: HashMap<String, String> = faces
        .iter()
        .map(|(face, cluster)| (face.face_id.clone(), (*cluster).to_string()))
        .collect();
    store.db().update_face_id_to_cluster_id(&clusters).unwrap();
}

pub(super) fn add_clip(store: &MlStore, file_id: i64, vector: &[f32]) {
    assert_eq!(vector.len(), CLIP_EMBEDDING_DIMENSIONS);
    store
        .put_clip(&[ClipEmbedding {
            file_id,
            embedding: vector.iter().map(|&value| f64::from(value)).collect(),
            version: CLIP_ML_VERSION,
        }])
        .unwrap();
}

pub(super) fn appear(
    store: &MlStore,
    cluster: &str,
    person: Option<&str>,
    file_ids: impl IntoIterator<Item = i64>,
) {
    let faces: Vec<(FaceRow, &str)> = file_ids
        .into_iter()
        .map(|file_id| (face_row(&format!("{file_id}_{cluster}"), 0.9, 0.2), cluster))
        .collect();
    add_faces(store, &faces);
    if let Some(person) = person {
        store
            .db()
            .assign_cluster_to_person(person, cluster)
            .unwrap();
    }
}
