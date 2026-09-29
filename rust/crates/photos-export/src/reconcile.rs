use std::{
    fs as disk,
    fs::{File, OpenOptions},
    io::Write,
    path::{Path, PathBuf},
    sync::Mutex,
};

use crate::{metadata::Role, snapshot::FileSnapshot};
use anyhow::{Context, Result, ensure};
use rusqlite::{OptionalExtension, params};
use serde_json::Value;
use tokio::sync::watch;
use uuid::Uuid;

use super::{
    fs, names,
    store::{
        self, Action, Album, AlbumSource, Component, JsonRecord, Location, Output, Pending,
        Placement, Properties, Store, Temporary,
    },
    transfer,
};

pub struct Run<'a> {
    pub root: &'a Path,
    pub store: &'a Mutex<Store>,
    pub cancel: &'a watch::Receiver<bool>,
    pub report: &'a (dyn Fn(&str) + Sync),
}

impl Run<'_> {
    pub fn path(&self, location: &Location) -> Result<PathBuf> {
        let relative = {
            let store = store::lock(self.store)?;
            ensure!(
                !store
                    .pending(&location.folder)?
                    .is_some_and(|pending| matches!(
                        pending.action,
                        Some(Action::Directory { .. })
                    )),
                "album directory has an unfinished transition"
            );
            store.relative(location)?
        };
        names::check(self.root, &relative)
    }

    pub fn check_cancel(&self) -> Result<()> {
        ensure!(!*self.cancel.borrow(), super::Cancelled);
        Ok(())
    }

    pub fn temporary(
        &self,
        folder: &str,
        album: i64,
        file: Option<i64>,
    ) -> Result<(Location, File)> {
        self.check_cancel()?;
        let temporary = Temporary {
            location: Location {
                folder: folder.into(),
                name: format!(".ente-{}.part", Uuid::new_v4().simple()),
            },
            album,
            file,
        };
        store::lock(self.store)?.temporary(&temporary)?;
        let path = self.path(&temporary.location)?;
        let file = OpenOptions::new()
            .write(true)
            .read(true)
            .create_new(true)
            .open(&path)?;
        Ok((temporary.location, file))
    }

    pub fn discard(&self, location: &Location) -> Result<()> {
        fs::remove(&self.path(location)?)?;
        store::lock(self.store)?
            .db
            .execute("DELETE FROM temporaries WHERE name=?1", [&location.name])?;
        Ok(())
    }

    pub fn report(&self, unit: &str, error: &anyhow::Error) -> Result<()> {
        {
            let store = store::lock(self.store)?;
            super::record_outcome(&store, unit, error)?;
        }
        (self.report)(&format!("{unit}: {error:#}"));
        Ok(())
    }

    pub fn block(&self, album: i64, file: Option<i64>, error: anyhow::Error) -> Result<()> {
        let unit = file.map_or_else(
            || format!("album:{album}"),
            |file| format!("file:{album}:{file}"),
        );
        self.report(&unit, &error)?;
        if file.is_none() {
            store::lock(self.store)?.db.execute(
                "UPDATE desired_albums SET failure=?1 WHERE id=?2",
                params![error.to_string(), album],
            )?;
            let mut after = 0;
            loop {
                let next: Option<i64> = store::lock(self.store)?
                    .db
                    .query_row(
                        "SELECT file FROM desired_files WHERE album=?1 AND file>?2 ORDER BY file LIMIT 1",
                        params![album, after],
                        |r| r.get(0),
                    )
                    .optional()?;
                let Some(file) = next else { break };
                after = file;
                self.report(&format!("file:{album}:{file}"), &error)?;
            }
        }
        store::lock(self.store)?.db.execute(
            "UPDATE desired_files SET failure=?1 WHERE album=?2 AND (?3 IS NULL OR file=?3)",
            params![error.to_string(), album, file],
        )?;
        if super::fatal(&error) {
            return Err(error);
        }
        Ok(())
    }

    pub fn block_file(&self, file: i64, error: anyhow::Error) -> Result<()> {
        let mut after = 0;
        loop {
            let next: Option<i64> = store::lock(self.store)?
                .db
                .query_row(
                    "SELECT album FROM desired_files WHERE file=?1 AND album>?2 ORDER BY album LIMIT 1",
                    params![file, after],
                    |r| r.get(0),
                )
                .optional()?;
            let Some(album) = next else { break };
            after = album;
            self.report(&format!("file:{album}:{file}"), &error)?;
        }
        store::lock(self.store)?.db.execute(
            "UPDATE desired_files SET failure=?1 WHERE file=?2",
            params![error.to_string(), file],
        )?;
        if super::fatal(&error) {
            return Err(error);
        }
        Ok(())
    }

    fn start(
        &self,
        target: &mut Pending,
        action: Action,
        snapshots: &[(Option<Role>, Value)],
    ) -> Result<()> {
        self.check_cancel()?;
        let store = store::lock(self.store)?;
        let transaction = store.db.unchecked_transaction()?;
        let published = !store.components(&target.owner)?.is_empty();
        for (role, value) in snapshots {
            let previous = store.json_record(&target.owner, role.as_ref())?;
            if previous.is_none()
                || (previous
                    .as_ref()
                    .is_some_and(|record| record.location.is_none())
                    && !published)
            {
                store.save_json(&JsonRecord {
                    owner: target.owner.clone(),
                    role: role.clone(),
                    location: None,
                    value: value.clone(),
                    hash: None,
                    properties: None,
                })?;
            }
        }
        target.action = Some(action);
        store.save_pending(target)?;
        transaction.commit()?;
        Ok(())
    }

    fn owns(&self, owner: &str, location: &Location, output: &Output) -> Result<bool> {
        let store = store::lock(self.store)?;
        Ok(match output {
            Output::Media { role, .. } => store
                .components(owner)?
                .iter()
                .any(|component| component.role == *role && component.location == *location),
            Output::Json { role, .. } => store
                .json_record(owner, role.as_ref())?
                .is_some_and(|record| record.location.as_ref() == Some(location)),
        })
    }

    fn clear_action(&self, target: &mut Pending) -> Result<()> {
        target.action = None;
        store::lock(self.store)?.save_pending(target)
    }

    fn acknowledge(
        &self,
        target: &mut Pending,
        destination: &Location,
        output: &Output,
        value: Option<Value>,
    ) -> Result<()> {
        let path = self.path(destination)?;
        let properties = Properties::read(&path)?;
        let value = if matches!(output, Output::Json { .. }) {
            Some(match value {
                Some(value) => value,
                None => serde_json::from_slice(&disk::read(&path)?)?,
            })
        } else {
            None
        };
        let store = store::lock(self.store)?;
        let transaction = store.db.unchecked_transaction()?;
        match output {
            Output::Media {
                role,
                size,
                hash,
                signature,
            } => {
                if store
                    .placement(
                        target.album,
                        target.file.context("missing publication file")?,
                    )?
                    .is_none()
                {
                    store.save_placement(&target.placement()?)?;
                }
                let component = Component {
                    placement: target.owner.clone(),
                    role: role.clone(),
                    location: destination.clone(),
                    size: *size,
                    hash: hash.clone(),
                    signature: signature.clone(),
                    properties: Some(properties),
                    intended_time: None,
                };
                store.save_component(&component)?;
            }
            Output::Json { role, hash, .. } => {
                let mut record = store
                    .json_record(&target.owner, role.as_ref())?
                    .context("missing metadata snapshot")?;
                record.location = Some(destination.clone());
                record.properties = Some(properties);
                if let Some(value) = value {
                    record.value = value;
                    record.hash = Some(hash.clone());
                }
                store.save_json(&record)?;
            }
        }
        if let Some(Action::Publish { temporary, .. }) = &target.action {
            store
                .db
                .execute("DELETE FROM temporaries WHERE name=?1", [&temporary.name])?;
        }
        target.action = None;
        store.save_pending(target)?;
        transaction.commit()?;
        Ok(())
    }

    fn finish_action(
        &self,
        target: &mut Pending,
        recovering: bool,
        value: Option<Value>,
    ) -> Result<()> {
        let Some(action) = target.action.clone() else {
            return Ok(());
        };
        self.check_cancel()?;
        match action {
            Action::Directory { source } => {
                let destination = names::check(self.root, &target.album_path())?;
                if let Some(source) = source {
                    let source = names::check(self.root, &source)?;
                    if directory_exists(&source)? {
                        free_rename(&source, &destination)?;
                        disk::rename(&source, &destination)?;
                    } else if !directory_exists(&destination)? {
                        let unrepairable: bool = store::lock(self.store)?
                            .db
                            .query_row(
                                "SELECT EXISTS(SELECT 1 FROM placements p WHERE p.album=?1 AND p.retained=0 AND NOT EXISTS(SELECT 1 FROM desired_files f WHERE f.album=p.album AND f.file=p.file AND f.failure IS NULL))",
                                [target.album],
                                |r| r.get(0),
                            )?;
                        ensure!(
                            !unrepairable,
                            "missing album contains originals that cannot be repaired"
                        );
                        fs::create_directory(&destination)?;
                    }
                    fs::sync_move(&source, &destination)?;
                } else {
                    fs::create_directory(&destination)?;
                    ensure!(
                        disk::read_dir(&destination)?.next().is_none(),
                        super::Conflict(format!(
                            "at {}: unrelated directory contents",
                            destination.display()
                        ))
                    );
                    fs::sync_parent(&destination)?;
                    if target.retained {
                        fs::sync_parent(
                            destination
                                .parent()
                                .context("retained album has no parent")?,
                        )?;
                    }
                }
                let store = store::lock(self.store)?;
                let transaction = store.db.unchecked_transaction()?;
                store.save_album(&Album {
                    key: target.owner.clone(),
                    id: target.album,
                    retained: target.retained,
                    name: target.name.clone(),
                    path: target.album_path(),
                })?;
                target.action = None;
                store.save_pending(target)?;
                transaction.commit()?;
            }
            Action::Publish {
                temporary,
                destination,
                output,
            } => {
                let source = self.path(&temporary)?;
                let path = self.path(&destination)?;
                let owned = self.owns(&target.owner, &destination, &output)?;
                if Properties::optional(&source)?.is_some() {
                    if recovering {
                        self.clear_action(target)?;
                        return self.discard(&temporary);
                    }
                    ensure!(
                        Properties::optional(&path)?.is_none() || owned,
                        super::Conflict(format!("at {}: unrelated occupant", path.display()))
                    );
                    fs::create_directory(path.parent().context("publication has no parent")?)?;
                    disk::rename(&source, &path)?;
                } else {
                    let (size, hash) = output.identity();
                    let matches = Properties::optional(&path)?.is_some()
                        && fs::matches(&path, size, hash, self.cancel)?;
                    if !matches {
                        ensure!(
                            !path.try_exists()? || owned,
                            super::Conflict(format!("at {}: unrelated occupant", path.display()))
                        );
                        self.clear_action(target)?;
                        self.discard(&temporary)?;
                        ensure!(recovering, "publication temporary disappeared");
                        return Ok(());
                    }
                }
                fs::sync_move(&source, &path)?;
                self.acknowledge(target, &destination, &output, value)?;
            }
            Action::Move {
                source,
                destination,
                role,
                size,
                hash,
            } => {
                let from = self.path(&source)?;
                let to = self.path(&destination)?;
                if Properties::optional(&from)?.is_some() {
                    free_rename(&from, &to)?;
                    fs::create_directory(to.parent().context("move has no parent")?)?;
                    disk::rename(&from, &to)?;
                } else if Properties::optional(&to)?.is_some() {
                    ensure!(
                        fs::matches(&to, size, &hash, self.cancel)?,
                        super::Conflict(format!("at {}: moved bytes differ", to.display()))
                    );
                } else {
                    ensure!(
                        !target.retained,
                        "retained original is missing at both move endpoints"
                    );
                    return self.clear_action(target);
                }
                fs::sync_move(&from, &to)?;
                let store = store::lock(self.store)?;
                let transaction = store.db.unchecked_transaction()?;
                let mut component = store
                    .components(&target.owner)?
                    .into_iter()
                    .find(|component| component.role == role)
                    .context("missing moved component")?;
                component.location = destination;
                component.properties = None;
                component.intended_time = None;
                store.save_component(&component)?;
                target.action = None;
                store.save_pending(target)?;
                transaction.commit()?;
            }
            Action::Remove { location, role } => {
                fs::remove(&self.path(&location)?)?;
                let store = store::lock(self.store)?;
                let transaction = store.db.unchecked_transaction()?;
                let mut record = store
                    .json_record(&target.owner, role.as_ref())?
                    .context("missing removed JSON record")?;
                record.location = None;
                record.hash = None;
                record.properties = None;
                store.save_json(&record)?;
                target.action = None;
                store.save_pending(target)?;
                transaction.commit()?;
            }
        }
        Ok(())
    }

    fn json_changed(
        &self,
        previous: Option<&JsonRecord>,
        location: &Location,
        json: &fs::Json,
    ) -> Result<bool> {
        let path = self.path(location)?;
        let properties = Properties::optional(&path)?;
        let owned = previous
            .as_ref()
            .is_some_and(|record| record.location.as_ref() == Some(location));
        let renamed = previous
            .as_ref()
            .and_then(|record| record.location.as_ref())
            .map(|source| {
                self.path(source)
                    .map(|source| names::same_path(&source, &path))
            })
            .transpose()?
            .unwrap_or(false);
        ensure!(
            properties.is_none() || owned || renamed,
            super::Conflict(format!("at {}: unrelated JSON", path.display()))
        );
        Ok(!previous.as_ref().is_some_and(|record| {
            owned
                && record.hash.as_ref() == Some(&json.hash)
                && record.properties == properties
                && properties.is_some()
        }))
    }

    fn write_json(
        &self,
        target: &mut Pending,
        role: Option<Role>,
        location: Location,
        json: fs::Json,
    ) -> Result<bool> {
        let previous = store::lock(self.store)?.json_record(&target.owner, role.as_ref())?;
        if !self.json_changed(previous.as_ref(), &location, &json)? {
            return Ok(false);
        }
        self.replace_json(target, role, location, json, previous)?;
        Ok(true)
    }

    fn replace_json(
        &self,
        target: &mut Pending,
        role: Option<Role>,
        location: Location,
        json: fs::Json,
        previous: Option<JsonRecord>,
    ) -> Result<bool> {
        let previous = previous
            .and_then(|record| record.location)
            .filter(|old| *old != location);
        let renamed = previous.is_some();
        if let Some(previous) = previous {
            self.start(
                target,
                Action::Remove {
                    location: previous,
                    role: role.clone(),
                },
                &[],
            )?;
            self.finish_action(target, false, None)?;
        }
        self.publish_json(target, role, location, json)?;
        Ok(renamed)
    }

    fn publish_json(
        &self,
        target: &mut Pending,
        role: Option<Role>,
        location: Location,
        json: fs::Json,
    ) -> Result<()> {
        let (temporary, mut file) = self.temporary(&location.folder, target.album, target.file)?;
        file.write_all(&json.bytes)?;
        file.sync_all()?;
        drop(file);
        let output = Output::Json {
            role: role.clone(),
            size: json.bytes.len() as u64,
            hash: json.hash,
        };
        self.start(
            target,
            Action::Publish {
                temporary,
                destination: location,
                output,
            },
            &[(role, json.value.clone())],
        )?;
        self.finish_action(target, false, Some(json.value))
    }

    fn move_media(
        &self,
        target: &mut Pending,
        component: &Component,
        destination: Location,
        verified: Option<&Properties>,
    ) -> Result<bool> {
        if component.location == destination {
            return Ok(false);
        }
        let from = self.path(&component.location)?;
        let to = self.path(&destination)?;
        free_rename(&from, &to)?;
        let properties = Properties::optional(&from)?;
        if properties.is_none() {
            ensure!(!target.retained, "previously published original is missing");
            return Ok(false);
        }
        let (size, hash) = if verified == properties.as_ref() {
            (component.size, component.hash.clone())
        } else {
            fs::hash_cancellable(&from, self.cancel)?
        };
        self.start(
            target,
            Action::Move {
                source: component.location.clone(),
                destination,
                role: component.role.clone(),
                size,
                hash,
            },
            &[],
        )?;
        self.finish_action(target, false, None)?;
        Ok(true)
    }
}

