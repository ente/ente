use std::cmp::Reverse;

use super::percent;
use crate::rewind::clip::{COLOURS, Clip};
use crate::rewind::library::{Library, YearFile};
use crate::rewind::ranking::{Ranking, Spread};
use crate::rewind::report::ColourOfTheYear;

const COLOUR_MINIMUM_CLASSIFIED: usize = 50;
const COLOUR_MINIMUM_CANDIDATES: usize = 9;
const COLOUR_CANDIDATES: usize = 18;
const MINIMUM_DEVIATION: f32 = 1e-6;

type Scores = [f32; COLOURS.len()];

pub(in crate::rewind) fn colour(
    library: &Library<'_>,
    clip: &Clip,
    ranking: &Ranking<'_>,
) -> Option<ColourOfTheYear> {
    let classified: Vec<(&YearFile, Scores)> = library
        .taken()
        .filter(|file| file.is_image())
        .filter_map(|file| Some((file, clip.get(file.id())?.colours)))
        .collect();
    if classified.len() < COLOUR_MINIMUM_CLASSIFIED {
        return None;
    }
    let standardized = standardize(classified.iter().map(|(_, scores)| *scores).collect());
    let best: Vec<usize> = standardized.iter().map(best_colour).collect();
    let mut wins = [0usize; COLOURS.len()];
    for &colour in &best {
        wins[colour] += 1;
    }
    let winner = (0..COLOURS.len()).max_by_key(|&colour| (wins[colour], Reverse(colour)))?;
    let mut candidates: Vec<(&YearFile, f32)> = classified
        .iter()
        .zip(&standardized)
        .zip(&best)
        .filter(|&(_, &colour)| colour == winner)
        .map(|(((file, _), scores), _)| (*file, scores[winner]))
        .collect();
    candidates.sort_by(|first, second| {
        second
            .1
            .total_cmp(&first.1)
            .then(first.0.id().cmp(&second.0.id()))
    });
    let file_ids = ranking.pick(
        candidates.into_iter().map(|(file, _)| file),
        Spread::Days,
        COLOUR_CANDIDATES,
    );
    (file_ids.len() >= COLOUR_MINIMUM_CANDIDATES).then(|| ColourOfTheYear {
        colour: COLOURS[winner],
        percent: percent(wins[winner], classified.len()),
        file_ids,
    })
}

fn standardize(mut scores: Vec<Scores>) -> Vec<Scores> {
    let count = scores.len() as f32;
    for colour in 0..COLOURS.len() {
        let mean = scores.iter().map(|scores| scores[colour]).sum::<f32>() / count;
        let variance = scores
            .iter()
            .map(|scores| (scores[colour] - mean).powi(2))
            .sum::<f32>()
            / count;
        let deviation = variance.sqrt();
        for scores in &mut scores {
            scores[colour] = if deviation > MINIMUM_DEVIATION {
                (scores[colour] - mean) / deviation
            } else {
                0.0
            };
        }
    }
    scores
}

fn best_colour(scores: &Scores) -> usize {
    (0..COLOURS.len())
        .reduce(|best, colour| {
            if scores[colour] > scores[best] {
                colour
            } else {
                best
            }
        })
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use crate::rewind::clip::Clip;
    use crate::rewind::clip::tests::colour_vector;
    use crate::rewind::fixtures::{add_clip, daily_photos, request, store};
    use crate::rewind::input::{RewindFileType, RewindVisibility};
    use crate::rewind::library::Library;
    use crate::rewind::ranking::Ranking;
    use crate::rewind::report::{ColourOfTheYear, RewindColour};

    use super::{COLOURS, best_colour, colour, standardize};

    fn direction(colour: RewindColour) -> Vec<f32> {
        let vectors: Vec<Vec<f32>> = COLOURS
            .iter()
            .map(|&colour| colour_vector(colour))
            .collect();
        let own = colour_vector(colour);
        let direction: Vec<f32> = (0..own.len())
            .map(|position| {
                own[position]
                    - vectors.iter().map(|vector| vector[position]).sum::<f32>()
                        / vectors.len() as f32
            })
            .collect();
        let norm = direction
            .iter()
            .map(|value| value * value)
            .sum::<f32>()
            .sqrt();
        direction.into_iter().map(|value| value / norm).collect()
    }

    #[test]
    fn the_colour_most_photos_show_wins_with_its_share_of_classified_photos() {
        let (_directory, store) = store();
        let mut files = daily_photos(1, "2026-01-01T10:00:00", 70);
        files[60].visibility = RewindVisibility::Hidden;
        files[61].file_type = RewindFileType::Video;
        for file in &mut files[62..] {
            file.is_junk = true;
        }
        let [red, blue, green] = [
            RewindColour::CherryBomb,
            RewindColour::BerryBlue,
            RewindColour::Pistachio,
        ]
        .map(direction);
        for file in &files {
            let vector = match file.id {
                31..=50 => &blue,
                51..=60 => &green,
                _ => &red,
            };
            add_clip(&store, file.id, vector);
        }
        let colour_request = request(files);
        let library = Library::of_year(&colour_request).unwrap();
        let clip = Clip::load(&library, &store).unwrap();

        assert_eq!(
            colour(&library, &clip, &Ranking::new(None, None)),
            Some(ColourOfTheYear {
                colour: RewindColour::CherryBomb,
                percent: 50,
                file_ids: (1..=18).collect(),
            })
        );

        let mut sparse = colour_request.clone();
        sparse.files.truncate(49);
        let library = Library::of_year(&sparse).unwrap();
        let clip = Clip::load(&library, &store).unwrap();
        assert_eq!(colour(&library, &clip, &Ranking::new(None, None)), None);
    }

    #[test]
    fn a_colour_every_photo_leans_towards_does_not_win_everywhere() {
        let mut scores = Vec::new();
        for photo in 0..100 {
            let mut photo_scores = [0.20; 10];
            photo_scores[8] = if photo % 2 == 0 { 0.261 } else { 0.260 };
            if photo < 40 {
                photo_scores[0] = 0.25;
            }
            scores.push(photo_scores);
        }
        assert!(scores.iter().all(|scores| best_colour(scores) == 8));

        let best: Vec<usize> = standardize(scores).iter().map(best_colour).collect();

        assert_eq!(best.iter().filter(|&&colour| colour == 0).count(), 40);
    }

    #[test]
    fn ties_go_to_the_first_colour() {
        assert_eq!(best_colour(&[0.0; 10]), 0);
        let mut scores = [0.0; 10];
        scores[3] = 1.0;
        scores[7] = 1.0;
        assert_eq!(best_colour(&scores), 3);
    }
}
