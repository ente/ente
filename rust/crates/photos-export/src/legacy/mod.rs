pub mod read;
mod verify;

use crate::{
    Options, Source,
    adopt::{self, AlbumRecord, Index, Item},
    fs, names,
    snapshot::FileSnapshot,
    store::{self, AlbumSource, JsonRecord, Properties, Store},
};
use anyhow::{Context, Result, ensure};
use ente_core::Session;
use rusqlite::{OptionalExtension, params};
use std::{
    collections::{BTreeMap, HashSet, btree_map::Entry},
    fs as disk,
    path::Path,
};
use tokio::sync::watch;

#[derive(Default)]
pub struct Failures {
    count: usize,
    examples: Vec<String>,
}

impl Failures {
    pub fn record(&mut self, result: Result<()>, context: &str) -> Result<()> {
        if let Err(error) = result {
            if crate::fatal(&error) {
                return Err(error.context(format!("adoption preflight incomplete: {context}")));
            }
            self.count += 1;
            if self.examples.len() < 10 {
                self.examples.push(format!("{context}: {error:#}"));
            }
        }
        Ok(())
    }

    fn message(&self) -> String {
        let omitted = self.count.saturating_sub(self.examples.len());
        format!(
            "{} failing items\n{}{}",
            self.count,
            self.examples.join("\n"),
            if omitted == 0 {
                String::new()
            } else {
                format!("\n{omitted} more omitted")
            }
        )
    }

    pub fn finish(&self) -> Result<()> {
        ensure!(
            self.count == 0,
            "adoption preflight failed: {}",
            self.message()
        );
        Ok(())
    }
}

pub fn scope(store: &Store, options: &Options, index: Option<&Index>) -> Result<()> {
    let explicit = !options.albums.is_empty() || !options.exclude_albums.is_empty();
    if explicit {
        crate::select(store, options)?;
    }
    let (db, table) = match index {
        Some(index) => (&index.db, "adoption_album"),
        None => (&store.db, "albums"),
    };
    let mut membership = db.prepare(&format!(
        "SELECT EXISTS(SELECT 1 FROM {table} WHERE id=?1 AND retained=0)"
    ))?;
    let mut desired = store.db.prepare("SELECT id,selected FROM desired_albums")?;
    for row in desired.query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, bool>(1)?)))? {
        let (id, selected) = row?;
        let recorded: bool = membership.query_row([id], |r| r.get(0))?;
        if explicit {
            ensure!(
                selected == recorded,
                "adoption filters must select exactly the recorded album IDs"
            );
        } else {
            store.db.execute(
                "UPDATE desired_albums SET selected=?1 WHERE id=?2",
                params![recorded, id],
            )?;
        }
    }
    Ok(())
}

pub struct Preflight<'a> {
    pub root: &'a Path,
    pub store: &'a Store,
    pub session: &'a Session,
    pub index: &'a Index,
    pub cancel: &'a watch::Receiver<bool>,
    pub matching_root: bool,
}

