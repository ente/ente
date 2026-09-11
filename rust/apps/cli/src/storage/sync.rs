use crate::{
    Result,
    models::{collection::Collection, file::RemoteFile},
};
use rusqlite::{Connection, OptionalExtension, params};
use serde_json;

pub struct SyncStore<'a> {
    conn: &'a Connection,
}

impl<'a> SyncStore<'a> {
    pub fn new(conn: &'a Connection) -> Self {
        Self { conn }
    }

    pub fn upsert_collection(&self, collection: &Collection) -> Result<()> {
        let metadata = serde_json::to_string(&collection)?;

        self.conn.execute(
            "INSERT OR REPLACE INTO collections 
             (collection_id, owner, name, type, is_deleted, metadata, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![
                collection.id,
                collection.owner,
                collection.name,
                format!("{:?}", collection.collection_type).to_lowercase(),
                collection.is_deleted as i32,
                metadata,
                collection.updated_at
            ],
        )?;

        Ok(())
    }

    pub fn get_collections(&self, user_id: i64) -> Result<Vec<Collection>> {
        let mut stmt = self.conn.prepare(
            "SELECT metadata FROM collections 
             WHERE owner = ?1 AND is_deleted = 0
             ORDER BY collection_id",
        )?;

        stmt.query_map(params![user_id], |row| row.get::<_, String>(0))?
            .map(|metadata| Ok(serde_json::from_str(&metadata?)?))
            .collect()
    }

    pub fn upsert_file(&self, file: &RemoteFile) -> Result<()> {
        self.upsert_file_with_hash(file, None)
    }

    pub fn upsert_file_with_hash(
        &self,
        file: &RemoteFile,
        content_hash: Option<&str>,
    ) -> Result<()> {
        let file_info = serde_json::to_string(&file.file)?;
        let metadata = serde_json::to_string(&file.metadata)?;
        let pub_magic_metadata = match &file.pub_magic_metadata {
            Some(meta) => Some(serde_json::to_string(meta)?),
            None => None,
        };

        // Refreshing remote metadata must preserve the local-sync flag.
        let existing_sync_status: Option<i32> = self
            .conn
            .query_row(
                "SELECT is_synced_locally FROM files WHERE file_id = ?1",
                params![file.id],
                |row| row.get(0),
            )
            .optional()?;

        let is_synced = existing_sync_status.unwrap_or(0);

        self.conn.execute(
            "INSERT OR REPLACE INTO files 
             (file_id, owner_id, collection_id, encrypted_key, key_decryption_nonce, 
              file_info, metadata, pub_magic_metadata, content_hash, is_deleted, is_synced_locally, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)",
            params![
                file.id,
                file.owner_id,
                file.collection_id,
                file.encrypted_key,
                file.key_decryption_nonce,
                file_info,
                metadata,
                pub_magic_metadata,
                content_hash,
                file.is_deleted as i32,
                is_synced,
                file.updated_at
            ],
        )?;

        Ok(())
    }

    pub fn get_files_by_collection(
        &self,
        user_id: i64,
        collection_id: i64,
    ) -> Result<Vec<RemoteFile>> {
        let mut stmt = self.conn.prepare(
            "SELECT file_id, collection_id, encrypted_key, key_decryption_nonce, 
                    file_info, metadata, is_deleted, updated_at, owner_id, pub_magic_metadata
             FROM files 
             WHERE owner_id = ?1 AND collection_id = ?2 AND is_deleted = 0
             ORDER BY file_id",
        )?;

        let files = stmt
            .query_map(params![user_id, collection_id], |row| {
                let file_info: String = row.get(4)?;
                let metadata: String = row.get(5)?;
                let pub_magic_metadata_json: Option<String> = row.get(9)?;

                let file_obj: crate::models::file::FileInfo = serde_json::from_str(&file_info)
                    .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?;

                let metadata_obj: crate::models::file::MetadataInfo =
                    serde_json::from_str(&metadata)
                        .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?;

                let pub_magic_metadata = match pub_magic_metadata_json {
                    Some(json) => Some(
                        serde_json::from_str(&json)
                            .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?,
                    ),
                    None => None,
                };

                let thumbnail = crate::models::file::FileInfo {
                    encrypted_data: None,
                    decryption_header: String::new(),
                    object_key: None,
                    size: None,
                };

                Ok(RemoteFile {
                    id: row.get(0)?,
                    collection_id: row.get(1)?,
                    owner_id: row.get(8)?,
                    encrypted_key: row.get(2)?,
                    key_decryption_nonce: row.get(3)?,
                    file: file_obj,
                    thumbnail,
                    metadata: metadata_obj,
                    is_deleted: row.get::<_, i32>(6)? != 0,
                    updated_at: row.get(7)?,
                    pub_magic_metadata,
                })
            })?
            .collect::<std::result::Result<Vec<_>, _>>()?;

        Ok(files)
    }

    pub fn update_sync_state(&self, user_id: i64, sync_type: &str, timestamp: i64) -> Result<()> {
        if sync_type.starts_with("collection_") {
            let collection_id = sync_type
                .strip_prefix("collection_")
                .and_then(|s| s.strip_suffix("_files"))
                .and_then(|s| s.parse::<i64>().ok())
                .ok_or_else(|| {
                    crate::Error::InvalidInput(format!("Invalid sync type: {sync_type}"))
                })?;

            let now = chrono::Utc::now().timestamp_micros();
            self.conn.execute(
                "INSERT OR REPLACE INTO collection_sync_state 
                 (user_id, collection_id, last_sync_time, updated_at)
                 VALUES (?1, ?2, ?3, ?4)",
                params![user_id, collection_id, timestamp, now],
            )?;
            return Ok(());
        }

        let column = match sync_type {
            "files" => "last_file_sync",
            "collections" => "last_collection_sync",
            "albums" => "last_album_sync",
            _ => return Err(crate::Error::InvalidInput("Invalid sync type".into())),
        };

        let query = format!(
            "INSERT OR REPLACE INTO sync_state (user_id, app, {column}) VALUES (?1, 'photos', ?2)
             ON CONFLICT(user_id, app) DO UPDATE SET {column} = ?2"
        );

        self.conn.execute(&query, params![user_id, timestamp])?;

        Ok(())
    }

    pub fn get_last_sync(&self, user_id: i64, sync_type: &str) -> Result<Option<i64>> {
        if sync_type.starts_with("collection_") {
            let collection_id = sync_type
                .strip_prefix("collection_")
                .and_then(|s| s.strip_suffix("_files"))
                .and_then(|s| s.parse::<i64>().ok())
                .ok_or_else(|| {
                    crate::Error::InvalidInput(format!("Invalid sync type: {sync_type}"))
                })?;

            let timestamp = self
                .conn
                .query_row(
                    "SELECT last_sync_time FROM collection_sync_state 
                     WHERE user_id = ?1 AND collection_id = ?2",
                    params![user_id, collection_id],
                    |row| row.get::<_, i64>(0),
                )
                .optional()?;

            return Ok(timestamp);
        }

        let column = match sync_type {
            "files" => "last_file_sync",
            "collections" => "last_collection_sync",
            "albums" => "last_album_sync",
            _ => return Err(crate::Error::InvalidInput("Invalid sync type".into())),
        };

        let query =
            format!("SELECT {column} FROM sync_state WHERE user_id = ?1 AND app = 'photos'");
        let mut stmt = self.conn.prepare(&query)?;

        let timestamp = stmt
            .query_row(params![user_id], |row| row.get::<_, Option<i64>>(0))
            .optional()?
            .flatten();

        Ok(timestamp)
    }

    pub fn mark_album_file_synced(&self, album_id: i64, file_id: i64) -> Result<()> {
        self.conn.execute(
            "UPDATE album_files SET synced_locally = 1 
             WHERE album_id = ?1 AND file_id = ?2",
            params![album_id, file_id],
        )?;

        Ok(())
    }

    pub fn clear_sync_state(&self, user_id: i64) -> Result<()> {
        self.conn.execute(
            "DELETE FROM sync_state WHERE user_id = ?1 AND app = 'photos'",
            params![user_id],
        )?;

        self.conn.execute(
            "DELETE FROM collection_sync_state WHERE user_id = ?1",
            params![user_id],
        )?;

        Ok(())
    }

    pub fn get_pending_downloads(&self, user_id: i64) -> Result<Vec<RemoteFile>> {
        let synced_count: i64 = self.conn.query_row(
            "SELECT COUNT(*) FROM files WHERE owner_id = ?1 AND is_synced_locally = 1",
            params![user_id],
            |row| row.get(0),
        )?;
        log::debug!("Files already synced locally: {synced_count}");

        let mut stmt = self.conn.prepare(
            "SELECT file_id, collection_id, encrypted_key, key_decryption_nonce, 
                    file_info, metadata, is_deleted, updated_at, owner_id, pub_magic_metadata
             FROM files 
             WHERE owner_id = ?1 AND is_deleted = 0 AND is_synced_locally = 0
             ORDER BY file_id",
        )?;

        let files = stmt
            .query_map(params![user_id], |row| {
                let file_info: String = row.get(4)?;
                let metadata: String = row.get(5)?;
                let pub_magic_metadata_json: Option<String> = row.get(9)?;

                let file_obj: crate::models::file::FileInfo = serde_json::from_str(&file_info)
                    .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?;

                let metadata_obj: crate::models::file::MetadataInfo =
                    serde_json::from_str(&metadata)
                        .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?;

                let pub_magic_metadata = match pub_magic_metadata_json {
                    Some(json) => Some(
                        serde_json::from_str(&json)
                            .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?,
                    ),
                    None => None,
                };

                let thumbnail = crate::models::file::FileInfo {
                    encrypted_data: None,
                    decryption_header: String::new(),
                    object_key: None,
                    size: None,
                };

                Ok(RemoteFile {
                    id: row.get(0)?,
                    collection_id: row.get(1)?,
                    owner_id: row.get(8)?,
                    encrypted_key: row.get(2)?,
                    key_decryption_nonce: row.get(3)?,
                    file: file_obj,
                    thumbnail,
                    metadata: metadata_obj,
                    is_deleted: row.get::<_, i32>(6)? != 0,
                    updated_at: row.get(7)?,
                    pub_magic_metadata,
                })
            })?
            .collect::<std::result::Result<Vec<_>, _>>()?;

        Ok(files)
    }

    pub fn mark_file_synced(&self, file_id: i64, local_path: Option<&str>) -> Result<()> {
        let rows_updated = if let Some(path) = local_path {
            self.conn.execute(
                "UPDATE files SET is_synced_locally = 1, local_path = ?2 
                 WHERE file_id = ?1",
                params![file_id, path],
            )?
        } else {
            self.conn.execute(
                "UPDATE files SET is_synced_locally = 1 
                 WHERE file_id = ?1",
                params![file_id],
            )?
        };

        log::debug!("Marked file {file_id} as synced locally, rows affected: {rows_updated}");

        Ok(())
    }

    pub fn find_duplicate_by_hash(&self, owner_id: i64, content_hash: &str) -> Result<Option<i64>> {
        let file_id: Option<i64> = self
            .conn
            .query_row(
                "SELECT file_id FROM files 
                 WHERE owner_id = ?1 AND content_hash = ?2 AND is_deleted = 0 
                 AND is_synced_locally = 1
                 LIMIT 1",
                params![owner_id, content_hash],
                |row| row.get(0),
            )
            .optional()?;

        Ok(file_id)
    }

    pub fn get_file_local_path(&self, file_id: i64) -> Result<Option<String>> {
        let path: Option<String> = self
            .conn
            .query_row(
                "SELECT local_path FROM files WHERE file_id = ?1",
                params![file_id],
                |row| row.get(0),
            )
            .optional()?;

        Ok(path)
    }
}

#[cfg(test)]
mod tests {
    use crate::{Error, Result, storage::Storage};

    #[test]
    fn malformed_collection_metadata_returns_error() -> Result<()> {
        let storage = Storage::new_in_memory()?;
        storage.conn().execute(
            "INSERT INTO collections
             (collection_id, owner, name, type, metadata, updated_at)
             VALUES (1, 1, 'album', 'album', '{', 0)",
            [],
        )?;

        assert!(matches!(
            storage.sync().get_collections(1),
            Err(Error::Serialization(_))
        ));
        Ok(())
    }
}