fn directory_exists(path: &Path) -> Result<bool> {
    match disk::symlink_metadata(path) {
        Ok(metadata) => {
            ensure!(
                metadata.is_dir(),
                super::Conflict(format!("at {}: expected directory", path.display()))
            );
            Ok(true)
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(error.into()),
    }
}

fn free_rename(source: &Path, destination: &Path) -> Result<()> {
    ensure!(
        !destination.try_exists()? || names::same_path(source, destination),
        super::Conflict(format!(
            "at {}: occupied rename target",
            destination.display()
        ))
    );
    Ok(())
}

impl Run<'_> {
    pub fn recover(&self) -> Result<()> {
        for albums in [true, false] {
            let mut after = String::new();
            loop {
                let next = {
                    let store = store::lock(self.store)?;
                    store
                        .db
                        .query_row(
                            "SELECT p.owner,p.album,p.file FROM pending p JOIN desired_albums a ON a.id=p.album WHERE p.owner>?1 AND (p.file IS NULL)=?2 AND a.selected=1 AND a.ready=1 AND a.failure IS NULL AND NOT EXISTS(SELECT 1 FROM desired_files f WHERE f.album=p.album AND f.file=p.file AND f.failure IS NOT NULL) ORDER BY p.owner LIMIT 1",
                            params![after, albums],
                            |r| {
                                Ok((
                                    r.get::<_, String>(0)?,
                                    r.get::<_, i64>(1)?,
                                    r.get::<_, Option<i64>>(2)?,
                                ))
                            },
                        )
                        .optional()?
                };
                let Some((owner, album, file)) = next else {
                    break;
                };
                after = owner.clone();
                let mut pending = store::lock(self.store)?
                    .pending(&owner)?
                    .context("missing pending transition")?;
                if let Err(error) = self.finish_action(&mut pending, true, None) {
                    self.block(album, file, error)?;
                }
            }
        }
        {
            let store = store::lock(self.store)?;
            let transaction = store.db.unchecked_transaction()?;
            store
                .db
                .execute(
                    "DELETE FROM pending WHERE file IS NULL AND action='null' AND album IN (SELECT id FROM desired_albums WHERE selected=1 AND ready=1 AND failure IS NULL) AND ((retained=0 AND album IN (SELECT id FROM desired_albums WHERE present=0)) OR (retained=1 AND NOT EXISTS(SELECT 1 FROM albums WHERE key=pending.owner) AND NOT EXISTS(SELECT 1 FROM placements p WHERE p.album=pending.album AND p.retained=0 AND NOT EXISTS(SELECT 1 FROM desired_files f WHERE f.album=p.album AND f.file=p.file))))",
                    [],
                )?;
            store
                .db
                .execute(
                    "DELETE FROM json_records WHERE folder IS NULL AND NOT EXISTS(SELECT 1 FROM albums WHERE key=json_records.owner) AND NOT EXISTS(SELECT 1 FROM components WHERE placement=json_records.owner) AND NOT EXISTS(SELECT 1 FROM pending WHERE owner=json_records.owner)",
                    [],
                )?;
            transaction.commit()?;
        }
        self.cleanup(None)
    }

    pub fn cleanup(&self, file: Option<i64>) -> Result<()> {
        let mut after = String::new();
        loop {
            let next = {
                let store = store::lock(self.store)?;
                store
                    .db
                    .query_row(
                        "SELECT t.name,t.folder,t.album,t.file FROM temporaries t JOIN desired_albums a ON a.id=t.album WHERE t.name>?1 AND (?2 IS NULL OR t.file=?2) AND a.selected=1 ORDER BY t.name LIMIT 1",
                        params![after, file],
                        |r| {
                            Ok(Temporary {
                                location: Location {
                                    name: r.get(0)?,
                                    folder: r.get(1)?,
                                },
                                album: r.get(2)?,
                                file: r.get(3)?,
                            })
                        },
                    )
                    .optional()?
            };
            let Some(temporary) = next else {
                break;
            };
            after = temporary.location.name.clone();
            let result = (|| {
                let pending = {
                    let store = store::lock(self.store)?;
                    let owner: Option<String> = store
                        .db
                        .query_row(
                            "SELECT owner FROM pending WHERE json_extract(action,'$.Publish.temporary.name')=?1",
                            [&temporary.location.name],
                            |r| r.get(0),
                        )
                        .optional()?;
                    owner
                        .map(|owner| store.pending(&owner))
                        .transpose()?
                        .flatten()
                };
                if let Some(mut pending) = pending {
                    let selected: bool = store::lock(self.store)?.db.query_row(
                        "SELECT selected FROM desired_albums WHERE id=?1",
                        [pending.album],
                        |r| r.get(0),
                    )?;
                    if !selected
                        || Properties::optional(&self.path(&temporary.location)?)?.is_none()
                    {
                        return Ok(());
                    }
                    self.clear_action(&mut pending)?;
                }
                self.discard(&temporary.location)
            })();
            if let Err(error) = result {
                if let Some(file) = temporary.file {
                    let selected: bool = store::lock(self.store)?.db.query_row(
                        "SELECT EXISTS(SELECT 1 FROM desired_files WHERE file=?1)",
                        [file],
                        |r| r.get(0),
                    )?;
                    if selected {
                        self.block_file(file, error)?;
                        continue;
                    }
                }
                self.block(temporary.album, temporary.file, error)?;
            }
        }
        Ok(())
    }

    fn album_target(&self, album: i64, name: &str, retained: bool) -> Result<Pending> {
        let store = store::lock(self.store)?;
        let existing = store.album(album, retained)?;
        let owner = existing
            .as_ref()
            .map(|album| album.key.clone())
            .unwrap_or_else(|| format!("{}:{album}", if retained { "retained" } else { "active" }));
        if let Some(pending) = store.pending(&owner)? {
            ensure!(pending.action.is_none(), "album has unfinished action");
            if pending.name == name || retained {
                return Ok(pending);
            }
        }
        let transaction = store.db.unchecked_transaction()?;
        let parent = if retained { "Trash" } else { "" };
        let names = if let Some(existing) = &existing
            && (retained || existing.name == name)
        {
            vec![
                existing
                    .path
                    .rsplit('/')
                    .next()
                    .context("empty album path")?
                    .to_owned(),
            ]
        } else {
            names::allocate(&store, parent, name, "album", None, &owner)?
        };
        let target = Pending {
            owner,
            album,
            file: None,
            retained,
            name: name.into(),
            kind: "album".into(),
            folder: parent.into(),
            names,
            action: None,
        };
        store.save_pending(&target)?;
        transaction.commit()?;
        Ok(target)
    }

    fn maintain_album(
        &self,
        album: i64,
        name: &str,
        retained: bool,
        metadata: Value,
    ) -> Result<Album> {
        let existing = store::lock(self.store)?.album(album, retained)?;
        let json = fs::Json::new(metadata)?;
        if let Some(existing) = &existing
            && (retained || existing.name == name)
        {
            let pending = store::lock(self.store)?.pending(&existing.key)?;
            let cached = store::lock(self.store)?.json_record(&existing.key, None)?;
            let location = Location {
                folder: existing.key.clone(),
                name: "metadata.json".into(),
            };
            if pending.is_none()
                && let Some(cached) = cached
            {
                let properties = Properties::optional(&self.path(&location)?)?;
                if cached.location.as_ref() == Some(&location)
                    && cached.hash.as_ref() == Some(&json.hash)
                    && properties.is_some()
                    && cached.properties == properties
                {
                    return Ok(existing.clone());
                }
            }
        }
        let mut target = self.album_target(album, name, retained)?;
        let target_path = target.album_path();
        if existing
            .as_ref()
            .is_none_or(|album| album.path != target_path)
        {
            let source = existing.as_ref().map(|album| album.path.clone());
            let destination = names::check(self.root, &target_path)?;
            if let Some(source) = &source {
                free_rename(&names::check(self.root, source)?, &destination)?;
            } else {
                ensure!(
                    !destination.try_exists()?,
                    super::Conflict(format!("at {}: unrelated directory", destination.display()))
                );
            }
            self.start(
                &mut target,
                Action::Directory { source },
                &[(None, json.value.clone())],
            )?;
            self.finish_action(&mut target, false, None)?;
            if existing.is_some() {
                let store = store::lock(self.store)?;
                store
                    .db
                    .execute(
                        "INSERT INTO events(placement,renamed) SELECT id,1 FROM placements WHERE album=?1 AND retained=0 ON CONFLICT(placement) DO UPDATE SET renamed=1",
                        [album],
                    )?;
            }
        } else {
            fs::directory(self.root, &target_path)?;
        }
        let location = Location {
            folder: target.owner.clone(),
            name: "metadata.json".into(),
        };
        self.write_json(&mut target, None, location, json)?;
        let store = store::lock(self.store)?;
        let mut album = store.folder(&target.owner)?;
        album.name = target.name;
        store.save_album(&album)?;
        store.clear_pending(&target.owner)?;
        Ok(album)
    }

    pub fn albums(&self) -> Result<()> {
        let mut after = 0;
        loop {
            let source: Option<(i64, String)> = store::lock(self.store)?
                .db
                .query_row(
                    "SELECT a.id,s.record FROM desired_albums a JOIN album_sources s ON s.id=a.id WHERE a.id>?1 AND a.selected=1 AND a.ready=1 AND a.failure IS NULL AND a.present=1 ORDER BY a.id LIMIT 1",
                    [after],
                    |r| Ok((r.get(0)?, r.get(1)?)),
                )
                .optional()?;
            let Some((id, source)) = source else {
                break;
            };
            after = id;
            let source: AlbumSource = serde_json::from_str(&source)?;
            for field in &source.warnings {
                (self.report)(&format!(
                    "album {id}: unfamiliar metadata field {field:?}; exporting supported fields"
                ));
            }
            if let Err(error) = self.maintain_album(id, &source.name, false, source.metadata) {
                self.block(id, None, error)?;
            }
        }
        Ok(())
    }
}

