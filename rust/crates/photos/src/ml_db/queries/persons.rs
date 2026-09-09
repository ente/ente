use std::collections::{HashMap, HashSet};
use std::num::NonZeroUsize;

use crate::db::{MAX_SQL_BIND_PARAMS_PER_QUERY, pair};

use super::clusters::file_id_to_cluster_ids;
use crate::ml_db::schema::{
    CREATE_CLUSTER_PERSON_TABLE, CREATE_NOT_PERSON_FEEDBACK_TABLE, DELETE_CLUSTER_PERSON,
    DELETE_NOT_PERSON_FEEDBACK,
};
use crate::ml_db::{MlDb, Result};

pub type PersonToClusterIdToFaceIds = HashMap<String, HashMap<String, HashSet<String>>>;

const INSERT_CLUSTER_PERSON: &str = r#"
    INSERT INTO cluster_person (person_id, cluster_id)
    VALUES (?, ?)
    ON CONFLICT (person_id, cluster_id) DO NOTHING
"#;
const INSERT_NOT_PERSON_FEEDBACK: &str = r#"
    INSERT INTO not_person_feedback (person_id, cluster_id)
    VALUES (?, ?)
    ON CONFLICT DO NOTHING
"#;

impl MlDb {
    pub fn get_clusters_with_three_or_more_not_person_feedback(&self) -> Result<HashSet<String>> {
        self.db
            .read_column(
                r#"
                SELECT cluster_id
                FROM not_person_feedback
                GROUP BY cluster_id
                HAVING COUNT(*) >= 3
                "#,
                (),
            )
            .map_err(Into::into)
    }

    pub fn get_person_ignored_clusters(&self, person_id: &str) -> Result<HashSet<String>> {
        let mut ignored_cluster_ids: HashSet<String> = self.db.read_column(
            r#"
            SELECT cluster_id
            FROM cluster_person
            WHERE person_id != ?
                AND person_id IS NOT NULL
            "#,
            [person_id],
        )?;
        let reject_cluster_ids: Vec<String> = self.db.read_column(
            "SELECT cluster_id FROM not_person_feedback WHERE person_id = ?",
            [person_id],
        )?;
        ignored_cluster_ids.extend(reject_cluster_ids);
        Ok(ignored_cluster_ids)
    }

    pub fn get_person_to_rejected_suggestions(&self) -> Result<HashMap<String, HashSet<String>>> {
        self.db
            .read_grouped("SELECT person_id, cluster_id FROM not_person_feedback", ())
            .map_err(Into::into)
    }

    pub fn get_person_cluster_ids(&self, person_id: &str) -> Result<HashSet<String>> {
        self.db
            .read_column(
                "SELECT cluster_id FROM cluster_person WHERE person_id = ?",
                [person_id],
            )
            .map_err(Into::into)
    }

    pub fn get_persons_cluster_ids(&self, person_ids: &[String]) -> Result<HashSet<String>> {
        self.db
            .read_chunked_in(
                "SELECT cluster_id FROM cluster_person WHERE person_id IN ({})",
                person_ids,
                const { NonZeroUsize::new(MAX_SQL_BIND_PARAMS_PER_QUERY).unwrap() },
                |row| row.get(0),
            )
            .map_err(Into::into)
    }

    pub fn get_person_to_cluster_id_to_face_ids(&self) -> Result<PersonToClusterIdToFaceIds> {
        let rows: Vec<(String, String, String)> = self.db.read_all(
            r#"
            SELECT person_id, face_clusters.cluster_id, face_id
            FROM cluster_person
            INNER JOIN face_clusters
                ON cluster_person.cluster_id = face_clusters.cluster_id
            "#,
            (),
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )?;
        let mut result: PersonToClusterIdToFaceIds = HashMap::new();
        for (person_id, cluster_id, face_id) in rows {
            result
                .entry(person_id)
                .or_default()
                .entry(cluster_id)
                .or_default()
                .insert(face_id);
        }
        Ok(result)
    }

    pub fn get_person_to_cluster_ids(&self) -> Result<HashMap<String, HashSet<String>>> {
        self.db
            .read_grouped("SELECT person_id, cluster_id FROM cluster_person", ())
            .map_err(Into::into)
    }

