use std::cmp::Reverse;
use std::collections::{BTreeSet, HashMap, HashSet};

use super::calendar::{Anniversary, LocalDate, MICROS_PER_DAY, upcoming_anniversary};
use super::input::{
    MemoriesRequest, MemoryPerson, PeopleInputs, Period, PhotoSignals, ShownPerson, UnnamedCluster,
};
use super::output::{Birthday, Memory, MemoryKind, PeopleActivity, PeopleMemory, PeopleMemoryType};
use super::photo::{Photo, sort_chronologically};
use super::selector::{Selector, best_for_person, first_distinct_and_spaced};
use super::signals::Signals;
use super::{MAX_MEMORY_ITEMS, MINIMUM_MEMORY_LENGTH, UPDATE_FREQUENCY_DAYS};
use crate::ml_store::Result;

const ACTIVITY_SIMILARITY: f32 = 0.20;
const PERSON_SHOW_TIMEOUT_DAYS: i64 = 16 * UPDATE_FREQUENCY_DAYS;
const LONG_AGO_DAYS: i64 = 365;
const MINIMUM_LAST_SEEN_PHOTOS: usize = 2;
const LAST_MET_WINDOW_DAYS: i64 = 7;
const BIRTHDAY_WINDOW_DAYS: i64 = 7;
const UPCOMING_BIRTHDAY_LEAD_DAYS: i64 = 5;
const ROTATION_MEMORIES_PER_PERSON: usize = 2;
const FEW_MEMORY_TYPES: usize = 2;
const NAMED_PEOPLE_DISABLING_UNNAMED_FALLBACK: usize = 5;
const MAXIMUM_UNNAMED_PEOPLE: usize = 10;
const MAXIMUM_UNNAMED_GROUP_SIZE: u32 = 6;
const MINIMUM_UNNAMED_NON_CONSECUTIVE_DAYS: usize = 4;
const UNNAMED_PERSON_ID_PREFIX: &str = "cluster:";

pub(super) struct People<'a> {
    persons: Vec<Person<'a>>,
    unnamed_people: Vec<UnnamedPerson<'a>>,
    uses_unnamed_fallback: bool,
    surface_all: bool,
    show_timeout_days: i64,
    shown: &'a [ShownPerson],
    face_counts: &'a HashMap<i64, u32>,
    signals: &'a dyn PhotoSignals,
}

struct Person<'a> {
    id: &'a str,
    is_me: bool,
    birth_date: Option<LocalDate>,
    photos: Vec<&'a Photo>,
    spotlight: Option<Vec<&'a Photo>>,
    you_and_them: Option<Vec<&'a Photo>>,
    activities: Vec<(PeopleActivity, Vec<&'a Photo>)>,
}

struct UnnamedPerson<'a> {
    id: String,
    photos: Vec<&'a Photo>,
}

#[derive(Clone, Copy)]
struct Me<'a> {
    id: &'a str,
    file_ids: &'a HashSet<i64>,
}

#[derive(Clone, Copy)]
struct Candidate<'c, 'a> {
    person_id: &'c str,
    is_unnamed_cluster: bool,
    memory_type: PeopleMemoryType,
    activity: Option<PeopleActivity>,
    photos: &'c [&'a Photo],
}

impl<'a> People<'a> {
    pub(super) fn new(
        photos: &'a [Photo],
        request: &'a MemoriesRequest,
        inputs: &'a PeopleInputs,
        signals: &'a Signals<'_>,
    ) -> Result<Self> {
        let photos_by_id: HashMap<i64, &Photo> =
            photos.iter().map(|photo| (photo.id, photo)).collect();
        let no_file_ids = HashSet::new();
        let me = request.me_person_id.as_deref().map(|id| Me {
            id,
            file_ids: inputs.person_file_ids.get(id).unwrap_or(&no_file_ids),
        });
        let mut important: Vec<&MemoryPerson> = request
            .people
            .iter()
            .filter(|person| !request.local_gallery_mode && !person.is_ignored)
            .collect();
        important.sort_by_key(|&person| &person.id);
        let activity_file_ids = match me {
            Some(me) if important.iter().any(|person| person.id != me.id) => {
                activity_file_ids(signals)?
            }
            _ => Vec::new(),
        };
        let uses_unnamed_fallback = request.shows_unnamed_people
            && (request.local_gallery_mode
                || important.len() < NAMED_PEOPLE_DISABLING_UNNAMED_FALLBACK);
        let unnamed_people =
            if uses_unnamed_fallback || (request.shows_unnamed_people && request.surface_all) {
                unnamed_people(inputs, &photos_by_id, me)
            } else {
                Vec::new()
            };
        Ok(Self {
            show_timeout_days: PERSON_SHOW_TIMEOUT_DAYS
                .min(important.len().max(1) as i64 * UPDATE_FREQUENCY_DAYS),
            persons: important
                .into_iter()
                .map(|person| Person::new(person, inputs, &photos_by_id, me, &activity_file_ids))
                .collect(),
            unnamed_people,
            uses_unnamed_fallback,
            surface_all: request.surface_all,
            shown: &request.shown_people,
            face_counts: &inputs.face_counts,
            signals,
        })
    }

