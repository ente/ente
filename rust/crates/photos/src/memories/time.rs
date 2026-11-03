use std::cmp::Reverse;
use std::collections::HashMap;

use super::calendar::{LocalDate, MICROS_PER_DAY};
use super::input::Period;
use super::output::{Memory, MemoryKind, TimeMemory};
use super::photo::Photo;
use super::selector::Selector;
use super::{MINIMUM_MEMORY_LENGTH, UPDATE_FREQUENCY_DAYS, unused_photos};
use crate::ml_store::Result;

const RECENT_SELECTION_SIZE: usize = 10;
const MONTH_SELECTION_SIZE: usize = 20;
const SINGLE_YEAR_MONTH_MEMORIES: usize = 2;
const MINIMUM_YEARS_FOR_MONTH_THROUGH_THE_YEARS: usize = 4;
const MINIMUM_SIGNIFICANT_YEARS_FOR_THROUGH_THE_YEARS: usize = 3;
const SIGNIFICANT_DAY_SHARE: f64 = 0.25;
const SIGNIFICANT_WEEK_SHARE: f64 = 0.40;
const DAYS_PER_YEAR: i64 = 365;

pub(super) fn memories(
    available: &[&Photo],
    all_photos: &[Photo],
    period: Period,
    selector: &mut Selector,
) -> Result<Vec<Memory>> {
    let mut memories = recent_memories(all_photos, period, selector)?;
    let cutoff = period.now - DAYS_PER_YEAR * MICROS_PER_DAY;
    let historical: Vec<&Photo> = available
        .iter()
        .copied()
        .filter(|photo| photo.creation_time <= cutoff)
        .collect();
    let average_daily_photos = available.len() as f64 / DAYS_PER_YEAR as f64;

    let mut past_memories = day_memories(
        &historical,
        period,
        average_daily_photos * SIGNIFICANT_DAY_SHARE,
        selector,
    )?;
    if past_memories.is_empty() {
        past_memories = week_memories(
            &historical,
            period,
            average_daily_photos * SIGNIFICANT_WEEK_SHARE,
            selector,
        )?;
    }
    let month_photos = unused_photos(historical, &past_memories);
    past_memories.extend(month_memories(&month_photos, period, selector)?);
    memories.extend(past_memories);
    Ok(memories)
}

fn recent_memories(
    photos: &[Photo],
    period: Period,
    selector: &mut Selector,
) -> Result<Vec<Memory>> {
    let today = period.today();
    let week_start = today.plus_days(1 - today.weekday());
    let month_start = LocalDate::new(today.year, today.month, 1);
    let windows = [
        (
            TimeMemory::LastWeek,
            week_start.plus_days(-7),
            week_start,
            week_start.plus_days(7),
        ),
        (
            TimeMemory::LastMonth,
            LocalDate::new(today.year, today.month - 1, 1),
            month_start,
            LocalDate::new(today.year, today.month + 1, 1),
        ),
    ];
    let mut memories = Vec::new();
    for (kind, source_start, show_start, show_end) in windows {
        let candidates: Vec<&Photo> = photos
            .iter()
            .filter(|photo| (source_start..show_start).contains(&photo.date))
            .collect();
        if candidates.len() >= MINIMUM_MEMORY_LENGTH {
            memories.push(Memory::new(
                MemoryKind::Time(kind),
                &selector.best_over_time(candidates, RECENT_SELECTION_SIZE)?,
                period.start_of(show_start),
                period.start_of(show_end),
            ));
        }
    }
    Ok(memories)
}

fn day_memories(
    photos: &[&Photo],
    period: Period,
    significance_threshold: f64,
    selector: &mut Selector,
) -> Result<Vec<Memory>> {
    let show_dates = show_dates(period.today());
    let mut groups: HashMap<(i32, i32), HashMap<i32, Vec<&Photo>>> = HashMap::new();
    for &photo in photos {
        let month_day = (photo.date.month, photo.date.day);
        if show_dates
            .get(&month_day)
            .is_some_and(|show_date| photo.date.year < show_date.year)
        {
            groups
                .entry(month_day)
                .or_default()
                .entry(photo.date.year)
                .or_default()
                .push(photo);
        }
    }
    let mut month_days: Vec<(LocalDate, (i32, i32))> = groups
        .keys()
        .map(|month_day| (show_dates[month_day], *month_day))
        .collect();
    month_days.sort();

    let mut memories = Vec::new();
    for (show_date, (month, day)) in month_days {
        let years = &groups[&(month, day)];
        let significant_years = significant_years(years, significance_threshold);
        let first_date_to_show = period.start_of(show_date.plus_days(-1));
        let last_date_to_show = period.start_of(show_date.plus_days(1));
        if significant_years.len() >= MINIMUM_SIGNIFICANT_YEARS_FOR_THROUGH_THE_YEARS {
            let kind = TimeMemory::Day {
                date: LocalDate::new(significant_years[0], month, day),
                years_ago: None,
            };
            let photos = years.values().flatten().copied().collect();
            memories.push(Memory::new(
                MemoryKind::Time(kind),
                &selector.best(photos, None)?,
                first_date_to_show,
                last_date_to_show,
            ));
        } else {
            for year in significant_years {
                let kind = TimeMemory::Day {
                    date: LocalDate::new(year, month, day),
                    years_ago: Some(show_date.year - year),
                };
                memories.push(Memory::new(
                    MemoryKind::Time(kind),
                    &selector.best(years[&year].clone(), None)?,
                    first_date_to_show,
                    last_date_to_show,
                ));
            }
        }
    }
    Ok(memories)
}

