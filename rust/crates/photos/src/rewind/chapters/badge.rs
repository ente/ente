use std::collections::{HashMap, HashSet};

use super::spots::spots_of;
use super::{count, percent};
use crate::rewind::clip::{Clip, Similarities, Subject};
use crate::rewind::geo::distance_km;
use crate::rewind::input::{RewindFileType, RewindRequest};
use crate::rewind::library::{Library, YearFile, local_time};
use crate::rewind::people::People;
use crate::rewind::report::{Badge, RewindBadge};

const BADGE_MINIMUM_TAKEN: usize = 50;
const BADGE_SCORE_CAP: f64 = 3.0;

const CONSISTENCY_CHAMP_MONTHLY_MINIMUM: usize = 10;
const UNPAID_PHOTOGRAPHER_ALBUMS: usize = 5;
const MAIN_CHARACTER_SHARE: f64 = 0.25;
const MAIN_CHARACTER_MINIMUM: usize = 30;
const EARLY_BIRD_HOURS: [u32; 4] = [4, 5, 6, 7];
const EARLY_BIRD_SHARE: f64 = 0.20;
const NIGHT_OWL_HOURS: [u32; 6] = [22, 23, 0, 1, 2, 3];
const NIGHT_OWL_SHARE: f64 = 0.25;
const WEEKEND_DAYS: [u32; 2] = [6, 7];
const WEEKEND_STAR_SHARE: f64 = 0.50;
const SCREENSHOT_COLLECTOR_SHARE: f64 = 0.15;
const SCREENSHOT_COLLECTOR_MINIMUM: usize = 100;
const HOBBY_HOPPER_QUARTER_MINIMUM: usize = 15;
const HOBBY_HOPPER_DISTINCT_TOPS: usize = 3;
const INDOOR_KID_SHARE: f64 = 0.65;
const INDOOR_KID_MINIMUM_CLASSIFIED: usize = 100;
const OUT_OF_OFFICE_TRIPS: usize = 4;
const EVENT_HOPPER_PHOTOS_PER_DATE: usize = 3;
const EVENT_HOPPER_DATES: usize = 10;
const ALWAYS_ROLLING_SHARE: f64 = 0.15;
const ALWAYS_ROLLING_MINIMUM: usize = 50;
const LIMITED_EDITION_MAXIMUM_TAKEN: usize = 300;
const GUEST_STAR_MAXIMUM_DATES: usize = 60;
const GUEST_STAR_BUSIEST_DATES: usize = 5;
const GUEST_STAR_BUSIEST_SHARE: f64 = 0.5;
const HAPPY_SNAPPER_MINIMUM_TAKEN: usize = 3000;
const TRIP_AWAY_KM: f64 = 100.0;
const TRIP_MAXIMUM_GAP_DAYS: i64 = 2;
const TRIP_MINIMUM_DATES: usize = 2;

const SUBJECT_BADGES: [SubjectBadge; 8] = [
    SubjectBadge {
        id: RewindBadge::SunChaser,
        subject: Subject::GoldenHour,
        share: 0.06,
        minimum: 30,
    },
    SubjectBadge {
        id: RewindBadge::Pawparazzi,
        subject: Subject::Pets,
        share: 0.08,
        minimum: 40,
    },
    SubjectBadge {
        id: RewindBadge::Foodie,
        subject: Subject::Food,
        share: 0.08,
        minimum: 40,
    },
    SubjectBadge {
        id: RewindBadge::PlantParent,
        subject: Subject::Plants,
        share: 0.06,
        minimum: 30,
    },
    SubjectBadge {
        id: RewindBadge::BuildingBuff,
        subject: Subject::Architecture,
        share: 0.08,
        minimum: 40,
    },
    SubjectBadge {
        id: RewindBadge::FullThrottle,
        subject: Subject::SportsAction,
        share: 0.05,
        minimum: 25,
    },
    SubjectBadge {
        id: RewindBadge::FitCheck,
        subject: Subject::Outfits,
        share: 0.04,
        minimum: 20,
    },
    SubjectBadge {
        id: RewindBadge::ArtLover,
        subject: Subject::Artwork,
        share: 0.04,
        minimum: 20,
    },
];

const EVENTS: [Subject; 3] = [Subject::Concerts, Subject::Parties, Subject::Festivities];
const HOBBIES: [&[Subject]; 8] = [
    &[Subject::Pets],
    &[Subject::Food],
    &[Subject::Plants],
    &[Subject::Architecture],
    &[Subject::SportsAction],
    &EVENTS,
    &[Subject::Outfits],
    &[Subject::Artwork],
];

