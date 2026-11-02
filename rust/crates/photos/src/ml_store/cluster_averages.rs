use std::cmp::Reverse;
use std::collections::{HashMap, HashSet};

use super::clustering::{clusterable_embedding, is_clusterable, summaries};
use super::fill::decode_centroid;
use super::{Error, Index, Match, MlStore, Result, SearchParams};
use crate::face_clustering::{ClusterMean, distance, normalized_mean_from_sum};

const MAX_CLUSTERS_PER_REFRESH: usize = 500;
const MAX_EMBEDDINGS_PER_REFRESH: i64 = 10_000;
const MAX_MEAN_SUGGESTIONS: usize = 20;
const SUMMARY_READ_BATCH_SIZE: usize = 500;

#[derive(Clone, Debug, PartialEq)]
pub struct MeanSuggestion {
    pub cluster_id: String,
    pub distance: f64,
    pub person_cluster_id: String,
}

#[derive(Default)]
struct ClusterAverage {
    sum: Vec<f32>,
    valid_count: usize,
    count: usize,
}

impl ClusterAverage {
    fn add(&mut self, embedding: &[u8]) {
        self.count += 1;
        let Some(embedding) = clusterable_embedding(embedding) else {
            return;
        };
        if self.valid_count == 0 {
            self.sum = embedding;
        } else {
            for (sum, value) in self.sum.iter_mut().zip(embedding) {
                *sum += value;
            }
        }
        self.valid_count += 1;
    }

    fn into_mean(self) -> Option<ClusterMean> {
        if self.valid_count == 0 {
            return None;
        }
        let mean = normalized_mean_from_sum(self.sum, self.valid_count);
        is_clusterable(&mean).then_some(ClusterMean {
            mean,
            count: self.count,
        })
    }
}

impl MlStore {
    pub fn refresh_cluster_averages(
        &self,
        cluster_face_counts: &HashMap<String, i64>,
        ignored_cluster_ids: &HashSet<String>,
        min_cluster_size: i64,
    ) -> Result<HashSet<String>> {
        let mut averaged = HashSet::new();
        let mut stale = Vec::new();
        let cluster_ids: Vec<String> = cluster_face_counts
            .iter()
            .filter(|&(_, &face_count)| face_count >= min_cluster_size)
            .map(|(cluster_id, _)| cluster_id.clone())
            .collect();
        for chunk in cluster_ids.chunks(SUMMARY_READ_BATCH_SIZE) {
            let summaries = self.db.get_cluster_to_cluster_summary(chunk)?;
            for cluster_id in chunk {
                let face_count = cluster_face_counts[cluster_id];
                let current = summaries.get(cluster_id).is_some_and(|summary| {
                    summary.count == face_count
                        && decode_centroid(cluster_id, &summary.avg).is_some()
                });
                if current {
                    averaged.insert(cluster_id.clone());
                } else if !ignored_cluster_ids.contains(cluster_id) {
                    stale.push((cluster_id.clone(), face_count));
                }
            }
        }
        let means = self.average_clusters(&largest_within_budget(stale))?;
        match self.cluster_summary_update(&summaries(&means)) {
            Ok(()) => {}
            Err(Error::Index(error)) => {
                log::warn!(
                    "cluster centroid index write failed while refreshing cluster averages: {error}"
                );
            }
            Err(error) => return Err(error),
        }
        averaged.extend(means.into_keys());
        Ok(averaged)
    }

    pub fn search_cluster_centroids(
        &self,
        cluster_ids: &[String],
        allowed_cluster_ids: Vec<String>,
        limit: usize,
        max_distance: f32,
    ) -> Result<Vec<Vec<Match>>> {
        let centroids = self.cluster_centroids(cluster_ids)?;
        let queries: Vec<Vec<f32>> = cluster_ids
            .iter()
            .filter_map(|cluster_id| centroids.get(cluster_id).cloned())
            .collect();
        let params = SearchParams {
            limit: Some(limit),
            max_distance: Some(max_distance),
            exact: false,
            allowed_keys: Some(allowed_cluster_ids),
        };
        let mut matches = self
            .bulk_search(Index::ClusterCentroid, &queries, &params)?
            .into_iter();
        Ok(cluster_ids
            .iter()
            .map(|cluster_id| {
                if centroids.contains_key(cluster_id) {
                    matches.next().unwrap_or_default()
                } else {
                    Vec::new()
                }
            })
            .collect())
    }

