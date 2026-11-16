use std::cmp::Reverse;
use std::collections::{BTreeMap, HashSet};

use super::{Format, History, special};
use crate::memories::calendar::{LocalDate, MICROS_PER_DAY, MICROS_PER_HOUR};
use crate::memories::geo::{Located, mean_location};
use crate::memories::input::Period;
use crate::memories::output::{Memory, OneDay, SpecialFormat};
use crate::memories::photo::Photo;
use crate::memories::places::Places;
use crate::memories::selector::Selector;
use crate::memories::trips::TripAnalysis;
use crate::ml_store::Result;

const DAY_STARTS_AT_HOUR: i64 = 4;
const MINIMUM_PHOTOS: usize = 10;
const MINIMUM_HOURS: usize = 5;
const MINIMUM_SPAN_HOURS: i64 = 6;
const MINIMUM_AGE_DAYS: i64 = 90;
const FRAMES: usize = 16;
const BEST_DAYS: usize = 20;
const SURFACED_DAYS: usize = 12;
const DAY_COOLDOWN_DAYS: i64 = 365;
const SCORE_PER_HOUR: usize = 100;
const MAXIMUM_SCORED_PHOTOS: usize = 60;

pub(super) struct Day<'p> {
    date: LocalDate,
    part: usize,
    members: Vec<Located<'p>>,
}

impl Day<'_> {
    fn key(&self) -> String {
        let LocalDate { year, month, day } = self.date;
        let part = self.part;
        Format::OneDay.key(format_args!("{year:04}-{month:02}-{day:02}:{part}"))
    }

    fn hours(&self) -> usize {
        self.members
            .iter()
            .map(|member| story_time(member.photo).div_euclid(MICROS_PER_HOUR))
            .collect::<HashSet<_>>()
            .len()
    }

    fn span(&self) -> i64 {
        let times = self.members.iter().map(|member| member.photo.local_time);
        times.clone().max().unwrap_or(0) - times.min().unwrap_or(0)
    }

    fn is_eventful(&self) -> bool {
        self.members.len() >= MINIMUM_PHOTOS
            && self.hours() >= MINIMUM_HOURS
            && self.span() >= MINIMUM_SPAN_HOURS * MICROS_PER_HOUR
    }

    fn score(&self) -> usize {
        self.hours() * SCORE_PER_HOUR + self.members.len().min(MAXIMUM_SCORED_PHOTOS)
    }

    fn ended_by(&self, time: i64) -> bool {
        self.members
            .iter()
            .all(|member| member.photo.creation_time <= time)
    }

    fn shows_any(&self, photo_ids: &HashSet<i64>) -> bool {
        self.members
            .iter()
            .any(|member| photo_ids.contains(&member.photo.id))
    }

    fn memory(&self, period: Period, places: &Places, selector: &mut Selector) -> Result<Memory> {
        let photos = self.members.iter().map(|member| member.photo).collect();
        Ok(special(
            self.key(),
            SpecialFormat::OneDay(OneDay {
                date: self.date,
                location: mean_location(&self.members),
                location_name: places.base_name(&self.members),
            }),
            &selector.best_over_time(photos, FRAMES)?,
            period,
        ))
    }
}

pub(super) fn travel_days<'p>(trips: &TripAnalysis<'p>) -> Vec<Day<'p>> {
    let mut days: BTreeMap<(usize, LocalDate), Vec<Located>> = BTreeMap::new();
    for (trip, members) in trips.members_by_trip().enumerate() {
        for member in members {
            if !member.photo.shared && member.photo.has_capture_clock {
                let date = LocalDate::of_local_time(story_time(member.photo));
                days.entry((trip, date)).or_default().push(*member);
            }
        }
    }
    let mut parts: BTreeMap<LocalDate, usize> = BTreeMap::new();
    let mut days: Vec<Day> = days
        .into_iter()
        .map(|((_, date), members)| {
            let part = parts.entry(date).or_default();
            *part += 1;
            Day {
                date,
                part: *part,
                members,
            }
        })
        .filter(Day::is_eventful)
        .collect();
    days.sort_by_key(|day| (Reverse(day.score()), Reverse(day.date)));
    days
}

