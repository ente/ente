use std::time::{SystemTime, UNIX_EPOCH};

use super::clip::CLIP_ML_VERSION;
use crate::ml_db::vector_encoding::{decode_f32, encode_f32};
use crate::ml_db::{MlDb, Result};

const THREE_MONTHS_MILLIS: i64 = 90 * 24 * 60 * 60 * 1000;

impl MlDb {
    pub fn put_repeated_text_embedding_cache(&self, query: &str, embedding: &[f64]) -> Result<()> {
        let embedding_bytes = encode_f32(embedding.iter().map(|value| *value as f32));
        self.db.execute(
            r#"
            INSERT OR REPLACE INTO text_embeddings_cache (text_query, embedding, ml_version, created_at)
            VALUES (?, ?, ?, ?)
            "#,
            (query, embedding_bytes, CLIP_ML_VERSION, now_millis()),
        )?;
        Ok(())
    }

    pub fn get_repeated_text_embedding_cache(&self, query: &str) -> Result<Option<Vec<f32>>> {
        let results: Vec<(Vec<u8>, i64, i64)> = self.db.read_all(
            r#"
            SELECT embedding, ml_version, created_at
            FROM text_embeddings_cache
            WHERE text_query = ?
            "#,
            [query],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )?;
        if results.is_empty() {
            return Ok(None);
        }
        let three_months_ago = now_millis() - THREE_MONTHS_MILLIS;
        for (embedding, ml_version, created_at) in &results {
            if *ml_version == CLIP_ML_VERSION && *created_at > three_months_ago {
                return Ok(Some(decode_f32(embedding)));
            }
        }
        self.db.execute(
            "DELETE FROM text_embeddings_cache WHERE text_query = ?",
            [query],
        )?;
        Ok(None)
    }

    pub fn put_face_id_cached_for_person_or_cluster(
        &self,
        person_or_cluster_id: &str,
        face_id: &str,
    ) -> Result<()> {
        self.db.execute(
            "INSERT OR REPLACE INTO face_cache (person_or_cluster_id, face_id) VALUES (?, ?)",
            [person_or_cluster_id, face_id],
        )?;
        Ok(())
    }

    pub fn get_face_id_used_for_person_or_cluster(
        &self,
        person_or_cluster_id: &str,
    ) -> Result<Option<String>> {
        self.db
            .read_optional(
                "SELECT face_id FROM face_cache WHERE person_or_cluster_id = ?",
                [person_or_cluster_id],
            )
            .map_err(Into::into)
    }

    pub fn remove_face_id_cached_for_person_or_cluster(
        &self,
        person_or_cluster_id: &str,
    ) -> Result<()> {
        self.db.execute(
            "DELETE FROM face_cache WHERE person_or_cluster_id = ?",
            [person_or_cluster_id],
        )?;
        Ok(())
    }
}

fn now_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_millis() as i64)
        .unwrap_or(0)
}

#[cfg(test)]
pub(in crate::ml_db) mod tests {
    use super::MlDb;
    use crate::db::Connection;
    use crate::ml_db::tests::{cases, check, open};
    use tempfile::TempDir;

    pub(in crate::ml_db) fn seed(db: &MlDb) {
        db.put_repeated_text_embedding_cache("dog", &[0.5, -1.0])
            .unwrap();
        db.put_face_id_cached_for_person_or_cluster("p1", "1_0")
            .unwrap();
    }

    fn seeded() -> (TempDir, MlDb) {
        let (directory, db) = open();
        seed(&db);
        (directory, db)
    }

    #[test]
    fn seeded_optional_values() {
        let (_directory, db) = seeded();
        check(
            &db,
            &cases![
                "cached face p1": Some("1_0".to_string()) =>
                    |db| db.get_face_id_used_for_person_or_cluster("p1"),
                "cached face p2": None => |db| db.get_face_id_used_for_person_or_cluster("p2"),
            ],
        );
        check(
            &db,
            &cases![
                "cached dog": Some(vec![0.5, -1.0]) => |db| db.get_repeated_text_embedding_cache("dog"),
                "uncached cat": None => |db| db.get_repeated_text_embedding_cache("cat"),
            ],
        );
    }

    #[test]
    fn text_embedding_cache_replaces_and_expires() {
        let (directory, db) = seeded();
        db.put_repeated_text_embedding_cache("dog", &[2.0]).unwrap();
        assert_eq!(
            db.get_repeated_text_embedding_cache("dog").unwrap(),
            Some(vec![2.0f32])
        );

        let connection = Connection::open(directory.path().join("ente.ml.db")).unwrap();
        connection
            .execute(
                "UPDATE text_embeddings_cache SET created_at = 1 WHERE text_query = ?",
                ["dog"],
            )
            .unwrap();
        assert_eq!(db.get_repeated_text_embedding_cache("dog").unwrap(), None);
        let remaining: i64 = connection
            .query_row("SELECT COUNT(*) FROM text_embeddings_cache", (), |row| {
                row.get(0)
            })
            .unwrap();
        assert_eq!(remaining, 0);
    }

    #[test]
    fn face_cache_replaces_and_removes() {
        let (_directory, db) = seeded();
        db.put_face_id_cached_for_person_or_cluster("p1", "2_0")
            .unwrap();
        assert_eq!(
            db.get_face_id_used_for_person_or_cluster("p1").unwrap(),
            Some("2_0".to_string())
        );
        db.remove_face_id_cached_for_person_or_cluster("p1")
            .unwrap();
        assert_eq!(
            db.get_face_id_used_for_person_or_cluster("p1").unwrap(),
            None
        );
    }
}
