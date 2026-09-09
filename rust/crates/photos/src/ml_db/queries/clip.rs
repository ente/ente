use std::collections::HashMap;

use crate::db::pair;
use crate::ml_db::schema;
use crate::ml_db::vector_encoding::{decode_f32, encode_f32};
use crate::ml_db::{MlDb, Result};

pub const CLIP_ML_VERSION: i64 = 1;

pub const CLIP_EMBEDDING_DIMENSIONS: usize = 512;
pub const CLIP_EMBEDDING_BYTES_LENGTH: i64 = CLIP_EMBEDDING_DIMENSIONS as i64 * 4;

#[derive(Clone, Debug, PartialEq)]
pub struct ClipEmbedding {
    pub file_id: i64,
    pub embedding: Vec<f64>,
    pub version: i64,
}

#[derive(Clone, Debug, PartialEq)]
pub struct EmbeddingVector {
    pub file_id: i64,
    pub embedding: Vec<f32>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ClipRow {
    pub file_id: i64,
    pub embedding: Vec<u8>,
}

impl MlDb {
    pub fn get_all_clip_vectors(&self) -> Result<Vec<EmbeddingVector>> {
        let rows: Vec<(i64, Vec<u8>)> =
            self.db
                .read_all("SELECT file_id, embedding FROM clip", (), pair)?;
        Ok(rows
            .into_iter()
            .map(|(file_id, embedding)| EmbeddingVector {
                file_id,
                embedding: decode_f32(&embedding),
            })
            .filter(|vector| !vector.embedding.is_empty())
            .collect())
    }

    pub fn clip_indexed_file_with_version(&self) -> Result<HashMap<i64, i64>> {
        self.db
            .read_all("SELECT file_id , ml_version FROM clip", (), pair)
            .map_err(Into::into)
    }

    pub fn get_clip_indexed_file_count(&self, minimum_ml_version: i64) -> Result<i64> {
        self.db
            .read_value(
                "SELECT COUNT(DISTINCT file_id) as count FROM clip WHERE ml_version >= ?",
                [minimum_ml_version],
            )
            .map_err(Into::into)
    }

    pub fn get_clip_vectorizable_file_count(&self, minimum_ml_version: i64) -> Result<i64> {
        self.db
            .read_value(
                r#"
                SELECT COUNT(DISTINCT file_id) as count
                FROM clip
                WHERE ml_version >= ?
                    AND LENGTH(embedding) = ?
                "#,
                [minimum_ml_version, CLIP_EMBEDDING_BYTES_LENGTH],
            )
            .map_err(Into::into)
    }

    pub fn insert_clip_rows(&self, embeddings: &[ClipEmbedding]) -> Result<()> {
        if let [embedding] = embeddings {
            self.db.execute(
                "INSERT OR REPLACE INTO clip (file_id, embedding, ml_version) VALUES (?, ?, ?)",
                clip_row(embedding),
            )?;
            return Ok(());
        }
        self.db
            .write_batch_atomic(
                "INSERT OR REPLACE INTO clip (file_id, embedding, ml_version) values(?, ?, ?)",
                embeddings.iter().map(clip_row),
            )
            .map_err(Into::into)
    }

    pub fn delete_clip_rows(&self, file_ids: &[i64]) -> Result<()> {
        self.db
            .execute_chunked_in("DELETE FROM clip WHERE file_id IN ({})", file_ids)
            .map_err(Into::into)
    }

    pub fn delete_all_clip_rows(&self) -> Result<()> {
        self.db
            .execute_statements([schema::DELETE_CLIP_EMBEDDINGS])
            .map_err(Into::into)
    }

    pub fn count_clip_rows(&self) -> Result<i64> {
        self.db
            .read_value("SELECT COUNT(file_id) as total FROM clip", ())
            .map_err(Into::into)
    }

    pub fn get_clip_rows_page(&self, limit: i64, offset: i64) -> Result<Vec<ClipRow>> {
        self.db
            .read_all(
                "SELECT file_id, embedding FROM clip ORDER BY file_id DESC LIMIT ? OFFSET ?",
                [limit, offset],
                |row| {
                    Ok(ClipRow {
                        file_id: row.get(0)?,
                        embedding: row.get(1)?,
                    })
                },
            )
            .map_err(Into::into)
    }
}

fn clip_row(embedding: &ClipEmbedding) -> (i64, Vec<u8>, i64) {
    (
        embedding.file_id,
        encode_f32(embedding.embedding.iter().map(|value| *value as f32)),
        embedding.version,
    )
}

#[cfg(test)]
pub(in crate::ml_db) mod tests {
    use std::collections::HashMap;

