use std::collections::HashSet;

use super::percent;
use crate::rewind::library::{Library, YearFile};
use crate::rewind::ranking::{Ranking, Spread};
use crate::rewind::report::WeeklyHabit;

const WEEKLY_HABIT_MINIMUM_PHOTOS: usize = 100;
const WEEKLY_HABIT_MINIMUM_DATES: usize = 8;
const WEEKLY_HABIT_CANDIDATES: usize = 36;

pub(in crate::rewind) fn weekly_habit(
    library: &Library<'_>,
    ranking: &Ranking<'_>,
) -> Option<WeeklyHabit> {
    let taken: Vec<&YearFile> = library.taken().collect();
    if taken.len() < WEEKLY_HABIT_MINIMUM_PHOTOS {
        return None;
    }
    let weekday = most_common(taken.iter().map(|file| file.weekday), 1..=7)?;
    let on_weekday: Vec<&YearFile> = taken
        .iter()
        .copied()
        .filter(|file| file.weekday == weekday)
        .collect();
    let dates: HashSet<i64> = on_weekday.iter().map(|file| file.day).collect();
    if dates.len() < WEEKLY_HABIT_MINIMUM_DATES {
        return None;
    }
    let hour = most_common(on_weekday.iter().map(|file| file.hour), 0..=23)?;
    let percent = percent(on_weekday.len(), taken.len());
    let (at_hour, other_hours): (Vec<&YearFile>, Vec<&YearFile>) =
        on_weekday.into_iter().partition(|file| file.hour == hour);
    let ranked = ranking
        .by_quality(at_hour)
        .into_iter()
        .chain(ranking.by_quality(other_hours));
    let file_ids = ranking.pick(ranked, Spread::Days, WEEKLY_HABIT_CANDIDATES);
    let led_by_the_hour = file_ids
        .first()
        .and_then(|&id| library.get(id))
        .is_some_and(|file| file.hour == hour);
    Some(WeeklyHabit {
        weekday,
        hour,
        percent,
        file_ids: if led_by_the_hour {
            file_ids
        } else {
            Vec::new()
        },
    })
}

fn most_common(
    values: impl Iterator<Item = u32>,
    range: std::ops::RangeInclusive<u32>,
) -> Option<u32> {
    let values: Vec<u32> = values.collect();
    range
        .rev()
        .max_by_key(|candidate| values.iter().filter(|value| *value == candidate).count())
}

#[cfg(test)]
mod tests {
    use crate::rewind::fixtures::{micros, photo, request};
    use crate::rewind::input::{RewindFile, RewindFileType};
    use crate::rewind::library::Library;
    use crate::rewind::ranking::Ranking;
    use crate::rewind::report::WeeklyHabit;

    use super::weekly_habit;

    fn sundays(first_id: i64, weeks: i64, hour: u32, per_week: i64) -> Vec<RewindFile> {
        let first_sunday = micros("2026-01-04T00:00:00");
        (0..weeks)
            .flat_map(|week| (0..per_week).map(move |shot| (week, shot)))
            .map(|(week, shot)| {
                let mut file = photo(first_id + week * per_week + shot, "2026-01-04T00:00:00");
                file.creation_time = first_sunday
                    + week * 7 * 86_400_000_000
                    + i64::from(hour) * 3_600_000_000
                    + shot * 60_000_000;
                file
            })
            .collect()
    }

    #[test]
    fn the_habit_is_the_busiest_weekday_and_hour_with_the_weekday_share() {
        let mut files = sundays(1, 10, 18, 5);
        files.extend(sundays(1000, 10, 17, 2));
        files.extend(sundays(2000, 10, 9, 1));
        let mut monday = sundays(3000, 30, 12, 1);
        for file in &mut monday {
            file.creation_time += 86_400_000_000;
        }
        files.extend(monday);
        let mut junk = sundays(4000, 1, 3, 40);
        for file in &mut junk {
            file.creation_time += 2 * 86_400_000_000;
            file.is_junk = true;
        }
        files.extend(junk);
        let habit_request = request(files);
        let library = Library::of_year(&habit_request).unwrap();

        let habit = weekly_habit(&library, &Ranking::new(None, None)).unwrap();

        assert_eq!((habit.weekday, habit.hour, habit.percent), (7, 18, 73));
    }

    #[test]
    fn the_habit_photos_favour_the_habit_hour_on_different_dates() {
        let mut files = sundays(1, 10, 18, 5);
        files.extend(sundays(1000, 10, 9, 1));
        let mut later = sundays(2000, 4, 9, 1);
        for file in &mut later {
            file.creation_time += 10 * 7 * 86_400_000_000;
        }
        files.extend(later);
        files.extend(sundays(3000, 40, 12, 1).into_iter().map(|mut file| {
            file.creation_time += 86_400_000_000;
            file
        }));
        let habit_request = request(files);
        let library = Library::of_year(&habit_request).unwrap();

        let WeeklyHabit { file_ids, .. } =
            weekly_habit(&library, &Ranking::new(None, None)).unwrap();

        assert_eq!(
            file_ids[..16],
            [
                1, 6, 11, 16, 21, 26, 31, 36, 41, 46, 2000, 2001, 2002, 2003, 2, 7
            ]
        );
        assert_eq!(file_ids.len(), 36);
    }

    #[test]
    fn the_habit_has_no_photos_when_none_from_the_habit_hour_can_be_shown() {
        let mut files = sundays(1, 10, 18, 5);
        for file in &mut files {
            file.file_type = RewindFileType::Video;
        }
        files.extend(sundays(1000, 10, 9, 1));
        files.extend(sundays(3000, 40, 12, 1).into_iter().map(|mut file| {
            file.creation_time += 86_400_000_000;
            file
        }));
        let habit_request = request(files);
        let library = Library::of_year(&habit_request).unwrap();

        let habit = weekly_habit(&library, &Ranking::new(None, None)).unwrap();

        assert_eq!((habit.weekday, habit.hour), (7, 18));
        assert!(habit.file_ids.is_empty());
    }

    #[test]
    fn few_photos_or_a_weekday_on_few_dates_skip_the_habit() {
        let few = request(sundays(1, 10, 18, 9));
        let library = Library::of_year(&few).unwrap();
        assert_eq!(weekly_habit(&library, &Ranking::new(None, None)), None);

        let mut burst = sundays(1, 7, 18, 20);
        burst.extend(sundays(1000, 7, 18, 1));
        for file in &mut burst[140..] {
            file.creation_time += 86_400_000_000;
        }
        let bursty = request(burst);
        let library = Library::of_year(&bursty).unwrap();
        assert_eq!(weekly_habit(&library, &Ranking::new(None, None)), None);
    }
}
