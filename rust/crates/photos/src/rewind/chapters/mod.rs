mod badge;
mod busiest_day;
mod colour;
mod crowd_favourite;
mod favourites;
mod new_faces;
mod people_race;
mod places;
mod scrapbook;
mod spots;
mod totals;
mod weekly_habit;

pub(super) use badge::{badge, badge_uses_ml};
pub(super) use busiest_day::busiest_day;
pub(super) use colour::colour;
pub(super) use crowd_favourite::crowd_favourite;
pub(super) use favourites::favourites;
pub(super) use new_faces::new_faces;
pub(super) use people_race::people_race;
pub(super) use places::places;
pub(super) use scrapbook::scrapbook;
pub(super) use spots::spots;
pub(super) use totals::totals;
pub(super) use weekly_habit::weekly_habit;

fn percent(part: usize, whole: usize) -> u32 {
    ((100 * part) as f64 / whole as f64).round().max(1.0) as u32
}

fn count(items: usize) -> u32 {
    u32::try_from(items).unwrap_or(u32::MAX)
}
