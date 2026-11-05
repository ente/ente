use std::collections::{HashMap, HashSet};

use ente_location::CountryCode;

use super::Placed;
use crate::memories::geo::Located;
use crate::memories::input::CityLookup;
use crate::memories::places::Places;

const DOMINANT_COUNTRY_SHARE: f64 = 0.8;
const SIGNIFICANT_CITY_SHARE: f64 = 0.1;

pub(super) fn trip_name(
    points: &[Placed],
    places: &Places,
    home_countries: &HashSet<CountryCode>,
    lookup: Option<&dyn CityLookup>,
) -> Option<String> {
    let members: Vec<Located> = points.iter().map(|point| point.member).collect();
    let cities = places.city_counts(&members);
    let foreign_country = dominant_country(points)
        .filter(|country| !home_countries.contains(country))
        .and_then(|country| lookup?.country_name(country));
    let Some(&(top, top_count)) = cities.first() else {
        return foreign_country;
    };
    let named: usize = cities.iter().map(|&(_, count)| count).sum();
    if top_count * 2 > named {
        return Some(top.to_owned());
    }
    let significant = cities
        .iter()
        .filter(|&&(_, count)| count as f64 >= named as f64 * SIGNIFICANT_CITY_SHARE)
        .count();
    if significant != 2
        && let Some(country) = foreign_country
    {
        return Some(country);
    }
    Some(match cities.get(1) {
        Some(&(second, _)) => format!("{top} & {second}"),
        None => top.to_owned(),
    })
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