struct SubjectBadge {
    id: RewindBadge,
    subject: Subject,
    share: f64,
    minimum: usize,
}

struct Candidate {
    id: RewindBadge,
    score: f64,
    value: Option<u32>,
}

pub(in crate::rewind) fn badge(
    request: &RewindRequest,
    library: &Library<'_>,
    people: Option<&People>,
    clip: Option<&Clip>,
) -> Option<Badge> {
    if library.files().is_empty() {
        return None;
    }
    let taken: Vec<&YearFile> = library.taken().collect();
    let specific = (taken.len() >= BADGE_MINIMUM_TAKEN)
        .then(|| specific(request, library, &taken, people, clip))
        .flatten();
    Some(specific.unwrap_or_else(|| generic(request, library, &taken)))
}

fn specific(
    request: &RewindRequest,
    library: &Library<'_>,
    taken: &[&YearFile<'_>],
    people: Option<&People>,
    clip: Option<&Clip>,
) -> Option<Badge> {
    let eligible: Vec<&YearFile> = library.eligible().collect();
    let mut candidates = vec![
        consistency_champ(taken),
        unpaid_photographer(&eligible),
        share_of_hours(
            RewindBadge::EarlyBird,
            taken,
            &EARLY_BIRD_HOURS,
            EARLY_BIRD_SHARE,
        ),
        share_of_hours(
            RewindBadge::NightOwl,
            taken,
            &NIGHT_OWL_HOURS,
            NIGHT_OWL_SHARE,
        ),
        weekend_star(taken),
        share(
            RewindBadge::ScreenshotCollector,
            eligible
                .iter()
                .filter(|file| file.file.is_screenshot)
                .count(),
            eligible.len(),
            SCREENSHOT_COLLECTOR_SHARE,
            SCREENSHOT_COLLECTOR_MINIMUM,
        ),
        out_of_office(library, taken),
        share(
            RewindBadge::AlwaysRolling,
            eligible
                .iter()
                .filter(|file| file.file.file_type == RewindFileType::Video)
                .count(),
            eligible.len(),
            ALWAYS_ROLLING_SHARE,
            ALWAYS_ROLLING_MINIMUM,
        ),
    ];
    if let Some(people) = people {
        candidates.push(main_character(request, library, taken, people));
    }
    if let Some(clip) = clip {
        let classified: Vec<(&YearFile, &Similarities)> = taken
            .iter()
            .filter(|file| file.is_image())
            .filter_map(|&file| Some((file, clip.get(file.id())?)))
            .collect();
        candidates.extend(
            SUBJECT_BADGES
                .iter()
                .map(|badge| subject_share(badge, &classified)),
        );
        candidates.extend([
            hobby_hopper(&classified),
            indoor_kid(&classified),
            event_hopper(&classified),
        ]);
    }
    candidates
        .into_iter()
        .flatten()
        .max_by(|first, second| {
            first
                .score
                .total_cmp(&second.score)
                .then((second.id as usize).cmp(&(first.id as usize)))
        })
        .map(|candidate| Badge {
            id: candidate.id,
            value: candidate.value,
        })
}

fn generic(request: &RewindRequest, library: &Library<'_>, taken: &[&YearFile<'_>]) -> Badge {
    let id = if request
        .files
        .iter()
        .map(local_time)
        .min()
        .is_some_and(|first| first >= library.start())
    {
        RewindBadge::OpeningCredits
    } else if taken.len() < LIMITED_EDITION_MAXIMUM_TAKEN {
        RewindBadge::LimitedEdition
    } else if is_bursty(taken) {
        RewindBadge::GuestStar
    } else if taken.len() >= HAPPY_SNAPPER_MINIMUM_TAKEN {
        RewindBadge::HappySnapper
    } else {
        RewindBadge::MixedBag
    };
    Badge { id, value: None }
}