impl Preflight<'_> {
    pub async fn run(&self, source: &impl Source, mut failures: Failures) -> Result<()> {
        let store = self.store;
        let index = self.index;
        let mut after = String::new();
        while let Some(mut record) = store::json::<AlbumRecord>(
            &index.db,
            "SELECT record FROM adoption_album WHERE retained=0 AND key>?1 ORDER BY key LIMIT 1",
            [&after],
        )? {
            after = record.album.key.clone();
            let id = record.album.id;
            let result = (|| {
                let (ready, present, failure): (bool, bool, Option<String>) = store.db.query_row(
                    "SELECT ready,present,failure FROM desired_albums WHERE id=?1",
                    [id],
                    |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
                )?;
                ensure!(
                    ready && failure.is_none(),
                    "album source is incomplete: {}",
                    failure.as_deref().unwrap_or("refresh failed")
                );
                if let Some(legacy) = &record.legacy
                    && present
                    && let Some(owner) = legacy.owner
                {
                    let entry = source
                        .catalog_page(id - 1)?
                        .into_iter()
                        .find(|e| e.id == id)
                        .context("missing current album")?;
                    ensure!(
                        entry.value?.0.owner_id == owner,
                        "album owner disagrees with source"
                    );
                }
                if record.json.is_none() && present {
                    let source: AlbumSource = store::json(
                        &store.db,
                        "SELECT record FROM album_sources WHERE id=?1",
                        [id],
                    )?
                    .context("missing album source")?;
                    if record.legacy.as_ref().is_some_and(|legacy| !legacy.go) {
                        record.album.name = source.name;
                    }
                    record.json = Some(JsonRecord {
                        owner: record.album.key.clone(),
                        role: None,
                        location: None,
                        value: source.metadata,
                        hash: None,
                        properties: None,
                    });
                }
                adopt::save_album(index, &record)
            })();
            if result.is_err() {
                store.db.execute("UPDATE desired_albums SET failure='adoption album preflight failed' WHERE id=?1",[id])?;
            }
            failures.record(result, &format!("album:{id}"))?;
        }
        let mut after = (0, String::new());
        let mut expected = None;
        let mut verified = 0;
        loop {
            let next = store::json::<Item>(
                &index.db,
                "SELECT record FROM adoption_item WHERE origin='legacy' AND (file_id,key)>(?1,?2) ORDER BY file_id,key LIMIT 1",
                params![after.0, after.1],
            )?;
            let Some(mut item) = next else { break };
            if after.0 != item.placement.file {
                expected = None;
            }
            after = (item.placement.file, item.placement.id.clone());
            ensure!(!*self.cancel.borrow(), crate::Cancelled);
            let ready: bool = store.db.query_row(
                "SELECT ready=1 AND failure IS NULL FROM desired_albums WHERE id=?1",
                [item.placement.album],
                |r| r.get(0),
            )?;
            if !ready || expected.as_ref().is_some_and(Result::is_err) {
                continue;
            }
            let result = async {
                let record = item.legacy.as_ref().context("missing legacy identity")?;
                let album: AlbumRecord = store::json(
                    &index.db,
                    "SELECT record FROM adoption_album WHERE id=?1 AND retained=0",
                    [record.album],
                )?
                .context("missing album")?;
                let failure: Option<Option<String>> = store
                    .db
                    .query_row(
                        "SELECT failure FROM desired_files WHERE album=?1 AND file=?2",
                        params![record.album, record.file],
                        |r| r.get(0),
                    )
                    .optional()?;
                if let Some(failure) = failure {
                    ensure!(
                        failure.is_none(),
                        "file source is incomplete: {}",
                        failure.unwrap_or_default()
                    );
                    let remote = source.file(record.album, record.file)?.value?.0;
                    ensure!(
                        record.owner.is_none_or(|owner| owner == remote.owner_id),
                        "file owner disagrees with source"
                    );
                    let file: FileSnapshot = store::json(
                        &store.db,
                        "SELECT record FROM sources WHERE file=?1",
                        [record.file],
                    )?
                    .context("missing source snapshot")?;
                    verified +=
                        verify::file(self, &album.album, &mut item, &file, &mut expected).await?;
                } else {
                    item.leftover = true;
                }
                adopt::save_item(index, &album.album, &item)
            }
            .await;
            failures.record(
                result,
                &format!("file:{}:{}", item.placement.album, item.placement.file),
            )?;
        }
        failures.record((|| {
            let trash=names::check(self.root,"Trash")?;
            ensure!(!trash.try_exists()? || trash.is_dir(),"Trash is not a directory");
            let reserved:Option<AlbumRecord>=store::json(&index.db,"SELECT record FROM adoption_album WHERE retained=0 AND parent='' AND folded='trash'",[])?;
            ensure!(reserved.is_none_or(|r|r.legacy.is_some_and(|l|l.go)),"reserved legacy album path");
            Ok(())
        })(),"Trash")?;
        if !self.matching_root && verified == 0 && failures.count == 0 {
            failures.record(
                Err(anyhow::anyhow!(
                    "at least one existing active original must verify"
                )),
                "source association",
            )?;
        }
        failures.finish()
    }
}

