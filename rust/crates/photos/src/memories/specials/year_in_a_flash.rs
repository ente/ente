use std::collections::{BTreeMap, HashSet};

use super::{Format, History, special};
use crate::memories::calendar::LocalDate;
use crate::memories::input::{Period, PhotoSignals};
use crate::memories::output::{Memory, SpecialFormat};
use crate::memories::photo::{Photo, sort_chronologically};
use crate::memories::selector::{Selector, best_first};
use crate::ml_store::Result;

const FRAMES: usize = 90;
const MINIMUM_DAYS: usize = 40;
const MINIMUM_MONTHS: usize = 8;
const YEAR_COOLDOWN_DAYS: i64 = 120;
const REPEATED_SCENE_SIMILARITY: f32 = 0.8;

pub(super) fn memory(
    photos: &[Photo],
    period: Period,
    history: &History,
    signals: Option<&dyn PhotoSignals>,
    selector: &mut Selector,
) -> Result<Option<Memory>> {
    let mut years = full_years(photos, period);
    selector.shuffle(&mut years);
    years
        .into_iter()
        .find(|(year, _)| !history.was_shown_within(&key(*year), YEAR_COOLDOWN_DAYS, period))
        .map(|(year, photos)| year_memory(year, &photos, period, signals, selector))
        .transpose()
}

pub(super) fn all_memories(
    photos: &[Photo],
    period: Period,
    signals: Option<&dyn PhotoSignals>,
    selector: &mut Selector,
) -> Result<Vec<Memory>> {
    full_years(photos, period)
        .into_iter()
        .rev()
        .map(|(year, photos)| year_memory(year, &photos, period, signals, selector))
        .collect()
}

fn key(year: i32) -> String {
    Format::YearInAFlash.key(year)
}

fn full_years(photos: &[Photo], period: Period) -> Vec<(i32, Vec<&Photo>)> {
    let this_year = period.today().year;
    let mut years: BTreeMap<i32, Vec<&Photo>> = BTreeMap::new();
    for photo in photos {
        if photo.date.year < this_year {
            years.entry(photo.date.year).or_default().push(photo);
        }
    }
    years
        .into_iter()
        .filter(|(_, photos)| covers_the_year(photos))
        .collect()
}

fn covers_the_year(photos: &[&Photo]) -> bool {
    let days: HashSet<LocalDate> = photos.iter().map(|photo| photo.date).collect();
    let months: HashSet<i32> = days.iter().map(|day| day.month).collect();
    days.len() >= MINIMUM_DAYS && months.len() >= MINIMUM_MONTHS
}

fn year_memory(
    year: i32,
    photos: &[&Photo],
    period: Period,
    signals: Option<&dyn PhotoSignals>,
    selector: &mut Selector,
) -> Result<Memory> {
    Ok(special(
        key(year),
        SpecialFormat::YearInAFlash { year },
        &frames(year, photos, signals, selector)?,
        period,
    ))
}

fn frames<'p>(
    year: i32,
    photos: &[&'p Photo],
    signals: Option<&dyn PhotoSignals>,
    selector: &mut Selector,
) -> Result<Vec<&'p Photo>> {
    let new_year = LocalDate::new(year, 1, 1);
    let days_in_year = new_year.days_until(LocalDate::new(year + 1, 1, 1));
    let mut stretches: Vec<Vec<&Photo>> = vec![Vec::new(); FRAMES];
    for &photo in photos {
        let day = new_year.days_until(photo.date);
        stretches[(day * FRAMES as i64 / days_in_year) as usize].push(photo);
    }
    let mut frames: Vec<&Photo> = Vec::with_capacity(FRAMES);
    for stretch in stretches {
        if stretch.is_empty() {
            continue;
        }
        let frame = match signals {
            Some(signals) => first_new_scene(
                &best_first(&stretch, signals),
                frames.last().copied(),
                signals,
            )?,
            None => stretch[selector.below(stretch.len())],
        };
        frames.push(frame);
    }
    sort_chronologically(&mut frames);
    Ok(frames)
}

fn first_new_scene<'p>(
    ranked: &[&'p Photo],
    previous: Option<&Photo>,
    signals: &dyn PhotoSignals,
) -> Result<&'p Photo> {
    let Some(previous) = previous else {
        return Ok(ranked[0]);
    };
    for &photo in ranked {
        let repeats = signals
            .similarity(photo.id, previous.id)?
            .is_some_and(|similarity| similarity > REPEATED_SCENE_SIMILARITY);
        if !repeats {
            return Ok(photo);
        }
    }
    Ok(ranked[0])
}

#[cfg(test)]
mod tests {
    use std::collections::{HashMap, HashSet};

    use crate::memories::calendar::MICROS_PER_DAY;
    use crate::memories::specials::tests::{Clip, NOW};
    use crate::memories::tests::{file, micros, period};
    use crate::memories::{
        MemoriesRequest, Memory, MemoryFile, MemoryKind, MlInputs, ShownSpecial, SpecialFormat,
        compute_smart_memories,
    };

