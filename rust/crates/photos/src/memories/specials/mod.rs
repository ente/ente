mod one_day;
mod then_and_now;
mod year_in_a_flash;

use std::collections::HashSet;
use std::fmt::Display;

use one_day::Day;
use then_and_now::Pair;

use crate::memories::UPDATE_FREQUENCY_DAYS;
use crate::memories::calendar::MICROS_PER_DAY;
use crate::memories::geo::Located;
use crate::memories::input::{Period, PhotoSignals, ShownSpecial};
use crate::memories::output::{Memory, MemoryKind, Special, SpecialFormat};
use crate::memories::photo::Photo;
use crate::memories::places::Places;
use crate::memories::selector::Selector;
use crate::memories::trips::TripAnalysis;
use crate::ml_store::Result;

const SLOTS: usize = 2;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
enum Format {
    ThenAndNow,
    YearInAFlash,
    OneDay,
}

impl Format {
    const ALL: [Self; 3] = [Self::ThenAndNow, Self::YearInAFlash, Self::OneDay];

    fn name(self) -> &'static str {
        match self {
            Self::ThenAndNow => "then-and-now",
            Self::YearInAFlash => "year-in-a-flash",
            Self::OneDay => "one-day",
        }
    }

    fn key(self, detail: impl Display) -> String {
        format!("{}:{detail}", self.name())
    }

    fn owns(self, key: &str) -> bool {
        key.strip_prefix(self.name())
            .is_some_and(|detail| detail.starts_with(':'))
    }
}

pub(super) struct History<'r> {
    shown: &'r [ShownSpecial],
}

impl<'r> History<'r> {
    pub(super) fn new(shown: &'r [ShownSpecial]) -> Self {
        Self { shown }
    }

    fn was_shown_within(&self, key: &str, days: i64, period: Period) -> bool {
        let cutoff = period.now - days * MICROS_PER_DAY;
        self.shown
            .iter()
            .any(|shown| shown.key == key && shown.last_time_shown > cutoff)
    }

    fn last_shown(&self, format: Format) -> Option<i64> {
        self.shown
            .iter()
            .filter(|shown| format.owns(&shown.key))
            .map(|shown| shown.last_time_shown)
            .max()
    }
}

pub(super) struct Specials<'a> {
    photos: &'a [Photo],
    places: &'a Places,
    signals: Option<&'a dyn PhotoSignals>,
    pairs: Vec<Pair<'a>>,
    travel_days: Vec<Day<'a>>,
    surface_all: bool,
}

impl<'a> Specials<'a> {
    pub(super) fn new(
        photos: &'a [Photo],
        located: &[Located<'a>],
        places: &'a Places,
        signals: Option<&'a dyn PhotoSignals>,
        trips: Option<&TripAnalysis<'a>>,
        surface_all: bool,
    ) -> Result<Self> {
        let pairs = match signals {
            Some(signals) => then_and_now::pairs(located, signals)?,
            None => Vec::new(),
        };
        let travel_days = trips.map(one_day::travel_days).unwrap_or_default();
        log::info!(
            "found {} then-and-now pairs and {} eventful travel days",
            pairs.len(),
            travel_days.len()
        );
        Ok(Self {
            photos,
            places,
            signals,
            pairs,
            travel_days,
            surface_all,
        })
    }

    pub(super) fn memories(
        &self,
        period: Period,
        history: &History,
        shown_elsewhere: &HashSet<i64>,
        selector: &mut Selector,
    ) -> Result<Vec<Memory>> {
        if self.surface_all {
            return self.all_memories(period, selector);
        }
        let mut formats = Format::ALL;
        selector.shuffle(&mut formats);
        formats.sort_by_key(|&format| history.last_shown(format));
        let mut others = Vec::with_capacity(SLOTS);
        let mut others_ahead_of_one_day = 0;
        for format in formats {
            let memory = match format {
                Format::ThenAndNow => {
                    then_and_now::memory(&self.pairs, period, history, self.places)
                }
                Format::YearInAFlash => {
                    year_in_a_flash::memory(self.photos, period, history, self.signals, selector)?
                }
                Format::OneDay => {
                    others_ahead_of_one_day = others.len();
                    None
                }
            };
            others.extend(memory);
        }
        if others_ahead_of_one_day < SLOTS {
            let shown_beside: HashSet<i64> = others
                .iter()
                .take(SLOTS - 1)
                .flat_map(|memory| memory.file_ids.iter().copied())
                .chain(shown_elsewhere.iter().copied())
                .collect();
            let day = one_day::memory(
                &self.travel_days,
                period,
                history,
                &shown_beside,
                self.places,
                selector,
            )?;
            if let Some(day) = day {
                others.truncate(SLOTS - 1);
                others.insert(others_ahead_of_one_day.min(others.len()), day);
                return Ok(others);
            }
        }
        others.truncate(SLOTS);
        Ok(others)
    }

    fn all_memories(&self, period: Period, selector: &mut Selector) -> Result<Vec<Memory>> {
        let mut memories = then_and_now::all_memories(&self.pairs, period, self.places);
        memories.extend(year_in_a_flash::all_memories(
            self.photos,
            period,
            self.signals,
            selector,
        )?);
        memories.extend(one_day::all_memories(
            &self.travel_days,
            period,
            self.places,
            selector,
        )?);
        Ok(memories)
    }
}

fn special(key: String, format: SpecialFormat, photos: &[&Photo], period: Period) -> Memory {
    Memory::new(
        MemoryKind::Special(Special { key, format }),
        photos,
        period.now,
        period.now + UPDATE_FREQUENCY_DAYS * MICROS_PER_DAY,
    )
}

#[cfg(test)]
mod tests {
    use std::collections::{HashMap, HashSet};

