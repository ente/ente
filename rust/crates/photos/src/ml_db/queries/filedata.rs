use std::collections::{HashMap, HashSet};

use crate::db::optional_parameter;
use crate::ml_db::{MlDb, Result};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FdStatus {
    pub file_id: i64,
    pub user_id: i64,
    pub data_type: String,
    pub size: i64,
    pub object_id: Option<String>,
    pub object_nonce: Option<String>,
    pub updated_at: i64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PreviewInfo {
    pub object_id: String,
    pub object_size: i64,
}

impl MlDb {
    pub fn put_fd_status(&self, fd_status_list: &[FdStatus]) -> Result<()> {
        if fd_status_list.is_empty() {
            return Ok(());
        }
        self.db
            .write_batch_atomic(
                r#"
                INSERT OR REPLACE INTO filedata (
                    file_id, user_id, type, size, obj_id, obj_nonce, updated_at
                )
                values (?, ?, ?, ?, ?, ?, ?)
                "#,
                fd_status_list.iter().map(|status| {
                    (
                        status.file_id,
                        status.user_id,
                        &status.data_type,
                        status.size,
                        &status.object_id,
                        &status.object_nonce,
                        status.updated_at,
                    )
                }),
            )
            .map_err(Into::into)
    }

    pub fn get_file_ids_vid_preview(&self) -> Result<HashMap<i64, PreviewInfo>> {
        self.db
            .read_all(
                "SELECT file_id, obj_id, size FROM filedata WHERE type='vid_preview'",
                (),
                |row| {
                    Ok((
                        row.get(0)?,
                        PreviewInfo {
                            object_id: row.get(1)?,
                            object_size: row.get(2)?,
                        },
                    ))
                },
            )
            .map_err(Into::into)
    }

    pub fn get_file_ids_with_fd_data(&self, data_type: Option<&str>) -> Result<HashSet<i64>> {
        let sql = match data_type {
            None => "SELECT file_id FROM filedata",
            Some(_) => "SELECT file_id FROM filedata WHERE type = ?",
        };
        self.db
            .read_column(sql, optional_parameter(&data_type).as_slice())
            .map_err(Into::into)
    }
}

#[cfg(test)]
pub(in crate::ml_db) mod tests {
    use std::collections::{HashMap, HashSet};

    use super::{FdStatus, MlDb, PreviewInfo};
    use crate::ml_db::tests::{cases, check, open};
    use tempfile::TempDir;

    fn status(file_id: i64, data_type: &str, object_id: Option<&str>) -> FdStatus {
        FdStatus {
            file_id,
            user_id: 42,
            data_type: data_type.to_string(),
            size: file_id * 10,
            object_id: object_id.map(str::to_string),
            object_nonce: None,
            updated_at: 1000,
        }
    }

    fn preview(object_id: &str, object_size: i64) -> PreviewInfo {
        PreviewInfo {
            object_id: object_id.to_string(),
            object_size,
        }
    }

    fn ids<const N: usize>(values: [i64; N]) -> HashSet<i64> {
        HashSet::from(values)
    }

    pub(in crate::ml_db) fn seed(db: &MlDb) {
        db.put_fd_status(&[
            status(1, "vid_preview", Some("obj1")),
            status(2, "mldata", None),
            status(3, "vid_preview", Some("obj3")),
        ])
        .unwrap();
    }

    fn seeded() -> (TempDir, MlDb) {
        let (directory, db) = open();
        seed(&db);
        (directory, db)
    }

    #[test]
    fn seeded_file_id_sets() {
        let (_directory, db) = seeded();
        check(
            &db,
            &cases![
                "fd data": ids([1, 2, 3]) => |db| db.get_file_ids_with_fd_data(None),
                "fd mldata": ids([2]) => |db| db.get_file_ids_with_fd_data(Some("mldata")),
            ],
        );
    }

    #[test]
    fn seeded_video_previews() {
        let (_directory, db) = seeded();
        check(
            &db,
            &cases![
                "video previews": HashMap::from([(1, preview("obj1", 10)), (3, preview("obj3", 30))]) =>
                    |db| db.get_file_ids_vid_preview(),
            ],
        );
    }

    #[test]
    fn filedata_upsert() {
        let (_directory, db) = seeded();
        db.put_fd_status(&[]).unwrap();
        db.put_fd_status(&[status(1, "vid_preview", Some("obj1b"))])
            .unwrap();
        assert_eq!(
            db.get_file_ids_vid_preview().unwrap(),
            HashMap::from([(1, preview("obj1b", 10)), (3, preview("obj3", 30))])
        );
        assert_eq!(db.get_file_ids_with_fd_data(None).unwrap(), ids([1, 2, 3]));
    }
}