    pub(super) fn memories(&self, period: Period, selector: &mut Selector) -> Result<Vec<Memory>> {
        let mut persons: Vec<&Person> = self.persons.iter().collect();
        selector.shuffle(&mut persons);
        if self.surface_all {
            return self.all_memories(&persons, period);
        }
        let mut memories = Vec::new();
        let mut rotation_pool = Vec::with_capacity(persons.len());
        for person in persons {
            let relevant = self.relevant_memories(person, period)?;
            if relevant.is_empty() {
                rotation_pool.push(person);
            }
            memories.extend(relevant);
        }
        let rotation = self.rotation_memories(&rotation_pool, period, selector)?;
        let needs_fallback = rotation.is_empty() && self.uses_unnamed_fallback;
        memories.extend(rotation);
        if needs_fallback {
            memories.extend(self.unnamed_memory(period, selector)?);
        }
        Ok(memories)
    }

    fn all_memories(&self, persons: &[&Person], period: Period) -> Result<Vec<Memory>> {
        let today = period.today();
        persons
            .iter()
            .flat_map(|person| person.candidates_by_type(today))
            .flatten()
            .chain(self.unnamed_people.iter().map(UnnamedPerson::candidate))
            .map(|candidate| self.memory(candidate, period))
            .collect()
    }

    fn relevant_memories(&self, person: &Person, period: Period) -> Result<Vec<Memory>> {
        let today = period.today();
        let mut memories = Vec::new();
        if let Some(last_seen) = person.last_seen(today)
            && is_last_met_anniversary_near(last_seen, today)
        {
            memories.push(self.memory(last_seen, period)?);
        }
        let birthday = person
            .birth_date
            .and_then(|date| upcoming_anniversary(date, today, BIRTHDAY_WINDOW_DAYS));
        if let Some(birthday) = birthday {
            let spotlight = person.spotlight().filter(|_| !person.is_me);
            for candidate in spotlight.into_iter().chain(person.you_and_them()) {
                memories.extend(self.birthday_memories(candidate, &birthday, period)?);
            }
        }
        Ok(memories)
    }

    fn rotation_memories(
        &self,
        persons: &[&Person],
        period: Period,
        selector: &mut Selector,
    ) -> Result<Vec<Memory>> {
        let today = period.today();
        for person in persons {
            if self.was_shown_within(self.show_timeout_days, period, person.id, None) {
                continue;
            }
            let types = person.candidates_by_type(today);
            let mut memories = Vec::with_capacity(ROTATION_MEMORIES_PER_PERSON);
            for candidates in &types {
                let candidate = candidates[selector.below(candidates.len())];
                let type_is_cooling_down = types.len() > FEW_MEMORY_TYPES
                    && self.was_shown_within(
                        self.show_timeout_days * 2,
                        period,
                        person.id,
                        Some(candidate.memory_type),
                    );
                if !type_is_cooling_down {
                    memories.push(self.memory(candidate, period)?);
                }
                if memories.len() == ROTATION_MEMORIES_PER_PERSON {
                    break;
                }
            }
            if !memories.is_empty() {
                return Ok(memories);
            }
        }
        Ok(Vec::new())
    }

    fn unnamed_memory(&self, period: Period, selector: &mut Selector) -> Result<Option<Memory>> {
        let eligible: Vec<&UnnamedPerson> = self
            .unnamed_people
            .iter()
            .filter(|person| {
                !self.was_shown_within(self.show_timeout_days, period, &person.id, None)
            })
            .collect();
        let weights: Vec<i64> = eligible
            .iter()
            .map(|person| self.unnamed_weight(person, period))
            .collect();
        let mut remaining = selector.below(weights.iter().sum::<i64>() as usize) as i64;
        let chosen = weights.iter().position(|weight| {
            remaining -= weight;
            remaining < 0
        });
        chosen
            .map(|index| self.memory(eligible[index].candidate(), period))
            .transpose()
    }