    use ente_location::Coordinate;

    use super::Format;
    use crate::memories::calendar::{MICROS_PER_DAY, MICROS_PER_HOUR};
    use crate::memories::tests::{file, located_file, micros, period};
    use crate::memories::{
        ClipVectors, MemoriesRequest, MemoryFile, MemoryKind, MlInputs, PeopleInputs, ShownSpecial,
        SpecialFormat, compute_smart_memories,
    };
    use crate::ml_store::Result;

    pub(super) const NOW: &str = "2026-11-12T09:00:00";
    pub(super) const HOME: (f64, f64) = (52.3676, 4.9041);
    pub(super) const KYOTO: (f64, f64) = (35.0116, 135.7681);
    pub(super) const LISBON: (f64, f64) = (38.7223, -9.1393);
    pub(super) const FULL_DAY: [i64; 16] =
        [7, 8, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 20, 21, 22];
    const PARK: (f64, f64) = (52.3580, 4.8686);
    const HOME_UTC_OFFSET_SECONDS: i32 = 3600;

    #[derive(Default)]
    pub(super) struct Clip {
        pub(super) scenes: HashMap<i64, [f32; 2]>,
    }

    impl Clip {
        pub(super) fn show(&mut self, file_id: i64, degrees: f32) {
            let angle = degrees.to_radians();
            self.scenes.insert(file_id, [angle.cos(), angle.sin()]);
        }

        pub(super) fn inputs(&self) -> MlInputs<'_> {
            MlInputs {
                clip: self,
                face_weights: HashMap::new(),
                people: PeopleInputs::default(),
            }
        }
    }

    impl ClipVectors for Clip {
        fn matches(&self, _: &[f32], _: f32) -> Result<Vec<(i64, f32)>> {
            Ok(Vec::new())
        }

        fn vector(&self, file_id: i64) -> Result<Option<Vec<f32>>> {
            Ok(self.scenes.get(&file_id).map(|scene| scene.to_vec()))
        }
    }

    pub(super) fn year_at_home(first_id: i64, year: i32) -> Vec<MemoryFile> {
        let new_year = micros(&format!("{year}-01-01T12:00:00"));
        (0..61)
            .map(|index| {
                located_file(
                    first_id + index,
                    new_year + index * 6 * MICROS_PER_DAY,
                    HOME,
                )
            })
            .collect()
    }

    pub(super) fn travel_day(
        first_id: i64,
        date: &str,
        hours: &[i64],
        place: (f64, f64),
    ) -> Vec<MemoryFile> {
        let utc_offset_hours = (place.1 / 15.0).round() as i64;
        hours
            .iter()
            .enumerate()
            .map(|(index, hour)| {
                let clock = format!("{date}T{hour:02}:{:02}:00", index % 60);
                MemoryFile {
                    creation_time: micros(&clock) - utc_offset_hours * MICROS_PER_HOUR,
                    local_date_time: Some(clock),
                    utc_offset_seconds: HOME_UTC_OFFSET_SECONDS,
                    location: Some(Coordinate::new(place.0, place.1)),
                    ..file(first_id + index as i64, "1970-01-01T00:00:00")
                }
            })
            .collect()
    }

    fn library() -> Vec<MemoryFile> {
        let mut files = year_at_home(1, 2023);
        files.extend(travel_day(1000, "2026-04-16", &FULL_DAY, KYOTO));
        files.push(located_file(2000, micros("2019-07-14T15:00:00"), PARK));
        files.push(located_file(2001, micros("2025-08-02T11:00:00"), PARK));
        files
    }

    fn revisited_park() -> Clip {
        let mut clip = Clip::default();
        clip.show(2000, 0.0);
        clip.show(2001, 20.0);
        clip
    }

    fn request() -> MemoriesRequest {
        MemoriesRequest {
            files: library(),
            shows_specials: true,
            ..MemoriesRequest::default()
        }
    }

