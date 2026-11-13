use std::collections::{HashMap, HashSet};

use ente_location::Coordinate;

use super::count;
use super::places::{City, stays, travelled_km};
use super::tour::stops;
use crate::memories::CityLookup;
use crate::rewind::ranking::{Ranking, Spread};
use crate::rewind::report::{Globe, GlobePlace};

const GLOBE_ROWS: usize = 96;
const GLOBE_PLACES: usize = 40;
const GLOBE_LEGS: usize = 80;
const GLOBE_PLACE_PHOTOS: usize = 3;
const MICRODEGREES: f64 = 1_000_000.0;

pub(in crate::rewind) fn globe(
    cities: &[City<'_, '_>],
    lookup: &dyn CityLookup,
    ranking: &Ranking<'_>,
) -> Option<Globe> {
    let mut stops = stops(cities);
    let city_count = count(stops.len());
    let visited: HashSet<&str> = stops
        .iter()
        .map(|stop| stop.city.country_code.as_str())
        .collect();
    stops.truncate(GLOBE_PLACES);
    let place_of: HashMap<usize, u32> = stops
        .iter()
        .zip(0..)
        .flat_map(|(stop, place)| stop.cities.iter().map(move |&city| (city, place)))
        .collect();
    let mut route: Vec<u32> = Vec::new();
    for place in stays(cities)
        .iter()
        .filter_map(|city| place_of.get(city).copied())
    {
        if route.last() != Some(&place) {
            route.push(place);
        }
    }
    route.truncate(GLOBE_LEGS + 1);
    if route.len() < 2 {
        return None;
    }
    let rows: Vec<u32> = (0..GLOBE_ROWS).map(dots_in_row).collect();
    let dots: Vec<Coordinate> = rows
        .iter()
        .enumerate()
        .flat_map(|(row, &dots)| {
            let latitude = -90.0 + (row as f64 + 0.5) * 180.0 / GLOBE_ROWS as f64;
            (0..dots).map(move |dot| {
                Coordinate::new(
                    latitude,
                    -180.0 + (f64::from(dot) + 0.5) * 360.0 / f64::from(dots),
                )
            })
        })
        .collect();
    let countries = lookup.countries(&dots);
    Some(Globe {
        rows,
        land: bits(countries.iter().map(Option::is_some)),
        visited: bits(
            countries
                .iter()
                .map(|country| country.is_some_and(|country| visited.contains(country.as_str()))),
        ),
        places: stops
            .iter()
            .map(|stop| GlobePlace {
                name: stop.city.name.clone(),
                country_code: stop.city.country_code.clone(),
                latitude_microdegrees: (stop.city.center.latitude * MICRODEGREES).round() as i32,
                longitude_microdegrees: (stop.city.center.longitude * MICRODEGREES).round() as i32,
                photo_count: count(stop.photos),
                file_ids: ranking.best(
                    stop.city.files.iter().copied(),
                    Spread::Days,
                    GLOBE_PLACE_PHOTOS,
                ),
            })
            .collect(),
        route,
        distance_km: travelled_km(cities).round() as u32,
        city_count,
        country_count: count(visited.len()),
    })
}

fn dots_in_row(row: usize) -> u32 {
    let latitude = -90.0 + (row as f64 + 0.5) * 180.0 / GLOBE_ROWS as f64;
    ((2 * GLOBE_ROWS) as f64 * latitude.to_radians().cos())
        .round()
        .max(1.0) as u32
}

fn bits(flags: impl Iterator<Item = bool>) -> Vec<u8> {
    let mut bytes = Vec::new();
    for (position, flag) in flags.enumerate() {
        if position % 8 == 0 {
            bytes.push(0);
        }
        if flag && let Some(byte) = bytes.last_mut() {
            *byte |= 1 << (position % 8);
        }
    }
    bytes
}

#[cfg(test)]
mod tests {
    use ente_location::{CityMatch, Coordinate, CountryCode};

    use crate::memories::CityLookup;
    use crate::rewind::chapters::places::cities;
    use crate::rewind::chapters::places::tests::Towns;
    use crate::rewind::fixtures::{located, photo, request};
    use crate::rewind::input::RewindFile;
    use crate::rewind::library::Library;
    use crate::rewind::ranking::Ranking;

