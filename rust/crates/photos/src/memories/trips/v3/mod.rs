mod homes;
mod naming;

use std::collections::HashMap;
use std::mem;

use ente_location::{Coordinate, CountryCode};

use homes::Homes;

use crate::memories::UPDATE_FREQUENCY_DAYS;
use crate::memories::calendar::{LocalDate, MICROS_PER_DAY};
use crate::memories::geo::{Located, cluster_by_location, mean_location, two_decimals};
use crate::memories::input::{CityLookup, Period};
use crate::memories::output::{BaseMemory, Memory, MemoryKind, TripMemory};
use crate::memories::photo::{Photo, sort_chronologically};
use crate::memories::places::Places;

const AWAY_MIN_KM: f64 = 30.0;
const DAY_TRIP_MIN_KM: f64 = 50.0;
const OVERNIGHT_TRIP_MIN_PHOTOS: usize = 10;
const DAY_TRIP_MIN_PHOTOS: usize = 15;
const MAX_PHOTO_GAP_DAYS: i64 = 3;
const LONG_TRIP_DAYS: i64 = 14;
const DESTINATION_RADIUS_KM: f64 = 25.0;
const FREQUENT_VISITS: usize = 4;
const FREQUENT_WINDOW_DAYS: i64 = 182;

#[derive(Clone, Copy)]
struct Placed<'p> {
    member: Located<'p>,
    urban_center: Option<u32>,
    country: Option<CountryCode>,
}

pub(in crate::memories) fn all_memories(
    located: &[Located],
    period: Period,
    places: &Places,
    lookup: Option<&dyn CityLookup>,
) -> Vec<Memory> {
    let points = placed(located, places, lookup);
    let homes = Homes::detect(&points, lookup);
    let home_countries = homes.countries();
    let today = period.today().days_since_epoch();
    let last_date_to_show = period.now + UPDATE_FREQUENCY_DAYS * MICROS_PER_DAY;
    let mut memories: Vec<Memory> = homes
        .areas()
        .into_iter()
        .map(|area| {
            let members: Vec<Located> = area
                .iter()
                .flat_map(|home| home.members.iter().copied())
                .collect();
            let mut photos: Vec<&Photo> = members.iter().map(|member| member.photo).collect();
            sort_chronologically(&mut photos);
            let kind = MemoryKind::Base(BaseMemory {
                location: area[0].center,
                location_name: places.base_name(&members),
                is_current: area.iter().any(|home| home.covers(today)),
            });
            Memory::uncapped(kind, &photos, period.now, last_date_to_show)
        })
        .collect();
    let trips = trips(&points, &homes);
    memories.extend(trips.iter().rev().map(|trip| {
        let photos: Vec<&Photo> = trip.iter().map(|point| point.member.photo).collect();
        let kind = MemoryKind::Trip(trip_memory(
            trip,
            naming::trip_name(trip, places, &home_countries, lookup),
        ));
        Memory::uncapped(kind, &photos, period.now, last_date_to_show)
    }));
    memories
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
        .map(|(index, &member)| Placed {
            member,
            urban_center: urban_centers
                .as_ref()
                .and_then(|urban_centers| urban_centers.get(index).copied().flatten()),
            country: countries
                .as_ref()
                .and_then(|countries| countries.get(index).copied().flatten())
                .or_else(|| places.country_code(member.photo.id)),
        })
        .collect()
}

fn trips<'p>(points: &[Placed<'p>], homes: &Homes) -> Vec<Vec<Placed<'p>>> {
    let visits = away_visits(points, homes);
    let frequent = frequent_visits(&visits);
    visits
        .into_iter()
        .zip(frequent)
        .filter(|(_, frequent)| !frequent)
        .flat_map(|(visit, _)| country_legs(visit))
        .filter(|leg| is_trip(leg, homes))
        .collect()
}