    pub fn suggest_clusters_by_mean(
        &self,
        person_cluster_ids: &[String],
        candidate_cluster_ids: &[String],
        max_distance: f64,
        ignored_by_person_cluster: &HashMap<String, HashSet<String>>,
    ) -> Result<Vec<MeanSuggestion>> {
        let centroids = self.cluster_centroids(person_cluster_ids)?;
        let person_centroids: Vec<(&String, &Vec<f32>)> = person_cluster_ids
            .iter()
            .filter_map(|cluster_id| Some((cluster_id, centroids.get(cluster_id)?)))
            .collect();
        let mut suggestions: Vec<MeanSuggestion> = Vec::new();
        for chunk in candidate_cluster_ids.chunks(SUMMARY_READ_BATCH_SIZE) {
            let candidates = self.cluster_centroids(chunk)?;
            for candidate_id in chunk {
                let Some(candidate) = candidates.get(candidate_id) else {
                    continue;
                };
                let mut nearest: Option<(&String, f64)> = None;
                for &(person_cluster_id, person_centroid) in &person_centroids {
                    if ignored_by_person_cluster
                        .get(person_cluster_id)
                        .is_some_and(|ignored| ignored.contains(candidate_id))
                    {
                        continue;
                    }
                    let distance = distance(person_centroid, candidate);
                    if distance < max_distance && nearest.is_none_or(|(_, best)| distance < best) {
                        nearest = Some((person_cluster_id, distance));
                    }
                }
                if let Some((person_cluster_id, distance)) = nearest {
                    let position = suggestions.partition_point(|suggestion| {
                        suggestion.distance.total_cmp(&distance).is_le()
                    });
                    if position < MAX_MEAN_SUGGESTIONS {
                        suggestions.insert(
                            position,
                            MeanSuggestion {
                                cluster_id: candidate_id.clone(),
                                distance,
                                person_cluster_id: person_cluster_id.clone(),
                            },
                        );
                        suggestions.truncate(MAX_MEAN_SUGGESTIONS);
                    }
                }
            }
        }
        Ok(suggestions)
    }

    fn average_clusters(&self, cluster_ids: &[String]) -> Result<HashMap<String, ClusterMean>> {
        let mut averages: HashMap<String, ClusterAverage> = HashMap::new();
        self.db
            .for_each_face_embedding_for_clusters(cluster_ids, |cluster_id, embedding| {
                averages.entry(cluster_id).or_default().add(&embedding);
            })?;
        Ok(averages
            .into_iter()
            .filter_map(|(cluster_id, average)| Some((cluster_id, average.into_mean()?)))
            .collect())
    }

    pub(super) fn cluster_centroids(
        &self,
        cluster_ids: &[String],
    ) -> Result<HashMap<String, Vec<f32>>> {
        Ok(self
            .db
            .get_cluster_to_cluster_summary(cluster_ids)?
            .into_iter()
            .filter_map(|(cluster_id, summary)| {
                let centroid = decode_centroid(&cluster_id, &summary.avg)?;
                Some((cluster_id, centroid))
            })
            .collect())
    }
}

fn largest_within_budget(mut stale: Vec<(String, i64)>) -> Vec<String> {
    stale.sort_by_key(|&(_, face_count)| Reverse(face_count));
    let mut selected = Vec::new();
    let mut embeddings = 0;
    for (cluster_id, face_count) in stale.into_iter().take(MAX_CLUSTERS_PER_REFRESH) {
        if !selected.is_empty() && embeddings + face_count >= MAX_EMBEDDINGS_PER_REFRESH {
            break;
        }
        embeddings += face_count;
        selected.push(cluster_id);
    }
    selected
}

