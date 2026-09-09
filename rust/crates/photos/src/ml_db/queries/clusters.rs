use std::collections::{HashMap, HashSet};
use std::num::NonZeroUsize;

use crate::db::{
    MAX_SQL_BIND_PARAMS_PER_QUERY, Row, SqliteResult, bind_placeholders, group_into,
    optional_parameter, pair, params_from_iter,
};

use super::faces::{file_id_from_face_id, is_bad_face_for_clustering};
use super::unique_in_order;
use crate::ml_db::schema::{
    CREATE_CLUSTER_CENTROID_VECTOR_ID_MAPPING_TABLE, CREATE_CLUSTER_PERSON_TABLE,
    CREATE_CLUSTER_SUMMARY_TABLE, CREATE_FACE_CLUSTERS_TABLE, CREATE_FACES_TABLE,
    CREATE_NOT_PERSON_FEEDBACK_TABLE, DELETE_CLUSTER_CENTROID_VECTOR_ID_MAPPING,
    DELETE_CLUSTER_PERSON, DELETE_CLUSTER_SUMMARY, DELETE_FACE_CLUSTERS, DELETE_FACES,
    DELETE_NOT_PERSON_FEEDBACK, FC_CLUSTER_ID_INDEX,
};
use crate::ml_db::{MlDb, Result};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ClusterSummary {
    pub avg: Vec<u8>,
    pub count: i64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ClusterCentroidRow {
    pub cluster_id: String,
    pub avg: Vec<u8>,
}

const UPSERT_FACE_CLUSTER: &str = r#"
    INSERT INTO face_clusters (face_id, cluster_id)
    VALUES (?, ?)
    ON CONFLICT (face_id) DO UPDATE SET
        cluster_id = excluded.cluster_id
"#;
const UPSERT_CLUSTER_SUMMARY: &str = r#"
    INSERT INTO cluster_summary (cluster_id, avg, count)
    VALUES (?, ?, ?)
    ON CONFLICT (cluster_id) DO UPDATE SET
        avg = excluded.avg,
        count = excluded.count
"#;

impl MlDb {
    pub fn update_face_id_to_cluster_id(
        &self,
        face_id_to_cluster_id: &HashMap<String, String>,
    ) -> Result<()> {
        self.db
            .write_batches_committing_each(
                UPSERT_FACE_CLUSTER,
                const { NonZeroUsize::new(500).unwrap() },
                face_id_to_cluster_id.iter(),
            )
            .map_err(Into::into)
    }

    pub fn cluster_id_to_face_count(&self) -> Result<HashMap<String, i64>> {
        self.db
            .read_all(
                r#"
                SELECT cluster_id, COUNT(*) as count
                FROM face_clusters
                where cluster_id IS NOT NULL
                GROUP BY cluster_id
                "#,
                (),
                pair,
            )
            .map_err(Into::into)
    }

    pub fn get_bad_face_singleton_cluster_ids(&self) -> Result<HashSet<String>> {
        let rows: Vec<(String, f64, f64, i64)> = self.db.read_all(
            r#"
            SELECT fc.cluster_id, f.score, f.blur, f.is_sideways
            FROM face_clusters fc
            INNER JOIN faces f
                ON fc.face_id = f.face_id
            GROUP BY fc.cluster_id
            HAVING COUNT(*) = 1
            "#,
            (),
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )?;
        Ok(rows
            .into_iter()
            .filter(|(_, score, blur, is_sideways)| {
                is_bad_face_for_clustering(*score, *blur, *is_sideways == 1)
            })
            .map(|(cluster_id, _, _, _)| cluster_id)
            .collect())
    }

    pub fn get_cluster_to_face_ids(
        &self,
        cluster_ids: &HashSet<String>,
    ) -> Result<HashMap<String, Vec<String>>> {
        if cluster_ids.is_empty() {
            return Ok(HashMap::new());
        }
        let cluster_id_list: Vec<&String> = cluster_ids.iter().collect();
        let rows: Vec<(String, String)> = self.db.read_chunked_in(
            "SELECT cluster_id, face_id FROM face_clusters WHERE cluster_id IN ({})",
            &cluster_id_list,
            const { NonZeroUsize::new(MAX_SQL_BIND_PARAMS_PER_QUERY).unwrap() },
            pair,
        )?;
        Ok(group_into(rows))
    }

    pub fn get_cluster_id_for_face_id(&self, face_id: &str) -> Result<Option<String>> {
        self.db
            .read_optional(
                "SELECT cluster_id FROM face_clusters WHERE face_id = ?",
                [face_id],
            )
            .map_err(Into::into)
    }

    pub fn get_all_cluster_id_to_face_ids(&self) -> Result<HashMap<String, Vec<String>>> {
        self.db
            .read_grouped("SELECT cluster_id, face_id FROM face_clusters", ())
            .map_err(Into::into)
    }

    pub fn get_face_ids_for_cluster(&self, cluster_id: &str) -> Result<Vec<String>> {
        self.db
            .read_column(
                "SELECT face_id FROM face_clusters WHERE face_clusters.cluster_id = ?",
                [cluster_id],
            )
            .map_err(Into::into)
    }

    pub fn get_face_ids_for_cluster_ordered_by_score(
        &self,
        cluster_id: &str,
        limit: i64,
    ) -> Result<Vec<String>> {
        self.db
            .read_column(
                r#"
                SELECT faces.face_id
                FROM faces
                JOIN face_clusters
                    ON faces.face_id = face_clusters.face_id
                WHERE face_clusters.cluster_id = ?
                ORDER BY faces.score DESC
                LIMIT ?
                "#,
                (cluster_id, limit),
            )
            .map_err(Into::into)
    }

    pub fn get_blur_values_for_cluster(&self, cluster_id: &str) -> Result<Vec<f64>> {
        let blur_values: Vec<f64> = self.db.read_column(
            r#"
            SELECT faces.blur
            FROM faces
            JOIN face_clusters
                ON faces.face_id = face_clusters.face_id
            WHERE face_clusters.cluster_id = ?
            "#,
            [cluster_id],
        )?;
        let mut seen = HashSet::new();
        Ok(blur_values
            .into_iter()
            .filter(|blur| seen.insert(blur.to_bits()))
            .collect())
    }

    pub fn get_face_ids_to_cluster_ids(
        &self,
        face_ids: &[String],
    ) -> Result<HashMap<String, Option<String>>> {
        self.db
            .read_chunked_in(
                "SELECT face_id, cluster_id FROM face_clusters where face_id IN ({})",
                face_ids,
                const { NonZeroUsize::new(MAX_SQL_BIND_PARAMS_PER_QUERY).unwrap() },
                pair,
            )
            .map_err(Into::into)
    }

    pub fn get_file_id_to_cluster_ids(&self) -> Result<HashMap<i64, HashSet<String>>> {
        self.db
            .read_all("SELECT cluster_id, face_id FROM face_clusters", (), pair)
            .map_err(Into::into)
            .and_then(file_id_to_cluster_ids)
    }

    pub fn force_update_cluster_ids(
        &self,
        face_id_to_cluster_id: &HashMap<String, String>,
    ) -> Result<()> {
        self.db
            .write_batch_atomic(UPSERT_FACE_CLUSTER, face_id_to_cluster_id.iter())
            .map_err(Into::into)
    }

    pub fn remove_face_id_to_cluster_id(
        &self,
        face_id_to_cluster_id: &HashMap<String, String>,
    ) -> Result<()> {
        self.db
            .write_batch_atomic(
                "DELETE FROM face_clusters WHERE face_id = ? AND cluster_id = ?",
                face_id_to_cluster_id.iter(),
            )
            .map_err(Into::into)
    }

    pub fn get_file_id_to_cluster_id_set_for_cluster(
        &self,
        cluster_ids: &HashSet<String>,
    ) -> Result<HashMap<i64, HashSet<String>>> {
        let sql = format!(
            "SELECT cluster_id, face_id FROM face_clusters WHERE cluster_id IN ({})",
            bind_placeholders(cluster_ids.len())
        );
        self.db
            .read_all(&sql, params_from_iter(cluster_ids), pair)
            .map_err(Into::into)
            .and_then(file_id_to_cluster_ids)
    }

    pub fn get_file_ids_of_cluster_id(&self, cluster_id: &str) -> Result<Vec<i64>> {
        self.db
            .read_column(
                r#"
                SELECT DISTINCT faces.file_id
                FROM face_clusters
                JOIN faces
                    ON face_clusters.face_id = faces.face_id
                WHERE face_clusters.cluster_id = ?
                "#,
                [cluster_id],
            )
            .map_err(Into::into)
    }

    pub fn get_cluster_centroid_vector_id_map(
        &self,
        cluster_ids: &[String],
        create_if_missing: bool,
    ) -> Result<HashMap<String, i64>> {
        let unique_cluster_ids = unique_in_order(cluster_ids);
        if unique_cluster_ids.is_empty() {
            return Ok(HashMap::new());
        }
        if create_if_missing {
            self.db.write_batch_atomic(
                "INSERT OR IGNORE INTO cluster_centroid_vector_id_map (cluster_id) VALUES (?)",
                unique_cluster_ids.iter().map(|cluster_id| [cluster_id]),
            )?;
        }
        self.db
            .read_chunked_in(
                r#"
                SELECT cluster_id, cluster_vector_id
                FROM cluster_centroid_vector_id_map
                WHERE cluster_id IN ({})
                "#,
                &unique_cluster_ids,
                const { NonZeroUsize::new(800).unwrap() },
                pair,
            )
            .map_err(Into::into)
    }

    pub fn delete_cluster_centroid_vector_id_mapping(&self, cluster_id: &str) -> Result<()> {
        self.db.execute(
            "DELETE FROM cluster_centroid_vector_id_map WHERE cluster_id = ?",
            [cluster_id],
        )?;
        Ok(())
    }

    pub fn clear_cluster_centroid_vector_id_mappings(&self) -> Result<()> {
        self.db
            .execute_statements([DELETE_CLUSTER_CENTROID_VECTOR_ID_MAPPING])
            .map_err(Into::into)
    }

    pub fn upsert_cluster_summary_rows(
        &self,
        summary: &HashMap<String, ClusterSummary>,
    ) -> Result<()> {
        self.db
            .write_batches_committing_each(
                UPSERT_CLUSTER_SUMMARY,
                const { NonZeroUsize::new(400).unwrap() },
                summary
                    .iter()
                    .map(|(cluster_id, summary)| (cluster_id, &summary.avg, summary.count)),
            )
            .map_err(Into::into)
    }

    pub fn delete_cluster_summary_row(&self, cluster_id: &str) -> Result<()> {
        self.db.execute(
            "DELETE FROM cluster_summary WHERE cluster_id = ?",
            [cluster_id],
        )?;
        Ok(())
    }

    pub fn get_all_cluster_summary(
        &self,
        min_cluster_size: Option<i64>,
    ) -> Result<HashMap<String, ClusterSummary>> {
        let sql = format!(
            "SELECT * FROM cluster_summary{}",
            if min_cluster_size.is_some() {
                " WHERE count >= ?"
            } else {
                ""
            }
        );
        self.db
            .read_all(
                &sql,
                optional_parameter(&min_cluster_size).as_slice(),
                read_cluster_summary,
            )
            .map_err(Into::into)
    }

    pub fn get_cluster_to_cluster_summary(
        &self,
        cluster_ids: &[String],
    ) -> Result<HashMap<String, ClusterSummary>> {
        let sql = format!(
            "SELECT * FROM cluster_summary WHERE cluster_id IN ({})",
            bind_placeholders(cluster_ids.len())
        );
        self.db
            .read_all(&sql, params_from_iter(cluster_ids), read_cluster_summary)
            .map_err(Into::into)
    }

    pub fn count_cluster_summaries(&self) -> Result<i64> {
        self.db
            .read_value("SELECT COUNT(cluster_id) as total FROM cluster_summary", ())
            .map_err(Into::into)
    }

    pub fn get_cluster_summary_page(
        &self,
        before_cluster_id: Option<&str>,
        limit: i64,
    ) -> Result<Vec<ClusterCentroidRow>> {
        match before_cluster_id {
            None => self.db.read_all(
                "SELECT cluster_id, avg FROM cluster_summary ORDER BY cluster_id DESC LIMIT ?",
                [limit],
                read_cluster_centroid,
            ),
            Some(before_cluster_id) => self.db.read_all(
                r#"
                SELECT cluster_id, avg
                FROM cluster_summary
                WHERE cluster_id < ?
                ORDER BY cluster_id DESC
                LIMIT ?
                "#,
                (before_cluster_id, limit),
                read_cluster_centroid,
            ),
        }
        .map_err(Into::into)
    }

    pub fn reset_cluster_tables(&self, faces: bool) -> Result<()> {
        let face_statements: &[&str] = if faces {
            &[
                DELETE_FACES,
                CREATE_FACES_TABLE,
                DELETE_FACE_CLUSTERS,
                CREATE_FACE_CLUSTERS_TABLE,
                FC_CLUSTER_ID_INDEX,
            ]
        } else {
            &[]
        };
        self.db
            .execute_statements(face_statements.iter().copied().chain([
                DELETE_CLUSTER_PERSON,
                DELETE_NOT_PERSON_FEEDBACK,
                DELETE_CLUSTER_SUMMARY,
                DELETE_CLUSTER_CENTROID_VECTOR_ID_MAPPING,
                DELETE_FACE_CLUSTERS,
                CREATE_CLUSTER_PERSON_TABLE,
                CREATE_NOT_PERSON_FEEDBACK_TABLE,
                CREATE_CLUSTER_SUMMARY_TABLE,
                CREATE_CLUSTER_CENTROID_VECTOR_ID_MAPPING_TABLE,
                CREATE_FACE_CLUSTERS_TABLE,
                FC_CLUSTER_ID_INDEX,
            ]))
            .map_err(Into::into)
    }

    pub fn get_clusters_for_memory_lane(
        &self,
        assigned: &HashSet<String>,
    ) -> Result<HashSet<String>> {
        let batch_size: i64 = 256;
        let mut clusters = HashSet::new();
        let mut offset: i64 = 0;
        while clusters.len() < 20 {
            let batch: Vec<String> = self.db.read_column(
                r#"
                SELECT cluster_id, COUNT(*) AS count
                FROM face_clusters
                WHERE cluster_id IS NOT NULL
                GROUP BY cluster_id
                ORDER BY count DESC, cluster_id
                LIMIT ?
                OFFSET ?
                "#,
                [batch_size, offset],
            )?;
            let batch_len = batch.len() as i64;
            for cluster in batch {
                if !assigned.contains(&cluster) {
                    clusters.insert(cluster);
                    if clusters.len() == 20 {
                        break;
                    }
                }
            }
            if batch_len < batch_size {
                break;
            }
            offset += batch_size;
        }
        Ok(clusters)
    }
}

pub(super) fn file_id_to_cluster_ids(
    cluster_and_face_ids: Vec<(String, String)>,
) -> Result<HashMap<i64, HashSet<String>>> {
    let mut result: HashMap<i64, HashSet<String>> = HashMap::new();
    for (cluster_id, face_id) in cluster_and_face_ids {
        let file_id = file_id_from_face_id(&face_id)?;
        result.entry(file_id).or_default().insert(cluster_id);
    }
    Ok(result)
}

fn read_cluster_summary(row: &Row<'_>) -> SqliteResult<(String, ClusterSummary)> {
    Ok((
        row.get("cluster_id")?,
        ClusterSummary {
            avg: row.get("avg")?,
            count: row.get("count")?,
        },
    ))
}

fn read_cluster_centroid(row: &Row<'_>) -> SqliteResult<ClusterCentroidRow> {
    Ok(ClusterCentroidRow {
        cluster_id: row.get(0)?,
        avg: row.get(1)?,
    })
}

#[cfg(test)]
pub(in crate::ml_db) mod tests {
    use std::collections::HashMap;

    use super::{ClusterCentroidRow, ClusterSummary, MlDb};
    use crate::ml_db::queries::{faces, persons};
    use crate::ml_db::tests::{
        cases, check, grouped, grouped_by_file, index_count, map, open, pairs, set, sorted, strings,
    };
    use crate::ml_db::vector_encoding::encode_evector;
    use tempfile::TempDir;

    fn summary(count: i64) -> ClusterSummary {
        ClusterSummary {
            avg: encode_evector(&[count as f64]),
            count,
        }
    }

    fn summaries<const N: usize>(entries: [(&str, i64); N]) -> HashMap<String, ClusterSummary> {
        pairs(entries.map(|(key, count)| (key, summary(count))))
    }

    fn sorted_lists(mut lists: HashMap<String, Vec<String>>) -> HashMap<String, Vec<String>> {
        lists.values_mut().for_each(|values| values.sort());
        lists
    }

    pub(in crate::ml_db) fn seed(db: &MlDb) {
        db.update_face_id_to_cluster_id(&map([
            ("1_0", "c1"),
            ("1_1", "c2"),
            ("2_0", "c1"),
            ("3_0", "c3"),
            ("7_0", "c7"),
            ("8_0", "c8"),
            ("9_0", "c9"),
        ]))
        .unwrap();
        db.upsert_cluster_summary_rows(&summaries([("c1", 2), ("c2", 1), ("c3", 1)]))
            .unwrap();
        db.get_cluster_centroid_vector_id_map(&strings(["c1", "c2"]), true)
            .unwrap();
    }

    fn seeded() -> (TempDir, MlDb) {
        let (directory, db) = open();
        faces::tests::seed(&db);
        seed(&db);
        persons::tests::seed(&db);
        (directory, db)
    }

    #[test]
    fn seeded_counts() {
        let (_directory, db) = seeded();
        check(
            &db,
            &cases![
                "cluster summaries": 3 => |db| db.count_cluster_summaries(),
            ],
        );
    }

    #[test]
    fn seeded_id_sets() {
        let (_directory, db) = seeded();
        check(
            &db,
            &cases![
                "bad singletons": set(["c7", "c8", "c9"]) => |db| db.get_bad_face_singleton_cluster_ids(),
                "memory lane": set(["c2", "c3", "c7", "c8", "c9"]) =>
                    |db| db.get_clusters_for_memory_lane(&set(["c1"])),
            ],
        );
    }

    #[test]
    fn seeded_ordered_lists() {
        let (_directory, db) = seeded();
        check(
            &db,
            &cases![
                "c1 by score": strings(["1_0", "2_0"]) =>
                    |db| db.get_face_ids_for_cluster_ordered_by_score("c1", 10),
                "c1 by score limited": strings(["1_0"]) =>
                    |db| db.get_face_ids_for_cluster_ordered_by_score("c1", 1),
                "c1 faces": strings(["1_0", "2_0"]) => |db| db.get_face_ids_for_cluster("c1").map(sorted),
            ],
        );
        check(
            &db,
            &cases![
                "c1 files": vec![1, 2] => |db| db.get_file_ids_of_cluster_id("c1").map(sorted),
            ],
        );
        check(
            &db,
            &cases![
                "c1 blur deduplicated": vec![300.0] => |db| db.get_blur_values_for_cluster("c1"),
                "c9 blur": vec![20.0] => |db| db.get_blur_values_for_cluster("c9"),
            ],
        );
    }

    #[test]
    fn seeded_optional_values() {
        let (_directory, db) = seeded();
        check(
            &db,
            &cases![
                "cluster of 1_1": Some("c2".to_string()) => |db| db.get_cluster_id_for_face_id("1_1"),
                "cluster of unclustered": None => |db| db.get_cluster_id_for_face_id("4_0"),
            ],
        );
    }

    #[test]
    fn seeded_maps() {
        let (_directory, db) = seeded();
        check(
            &db,
            &cases![
                "cluster sizes": pairs([
                    ("c1", 2), ("c2", 1), ("c3", 1), ("c7", 1), ("c8", 1), ("c9", 1),
                ]) => |db| db.cluster_id_to_face_count(),
                "centroid vector ids": pairs([("c1", 1), ("c2", 2)]) =>
                    |db| db.get_cluster_centroid_vector_id_map(&strings(["c1", "c2", "c3"]), false),
            ],
        );
        check(
            &db,
            &cases![
                "file clusters": grouped_by_file([
                    (1, &["c1", "c2"]), (2, &["c1"]), (3, &["c3"]),
                    (7, &["c7"]), (8, &["c8"]), (9, &["c9"]),
                ]) => |db| db.get_file_id_to_cluster_ids(),
                "file clusters for c2 and c9": grouped_by_file([(1, &["c2"]), (9, &["c9"])]) =>
                    |db| db.get_file_id_to_cluster_id_set_for_cluster(&set(["c2", "c9"])),
            ],
        );
        check(
            &db,
            &cases![
                "all cluster faces": grouped([
                    ("c1", &["1_0", "2_0"]), ("c2", &["1_1"]), ("c3", &["3_0"]),
                    ("c7", &["7_0"]), ("c8", &["8_0"]), ("c9", &["9_0"]),
                ]) => |db| db.get_all_cluster_id_to_face_ids().map(sorted_lists),
                "some cluster faces": grouped([("c1", &["1_0", "2_0"]), ("c2", &["1_1"])]) =>
                    |db| db.get_cluster_to_face_ids(&set(["c1", "c2", "missing"])).map(sorted_lists),
                "no cluster faces": grouped([]) => |db| db.get_cluster_to_face_ids(&set([])),
            ],
        );
        check(
            &db,
            &cases![
                "all summaries": summaries([("c1", 2), ("c2", 1), ("c3", 1)]) =>
                    |db| db.get_all_cluster_summary(None),
                "large summaries": summaries([("c1", 2)]) => |db| db.get_all_cluster_summary(Some(2)),
                "some summaries": summaries([("c1", 2), ("c3", 1)]) =>
                    |db| db.get_cluster_to_cluster_summary(&strings(["c1", "c3", "nope"])),
            ],
        );
    }

    #[test]
    fn seeded_face_clusters() {
        let (_directory, db) = seeded();
        assert_eq!(
            db.get_face_ids_to_cluster_ids(&strings(["1_0", "1_1", "4_0"]))
                .unwrap(),
            pairs([
                ("1_0", Some("c1".to_string())),
                ("1_1", Some("c2".to_string()))
            ])
        );
        assert!(db.get_face_ids_to_cluster_ids(&[]).unwrap().is_empty());
    }

    #[test]
    fn cluster_assignment_upserts_and_removals() {
        let (_directory, db) = seeded();
        db.update_face_id_to_cluster_id(&map([("1_1", "c5"), ("4_0", "c5")]))
            .unwrap();
        assert_eq!(
            db.get_cluster_id_for_face_id("1_1").unwrap(),
            Some("c5".to_string())
        );
        db.force_update_cluster_ids(&map([("1_0", "c9"), ("5_0", "c9")]))
            .unwrap();
        assert_eq!(
            db.get_cluster_id_for_face_id("1_0").unwrap(),
            Some("c9".to_string())
        );
        assert_eq!(
            db.get_cluster_id_for_face_id("5_0").unwrap(),
            Some("c9".to_string())
        );
        db.remove_face_id_to_cluster_id(&map([("2_0", "c1"), ("5_0", "c1")]))
            .unwrap();
        assert_eq!(db.get_cluster_id_for_face_id("2_0").unwrap(), None);
        assert_eq!(
            db.get_cluster_id_for_face_id("5_0").unwrap(),
            Some("c9".to_string())
        );
        let sizes = db.cluster_id_to_face_count().unwrap();
        assert_eq!((sizes.get("c1"), sizes["c5"], sizes["c9"]), (None, 2, 3));
    }

    #[test]
    fn reset_cluster_tables_keeps_or_drops_faces() {
        let (directory, db) = seeded();
        db.reset_cluster_tables(false).unwrap();
        assert_eq!(db.get_total_face_count().unwrap(), 9);
        assert!(db.cluster_id_to_face_count().unwrap().is_empty());
        assert!(db.get_person_to_cluster_ids().unwrap().is_empty());
        assert!(db.get_person_to_rejected_suggestions().unwrap().is_empty());
        assert_eq!(db.count_cluster_summaries().unwrap(), 0);
        assert!(
            db.get_cluster_centroid_vector_id_map(&strings(["c1"]), false)
                .unwrap()
                .is_empty()
        );

        db.reset_cluster_tables(true).unwrap();
        assert_eq!(db.get_total_face_count().unwrap(), 0);
        assert_eq!(index_count(&directory.path().join("ente.ml.db")), 1);
    }

    #[test]
    fn cluster_summary_upsert_and_keyset_paging() {
        let (_directory, db) = open();
        let mut rows = HashMap::new();
        for index in 0..1000 {
            rows.insert(format!("c{index:04}"), summary(index));
        }
        db.upsert_cluster_summary_rows(&rows).unwrap();
        db.upsert_cluster_summary_rows(&summaries([("c0001", 77)]))
            .unwrap();

        assert_eq!(db.count_cluster_summaries().unwrap(), 1000);
        let all = db.get_all_cluster_summary(None).unwrap();
        assert_eq!(all.len(), 1000);
        assert_eq!(all["c0001"], summary(77));
        assert_eq!(db.get_all_cluster_summary(Some(998)).unwrap().len(), 2);
        assert_eq!(
            db.get_cluster_to_cluster_summary(&strings(["c0002", "c0003", "nope"]))
                .unwrap(),
            summaries([("c0002", 2), ("c0003", 3)])
        );

        let first_page = db.get_cluster_summary_page(None, 2).unwrap();
        let ids = |page: &[ClusterCentroidRow]| -> Vec<String> {
            page.iter().map(|row| row.cluster_id.clone()).collect()
        };
        assert_eq!(ids(&first_page), strings(["c0999", "c0998"]));
        assert_eq!(first_page[0].avg, encode_evector(&[999.0]));
        let next_page = db.get_cluster_summary_page(Some("c0998"), 2).unwrap();
        assert_eq!(ids(&next_page), strings(["c0997", "c0996"]));
        assert!(
            db.get_cluster_summary_page(Some("c0000"), 2)
                .unwrap()
                .is_empty()
        );

        db.delete_cluster_summary_row("c0999").unwrap();
        assert_eq!(db.count_cluster_summaries().unwrap(), 999);
        assert!(
            !db.get_all_cluster_summary(None)
                .unwrap()
                .contains_key("c0999")
        );
    }

    #[test]
    fn cluster_centroid_vector_ids() {
        let (_directory, db) = seeded();
        assert!(
            db.get_cluster_centroid_vector_id_map(&[], true)
                .unwrap()
                .is_empty()
        );
        let created = db
            .get_cluster_centroid_vector_id_map(&strings(["c2", "c3", "c2"]), true)
            .unwrap();
        assert_eq!(created.len(), 2);
        assert_eq!(created["c2"], 2);
        assert!(created["c3"] > 2);
        db.delete_cluster_centroid_vector_id_mapping("c1").unwrap();
        assert_eq!(
            db.get_cluster_centroid_vector_id_map(&strings(["c1", "c2"]), false)
                .unwrap(),
            pairs([("c2", 2)])
        );
        db.clear_cluster_centroid_vector_id_mappings().unwrap();
        assert!(
            db.get_cluster_centroid_vector_id_map(&strings(["c2", "c3"]), false)
                .unwrap()
                .is_empty()
        );
    }

    #[test]
    fn clusters_for_memory_lane_skips_assigned_and_caps_at_twenty() {
        let (_directory, db) = open();
        let mut mapping = HashMap::new();
        for cluster in 0..30 {
            for face in 0..=cluster {
                mapping.insert(format!("{face}_{cluster}"), format!("c{cluster:02}"));
            }
        }
        db.update_face_id_to_cluster_id(&mapping).unwrap();
        let clusters = db
            .get_clusters_for_memory_lane(&set(["c29", "c27"]))
            .unwrap();
        assert_eq!(clusters.len(), 20);
        assert!(!clusters.contains("c29"));
        assert!(!clusters.contains("c27"));
        assert!(clusters.contains("c28"));
        assert!(clusters.contains("c08"));
        assert!(!clusters.contains("c07"));
        assert_eq!(db.get_clusters_for_memory_lane(&set([])).unwrap().len(), 20);
    }
}