    fn unnamed_weight(&self, person: &UnnamedPerson, period: Period) -> i64 {
        self.shown
            .iter()
            .filter(|shown| shown.person_id == person.id)
            .map(|shown| shown.last_time_shown)
            .max()
            .map_or(self.show_timeout_days * 2, |last_time_shown| {
                ((period.now - last_time_shown) / MICROS_PER_DAY).max(1)
            })
    }

    fn was_shown_within(
        &self,
        days: i64,
        period: Period,
        person_id: &str,
        memory_type: Option<PeopleMemoryType>,
    ) -> bool {
        let cutoff = period.now - days * MICROS_PER_DAY;
        self.shown
            .iter()
            .filter(|shown| shown.person_id == person_id)
            .filter(|shown| memory_type.is_none_or(|memory_type| memory_type == shown.memory_type))
            .any(|shown| shown.last_time_shown > cutoff)
    }

    fn memory(&self, candidate: Candidate, period: Period) -> Result<Memory> {
        Ok(Memory::new(
            candidate.kind(None),
            &self.photos(candidate)?,
            period.now,
            period.now + UPDATE_FREQUENCY_DAYS * MICROS_PER_DAY,
        ))
    }

    fn birthday_memories(
        &self,
        candidate: Candidate,
        birthday: &Anniversary,
        period: Period,
    ) -> Result<[Memory; 2]> {
        let date = period.today().plus_days(birthday.days_from_today);
        let starts_at = period.start_of(date);
        let photos = self.photos(candidate)?;
        let memory = |is_upcoming, first_date_to_show, last_date_to_show| {
            let birthday = Birthday {
                is_upcoming,
                new_age: birthday.years_ago,
            };
            Memory::new(
                candidate.kind(Some(birthday)),
                &photos,
                first_date_to_show,
                last_date_to_show,
            )
        };
        Ok([
            memory(
                true,
                period.start_of(date.plus_days(-UPCOMING_BIRTHDAY_LEAD_DAYS)),
                starts_at,
            ),
            memory(false, starts_at, period.start_of(date.plus_days(1))),
        ])
    }

    fn photos<'c>(&self, candidate: Candidate<'c, 'a>) -> Result<Vec<&'a Photo>> {
        if candidate.memory_type == PeopleMemoryType::LastTimeYouSawThem {
            return first_distinct_and_spaced(
                candidate.photos,
                MINIMUM_LAST_SEEN_PHOTOS,
                MAX_MEMORY_ITEMS,
                self.signals,
            );
        }
        let mut photos = best_for_person(candidate.photos.to_vec(), self.signals)?;
        if candidate.is_unnamed_cluster {
            self.move_fewest_faces_to_front(&mut photos);
        }
        Ok(photos)
    }

    fn move_fewest_faces_to_front(&self, photos: &mut [&Photo]) {
        let fewest_faces = photos
            .iter()
            .enumerate()
            .min_by_key(|(_, photo)| self.face_counts.get(&photo.id).copied().unwrap_or(u32::MAX));
        if let Some((index, _)) = fewest_faces {
            photos[..=index].rotate_right(1);
        }
    }
}

impl<'a> Person<'a> {
    fn new(
        person: &'a MemoryPerson,
        inputs: &PeopleInputs,
        photos_by_id: &HashMap<i64, &'a Photo>,
        me: Option<Me>,
        activity_file_ids: &[(PeopleActivity, HashSet<i64>)],
    ) -> Self {
        let mut photos: Vec<&Photo> = inputs
            .person_file_ids
            .get(&person.id)
            .into_iter()
            .flatten()
            .filter_map(|file_id| photos_by_id.get(file_id).copied())
            .collect();
        sort_chronologically(&mut photos);
        let face_count = |photo: &Photo| inputs.face_counts.get(&photo.id).copied();
        let enough_matching = |matches: &dyn Fn(&Photo) -> bool| {
            let matching: Vec<&Photo> = photos
                .iter()
                .copied()
                .filter(|photo| matches(photo))
                .collect();
            (matching.len() > MINIMUM_MEMORY_LENGTH).then_some(matching)
        };
        let other_than_me = me.filter(|me| me.id != person.id);
        Self {
            id: &person.id,
            is_me: me.is_some_and(|me| me.id == person.id),
            birth_date: person.birth_date,
            spotlight: enough_matching(&|photo| face_count(photo).is_some_and(|count| count <= 1)),
            you_and_them: other_than_me.and_then(|me| {
                enough_matching(&|photo| {
                    me.file_ids.contains(&photo.id) && face_count(photo) == Some(2)
                })
            }),
            activities: other_than_me
                .iter()
                .flat_map(|_| activity_file_ids)
                .filter_map(|(activity, file_ids)| {
                    let photos = enough_matching(&|photo| file_ids.contains(&photo.id))?;
                    Some((*activity, photos))
                })
                .collect(),
            photos,
        }
    }

