mod homes;
mod naming;

use std::collections::HashMap;
use std::mem;

use ente_location::{Coordinate, CountryCode};

use homes::Homes;

use super::{Base, Trip, TripAnalysis};
use crate::memories::calendar::MICROS_PER_DAY;
use crate::memories::geo::{Located, cluster_by_location, distance_km, mean_location};
use crate::memories::input::{CityLookup, Period};
use crate::memories::photo::Photo;
use crate::memories::places::Places;

const AWAY_MIN_KM: f64 = 50.0;
const OVERNIGHT_TRIP_MIN_PHOTOS: usize = 10;
const DAY_TRIP_MIN_PHOTOS: usize = 15;
const MAX_PHOTO_GAP_DAYS: i64 = 3;
const MAX_PHOTO_GAP_ABROAD_DAYS: i64 = 7;
const LONG_TRIP_DAYS: i64 = 30;
const DESTINATION_RADIUS_KM: f64 = 25.0;
const FREQUENT_VISITS: usize = 4;
const FREQUENT_WINDOW_DAYS: i64 = 182;
const SHARED_PHOTO_MAX_KM: f64 = 50.0;

#[derive(Clone, Copy)]
struct Placed<'p> {
    member: Located<'p>,
    urban_center: Option<u32>,
    country: Option<CountryCode>,
    joined: bool,
}

pub(in crate::memories) fn analyze<'p>(
    photos: &[Photo],
    located: &[Located<'p>],
    period: Period,
    places: &Places,
    lookup: Option<&dyn CityLookup>,
) -> TripAnalysis<'p> {
    let (own, shared) = by_owner(
        placed(located, places, lookup),
        photos.iter().any(|photo| !photo.shared),
    );
    let homes = Homes::detect(&own, lookup);
    let today = period.today().days_since_epoch();
    let bases = homes
        .areas()
        .into_iter()
        .map(|area| Base {
            members: area
                .iter()
                .flat_map(|home| home.members.iter().copied())
                .collect(),
            location: area[0].center,
            is_current: area.iter().any(|home| home.covers(today)),
        })
        .collect();
    let trips = trips(&own, &shared, &homes)
        .into_iter()
        .map(|points| {
            let members: Vec<Located> = points.iter().map(|point| point.member).collect();
            let mut trip = Trip::new(
                members.clone(),
                members,
                center(&points),
                points[0].member.photo,
                points[points.len() - 1].member.photo,
            );
            let home_countries = homes.countries_on(points[0].member.photo.date.days_since_epoch());
            trip.location_name = naming::trip_name(&points, places, &home_countries, lookup);
            trip
        })
        .collect();
    TripAnalysis { bases, trips }
}

fn placed<'p>(
    located: &[Located<'p>],
    places: &Places,
    lookup: Option<&dyn CityLookup>,
) -> Vec<Placed<'p>> {
    let coordinates: Vec<Coordinate> = located.iter().map(|member| member.location).collect();
    let urban_centers = lookup.map(|lookup| lookup.urban_centers(&coordinates));
    let countries = lookup.map(|lookup| lookup.countries(&coordinates));
    located
        .iter()
        .enumerate()
        .map(|(index, &member)| {
            let polygon = countries
                .as_ref()
                .and_then(|countries| countries.get(index).copied().flatten());
            let city = places.country_code(member.photo.id);
            Placed {
                member,
                urban_center: urban_centers
                    .as_ref()
                    .and_then(|urban_centers| urban_centers.get(index).copied().flatten()),
                country: match (polygon, city) {
                    (Some(polygon), Some(city)) if polygon != city => None,
                    (polygon, city) => polygon.or(city),
                },
                joined: false,
            }
        })
        .collect()
}

fn by_owner(points: Vec<Placed>, has_own_photos: bool) -> (Vec<Placed>, Vec<Placed>) {
    if !has_own_photos {
        return (points, Vec::new());
    }
    let (shared, own): (Vec<Placed>, Vec<Placed>) = points
        .into_iter()
        .partition(|point| point.member.photo.shared);
    (own, shared)
}

fn trips<'p>(own: &[Placed<'p>], shared: &[Placed<'p>], homes: &Homes) -> Vec<Vec<Placed<'p>>> {
    let mut visits = away_visits(own, homes);
    join_shared(&mut visits, shared);
    visits.retain(|visit| visit.len() >= OVERNIGHT_TRIP_MIN_PHOTOS);
    let frequent = frequent_visits(&visits);
    visits
        .into_iter()
        .zip(frequent)
        .filter(|(_, frequent)| !frequent)
        .flat_map(|(visit, _)| country_legs(visit))
        .filter(|leg| is_trip(leg))
        .collect()
}

fn away_visits<'p>(points: &[Placed<'p>], homes: &Homes) -> Vec<Vec<Placed<'p>>> {
    let mut visits = Vec::new();
    let mut visit: Vec<Placed> = Vec::new();
    let mut country = None;
    for &point in points {
        if homes.contains(&point) {
            if !visit.is_empty() {
                visits.push(mem::take(&mut visit));
            }
            continue;
        }
        if let Some(last) = visit.last() {
            let abroad = point.country.is_some_and(|point_country| {
                country == Some(point_country)
                    && !homes
                        .countries_on(point.member.photo.date.days_since_epoch())
                        .contains(&point_country)
            });
            let max_gap_days = if abroad {
                MAX_PHOTO_GAP_ABROAD_DAYS
            } else {
                MAX_PHOTO_GAP_DAYS
            };
            if point.member.photo.creation_time - last.member.photo.creation_time
                > max_gap_days * MICROS_PER_DAY
            {
                visits.push(mem::take(&mut visit));
            }
        }
        if visit.is_empty() {
            country = None;
        }
        country = point.country.or(country);
        visit.push(point);
    }
    if !visit.is_empty() {
        visits.push(visit);
    }
    visits
}

