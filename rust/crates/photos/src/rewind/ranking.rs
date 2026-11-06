use std::cmp::Reverse;
use std::collections::HashMap;

use super::input::RewindVisibility;
use super::library::{Library, YearFile};
use super::people::{Entity, People};
use crate::face_clustering::dot;
use crate::memories::ClipVectors;

const NEAR_DUPLICATE_MICROS: i64 = 2_000_000;
const NEAR_DUPLICATE_SIMILARITY: f64 = 0.95;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum Spread {
    Days,
    Hours,
    Months,
}

impl Spread {
    fn key(self, file: &YearFile<'_>) -> i64 {
        match self {
            Self::Days => file.day,
            Self::Hours => i64::from(file.hour),
            Self::Months => i64::from(file.month),
        }
    }
}

pub(super) struct Ranking<'a> {
    people: Option<&'a People>,
    vectors: Option<&'a dyn ClipVectors>,
}

struct Chosen {
    id: i64,
    creation_time: i64,
    vector: Option<Vec<f32>>,
}

impl Chosen {
    fn is_near(&self, file: &YearFile<'_>, vector: Option<&[f32]>) -> bool {
        (self.creation_time - file.file.creation_time).abs() <= NEAR_DUPLICATE_MICROS
            || self
                .vector
                .as_deref()
                .zip(vector)
                .is_some_and(|(first, second)| dot(first, second) >= NEAR_DUPLICATE_SIMILARITY)
    }
}

impl<'a> Ranking<'a> {
    pub(super) fn new(people: Option<&'a People>, vectors: Option<&'a dyn ClipVectors>) -> Self {
        Self { people, vectors }
    }

    pub(super) fn is_showable(&self, file: &YearFile<'_>) -> bool {
        file.is_eligible()
            && file.file.visibility == RewindVisibility::Visible
            && file.is_image()
            && !self.people.is_some_and(|people| people.hides(file.id()))
    }

    pub(super) fn by_quality<'f, 'r>(
        &self,
        files: impl IntoIterator<Item = &'f YearFile<'r>>,
    ) -> Vec<&'f YearFile<'r>> {
        let mut files: Vec<&YearFile> = files.into_iter().collect();
        files.sort_by_cached_key(|file| {
            (
                Reverse(file.file.is_favourite),
                Reverse(file.file.like_count),
                Reverse(self.named_face_count(file.id())),
                file.file.creation_time,
                file.id(),
            )
        });
        files
    }

    pub(super) fn best<'f, 'r: 'f>(
        &self,
        files: impl IntoIterator<Item = &'f YearFile<'r>>,
        spread: Spread,
        limit: usize,
    ) -> Vec<i64> {
        self.pick(self.by_quality(files), spread, limit)
    }

    pub(super) fn pick<'f, 'r: 'f>(
        &self,
        ranked: impl IntoIterator<Item = &'f YearFile<'r>>,
        spread: Spread,
        limit: usize,
    ) -> Vec<i64> {
        let (kept, junk): (Vec<&YearFile>, Vec<&YearFile>) = ranked
            .into_iter()
            .filter(|file| self.is_showable(file))
            .partition(|file| !file.file.is_junk);
        let mut groups: Vec<Vec<&YearFile>> = Vec::new();
        let mut positions: HashMap<i64, usize> = HashMap::new();
        for file in kept.into_iter().chain(junk) {
            let position = *positions.entry(spread.key(file)).or_insert_with(|| {
                groups.push(Vec::new());
                groups.len() - 1
            });
            groups[position].push(file);
        }
        let rounds = groups.iter().map(Vec::len).max().unwrap_or(0);
        let mut chosen: Vec<Chosen> = Vec::new();
        'rounds: for round in 0..rounds {
            for file in groups.iter().filter_map(|group| group.get(round)) {
                let vector = self.vector(file.id());
                if chosen
                    .iter()
                    .any(|chosen| chosen.is_near(file, vector.as_deref()))
                {
                    continue;
                }
                chosen.push(Chosen {
                    id: file.id(),
                    creation_time: file.file.creation_time,
                    vector,
                });
                if chosen.len() >= limit {
                    break 'rounds;
                }
            }
        }
        chosen.into_iter().map(|chosen| chosen.id).collect()
    }

    fn named_face_count(&self, file_id: i64) -> u32 {
        self.people
            .map_or(0, |people| people.named_face_count(file_id))
    }

    fn vector(&self, file_id: i64) -> Option<Vec<f32>> {
        let vectors = self.vectors?;
        vectors.vector(file_id).unwrap_or_else(|error| {
            log::warn!("rewind skips the clip duplicate check for file {file_id}: {error}");
            None
        })
    }
}