    fn candidate<'c>(
        &'c self,
        memory_type: PeopleMemoryType,
        activity: Option<PeopleActivity>,
        photos: &'c [&'a Photo],
    ) -> Candidate<'c, 'a> {
        Candidate {
            person_id: self.id,
            is_unnamed_cluster: false,
            memory_type,
            activity,
            photos,
        }
    }

    fn spotlight(&self) -> Option<Candidate<'_, 'a>> {
        let photos = self.spotlight.as_deref()?;
        Some(self.candidate(PeopleMemoryType::Spotlight, None, photos))
    }

    fn you_and_them(&self) -> Option<Candidate<'_, 'a>> {
        let photos = self.you_and_them.as_deref()?;
        Some(self.candidate(PeopleMemoryType::YouAndThem, None, photos))
    }

    fn last_seen(&self, today: LocalDate) -> Option<Candidate<'_, 'a>> {
        let is_long_ago = self
            .photos
            .iter()
            .all(|photo| photo.date.days_until(today) >= LONG_AGO_DAYS);
        if self.is_me || !is_long_ago {
            return None;
        }
        let last_day_start = self
            .photos
            .windows(2)
            .rposition(|pair| pair[1].creation_time - pair[0].creation_time > MICROS_PER_DAY)
            .map_or(0, |gap| gap + 1);
        let last_day = &self.photos[last_day_start..];
        (last_day.len() >= MINIMUM_LAST_SEEN_PHOTOS)
            .then(|| self.candidate(PeopleMemoryType::LastTimeYouSawThem, None, last_day))
    }

    fn candidates_by_type(&self, today: LocalDate) -> Vec<Vec<Candidate<'_, 'a>>> {
        let activities: Vec<Candidate> = self
            .activities
            .iter()
            .map(|(activity, photos)| {
                self.candidate(
                    PeopleMemoryType::DoingSomethingTogether,
                    Some(*activity),
                    photos,
                )
            })
            .collect();
        [
            self.spotlight().into_iter().collect(),
            self.you_and_them().into_iter().collect(),
            activities,
            self.last_seen(today).into_iter().collect(),
        ]
        .into_iter()
        .filter(|candidates: &Vec<Candidate>| !candidates.is_empty())
        .collect()
    }
}

impl<'a> UnnamedPerson<'a> {
    fn candidate(&self) -> Candidate<'_, 'a> {
        Candidate {
            person_id: &self.id,
            is_unnamed_cluster: true,
            memory_type: PeopleMemoryType::Spotlight,
            activity: None,
            photos: &self.photos,
        }
    }
}

impl Candidate<'_, '_> {
    fn kind(&self, birthday: Option<Birthday>) -> MemoryKind {
        MemoryKind::People(PeopleMemory {
            person_id: self.person_id.to_owned(),
            is_unnamed_cluster: self.is_unnamed_cluster,
            memory_type: self.memory_type,
            activity: self.activity,
            birthday,
        })
    }
}

fn activity_file_ids(signals: &Signals) -> Result<Vec<(PeopleActivity, HashSet<i64>)>> {
    PeopleActivity::ALL
        .into_iter()
        .map(|activity| {
            let file_ids = signals
                .matches(activity.embedding(), ACTIVITY_SIMILARITY)?
                .into_iter()
                .filter(|&(_, similarity)| similarity > ACTIVITY_SIMILARITY)
                .map(|(file_id, _)| file_id)
                .collect();
            Ok((activity, file_ids))
        })
        .collect()
}

fn is_last_met_anniversary_near(last_seen: Candidate, today: LocalDate) -> bool {
    last_seen.photos.last().is_some_and(|photo| {
        let anniversary = LocalDate::new(today.year, photo.date.month, photo.date.day);
        (0..LAST_MET_WINDOW_DAYS).contains(&today.days_until(anniversary))
    })
}

fn unnamed_people<'a>(
    inputs: &'a PeopleInputs,
    photos_by_id: &HashMap<i64, &'a Photo>,
    me: Option<Me>,
) -> Vec<UnnamedPerson<'a>> {
    if me.is_some_and(|me| me.file_ids.is_empty()) {
        return Vec::new();
    }
    let mut clusters: Vec<&UnnamedCluster> = inputs.unnamed_clusters.iter().collect();
    clusters.sort_by_key(|&cluster| (Reverse(cluster.face_count), &cluster.id));
    clusters
        .into_iter()
        .filter_map(|cluster| unnamed_person(cluster, inputs, photos_by_id, me))
        .take(MAXIMUM_UNNAMED_PEOPLE)
        .collect()
}

