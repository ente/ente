use std::collections::hash_map::Entry;
use std::collections::{HashMap, HashSet};
use std::slice;

use ente_core::crypto::random_bytes;

use super::clustering::clusterable_embedding;
use super::fill::decode_centroid;
use super::{MlStore, Result};
use crate::face_clustering::{distance, dot, weighted_sum};

const SAMPLE_OFFSET_BYTES: usize = size_of::<u64>();

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MedianQuery {
    pub person_cluster_ids: Vec<String>,
    pub candidate_cluster_ids: Vec<String>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct MedianSuggestion {
    pub cluster_id: String,
    pub distance: f64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PersonFaces {
    pub person_id: String,
    pub face_ids: Vec<String>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct FaceDistance {
    pub face_id: String,
    pub distance: f64,
}

impl MlStore {
    pub fn suggest_clusters_by_median(
        &self,
        queries: &[MedianQuery],
        sample_size: usize,
        max_distance: f64,
        good_distance: f64,
    ) -> Result<Vec<Vec<MedianSuggestion>>> {
        let cluster_ids: HashSet<String> = queries
            .iter()
            .flat_map(|query| {
                query
                    .person_cluster_ids
                    .iter()
                    .chain(&query.candidate_cluster_ids)
            })
            .cloned()
            .collect();
        let face_ids_by_cluster = self.db.get_cluster_to_indexed_face_ids(&cluster_ids)?;
        let sample = |cluster_ids: &[String]| {
            let face_ids = cluster_ids
                .iter()
                .filter_map(|cluster_id| face_ids_by_cluster.get(cluster_id))
                .flatten()
                .collect();
            self.sample_embeddings(face_ids, sample_size)
        };
        let mut candidate_samples: HashMap<&str, Vec<Vec<f32>>> = HashMap::new();
        let mut suggestions = Vec::with_capacity(queries.len());
        for query in queries {
            let person_sample = sample(&query.person_cluster_ids)?;
            let mut closer = Vec::new();
            let mut closest = max_distance;
            for candidate_id in &query.candidate_cluster_ids {
                let candidate_sample = match candidate_samples.entry(candidate_id.as_str()) {
                    Entry::Occupied(entry) => entry.into_mut(),
                    Entry::Vacant(entry) => entry.insert(sample(slice::from_ref(candidate_id))?),
                };
                let Some(median) = median_distance(&person_sample, candidate_sample) else {
                    continue;
                };
                if median < closest {
                    closest = median;
                    closer.push(MedianSuggestion {
                        cluster_id: candidate_id.clone(),
                        distance: median,
                    });
                    if median < good_distance {
                        break;
                    }
                }
            }
            suggestions.push(closer);
        }
        Ok(suggestions)
    }

    pub fn distances_to_person_averages(
        &self,
        requests: &[PersonFaces],
    ) -> Result<Vec<Option<Vec<FaceDistance>>>> {
        let mut averages: HashMap<&str, Option<Vec<f32>>> = HashMap::new();
        let mut distances = Vec::with_capacity(requests.len());
        for request in requests {
            let average = match averages.entry(request.person_id.as_str()) {
                Entry::Occupied(entry) => entry.into_mut(),
                Entry::Vacant(entry) => entry.insert(self.person_average(&request.person_id)?),
            };
            distances.push(
                average
                    .as_deref()
                    .map(|average| self.face_distances(average, &request.face_ids))
                    .transpose()?,
            );
        }
        Ok(distances)
    }

    pub fn max_similarities_to_persons(
        &self,
        cluster_id: &str,
        person_ids: &HashSet<String>,
    ) -> Result<HashMap<String, f64>> {
        let Some(average) = self
            .cluster_centroids(&[cluster_id.to_owned()])?
            .remove(cluster_id)
        else {
            return Ok(HashMap::new());
        };
        let mut cluster_to_person = self.db.get_cluster_id_to_person_id()?;
        cluster_to_person.retain(|_, person_id| person_ids.contains(person_id));
        let cluster_ids: Vec<String> = cluster_to_person.keys().cloned().collect();
        let centroids = self.cluster_centroids(&cluster_ids)?;
        let mut similarities: HashMap<String, f64> = HashMap::new();
        for (cluster_id, person_id) in cluster_to_person {
            let Some(centroid) = centroids.get(&cluster_id) else {
                continue;
            };
            let similarity = dot(&average, centroid);
            similarities
                .entry(person_id)
                .and_modify(|best| *best = best.max(similarity))
                .or_insert(similarity);
        }
        Ok(similarities)
    }

    fn sample_embeddings(
        &self,
        face_ids: Vec<&String>,
        sample_size: usize,
    ) -> Result<Vec<Vec<f32>>> {
        let sampled: Vec<String> = random_sample(face_ids, sample_size)
            .into_iter()
            .cloned()
            .collect();
        Ok(self
            .db
            .get_face_embedding_rows_for_faces(&sampled)?
            .into_iter()
            .filter_map(|(_, embedding)| clusterable_embedding(&embedding))
            .collect())
    }

    fn person_average(&self, person_id: &str) -> Result<Option<Vec<f32>>> {
        let mut cluster_ids: Vec<String> = self
            .db
            .get_person_cluster_ids(person_id)?
            .into_iter()
            .collect();
        cluster_ids.sort_unstable();
        let summaries = self.db.get_cluster_to_cluster_summary(&cluster_ids)?;
        let centroids: Vec<(Vec<f32>, i64)> = cluster_ids
            .iter()
            .filter_map(|cluster_id| {
                let summary = summaries.get(cluster_id)?;
                Some((decode_centroid(cluster_id, &summary.avg)?, summary.count))
            })
            .collect();
        let face_count: i64 = centroids.iter().map(|(_, count)| count).sum();
        let terms: Vec<(&[f32], f64)> = centroids
            .iter()
            .map(|(centroid, count)| (centroid.as_slice(), *count as f64 / face_count as f64))
            .collect();
        Ok(weighted_sum(&terms))
    }

    fn face_distances(&self, average: &[f32], face_ids: &[String]) -> Result<Vec<FaceDistance>> {
        Ok(self
            .db
            .get_face_embedding_rows_for_faces(face_ids)?
            .into_iter()
            .filter_map(|(face_id, embedding)| {
                let embedding = clusterable_embedding(&embedding)?;
                Some(FaceDistance {
                    face_id,
                    distance: distance(average, &embedding),
                })
            })
            .collect())
    }
}

fn random_sample<T>(mut items: Vec<T>, sample_size: usize) -> Vec<T> {
    let sample_size = sample_size.min(items.len());
    let random = random_bytes(sample_size * SAMPLE_OFFSET_BYTES);
    let (offsets, _) = random.as_chunks::<SAMPLE_OFFSET_BYTES>();
    for (index, offset) in offsets.iter().enumerate() {
        let remaining = (items.len() - index) as u64;
        let chosen = index + (u64::from_le_bytes(*offset) % remaining) as usize;
        items.swap(index, chosen);
    }
    items.truncate(sample_size);
    items
}

fn median_distance(person_sample: &[Vec<f32>], candidate_sample: &[Vec<f32>]) -> Option<f64> {
    let mut distances: Vec<f64> = candidate_sample
        .iter()
        .flat_map(|candidate| {
            person_sample
                .iter()
                .map(move |person| distance(person, candidate))
        })
        .collect();
    if distances.is_empty() {
        return None;
    }
    let middle = distances.len() / 2;
    let (_, median, _) = distances.select_nth_unstable_by(middle, f64::total_cmp);
    Some(*median)
}

#[cfg(test)]
mod tests {
    use std::collections::{HashMap, HashSet};

    use super::{
        FaceDistance, MedianQuery, MedianSuggestion, PersonFaces, median_distance, random_sample,
    };
    use crate::ml_db::ClusterSummary;
    use crate::ml_db::vector_encoding::encode_evector;
    use crate::ml_store::tests::{assign, embedding, face, open, seed};
    use crate::ml_store::{CLUSTER_CENTROID_DIMENSIONS, MlStore};

    fn ids(ids: &[&str]) -> Vec<String> {
        ids.iter().map(ToString::to_string).collect()
    }

    fn query(person_cluster_ids: &[&str], candidate_cluster_ids: &[&str]) -> MedianQuery {
        MedianQuery {
            person_cluster_ids: ids(person_cluster_ids),
            candidate_cluster_ids: ids(candidate_cluster_ids),
        }
    }

    fn vectors(degrees: &[f64]) -> Vec<Vec<f32>> {
        degrees
            .iter()
            .map(|&degrees| {
                embedding(degrees)
                    .into_iter()
                    .map(|value| value as f32)
                    .collect()
            })
            .collect()
    }

    fn cosine_distance(degrees: f64) -> f64 {
        1.0 - degrees.to_radians().cos()
    }

    fn suggestions(store: &MlStore, queries: &[MedianQuery]) -> Vec<Vec<(String, f64)>> {
        store
            .suggest_clusters_by_median(queries, 50, 0.62, 0.55)
            .unwrap()
            .into_iter()
            .map(|suggestions| {
                suggestions
                    .into_iter()
                    .map(
                        |MedianSuggestion {
                             cluster_id,
                             distance,
                         }| (cluster_id, distance),
                    )
                    .collect()
            })
            .collect()
    }

    fn assert_distances(actual: &[(String, f64)], expected: &[(&str, f64)]) {
        let actual_ids: Vec<&str> = actual.iter().map(|(id, _)| id.as_str()).collect();
        let expected_ids: Vec<&str> = expected.iter().map(|&(id, _)| id).collect();
        assert_eq!(actual_ids, expected_ids);
        for ((_, actual), (_, expected)) in actual.iter().zip(expected) {
            assert!((actual - expected).abs() < 1e-5, "{actual} != {expected}");
        }
    }

    fn put_summaries(store: &MlStore, summaries: &[(&str, f64, i64)]) {
        let summaries: HashMap<String, ClusterSummary> = summaries
            .iter()
            .map(|&(cluster_id, degrees, count)| {
                let summary = ClusterSummary {
                    avg: encode_evector(&embedding(degrees)),
                    count,
                };
                (cluster_id.to_string(), summary)
            })
            .collect();
        store.cluster_summary_update(&summaries).unwrap();
    }

    fn put_unusable_summary(store: &MlStore, cluster_id: &str) {
        let summary = ClusterSummary {
            avg: encode_evector(&[f64::NAN; CLUSTER_CENTROID_DIMENSIONS]),
            count: 5,
        };
        store
            .cluster_summary_update(&HashMap::from([(cluster_id.to_string(), summary)]))
            .unwrap();
    }

    fn assign_to_person(store: &MlStore, person_id: &str, cluster_ids: &[&str]) {
        for cluster_id in cluster_ids {
            store
                .db()
                .assign_cluster_to_person(person_id, cluster_id)
                .unwrap();
        }
    }

    fn distances(store: &MlStore, requests: &[(&str, &[&str])]) -> Vec<Option<Vec<(String, f64)>>> {
        let requests: Vec<PersonFaces> = requests
            .iter()
            .map(|&(person_id, face_ids)| PersonFaces {
                person_id: person_id.to_string(),
                face_ids: ids(face_ids),
            })
            .collect();
        store
            .distances_to_person_averages(&requests)
            .unwrap()
            .into_iter()
            .map(|distances| {
                distances.map(|distances| {
                    distances
                        .into_iter()
                        .map(|FaceDistance { face_id, distance }| (face_id, distance))
                        .collect()
                })
            })
            .collect()
    }

    fn similarities(
        store: &MlStore,
        cluster_id: &str,
        person_ids: &[&str],
    ) -> HashMap<String, f64> {
        let person_ids = person_ids.iter().map(ToString::to_string).collect();
        store
            .max_similarities_to_persons(cluster_id, &person_ids)
            .unwrap()
    }

    fn assert_similarities(actual: &HashMap<String, f64>, expected: &[(&str, f64)]) {
        assert_eq!(actual.len(), expected.len());
        for (person_id, expected) in expected {
            let actual = actual[*person_id];
            assert!((actual - expected).abs() < 1e-5, "{actual} != {expected}");
        }
    }

    #[test]
    fn median_distance_is_the_upper_middle_of_all_pairwise_distances() {
        let person = vectors(&[0.0]);
        let median = median_distance(&person, &vectors(&[10.0, 60.0, 80.0])).unwrap();
        assert!((median - cosine_distance(60.0)).abs() < 1e-6);
        let median = median_distance(&person, &vectors(&[10.0, 60.0, 70.0, 80.0])).unwrap();
        assert!((median - cosine_distance(70.0)).abs() < 1e-6);
        assert_eq!(median_distance(&person, &[]), None);
        assert_eq!(median_distance(&[], &person), None);
    }

    #[test]
    fn random_samples_are_distinct_items_up_to_the_sample_size() {
        let sample = random_sample((0..100).collect(), 10);
        assert_eq!(sample.len(), 10);
        assert_eq!(sample.iter().collect::<HashSet<_>>().len(), 10);
        assert!(sample.iter().all(|item| (0..100).contains(item)));

        let mut everything = random_sample(vec![3, 1, 2], 50);
        everything.sort_unstable();
        assert_eq!(everything, vec![1, 2, 3]);
        assert!(random_sample(vec![1, 2, 3], 0).is_empty());
    }

    #[test]
    fn median_suggestions_record_each_closer_cluster_until_one_is_good_enough() {
        let (_directory, store) = open();
        seed(
            &store,
            &[
                (1, 0.0),
                (2, 0.0),
                (3, 70.0),
                (4, 66.0),
                (5, 64.0),
                (6, 65.0),
                (7, 60.0),
                (8, 0.0),
            ],
        );
        assign(
            &store,
            &[
                (1, "person_a"),
                (2, "person_b"),
                (3, "too_far"),
                (4, "close"),
                (5, "closer"),
                (6, "not_closer"),
                (7, "good"),
                (8, "after_good"),
            ],
        );

        let candidates = [
            "too_far",
            "close",
            "closer",
            "not_closer",
            "good",
            "after_good",
        ];
        assert_distances(
            &suggestions(&store, &[query(&["person_a", "person_b"], &candidates)])[0],
            &[
                ("close", cosine_distance(66.0)),
                ("closer", cosine_distance(64.0)),
                ("good", cosine_distance(60.0)),
            ],
        );
    }

    #[test]
    fn median_suggestions_answer_each_query_in_order() {
        let (_directory, store) = open();
        seed(&store, &[(1, 0.0), (2, 180.0), (3, 30.0), (4, 150.0)]);
        assign(
            &store,
            &[
                (1, "person_a"),
                (2, "person_b"),
                (3, "near_a"),
                (4, "near_b"),
            ],
        );

        let result = suggestions(
            &store,
            &[
                query(&["person_a"], &["near_b", "near_a"]),
                query(&["person_b"], &["near_a", "near_b"]),
                query(&["unknown"], &["near_a"]),
            ],
        );

        assert_eq!(result.len(), 3);
        assert_distances(&result[0], &[("near_a", cosine_distance(30.0))]);
        assert_distances(&result[1], &[("near_b", cosine_distance(30.0))]);
        assert!(result[2].is_empty());
    }

    #[test]
    fn median_suggestions_ignore_faces_without_a_valid_embedding() {
        let (_directory, store) = open();
        seed(&store, &[(1, 0.0), (2, 30.0), (3, 30.0)]);
        let mut invalid = face(4, 0.0);
        invalid.embedding[5] = f64::NAN;
        let mut short = face(5, 0.0);
        short.embedding.truncate(3);
        let mut also_invalid = face(6, 0.0);
        also_invalid.embedding[0] = f64::INFINITY;
        store
            .db()
            .bulk_insert_faces(&[invalid, short, also_invalid])
            .unwrap();
        assign(
            &store,
            &[
                (1, "person"),
                (4, "person"),
                (5, "invalid"),
                (2, "mixed"),
                (3, "mixed"),
                (6, "mixed"),
            ],
        );

        let result = suggestions(
            &store,
            &[
                query(&["person"], &["invalid", "mixed"]),
                query(&["invalid"], &["mixed"]),
            ],
        );

        assert_distances(&result[0], &[("mixed", cosine_distance(30.0))]);
        assert!(result[1].is_empty());
    }

    #[test]
    fn median_suggestions_sample_only_faces_that_are_indexed() {
        let (_directory, store) = open();
        seed(&store, &[(1, 0.0), (2, 30.0)]);
        assign(&store, &[(1, "person"), (2, "candidate")]);
        let synced_only: Vec<(i64, &str)> = (3..2003)
            .map(|file_id| (file_id, "person"))
            .chain((2003..4003).map(|file_id| (file_id, "candidate")))
            .collect();
        assign(&store, &synced_only);

        assert_distances(
            &suggestions(&store, &[query(&["person"], &["candidate"])])[0],
            &[("candidate", cosine_distance(30.0))],
        );
    }

    #[test]
    fn distances_are_measured_to_the_count_weighted_person_average() {
        let (_directory, store) = open();
        seed(&store, &[(1, 0.0), (2, 90.0)]);
        let mut invalid = face(3, 0.0);
        invalid.embedding[5] = f64::NAN;
        store.db().bulk_insert_faces(&[invalid]).unwrap();
        put_summaries(&store, &[("a", 0.0, 3), ("b", 90.0, 1)]);
        put_unusable_summary(&store, "unusable");
        assign_to_person(&store, "person", &["a", "b", "no_summary", "unusable"]);

        let result = distances(&store, &[("person", &["1_0", "2_0", "3_0", "9_0"])]);

        let expected = [("2_0", 1.0 - 0.25), ("1_0", 1.0 - 0.75)];
        assert_distances(result[0].as_ref().unwrap(), &expected);
    }

    #[test]
    fn distances_are_absent_for_persons_without_an_average() {
        let (_directory, store) = open();
        seed(&store, &[(1, 0.0)]);
        put_summaries(&store, &[("a", 0.0, 1)]);
        put_unusable_summary(&store, "unusable");
        assign_to_person(&store, "person", &["a"]);
        assign_to_person(&store, "no_summaries", &["missing"]);
        assign_to_person(&store, "unusable_summaries", &["unusable"]);

        let result = distances(
            &store,
            &[
                ("no_summaries", &["1_0"]),
                ("person", &["1_0"]),
                ("no_clusters", &["1_0"]),
                ("person", &[]),
                ("unusable_summaries", &["1_0"]),
            ],
        );

        assert_eq!(result.len(), 5);
        assert!(result[0].is_none());
        assert_distances(result[1].as_ref().unwrap(), &[("1_0", 0.0)]);
        assert!(result[2].is_none());
        assert_eq!(result[3], Some(Vec::new()));
        assert!(result[4].is_none());
    }

    #[test]
    fn similarity_is_the_closest_cluster_of_each_requested_person() {
        let (_directory, store) = open();
        put_summaries(
            &store,
            &[
                ("seed", 0.0, 1),
                ("far", 60.0, 1),
                ("near", 30.0, 1),
                ("right_angle", 90.0, 1),
                ("unrequested", 10.0, 1),
            ],
        );
        assign_to_person(&store, "closest_second", &["far", "near"]);
        assign_to_person(&store, "other", &["right_angle"]);
        assign_to_person(&store, "not_requested", &["unrequested"]);

        let result = similarities(&store, "seed", &["closest_second", "other", "no_clusters"]);

        let expected = [
            ("closest_second", 30.0_f64.to_radians().cos()),
            ("other", 0.0),
        ];
        assert_similarities(&result, &expected);
    }

    #[test]
    fn similarity_includes_the_cluster_itself_when_a_requested_person_owns_it() {
        let (_directory, store) = open();
        put_summaries(&store, &[("seed", 0.0, 1), ("other", 90.0, 1)]);
        assign_to_person(&store, "person", &["seed", "other"]);

        let result = similarities(&store, "seed", &["person"]);

        assert_similarities(&result, &[("person", 1.0)]);
    }

    #[test]
    fn similarities_are_empty_without_a_usable_average_for_the_cluster() {
        let (_directory, store) = open();
        put_summaries(&store, &[("a", 0.0, 1)]);
        put_unusable_summary(&store, "unusable");
        assign_to_person(&store, "person", &["a"]);

        assert!(similarities(&store, "missing", &["person"]).is_empty());
        assert!(similarities(&store, "unusable", &["person"]).is_empty());
    }

    #[test]
    fn similarity_skips_person_clusters_without_a_usable_average() {
        let (_directory, store) = open();
        put_summaries(&store, &[("seed", 0.0, 1), ("usable", 60.0, 1)]);
        put_unusable_summary(&store, "unusable");
        assign_to_person(&store, "person", &["no_summary", "unusable", "usable"]);
        assign_to_person(&store, "unusable_only", &["no_summary", "unusable"]);

        let result = similarities(&store, "seed", &["person", "unusable_only"]);

        assert_similarities(&result, &[("person", 0.5)]);
    }
}
