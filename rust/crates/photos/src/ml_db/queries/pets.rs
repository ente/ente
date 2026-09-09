use std::collections::HashMap;
use std::num::NonZeroUsize;

use crate::db::{Row, SqliteResult, bind_placeholders, pair, params_from_iter};

use super::unique_in_order;
use crate::ml_db::{MlDb, Result};

pub const PET_ML_VERSION: i64 = 1;

#[derive(Clone, Debug, PartialEq)]
pub struct PetFaceRow {
    pub file_id: i64,
    pub pet_face_id: String,
    pub detection_json: String,
    pub face_vector_id: Option<i64>,
    pub species: i64,
    pub face_score: f64,
    pub image_height: i64,
    pub image_width: i64,
    pub ml_version: i64,
}

#[derive(Clone, Debug, PartialEq)]
pub struct PetBodyRow {
    pub file_id: i64,
    pub pet_body_id: String,
    pub detection_json: String,
    pub body_vector_id: Option<i64>,
    pub species: i64,
    pub score: f64,
    pub image_height: i64,
    pub image_width: i64,
    pub ml_version: i64,
}

#[derive(Clone, Debug, PartialEq)]
pub struct PetFaceVectorRow {
    pub pet_face_id: String,
    pub face_vector_id: Option<i64>,
    pub species: i64,
}

#[derive(Clone, Debug, PartialEq)]
pub struct PetBodyVectorRow {
    pub pet_body_id: String,
    pub body_vector_id: Option<i64>,
    pub species: i64,
}

#[derive(Clone, Debug, PartialEq)]
pub struct PetRowsForFiles {
    pub faces: Vec<PetFaceVectorRow>,
    pub bodies: Vec<PetBodyVectorRow>,
}