fn unnamed_person<'a>(
    cluster: &UnnamedCluster,
    inputs: &PeopleInputs,
    photos_by_id: &HashMap<i64, &'a Photo>,
    me: Option<Me>,
) -> Option<UnnamedPerson<'a>> {
    let is_in_small_group = |file_id: &&i64| {
        inputs
            .face_counts
            .get(*file_id)
            .is_some_and(|count| (1..=MAXIMUM_UNNAMED_GROUP_SIZE).contains(count))
    };
    let photos: Vec<&Photo> = cluster
        .file_ids
        .iter()
        .filter(is_in_small_group)
        .filter_map(|file_id| photos_by_id.get(file_id).copied())
        .collect();
    let enough_with_me = me.is_none_or(|me| {
        photos
            .iter()
            .filter(|photo| me.file_ids.contains(&photo.id))
            .count()
            >= MINIMUM_MEMORY_LENGTH
    });
    let qualifies = enough_with_me
        && photos.len() >= MINIMUM_MEMORY_LENGTH
        && non_consecutive_days(&photos) >= MINIMUM_UNNAMED_NON_CONSECUTIVE_DAYS;
    qualifies.then(|| UnnamedPerson {
        id: format!("{UNNAMED_PERSON_ID_PREFIX}{}", cluster.id),
        photos,
    })
}

fn non_consecutive_days(photos: &[&Photo]) -> usize {
    let days: BTreeSet<i64> = photos
        .iter()
        .map(|photo| photo.date.days_since_epoch())
        .collect();
    let gaps = days
        .iter()
        .zip(days.iter().skip(1))
        .filter(|(day, next_day)| *next_day - *day > 1)
        .count();
    gaps + 1
}

#[cfg(test)]
mod tests {
    use std::collections::{HashMap, HashSet};

    use crate::memories::calendar::MICROS_PER_DAY;
    use crate::memories::tests::{files_on, micros, period};
    use crate::memories::{
        Birthday, ClipVectors, LocalDate, MemoriesRequest, Memory, MemoryKind, MemoryPerson,
        MlInputs, PeopleActivity, PeopleInputs, PeopleMemory, PeopleMemoryType, ShownPerson,
        UnnamedCluster, compute_smart_memories,
    };
    use crate::ml_store::Result;

    const NOW: &str = "2026-10-30T09:00:00";

    type Summary = (String, PeopleMemoryType, Option<PeopleActivity>);

    #[derive(Default)]
    struct Library {
        request: MemoriesRequest,
        inputs: PeopleInputs,
        activities: HashMap<PeopleActivity, Vec<i64>>,
    }

    impl ClipVectors for Library {
        fn matches(&self, query: &[f32], _: f32) -> Result<Vec<(i64, f32)>> {
            let activity = PeopleActivity::ALL.into_iter().find(|activity| {
                activity
                    .embedding()
                    .iter()
                    .copied()
                    .map(f32::from)
                    .eq(query.iter().copied())
            });
            Ok(activity
                .and_then(|activity| self.activities.get(&activity))
                .into_iter()
                .flatten()
                .map(|&file_id| (file_id, 0.3))
                .collect())
        }

        fn vector(&self, _: i64) -> Result<Option<Vec<f32>>> {
            Ok(None)
        }
    }

    impl Library {
        fn new(person_ids: &[&str]) -> Self {
            let people = person_ids
                .iter()
                .map(|id| MemoryPerson {
                    id: (*id).to_owned(),
                    is_ignored: false,
                    birth_date: None,
                })
                .collect();
            Self {
                request: MemoriesRequest {
                    people,
                    ..MemoriesRequest::default()
                },
                ..Self::default()
            }
        }

        fn with_me(person_ids: &[&str]) -> Self {
            let mut library = Self::new(person_ids);
            library.request.me_person_id = Some("me".to_owned());
            library
        }

        fn add_photos(
            &mut self,
            person_ids: &[&str],
            first_id: i64,
            date: &str,
            count: i64,
            faces: u32,
        ) {
            self.request.files.extend(files_on(first_id, date, count));
            for file_id in first_id..first_id + count {
                self.inputs.face_counts.insert(file_id, faces);
                for person_id in person_ids {
                    self.inputs
                        .person_file_ids
                        .entry((*person_id).to_owned())
                        .or_default()
                        .insert(file_id);
                }
            }
        }

