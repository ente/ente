use std::collections::HashMap;
use std::num::NonZeroUsize;

use super::Result;
use super::library::Library;
use super::queries::TextEmbedding;
use super::report::RewindColour;
use crate::face_clustering::dot;
use crate::ml_db::CLIP_EMBEDDING_DIMENSIONS;
use crate::ml_db::vector_encoding::decode_f32;
use crate::ml_store::MlStore;

const SCAN_PAGE: NonZeroUsize = NonZeroUsize::new(1000).unwrap();
const MATCH_SIMILARITY: f32 = 0.225;

pub(super) const COLOURS: [RewindColour; 10] = [
    RewindColour::CherryBomb,
    RewindColour::TangerinePop,
    RewindColour::LemonDrop,
    RewindColour::Pistachio,
    RewindColour::BerryBlue,
    RewindColour::LavenderFizz,
    RewindColour::Bubblegum,
    RewindColour::HotCocoa,
    RewindColour::Marshmallow,
    RewindColour::MidnightCola,
];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum Subject {
    GoldenHour,
    Pets,
    Food,
    Plants,
    Architecture,
    Indoors,
    Outdoors,
    SportsAction,
    Concerts,
    Parties,
    Festivities,
    Outfits,
    Artwork,
}

const SUBJECTS: [Subject; 13] = [
    Subject::GoldenHour,
    Subject::Pets,
    Subject::Food,
    Subject::Plants,
    Subject::Architecture,
    Subject::Indoors,
    Subject::Outdoors,
    Subject::SportsAction,
    Subject::Concerts,
    Subject::Parties,
    Subject::Festivities,
    Subject::Outfits,
    Subject::Artwork,
];

#[derive(Clone, Copy, Debug, PartialEq)]
pub(super) struct Similarities {
    pub(super) colours: [f32; COLOURS.len()],
    subjects: [f32; SUBJECTS.len()],
}

impl Similarities {
    pub(super) fn matches(&self, subject: Subject) -> bool {
        self.subject(subject) >= MATCH_SIMILARITY
    }

    pub(super) fn subject(&self, subject: Subject) -> f32 {
        self.subjects[subject as usize]
    }
}

pub(super) struct Clip {
    similarities: HashMap<i64, Similarities>,
}

impl Clip {
    pub(super) fn load(library: &Library<'_>, store: &MlStore) -> Result<Self> {
        let colour_queries = COLOURS.map(|colour| unit(colour.embedding()));
        let subject_queries = SUBJECTS.map(|subject| unit(subject.embedding()));
        let mut similarities = HashMap::new();
        let mut before_file_id = None;
        loop {
            let page = store.db().get_clip_rows_before(before_file_id, SCAN_PAGE)?;
            let Some(last_row) = page.last() else {
                break;
            };
            before_file_id = Some(last_row.file_id);
            for row in page {
                if !library
                    .get(row.file_id)
                    .is_some_and(|file| file.is_taken() && file.is_image())
                {
                    continue;
                }
                let embedding = decode_f32(&row.embedding);
                if embedding.len() != CLIP_EMBEDDING_DIMENSIONS
                    || !embedding.iter().all(|value| value.is_finite())
                {
                    continue;
                }
                similarities.insert(
                    row.file_id,
                    Similarities {
                        colours: colour_queries
                            .each_ref()
                            .map(|query| similarity(&embedding, query)),
                        subjects: subject_queries
                            .each_ref()
                            .map(|query| similarity(&embedding, query)),
                    },
                );
            }
        }
        Ok(Self { similarities })
    }

    pub(super) fn get(&self, file_id: i64) -> Option<&Similarities> {
        self.similarities.get(&file_id)
    }
}

fn unit(embedding: &TextEmbedding) -> Vec<f32> {
    let norm = embedding
        .iter()
        .map(|&value| f32::from(value).powi(2))
        .sum::<f32>()
        .sqrt();
    embedding
        .iter()
        .map(|&value| f32::from(value) / norm)
        .collect()
}

fn similarity(embedding: &[f32], query: &[f32]) -> f32 {
    dot(embedding, query) as f32
}

#[cfg(test)]
pub(super) mod tests {
    use std::collections::HashMap;

    use super::{COLOURS, Clip, SUBJECTS, Similarities, Subject, unit};
    use crate::face_clustering::dot;
    use crate::ml_db::CLIP_EMBEDDING_DIMENSIONS;
    use crate::rewind::fixtures::{add_clip, daily_photos, request, store};
    use crate::rewind::input::{RewindFileType, RewindVisibility};
    use crate::rewind::library::Library;
    use crate::rewind::report::RewindColour;

    pub(in crate::rewind) fn colour_vector(colour: RewindColour) -> Vec<f32> {
        unit(colour.embedding())
    }

    pub(in crate::rewind) fn showing(subjects: &[Subject]) -> Similarities {
        let mut similarities = Similarities {
            colours: [0.0; COLOURS.len()],
            subjects: [0.1; SUBJECTS.len()],
        };
        for &subject in subjects {
            similarities.subjects[subject as usize] = 0.3;
        }
        similarities
    }

    pub(in crate::rewind) fn clip_of(
        similarities: impl IntoIterator<Item = (i64, Similarities)>,
    ) -> Clip {
        Clip {
            similarities: similarities.into_iter().collect::<HashMap<_, _>>(),
        }
    }

    #[test]
    fn query_lists_follow_enum_order() {
        for (position, colour) in COLOURS.iter().enumerate() {
            assert_eq!(*colour as usize, position);
        }
        for (position, subject) in SUBJECTS.iter().enumerate() {
            assert_eq!(*subject as usize, position);
        }
    }

    #[test]
    fn the_scan_scores_taken_year_images_against_every_query() {
        let mut files = daily_photos(1, "2026-01-01T10:00:00", 5);
        files[1].visibility = RewindVisibility::Hidden;
        files[2].is_junk = true;
        files[3].file_type = RewindFileType::Video;
        let (_directory, store) = store();
        let food = unit(Subject::Food.embedding());
        for file in &files {
            add_clip(&store, file.id, &food);
        }
        store
            .db()
            .insert_clip_rows(&[crate::ml_db::ClipEmbedding {
                file_id: 5,
                embedding: vec![0.1; CLIP_EMBEDDING_DIMENSIONS - 1],
                version: 1,
            }])
            .unwrap();
        let clip_request = request(files);
        let library = Library::of_year(&clip_request).unwrap();

        let clip = Clip::load(&library, &store).unwrap();

        let similarities = clip.get(1).unwrap();
        assert!((similarities.subject(Subject::Food) - 1.0).abs() < 1e-3);
        let pets = unit(Subject::Pets.embedding());
        assert!((similarities.subject(Subject::Pets) - dot(&food, &pets) as f32).abs() < 1e-3);
        let red = colour_vector(RewindColour::CherryBomb);
        assert!((similarities.colours[0] - dot(&food, &red) as f32).abs() < 1e-3);
        assert!([2, 3, 4, 5].iter().all(|&id| clip.get(id).is_none()));
    }
}
