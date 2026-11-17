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

const CONSISTENCY_CHAMP: Scale = Scale::new(0.5, 0.8);
const CONSISTENCY_CHAMP_MONTHLY_MINIMUM: usize = 10;
const UNPAID_PHOTOGRAPHER: Scale = Scale::new(5.0, 20.0);
const UNPAID_PHOTOGRAPHER_ALBUM_PHOTOS: usize = 5;
const MAIN_CHARACTER: Scale = Scale::new(0.25, 0.5);
const MAIN_CHARACTER_MINIMUM: usize = 30;
const EARLY_BIRD_HOURS: [u32; 4] = [4, 5, 6, 7];
const EARLY_BIRD: Scale = Scale::new(0.2, 0.4);
const NIGHT_OWL_HOURS: [u32; 6] = [22, 23, 0, 1, 2, 3];
const NIGHT_OWL: Scale = Scale::new(0.25, 0.5);
const WEEKEND_DAYS: [u32; 2] = [6, 7];
const WEEKEND_STAR: Scale = Scale::new(0.5, 0.75);
const SCREENSHOT_COLLECTOR: Scale = Scale::new(0.15, 0.4);
const SCREENSHOT_COLLECTOR_MINIMUM: usize = 100;
const HOBBY_HOPPER: Scale = Scale::new(3.0, 4.0);
const HOBBY_HOPPER_QUARTER_MINIMUM: usize = 15;
const INDOOR_KID: Scale = Scale::new(0.65, 0.85);
const INDOOR_KID_MINIMUM_CLASSIFIED: usize = 100;
const OUT_OF_OFFICE: Scale = Scale::new(4.0, 12.0);
const EVENT_HOPPER: Scale = Scale::new(10.0, 30.0);
const EVENT_HOPPER_PHOTOS_PER_DATE: usize = 3;
const ALWAYS_ROLLING: Scale = Scale::new(0.15, 0.35);
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
        scale: Scale::new(0.06, 0.18),
        minimum: 30,
    },
    SubjectBadge {
        id: RewindBadge::Pawparazzi,
        subject: Subject::Pets,
        scale: Scale::new(0.08, 0.24),
        minimum: 40,
    },
    SubjectBadge {
        id: RewindBadge::Foodie,
        subject: Subject::Food,
        scale: Scale::new(0.08, 0.24),
        minimum: 40,
    },
    SubjectBadge {
        id: RewindBadge::PlantParent,
        subject: Subject::Plants,
        scale: Scale::new(0.06, 0.18),
        minimum: 30,
    },
    SubjectBadge {
        id: RewindBadge::BuildingBuff,
        subject: Subject::Architecture,
        scale: Scale::new(0.08, 0.24),
        minimum: 40,
    },
    SubjectBadge {
        id: RewindBadge::FullThrottle,
        subject: Subject::SportsAction,
        scale: Scale::new(0.05, 0.15),
        minimum: 25,
    },
    SubjectBadge {
        id: RewindBadge::FitCheck,
        subject: Subject::Outfits,
        scale: Scale::new(0.04, 0.12),
        minimum: 20,
    },
    SubjectBadge {
        id: RewindBadge::ArtLover,
        subject: Subject::Artwork,
        scale: Scale::new(0.04, 0.12),
        minimum: 20,
    },
];

