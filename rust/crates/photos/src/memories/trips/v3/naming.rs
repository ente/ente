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
    let cities = places.city_counts(&members);
    let foreign_country = dominant_country(points)
        .filter(|country| !home_countries.contains(country))
        .and_then(|country| lookup?.country_name(country));
    let Some(&(top, top_count)) = cities.first() else {
        return foreign_country;
    };
    if top_count * 2 > points.len() {
        return Some(top.to_owned());
    }
    let is_significant =
        |count: usize| count as f64 >= points.len() as f64 * SIGNIFICANT_CITY_SHARE;
    let significant = cities
        .iter()
        .filter(|&&(_, count)| is_significant(count))
        .count();
    let pair_covers_trip = significant == 2
        && cities
            .get(1)
            .is_some_and(|&(_, second_count)| (top_count + second_count) * 2 > points.len());
    if !pair_covers_trip && let Some(country) = foreign_country {
        return Some(country);
    }
    Some(match cities.get(1) {
        Some(&(second, count)) if is_significant(count) => format!("{top} & {second}"),
        _ => top.to_owned(),
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