    fn formats(request: &MemoriesRequest, periods: &[&str]) -> Vec<Vec<Format>> {
        let periods: Vec<_> = periods.iter().map(|now| period(now)).collect();
        let clip = revisited_park();
        compute_smart_memories(request, &periods, Some(&clip.inputs()), None)
            .unwrap()
            .periods
            .into_iter()
            .map(|memories| {
                memories
                    .into_iter()
                    .filter_map(|memory| match memory.kind {
                        MemoryKind::Special(special) => Some(match special.format {
                            SpecialFormat::ThenAndNow(_) => Format::ThenAndNow,
                            SpecialFormat::YearInAFlash { .. } => Format::YearInAFlash,
                            SpecialFormat::OneDay(_) => Format::OneDay,
                        }),
                        _ => None,
                    })
                    .collect()
            })
            .collect()
    }

    #[test]
    fn specials_stay_off_unless_requested() {
        let request = MemoriesRequest {
            shows_specials: false,
            ..request()
        };

        assert_eq!(formats(&request, &[NOW]), [[]]);
    }

    #[test]
    fn only_the_first_period_shows_two_formats_starting_with_the_ones_shown_longest_ago() {
        let mut shown = HashSet::new();
        for seed in 0..20 {
            let mut request = MemoriesRequest { seed, ..request() };

            let periods = formats(&request, &[NOW, "2026-11-15T09:00:00"]);

            assert_eq!(periods[0].len(), 2, "{periods:?}");
            assert_eq!(periods[1], [], "{periods:?}");
            shown.extend(periods[0].iter().copied());

            request.shown_specials = vec![
                ShownSpecial {
                    key: "then-and-now:1:2".to_owned(),
                    last_time_shown: micros(NOW) - MICROS_PER_DAY,
                },
                ShownSpecial {
                    key: "one-day:2020-03-09".to_owned(),
                    last_time_shown: micros(NOW) - 4 * MICROS_PER_DAY,
                },
            ];
            assert_eq!(
                formats(&request, &[NOW]),
                [[Format::YearInAFlash, Format::OneDay]]
            );
        }
        assert_eq!(shown, HashSet::from(Format::ALL));
    }

    #[test]
    fn one_day_never_shares_a_photo_with_the_special_shown_beside_it() {
        let mut files = year_at_home(1, 2023);
        files.extend(travel_day(1000, "2023-04-22", &FULL_DAY, KYOTO));
        files.extend(travel_day(2000, "2022-07-01", &FULL_DAY, LISBON));
        let request = MemoriesRequest {
            files,
            shows_specials: true,
            ..MemoriesRequest::default()
        };
        let specials = |request: &MemoriesRequest| -> Vec<(String, Vec<i64>)> {
            compute_smart_memories(request, &[period(NOW)], None, None)
                .unwrap()
                .periods
                .remove(0)
                .into_iter()
                .filter_map(|memory| match memory.kind {
                    MemoryKind::Special(special) => Some((special.key, memory.file_ids)),
                    _ => None,
                })
                .collect()
        };
        let is_from_the_kyoto_day = |id: &i64| (1000..1016).contains(id);

        for seed in 0..20 {
            let mut shown = specials(&MemoriesRequest {
                seed,
                ..request.clone()
            });
            shown.sort();
            let [(day, _), (year, frames)] = &shown[..] else {
                panic!("{shown:?}");
            };
            assert_eq!(
                (day.as_str(), year.as_str()),
                ("one-day:2022-07-01:1", "year-in-a-flash:2023")
            );
            assert!(frames.iter().any(is_from_the_kyoto_day));
        }

        let everything = specials(&MemoriesRequest {
            surface_all: true,
            ..request
        });
        assert!(
            everything
                .iter()
                .any(|(key, _)| key == "one-day:2023-04-22:1")
        );
    }

    #[test]
    fn specials_follow_on_this_day_and_show_for_three_days() {
        let mut request = request();
        for (index, year) in [2021, 2024].into_iter().enumerate() {
            for photo in 0..3 {
                request.files.push(file(
                    10_000 + index as i64 * 10 + photo,
                    &format!("{year}-11-12T1{photo}:30:00"),
                ));
            }
        }

        let memories = compute_smart_memories(&request, &[period(NOW)], None, None)
            .unwrap()
            .periods
            .remove(0);

        assert_eq!(memories[0].kind, MemoryKind::OnThisDay);
        for memory in &memories[1..3] {
            assert!(matches!(memory.kind, MemoryKind::Special(_)));
            assert_eq!(memory.first_date_to_show, micros(NOW).into());
            assert_eq!(
                memory.last_date_to_show,
                (micros(NOW) + 3 * MICROS_PER_DAY).into()
            );
        }
        assert!(
            memories[3..]
                .iter()
                .all(|memory| !matches!(memory.kind, MemoryKind::Special(_)))
        );
    }

    #[test]
    fn surfacing_everything_lists_every_available_format() {
        let request = MemoriesRequest {
            surface_all: true,
            ..request()
        };

        let formats: HashSet<Format> = formats(&request, &[NOW]).remove(0).into_iter().collect();

        assert_eq!(formats, HashSet::from(Format::ALL));
    }
}
