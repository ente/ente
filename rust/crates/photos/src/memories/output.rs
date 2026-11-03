use ente_location::Coordinate;

use super::MAX_MEMORY_ITEMS;
use super::calendar::LocalDate;
use super::photo::Photo;

#[derive(Clone, Debug, PartialEq)]
pub struct SmartMemories {
    pub periods: Vec<Vec<Memory>>,
    pub base_locations: Vec<BaseLocation>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct BaseLocation {
    pub file_ids: Vec<i64>,
    pub location: Coordinate,
    pub is_current: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Memory {
    pub kind: MemoryKind,
    pub file_ids: Vec<i64>,
    pub first_date_to_show: i64,
    pub last_date_to_show: i64,
}

#[derive(Clone, Debug, PartialEq)]
pub enum MemoryKind {
    OnThisDay,
    People(PeopleMemory),
    Trip(TripMemory),
    Base(BaseMemory),
    Clip(ClipMemoryType),
    Time(TimeMemory),
    Filler { years_ago: i32 },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PeopleMemory {
    pub person_id: String,
    pub is_unnamed_cluster: bool,
    pub memory_type: PeopleMemoryType,
    pub activity: Option<PeopleActivity>,
    pub birthday: Option<Birthday>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PeopleMemoryType {
    YouAndThem,
    DoingSomethingTogether,
    Spotlight,
    LastTimeYouSawThem,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum PeopleActivity {
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

impl PeopleActivity {
    pub const ALL: [Self; 10] = [
        Self::Admiring,
        Self::Embracing,
        Self::Party,
        Self::Hiking,
        Self::Feast,
        Self::Selfies,
        Self::Posing,
        Self::Background,
        Self::Sports,
        Self::Roadtrip,
    ];
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Birthday {
    pub is_upcoming: bool,
    pub new_age: i32,
}

#[derive(Clone, Debug, PartialEq)]
pub struct TripMemory {
    pub location: Coordinate,
    pub location_name: Option<String>,
    pub year: i32,
    pub key: String,
}

#[derive(Clone, Debug, PartialEq)]
pub struct BaseMemory {
    pub location: Coordinate,
    pub location_name: Option<String>,
    pub is_current: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ClipMemoryType {
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

impl ClipMemoryType {
    pub const ALL: [Self; 48] = [
        Self::Sunrise,
        Self::Mountains,
        Self::Greenery,
        Self::Beach,
        Self::City,
        Self::Moon,
        Self::OnTheRoad,
        Self::Food,
        Self::Pets,
        Self::Festivities,
        Self::SnowAdventures,
        Self::Waterfalls,
        Self::Wildlife,
        Self::Flowers,
        Self::NightLights,
        Self::Architecture,
        Self::AutumnColors,
        Self::DesertDreams,
        Self::Stargazing,
        Self::Lakeside,
        Self::RainyDays,
        Self::SportsAction,
        Self::StreetArt,
        Self::FamilyMoments,
        Self::Fireworks,
        Self::HistoricSites,
        Self::TropicalParadise,
        Self::ForestTrails,
        Self::CitySunsets,
        Self::ColorfulMarkets,
        Self::CozyCafes,
        Self::VintageVibes,
        Self::AerialViews,
        Self::ArtisticPortraits,
        Self::StreetFood,
        Self::RiverCruises,
        Self::PlayfulKids,
        Self::CoastalCliffs,
        Self::CandidLaughter,
        Self::GroupSelfies,
        Self::BirthdayJoy,
        Self::WeddingMoments,
        Self::GoldenHourPortraits,
        Self::ConcertNights,
        Self::PoolDays,
        Self::PicnicDays,
        Self::CampingMoments,
        Self::BabySmiles,
    ];
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TimeMemory {
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

impl Memory {
    pub(super) fn new(
        kind: MemoryKind,
        photos: &[&Photo],
        first_date_to_show: i64,
        last_date_to_show: i64,
    ) -> Self {
        Self {
            kind,
            file_ids: photos
                .iter()
                .take(MAX_MEMORY_ITEMS)
                .map(|photo| photo.id)
                .collect(),
            first_date_to_show,
            last_date_to_show,
        }
    }

    pub(super) fn is_shown_at(&self, time: i64) -> bool {
        (self.first_date_to_show..=self.last_date_to_show).contains(&time)
    }
}
