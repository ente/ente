mod bases;
mod surface;

use std::cmp;
use std::collections::HashSet;
use std::mem;

use ente_location::Coordinate;

use super::MAX_MEMORY_ITEMS;
use super::calendar::{LocalDate, MICROS_PER_DAY};
use super::geo::{
    Cluster, Located, cluster_by_location, distance_km, is_within, mean_location, two_decimals,
};
use super::photo::Photo;
use super::places::Places;

pub(super) use bases::Base;
pub(super) use surface::{TripHistory, memories};

const MAX_TEMPORAL_GAP_DAYS: i64 = 15;
const TRIP_CLUSTER_RADIUS_KM: f64 = 25.0;
const CHAIN_HOP_DISTANCE_KM: f64 = 800.0;
const BASE_OVERLAP_RADIUS_KM: f64 = 10.0;
const MIN_TRIP_DAYS: i64 = 2;
const MAX_TRIP_DAYS: i64 = 30;
const MIN_TRIP_PHOTOS: usize = 20;
const MIN_CHAIN_CLUSTER_PHOTOS: usize = 5;
const MERGE_WINDOW_DAYS: i64 = 2;
const MERGE_MAX_DISTANCE_KM: f64 = 25.0;

pub(super) struct TripAnalysis<'p> {
    pub(super) bases: Vec<Base<'p>>,
    base_countries: HashSet<String>,
    trips: Vec<Trip<'p>>,
}

struct Trip<'p> {
    members: Vec<Located<'p>>,
    location: Coordinate,
    first: &'p Photo,
    last: &'p Photo,
    key: String,
}

impl<'p> Trip<'p> {
    fn new(
        mut members: Vec<Located<'p>>,
        location: Coordinate,
        first: &'p Photo,
        last: &'p Photo,
    ) -> Self {
        members.truncate(MAX_MEMORY_ITEMS);
        let key = format!(
            "trip_{}_{}_{}_{}",
            two_decimals(location.latitude),
            two_decimals(location.longitude),
            first.creation_time / MICROS_PER_DAY,
            last.creation_time / MICROS_PER_DAY
        );
        Self {
            members,
            location,
            first,
            last,
            key,
        }
    }

    fn average_creation_time(&self) -> i64 {
        (self.first.creation_time + self.last.creation_time) / 2
    }

    fn year(&self) -> i32 {
        LocalDate::of_local_time((self.first.local_time + self.last.local_time) / 2).year
    }
}

pub(super) fn analyze<'p>(members: &[Located<'p>], now: i64, places: &Places) -> TripAnalysis<'p> {
    let bases = bases::detect(members, now);
    let base_countries = bases
        .iter()
        .filter_map(|base| places.normalized_country(&base.members))
        .collect();
    let mut trips = Vec::new();
    for block in segment_away_from_bases(members, &bases) {
        let clusters = merge_chained_clusters(cluster_by_location(block, TRIP_CLUSTER_RADIUS_KM));
        trips.extend(
            clusters
                .into_iter()
                .filter_map(|cluster| valid_trip(cluster, &bases)),
        );
    }
    TripAnalysis {
        bases,
        base_countries,
        trips: merge_nearby_trips(trips),
    }
}

fn valid_trip<'p>(cluster: Cluster<'p>, bases: &[Base]) -> Option<Trip<'p>> {
    let location = cluster.center;
    let mut members = cluster.members;
    members.sort_by_key(|member| (member.photo.creation_time, member.photo.id));
    let first = members.first()?.photo;
    let last = members.last()?.photo;
    let span_days = (last.creation_time - first.creation_time) / MICROS_PER_DAY;
    (members.len() >= MIN_TRIP_PHOTOS
        && span_days >= MIN_TRIP_DAYS
        && !is_near_any_base(location, bases))
    .then(|| Trip::new(members, location, first, last))
}

fn is_near_any_base(location: Coordinate, bases: &[Base]) -> bool {
    bases
        .iter()
        .any(|base| is_within(base.location, location, BASE_OVERLAP_RADIUS_KM))
}