        fn memories(&self) -> Vec<Memory> {
            let ml = MlInputs {
                clip: self,
                face_weights: HashMap::new(),
                people: self.inputs.clone(),
            };
            compute_smart_memories(&self.request, &[period(NOW)], Some(&ml), None)
                .unwrap()
                .periods
                .remove(0)
        }

        fn people_memories(&self) -> Vec<(PeopleMemory, Memory)> {
            self.memories()
                .into_iter()
                .filter_map(|memory| match &memory.kind {
                    MemoryKind::People(people) => Some((people.clone(), memory)),
                    _ => None,
                })
                .collect()
        }

        fn summaries(&self) -> Vec<Summary> {
            self.people_memories()
                .into_iter()
                .map(|(people, _)| (people.person_id, people.memory_type, people.activity))
                .collect()
        }

        fn summaries_for_seed(&mut self, seed: u64) -> Vec<Summary> {
            self.request.seed = seed;
            self.summaries()
        }
    }

    fn summary(
        person_id: &str,
        memory_type: PeopleMemoryType,
        activity: Option<PeopleActivity>,
    ) -> Summary {
        (person_id.to_owned(), memory_type, activity)
    }

    fn shown(person_id: &str, memory_type: PeopleMemoryType, days_ago: i64) -> ShownPerson {
        ShownPerson {
            person_id: person_id.to_owned(),
            memory_type,
            last_time_shown: micros(NOW) - days_ago * MICROS_PER_DAY,
        }
    }

    fn cluster(
        id: &str,
        face_count: u32,
        file_ids: impl IntoIterator<Item = i64>,
    ) -> UnnamedCluster {
        UnnamedCluster {
            id: id.to_owned(),
            face_count,
            file_ids: file_ids.into_iter().collect(),
        }
    }

    #[test]
    fn surfacing_everything_lists_each_type_with_more_than_five_photos() {
        let mut library = Library::with_me(&["me", "alice", "bob", "ignored"]);
        library.request.people[3].is_ignored = true;
        library.request.surface_all = true;
        library.add_photos(&["me"], 1, "2026-05-01", 6, 1);
        library.add_photos(&["alice"], 11, "2026-05-02", 6, 1);
        library.add_photos(&["bob"], 21, "2026-05-03", 5, 1);
        library.add_photos(&["me", "alice"], 31, "2026-05-04", 6, 2);
        library.add_photos(&["me", "bob"], 41, "2026-05-05", 6, 3);
        library.add_photos(&["ignored"], 51, "2026-05-06", 6, 1);
        library.activities = HashMap::from([
            (PeopleActivity::Party, (1..=6).chain(11..=16).collect()),
            (PeopleActivity::Hiking, (11..=15).collect()),
        ]);

        let summaries = library.summaries();

        let of = |person_id: &str| -> Vec<Summary> {
            summaries
                .iter()
                .filter(|summary| summary.0 == person_id)
                .cloned()
                .collect()
        };
        assert_eq!(summaries.len(), 4);
        assert_eq!(
            of("alice"),
            [
                summary("alice", PeopleMemoryType::Spotlight, None),
                summary("alice", PeopleMemoryType::YouAndThem, None),
                summary(
                    "alice",
                    PeopleMemoryType::DoingSomethingTogether,
                    Some(PeopleActivity::Party)
                ),
            ]
        );
        assert_eq!(of("me"), [summary("me", PeopleMemoryType::Spotlight, None)]);
    }

    #[test]
    fn someone_not_seen_for_a_year_returns_in_the_week_before_their_last_day_comes_round() {
        let mut library = Library::new(&["alice", "bob", "carol"]);
        library.add_photos(&["alice"], 1, "2023-03-01", 3, 1);
        library.add_photos(&["alice"], 11, "2024-11-02", 3, 1);
        library.add_photos(&["bob"], 21, "2024-11-06", 3, 1);
        library.add_photos(&["carol"], 31, "2024-11-02", 3, 1);
        library.add_photos(&["carol"], 41, "2025-10-31", 1, 1);
        library.request.shown_people = ["alice", "bob", "carol"]
            .map(|id| shown(id, PeopleMemoryType::Spotlight, 1))
            .into();

        let memories = library.people_memories();

        assert_eq!(memories.len(), 1);
        let (people, memory) = &memories[0];
        assert_eq!(people.person_id, "alice");
        assert_eq!(people.memory_type, PeopleMemoryType::LastTimeYouSawThem);
        assert_eq!(memory.file_ids, [11, 12, 13]);
        assert_eq!(
            (memory.first_date_to_show, memory.last_date_to_show),
            (micros(NOW), micros(NOW) + 3 * MICROS_PER_DAY)
        );
    }

