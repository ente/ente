mod complete;
mod linear;

use std::cmp::Reverse;
use std::collections::{HashMap, HashSet};
use std::iter;

use ente_core::crypto::random_bytes;

const RECOMMENDED_DISTANCE_THRESHOLD: f64 = 0.24;
const CONSERVATIVE_DISTANCE_THRESHOLD: f64 = 0.16;

const CONSERVATIVE_DISTANCE_DELTA: f64 =
    RECOMMENDED_DISTANCE_THRESHOLD - CONSERVATIVE_DISTANCE_THRESHOLD;
const COMPLETE_CLUSTERING_FACE_LIMIT: usize = 500;

const CLUSTER_ID_PREFIX: &str = "cluster_";
const CLUSTER_ID_ALPHABET: &[u8] =
    b"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
const CLUSTER_ID_LENGTH: usize = 22;
const CLUSTER_ID_MASK: u8 = 63;
const SIMD_LANES: usize = 4;

#[derive(Clone, Debug, PartialEq)]
pub struct Face {
    pub face_id: String,
    pub embedding: Vec<f32>,
    pub creation_time: Option<i64>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct IncrementalFace {
    pub face: Face,
    pub cluster_id: Option<String>,
    pub bad: bool,
    pub rejected_cluster_ids: HashSet<String>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ClusterMean {
    pub mean: Vec<f32>,
    pub count: usize,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Clustering {
    pub assignments: HashMap<String, String>,
    pub means: HashMap<String, ClusterMean>,
}

pub fn cluster_incrementally(
    faces: Vec<IncrementalFace>,
    distance_threshold: f64,
    previous_means: &HashMap<String, ClusterMean>,
) -> Clustering {
    linear::cluster(
        faces,
        linear::Thresholds::new(distance_threshold, true),
        previous_means,
    )
}

pub fn recluster(faces: Vec<Face>, distance_threshold: f64) -> Clustering {
    if faces.len() < COMPLETE_CLUSTERING_FACE_LIMIT {
        return complete::cluster(
            faces,
            conservative_threshold(distance_threshold),
            distance_threshold,
        );
    }
    let faces = faces
        .into_iter()
        .map(|face| IncrementalFace {
            face,
            cluster_id: None,
            bad: false,
            rejected_cluster_ids: HashSet::new(),
        })
        .collect();
    linear::cluster(
        faces,
        linear::Thresholds::new(distance_threshold, false),
        &HashMap::new(),
    )
}

fn conservative_threshold(distance_threshold: f64) -> f64 {
    (distance_threshold - CONSERVATIVE_DISTANCE_DELTA)
        .max(0.0)
        .min(distance_threshold)
}

fn newest_first(creation_time: Option<i64>) -> (bool, Reverse<Option<i64>>) {
    (creation_time.is_some(), Reverse(creation_time))
}

pub(crate) fn new_cluster_id() -> String {
    let suffix: String = iter::repeat_with(|| random_bytes(CLUSTER_ID_LENGTH * 2))
        .flatten()
        .filter_map(|byte| CLUSTER_ID_ALPHABET.get(usize::from(byte & CLUSTER_ID_MASK)))
        .take(CLUSTER_ID_LENGTH)
        .map(|&byte| char::from(byte))
        .collect();
    format!("{CLUSTER_ID_PREFIX}{suffix}")
}

#[cfg(any(test, not(target_arch = "wasm32")))]
pub(crate) fn normalized_mean(embeddings: &[Vec<f32>]) -> Option<Vec<f32>> {
    let (first, rest) = embeddings.split_first()?;
    let mut sum = first.clone();
    for embedding in rest {
        add_scaled(&mut sum, embedding, 1.0);
    }
    Some(normalized(scaled(sum, 1.0 / embeddings.len() as f64)))
}

pub(crate) fn weighted_sum(terms: &[(&[f32], f64)]) -> Option<Vec<f32>> {
    let (first, _) = terms.first()?;
    let mut sum = vec![0.0; first.len()];
    for &(vector, weight) in terms {
        add_scaled(&mut sum, vector, weight);
    }
    Some(sum)
}

pub(crate) fn distance(a: &[f32], b: &[f32]) -> f64 {
    1.0 - dot(a, b)
}

pub(crate) fn dot(a: &[f32], b: &[f32]) -> f64 {
    debug_assert_eq!(a.len(), b.len());
    let (a_chunks, a_rest) = a.as_chunks::<SIMD_LANES>();
    let (b_chunks, b_rest) = b.as_chunks::<SIMD_LANES>();
    let mut lanes = [0.0_f32; SIMD_LANES];
    for (a_chunk, b_chunk) in a_chunks.iter().zip(b_chunks) {
        for ((lane, x), y) in lanes.iter_mut().zip(a_chunk).zip(b_chunk) {
            *lane += x * y;
        }
    }
    for ((lane, x), y) in lanes.iter_mut().zip(a_rest).zip(b_rest) {
        *lane += x * y;
    }
    lanes.into_iter().map(f64::from).sum()
}

fn add_scaled(sum: &mut [f32], vector: &[f32], scale: f64) {
    let scale = scale as f32;
    for (total, value) in sum.iter_mut().zip(vector) {
        *total += value * scale;
    }
}

fn scaled(mut vector: Vec<f32>, scale: f64) -> Vec<f32> {
    let scale = scale as f32;
    for value in &mut vector {
        *value *= scale;
    }
    vector
}

fn normalized(vector: Vec<f32>) -> Vec<f32> {
    let norm = dot(&vector, &vector).sqrt();
    scaled(vector, 1.0 / norm)
}

fn summarize<'a>(
    members: impl IntoIterator<Item = (&'a String, &'a [f32])>,
    previous_means: &HashMap<String, ClusterMean>,
) -> HashMap<String, ClusterMean> {
    let mut sums: HashMap<&String, (Vec<f32>, usize)> = HashMap::new();
    for (cluster_id, embedding) in members {
        let (sum, count) = sums
            .entry(cluster_id)
            .or_insert_with(|| (vec![0.0; embedding.len()], 0));
        add_scaled(sum, embedding, 1.0);
        *count += 1;
    }
    sums.into_iter()
        .map(|(cluster_id, (mut sum, mut count))| {
            if let Some(previous) = previous_means.get(cluster_id) {
                add_scaled(&mut sum, &previous.mean, previous.count as f64);
                count += previous.count;
                sum = scaled(sum, 1.0 / count as f64);
            }
            (
                cluster_id.clone(),
                ClusterMean {
                    mean: normalized(sum),
                    count,
                },
            )
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use std::collections::{HashMap, HashSet};

    use super::{
        CLUSTER_ID_LENGTH, CLUSTER_ID_PREFIX, Clustering, Face, IncrementalFace, dot,
        new_cluster_id, newest_first, normalized_mean, recluster, weighted_sum,
    };

    pub(super) fn direction(degrees: f32) -> Vec<f32> {
        let radians = degrees.to_radians();
        vec![radians.cos(), radians.sin()]
    }

    pub(super) fn face(face_id: &str, degrees: f32, creation_time: i64) -> Face {
        Face {
            face_id: face_id.to_owned(),
            embedding: direction(degrees),
            creation_time: Some(creation_time),
        }
    }

    pub(super) fn new_face(face_id: &str, degrees: f32, creation_time: i64) -> IncrementalFace {
        IncrementalFace {
            face: face(face_id, degrees, creation_time),
            cluster_id: None,
            bad: false,
            rejected_cluster_ids: HashSet::new(),
        }
    }

    pub(super) fn clustered_face(
        face_id: &str,
        degrees: f32,
        creation_time: i64,
        cluster_id: &str,
    ) -> IncrementalFace {
        IncrementalFace {
            cluster_id: Some(cluster_id.to_owned()),
            ..new_face(face_id, degrees, creation_time)
        }
    }

    pub(super) fn groups(clustering: &Clustering) -> Vec<Vec<String>> {
        let mut by_cluster: HashMap<&String, Vec<String>> = HashMap::new();
        for (face_id, cluster_id) in &clustering.assignments {
            by_cluster
                .entry(cluster_id)
                .or_default()
                .push(face_id.clone());
        }
        let mut groups: Vec<Vec<String>> = by_cluster
            .into_values()
            .map(|mut faces| {
                faces.sort();
                faces
            })
            .collect();
        groups.sort();
        groups
    }

    pub(super) fn names(groups: &[&[&str]]) -> Vec<Vec<String>> {
        let mut groups: Vec<Vec<String>> = groups
            .iter()
            .map(|group| {
                let mut group: Vec<String> = group.iter().map(|name| (*name).to_owned()).collect();
                group.sort();
                group
            })
            .collect();
        groups.sort();
        groups
    }

    pub(super) fn assert_close(actual: &[f32], expected: &[f32]) {
        assert_eq!(actual.len(), expected.len());
        for (actual, expected) in actual.iter().zip(expected) {
            assert!((actual - expected).abs() < 1e-5, "{actual} != {expected}");
        }
    }

    fn chained_faces(count_before_bridge: usize, count_after_bridge: usize) -> Vec<Face> {
        let far_side = 45.57;
        let mut faces = Vec::new();
        let mut creation_time = 10_000;
        for index in 0..count_before_bridge {
            faces.push(face(&format!("a{index}"), 0.0, creation_time));
            creation_time -= 1;
        }
        faces.push(face("bridge", far_side / 2.0, creation_time));
        creation_time -= 1;
        for index in 0..count_after_bridge {
            faces.push(face(&format!("b{index}"), far_side, creation_time));
            creation_time -= 1;
        }
        faces
    }

    #[test]
    fn cluster_ids_match_the_dart_and_web_format() {
        let first = new_cluster_id();
        let second = new_cluster_id();
        assert_ne!(first, second);
        for id in [first, second] {
            let suffix = id.strip_prefix(CLUSTER_ID_PREFIX).unwrap();
            assert_eq!(suffix.len(), CLUSTER_ID_LENGTH);
            assert!(suffix.chars().all(|c| c.is_ascii_alphanumeric()));
        }
    }

    #[test]
    fn dot_covers_full_lanes_and_the_remainder() {
        let a: Vec<f32> = (0..19).map(|value| value as f32).collect();
        let b = vec![2.0; 19];
        assert_eq!(dot(&a, &b), 342.0);
    }

    #[test]
    fn dot_rounds_like_dart_float32x4_lanes_summed_as_doubles() {
        let tiny = f32::EPSILON / 4.0;
        let a = [1.0, tiny, 0.0, 0.0, tiny, 0.0, 0.0, 0.0];
        assert_eq!(dot(&a, &[1.0; 8]), 1.0 + f64::from(tiny));
    }

    #[test]
    fn normalized_mean_averages_then_scales_to_unit_length() {
        let mean = normalized_mean(&[vec![3.0, 0.0], vec![0.0, 4.0], vec![3.0, 4.0]]).unwrap();
        assert_close(&mean, &[0.6, 0.8]);
    }

    #[test]
    fn normalized_mean_of_no_embeddings_is_none() {
        assert_eq!(normalized_mean(&[]), None);
    }

    #[test]
    fn weighted_sum_adds_each_vector_scaled_by_its_weight() {
        let sum = weighted_sum(&[(&[1.0, 0.0], 0.25), (&[0.0, 2.0], 0.75)]).unwrap();
        assert_close(&sum, &[0.25, 1.5]);
    }

    #[test]
    fn weighted_sum_of_no_vectors_is_none() {
        assert_eq!(weighted_sum(&[]), None);
    }

    #[test]
    fn unknown_creation_times_sort_first_then_newest() {
        let mut times = vec![Some(1), None, Some(3), Some(2)];
        times.sort_by_key(|time| newest_first(*time));
        assert_eq!(times, vec![None, Some(3), Some(2), Some(1)]);
    }

    #[test]
    fn reclustering_below_500_faces_merges_by_cluster_mean() {
        let clustering = recluster(chained_faces(249, 249), 0.24);
        assert_eq!(groups(&clustering).len(), 2);
        assert_eq!(clustering.assignments.len(), 499);
    }

    #[test]
    fn reclustering_below_500_faces_assigns_conservatively_and_merges_at_the_threshold() {
        let clustering = recluster(
            vec![face("a", 0.0, 3), face("b", 34.0, 2), face("c", 68.0, 1)],
            0.24,
        );
        assert_eq!(groups(&clustering).len(), 2);
    }

    #[test]
    fn reclustering_from_500_faces_joins_within_the_full_threshold() {
        let faces = (0..500_i64)
            .map(|index| {
                let degrees = if index < 250 { 0.0 } else { 34.0 };
                face(&format!("f{index}"), degrees, 1000 - index)
            })
            .collect();
        assert_eq!(groups(&recluster(faces, 0.24)).len(), 1);
    }

    #[test]
    fn reclustering_from_500_faces_chains_through_nearest_faces() {
        let clustering = recluster(chained_faces(250, 249), 0.24);
        assert_eq!(groups(&clustering).len(), 1);
        assert_eq!(clustering.assignments.len(), 500);
    }
}
