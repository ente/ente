use std::collections::HashSet;

use anyhow::{Context, Result};
use ente_core::{
    Session, b64,
    crypto::{Key, hash},
};
use ente_photos::{
    collections::{self, Collection, RemoteCollection},
    files::{self, File, RemoteFile},
    source::Documents,
};
use serde::{Deserialize, Serialize, de::DeserializeOwned};

use crate::core_db::{
    self, Db, OptionalExtension, Row, SqliteError, SqliteResult, params, params_from_iter,
    types::{Type, Value},
};

pub const SCHEMA: &str = "
    CREATE TABLE photos_sync (id INTEGER PRIMARY KEY CHECK(id=1), cursor INTEGER NOT NULL);
    CREATE TABLE photos_collections (
        id INTEGER PRIMARY KEY, name TEXT, updated_at INTEGER NOT NULL,
        record TEXT NOT NULL, files_cursor INTEGER NOT NULL DEFAULT 0, files_synced_to INTEGER
    );
    CREATE INDEX photos_collections_name ON photos_collections(name);
    CREATE TABLE photos_files (
        collection_id INTEGER NOT NULL REFERENCES photos_collections(id) ON DELETE CASCADE,
        id INTEGER NOT NULL, name TEXT, updated_at INTEGER NOT NULL,
        record TEXT NOT NULL, failed INTEGER NOT NULL,
        PRIMARY KEY(collection_id,id)
    );
    CREATE INDEX photos_files_id ON photos_files(id,updated_at DESC);
    CREATE INDEX photos_files_name ON photos_files(name);
";

#[derive(Clone, Serialize, Deserialize)]
pub struct Record<R> {
    pub remote: R,
    pub documents: Option<Documents>,
    pub key: Option<String>,
    pub input_hash: String,
    pub failure: Option<String>,
}

pub type AlbumRecord = Record<RemoteCollection>;
pub type FileRecord = Record<RemoteFile>;

impl<R: Serialize> Record<R> {
    fn receive<E: RecordError>(
        remote: R,
        previous: Option<Self>,
        parent_key: &[u8],
        failed_inputs: &mut HashSet<String>,
        decrypt: impl FnOnce(&R) -> std::result::Result<(Key, Documents), E>,
    ) -> Result<Self> {
        let mut input = serde_json::to_value(&remote)?;
        if let Some(object) = input.as_object_mut() {
            object.retain(|name, _| {
                [
                    "encryptedKey",
                    "keyDecryptionNonce",
                    "name",
                    "encryptedName",
                    "nameDecryptionNonce",
                    "metadata",
                    "magicMetadata",
                    "pubMagicMetadata",
                    "sharedMagicMetadata",
                ]
                .contains(&name.as_str())
            });
            for name in [
                "metadata",
                "magicMetadata",
                "pubMagicMetadata",
                "sharedMagicMetadata",
            ] {
                if let Some(object) = object
                    .get_mut(name)
                    .and_then(serde_json::Value::as_object_mut)
                {
                    object.retain(|name, _| {
                        ["encryptedData", "decryptionHeader", "data", "header"]
                            .contains(&name.as_str())
                    });
                }
            }
        }
        let input_hash = b64::encode(&hash::hash(
            &serde_json::to_vec(&input)?,
            Some(32),
            Some(parent_key),
        )?);
        if let Some(mut previous) = previous
            && previous.input_hash == input_hash
            && (previous.documents.is_some() || failed_inputs.contains(&input_hash))
        {
            previous.remote = remote;
            return Ok(previous);
        }
        let (key, documents, failure) = match decrypt(&remote) {
            Ok((key, documents)) => (Some(b64::encode(key.as_bytes())), Some(documents), None),
            Err(error) if error.is_record_failure() => {
                failed_inputs.insert(input_hash.clone());
                (None, None, Some(error.to_string()))
            }
            Err(error) => return Err(error.into()),
        };
        Ok(Self {
            remote,
            key,
            documents,
            input_hash,
            failure,
        })
    }

    fn opened(&self) -> Result<(Key, &Documents)> {
        let documents = self.documents.as_ref().with_context(|| {
            self.failure
                .clone()
                .unwrap_or_else(|| "metadata is unavailable".into())
        })?;
        let key = Key::try_from_slice(&b64::decode(
            self.key.as_deref().context("decrypted record has no key")?,
        )?)?;
        Ok((key, documents))
    }
}

trait RecordError: std::error::Error + Send + Sync + 'static {
    fn is_record_failure(&self) -> bool;
}

fn decryption_failure(error: &ente_core::crypto::Error) -> bool {
    use ente_core::crypto::Error::*;
    matches!(
        error,
        InvalidKeyLength { .. }
            | InvalidNonceLength { .. }
            | InvalidHeaderLength { .. }
            | CiphertextTooShort { .. }
            | DecryptionFailed
            | StreamPullFailed
            | StreamTruncated
            | StreamTrailingData
            | SealedBoxOpenFailed
    )
}

