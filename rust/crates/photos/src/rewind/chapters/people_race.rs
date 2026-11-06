use std::collections::HashMap;

use super::count;
use crate::rewind::input::RewindRequest;
use crate::rewind::library::{Library, YearFile};
use crate::rewind::people::{Entity, People};
use crate::rewind::ranking::{Ranking, Spread, best_faces};
use crate::rewind::report::{PeopleRace, RacePerson};

const RACE_PEOPLE: usize = 3;
const RACE_MINIMUM_PHOTOS: usize = 10;
const RACE_FACES: usize = 5;
const RACE_CANDIDATES: usize = 8;

pub(in crate::rewind) fn people_race(
    request: &RewindRequest,
    library: &Library<'_>,
    people: &People,
    ranking: &Ranking<'_>,
) -> Option<PeopleRace> {
    let me = request.me_person_id.as_deref();
    let mut racers: Vec<(&Entity, Vec<&YearFile>)> = people
        .persons()
        .iter()
        .filter(|person| Some(person.id.as_str()) != me)
        .map(|person| (person, people.files_of(person, library)))
        .collect();
    racers.sort_by(|(first, first_files), (second, second_files)| {
        second_files
            .len()
            .cmp(&first_files.len())
            .then_with(|| first_photo(first_files).cmp(&first_photo(second_files)))
            .then_with(|| first.id.cmp(&second.id))
    });
    racers.truncate(RACE_PEOPLE);
    if racers.len() < RACE_PEOPLE
        || racers
            .iter()
            .any(|(_, files)| files.len() < RACE_MINIMUM_PHOTOS)
    {
        return None;
    }
    Some(PeopleRace {
        people: racers
            .into_iter()
            .map(|(person, files)| RacePerson {
                person_id: person.id.clone(),
                photo_count: count(files.len()),
                monthly_counts: monthly_counts(&files),
                face_ids: best_faces(ranking, people, person, library, RACE_FACES),
                file_ids: ranking.pick(
                    by_prominence(person, people, library),
                    Spread::Days,
                    RACE_CANDIDATES,
                ),
            })
            .collect(),
    })
}

fn first_photo(files: &[&YearFile<'_>]) -> Option<i64> {
    files.iter().map(|file| file.local_time).min()
}

fn monthly_counts(files: &[&YearFile<'_>]) -> Vec<u32> {
    let mut counts = vec![0; 12];
    for file in files {
        counts[file.month as usize - 1] += 1;
    }
    for month in 1..counts.len() {
        counts[month] += counts[month - 1];
    }
    counts
}

fn by_prominence<'l, 'r>(
    person: &Entity,
    people: &People,
    library: &'l Library<'r>,
) -> Vec<&'l YearFile<'r>> {
    let mut faces: HashMap<i64, (u32, f64)> = HashMap::new();
    for face in person
        .face_ids
        .iter()
        .filter_map(|face_id| people.face(face_id))
    {
        let (own_faces, prominence) = faces.entry(face.file_id).or_insert((0, 0.0));
        *own_faces += 1;
        *prominence = prominence.max(face.area * face.score);
    }
    let mut files: Vec<(&YearFile, f64)> = faces
        .into_iter()
        .filter_map(|(file_id, (own_faces, prominence))| {
            let others = people.face_count(file_id).saturating_sub(own_faces);
            Some((library.get(file_id)?, prominence / f64::from(1 + others)))
        })
        .collect();
    files.sort_by(|first, second| {
        second
            .1
            .total_cmp(&first.1)
            .then(first.0.id().cmp(&second.0.id()))
    });
    files.into_iter().map(|(file, _)| file).collect()
}

#[cfg(test)]
mod tests {
    use crate::ml_store::MlStore;
    use crate::rewind::fixtures::{
        add_faces, appear, daily_photos, face_row, person, request, store,
    };
    use crate::rewind::input::{RewindPerson, RewindRequest};
    use crate::rewind::library::Library;
    use crate::rewind::people::People;
    use crate::rewind::ranking::Ranking;

    use super::people_race;

    fn race_request(people: &[&str]) -> RewindRequest {
        let mut request = request(daily_photos(1, "2026-01-01T10:00:00", 120));
        request.people = people.iter().map(|&id| person(id)).collect();
        request.me_person_id = Some("me".to_string());
        request
    }

    fn racers(store: &MlStore) {
        appear(
            store,
            "alice",
            Some("alice"),
            (1..=12).filter(|&id| id != 5 && id != 7),
        );
        add_faces(
            store,
            &[
                (face_row("5_alice", 0.9, 0.4), "alice"),
                (face_row("7_alice", 0.99, 0.2), "alice"),
                (face_row("3_stranger", 0.9, 0.2), "stranger"),
            ],
        );
        appear(store, "bob", Some("bob"), 21..=31);
        appear(store, "carol", Some("carol"), 41..=50);
        appear(store, "frank", Some("frank"), 81..=90);
        appear(store, "dave", Some("dave"), [12].into_iter().chain(60..=74));
        appear(store, "erin", Some("erin"), 91..=110);
        appear(store, "me", Some("me"), 1..=40);
    }

    fn hidden_and_ignored(mut people: Vec<RewindPerson>) -> Vec<RewindPerson> {
        for person in &mut people {
            person.is_hidden_from_memories = person.id == "dave";
            person.is_ignored = person.id == "erin";
        }
        people
    }

    #[test]
    fn the_three_most_photographed_people_race_without_me_ignored_or_hidden_people() {
        let (_directory, store) = store();
        racers(&store);
        let mut race_request =
            race_request(&["alice", "bob", "carol", "dave", "erin", "frank", "me"]);
        race_request.people = hidden_and_ignored(race_request.people);
        let library = Library::of_year(&race_request).unwrap();
        let people = People::load(&race_request, &library, &store).unwrap();
        let ranking = Ranking::new(Some(&people), None);

        let race = people_race(&race_request, &library, &people, &ranking).unwrap();

        let ids: Vec<&str> = race
            .people
            .iter()
            .map(|racer| racer.person_id.as_str())
            .collect();
        assert_eq!(ids, ["alice", "bob", "carol"]);
        let alice = &race.people[0];
        assert_eq!(alice.photo_count, 12);
        assert_eq!(alice.monthly_counts, vec![12; 12]);
        assert_eq!(race.people[2].monthly_counts[..3], [0, 10, 10]);
        assert_eq!(alice.file_ids, [5, 7, 1, 2, 4, 6, 8, 9]);
        assert_eq!(
            alice.face_ids,
            ["7_alice", "10_alice", "11_alice", "1_alice", "2_alice"]
        );
    }

    #[test]
    fn fewer_than_three_people_with_ten_photos_skip_the_race() {
        let (_directory, store) = store();
        racers(&store);
        let mut race_request = race_request(&["alice", "bob", "dave", "erin", "me"]);
        race_request.people = hidden_and_ignored(race_request.people);
        let library = Library::of_year(&race_request).unwrap();
        let people = People::load(&race_request, &library, &store).unwrap();

        let race = people_race(
            &race_request,
            &library,
            &people,
            &Ranking::new(Some(&people), None),
        );

        assert_eq!(race, None);
    }
}