    #[test]
    fn birthdays_show_a_lead_up_and_a_day_of_memory_for_spotlight_and_you_and_them() {
        let birthday = |day| LocalDate {
            year: 1990,
            month: 11,
            day,
        };
        let mut library = Library::with_me(&["me", "alice", "bob"]);
        library.request.people[0].birth_date = Some(birthday(2));
        library.request.people[1].birth_date = Some(birthday(2));
        library.request.people[2].birth_date = Some(birthday(6));
        library.add_photos(&["me"], 1, "2026-05-01", 6, 1);
        library.add_photos(&["alice"], 11, "2026-05-02", 6, 1);
        library.add_photos(&["me", "alice"], 21, "2026-05-03", 6, 2);
        library.add_photos(&["bob"], 31, "2026-05-04", 6, 1);

        let birthdays: Vec<_> = library
            .people_memories()
            .into_iter()
            .filter_map(|(people, memory)| {
                Some((
                    people.person_id,
                    people.memory_type,
                    people.birthday?,
                    memory.first_date_to_show,
                    memory.last_date_to_show,
                ))
            })
            .collect();

        let (lead_up, day_of, day_after) = (
            micros("2026-10-28T00:00:00"),
            micros("2026-11-02T00:00:00"),
            micros("2026-11-03T00:00:00"),
        );
        let entry = |memory_type, is_upcoming, first, last| {
            let birthday = Birthday {
                is_upcoming,
                new_age: 36,
            };
            ("alice".to_owned(), memory_type, birthday, first, last)
        };
        assert_eq!(
            birthdays,
            [
                entry(PeopleMemoryType::Spotlight, true, lead_up, day_of),
                entry(PeopleMemoryType::Spotlight, false, day_of, day_after),
                entry(PeopleMemoryType::YouAndThem, true, lead_up, day_of),
                entry(PeopleMemoryType::YouAndThem, false, day_of, day_after),
            ]
        );
    }

    #[test]
    fn rotation_gives_one_rested_person_their_first_two_rested_types() {
        let mut library = Library::with_me(&["me", "alice", "bob"]);
        library.add_photos(&["alice"], 1, "2026-05-01", 6, 1);
        library.add_photos(&["me", "alice"], 11, "2026-05-02", 6, 2);
        library.add_photos(&["bob"], 21, "2026-05-03", 6, 1);
        library.activities = HashMap::from([(PeopleActivity::Party, (1..=6).collect())]);
        library.request.shown_people = vec![
            shown("alice", PeopleMemoryType::Spotlight, 12),
            shown("bob", PeopleMemoryType::YouAndThem, 8),
        ];

        for seed in 0..20 {
            assert_eq!(
                library.summaries_for_seed(seed),
                [
                    summary("alice", PeopleMemoryType::YouAndThem, None),
                    summary(
                        "alice",
                        PeopleMemoryType::DoingSomethingTogether,
                        Some(PeopleActivity::Party)
                    ),
                ]
            );
        }

        library.activities.clear();
        assert_eq!(
            library.summaries_for_seed(0),
            [
                summary("alice", PeopleMemoryType::Spotlight, None),
                summary("alice", PeopleMemoryType::YouAndThem, None),
            ]
        );

        library.request.shown_people.clear();
        let chosen_people: HashSet<String> = (0..20)
            .flat_map(|seed| library.summaries_for_seed(seed))
            .map(|summary| summary.0)
            .collect();
        assert_eq!(
            chosen_people,
            HashSet::from(["alice".to_owned(), "bob".to_owned()])
        );
    }

    fn unnamed_library(person_ids: &[&str]) -> Library {
        let mut library = Library::new(person_ids);
        library.request.shows_unnamed_people = true;
        for (index, (date, faces)) in [
            ("2025-01-01", 3),
            ("2025-01-03", 2),
            ("2025-01-05", 1),
            ("2025-01-07", 2),
            ("2025-01-09", 3),
        ]
        .into_iter()
        .enumerate()
        {
            library.add_photos(&[], index as i64 + 1, date, 1, faces);
        }
        library.add_photos(&[], 11, "2025-02-01", 5, 2);
        library.add_photos(&[], 21, "2025-02-03", 5, 7);
        library.inputs.unnamed_clusters = vec![
            cluster("same_day", 9, 11..=15),
            cluster("crowded", 8, 21..=25),
            cluster("spread_out", 5, 1..=5),
        ];
        library
    }