fn join_shared<'p>(visits: &mut [Vec<Placed<'p>>], shared: &[Placed<'p>]) {
    let mut joined: Vec<Vec<Placed<'p>>> = vec![Vec::new(); visits.len()];
    for &point in shared {
        let time = point.member.photo.creation_time;
        let Some(index) = visits
            .partition_point(|visit| visit[0].member.photo.creation_time <= time)
            .checked_sub(1)
        else {
            continue;
        };
        let visit = &visits[index];
        if time > visit[visit.len() - 1].member.photo.creation_time {
            continue;
        }
        let next = visit.partition_point(|own| own.member.photo.creation_time < time);
        if let Some(nearest) = visit[next.saturating_sub(1)..(next + 1).min(visit.len())]
            .iter()
            .min_by_key(|own| (own.member.photo.creation_time - time).abs())
            && distance_km(nearest.member.location, point.member.location) <= SHARED_PHOTO_MAX_KM
        {
            joined[index].push(Placed {
                joined: true,
                ..point
            });
        }
    }
    for (visit, joined) in visits.iter_mut().zip(joined) {
        if !joined.is_empty() {
            visit.extend(joined);
            visit.sort_by_key(|point| (point.member.photo.creation_time, point.member.photo.id));
        }
    }
}

fn frequent_visits(visits: &[Vec<Placed>]) -> Vec<bool> {
    let centers: Vec<Located> = visits
        .iter()
        .map(|visit| Located {
            photo: visit[0].member.photo,
            location: center(visit),
        })
        .collect();
    let mut destination_of: HashMap<i64, usize> = HashMap::new();
    for (destination, cluster) in
        cluster_by_location(centers.iter().copied(), DESTINATION_RADIUS_KM)
            .iter()
            .enumerate()
    {
        for member in &cluster.members {
            destination_of.insert(member.photo.id, destination);
        }
    }
    let mut starts: HashMap<usize, Vec<i64>> = HashMap::new();
    for visit in visits {
        starts
            .entry(destination_of[&visit[0].member.photo.id])
            .or_default()
            .push(visit[0].member.photo.creation_time);
    }
    let window = FREQUENT_WINDOW_DAYS * MICROS_PER_DAY;
    visits
        .iter()
        .map(|visit| {
            let start = visit[0].member.photo.creation_time;
            let others = &starts[&destination_of[&visit[0].member.photo.id]];
            let first = others.partition_point(|&other| other < start - window);
            let last = others.partition_point(|&other| other <= start + window);
            last - first >= FREQUENT_VISITS
        })
        .collect()
}

fn country_legs(visit: Vec<Placed>) -> Vec<Vec<Placed>> {
    let (Some(first), Some(last)) = (visit.first(), visit.last()) else {
        return Vec::new();
    };
    if last.member.photo.creation_time - first.member.photo.creation_time
        <= LONG_TRIP_DAYS * MICROS_PER_DAY
    {
        return vec![visit];
    }
    let mut country = visit
        .iter()
        .filter(|point| !point.joined)
        .find_map(|point| point.country);
    let mut legs: Vec<(Option<CountryCode>, Vec<Placed>)> = Vec::new();
    for point in visit {
        if !point.joined {
            country = point.country.or(country);
        }
        match legs.last_mut() {
            Some((leg_country, leg)) if *leg_country == country => leg.push(point),
            _ => legs.push((country, vec![point])),
        }
    }
    let mut merged: Vec<(Option<CountryCode>, Vec<Placed>)> = Vec::new();
    for (country, leg) in legs {
        match merged.last_mut() {
            Some((merged_country, merged_leg))
                if *merged_country == country || leg.len() < OVERNIGHT_TRIP_MIN_PHOTOS =>
            {
                merged_leg.extend(leg);
            }
            _ => merged.push((country, leg)),
        }
    }
    if merged.len() > 1 && merged[0].1.len() < OVERNIGHT_TRIP_MIN_PHOTOS {
        let (_, first) = merged.remove(0);
        merged[0].1.splice(0..0, first);
    }
    merged.into_iter().map(|(_, leg)| leg).collect()
}

fn is_trip(points: &[Placed]) -> bool {
    let (Some(first), Some(last)) = (points.first(), points.last()) else {
        return false;
    };
    let min_photos = if last.member.photo.date > first.member.photo.date {
        OVERNIGHT_TRIP_MIN_PHOTOS
    } else {
        DAY_TRIP_MIN_PHOTOS
    };
    points.len() >= min_photos
}

fn center(points: &[Placed]) -> Coordinate {
    let members: Vec<Located> = points.iter().map(|point| point.member).collect();
    mean_location(&members)
}

#[cfg(test)]
mod tests {
    use ente_location::{City, CityMatch, Coordinate, CountryCode};

    use crate::memories::calendar::MICROS_PER_DAY;
    use crate::memories::geo::distance_km;
    use crate::memories::tests::{file, located_file, micros, period};
    use crate::memories::{
        CityLookup, MemoriesRequest, Memory, MemoryFile, MemoryKind, ShownTrip, TripDetection,
        compute_all_trip_memories, compute_smart_memories,
    };

