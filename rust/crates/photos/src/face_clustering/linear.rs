use std::collections::HashMap;

use super::{
    ClusterMean, Clustering, IncrementalFace, conservative_threshold, distance, new_cluster_id,
    newest_first, summarize,
};

#[derive(Clone, Copy, Debug)]
pub(super) struct Thresholds {
    distance: f64,
    conservative: f64,
    dynamic: bool,
}

impl Thresholds {
    pub(super) fn new(distance: f64, dynamic: bool) -> Self {
        Self {
            distance,
            conservative: conservative_threshold(distance),
            dynamic,
        }
    }

    fn for_face(self, face: &IncrementalFace) -> f64 {
        if self.dynamic && face.bad {
            self.conservative
        } else {
            self.distance
        }
    }
}

pub(super) fn cluster(
    mut faces: Vec<IncrementalFace>,
    thresholds: Thresholds,
    previous_means: &HashMap<String, ClusterMean>,
) -> Clustering {
    faces.sort_by_key(|face| {
        (
            face.cluster_id.is_none(),
            newest_first(face.face.creation_time),
        )
    });
    let mut clusters: Vec<String> = Vec::with_capacity(faces.len());
    for (index, face) in faces.iter().enumerate() {
        let cluster_id = match &face.cluster_id {
            Some(cluster_id) => cluster_id.clone(),
            None => nearest_cluster(face, &faces[..index], &clusters, thresholds)
                .unwrap_or_else(new_cluster_id),
        };
        clusters.push(cluster_id);
    }

    let first_new = faces.partition_point(|face| face.cluster_id.is_some());
    let new_faces = || faces[first_new..].iter().zip(&clusters[first_new..]);
    Clustering {
        assignments: new_faces()
            .map(|(face, cluster_id)| (face.face.face_id.clone(), cluster_id.clone()))
            .collect(),
        means: summarize(
            new_faces().map(|(face, cluster_id)| (cluster_id, face.face.embedding.as_slice())),
            previous_means,
        ),
    }
}

fn nearest_cluster(
    face: &IncrementalFace,
    earlier: &[IncrementalFace],
    clusters: &[String],
    thresholds: Thresholds,
) -> Option<String> {
    let mut closest_distance = f64::INFINITY;
    let mut closest_index = None;
    for (index, candidate) in earlier.iter().enumerate().rev() {
        let candidate_distance = distance(&face.face.embedding, &candidate.face.embedding);
        if candidate_distance < closest_distance
            && !is_excluded(
                face,
                candidate,
                &clusters[index],
                candidate_distance,
                thresholds,
            )
        {
            closest_distance = candidate_distance;
            closest_index = Some(index);
        }
    }
    closest_index
        .filter(|_| closest_distance < thresholds.for_face(face))
        .map(|index| clusters[index].clone())
}

