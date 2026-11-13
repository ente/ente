use std::collections::{HashMap, HashSet};
use std::time::Instant;

use super::compute_smart_memories;
use super::input::{CityLookup, MemoriesRequest, MlInputs, PeopleInputs, Period, UnnamedCluster};
use super::output::SmartMemories;
use super::people::shows_unnamed_clusters;
use crate::ml_db::{MlDb, try_file_id_from_face_id};
use crate::ml_store::{Error, FillState, Index, MlStore, Result};

const NAMED_FACE_WEIGHT: u32 = 10;
const OTHER_FACE_WEIGHT: u32 = 1;

pub fn compute_smart_memories_from_store(
    request: &MemoriesRequest,
    periods: &[Period],
    store: Option<&MlStore>,
    cities: Option<&dyn CityLookup>,
) -> Result<SmartMemories> {
    let started = Instant::now();
    let ml = store
        .map(|store| load_ml_inputs(store, request))
        .transpose()?;
    log::info!(
        "loaded memories ML inputs in {} ms",
        started.elapsed().as_millis()
    );
    let started = Instant::now();
    let memories = compute_smart_memories(request, periods, ml.as_ref(), cities)?;
    log::info!(
        "computed smart memories for {} files with seed {} in {} ms",
        request.files.len(),
        request.seed,
        started.elapsed().as_millis()
    );
    Ok(memories)
}

fn load_ml_inputs<'s>(store: &'s MlStore, request: &MemoriesRequest) -> Result<MlInputs<'s>> {
    store.fill_clip_index(false)?;
    if store.fill_state(Index::Clip)? != FillState::Filled {
        return Err(Error::NotFilled(Index::Clip));
    }
    let db = store.db();
    let NamedFaces {
        file_ids_by_person,
        face_ids,
    } = named_faces(db, request)?;
    let (face_counts, face_weights) = face_counts_and_weights(db, &face_ids)?;
    drop(face_ids);
    let unnamed_clusters = if shows_unnamed_clusters(request) {
        unnamed_clusters(db, request)?
    } else {
        Vec::new()
    };
    Ok(MlInputs {
        clip: store,
        face_weights,
        people: PeopleInputs {
            face_counts,
            person_file_ids: file_ids_by_person,
            unnamed_clusters,
        },
    })
}

struct NamedFaces {
    file_ids_by_person: HashMap<String, HashSet<i64>>,
    face_ids: HashSet<String>,
}

fn named_faces(db: &MlDb, request: &MemoriesRequest) -> Result<NamedFaces> {
    let person_ids: HashSet<&str> = request
        .people
        .iter()
        .map(|person| person.id.as_str())
        .collect();
    let mut faces = NamedFaces {
        file_ids_by_person: HashMap::new(),
        face_ids: HashSet::new(),
    };
    db.for_each_person_face_id(|person_id, face_id| {
        if person_ids.contains(person_id.as_str()) {
            faces
                .file_ids_by_person
                .entry(person_id)
                .or_default()
                .extend(try_file_id_from_face_id(&face_id));
            faces.face_ids.insert(face_id);
        }
    })?;
    Ok(faces)
}

fn face_counts_and_weights(
    db: &MlDb,
    named_face_ids: &HashSet<String>,
) -> Result<(HashMap<i64, u32>, HashMap<i64, u32>)> {
    let mut face_counts = HashMap::new();
    let mut face_weights = HashMap::new();
    db.for_each_face_id(|file_id, face_id| {
        let weight = if named_face_ids.contains(&face_id) {
            NAMED_FACE_WEIGHT
        } else {
            OTHER_FACE_WEIGHT
        };
        *face_counts.entry(file_id).or_insert(0) += 1;
        *face_weights.entry(file_id).or_insert(0) += weight;
    })?;
    Ok((face_counts, face_weights))
}

fn unnamed_clusters(db: &MlDb, request: &MemoriesRequest) -> Result<Vec<UnnamedCluster>> {
    let person_ids: Vec<String> = request
        .people
        .iter()
        .map(|person| person.id.clone())
        .chain(request.people_hidden_from_memories.iter().cloned())
        .collect();
    let assigned = db.get_persons_cluster_ids(&person_ids)?;
    let mut clusters: HashMap<String, UnnamedCluster> = HashMap::new();
    db.for_each_cluster_face_id(|cluster_id, face_id| {
        if assigned.contains(&cluster_id) {
            return;
        }
        let cluster = clusters
            .entry(cluster_id)
            .or_insert_with_key(|id| UnnamedCluster {
                id: id.clone(),
                face_count: 0,
                file_ids: HashSet::new(),
            });
        cluster.face_count += 1;
        cluster.file_ids.extend(try_file_id_from_face_id(&face_id));
    })?;
    Ok(clusters.into_values().collect())
}