impl Run<'_> {
    fn file_target(
        &self,
        album: &Album,
        file: &FileSnapshot,
        prepared: &transfer::Prepared,
    ) -> Result<Pending> {
        let store = store::lock(self.store)?;
        let existing = store.placement(album.id, file.id)?;
        let previous = store.pending_file(album.id, file.id)?;
        let owner = existing
            .as_ref()
            .map(|placement| placement.id.clone())
            .or_else(|| previous.as_ref().map(|pending| pending.owner.clone()))
            .unwrap_or_else(|| Uuid::new_v4().to_string());
        let components = store.components(&owner)?;
        let roles = transfer::roles(file);
        let extensions: Vec<String> = roles
            .iter()
            .map(|role| {
                prepared
                    .components
                    .iter()
                    .find(|source| source.role == *role)
                    .map(|source| source.extension.clone())
                    .or_else(|| {
                        components
                            .iter()
                            .find(|component| component.role == *role)
                            .map(|component| {
                                names::split(&component.location.name, false).1.to_owned()
                            })
                    })
                    .context("missing verified original")
            })
            .collect::<Result<_>>()?;
        let compatible = |names: &[String]| {
            names.len() == roles.len()
                && (roles.len() == 1
                    || names.iter().zip(&extensions).all(|(name, extension)| {
                        names::split(name, false).1 == names::portable(extension)
                    }))
        };
        if let Some(previous) = previous {
            ensure!(
                previous.action.is_none() && !previous.retained,
                "file has unfinished transition"
            );
            let same_folder = previous.folder == album.key;
            if same_folder
                && previous.name == file.name
                && previous.kind == file.kind.as_str()
                && compatible(&previous.names)
            {
                return Ok(previous);
            }
        }
        let existing_names: Vec<_> = components
            .iter()
            .map(|component| component.location.name.clone())
            .collect();
        let unchanged = existing.as_ref().is_some_and(|placement| {
            placement.name == file.name && placement.kind == file.kind.as_str()
        }) && components
            .iter()
            .all(|component| component.location.folder == album.key)
            && compatible(&existing_names);
        let transaction = store.db.unchecked_transaction()?;
        let names = if unchanged {
            existing_names
        } else {
            names::allocate(
                &store,
                &album.key,
                &file.name,
                file.kind.as_str(),
                if roles.len() == 2 {
                    Some((&extensions[0], &extensions[1]))
                } else {
                    None
                },
                &owner,
            )?
        };
        let target = Pending {
            owner,
            album: album.id,
            file: Some(file.id),
            retained: false,
            name: file.name.clone(),
            kind: file.kind.clone(),
            folder: album.key.clone(),
            names,
            action: None,
        };
        if !unchanged {
            store.save_pending(&target)?;
        } else if store.pending(&target.owner)?.is_some() {
            store.clear_pending(&target.owner)?;
        }
        transaction.commit()?;
        Ok(target)
    }

    pub async fn file(&self, session: &ente_core::Session, file: FileSnapshot) -> Result<()> {
        let mut prepared = transfer::prepare(self, session, &file).await?;
        let mut after = 0;
        loop {
            let album: Option<i64> = store::lock(self.store)?
                .db
                .query_row(
                    "SELECT album FROM desired_files WHERE file=?1 AND album>?2 AND failure IS NULL ORDER BY album LIMIT 1",
                    params![file.id, after],
                    |r| r.get(0),
                )
                .optional()?;
            let Some(album) = album else {
                break;
            };
            after = album;
            let pending = store::lock(self.store)?.pending_file(album, file.id)?;
            if let Some(mut pending) = pending
                && pending.retained
            {
                let components = store::lock(self.store)?.components(&pending.owner)?;
                if components
                    .iter()
                    .any(|component| component.location.folder == pending.folder)
                {
                    if let Err(error) = self.finish_retention(&mut pending) {
                        self.block(album, Some(file.id), error)?;
                    } else {
                        self.retired_sources(&components, &mut prepared, album)?;
                    }
                } else {
                    store::lock(self.store)?.clear_pending(&pending.owner)?;
                }
            }
        }
        for field in &file.warnings {
            (self.report)(&format!(
                "file {}: unfamiliar metadata field {field:?}; exporting supported fields",
                file.id
            ));
        }
        after = 0;
        loop {
            self.check_cancel()?;
            let next: Option<(i64, bool)> = store::lock(self.store)?
                .db
                .query_row(
                    "SELECT album,favorited FROM desired_files WHERE file=?1 AND album>?2 AND failure IS NULL ORDER BY album LIMIT 1",
                    params![file.id, after],
                    |r| Ok((r.get(0)?, r.get(1)?)),
                )
                .optional()?;
            let Some((album, favorited)) = next else {
                break;
            };
            after = album;
            if let Err(error) = self.placement(&file, &mut prepared, album, favorited) {
                self.block(album, Some(file.id), error)?;
            }
        }
        Ok(())
    }

    fn retired_sources(
        &self,
        previous: &[Component],
        prepared: &mut transfer::Prepared,
        album: i64,
    ) -> Result<()> {
        for previous in previous {
            let current = store::lock(self.store)?.components(&previous.placement)?;
            if let Some(current) = current.iter().find(|current| current.role == previous.role) {
                for source in &mut prepared.components {
                    if source.location == previous.location {
                        source.location = current.location.clone();
                    }
                }
            }
        }
        prepared.observed.retain(|(id, _)| *id != album);
        Ok(())
    }

    fn placement(
        &self,
        file: &FileSnapshot,
        prepared: &mut transfer::Prepared,
        album_id: i64,
        favorited: bool,
    ) -> Result<()> {
        let album = store::lock(self.store)?
            .album(album_id, false)?
            .context("missing destination album")?;
        let existing = store::lock(self.store)?.placement(album_id, file.id)?;
        if let Some(existing) = existing {
            let components = store::lock(self.store)?.components(&existing.id)?;
            if components
                .iter()
                .any(|component| !transfer::roles(file).contains(&component.role))
            {
                self.retain(existing)?;
                self.retired_sources(&components, prepared, album_id)?;
            }
        }
        let existing = store::lock(self.store)?.placement(album_id, file.id)?;
        let mut target = self.file_target(&album, file, prepared)?;
        let old = store::lock(self.store)?.components(&target.owner)?;
        let intended: Vec<_> = transfer::roles(file)
            .into_iter()
            .zip(&target.names)
            .map(|(role, name)| {
                let (size, hash) = if let Some(source) = prepared
                    .components
                    .iter()
                    .find(|source| source.role == role)
                {
                    (source.size, source.hash.clone())
                } else {
                    let component = old
                        .iter()
                        .find(|component| component.role == role)
                        .context("missing completed original")?;
                    (component.size, component.hash.clone())
                };
                Ok(crate::metadata::Component {
                    role,
                    path: name.clone(),
                    size,
                    hash,
                })
            })
            .collect::<Result<_>>()?;
        let metadata: Vec<_> = intended
            .iter()
            .enumerate()
            .map(|(index, component)| {
                Ok((
                    Some(component.role.clone()),
                    crate::metadata::publish(&file.metadata, &intended, index, favorited)?,
                ))
            })
            .collect::<Result<_>>()?;
        let mut sidecars = Vec::new();
        for (component, (_, value)) in intended.iter().zip(&metadata) {
            let location = Location {
                folder: album.key.clone(),
                name: component.path.clone(),
            };
            let previous = old.iter().find(|previous| previous.role == component.role);
            let observed = prepared
                .observed
                .iter()
                .find(|(id, _)| *id == album_id)
                .is_some_and(|(_, observed)| {
                    observed.iter().any(|(role, _)| *role == component.role)
                });
            if !observed || previous.is_none_or(|previous| previous.location != location) {
                let path = self.path(&location)?;
                let owned = previous.is_some_and(|previous| previous.location == location);
                let renamed = previous
                    .map(|previous| {
                        self.path(&previous.location)
                            .map(|source| names::same_path(&source, &path))
                    })
                    .transpose()?
                    .unwrap_or(false);
                ensure!(
                    Properties::optional(&path)?.is_none() || owned || renamed,
                    super::Conflict(format!("at {}: unrelated occupant", path.display()))
                );
            }
            let location = Location {
                folder: album.key.clone(),
                name: format!("metadata/{}.json", component.path),
            };
            let json = fs::Json::new(value.clone())?;
            let previous =
                store::lock(self.store)?.json_record(&target.owner, Some(&component.role))?;
            let changed = self.json_changed(previous.as_ref(), &location, &json)?;
            sidecars.push((location, json, changed, previous));
        }
        let intended_time = file.intended_time;
        let mut wrote_media = false;
        let mut renamed = false;
        for component in &intended {
            self.check_cancel()?;
            let destination = Location {
                folder: album.key.clone(),
                name: component.path.clone(),
            };
            let previous = old.iter().find(|previous| previous.role == component.role);
            let observed = prepared
                .observed
                .iter()
                .find(|(id, _)| *id == album_id)
                .and_then(|(_, observed)| observed.iter().find(|(role, _)| *role == component.role))
                .map(|(_, properties)| properties);
            let valid = observed.is_some();
            if let Some(previous) = previous
                && previous.location != destination
            {
                let moved =
                    self.move_media(&mut target, previous, destination.clone(), observed)?;
                if moved {
                    renamed = true;
                    for source in &mut prepared.components {
                        if source.location == previous.location {
                            source.location = destination.clone();
                        }
                    }
                }
            }
            if !valid {
                let source = prepared
                    .components
                    .iter_mut()
                    .find(|source| source.role == component.role)
                    .context("no verified original is available")?;
                let temporary = if source.temporary {
                    source.location.clone()
                } else {
                    let (temporary, file) = self.temporary(&album.key, album_id, Some(file.id))?;
                    let mut writer = fs::HashWriter::new(file, self.cancel)?;
                    std::io::copy(&mut File::open(self.path(&source.location)?)?, &mut writer)?;
                    let (_, size, hash) = writer.finish()?;
                    ensure!(
                        size == source.size && hash == source.hash,
                        "local original changed while copying"
                    );
                    temporary
                };
                let output = Output::Media {
                    role: component.role.clone(),
                    size: source.size,
                    hash: source.hash.clone(),
                    signature: Some(prepared.signature.clone()),
                };
                self.start(
                    &mut target,
                    Action::Publish {
                        temporary,
                        destination: destination.clone(),
                        output,
                    },
                    &metadata,
                )?;
                self.finish_action(&mut target, false, None)?;
                source.location = destination.clone();
                source.temporary = false;
                wrote_media = true;
            }
            let mut published = store::lock(self.store)?
                .components(&target.owner)?
                .into_iter()
                .find(|published| published.role == component.role)
                .context("missing published component")?;
            let previous = published.clone();
            if published.intended_time != Some(intended_time)
                || observed != published.properties.as_ref()
                || renamed
            {
                published.properties =
                    Some(fs::set_time(&self.path(&destination)?, intended_time)?);
            }
            published.intended_time = Some(intended_time);
            published.signature = Some(prepared.signature.clone());
            if published != previous {
                store::lock(self.store)?.save_component(&published)?;
            }
        }
        let mut metadata_changed = false;
        for (component, (location, json, changed, previous)) in intended.iter().zip(sidecars) {
            if changed {
                renamed |= self.replace_json(
                    &mut target,
                    Some(component.role.clone()),
                    location,
                    json,
                    previous,
                )?;
                metadata_changed = true;
            }
        }
        let store = store::lock(self.store)?;
        let transaction = store.db.unchecked_transaction()?;
        if existing
            .as_ref()
            .is_some_and(|previous| previous.name != target.name || previous.kind != target.kind)
        {
            store.save_placement(&target.placement()?)?;
        }
        store.clear_pending(&target.owner)?;
        store.db.execute(
            "UPDATE desired_files SET completed=1 WHERE album=?1 AND file=?2",
            params![album_id, file.id],
        )?;
        if wrote_media || existing.is_none() {
            event(&store, &target.owner, "exported")?;
        }
        if existing.is_some() && metadata_changed {
            event(&store, &target.owner, "metadata_updated")?;
        }
        if renamed {
            event(&store, &target.owner, "renamed")?;
        }
        transaction.commit()?;
        Ok(())
    }
}