pub(super) fn memory(
    travel_days: &[Day],
    period: Period,
    history: &History,
    shown_elsewhere: &HashSet<i64>,
    places: &Places,
    selector: &mut Selector,
) -> Result<Option<Memory>> {
    let fresh: Vec<&Day> = old_enough(travel_days, period)
        .filter(|day| !history.was_shown_within(&day.key(), DAY_COOLDOWN_DAYS, period))
        .filter(|day| !day.shows_any(shown_elsewhere))
        .take(BEST_DAYS)
        .collect();
    if fresh.is_empty() {
        return Ok(None);
    }
    fresh[selector.below(fresh.len())]
        .memory(period, places, selector)
        .map(Some)
}

pub(super) fn all_memories(
    travel_days: &[Day],
    period: Period,
    places: &Places,
    selector: &mut Selector,
) -> Result<Vec<Memory>> {
    old_enough(travel_days, period)
        .take(SURFACED_DAYS)
        .map(|day| day.memory(period, places, selector))
        .collect()
}

fn old_enough<'d, 'p>(
    travel_days: &'d [Day<'p>],
    period: Period,
) -> impl Iterator<Item = &'d Day<'p>> {
    let cutoff = period.now - MINIMUM_AGE_DAYS * MICROS_PER_DAY;
    travel_days.iter().filter(move |day| day.ended_by(cutoff))
}

fn story_time(photo: &Photo) -> i64 {
    photo.local_time - DAY_STARTS_AT_HOUR * MICROS_PER_HOUR
}

#[cfg(test)]
mod tests {
    use std::collections::HashSet;
    use std::ops::Range;

    use ente_location::{City, CityMatch, Coordinate, CountryCode};

    use super::{memory, travel_days};
    use crate::memories::calendar::MICROS_PER_DAY;
    use crate::memories::places::Places;
    use crate::memories::selector::Selector;
    use crate::memories::specials::History;
    use crate::memories::specials::tests::{
        FULL_DAY, HOME, KYOTO, LISBON, NOW, travel_day, year_at_home,
    };
    use crate::memories::tests::{micros, period};
    use crate::memories::{
        CachedTrip, CityLookup, LocalDate, MemoriesRequest, Memory, MemoryFile, MemoryKind, OneDay,
        ShownSpecial, SpecialFormat, compute_smart_memories, geo, photo, trips,
    };

    const HAARLEM: (f64, f64) = (52.3874, 4.6462);

    struct Cities;

    impl CityLookup for Cities {
        fn group_cities(&self, coordinates: &[Coordinate]) -> Vec<CityMatch> {
            vec![CityMatch {
                city: City {
                    point_index: 0,
                    source_id: 0,
                    name: "Kyoto".to_owned(),
                    country_name: "Japan".to_owned(),
                    country_code: CountryCode::from_bytes(*b"JP").unwrap(),
                    latitude: KYOTO.0,
                    longitude: KYOTO.1,
                    rank: 0,
                },
                coordinate_indices: (0..coordinates.len() as u32).collect(),
            }]
        }

        fn urban_centers(&self, coordinates: &[Coordinate]) -> Vec<Option<u32>> {
            vec![None; coordinates.len()]
        }

        fn countries(&self, coordinates: &[Coordinate]) -> Vec<Option<CountryCode>> {
            vec![None; coordinates.len()]
        }

        fn country_name(&self, _: CountryCode) -> Option<String> {
            None
        }
    }

    fn request(travel: Vec<MemoryFile>) -> MemoriesRequest {
        let mut files = year_at_home(1, 2023);
        files.extend(travel);
        MemoriesRequest {
            files,
            shows_specials: true,
            ..MemoriesRequest::default()
        }
    }

    fn memories(request: &MemoriesRequest, cities: Option<&dyn CityLookup>) -> Vec<Memory> {
        compute_smart_memories(request, &[period(NOW)], None, cities)
            .unwrap()
            .periods
            .remove(0)
    }

    fn stories(
        request: &MemoriesRequest,
        cities: Option<&dyn CityLookup>,
    ) -> Vec<(OneDay, Memory)> {
        memories(request, cities)
            .into_iter()
            .filter_map(|memory| match &memory.kind {
                MemoryKind::Special(special) => match &special.format {
                    SpecialFormat::OneDay(story) => Some((story.clone(), memory)),
                    _ => None,
                },
                _ => None,
            })
            .collect()
    }