fn segment_away_from_bases<'p>(members: &[Located<'p>], bases: &[Base]) -> Vec<Vec<Located<'p>>> {
    let mut blocks = Vec::new();
    let mut block: Vec<Located> = Vec::new();
    let mut returned_to_base = false;
    for &member in members {
        if is_near_any_base(member.location, bases) {
            returned_to_base |= !block.is_empty();
            continue;
        }
        if let Some(previous) = block.last() {
            let gap_days =
                (member.photo.creation_time - previous.photo.creation_time) / MICROS_PER_DAY;
            if gap_days > MAX_TEMPORAL_GAP_DAYS || returned_to_base {
                blocks.push(mem::take(&mut block));
            }
        }
        block.push(member);
        returned_to_base = false;
    }
    if !block.is_empty() {
        blocks.push(block);
    }
    blocks
}

fn merge_chained_clusters(clusters: Vec<Cluster<'_>>) -> Vec<Cluster<'_>> {
    if clusters.len() <= 1
        || clusters
            .iter()
            .all(|cluster| cluster.members.len() < MIN_CHAIN_CLUSTER_PHOTOS)
    {
        return clusters;
    }
    let mut clusters = clusters;
    clusters.sort_by_key(|cluster| {
        cluster
            .members
            .iter()
            .map(|member| (member.photo.creation_time, member.photo.id))
            .min()
    });
    let (chainable, too_small): (Vec<Cluster>, Vec<Cluster>) = clusters
        .into_iter()
        .partition(|cluster| cluster.members.len() >= MIN_CHAIN_CLUSTER_PHOTOS);
    let mut merged = Vec::new();
    let mut chainable = chainable
        .into_iter()
        .map(|cluster| Cluster::from_members(cluster.members));
    let Some(mut current) = chainable.next() else {
        return too_small;
    };
    for next in chainable {
        let gap_days = (next.first_creation_time() - current.last_creation_time()) / MICROS_PER_DAY;
        let span_days = (next.last_creation_time().max(current.last_creation_time())
            - next
                .first_creation_time()
                .min(current.first_creation_time()))
            / MICROS_PER_DAY;
        if distance_km(current.center, next.center) <= CHAIN_HOP_DISTANCE_KM
            && gap_days <= MERGE_WINDOW_DAYS
            && span_days <= MAX_TRIP_DAYS
        {
            current.absorb(next);
        } else {
            merged.push(mem::replace(&mut current, next));
        }
    }
    merged.push(current);
    merged.extend(too_small);
    merged
}

fn merge_nearby_trips(mut trips: Vec<Trip<'_>>) -> Vec<Trip<'_>> {
    trips.sort_by_key(|trip| (trip.first.creation_time, trip.first.id));
    let mut merged: Vec<Trip> = Vec::new();
    for trip in trips {
        let Some(position) = merged.iter().position(|other| should_merge(&trip, other)) else {
            merged.push(trip);
            continue;
        };
        let other = merged.remove(position);
        merged.insert(position, combined(other, trip));
    }
    merged
}

fn combined<'p>(other: Trip<'p>, trip: Trip<'p>) -> Trip<'p> {
    let first = cmp::min_by_key(other.first, trip.first, |photo| {
        (photo.creation_time, photo.id)
    });
    let last = cmp::max_by_key(other.last, trip.last, |photo| {
        (photo.creation_time, photo.id)
    });
    let mut members = other.members;
    members.extend(trip.members);
    let location = mean_location(&members);
    Trip::new(members, location, first, last)
}

fn should_merge(trip: &Trip, other: &Trip) -> bool {
    let window = MERGE_WINDOW_DAYS * MICROS_PER_DAY;
    let first = trip.first.creation_time.min(other.first.creation_time);
    let last = trip.last.creation_time.max(other.last.creation_time);
    trip.first.creation_time < other.last.creation_time + window
        && trip.last.creation_time > other.first.creation_time - window
        && distance_km(trip.location, other.location) < MERGE_MAX_DISTANCE_KM
        && (last - first) / MICROS_PER_DAY <= MAX_TRIP_DAYS
}

#[cfg(test)]
mod tests {
    use ente_location::{City, CityMatch, Coordinate, CountryCode};

    use crate::memories::calendar::MICROS_PER_DAY;
    use crate::memories::geo::distance_km;
    use crate::memories::tests::{located_file, micros, period};
    use crate::memories::{
        BaseMemory, CachedTrip, CityLookup, MemoriesRequest, Memory, MemoryFile, MemoryKind,
        ShownTrip, SmartMemories, TripMemory, compute_smart_memories,
    };

    const AMSTERDAM: (f64, f64) = (52.37, 4.90);
    const BORDEAUX: (f64, f64) = (44.8378, -0.5792);
    const PARIS: (f64, f64) = (48.8566, 2.3522);
    const LYON: (f64, f64) = (45.764, 4.8357);
    const MARSEILLE: (f64, f64) = (43.2965, 5.3698);
    const ROME: (f64, f64) = (41.9028, 12.4964);
    const LISBON: (f64, f64) = (38.7223, -9.1393);
    const NOW: &str = "2026-10-29T09:00:00";
    const HOUR: i64 = MICROS_PER_DAY / 24;

    struct Cities(Vec<(&'static str, &'static str, (f64, f64))>);

    impl CityLookup for Cities {
        fn group_cities(&self, coordinates: &[Coordinate]) -> Vec<CityMatch> {
            self.0
                .iter()
                .enumerate()
                .map(
                    |(index, &(name, country, (latitude, longitude)))| CityMatch {
                        city: City {
                            point_index: index as u32,
                            source_id: index as u32,
                            name: name.to_owned(),
                            country_name: country.to_owned(),
                            country_code: CountryCode::from_bytes(*b"FR").unwrap(),
                            latitude,
                            longitude,
                            rank: 0,
                        },
                        coordinate_indices: coordinates
                            .iter()
                            .enumerate()
                            .filter(|(_, coordinate)| {
                                distance_km(**coordinate, Coordinate::new(latitude, longitude))
                                    < 30.0
                            })
                            .map(|(position, _)| position as u32)
                            .collect(),
                    },
                )
                .filter(|group| !group.coordinate_indices.is_empty())
                .collect()
        }
    }

    fn stay(first_id: i64, start: &str, count: i64, place: (f64, f64)) -> Vec<MemoryFile> {
        let start = micros(start);
        (0..count)
            .map(|index| located_file(first_id + index, start + index * 4 * HOUR, place))
            .collect()
    }

    fn home(place: (f64, f64), away: &[&[MemoryFile]]) -> Vec<MemoryFile> {
        let first = micros("2023-01-01T12:00:00");
        let last = micros("2026-10-25T12:00:00");
        (0..)
            .map(|index| first + index * 3 * MICROS_PER_DAY)
            .take_while(|&time| time <= last)
            .filter(|&time| {
                away.iter().all(|files| {
                    let start = files[0].creation_time - MICROS_PER_DAY;
                    let end = files[files.len() - 1].creation_time + MICROS_PER_DAY;
                    !(start..=end).contains(&time)
                })
            })
            .enumerate()
            .map(|(index, time)| located_file(100_000 + index as i64, time, place))
            .collect()
    }

    fn compute(
        request: &MemoriesRequest,
        periods: &[&str],
        cities: Option<&Cities>,
    ) -> SmartMemories {
        let periods: Vec<_> = periods.iter().map(|now| period(now)).collect();
        compute_smart_memories(
            request,
            &periods,
            None,
            cities.map(|cities| cities as &dyn CityLookup),
        )
        .unwrap()
    }

    fn trips(memories: &[Memory]) -> Vec<&TripMemory> {
        memories
            .iter()
            .filter_map(|memory| match &memory.kind {
                MemoryKind::Trip(trip) => Some(trip),
                _ => None,
            })
            .collect()
    }

    fn trip_keys(memories: &[Memory]) -> Vec<&str> {
        trips(memories)
            .into_iter()
            .map(|trip| trip.key.as_str())
            .collect()
    }

    const PARIS_KEY: &str = "trip_48.86_2.35_20157_20161";
    const ROME_KEY: &str = "trip_41.90_12.50_20022_20026";
    const LISBON_KEY: &str = "trip_38.72_-9.14_19509_19513";

    fn three_trips() -> MemoriesRequest {
        let paris = stay(1, "2025-03-10T08:00:00", 24, PARIS);
        let rome = stay(100, "2024-10-26T08:00:00", 24, ROME);
        let lisbon = stay(200, "2023-06-01T08:00:00", 24, LISBON);
        let mut files = home(AMSTERDAM, &[&paris, &rome, &lisbon]);
        files.extend(paris);
        files.extend(rome);
        files.extend(lisbon);
        MemoriesRequest {
            files,
            ..MemoriesRequest::default()
        }
    }

    fn shown(key: Option<&str>, place: (f64, f64), days_ago: i64) -> ShownTrip {
        ShownTrip {
            key: key.map(str::to_owned),
            location: Coordinate::new(place.0, place.1),
            last_time_shown: micros(NOW) - days_ago * MICROS_PER_DAY,
        }
    }

    #[test]
    fn two_trip_slots_go_to_the_trip_at_its_anniversary_then_the_nearest_other_trip() {
        let result = compute(&three_trips(), &[NOW], None);

        let memories = &result.periods[0];
        assert_eq!(trip_keys(memories), [ROME_KEY, PARIS_KEY]);
        let rome = trips(memories)[0];
        assert_eq!((rome.year, rome.location_name.as_deref()), (2024, None));
        let rome_memory = memories
            .iter()
            .find(|memory| matches!(&memory.kind, MemoryKind::Trip(trip) if trip.key == ROME_KEY))
            .unwrap();
        assert_eq!(rome_memory.first_date_to_show, micros(NOW));
        assert_eq!(
            rome_memory.last_date_to_show,
            micros(NOW) + 10 * MICROS_PER_DAY
        );
        assert_eq!(rome_memory.file_ids.len(), 10);

        assert_eq!(result.base_locations.len(), 1);
        assert!(result.base_locations[0].is_current);
    }

    #[test]
    fn active_and_recently_shown_trips_wait_for_their_cooldown() {
        let mut request = three_trips();
        request.cached_trips = vec![CachedTrip {
            identity_key: format!("trip:{ROME_KEY}"),
            first_date_to_show: micros(NOW) - 2 * MICROS_PER_DAY,
            last_date_to_show: micros(NOW) + 8 * MICROS_PER_DAY,
        }];
        request.shown_trips = vec![shown(Some(PARIS_KEY), PARIS, 30)];
        assert_eq!(
            trip_keys(&compute(&request, &[NOW], None).periods[0]),
            [LISBON_KEY]
        );

        request.shown_trips.push(shown(None, LISBON, 10));
        assert!(trip_keys(&compute(&request, &[NOW], None).periods[0]).is_empty());

        request.local_gallery_mode = true;
        request.cached_trips.clear();
        request.shown_trips.push(shown(Some(ROME_KEY), ROME, 5));
        assert_eq!(
            trip_keys(&compute(&request, &[NOW], None).periods[0]),
            [ROME_KEY]
        );
    }

    #[test]
    fn the_next_period_counts_trips_shown_in_the_current_one() {
        let result = compute(&three_trips(), &[NOW, "2026-11-01T09:00:00"], None);

        assert_eq!(trip_keys(&result.periods[0]), [ROME_KEY, PARIS_KEY]);
        assert!(trip_keys(&result.periods[1]).is_empty());
    }

    #[test]
    fn surfacing_everything_lists_bases_then_every_old_enough_trip() {
        let request = MemoriesRequest {
            surface_all: true,
            ..three_trips()
        };

        let memories = &compute(&request, &[NOW], None).periods[0];

        let places: Vec<&MemoryKind> = memories
            .iter()
            .map(|memory| &memory.kind)
            .filter(|kind| matches!(kind, MemoryKind::Trip(_) | MemoryKind::Base(_)))
            .collect();
        assert!(matches!(
            places[0],
            MemoryKind::Base(BaseMemory {
                is_current: true,
                ..
            })
        ));
        assert_eq!(trip_keys(memories), [LISBON_KEY, ROME_KEY, PARIS_KEY]);
    }

    #[test]
    fn hops_between_cities_chain_into_one_trip_but_a_return_home_splits_it() {
        let paris = stay(1, "2025-03-10T08:00:00", 12, PARIS);
        let lyon = stay(20, "2025-03-12T08:00:00", 12, LYON);
        let mut files = home(AMSTERDAM, &[&paris, &lyon]);
        files.extend(paris.clone());
        files.extend(lyon);
        let request = MemoriesRequest {
            files,
            surface_all: true,
            ..MemoriesRequest::default()
        };
        let keys = trip_keys(&compute(&request, &[NOW], None).periods[0])
            .into_iter()
            .map(str::to_owned)
            .collect::<Vec<_>>();
        assert_eq!(keys.len(), 1);
        assert!(keys[0].starts_with("trip_47.31_3.59_"), "{keys:?}");

        let later = stay(40, "2025-03-12T08:00:00", 12, PARIS);
        let mut files = home(AMSTERDAM, &[&paris, &later]);
        files.push(located_file(99, micros("2025-03-12T06:00:00"), AMSTERDAM));
        files.extend(paris);
        files.extend(later);
        let request = MemoriesRequest {
            files,
            surface_all: true,
            ..MemoriesRequest::default()
        };
        assert!(trip_keys(&compute(&request, &[NOW], None).periods[0]).is_empty());
    }

    #[test]
    fn trips_keep_their_first_hundred_photos_when_merging_and_picking() {
        let long_stay = stay(1, "2025-03-01T08:00:00", 120, (48.80, 2.30));
        let short_stay = stay(200, "2025-03-21T16:00:00", 20, (48.90, 2.30));
        let mut files = home(AMSTERDAM, &[&long_stay, &short_stay]);
        files.push(located_file(199, micros("2025-03-21T10:00:00"), AMSTERDAM));
        files.extend(long_stay);
        files.extend(short_stay);
        let request = MemoriesRequest {
            files,
            surface_all: true,
            ..MemoriesRequest::default()
        };

        let result = compute(&request, &[NOW], None);

        let memories = &result.periods[0];
        let keys = trip_keys(memories);
        assert_eq!(keys.len(), 1);
        assert!(keys[0].starts_with("trip_48.82_2.30_"), "{keys:?}");
        let trip = memories
            .iter()
            .find(|memory| matches!(memory.kind, MemoryKind::Trip(_)))
            .unwrap();
        assert!(trip.file_ids.iter().all(|id| (1..=100).contains(id)));
    }

    #[test]
    fn trip_keys_keep_negative_zero_only_where_dart_does() {
        let keys = |files: Vec<MemoryFile>| {
            let request = MemoriesRequest {
                files,
                surface_all: true,
                ..MemoriesRequest::default()
            };
            trip_keys(&compute(&request, &[NOW], None).periods[0])
                .into_iter()
                .map(str::to_owned)
                .collect::<Vec<_>>()
        };
        let equator = stay(1, "2025-03-10T08:00:00", 24, (-0.0, 30.0));

        assert_eq!(keys(equator.clone()), ["trip_-0.00_30.00_20157_20161"]);

        let mut files = equator;
        files.push(located_file(
            100,
            micros("2025-03-14T08:00:00"),
            (5.0, 50.0),
        ));
        assert_eq!(keys(files), ["trip_0.00_30.00_20157_20161"]);
    }

    #[test]
    fn trips_are_named_after_their_main_city_or_a_country_away_from_home() {
        let cities = Cities(vec![
            ("Paris", "France", PARIS),
            ("Lyon", "France", LYON),
            ("Marseille", "France", MARSEILLE),
            ("Bordeaux", "France", BORDEAUX),
            ("Amsterdam", "Netherlands", AMSTERDAM),
        ]);
        let tour = |home_place| {
            let paris = stay(1, "2025-03-10T08:00:00", 8, PARIS);
            let lyon = stay(20, "2025-03-11T16:00:00", 8, LYON);
            let marseille = stay(40, "2025-03-13T00:00:00", 8, MARSEILLE);
            let mut files = home(home_place, &[&paris, &marseille]);
            files.extend(paris);
            files.extend(lyon);
            files.extend(marseille);
            MemoriesRequest {
                files,
                surface_all: true,
                ..MemoriesRequest::default()
            }
        };
        let name = |request: &MemoriesRequest| {
            let result = compute(request, &[NOW], Some(&cities));
            trips(&result.periods[0])[0].location_name.clone()
        };

        assert_eq!(name(&tour(AMSTERDAM)).as_deref(), Some("France"));
        assert_eq!(name(&tour(BORDEAUX)), None);

        let paris = stay(1, "2025-03-10T08:00:00", 24, PARIS);
        let mut files = home(AMSTERDAM, &[&paris]);
        files.extend(paris);
        let request = MemoriesRequest {
            files,
            surface_all: true,
            ..MemoriesRequest::default()
        };
        assert_eq!(name(&request).as_deref(), Some("Paris"));
    }
}
