use std::{fs, path::Path};

use anyhow::{Context, Result, ensure};
use rusqlite::{Connection, params};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use uuid::Uuid;

use crate::{
    legacy::read::Desktop,
    metadata::{Component, Role},
    names,
    store::{self, Album, JsonRecord, Location, Placement, Properties, Store},
};

#[derive(Serialize, Deserialize)]
pub struct AlbumRecord {
    pub album: Album,
    pub json: Option<JsonRecord>,
    pub legacy: Option<crate::legacy::read::AlbumInfo>,
}

#[derive(Serialize, Deserialize)]
pub struct Item {
    pub placement: Placement,
    pub components: Vec<store::Component>,
    pub json: Vec<JsonRecord>,
    pub legacy: Option<crate::legacy::read::Record>,
    pub leftover: bool,
}

pub struct Index {
    pub db: Connection,
    _directory: tempfile::TempDir,
}

impl Index {
    pub fn new(open: impl FnOnce(&Path) -> Result<Connection>) -> Result<Self> {
        let directory = tempfile::tempdir()?;
        let db = open(&directory.path().join("index.db"))?;
        db.execute_batch(
            "PRAGMA temp_store=MEMORY; PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF; BEGIN;",
        )?;
        db.execute_batch("
CREATE TABLE adoption_album(key TEXT PRIMARY KEY,id INTEGER NOT NULL,retained INTEGER NOT NULL,parent TEXT NOT NULL,folded TEXT NOT NULL,record TEXT NOT NULL);
CREATE UNIQUE INDEX adoption_album_id ON adoption_album(id) WHERE retained=0;
CREATE UNIQUE INDEX adoption_album_path ON adoption_album(parent,folded);
CREATE TABLE adoption_item(key TEXT PRIMARY KEY,album_key TEXT NOT NULL,file_id INTEGER NOT NULL,active INTEGER NOT NULL,origin TEXT NOT NULL,anchor TEXT NOT NULL,record TEXT NOT NULL);
CREATE UNIQUE INDEX adoption_membership ON adoption_item(album_key,file_id) WHERE active=1;
CREATE INDEX adoption_retained ON adoption_item(album_key,file_id,anchor);
CREATE INDEX adoption_file ON adoption_item(file_id,key);
CREATE TABLE adoption_path(path TEXT PRIMARY KEY,album_key TEXT NOT NULL,stem TEXT NOT NULL,kind TEXT NOT NULL,item_key TEXT NOT NULL);
CREATE INDEX adoption_stem ON adoption_path(album_key,stem);
")?;
        Ok(Self {
            db,
            _directory: directory,
        })
    }
}

pub fn save_album(index: &Index, record: &AlbumRecord) -> Result<()> {
    let a = &record.album;
    let (parent, name) = a.path.rsplit_once('/').unwrap_or(("", &a.path));
    index.db.execute("INSERT INTO adoption_album VALUES(?1,?2,?3,?4,?5,?6) ON CONFLICT(key) DO UPDATE SET parent=excluded.parent,folded=excluded.folded,record=excluded.record",params![a.key,a.id,a.retained,parent,names::folded(name),serde_json::to_string(record)?])?;
    Ok(())
}

pub fn save_item(index: &Index, album: &Album, item: &Item) -> Result<()> {
    index.db.execute("INSERT INTO adoption_item VALUES(?1,?2,?3,?4,?5,?6,?7) ON CONFLICT(key) DO UPDATE SET record=excluded.record",params![item.placement.id,album.key,item.placement.file,!item.placement.retained,if item.legacy.is_some(){"legacy"}else{"native"},item.components.first().map(|c|c.location.name.as_str()).unwrap_or(""),serde_json::to_string(item)?])?;
    Ok(())
}

pub fn claim(index: &Index, album: &Album, item: &str, name: &str, kind: &str) -> Result<()> {
    let path = names::folded(&format!("{}/{name}", album.path));
    let stem = names::folded(names::split(name, false).0);
    let overlap: bool=index.db.query_row("SELECT EXISTS(SELECT 1 FROM adoption_path WHERE item_key<>?1 AND (path=?2 OR (album_key=?3 AND stem=?4 AND kind<>'' AND ?5<>'' AND NOT(kind=?5 AND kind IN ('image','video')))))",params![item,path,album.key,stem,kind],|r|r.get(0))?;
    ensure!(
        !overlap,
        crate::Conflict(format!("overlapping media paths at {}/{name}", album.path))
    );
    index.db.execute("INSERT INTO adoption_path VALUES(?1,?2,?3,?4,?5) ON CONFLICT(path) DO UPDATE SET kind=excluded.kind",params![path,album.key,stem,kind,item])?;
    Ok(())
}

pub fn scan(root: &Path, index: &Index, desktop: Option<&Desktop>) -> Result<()> {
    for entry in fs::read_dir(root)? {
        let entry = entry?;
        if entry.file_name() == "Trash"
            && !entry.path().join(".meta/album_meta.json").try_exists()?
        {
            ensure!(
                entry.file_type()?.is_dir(),
                crate::Conflict("at Trash: expected directory".into())
            );
            for entry in fs::read_dir(entry.path())? {
                let entry = entry?;
                if entry.file_type()?.is_dir() {
                    scan_album(root, index, &entry.path(), true, desktop)?;
                }
            }
        } else if entry.file_type()?.is_dir() {
            scan_album(root, index, &entry.path(), false, desktop)?;
        }
    }
    Ok(())
}

fn scan_album(
    root: &Path,
    index: &Index,
    directory: &Path,
    retained: bool,
    desktop: Option<&Desktop>,
) -> Result<()> {
    let Some(record) = parse_album(root, directory, retained)? else {
        return Ok(());
    };
    let album = &record.album;
    let (parent, name) = album.path.rsplit_once('/').unwrap_or(("", &album.path));
    let (duplicate_id, duplicate_path): (bool, bool)=index.db.query_row("SELECT EXISTS(SELECT 1 FROM adoption_album WHERE id=?1 AND retained=0 AND ?2=0), EXISTS(SELECT 1 FROM adoption_album WHERE parent=?3 AND folded=?4)",params![album.id,retained,parent,names::folded(name)],|r|Ok((r.get(0)?,r.get(1)?)))?;
    ensure!(
        !duplicate_id,
        crate::Conflict(format!("active album ID {}", album.id))
    );
    ensure!(
        !duplicate_path,
        crate::Conflict(format!("duplicate native album path {}", album.path))
    );
    save_album(index, &record)?;
    let metadata = names::check(root, &format!("{}/metadata", album.path))?;
    if !metadata.try_exists()? {
        return Ok(());
    }
    ensure!(
        metadata.is_dir(),
        crate::Conflict("expected metadata directory".into())
    );
    for entry in fs::read_dir(metadata)? {
        let entry = entry?;
        if entry.path().extension().is_none_or(|e| e != "json") {
            continue;
        }
        let name = entry
            .file_name()
            .into_string()
            .map_err(|_| anyhow::anyhow!("claimed Ente sidecar name is not UTF-8"))?;
        let path = names::check(root, &format!("{}/metadata/{name}", album.path))?;
        let properties = Properties::read(&path)?;
        let bytes = fs::read(path)?;
        let value: Value = match serde_json::from_slice(&bytes) {
            Ok(value) => value,
            Err(_) if desktop.is_some_and(|d| d.common_sidecar(album.id, &name)) => continue,
            Err(error) => return Err(error.into()),
        };
        let Some(mut item) = parse_sidecar(album, &name, value, &bytes, properties)? else {
            continue;
        };
        let previous: Option<Item> = store::json(
            &index.db,
            "SELECT record FROM adoption_item WHERE album_key=?1 AND file_id=?2 AND (active=1 OR anchor=?3)",
            params![
                album.key,
                item.placement.file,
                item.components[0].location.name
            ],
        )?;
        if let Some(mut previous) = previous {
            ensure!(
                previous.placement.kind == item.placement.kind
                    && previous.components
                        == item
                            .components
                            .iter()
                            .map(|c| {
                                let mut c = c.clone();
                                c.placement = previous.placement.id.clone();
                                c
                            })
                            .collect::<Vec<_>>(),
                crate::Conflict(format!(
                    "contradictory native placement for file {}",
                    item.placement.file
                ))
            );
            let actual = item
                .json
                .iter()
                .find(|r| r.location.is_some())
                .context("missing sidecar")?;
            let slot = previous
                .json
                .iter_mut()
                .find(|r| r.role == actual.role)
                .context("missing component")?;
            ensure!(
                slot.location.is_none(),
                "duplicate component identity for file {}",
                item.placement.file
            );
            *slot = actual.clone();
            slot.owner = previous.placement.id.clone();
            item = previous;
        }
        for component in &item.components {
            claim(
                index,
                album,
                &item.placement.id,
                &component.location.name,
                &item.placement.kind,
            )?;
        }
        save_item(index, album, &item)?;
    }
    Ok(())
}

fn parse_album(root: &Path, directory: &Path, retained: bool) -> Result<Option<AlbumRecord>> {
    let path = directory.join("metadata.json");
    let Some(properties) = Properties::optional(&path)? else {
        return Ok(None);
    };
    let bytes = fs::read(&path)?;
    let record: Value = serde_json::from_slice(&bytes)?;
    let Some(identity) = record.get("ente") else {
        return Ok(None);
    };
    let folder = directory
        .strip_prefix(root)?
        .to_str()
        .context("claimed Ente album path is not UTF-8")?;
    names::check(root, &format!("{folder}/metadata.json"))?;
    let id = parse_id(identity, "albumID")?;
    let name = record["title"]
        .as_str()
        .context("album record has no title")?
        .to_owned();
    ensure!(
        [
            "album",
            "folder",
            "favorites",
            "uncategorized",
            "defaultHidden",
            "quicklink"
        ]
        .contains(&identity["type"].as_str().unwrap_or_default()),
        "unsupported album type in {folder}"
    );
    ensure!(
        ["visible", "archived", "hidden"]
            .contains(&identity["visibility"].as_str().unwrap_or_default()),
        "unsupported album visibility in {folder}"
    );
    ensure!(
        retained || !names::reserved(folder, true),
        "reserved active album path {folder}"
    );
    let album = Album {
        key: if retained {
            Uuid::new_v4().to_string()
        } else {
            format!("active:{id}")
        },
        id,
        retained,
        name,
        path: folder.into(),
    };
    let json = JsonRecord {
        owner: album.key.clone(),
        role: None,
        location: Some(Location {
            folder: album.key.clone(),
            name: "metadata.json".into(),
        }),
        value: record,
        hash: Some(digest(&bytes)?),
        properties: Some(properties),
    };
    Ok(Some(AlbumRecord {
        album,
        json: Some(json),
        legacy: None,
    }))
}

fn parse_sidecar(
    album: &Album,
    name: &str,
    record: Value,
    bytes: &[u8],
    properties: Properties,
) -> Result<Option<Item>> {
    let Some(identity) = record.get("ente") else {
        return Ok(None);
    };
    let file = parse_id(identity, "fileID")?;
    let display_name = identity["name"]
        .as_str()
        .context("file record has no name")?;
    chrono::DateTime::parse_from_rfc3339(
        identity["creationTime"]
            .as_str()
            .context("file record has no creationTime")?,
    )?;
    let kind = identity["type"]
        .as_str()
        .context("file record has no type")?;
    ensure!(
        ["image", "video", "livePhoto", "unknown"].contains(&kind),
        "unsupported file type for {file}"
    );
    let mut components: Vec<Component> = serde_json::from_value(identity["components"].clone())?;
    ensure!(
        if kind == "livePhoto" {
            components.len() == 2
                && components.iter().any(|c| c.role == Role::Image)
                && components.iter().any(|c| c.role == Role::Video)
        } else {
            components.len() == 1 && components[0].role == Role::Original
        },
        "invalid components for file {file}"
    );
    components.sort_by_key(|component| match component.role {
        Role::Original => 0,
        Role::Image => 1,
        Role::Video => 2,
    });
    for component in &components {
        names::relative(&component.path)?;
        ensure!(
            !component.path.contains('/') && !names::reserved(&component.path, false),
            "invalid component path for file {file}"
        );
        ensure!(
            ente_core::b64::decode(&component.hash)?.len() == 64,
            "invalid component hash for file {file}"
        );
    }
    ensure!(
        components.len() == 1
            || names::folded(&components[0].path) != names::folded(&components[1].path),
        "overlapping Live Photo components for file {file}"
    );
    let own: Role = serde_json::from_value(identity["component"].clone())?;
    let index = components
        .iter()
        .position(|c| c.role == own)
        .context("undeclared sidecar component")?;
    ensure!(
        record["title"].as_str() == Some(components[index].path.as_str())
            && name == format!("{}.json", components[index].path),
        "contradictory sidecar location for file {file}"
    );
    let kind = if kind == "livePhoto" {
        "livephoto"
    } else {
        kind
    };
    let placement = Placement {
        id: Uuid::new_v4().to_string(),
        album: album.id,
        file,
        retained: album.retained,
        name: display_name.into(),
        kind: kind.into(),
    };
    let mut json = Vec::new();
    let components = components
        .into_iter()
        .map(|component| {
            let actual = component.role == own;
            let mut value = record.clone();
            value["title"] = Value::String(component.path.clone());
            value["ente"]["component"] = serde_json::to_value(&component.role)?;
            json.push(JsonRecord {
                owner: placement.id.clone(),
                role: Some(component.role.clone()),
                location: actual.then(|| Location {
                    folder: album.key.clone(),
                    name: format!("metadata/{name}"),
                }),
                value,
                hash: if actual { Some(digest(bytes)?) } else { None },
                properties: actual.then(|| properties.clone()),
            });
            Ok(store::Component {
                placement: placement.id.clone(),
                role: component.role,
                location: Location {
                    folder: album.key.clone(),
                    name: component.path,
                },
                size: component.size,
                hash: component.hash,
                signature: None,
                properties: None,
                intended_time: None,
            })
        })
        .collect::<Result<Vec<_>>>()?;
    Ok(Some(Item {
        placement,
        components,
        json,
        legacy: None,
        leftover: false,
    }))
}

pub fn accept(index: &Index, store: &Store, bound: bool) -> Result<()> {
    let transaction = store.db.unchecked_transaction()?;
    store.db.execute_batch("DELETE FROM components; DELETE FROM json_records; DELETE FROM placements; DELETE FROM albums; DELETE FROM pending; DELETE FROM temporaries;")?;
    let mut after = String::new();
    while let Some(record) = store::json::<AlbumRecord>(
        &index.db,
        "SELECT record FROM adoption_album WHERE key>?1 ORDER BY key LIMIT 1",
        [&after],
    )? {
        after = record.album.key.clone();
        store.save_album(&record.album)?;
        if let Some(json) = record.json {
            store.save_json(&json)?;
        }
    }
    after.clear();
    while let Some(item) = store::json::<Item>(
        &index.db,
        "SELECT record FROM adoption_item WHERE key>?1 ORDER BY key LIMIT 1",
        [&after],
    )? {
        after = item.placement.id.clone();
        if item.leftover || item.components.is_empty() {
            continue;
        }
        store.save_placement(&item.placement)?;
        for component in item.components {
            store.save_component(&component)?;
        }
        for json in item.json {
            store.save_json(&json)?;
        }
    }
    store
        .db
        .execute("UPDATE export SET bound=?1 WHERE id=1", [bound])?;
    transaction.commit()?;
    Ok(())
}

pub fn digest(bytes: &[u8]) -> Result<String> {
    Ok(ente_core::b64::encode(&ente_core::crypto::hash::hash(
        bytes,
        Some(64),
        None,
    )?))
}

fn parse_id(value: &Value, field: &str) -> Result<i64> {
    let text = value[field]
        .as_str()
        .with_context(|| format!("missing {field}"))?;
    let id: i64 = text.parse().with_context(|| format!("invalid {field}"))?;
    ensure!(id > 0 && id.to_string() == text, "invalid {field}");
    Ok(id)
}
