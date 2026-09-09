use std::collections::{HashMap, HashSet};
use std::num::NonZeroUsize;

use crate::db::{
    MAX_SQL_BIND_PARAMS_PER_QUERY, Row, SqliteResult, ToSql, bind_placeholders, group_into,
    optional_parameter, pair, params_from_iter,
};

use super::clip::CLIP_ML_VERSION;
use super::pets::PET_ML_VERSION;
use super::{limit_clause, unique_in_order};
use crate::ml_db::vector_encoding::{decode_evector, encode_evector};
use crate::ml_db::{Error, MlDb, Result};

pub const FACE_ML_VERSION: i64 = 1;

pub const LAPLACIAN_HARD_THRESHOLD: f64 = 10.0;
pub const LAPLACIAN_SOFT_THRESHOLD: f64 = 50.0;
pub const LAPLACIAN_VERY_SOFT_THRESHOLD: f64 = 200.0;
pub const MINIMUM_QUALITY_FACE_SCORE: f64 = 0.80;
pub const MEDIUM_QUALITY_FACE_SCORE: f64 = 0.85;

#[derive(Clone, Debug, PartialEq)]
pub struct FaceRow {
    pub file_id: i64,
    pub face_id: String,
    pub detection_json: String,
    pub embedding: Vec<f64>,
    pub score: f64,
    pub blur: f64,
    pub is_sideways: bool,
    pub image_height: i64,
    pub image_width: i64,
    pub ml_version: i64,
}

#[derive(Clone, Debug, PartialEq)]
pub struct FaceWithoutEmbedding {
    pub face_id: String,
    pub file_id: i64,
    pub score: f64,
    pub detection_json: String,
    pub blur: f64,
}

#[derive(Clone, Debug, PartialEq)]
pub struct FaceDbInfoForClustering {
    pub face_id: String,
    pub cluster_id: Option<String>,
    pub embedding_bytes: Vec<u8>,
    pub face_score: f64,
    pub blur_value: f64,
    pub is_sideways: bool,
}

const FACE_EMBEDDING_MAX_ROWS: usize = 20000;

