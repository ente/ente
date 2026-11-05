use std::cmp::Reverse;
use std::collections::{HashMap, HashSet};

use ente_location::{Coordinate, CountryCode};

use super::{AWAY_MIN_KM, Placed};
use crate::memories::calendar::LocalDate;
use crate::memories::geo::{Located, cluster_by_location, distance_km, merge_nearby_clusters};
use crate::memories::input::CityLookup;

const HOME_RADIUS_KM: f64 = 0.6;
const HOME_MERGE_RADIUS_KM: f64 = 1.5;
const HOME_WINDOW_DAYS: i64 = 182;
const HOME_MIN_DAYS: usize = 6;
const HOME_MIN_MONTHS: usize = 3;
const HOME_MARGIN_DAYS: i64 = 60;
const RESIDENCE_DAY_SHARE: f64 = 0.2;
const REGULAR_PLACE_RADIUS_KM: f64 = 2.0;
const STAY_GAP_DAYS: i64 = 7;

type DayRanges = Vec<(i64, i64)>;

pub(super) struct Home<'p> {
    pub(super) members: Vec<Located<'p>>,
    pub(super) center: Coordinate,
    country: Option<CountryCode>,
    urban_center: Option<u32>,
    residence: DayRanges,
    stays: DayRanges,
    regular: DayRanges,
}

impl Home<'_> {
    pub(super) fn covers(&self, day: i64) -> bool {
        self.lived_in(day) || days_outside(&self.regular, day) == 0
    }

    fn lived_in(&self, day: i64) -> bool {
        days_outside(&self.residence, day) == 0 || days_outside(&self.stays, day) == 0
    }

    fn is_residence(&self) -> bool {
        !self.residence.is_empty()
    }

    fn surrounds(&self, point: &Placed) -> bool {
        distance_km(self.center, point.member.location) < AWAY_MIN_KM
            || (self.urban_center.is_some() && self.urban_center == point.urban_center)
    }

    fn shares_area_with(&self, other: &Home) -> bool {
        distance_km(self.center, other.center) < AWAY_MIN_KM
            || (self.urban_center.is_some() && self.urban_center == other.urban_center)
    }
}

pub(super) struct Homes<'p> {
    homes: Vec<Home<'p>>,
}

impl<'p> Homes<'p> {
    pub(super) fn detect(points: &[Placed<'p>], lookup: Option<&dyn CityLookup>) -> Self {
        let all_days = distinct_days(points.iter().map(|point| point.member));
        let clusters = merge_nearby_clusters(
            cluster_by_location(points.iter().map(|point| point.member), HOME_RADIUS_KM),
            HOME_MERGE_RADIUS_KM,
        );
        let mut homes: Vec<Home<'p>> = clusters
            .into_iter()
            .map(|cluster| {
                let (residence, regular) = periods(&cluster.members, &all_days);
                let stays = stays(&cluster.members, &residence, &regular);
                Home {
                    members: cluster.members,
                    center: cluster.center,
                    country: None,
                    urban_center: None,
                    residence,
                    stays,
                    regular,
                }
            })
            .collect();
        if !homes.iter().any(Home::is_residence)
            && let Some(busiest) = homes
                .iter_mut()
                .max_by_key(|home| distinct_days(home.members.iter().copied()).len())
        {
            busiest.residence = vec![(i64::MIN, i64::MAX)];
        }
        homes.retain(|home| home.is_residence() || !home.regular.is_empty());
        let centers: Vec<Coordinate> = homes.iter().map(|home| home.center).collect();
        let urban_centers = lookup.map_or_else(Vec::new, |lookup| lookup.urban_centers(&centers));
        let countries = lookup.map_or_else(Vec::new, |lookup| lookup.countries(&centers));
        let country_of_photo: HashMap<i64, CountryCode> = points
            .iter()
            .filter_map(|point| {
                point
                    .country
                    .map(|country| (point.member.photo.id, country))
            })
            .collect();
        for (index, home) in homes.iter_mut().enumerate() {
            home.urban_center = urban_centers.get(index).copied().flatten();
            home.country = countries
                .get(index)
                .copied()
                .flatten()
                .or_else(|| most_common_country(&home.members, &country_of_photo));
        }
        Self { homes }
    }

    pub(super) fn contains(&self, point: &Placed) -> bool {
        let day = point.member.photo.date.days_since_epoch();
        self.residences(day).any(|home| home.surrounds(point))
            || self.homes.iter().any(|home| {
                days_outside(&home.regular, day) == 0
                    && distance_km(home.center, point.member.location) < REGULAR_PLACE_RADIUS_KM
            })
    }

    pub(super) fn distance_km(&self, day: i64, location: Coordinate) -> f64 {
        self.residences(day)
            .map(|home| distance_km(home.center, location))
            .reduce(f64::min)
            .unwrap_or(f64::INFINITY)
    }

    pub(super) fn areas(&self) -> Vec<Vec<&Home<'p>>> {
        let mut largest_first: Vec<&Home> = self.homes.iter().collect();
        largest_first.sort_by_key(|home| Reverse(home.members.len()));
        let mut areas: Vec<Vec<&Home>> = Vec::new();
        for home in largest_first {
            match areas.iter_mut().find(|area| area[0].shares_area_with(home)) {
                Some(area) => area.push(home),
                None => areas.push(vec![home]),
            }
        }
        areas
    }