const RAREST_FIRST: [RewindBadge; 20] = [
    RewindBadge::FitCheck,
    RewindBadge::ArtLover,
    RewindBadge::FullThrottle,
    RewindBadge::SunChaser,
    RewindBadge::PlantParent,
    RewindBadge::EarlyBird,
    RewindBadge::Pawparazzi,
    RewindBadge::MainCharacter,
    RewindBadge::HobbyHopper,
    RewindBadge::BuildingBuff,
    RewindBadge::Foodie,
    RewindBadge::EventHopper,
    RewindBadge::AlwaysRolling,
    RewindBadge::ConsistencyChamp,
    RewindBadge::OutOfOffice,
    RewindBadge::ScreenshotCollector,
    RewindBadge::IndoorKid,
    RewindBadge::WeekendStar,
    RewindBadge::NightOwl,
    RewindBadge::UnpaidPhotographer,
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

struct Scale {
    qualifies: f64,
    standout: f64,
}

impl Scale {
    const fn new(qualifies: f64, standout: f64) -> Self {
        Self {
            qualifies,
            standout,
        }
    }

    fn strength(&self, signal: f64) -> Option<f64> {
        (signal >= self.qualifies)
            .then(|| ((signal - self.qualifies) / (self.standout - self.qualifies)).min(1.0))
    }
}

struct SubjectBadge {
    id: RewindBadge,
    subject: Subject,
    scale: Scale,
    minimum: usize,
}

struct Candidate {
    id: RewindBadge,
    score: f64,
    value: Option<u32>,
}

fn rarity_rank(badge: RewindBadge) -> usize {
    RAREST_FIRST
        .iter()
        .position(|&rarer| rarer == badge)
        .unwrap_or(RAREST_FIRST.len())
}

pub(in crate::rewind) fn badge_uses_ml(badge: RewindBadge) -> bool {
    matches!(
        badge,
        RewindBadge::MainCharacter
            | RewindBadge::HobbyHopper
            | RewindBadge::IndoorKid
            | RewindBadge::EventHopper
    ) || SUBJECT_BADGES.iter().any(|subject| subject.id == badge)
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
        consistency_champ(library, taken),
        unpaid_photographer(taken),
        share_of_hours(
            RewindBadge::EarlyBird,
            taken,
            &EARLY_BIRD_HOURS,
            &EARLY_BIRD,
        ),
        share_of_hours(RewindBadge::NightOwl, taken, &NIGHT_OWL_HOURS, &NIGHT_OWL),
        weekend_star(taken),
        share(
            RewindBadge::ScreenshotCollector,
            eligible
                .iter()
                .filter(|file| file.file.is_screenshot)
                .count(),
            eligible.len(),
            &SCREENSHOT_COLLECTOR,
            SCREENSHOT_COLLECTOR_MINIMUM,
        ),
        out_of_office(library, taken),
        share(
            RewindBadge::AlwaysRolling,
            taken
                .iter()
                .filter(|file| file.file.file_type == RewindFileType::Video)
                .count(),
            taken.len(),
            &ALWAYS_ROLLING,
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
                .then(rarity_rank(second.id).cmp(&rarity_rank(first.id)))
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

fn scored(id: RewindBadge, signal: f64, scale: &Scale, value: Option<u32>) -> Option<Candidate> {
    scale
        .strength(signal)
        .map(|score| Candidate { id, score, value })
}

fn share(
    id: RewindBadge,
    matching: usize,
    base: usize,
    scale: &Scale,
    minimum: usize,
) -> Option<Candidate> {
    (matching >= minimum && base > 0)
        .then(|| {
            scored(
                id,
                matching as f64 / base as f64,
                scale,
                Some(count(matching)),
            )
        })
        .flatten()
}

fn consistency_champ(library: &Library<'_>, taken: &[&YearFile<'_>]) -> Option<Candidate> {
    let mut per_month = [0usize; 12];
    for file in taken {
        per_month[file.month as usize - 1] += 1;
    }
    let mut complete = per_month[..library.complete_months()].to_vec();
    complete.sort_unstable();
    let quietest = *complete.first()?;
    let median = complete[complete.len() / 2];
    (quietest >= CONSISTENCY_CHAMP_MONTHLY_MINIMUM)
        .then(|| {
            scored(
                RewindBadge::ConsistencyChamp,
                quietest as f64 / median as f64,
                &CONSISTENCY_CHAMP,
                Some(count(complete.len())),
            )
        })
        .flatten()
}

fn unpaid_photographer(taken: &[&YearFile<'_>]) -> Option<Candidate> {
    let mut photos_per_album: HashMap<i64, usize> = HashMap::new();
    for file in taken {
        for &album in &file.file.shared_album_ids {
            *photos_per_album.entry(album).or_default() += 1;
        }
    }
    let albums = photos_per_album
        .into_values()
        .filter(|&photos| photos >= UNPAID_PHOTOGRAPHER_ALBUM_PHOTOS)
        .count();
    scored(
        RewindBadge::UnpaidPhotographer,
        albums as f64,
        &UNPAID_PHOTOGRAPHER,
        Some(count(albums)),
    )
}

fn share_of_hours(
    id: RewindBadge,
    taken: &[&YearFile<'_>],
    hours: &[u32],
    scale: &Scale,
) -> Option<Candidate> {
    let matching = taken
        .iter()
        .filter(|file| hours.contains(&file.hour))
        .count();
    share(id, matching, taken.len(), scale, 1).map(|candidate| Candidate {
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
        &WEEKEND_STAR,
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
        &MAIN_CHARACTER,
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
        &OUT_OF_OFFICE,
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
        &badge.scale,
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
    scored(
        RewindBadge::HobbyHopper,
        tops.len() as f64,
        &HOBBY_HOPPER,
        None,
    )
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
        &INDOOR_KID,
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
        &EVENT_HOPPER,
        Some(count(dates)),
    )
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use crate::rewind::clip::Subject;
    use crate::rewind::clip::tests::{clip_of, showing};
    use crate::rewind::fixtures::{
        appear, daily_photos, located, micros, person, photo, photos_every, request, request_at,
        store,
    };
    use crate::rewind::input::{RewindFile, RewindFileType};
    use crate::rewind::library::Library;
    use crate::rewind::people::People;
    use crate::rewind::report::{Badge, RewindBadge};

    use super::{badge, badge_uses_ml};

    const HOUR: i64 = 3_600_000_000;
    const DAY: i64 = 24 * HOUR;

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

    #[test]
    fn only_badges_from_faces_or_clip_count_as_ml() {
        for id in [
            RewindBadge::MainCharacter,
            RewindBadge::Foodie,
            RewindBadge::SunChaser,
            RewindBadge::IndoorKid,
        ] {
            assert!(badge_uses_ml(id), "{id:?}");
        }
        for id in [
            RewindBadge::NightOwl,
            RewindBadge::OutOfOffice,
            RewindBadge::MixedBag,
        ] {
            assert!(!badge_uses_ml(id), "{id:?}");
        }
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
    fn a_standout_badge_beats_one_that_only_just_qualifies_and_ties_go_to_the_rarer_badge() {
        let mut files = weekday_shots(1, 100, 1);
        for (position, file) in files.iter_mut().enumerate() {
            file.creation_time += 11 * HOUR;
            file.shared_album_ids = vec![position as i64 / 5];
        }
        assert_eq!(
            badge_of(with_history(files.clone())),
            generic(RewindBadge::NightOwl)
        );

        for file in files.iter_mut().skip(30) {
            file.creation_time -= 11 * HOUR;
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
    fn shared_albums_count_once_they_hold_five_of_the_years_own_photos() {
        let mut files = weekday_shots(1, 100, 1);
        for (position, file) in files.iter_mut().enumerate() {
            file.shared_album_ids = vec![position as i64 / 4];
        }
        assert_eq!(
            badge_of(with_history(files.clone())),
            generic(RewindBadge::LimitedEdition)
        );

        for (position, file) in files.iter_mut().enumerate() {
            file.shared_album_ids = vec![position as i64 / 5];
            file.is_junk = position < 50 && position % 5 == 0;
        }
        assert_eq!(
            badge_of(with_history(files)),
            Some(Badge {
                id: RewindBadge::UnpaidPhotographer,
                value: Some(10),
            })
        );
    }

    #[test]
    fn always_rolling_counts_recorded_videos_but_not_forwarded_ones() {
        let mut files = weekday_shots(1, 200, 1);
        for file in files.iter_mut().take(60) {
            file.file_type = RewindFileType::Video;
        }
        assert_eq!(
            badge_of(with_history(files.clone())),
            Some(Badge {
                id: RewindBadge::AlwaysRolling,
                value: Some(60),
            })
        );

        for file in files.iter_mut().take(30) {
            file.is_junk = true;
        }
        assert_eq!(
            badge_of(with_history(files)),
            generic(RewindBadge::LimitedEdition)
        );
    }

    #[test]
    fn consistency_needs_every_ended_month_to_keep_up_with_a_typical_month() {
        let files = daily_photos(1, "2026-01-01T12:00:00", 334);
        let mut busy_august = files.clone();
        busy_august.extend(photos_every(1000, "2026-08-10T12:00:00", 300, 0));
        assert_eq!(
            badge_of(with_history(busy_august)),
            Some(Badge {
                id: RewindBadge::ConsistencyChamp,
                value: Some(11),
            })
        );

        let quiet = micros("2026-06-11T00:00:00")..micros("2026-07-01T00:00:00");
        let quiet_june: Vec<RewindFile> = files
            .into_iter()
            .filter(|file| !quiet.contains(&file.creation_time))
            .collect();
        assert_eq!(
            badge_of(with_history(quiet_june)),
            generic(RewindBadge::MixedBag)
        );
    }

    #[test]
    fn consistency_counts_all_twelve_months_after_new_year_and_none_in_january() {
        let after_new_year = request_at(
            "2027-01-10T10:00:00",
            with_history(daily_photos(1, "2026-01-01T12:00:00", 365)),
        );
        let library = Library::of_year(&after_new_year).unwrap();
        assert_eq!(
            badge(&after_new_year, &library, None, None),
            Some(Badge {
                id: RewindBadge::ConsistencyChamp,
                value: Some(12),
            })
        );

        let mut january = daily_photos(1, "2026-01-01T12:00:00", 30);
        january.extend(daily_photos(100, "2026-01-01T18:00:00", 30));
        let in_january = request_at("2026-01-31T10:00:00", with_history(january));
        let library = Library::of_year(&in_january).unwrap();
        assert_eq!(
            badge(&in_january, &library, None, None),
            generic(RewindBadge::LimitedEdition)
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