fn week_memories(
    photos: &[&Photo],
    period: Period,
    significance_threshold: f64,
    selector: &mut Selector,
) -> Result<Vec<Memory>> {
    let today = period.today();
    let mut years: HashMap<i32, Vec<&Photo>> = HashMap::new();
    for &photo in photos {
        if photo.date.week_of_year() == today.week_of_year() && photo.date.year < today.year {
            years.entry(photo.date.year).or_default().push(photo);
        }
    }
    let significant_years = significant_years(&years, significance_threshold);
    let first_date_to_show = period.now - MICROS_PER_DAY;
    let last_date_to_show = period.now + UPDATE_FREQUENCY_DAYS * MICROS_PER_DAY;
    if significant_years.len() >= MINIMUM_SIGNIFICANT_YEARS_FOR_THROUGH_THE_YEARS {
        let photos = years.values().flatten().copied().collect();
        return Ok(vec![Memory::new(
            MemoryKind::Time(TimeMemory::Week { years_ago: None }),
            &selector.best(photos, None)?,
            first_date_to_show,
            last_date_to_show,
        )]);
    }
    let mut memories = Vec::new();
    for year in significant_years {
        let kind = TimeMemory::Week {
            years_ago: Some(today.year - year),
        };
        memories.push(Memory::new(
            MemoryKind::Time(kind),
            &selector.best(years[&year].clone(), None)?,
            first_date_to_show,
            last_date_to_show,
        ));
    }
    Ok(memories)
}

fn month_memories(
    photos: &[&Photo],
    period: Period,
    selector: &mut Selector,
) -> Result<Vec<Memory>> {
    let today = period.today();
    let mut years: HashMap<i32, Vec<&Photo>> = HashMap::new();
    for &photo in photos {
        if photo.date.month == today.month && photo.date.year < today.year {
            years.entry(photo.date.year).or_default().push(photo);
        }
    }
    let mut years: Vec<(i32, Vec<&Photo>)> = years.into_iter().collect();
    years.sort_by_key(|(year, photos)| (Reverse(photos.len()), Reverse(*year)));

    let first_date_to_show = period.now;
    let last_date_to_show = period.start_of(LocalDate::new(today.year, today.month + 1, 1));
    let mut years = years.into_iter();
    let mut memories = Vec::new();
    for (year, photos) in years.by_ref().take(SINGLE_YEAR_MONTH_MEMORIES) {
        let kind = TimeMemory::Month {
            year,
            month: today.month,
            years_ago: Some(today.year - year),
        };
        memories.push(Memory::new(
            MemoryKind::Time(kind),
            &selector.best(photos, Some(MONTH_SELECTION_SIZE))?,
            first_date_to_show,
            last_date_to_show,
        ));
    }
    let remaining_years: Vec<(i32, Vec<&Photo>)> = years.collect();
    if remaining_years.len() >= MINIMUM_YEARS_FOR_MONTH_THROUGH_THE_YEARS {
        let kind = TimeMemory::Month {
            year: today.year,
            month: today.month,
            years_ago: None,
        };
        let photos = remaining_years
            .into_iter()
            .flat_map(|(_, photos)| photos)
            .collect();
        memories.push(Memory::new(
            MemoryKind::Time(kind),
            &selector.best(photos, Some(MONTH_SELECTION_SIZE))?,
            first_date_to_show,
            last_date_to_show,
        ));
    }
    Ok(memories)
}

fn show_dates(today: LocalDate) -> HashMap<(i32, i32), LocalDate> {
    let mut dates = HashMap::new();
    for offset in 0..=UPDATE_FREQUENCY_DAYS {
        let date = today.plus_days(offset);
        dates.insert((date.month, date.day), date);
        if (date.month, date.day) == (2, 28) && !date.is_in_leap_year() {
            dates.insert((2, 29), date);
        }
    }
    dates
}

fn significant_years(years: &HashMap<i32, Vec<&Photo>>, threshold: f64) -> Vec<i32> {
    let mut significant: Vec<i32> = years
        .iter()
        .filter(|(_, photos)| photos.len() as f64 > threshold)
        .map(|(year, _)| *year)
        .collect();
    significant.sort_by_key(|year| Reverse(*year));
    significant
}

