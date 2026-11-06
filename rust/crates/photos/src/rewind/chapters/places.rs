use ente_location::Coordinate;

use super::count;
use crate::memories::CityLookup;
use crate::rewind::geo::distance_km;
use crate::rewind::library::{Library, YearFile};
use crate::rewind::ranking::{Ranking, Spread};
use crate::rewind::report::{Places, RewindCity};

const PLACES_MINIMUM_LOCATED: usize = 20;
const PLACES_MINIMUM_CITIES: usize = 3;
const PLACES_CITIES: usize = 6;
const PLACES_CITY_CANDIDATES: usize = 3;
const PLACES_MINIMUM_VISIT_PHOTOS: usize = 2;

struct City<'l, 'r> {
    name: String,
    country: String,
    center: Coordinate,
    files: Vec<&'l YearFile<'r>>,
}

pub(in crate::rewind) fn places(
    library: &Library<'_>,
    lookup: &dyn CityLookup,
    ranking: &Ranking<'_>,
) -> Option<Places> {
    let located: Vec<(&YearFile, Coordinate)> = library
        .eligible()
        .filter_map(|file| Some((file, file.location()?)))
        .collect();
    if located.len() < PLACES_MINIMUM_LOCATED {
        return None;
    }
    let coordinates: Vec<Coordinate> = located.iter().map(|&(_, location)| location).collect();
    let mut cities: Vec<City> = lookup
        .group_cities(&coordinates)
        .into_iter()
        .map(|group| City {
            name: group.city.name,
            country: group.city.country_name,
            center: Coordinate::new(group.city.latitude, group.city.longitude),
            files: group
                .coordinate_indices
                .iter()
                .filter_map(|&position| Some(located.get(position as usize)?.0))
                .collect(),
        })
        .filter(|city| !city.files.is_empty())
        .collect();
    cities.sort_by(|first, second| {
        second
            .files
            .len()
            .cmp(&first.files.len())
            .then_with(|| first.name.cmp(&second.name))
    });
    let listed: Vec<RewindCity> = cities
        .iter()
        .filter_map(|city| {
            let file_ids = ranking.best(
                city.files.iter().copied(),
                Spread::Days,
                PLACES_CITY_CANDIDATES,
            );
            (!file_ids.is_empty()).then(|| RewindCity {
                name: city.name.clone(),
                country: city.country.clone(),
                photo_count: count(city.files.len()),
                file_ids,
            })
        })
        .take(PLACES_CITIES)
        .collect();
    (listed.len() >= PLACES_MINIMUM_CITIES).then(|| Places {
        distance_km: travelled_km(&cities).round() as u32,
        cities: listed,
    })
}

fn travelled_km(cities: &[City<'_, '_>]) -> f64 {
    let mut visits: Vec<(i64, i64, usize)> = cities
        .iter()
        .enumerate()
        .flat_map(|(city, place)| {
            place
                .files
                .iter()
                .filter(|file| file.is_taken())
                .map(move |file| (file.file.creation_time, file.id(), city))
        })
        .collect();
    visits.sort_unstable();
    let runs = collapse(visits.into_iter().map(|(_, _, city)| (city, 1)));
    let stays = collapse(
        runs.into_iter()
            .filter(|&(_, photos)| photos >= PLACES_MINIMUM_VISIT_PHOTOS),
    );
    stays
        .windows(2)
        .map(|pair| distance_km(cities[pair[0].0].center, cities[pair[1].0].center))
        .sum()
}

fn collapse(visits: impl IntoIterator<Item = (usize, usize)>) -> Vec<(usize, usize)> {
    let mut runs: Vec<(usize, usize)> = Vec::new();
    for (city, photos) in visits {
        match runs.last_mut() {
            Some((last, total)) if *last == city => *total += photos,
            _ => runs.push((city, photos)),
        }
    }
    runs
}

#[cfg(test)]
pub(in crate::rewind) mod tests {
    use ente_location::{City, CityMatch, Coordinate, CountryCode};

    use crate::memories::CityLookup;
    use crate::rewind::fixtures::{located, photo, request};
    use crate::rewind::geo::distance_km;
    use crate::rewind::input::RewindVisibility;
    use crate::rewind::library::Library;
    use crate::rewind::ranking::Ranking;

    use super::places;

