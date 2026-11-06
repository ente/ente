use std::cmp::Reverse;

use super::count;
use crate::rewind::input::RewindRequest;
use crate::rewind::library::Library;
use crate::rewind::people::{Entity, People};
use crate::rewind::ranking::{Ranking, best_faces};
use crate::rewind::report::{NewFace, NewFaces};

const NEW_FACE_MINIMUM_PHOTOS: usize = 5;
const NEW_FACES_MINIMUM: usize = 3;
const NEW_FACES_SHOWN: usize = 12;
const NEW_FACE_FACES: usize = 3;

pub(in crate::rewind) fn new_faces(
    request: &RewindRequest,
    library: &Library<'_>,
    people: &People,
    ranking: &Ranking<'_>,
) -> Option<NewFaces> {
    let me = request.me_person_id.as_deref();
    let named = people
        .persons()
        .iter()
        .filter(|person| Some(person.id.as_str()) != me)
        .map(|person| (person, true));
    let unnamed = people.clusters().iter().map(|cluster| (cluster, false));
    let mut arrivals: Vec<(&Entity, bool, usize)> = named
        .chain(unnamed)
        .filter(|(entity, _)| entity.first_local_time >= library.start())
        .map(|(entity, is_named)| (entity, is_named, people.files_of(entity, library).len()))
        .filter(|&(_, _, photos)| photos >= NEW_FACE_MINIMUM_PHOTOS)
        .collect();
    arrivals.sort_by(|first, second| {
        (Reverse(first.1), Reverse(first.2), &first.0.id).cmp(&(
            Reverse(second.1),
            Reverse(second.2),
            &second.0.id,
        ))
    });
    let faces: Vec<NewFace> = arrivals
        .iter()
        .filter_map(|&(entity, is_named, _)| {
            let face_ids = best_faces(ranking, people, entity, library, NEW_FACE_FACES);
            (!face_ids.is_empty()).then(|| NewFace {
                person_id: is_named.then(|| entity.id.clone()),
                cluster_id: (!is_named).then(|| entity.id.clone()),
                face_ids,
            })
        })
        .take(NEW_FACES_SHOWN)
        .collect();
    (faces.len() >= NEW_FACES_MINIMUM).then(|| NewFaces {
        count: count(arrivals.len()),
        faces,
    })
}

#[cfg(test)]
mod tests {
    use crate::rewind::fixtures::{appear, daily_photos, person, photo, request, store};
    use crate::rewind::library::Library;
    use crate::rewind::people::People;
    use crate::rewind::ranking::Ranking;

    use super::new_faces;

    #[test]
    fn people_and_clusters_first_seen_this_year_are_new_named_ones_first() {
        let (_directory, store) = store();
        let mut files = daily_photos(1, "2026-01-01T10:00:00", 100);
        files.push(photo(500, "2025-06-01T10:00:00"));
        let mut faces_request = request(files);
        faces_request.people = ["ana", "ben", "old", "me", "hidden"].map(person).to_vec();
        faces_request.people[4].is_hidden_from_memories = true;
        faces_request.me_person_id = Some("me".to_string());
        appear(&store, "ana", Some("ana"), 1..=5);
        appear(&store, "ben", Some("ben"), 11..=16);
        appear(&store, "old", Some("old"), [500].into_iter().chain(21..=30));
        appear(&store, "me", Some("me"), 31..=40);
        appear(&store, "hidden", Some("hidden"), 41..=50);
        appear(&store, "stranger", None, 51..=58);
        appear(&store, "passer-by", None, 61..=64);
        appear(&store, "deleted-person", Some("gone"), 71..=80);
        let library = Library::of_year(&faces_request).unwrap();
        let people = People::load(&faces_request, &library, &store).unwrap();
        let ranking = Ranking::new(Some(&people), None);

        let new = new_faces(&faces_request, &library, &people, &ranking).unwrap();

        assert_eq!(new.count, 3);
        let shown: Vec<(Option<&str>, Option<&str>)> = new
            .faces
            .iter()
            .map(|face| (face.person_id.as_deref(), face.cluster_id.as_deref()))
            .collect();
        assert_eq!(
            shown,
            [
                (Some("ben"), None),
                (Some("ana"), None),
                (None, Some("stranger"))
            ]
        );
        assert_eq!(new.faces[1].face_ids, ["1_ana", "2_ana", "3_ana"]);

        let mut fewer = faces_request.clone();
        fewer.people.retain(|person| person.id != "ben");
        let library = Library::of_year(&fewer).unwrap();
        let people = People::load(&fewer, &library, &store).unwrap();
        let ranking = Ranking::new(Some(&people), None);
        assert!(new_faces(&fewer, &library, &people, &ranking).is_none());
    }
}