#[cfg(test)]
mod tests {
    use super::memories;
    use crate::memories::calendar::LocalDate;
    use crate::memories::input::MemoryFile;
    use crate::memories::output::{Memory, MemoryKind, TimeMemory};
    use crate::memories::photo::prepare;
    use crate::memories::selector::Selector;
    use crate::memories::tests::{files_on, micros, period};

    fn time_memories(files: &[MemoryFile], now: &str) -> Vec<Memory> {
        let photos = prepare(files);
        let available: Vec<_> = photos.iter().collect();
        memories(
            &available,
            &photos,
            period(now),
            &mut Selector::new(None, 0),
        )
        .unwrap()
    }

    fn day(year: i32, month: i32, day: i32, years_ago: Option<i32>) -> MemoryKind {
        MemoryKind::Time(TimeMemory::Day {
            date: LocalDate { year, month, day },
            years_ago,
        })
    }

    #[test]
    fn upcoming_days_go_through_the_years_from_three_significant_years() {
        let mut files = Vec::new();
        for year in 2020..2023 {
            files.extend(files_on(i64::from(year) * 10, &format!("{year}-10-30"), 2));
        }
        files.extend(files_on(1, "2019-11-01", 2));

        let memories = time_memories(&files, "2026-10-29T09:00:00");

        let kinds: Vec<MemoryKind> = memories.iter().map(|memory| memory.kind.clone()).collect();
        assert_eq!(kinds, [day(2022, 10, 30, None), day(2019, 11, 1, Some(7))]);
        assert_eq!(memories[0].file_ids.len(), 6);
        assert_eq!(
            memories[0].first_date_to_show,
            micros("2026-10-29T00:00:00")
        );
        assert_eq!(memories[0].last_date_to_show, micros("2026-10-31T00:00:00"));
        assert_eq!(
            memories[1].first_date_to_show,
            micros("2026-10-31T00:00:00")
        );
    }

    #[test]
    fn leap_days_show_on_february_twenty_eighth_in_common_years() {
        let memories = time_memories(&files_on(1, "2024-02-29", 2), "2027-02-27T09:00:00");

        assert_eq!(memories[0].kind, day(2024, 2, 29, Some(3)));
        assert_eq!(
            memories[0].first_date_to_show,
            micros("2027-02-27T00:00:00")
        );
        assert_eq!(memories[0].last_date_to_show, micros("2027-03-01T00:00:00"));
    }

    #[test]
    fn months_show_the_two_busiest_years_then_the_rest_through_the_years() {
        let mut files = files_on(150, "2015-10-20", 5);
        files.extend(files_on(160, "2016-10-20", 4));
        for year in 2017..2021 {
            files.extend(files_on(i64::from(year) * 10, &format!("{year}-10-20"), 1));
        }
        files.extend(files_on(1, "2015-10-06", 1));

        let memories = time_memories(&files, "2026-10-05T09:00:00");

        let month = |year, years_ago| {
            MemoryKind::Time(TimeMemory::Month {
                year,
                month: 10,
                years_ago,
            })
        };
        let kinds: Vec<MemoryKind> = memories.iter().map(|memory| memory.kind.clone()).collect();
        assert_eq!(
            kinds,
            [
                day(2015, 10, 6, Some(11)),
                month(2015, Some(11)),
                month(2016, Some(10)),
                month(2026, None),
            ]
        );
        assert_eq!(memories[1].file_ids, [150, 151, 152, 153, 154]);
        assert_eq!(memories[3].file_ids, [20170, 20180, 20190, 20200]);
        assert_eq!(
            memories[3].first_date_to_show,
            micros("2026-10-05T09:00:00")
        );
        assert_eq!(memories[3].last_date_to_show, micros("2026-11-01T00:00:00"));
    }

    #[test]
    fn photos_dated_in_the_show_year_are_not_past_memories() {
        let mut files = files_on(1, "2015-10-30", 2);
        for file in &mut files {
            file.local_date_time = Some("2026-10-30T10:00:00".to_owned());
        }

        assert!(time_memories(&files, "2026-10-29T09:00:00").is_empty());
    }

    #[test]
    fn recent_weeks_and_months_need_five_photos() {
        let mut files = files_on(1, "2026-10-21", 5);
        files.extend(files_on(10, "2026-09-15", 4));

        let memories = time_memories(&files, "2026-10-29T09:00:00");

        assert_eq!(memories.len(), 1);
        assert_eq!(memories[0].kind, MemoryKind::Time(TimeMemory::LastWeek));
        assert_eq!(
            memories[0].first_date_to_show,
            micros("2026-10-26T00:00:00")
        );
        assert_eq!(memories[0].last_date_to_show, micros("2026-11-02T00:00:00"));
    }
}