#[cfg(test)]
mod tests {
    use std::collections::{HashMap, HashSet};
    use std::fs;

    use super::{MeanSuggestion, largest_within_budget};
    use crate::ml_db::ClusterSummary;
    use crate::ml_db::vector_encoding::encode_evector;
    use crate::ml_store::tests::{
        assert_direction, assign, embedding, face, index_path, meta, open, seed, summary_of,
    };
    use crate::ml_store::{CLUSTER_CENTROID_DIMENSIONS, Index, MlStore};

    fn summary(degrees: f64, count: i64) -> ClusterSummary {
        ClusterSummary {
            avg: encode_evector(&embedding(degrees)),
            count,
        }
    }

    fn put_summaries(store: &MlStore, summaries: &[(&str, f64)]) {
        let summaries: HashMap<String, ClusterSummary> = summaries
            .iter()
            .map(|&(cluster_id, degrees)| (cluster_id.to_string(), summary(degrees, 1)))
            .collect();
        store.cluster_summary_update(&summaries).unwrap();
    }

    fn ids(cluster_ids: &[&str]) -> Vec<String> {
        cluster_ids.iter().map(ToString::to_string).collect()
    }

    fn id_set(cluster_ids: &[&str]) -> HashSet<String> {
        cluster_ids.iter().map(ToString::to_string).collect()
    }

    fn refresh(store: &MlStore, ignored: &[&str], min_cluster_size: i64) -> HashSet<String> {
        let face_counts = store.db().cluster_id_to_face_count().unwrap();
        store
            .refresh_cluster_averages(&face_counts, &id_set(ignored), min_cluster_size)
            .unwrap()
    }

    #[test]
    fn refreshing_recomputes_stale_averages_and_keeps_current_ones() {
        let (_directory, store) = open();
        store.fill_cluster_centroid_index(false).unwrap();
        seed(&store, &[(1, 0.0), (2, 90.0), (3, 0.0)]);
        assign(&store, &[(1, "stale"), (2, "stale"), (3, "current")]);
        store
            .cluster_summary_update(&HashMap::from([
                ("stale".to_string(), summary(0.0, 1)),
                ("current".to_string(), summary(45.0, 1)),
            ]))
            .unwrap();

        assert_eq!(refresh(&store, &[], 1), id_set(&["stale", "current"]));

        let (mean, count) = summary_of(&store, "stale");
        assert_eq!(count, 2);
        assert_direction(&mean, 45.0);
        let (mean, count) = summary_of(&store, "current");
        assert_eq!(count, 1);
        assert_direction(&mean, 45.0);
        let indexed = store
            .get_vector(Index::ClusterCentroid, "stale")
            .unwrap()
            .unwrap();
        assert!(indexed[0] > 0.7 && indexed[1] > 0.7);
    }

    #[test]
    fn refreshing_skips_ignored_and_small_stale_clusters_but_returns_their_current_averages() {
        let (_directory, store) = open();
        seed(
            &store,
            &[
                (1, 0.0),
                (2, 0.0),
                (3, 0.0),
                (4, 0.0),
                (5, 0.0),
                (6, 0.0),
                (7, 0.0),
            ],
        );
        assign(
            &store,
            &[
                (1, "ignored_current"),
                (2, "ignored_current"),
                (3, "ignored_stale"),
                (4, "ignored_stale"),
                (5, "small"),
                (6, "large"),
                (7, "large"),
            ],
        );
        store
            .cluster_summary_update(&HashMap::from([(
                "ignored_current".to_string(),
                summary(0.0, 2),
            )]))
            .unwrap();

        assert_eq!(
            refresh(&store, &["ignored_current", "ignored_stale"], 2),
            id_set(&["ignored_current", "large"])
        );
        let refreshed = store
            .db()
            .get_cluster_to_cluster_summary(&ids(&["ignored_stale", "small", "large"]))
            .unwrap();
        assert_eq!(refreshed.keys().collect::<Vec<_>>(), ["large"]);
    }

