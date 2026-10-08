use std::{
    path::Path,
    sync::{Mutex, MutexGuard},
    time::{SystemTime, UNIX_EPOCH},
};

use anyhow::{Context, Result, ensure};
use ente_photos::{collections::Collection, source::Documents};
use rusqlite::{Connection, OptionalExtension, Row, TransactionBehavior, params};
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use serde_json::Value;

use super::names;
use crate::{AdoptionRequired, CollectionEntry, metadata::Role, snapshot::FileSnapshot};

pub struct Store {
    pub db: Connection,
}

pub fn lock(store: &Mutex<Store>) -> Result<MutexGuard<'_, Store>> {
    store
        .lock()
        .map_err(|_| anyhow::anyhow!("export database mutex poisoned"))
}

pub fn json<T: DeserializeOwned>(
    db: &Connection,
    sql: &str,
    parameters: impl rusqlite::Params,
) -> Result<Option<T>> {
    let text: Option<String> = db.query_row(sql, parameters, |r| r.get(0)).optional()?;
    text.map(|text| serde_json::from_str(&text).map_err(Into::into))
        .transpose()
}

#[derive(Clone, Serialize, Deserialize)]
pub struct Album {
    pub key: String,
    pub id: i64,
    pub retained: bool,
    pub name: String,
    pub path: String,
}

impl Album {
    pub fn read(row: &Row<'_>) -> rusqlite::Result<Self> {
        Ok(Self {
            key: row.get(0)?,
            id: row.get(1)?,
            retained: row.get(2)?,
            name: row.get(3)?,
            path: row.get(4)?,
        })
    }
}

#[derive(Clone, Serialize, Deserialize)]
pub struct Placement {
    pub id: String,
    pub album: i64,
    pub file: i64,
    pub retained: bool,
    pub name: String,
    pub kind: String,
}

impl Placement {
    pub fn read(row: &Row<'_>) -> rusqlite::Result<Self> {
        Ok(Self {
            id: row.get(0)?,
            album: row.get(1)?,
            file: row.get(2)?,
            retained: row.get(3)?,
            name: row.get(4)?,
            kind: row.get(5)?,
        })
    }
}

#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Location {
    pub folder: String,
    pub name: String,
}

#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Component {
    pub placement: String,
    pub role: Role,
    pub location: Location,
    pub size: u64,
    pub hash: String,
    pub signature: Option<String>,
    pub properties: Option<Properties>,
    pub intended_time: Option<i64>,
}

impl Component {
    pub fn read(row: &Row<'_>) -> rusqlite::Result<Self> {
        Ok(Self {
            placement: row.get(0)?,
            role: read_role(row, 1)?,
            location: Location {
                folder: row.get(2)?,
                name: row.get(3)?,
            },
            size: row.get::<_, i64>(4)? as u64,
            hash: row.get(5)?,
            signature: row.get(6)?,
            properties: read_json(row, 7)?,
            intended_time: row.get(8)?,
        })
    }

    pub fn portable(&self) -> crate::metadata::Component {
        crate::metadata::Component {
            role: self.role.clone(),
            path: self.location.name.clone(),
            size: self.size,
            hash: self.hash.clone(),
        }
    }
}

