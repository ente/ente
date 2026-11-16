use std::collections::{BTreeMap, HashSet};

use super::count;
use super::people_race::others_by_photos;
use crate::rewind::input::RewindRequest;
use crate::rewind::library::{Library, MICROS_PER_DAY, YearFile};
use crate::rewind::people::{Entity, Eyes, People};
use crate::rewind::ranking::Ranking;
use crate::rewind::report::{Timelapse, TimelapseFrame};

const TIMELAPSE_FRAMES: usize = 40;
const TIMELAPSE_MINIMUM_FRAMES: usize = 10;
const TIMELAPSE_MINIMUM_MONTHS: usize = 3;
const TIMELAPSE_MINIMUM_SCORE: f64 = 0.75;
const TIMELAPSE_BLURRY: f64 = 10.0;
const TIMELAPSE_MINIMUM_EYE_DISTANCE: f64 = 0.06;
const TIMELAPSE_MAXIMUM_TILT: f64 = 0.45;
const TIMELAPSE_MAXIMUM_TURN: f64 = 0.3;
const TIMELAPSE_SHARP_BLUR: f64 = 100.0;
const EYE_UNITS: f64 = 100_000.0;

struct Candidate<'l, 'r> {
    file: &'l YearFile<'r>,
    eyes: Eyes,
    quality: f64,
}

pub(in crate::rewind) fn timelapse(
    request: &RewindRequest,
    library: &Library<'_>,
    people: &People,
    ranking: &Ranking<'_>,
) -> Option<Timelapse> {
    let me = request
        .me_person_id
        .as_deref()
        .and_then(|me| people.persons().iter().find(|person| person.id == me));
    others_by_photos(request, library, people)
        .into_iter()
        .map(|(person, files)| (person, files.len(), false))
        .chain(me.map(|person| (person, people.files_of(person, library).len(), true)))
        .find_map(|(person, photos, is_me)| {
            let frames = frames(person, library, people, ranking);
            let months: HashSet<u32> = frames.iter().map(|frame| frame.month).collect();
            (frames.len() >= TIMELAPSE_MINIMUM_FRAMES && months.len() >= TIMELAPSE_MINIMUM_MONTHS)
                .then(|| Timelapse {
                    person_id: person.id.clone(),
                    is_me,
                    photo_count: count(photos),
                    frames,
                })
        })
}

fn frames(
    person: &Entity,
    library: &Library<'_>,
    people: &People,
    ranking: &Ranking<'_>,
) -> Vec<TimelapseFrame> {
    let first_day = library.start().div_euclid(MICROS_PER_DAY);
    let mut slots: BTreeMap<usize, Candidate> = BTreeMap::new();
    for face in person
        .face_ids
        .iter()
        .filter_map(|face_id| people.face(face_id))
    {
        let Some(file) = library
            .get(face.file_id)
            .filter(|file| ranking.is_showable(file))
        else {
            continue;
        };
        let Some(eyes) = face.eyes else {
            continue;
        };
        let across = (eyes.right.0 - eyes.left.0, eyes.right.1 - eyes.left.1);
        let distance = across.0.hypot(across.1);
        let centre = (eyes.left.0 + eyes.right.0) / 2.0;
        if face.score < TIMELAPSE_MINIMUM_SCORE
            || face.blur <= TIMELAPSE_BLURRY
            || distance < TIMELAPSE_MINIMUM_EYE_DISTANCE
            || across.0 <= 0.0
            || (across.1 / across.0).abs() > TIMELAPSE_MAXIMUM_TILT
            || ((eyes.nose.0 - centre) / distance).abs() > TIMELAPSE_MAXIMUM_TURN
        {
            continue;
        }
        let sharpness = (face.blur / TIMELAPSE_SHARP_BLUR).clamp(0.2, 1.0);
        let candidate = Candidate {
            file,
            eyes,
            quality: distance.powf(1.5) * sharpness * face.score,
        };
        let day = (file.day - first_day).max(0) as usize;
        let slot = (day * TIMELAPSE_FRAMES / library.elapsed_days()).min(TIMELAPSE_FRAMES - 1);
        match slots.get(&slot) {
            Some(best)
                if (best.quality, -best.file.id()) >= (candidate.quality, -candidate.file.id()) => {
            }
            _ => {
                slots.insert(slot, candidate);
            }
        }
    }
    slots
        .into_values()
        .map(|candidate| TimelapseFrame {
            file_id: candidate.file.id(),
            month: candidate.file.month,
            day: candidate.file.day_of_month,
            left_eye_x: units(candidate.eyes.left.0),
            left_eye_y: units(candidate.eyes.left.1),
            right_eye_x: units(candidate.eyes.right.0),
            right_eye_y: units(candidate.eyes.right.1),
        })
        .collect()
}