fn event(store: &Store, placement: &str, name: &str) -> Result<()> {
    store
        .db
        .execute(
            &format!(
                "INSERT INTO events(placement,{name}) VALUES(?1,1) ON CONFLICT(placement) DO UPDATE SET {name}=1",
            ),
            [placement],
        )?;
    Ok(())
}

impl Run<'_> {
    fn retained_album(&self, active: &Album) -> Result<Album> {
        let existing = store::lock(self.store)?.album(active.id, true)?;
        let (name, value) = if let Some(existing) = existing {
            let record = store::lock(self.store)?
                .json_record(&existing.key, None)?
                .context("missing retained album snapshot")?;
            (existing.name, record.value)
        } else {
            let record = store::lock(self.store)?
                .json_record(&active.key, None)?
                .context("missing album snapshot")?;
            (active.name.clone(), record.value)
        };
        self.maintain_album(active.id, &name, true, value)
    }

    fn retain(&self, placement: Placement) -> Result<()> {
        let mut pending = store::lock(self.store)?.pending(&placement.id)?;
        if let Some(target) = &mut pending {
            self.finish_action(target, true, None)?;
            if target.retained {
                return self.finish_retention(target);
            }
        }
        let components = store::lock(self.store)?.components(&placement.id)?;
        for component in &components {
            Properties::read(&self.path(&component.location)?)
                .context("previously published original is missing")?;
        }
        let active = store::lock(self.store)?
            .album(placement.album, false)?
            .context("missing active album")?;
        let album = self.retained_album(&active)?;
        let template = components
            .first()
            .context("placement has no published components")?;
        let metadata = store::lock(self.store)?
            .json_record(&placement.id, Some(&template.role))?
            .context("missing retained metadata snapshot")?;
        let layout: Vec<crate::metadata::Component> =
            serde_json::from_value(metadata.value["ente"]["components"].clone())?;
        let extensions = if placement.kind == "livephoto" {
            Some((
                names::split(
                    &layout
                        .iter()
                        .find(|component| component.role == Role::Image)
                        .context("missing image identity")?
                        .path,
                    false,
                )
                .1,
                names::split(
                    &layout
                        .iter()
                        .find(|component| component.role == Role::Video)
                        .context("missing video identity")?
                        .path,
                    false,
                )
                .1,
            ))
        } else {
            None
        };
        let mut target = {
            let store = store::lock(self.store)?;
            let transaction = store.db.unchecked_transaction()?;
            let names = names::allocate(
                &store,
                &album.key,
                &placement.name,
                &placement.kind,
                extensions,
                &placement.id,
            )?;
            let target = Pending {
                owner: placement.id,
                album: placement.album,
                file: Some(placement.file),
                retained: true,
                name: placement.name,
                kind: placement.kind,
                folder: album.key,
                names,
                action: None,
            };
            store.save_pending(&target)?;
            transaction.commit()?;
            target
        };
        self.finish_retention(&mut target)
    }

    fn finish_retention(&self, target: &mut Pending) -> Result<()> {
        let components = store::lock(self.store)?.components(&target.owner)?;
        for component in &components {
            let name = target_component(target, &component.role)?;
            let location = Location {
                folder: target.folder.clone(),
                name: name.into(),
            };
            self.move_media(target, component, location, component.properties.as_ref())?;
        }
        let components = store::lock(self.store)?.components(&target.owner)?;
        for component in &components {
            Properties::read(&self.path(&component.location)?)
                .context("retained original is missing")?;
            let previous = store::lock(self.store)?
                .json_record(&target.owner, Some(&component.role))?
                .context("missing retained metadata")?;
            let location = Location {
                folder: target.folder.clone(),
                name: format!("metadata/{}.json", component.location.name),
            };
            let mut value = previous.value;
            value["title"] = Value::String(component.location.name.clone());
            let mut layout: Vec<crate::metadata::Component> =
                serde_json::from_value(value["ente"]["components"].clone())?;
            for identity in &mut layout {
                identity.path = target_component(target, &identity.role)?.into();
                if let Some(recorded) = components
                    .iter()
                    .find(|component| component.role == identity.role)
                {
                    identity.size = recorded.size;
                    identity.hash = recorded.hash.clone();
                }
            }
            value["ente"]["components"] = serde_json::to_value(layout)?;
            self.write_json(
                target,
                Some(component.role.clone()),
                location,
                fs::Json::new(value)?,
            )?;
        }
        let store = store::lock(self.store)?;
        let transaction = store.db.unchecked_transaction()?;
        store.save_placement(&target.placement()?)?;
        store.clear_pending(&target.owner)?;
        event(&store, &target.owner, "retained")?;
        transaction.commit()?;
        Ok(())
    }

    pub fn retain_removed(&self) -> Result<()> {
        let mut after = String::new();
        loop {
            self.check_cancel()?;
            let next = {
                let store = store::lock(self.store)?;
                store
                    .db
                    .query_row(
                        "SELECT p.id,p.album,p.file,p.retained,p.name,p.kind FROM placements p JOIN desired_albums a ON a.id=p.album WHERE p.id>?1 AND p.retained=0 AND a.selected=1 AND a.ready=1 AND a.failure IS NULL AND NOT EXISTS(SELECT 1 FROM desired_files f WHERE f.album=p.album AND f.file=p.file) AND NOT EXISTS(SELECT 1 FROM outcomes WHERE unit='file:'||p.album||':'||p.file) ORDER BY p.id LIMIT 1",
                        [&after],
                        Placement::read,
                    )
                    .optional()?
            };
            let Some(placement) = next else {
                break;
            };
            after = placement.id.clone();
            let (album, file) = (placement.album, placement.file);
            if let Err(error) = self.retain(placement) {
                self.block(album, Some(file), error)?;
            }
        }
        {
            let store = store::lock(self.store)?;
            let transaction = store.db.unchecked_transaction()?;
            store
                .db
                .execute(
                    "DELETE FROM pending WHERE file IS NOT NULL AND action='null' AND album IN (SELECT id FROM desired_albums WHERE selected=1 AND ready=1 AND failure IS NULL) AND NOT EXISTS(SELECT 1 FROM placements WHERE id=pending.owner) AND NOT EXISTS(SELECT 1 FROM desired_files WHERE album=pending.album AND file=pending.file)",
                    [],
                )?;
            store
                .db
                .execute(
                    "DELETE FROM json_records WHERE folder IS NULL AND NOT EXISTS(SELECT 1 FROM albums WHERE key=json_records.owner) AND NOT EXISTS(SELECT 1 FROM components WHERE placement=json_records.owner) AND NOT EXISTS(SELECT 1 FROM pending WHERE owner=json_records.owner)",
                    [],
                )?;
            transaction.commit()?;
        }
        let mut after = 0;
        loop {
            self.check_cancel()?;
            let id: Option<i64> = store::lock(self.store)?
                .db
                .query_row(
                    "SELECT id FROM desired_albums WHERE id>?1 AND selected=1 AND ready=1 AND failure IS NULL AND present=0 ORDER BY id LIMIT 1",
                    [after],
                    |r| r.get(0),
                )
                .optional()?;
            let Some(id) = id else {
                break;
            };
            after = id;
            if let Err(error) = self.remove_album(id) {
                self.block(id, None, error)?;
            }
        }
        Ok(())
    }

    fn remove_album(&self, id: i64) -> Result<()> {
        let active = store::lock(self.store)?.album(id, false)?;
        let Some(active) = active else {
            let store = store::lock(self.store)?;
            store.clear_pending(&format!("active:{id}"))?;
            return Ok(());
        };
        let incomplete: bool = store::lock(self.store)?.db.query_row(
            "SELECT EXISTS(SELECT 1 FROM placements WHERE album=?1 AND retained=0) OR EXISTS(SELECT 1 FROM pending WHERE album=?1 AND file IS NOT NULL)",
            [id],
            |r| r.get(0),
        )?;
        ensure!(!incomplete, "album has unfinished retention");
        self.retained_album(&active)?;
        let mut target = self.album_target(id, &active.name, false)?;
        let record = store::lock(self.store)?.json_record(&active.key, None)?;
        if let Some(record) = record
            && let Some(location) = record.location
        {
            self.start(
                &mut target,
                Action::Remove {
                    location,
                    role: None,
                },
                &[],
            )?;
            self.finish_action(&mut target, false, None)?;
        }
        for relative in [format!("{}/metadata", active.path), active.path.clone()] {
            let path = names::check(self.root, &relative)?;
            if directory_exists(&path)? && disk::read_dir(&path)?.next().is_none() {
                disk::remove_dir(&path)?;
                fs::sync_parent(&path)?;
            }
        }
        let store = store::lock(self.store)?;
        let transaction = store.db.unchecked_transaction()?;
        store
            .db
            .execute(
                "DELETE FROM albums WHERE key=?1 AND NOT EXISTS(SELECT 1 FROM temporaries WHERE folder=?1)",
                [&active.key],
            )?;
        store.clear_pending(&target.owner)?;
        transaction.commit()?;
        Ok(())
    }
}

fn target_component<'a>(target: &'a Pending, role: &Role) -> Result<&'a str> {
    let index = match role {
        Role::Original | Role::Image => 0,
        Role::Video => 1,
    };
    target
        .names
        .get(index)
        .map(String::as_str)
        .context("missing target component")
}
