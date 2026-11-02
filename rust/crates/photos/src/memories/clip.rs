use std::collections::HashMap;

use super::UPDATE_FREQUENCY_DAYS;
use super::calendar::MICROS_PER_DAY;
use super::input::{MemoriesRequest, Period};
use super::output::{ClipMemoryType, Memory, MemoryKind};
use super::photo::Photo;
use super::selector::Selector;
use super::signals::Signals;
use crate::ml_store::Result;

const MATCH_SIMILARITY: f32 = 0.225;
const MINIMUM_MATCHES: usize = 10;
const SHOW_TIMEOUT_DAYS: i64 = 10 * UPDATE_FREQUENCY_DAYS;

pub(super) fn memories(
    photos: &[Photo],
    period: Period,
    request: &MemoriesRequest,
    signals: &Signals,
    selector: &mut Selector,
) -> Result<Vec<Memory>> {
    let photos_by_id: HashMap<i64, &Photo> = photos.iter().map(|photo| (photo.id, photo)).collect();
    if request.surface_all {
        let mut memories = Vec::new();
        for kind in ClipMemoryType::ALL {
            memories.extend(memory(kind, &photos_by_id, period, signals, selector)?);
        }
        return Ok(memories);
    }
    let mut kinds = ClipMemoryType::ALL;
    selector.shuffle(&mut kinds);
    for kind in kinds {
        if was_shown_recently(kind, request, period) {
            continue;
        }
        if let Some(memory) = memory(kind, &photos_by_id, period, signals, selector)? {
            return Ok(vec![memory]);
        }
    }
    Ok(Vec::new())
}

fn was_shown_recently(kind: ClipMemoryType, request: &MemoriesRequest, period: Period) -> bool {
    let cutoff = period.now - SHOW_TIMEOUT_DAYS * MICROS_PER_DAY;
    request
        .shown_clip_memories
        .iter()
        .any(|shown| shown.kind == kind && shown.last_time_shown > cutoff)
}

fn memory(
    kind: ClipMemoryType,
    photos_by_id: &HashMap<i64, &Photo>,
    period: Period,
    signals: &Signals,
    selector: &mut Selector,
) -> Result<Option<Memory>> {
    let matches: Vec<(&Photo, f32)> = signals
        .matches(kind.embedding(), MATCH_SIMILARITY)?
        .into_iter()
        .filter(|&(_, similarity)| similarity > MATCH_SIMILARITY)
        .filter_map(|(file_id, similarity)| Some((*photos_by_id.get(&file_id)?, similarity)))
        .collect();
    if matches.len() < MINIMUM_MATCHES {
        return Ok(None);
    }
    Ok(Some(Memory::new(
        MemoryKind::Clip(kind),
        &selector.best_matches(matches)?,
        period.now,
        period.now + UPDATE_FREQUENCY_DAYS * MICROS_PER_DAY,
    )))
}

#[cfg(test)]
mod tests {
    use std::collections::{HashMap, HashSet};

    use crate::memories::calendar::MICROS_PER_DAY;
    use crate::memories::tests::{files_on, micros, period};
    use crate::memories::{
        ClipMemoryType, ClipVectors, MemoriesRequest, Memory, MemoryKind, MlInputs, PeopleInputs,
        ShownClipMemory, compute_smart_memories,
    };
    use crate::ml_store::Result;

    const NOW: &str = "2026-10-30T09:00:00";

    #[derive(Default)]
    struct Clip {
        matches: HashMap<ClipMemoryType, Vec<(i64, f32)>>,
        vectors: HashMap<i64, Vec<f32>>,
    }

    impl ClipVectors for Clip {
        fn matches(&self, query: &[f32], min_similarity: f32) -> Result<Vec<(i64, f32)>> {
            let kind = ClipMemoryType::ALL.into_iter().find(|kind| {
                kind.embedding()
                    .iter()
                    .copied()
                    .map(f32::from)
                    .eq(query.iter().copied())
            });
            Ok(kind
                .and_then(|kind| self.matches.get(&kind))
                .into_iter()
                .flatten()
                .copied()
                .filter(|&(_, similarity)| similarity >= min_similarity)
                .collect())
        }

        fn vector(&self, file_id: i64) -> Result<Option<Vec<f32>>> {
            Ok(self.vectors.get(&file_id).cloned())
        }
    }

    fn scored(first_id: i64, count: i64, similarity: f32) -> Vec<(i64, f32)> {
        (0..count)
            .map(|index| (first_id + index, similarity + index as f32 / 1000.0))
            .collect()
    }

    fn request() -> MemoriesRequest {
        let mut files = files_on(1, "2025-05-01", 20);
        files.extend(files_on(21, "2025-06-01", 20));
        files.extend(files_on(41, "2025-07-01", 20));
        MemoriesRequest {
            files,
            ..MemoriesRequest::default()
        }
    }

