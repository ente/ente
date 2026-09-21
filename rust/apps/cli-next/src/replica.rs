use anyhow::Result;
use ente_core::{
    Session,
    crypto::{Header, Key},
};

use ente_photos::{
    collections::{self, Collection, Visibility},
    files::{self, File, Location},
};

use crate::core_db::{
    self, Connection, Db, OptionalExtension, Row, SqliteError, SqliteResult, params,
    params_from_iter,
    types::{Type, Value},
};

pub struct Entry {
    pub file: File,
    pub album_ids: Vec<i64>,
}

pub struct Replica<'a> {
    db: &'a mut Db,
}

const COLLECTION_COLUMNS: &str = "id, name, kind, visibility, owner_id, updated_at, key";
const FILE_COLUMNS: &str = "f.id, f.owner_id, f.updated_at, f.name, f.kind, f.created_at, f.modified_at,
    f.latitude, f.longitude, f.caption, f.hash, f.date_time, f.offset_time, f.duration, f.width, f.height,
    f.visibility, f.key, f.header";

pub const SCHEMA: &str = "
    CREATE TABLE photos_sync (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        classical_collections_cursor INTEGER NOT NULL
    );
    CREATE TABLE photos_collections (
        id INTEGER PRIMARY KEY, name TEXT NOT NULL, kind TEXT NOT NULL,
        visibility TEXT NOT NULL, owner_id INTEGER NOT NULL, updated_at INTEGER NOT NULL,
        key BLOB NOT NULL, files_cursor INTEGER NOT NULL DEFAULT 0, files_synced_to INTEGER
    );
    CREATE INDEX photos_collections_name ON photos_collections(name);
    CREATE TABLE photos_files (
        id INTEGER PRIMARY KEY, owner_id INTEGER NOT NULL, updated_at INTEGER NOT NULL,
        name TEXT NOT NULL, kind TEXT NOT NULL, created_at INTEGER NOT NULL, modified_at INTEGER NOT NULL,
        latitude REAL, longitude REAL, caption TEXT, hash TEXT, date_time TEXT, offset_time TEXT,
        duration INTEGER, width INTEGER, height INTEGER, visibility TEXT NOT NULL, key BLOB NOT NULL, header BLOB NOT NULL
    );
    CREATE INDEX photos_files_name ON photos_files(name);
    CREATE TABLE photos_memberships (
        collection_id INTEGER NOT NULL REFERENCES photos_collections(id) ON DELETE CASCADE,
        file_id INTEGER NOT NULL REFERENCES photos_files(id) ON DELETE CASCADE,
        PRIMARY KEY(collection_id, file_id)
    );
    CREATE INDEX photos_memberships_file ON photos_memberships(file_id);
";

impl<'a> Replica<'a> {
    pub fn new(db: &'a mut Db) -> Self {
        Self { db }
    }