fn units(position: f64) -> u32 {
    (position.clamp(0.0, 1.0) * EYE_UNITS).round() as u32
}

#[cfg(test)]
mod tests {
    use crate::ml_db::FaceRow;
    use crate::rewind::fixtures::{add_faces, face_row, person, photos_every, request, store};
    use crate::rewind::library::Library;
    use crate::rewind::people::People;
    use crate::rewind::ranking::Ranking;
    use crate::rewind::report::TimelapseFrame;

    use super::timelapse;

    fn facing(file_id: i64, cluster: &str, eye_distance: f64, nose_shift: f64) -> FaceRow {
        let mut face = face_row(&format!("{file_id}_{cluster}"), 0.9, 0.3);
        face.detection_json = format!(
            r#"{{"box":{{"x":0.3,"y":0.2,"width":0.3,"height":0.3}},"landmarks":[{{"x":0.4,"y":0.3}},{{"x":{},"y":0.3}},{{"x":{},"y":0.36}},{{"x":0.42,"y":0.42}},{{"x":0.48,"y":0.42}}]}}"#,
            0.4 + eye_distance,
            0.4 + eye_distance / 2.0 + nose_shift,
        );
        face
    }

    #[test]
    fn frames_follow_the_year_with_the_clearest_frontal_face_of_each_stretch() {
        let (_directory, store) = store();
        let files = photos_every(1, "2026-01-01T10:00:00", 60, 5);
        let mut faces: Vec<(FaceRow, &str)> = (1..=60)
            .map(|file_id| (facing(file_id, "kid", 0.1, 0.0), "kid"))
            .collect();
        faces[0].0 = facing(1, "kid", 0.1, 0.06);
        faces[1].0 = facing(2, "kid", 0.2, 0.0);
        faces[2].0 = facing(3, "kid", 0.02, 0.0);
        add_faces(&store, &faces);
        store.db().assign_cluster_to_person("kid", "kid").unwrap();
        let mut timelapse_request = request(files);
        timelapse_request.people = vec![person("kid")];
        let library = Library::of_year(&timelapse_request).unwrap();
        let people = People::load(&timelapse_request, &library, &store).unwrap();

        let lapse = timelapse(
            &timelapse_request,
            &library,
            &people,
            &Ranking::new(Some(&people), None),
        )
        .unwrap();

        assert_eq!(lapse.person_id, "kid");
        assert!(!lapse.is_me);
        assert_eq!(lapse.photo_count, 60);
        assert_eq!(
            lapse.frames[0],
            TimelapseFrame {
                file_id: 2,
                month: 1,
                day: 6,
                left_eye_x: 40_000,
                left_eye_y: 30_000,
                right_eye_x: 60_000,
                right_eye_y: 30_000,
            }
        );
        assert!(
            lapse
                .frames
                .iter()
                .all(|frame| frame.file_id != 1 && frame.file_id != 3)
        );
        assert!(
            lapse
                .frames
                .windows(2)
                .all(|pair| pair[0].file_id < pair[1].file_id)
        );
        assert!(lapse.frames.len() >= 30);
    }