fn is_bursty(taken: &[&YearFile<'_>]) -> bool {
    let mut per_date: HashMap<i64, usize> = HashMap::new();
    for file in taken {
        *per_date.entry(file.day).or_default() += 1;
    }
    let mut counts: Vec<usize> = per_date.into_values().collect();
    counts.sort_unstable_by(|first, second| second.cmp(first));
    let busiest: usize = counts.iter().take(GUEST_STAR_BUSIEST_DATES).sum();
    counts.len() <= GUEST_STAR_MAXIMUM_DATES
        && busiest as f64 >= GUEST_STAR_BUSIEST_SHARE * taken.len() as f64
}

fn scored(id: RewindBadge, signal: f64, threshold: f64, value: Option<u32>) -> Option<Candidate> {
    let score = (signal / threshold).min(BADGE_SCORE_CAP);
    (score >= 1.0).then_some(Candidate { id, score, value })
}

fn share(
    id: RewindBadge,
    matching: usize,
    base: usize,
    threshold: f64,
    minimum: usize,
) -> Option<Candidate> {
    (matching >= minimum && base > 0)
        .then(|| {
            scored(
                id,
                matching as f64 / base as f64,
                threshold,
                Some(count(matching)),
            )
        })
        .flatten()
}

fn consistency_champ(taken: &[&YearFile<'_>]) -> Option<Candidate> {
    let mut per_month = [0usize; 12];
    for file in taken {
        per_month[file.month as usize - 1] += 1;
    }
    per_month
        .iter()
        .all(|&photos| photos >= CONSISTENCY_CHAMP_MONTHLY_MINIMUM)
        .then_some(Candidate {
            id: RewindBadge::ConsistencyChamp,
            score: 1.0,
            value: Some(12),
        })
}

fn unpaid_photographer(eligible: &[&YearFile<'_>]) -> Option<Candidate> {
    let albums: HashSet<i64> = eligible
        .iter()
        .flat_map(|file| file.file.shared_album_ids.iter().copied())
        .collect();
    scored(
        RewindBadge::UnpaidPhotographer,
        albums.len() as f64,
        UNPAID_PHOTOGRAPHER_ALBUMS as f64,
        Some(count(albums.len())),
    )
}

fn share_of_hours(
    id: RewindBadge,
    taken: &[&YearFile<'_>],
    hours: &[u32],
    threshold: f64,
) -> Option<Candidate> {
    let matching = taken
        .iter()
        .filter(|file| hours.contains(&file.hour))
        .count();
    share(id, matching, taken.len(), threshold, 1).map(|candidate| Candidate {
        value: None,
        ..candidate
    })
}

fn weekend_star(taken: &[&YearFile<'_>]) -> Option<Candidate> {
    let weekend = taken
        .iter()
        .filter(|file| WEEKEND_DAYS.contains(&file.weekday))
        .count();
    share(
        RewindBadge::WeekendStar,
        weekend,
        taken.len(),
        WEEKEND_STAR_SHARE,
        1,
    )
    .map(|candidate| Candidate {
        value: Some(percent(weekend, taken.len())),
        ..candidate
    })
}

fn main_character(
    request: &RewindRequest,
    library: &Library<'_>,
    taken: &[&YearFile<'_>],
    people: &People,
) -> Option<Candidate> {
    let me = request.me_person_id.as_deref()?;
    let person = people.persons().iter().find(|person| person.id == me)?;
    let images = taken.iter().filter(|file| file.is_image()).count();
    let with_me = people
        .files_of(person, library)
        .into_iter()
        .filter(|file| file.is_taken() && file.is_image())
        .count();
    share(
        RewindBadge::MainCharacter,
        with_me,
        images,
        MAIN_CHARACTER_SHARE,
        MAIN_CHARACTER_MINIMUM,
    )
    .map(|candidate| Candidate {
        value: Some(percent(with_me, images)),
        ..candidate
    })
}

fn out_of_office(library: &Library<'_>, taken: &[&YearFile<'_>]) -> Option<Candidate> {
    let home = spots_of(library)
        .into_iter()
        .max_by_key(|spot| (spot.days, spot.files.len()))?
        .center;
    let mut located_per_date: HashMap<i64, (usize, usize)> = HashMap::new();
    for file in taken {
        if let Some(location) = file.location() {
            let (located, away) = located_per_date.entry(file.day).or_default();
            *located += 1;
            if distance_km(home, location) > TRIP_AWAY_KM {
                *away += 1;
            }
        }
    }
    let mut away_dates: Vec<i64> = located_per_date
        .into_iter()
        .filter(|&(_, (located, away))| 2 * away > located)
        .map(|(day, _)| day)
        .collect();
    away_dates.sort_unstable();
    let mut trips = 0;
    let mut run = 0;
    for (position, &day) in away_dates.iter().enumerate() {
        let continues = position > 0 && day - away_dates[position - 1] <= TRIP_MAXIMUM_GAP_DAYS + 1;
        if !continues {
            run = 0;
        }
        run += 1;
        if run == TRIP_MINIMUM_DATES {
            trips += 1;
        }
    }
    scored(
        RewindBadge::OutOfOffice,
        trips as f64,
        OUT_OF_OFFICE_TRIPS as f64,
        Some(count(trips)),
    )
}

fn subject_share(
    badge: &SubjectBadge,
    classified: &[(&YearFile<'_>, &Similarities)],
) -> Option<Candidate> {
    let matching = classified
        .iter()
        .filter(|(_, similarities)| similarities.matches(badge.subject))
        .count();
    share(
        badge.id,
        matching,
        classified.len(),
        badge.share,
        badge.minimum,
    )
}

fn hobby_hopper(classified: &[(&YearFile<'_>, &Similarities)]) -> Option<Candidate> {
    let tops: HashSet<usize> = (0..4)
        .filter_map(|quarter| {
            let in_quarter: Vec<&Similarities> = classified
                .iter()
                .filter(|(file, _)| (file.month - 1) / 3 == quarter)
                .map(|&(_, similarities)| similarities)
                .collect();
            let counts = HOBBIES.map(|subjects| {
                in_quarter
                    .iter()
                    .filter(|similarities| {
                        subjects
                            .iter()
                            .any(|&subject| similarities.matches(subject))
                    })
                    .count()
            });
            (0..HOBBIES.len())
                .rev()
                .max_by_key(|&hobby| counts[hobby])
                .filter(|&hobby| counts[hobby] >= HOBBY_HOPPER_QUARTER_MINIMUM)
        })
        .collect();
    (tops.len() >= HOBBY_HOPPER_DISTINCT_TOPS).then_some(Candidate {
        id: RewindBadge::HobbyHopper,
        score: 1.0,
        value: None,
    })
}

fn indoor_kid(classified: &[(&YearFile<'_>, &Similarities)]) -> Option<Candidate> {
    let indoors = classified
        .iter()
        .filter(|(_, similarities)| {
            similarities.subject(Subject::Indoors) > similarities.subject(Subject::Outdoors)
        })
        .count();
    share(
        RewindBadge::IndoorKid,
        indoors,
        classified.len(),
        INDOOR_KID_SHARE,
        1,
    )
    .filter(|_| classified.len() >= INDOOR_KID_MINIMUM_CLASSIFIED)
    .map(|candidate| Candidate {
        value: Some(percent(indoors, classified.len())),
        ..candidate
    })
}

fn event_hopper(classified: &[(&YearFile<'_>, &Similarities)]) -> Option<Candidate> {
    let mut per_date: HashMap<i64, usize> = HashMap::new();
    for (file, similarities) in classified {
        if EVENTS.iter().any(|&subject| similarities.matches(subject)) {
            *per_date.entry(file.day).or_default() += 1;
        }
    }
    let dates = per_date
        .into_values()
        .filter(|&photos| photos >= EVENT_HOPPER_PHOTOS_PER_DATE)
        .count();
    scored(
        RewindBadge::EventHopper,
        dates as f64,
        EVENT_HOPPER_DATES as f64,
        Some(count(dates)),
    )
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use crate::rewind::clip::Subject;
    use crate::rewind::clip::tests::{clip_of, showing};
    use crate::rewind::fixtures::{appear, located, micros, person, photo, request, store};
    use crate::rewind::input::RewindFile;
    use crate::rewind::library::Library;
    use crate::rewind::people::People;
    use crate::rewind::report::{Badge, RewindBadge};

    use super::badge;

    const DAY: i64 = 86_400_000_000;

    fn weekday_shots(first_id: i64, dates: i64, per_date: i64) -> Vec<RewindFile> {
        let monday = micros("2026-03-02T12:00:00");
        (0..dates)
            .flat_map(|date| (0..per_date).map(move |shot| (date, shot)))
            .zip(first_id..)
            .map(|((date, shot), id)| {
                let mut file = photo(id, "2026-03-02T12:00:00");
                file.creation_time = monday + (date / 5 * 7 + date % 5) * DAY + shot * 60_000_000;
                file
            })
            .collect()
    }

    fn with_history(mut files: Vec<RewindFile>) -> Vec<RewindFile> {
        files.push(photo(0, "2024-05-01T12:00:00"));
        files
    }

    fn badge_of(files: Vec<RewindFile>) -> Option<Badge> {
        let badge_request = request(files);
        let library = Library::of_year(&badge_request).unwrap();
        badge(&badge_request, &library, None, None)
    }

    fn generic(id: RewindBadge) -> Option<Badge> {
        Some(Badge { id, value: None })
    }

    #[test]
    fn an_empty_year_has_no_badge_and_small_years_get_a_generic_one() {
        assert_eq!(badge_of(Vec::new()), None);
        assert_eq!(badge_of(with_history(Vec::new())), None);
        assert_eq!(
            badge_of(weekday_shots(1, 10, 1)),
            generic(RewindBadge::OpeningCredits)
        );
        assert_eq!(
            badge_of(with_history(weekday_shots(1, 10, 1))),
            generic(RewindBadge::LimitedEdition)
        );
    }

    #[test]
    fn generic_badges_follow_the_shape_of_the_year() {
        let mut bursty = weekday_shots(1, 5, 50);
        bursty.extend(weekday_shots(1000, 15, 10));
        assert_eq!(
            badge_of(with_history(bursty)),
            generic(RewindBadge::GuestStar)
        );
        assert_eq!(
            badge_of(with_history(weekday_shots(1, 100, 30))),
            generic(RewindBadge::HappySnapper)
        );
        assert_eq!(
            badge_of(with_history(weekday_shots(1, 100, 5))),
            generic(RewindBadge::MixedBag)
        );
    }

    #[test]
    fn the_strongest_capped_badge_wins_and_ties_follow_the_badge_order() {
        let mut files = weekday_shots(1, 100, 1);
        for file in &mut files {
            file.creation_time += 11 * 3_600_000_000;
        }
        let night_owl = badge_of(with_history(files.clone()));
        assert_eq!(night_owl, generic(RewindBadge::NightOwl));

        for (album, file) in files.iter_mut().enumerate().take(20) {
            file.shared_album_ids = vec![album as i64];
        }
        assert_eq!(
            badge_of(with_history(files)),
            Some(Badge {
                id: RewindBadge::UnpaidPhotographer,
                value: Some(20),
            })
        );
    }

    #[test]
    fn weekend_star_and_trips_report_their_numbers() {
        let mut files = weekday_shots(1, 40, 1);
        let saturday = micros("2026-03-07T12:00:00");
        for (position, file) in weekday_shots(100, 60, 1).into_iter().enumerate() {
            let mut file = file;
            file.creation_time = saturday + (position as i64 / 2 * 7 + position as i64 % 2) * DAY;
            files.push(file);
        }
        assert_eq!(
            badge_of(with_history(files)),
            Some(Badge {
                id: RewindBadge::WeekendStar,
                value: Some(60),
            })
        );

        let mut files: Vec<RewindFile> = weekday_shots(1, 40, 1)
            .into_iter()
            .map(|file| located(file, 52.0, 4.9))
            .collect();
        let first_trip = micros("2026-06-06T12:00:00");
        for trip in 0..4 {
            for day in 0..2 {
                for shot in 0..3 {
                    let id = 1000 + trip * 10 + day * 3 + shot;
                    let mut file = located(photo(id, "2026-06-06T12:00:00"), 48.85, 2.35);
                    file.creation_time = first_trip + (trip * 14 + day) * DAY + shot * 60_000_000;
                    files.push(file);
                }
            }
        }
        assert_eq!(
            badge_of(with_history(files)),
            Some(Badge {
                id: RewindBadge::OutOfOffice,
                value: Some(4),
            })
        );
    }

    #[test]
    fn clip_and_face_badges_need_ml() {
        let files = with_history(weekday_shots(1, 100, 2));
        let ml_request = request(files.clone());
        let library = Library::of_year(&ml_request).unwrap();
        let foods = clip_of((1..=200).map(|id| {
            let subjects: &[Subject] = if id <= 100 { &[Subject::Food] } else { &[] };
            (id, showing(subjects))
        }));
        assert_eq!(
            badge(&ml_request, &library, None, Some(&foods)),
            Some(Badge {
                id: RewindBadge::Foodie,
                value: Some(100),
            })
        );
        assert_eq!(
            badge(&ml_request, &library, None, None),
            generic(RewindBadge::LimitedEdition)
        );

        let mut shown_per_month: HashMap<u32, usize> = HashMap::new();
        let hobbies = clip_of(library.files().iter().map(|file| {
            let shown = shown_per_month.entry(file.month).or_default();
            *shown += 1;
            let subjects: &[Subject] = match (file.month, *shown <= 15) {
                (3, true) => &[Subject::Pets],
                (5, true) => &[Subject::Concerts],
                (7, true) => &[Subject::Plants],
                _ => &[],
            };
            (file.id(), showing(subjects))
        }));
        assert_eq!(
            badge(&ml_request, &library, None, Some(&hobbies)),
            generic(RewindBadge::HobbyHopper)
        );

        let (_directory, store) = store();
        let mut me_request = request(files);
        me_request.people = vec![person("me")];
        me_request.me_person_id = Some("me".to_string());
        appear(&store, "me", Some("me"), 1..=60);
        let library = Library::of_year(&me_request).unwrap();
        let people = People::load(&me_request, &library, &store).unwrap();
        assert_eq!(
            badge(&me_request, &library, Some(&people), None),
            Some(Badge {
                id: RewindBadge::MainCharacter,
                value: Some(30),
            })
        );
    }
}
