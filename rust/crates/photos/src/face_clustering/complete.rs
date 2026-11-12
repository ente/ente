use std::collections::HashMap;

use super::{
    Clustering, Face, add_scaled, distance, new_cluster_id, newest_first, normalized, scaled,
    summarize,
};

struct Group {
    cluster_id: String,
    mean: Vec<f32>,
    count: usize,
}

pub(super) fn cluster(
    mut faces: Vec<Face>,
    distance_threshold: f64,
    merge_threshold: f64,
) -> Clustering {
    faces.sort_by_key(|face| newest_first(face.creation_time));
    let clusters = assign_nearest(&faces, distance_threshold);
    let merged_into = merge_groups(group_means(&faces, &clusters), merge_threshold);
    let clusters: Vec<String> = clusters
        .iter()
        .map(|cluster_id| final_cluster(&merged_into, cluster_id).to_owned())
        .collect();
    Clustering {
        assignments: faces
            .iter()
            .zip(&clusters)
            .map(|(face, cluster_id)| (face.face_id.clone(), cluster_id.clone()))
            .collect(),
        means: summarize(
            faces
                .iter()
                .zip(&clusters)
                .map(|(face, cluster_id)| (cluster_id, face.embedding.as_slice())),
            &HashMap::new(),
        ),
    }
}

fn assign_nearest(faces: &[Face], distance_threshold: f64) -> Vec<String> {
    let mut clusters: Vec<Option<String>> = vec![None; faces.len()];
    for (index, face) in faces.iter().enumerate() {
        if clusters[index].is_some() {
            continue;
        }
        let cluster_id = match closest_other(faces, index, face) {
            Some((other, other_distance)) if other_distance < distance_threshold => {
                clusters[other].get_or_insert_with(new_cluster_id).clone()
            }
            _ => new_cluster_id(),
        };
        clusters[index] = Some(cluster_id);
    }
    clusters.into_iter().flatten().collect()
}

fn closest_other(faces: &[Face], index: usize, face: &Face) -> Option<(usize, f64)> {
    let mut closest: Option<(usize, f64)> = None;
    for (other, candidate) in faces.iter().enumerate() {
        if other == index {
            continue;
        }
        let candidate_distance = distance(&face.embedding, &candidate.embedding);
        if candidate_distance < closest.map_or(f64::INFINITY, |(_, closest)| closest) {
            closest = Some((other, candidate_distance));
        }
    }
    closest
}

fn group_means(faces: &[Face], clusters: &[String]) -> Vec<Group> {
    let mut groups: Vec<Group> = Vec::new();
    let mut positions: HashMap<&String, usize> = HashMap::new();
    for (face, cluster_id) in faces.iter().zip(clusters) {
        let position = *positions.entry(cluster_id).or_insert_with(|| {
            groups.push(Group {
                cluster_id: cluster_id.clone(),
                mean: vec![0.0; face.embedding.len()],
                count: 0,
            });
            groups.len() - 1
        });
        add_scaled(&mut groups[position].mean, &face.embedding, 1.0);
        groups[position].count += 1;
    }
    for group in &mut groups {
        let sum = std::mem::take(&mut group.mean);
        group.mean = normalized(scaled(sum, 1.0 / group.count as f64));
    }
    groups
}

fn merge_groups(mut groups: Vec<Group>, merge_threshold: f64) -> HashMap<String, String> {
    let mut merged_into = HashMap::new();
    while let Some((keep, absorb)) = closest_pair(&groups, merge_threshold) {
        let absorbed = groups.remove(absorb);
        let kept = &mut groups[keep];
        let total = (kept.count + absorbed.count) as f64;
        let mut mean = vec![0.0; kept.mean.len()];
        add_scaled(&mut mean, &kept.mean, kept.count as f64 / total);
        add_scaled(&mut mean, &absorbed.mean, absorbed.count as f64 / total);
        kept.mean = normalized(mean);
        kept.count += absorbed.count;
        merged_into.insert(absorbed.cluster_id, kept.cluster_id.clone());
    }
    merged_into
}