    pub fn get_face_id_to_person_id_for_faces(
        &self,
        face_ids: &[String],
    ) -> Result<HashMap<String, String>> {
        self.db
            .read_chunked_in(
                r#"
                SELECT face_id, person_id
                FROM cluster_person
                INNER JOIN face_clusters
                    ON cluster_person.cluster_id = face_clusters.cluster_id
                WHERE face_id IN ({})
                "#,
                face_ids,
                const { NonZeroUsize::new(MAX_SQL_BIND_PARAMS_PER_QUERY).unwrap() },
                pair,
            )
            .map_err(Into::into)
    }

    pub fn get_cluster_id_to_face_ids_for_person(
        &self,
        person_id: &str,
    ) -> Result<HashMap<String, HashSet<String>>> {
        self.db
            .read_grouped(
                r#"
                SELECT face_clusters.cluster_id, face_id
                FROM cluster_person
                INNER JOIN face_clusters
                    ON cluster_person.cluster_id = face_clusters.cluster_id
                WHERE person_id = ?
                "#,
                [person_id],
            )
            .map_err(Into::into)
    }

    pub fn get_face_ids_for_person(&self, person_id: &str) -> Result<HashSet<String>> {
        self.db
            .read_column(
                r#"
                SELECT face_id
                FROM face_clusters
                LEFT JOIN cluster_person
                    ON face_clusters.cluster_id = cluster_person.cluster_id
                WHERE cluster_person.person_id = ?
                "#,
                [person_id],
            )
            .map_err(Into::into)
    }

    pub fn get_face_ids_for_person_ordered_by_score(
        &self,
        person_id: &str,
        limit: i64,
    ) -> Result<Vec<String>> {
        self.db
            .read_column(
                r#"
                SELECT faces.face_id
                FROM faces
                JOIN face_clusters
                    ON faces.face_id = face_clusters.face_id
                JOIN cluster_person
                    ON face_clusters.cluster_id = cluster_person.cluster_id
                WHERE cluster_person.person_id = ?
                ORDER BY faces.score DESC
                LIMIT ?
                "#,
                (person_id, limit),
            )
            .map_err(Into::into)
    }

    pub fn remove_person(&self, person_id: &str) -> Result<()> {
        self.db
            .write_transaction(|transaction| {
                transaction.execute(
                    "DELETE FROM cluster_person WHERE person_id = ?",
                    [person_id],
                )?;
                transaction.execute(
                    "DELETE FROM not_person_feedback WHERE person_id = ?",
                    [person_id],
                )?;
                Ok(())
            })
            .map_err(Into::into)
    }

    pub fn assign_cluster_to_person(&self, person_id: &str, cluster_id: &str) -> Result<()> {
        self.db
            .execute(INSERT_CLUSTER_PERSON, [person_id, cluster_id])?;
        Ok(())
    }

    pub fn bulk_assign_cluster_to_person_id(
        &self,
        cluster_to_person_id: &HashMap<String, String>,
    ) -> Result<()> {
        self.db
            .write_batch_atomic(
                INSERT_CLUSTER_PERSON,
                cluster_to_person_id
                    .iter()
                    .map(|(cluster_id, person_id)| (person_id, cluster_id)),
            )
            .map_err(Into::into)
    }

    pub fn capture_not_person_feedback(&self, person_id: &str, cluster_id: &str) -> Result<()> {
        self.db
            .execute(INSERT_NOT_PERSON_FEEDBACK, [person_id, cluster_id])?;
        Ok(())
    }

    pub fn bulk_capture_not_person_feedback(
        &self,
        cluster_to_person_id: &HashMap<String, String>,
    ) -> Result<()> {
        self.db
            .write_batch_atomic(
                INSERT_NOT_PERSON_FEEDBACK,
                cluster_to_person_id
                    .iter()
                    .map(|(cluster_id, person_id)| (person_id, cluster_id)),
            )
            .map_err(Into::into)
    }

    pub fn remove_not_person_feedback(&self, person_id: &str, cluster_id: &str) -> Result<()> {
        self.db.execute(
            "DELETE FROM not_person_feedback WHERE person_id = ? AND cluster_id = ?",
            [person_id, cluster_id],
        )?;
        Ok(())
    }

    pub fn remove_cluster_to_person(&self, person_id: &str, cluster_id: &str) -> Result<()> {
        self.db.execute(
            "DELETE FROM cluster_person WHERE person_id = ? AND cluster_id = ?",
            [person_id, cluster_id],
        )?;
        Ok(())
    }

