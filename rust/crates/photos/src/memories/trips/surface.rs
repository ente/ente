use std::cmp::Reverse;
use std::collections::HashSet;

use ente_location::Coordinate;

use super::{Base, Trip, TripAnalysis};
use crate::memories::UPDATE_FREQUENCY_DAYS;
use crate::memories::calendar::{LocalDate, MICROS_PER_DAY};
use crate::memories::geo::distance_km;
use crate::memories::input::{CachedTrip, MemoriesRequest, Period, ShownTrip};
use crate::memories::output::{BaseMemory, Memory, MemoryBoundary, MemoryKind, TripMemory};
use crate::memories::photo::{Photo, sort_chronologically};
use crate::memories::places::Places;
use crate::memories::selector::Selector;
use crate::ml_store::Result;

const TRIP_SURFACE_SLOTS: usize = 2;
const TRIP_SHOW_TIMEOUT_DAYS: i64 = 40 * UPDATE_FREQUENCY_DAYS;
const TRIP_DISPLAY_DAYS: i64 = 10;
const SEASONAL_TRIP_BAND_DAYS: i64 = 45;
const MINIMUM_TRIP_AGE_DAYS: i64 = 365;
const LEGACY_SHOWN_TRIP_RADIUS_KM: f64 = 10.0;
const OLDER_KEY_MAX_DISTANCE_KM: f64 = 50.0;

pub(in crate::memories) struct TripHistory<'r> {
    shown: &'r [ShownTrip],
    cached: Vec<CachedTrip>,
}

struct Candidate<'a, 'p> {
    trip: &'a Trip<'p>,
    last_shown: Option<i64>,
    cooldown_expired: bool,
    anniversary_distance_days: i64,
}

impl<'r> TripHistory<'r> {
    pub(in crate::memories) fn new(shown: &'r [ShownTrip], cached: &[CachedTrip]) -> Self {
        Self {
            shown,
            cached: cached.to_vec(),
        }
    }

    pub(in crate::memories) fn record(&mut self, memories: &[Memory]) {
        for memory in memories {
            if let (
                MemoryKind::Trip(trip),
                MemoryBoundary::Timestamp(first_date_to_show),
                MemoryBoundary::Timestamp(last_date_to_show),
            ) = (
                &memory.kind,
                memory.first_date_to_show,
                memory.last_date_to_show,
            ) {
                self.cached.push(CachedTrip {
                    identity_key: identity_key(&trip.key),
                    first_date_to_show,
                    last_date_to_show,
                });
            }
        }
    }

    fn active_identity_keys(&self, now: i64) -> Vec<&str> {
        let mut seen = HashSet::new();
        self.cached
            .iter()
            .filter(|cached| (cached.first_date_to_show..cached.last_date_to_show).contains(&now))
            .map(|cached| cached.identity_key.as_str())
            .filter(|key| seen.insert(*key))
            .take(TRIP_SURFACE_SLOTS)
            .collect()
    }

    fn last_shown(&self, trip: &Trip, current: &HashSet<&str>) -> Option<i64> {
        self.shown
            .iter()
            .filter(|shown| match &shown.key {
                Some(key) => is_same_trip(key, trip, current),
                None => distance_km(trip.location, shown.location) < LEGACY_SHOWN_TRIP_RADIUS_KM,
            })
            .map(|shown| shown.last_time_shown)
            .max()
    }
}

pub(in crate::memories) fn memories(
    analysis: &TripAnalysis,
    history: &TripHistory,
    period: Period,
    request: &MemoriesRequest,
    places: &Places,
    selector: &mut Selector,
) -> Result<Vec<Memory>> {
    let cutoff = period.now - MINIMUM_TRIP_AGE_DAYS * MICROS_PER_DAY;
    let trips: Vec<&Trip> = analysis
        .trips
        .iter()
        .filter(|trip| trip.average_creation_time() < cutoff)
        .collect();
    if request.surface_all {
        return surface_all(analysis, &trips, period, places, selector);
    }
    let current: HashSet<&str> = analysis
        .trips
        .iter()
        .map(|trip| trip.key.as_str())
        .collect();
    let selected = scheduled(
        &trips,
        &current,
        history,
        period,
        request.local_gallery_mode,
    );
    let last_date_to_show = period.now + TRIP_DISPLAY_DAYS * MICROS_PER_DAY;
    selected
        .into_iter()
        .map(|trip| trip_memory(trip, selector, period.now, last_date_to_show))
        .collect()
}

