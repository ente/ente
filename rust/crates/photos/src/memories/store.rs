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
    let person_face_ids = person_face_ids(db, request)?;
    let named_face_ids: HashSet<&String> = person_face_ids.values().flatten().collect();
    let mut face_counts = HashMap::new();
    let mut face_weights = HashMap::new();
    for (file_id, face_ids) in db.get_file_id_to_face_ids()? {
        let weight = face_ids
            .iter()
            .map(|face_id| {
                if named_face_ids.contains(face_id) {
                    NAMED_FACE_WEIGHT
                } else {
                    OTHER_FACE_WEIGHT
                }
            })
            .sum();
        face_counts.insert(file_id, face_ids.len() as u32);
        face_weights.insert(file_id, weight);
    }
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
            person_file_ids: person_face_ids
                .iter()
                .map(|(person_id, face_ids)| (person_id.clone(), file_ids(face_ids)))
                .collect(),
            unnamed_clusters,
        },
    })
}

fn person_face_ids(db: &MlDb, request: &MemoriesRequest) -> Result<HashMap<String, Vec<String>>> {
    let person_ids: HashSet<&str> = request
        .people
        .iter()
        .map(|person| person.id.as_str())
        .collect();
    Ok(db
        .get_person_to_cluster_id_to_face_ids()?
        .into_iter()
        .filter(|(person_id, _)| person_ids.contains(person_id.as_str()))
        .map(|(person_id, clusters)| (person_id, clusters.into_values().flatten().collect()))
        .collect())
}

fn unnamed_clusters(db: &MlDb, request: &MemoriesRequest) -> Result<Vec<UnnamedCluster>> {
    let person_ids: Vec<String> = request
        .people
        .iter()
        .map(|person| person.id.clone())
        .chain(request.people_hidden_from_memories.iter().cloned())
        .collect();
    let assigned = db.get_persons_cluster_ids(&person_ids)?;
    Ok(db
        .get_all_cluster_id_to_face_ids()?
        .into_iter()
        .filter(|(cluster_id, _)| !assigned.contains(cluster_id))
        .map(|(id, face_ids)| UnnamedCluster {
            id,
            face_count: face_ids.len() as u32,
            file_ids: file_ids(&face_ids),
        })
        .collect())
}

fn file_ids(face_ids: &[String]) -> HashSet<i64> {
    face_ids
        .iter()
        .filter_map(|face_id| try_file_id_from_face_id(face_id))
        .collect()
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
        db.bulk_insert_faces(&["1_a", "1_c", "2_a", "3_b", "4_c"].map(face))
            .unwrap();
        db.update_face_id_to_cluster_id(&HashMap::from(
            [
                ("1_a", "named"),
                ("2_a", "named"),
                ("3_b", "hidden"),
                ("1_c", "unnamed"),
                ("4_c", "unnamed"),
            ]
            .map(|(face_id, cluster_id)| (face_id.to_string(), cluster_id.to_string())),
        ))
        .unwrap();
        db.assign_cluster_to_person("alice", "named").unwrap();
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
            HashMap::from([(1, 11), (2, 10), (3, 1), (4, 1)])
        );
        assert_eq!(
            inputs.people.face_counts,
            HashMap::from([(1, 2), (2, 1), (3, 1), (4, 1)])
        );
        assert_eq!(
            inputs.people.person_file_ids,
            HashMap::from([("alice".to_string(), HashSet::from([1, 2]))])
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
        assert_eq!(inputs.face_weights[&3], 10);
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