    use super::{bits, globe};

    struct LowCountries(Towns);

    impl CityLookup for LowCountries {
        fn group_cities(&self, coordinates: &[Coordinate]) -> Vec<CityMatch> {
            self.0.group_cities(coordinates)
        }

        fn urban_centers(&self, coordinates: &[Coordinate]) -> Vec<Option<u32>> {
            vec![None; coordinates.len()]
        }

        fn countries(&self, coordinates: &[Coordinate]) -> Vec<Option<CountryCode>> {
            coordinates
                .iter()
                .map(|coordinate| {
                    let within = |south: f64, north: f64, west: f64, east: f64| {
                        (south..north).contains(&coordinate.latitude)
                            && (west..east).contains(&coordinate.longitude)
                    };
                    let code = if within(50.0, 54.0, 3.0, 8.0) {
                        b"NL"
                    } else if within(40.0, 50.0, -5.0, 3.0) {
                        b"FR"
                    } else {
                        return None;
                    };
                    CountryCode::from_bytes(*code).ok()
                })
                .collect()
        }

        fn country_name(&self, _country: CountryCode) -> Option<String> {
            None
        }
    }

    fn visit(first_id: i64, town: (f64, f64), date: &str, photos: i64) -> Vec<RewindFile> {
        (0..photos)
            .map(|shot| {
                located(
                    photo(first_id + shot, &format!("{date}T{:02}:00:00", 8 + shot)),
                    town.0,
                    town.1,
                )
            })
            .collect()
    }

    #[test]
    fn the_route_follows_every_stay_and_the_dots_mark_land_and_visited_countries() {
        let lookup = LowCountries(Towns(vec![
            ("Amsterdam", 52.37, 4.90),
            ("Utrecht", 52.09, 5.12),
            ("Groningen", 53.22, 6.57),
        ]));
        let mut files = visit(1, (52.37, 4.90), "2026-02-01", 9);
        files.extend(visit(100, (53.22, 6.57), "2026-03-01", 5));
        files.extend(visit(200, (52.37, 4.90), "2026-04-01", 9));
        files.extend(visit(300, (52.09, 5.12), "2026-05-01", 4));
        let globe_request = request(files);
        let library = Library::of_year(&globe_request).unwrap();
        let cities = cities(&library, &lookup).unwrap();

        let globe = globe(&cities, &lookup, &Ranking::new(None, None)).unwrap();

        let names: Vec<&str> = globe
            .places
            .iter()
            .map(|place| place.name.as_str())
            .collect();
        assert_eq!(names, ["Amsterdam", "Groningen", "Utrecht"]);
        assert_eq!(globe.route, [0, 1, 0, 2]);
        assert_eq!(globe.places[0].latitude_microdegrees, 52_370_000);
        assert_eq!(globe.places[0].file_ids.len(), 3);
        assert_eq!(globe.city_count, 3);
        assert_eq!(globe.country_count, 1);
        assert_eq!(globe.rows.len(), 96);
        let dots: u32 = globe.rows.iter().sum();
        assert_eq!(globe.land.len(), (dots as usize).div_ceil(8));
        let ones = |bytes: &[u8]| bytes.iter().map(|byte| byte.count_ones()).sum::<u32>();
        assert!(ones(&globe.visited) > 0);
        assert!(ones(&globe.land) > ones(&globe.visited));
    }

    #[test]
    fn a_year_in_one_place_has_no_globe() {
        let lookup = LowCountries(Towns(vec![("Amsterdam", 52.37, 4.90)]));
        let mut files = visit(1, (52.37, 4.90), "2026-02-01", 12);
        files.extend(visit(100, (52.37, 4.90), "2026-02-02", 12));
        let home = request(files);
        let library = Library::of_year(&home).unwrap();
        let cities = cities(&library, &lookup).unwrap();
        assert_eq!(globe(&cities, &lookup, &Ranking::new(None, None)), None);
        assert_eq!(bits([true, false, false, true].into_iter()), [0b1001]);
    }
}