    pub fn get_file_id_to_cluster_id_set(
        &self,
        person_id: &str,
    ) -> Result<HashMap<i64, HashSet<String>>> {
        self.db
            .read_all(
                r#"
                SELECT face_clusters.cluster_id, face_id
                FROM face_clusters
                INNER JOIN cluster_person
                    ON face_clusters.cluster_id = cluster_person.cluster_id
                WHERE cluster_person.person_id = ?
                "#,
                [person_id],
                pair,
            )
            .map_err(Into::into)
            .and_then(file_id_to_cluster_ids)
    }

    pub fn get_cluster_id_to_person_id(&self) -> Result<HashMap<String, String>> {
        self.db
            .read_all(
                "SELECT person_id, cluster_id FROM cluster_person",
                (),
                |row| Ok((row.get(1)?, row.get(0)?)),
            )
            .map_err(Into::into)
    }

    pub fn drop_faces_feedback_tables(&self) -> Result<()> {
        self.db
            .execute_statements([
                DELETE_CLUSTER_PERSON,
                DELETE_NOT_PERSON_FEEDBACK,
                CREATE_CLUSTER_PERSON_TABLE,
                CREATE_NOT_PERSON_FEEDBACK_TABLE,
            ])
            .map_err(Into::into)
    }

    pub fn get_file_ids_of_person_id(&self, person_id: &str) -> Result<Vec<i64>> {
        self.db
            .read_column(
                r#"
                SELECT DISTINCT faces.file_id
                FROM cluster_person
                JOIN face_clusters
                    ON cluster_person.cluster_id = face_clusters.cluster_id
                JOIN faces
                    ON face_clusters.face_id = faces.face_id
                WHERE cluster_person.person_id = ?
                "#,
                [person_id],
            )
            .map_err(Into::into)
    }
}

#[cfg(test)]
pub(in crate::ml_db) mod tests {
    use std::collections::HashMap;

    use super::MlDb;
    use crate::ml_db::queries::{clusters, faces};
    use crate::ml_db::tests::{
        cases, check, grouped, grouped_by_file, map, open, set, sorted, strings,
    };
    use tempfile::TempDir;

    pub(in crate::ml_db) fn seed(db: &MlDb) {
        db.assign_cluster_to_person("p1", "c1").unwrap();
        db.assign_cluster_to_person("p1", "c2").unwrap();
        db.assign_cluster_to_person("p2", "c3").unwrap();
        db.capture_not_person_feedback("p1", "c3").unwrap();
        db.capture_not_person_feedback("p1", "c3").unwrap();
        db.capture_not_person_feedback("p2", "c3").unwrap();
        db.capture_not_person_feedback("p2", "c1").unwrap();
        db.bulk_capture_not_person_feedback(&map([("c1", "p2"), ("c2", "p3")]))
            .unwrap();
    }

    fn seeded() -> (TempDir, MlDb) {
        let (directory, db) = open();
        faces::tests::seed(&db);
        clusters::tests::seed(&db);
        seed(&db);
        (directory, db)
    }

    #[test]
    fn seeded_id_sets() {
        let (_directory, db) = seeded();
        check(
            &db,
            &cases![
                "p1 clusters": set(["c1", "c2"]) => |db| db.get_person_cluster_ids("p1"),
                "unknown person clusters": set([]) => |db| db.get_person_cluster_ids("p9"),
                "persons clusters": set(["c1", "c2", "c3"]) =>
                    |db| db.get_persons_cluster_ids(&strings(["p1", "p2"])),
                "no persons clusters": set([]) => |db| db.get_persons_cluster_ids(&[]),
                "p1 ignored": set(["c3"]) => |db| db.get_person_ignored_clusters("p1"),
                "p2 ignored": set(["c1", "c2", "c3"]) => |db| db.get_person_ignored_clusters("p2"),
                "p3 ignored": set(["c1", "c2", "c3"]) => |db| db.get_person_ignored_clusters("p3"),
                "rejected thrice": set([]) => |db| db.get_clusters_with_three_or_more_not_person_feedback(),
                "p1 faces": set(["1_0", "1_1", "2_0"]) => |db| db.get_face_ids_for_person("p1"),
            ],
        );
    }

    #[test]
    fn seeded_ordered_lists() {
        let (_directory, db) = seeded();
        check(
            &db,
            &cases![
                "p1 by score": strings(["1_1", "1_0", "2_0"]) =>
                    |db| db.get_face_ids_for_person_ordered_by_score("p1", 10),
                "p1 by score limited": strings(["1_1", "1_0"]) =>
                    |db| db.get_face_ids_for_person_ordered_by_score("p1", 2),
            ],
        );
        check(
            &db,
            &cases![
                "p1 files": vec![1, 2] => |db| db.get_file_ids_of_person_id("p1").map(sorted),
            ],
        );
    }