fn is_excluded(
    face: &IncrementalFace,
    candidate: &IncrementalFace,
    candidate_cluster: &str,
    candidate_distance: f64,
    thresholds: Thresholds,
) -> bool {
    (candidate.bad && candidate_distance > thresholds.conservative)
        || (!face.rejected_cluster_ids.is_empty()
            && face.rejected_cluster_ids.contains(candidate_cluster))
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use super::{Thresholds, cluster};
    use crate::face_clustering::tests::{
        assert_close, clustered_face, direction, groups, names, new_face,
    };
    use crate::face_clustering::{
        ClusterMean, Clustering, IncrementalFace, RECOMMENDED_DISTANCE_THRESHOLD,
        cluster_incrementally,
    };

    fn cluster_dynamic(faces: Vec<IncrementalFace>) -> Clustering {
        cluster_incrementally(faces, RECOMMENDED_DISTANCE_THRESHOLD, &HashMap::new())
    }

    #[test]
    fn faces_join_an_earlier_cluster_only_within_the_threshold() {
        let clustering = cluster_dynamic(vec![
            new_face("x", 0.0, 3),
            new_face("y", 10.0, 2),
            new_face("z", 60.0, 1),
        ]);
        assert_eq!(groups(&clustering), names(&[&["x", "y"], &["z"]]));
    }

    #[test]
    fn faces_join_the_nearest_cluster_not_the_most_recent_one() {
        for (degrees, expected) in [(30.0, "q"), (12.0, "p")] {
            let clustering = cluster_dynamic(vec![
                clustered_face("p0", 0.0, 2, "p"),
                clustered_face("q0", 40.0, 1, "q"),
                new_face("f", degrees, 3),
            ]);
            assert_eq!(clustering.assignments["f"], expected);
        }
    }

    #[test]
    fn only_new_faces_are_assigned() {
        let clustering = cluster_dynamic(vec![
            clustered_face("p0", 0.0, 1, "p"),
            new_face("f", 5.0, 2),
        ]);
        assert_eq!(clustering.assignments.len(), 1);
        assert_eq!(clustering.assignments["f"], "p");
    }

    #[test]
    fn bad_faces_join_only_within_the_conservative_threshold() {
        for (bad, joins) in [(true, false), (false, true)] {
            let mut joining = new_face("f", 34.0, 2);
            joining.bad = bad;
            let clustering = cluster_dynamic(vec![clustered_face("p0", 0.0, 1, "p"), joining]);
            assert_eq!(clustering.assignments["f"] == "p", joins);
        }
    }

    #[test]
    fn bad_faces_use_the_full_threshold_without_dynamic_thresholds() {
        let mut joining = new_face("f", 34.0, 2);
        joining.bad = true;
        let clustering = cluster(
            vec![clustered_face("p0", 0.0, 1, "p"), joining],
            Thresholds::new(RECOMMENDED_DISTANCE_THRESHOLD, false),
            &HashMap::new(),
        );
        assert_eq!(clustering.assignments["f"], "p");
    }

    #[test]
    fn bad_candidates_attract_only_within_the_conservative_threshold() {
        for (degrees, joins) in [(34.0, false), (20.0, true)] {
            let mut candidate = clustered_face("p0", 0.0, 1, "p");
            candidate.bad = true;
            let clustering = cluster_dynamic(vec![candidate, new_face("f", degrees, 2)]);
            assert_eq!(clustering.assignments["f"] == "p", joins);
        }
    }

    #[test]
    fn equally_close_faces_resolve_to_the_one_processed_last() {
        let clustering = cluster_dynamic(vec![
            clustered_face("p0", 0.0, 2, "p"),
            clustered_face("q0", 0.0, 1, "q"),
            new_face("f", 5.0, 3),
        ]);
        assert_eq!(clustering.assignments["f"], "q");
    }

    #[test]
    fn distances_are_compared_in_double_precision_like_dart() {
        let mut a = new_face("a", 0.0, 2);
        a.face.embedding = vec![0.6, 0.8];
        let mut b = new_face("b", 0.0, 1);
        b.face.embedding = vec![-0.063938476, 0.99795383];
        let clustering = cluster_dynamic(vec![a, b]);
        assert_eq!(clustering.assignments["a"], clustering.assignments["b"]);
    }

    #[test]
    fn rejected_clusters_are_skipped() {
        let mut rejecting = new_face("f", 5.0, 3);
        rejecting.rejected_cluster_ids.insert("p".to_owned());
        let clustering = cluster_dynamic(vec![
            clustered_face("p0", 0.0, 2, "p"),
            clustered_face("q0", 25.0, 1, "q"),
            rejecting,
        ]);
        assert_eq!(clustering.assignments["f"], "q");
    }

    #[test]
    fn faces_are_clustered_newest_first() {
        let clustering = cluster_dynamic(vec![
            new_face("x", 0.0, 3),
            new_face("z", 74.0, 1),
            new_face("y", 37.0, 2),
        ]);
        assert_eq!(groups(&clustering), names(&[&["x", "y", "z"]]));
    }

    #[test]
    fn means_fold_new_faces_into_the_previous_cluster_mean() {
        let previous = HashMap::from([(
            "p".to_owned(),
            ClusterMean {
                mean: direction(0.0),
                count: 3,
            },
        )]);
        let clustering = cluster_incrementally(
            vec![
                clustered_face("p0", 0.0, 1, "p"),
                new_face("f", 20.0, 2),
                new_face("g", 90.0, 3),
            ],
            RECOMMENDED_DISTANCE_THRESHOLD,
            &previous,
        );

        let joined = &clustering.means["p"];
        let new_member = direction(20.0);
        let sum = [3.0 + new_member[0], new_member[1]];
        let norm = (sum[0] * sum[0] + sum[1] * sum[1]).sqrt();
        assert_eq!(joined.count, 4);
        assert_close(&joined.mean, &[sum[0] / norm, sum[1] / norm]);

        let created = &clustering.means[&clustering.assignments["g"]];
        assert_eq!(created.count, 1);
        assert_close(&created.mean, &direction(90.0));
    }

    #[test]
    fn empty_input_has_no_clusters() {
        assert_eq!(cluster_dynamic(Vec::new()), Clustering::default());
    }
}