    #[test]
    fn refreshing_excludes_current_small_clusters_and_recomputes_eligible_stale_counts() {
        let (_directory, store) = open();
        seed(&store, &[(1, 0.0), (2, 0.0), (3, 90.0)]);
        assign(&store, &[(1, "small"), (2, "stale"), (3, "stale")]);
        store
            .cluster_summary_update(&HashMap::from([
                ("small".to_owned(), summary(30.0, 1)),
                ("stale".to_owned(), summary(0.0, 1)),
            ]))
            .unwrap();

        assert_eq!(refresh(&store, &[], 2), id_set(&["stale"]));

        let (mean, count) = summary_of(&store, "small");
        assert_eq!(count, 1);
        assert_direction(&mean, 30.0);
        let (mean, count) = summary_of(&store, "stale");
        assert_eq!(count, 2);
        assert_direction(&mean, 45.0);
    }

    #[test]
    fn refreshing_averages_only_valid_embeddings() {
        let (_directory, store) = open();
        store.fill_cluster_centroid_index(false).unwrap();
        seed(&store, &[(1, 0.0), (2, 90.0), (5, 30.0)]);
        let mut invalid = face(3, 0.0);
        invalid.embedding[5] = f64::NAN;
        let mut short = face(4, 0.0);
        short.embedding.truncate(3);
        store.db().bulk_insert_faces(&[invalid, short]).unwrap();
        assign(
            &store,
            &[
                (1, "mixed"),
                (2, "mixed"),
                (3, "mixed"),
                (4, "invalid"),
                (5, "corrupt"),
            ],
        );
        store
            .cluster_summary_update(&HashMap::from([(
                "corrupt".to_string(),
                ClusterSummary {
                    avg: encode_evector(&[f64::NAN; CLUSTER_CENTROID_DIMENSIONS]),
                    count: 1,
                },
            )]))
            .unwrap();

        assert_eq!(refresh(&store, &[], 1), id_set(&["mixed", "corrupt"]));

        let (mean, count) = summary_of(&store, "mixed");
        assert_eq!(count, 3);
        assert_direction(&mean, 45.0);
        let (mean, _) = summary_of(&store, "corrupt");
        assert_direction(&mean, 30.0);
        assert!(
            store
                .db()
                .get_cluster_to_cluster_summary(&ids(&["invalid"]))
                .unwrap()
                .is_empty()
        );
        assert!(!store.contains(Index::ClusterCentroid, "invalid").unwrap());
        assert_eq!(refresh(&store, &[], 1), id_set(&["mixed", "corrupt"]));
    }

    #[test]
    fn refreshing_considers_only_the_callers_clusters() {
        let (_directory, store) = open();
        seed(&store, &[(1, 0.0), (2, 90.0), (3, 0.0)]);
        assign(&store, &[(1, "known")]);
        let face_counts = store.db().cluster_id_to_face_count().unwrap();
        assign(&store, &[(2, "new_stale"), (3, "new_current")]);
        store
            .cluster_summary_update(&HashMap::from([(
                "new_current".to_string(),
                summary(0.0, 1),
            )]))
            .unwrap();

        let averaged = store
            .refresh_cluster_averages(&face_counts, &HashSet::new(), 1)
            .unwrap();

        assert_eq!(averaged, id_set(&["known"]));
        assert!(
            store
                .db()
                .get_cluster_to_cluster_summary(&ids(&["new_stale"]))
                .unwrap()
                .is_empty()
        );
    }

