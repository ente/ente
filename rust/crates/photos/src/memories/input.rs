use std::collections::{HashMap, HashSet};

use ente_location::{CityMatch, Coordinate};

use super::calendar::{LocalDate, MICROS_PER_DAY, MICROS_PER_SECOND};
use super::output::{ClipMemoryType, PeopleMemoryType};
use crate::location::LocationIndex;
use crate::ml_store::Result;

#[derive(Clone, Debug, PartialEq)]
pub struct MemoryFile {
    pub id: i64,
    pub creation_time: i64,
    pub local_date_time: Option<String>,
    pub utc_offset_seconds: i32,
    pub collection_id: Option<i64>,
    pub location: Option<Coordinate>,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct MemoriesRequest {
    pub files: Vec<MemoryFile>,
    pub excluded_collection_ids: Vec<i64>,
    pub people: Vec<MemoryPerson>,
    pub me_person_id: Option<String>,
    pub shows_unnamed_people: bool,
    pub shown_people: Vec<ShownPerson>,
    pub shown_trips: Vec<ShownTrip>,
    pub cached_trips: Vec<CachedTrip>,
    pub shown_clip_memories: Vec<ShownClipMemory>,
    pub surface_all: bool,
    pub local_gallery_mode: bool,
    pub seed: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MemoryPerson {
    pub id: String,
    pub is_ignored: bool,
    pub birth_date: Option<LocalDate>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ShownPerson {
    pub person_id: String,
    pub memory_type: PeopleMemoryType,
    pub last_time_shown: i64,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ShownTrip {
    pub key: Option<String>,
    pub location: Coordinate,
    pub last_time_shown: i64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ShownClipMemory {
    pub kind: ClipMemoryType,
    pub last_time_shown: i64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CachedTrip {
    pub identity_key: String,
    pub first_date_to_show: i64,
    pub last_date_to_show: i64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Period {
    pub now: i64,
    pub utc_offset_seconds: i32,
}

impl Period {
    pub(super) fn local_now(self) -> i64 {
        self.now + self.utc_offset_micros()
    }

    pub(super) fn today(self) -> LocalDate {
        LocalDate::of_local_time(self.local_now())
    }

    pub(super) fn start_of(self, date: LocalDate) -> i64 {
        date.days_since_epoch() * MICROS_PER_DAY - self.utc_offset_micros()
    }

    fn utc_offset_micros(self) -> i64 {
        i64::from(self.utc_offset_seconds) * MICROS_PER_SECOND
    }
}

pub struct MlInputs<'m> {
    pub clip: &'m dyn ClipVectors,
    pub face_weights: HashMap<i64, u32>,
    pub people: PeopleInputs,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct PeopleInputs {
    pub face_counts: HashMap<i64, u32>,
    pub person_file_ids: HashMap<String, HashSet<i64>>,
    pub unnamed_clusters: Vec<UnnamedCluster>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct UnnamedCluster {
    pub id: String,
    pub face_count: u32,
    pub file_ids: HashSet<i64>,
}

pub trait ClipVectors {
    fn matches(&self, query: &[f32], min_similarity: f32) -> Result<Vec<(i64, f32)>>;
    fn vector(&self, file_id: i64) -> Result<Option<Vec<f32>>>;
}

pub(super) trait PhotoSignals {
    fn face_weight(&self, file_id: i64) -> u32;
    fn nostalgia(&self, file_id: i64) -> Option<f32>;
    fn similarity(&self, file_id: i64, other_file_id: i64) -> Result<Option<f32>>;
}

pub trait CityLookup {
    fn group_cities(&self, coordinates: &[Coordinate]) -> Vec<CityMatch>;
}

impl CityLookup for LocationIndex {
    fn group_cities(&self, coordinates: &[Coordinate]) -> Vec<CityMatch> {
        LocationIndex::group_cities(self, coordinates, "")
    }
}
