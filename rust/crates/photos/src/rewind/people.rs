use std::collections::{HashMap, HashSet};

use serde::Deserialize;

use super::Result;
use super::input::{RewindPerson, RewindRequest};
use super::library::{Library, YearFile, local_time};
use crate::ml_db::try_file_id_from_face_id;
use crate::ml_store::MlStore;

pub(super) struct People {
    hidden_file_ids: HashSet<i64>,
    named_face_counts: HashMap<i64, u32>,
    face_counts: HashMap<i64, u32>,
    faces: HashMap<String, Face>,
    persons: Vec<Entity>,
    clusters: Vec<Entity>,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub(super) struct Face {
    pub(super) file_id: i64,
    pub(super) score: f64,
    pub(super) blur: f64,
    pub(super) area: f64,
    pub(super) eyes: Option<Eyes>,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub(super) struct Eyes {
    pub(super) left: (f64, f64),
    pub(super) right: (f64, f64),
    pub(super) nose: (f64, f64),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) struct Entity {
    pub(super) id: String,
    pub(super) first_local_time: i64,
    pub(super) face_ids: Vec<String>,
}

#[derive(Deserialize)]
struct Detection {
    #[serde(rename = "box")]
    face_box: FaceBox,
    #[serde(default)]
    landmarks: Vec<Landmark>,
}

#[derive(Deserialize)]
struct FaceBox {
    width: f64,
    height: f64,
}

#[derive(Deserialize)]
struct Landmark {
    x: f64,
    y: f64,
}

impl People {
    pub(super) fn load(
        request: &RewindRequest,
        library: &Library<'_>,
        store: &MlStore,
    ) -> Result<Self> {
        let db = store.db();
        let mut faces = HashMap::new();
        let mut face_counts = HashMap::new();
        db.for_each_face_without_embedding(|face| {
            if library.get(face.file_id).is_some_and(YearFile::is_eligible) {
                *face_counts.entry(face.file_id).or_insert(0) += 1;
                let (area, eyes) = shape(&face.detection_json);
                faces.insert(
                    face.face_id,
                    Face {
                        file_id: face.file_id,
                        score: face.score,
                        blur: face.blur,
                        area,
                        eyes,
                    },
                );
            }
        })?;
        let people: HashMap<&str, &RewindPerson> = request
            .people
            .iter()
            .map(|person| (person.id.as_str(), person))
            .collect();
        let local_times: HashMap<i64, i64> = request
            .files
            .iter()
            .map(|file| (file.id, local_time(file)))
            .collect();
        let cluster_people = db.get_cluster_id_to_person_id()?;
        let mut hidden_file_ids = HashSet::new();
        let mut named_face_counts = HashMap::new();
        let mut persons: HashMap<String, Entity> = HashMap::new();
        let mut clusters: HashMap<String, Entity> = HashMap::new();
        db.for_each_cluster_face_id(|cluster_id, face_id| {
            let Some(file_id) = try_file_id_from_face_id(&face_id) else {
                return;
            };
            let entity = match cluster_people.get(&cluster_id) {
                None => clusters
                    .entry(cluster_id)
                    .or_insert_with_key(|id| Entity::new(id)),
                Some(person_id) => match people.get(person_id.as_str()) {
                    Some(person) if person.is_hidden_from_memories => {
                        hidden_file_ids.insert(file_id);
                        return;
                    }
                    Some(person) if !person.is_ignored => {
                        if faces.contains_key(&face_id) {
                            *named_face_counts.entry(file_id).or_insert(0) += 1;
                        }
                        persons
                            .entry(person_id.clone())
                            .or_insert_with_key(|id| Entity::new(id))
                    }
                    _ => return,
                },
            };
            if let Some(&time) = local_times.get(&file_id) {
                entity.first_local_time = entity.first_local_time.min(time);
            }
            if faces.contains_key(&face_id) {
                entity.face_ids.push(face_id);
            }
        })?;
        Ok(Self {
            hidden_file_ids,
            named_face_counts,
            face_counts,
            faces,
            persons: in_year(persons),
            clusters: in_year(clusters),
        })
    }

    pub(super) fn hides(&self, file_id: i64) -> bool {
        self.hidden_file_ids.contains(&file_id)
    }

    pub(super) fn named_face_count(&self, file_id: i64) -> u32 {
        self.named_face_counts.get(&file_id).copied().unwrap_or(0)
    }

    pub(super) fn face_count(&self, file_id: i64) -> u32 {
        self.face_counts.get(&file_id).copied().unwrap_or(0)
    }

    pub(super) fn face(&self, face_id: &str) -> Option<&Face> {
        self.faces.get(face_id)
    }

    pub(super) fn persons(&self) -> &[Entity] {
        &self.persons
    }

    pub(super) fn clusters(&self) -> &[Entity] {
        &self.clusters
    }

    pub(super) fn files_of<'l, 'r>(
        &self,
        entity: &Entity,
        library: &'l Library<'r>,
    ) -> Vec<&'l YearFile<'r>> {
        let mut seen = HashSet::new();
        entity
            .face_ids
            .iter()
            .filter_map(|face_id| self.face(face_id))
            .filter(|face| seen.insert(face.file_id))
            .filter_map(|face| library.get(face.file_id))
            .collect()
    }
}

impl Entity {
    fn new(id: &str) -> Self {
        Self {
            id: id.to_owned(),
            first_local_time: i64::MAX,
            face_ids: Vec::new(),
        }
    }
}

fn in_year(entities: HashMap<String, Entity>) -> Vec<Entity> {
    let mut entities: Vec<Entity> = entities
        .into_values()
        .filter(|entity| !entity.face_ids.is_empty())
        .collect();
    entities.sort_by(|first, second| first.id.cmp(&second.id));
    for entity in &mut entities {
        entity.face_ids.sort();
    }
    entities
}

fn shape(detection_json: &str) -> (f64, Option<Eyes>) {
    let Ok(detection) = serde_json::from_str::<Detection>(detection_json) else {
        return (0.0, None);
    };
    let eyes = match detection.landmarks.as_slice() {
        [left, right, nose, ..] => Some(Eyes {
            left: (left.x, left.y),
            right: (right.x, right.y),
            nose: (nose.x, nose.y),
        }),
        _ => None,
    };
    (detection.face_box.width * detection.face_box.height, eyes)
}
