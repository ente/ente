use std::collections::BTreeMap;

use super::{Format, History, special};
use crate::memories::calendar::LocalDate;
use crate::memories::geo::{Located, cluster_by_location};
use crate::memories::input::{Period, PhotoSignals};
use crate::memories::output::{Memory, SpecialFormat, ThenAndNow};
use crate::memories::photo::Photo;
use crate::memories::places::Places;
use crate::memories::selector::best_first;
use crate::ml_store::Result;

const SPOT_RADIUS_KM: f64 = 0.1;
const MINIMUM_YEARS_APART: i32 = 2;
const SAME_SCENE_SIMILARITY: f32 = 0.85;
const SAME_PHOTO_SIMILARITY: f32 = 0.97;
const PHOTOS_PER_VISIT: usize = 3;
const VISITS_PER_END: usize = 6;
const SCORE_PER_YEAR_APART: f64 = 0.01;
const MAXIMUM_SCORED_YEARS: i32 = 10;
const PAIR_COOLDOWN_DAYS: i64 = 180;
const SURFACED_PAIRS: usize = 12;

pub(super) struct Pair<'p> {
    then: &'p Photo,
    now: &'p Photo,
    years_apart: i32,
    score: f64,
}

impl Pair<'_> {
    fn key(&self) -> String {
        Format::ThenAndNow.key(format_args!("{}:{}", self.then.id, self.now.id))
    }

    fn memory(&self, period: Period, places: &Places) -> Memory {
        let location_name = places
            .city(self.now.id)
            .or_else(|| places.city(self.then.id))
            .map(str::to_owned);
        special(
            self.key(),
            SpecialFormat::ThenAndNow(ThenAndNow {
                location_name,
                then_year: self.then.date.year,
                now_year: self.now.date.year,
                years_apart: self.years_apart,
            }),
            &[self.then, self.now],
            period,
        )
    }
}

pub(super) fn pairs<'p>(
    located: &[Located<'p>],
    signals: &dyn PhotoSignals,
) -> Result<Vec<Pair<'p>>> {
    let mut pairs = Vec::new();
    for spot in cluster_by_location(located.iter().copied(), SPOT_RADIUS_KM) {
        pairs.extend(best_pair(&spot.members, signals)?);
    }
    pairs.sort_by(|a: &Pair, b: &Pair| {
        b.score
            .total_cmp(&a.score)
            .then_with(|| (a.then.id, a.now.id).cmp(&(b.then.id, b.now.id)))
    });
    Ok(pairs)
}

pub(super) fn memory(
    pairs: &[Pair],
    period: Period,
    history: &History,
    places: &Places,
) -> Option<Memory> {
    pairs
        .iter()
        .find(|pair| !history.was_shown_within(&pair.key(), PAIR_COOLDOWN_DAYS, period))
        .map(|pair| pair.memory(period, places))
}

pub(super) fn all_memories(pairs: &[Pair], period: Period, places: &Places) -> Vec<Memory> {
    pairs
        .iter()
        .take(SURFACED_PAIRS)
        .map(|pair| pair.memory(period, places))
        .collect()
}

fn best_pair<'p>(members: &[Located<'p>], signals: &dyn PhotoSignals) -> Result<Option<Pair<'p>>> {
    let visits = visits(members, signals);
    let early = &visits[..visits.len().min(VISITS_PER_END)];
    let late = &visits[visits.len().saturating_sub(VISITS_PER_END)..];
    let mut best: Option<Pair> = None;
    for &then in early.iter().flatten() {
        for &now in late.iter().flatten() {
            let years_apart = then.date.whole_years_until(now.date);
            if years_apart < MINIMUM_YEARS_APART || !is_same_spot(then, now) {
                continue;
            }
            let Some(similarity) = signals.similarity(then.id, now.id)? else {
                continue;
            };
            if !(SAME_SCENE_SIMILARITY..SAME_PHOTO_SIMILARITY).contains(&similarity) {
                continue;
            }
            let score = score(similarity, years_apart);
            if best.as_ref().is_none_or(|best| score > best.score) {
                best = Some(Pair {
                    then,
                    now,
                    years_apart,
                    score,
                });
            }
        }
    }
    Ok(best)
}

fn visits<'p>(members: &[Located<'p>], signals: &dyn PhotoSignals) -> Vec<Vec<&'p Photo>> {
    let mut visits: BTreeMap<LocalDate, Vec<&Photo>> = BTreeMap::new();
    for member in members {
        visits
            .entry(member.photo.date)
            .or_default()
            .push(member.photo);
    }
    visits
        .into_values()
        .map(|photos| {
            let mut photos = best_first(&photos, signals);
            photos.truncate(PHOTOS_PER_VISIT);
            photos
        })
        .collect()
}