    const AMSTERDAM: (f64, f64) = (52.37, 4.90);
    const BERLIN: (f64, f64) = (52.52, 13.405);
    const PASADENA: (f64, f64) = (34.1478, -118.1445);
    const DOWNTOWN_LOS_ANGELES: (f64, f64) = (34.0522, -118.2437);
    const RIVERSIDE: (f64, f64) = (33.9533, -117.3962);
    const GYM_TOWARDS_ROTTERDAM: (f64, f64) = (52.10, 4.65);
    const LAS_VEGAS: (f64, f64) = (36.1699, -115.1398);
    const PARIS: (f64, f64) = (48.8566, 2.3522);
    const ROTTERDAM: (f64, f64) = (51.9244, 4.4777);
    const UTRECHT: (f64, f64) = (52.0907, 5.1214);
    const HAARLEM: (f64, f64) = (52.381, 4.636);
    const BRUGES: (f64, f64) = (51.2093, 3.2247);
    const GRONINGEN: (f64, f64) = (53.2194, 6.5665);
    const ZERMATT: (f64, f64) = (46.0207, 7.7491);
    const ROME: (f64, f64) = (41.9028, 12.4964);
    const ZURICH: (f64, f64) = (47.3769, 8.5417);
    const BRUSSELS: (f64, f64) = (50.8503, 4.3517);
    const LUXEMBOURG: (f64, f64) = (49.6116, 6.1319);
    const LANDMANNALAUGAR: (f64, f64) = (63.983, -19.067);
    const NIJMEGEN: (f64, f64) = (51.842, 5.853);
    const FAMILY_HOME: (f64, f64) = (51.7317, 5.5394);
    const HO_CHI_MINH_CITY: (f64, f64) = (10.7769, 106.7009);
    const MATTERHORN_BORDER: (f64, f64) = (45.976, 7.658);
    const ROMAN_COUNTRYSIDE: (f64, f64) = (42.25, 12.95);
    const ARDECHE: (f64, f64) = (44.6, 4.4);
    const TRIER: (f64, f64) = (49.7499, 6.6371);
    const FRENCH_TOWNS: [(f64, f64); 6] = [
        (45.764, 4.8357),
        (45.1885, 5.7245),
        (43.9493, 4.8055),
        (43.2965, 5.3698),
        (43.7102, 7.262),
        (43.6047, 1.4442),
    ];
    const CITY_SPOTS: [(f64, f64); 6] = [
        (0.0, 0.0),
        (0.03, 0.04),
        (-0.03, 0.04),
        (0.03, -0.05),
        (-0.03, -0.05),
        (0.0, 0.08),
    ];
    const NOW: &str = "2026-10-29T09:00:00";
    const HOUR: i64 = MICROS_PER_DAY / 24;
    const LOS_ANGELES_AREA: u32 = 1;

