use std::collections::{HashMap, HashSet};

use ente_location::CountryCode;

use super::Placed;
use crate::memories::geo::{Located, distance_km};
use crate::memories::input::CityLookup;
use crate::memories::places::{CityPhotos, Places};

const DOMINANT_COUNTRY_SHARE: f64 = 0.8;
const SIGNIFICANT_CITY_SHARE: f64 = 0.1;
const CITY_OVER_COUNTRY_SHARE: f64 = 0.75;
const SPREAD_OUT_KM: f64 = 100.0;

pub(super) fn trip_name(
    points: &[Placed],
    places: &Places,
    home_countries: &HashSet<CountryCode>,
    lookup: Option<&dyn CityLookup>,
) -> Option<String> {
    let foreign: Vec<Placed> = points
        .iter()
        .copied()
        .filter(|point| {
            point
                .country
                .is_some_and(|country| !home_countries.contains(&country))
        })
        .collect();
    let points: &[Placed] = if foreign.len() * 2 > points.len() {
        &foreign
    } else {
        points
    };
    let members: Vec<Located> = points.iter().map(|point| point.member).collect();
    let cities = places.cities(&members);
    let foreign_country = dominant_country(points)
        .filter(|country| !home_countries.contains(country))
        .and_then(|country| lookup?.country_name(country));
    let Some(top) = cities.first() else {
        return foreign_country;
    };
    let significant: Vec<&CityPhotos> = cities
        .iter()
        .filter(|city| city.photos as f64 >= points.len() as f64 * SIGNIFICANT_CITY_SHARE)
        .collect();
    if foreign_country.is_some()
        && (top.photos as f64) < points.len() as f64 * CITY_OVER_COUNTRY_SHARE
        && spread_km(&significant) >= SPREAD_OUT_KM
    {
        return foreign_country;
    }
    if top.photos * 2 > points.len() {
        return Some(top.name.to_owned());
    }
    let pair_covers_trip = significant.len() == 2
        && (significant[0].photos + significant[1].photos) * 2 > points.len();
    if !pair_covers_trip && let Some(country) = foreign_country {
        return Some(country);
    }
    Some(match significant.get(1) {
        Some(second) => format!("{} & {}", top.name, second.name),
        None => top.name.to_owned(),
    })
}

fn spread_km(cities: &[&CityPhotos]) -> f64 {
    cities
        .iter()
        .flat_map(|city| {
            cities
                .iter()
                .map(|other| distance_km(city.location, other.location))
        })
        .fold(0.0, f64::max)
}

fn dominant_country(points: &[Placed]) -> Option<CountryCode> {
    let mut counts: HashMap<CountryCode, usize> = HashMap::new();
    for country in points.iter().filter_map(|point| point.country) {
        *counts.entry(country).or_default() += 1;
    }
    let known: usize = counts.values().sum();
    counts
        .into_iter()
        .find(|&(_, count)| count as f64 >= known as f64 * DOMINANT_COUNTRY_SHARE)
        .map(|(country, _)| country)
}
