use std::collections::HashSet;

use super::count;
use super::places::{City, mentionable};
use crate::rewind::geo::distance_km;
use crate::rewind::library::YearFile;
use crate::rewind::ranking::Ranking;
use crate::rewind::report::{Tour, TourStop};

const TOUR_MINIMUM_STOPS: usize = 3;
const TOUR_STOPS: usize = 14;
const TOUR_MINIMUM_STOP_PHOTOS: usize = 3;
const TOUR_NEIGHBOUR_KM: f64 = 20.0;

pub(super) struct Stop<'c, 'l, 'r> {
    pub(super) city: &'c City<'l, 'r>,
    pub(super) first: &'l YearFile<'r>,
    pub(super) photos: usize,
    pub(super) cities: Vec<usize>,
}

pub(super) fn stops<'c, 'l, 'r>(
    cities: &'c [City<'l, 'r>],
    ranking: &Ranking<'_>,
) -> Vec<Stop<'c, 'l, 'r>> {
    let mut stops: Vec<Stop> = Vec::new();
    for (index, city) in cities.iter().enumerate() {
        if !city.files.iter().any(|file| ranking.is_showable(file)) {
            continue;
        }
        let taken: Vec<&YearFile> = city
            .files
            .iter()
            .copied()
            .filter(|file| file.is_taken())
            .collect();
        let Some(first) = taken
            .iter()
            .copied()
            .min_by_key(|file| (file.local_time, file.id()))
        else {
            continue;
        };
        if taken.len() < TOUR_MINIMUM_STOP_PHOTOS {
            continue;
        }
        match stops
            .iter_mut()
            .find(|bigger| distance_km(bigger.city.center, city.center) <= TOUR_NEIGHBOUR_KM)
        {
            Some(bigger) => {
                bigger.photos += taken.len();
                bigger.cities.push(index);
                if (first.local_time, first.id()) < (bigger.first.local_time, bigger.first.id()) {
                    bigger.first = first;
                }
            }
            None => stops.push(Stop {
                city,
                first,
                photos: taken.len(),
                cities: vec![index],
            }),
        }
    }
    stops
}

pub(super) fn countries<'c>(
    cities: &'c [City<'_, '_>],
    stops: &[Stop<'c, '_, '_>],
) -> HashSet<&'c str> {
    stops
        .iter()
        .flat_map(|stop| &stop.cities)
        .map(|&city| cities[city].country_code.as_str())
        .collect()
}

pub(in crate::rewind) fn tour(cities: &[City<'_, '_>], ranking: &Ranking<'_>) -> Option<Tour> {
    let cities = &mentionable(cities, ranking);
    let mut stops = stops(cities, ranking);
    if stops.len() < TOUR_MINIMUM_STOPS {
        return None;
    }
    let city_count = count(stops.len());
    let country_count = count(countries(cities, &stops).len());
    stops.sort_by(|first, second| {
        second
            .photos
            .cmp(&first.photos)
            .then_with(|| first.city.name.cmp(&second.city.name))
    });
    stops.truncate(TOUR_STOPS);
    stops.sort_by_key(|stop| (stop.first.local_time, stop.first.id()));
    Some(Tour {
        stops: stops
            .iter()
            .map(|stop| TourStop {
                city: stop.city.name.clone(),
                country_code: stop.city.country_code.clone(),
                month: stop.first.month,
                day: stop.first.day_of_month,
                photo_count: count(stop.photos),
            })
            .collect(),
        city_count,
        country_count,
    })
}

#[cfg(test)]
mod tests {
    use crate::rewind::chapters::places::cities;
    use crate::rewind::chapters::places::tests::Towns;
    use crate::rewind::fixtures::{located, photo, request};
    use crate::rewind::input::{RewindFile, RewindVisibility};
    use crate::rewind::library::Library;
    use crate::rewind::ranking::Ranking;

    use super::tour;