fn away_visits<'p>(points: &[Placed<'p>], homes: &Homes) -> Vec<Vec<Placed<'p>>> {
    let mut visits = Vec::new();
    let mut visit: Vec<Placed> = Vec::new();
    for &point in points {
        if homes.contains(&point) {
            if !visit.is_empty() {
                visits.push(mem::take(&mut visit));
            }
            continue;
        }
        if let Some(last) = visit.last()
            && point.member.photo.creation_time - last.member.photo.creation_time
                > MAX_PHOTO_GAP_DAYS * MICROS_PER_DAY
        {
            visits.push(mem::take(&mut visit));
        }
        visit.push(point);
    }
    if !visit.is_empty() {
        visits.push(visit);
    }
    visits
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
    let mut country = visit.iter().find_map(|point| point.country);
    let mut legs: Vec<(Option<CountryCode>, Vec<Placed>)> = Vec::new();
    for point in visit {
        country = point.country.or(country);
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

fn is_trip(points: &[Placed], homes: &Homes) -> bool {
    let (Some(first), Some(last)) = (points.first(), points.last()) else {
        return false;
    };
    let first_day = first.member.photo.date.days_since_epoch();
    let nights = last.member.photo.date.days_since_epoch() - first_day;
    let distance_km = homes.distance_km(first_day, center(points));
    if nights > 0 {
        points.len() >= OVERNIGHT_TRIP_MIN_PHOTOS && distance_km >= AWAY_MIN_KM
    } else {
        points.len() >= DAY_TRIP_MIN_PHOTOS && distance_km >= DAY_TRIP_MIN_KM
    }
}

fn center(points: &[Placed]) -> Coordinate {
    let members: Vec<Located> = points.iter().map(|point| point.member).collect();
    mean_location(&members)
}

fn trip_memory(points: &[Placed], location_name: Option<String>) -> TripMemory {
    let first = points[0].member.photo;
    let last = points[points.len() - 1].member.photo;
    let location = center(points);
    TripMemory {
        location,
        location_name,
        year: LocalDate::of_local_time((first.local_time + last.local_time) / 2).year,
        key: format!(
            "trip_{}_{}_{}_{}",
            two_decimals(location.latitude),
            two_decimals(location.longitude),
            first.creation_time / MICROS_PER_DAY,
            last.creation_time / MICROS_PER_DAY
        ),
    }
}

#[cfg(test)]
mod tests {
    use ente_location::{City, CityMatch, Coordinate, CountryCode};

    use crate::memories::calendar::MICROS_PER_DAY;
    use crate::memories::geo::distance_km;
    use crate::memories::tests::{located_file, micros, period};
    use crate::memories::{
        CityLookup, MemoriesRequest, MemoryFile, MemoryKind, TripDetection,
        compute_all_trip_memories,
    };

    const AMSTERDAM: (f64, f64) = (52.37, 4.90);
    const BERLIN: (f64, f64) = (52.52, 13.405);
    const PASADENA: (f64, f64) = (34.1478, -118.1445);
    const DOWNTOWN_LOS_ANGELES: (f64, f64) = (34.0522, -118.2437);
    const LONG_BEACH: (f64, f64) = (33.7701, -118.1937);
    const GYM_TOWARDS_UTRECHT: (f64, f64) = (52.202, 5.033);
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

    struct Atlas;

    const CITIES: [(&str, [u8; 2], (f64, f64)); 22] = [
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
                    (distance_km(coordinate, Coordinate::new(latitude, longitude)) < 45.0)
                        .then_some(LOS_ANGELES_AREA)
                })
                .collect()
        }

        fn countries(&self, coordinates: &[Coordinate]) -> Vec<Option<CountryCode>> {
            coordinates
                .iter()
                .map(|&coordinate| CountryCode::from_bytes(CITIES[nearest_city(coordinate)].1).ok())
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

    fn trips(files: Vec<MemoryFile>) -> Vec<(i64, Option<String>)> {
        let request = MemoriesRequest {
            files,
            ..MemoriesRequest::default()
        };
        let mut trips: Vec<(i64, Option<String>)> =
            compute_all_trip_memories(&request, period(NOW), Some(&Atlas), TripDetection::Improved)
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
            ],
            &[
                (
                    &[AMSTERDAM],
                    "2023-01-01T12:00:00",
                    "2026-10-25T12:00:00",
                    3,
                ),
                (
                    &[GYM_TOWARDS_UTRECHT],
                    "2023-01-02T19:00:00",
                    "2026-10-25T19:00:00",
                    21,
                ),
            ],
        );

        assert_eq!(
            trips(files),
            named(&[(1, "Paris"), (2, "Rotterdam"), (5, "Utrecht")])
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
    fn road_trips_stay_whole_long_trips_split_by_country_and_names_follow_the_places() {
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
        let mut long_trip = stay(2000, "2024-09-01T09:00:00", 30, 480, ROME);
        long_trip.extend(stay(3000, "2024-09-11T09:00:00", 30, 480, ZURICH));
        let mut benelux = stay(4000, "2025-03-01T09:00:00", 15, 240, BRUSSELS);
        benelux.extend(stay(4100, "2025-03-04T09:00:00", 15, 240, LUXEMBOURG));
        let files = library(
            vec![
                road_trip,
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
                (2, "Rome"),
                (3, "Zurich"),
                (4, "Brussels & Luxembourg"),
                (5, "Iceland"),
            ])
        );
    }

    #[test]
    fn sparse_home_photos_and_weekends_inside_the_home_urban_area_are_not_trips() {
        let files = library(
            vec![
                stay(1000, "2024-03-08T10:00:00", 15, 240, LONG_BEACH),
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
}
