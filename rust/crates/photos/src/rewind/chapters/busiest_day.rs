use std::cmp::Reverse;
use std::collections::BTreeMap;

use super::count;
use crate::rewind::library::{Library, YearFile};
use crate::rewind::ranking::{Ranking, Spread};
use crate::rewind::report::BusiestDay;

const BUSIEST_DAY_MINIMUM_PHOTOS: usize = 10;
const BUSIEST_DAY_MINIMUM_CANDIDATES: usize = 4;
const BUSIEST_DAY_CANDIDATES: usize = 16;

pub(in crate::rewind) fn busiest_day(
    library: &Library<'_>,
    ranking: &Ranking<'_>,
) -> Option<BusiestDay> {
    let mut days: BTreeMap<i64, Vec<&YearFile>> = BTreeMap::new();
    for file in library.taken() {
        days.entry(file.day).or_default().push(file);
    }
    let files = days
        .into_iter()
        .max_by_key(|(day, files)| (files.len(), Reverse(*day)))?
        .1;
    if files.len() < BUSIEST_DAY_MINIMUM_PHOTOS {
        return None;
    }
    let file_ids = ranking.best(files.iter().copied(), Spread::Hours, BUSIEST_DAY_CANDIDATES);
    (file_ids.len() >= BUSIEST_DAY_MINIMUM_CANDIDATES).then(|| BusiestDay {
        month: files[0].month,
        day: files[0].day_of_month,
        photo_count: count(files.len()),
        file_ids,
    })
}

#[cfg(test)]
mod tests {
    use crate::rewind::fixtures::{photo, request};
    use crate::rewind::input::{RewindFile, RewindFileType};
    use crate::rewind::library::Library;
    use crate::rewind::ranking::Ranking;
    use crate::rewind::report::BusiestDay;

    use super::busiest_day;

    fn day(first_id: i64, date: &str, hours: &[u32]) -> Vec<RewindFile> {
        hours
            .iter()
            .zip(first_id..)
            .map(|(hour, id)| photo(id, &format!("{date}T{hour:02}:{:02}:00", id % 60)))
            .collect()
    }

    #[test]
    fn the_busiest_day_counts_videos_but_not_junk_and_spreads_over_hours() {
        let mut files = day(1, "2026-08-14", &[9, 9, 9, 9, 9, 9, 12, 12, 18, 18, 18]);
        files[10].file_type = RewindFileType::Video;
        files.extend(day(100, "2026-03-01", &[10; 10]));
        let mut junk = day(200, "2026-05-05", &[8; 30]);
        for file in &mut junk {
            file.is_junk = true;
        }
        files.extend(junk);
        let request = request(files);
        let library = Library::of_year(&request).unwrap();

        let busiest = busiest_day(&library, &Ranking::new(None, None)).unwrap();

        assert_eq!(
            (busiest.month, busiest.day, busiest.photo_count),
            (8, 14, 11)
        );
        assert_eq!(&busiest.file_ids[..4], [1, 7, 9, 2]);
        assert_eq!(busiest.file_ids.len(), 10);
    }

    #[test]
    fn ties_go_to_the_earlier_day_and_small_days_skip_the_chapter() {
        let mut files = day(1, "2026-06-02", &[10; 10]);
        files.extend(day(100, "2026-06-01", &[11; 10]));
        let tied = request(files);
        let library = Library::of_year(&tied).unwrap();
        assert!(matches!(
            busiest_day(&library, &Ranking::new(None, None)),
            Some(BusiestDay {
                month: 6,
                day: 1,
                ..
            })
        ));

        let small = request(day(1, "2026-06-02", &[10; 9]));
        let library = Library::of_year(&small).unwrap();
        assert_eq!(busiest_day(&library, &Ranking::new(None, None)), None);
    }
}