    pub async fn sync_collections(&mut self, session: &Session) -> Result<()> {
        let since = self.collections_cursor()?.unwrap_or(0);
        let page = collections::diff(session, since).await?;
        self.db.write(|tx| {
            for change in page.changes {
                match change.collection {
                    Some(c) => {
                        tx.execute("
                            INSERT INTO photos_collections (id, name, kind, visibility, owner_id, updated_at, key)
                            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
                            ON CONFLICT(id) DO UPDATE SET name=excluded.name, kind=excluded.kind,
                                visibility=excluded.visibility, owner_id=excluded.owner_id,
                                updated_at=excluded.updated_at, key=excluded.key
                        ", params![c.id, c.name, c.kind.name(), c.visibility.name(), c.owner_id, c.updated_at_micros, c.key.as_bytes()])?;
                    }
                    None => {
                        tx.execute(
                            "DELETE FROM photos_files WHERE id IN
                            (SELECT file_id FROM photos_memberships WHERE collection_id=?1)
                            AND NOT EXISTS (SELECT 1 FROM photos_memberships
                                WHERE file_id=photos_files.id AND collection_id!=?1)",
                            [change.id],
                        )?;
                        tx.execute("DELETE FROM photos_collections WHERE id=?1", [change.id])?;
                    }
                }
            }
            tx.execute("INSERT INTO photos_sync VALUES (1, ?1)
                ON CONFLICT(id) DO UPDATE SET classical_collections_cursor=excluded.classical_collections_cursor", [page.cursor])?;
            Ok(())
        })?;
        Ok(())
    }

    pub fn collections<T>(
        &self,
        selector: Option<&str>,
        limit: Option<i64>,
        read: impl FnOnce(&mut dyn Iterator<Item = SqliteResult<Collection>>) -> Result<T>,
    ) -> Result<T> {
        let mut sql = format!("SELECT {COLLECTION_COLUMNS} FROM photos_collections");
        let mut parameters = Vec::new();
        if let Some(selector) = selector {
            sql.push_str(" WHERE id=? OR name=?");
            parameters.push(canonical_id(selector));
            parameters.push(Value::Text(selector.to_owned()));
        }
        sql.push_str(" ORDER BY id");
        if let Some(limit) = limit {
            sql.push_str(" LIMIT ?");
            parameters.push(Value::Integer(limit));
        }
        self.db.read(|conn| {
            let mut statement = conn.prepare(&sql)?;
            let mut rows = statement.query_map(params_from_iter(parameters), read_collection)?;
            Ok(read(&mut rows))
        })?
    }

    pub async fn sync_files(
        &mut self,
        session: &Session,
        collections: &[Collection],
    ) -> Result<()> {
        for collection in collections {
            let (mut cursor, synced_to): (i64, Option<i64>) = self.db.read(|conn| {
                Ok(conn.query_row(
                    "SELECT files_cursor, files_synced_to FROM photos_collections WHERE id=?1",
                    [collection.id],
                    |row| Ok((row.get(0)?, row.get(1)?)),
                )?)
            })?;
            // Museum advances the collection timestamp on file and membership changes.
            if synced_to.is_some_and(|time| time >= collection.updated_at_micros) {
                continue;
            }
            loop {
                let page = files::diff(session, collection, cursor).await?;
                self.db.write(|tx| {
                    for change in page.changes {
                        match change.file {
                            Some(file) => {
                                save_file(tx, &file)?;
                                tx.execute(
                                    "INSERT OR IGNORE INTO photos_memberships VALUES (?1, ?2)",
                                    params![collection.id, file.id],
                                )?;
                            }
                            None => {
                                tx.execute("DELETE FROM photos_memberships WHERE collection_id=?1 AND file_id=?2",
                                    params![collection.id, change.id])?;
                                tx.execute(
                                    "DELETE FROM photos_files WHERE id=?1 AND NOT EXISTS
                                    (SELECT 1 FROM photos_memberships WHERE file_id=?1)",
                                    [change.id],
                                )?;
                            }
                        }
                    }
                    tx.execute(
                        "UPDATE photos_collections SET files_cursor=?1,
                        files_synced_to=CASE WHEN ?2 THEN files_synced_to ELSE ?3 END WHERE id=?4",
                        params![
                            page.cursor,
                            page.has_more,
                            collection.updated_at_micros,
                            collection.id
                        ],
                    )?;
                    Ok(())
                })?;
                cursor = page.cursor;
                if !page.has_more {
                    break;
                }
            }
        }
        Ok(())
    }

    pub fn files_synced_to(&self, collection_id: i64) -> core_db::Result<Option<i64>> {
        self.db.read(|conn| {
            Ok(conn.query_row(
                "SELECT files_synced_to FROM photos_collections WHERE id=?1",
                [collection_id],
                |row| row.get(0),
            )?)
        })
    }

    pub fn files<T>(
        &self,
        album: Option<i64>,
        selector: Option<&str>,
        limit: Option<i64>,
        read: impl FnOnce(&mut dyn Iterator<Item = SqliteResult<Entry>>) -> Result<T>,
    ) -> Result<T> {
        let album_ids = if album.is_some() {
            "json_array(m.collection_id)"
        } else {
            "json_group_array(m.collection_id ORDER BY m.collection_id)"
        };
        let mut sql = format!(
            "SELECT {FILE_COLUMNS}, {album_ids}
            FROM photos_files f JOIN photos_memberships m ON m.file_id=f.id"
        );
        let mut parameters = Vec::new();
        let mut conditions = Vec::new();
        if let Some(selector) = selector {
            conditions.push("(f.id=? OR f.name=?)");
            parameters.push(canonical_id(selector));
            parameters.push(Value::Text(selector.to_owned()));
        }
        if let Some(album) = album {
            conditions.push("m.collection_id=?");
            parameters.push(Value::Integer(album));
        }
        if !conditions.is_empty() {
            sql.push_str(" WHERE ");
            sql.push_str(&conditions.join(" AND "));
        }
        if album.is_some() {
            sql.push_str(" ORDER BY m.file_id");
        } else {
            sql.push_str(" GROUP BY f.id ORDER BY f.id");
        }
        if let Some(limit) = limit {
            sql.push_str(" LIMIT ?");
            parameters.push(Value::Integer(limit));
        }
        self.db.read(|conn| {
            let mut statement = conn.prepare(&sql)?;
            let mut rows = statement.query_map(params_from_iter(parameters), |row| {
                let ids: String = row.get(19)?;
                let album_ids = serde_json::from_str(&ids).map_err(|error| {
                    SqliteError::FromSqlConversionFailure(19, Type::Text, Box::new(error))
                })?;
                Ok(Entry {
                    file: read_file(row)?,
                    album_ids,
                })
            })?;
            Ok(read(&mut rows))
        })?
    }

    pub fn collections_cursor(&self) -> core_db::Result<Option<i64>> {
        self.db.read(|conn| {
            Ok(conn
                .query_row(
                    "SELECT classical_collections_cursor FROM photos_sync WHERE id=1",
                    [],
                    |row| row.get(0),
                )
                .optional()?)
        })
    }
}

fn canonical_id(selector: &str) -> Value {
    selector
        .parse::<i64>()
        .ok()
        .filter(|id| id.to_string() == selector)
        .map(Value::Integer)
        .unwrap_or(Value::Null)
}

fn read_collection(row: &Row<'_>) -> SqliteResult<Collection> {
    let key: Vec<u8> = row.get(6)?;
    Ok(Collection {
        id: row.get(0)?,
        name: row.get(1)?,
        kind: match row.get::<_, String>(2)?.as_str() {
            "favorites" => collections::Kind::Favorites,
            "uncategorized" => collections::Kind::Uncategorized,
            _ => collections::Kind::Album,
        },
        visibility: visibility(&row.get::<_, String>(3)?),
        owner_id: row.get(4)?,
        updated_at_micros: row.get(5)?,
        key: Key::try_from_slice(&key).map_err(|error| {
            SqliteError::FromSqlConversionFailure(6, Type::Blob, Box::new(error))
        })?,
    })
}

fn visibility(name: &str) -> Visibility {
    match name {
        "archived" => Visibility::Archived,
        "hidden" => Visibility::Hidden,
        _ => Visibility::Visible,
    }
}

fn read_file(row: &Row<'_>) -> SqliteResult<File> {
    let key: Vec<u8> = row.get(17)?;
    let header: Vec<u8> = row.get(18)?;
    let latitude: Option<f64> = row.get(7)?;
    let longitude: Option<f64> = row.get(8)?;
    Ok(File {
        id: row.get(0)?,
        owner_id: row.get(1)?,
        updated_at_micros: row.get(2)?,
        name: row.get(3)?,
        kind: match row.get::<_, String>(4)?.as_str() {
            "image" => files::Kind::Image,
            "video" => files::Kind::Video,
            "livephoto" => files::Kind::LivePhoto,
            _ => files::Kind::Unknown,
        },
        created_at_micros: row.get(5)?,
        modified_at_micros: row.get(6)?,
        location: latitude
            .zip(longitude)
            .map(|(latitude, longitude)| Location {
                latitude,
                longitude,
            }),
        caption: row.get(9)?,
        hash: row.get(10)?,
        date_time: row.get(11)?,
        offset_time: row.get(12)?,
        duration_seconds: row
            .get::<_, Option<i64>>(13)?
            .map(u64::try_from)
            .transpose()
            .map_err(|error| {
                SqliteError::FromSqlConversionFailure(13, Type::Integer, Box::new(error))
            })?,
        width: row.get(14)?,
        height: row.get(15)?,
        visibility: visibility(&row.get::<_, String>(16)?),
        key: Key::try_from_slice(&key).map_err(|error| {
            SqliteError::FromSqlConversionFailure(17, Type::Blob, Box::new(error))
        })?,
        header: Header::try_from_slice(&header).map_err(|error| {
            SqliteError::FromSqlConversionFailure(18, Type::Blob, Box::new(error))
        })?,
    })
}

fn save_file(connection: &Connection, file: &File) -> SqliteResult<()> {
    let duration = file
        .duration_seconds
        .map(i64::try_from)
        .transpose()
        .map_err(|error| SqliteError::ToSqlConversionFailure(Box::new(error)))?;
    connection.execute("INSERT INTO photos_files VALUES
        (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17,?18,?19)
        ON CONFLICT(id) DO UPDATE SET owner_id=excluded.owner_id, updated_at=excluded.updated_at,
            name=excluded.name, kind=excluded.kind, created_at=excluded.created_at, modified_at=excluded.modified_at,
            latitude=excluded.latitude, longitude=excluded.longitude, caption=excluded.caption, hash=excluded.hash,
            date_time=excluded.date_time, offset_time=excluded.offset_time, duration=excluded.duration,
            width=excluded.width, height=excluded.height, visibility=excluded.visibility, key=excluded.key, header=excluded.header
        WHERE excluded.updated_at >= photos_files.updated_at",
        params![file.id, file.owner_id, file.updated_at_micros, file.name, file.kind.name(), file.created_at_micros,
            file.modified_at_micros, file.location.as_ref().map(|l| l.latitude), file.location.as_ref().map(|l| l.longitude),
            file.caption, file.hash, file.date_time, file.offset_time, duration, file.width, file.height,
            file.visibility.name(), file.key.as_bytes(), file.header.as_bytes()])?;
    Ok(())
}