    fn every_other_day(year: i64, first_id: i64, photos_per_day: i64) -> Vec<MemoryFile> {
        let new_year = micros(&format!("{year}-01-01T00:00:00"));
        (0..183)
            .flat_map(|index| {
                (0..photos_per_day).map(move |photo| MemoryFile {
                    creation_time: new_year
                        + index * 2 * MICROS_PER_DAY
                        + (10 + photo) * 3_600_000_000,
                    ..file(
                        first_id + index * photos_per_day + photo,
                        "1970-01-01T00:00:00",
                    )
                })
            })
            .collect()
    }

    fn flashes(request: &MemoriesRequest, ml: Option<&MlInputs>) -> Vec<(i32, Memory)> {
        compute_smart_memories(request, &[period(NOW)], ml, None)
            .unwrap()
            .periods
            .remove(0)
            .into_iter()
            .filter_map(|memory| match &memory.kind {
                MemoryKind::Special(special) => match special.format {
                    SpecialFormat::YearInAFlash { year } => Some((year, memory)),
                    _ => None,
                },
                _ => None,
            })
            .collect()
    }

    fn request(files: Vec<MemoryFile>) -> MemoriesRequest {
        MemoriesRequest {
            files,
            shows_specials: true,
            ..MemoriesRequest::default()
        }
    }

    #[test]
    fn a_past_year_becomes_ninety_frames_spread_over_the_whole_year() {
        let mut files = every_other_day(2023, 1, 3);
        files.extend(every_other_day(2026, 10_000, 3));
        files.extend((0..60).map(|index| file(20_000 + index, "2022-05-01T10:00:00")));

        let flashes = flashes(&request(files.clone()), None);

        assert_eq!(flashes.len(), 1);
        let (year, memory) = &flashes[0];
        assert_eq!(*year, 2023);
        assert_eq!(memory.file_ids.len(), 90);
        let days: Vec<i64> = memory.file_ids.iter().map(|id| (id - 1) / 3 * 2).collect();
        assert!(days.is_sorted());
        assert!(
            days.windows(2)
                .all(|pair| (2..=8).contains(&(pair[1] - pair[0])))
        );
        assert!(days[0] < 5 && days[89] > 353);
    }

    #[test]
    fn frames_prefer_the_best_photo_that_does_not_repeat_the_previous_scene() {
        let files = every_other_day(2023, 1, 3);
        let face_weights: HashMap<i64, u32> = files
            .iter()
            .filter(|file| file.id % 3 == 2)
            .map(|file| (file.id, 10))
            .collect();
        let scenes = files
            .iter()
            .map(|file| {
                let is_first_half = (file.id - 1) / 3 < 90;
                let angle = (file.id as f32 * 7.0).to_radians();
                let scene = match (is_first_half, file.id % 3 == 2) {
                    (true, _) => [angle.cos(), angle.sin()],
                    (false, true) => [1.0, 0.0],
                    (false, false) => [0.0, 1.0],
                };
                (file.id, scene)
            })
            .collect();
        let clip = Clip { scenes };
        let ml = MlInputs {
            face_weights,
            ..clip.inputs()
        };

        let (_, memory) = flashes(&request(files), Some(&ml)).remove(0);

        let first_half: HashSet<i64> = memory.file_ids[..44].iter().map(|id| id % 3).collect();
        assert_eq!(first_half, HashSet::from([2]));
        let second_half = &memory.file_ids[45..];
        assert!(second_half.iter().any(|id| id % 3 != 2));
        assert!(
            second_half
                .windows(2)
                .all(|pair| pair[0] % 3 != 2 || pair[1] % 3 != 2)
        );
    }

    #[test]
    fn years_take_turns_and_rest_for_four_months() {
        let mut files = every_other_day(2022, 1, 1);
        files.extend(every_other_day(2023, 1000, 1));
        let shown = |days_ago: i64| MemoriesRequest {
            shown_specials: vec![ShownSpecial {
                key: "year-in-a-flash:2022".to_owned(),
                last_time_shown: micros(NOW) - days_ago * MICROS_PER_DAY,
            }],
            ..request(files.clone())
        };

        let mut years = HashSet::new();
        for seed in 0..20 {
            let resting = MemoriesRequest { seed, ..shown(119) };
            assert_eq!(flashes(&resting, None)[0].0, 2023);
            let rested = MemoriesRequest { seed, ..shown(121) };
            years.insert(flashes(&rested, None)[0].0);
        }
        assert_eq!(years, HashSet::from([2022, 2023]));

        let everything = MemoriesRequest {
            surface_all: true,
            ..shown(1)
        };
        let all: Vec<i32> = flashes(&everything, None)
            .into_iter()
            .map(|(year, _)| year)
            .collect();
        assert_eq!(all, [2023, 2022]);
    }

    #[test]
    fn sparse_years_are_skipped() {
        let few_days: Vec<MemoryFile> = every_other_day(2023, 1, 1).into_iter().take(39).collect();
        assert!(flashes(&request(few_days), None).is_empty());

        let few_months: Vec<MemoryFile> =
            every_other_day(2023, 1, 1).into_iter().take(100).collect();
        assert!(flashes(&request(few_months), None).is_empty());
    }
}
