use std::collections::{BTreeSet, HashSet};

use ente_location::Coordinate;

use crate::memories::calendar::{LocalDate, MICROS_PER_DAY};
use crate::memories::geo::{Cluster, Located, cluster_by_location, merge_nearby_clusters};

const BASE_RADIUS_KM: f64 = 0.6;
const BASE_MERGE_RADIUS_KM: f64 = 1.5;
const MIN_BASE_PHOTOS: usize = 10;
const MIN_BASE_ACTIVE_DAYS: usize = 10;
const MIN_BASE_ACTIVE_WEEKS: usize = 6;
const MIN_BASE_ACTIVE_MONTHS: usize = 2;
const MIN_BASE_SPAN_DAYS: i64 = 45;
const BASE_DENSITY_WINDOW_DAYS: i64 = 120;
const MIN_BASE_ACTIVE_DAYS_IN_WINDOW: usize = 12;
const CURRENT_BASE_DAYS: i64 = 90;

pub(in crate::memories) struct Base<'p> {
    pub(in crate::memories) members: Vec<Located<'p>>,
    pub(in crate::memories) location: Coordinate,
    pub(in crate::memories) is_current: bool,
}

pub(super) fn detect<'p>(members: &[Located<'p>], now: i64) -> Vec<Base<'p>> {
    let clusters = cluster_by_location(members.iter().copied(), BASE_RADIUS_KM);
    merge_nearby_clusters(clusters, BASE_MERGE_RADIUS_KM)
        .into_iter()
        .filter(is_residence)
        .map(|cluster| Base {
            is_current: cluster.last_creation_time() > now - CURRENT_BASE_DAYS * MICROS_PER_DAY,
            location: cluster.center,
            members: cluster.members,
        })
        .collect()
}

fn is_residence(cluster: &Cluster) -> bool {
    if cluster.members.len() < MIN_BASE_PHOTOS {
        return false;
    }
    let dates = cluster.members.iter().map(|member| member.photo.date);
    let days: BTreeSet<i64> = dates.clone().map(LocalDate::days_since_epoch).collect();
    let weeks: HashSet<i64> = dates
        .clone()
        .map(|date| date.plus_days(1 - date.weekday()).days_since_epoch())
        .collect();
    let months: HashSet<(i32, i32)> = dates.map(|date| (date.year, date.month)).collect();
    let span_days = (cluster.last_creation_time() - cluster.first_creation_time()) / MICROS_PER_DAY;
    days.len() >= MIN_BASE_ACTIVE_DAYS
        && weeks.len() >= MIN_BASE_ACTIVE_WEEKS
        && months.len() >= MIN_BASE_ACTIVE_MONTHS
        && has_dense_window(&days.into_iter().collect::<Vec<_>>())
        && span_days >= MIN_BASE_SPAN_DAYS
}

fn has_dense_window(days: &[i64]) -> bool {
    let mut start = 0;
    (0..days.len()).any(|end| {
        while days[end] - days[start] > BASE_DENSITY_WINDOW_DAYS {
            start += 1;
        }
        end - start + 1 >= MIN_BASE_ACTIVE_DAYS_IN_WINDOW
    })
}
