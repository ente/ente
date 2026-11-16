use super::people_race::others_by_photos;
use crate::rewind::input::RewindRequest;
use crate::rewind::library::Library;
use crate::rewind::people::{Entity, People};
use crate::rewind::ranking::{Ranking, Spread, best_faces};
use crate::rewind::report::Mosaic;

const YEAR_PHOTOS: usize = 720;
const MOSAIC_MINIMUM_TILES: usize = 150;
const MOSAIC_FACES: usize = 5;

pub(in crate::rewind) fn year_photos(library: &Library<'_>, ranking: &Ranking<'_>) -> Vec<i64> {
    ranking.best(
        library.taken().filter(|file| file.is_image()),
        Spread::Days,
        YEAR_PHOTOS,
    )
}

pub(in crate::rewind) fn mosaic(
    request: &RewindRequest,
    library: &Library<'_>,
    people: Option<&People>,
    ranking: &Ranking<'_>,
    year_photos: &[i64],
) -> Option<Mosaic> {
    if year_photos.len() < MOSAIC_MINIMUM_TILES {
        return None;
    }
    let subject = |people: &People, person: &Entity| {
        let face_ids = best_faces(ranking, people, person, library, MOSAIC_FACES);
        (!face_ids.is_empty()).then(|| (person.id.clone(), face_ids))
    };
    let me = people
        .zip(request.me_person_id.as_deref())
        .and_then(|(people, me)| {
            let person = people.persons().iter().find(|person| person.id == me)?;
            subject(people, person)
        });
    let top = people.and_then(|people| {
        others_by_photos(request, library, people)
            .into_iter()
            .find_map(|(person, _)| subject(people, person))
    });
    let (me_person_id, me_face_ids) = me.unzip();
    let (top_person_id, top_face_ids) = top.unzip();
    Some(Mosaic {
        file_ids: year_photos.to_vec(),
        me_person_id,
        me_face_ids: me_face_ids.unwrap_or_default(),
        top_person_id,
        top_face_ids: top_face_ids.unwrap_or_default(),
    })
}

#[cfg(test)]
mod tests {
    use crate::rewind::fixtures::{appear, daily_photos, person, request, store};
    use crate::rewind::library::Library;
    use crate::rewind::people::People;
    use crate::rewind::ranking::Ranking;

    use super::{mosaic, year_photos};

    #[test]
    fn the_tiles_span_the_year_and_my_own_face_is_the_subject() {
        let (_directory, store) = store();
        appear(&store, "mine", Some("me"), 10..=14);
        appear(&store, "friends", Some("friend"), 20..=22);
        appear(&store, "sisters", Some("sister"), 30..=37);
        let mut files = daily_photos(1, "2026-01-01T10:00:00", 200);
        files[199].is_junk = true;
        let mut mosaic_request = request(files);
        mosaic_request.people = vec![person("me"), person("friend"), person("sister")];
        mosaic_request.me_person_id = Some("me".to_string());
        let library = Library::of_year(&mosaic_request).unwrap();
        let people = People::load(&mosaic_request, &library, &store).unwrap();
        let ranking = Ranking::new(Some(&people), None);

        let tiles = mosaic(
            &mosaic_request,
            &library,
            Some(&people),
            &ranking,
            &year_photos(&library, &ranking),
        )
        .unwrap();

        assert_eq!(tiles.file_ids.len(), 199);
        assert_eq!(tiles.me_person_id.as_deref(), Some("me"));
        assert_eq!(tiles.me_face_ids.len(), 5);
        assert_eq!(tiles.top_person_id.as_deref(), Some("sister"));
        assert_eq!(tiles.top_face_ids.len(), 5);

        let nobody = Ranking::new(None, None);
        let anonymous = mosaic(
            &mosaic_request,
            &library,
            None,
            &nobody,
            &year_photos(&library, &nobody),
        )
        .unwrap();
        assert_eq!(anonymous.me_person_id, None);
        assert!(anonymous.me_face_ids.is_empty());
        assert_eq!(anonymous.top_person_id, None);
        assert!(anonymous.top_face_ids.is_empty());
    }

    #[test]
    fn a_small_year_has_no_mosaic() {
        let small = request(daily_photos(1, "2026-01-01T10:00:00", 149));
        let library = Library::of_year(&small).unwrap();
        let ranking = Ranking::new(None, None);
        assert_eq!(
            mosaic(
                &small,
                &library,
                None,
                &ranking,
                &year_photos(&library, &ranking)
            ),
            None
        );
    }
}