    pub(in crate::rewind) struct Towns(pub(in crate::rewind) Vec<(&'static str, f64, f64)>);

    impl CityLookup for Towns {
        fn group_cities(&self, coordinates: &[Coordinate]) -> Vec<CityMatch> {
            self.0
                .iter()
                .enumerate()
                .filter_map(|(index, &(name, latitude, longitude))| {
                    let coordinate_indices: Vec<u32> = coordinates
                        .iter()
                        .enumerate()
                        .filter(|(_, coordinate)| {
                            (coordinate.latitude - latitude).abs() < 0.01
                                && (coordinate.longitude - longitude).abs() < 0.01
                        })
                        .map(|(position, _)| position as u32)
                        .collect();
                    (!coordinate_indices.is_empty()).then(|| CityMatch {
                        city: City {
                            point_index: index as u32,
                            source_id: index as u32,
                            name: name.to_string(),
                            country_name: "Netherlands".to_string(),
                            country_code: CountryCode::from_bytes(*b"NL").unwrap(),
                            latitude,
                            longitude,
                            rank: 0,
                        },
                        coordinate_indices,
                    })
                })
                .collect()
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

    fn towns() -> Towns {
        Towns(vec![
            ("Amsterdam", 52.37, 4.90),
            ("Utrecht", 52.09, 5.12),
            ("Rotterdam", 51.92, 4.48),
            ("Groningen", 53.22, 6.57),
            ("Leiden", 52.16, 4.49),
        ])
    }

    #[test]
    fn cities_rank_by_photos_and_distance_skips_single_photo_visits() {
        let mut files = Vec::new();
        let mut id = 0;
        let mut visit = |files: &mut Vec<_>, town: (f64, f64), day: u32, photos: usize| {
            for hour in 0..photos {
                id += 1;
                files.push(located(
                    photo(id, &format!("2026-03-{day:02}T{:02}:00:00", hour + 8)),
                    town.0,
                    town.1,
                ));
            }
        };
        visit(&mut files, (52.37, 4.90), 1, 10);
        visit(&mut files, (53.22, 6.57), 2, 1);
        visit(&mut files, (52.37, 4.90), 3, 2);
        visit(&mut files, (52.09, 5.12), 4, 6);
        visit(&mut files, (51.92, 4.48), 5, 6);
        visit(&mut files, (53.22, 6.57), 6, 2);
        for file in &mut files[25..] {
            file.is_junk = true;
        }
        let request = request(files);
        let library = Library::of_year(&request).unwrap();

        let places = places(&library, &towns(), &Ranking::new(None, None)).unwrap();

        let names: Vec<&str> = places
            .cities
            .iter()
            .map(|city| city.name.as_str())
            .collect();
        assert_eq!(names, ["Amsterdam", "Rotterdam", "Utrecht", "Groningen"]);
        assert_eq!(places.cities[3].photo_count, 3);
        assert_eq!(places.cities[0].photo_count, 12);
        assert_eq!(places.cities[0].file_ids, [1, 12, 2]);
        let [amsterdam, utrecht, rotterdam] = [(52.37, 4.90), (52.09, 5.12), (51.92, 4.48)]
            .map(|(latitude, longitude)| Coordinate::new(latitude, longitude));
        let expected = distance_km(amsterdam, utrecht) + distance_km(utrecht, rotterdam);
        assert_eq!(places.distance_km, expected.round() as u32);
    }

    #[test]
    fn too_few_cities_or_located_photos_skip_the_chapter_and_hidden_photos_never_count() {
        let mut files: Vec<_> = (1..=18)
            .map(|id| located(photo(id, "2026-04-01T10:00:00"), 52.37, 4.90))
            .collect();
        files.push(located(photo(19, "2026-04-02T10:00:00"), 52.09, 5.12));
        let mut hidden = located(photo(20, "2026-04-03T10:00:00"), 51.92, 4.48);
        hidden.visibility = RewindVisibility::Hidden;
        files.push(hidden);
        let too_few = request(files.clone());
        let library = Library::of_year(&too_few).unwrap();
        assert_eq!(places(&library, &towns(), &Ranking::new(None, None)), None);

        files.push(located(photo(21, "2026-04-04T10:00:00"), 51.92, 4.48));
        let mut archived = located(photo(22, "2026-04-05T10:00:00"), 52.16, 4.49);
        archived.visibility = RewindVisibility::Archived;
        files.push(archived);
        let enough = request(files);
        let library = Library::of_year(&enough).unwrap();
        let places = places(&library, &towns(), &Ranking::new(None, None)).unwrap();
        let names: Vec<&str> = places
            .cities
            .iter()
            .map(|city| city.name.as_str())
            .collect();
        assert_eq!(names, ["Amsterdam", "Rotterdam", "Utrecht"]);
        assert_eq!(places.cities[1].photo_count, 1);
    }
}