fn is_same_spot(then: &Photo, now: &Photo) -> bool {
    then.location
        .zip(now.location)
        .is_some_and(|(then, now)| then.distance_km(now) <= SPOT_RADIUS_KM)
}

fn score(similarity: f32, years_apart: i32) -> f64 {
    f64::from(similarity) + f64::from(years_apart.min(MAXIMUM_SCORED_YEARS)) * SCORE_PER_YEAR_APART
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use crate::memories::calendar::MICROS_PER_DAY;
    use crate::memories::specials::tests::{Clip, NOW};
    use crate::memories::tests::{located_file, micros, period};
    use crate::memories::{
        MemoriesRequest, Memory, MemoryFile, MemoryKind, MlInputs, ShownSpecial, SpecialFormat,
        ThenAndNow, compute_smart_memories,
    };

    const BEACH: (f64, f64) = (52.3713, 4.5331);
    const PARK: (f64, f64) = (52.3580, 4.8686);

    struct Library {
        files: Vec<MemoryFile>,
        clip: Clip,
        face_weights: HashMap<i64, u32>,
    }

    impl Library {
        fn new() -> Self {
            Self {
                files: Vec::new(),
                clip: Clip::default(),
                face_weights: HashMap::new(),
            }
        }

        fn photo(mut self, id: i64, date_time: &str, place: (f64, f64), degrees: f32) -> Self {
            self.files.push(located_file(id, micros(date_time), place));
            self.clip.show(id, degrees);
            self
        }

        fn memories(&self, request: MemoriesRequest) -> Vec<(ThenAndNow, Memory)> {
            let ml = MlInputs {
                face_weights: self.face_weights.clone(),
                ..self.clip.inputs()
            };
            let request = MemoriesRequest {
                files: self.files.clone(),
                shows_specials: true,
                ..request
            };
            compute_smart_memories(&request, &[period(NOW)], Some(&ml), None)
                .unwrap()
                .periods
                .remove(0)
                .into_iter()
                .filter_map(|memory| match &memory.kind {
                    MemoryKind::Special(special) => match &special.format {
                        SpecialFormat::ThenAndNow(pair) => Some((pair.clone(), memory)),
                        _ => None,
                    },
                    _ => None,
                })
                .collect()
        }

        fn pairs(&self) -> Vec<Vec<i64>> {
            self.memories(MemoriesRequest {
                surface_all: true,
                ..MemoriesRequest::default()
            })
            .into_iter()
            .map(|(_, memory)| memory.file_ids)
            .collect()
        }
    }

    #[test]
    fn pairs_the_same_scene_at_the_same_spot_at_least_two_years_apart() {
        let library = Library::new()
            .photo(1, "2019-07-14T15:00:00", BEACH, 0.0)
            .photo(2, "2019-07-14T16:00:00", BEACH, 80.0)
            .photo(3, "2025-08-02T11:00:00", BEACH, 20.0)
            .photo(4, "2025-08-02T12:00:00", BEACH, 150.0)
            .photo(5, "2020-08-02T12:00:00", BEACH, 60.0)
            .photo(6, "2024-08-02T12:00:00", PARK, 0.0);

        let memories = library.memories(MemoriesRequest::default());

        assert_eq!(memories.len(), 1);
        let (pair, memory) = &memories[0];
        assert_eq!(memory.file_ids, [1, 3]);
        assert_eq!((pair.then_year, pair.now_year), (2019, 2025));
        assert_eq!(pair.years_apart, 6);
        assert_eq!(pair.location_name, None);
        assert_eq!(memory.first_date_to_show, micros(NOW).into());
        assert_eq!(
            memory.last_date_to_show,
            (micros(NOW) + 3 * MICROS_PER_DAY).into()
        );
    }

    #[test]
    fn different_scenes_resaved_copies_and_recent_revisits_do_not_pair() {
        let different_scenes = Library::new()
            .photo(1, "2019-07-14T15:00:00", BEACH, 0.0)
            .photo(2, "2025-08-02T11:00:00", BEACH, 45.0);
        assert_eq!(different_scenes.pairs(), Vec::<Vec<i64>>::new());

        let resaved_copy = Library::new()
            .photo(1, "2019-07-14T15:00:00", BEACH, 0.0)
            .photo(2, "2025-08-02T11:00:00", BEACH, 0.0);
        assert_eq!(resaved_copy.pairs(), Vec::<Vec<i64>>::new());

        let recent_revisit = Library::new()
            .photo(1, "2024-07-14T15:00:00", BEACH, 0.0)
            .photo(2, "2025-08-02T11:00:00", BEACH, 20.0);
        assert_eq!(recent_revisit.pairs(), Vec::<Vec<i64>>::new());

        let other_spot = Library::new()
            .photo(1, "2019-07-14T15:00:00", BEACH, 0.0)
            .photo(2, "2025-08-02T11:00:00", PARK, 20.0);
        assert_eq!(other_spot.pairs(), Vec::<Vec<i64>>::new());
    }

    #[test]
    fn photos_more_than_a_hundred_metres_apart_do_not_pair() {
        let north_of = |metres: f64| (BEACH.0 + metres / 111_195.0, BEACH.1);
        let across_the_spot = Library::new()
            .photo(1, "2019-07-14T15:00:00", BEACH, 0.0)
            .photo(2, "2025-08-02T11:00:00", north_of(139.0), 20.0);
        assert_eq!(across_the_spot.pairs(), Vec::<Vec<i64>>::new());

        let around_a_drifting_centre = Library::new()
            .photo(1, "2016-07-14T15:00:00", BEACH, 0.0)
            .photo(2, "2019-07-14T15:00:00", north_of(89.0), 0.0)
            .photo(3, "2025-08-02T11:00:00", north_of(178.0), 20.0);
        assert_eq!(around_a_drifting_centre.pairs(), [[2, 3]]);
    }

    #[test]
    fn pairs_need_two_completed_years_between_them() {
        let pair = |then: &str, now: &str| {
            Library::new()
                .photo(1, then, BEACH, 0.0)
                .photo(2, now, BEACH, 20.0)
                .memories(MemoriesRequest::default())
                .into_iter()
                .map(|(pair, _)| (pair.then_year, pair.now_year, pair.years_apart))
                .collect::<Vec<_>>()
        };

        assert_eq!(pair("2023-01-01T12:00:00", "2024-12-31T12:00:00"), []);
        assert_eq!(
            pair("2023-01-01T12:00:00", "2025-01-01T12:00:00"),
            [(2023, 2025, 2)]
        );
        assert_eq!(
            pair("2018-12-31T12:00:00", "2021-01-02T12:00:00"),
            [(2018, 2021, 2)]
        );
        assert_eq!(pair("2020-02-29T12:00:00", "2022-02-28T12:00:00"), []);
        assert_eq!(
            pair("2020-02-29T12:00:00", "2022-03-01T12:00:00"),
            [(2020, 2022, 2)]
        );
    }

    #[test]
    fn each_spot_offers_its_best_pair_and_longer_gaps_and_faces_break_ties() {
        let mut library = Library::new()
            .photo(1, "2016-07-14T15:00:00", BEACH, 0.0)
            .photo(2, "2019-07-14T15:00:00", BEACH, 0.0)
            .photo(3, "2025-08-02T11:00:00", BEACH, 20.0)
            .photo(10, "2019-05-01T10:00:00", PARK, 0.0)
            .photo(11, "2019-05-01T11:00:00", PARK, 0.0)
            .photo(12, "2022-05-01T10:00:00", PARK, 20.0);
        library.face_weights = HashMap::from([(11, 1), (12, 10)]);

        assert_eq!(library.pairs(), [[1, 3], [11, 12]]);
    }

    #[test]
    fn a_pair_rests_for_half_a_year_after_it_was_shown() {
        let library = Library::new()
            .photo(1, "2019-07-14T15:00:00", BEACH, 0.0)
            .photo(3, "2025-08-02T11:00:00", BEACH, 20.0)
            .photo(11, "2019-05-01T11:00:00", PARK, 0.0)
            .photo(12, "2022-05-01T10:00:00", PARK, 30.0);
        let shown = |days_ago: i64| MemoriesRequest {
            shown_specials: vec![ShownSpecial {
                key: "then-and-now:1:3".to_owned(),
                last_time_shown: micros(NOW) - days_ago * MICROS_PER_DAY,
            }],
            ..MemoriesRequest::default()
        };
        let file_ids = |request| -> Vec<Vec<i64>> {
            library
                .memories(request)
                .into_iter()
                .map(|(_, memory)| memory.file_ids)
                .collect()
        };

        assert_eq!(file_ids(shown(179)), [[11, 12]]);
        assert_eq!(file_ids(shown(181)), [[1, 3]]);
    }
}
