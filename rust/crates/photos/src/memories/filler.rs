use std::collections::BTreeMap;

use super::UPDATE_FREQUENCY_DAYS;
use super::calendar::{MICROS_PER_DAY, upcoming_anniversary};
use super::input::Period;
use super::output::{Memory, MemoryKind};
use super::photo::Photo;

const MAXIMUM_YEARS_AGO: i32 = 30;
const MINIMUM_AGE_DAYS: i64 = 364 - UPDATE_FREQUENCY_DAYS;

pub(super) fn memories(photos: &[&Photo], period: Period) -> Vec<Memory> {
    let today = period.today();
    let cutoff = period.now - MINIMUM_AGE_DAYS * MICROS_PER_DAY;
    let mut photos_by_years_ago: BTreeMap<i32, Vec<&Photo>> = BTreeMap::new();
    for &photo in photos {
        if photo.creation_time <= cutoff
            && let Some(anniversary) =
                upcoming_anniversary(photo.date, today, UPDATE_FREQUENCY_DAYS)
            && (1..=MAXIMUM_YEARS_AGO).contains(&anniversary.years_ago)
        {
            photos_by_years_ago
                .entry(anniversary.years_ago)
                .or_default()
                .push(photo);
        }
    }
    photos_by_years_ago
        .into_iter()
        .map(|(years_ago, photos)| {
            Memory::new(
                MemoryKind::Filler { years_ago },
                &photos,
                period.now,
                period.now + UPDATE_FREQUENCY_DAYS * MICROS_PER_DAY,
            )
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::memories;
    use crate::memories::output::MemoryKind;
    use crate::memories::photo::prepare;
    use crate::memories::tests::{file, files_on, micros, period};

    #[test]
    fn groups_anniversaries_of_the_next_three_days_by_years_ago() {
        let mut files = files_on(1, "2025-10-31", 2);
        files.extend(files_on(10, "2024-10-29", 1));
        files.extend(files_on(20, "2023-10-30", 1));
        files.extend(files_on(30, "2025-11-01", 1));
        files.extend(files_on(40, "1990-10-29", 1));
        files.extend(files_on(50, "2026-10-29", 1));
        files.push(file(60, "2023-10-30T07:00:00"));
        let mut recently_created = file(70, "2026-10-20T08:00:00");
        recently_created.local_date_time = Some("2024-10-30T08:00:00".to_owned());
        files.push(recently_created);
        let photos = prepare(&files);
        let photos: Vec<_> = photos.iter().collect();

        let memories = memories(&photos, period("2026-10-29T18:00:00"));

        let groups: Vec<(MemoryKind, Vec<i64>)> = memories
            .iter()
            .map(|memory| (memory.kind.clone(), memory.file_ids.clone()))
            .collect();
        assert_eq!(
            groups,
            [
                (MemoryKind::Filler { years_ago: 1 }, vec![1, 2]),
                (MemoryKind::Filler { years_ago: 2 }, vec![10]),
                (MemoryKind::Filler { years_ago: 3 }, vec![60, 20]),
            ]
        );
        assert_eq!(
            memories[0].first_date_to_show,
            micros("2026-10-29T18:00:00")
        );
        assert_eq!(memories[0].last_date_to_show, micros("2026-11-01T18:00:00"));
    }
}