    #[test]
    fn seeded_maps() {
        let (_directory, db) = seeded();
        check(
            &db,
            &cases![
                "cluster persons": map([("c1", "p1"), ("c2", "p1"), ("c3", "p2")]) =>
                    |db| db.get_cluster_id_to_person_id(),
                "face persons": map([("1_0", "p1"), ("3_0", "p2")]) =>
                    |db| db.get_face_id_to_person_id_for_faces(&strings(["1_0", "3_0", "4_0", "7_0"])),
                "no face persons": map([]) => |db| db.get_face_id_to_person_id_for_faces(&[]),
            ],
        );
        check(
            &db,
            &cases![
                "person clusters": grouped([("p1", &["c1", "c2"]), ("p2", &["c3"])]) =>
                    |db| db.get_person_to_cluster_ids(),
                "p1 cluster faces": grouped([("c1", &["1_0", "2_0"]), ("c2", &["1_1"])]) =>
                    |db| db.get_cluster_id_to_face_ids_for_person("p1"),
                "rejected suggestions": grouped([
                    ("p1", &["c3"]), ("p2", &["c3", "c1"]), ("p3", &["c2"]),
                ]) => |db| db.get_person_to_rejected_suggestions(),
            ],
        );
        check(
            &db,
            &cases![
                "file clusters for p1": grouped_by_file([(1, &["c1", "c2"]), (2, &["c1"])]) =>
                    |db| db.get_file_id_to_cluster_id_set("p1"),
            ],
        );
    }

    #[test]
    fn seeded_nested_faces() {
        let (_directory, db) = seeded();
        let nested = db.get_person_to_cluster_id_to_face_ids().unwrap();
        assert_eq!(nested["p1"]["c1"], set(["1_0", "2_0"]));
        assert_eq!(nested["p1"]["c2"], set(["1_1"]));
        assert_eq!(nested["p2"]["c3"], set(["3_0"]));
    }

    #[test]
    fn person_and_feedback_mutations() {
        let (_directory, db) = seeded();
        db.capture_not_person_feedback("p3", "c3").unwrap();
        assert_eq!(
            db.get_clusters_with_three_or_more_not_person_feedback()
                .unwrap(),
            set(["c3"])
        );
        db.remove_not_person_feedback("p2", "c1").unwrap();
        assert_eq!(
            db.get_person_to_rejected_suggestions().unwrap()["p2"],
            set(["c3"])
        );
        assert_eq!(
            db.get_person_ignored_clusters("p2").unwrap(),
            set(["c1", "c2", "c3"])
        );

        db.remove_person("p1").unwrap();
        assert!(db.get_person_cluster_ids("p1").unwrap().is_empty());
        assert!(
            !db.get_person_to_rejected_suggestions()
                .unwrap()
                .contains_key("p1")
        );
        assert_eq!(db.get_person_cluster_ids("p2").unwrap(), set(["c3"]));
        db.remove_cluster_to_person("p2", "c3").unwrap();
        assert!(db.get_person_cluster_ids("p2").unwrap().is_empty());

        db.assign_cluster_to_person("p5", "c3").unwrap();
        db.assign_cluster_to_person("p5", "c3").unwrap();
        db.bulk_assign_cluster_to_person_id(&map([("c1", "p5"), ("c2", "p5")]))
            .unwrap();
        db.bulk_assign_cluster_to_person_id(&map([("c1", "p5")]))
            .unwrap();
        db.bulk_capture_not_person_feedback(&HashMap::new())
            .unwrap();
        assert_eq!(
            db.get_person_cluster_ids("p5").unwrap(),
            set(["c1", "c2", "c3"])
        );
        assert_eq!(db.get_cluster_id_to_person_id().unwrap().len(), 3);

        db.drop_faces_feedback_tables().unwrap();
        assert!(db.get_person_to_cluster_ids().unwrap().is_empty());
        assert!(db.get_person_to_rejected_suggestions().unwrap().is_empty());
        assert_eq!(db.get_total_face_count().unwrap(), 9);
        assert_eq!(db.cluster_id_to_face_count().unwrap().len(), 6);
    }
}