    fn dates(request: &MemoriesRequest) -> Vec<LocalDate> {
        stories(request, None)
            .into_iter()
            .map(|(story, _)| story.date)
            .collect()
    }

    #[test]
    fn tells_a_day_of_a_trip_from_morning_to_night_with_its_place() {
        let mut travel = travel_day(1000, "2026-04-16", &FULL_DAY[..12], KYOTO);
        travel.extend(travel_day(1100, "2026-04-17", &[1, 2], KYOTO));
        travel.extend(travel_day(1200, "2026-04-17", &[9, 9, 10], KYOTO));

        let stories = stories(&request(travel), None);

        assert_eq!(stories.len(), 1);
        let (story, memory) = &stories[0];
        assert_eq!(story.date, LocalDate::new(2026, 4, 16));
        assert_eq!(story.location_name, None);
        assert!((story.location.latitude - KYOTO.0).abs() < 1e-9);
        assert!((story.location.longitude - KYOTO.1).abs() < 1e-9);
        assert_eq!(
            memory.file_ids,
            (1000..1012).chain([1100, 1101]).collect::<Vec<_>>()
        );
    }

    #[test]
    fn a_day_shared_by_two_trips_is_not_told_as_one() {
        let mut travel = travel_day(1000, "2026-04-14", &FULL_DAY[..8], KYOTO);
        travel.extend(travel_day(1100, "2026-04-15", &FULL_DAY[..8], KYOTO));
        travel.extend(travel_day(1200, "2026-04-16", &[5, 5, 6, 6, 7, 7], KYOTO));
        travel.extend(travel_day(1250, "2026-04-16", &[12, 13], HOME));
        travel.extend(travel_day(
            1300,
            "2026-04-16",
            &[19, 20, 21, 21, 22, 22],
            LISBON,
        ));
        travel.extend(travel_day(1400, "2026-04-17", &FULL_DAY[..8], LISBON));
        travel.extend(travel_day(1500, "2026-04-18", &FULL_DAY[..8], LISBON));

        assert_eq!(dates(&request(travel)), []);
    }

    #[test]
    fn two_trips_on_one_date_each_tell_and_rest_their_own_day() {
        let mut travel = travel_day(1000, "2026-04-14", &FULL_DAY[..8], KYOTO);
        travel.extend(travel_day(1100, "2026-04-15", &FULL_DAY[..8], KYOTO));
        travel.extend(travel_day(
            1200,
            "2026-04-16",
            &[4, 5, 6, 7, 8, 9, 10, 10, 10, 10],
            KYOTO,
        ));
        travel.extend(travel_day(1250, "2026-04-16", &[12, 13], HOME));
        travel.extend(travel_day(
            1300,
            "2026-04-16",
            &[15, 16, 17, 18, 19, 20, 21, 21, 21, 22],
            LISBON,
        ));
        travel.extend(travel_day(1400, "2026-04-17", &FULL_DAY[..8], LISBON));
        travel.extend(travel_day(1500, "2026-04-18", &FULL_DAY[..8], LISBON));
        let told = |shown: &[&str]| -> HashSet<Vec<i64>> {
            (0..20)
                .flat_map(|seed| {
                    let request = MemoriesRequest {
                        seed,
                        shown_specials: shown
                            .iter()
                            .map(|key| ShownSpecial {
                                key: (*key).to_owned(),
                                last_time_shown: micros(NOW) - MICROS_PER_DAY,
                            })
                            .collect(),
                        ..request(travel.clone())
                    };
                    stories(&request, None)
                })
                .map(|(_, memory)| memory.file_ids)
                .collect()
        };
        let kyoto: Vec<i64> = (1200..1210).collect();
        let lisbon: Vec<i64> = (1300..1310).collect();

        assert_eq!(told(&[]), HashSet::from([kyoto.clone(), lisbon.clone()]));
        assert_eq!(told(&["one-day:2026-04-16:1"]), HashSet::from([lisbon]));
        assert_eq!(told(&["one-day:2026-04-16:2"]), HashSet::from([kyoto]));
    }