    fn clip_memories(clip: &Clip, request: &MemoriesRequest) -> Vec<(ClipMemoryType, Memory)> {
        let ml = MlInputs {
            clip,
            face_weights: HashMap::new(),
            people: PeopleInputs::default(),
        };
        compute_smart_memories(request, &[period(NOW)], Some(&ml), None)
            .unwrap()
            .periods
            .remove(0)
            .into_iter()
            .filter_map(|memory| match memory.kind {
                MemoryKind::Clip(kind) => Some((kind, memory)),
                _ => None,
            })
            .collect()
    }

    fn shown(kind: ClipMemoryType, days_ago: i64) -> ShownClipMemory {
        ShownClipMemory {
            kind,
            last_time_shown: micros(NOW) - days_ago * MICROS_PER_DAY,
        }
    }

    fn library() -> Clip {
        Clip {
            matches: HashMap::from([
                (ClipMemoryType::Beach, scored(1, 12, 0.3)),
                (ClipMemoryType::Food, scored(21, 15, 0.3)),
                (ClipMemoryType::Moon, scored(41, 9, 0.3)),
                (
                    ClipMemoryType::Mountains,
                    scored(41, 20, 0.225)[1..].to_vec(),
                ),
                (ClipMemoryType::City, vec![(41, 0.225); 12]),
            ]),
            ..Clip::default()
        }
    }

    #[test]
    fn each_period_shows_one_type_with_ten_strong_matches_that_is_not_cooling_down() {
        let clip = library();
        let kinds_over_seeds = |request: &MemoriesRequest| {
            (0..20)
                .flat_map(|seed| {
                    let request = MemoriesRequest {
                        seed,
                        ..request.clone()
                    };
                    clip_memories(&clip, &request)
                        .into_iter()
                        .map(|(kind, _)| kind)
                })
                .collect::<HashSet<_>>()
        };

        let mut request = request();
        request.shown_clip_memories = vec![shown(ClipMemoryType::Food, 31)];
        assert_eq!(
            kinds_over_seeds(&request),
            HashSet::from([
                ClipMemoryType::Beach,
                ClipMemoryType::Food,
                ClipMemoryType::Mountains,
            ])
        );

        request.shown_clip_memories = vec![
            shown(ClipMemoryType::Food, 29),
            shown(ClipMemoryType::Mountains, -1),
        ];
        let memories = clip_memories(&clip, &request);
        assert_eq!(memories.len(), 1);
        let (kind, memory) = &memories[0];
        assert_eq!(*kind, ClipMemoryType::Beach);
        assert_eq!(memory.file_ids.len(), 10);
        assert!(memory.file_ids.is_sorted_by(|a, b| a > b));
        assert_eq!(
            (memory.first_date_to_show, memory.last_date_to_show),
            (micros(NOW), micros(NOW) + 3 * MICROS_PER_DAY)
        );
    }

    #[test]
    fn surfacing_everything_lists_every_type_with_enough_matches_in_type_order() {
        let request = MemoriesRequest {
            surface_all: true,
            shown_clip_memories: vec![shown(ClipMemoryType::Food, 1)],
            ..request()
        };

        let kinds: Vec<ClipMemoryType> = clip_memories(&library(), &request)
            .into_iter()
            .map(|(kind, _)| kind)
            .collect();

        assert_eq!(
            kinds,
            [
                ClipMemoryType::Mountains,
                ClipMemoryType::Beach,
                ClipMemoryType::Food,
            ]
        );
    }

    #[test]
    fn picks_skip_photos_taken_within_ten_minutes_and_near_duplicates() {
        let mut request = request();
        request.files[2].creation_time = request.files[1].creation_time + 60_000_000;
        request.files[3].creation_time = request.files[1].creation_time + 120_000_000;
        let one_hot = |hot: usize| {
            let mut vector = vec![0.0; 32];
            vector[hot] = 1.0;
            vector
        };
        let mut vectors: HashMap<i64, Vec<f32>> =
            (1..=20).map(|id| (id, one_hot(id as usize))).collect();
        vectors.insert(6, one_hot(5));
        let clip = Clip {
            matches: HashMap::from([(ClipMemoryType::Beach, scored(1, 20, 0.3))]),
            vectors,
        };

        for seed in 0..20 {
            let request = MemoriesRequest {
                seed,
                ..request.clone()
            };
            let ids: HashSet<i64> = clip_memories(&clip, &request)[0]
                .1
                .file_ids
                .iter()
                .copied()
                .collect();
            assert_eq!(ids.len(), 10);
            assert!(ids.iter().filter(|id| (2..=4).contains(*id)).count() <= 1);
            assert!(!(ids.contains(&5) && ids.contains(&6)));
        }
    }
}