    use super::{CLIP_EMBEDDING_DIMENSIONS, ClipEmbedding, ClipRow, MlDb};
    use crate::ml_db::tests::{cases, check, open};
    use crate::ml_db::vector_encoding::encode_f32;
    use tempfile::TempDir;

    fn clip(file_id: i64, embedding: Vec<f64>) -> ClipEmbedding {
        ClipEmbedding {
            file_id,
            embedding,
            version: 1,
        }
    }

    pub(in crate::ml_db) fn full_clip(file_id: i64) -> ClipEmbedding {
        clip(file_id, vec![0.25; CLIP_EMBEDDING_DIMENSIONS])
    }

    pub(in crate::ml_db) fn seed(db: &MlDb) {
        db.insert_clip_rows(&[
            full_clip(1),
            ClipEmbedding {
                version: 2,
                ..full_clip(2)
            },
            clip(3, vec![1.0, 2.0]),
            clip(4, vec![]),
        ])
        .unwrap();
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
                "clip files": 4 => |db| db.get_clip_indexed_file_count(1),
                "clip files v2": 1 => |db| db.get_clip_indexed_file_count(2),
                "clip vectorizable": 2 => |db| db.get_clip_vectorizable_file_count(1),
                "clip vectorizable v2": 1 => |db| db.get_clip_vectorizable_file_count(2),
                "clip rows": 4 => |db| db.count_clip_rows(),
            ],
        );
    }

    #[test]
    fn seeded_versions() {
        let (_directory, db) = seeded();
        check(
            &db,
            &cases![
                "clip versions": HashMap::from([(1, 1), (2, 2), (3, 1), (4, 1)]) =>
                    |db| db.clip_indexed_file_with_version(),
            ],
        );
    }

    #[test]
    fn seeded_rows() {
        let (_directory, db) = seeded();
        let mut vectors = db.get_all_clip_vectors().unwrap();
        vectors.sort_by_key(|vector| vector.file_id);
        let dimensions: Vec<(i64, usize)> = vectors
            .iter()
            .map(|v| (v.file_id, v.embedding.len()))
            .collect();
        assert_eq!(
            dimensions,
            vec![
                (1, CLIP_EMBEDDING_DIMENSIONS),
                (2, CLIP_EMBEDDING_DIMENSIONS),
                (3, 2)
            ]
        );
        assert_eq!(vectors[2].embedding, vec![1.0f32, 2.0]);
        let page = db.get_clip_rows_page(2, 1).unwrap();
        let clip_row = |file_id, embedding: Vec<f32>| ClipRow {
            file_id,
            embedding: encode_f32(embedding),
        };
        assert_eq!(
            page,
            vec![
                clip_row(3, vec![1.0, 2.0]),
                clip_row(2, vec![0.25; CLIP_EMBEDDING_DIMENSIONS])
            ]
        );
    }

    #[test]
    fn clip_rows_replace_and_delete() {
        let (_directory, db) = seeded();
        db.insert_clip_rows(&[]).unwrap();
        db.insert_clip_rows(&[clip(1, vec![1.0])]).unwrap();
        db.insert_clip_rows(&[clip(3, vec![3.0]), full_clip(5)])
            .unwrap();
        assert_eq!(
            db.clip_indexed_file_with_version().unwrap(),
            HashMap::from([(1, 1), (2, 2), (3, 1), (4, 1), (5, 1)])
        );
        let mut vectors = db.get_all_clip_vectors().unwrap();
        vectors.sort_by_key(|vector| vector.file_id);
        assert_eq!(vectors[0].embedding, vec![1.0f32]);
        assert_eq!(vectors[2].embedding, vec![3.0f32]);
        assert_eq!(db.get_clip_vectorizable_file_count(1).unwrap(), 2);

        db.delete_clip_rows(&[]).unwrap();
        db.delete_clip_rows(&[1, 3]).unwrap();
        assert_eq!(db.count_clip_rows().unwrap(), 3);
        db.delete_all_clip_rows().unwrap();
        assert_eq!(db.count_clip_rows().unwrap(), 0);
    }
}