    #[test]
    fn names_the_city_most_of_the_day_was_spent_in() {
        let travel = travel_day(1000, "2026-04-16", &FULL_DAY, KYOTO);

        let stories = stories(&request(travel), Some(&Cities));

        assert_eq!(stories[0].0.location_name.as_deref(), Some("Kyoto"));
    }

    #[test]
    fn only_days_of_a_trip_away_from_home_are_told() {
        let at_home = travel_day(1000, "2026-04-16", &FULL_DAY, HOME);
        assert_eq!(dates(&request(at_home)), []);

        let next_town = travel_day(1000, "2026-04-16", &FULL_DAY, HAARLEM);
        assert_eq!(dates(&request(next_town)), []);

        let short_outing = travel_day(1000, "2026-04-16", &FULL_DAY[..12], KYOTO);
        assert_eq!(dates(&request(short_outing)), []);

        let regular_visits: Vec<MemoryFile> =
            ["2026-01-10", "2026-02-14", "2026-03-14", "2026-04-16"]
                .into_iter()
                .enumerate()
                .flat_map(|(visit, date)| {
                    travel_day(1000 + visit as i64 * 100, date, &FULL_DAY, KYOTO)
                })
                .collect();
        assert_eq!(dates(&request(regular_visits)), []);

        let trip = travel_day(1000, "2026-04-16", &FULL_DAY, KYOTO);
        assert_eq!(dates(&request(trip)), [LocalDate::new(2026, 4, 16)]);
    }

    #[test]
    fn only_photos_with_a_stored_capture_time_are_used() {
        let without_capture_time = |ids: Range<i64>| -> Vec<MemoryFile> {
            travel_day(1000, "2026-04-16", &FULL_DAY, KYOTO)
                .into_iter()
                .map(|file| {
                    let has_capture_time = !ids.contains(&file.id);
                    MemoryFile {
                        local_date_time: file.local_date_time.filter(|_| has_capture_time),
                        ..file
                    }
                })
                .collect()
        };

        assert_eq!(dates(&request(without_capture_time(1000..1016))), []);
        assert_eq!(dates(&request(without_capture_time(1000..1007))), []);

        let stories = stories(&request(without_capture_time(1000..1004)), None);
        assert_eq!(stories[0].0.date, LocalDate::new(2026, 4, 16));
        assert_eq!(stories[0].1.file_ids, (1004..1016).collect::<Vec<_>>());
    }

    #[test]
    fn days_without_enough_photos_hours_or_age_are_skipped() {
        let mut few_photos = travel_day(1000, "2026-04-16", &FULL_DAY[..9], KYOTO);
        few_photos.extend(travel_day(1100, "2026-04-17", &FULL_DAY[..9], KYOTO));
        assert_eq!(dates(&request(few_photos)), []);

        let few_hours = [9, 9, 9, 9, 10, 10, 10, 10, 11, 11, 11, 11, 12, 12, 12, 12];
        assert_eq!(
            dates(&request(travel_day(1000, "2026-04-16", &few_hours, KYOTO))),
            []
        );

        let short_span = [9, 9, 9, 10, 10, 10, 11, 11, 11, 12, 12, 12, 13, 13, 13, 13];
        assert_eq!(
            dates(&request(travel_day(1000, "2026-04-16", &short_span, KYOTO))),
            []
        );

        let recent = travel_day(1000, "2026-09-01", &FULL_DAY, KYOTO);
        assert_eq!(dates(&request(recent)), []);

        let half_shared: Vec<MemoryFile> = travel_day(1000, "2026-04-16", &FULL_DAY, KYOTO)
            .into_iter()
            .map(|file| MemoryFile {
                shared: file.id % 2 == 1,
                ..file
            })
            .collect();
        assert_eq!(dates(&request(half_shared)), []);
    }

