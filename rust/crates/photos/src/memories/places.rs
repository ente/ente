use std::cmp::Reverse;
use std::collections::{HashMap, HashSet};

use ente_location::{Coordinate, CountryCode};

use super::geo::Located;
use super::input::CityLookup;

#[derive(Debug)]
struct Place {
    city: String,
    country: String,
    country_code: CountryCode,
}

#[derive(Debug, Default)]
pub(super) struct Places {
    places: Vec<Place>,
    place_of_photo: HashMap<i64, usize>,
}

struct Tally {
    biggest: usize,
    biggest_count: usize,
    place_count: usize,
    single_country: bool,
}

impl Places {
    pub(super) fn new(members: &[Located], lookup: Option<&dyn CityLookup>) -> Self {
        let mut places = Self::default();
        let Some(lookup) = lookup else {
            return places;
        };
        let coordinates: Vec<Coordinate> = members.iter().map(|member| member.location).collect();
        for group in lookup.group_cities(&coordinates) {
            let index = places.places.len();
            places.places.push(Place {
                city: group.city.name,
                country: group.city.country_name,
                country_code: group.city.country_code,
            });
            for position in group.coordinate_indices {
                if let Some(member) = members.get(position as usize) {
                    places.place_of_photo.insert(member.photo.id, index);
                }
            }
        }
        places
    }

    pub(super) fn trip_name(
        &self,
        members: &[Located],
        excluded_countries: &HashSet<String>,
    ) -> Option<String> {
        let tally = self.tally(members)?;
        let biggest = &self.places[tally.biggest];
        if tally.biggest_count as f64 > members.len() as f64 / 2.0 {
            return Some(biggest.city.clone());
        }
        (tally.place_count > 2
            && tally.single_country
            && !excluded_countries.contains(&normalized(&biggest.country)))
        .then(|| biggest.country.clone())
    }

    pub(super) fn base_name(&self, members: &[Located]) -> Option<String> {
        let tally = self.tally(members)?;
        (tally.biggest_count as f64 > members.len() as f64 / 2.0)
            .then(|| self.places[tally.biggest].city.clone())
    }

    pub(super) fn normalized_country(&self, members: &[Located]) -> Option<String> {
        let tally = self.tally(members)?;
        Some(normalized(&self.places[tally.biggest].country)).filter(|country| !country.is_empty())
    }

    pub(super) fn country_code(&self, photo_id: i64) -> Option<CountryCode> {
        self.place_of_photo
            .get(&photo_id)
            .map(|&place| self.places[place].country_code)
    }

    pub(super) fn city_counts(&self, members: &[Located]) -> Vec<(&str, usize)> {
        let mut counts: Vec<(usize, usize)> = self.place_counts(members).into_iter().collect();
        counts.sort_by_key(|&(place, count)| (Reverse(count), place));
        counts
            .into_iter()
            .map(|(place, count)| (self.places[place].city.as_str(), count))
            .collect()
    }

    fn place_counts(&self, members: &[Located]) -> HashMap<usize, usize> {
        let mut counts: HashMap<usize, usize> = HashMap::new();
        for member in members {
            if let Some(&place) = self.place_of_photo.get(&member.photo.id) {
                *counts.entry(place).or_default() += 1;
            }
        }
        counts
    }

    fn tally(&self, members: &[Located]) -> Option<Tally> {
        let counts = self.place_counts(members);
        let (&biggest, &biggest_count) = counts
            .iter()
            .max_by_key(|&(&place, &count)| (count, Reverse(place)))?;
        let countries: HashSet<&str> = counts
            .keys()
            .map(|&place| self.places[place].country.as_str())
            .collect();
        Some(Tally {
            biggest,
            biggest_count,
            place_count: counts.len(),
            single_country: countries.len() == 1,
        })
    }
}

fn normalized(place_name: &str) -> String {
    place_name.trim().to_lowercase()
}
