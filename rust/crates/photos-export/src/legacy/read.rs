use std::{collections::BTreeMap, fs, path::Path};

use anyhow::{Context, Result, ensure};
use rusqlite::params;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use super::Failures;
use crate::adopt::{self, AlbumRecord, Index, Item};
use crate::store::{self, Album, Placement};
use crate::{metadata::Role, names, store::Properties};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct GoAlbum {
    id: i64,
    #[serde(rename = "ownerID")]
    owner_id: i64,
    album_name: String,
    #[serde(default, rename = "accountOwnerIDs")]
    account_owner_ids: Vec<i64>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct GoInfo {
    id: i64,
    #[serde(rename = "ownerID")]
    owner_id: i64,
    file_names: Vec<String>,
    hash: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Desktop {
    pub version: u32,
    pub collection_export_names: BTreeMap<String, String>,
    pub file_export_names: BTreeMap<String, String>,
}

#[derive(Clone, Serialize, Deserialize)]
pub struct Part {
    pub name: String,
    pub role: Option<Role>,
}

#[derive(Clone, Serialize, Deserialize)]
pub struct Record {
    pub album: i64,
    pub file: i64,
    pub owner: Option<i64>,
    pub name: String,
    pub hash: Option<String>,
    pub parts: Vec<Part>,
    pub go_record: Option<String>,
    pub desktop: bool,
}

#[derive(Serialize, Deserialize)]
pub struct AlbumInfo {
    pub owner: Option<i64>,
    pub go: bool,
}

pub fn recognized(root: &Path) -> Result<bool> {
    if !root.is_dir() {
        return Ok(false);
    }
    if root.join("export_status.json").try_exists()? {
        return Ok(true);
    }
    for entry in fs::read_dir(root)? {
        let path = entry?.path().join(".meta");
        if path.is_dir() && path.join("album_meta.json").try_exists()? {
            return Ok(true);
        }
    }
    Ok(false)
}

pub fn desktop(root: &Path) -> Result<Option<Desktop>> {
    let manifest = names::check(root, "export_status.json")?;
    if !manifest.try_exists()? {
        return Ok(None);
    }
    Ok(Some(json(&manifest)?))
}

pub fn scan(
    root: &Path,
    index: &Index,
    user: i64,
    desktop: Option<&Desktop>,
    failures: &mut Failures,
) -> Result<()> {
    if let Some(desktop) = desktop {
        let result = (|| {
            ensure!(
                desktop.version == 5,
                "unsupported Desktop export version {}",
                desktop.version
            );
            for (id, path) in &desktop.collection_export_names {
                let result = (|| {
                    let id = id_string(id)?;
                    album(root, index, id, path, path, None, false)
                })();
                failures.record(result, path)?;
            }
            for (key, name) in &desktop.file_export_names {
                let result = (|| {
                    let parts: Vec<_> = key.split('_').collect();
                    ensure!(parts.len() == 3, "invalid Desktop file identity");
                    let file = id_string(parts[0])?;
                    let album = id_string(parts[1])?;
                    id_string(parts[2])?;
                    let mapped: bool = index.db.query_row(
                        "SELECT EXISTS(SELECT 1 FROM adoption_album WHERE id=?1 AND retained=0)",
                        [album],
                        |r| r.get(0),
                    )?;
                    if !mapped && desktop.collection_export_names.contains_key(parts[1]) {
                        return Ok(());
                    }
                    let paths = if name.starts_with('{') {
                        #[derive(Deserialize)]
                        struct Pair {
                            image: String,
                            video: String,
                        }
                        let pair: Pair = serde_json::from_str(name)?;
                        vec![
                            Part {
                                name: pair.image,
                                role: Some(Role::Image),
                            },
                            Part {
                                name: pair.video,
                                role: Some(Role::Video),
                            },
                        ]
                    } else {
                        vec![Part {
                            name: name.clone(),
                            role: Some(Role::Original),
                        }]
                    };
                    let record = Record {
                        album,
                        file,
                        owner: None,
                        name: paths[0].name.clone(),
                        hash: None,
                        parts: paths,
                        go_record: None,
                        desktop: true,
                    };
                    insert(root, index, &record)
                })();
                failures.record(result, key)?;
            }
            Ok(())
        })();
        failures.record(result, "export_status.json")?;
    }
    for entry in fs::read_dir(root)? {
        let entry = entry?;
        let meta = entry.path().join(".meta");
        if !meta.is_dir() {
            continue;
        }
        let identity = meta.join("album_meta.json");
        if !identity.try_exists()? {
            let result = (|| {
                let folder = entry
                    .file_name()
                    .into_string()
                    .map_err(|_| anyhow::anyhow!("legacy album path is not UTF-8"))?;
                let meta = names::check(root, &format!("{folder}/.meta"))?;
                for sidecar in fs::read_dir(meta)? {
                    let sidecar = sidecar?;
                    if !sidecar.path().extension().is_some_and(|s| s == "json") {
                        continue;
                    }
                    let name = sidecar
                        .file_name()
                        .into_string()
                        .map_err(|_| anyhow::anyhow!("legacy sidecar name is not UTF-8"))?;
                    let path = names::check(root, &format!("{folder}/.meta/{name}"))?;
                    if json::<Value>(&path)
                        .ok()
                        .is_some_and(|value| value["info"]["id"].as_i64().is_some())
                    {
                        anyhow::bail!("Go file identities remain without album_meta.json");
                    }
                }
                Ok(())
            })();
            failures.record(result, &entry.path().display().to_string())?;
            continue;
        }
        let path = entry
            .file_name()
            .into_string()
            .map_err(|_| anyhow::anyhow!("legacy album path is not UTF-8"))?;
        let result = (|| {
            names::check(root, &format!("{path}/.meta/album_meta.json"))?;
            let record: GoAlbum = json(&identity)?;
            ensure!(
                record.account_owner_ids.is_empty() || record.account_owner_ids.contains(&user),
                "legacy account owners exclude the selected account"
            );
            ensure!(record.owner_id > 0, "invalid album owner");
            album(
                root,
                index,
                record.id,
                &path,
                &record.album_name,
                Some(record.owner_id),
                true,
            )?;
            for entry in fs::read_dir(identity.parent().context("missing metadata parent")?)? {
                let entry = entry?;
                if entry.file_name() == "album_meta.json"
                    || entry.path().extension().is_none_or(|s| s != "json")
                {
                    continue;
                }
                let name = entry
                    .file_name()
                    .into_string()
                    .map_err(|_| anyhow::anyhow!("legacy sidecar name is not UTF-8"))?;
                let result = (|| {
                    names::check(root, &format!("{path}/.meta/{name}"))?;
                    let value: Value = json(&entry.path())?;
                    let Some(info) = value.get("info") else {
                        return Ok(());
                    };
                    let info: GoInfo = serde_json::from_value(info.clone())?;
                    ensure!(info.owner_id > 0, "invalid file owner");
                    let title = value["title"]
                        .as_str()
                        .context("missing legacy file title")?
                        .to_owned();
                    let record = Record {
                        album: record.id,
                        file: info.id,
                        owner: Some(info.owner_id),
                        name: title,
                        hash: info.hash,
                        parts: info
                            .file_names
                            .into_iter()
                            .map(|name| Part { name, role: None })
                            .collect(),
                        go_record: Some(format!(".meta/{name}")),
                        desktop: false,
                    };
                    insert(root, index, &record)
                })();
                failures.record(result, &format!("{path}/.meta/{name}"))?;
            }
            Ok(())
        })();
        failures.record(result, &path)?;
    }
    Ok(())
}

fn album(
    root: &Path,
    index: &Index,
    id: i64,
    path: &str,
    name: &str,
    owner: Option<i64>,
    go: bool,
) -> Result<()> {
    ensure!(id > 0, "invalid album ID");
    leaf(path)?;
    let previous: Option<AlbumRecord> = store::json(
        &index.db,
        "SELECT record FROM adoption_album WHERE id=?1 AND retained=0",
        [id],
    )?;
    let mut record = if let Some(record) = previous {
        ensure!(record.legacy.is_none(), "duplicate legacy album identity");
        record
    } else {
        let directory = names::check(root, path)?;
        ensure!(
            !directory.try_exists()? || directory.is_dir(),
            "legacy album is not a directory"
        );
        let occupied: bool = index.db.query_row(
            "SELECT EXISTS(SELECT 1 FROM adoption_album WHERE parent='' AND folded=?1)",
            [names::folded(path)],
            |r| r.get(0),
        )?;
        ensure!(!occupied, "overlapping legacy album path");
        AlbumRecord {
            album: Album {
                key: format!("active:{id}"),
                id,
                retained: false,
                name: name.into(),
                path: path.into(),
            },
            json: None,
            legacy: None,
        }
    };
    let metadata = names::check(root, &format!("{}/metadata", record.album.path))?;
    ensure!(
        !metadata.try_exists()? || metadata.is_dir(),
        "required metadata directory is occupied"
    );
    let json = names::check(root, &format!("{}/metadata.json", record.album.path))?;
    ensure!(
        !json.try_exists()? || record.json.is_some(),
        "required metadata.json is occupied"
    );
    record.legacy = Some(AlbumInfo { owner, go });
    adopt::save_album(index, &record)
}

fn insert(root: &Path, index: &Index, record: &Record) -> Result<()> {
    ensure!(
        record.file > 0 && (1..=2).contains(&record.parts.len()),
        "invalid legacy file identity or components"
    );
    let album: AlbumRecord = store::json(
        &index.db,
        "SELECT record FROM adoption_album WHERE id=?1 AND retained=0",
        [record.album],
    )?
    .context("file has no valid album mapping")?;
    if let Some(existing) = store::json::<Item>(
        &index.db,
        "SELECT record FROM adoption_item WHERE album_key=?1 AND file_id=?2 AND active=1",
        params![album.album.key, record.file],
    )? {
        ensure!(existing.legacy.is_none(), "duplicate legacy membership");
        return Ok(());
    }
    let folder = album.album;
    for part in &record.parts {
        leaf(&part.name)?;
        if store::json::<Item>(&index.db,"SELECT i.record FROM adoption_path p JOIN adoption_item i ON i.key=p.item_key WHERE p.path=?1 AND i.origin='native'",[names::folded(&format!("{}/{}",folder.path,part.name))])?.is_some() { return Ok(()) }
    }
    let item = Item {
        placement: Placement {
            id: format!("legacy:{}:{}", record.album, record.file),
            album: record.album,
            file: record.file,
            retained: false,
            name: record.name.clone(),
            kind: String::new(),
        },
        components: Vec::new(),
        json: Vec::new(),
        legacy: Some(record.clone()),
        leftover: false,
    };
    let mut claimed = Vec::new();
    for part in &record.parts {
        ensure!(
            !["metadata", "metadata.json"].contains(&names::folded(&part.name).as_str()),
            "legacy media occupies a required metadata path"
        );
        ensure!(
            !claimed.contains(&names::folded(&part.name)),
            "duplicate legacy component path"
        );
        claimed.push(names::folded(&part.name));
        Properties::optional(&names::check(
            root,
            &format!("{}/{}", folder.path, part.name),
        )?)?;
        adopt::claim(index, &folder, &item.placement.id, &part.name, "")?;
        let sidecar = Properties::optional(&names::check(
            root,
            &format!("{}/metadata/{}.json", folder.path, part.name),
        )?)?;
        ensure!(
            record.desktop || sidecar.is_none(),
            "required metadata path is occupied"
        );
    }
    adopt::save_item(index, &folder, &item)
}

impl Desktop {
    pub fn common_sidecar(&self, album: i64, name: &str) -> bool {
        self.file_export_names.iter().any(|(key, value)| {
            let Some(id) = key.split('_').nth(1) else {
                return false;
            };
            if id.parse::<i64>().ok() != Some(album) {
                return false;
            }
            if value.starts_with('{') {
                serde_json::from_str::<Value>(value).is_ok_and(|pair| {
                    ["image", "video"].iter().any(|role| {
                        pair[role]
                            .as_str()
                            .is_some_and(|p| format!("{p}.json") == name)
                    })
                })
            } else {
                format!("{value}.json") == name
            }
        })
    }
}

pub fn go_record(path: &Path) -> Result<bool> {
    let bytes = fs::read(path)?;
    Ok(serde_json::from_slice::<Value>(&bytes)
        .is_ok_and(|value| value["info"]["id"].as_i64().is_some_and(|id| id > 0)))
}

pub fn json<T: serde::de::DeserializeOwned>(path: &Path) -> Result<T> {
    Properties::read(path)?;
    Ok(serde_json::from_reader(fs::File::open(path)?)?)
}

pub fn id_string(text: &str) -> Result<i64> {
    let id: i64 = text.parse()?;
    ensure!(
        id > 0 && id.to_string() == text,
        "invalid identity {text:?}"
    );
    Ok(id)
}

fn leaf(name: &str) -> Result<()> {
    names::relative(name)?;
    ensure!(
        !name.contains('/'),
        "legacy path is not a single name: {name:?}"
    );
    Ok(())
}