    #[test]
    fn largest_stale_clusters_are_refreshed_first_within_the_embedding_budget() {
        let stale = |clusters: &[(&str, i64)]| -> Vec<(String, i64)> {
            clusters
                .iter()
                .map(|&(cluster_id, count)| (cluster_id.to_string(), count))
                .collect()
        };
        assert_eq!(
            largest_within_budget(stale(&[("a", 20), ("b", 9_000), ("c", 1), ("d", 990)])),
            ids(&["b", "d"])
        );
        assert_eq!(
            largest_within_budget(stale(&[("a", 5), ("b", 12_000), ("c", 1)])),
            ids(&["b"])
        );
        let singletons: Vec<(String, i64)> = (0..600).map(|i| (format!("c{i}"), 1)).collect();
        assert_eq!(largest_within_budget(singletons).len(), 500);
    }

    #[test]
    fn refreshing_keeps_the_averages_when_the_centroid_write_fails() {
        let (directory, store) = open();
        fs::create_dir(index_path(&directory, Index::ClusterCentroid)).unwrap();
        store
            .db()
            .set_meta("cluster_centroid.fill", "filled")
            .unwrap();
        seed(&store, &[(1, 0.0), (2, 90.0)]);
        assign(&store, &[(1, "c"), (2, "c")]);

        assert_eq!(refresh(&store, &[], 1), id_set(&["c"]));

        let (mean, count) = summary_of(&store, "c");
        assert_eq!(count, 2);
        assert_direction(&mean, 45.0);
        assert_eq!(meta(&store, "cluster_centroid.fill"), None);
    }

    #[test]
    fn centroid_search_queries_with_the_stored_averages_in_query_order() {
        let (_directory, store) = open();
        store.fill_cluster_centroid_index(false).unwrap();
        put_summaries(
            &store,
            &[
                ("p1", 0.0),
                ("p2", 90.0),
                ("c1", 10.0),
                ("c2", 80.0),
                ("c3", 5.0),
            ],
        );
        let results = store
            .search_cluster_centroids(
                &ids(&["p2", "missing", "p1"]),
                ids(&["c1", "c2", "c3"]),
                2,
                0.5,
            )
            .unwrap();

        let keys: Vec<Vec<&str>> = results
            .iter()
            .map(|matches| matches.iter().map(|m| m.key.as_str()).collect())
            .collect();
        assert_eq!(keys, [vec!["c2"], vec![], vec!["c3", "c1"]]);
    }

    #[test]
    fn mean_suggestions_pick_the_nearest_allowed_person_cluster_within_the_threshold() {
        let (_directory, store) = open();
        put_summaries(
            &store,
            &[
                ("p1", 0.0),
                ("p2", 90.0),
                ("c1", 10.0),
                ("c2", 70.0),
                ("c3", 180.0),
                ("c4", 40.0),
            ],
        );

        let suggestions = store
            .suggest_clusters_by_mean(
                &ids(&["p1", "p2", "missing"]),
                &ids(&["c4", "c3", "missing", "c2", "c1"]),
                0.5,
                &HashMap::from([("p1".to_string(), id_set(&["c4"]))]),
            )
            .unwrap();

        let found: Vec<(&str, &str)> = suggestions
            .iter()
            .map(|s| (s.cluster_id.as_str(), s.person_cluster_id.as_str()))
            .collect();
        assert_eq!(found, [("c1", "p1"), ("c2", "p2"), ("c4", "p2")]);
        let MeanSuggestion { distance, .. } = &suggestions[2];
        assert!((distance - (1.0 - 50.0_f64.to_radians().cos())).abs() < 1e-6);
    }

    #[test]
    fn mean_suggestions_keep_the_nearest_twenty() {
        let (_directory, store) = open();
        let candidates: Vec<(String, f64)> = (1..=25)
            .map(|degrees| (format!("c{degrees}"), f64::from(degrees)))
            .collect();
        let mut summaries: Vec<(&str, f64)> = candidates
            .iter()
            .map(|(cluster_id, degrees)| (cluster_id.as_str(), *degrees))
            .collect();
        summaries.push(("p", 0.0));
        put_summaries(&store, &summaries);
        let candidate_ids: Vec<String> = candidates.into_iter().rev().map(|(id, _)| id).collect();

        let suggestions = store
            .suggest_clusters_by_mean(&ids(&["p"]), &candidate_ids, 0.5, &HashMap::new())
            .unwrap();

        let found: Vec<&str> = suggestions.iter().map(|s| s.cluster_id.as_str()).collect();
        let expected: Vec<String> = (1..=20).map(|degrees| format!("c{degrees}")).collect();
        assert_eq!(found, expected);
    }