impl RecordError for ente_collections::Error {
    fn is_record_failure(&self) -> bool {
        use ente_collections::Error::*;
        match self {
            Decode(_) | MissingKeyDecryptionNonce | InvalidCollection { .. } => true,
            Crypto(error) => decryption_failure(error),
            _ => false,
        }
    }
}

impl RecordError for files::Error {
    fn is_record_failure(&self) -> bool {
        match self {
            Self::Base64(_) => true,
            Self::Crypto(error) => decryption_failure(error),
            Self::Collections(error) => error.is_record_failure(),
            _ => false,
        }
    }
}

impl AlbumRecord {
    pub fn album(&self, user_id: i64) -> Result<Collection> {
        let (key, documents) = self.opened()?;
        Ok(collections::interpret(
            &self.remote,
            &key,
            documents,
            user_id,
        )?)
    }
}

impl FileRecord {
    pub fn file(&self, user_id: i64) -> Result<File> {
        let (key, documents) = self.opened()?;
        Ok(files::interpret(&self.remote, &key, documents, user_id)?)
    }
}

pub struct AlbumEntry {
    pub id: i64,
    pub name: Option<String>,
    pub value: Result<Collection>,
}

pub struct Entry {
    pub id: i64,
    pub name: Option<String>,
    pub file: Result<File>,
    pub album_ids: Vec<i64>,
}

pub struct Replica<'a> {
    pub db: &'a mut Db,
    user_id: i64,
    failed_inputs: HashSet<String>,
}

impl<'a> Replica<'a> {
    pub fn new(db: &'a mut Db, user_id: i64) -> Self {
        Self {
            db,
            user_id,
            failed_inputs: HashSet::new(),
        }
    }

    pub async fn sync_collections(&mut self, session: &Session) -> Result<()> {
        let page = ente_collections::client::diff(session, self.collections_cursor()?.unwrap_or(0))
            .await?;
        let mut changes = Vec::with_capacity(page.collections.len());
        for remote in page.collections {
            let id = remote.id;
            if remote.is_deleted == Some(true) {
                changes.push((id, None));
                continue;
            }
            let previous = self.album_record(id)?;
            let parent_key = if remote.owner.id == session.user_id {
                session.master_key.as_bytes().as_slice()
            } else {
                session.secret_key.as_bytes().as_slice()
            };
            let record =
                Record::receive(remote, previous, parent_key, &mut self.failed_inputs, |r| {
                    collections::decrypt(r, session)
                })?;
            changes.push((id, Some(record)));
        }
        self.db.write(|tx| {
            for (id, record) in changes {
                if let Some(record) = record {
                    save_album(tx, record, self.user_id)?;
                } else {
                    tx.execute("DELETE FROM photos_collections WHERE id=?1", [id])?;
                }
            }
            tx.execute(
                "INSERT INTO photos_sync VALUES(1,?1) ON CONFLICT(id) DO UPDATE SET cursor=excluded.cursor",
                [page.cursor],
            )?;
            Ok(())
        })?;
        Ok(())
    }

    pub fn retry_failed_albums(&mut self, session: &Session) -> Result<()> {
        let mut after = 0;
        loop {
            let ids: Vec<i64> = self.db.read(|db| {
                let mut query = db.prepare("SELECT id FROM photos_collections WHERE id>?1 AND json_extract(record,'$.failure') IS NOT NULL ORDER BY id LIMIT 128")?;
                Ok(query.query_map([after], |row| row.get(0))?.collect::<SqliteResult<_>>()?)
            })?;
            if ids.is_empty() {
                return Ok(());
            }
            for id in ids {
                after = id;
                self.retry_album(session, id)?;
            }
        }
    }

    pub fn retry_album(&mut self, session: &Session, id: i64) -> Result<()> {
        let Some(previous) = self.album_record(id)? else {
            return Ok(());
        };
        if previous.documents.is_some() && previous.failure.is_none() {
            return Ok(());
        }
        let parent_key = if previous.remote.owner.id == session.user_id {
            session.master_key.as_bytes().as_slice()
        } else {
            session.secret_key.as_bytes().as_slice()
        };
        let record = Record::receive(
            previous.remote.clone(),
            Some(previous),
            parent_key,
            &mut self.failed_inputs,
            |r| collections::decrypt(r, session),
        )?;
        self.db.write(|tx| save_album(tx, record, self.user_id))?;
        Ok(())
    }

    pub async fn sync_files(
        &mut self,
        session: &Session,
        collections: &[Collection],
    ) -> Result<()> {
        for collection in collections {
            self.sync_album_files(session, collection).await?;
        }
        Ok(())
    }