const UPSERT_FACE: &str = r#"
    INSERT INTO faces (
        file_id, face_id, detection, embedding, score, blur,
        is_sideways, height, width, ml_version
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT (file_id, face_id) DO UPDATE SET
        face_id = excluded.face_id,
        detection = excluded.detection,
        embedding = excluded.embedding,
        score = excluded.score,
        blur = excluded.blur,
        is_sideways = excluded.is_sideways,
        height = excluded.height,
        width = excluded.width,
        ml_version = excluded.ml_version
"#;

impl MlDb {
    pub fn bulk_insert_faces(&self, faces: &[FaceRow]) -> Result<()> {
        self.db
            .write_batches_committing_each(
                UPSERT_FACE,
                const { NonZeroUsize::new(500).unwrap() },
                faces.iter().map(|face| {
                    (
                        face.file_id,
                        &face.face_id,
                        &face.detection_json,
                        encode_evector(&face.embedding),
                        face.score,
                        face.blur,
                        face.is_sideways,
                        face.image_height,
                        face.image_width,
                        face.ml_version,
                    )
                }),
            )
            .map_err(Into::into)
    }

    pub fn face_indexed_file_ids(&self, minimum_ml_version: i64) -> Result<HashMap<i64, i64>> {
        self.db
            .read_all(
                "SELECT file_id, ml_version FROM faces WHERE ml_version >= ?",
                [minimum_ml_version],
                pair,
            )
            .map_err(Into::into)
    }

    pub fn get_face_indexed_file_count(&self, minimum_ml_version: i64) -> Result<i64> {
        self.db
            .read_value(
                "SELECT COUNT(DISTINCT file_id) as count FROM faces WHERE ml_version >= ?",
                [minimum_ml_version],
            )
            .map_err(Into::into)
    }

    pub fn get_face_embeddings_for_cluster(
        &self,
        cluster_id: &str,
        limit: Option<i64>,
    ) -> Result<Vec<Vec<u8>>> {
        let sql = format!(
            r#"
            SELECT embedding
            FROM faces
            WHERE face_id in (
                SELECT face_id
                from face_clusters
                where cluster_id = ?
            ) {}
            "#,
            limit_clause(limit)
        );
        let mut parameters: Vec<&dyn ToSql> = vec![&cluster_id];
        parameters.extend(optional_parameter(&limit));
        self.db
            .read_column(&sql, parameters.as_slice())
            .map_err(Into::into)
    }

    pub fn get_face_embeddings_for_clusters(
        &self,
        cluster_ids: &[String],
        limit: Option<i64>,
    ) -> Result<HashMap<String, Vec<Vec<u8>>>> {
        if cluster_ids.is_empty() {
            return Ok(HashMap::new());
        }
        let unique_cluster_ids = unique_in_order(cluster_ids);
        let max_cluster_ids_per_query = if limit.is_some() {
            MAX_SQL_BIND_PARAMS_PER_QUERY - 1
        } else {
            MAX_SQL_BIND_PARAMS_PER_QUERY
        };
        let mut remaining_limit = limit;
        let mut result: HashMap<String, Vec<Vec<u8>>> = HashMap::new();
        for cluster_chunk in unique_cluster_ids.chunks(max_cluster_ids_per_query) {
            if remaining_limit.is_some_and(|remaining| remaining <= 0) {
                break;
            }
            let sql = format!(
                r#"
                SELECT fc.cluster_id, fe.embedding
                FROM face_clusters fc
                INNER JOIN faces fe
                    ON fc.face_id = fe.face_id
                WHERE fc.cluster_id IN ({}) {}
                "#,
                bind_placeholders(cluster_chunk.len()),
                limit_clause(remaining_limit)
            );
            let mut parameters: Vec<&dyn ToSql> =
                cluster_chunk.iter().map(|id| id as &dyn ToSql).collect();
            parameters.extend(optional_parameter(&remaining_limit));
            let rows: Vec<(String, Vec<u8>)> =
                self.db.read_all(&sql, parameters.as_slice(), pair)?;
            if let Some(remaining) = remaining_limit.as_mut() {
                *remaining -= rows.len() as i64;
            }
            for (cluster_id, embedding) in rows {
                result.entry(cluster_id).or_default().push(embedding);
            }
        }
        Ok(result)
    }

    pub fn get_cover_face_for_person(
        &self,
        recent_file_id: i64,
        person_id: Option<&str>,
        avatar_face_id: Option<&str>,
        cluster_id: Option<&str>,
    ) -> Result<Option<FaceRow>> {
        if let Some(person_id) = person_id {
            let mut file_ids = vec![recent_file_id];
            let avatar_file_id = avatar_face_id.and_then(try_file_id_from_face_id);
            if let Some(avatar_file_id) = avatar_file_id {
                file_ids.push(avatar_file_id);
            }
            let cluster_ids: Vec<String> = self.db.read_column(
                "SELECT cluster_id FROM cluster_person WHERE person_id = ?",
                [person_id],
            )?;
            let sql = format!(
                r#"
                SELECT *
                FROM faces
                WHERE face_id IN (
                    SELECT face_id
                    FROM face_clusters
                    WHERE cluster_id IN ({})
                )
                    AND file_id IN ({})
                ORDER BY score DESC
                "#,
                bind_placeholders(cluster_ids.len()),
                bind_placeholders(file_ids.len())
            );
            let mut parameters: Vec<&dyn ToSql> =
                cluster_ids.iter().map(|id| id as &dyn ToSql).collect();
            parameters.extend(file_ids.iter().map(|id| id as &dyn ToSql));
            let faces: Vec<StoredFace> =
                self.db
                    .read_all(&sql, parameters.as_slice(), read_stored_face)?;
            if !faces.is_empty() {
                if let Some(avatar_file_id) = avatar_file_id
                    && let Some(face) = faces.iter().find(|face| face.row.file_id == avatar_file_id)
                {
                    return face.clone().decode().map(Some);
                }
                return faces[0].clone().decode().map(Some);
            }
        }
        if let Some(cluster_id) = cluster_id {
            let face_ids: Vec<String> = self.db.read_column(
                "SELECT face_id FROM face_clusters WHERE cluster_id = ?",
                [cluster_id],
            )?;
            for face in self.get_faces_for_given_file_id(recent_file_id)? {
                if face_ids.contains(&face.face_id) {
                    return Ok(Some(face));
                }
            }
        }
        if person_id.is_none() && cluster_id.is_none() {
            return Err(Error::InvalidArgument(
                "personID and clusterID cannot be null".to_string(),
            ));
        }
        Ok(None)
    }

    pub fn get_faces_for_given_file_id(&self, file_upload_id: i64) -> Result<Vec<FaceRow>> {
        let faces: Vec<StoredFace> = self.db.read_all(
            "SELECT * FROM faces WHERE file_id = ?",
            [file_upload_id],
            read_stored_face,
        )?;
        faces.into_iter().map(StoredFace::decode).collect()
    }

    pub fn get_file_ids_to_faces_without_embedding(
        &self,
    ) -> Result<HashMap<i64, Vec<FaceWithoutEmbedding>>> {
        let faces: Vec<FaceWithoutEmbedding> = self.db.read_all(
            "SELECT face_id, file_id, score, detection, blur FROM faces",
            (),
            |row| {
                Ok(FaceWithoutEmbedding {
                    face_id: row.get(0)?,
                    file_id: row.get(1)?,
                    score: row.get(2)?,
                    detection_json: row.get(3)?,
                    blur: row.get(4)?,
                })
            },
        )?;
        Ok(group_into(
            faces.into_iter().map(|face| (face.file_id, face)),
        ))
    }

    pub fn get_face_info_for_clustering(
        &self,
        max_faces: i64,
        offset: i64,
        batch_size: i64,
    ) -> Result<Vec<FaceDbInfoForClustering>> {
        let mut offset = offset;
        let mut result = Vec::new();
        loop {
            let rows: Vec<(String, Vec<u8>, f64, f64, i64)> = self.db.read_all(
                r#"
                SELECT face_id, embedding, score, blur, is_sideways
                FROM faces
                WHERE score > ?
                    AND blur > ?
                ORDER BY face_id DESC
                LIMIT ?
                OFFSET ?
                "#,
                (
                    MINIMUM_QUALITY_FACE_SCORE,
                    LAPLACIAN_HARD_THRESHOLD,
                    batch_size,
                    offset,
                ),
                |row| {
                    Ok((
                        row.get(0)?,
                        row.get(1)?,
                        row.get(2)?,
                        row.get(3)?,
                        row.get(4)?,
                    ))
                },
            )?;
            if rows.is_empty() {
                break;
            }
            let face_ids: Vec<String> = rows.iter().map(|row| row.0.clone()).collect();
            let face_id_to_cluster_id = self.get_face_ids_to_cluster_ids(&face_ids)?;
            for (face_id, embedding_bytes, face_score, blur_value, is_sideways) in rows {
                let cluster_id = face_id_to_cluster_id.get(&face_id).cloned().flatten();
                result.push(FaceDbInfoForClustering {
                    face_id,
                    cluster_id,
                    embedding_bytes,
                    face_score,
                    blur_value,
                    is_sideways: is_sideways == 1,
                });
            }
            if result.len() as i64 >= max_faces {
                break;
            }
            offset += batch_size;
        }
        Ok(result)
    }

    pub fn get_face_embedding_rows_for_faces(
        &self,
        face_ids: &[String],
    ) -> Result<Vec<(String, Vec<u8>)>> {
        let mut face_ids: Vec<&str> = face_ids.iter().map(String::as_str).collect();
        face_ids.sort_unstable_by(|left, right| right.cmp(left));
        face_ids.dedup();

        let mut result = Vec::new();
        for chunk in face_ids.chunks(MAX_SQL_BIND_PARAMS_PER_QUERY - 1) {
            let remaining_limit = (FACE_EMBEDDING_MAX_ROWS - result.len()) as i64;
            if remaining_limit == 0 {
                break;
            }
            let sql = format!(
                r#"
                SELECT face_id, embedding
                FROM faces
                WHERE face_id IN ({})
                ORDER BY face_id DESC
                LIMIT ?
                "#,
                bind_placeholders(chunk.len())
            );
            let mut parameters: Vec<&dyn ToSql> = chunk.iter().map(|id| id as &dyn ToSql).collect();
            parameters.push(&remaining_limit);
            let rows: Vec<(String, Vec<u8>)> =
                self.db.read_all(&sql, parameters.as_slice(), pair)?;
            result.extend(rows);
        }
        Ok(result)
    }

    pub fn get_total_face_count(&self) -> Result<i64> {
        self.db
            .read_value(
                "SELECT COUNT(*) as count FROM faces WHERE score > ? AND blur > ?",
                (MINIMUM_QUALITY_FACE_SCORE, LAPLACIAN_HARD_THRESHOLD),
            )
            .map_err(Into::into)
    }

    pub fn get_errored_face_count(&self) -> Result<i64> {
        self.db
            .read_value("SELECT COUNT(*) as count FROM faces WHERE score < 0", ())
            .map_err(Into::into)
    }

    pub fn get_errored_file_ids(&self) -> Result<HashSet<i64>> {
        self.db
            .read_column("SELECT DISTINCT file_id FROM faces WHERE score < 0", ())
            .map_err(Into::into)
    }

    pub fn prune_resolved_face_error_results(&self, file_ids: &[i64]) -> Result<()> {
        if file_ids.is_empty() {
            return Ok(());
        }
        self.db
            .execute_chunked_in(
                r#"
                DELETE FROM faces
                WHERE file_id IN ({})
                    AND score < 0
                    AND EXISTS (
                        SELECT 1
                        FROM faces AS successful
                        WHERE successful.file_id = faces.file_id
                            AND successful.score >= 0
                            AND successful.ml_version >= faces.ml_version
                    )
                "#,
                file_ids,
            )
            .map_err(Into::into)
    }

    pub fn get_file_ids_with_error_results(&self, file_ids: &[i64]) -> Result<HashSet<i64>> {
        if file_ids.is_empty() {
            return Ok(HashSet::new());
        }
        let mut result = HashSet::new();
        for chunk in file_ids.chunks(MAX_SQL_BIND_PARAMS_PER_QUERY / 3) {
            let placeholders = bind_placeholders(chunk.len());
            let sql = format!(
                r#"
                SELECT failed.file_id
                FROM faces AS failed
                WHERE failed.file_id IN ({placeholders})
                    AND failed.score < 0
                    AND NOT EXISTS (
                        SELECT 1
                        FROM faces AS successful
                        WHERE successful.file_id = failed.file_id
                            AND successful.score >= 0
                            AND successful.ml_version >= failed.ml_version
                    )
                UNION
                SELECT file_id
                FROM clip
                WHERE file_id IN ({placeholders})
                    AND LENGTH(embedding) = 0
                UNION
                SELECT file_id
                FROM pet_faces
                WHERE file_id IN ({placeholders})
                    AND score < 0
                "#
            );
            let matches: Vec<i64> = self.db.read_column(
                &sql,
                params_from_iter(chunk.iter().chain(chunk).chain(chunk)),
            )?;
            result.extend(matches);
        }
        Ok(result)
    }

    pub fn delete_face_index_for_files(&self, file_ids: &[i64]) -> Result<()> {
        self.db
            .execute_chunked_in("DELETE FROM faces WHERE file_id IN ({})", file_ids)
            .map_err(Into::into)
    }

    pub fn delete_unclustered_face_index_for_files(&self, file_ids: &[i64]) -> Result<()> {
        if file_ids.is_empty() {
            return Ok(());
        }
        self.db
            .execute_chunked_in(
                r#"
                DELETE FROM faces
                WHERE file_id IN ({})
                    AND NOT EXISTS (
                        SELECT 1
                        FROM face_clusters
                        WHERE face_clusters.face_id = faces.face_id
                    )
                "#,
                file_ids,
            )
            .map_err(Into::into)
    }

    pub fn get_clustered_or_faceless_file_count(&self) -> Result<i64> {
        let clustered_face_ids: Vec<String> = self
            .db
            .read_column("SELECT face_id FROM face_clusters", ())?;
        let clustered_file_ids = clustered_face_ids
            .iter()
            .map(|face_id| file_id_from_face_id(face_id))
            .collect::<Result<HashSet<i64>>>()?;

        let bad_file_ids: HashSet<i64> = self.db.read_column(
            "SELECT DISTINCT file_id FROM faces WHERE score <= ? OR blur <= ?",
            (MINIMUM_QUALITY_FACE_SCORE, LAPLACIAN_HARD_THRESHOLD),
        )?;
        let good_file_ids: HashSet<i64> = self.db.read_column(
            "SELECT DISTINCT file_id FROM faces WHERE score > ? AND blur > ?",
            (MINIMUM_QUALITY_FACE_SCORE, LAPLACIAN_HARD_THRESHOLD),
        )?;
        let truly_faceless_files = bad_file_ids.difference(&good_file_ids).count();
        Ok((clustered_file_ids.len() + truly_faceless_files) as i64)
    }

    pub fn get_unclustered_face_count(&self) -> Result<i64> {
        self.db
            .read_value(
                r#"
                SELECT COUNT(*) as count
                FROM faces f
                LEFT JOIN face_clusters fc
                    ON f.face_id = fc.face_id
                WHERE f.score > ?
                    AND f.blur > ?
                    AND fc.face_id IS NULL
                "#,
                (MINIMUM_QUALITY_FACE_SCORE, LAPLACIAN_HARD_THRESHOLD),
            )
            .map_err(Into::into)
    }

    pub fn get_all_file_ids_of_face_ids_not_in_any_cluster(&self) -> Result<HashSet<i64>> {
        self.db
            .read_column(
                r#"
                SELECT DISTINCT file_id
                FROM faces
                LEFT JOIN face_clusters
                    ON faces.face_id = face_clusters.face_id
                WHERE face_clusters.face_id IS NULL
                "#,
                (),
            )
            .map_err(Into::into)
    }

    pub fn get_all_files_associated_with_all_clusters(
        &self,
        except_clusters: Option<&[String]>,
    ) -> Result<HashSet<i64>> {
        let except_clusters = except_clusters.unwrap_or_default();
        let sql = format!(
            r#"
            SELECT DISTINCT faces.file_id
            FROM faces
            JOIN face_clusters
                on face_clusters.face_id = faces.face_id
            WHERE face_clusters.cluster_id NOT IN ({})
            "#,
            bind_placeholders(except_clusters.len())
        );
        self.db
            .read_column(&sql, params_from_iter(except_clusters))
            .map_err(Into::into)
    }

    pub fn get_fully_indexed_file_ids(&self, include_pets: bool) -> Result<HashSet<i64>> {
        let mut sql = String::from(
            r#"
            SELECT file_id
            FROM faces
            WHERE ml_version >= ?
            INTERSECT
            SELECT file_id
            FROM clip
            WHERE ml_version >= ?
            "#,
        );
        let mut parameters = vec![FACE_ML_VERSION, CLIP_ML_VERSION];
        if include_pets {
            sql.push_str(" INTERSECT SELECT file_id FROM pet_faces WHERE ml_version >= ?");
            parameters.push(PET_ML_VERSION);
        }
        self.db
            .read_column(&sql, params_from_iter(parameters))
            .map_err(Into::into)
    }
}

pub fn is_bad_face_for_clustering(face_score: f64, blur_value: f64, is_sideways: bool) -> bool {
    face_score < MINIMUM_QUALITY_FACE_SCORE
        || blur_value < LAPLACIAN_SOFT_THRESHOLD
        || (blur_value < LAPLACIAN_VERY_SOFT_THRESHOLD && face_score < MEDIUM_QUALITY_FACE_SCORE)
        || is_sideways
}

pub(super) fn file_id_from_face_id(face_id: &str) -> Result<i64> {
    try_file_id_from_face_id(face_id)
        .ok_or_else(|| Error::Codec(format!("Error parsing faceId: {face_id}")))
}

fn try_file_id_from_face_id(face_id: &str) -> Option<i64> {
    face_id
        .split_once('_')
        .and_then(|(file_id, _)| file_id.parse().ok())
}

#[derive(Clone)]
struct StoredFace {
    row: FaceRow,
    embedding_bytes: Vec<u8>,
}

impl StoredFace {
    fn decode(mut self) -> Result<FaceRow> {
        self.row.embedding = decode_evector(&self.embedding_bytes)?;
        Ok(self.row)
    }
}

fn read_stored_face(row: &Row<'_>) -> SqliteResult<StoredFace> {
    Ok(StoredFace {
        row: FaceRow {
            file_id: row.get("file_id")?,
            face_id: row.get("face_id")?,
            detection_json: row.get("detection")?,
            embedding: Vec::new(),
            score: row.get("score")?,
            blur: row.get("blur")?,
            is_sideways: row.get::<_, i64>("is_sideways")? == 1,
            image_height: row.get("height")?,
            image_width: row.get("width")?,
            ml_version: row.get("ml_version")?,
        },
        embedding_bytes: row.get("embedding")?,
    })
}

#[cfg(test)]
pub(in crate::ml_db) mod tests {
    use std::collections::HashMap;
    use std::ops::RangeInclusive;

    use super::{FaceRow, MlDb};
    use crate::ml_db::queries::{clip, clusters, persons, pets};
    use crate::ml_db::tests::{cases, check, ids, open, sorted, strings};
    use crate::ml_db::vector_encoding::encode_evector;
    use crate::ml_db::{Error, PetFaceRow};
    use tempfile::TempDir;

    fn face(file_id: i64, index: i64, score: f64, blur: f64, is_sideways: bool) -> FaceRow {
        FaceRow {
            file_id,
            face_id: format!("{file_id}_{index}"),
            detection_json: format!("{{\"index\":{index}}}"),
            embedding: vec![file_id as f64, index as f64, 0.5],
            score,
            blur,
            is_sideways,
            image_height: 100,
            image_width: 200,
            ml_version: 1,
        }
    }

    fn good_face(file_id: i64, index: i64) -> FaceRow {
        face(file_id, index, 0.9, 300.0, false)
    }

    fn versions(file_ids: RangeInclusive<i64>, version: i64) -> HashMap<i64, i64> {
        file_ids.map(|file_id| (file_id, version)).collect()
    }

    pub(in crate::ml_db) fn seed(db: &MlDb) {
        db.bulk_insert_faces(&[
            good_face(1, 0),
            face(1, 1, 0.95, 300.0, false),
            face(2, 0, 0.85, 300.0, false),
            face(3, 0, 0.95, 300.0, false),
            face(4, 0, 0.5, 300.0, false),
            face(5, 0, -1.0, 300.0, false),
            face(6, 0, 0.9, 5.0, false),
            good_face(6, 1),
            face(7, 0, 0.9, 300.0, true),
            face(8, 0, 0.82, 150.0, false),
            face(9, 0, 0.9, 20.0, false),
            FaceRow {
                ml_version: 0,
                ..good_face(10, 0)
            },
        ])
        .unwrap();
    }

    fn seeded() -> (TempDir, MlDb) {
        let (directory, db) = open();
        clip::tests::seed(&db);
        seed(&db);
        clusters::tests::seed(&db);
        persons::tests::seed(&db);
        pets::tests::seed(&db);
        (directory, db)
    }

    #[test]
    fn seeded_counts() {
        let (_directory, db) = seeded();
        check(
            &db,
            &cases![
                "total faces": 9 => |db| db.get_total_face_count(),
                "errored faces": 1 => |db| db.get_errored_face_count(),
                "face files": 9 => |db| db.get_face_indexed_file_count(1),
                "face files v0": 10 => |db| db.get_face_indexed_file_count(0),
                "unclustered faces": 2 => |db| db.get_unclustered_face_count(),
                "clustered or faceless files": 8 => |db| db.get_clustered_or_faceless_file_count(),
            ],
        );
    }

    #[test]
    fn seeded_file_id_sets() {
        let (_directory, db) = seeded();
        check(
            &db,
            &cases![
                "errored": ids([5]) => |db| db.get_errored_file_ids(),
                "fully indexed": ids([1, 2, 3, 4]) => |db| db.get_fully_indexed_file_ids(false),
                "fully indexed with pets": ids([1, 2]) => |db| db.get_fully_indexed_file_ids(true),
                "unclustered": ids([4, 5, 6, 10]) =>
                    |db| db.get_all_file_ids_of_face_ids_not_in_any_cluster(),
                "clustered": ids([1, 2, 3, 7, 8, 9]) =>
                    |db| db.get_all_files_associated_with_all_clusters(None),
                "clustered except c1": ids([1, 3, 7, 8, 9]) =>
                    |db| db.get_all_files_associated_with_all_clusters(Some(&strings(["c1"]))),
            ],
        );
    }

    #[test]
    fn seeded_versions() {
        let (_directory, db) = seeded();
        check(
            &db,
            &cases![
                "face versions": versions(1..=9, 1) => |db| db.face_indexed_file_ids(1),
                "face versions v0": versions(1..=9, 1).into_iter().chain([(10, 0)]).collect() =>
                    |db| db.face_indexed_file_ids(0),
            ],
        );
    }

    #[test]
    fn seeded_rows() {
        let (_directory, db) = seeded();
        let mut faces = db.get_faces_for_given_file_id(1).unwrap();
        faces.sort_by(|left, right| left.face_id.cmp(&right.face_id));
        assert_eq!(faces, vec![good_face(1, 0), face(1, 1, 0.95, 300.0, false)]);
        assert!(db.get_faces_for_given_file_id(99).unwrap().is_empty());

        let without_embedding = db.get_file_ids_to_faces_without_embedding().unwrap();
        assert_eq!(without_embedding.len(), 10);
        assert_eq!(without_embedding[&6].len(), 2);
        let blurry = without_embedding[&6]
            .iter()
            .find(|face| face.face_id == "6_0")
            .unwrap();
        assert_eq!((blurry.file_id, blurry.score, blurry.blur), (6, 0.9, 5.0));
        assert_eq!(blurry.detection_json, "{\"index\":0}");
    }

    #[test]
    fn face_embeddings_by_cluster_and_face() {
        let (_directory, db) = seeded();
        let c1 = db.get_face_embeddings_for_cluster("c1", None).unwrap();
        assert_eq!(
            sorted(c1),
            sorted(vec![
                encode_evector(&[1.0, 0.0, 0.5]),
                encode_evector(&[2.0, 0.0, 0.5])
            ])
        );
        assert_eq!(
            db.get_face_embeddings_for_cluster("c1", Some(1))
                .unwrap()
                .len(),
            1
        );

        let all = db
            .get_face_embeddings_for_clusters(&strings(["c1", "c2", "c1"]), None)
            .unwrap();
        assert_eq!(all["c1"].len(), 2);
        assert_eq!(all["c2"], vec![encode_evector(&[1.0, 1.0, 0.5])]);
        let limited = db
            .get_face_embeddings_for_clusters(&strings(["c1", "c2"]), Some(2))
            .unwrap();
        assert_eq!(limited.values().map(Vec::len).sum::<usize>(), 2);
        assert!(
            db.get_face_embeddings_for_clusters(&[], Some(2))
                .unwrap()
                .is_empty()
        );

        assert_eq!(
            db.get_face_embedding_rows_for_faces(&strings(["1_0", "2_0", "1_1", "1_0", "nope"]))
                .unwrap(),
            vec![
                ("2_0".to_string(), encode_evector(&[2.0, 0.0, 0.5])),
                ("1_1".to_string(), encode_evector(&[1.0, 1.0, 0.5])),
                ("1_0".to_string(), encode_evector(&[1.0, 0.0, 0.5])),
            ]
        );
        assert!(
            db.get_face_embedding_rows_for_faces(&[])
                .unwrap()
                .is_empty()
        );
    }

    #[test]
    fn face_info_for_clustering_filters_and_pages() {
        let (_directory, db) = seeded();
        let info = db.get_face_info_for_clustering(20000, 0, 3).unwrap();
        let ids: Vec<&str> = info.iter().map(|face| face.face_id.as_str()).collect();
        assert_eq!(
            ids,
            [
                "9_0", "8_0", "7_0", "6_1", "3_0", "2_0", "1_1", "1_0", "10_0"
            ]
        );
        assert_eq!(info[0].cluster_id, Some("c9".to_string()));
        assert_eq!(info[0].embedding_bytes, encode_evector(&[9.0, 0.0, 0.5]));
        assert_eq!(
            (info[0].face_score, info[0].blur_value, info[0].is_sideways),
            (0.9, 20.0, false)
        );
        assert!(info[2].is_sideways);
        assert_eq!(info[3].cluster_id, None);

        assert_eq!(db.get_face_info_for_clustering(3, 0, 3).unwrap().len(), 3);
        let last_page = db.get_face_info_for_clustering(20000, 6, 3).unwrap();
        let last_ids: Vec<&str> = last_page.iter().map(|face| face.face_id.as_str()).collect();
        assert_eq!(last_ids, ["1_1", "1_0", "10_0"]);
        assert!(
            db.get_face_info_for_clustering(20000, 9, 3)
                .unwrap()
                .is_empty()
        );
    }

    #[test]
    fn face_embedding_rows_keep_twenty_thousand_highest_face_ids_in_order() {
        let (_directory, db) = open();
        let faces: Vec<FaceRow> = (0..20005).map(|index| good_face(index, 0)).collect();
        db.bulk_insert_faces(&faces).unwrap();
        assert_eq!(db.get_total_face_count().unwrap(), 20005);
        let mut face_ids: Vec<String> = faces.iter().map(|face| face.face_id.clone()).collect();
        face_ids.rotate_left(1337);

        let embeddings = db.get_face_embedding_rows_for_faces(&face_ids).unwrap();
        assert_eq!(embeddings.len(), 20000);
        face_ids.sort();
        assert_eq!(
            embeddings
                .iter()
                .map(|(face_id, _)| face_id)
                .collect::<Vec<_>>(),
            face_ids[5..].iter().rev().collect::<Vec<_>>()
        );
        let expected = embeddings;

        let mut with_duplicates = face_ids[5..].to_vec();
        with_duplicates.extend(face_ids[5..10].iter().cloned());
        assert_eq!(
            db.get_face_embedding_rows_for_faces(&with_duplicates)
                .unwrap(),
            expected
        );

        let mut with_missing = face_ids.clone();
        with_missing.extend((0..20000).map(|index| format!("missing_{index}")));
        with_missing.extend(face_ids.iter().cloned());
        with_missing.reverse();
        assert_eq!(
            db.get_face_embedding_rows_for_faces(&with_missing).unwrap(),
            expected
        );

        for count in [9998, 9999, 10000, 19999, 20000, 20001] {
            let embeddings = db
                .get_face_embedding_rows_for_faces(&face_ids[..count])
                .unwrap();
            assert_eq!(
                embeddings
                    .iter()
                    .map(|(face_id, _)| face_id)
                    .collect::<Vec<_>>(),
                face_ids[..count]
                    .iter()
                    .rev()
                    .take(20000)
                    .collect::<Vec<_>>()
            );
        }
    }

    #[test]
    fn cover_face_for_person_prefers_avatar_then_score() {
        let (_directory, db) = seeded();
        let cover = |recent_file_id, person_id, avatar_face_id, cluster_id| {
            db.get_cover_face_for_person(recent_file_id, person_id, avatar_face_id, cluster_id)
                .unwrap()
                .map(|face| face.face_id)
        };
        let by_score = db
            .get_cover_face_for_person(2, Some("p1"), None, None)
            .unwrap()
            .unwrap();
        assert_eq!(by_score, face(2, 0, 0.85, 300.0, false));
        assert_eq!(
            cover(2, Some("p1"), Some("1_1"), None),
            Some("1_1".to_string())
        );
        assert_eq!(
            cover(2, Some("p1"), Some("9_0"), None),
            Some("2_0".to_string())
        );
        assert_eq!(
            cover(3, Some("p1"), None, Some("c3")),
            Some("3_0".to_string())
        );
        assert_eq!(cover(1, None, None, Some("c1")), Some("1_0".to_string()));
        assert_eq!(cover(1, None, None, Some("c3")), None);
        assert_eq!(cover(9, Some("p9"), None, None), None);
        assert!(matches!(
            db.get_cover_face_for_person(1, None, None, None),
            Err(Error::InvalidArgument(_))
        ));
    }

    #[test]
    fn face_upsert_and_deletion() {
        let (_directory, db) = seeded();
        let updated = FaceRow {
            score: 0.99,
            embedding: vec![9.0, 8.0],
            ..good_face(1, 0)
        };
        db.bulk_insert_faces(std::slice::from_ref(&updated))
            .unwrap();
        let faces = db.get_faces_for_given_file_id(1).unwrap();
        assert_eq!(faces.len(), 2);
        assert_eq!(
            faces.iter().find(|face| face.face_id == "1_0"),
            Some(&updated)
        );
        assert_eq!(db.get_total_face_count().unwrap(), 9);

        db.delete_unclustered_face_index_for_files(&[]).unwrap();
        db.delete_unclustered_face_index_for_files(&[1, 6]).unwrap();
        assert_eq!(db.get_faces_for_given_file_id(1).unwrap().len(), 2);
        assert!(db.get_faces_for_given_file_id(6).unwrap().is_empty());

        db.delete_face_index_for_files(&[]).unwrap();
        db.delete_face_index_for_files(&[1, 2]).unwrap();
        assert_eq!(db.get_face_indexed_file_count(1).unwrap(), 6);
        assert!(db.get_faces_for_given_file_id(1).unwrap().is_empty());
    }

    #[test]
    fn error_results_lookup_and_prune() {
        let (_directory, db) = seeded();
        db.bulk_insert_faces(&[
            face(11, 0, -1.0, 300.0, false),
            good_face(11, 1),
            FaceRow {
                ml_version: 2,
                ..face(12, 0, -1.0, 300.0, false)
            },
            good_face(12, 1),
        ])
        .unwrap();
        db.bulk_insert_pet_faces(&[PetFaceRow {
            face_score: -1.0,
            ..pets::tests::pet_face(13, 0, 0)
        }])
        .unwrap();
        let file_ids: Vec<i64> = (1..=13).chain([99]).collect();
        let many: Vec<i64> = (0..=10000).collect();
        assert_eq!(db.get_file_ids_with_error_results(&[]).unwrap(), ids([]));
        assert_eq!(
            db.get_file_ids_with_error_results(&file_ids).unwrap(),
            ids([4, 5, 12, 13])
        );
        assert_eq!(
            db.get_file_ids_with_error_results(&many).unwrap(),
            ids([4, 5, 12, 13])
        );

        db.prune_resolved_face_error_results(&[]).unwrap();
        db.prune_resolved_face_error_results(&[5]).unwrap();
        assert_eq!(db.get_errored_file_ids().unwrap(), ids([5, 11, 12]));
        db.prune_resolved_face_error_results(&[5, 11, 12]).unwrap();
        assert_eq!(db.get_errored_file_ids().unwrap(), ids([5, 12]));
        assert_eq!(db.get_faces_for_given_file_id(11).unwrap().len(), 1);
        assert_eq!(
            db.get_file_ids_with_error_results(&file_ids).unwrap(),
            ids([4, 5, 12, 13])
        );
    }

    #[test]
    fn large_id_lists_are_chunked() {
        let (_directory, db) = open();
        let faces: Vec<FaceRow> = (0..30).map(|index| good_face(index, 0)).collect();
        db.bulk_insert_faces(&faces).unwrap();
        let mapping: HashMap<String, String> = (0..30)
            .map(|index| (format!("{index}_0"), format!("c{}", index % 3)))
            .collect();
        db.update_face_id_to_cluster_id(&mapping).unwrap();

        let face_ids: Vec<String> = (0..12000).map(|index| format!("{index}_0")).collect();
        assert_eq!(db.get_face_ids_to_cluster_ids(&face_ids).unwrap().len(), 30);
        assert_eq!(
            db.get_face_embedding_rows_for_faces(&face_ids)
                .unwrap()
                .len(),
            30
        );
        let file_ids: Vec<i64> = (0..12000).collect();
        db.delete_unclustered_face_index_for_files(&file_ids)
            .unwrap();
        assert_eq!(db.get_total_face_count().unwrap(), 30);
        db.delete_face_index_for_files(&file_ids).unwrap();
        assert_eq!(db.get_total_face_count().unwrap(), 0);
    }
}