fn read_role(row: &Row<'_>, index: usize) -> rusqlite::Result<Role> {
    let role: String = row.get(index)?;
    serde_json::from_value(Value::String(role)).map_err(|error| {
        rusqlite::Error::FromSqlConversionFailure(
            index,
            rusqlite::types::Type::Text,
            Box::new(error),
        )
    })
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Properties {
    pub size: u64,
    pub modified: i128,
}

impl Properties {
    pub fn read(path: &Path) -> Result<Self> {
        Self::optional(path)?.with_context(|| format!("missing file at {}", path.display()))
    }

    pub fn optional(path: &Path) -> Result<Option<Self>> {
        let metadata = match std::fs::symlink_metadata(path) {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(error) => return Err(error.into()),
        };
        ensure!(
            metadata.is_file(),
            super::Conflict(format!("at {}: expected a regular file", path.display()))
        );
        Ok(Some(Self {
            size: metadata.len(),
            modified: system_time(metadata.modified()?),
        }))
    }
}

pub fn system_time(time: SystemTime) -> i128 {
    match time.duration_since(UNIX_EPOCH) {
        Ok(duration) => duration.as_nanos() as i128,
        Err(error) => -(error.duration().as_nanos() as i128),
    }
}

#[derive(Clone, Serialize, Deserialize)]
pub struct JsonRecord {
    pub owner: String,
    pub role: Option<Role>,
    pub location: Option<Location>,
    pub value: Value,
    pub hash: Option<String>,
    pub properties: Option<Properties>,
}

impl JsonRecord {
    pub fn read(row: &Row<'_>) -> rusqlite::Result<Self> {
        Ok(Self {
            owner: row.get(0)?,
            role: if row.get::<_, String>(1)?.is_empty() {
                None
            } else {
                Some(read_role(row, 1)?)
            },
            location: row
                .get::<_, Option<String>>(2)?
                .map(|folder| {
                    Ok::<_, rusqlite::Error>(Location {
                        folder,
                        name: row.get(3)?,
                    })
                })
                .transpose()?,
            value: read_json(row, 4)?,
            hash: row.get(5)?,
            properties: read_json(row, 6)?,
        })
    }
}

#[derive(Serialize, Deserialize)]
pub struct AlbumSource {
    pub name: String,
    pub metadata: Value,
    pub warnings: Vec<String>,
}

#[derive(Clone)]
pub struct Temporary {
    pub location: Location,
    pub album: i64,
    pub file: Option<i64>,
}

#[derive(Clone)]
pub struct Pending {
    pub owner: String,
    pub album: i64,
    pub file: Option<i64>,
    pub retained: bool,
    pub name: String,
    pub kind: String,
    pub folder: String,
    pub names: Vec<String>,
    pub action: Option<Action>,
}

impl Pending {
    pub fn read(row: &Row<'_>) -> rusqlite::Result<Self> {
        let mut names = vec![row.get(7)?];
        if let Some(name) = row.get(8)? {
            names.push(name);
        }
        Ok(Self {
            owner: row.get(0)?,
            album: row.get(1)?,
            file: row.get(2)?,
            retained: row.get(3)?,
            name: row.get(4)?,
            kind: row.get(5)?,
            folder: row.get(6)?,
            names,
            action: read_json(row, 9)?,
        })
    }

    pub fn placement(&self) -> Result<Placement> {
        Ok(Placement {
            id: self.owner.clone(),
            album: self.album,
            file: self.file.context("album target is not a placement")?,
            retained: self.retained,
            name: self.name.clone(),
            kind: self.kind.clone(),
        })
    }

    pub fn album_path(&self) -> String {
        if self.folder.is_empty() {
            self.names[0].clone()
        } else {
            format!("{}/{}", self.folder, self.names[0])
        }
    }
}

#[derive(Clone, Serialize, Deserialize)]
pub enum Output {
    Media {
        role: Role,
        size: u64,
        hash: String,
        signature: Option<String>,
    },
    Json {
        role: Option<Role>,
        size: u64,
        hash: String,
    },
}

impl Output {
    pub fn identity(&self) -> (u64, &str) {
        match self {
            Self::Media { size, hash, .. } | Self::Json { size, hash, .. } => (*size, hash),
        }
    }
}

#[derive(Clone, Serialize, Deserialize)]
pub enum Action {
    Directory {
        source: Option<String>,
    },
    Publish {
        temporary: Location,
        destination: Location,
        output: Output,
    },
    Move {
        source: Location,
        destination: Location,
        role: Role,
        size: u64,
        hash: String,
    },
    Remove {
        location: Location,
        role: Option<Role>,
    },
}

impl Store {
    pub fn open(mut db: Connection, destination: &Path) -> Result<Self> {
        db.busy_timeout(std::time::Duration::from_secs(5))?;
        db.execute_batch(
            "PRAGMA foreign_keys = ON; PRAGMA temp_store = MEMORY; PRAGMA journal_mode = WAL;",
        )?;
        let transaction = db.transaction_with_behavior(TransactionBehavior::Immediate)?;
        let current: i64 =
            transaction.pragma_query_value(None, "user_version", |row| row.get(0))?;
        ensure!(
            current <= 1,
            "database version {current} is newer than this build supports (1)"
        );
        if current == 0 {
            transaction.execute_batch(SCHEMA)?;
            transaction.pragma_update(None, "user_version", 1)?;
            transaction.commit()?;
        } else {
            drop(transaction);
        }
        let connection = &db;
        let existing: Option<Vec<u8>> = connection
            .query_row("SELECT destination FROM export WHERE id=1", [], |r| {
                r.get(0)
            })
            .optional()?;
        if let Some(existing) = existing {
            ensure!(
                existing == destination.as_os_str().as_encoded_bytes(),
                AdoptionRequired("destination association does not match; use --adopt")
            );
        } else {
            connection.execute(
                "INSERT INTO export(id,destination) VALUES(1,?1)",
                [destination.as_os_str().as_encoded_bytes()],
            )?;
        }
        Ok(Self { db })
    }

    pub fn album(&self, id: i64, retained: bool) -> Result<Option<Album>> {
        Ok(self
            .db
            .query_row(
                "SELECT key,id,retained,name,path FROM albums WHERE id=?1 AND retained=?2 ORDER BY rowid LIMIT 1",
                params![id, retained],
                Album::read,
            )
            .optional()?)
    }

    pub fn folder(&self, key: &str) -> Result<Album> {
        Ok(self.db.query_row(
            "SELECT key,id,retained,name,path FROM albums WHERE key=?1",
            [key],
            Album::read,
        )?)
    }

    pub fn relative(&self, location: &Location) -> Result<String> {
        Ok(format!(
            "{}/{}",
            self.folder(&location.folder)?.path,
            location.name
        ))
    }

    pub fn save_album(&self, album: &Album) -> Result<()> {
        let (parent, name) = album.path.rsplit_once('/').unwrap_or(("", &album.path));
        self.db.execute(
            "INSERT INTO albums VALUES(?1,?2,?3,?4,?5,?6,?7) ON CONFLICT(key) DO UPDATE SET name=excluded.name,path=excluded.path,parent=excluded.parent,folded=excluded.folded WHERE albums.name<>excluded.name OR albums.path<>excluded.path",
            params![
                album.key,
                album.id,
                album.retained,
                album.name,
                album.path,
                parent,
                names::folded(name)
            ],
        )?;
        Ok(())
    }

    pub fn placement(&self, album: i64, file: i64) -> Result<Option<Placement>> {
        Ok(self
            .db
            .query_row(
                "SELECT id,album,file,retained,name,kind FROM placements WHERE album=?1 AND file=?2 AND retained=0",
                params![album, file],
                Placement::read,
            )
            .optional()?)
    }

    pub fn save_placement(&self, placement: &Placement) -> Result<()> {
        self.db.execute(
            "INSERT INTO placements VALUES(?1,?2,?3,?4,?5,?6) ON CONFLICT(id) DO UPDATE SET retained=excluded.retained,name=excluded.name,kind=excluded.kind WHERE placements.retained<>excluded.retained OR placements.name<>excluded.name OR placements.kind<>excluded.kind",
            params![
                placement.id,
                placement.album,
                placement.file,
                placement.retained,
                placement.name,
                placement.kind
            ],
        )?;
        Ok(())
    }

    pub fn components(&self, owner: &str) -> Result<Vec<Component>> {
        let mut query = self.db.prepare(
            "SELECT placement,role,folder,name,size,hash,signature,properties,intended_time FROM components WHERE placement=?1 ORDER BY role",
        )?;
        Ok(query
            .query_map([owner], Component::read)?
            .collect::<rusqlite::Result<_>>()?)
    }

    pub fn save_component(&self, component: &Component) -> Result<()> {
        self.db.execute(
            "INSERT INTO components VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11) ON CONFLICT(placement,role) DO UPDATE SET folder=excluded.folder,name=excluded.name,folded=excluded.folded,stem=excluded.stem,size=excluded.size,hash=excluded.hash,signature=excluded.signature,properties=excluded.properties,intended_time=excluded.intended_time WHERE components.folder<>excluded.folder OR components.name<>excluded.name OR components.size<>excluded.size OR components.hash<>excluded.hash OR components.signature IS NOT excluded.signature OR components.properties<>excluded.properties OR components.intended_time IS NOT excluded.intended_time",
            params![
                component.placement,
                component.role.name(),
                component.location.folder,
                component.location.name,
                names::folded(&component.location.name),
                names::folded(names::split(&component.location.name, false).0),
                component.size as i64,
                component.hash,
                component.signature,
                serde_json::to_string(&component.properties)?,
                component.intended_time
            ],
        )?;
        Ok(())
    }

    pub fn json_record(&self, owner: &str, role: Option<&Role>) -> Result<Option<JsonRecord>> {
        Ok(self
            .db
            .query_row(
                "SELECT owner,role,folder,name,value,hash,properties FROM json_records WHERE owner=?1 AND role=?2",
                params![owner, role.map_or("", Role::name)],
                JsonRecord::read,
            )
            .optional()?)
    }

    pub fn save_json(&self, record: &JsonRecord) -> Result<()> {
        let location = record.location.as_ref();
        let media = location
            .and_then(|location| location.name.strip_prefix("metadata/"))
            .and_then(|name| name.strip_suffix(".json"));
        self.db.execute(
            "INSERT INTO json_records VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9) ON CONFLICT(owner,role) DO UPDATE SET folder=excluded.folder,name=excluded.name,folded=excluded.folded,stem=excluded.stem,value=excluded.value,hash=excluded.hash,properties=excluded.properties WHERE json_records.folder IS NOT excluded.folder OR json_records.name IS NOT excluded.name OR json_records.value<>excluded.value OR json_records.hash IS NOT excluded.hash OR json_records.properties<>excluded.properties",
            params![
                record.owner,
                record.role.as_ref().map_or("", Role::name),
                location.map(|l| &l.folder),
                location.map(|l| &l.name),
                media.map(names::folded),
                media.map(|name| names::folded(names::split(name, false).0)),
                serde_json::to_string(&record.value)?,
                record.hash,
                serde_json::to_string(&record.properties)?
            ],
        )?;
        Ok(())
    }

    pub fn pending(&self, owner: &str) -> Result<Option<Pending>> {
        Ok(self
            .db
            .query_row(
                "SELECT owner,album,file,retained,name,kind,folder,name1,name2,action FROM pending WHERE owner=?1",
                [owner],
                Pending::read,
            )
            .optional()?)
    }

    pub fn pending_file(&self, album: i64, file: i64) -> Result<Option<Pending>> {
        Ok(self
            .db
            .query_row(
                "SELECT owner,album,file,retained,name,kind,folder,name1,name2,action FROM pending WHERE album=?1 AND file=?2 ORDER BY retained DESC LIMIT 1",
                params![album, file],
                Pending::read,
            )
            .optional()?)
    }

    pub fn save_pending(&self, pending: &Pending) -> Result<()> {
        let first = &pending.names[0];
        let second = pending.names.get(1);
        self.db.execute(
            "INSERT INTO pending VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14) ON CONFLICT(owner) DO UPDATE SET retained=excluded.retained,name=excluded.name,kind=excluded.kind,folder=excluded.folder,name1=excluded.name1,name2=excluded.name2,folded1=excluded.folded1,folded2=excluded.folded2,stem1=excluded.stem1,stem2=excluded.stem2,action=excluded.action",
            params![
                pending.owner,
                pending.album,
                pending.file,
                pending.retained,
                pending.name,
                pending.kind,
                pending.folder,
                first,
                second,
                names::folded(first),
                second.map(|name| names::folded(name)),
                names::folded(names::split(first, pending.file.is_none()).0),
                second.map(|name| names::folded(names::split(name, false).0)),
                serde_json::to_string(&pending.action)?
            ],
        )?;
        Ok(())
    }

    pub fn clear_pending(&self, owner: &str) -> Result<()> {
        self.db
            .execute("DELETE FROM pending WHERE owner=?1", [owner])?;
        self.db
            .execute(
                "DELETE FROM json_records WHERE owner=?1 AND folder IS NULL AND NOT EXISTS(SELECT 1 FROM components WHERE placement=?1)",
                [owner],
            )?;
        Ok(())
    }

    pub fn temporary(&self, temporary: &Temporary) -> Result<()> {
        self.db.execute(
            "INSERT INTO temporaries VALUES(?1,?2,?3,?4)",
            params![
                temporary.location.name,
                temporary.location.folder,
                temporary.album,
                temporary.file
            ],
        )?;
        Ok(())
    }
    pub fn reset_desired(&self) -> Result<()> {
        self.db.execute_batch(RUN_SCHEMA)?;
        Ok(())
    }

    pub fn desired_album(&self, entry: &CollectionEntry) -> Result<()> {
        self.db.execute(
            "INSERT INTO desired_albums(id,name,present,favorites) VALUES(?1,?2,1,?3) ON CONFLICT(id) DO UPDATE SET name=excluded.name,present=1,favorites=excluded.favorites",
            params![entry.id, entry.name, entry.favorites],
        )?;
        Ok(())
    }

    pub fn snapshot_album(
        &self,
        album: &Collection,
        documents: &Documents,
        user_id: i64,
    ) -> Result<()> {
        let (metadata, warnings) = crate::metadata::album(album, documents, user_id)?;
        let source = AlbumSource {
            name: album.name.clone(),
            metadata,
            warnings,
        };
        self.db.execute(
            "INSERT INTO album_sources VALUES(?1,?2) ON CONFLICT(id) DO UPDATE SET record=excluded.record WHERE album_sources.record<>excluded.record",
            params![album.id, serde_json::to_string(&source)?],
        )?;
        Ok(())
    }

    pub fn snapshot_file(&self, file: &FileSnapshot) -> Result<()> {
        self.db.execute(
            "INSERT INTO sources VALUES(?1,?2) ON CONFLICT(file) DO UPDATE SET record=excluded.record WHERE sources.record<>excluded.record",
            params![file.id, serde_json::to_string(file)?],
        )?;
        Ok(())
    }
}

const SCHEMA: &str = "
CREATE TABLE export (id INTEGER PRIMARY KEY CHECK(id=1), destination BLOB NOT NULL, bound INTEGER NOT NULL DEFAULT 0);
CREATE TABLE albums (key TEXT PRIMARY KEY, id INTEGER NOT NULL, retained INTEGER NOT NULL, name TEXT NOT NULL, path TEXT NOT NULL UNIQUE, parent TEXT NOT NULL, folded TEXT NOT NULL);
CREATE UNIQUE INDEX active_album ON albums(id) WHERE retained=0;
CREATE UNIQUE INDEX album_names ON albums(parent,folded);
CREATE TABLE placements (id TEXT PRIMARY KEY, album INTEGER NOT NULL, file INTEGER NOT NULL, retained INTEGER NOT NULL, name TEXT NOT NULL, kind TEXT NOT NULL);
CREATE UNIQUE INDEX active_placement ON placements(album,file) WHERE retained=0;
CREATE INDEX reusable_media ON placements(file,retained);
CREATE TABLE components (placement TEXT NOT NULL, role TEXT NOT NULL, folder TEXT NOT NULL, name TEXT NOT NULL, folded TEXT NOT NULL, stem TEXT NOT NULL, size INTEGER NOT NULL, hash TEXT NOT NULL, signature TEXT, properties TEXT NOT NULL, intended_time INTEGER, PRIMARY KEY(placement,role));
CREATE INDEX component_names ON components(folder,folded);
CREATE INDEX component_stems ON components(folder,stem);
CREATE TABLE json_records (owner TEXT NOT NULL, role TEXT NOT NULL, folder TEXT, name TEXT, folded TEXT, stem TEXT, value TEXT NOT NULL, hash TEXT, properties TEXT NOT NULL, PRIMARY KEY(owner,role));
CREATE INDEX json_names ON json_records(folder,folded);
CREATE INDEX json_stems ON json_records(folder,stem);
CREATE TABLE pending (owner TEXT PRIMARY KEY, album INTEGER NOT NULL, file INTEGER, retained INTEGER NOT NULL, name TEXT NOT NULL, kind TEXT NOT NULL, folder TEXT NOT NULL, name1 TEXT NOT NULL, name2 TEXT, folded1 TEXT NOT NULL, folded2 TEXT, stem1 TEXT NOT NULL, stem2 TEXT, action TEXT NOT NULL);
CREATE INDEX pending_file ON pending(album,file);
CREATE INDEX pending_temporary ON pending(json_extract(action,'$.Publish.temporary.name'));
CREATE INDEX pending_name1 ON pending(folder,folded1);
CREATE INDEX pending_name2 ON pending(folder,folded2);
CREATE INDEX pending_stem1 ON pending(folder,stem1);
CREATE INDEX pending_stem2 ON pending(folder,stem2);
CREATE TABLE temporaries (name TEXT PRIMARY KEY, folder TEXT NOT NULL, album INTEGER NOT NULL, file INTEGER);
CREATE INDEX temporary_file ON temporaries(file);
CREATE INDEX temporary_folder ON temporaries(folder);
CREATE TABLE album_sources (id INTEGER PRIMARY KEY, record TEXT NOT NULL);
CREATE TABLE sources (file INTEGER PRIMARY KEY, record TEXT NOT NULL);
";

const RUN_SCHEMA: &str = "
CREATE TEMP TABLE desired_albums (id INTEGER PRIMARY KEY, name TEXT, present INTEGER NOT NULL DEFAULT 0, favorites INTEGER NOT NULL DEFAULT 0, selected INTEGER NOT NULL DEFAULT 0, ready INTEGER NOT NULL DEFAULT 0, failure TEXT);
CREATE TEMP TABLE desired_files (album INTEGER NOT NULL, file INTEGER NOT NULL, favorited INTEGER, completed INTEGER NOT NULL DEFAULT 0, failure TEXT, claimed INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(album,file));
CREATE INDEX desired_file_id ON desired_files(file,album);
CREATE INDEX eligible_files ON desired_files(file) WHERE failure IS NULL AND claimed=0;
CREATE TEMP TABLE chosen_files (file INTEGER PRIMARY KEY, album INTEGER NOT NULL, version INTEGER NOT NULL);
CREATE TEMP TABLE favorites (file INTEGER PRIMARY KEY);
CREATE TEMP TABLE outcomes (unit TEXT PRIMARY KEY, conflict INTEGER NOT NULL);
CREATE TEMP TABLE events (placement TEXT PRIMARY KEY, exported INTEGER NOT NULL DEFAULT 0, metadata_updated INTEGER NOT NULL DEFAULT 0, renamed INTEGER NOT NULL DEFAULT 0, retained INTEGER NOT NULL DEFAULT 0);
";

fn read_json<T: DeserializeOwned>(row: &Row<'_>, column: usize) -> rusqlite::Result<T> {
    let text: String = row.get(column)?;
    serde_json::from_str(&text).map_err(|e| {
        rusqlite::Error::FromSqlConversionFailure(column, rusqlite::types::Type::Text, Box::new(e))
    })
}
