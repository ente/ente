pub use ente_location::Coordinate;
use ente_photos::memories;
use ente_photos::memories::CityLookup;
pub use ente_photos::memories::{
    BaseLocation, BaseMemory, Birthday, CachedTrip, ClipMemoryType, LocalDate, MemoriesRequest,
    Memory, MemoryBoundary, MemoryFile, MemoryKind, MemoryPerson, PeopleActivity, PeopleMemory,
    PeopleMemoryType, Period, ShownClipMemory, ShownPerson, ShownTrip, SmartMemories, TimeMemory,
    TripDetection, TripMemory,
};
use flutter_rust_bridge::frb;

use super::location_api::LocationIndex;
use super::ml_db_api::{MlDbError, MlStore};
use crate::frb_generated::RustAutoOpaque;

#[frb(mirror(Coordinate))]
pub struct _Coordinate {
    pub latitude: f64,
    pub longitude: f64,
}

#[frb(mirror(LocalDate))]
pub struct _LocalDate {
    pub year: i32,
    pub month: i32,
    pub day: i32,
}

#[frb(mirror(MemoryFile))]
pub struct _MemoryFile {
    pub id: i64,
    pub creation_time: i64,
    pub local_date_time: Option<String>,
    pub utc_offset_seconds: i32,
    pub collection_id: Option<i64>,
    pub location: Option<Coordinate>,
    pub shared: bool,
}