    type HomeSeries<'a> = (&'a [(f64, f64)], &'a str, &'a str, i64);

    const AMSTERDAM_HOME: [HomeSeries; 1] = [(
        &[AMSTERDAM],
        "2023-01-01T12:00:00",
        "2026-10-25T12:00:00",
        3,
    )];

    struct Atlas;

    const CITIES: [(&str, [u8; 2], (f64, f64)); 24] = [
        ("Amsterdam", *b"NL", AMSTERDAM),
        ("Berlin", *b"DE", BERLIN),
        ("Los Angeles", *b"US", DOWNTOWN_LOS_ANGELES),
        ("Las Vegas", *b"US", LAS_VEGAS),
        ("Paris", *b"FR", PARIS),
        ("Rotterdam", *b"NL", ROTTERDAM),
        ("Utrecht", *b"NL", UTRECHT),
        ("Haarlem", *b"NL", HAARLEM),
        ("Bruges", *b"BE", BRUGES),
        ("Groningen", *b"NL", GRONINGEN),
        ("Zermatt", *b"CH", ZERMATT),
        ("Rome", *b"IT", ROME),
        ("Zurich", *b"CH", ZURICH),
        ("Brussels", *b"BE", BRUSSELS),
        ("Luxembourg", *b"LU", LUXEMBOURG),
        ("Reykjavik", *b"IS", (64.1466, -21.9426)),
        ("Lyon", *b"FR", FRENCH_TOWNS[0]),
        ("Grenoble", *b"FR", FRENCH_TOWNS[1]),
        ("Avignon", *b"FR", FRENCH_TOWNS[2]),
        ("Marseille", *b"FR", FRENCH_TOWNS[3]),
        ("Nice", *b"FR", FRENCH_TOWNS[4]),
        ("Toulouse", *b"FR", FRENCH_TOWNS[5]),
        ("Nijmegen", *b"NL", NIJMEGEN),
        ("Trier", *b"DE", TRIER),
    ];

    fn nearest_city(coordinate: Coordinate) -> usize {
        (0..CITIES.len())
            .min_by(|&left, &right| {
                let distance = |index: usize| {
                    let (latitude, longitude) = CITIES[index].2;
                    distance_km(coordinate, Coordinate::new(latitude, longitude))
                };
                distance(left).total_cmp(&distance(right))
            })
            .unwrap()
    }

    impl CityLookup for Atlas {
        fn group_cities(&self, coordinates: &[Coordinate]) -> Vec<CityMatch> {
            CITIES
                .iter()
                .enumerate()
                .map(
                    |(index, &(name, country, (latitude, longitude)))| CityMatch {
                        city: City {
                            point_index: index as u32,
                            source_id: index as u32,
                            name: name.to_owned(),
                            country_name: String::new(),
                            country_code: CountryCode::from_bytes(country).unwrap(),
                            latitude,
                            longitude,
                            rank: 0,
                        },
                        coordinate_indices: coordinates
                            .iter()
                            .enumerate()
                            .filter(|&(_, &coordinate)| {
                                nearest_city(coordinate) == index
                                    && distance_km(coordinate, Coordinate::new(latitude, longitude))
                                        < 20.0
                            })
                            .map(|(position, _)| position as u32)
                            .collect(),
                    },
                )
                .filter(|group| !group.coordinate_indices.is_empty())
                .collect()
        }

        fn urban_centers(&self, coordinates: &[Coordinate]) -> Vec<Option<u32>> {
            let (latitude, longitude) = DOWNTOWN_LOS_ANGELES;
            coordinates
                .iter()
                .map(|&coordinate| {
                    (distance_km(coordinate, Coordinate::new(latitude, longitude)) < 90.0)
                        .then_some(LOS_ANGELES_AREA)
                })
                .collect()
        }

        fn countries(&self, coordinates: &[Coordinate]) -> Vec<Option<CountryCode>> {
            let (latitude, longitude) = MATTERHORN_BORDER;
            coordinates
                .iter()
                .map(|&coordinate| {
                    let country =
                        if distance_km(coordinate, Coordinate::new(latitude, longitude)) < 3.0 {
                            *b"IT"
                        } else {
                            CITIES[nearest_city(coordinate)].1
                        };
                    CountryCode::from_bytes(country).ok()
                })
                .collect()
        }

        fn country_name(&self, country: CountryCode) -> Option<String> {
            let name = match country.as_str() {
                "FR" => "France",
                "IS" => "Iceland",
                "CH" => "Switzerland",
                "IT" => "Italy",
                _ => return None,
            };
            Some(name.to_owned())
        }
    }

    fn stay(
        first_id: i64,
        start: &str,
        count: i64,
        every_minutes: i64,
        place: (f64, f64),
    ) -> Vec<MemoryFile> {
        let start = micros(start);
        (0..count)
            .map(|index| {
                located_file(
                    first_id + index,
                    start + index * every_minutes * 60_000_000,
                    place,
                )
            })
            .collect()
    }

    fn shared(files: Vec<MemoryFile>) -> Vec<MemoryFile> {
        files
            .into_iter()
            .map(|file| MemoryFile {
                shared: true,
                ..file
            })
            .collect()
    }

    fn home(
        first_id: i64,
        places: &[(f64, f64)],
        first: &str,
        last: &str,
        every_days: i64,
        away: &[MemoryFile],
    ) -> Vec<MemoryFile> {
        let (first, last) = (micros(first), micros(last));
        (0..)
            .map(|index| first + index * every_days * MICROS_PER_DAY)
            .take_while(|&time| time <= last)
            .filter(|&time| {
                away.iter()
                    .all(|file| (file.creation_time - time).abs() > 2 * MICROS_PER_DAY)
            })
            .enumerate()
            .map(|(index, time)| {
                located_file(first_id + index as i64, time, places[index % places.len()])
            })
            .collect()
    }

    fn library(trips: Vec<Vec<MemoryFile>>, homes: &[HomeSeries]) -> Vec<MemoryFile> {
        let away: Vec<MemoryFile> = trips.into_iter().flatten().collect();
        let mut files = away.clone();
        for (index, &(places, first, last, every_days)) in homes.iter().enumerate() {
            let first_id = 100_000 * (index as i64 + 1);
            files.extend(home(first_id, places, first, last, every_days, &away));
        }
        files
    }

    fn memories(files: Vec<MemoryFile>) -> Vec<Memory> {
        let request = MemoriesRequest {
            files,
            ..MemoriesRequest::default()
        };
        compute_all_trip_memories(&request, period(NOW), Some(&Atlas), TripDetection::Improved)
    }

    fn trips(files: Vec<MemoryFile>) -> Vec<(i64, Option<String>)> {
        let mut trips: Vec<(i64, Option<String>)> = memories(files)
            .into_iter()
            .filter_map(|memory| match memory.kind {
                MemoryKind::Trip(trip) => {
                    let ids: Vec<i64> = memory.file_ids.iter().map(|id| id / 1000).collect();
                    assert!(ids.iter().all(|&id| id == ids[0]), "{ids:?}");
                    Some((ids[0], trip.location_name))
                }
                _ => None,
            })
            .collect();
        trips.sort();
        trips
    }

    fn named(trips: &[(i64, &str)]) -> Vec<(i64, Option<String>)> {
        trips
            .iter()
            .map(|&(id, name)| (id, Some(name.to_owned())))
            .collect()
    }

    fn trip_key(files: &[MemoryFile], name: &str) -> String {
        memories(files.to_vec())
            .into_iter()
            .find_map(|memory| match memory.kind {
                MemoryKind::Trip(trip) if trip.location_name.as_deref() == Some(name) => {
                    Some(trip.key)
                }
                _ => None,
            })
            .unwrap()
    }

    fn surfaced_after_showing(files: &[MemoryFile], key: String) -> Vec<String> {
        let request = MemoriesRequest {
            files: files.to_vec(),
            shown_trips: vec![ShownTrip {
                key: Some(key),
                location: Coordinate::new(0.0, 0.0),
                last_time_shown: micros(NOW) - 30 * MICROS_PER_DAY,
            }],
            ..MemoriesRequest::default()
        };
        compute_smart_memories(&request, &[period(NOW)], None, Some(&Atlas))
            .unwrap()
            .periods[0]
            .iter()
            .filter_map(|memory| match &memory.kind {
                MemoryKind::Trip(trip) => Some(trip.key.clone()),
                _ => None,
            })
            .collect()
    }

    #[test]
    fn weekends_far_day_trips_and_light_trips_count_but_nearby_towns_do_not() {
        let files = library(
            vec![
                stay(1000, "2024-03-09T10:00:00", 12, 180, PARIS),
                stay(2000, "2024-04-13T09:00:00", 16, 30, ROTTERDAM),
                stay(3000, "2024-05-11T09:00:00", 20, 30, UTRECHT),
                stay(4000, "2024-06-08T10:00:00", 12, 180, HAARLEM),
                stay(5000, "2024-07-13T10:00:00", 12, 180, UTRECHT),
                stay(6000, "2024-08-10T10:00:00", 8, 240, BRUGES),
                stay(7000, "2024-09-14T10:00:00", 12, 180, ROTTERDAM),
            ],
            &[
                (
                    &[AMSTERDAM],
                    "2023-01-01T12:00:00",
                    "2026-10-25T12:00:00",
                    3,
                ),
                (
                    &[GYM_TOWARDS_ROTTERDAM],
                    "2023-01-02T19:00:00",
                    "2026-10-25T19:00:00",
                    21,
                ),
            ],
        );

        assert_eq!(
            trips(files),
            named(&[(1, "Paris"), (2, "Rotterdam"), (7, "Rotterdam")])
        );
    }

    #[test]
    fn trips_are_measured_from_where_you_lived_at_the_time() {
        let files = library(
            vec![
                stay(1000, "2023-09-08T10:00:00", 12, 180, BERLIN),
                stay(2000, "2025-05-09T10:00:00", 12, 180, AMSTERDAM),
            ],
            &[
                (
                    &[AMSTERDAM],
                    "2023-01-01T12:00:00",
                    "2024-06-30T12:00:00",
                    3,
                ),
                (&[BERLIN], "2024-07-01T12:00:00", "2026-10-25T12:00:00", 3),
            ],
        );

        assert_eq!(trips(files), named(&[(1, "Berlin"), (2, "Amsterdam")]));
    }

    #[test]
    fn places_visited_every_few_weeks_are_not_trips_but_yearly_ones_are() {
        let mut away: Vec<Vec<MemoryFile>> = (2023..=2025)
            .map(|year| {
                stay(
                    i64::from(year - 2022) * 1000,
                    &format!("{year}-02-11T09:00:00"),
                    20,
                    480,
                    ZERMATT,
                )
            })
            .collect();
        let first_visit = micros("2023-03-03T17:00:00");
        for visit in 0..24 {
            let start = first_visit + visit * 42 * MICROS_PER_DAY;
            let overlaps_skiing = away
                .iter()
                .any(|week| (week[0].creation_time - start).abs() < 10 * MICROS_PER_DAY);
            if overlaps_skiing {
                continue;
            }
            away.push(
                (0..12)
                    .map(|index| {
                        let (latitude, longitude) = GRONINGEN;
                        let (north, east) = CITY_SPOTS[visit as usize % CITY_SPOTS.len()];
                        located_file(
                            10_000 + visit * 100 + index,
                            start + index * 4 * HOUR,
                            (latitude + north, longitude + east),
                        )
                    })
                    .collect(),
            );
        }
        let files = library(
            away,
            &[(
                &[AMSTERDAM],
                "2023-01-01T12:00:00",
                "2026-10-25T12:00:00",
                3,
            )],
        );

        assert_eq!(
            trips(files),
            named(&[(1, "Zermatt"), (2, "Zermatt"), (3, "Zermatt")])
        );
    }

    #[test]
    fn staying_with_family_makes_neighbouring_towns_part_of_home_but_far_cities_are_trips() {
        let outings = vec![
            stay(1000, "2024-07-14T10:00:00", 20, 20, NIJMEGEN),
            stay(2000, "2024-12-27T10:00:00", 20, 20, ROTTERDAM),
            stay(3000, "2024-12-23T10:00:00", 30, 80, AMSTERDAM),
        ];
        let during_outing = |time: i64| {
            outings.iter().any(|outing| {
                (outing[0].creation_time..=outing[outing.len() - 1].creation_time).contains(&time)
            })
        };
        let mut away: Vec<Vec<MemoryFile>> = [
            "2024-07-10T08:00:00",
            "2024-12-20T08:00:00",
            "2025-07-05T08:00:00",
            "2025-12-19T08:00:00",
        ]
        .iter()
        .enumerate()
        .map(|(index, start)| {
            let first_id = 10_000 + index as i64 * 1000;
            let transit = |spot: usize| {
                let (north, east) = CITY_SPOTS[1 + spot % (CITY_SPOTS.len() - 1)];
                (AMSTERDAM.0 + north, AMSTERDAM.1 + east)
            };
            let mut visit = stay(first_id, start, 1, 0, transit(2 * index));
            visit.extend(
                stay(first_id + 1, start, 15, 24 * 60, FAMILY_HOME)
                    .into_iter()
                    .filter(|file| !during_outing(file.creation_time)),
            );
            let last = visit[visit.len() - 1].creation_time + 10 * HOUR;
            visit.push(located_file(first_id + 100, last, transit(2 * index + 1)));
            visit
        })
        .collect();
        away.extend(outings.clone());
        let files = library(
            away,
            &[(&[BERLIN], "2023-01-01T12:00:00", "2026-10-25T12:00:00", 1)],
        );

        assert_eq!(trips(files), named(&[(2, "Rotterdam"), (3, "Amsterdam")]));
    }

    #[test]
    fn shared_photos_join_your_trips_but_never_make_homes_or_trips_of_their_own() {
        let mut paris = stay(1000, "2024-05-10T10:00:00", 12, 360, PARIS);
        paris.extend(shared(stay(1500, "2024-05-10T11:00:00", 8, 480, PARIS)));
        let mut files = library(
            vec![
                paris,
                shared(stay(2000, "2024-09-05T10:00:00", 30, 240, ROME)),
                stay(3000, "2024-10-10T10:00:00", 12, 360, ZURICH),
            ],
            &[(
                &[AMSTERDAM],
                "2023-01-01T12:00:00",
                "2026-10-25T12:00:00",
                3,
            )],
        );
        let friend_start = micros("2023-06-01T05:00:00");
        files.extend(shared(
            (0..1800)
                .map(|index| {
                    located_file(
                        500_000 + index,
                        friend_start + index * 8 * HOUR,
                        HO_CHI_MINH_CITY,
                    )
                })
                .collect(),
        ));
        let files_in = |memories: &[Memory], first: i64| {
            memories
                .iter()
                .filter(|memory| matches!(memory.kind, MemoryKind::Trip(_)))
                .find(|memory| memory.file_ids.contains(&first))
                .map(|memory| memory.file_ids.len())
        };
        let all = memories(files.clone());

        assert_eq!(trips(files), named(&[(1, "Paris"), (3, "Zurich")]));
        assert_eq!(files_in(&all, 1000), Some(20));
        assert_eq!(
            all.iter()
                .filter(|memory| matches!(memory.kind, MemoryKind::Base(_)))
                .count(),
            1
        );
    }

    #[test]
    fn sparse_trips_abroad_stay_whole_across_photo_gaps_but_trips_at_home_do_not() {
        let mut america = stay(1000, "2024-04-01T10:00:00", 4, 120, DOWNTOWN_LOS_ANGELES);
        america.extend(stay(1100, "2024-04-06T10:00:00", 4, 120, LAS_VEGAS));
        america.extend(stay(
            1200,
            "2024-04-11T10:00:00",
            4,
            120,
            DOWNTOWN_LOS_ANGELES,
        ));
        let mut rotterdam = stay(2000, "2024-06-01T10:00:00", 6, 60, ROTTERDAM);
        rotterdam.extend(stay(2100, "2024-06-06T10:00:00", 6, 60, ROTTERDAM));
        let files = library(
            vec![america, rotterdam],
            &[(
                &[AMSTERDAM],
                "2023-01-01T12:00:00",
                "2026-10-25T12:00:00",
                3,
            )],
        );

        assert_eq!(trips(files), named(&[(1, "Los Angeles")]));
    }

    #[test]
    fn a_month_abroad_stays_one_trip_when_border_photos_disagree_on_the_country() {
        let mut switzerland = stay(1000, "2024-08-01T09:00:00", 45, 480, ZURICH);
        switzerland.extend(stay(
            1100,
            "2024-08-16T09:00:00",
            15,
            480,
            MATTERHORN_BORDER,
        ));
        switzerland.extend(stay(1200, "2024-08-21T09:00:00", 60, 480, ZURICH));
        let files = library(
            vec![switzerland],
            &[(
                &[AMSTERDAM],
                "2023-01-01T12:00:00",
                "2026-10-25T12:00:00",
                3,
            )],
        );

        assert_eq!(trips(files), named(&[(1, "Zurich")]));
    }

    #[test]
    fn trips_mostly_abroad_are_named_after_the_part_abroad() {
        let mut italy = stay(1000, "2024-02-10T07:00:00", 9, 10, ROTTERDAM);
        italy.extend(stay(
            1100,
            "2024-02-10T15:00:00",
            12,
            480,
            ROMAN_COUNTRYSIDE,
        ));
        let mut france = stay(2000, "2024-06-01T10:00:00", 3, 60, FRENCH_TOWNS[0]);
        france.extend(stay(2100, "2024-06-02T10:00:00", 3, 60, FRENCH_TOWNS[1]));
        france.extend(stay(2200, "2024-06-03T10:00:00", 14, 240, ARDECHE));
        let files = library(
            vec![italy, france],
            &[(
                &[AMSTERDAM],
                "2023-01-01T12:00:00",
                "2026-10-25T12:00:00",
                3,
            )],
        );

        assert_eq!(trips(files), named(&[(1, "Italy"), (2, "France")]));
    }

    #[test]
    fn road_trips_and_multi_country_holidays_stay_whole_and_only_month_long_trips_split() {
        let road_trip: Vec<MemoryFile> = FRENCH_TOWNS
            .iter()
            .enumerate()
            .flat_map(|(stop, &town)| {
                stay(
                    1000 + stop as i64 * 10,
                    &format!("2024-05-{:02}T10:00:00", 4 + stop),
                    3,
                    120,
                    town,
                )
            })
            .collect();
        let mut holiday = stay(2000, "2024-09-01T09:00:00", 30, 480, ROME);
        holiday.extend(stay(2100, "2024-09-11T09:00:00", 30, 480, ZURICH));
        let mut long_trip = stay(6000, "2025-09-01T09:00:00", 60, 480, ROME);
        long_trip.extend(stay(7000, "2025-09-21T09:00:00", 60, 480, ZURICH));
        let mut benelux = stay(4000, "2025-03-01T09:00:00", 15, 240, BRUSSELS);
        benelux.extend(stay(4100, "2025-03-04T09:00:00", 15, 240, LUXEMBOURG));
        let files = library(
            vec![
                road_trip,
                holiday,
                long_trip,
                benelux,
                stay(5000, "2025-07-01T09:00:00", 15, 360, LANDMANNALAUGAR),
            ],
            &[(
                &[AMSTERDAM],
                "2023-01-01T12:00:00",
                "2026-10-25T12:00:00",
                3,
            )],
        );

        assert_eq!(
            trips(files),
            named(&[
                (1, "France"),
                (2, "Rome & Zurich"),
                (4, "Brussels & Luxembourg"),
                (5, "Iceland"),
                (6, "Rome"),
                (7, "Zurich"),
            ])
        );
    }

    #[test]
    fn sparse_home_photos_and_weekends_inside_the_home_urban_area_are_not_trips() {
        let files = library(
            vec![
                stay(1000, "2024-03-08T10:00:00", 15, 240, RIVERSIDE),
                stay(2000, "2024-04-12T10:00:00", 15, 240, LAS_VEGAS),
            ],
            &[(
                &[PASADENA, DOWNTOWN_LOS_ANGELES],
                "2023-01-01T12:00:00",
                "2026-10-25T12:00:00",
                20,
            )],
        );

        assert_eq!(trips(files), named(&[(2, "Las Vegas")]));
    }
    #[test]
    fn a_month_away_or_two_stays_at_one_spot_do_not_make_it_a_home() {
        let files = library(
            vec![
                stay(1000, "2024-07-30T09:00:00", 99, 480, ROME),
                stay(2000, "2025-01-30T09:00:00", 12, 360, PARIS),
                stay(3000, "2025-03-08T09:00:00", 12, 360, PARIS),
                stay(4000, "2024-11-15T09:00:00", 12, 360, ROME),
            ],
            &AMSTERDAM_HOME,
        );

        assert_eq!(
            trips(files),
            named(&[(1, "Rome"), (2, "Paris"), (3, "Paris"), (4, "Rome")])
        );
    }

    #[test]
    fn a_family_stay_replaces_the_guess_of_a_home_you_no_longer_photograph() {
        let mut away: Vec<Vec<MemoryFile>> = [
            "2024-06-01T08:00:00",
            "2024-10-05T08:00:00",
            "2024-12-20T08:00:00",
        ]
        .iter()
        .enumerate()
        .map(|(index, start)| stay(10_000 + index as i64 * 1000, start, 7, 24 * 60, FAMILY_HOME))
        .collect();
        away.push(stay(1000, "2024-10-08T10:00:00", 20, 20, HAARLEM));
        away.push(stay(2000, "2024-10-09T10:00:00", 20, 20, NIJMEGEN));
        let files = library(
            away,
            &[
                (
                    &[AMSTERDAM],
                    "2023-01-01T12:00:00",
                    "2024-08-01T12:00:00",
                    1,
                ),
                (&[BERLIN], "2025-03-01T12:00:00", "2026-10-25T12:00:00", 2),
            ],
        );

        assert_eq!(trips(files), named(&[(1, "Haarlem")]));
    }

    #[test]
    fn shared_photos_from_across_a_border_never_split_a_long_trip() {
        let start = micros("2024-08-01T09:00:00");
        let mut visit: Vec<MemoryFile> = (0..70)
            .filter(|index| !(28..32).contains(index))
            .map(|index| located_file(1000 + index, start + index * 12 * HOUR, LUXEMBOURG))
            .collect();
        let gap_start = start + 28 * 12 * HOUR;
        visit.extend(shared(
            (0..15)
                .map(|index| located_file(1500 + index, gap_start + index * 3 * HOUR, TRIER))
                .collect(),
        ));

        assert_eq!(
            trips(library(vec![visit], &AMSTERDAM_HOME)),
            named(&[(1, "Luxembourg")])
        );
    }

    #[test]
    fn shared_photos_join_only_near_the_own_photo_closest_in_time() {
        let mut visit = stay(1000, "2024-06-01T09:00:00", 12, 60, PARIS);
        visit.extend(stay(1100, "2024-06-03T10:00:00", 12, 60, ROME));
        visit.extend(shared(vec![
            located_file(1500, micros("2024-06-03T09:59:00"), PARIS),
            located_file(1501, micros("2024-06-01T21:00:00"), PARIS),
        ]));
        let all = memories(library(vec![visit], &AMSTERDAM_HOME));
        let trip = all
            .iter()
            .find(|memory| memory.file_ids.contains(&1000))
            .unwrap();

        assert!(trip.file_ids.contains(&1501));
        assert!(!trip.file_ids.contains(&1500));
    }

    #[test]
    fn a_library_of_only_shared_photos_is_treated_as_your_own() {
        let files = shared(library(
            vec![stay(1000, "2024-03-09T10:00:00", 12, 180, PARIS)],
            &AMSTERDAM_HOME,
        ));

        assert_eq!(trips(files), named(&[(1, "Paris")]));
    }

    #[test]
    fn a_shown_country_leg_holds_back_only_itself_but_a_shown_whole_trip_holds_back_every_leg() {
        let mut long_trip = stay(1000, "2024-09-01T09:00:00", 57, 480, ROME);
        long_trip.extend(stay(2000, "2024-09-20T21:00:00", 60, 480, ZURICH));
        let files = library(vec![long_trip], &AMSTERDAM_HOME);
        let (rome, zurich) = (trip_key(&files, "Rome"), trip_key(&files, "Zurich"));
        let rome_parts: Vec<&str> = rome.split('_').collect();
        let zurich_parts: Vec<&str> = zurich.split('_').collect();
        assert_eq!(rome_parts[4], zurich_parts[3]);
        let older_rome = format!(
            "trip_41.91_{}_{}_{}",
            rome_parts[2], rome_parts[3], rome_parts[4]
        );
        let whole_trip = format!("trip_44.60_10.50_{}_{}", rome_parts[3], zurich_parts[4]);

        assert_eq!(
            surfaced_after_showing(&files, rome.clone()),
            [zurich.as_str()]
        );
        assert_eq!(
            surfaced_after_showing(&files, older_rome),
            [zurich.as_str()]
        );
        assert!(surfaced_after_showing(&files, whole_trip).is_empty());
    }

    #[test]
    fn a_day_trip_on_the_day_you_come_back_from_another_trip_is_not_held_back_by_it() {
        let mut files = library(
            vec![
                stay(1000, "2024-06-10T09:00:00", 12, 240, PARIS),
                stay(2000, "2024-06-12T14:00:00", 16, 20, GRONINGEN),
            ],
            &AMSTERDAM_HOME,
        );
        files.push(located_file(
            900_000,
            micros("2024-06-12T10:00:00"),
            AMSTERDAM,
        ));
        let (paris, groningen) = (trip_key(&files, "Paris"), trip_key(&files, "Groningen"));

        assert_eq!(surfaced_after_showing(&files, paris), [groningen.as_str()]);
    }

    #[test]
    fn two_holidays_at_one_spot_months_apart_are_both_trips() {
        let files = library(
            vec![
                stay(1000, "2024-12-27T09:00:00", 24, 480, ZERMATT),
                stay(2000, "2025-03-29T09:00:00", 24, 480, ZERMATT),
                stay(3000, "2025-06-06T09:00:00", 12, 360, PARIS),
                stay(4000, "2025-09-12T09:00:00", 12, 360, PARIS),
            ],
            &AMSTERDAM_HOME,
        );

        assert_eq!(
            trips(files),
            named(&[(1, "Zermatt"), (2, "Zermatt"), (3, "Paris"), (4, "Paris")])
        );
    }

    #[test]
    fn day_visits_to_a_regular_place_never_make_its_area_home() {
        let mut files = library(
            vec![stay(1000, "2024-06-15T10:00:00", 12, 180, ROTTERDAM)],
            &[(
                &[AMSTERDAM],
                "2023-01-01T12:00:00",
                "2026-10-25T12:00:00",
                1,
            )],
        );
        let first_visit = micros("2024-03-06T11:00:00");
        files.extend((0..30).map(|week| {
            located_file(
                700_000 + week,
                first_visit + week * 7 * MICROS_PER_DAY,
                UTRECHT,
            )
        }));
        files.push(located_file(700_100, first_visit + MICROS_PER_DAY, UTRECHT));

        assert_eq!(trips(files), named(&[(1, "Rotterdam")]));
    }

    #[test]
    fn a_family_stay_holds_across_a_week_without_photos_there() {
        let visit = |first_id: i64, days: &[&str]| -> Vec<MemoryFile> {
            days.iter()
                .enumerate()
                .map(|(index, day)| {
                    located_file(
                        first_id + index as i64,
                        micros(&format!("{day}T09:00:00")),
                        FAMILY_HOME,
                    )
                })
                .collect()
        };
        let files = library(
            vec![
                visit(10_000, &["2024-07-10", "2024-07-11", "2024-07-12"]),
                visit(11_000, &["2024-12-20", "2024-12-21", "2024-12-22"]),
                visit(12_000, &["2025-07-05", "2025-07-06", "2025-07-07"]),
                visit(
                    13_000,
                    &[
                        "2025-12-19",
                        "2025-12-20",
                        "2025-12-21",
                        "2025-12-24",
                        "2025-12-31",
                        "2026-01-01",
                    ],
                ),
                stay(1000, "2025-12-28T10:00:00", 20, 20, NIJMEGEN),
            ],
            &[(&[BERLIN], "2023-01-01T12:00:00", "2026-10-25T12:00:00", 1)],
        );

        assert_eq!(trips(files), named(&[]));
    }

    #[test]
    fn shared_photos_stay_shared_when_your_own_photos_have_no_location() {
        let mut files = shared(library(
            vec![stay(1000, "2024-03-09T10:00:00", 12, 180, PARIS)],
            &AMSTERDAM_HOME,
        ));
        files.push(MemoryFile {
            location: None,
            ..file(9_000_000, "2024-01-01T10:00:00")
        });

        assert_eq!(trips(files), named(&[]));
    }

    #[test]
    fn a_sparse_holiday_in_a_country_you_move_to_later_stays_whole() {
        let mut holiday = stay(1000, "2023-06-10T09:00:00", 6, 60, LAS_VEGAS);
        holiday.extend(stay(1100, "2023-06-15T09:00:00", 6, 60, LAS_VEGAS));
        let files = library(
            vec![holiday],
            &[
                (
                    &[AMSTERDAM],
                    "2023-01-01T12:00:00",
                    "2024-12-31T12:00:00",
                    1,
                ),
                (&[PASADENA], "2025-01-01T12:00:00", "2026-10-25T12:00:00", 1),
            ],
        );

        assert_eq!(trips(files), named(&[(1, "Las Vegas")]));
    }

    #[test]
    fn a_road_trip_to_both_sides_of_home_is_a_trip() {
        let mut road_trip = stay(1000, "2024-06-10T09:00:00", 12, 120, GRONINGEN);
        road_trip.extend(stay(1100, "2024-06-12T09:00:00", 12, 120, BRUGES));
        let files = library(vec![road_trip], &AMSTERDAM_HOME);

        assert_eq!(trips(files), named(&[(1, "Bruges & Groningen")]));
    }
}