fn closest_pair(groups: &[Group], merge_threshold: f64) -> Option<(usize, usize)> {
    let mut closest: Option<(usize, usize, f64)> = None;
    for (first, first_group) in groups.iter().enumerate() {
        for (second, second_group) in groups.iter().enumerate().skip(first + 1) {
            let pair_distance = distance(&first_group.mean, &second_group.mean);
            if pair_distance < closest.map_or(f64::INFINITY, |(_, _, closest)| closest) {
                closest = Some((first, second, pair_distance));
            }
        }
    }
    closest
        .filter(|(_, _, pair_distance)| *pair_distance < merge_threshold)
        .map(|(first, second, _)| (first, second))
}

fn final_cluster<'a>(merged_into: &'a HashMap<String, String>, cluster_id: &'a str) -> &'a str {
    let mut cluster_id = cluster_id;
    while let Some(next) = merged_into.get(cluster_id) {
        cluster_id = next;
    }
    cluster_id
}

#[cfg(test)]
mod tests {
    use super::cluster;
    use crate::face_clustering::tests::{assert_close, direction, face, groups, names};

    #[test]
    fn close_faces_cluster_and_distant_faces_stay_apart() {
        let clustering = cluster(
            vec![
                face("a0", 0.0, 4),
                face("a1", 1.0, 3),
                face("b0", 90.0, 2),
                face("b1", 91.0, 1),
            ],
            0.16,
            0.24,
        );
        assert_eq!(groups(&clustering), names(&[&["a0", "a1"], &["b0", "b1"]]));
    }

    #[test]
    fn clusters_merge_when_their_means_are_within_the_merge_threshold() {
        for (degrees, expected_groups) in [(34.0, 1), (45.6, 2)] {
            let clustering = cluster(
                vec![
                    face("a0", 0.0, 4),
                    face("a1", 0.0, 3),
                    face("b0", degrees, 2),
                    face("b1", degrees, 1),
                ],
                0.16,
                0.24,
            );
            assert_eq!(groups(&clustering).len(), expected_groups);
        }
    }

    #[test]
    fn equally_close_faces_resolve_to_the_first_one() {
        let clustering = cluster(
            vec![
                face("a0", 40.0, 5),
                face("a1", 40.0, 4),
                face("b0", -40.0, 3),
                face("b1", -40.0, 2),
                face("m", 0.0, 1),
            ],
            0.24,
            0.24,
        );
        assert_eq!(
            groups(&clustering),
            names(&[&["a0", "a1", "m"], &["b0", "b1"]])
        );
    }

    #[test]
    fn equally_close_clusters_merge_in_index_order() {
        let clustering = cluster(
            vec![
                face("g0", 0.0, 3),
                face("g1", 30.0, 2),
                face("g2", -30.0, 1),
            ],
            0.0,
            0.2,
        );
        assert_eq!(groups(&clustering), names(&[&["g0", "g1"], &["g2"]]));
    }

    #[test]
    fn chained_merges_relabel_every_face() {
        let clustering = cluster(
            vec![
                face("a0", 0.0, 6),
                face("a1", 0.0, 5),
                face("b0", 28.0, 4),
                face("b1", 28.0, 3),
                face("c0", 50.0, 2),
                face("c1", 50.0, 1),
            ],
            0.05,
            0.24,
        );
        assert_eq!(
            groups(&clustering),
            names(&[&["a0", "a1", "b0", "b1", "c0", "c1"]])
        );
        assert_eq!(clustering.means.len(), 1);
        assert_eq!(clustering.means[&clustering.assignments["a0"]].count, 6);
    }

    #[test]
    fn means_cover_every_face_of_each_final_cluster() {
        let clustering = cluster(
            vec![face("a0", 0.0, 3), face("a1", 2.0, 2), face("b0", 90.0, 1)],
            0.16,
            0.24,
        );
        let a = &clustering.means[&clustering.assignments["a0"]];
        assert_eq!(a.count, 2);
        assert_close(&a.mean, &direction(1.0));
        let b = &clustering.means[&clustering.assignments["b0"]];
        assert_eq!(b.count, 1);
        assert_close(&b.mean, &direction(90.0));
    }
}