pub fn move_leftovers(root: &Path, index: &Index, cancel: &watch::Receiver<bool>) -> Result<()> {
    if let Some(mut record) = store::json::<AlbumRecord>(
        &index.db,
        "SELECT record FROM adoption_album WHERE retained=0 AND parent='' AND folded='trash'",
        [],
    )? {
        let source = names::check(root, &record.album.path)?;
        if source.try_exists()? {
            let occupied = occupied_names(root, cancel)?;
            for suffix in 0.. {
                ensure!(!*cancel.borrow(), crate::Cancelled);
                let Some(candidate) = names::candidates(&record.album.name, true, None, suffix)?
                else {
                    continue;
                };
                let name = &candidate[0];
                let claimed: bool = index.db.query_row(
                    "SELECT EXISTS(SELECT 1 FROM adoption_album WHERE parent='' AND folded=?1)",
                    [names::folded(name)],
                    |r| r.get(0),
                )?;
                let destination = names::check(root, name)?;
                if claimed || occupied.contains(&names::folded(name)) {
                    continue;
                }
                fs::free_rename(&source, &destination)?;
                disk::rename(&source, &destination)?;
                fs::sync_move(&source, &destination)?;
                record.album.path = name.clone();
                adopt::save_album(index, &record)?;
                break;
            }
        }
    }
    let mut after = String::new();
    // Legacy keys keep each album's leftovers together.
    let mut album_id = None;
    let mut occupied = BTreeMap::new();
    while let Some(item) = store::json::<Item>(
        &index.db,
        "SELECT record FROM adoption_item WHERE origin='legacy' AND key>?1 ORDER BY key LIMIT 1",
        [&after],
    )? {
        after = item.placement.id.clone();
        if !item.leftover {
            continue;
        }
        let record = item.legacy.context("missing leftover identity")?;
        if album_id != Some(record.album) {
            occupied.clear();
            album_id = Some(record.album);
        }
        let album: AlbumRecord = store::json(
            &index.db,
            "SELECT record FROM adoption_album WHERE id=?1 AND retained=0",
            [record.album],
        )?
        .context("missing album")?;
        let folder = album.album.path;
        let trash = format!("Trash/{folder}");
        for part in &record.parts {
            move_one(
                root,
                index,
                &format!("{folder}/{}", part.name),
                &trash,
                &part.name,
                &mut occupied,
                cancel,
            )?;
            if record.desktop {
                move_one(
                    root,
                    index,
                    &format!("{folder}/metadata/{}.json", part.name),
                    &format!("{trash}/metadata"),
                    &format!("{}.json", part.name),
                    &mut occupied,
                    cancel,
                )?;
            }
        }
        if let Some(sidecar) = record.go_record {
            let name = sidecar
                .strip_prefix(".meta/")
                .context("invalid Go record")?;
            move_one(
                root,
                index,
                &format!("{folder}/{sidecar}"),
                &format!("{trash}/.meta"),
                name,
                &mut occupied,
                cancel,
            )?;
        }
    }
    Ok(())
}

fn occupied_names(directory: &Path, cancel: &watch::Receiver<bool>) -> Result<HashSet<String>> {
    let mut occupied = HashSet::new();
    if directory.try_exists()? {
        for entry in disk::read_dir(directory)? {
            ensure!(!*cancel.borrow(), crate::Cancelled);
            occupied.insert(names::folded(&entry?.file_name().to_string_lossy()));
        }
    }
    Ok(occupied)
}