pub(in crate::memories) fn all_memories(
    analysis: &TripAnalysis,
    places: &Places,
    period: Period,
) -> Vec<Memory> {
    let last_date_to_show = period.now + UPDATE_FREQUENCY_DAYS * MICROS_PER_DAY;
    let bases = analysis.bases.iter().map(|base| {
        let mut photos: Vec<&Photo> = base.members.iter().map(|member| member.photo).collect();
        sort_chronologically(&mut photos);
        Memory::uncapped(
            base_kind(base, places),
            &photos,
            period.now,
            last_date_to_show,
        )
    });
    let trips = analysis.trips.iter().rev().map(|trip| {
        let mut photos: Vec<&Photo> = trip.members.iter().map(|member| member.photo).collect();
        sort_chronologically(&mut photos);
        Memory::uncapped(trip_kind(trip), &photos, period.now, last_date_to_show)
    });
    bases.chain(trips).collect()
}

fn surface_all(
    analysis: &TripAnalysis,
    trips: &[&Trip],
    period: Period,
    places: &Places,
    selector: &mut Selector,
) -> Result<Vec<Memory>> {
    let last_date_to_show = period.now + UPDATE_FREQUENCY_DAYS * MICROS_PER_DAY;
    let bases = analysis.bases.iter().map(|base| {
        let photos: Vec<&Photo> = base.members.iter().map(|member| member.photo).collect();
        Memory::new(
            base_kind(base, places),
            &photos,
            period.now,
            last_date_to_show,
        )
    });
    let mut memories: Vec<Memory> = bases.collect();
    for trip in trips {
        memories.push(trip_memory(trip, selector, period.now, last_date_to_show)?);
    }
    Ok(memories)
}

fn scheduled<'a, 'p>(
    trips: &[&'a Trip<'p>],
    current: &HashSet<&str>,
    history: &TripHistory,
    period: Period,
    local_gallery_mode: bool,
) -> Vec<&'a Trip<'p>> {
    let active = history.active_identity_keys(period.now);
    let slots = TRIP_SURFACE_SLOTS.saturating_sub(active.len());
    if slots == 0 || trips.is_empty() {
        return Vec::new();
    }
    let candidates: Vec<Candidate> = trips
        .iter()
        .filter(|trip| {
            !active
                .iter()
                .any(|identity_key| is_same_trip(trip_key(identity_key), trip, current))
        })
        .map(|&trip| {
            let last_shown = history.last_shown(trip, current);
            Candidate {
                trip,
                last_shown,
                cooldown_expired: last_shown.is_none_or(|shown| {
                    period.now - shown >= TRIP_SHOW_TIMEOUT_DAYS * MICROS_PER_DAY
                }),
                anniversary_distance_days: anniversary_distance_days(trip, period),
            }
        })
        .collect();

    let mut seasonal: Vec<&Candidate> = candidates
        .iter()
        .filter(|candidate| {
            candidate.cooldown_expired
                && candidate.anniversary_distance_days <= SEASONAL_TRIP_BAND_DAYS
        })
        .collect();
    seasonal.sort_by_key(|candidate| seasonal_rank(candidate));
    let mut selected: Vec<&Candidate> = seasonal.into_iter().take(slots).collect();

    let mut evergreen: Vec<&Candidate> = candidates
        .iter()
        .filter(|candidate| {
            candidate.cooldown_expired
                && !selected
                    .iter()
                    .any(|chosen| chosen.trip.key == candidate.trip.key)
        })
        .collect();
    evergreen.sort_by_key(|candidate| evergreen_rank(candidate));
    let remaining = slots - selected.len();
    selected.extend(evergreen.into_iter().take(remaining));

    if local_gallery_mode && active.is_empty() && selected.is_empty() {
        let mut fallback: Vec<&Candidate> = candidates
            .iter()
            .filter(|candidate| candidate.anniversary_distance_days <= SEASONAL_TRIP_BAND_DAYS)
            .collect();
        if fallback.is_empty() {
            fallback = candidates.iter().collect();
            fallback.sort_by_key(|candidate| evergreen_rank(candidate));
        } else {
            fallback.sort_by_key(|candidate| seasonal_rank(candidate));
        }
        selected.extend(fallback.into_iter().take(1));
    }
    selected
        .into_iter()
        .map(|candidate| candidate.trip)
        .collect()
}