    pub async fn sync_album_files(&mut self, session: &Session, album: &Collection) -> Result<()> {
        let (mut cursor, synced_to): (i64, Option<i64>) = self.db.read(|db| {
            Ok(db.query_row(
                "SELECT files_cursor,files_synced_to FROM photos_collections WHERE id=?1",
                [album.id],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )?)
        })?;
        if synced_to.is_none_or(|time| time < album.updated_at_micros) {
            loop {
                let page = ente_collections::client::files_diff(session, album.id, cursor).await?;
                let mut changes = Vec::with_capacity(page.files.len());
                for remote in page.files {
                    let id = remote.id;
                    if remote.is_deleted() {
                        changes.push((id, None));
                        continue;
                    }
                    let previous = self.file_record(album.id, id)?;
                    let record = Record::receive(
                        remote,
                        previous,
                        album.key.as_bytes(),
                        &mut self.failed_inputs,
                        |r| files::decrypt(r, &album.key),
                    )?;
                    changes.push((id, Some(record)));
                }
                self.db.write(|tx| {
                    for (id, record) in changes {
                        if let Some(record) = record {
                            save_file(tx, album.id, record, self.user_id)?;
                        } else {
                            tx.execute(
                                "DELETE FROM photos_files WHERE collection_id=?1 AND id=?2",
                                params![album.id, id],
                            )?;
                        }
                    }
                    tx.execute(
                        "UPDATE photos_collections SET files_cursor=?1,files_synced_to=CASE WHEN ?2 THEN files_synced_to ELSE ?3 END WHERE id=?4",
                        params![page.cursor, page.has_more, album.updated_at_micros, album.id],
                    )?;
                    Ok(())
                })?;
                cursor = page.cursor;
                if !page.has_more {
                    break;
                }
            }
        }
        let mut after = 0;
        loop {
            let records: Vec<FileRecord> = self.db.read(|db| {
                let mut query = db.prepare("SELECT record FROM photos_files WHERE collection_id=?1 AND failed=1 AND id>?2 ORDER BY id LIMIT 128")?;
                Ok(query.query_map(params![album.id,after], |r| read_json(r,0))?.collect::<SqliteResult<_>>()?)
            })?;
            if records.is_empty() {
                break;
            }
            for previous in records {
                after = previous.remote.id;
                let record = Record::receive(
                    previous.remote.clone(),
                    Some(previous),
                    album.key.as_bytes(),
                    &mut self.failed_inputs,
                    |r| files::decrypt(r, &album.key),
                )?;
                self.db
                    .write(|tx| save_file(tx, album.id, record, self.user_id))?;
            }
        }
        Ok(())
    }

    pub fn album_record(&self, id: i64) -> Result<Option<AlbumRecord>> {
        Ok(self.db.read(|db| {
            Ok(db
                .query_row(
                    "SELECT record FROM photos_collections WHERE id=?1",
                    [id],
                    |r| read_json(r, 0),
                )
                .optional()?)
        })?)
    }

    pub fn file_record(&self, album: i64, id: i64) -> Result<Option<FileRecord>> {
        Ok(self.db.read(|db| {
            Ok(db
                .query_row(
                    "SELECT record FROM photos_files WHERE collection_id=?1 AND id=?2",
                    params![album, id],
                    |r| read_json(r, 0),
                )
                .optional()?)
        })?)
    }

    pub fn collections<T>(
        &self,
        selector: Option<&str>,
        limit: Option<i64>,
        read: impl FnOnce(&mut dyn Iterator<Item = SqliteResult<AlbumEntry>>) -> Result<T>,
    ) -> Result<T> {
        let mut sql = "SELECT record,name FROM photos_collections".to_owned();
        let mut parameters = Vec::new();
        if let Some(selector) = selector {
            sql.push_str(" WHERE id=? OR name=?");
            parameters.extend([canonical_id(selector), Value::Text(selector.to_owned())]);
        }
        sql.push_str(" ORDER BY id");
        if let Some(limit) = limit {
            sql.push_str(" LIMIT ?");
            parameters.push(Value::Integer(limit));
        }
        self.db.read(|db| {
            let mut statement = db.prepare(&sql)?;
            let mut rows = statement.query_map(params_from_iter(parameters), |row| {
                let record: AlbumRecord = read_json(row, 0)?;
                Ok(AlbumEntry {
                    id: record.remote.id,
                    name: row.get(1)?,
                    value: record.album(self.user_id),
                })
            })?;
            Ok(read(&mut rows))
        })?
    }

