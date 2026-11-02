use std::collections::{BTreeMap, HashSet};

use super::UPDATE_FREQUENCY_DAYS;
use super::calendar::{MICROS_PER_DAY, upcoming_anniversary};
use super::input::Period;
use super::output::{Memory, MemoryKind};
use super::photo::Photo;
use super::selector::Selector;

const MINIMUM_PHOTOS: usize = 5;
const MINIMUM_YEARS: usize = 2;
const MAXIMUM_PHOTOS: usize = 20;
const MINIMUM_AGE_DAYS: i64 = 363 - UPDATE_FREQUENCY_DAYS;

pub(super) fn memories(
    photos: &[Photo],
    period: Period,
    excluded_collection_ids: &HashSet<i64>,
    selector: &mut Selector,
) -> Vec<Memory> {
    let today = period.today();
    let cutoff = period.start_of(today) - MINIMUM_AGE_DAYS * MICROS_PER_DAY;
    let mut photos_by_day: BTreeMap<i64, Vec<&Photo>> = BTreeMap::new();
    for photo in photos {
        if photo.creation_time > cutoff
            || photo
                .collection_id
                .is_some_and(|id| excluded_collection_ids.contains(&id))
        {
            continue;
        }
        if let Some(anniversary) = upcoming_anniversary(photo.date, today, UPDATE_FREQUENCY_DAYS)
            && anniversary.years_ago >= 1
        {
            photos_by_day
                .entry(anniversary.days_from_today)
                .or_default()
                .push(photo);
        }
    }
    photos_by_day
        .into_iter()
        .filter(|(_, photos)| {
            photos.len() >= MINIMUM_PHOTOS
                && photos
                    .iter()
                    .map(|photo| photo.date.year)
                    .collect::<HashSet<_>>()
                    .len()
                    >= MINIMUM_YEARS
        })
        .map(|(days_from_today, photos)| {
            let day = today.plus_days(days_from_today);
            Memory::new(
                MemoryKind::OnThisDay,
                &selector.sample_across_years(photos, MAXIMUM_PHOTOS),
                period.start_of(day),
                period.start_of(day.plus_days(1)),
            )
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use std::collections::HashSet;

    use super::memories;
    use crate::memories::input::MemoryFile;
    use crate::memories::output::{Memory, MemoryKind};
    use crate::memories::photo::prepare;
    use crate::memories::selector::Selector;
    use crate::memories::tests::{files_on, micros, period};

    fn on_this_day(files: &[MemoryFile], now: &str, excluded: &[i64]) -> Vec<Memory> {
        let photos = prepare(files);
        memories(
            &photos,
            period(now),
            &excluded.iter().copied().collect::<HashSet<_>>(),
            &mut Selector::new(None, 1),
        )
    }

    #[test]
    fn shows_each_of_the_next_three_days_with_five_photos_from_two_earlier_years() {
        let mut files = files_on(1, "2023-10-30", 3);
        files.extend(files_on(10, "2021-10-30", 2));
        files.extend(files_on(20, "2024-10-29", 4));
        files.extend(files_on(30, "2026-10-31", 5));
        files.extend(files_on(40, "2022-11-01", 3));
        files.extend(files_on(50, "2020-11-01", 3));

        let memories = on_this_day(&files, "2026-10-29T18:00:00", &[]);

        assert_eq!(memories.len(), 1);
        assert_eq!(memories[0].kind, MemoryKind::OnThisDay);
        assert_eq!(memories[0].file_ids, [10, 11, 1, 2, 3]);
        assert_eq!(
            memories[0].first_date_to_show,
            micros("2026-10-30T00:00:00")
        );
        assert_eq!(memories[0].last_date_to_show, micros("2026-10-31T00:00:00"));
    }

    #[test]
    fn skips_photos_created_within_the_last_year_whatever_their_dates() {
        let mut files = files_on(1, "2026-10-28", 5);
        for (index, file) in files.iter_mut().enumerate() {
            let year = if index < 3 { 2021 } else { 2023 };
            file.local_date_time = Some(format!("{year}-10-29T08:00:00"));
        }

        assert!(on_this_day(&files, "2026-10-29T08:00:00", &[]).is_empty());
    }

    #[test]
    fn skips_photos_in_excluded_collections() {
        let mut files = files_on(1, "2023-10-29", 3);
        files.extend(files_on(10, "2021-10-29", 2));
        files[0].collection_id = Some(7);

        assert!(on_this_day(&files, "2026-10-29T08:00:00", &[7]).is_empty());
        assert_eq!(on_this_day(&files, "2026-10-29T08:00:00", &[]).len(), 1);
    }

    #[test]
    fn large_days_keep_twenty_photos_spread_across_years() {
        let mut files = Vec::new();
        for year in 2001..2004 {
            files.extend(files_on(
                i64::from(year) * 100,
                &format!("{year}-10-29"),
                30,
            ));
        }

        let memories = on_this_day(&files, "2026-10-29T08:00:00", &[]);

        let ids = &memories[0].file_ids;
        assert_eq!(ids.len(), 20);
        for year in 2001..2004 {
            let from_year = ids
                .iter()
                .filter(|id| **id / 100 == i64::from(year))
                .count();
            assert!((6..=7).contains(&from_year), "{year}: {from_year}");
        }
        assert!(ids.windows(2).all(|pair| pair[0] < pair[1]));
    }
}