    #[test]
    fn warm_refresh_spans_summary_batches_and_excludes_invalid_summaries() {
        let (_directory, store) = open();
        let clusters: Vec<String> = (0..1100).map(|i| format!("c{i}")).collect();
        let summaries: Vec<(&str, f64)> = clusters.iter().map(|id| (id.as_str(), 0.0)).collect();
        put_summaries(&store, &summaries);
        put_summaries(&store, &[("outside", 0.0)]);
        store
            .db()
            .upsert_cluster_summary_rows(&HashMap::from([(
                clusters[500].clone(),
                ClusterSummary {
                    avg: vec![255],
                    count: 1,
                },
            )]))
            .unwrap();
        let counts = clusters.iter().map(|id| (id.clone(), 1)).collect();

        let averaged = store
            .refresh_cluster_averages(&counts, &HashSet::new(), 1)
            .unwrap();

        let expected = clusters.into_iter().filter(|id| id != "c500").collect();
        assert_eq!(averaged, expected);
    }

    #[test]
    fn oversized_refresh_matches_collected_mean_and_counts_invalid_rows() {
        let (_directory, store) = open();
        let mut faces: Vec<_> = (1..=10003).map(|id| face(id, (id % 17) as f64)).collect();
        faces[0].embedding.truncate(3);
        faces[1].embedding[0] = f64::NAN;
        store.db().bulk_insert_faces(&faces).unwrap();
        let assignments: Vec<_> = (1..=10003).map(|id| (id, "large")).collect();
        assign(&store, &assignments);
        let stored = store
            .db()
            .get_face_embeddings_for_clusters(&ids(&["large"]), None)
            .unwrap();
        let valid: Vec<_> = stored["large"]
            .iter()
            .filter_map(|embedding| crate::ml_store::clustering::clusterable_embedding(embedding))
            .collect();
        let expected = crate::face_clustering::normalized_mean(&valid).unwrap();

        assert_eq!(refresh(&store, &[], 1), id_set(&["large"]));

        let (mean, count) = summary_of(&store, "large");
        assert_eq!(count, 10003);
        assert_eq!(
            mean,
            expected.into_iter().map(f64::from).collect::<Vec<_>>()
        );
        assert_eq!(refresh(&store, &[], 1), id_set(&["large"]));
    }

    #[test]
    fn mean_suggestions_preserve_ties_and_rejections_across_batches() {
        let (_directory, store) = open();
        let candidates: Vec<String> = (0..1100).map(|i| format!("c{i}")).collect();
        let summaries: Vec<(&str, f64)> = candidates.iter().map(|id| (id.as_str(), 30.0)).collect();
        put_summaries(&store, &summaries);
        put_summaries(&store, &[("p1", 0.0), ("p2", 0.0), ("c1099", 1.0)]);
        let ignored = HashMap::from([
            ("p1".to_owned(), id_set(&["c1"])),
            ("p2".to_owned(), id_set(&["c1"])),
        ]);

        let found = store
            .suggest_clusters_by_mean(&ids(&["p2", "p1"]), &candidates, 0.5, &ignored)
            .unwrap();

        let expected: Vec<_> = ["c1099".to_owned()]
            .into_iter()
            .chain((0..20).filter(|&i| i != 1).map(|i| format!("c{i}")))
            .collect();
        assert_eq!(
            found
                .iter()
                .map(|s| s.cluster_id.clone())
                .collect::<Vec<_>>(),
            expected
        );
        assert!(found.iter().all(|s| s.person_cluster_id == "p2"));
    }
}