    pub fn files<T>(
        &self,
        album: Option<i64>,
        selector: Option<&str>,
        limit: Option<i64>,
        read: impl FnOnce(&mut dyn Iterator<Item = SqliteResult<Entry>>) -> Result<T>,
    ) -> Result<T> {
        let mut sql = "SELECT record,(SELECT json_group_array(collection_id ORDER BY collection_id) FROM photos_files m WHERE m.id=f.id".to_owned();
        let mut parameters = Vec::new();
        if let Some(album) = album {
            sql.push_str(" AND m.collection_id=?1");
            parameters.push(Value::Integer(album));
        }
        sql.push_str("),name FROM photos_files f WHERE ");
        if album.is_some() {
            sql.push_str("collection_id=?1");
        } else {
            sql.push_str("NOT EXISTS (SELECT 1 FROM photos_files newer WHERE newer.id=f.id AND (newer.updated_at>f.updated_at OR (newer.updated_at=f.updated_at AND newer.collection_id<f.collection_id)))");
        }
        if let Some(selector) = selector {
            sql.push_str(" AND (id=? OR name=?)");
            parameters.extend([canonical_id(selector), Value::Text(selector.into())]);
        }
        sql.push_str(" ORDER BY id");
        if let Some(limit) = limit {
            sql.push_str(" LIMIT ?");
            parameters.push(Value::Integer(limit));
        }
        self.db.read(|db| {
            let mut statement = db.prepare(&sql)?;
            let mut rows = statement.query_map(params_from_iter(parameters), |row| {
                let record: FileRecord = read_json(row, 0)?;
                Ok(Entry {
                    id: record.remote.id,
                    name: row.get(2)?,
                    file: record.file(self.user_id),
                    album_ids: read_json(row, 1)?,
                })
            })?;
            Ok(read(&mut rows))
        })?
    }

    pub fn files_synced_to(&self, id: i64) -> core_db::Result<Option<i64>> {
        self.db.read(|db| {
            Ok(db.query_row(
                "SELECT files_synced_to FROM photos_collections WHERE id=?1",
                [id],
                |r| r.get(0),
            )?)
        })
    }

    pub fn collections_cursor(&self) -> core_db::Result<Option<i64>> {
        self.db.read(|db| {
            Ok(db
                .query_row("SELECT cursor FROM photos_sync WHERE id=1", [], |r| {
                    r.get(0)
                })
                .optional()?)
        })
    }
}

fn save_album(
    tx: &crate::core_db::Connection,
    mut record: AlbumRecord,
    user_id: i64,
) -> core_db::Result<()> {
    let name = match record.album(user_id) {
        Ok(album) => {
            record.failure = None;
            Some(album.name)
        }
        Err(error) => {
            record.failure = Some(error.to_string());
            None
        }
    };
    let json = encode(&record)?;
    tx.execute(
        "INSERT INTO photos_collections(id,name,updated_at,record) VALUES(?1,?2,?3,?4) ON CONFLICT(id) DO UPDATE SET name=coalesce(excluded.name,photos_collections.name),updated_at=excluded.updated_at,record=excluded.record WHERE excluded.record!=photos_collections.record OR coalesce(excluded.name,photos_collections.name) IS NOT photos_collections.name",
        params![record.remote.id, name, record.remote.updation_time, json],
    )?;
    Ok(())
}

fn save_file(
    tx: &crate::core_db::Connection,
    album: i64,
    mut record: FileRecord,
    user_id: i64,
) -> core_db::Result<()> {
    let name = match record.file(user_id) {
        Ok(file) => {
            record.failure = None;
            Some(file.name)
        }
        Err(error) => {
            record.failure = Some(error.to_string());
            None
        }
    };
    let json = encode(&record)?;
    tx.execute(
        "INSERT INTO photos_files VALUES(?1,?2,?3,?4,?5,?6) ON CONFLICT(collection_id,id) DO UPDATE SET name=coalesce(excluded.name,photos_files.name),updated_at=excluded.updated_at,record=excluded.record,failed=excluded.failed WHERE excluded.updated_at>=photos_files.updated_at AND (excluded.record!=photos_files.record OR coalesce(excluded.name,photos_files.name) IS NOT photos_files.name OR excluded.failed!=photos_files.failed)",
        params![
            album,
            record.remote.id,
            name,
            record.remote.updation_time,
            json,
            record.failure.is_some()
        ],
    )?;
    Ok(())
}

pub fn encode(value: &impl Serialize) -> SqliteResult<String> {
    serde_json::to_string(value).map_err(|e| SqliteError::ToSqlConversionFailure(Box::new(e)))
}

pub fn read_json<T: DeserializeOwned>(row: &Row<'_>, column: usize) -> SqliteResult<T> {
    let text: String = row.get(column)?;
    serde_json::from_str(&text)
        .map_err(|e| SqliteError::FromSqlConversionFailure(column, Type::Text, Box::new(e)))
}

pub fn canonical_id(selector: &str) -> Value {
    selector
        .parse::<i64>()
        .ok()
        .filter(|id| id.to_string() == selector)
        .map(Value::Integer)
        .unwrap_or(Value::Null)
}