#[cfg(test)]
mod tests {
    use std::collections::{HashMap, HashSet};

    use super::load_ml_inputs;
    use crate::memories::{MemoriesRequest, MemoryPerson, UnnamedCluster};
    use crate::ml_db::{CLIP_EMBEDDING_DIMENSIONS, ClipEmbedding, FaceRow};
    use crate::ml_store::{CLUSTER_CENTROID_DIMENSIONS, Error, FillState, Index, MlStore};

    fn face(face_id: &str) -> FaceRow {
        FaceRow {
            file_id: face_id.split_once('_').unwrap().0.parse().unwrap(),
            face_id: face_id.to_string(),
            detection_json: "{}".to_string(),
            embedding: vec![0.1; CLUSTER_CENTROID_DIMENSIONS],
            score: 0.9,
            blur: 300.0,
            is_sideways: false,
            image_height: 100,
            image_width: 100,
            ml_version: 1,
        }
    }

    fn person(id: &str) -> MemoryPerson {
        MemoryPerson {
            id: id.to_string(),
            is_ignored: false,
            birth_date: None,
        }
    }

    fn library() -> (tempfile::TempDir, MlStore) {
        let directory = tempfile::tempdir().unwrap();
        let store = MlStore::open(directory.path().join("ente.ml.db")).unwrap();
        let db = store.db();
        db.bulk_insert_faces(&["1_a", "1_c", "2_a", "3_b", "4_c", "5_d"].map(face))
            .unwrap();
        db.update_face_id_to_cluster_id(&HashMap::from(
            [
                ("1_a", "named"),
                ("2_a", "named"),
                ("6_a", "named"),
                ("3_b", "hidden"),
                ("1_c", "unnamed"),
                ("4_c", "unnamed"),
            ]
            .map(|(face_id, cluster_id)| (face_id.to_string(), cluster_id.to_string())),
        ))
        .unwrap();
        db.assign_cluster_to_person("alice", "named").unwrap();
        db.assign_cluster_to_person("carol", "named").unwrap();
        db.assign_cluster_to_person("bob", "hidden").unwrap();
        store
            .put_clip(&[ClipEmbedding {
                file_id: 1,
                embedding: vec![0.5; CLIP_EMBEDDING_DIMENSIONS],
                version: 1,
            }])
            .unwrap();
        (directory, store)
    }

    #[test]
    fn inputs_count_faces_weight_named_people_and_skip_assigned_clusters() {
        let (_directory, store) = library();
        let request = MemoriesRequest {
            people: vec![person("alice")],
            people_hidden_from_memories: vec!["bob".to_string()],
            shows_unnamed_people: true,
            ..MemoriesRequest::default()
        };

        let inputs = load_ml_inputs(&store, &request).unwrap();

        assert_eq!(store.fill_state(Index::Clip).unwrap(), FillState::Filled);
        assert_eq!(
            inputs.face_weights,
            HashMap::from([(1, 11), (2, 10), (3, 1), (4, 1), (5, 1)])
        );
        assert_eq!(
            inputs.people.face_counts,
            HashMap::from([(1, 2), (2, 1), (3, 1), (4, 1), (5, 1)])
        );
        assert_eq!(
            inputs.people.person_file_ids,
            HashMap::from([("alice".to_string(), HashSet::from([1, 2, 6]))])
        );
        assert_eq!(
            inputs.people.unnamed_clusters,
            [UnnamedCluster {
                id: "unnamed".to_string(),
                face_count: 2,
                file_ids: HashSet::from([1, 4]),
            }]
        );
    }

    #[test]
    fn unnamed_clusters_stay_unloaded_once_enough_people_are_named() {
        let (_directory, store) = library();
        let request = MemoriesRequest {
            people: ["alice", "bob", "carol", "dave", "erin"]
                .map(person)
                .to_vec(),
            shows_unnamed_people: true,
            ..MemoriesRequest::default()
        };

        let inputs = load_ml_inputs(&store, &request).unwrap();

        assert!(inputs.people.unnamed_clusters.is_empty());
        assert_eq!(inputs.face_weights[&1], 11);
        assert_eq!(inputs.face_weights[&3], 10);
        assert_eq!(
            inputs.people.person_file_ids["carol"],
            HashSet::from([1, 2, 6])
        );
    }

    #[test]
    fn unusable_clip_index_fails_the_load() {
        let (directory, store) = library();
        std::fs::create_dir(
            directory
                .path()
                .join(format!("ente.ml.vecdb.{}", Index::Clip.name())),
        )
        .unwrap();

        let result = load_ml_inputs(&store, &MemoriesRequest::default());

        assert!(matches!(result, Err(Error::Index(_))));
    }
}