    #[test]
    fn unnamed_clusters_fill_in_for_rotation_with_the_clearest_photo_first() {
        let memories = unnamed_library(&[]).people_memories();

        assert_eq!(memories.len(), 1);
        let (people, memory) = &memories[0];
        assert_eq!(people.person_id, "cluster:spread_out");
        assert!(people.is_unnamed_cluster);
        assert_eq!(people.memory_type, PeopleMemoryType::Spotlight);
        assert_eq!(memory.file_ids, [3, 5, 4, 2, 1]);
    }

    #[test]
    fn unnamed_clusters_stay_away_when_hidden_cooling_down_or_replaced_by_named_people() {
        let spotlight =
            |days_ago| shown("cluster:spread_out", PeopleMemoryType::Spotlight, days_ago);
        let named_people = ["a", "b", "c", "d", "e"];

        let mut hidden = unnamed_library(&[]);
        hidden.request.shows_unnamed_people = false;
        assert!(hidden.people_memories().is_empty());

        let mut cooling_down = unnamed_library(&[]);
        cooling_down.request.shown_people = vec![spotlight(2)];
        assert!(cooling_down.people_memories().is_empty());

        let mut rested = unnamed_library(&[]);
        rested.request.shown_people = vec![spotlight(3)];
        assert_eq!(rested.people_memories().len(), 1);

        let mut replaced = unnamed_library(&named_people);
        assert!(replaced.people_memories().is_empty());
        replaced.request.surface_all = true;
        assert_eq!(replaced.people_memories().len(), 1);

        let mut local_gallery = unnamed_library(&named_people);
        local_gallery.add_photos(&["a"], 41, "2026-05-01", 6, 1);
        local_gallery.request.local_gallery_mode = true;
        assert_eq!(
            local_gallery.summaries(),
            [summary(
                "cluster:spread_out",
                PeopleMemoryType::Spotlight,
                None
            )]
        );
    }

    #[test]
    fn unnamed_clusters_need_five_photos_with_me_once_i_am_known() {
        let mut library = unnamed_library(&[]);
        library.request.me_person_id = Some("me".to_owned());
        assert!(library.people_memories().is_empty());

        library
            .inputs
            .person_file_ids
            .insert("me".to_owned(), (1..=4).collect());
        assert!(library.people_memories().is_empty());

        library
            .inputs
            .person_file_ids
            .insert("me".to_owned(), (1..=5).collect());
        assert_eq!(library.people_memories().len(), 1);
    }

    #[test]
    fn unnamed_picks_lean_towards_clusters_not_seen_for_longest() {
        let mut library = unnamed_library(&[]);
        for (index, date) in [
            "2025-03-01",
            "2025-03-03",
            "2025-03-05",
            "2025-03-07",
            "2025-03-09",
        ]
        .into_iter()
        .enumerate()
        {
            library.add_photos(&[], index as i64 + 31, date, 1, 1);
        }
        library
            .inputs
            .unnamed_clusters
            .push(cluster("seen_before", 4, 31..=35));
        library.request.shown_people =
            vec![shown("cluster:seen_before", PeopleMemoryType::Spotlight, 3)];

        let picks: Vec<String> = (0..300)
            .flat_map(|seed| library.summaries_for_seed(seed))
            .map(|summary| summary.0)
            .collect();

        let seen_before = picks
            .iter()
            .filter(|person_id| *person_id == "cluster:seen_before")
            .count();
        assert_eq!(picks.len(), 300);
        assert!((70..130).contains(&seen_before), "{seen_before}");
    }

    #[test]
    fn people_memories_follow_on_this_day_and_later_memories_skip_their_photos() {
        let mut library = Library::new(&["alice"]);
        library.add_photos(&["alice"], 1, "2024-11-01", 6, 1);
        library.add_photos(&[], 11, "2023-10-31", 1, 1);
        library.add_photos(&[], 21, "2024-10-30", 3, 1);
        library.add_photos(&[], 31, "2023-10-30", 3, 1);

        let memories = library.memories();

        assert!(matches!(memories[0].kind, MemoryKind::OnThisDay));
        assert!(matches!(memories[1].kind, MemoryKind::People(_)));
        assert_eq!(memories[1].file_ids, [1, 2, 3, 4, 5, 6]);
        let later_photos: HashSet<i64> = memories[2..]
            .iter()
            .flat_map(|memory| memory.file_ids.iter().copied())
            .collect();
        assert_eq!(later_photos, HashSet::from([11]));
    }
}
