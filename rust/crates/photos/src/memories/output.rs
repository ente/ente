use std::cmp::Ordering;

use ente_location::Coordinate;

use super::MAX_MEMORY_ITEMS;
use super::calendar::{LocalDate, MICROS_PER_DAY};
use super::input::Period;
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
    pub first_date_to_show: MemoryBoundary,
    pub last_date_to_show: MemoryBoundary,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MemoryBoundary {
    Timestamp(i64),
    CalendarDate(LocalDate),
}

impl From<i64> for MemoryBoundary {
    fn from(timestamp: i64) -> Self {
        Self::Timestamp(timestamp)
    }
}

impl From<LocalDate> for MemoryBoundary {
    fn from(date: LocalDate) -> Self {
        Self::CalendarDate(date)
    }
}

impl MemoryBoundary {
    fn compare_to(self, period: Period) -> Ordering {
        match self {
            Self::Timestamp(timestamp) => timestamp.cmp(&period.now),
            Self::CalendarDate(date) => {
                (date.days_since_epoch() * MICROS_PER_DAY).cmp(&period.local_now())
            }
        }
    }
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
        first_date_to_show: impl Into<MemoryBoundary>,
        last_date_to_show: impl Into<MemoryBoundary>,
    ) -> Self {
        let mut memory = Self::uncapped(kind, photos, first_date_to_show, last_date_to_show);
        memory.file_ids.truncate(MAX_MEMORY_ITEMS);
        memory
    }

    pub(super) fn uncapped(
        kind: MemoryKind,
        photos: &[&Photo],
        first_date_to_show: impl Into<MemoryBoundary>,
        last_date_to_show: impl Into<MemoryBoundary>,
    ) -> Self {
        Self {
            kind,
            file_ids: photos.iter().map(|photo| photo.id).collect(),
            first_date_to_show: first_date_to_show.into(),
            last_date_to_show: last_date_to_show.into(),
        }
    }

    pub(super) fn is_shown_at(&self, period: Period) -> bool {
        self.first_date_to_show.compare_to(period).is_le()
            && self.last_date_to_show.compare_to(period).is_ge()
    }
}

#[cfg(test)]
mod tests {
    use super::{LocalDate, Memory, MemoryKind, Period};
    use crate::memories::tests::micros;

    #[test]
    fn calendar_window_visibility_uses_the_offsets_at_the_observed_instants() {
        let memory = Memory::new(
            MemoryKind::OnThisDay,
            &[],
            LocalDate::new(2026, 11, 1),
            LocalDate::new(2026, 11, 2),
        );
        for (now, offset, visible) in [
            ("2026-11-01T03:59:59", -14_400, false),
            ("2026-11-01T04:00:00", -14_400, true),
            ("2026-11-02T04:30:00", -18_000, true),
            ("2026-11-02T05:00:00", -18_000, true),
            ("2026-11-02T05:00:01", -18_000, false),
        ] {
            assert_eq!(
                memory.is_shown_at(Period {
                    now: micros(now),
                    utc_offset_seconds: offset,
                }),
                visible,
                "{now}"
            );
        }
    }

    #[test]
    fn mixed_windows_preserve_the_timestamp_start_and_local_date_end() {
        let memory = Memory::new(
            MemoryKind::OnThisDay,
            &[],
            micros("2026-10-15T12:34:56"),
            LocalDate::new(2026, 11, 1),
        );
        for (now, visible) in [
            ("2026-10-15T12:34:55", false),
            ("2026-10-15T12:34:56", true),
            ("2026-11-01T04:00:00", true),
            ("2026-11-01T04:00:01", false),
        ] {
            assert_eq!(
                memory.is_shown_at(Period {
                    now: micros(now),
                    utc_offset_seconds: -14_400,
                }),
                visible,
                "{now}"
            );
        }
    }
}