fn seasonal_rank<'c>(candidate: &'c Candidate) -> (bool, i64, Option<i64>, Reverse<i64>, &'c str) {
    (
        !candidate.cooldown_expired,
        candidate.anniversary_distance_days,
        candidate.last_shown,
        Reverse(candidate.trip.average_creation_time()),
        &candidate.trip.key,
    )
}

fn evergreen_rank<'c>(candidate: &'c Candidate) -> (bool, Option<i64>, i64, Reverse<i64>, &'c str) {
    (
        !candidate.cooldown_expired,
        candidate.last_shown,
        candidate.anniversary_distance_days,
        Reverse(candidate.trip.average_creation_time()),
        &candidate.trip.key,
    )
}

fn trip_memory(
    trip: &Trip,
    selector: &mut Selector,
    first_date_to_show: i64,
    last_date_to_show: i64,
) -> Result<Memory> {
    let photos: Vec<&Photo> = trip.members.iter().map(|member| member.photo).collect();
    Ok(Memory::new(
        trip_kind(trip),
        &selector.best(photos, None)?,
        first_date_to_show,
        last_date_to_show,
    ))
}

fn trip_kind(trip: &Trip) -> MemoryKind {
    MemoryKind::Trip(TripMemory {
        location: trip.location,
        location_name: trip.location_name.clone(),
        year: trip.year(),
        key: trip.key.clone(),
    })
}

fn base_kind(base: &Base, places: &Places) -> MemoryKind {
    MemoryKind::Base(BaseMemory {
        location: base.location,
        location_name: places.base_name(&base.members),
        is_current: base.is_current,
    })
}

fn anniversary_distance_days(trip: &Trip, period: Period) -> i64 {
    let now = period.local_now();
    let start = trip.first.local_time;
    let end = trip.last.local_time;
    let year_offset = LocalDate::of_local_time(end).year - LocalDate::of_local_time(start).year;
    let year = period.today().year;
    [year - 1, year, year + 1]
        .into_iter()
        .map(|start_year| {
            let projected_start = moved_to_year(start, start_year);
            let projected_end = moved_to_year(end, start_year + year_offset);
            if now < projected_start {
                (projected_start - now) / MICROS_PER_DAY
            } else if now > projected_end {
                (now - projected_end) / MICROS_PER_DAY
            } else {
                0
            }
        })
        .min()
        .unwrap_or_default()
}

fn moved_to_year(local_time: i64, year: i32) -> i64 {
    let date = LocalDate::of_local_time(local_time);
    let last_day_of_month = LocalDate::new(year, date.month + 1, 0).day;
    let moved = LocalDate {
        year,
        month: date.month,
        day: date.day.min(last_day_of_month),
    };
    moved.days_since_epoch() * MICROS_PER_DAY + local_time.rem_euclid(MICROS_PER_DAY)
}

fn identity_key(trip_key: &str) -> String {
    format!("trip:{trip_key}")
}

fn trip_key(identity_key: &str) -> &str {
    identity_key.strip_prefix("trip:").unwrap_or(identity_key)
}

fn is_same_trip(key: &str, trip: &Trip, current: &HashSet<&str>) -> bool {
    if key == trip.key {
        return true;
    }
    let (Some((first, last)), Some((trip_first, trip_last))) = (key_days(key), key_days(&trip.key))
    else {
        return false;
    };
    let contains =
        (first <= trip_first && trip_last <= last) || (trip_first <= first && last <= trip_last);
    let overlaps_nearby = first <= trip_last
        && trip_first <= last
        && key_location(key).is_some_and(|location| {
            distance_km(location, trip.location) < OLDER_KEY_MAX_DISTANCE_KM
        });
    !current.contains(key) && (contains || overlaps_nearby)
}

fn key_location(key: &str) -> Option<Coordinate> {
    let mut parts = key.strip_prefix("trip_")?.split('_');
    let latitude = parts.next()?.parse().ok()?;
    let longitude = parts.next()?.parse().ok()?;
    Some(Coordinate::new(latitude, longitude))
}

fn key_days(key: &str) -> Option<(i64, i64)> {
    let mut parts = key.strip_prefix("trip_")?.rsplitn(3, '_');
    let last = parts.next()?.parse().ok()?;
    let first = parts.next()?.parse().ok()?;
    Some((first, last))
}