fn move_one(
    root: &Path,
    index: &Index,
    source: &str,
    directory: &str,
    name: &str,
    occupied: &mut BTreeMap<String, HashSet<String>>,
    cancel: &watch::Receiver<bool>,
) -> Result<()> {
    ensure!(!*cancel.borrow(), crate::Cancelled);
    let source = names::check(root, source)?;
    let parent = names::check(root, directory)?;
    if Properties::optional(&source)?.is_none() {
        return fs::sync_move(&source, &parent.join(name));
    }
    for suffix in 0.. {
        ensure!(!*cancel.borrow(), crate::Cancelled);
        let Some(candidate) = names::candidates(name, false, None, suffix)? else {
            continue;
        };
        let relative = format!("{directory}/{}", candidate[0]);
        let destination = names::check(root, &relative)?;
        let occupied = match occupied.entry(directory.to_owned()) {
            Entry::Occupied(entry) => entry.into_mut(),
            Entry::Vacant(entry) => entry.insert(occupied_names(&parent, cancel)?),
        };
        let folded = names::folded(&candidate[0]);
        if occupied.contains(&folded) {
            continue;
        }
        let media = directory
            .strip_suffix("/metadata")
            .map(|p| {
                format!(
                    "{p}/{}",
                    candidate[0].strip_suffix(".json").unwrap_or(&candidate[0])
                )
            })
            .unwrap_or_else(|| relative.clone());
        let claimed: bool = index.db.query_row(
            "SELECT EXISTS(SELECT 1 FROM adoption_path WHERE path=?1)",
            [names::folded(&media)],
            |r| r.get(0),
        )?;
        if !claimed {
            fs::move_file(&source, &destination)?;
            occupied.insert(folded);
            return Ok(());
        }
    }
    unreachable!()
}

pub fn finish(root: &Path, store: &Store, cancel: &watch::Receiver<bool>) -> Result<()> {
    let mut after = String::new();
    loop {
        let next=store.db.query_row(
            "SELECT key,id,retained,name,path FROM albums WHERE retained=0 AND key>?1 ORDER BY key LIMIT 1",
            [&after],crate::store::Album::read,
        ).optional()?;
        let Some(album) = next else { break };
        ensure!(!*cancel.borrow(), crate::Cancelled);
        after = album.key.clone();
        let meta = names::check(root, &format!("{}/.meta", album.path))?;
        if meta.is_dir() {
            for entry in disk::read_dir(&meta)? {
                ensure!(!*cancel.borrow(), crate::Cancelled);
                let entry = entry?;
                if entry.file_name() == "album_meta.json"
                    || entry.path().extension().is_none_or(|e| e != "json")
                    || !entry.file_type()?.is_file()
                {
                    continue;
                }
                if read::go_record(&entry.path())? {
                    fs::remove(&entry.path())?;
                }
            }
            let identity = meta.join("album_meta.json");
            if identity.try_exists()? {
                let value: serde_json::Value = read::json(&identity)?;
                if value["id"].as_i64() == Some(album.id) {
                    fs::remove(&identity)?;
                }
            }
            if disk::read_dir(&meta)?.next().is_none() {
                disk::remove_dir(&meta)?;
                fs::sync_parent(&meta)?;
            }
        }
        let absent: bool = store.db.query_row(
            "SELECT present=0 FROM desired_albums WHERE id=?1",
            [album.id],
            |r| r.get(0),
        )?;
        if absent {
            for relative in [format!("{}/metadata", album.path), album.path] {
                let path = names::check(root, &relative)?;
                if path.is_dir() && disk::read_dir(&path)?.next().is_none() {
                    disk::remove_dir(&path)?;
                    fs::sync_parent(&path)?;
                }
            }
        }
    }
    let manifest = names::check(root, "export_status.json")?;
    if manifest.try_exists()? {
        fs::remove(&manifest)?;
    }
    let transaction = store.db.unchecked_transaction()?;
    store.db.execute("DELETE FROM albums WHERE retained=0 AND id IN (SELECT id FROM desired_albums WHERE selected=1 AND present=0) AND NOT EXISTS(SELECT 1 FROM placements WHERE album=albums.id AND retained=0) AND NOT EXISTS(SELECT 1 FROM temporaries WHERE folder=albums.key)",[])?;
    store
        .db
        .execute("UPDATE export SET bound=1 WHERE id=1", [])?;
    transaction.commit()?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nested_record_preserves_fatal_errors() {
        let mut failures = Failures::default();
        let result = failures.record(Err(rusqlite::Error::InvalidQuery.into()), "file");
        let error = failures.record(result, "album").unwrap_err();
        assert!(error.is::<rusqlite::Error>() && crate::fatal(&error));
        assert_eq!(failures.count, 0);
    }
}