    fn towns() -> Towns {
        Towns(vec![
            ("Amsterdam", 52.37, 4.90),
            ("Utrecht", 52.09, 5.12),
            ("Rotterdam", 51.92, 4.48),
            ("Groningen", 53.22, 6.57),
        ])
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
    fn stops_follow_the_first_visit_to_each_city() {
        let mut files = visit(1, (52.09, 5.12), "2026-05-04", 6);
        files.extend(visit(100, (52.37, 4.90), "2026-02-11", 5));
        files.extend(visit(200, (52.37, 4.90), "2026-08-01", 5));
        files.extend(visit(300, (51.92, 4.48), "2026-09-20", 4));
        files.extend(visit(400, (53.22, 6.57), "2026-03-03", 2));
        let tour_request = request(files);
        let library = Library::of_year(&tour_request).unwrap();
        let cities = cities(&library, &towns()).unwrap();

        let tour = tour(&cities, &Ranking::new(None, None)).unwrap();

        let stops: Vec<(&str, u32, u32, u32)> = tour
            .stops
            .iter()
            .map(|stop| (stop.city.as_str(), stop.month, stop.day, stop.photo_count))
            .collect();
        assert_eq!(
            stops,
            [
                ("Amsterdam", 2, 11, 10),
                ("Utrecht", 5, 4, 6),
                ("Rotterdam", 9, 20, 4),
            ]
        );
        assert_eq!(tour.stops[0].country_code, "NL");
        assert_eq!((tour.city_count, tour.country_count), (3, 1));
    }

    #[test]
    fn a_neighbouring_town_joins_the_bigger_city() {
        let towns = Towns(vec![
            ("Amsterdam", 52.37, 4.90),
            ("Amstelveen", 52.30, 4.86),
            ("Utrecht", 52.09, 5.12),
            ("Rotterdam", 51.92, 4.48),
        ]);
        let mut files = visit(1, (52.37, 4.90), "2026-02-11", 8);
        files.extend(visit(100, (52.30, 4.86), "2026-02-03", 4));
        files.extend(visit(200, (52.09, 5.12), "2026-05-04", 6));
        files.extend(visit(300, (51.92, 4.48), "2026-09-20", 5));
        let tour_request = request(files);
        let library = Library::of_year(&tour_request).unwrap();
        let cities = cities(&library, &towns).unwrap();

        let tour = tour(&cities, &Ranking::new(None, None)).unwrap();

        let stops: Vec<(&str, u32, u32, u32)> = tour
            .stops
            .iter()
            .map(|stop| (stop.city.as_str(), stop.month, stop.day, stop.photo_count))
            .collect();
        assert_eq!(
            stops,
            [
                ("Amsterdam", 2, 3, 12),
                ("Utrecht", 5, 4, 6),
                ("Rotterdam", 9, 20, 5),
            ]
        );
        assert_eq!(tour.city_count, 3);
    }

    #[test]
    fn archived_photos_neither_date_nor_count_towards_a_stop() {
        let archived = |files: Vec<RewindFile>| {
            files.into_iter().map(|mut file| {
                file.visibility = RewindVisibility::Archived;
                file
            })
        };
        let mut files = visit(1, (52.37, 4.90), "2026-02-11", 5);
        files.extend(archived(visit(50, (52.37, 4.90), "2026-01-05", 4)));
        files.extend(visit(100, (52.09, 5.12), "2026-05-04", 6));
        files.extend(visit(200, (51.92, 4.48), "2026-09-20", 4));
        files.extend(visit(300, (53.22, 6.57), "2026-03-03", 1));
        files.extend(archived(visit(350, (53.22, 6.57), "2026-03-04", 2)));
        let tour_request = request(files);
        let library = Library::of_year(&tour_request).unwrap();
        let cities = cities(&library, &towns()).unwrap();

        let tour = tour(&cities, &Ranking::new(None, None)).unwrap();

        let stops: Vec<(&str, u32, u32, u32)> = tour
            .stops
            .iter()
            .map(|stop| (stop.city.as_str(), stop.month, stop.day, stop.photo_count))
            .collect();
        assert_eq!(
            stops,
            [
                ("Amsterdam", 2, 11, 5),
                ("Utrecht", 5, 4, 6),
                ("Rotterdam", 9, 20, 4),
            ]
        );
        assert_eq!(tour.city_count, 3);
    }

    #[test]
    fn fewer_than_three_cities_is_not_a_tour() {
        let mut files = visit(1, (52.09, 5.12), "2026-05-04", 12);
        files.extend(visit(100, (52.37, 4.90), "2026-02-11", 12));
        let short = request(files);
        let library = Library::of_year(&short).unwrap();
        let cities = cities(&library, &towns()).unwrap();
        assert_eq!(tour(&cities, &Ranking::new(None, None)), None);
    }
}