#[frb(mirror(MemoriesRequest))]
pub struct _MemoriesRequest {
    pub files: Vec<MemoryFile>,
    pub excluded_collection_ids: Vec<i64>,
    pub people: Vec<MemoryPerson>,
    pub people_hidden_from_memories: Vec<String>,
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

#[frb(mirror(MemoryPerson))]
pub struct _MemoryPerson {
    pub id: String,
    pub is_ignored: bool,
    pub birth_date: Option<LocalDate>,
}

#[frb(mirror(ShownPerson))]
pub struct _ShownPerson {
    pub person_id: String,
    pub memory_type: PeopleMemoryType,
    pub last_time_shown: i64,
}

#[frb(mirror(ShownTrip))]
pub struct _ShownTrip {
    pub key: Option<String>,
    pub location: Coordinate,
    pub last_time_shown: i64,
}

#[frb(mirror(ShownClipMemory))]
pub struct _ShownClipMemory {
    pub kind: ClipMemoryType,
    pub last_time_shown: i64,
}

#[frb(mirror(CachedTrip))]
pub struct _CachedTrip {
    pub identity_key: String,
    pub first_date_to_show: i64,
    pub last_date_to_show: i64,
}

#[frb(mirror(Period))]
pub struct _Period {
    pub now: i64,
    pub utc_offset_seconds: i32,
}

#[frb(mirror(TripDetection))]
pub enum _TripDetection {
    Legacy,
    Improved,
}

#[frb(mirror(SmartMemories))]
pub struct _SmartMemories {
    pub periods: Vec<Vec<Memory>>,
    pub base_locations: Vec<BaseLocation>,
}

#[frb(mirror(BaseLocation))]
pub struct _BaseLocation {
    pub file_ids: Vec<i64>,
    pub location: Coordinate,
    pub is_current: bool,
}

#[frb(mirror(Memory))]
pub struct _Memory {
    pub kind: MemoryKind,
    pub file_ids: Vec<i64>,
    pub first_date_to_show: MemoryBoundary,
    pub last_date_to_show: MemoryBoundary,
}

#[frb(mirror(MemoryBoundary))]
pub enum _MemoryBoundary {
    Timestamp(i64),
    CalendarDate(LocalDate),
}

#[frb(mirror(MemoryKind))]
pub enum _MemoryKind {
    OnThisDay,
    People(PeopleMemory),
    Trip(TripMemory),
    Base(BaseMemory),
    Clip(ClipMemoryType),
    Time(TimeMemory),
    Filler { years_ago: i32 },
}

#[frb(mirror(PeopleMemory))]
pub struct _PeopleMemory {
    pub person_id: String,
    pub is_unnamed_cluster: bool,
    pub memory_type: PeopleMemoryType,
    pub activity: Option<PeopleActivity>,
    pub birthday: Option<Birthday>,
}

#[frb(mirror(PeopleMemoryType))]
pub enum _PeopleMemoryType {
    YouAndThem,
    DoingSomethingTogether,
    Spotlight,
    LastTimeYouSawThem,
}

#[frb(mirror(PeopleActivity))]
pub enum _PeopleActivity {
    Admiring,
    Embracing,
    Party,
    Hiking,
    Feast,
    Selfies,
    Posing,
    Background,
    Sports,
    Roadtrip,
}

#[frb(mirror(Birthday))]
pub struct _Birthday {
    pub is_upcoming: bool,
    pub new_age: i32,
}

#[frb(mirror(TripMemory))]
pub struct _TripMemory {
    pub location: Coordinate,
    pub location_name: Option<String>,
    pub year: i32,
    pub key: String,
}

#[frb(mirror(BaseMemory))]
pub struct _BaseMemory {
    pub location: Coordinate,
    pub location_name: Option<String>,
    pub is_current: bool,
}

#[frb(mirror(ClipMemoryType))]
pub enum _ClipMemoryType {
    Sunrise,
    Mountains,
    Greenery,
    Beach,
    City,
    Moon,
    OnTheRoad,
    Food,
    Pets,
    Festivities,
    SnowAdventures,
    Waterfalls,
    Wildlife,
    Flowers,
    NightLights,
    Architecture,
    AutumnColors,
    DesertDreams,
    Stargazing,
    Lakeside,
    RainyDays,
    SportsAction,
    StreetArt,
    FamilyMoments,
    Fireworks,
    HistoricSites,
    TropicalParadise,
    ForestTrails,
    CitySunsets,
    ColorfulMarkets,
    CozyCafes,
    VintageVibes,
    AerialViews,
    ArtisticPortraits,
    StreetFood,
    RiverCruises,
    PlayfulKids,
    CoastalCliffs,
    CandidLaughter,
    GroupSelfies,
    BirthdayJoy,
    WeddingMoments,
    GoldenHourPortraits,
    ConcertNights,
    PoolDays,
    PicnicDays,
    CampingMoments,
    BabySmiles,
}

#[frb(mirror(TimeMemory))]
pub enum _TimeMemory {
    Day {
        date: LocalDate,
        years_ago: Option<i32>,
    },
    Week {
        years_ago: Option<i32>,
    },
    Month {
        year: i32,
        month: i32,
        years_ago: Option<i32>,
    },
    LastWeek,
    LastMonth,
}

pub fn compute_smart_memories(
    request: MemoriesRequest,
    periods: Vec<Period>,
    store: Option<RustAutoOpaque<MlStore>>,
    cities: Option<RustAutoOpaque<LocationIndex>>,
) -> Result<SmartMemories, MlDbError> {
    let store = store.as_ref().map(RustAutoOpaque::blocking_read);
    let cities = cities.as_ref().map(RustAutoOpaque::blocking_read);
    Ok(memories::compute_smart_memories_from_store(
        &request,
        &periods,
        store.as_deref().map(|store| &store.inner),
        cities.as_deref().map(|cities| &cities.0 as &dyn CityLookup),
    )?)
}

pub fn compute_simple_memories(request: MemoriesRequest, period: Period) -> Vec<Memory> {
    memories::compute_simple_memories(&request, period)
}

pub fn compute_all_trip_memories(
    request: MemoriesRequest,
    period: Period,
    cities: Option<RustAutoOpaque<LocationIndex>>,
    detection: TripDetection,
) -> Vec<Memory> {
    let cities = cities.as_ref().map(RustAutoOpaque::blocking_read);
    memories::compute_all_trip_memories(
        &request,
        period,
        cities.as_deref().map(|cities| &cities.0 as &dyn CityLookup),
        detection,
    )
}