    #[test]
    fn everyone_else_is_tried_in_turn_before_my_own_face() {
        let (_directory, store) = store();
        let files = photos_every(1, "2026-01-01T10:00:00", 70, 5);
        let mut faces: Vec<(FaceRow, &str)> = Vec::new();
        for file_id in 1..=70 {
            for distant in ["aunt", "uncle", "cousin"] {
                faces.push((facing(file_id, distant, 0.02, 0.0), distant));
            }
            if file_id <= 65 {
                faces.push((facing(file_id, "me", 0.1, 0.0), "me"));
            }
            if file_id <= 60 {
                faces.push((facing(file_id, "kid", 0.1, 0.0), "kid"));
            }
        }
        add_faces(&store, &faces);
        let everyone = ["aunt", "uncle", "cousin", "kid", "me"];
        for name in everyone {
            store.db().assign_cluster_to_person(name, name).unwrap();
        }
        let mut family = request(files.clone());
        family.people = everyone.map(person).to_vec();
        family.me_person_id = Some("me".to_string());
        let library = Library::of_year(&family).unwrap();
        let people = People::load(&family, &library, &store).unwrap();
        let ranking = Ranking::new(Some(&people), None);

        let lapse = timelapse(&family, &library, &people, &ranking).unwrap();
        assert_eq!(lapse.person_id, "kid");
        assert!(!lapse.is_me);

        let mut without_kid = request(files);
        without_kid.people = ["aunt", "uncle", "cousin", "me"].map(person).to_vec();
        without_kid.me_person_id = Some("me".to_string());
        let library = Library::of_year(&without_kid).unwrap();
        let people = People::load(&without_kid, &library, &store).unwrap();
        let ranking = Ranking::new(Some(&people), None);
        let mine = timelapse(&without_kid, &library, &people, &ranking).unwrap();
        assert_eq!(mine.person_id, "me");
        assert!(mine.is_me);
        assert_eq!(mine.photo_count, 65);
    }

    #[test]
    fn blurry_faces_do_not_make_a_timelapse() {
        let (_directory, store) = store();
        let files = photos_every(1, "2026-01-01T10:00:00", 70, 5);
        let mut faces: Vec<(FaceRow, &str)> = Vec::new();
        for file_id in 1..=70 {
            let mut blurry = facing(file_id, "blurry", 0.1, 0.0);
            blurry.blur = 10.0;
            faces.push((blurry, "blurry"));
            if file_id <= 60 {
                faces.push((facing(file_id, "kid", 0.1, 0.0), "kid"));
            }
        }
        add_faces(&store, &faces);
        for name in ["blurry", "kid"] {
            store.db().assign_cluster_to_person(name, name).unwrap();
        }
        let mut family = request(files);
        family.people = ["blurry", "kid"].map(person).to_vec();
        let library = Library::of_year(&family).unwrap();
        let people = People::load(&family, &library, &store).unwrap();

        let lapse = timelapse(
            &family,
            &library,
            &people,
            &Ranking::new(Some(&people), None),
        )
        .unwrap();

        assert_eq!(lapse.person_id, "kid");
    }

    #[test]
    fn too_few_good_faces_make_no_timelapse() {
        let (_directory, store) = store();
        let files = photos_every(1, "2026-01-01T10:00:00", 9, 20);
        let faces: Vec<(FaceRow, &str)> = (1..=9)
            .map(|file_id| (facing(file_id, "kid", 0.1, 0.0), "kid"))
            .collect();
        add_faces(&store, &faces);
        store.db().assign_cluster_to_person("kid", "kid").unwrap();
        let mut few = request(files);
        few.people = vec![person("kid")];
        let library = Library::of_year(&few).unwrap();
        let people = People::load(&few, &library, &store).unwrap();
        assert_eq!(
            timelapse(&few, &library, &people, &Ranking::new(Some(&people), None)),
            None
        );
    }
}