pub(super) fn best_faces(
    ranking: &Ranking<'_>,
    people: &People,
    entity: &Entity,
    library: &Library<'_>,
    limit: usize,
) -> Vec<String> {
    let mut faces: Vec<(&String, f64, f64)> = entity
        .face_ids
        .iter()
        .filter_map(|face_id| {
            let face = people.face(face_id)?;
            library
                .get(face.file_id)
                .filter(|file| ranking.is_showable(file))
                .map(|_| (face_id, face.score, face.blur))
        })
        .collect();
    faces.sort_by(|first, second| {
        second
            .1
            .total_cmp(&first.1)
            .then(second.2.total_cmp(&first.2))
            .then(first.0.cmp(second.0))
    });
    faces
        .into_iter()
        .take(limit)
        .map(|(face_id, _, _)| face_id.clone())
        .collect()
}

#[cfg(test)]
mod tests {
    use crate::memories::ClipVectors;
    use crate::ml_db::CLIP_EMBEDDING_DIMENSIONS;
    use crate::rewind::fixtures::{add_clip, appear, daily_photos, person, photo, request, store};
    use crate::rewind::input::{RewindFileType, RewindVisibility};
    use crate::rewind::library::Library;
    use crate::rewind::people::People;

    use super::{Ranking, Spread};

    fn axis(position: usize) -> Vec<f32> {
        let mut vector = vec![0.0; CLIP_EMBEDDING_DIMENSIONS];
        vector[position] = 1.0;
        vector
    }

    #[test]
    fn candidates_are_showable_spread_over_days_with_junk_last_and_no_bursts() {
        let mut files = daily_photos(1, "2026-03-01T10:00:00", 4);
        files.push(photo(5, "2026-03-01T10:00:01"));
        files.push(photo(6, "2026-03-01T11:00:00"));
        files.push(photo(7, "2026-03-02T11:00:00"));
        files[0].is_junk = true;
        files[1].visibility = RewindVisibility::Archived;
        files[2].file_type = RewindFileType::Video;
        let mut hidden = photo(8, "2026-03-05T10:00:00");
        hidden.visibility = RewindVisibility::Hidden;
        files.push(hidden);
        let mut favourite = photo(9, "2026-03-04T12:00:00");
        favourite.is_favourite = true;
        files.push(favourite);
        let ranking_request = request(files);
        let library = Library::of_year(&ranking_request).unwrap();
        let ranking = Ranking::new(None, None);

        let ranked = ranking.best(library.files(), Spread::Days, 10);

        assert_eq!(ranked, [9, 5, 7, 4, 6]);
        assert_eq!(ranking.best(library.files(), Spread::Days, 2), [9, 5]);
    }

    #[test]
    fn photos_with_people_hidden_from_memories_and_clip_duplicates_are_never_picked() {
        let (_directory, store) = store();
        let files = daily_photos(1, "2026-03-01T10:00:00", 4);
        let mut ranking_request = request(files);
        ranking_request.people = vec![person("secret")];
        ranking_request.people[0].is_hidden_from_memories = true;
        appear(&store, "secret", Some("secret"), [2]);
        add_clip(&store, 1, &axis(0));
        add_clip(&store, 3, &axis(0));
        add_clip(&store, 4, &axis(1));
        store.fill_clip_index(false).unwrap();
        let library = Library::of_year(&ranking_request).unwrap();
        let people = People::load(&ranking_request, &library, &store).unwrap();
        let vectors: &dyn ClipVectors = &store;

        let ranked =
            Ranking::new(Some(&people), Some(vectors)).best(library.files(), Spread::Days, 10);

        assert_eq!(ranked, [1, 4]);
    }
}
