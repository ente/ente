pub(super) mod caches;
pub(super) mod clip;
pub(super) mod clusters;
pub(super) mod faces;
pub(super) mod filedata;
pub(super) mod persons;
pub(super) mod pets;

use std::collections::HashSet;

fn unique_in_order(ids: &[String]) -> Vec<&str> {
    let mut seen = HashSet::new();
    ids.iter()
        .map(String::as_str)
        .filter(|id| seen.insert(*id))
        .collect()
}

fn limit_clause(limit: Option<i64>) -> &'static str {
    if limit.is_some() { " LIMIT ?" } else { "" }
}