    #[test]
    fn a_day_rests_for_a_year_and_the_fullest_days_are_listed_first() {
        let mut travel = travel_day(1000, "2025-04-16", &FULL_DAY, KYOTO);
        travel.extend(travel_day(2000, "2026-07-01", &FULL_DAY[1..], LISBON));
        let shown = |days_ago: i64| MemoriesRequest {
            shown_specials: vec![ShownSpecial {
                key: "one-day:2025-04-16:1".to_owned(),
                last_time_shown: micros(NOW) - days_ago * MICROS_PER_DAY,
            }],
            ..request(travel.clone())
        };

        let mut rested = HashSet::new();
        for seed in 0..20 {
            let resting = MemoriesRequest { seed, ..shown(364) };
            assert_eq!(dates(&resting), [LocalDate::new(2026, 7, 1)]);
            rested.extend(dates(&MemoriesRequest { seed, ..shown(366) }));
        }
        assert_eq!(
            rested,
            HashSet::from([LocalDate::new(2025, 4, 16), LocalDate::new(2026, 7, 1)])
        );

        let everything = MemoriesRequest {
            surface_all: true,
            ..shown(1)
        };
        assert_eq!(
            dates(&everything),
            [LocalDate::new(2025, 4, 16), LocalDate::new(2026, 7, 1)]
        );
    }

    #[test]
    fn a_day_keeps_resting_when_its_first_photo_is_deleted() {
        let travel = travel_day(1000, "2026-04-16", &FULL_DAY, KYOTO);
        let shown_yesterday = |travel: &[MemoryFile]| MemoriesRequest {
            shown_specials: vec![ShownSpecial {
                key: "one-day:2026-04-16:1".to_owned(),
                last_time_shown: micros(NOW) - MICROS_PER_DAY,
            }],
            ..request(travel.to_vec())
        };

        assert_eq!(
            dates(&request(travel[1..].to_vec())),
            [LocalDate::new(2026, 4, 16)]
        );
        assert_eq!(dates(&shown_yesterday(&travel)), []);
        assert_eq!(dates(&shown_yesterday(&travel[1..])), []);
    }

    #[test]
    fn a_day_with_a_photo_in_another_memory_of_the_period_is_skipped() {
        let files = request(travel_day(1000, "2026-04-16", &FULL_DAY, KYOTO)).files;
        let photos = photo::prepare(&files);
        let located = geo::located(&photos);
        let places = Places::new(&located, None);
        let analysis = trips::v3::analyze(&photos, &located, period(NOW), &places, None);
        let days = travel_days(&analysis);
        let mut selector = Selector::new(None, 0);
        let mut story = |shown_elsewhere: &[i64]| {
            memory(
                &days,
                period(NOW),
                &History::new(&[]),
                &shown_elsewhere.iter().copied().collect(),
                &places,
                &mut selector,
            )
            .unwrap()
        };

        assert!(story(&[]).is_some());
        assert!(story(&[5, 1007]).is_none());
    }

    #[test]
    fn a_trip_that_is_on_screen_keeps_its_days_back() {
        let mut travel = travel_day(1000, "2024-04-16", &FULL_DAY, KYOTO);
        travel.extend(travel_day(1100, "2024-04-17", &[9, 10], KYOTO));
        let request = request(travel);
        let trip_keys = |request: &MemoriesRequest| -> Vec<String> {
            memories(request, None)
                .into_iter()
                .filter_map(|memory| match memory.kind {
                    MemoryKind::Trip(trip) => Some(trip.key),
                    _ => None,
                })
                .collect()
        };

        let keys = trip_keys(&request);
        assert_eq!(keys.len(), 1);
        assert_eq!(dates(&request), []);

        let shown_from = |days_ago: i64| MemoriesRequest {
            cached_trips: vec![CachedTrip {
                identity_key: format!("trip:{}", keys[0]),
                first_date_to_show: micros(NOW) - days_ago * MICROS_PER_DAY,
                last_date_to_show: micros(NOW) - (days_ago - 12) * MICROS_PER_DAY,
            }],
            ..request.clone()
        };
        assert_eq!(trip_keys(&shown_from(6)), Vec::<String>::new());
        assert_eq!(dates(&shown_from(6)), []);
        assert_eq!(trip_keys(&shown_from(13)), Vec::<String>::new());
        assert_eq!(dates(&shown_from(13)), [LocalDate::new(2024, 4, 16)]);

        let everything = MemoriesRequest {
            surface_all: true,
            ..request
        };
        assert_eq!(dates(&everything), [LocalDate::new(2024, 4, 16)]);
    }
}