    pub(super) fn countries(&self) -> HashSet<CountryCode> {
        self.homes
            .iter()
            .filter(|home| home.is_residence() || !home.stays.is_empty())
            .filter_map(|home| home.country)
            .collect()
    }

    fn residences(&self, day: i64) -> impl Iterator<Item = &Home<'p>> {
        let nearest = self
            .homes
            .iter()
            .filter(|home| home.is_residence())
            .map(|home| days_outside(&home.residence, day))
            .min();
        self.homes.iter().filter(move |home| {
            home.lived_in(day)
                || (home.is_residence() && Some(days_outside(&home.residence, day)) == nearest)
        })
    }
}

fn days_outside(periods: &[(i64, i64)], day: i64) -> i64 {
    periods
        .iter()
        .map(|&(first, last)| {
            if day < first {
                first - day
            } else if day > last {
                day - last
            } else {
                0
            }
        })
        .min()
        .unwrap_or(i64::MAX)
}

fn distinct_days<'p>(members: impl IntoIterator<Item = Located<'p>>) -> Vec<LocalDate> {
    let mut days: Vec<LocalDate> = members
        .into_iter()
        .map(|member| member.photo.date)
        .collect();
    days.sort_by_key(|day| day.days_since_epoch());
    days.dedup();
    days
}

fn periods(members: &[Located], all_days: &[LocalDate]) -> (DayRanges, DayRanges) {
    let days = distinct_days(members.iter().copied());
    let numbers: Vec<i64> = days.iter().map(|day| day.days_since_epoch()).collect();
    let (mut residence, mut regular) = (Vec::new(), Vec::new());
    let (mut start, mut end) = (0, 0);
    for &day in &numbers {
        while numbers[start] < day - HOME_WINDOW_DAYS {
            start += 1;
        }
        while end < numbers.len() && numbers[end] <= day + HOME_WINDOW_DAYS {
            end += 1;
        }
        let months: HashSet<(i32, i32)> = days[start..end]
            .iter()
            .map(|day| (day.year, day.month))
            .collect();
        if end - start < HOME_MIN_DAYS || months.len() < HOME_MIN_MONTHS {
            continue;
        }
        let all = all_days
            .partition_point(|other| other.days_since_epoch() <= day + HOME_WINDOW_DAYS)
            - all_days.partition_point(|other| other.days_since_epoch() < day - HOME_WINDOW_DAYS);
        let periods = if (end - start) as f64 >= all as f64 * RESIDENCE_DAY_SHARE {
            &mut residence
        } else {
            &mut regular
        };
        extend(periods, day - HOME_MARGIN_DAYS, day + HOME_MARGIN_DAYS);
    }
    (residence, regular)
}

fn stays(members: &[Located], residence: &[(i64, i64)], regular: &[(i64, i64)]) -> DayRanges {
    let days: Vec<i64> = distinct_days(members.iter().copied())
        .iter()
        .map(|day| day.days_since_epoch())
        .collect();
    let mut stays = Vec::new();
    let mut start = 0;
    for end in 1..=days.len() {
        if end == days.len() || days[end] - days[end - 1] > STAY_GAP_DAYS {
            let (first, last) = (days[start], days[end - 1]);
            if last > first
                && (days_outside(residence, first) == 0 || days_outside(regular, first) == 0)
            {
                stays.push((first, last));
            }
            start = end;
        }
    }
    stays
}

fn extend(periods: &mut DayRanges, first: i64, last: i64) {
    match periods.last_mut() {
        Some(period) if period.1 >= first => period.1 = period.1.max(last),
        _ => periods.push((first, last)),
    }
}

fn most_common_country(
    members: &[Located],
    country_of_photo: &HashMap<i64, CountryCode>,
) -> Option<CountryCode> {
    let mut counts: HashMap<CountryCode, usize> = HashMap::new();
    for member in members {
        if let Some(&country) = country_of_photo.get(&member.photo.id) {
            *counts.entry(country).or_default() += 1;
        }
    }
    counts
        .into_iter()
        .max_by_key(|&(country, count)| (count, Reverse(country)))
        .map(|(country, _)| country)
}
