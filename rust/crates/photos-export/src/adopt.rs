use std::{fs, path::Path};

use crate::metadata::{Component, Role};
use anyhow::{Context, Result, ensure};
use serde_json::Value;
use uuid::Uuid;

use super::{
    names,
    store::{Album, JsonRecord, Location, Placement, Properties, Store},
};

pub fn scan(root: &Path, store: &Store) -> Result<()> {
    store
        .db
        .execute_batch(
            "DELETE FROM components; DELETE FROM json_records; DELETE FROM placements; DELETE FROM albums; DELETE FROM pending; DELETE FROM temporaries;",
        )?;
    for entry in fs::read_dir(root)? {
        let entry = entry?;
        if entry.file_name() == "Trash" {
            ensure!(
                entry.file_type()?.is_dir(),
                super::Conflict("at Trash: expected directory".into())
            );
            for entry in fs::read_dir(entry.path())? {
                let entry = entry?;
                if entry.file_type()?.is_dir() {
                    album(root, store, &entry.path(), true)?;
                }
            }
        } else if entry.file_type()?.is_dir() {
            album(root, store, &entry.path(), false)?;
        }
    }
    Ok(())
}

fn album(root: &Path, store: &Store, directory: &Path, retained: bool) -> Result<()> {
    let path = directory.join("metadata.json");
    let Some(properties) = Properties::optional(&path)? else {
        return Ok(());
    };
    let bytes = fs::read(&path)?;
    let record: Value = serde_json::from_slice(&bytes)?;
    let Some(identity) = record.get("ente") else {
        return Ok(());
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
        retained || store.album(id, false)?.is_none(),
        super::Conflict(format!("active album ID {id}"))
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
    let (parent, name) = folder.rsplit_once('/').unwrap_or(("", folder));
    ensure!(
        retained || !names::reserved(name, true),
        "reserved active album path {folder}"
    );
    ensure!(
        names::available(store, parent, &[name.into()], &album.key, "album")?,
        super::Conflict(format!("overlapping album paths at {folder}"))
    );
    store.save_album(&album)?;
    store.save_json(&JsonRecord {
        owner: album.key.clone(),
        role: None,
        location: Some(Location {
            folder: album.key.clone(),
            name: "metadata.json".into(),
        }),
        value: record,
        hash: Some(digest(&bytes)?),
        properties: Some(properties),
    })?;
    let metadata = names::check(root, &format!("{folder}/metadata"))?;
    if !metadata.try_exists()? {
        return Ok(());
    }
    ensure!(
        metadata.is_dir(),
        super::Conflict(format!(
            "at {}: expected metadata directory",
            metadata.display()
        ))
    );
    for entry in fs::read_dir(metadata)? {
        let entry = entry?;
        if entry
            .path()
            .extension()
            .is_none_or(|extension| extension != "json")
        {
            continue;
        }
        let properties = Properties::read(&entry.path())?;
        let bytes = fs::read(entry.path())?;
        let record: Value = serde_json::from_slice(&bytes)?;
        let Some(identity) = record.get("ente") else {
            continue;
        };
        let name = entry
            .file_name()
            .into_string()
            .map_err(|_| anyhow::anyhow!("claimed Ente sidecar name is not UTF-8"))?;
        names::check(root, &format!("{folder}/metadata/{name}"))?;
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
        let mut components: Vec<Component> =
            serde_json::from_value(identity["components"].clone())?;
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
        let existing = if retained {
            let mut query = store
                .db
                .prepare(
                    "SELECT DISTINCT p.id,p.album,p.file,p.retained,p.name,p.kind FROM placements p JOIN components c ON c.placement=p.id WHERE p.album=?1 AND p.file=?2 AND p.retained=1 AND c.folder=?3",
                )?;
            let mut rows = query.query(rusqlite::params![id, file, album.key])?;
            let mut found = None;
            while let Some(row) = rows.next()? {
                let candidate = Placement::read(row)?;
                if store
                    .components(&candidate.id)?
                    .iter()
                    .map(super::store::Component::portable)
                    .eq(components.iter().cloned())
                {
                    found = Some(candidate);
                    break;
                }
            }
            found
        } else {
            store.placement(id, file)?
        };
        let fresh = existing.is_none();
        let placement = existing.unwrap_or_else(|| Placement {
            id: Uuid::new_v4().to_string(),
            album: id,
            file,
            retained,
            name: display_name.into(),
            kind: kind.into(),
        });
        if !fresh {
            ensure!(
                placement.kind == kind
                    && store
                        .components(&placement.id)?
                        .iter()
                        .all(|component| component.location.folder == album.key)
                    && store
                        .components(&placement.id)?
                        .iter()
                        .map(super::store::Component::portable)
                        .eq(components.iter().cloned()),
                super::Conflict(format!("active placement for file {file} in album {id}"))
            );
        }
        ensure!(
            !store
                .json_record(&placement.id, Some(&own))?
                .is_some_and(|record| record.location.is_some()),
            "duplicate component identity for file {file}"
        );
        let media_names: Vec<_> = components
            .iter()
            .map(|component| component.path.clone())
            .collect();
        ensure!(
            names::available(store, &album.key, &media_names, &placement.id, kind)?,
            super::Conflict(format!("overlapping media paths in {folder}"))
        );
        store.save_placement(&placement)?;
        if fresh {
            for component in &components {
                store.save_component(&super::store::Component {
                    placement: placement.id.clone(),
                    role: component.role.clone(),
                    location: Location {
                        folder: album.key.clone(),
                        name: component.path.clone(),
                    },
                    size: component.size,
                    hash: component.hash.clone(),
                    signature: None,
                    properties: None,
                    intended_time: None,
                })?;
                let mut fallback = record.clone();
                fallback["title"] = Value::String(component.path.clone());
                fallback["ente"]["component"] = serde_json::to_value(&component.role)?;
                store.save_json(&JsonRecord {
                    owner: placement.id.clone(),
                    role: Some(component.role.clone()),
                    location: None,
                    value: fallback,
                    hash: None,
                    properties: None,
                })?;
            }
        }
        store.save_json(&JsonRecord {
            owner: placement.id,
            role: Some(own),
            location: Some(Location {
                folder: album.key.clone(),
                name: format!("metadata/{name}"),
            }),
            value: record,
            hash: Some(digest(&bytes)?),
            properties: Some(properties),
        })?;
    }
    Ok(())
}

fn digest(bytes: &[u8]) -> Result<String> {
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