const UPSERT_PET_FACE: &str = r#"
    INSERT INTO pet_faces (
        file_id, pet_face_id, detection, face_vector_id, species,
        score, height, width, ml_version
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT (file_id, pet_face_id) DO UPDATE SET
        detection = excluded.detection,
        face_vector_id = excluded.face_vector_id,
        species = excluded.species,
        score = excluded.score,
        height = excluded.height,
        width = excluded.width,
        ml_version = excluded.ml_version
"#;
const UPSERT_PET_BODY: &str = r#"
    INSERT INTO pet_bodies (
        file_id, pet_body_id, detection, body_vector_id, species,
        score, height, width, ml_version
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT (file_id, pet_body_id) DO UPDATE SET
        detection = excluded.detection,
        body_vector_id = excluded.body_vector_id,
        species = excluded.species,
        score = excluded.score,
        height = excluded.height,
        width = excluded.width,
        ml_version = excluded.ml_version
"#;

impl MlDb {
    pub fn bulk_insert_pet_faces(&self, pet_faces: &[PetFaceRow]) -> Result<()> {
        self.db
            .write_batches_committing_each(
                UPSERT_PET_FACE,
                const { NonZeroUsize::new(500).unwrap() },
                pet_faces.iter().map(|pet_face| {
                    (
                        pet_face.file_id,
                        &pet_face.pet_face_id,
                        &pet_face.detection_json,
                        pet_face.face_vector_id,
                        pet_face.species,
                        pet_face.face_score,
                        pet_face.image_height,
                        pet_face.image_width,
                        pet_face.ml_version,
                    )
                }),
            )
            .map_err(Into::into)
    }

    pub fn bulk_insert_pet_bodies(&self, pet_bodies: &[PetBodyRow]) -> Result<()> {
        self.db
            .write_batches_committing_each(
                UPSERT_PET_BODY,
                const { NonZeroUsize::new(500).unwrap() },
                pet_bodies.iter().map(|pet_body| {
                    (
                        pet_body.file_id,
                        &pet_body.pet_body_id,
                        &pet_body.detection_json,
                        pet_body.body_vector_id,
                        pet_body.species,
                        pet_body.score,
                        pet_body.image_height,
                        pet_body.image_width,
                        pet_body.ml_version,
                    )
                }),
            )
            .map_err(Into::into)
    }

    pub fn update_pet_face_vector_ids(
        &self,
        pet_face_id_to_vector_id: &HashMap<String, i64>,
    ) -> Result<()> {
        if pet_face_id_to_vector_id.is_empty() {
            return Ok(());
        }
        self.db
            .write_batches_committing_each(
                "UPDATE pet_faces SET face_vector_id = ? WHERE pet_face_id = ?",
                const { NonZeroUsize::new(500).unwrap() },
                pet_face_id_to_vector_id
                    .iter()
                    .map(|(pet_face_id, vector_id)| (vector_id, pet_face_id)),
            )
            .map_err(Into::into)
    }

    pub fn update_pet_body_vector_ids(
        &self,
        pet_body_id_to_vector_id: &HashMap<String, i64>,
    ) -> Result<()> {
        if pet_body_id_to_vector_id.is_empty() {
            return Ok(());
        }
        self.db
            .write_batches_committing_each(
                "UPDATE pet_bodies SET body_vector_id = ? WHERE pet_body_id = ?",
                const { NonZeroUsize::new(500).unwrap() },
                pet_body_id_to_vector_id
                    .iter()
                    .map(|(pet_body_id, vector_id)| (vector_id, pet_body_id)),
            )
            .map_err(Into::into)
    }

    pub fn get_pet_faces_for_file_id(&self, file_upload_id: i64) -> Result<Vec<PetFaceRow>> {
        self.db
            .read_all(
                "SELECT * FROM pet_faces WHERE file_id = ? AND species != -1",
                [file_upload_id],
                read_pet_face,
            )
            .map_err(Into::into)
    }

    pub fn get_pet_bodies_for_file_id(&self, file_upload_id: i64) -> Result<Vec<PetBodyRow>> {
        self.db
            .read_all(
                "SELECT * FROM pet_bodies WHERE file_id = ? AND species != -1",
                [file_upload_id],
                read_pet_body,
            )
            .map_err(Into::into)
    }

    pub fn pet_indexed_file_ids(&self, minimum_ml_version: i64) -> Result<HashMap<i64, i64>> {
        self.db
            .read_all(
                "SELECT DISTINCT file_id, ml_version FROM pet_faces WHERE ml_version >= ?",
                [minimum_ml_version],
                pair,
            )
            .map_err(Into::into)
    }

    pub fn get_pet_indexed_file_count(&self, minimum_ml_version: i64) -> Result<i64> {
        self.db
            .read_value(
                "SELECT COUNT(DISTINCT file_id) as count FROM pet_faces WHERE ml_version >= ?",
                [minimum_ml_version],
            )
            .map_err(Into::into)
    }

    pub fn get_pet_rows_for_files(&self, file_ids: &[i64]) -> Result<PetRowsForFiles> {
        let placeholders = bind_placeholders(file_ids.len());
        let faces_sql = format!(
            r#"
            SELECT pet_face_id, face_vector_id, species
            FROM pet_faces
            WHERE file_id IN ({placeholders})
            "#
        );
        let bodies_sql = format!(
            r#"
            SELECT pet_body_id, body_vector_id, species
            FROM pet_bodies
            WHERE file_id IN ({placeholders})
            "#
        );
        let faces = self
            .db
            .read_all(&faces_sql, params_from_iter(file_ids), |row| {
                Ok(PetFaceVectorRow {
                    pet_face_id: row.get(0)?,
                    face_vector_id: row.get(1)?,
                    species: row.get(2)?,
                })
            })?;
        let bodies = self
            .db
            .read_all(&bodies_sql, params_from_iter(file_ids), |row| {
                Ok(PetBodyVectorRow {
                    pet_body_id: row.get(0)?,
                    body_vector_id: row.get(1)?,
                    species: row.get(2)?,
                })
            })?;
        Ok(PetRowsForFiles { faces, bodies })
    }

    pub fn delete_pet_rows_for_files(
        &self,
        file_ids: &[i64],
        pet_face_ids: &[String],
        pet_body_ids: &[String],
    ) -> Result<()> {
        let placeholders = bind_placeholders(file_ids.len());
        self.db
            .write_transaction(|transaction| {
                if !pet_face_ids.is_empty() {
                    transaction.execute(
                        &format!(
                            "DELETE FROM pet_face_vector_id_map WHERE pet_face_id IN ({})",
                            bind_placeholders(pet_face_ids.len())
                        ),
                        params_from_iter(pet_face_ids.iter()),
                    )?;
                }
                if !pet_body_ids.is_empty() {
                    transaction.execute(
                        &format!(
                            "DELETE FROM pet_body_vector_id_map WHERE pet_body_id IN ({})",
                            bind_placeholders(pet_body_ids.len())
                        ),
                        params_from_iter(pet_body_ids.iter()),
                    )?;
                }
                transaction.execute(
                    &format!("DELETE FROM pet_faces WHERE file_id IN ({placeholders})"),
                    params_from_iter(file_ids.iter()),
                )?;
                transaction.execute(
                    &format!("DELETE FROM pet_bodies WHERE file_id IN ({placeholders})"),
                    params_from_iter(file_ids.iter()),
                )?;
                Ok(())
            })
            .map_err(Into::into)
    }

    pub fn get_pet_face_vector_id_map(
        &self,
        pet_face_ids: &[String],
        create_if_missing: bool,
    ) -> Result<HashMap<String, i64>> {
        self.vector_id_map(
            pet_face_ids,
            create_if_missing,
            "INSERT OR IGNORE INTO pet_face_vector_id_map (pet_face_id) VALUES (?)",
            r#"
            SELECT pet_face_id, pet_face_vector_id
            FROM pet_face_vector_id_map
            WHERE pet_face_id IN
            "#,
        )
    }

    pub fn get_pet_body_vector_id_map(
        &self,
        pet_body_ids: &[String],
        create_if_missing: bool,
    ) -> Result<HashMap<String, i64>> {
        self.vector_id_map(
            pet_body_ids,
            create_if_missing,
            "INSERT OR IGNORE INTO pet_body_vector_id_map (pet_body_id) VALUES (?)",
            r#"
            SELECT pet_body_id, pet_body_vector_id
            FROM pet_body_vector_id_map
            WHERE pet_body_id IN
            "#,
        )
    }

    fn vector_id_map(
        &self,
        ids: &[String],
        create_if_missing: bool,
        insert_sql: &str,
        select_prefix: &str,
    ) -> Result<HashMap<String, i64>> {
        let unique_ids = unique_in_order(ids);
        if unique_ids.is_empty() {
            return Ok(HashMap::new());
        }
        if create_if_missing {
            self.db
                .write_batch_atomic(insert_sql, unique_ids.iter().map(|id| [id]))?;
        }
        let select_sql = select_prefix.to_owned() + " ({})";
        self.db
            .read_chunked_in(
                &select_sql,
                &unique_ids,
                const { NonZeroUsize::new(800).unwrap() },
                pair,
            )
            .map_err(Into::into)
    }
}

fn read_pet_face(row: &Row<'_>) -> SqliteResult<PetFaceRow> {
    Ok(PetFaceRow {
        file_id: row.get("file_id")?,
        pet_face_id: row.get("pet_face_id")?,
        detection_json: row.get("detection")?,
        face_vector_id: row.get("face_vector_id")?,
        species: row.get("species")?,
        face_score: row.get("score")?,
        image_height: row.get("height")?,
        image_width: row.get("width")?,
        ml_version: row.get("ml_version")?,
    })
}

fn read_pet_body(row: &Row<'_>) -> SqliteResult<PetBodyRow> {
    Ok(PetBodyRow {
        file_id: row.get("file_id")?,
        pet_body_id: row.get("pet_body_id")?,
        detection_json: row.get("detection")?,
        body_vector_id: row.get("body_vector_id")?,
        species: row.get("species")?,
        score: row.get("score")?,
        image_height: row.get("height")?,
        image_width: row.get("width")?,
        ml_version: row.get("ml_version")?,
    })
}

#[cfg(test)]
pub(in crate::ml_db) mod tests {
    use std::collections::HashMap;

    use super::{MlDb, PetBodyRow, PetFaceRow};
    use crate::ml_db::tests::{cases, check, open, pairs, sorted, strings};
    use tempfile::TempDir;

    pub(in crate::ml_db) fn pet_face(file_id: i64, index: i64, species: i64) -> PetFaceRow {
        PetFaceRow {
            file_id,
            pet_face_id: format!("{file_id}_pet_{index}"),
            detection_json: "{}".to_string(),
            face_vector_id: None,
            species,
            face_score: 0.7,
            image_height: 10,
            image_width: 20,
            ml_version: 1,
        }
    }

    fn pet_body(file_id: i64, index: i64, species: i64) -> PetBodyRow {
        PetBodyRow {
            file_id,
            pet_body_id: format!("{file_id}_body_{index}"),
            detection_json: "{}".to_string(),
            body_vector_id: None,
            species,
            score: 0.6,
            image_height: 10,
            image_width: 20,
            ml_version: 1,
        }
    }

    pub(in crate::ml_db) fn seed(db: &MlDb) {
        db.bulk_insert_pet_faces(&[
            pet_face(1, 0, 0),
            pet_face(1, 1, -1),
            PetFaceRow {
                ml_version: 2,
                ..pet_face(2, 0, 1)
            },
        ])
        .unwrap();
        db.bulk_insert_pet_bodies(&[pet_body(1, 0, 0), pet_body(3, 0, -1)])
            .unwrap();
        let face_vector_ids = db
            .get_pet_face_vector_id_map(&strings(["1_pet_0", "1_pet_1"]), true)
            .unwrap();
        db.update_pet_face_vector_ids(&face_vector_ids).unwrap();
        let body_vector_ids = db
            .get_pet_body_vector_id_map(&strings(["1_body_0"]), true)
            .unwrap();
        db.update_pet_body_vector_ids(&body_vector_ids).unwrap();
    }

    fn seeded() -> (TempDir, MlDb) {
        let (directory, db) = open();
        seed(&db);
        (directory, db)
    }

    #[test]
    fn seeded_counts() {
        let (_directory, db) = seeded();
        check(
            &db,
            &cases![
                "pet files": 2 => |db| db.get_pet_indexed_file_count(1),
                "pet files v2": 1 => |db| db.get_pet_indexed_file_count(2),
            ],
        );
    }

    #[test]
    fn seeded_maps() {
        let (_directory, db) = seeded();
        check(
            &db,
            &cases![
                "pet face vector ids": pairs([("1_pet_0", 1), ("1_pet_1", 2)]) =>
                    |db| db.get_pet_face_vector_id_map(&strings(["1_pet_0", "1_pet_1", "2_pet_0"]), false),
                "pet body vector ids": pairs([("1_body_0", 1)]) =>
                    |db| db.get_pet_body_vector_id_map(&strings(["1_body_0"]), false),
            ],
        );
        check(
            &db,
            &cases![
                "pet versions": HashMap::from([(1, 1), (2, 2)]) => |db| db.pet_indexed_file_ids(1),
                "pet versions v2": HashMap::from([(2, 2)]) => |db| db.pet_indexed_file_ids(2),
            ],
        );
    }

    #[test]
    fn seeded_rows() {
        let (_directory, db) = seeded();
        let linked_pet_face = PetFaceRow {
            face_vector_id: Some(1),
            ..pet_face(1, 0, 0)
        };
        assert_eq!(
            db.get_pet_faces_for_file_id(1).unwrap(),
            vec![linked_pet_face]
        );
        let new_pet_face = PetFaceRow {
            ml_version: 2,
            ..pet_face(2, 0, 1)
        };
        assert_eq!(db.get_pet_faces_for_file_id(2).unwrap(), vec![new_pet_face]);
        assert!(db.get_pet_faces_for_file_id(9).unwrap().is_empty());
        let linked_pet_body = PetBodyRow {
            body_vector_id: Some(1),
            ..pet_body(1, 0, 0)
        };
        assert_eq!(
            db.get_pet_bodies_for_file_id(1).unwrap(),
            vec![linked_pet_body]
        );
        assert!(db.get_pet_bodies_for_file_id(3).unwrap().is_empty());

        let rows = db.get_pet_rows_for_files(&[1, 3]).unwrap();
        let faces: Vec<(&str, Option<i64>, i64)> = rows
            .faces
            .iter()
            .map(|row| (row.pet_face_id.as_str(), row.face_vector_id, row.species))
            .collect();
        assert_eq!(
            sorted(faces),
            [("1_pet_0", Some(1), 0), ("1_pet_1", Some(2), -1)]
        );
        let bodies: Vec<(&str, Option<i64>, i64)> = rows
            .bodies
            .iter()
            .map(|row| (row.pet_body_id.as_str(), row.body_vector_id, row.species))
            .collect();
        assert_eq!(
            sorted(bodies),
            [("1_body_0", Some(1), 0), ("3_body_0", None, -1)]
        );
    }

    #[test]
    fn pet_upsert_vector_ids_and_deletion() {
        let (_directory, db) = seeded();
        let updated = PetFaceRow {
            face_score: 0.99,
            ..pet_face(2, 0, 1)
        };
        db.bulk_insert_pet_faces(std::slice::from_ref(&updated))
            .unwrap();
        assert_eq!(db.get_pet_faces_for_file_id(2).unwrap(), vec![updated]);
        db.bulk_insert_pet_bodies(&[pet_body(2, 0, 1)]).unwrap();
        assert_eq!(
            db.get_pet_bodies_for_file_id(2).unwrap(),
            vec![pet_body(2, 0, 1)]
        );

        let face_vector_ids = db
            .get_pet_face_vector_id_map(&strings(["2_pet_0", "1_pet_0", "2_pet_0"]), true)
            .unwrap();
        assert_eq!(face_vector_ids, pairs([("1_pet_0", 1), ("2_pet_0", 3)]));
        assert_eq!(
            db.get_pet_body_vector_id_map(&strings(["2_body_0"]), true)
                .unwrap(),
            pairs([("2_body_0", 2)])
        );
        db.update_pet_face_vector_ids(&HashMap::new()).unwrap();
        db.update_pet_body_vector_ids(&HashMap::new()).unwrap();
        db.update_pet_face_vector_ids(&face_vector_ids).unwrap();
        assert_eq!(
            db.get_pet_faces_for_file_id(2).unwrap()[0].face_vector_id,
            Some(3)
        );

        db.delete_pet_rows_for_files(
            &[1],
            &strings(["1_pet_0", "1_pet_1"]),
            &strings(["1_body_0"]),
        )
        .unwrap();
        assert!(db.get_pet_faces_for_file_id(1).unwrap().is_empty());
        assert!(db.get_pet_bodies_for_file_id(1).unwrap().is_empty());
        assert!(
            db.get_pet_face_vector_id_map(&strings(["1_pet_0", "1_pet_1"]), false)
                .unwrap()
                .is_empty()
        );
        assert!(
            db.get_pet_body_vector_id_map(&strings(["1_body_0"]), false)
                .unwrap()
                .is_empty()
        );
        db.delete_pet_rows_for_files(&[2], &[], &[]).unwrap();
        assert!(db.get_pet_faces_for_file_id(2).unwrap().is_empty());
        assert!(db.get_pet_bodies_for_file_id(2).unwrap().is_empty());
        assert_eq!(
            db.get_pet_face_vector_id_map(&strings(["2_pet_0"]), false)
                .unwrap(),
            pairs([("2_pet_0", 3)])
        );

        db.clear_pet_tables().unwrap();
        assert!(
            db.get_pet_face_vector_id_map(&strings(["2_pet_0"]), false)
                .unwrap()
                .is_empty()
        );
        assert_eq!(db.get_pet_indexed_file_count(0).unwrap(), 0);
    }
}
