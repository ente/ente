mod adopt;
mod fs;
mod legacy;
mod live_photo;
mod metadata;
mod names;
mod reconcile;
mod snapshot;
mod source;
mod store;
mod transfer;

pub use source::{CollectionEntry, FileEntry, Source};

use std::{
    fs::{File, OpenOptions},
    io::Write,
    num::NonZeroUsize,
    path::{Path, PathBuf},
    sync::Mutex,
    time::{Duration, Instant},
};

use crate::metadata::Root;
use anyhow::{Context, Result, bail, ensure};
use rusqlite::{OptionalExtension, params};
use serde_json::{Value, json};

use tokio::sync::watch;

use snapshot::FileSnapshot;
use store::Store;

#[derive(Debug, thiserror::Error)]
#[error("conflict: {0}")]
struct Conflict(String);

#[derive(Debug, thiserror::Error)]
#[error("export cancelled")]
struct Cancelled;

pub struct Options {
    pub albums: Vec<String>,
    pub exclude_albums: Vec<String>,
    pub adopt: bool,
    pub jobs: NonZeroUsize,
}

#[derive(Debug, thiserror::Error)]
#[error("{0}")]
pub struct AdoptionRequired(&'static str);

pub struct Summary {
    pub json: Value,
    pub complete: bool,
    pub completed: i64,
    pub expected: i64,
}

pub struct Export {
    destination: PathBuf,
    expected_root: Root,
    prepared: Option<(Store, Result<()>)>,
    root_lock: Option<File>,
    options: Options,
    adopting: bool,
}

impl Export {
    pub fn open(
        path: &Path,
        master_key: &ente_core::crypto::Key,
        options: Options,
    ) -> Result<Self> {
        let destination = destination(path)?;
        let expected_root = Root::new(master_key)?;
        let root_lock = open_root(&destination, &expected_root)?;
        let adopting = root_lock.is_none() && legacy::read::recognized(&destination)?;
        ensure!(
            !adopting || options.adopt,
            AdoptionRequired(
                "This folder contains an export from the old CLI or Ente Desktop. Use --adopt if you want to take it over."
            )
        );
        ensure!(
            !options.adopt || root_lock.is_some() || adopting,
            "there is no export to adopt"
        );
        ensure!(
            root_lock.is_some()
                || adopting
                || !destination.try_exists()?
                || std::fs::read_dir(&destination)?.next().is_none(),
            "nonempty destination has no recognized export.json"
        );
        Ok(Self {
            destination,
            expected_root,
            root_lock,
            options,
            prepared: None,
            adopting,
        })
    }

    pub fn destination(&self) -> &Path {
        &self.destination
    }

    pub fn exists(&self) -> bool {
        self.root_lock.is_some()
    }

    pub fn verify_source(&self, master_key: &ente_core::crypto::Key) -> Result<()> {
        ensure!(
            Root::new(master_key)?.source_verifier == self.expected_root.source_verifier,
            "account keys changed while waiting for access"
        );
        Ok(())
    }

    pub async fn prepare(
        &mut self,
        connection: rusqlite::Connection,
        open_index: impl FnOnce(&Path) -> Result<rusqlite::Connection>,
        source: &mut impl Source,
        session: &ente_core::Session,
        cancel: &mut watch::Receiver<bool>,
        report: &(dyn Fn(&str) + Sync),
    ) -> Result<()> {
        let store = Store::open(connection, &self.destination)?;
        let bound: bool = store
            .db
            .query_row("SELECT bound FROM export WHERE id=1", [], |r| r.get(0))?;
        let accepted = !bound
            && store.db.query_row(
                "SELECT EXISTS(SELECT 1 FROM albums WHERE retained=0)",
                [],
                |r| r.get::<_, bool>(0),
            )?;
        ensure!(
            self.root_lock.is_none() || bound || accepted || self.options.adopt,
            AdoptionRequired("this export is not associated; use --adopt")
        );
        let initial = !bound && !accepted && self.options.adopt;
        let index = initial.then(|| adopt::Index::new(open_index)).transpose()?;
        store.reset_desired()?;
        let mut failures = legacy::Failures::default();
        self.adopting = !bound
            && (accepted
                || (initial && (self.adopting || legacy::read::recognized(&self.destination)?)));
        if let Some(index) = &index {
            let mut desktop = None;
            failures.record(
                legacy::read::desktop(&self.destination).map(|value| desktop = value),
                "export_status.json",
            )?;
            if self.root_lock.is_some() {
                failures.record(
                    adopt::scan(&self.destination, index, desktop.as_ref()),
                    "native records",
                )?;
            }
            if self.adopting {
                legacy::read::scan(
                    &self.destination,
                    index,
                    session.user_id,
                    desktop.as_ref(),
                    &mut failures,
                )?;
            }
        }
        report("Refreshing album metadata.");
        tokio::select! {
            result=source.refresh_catalog(session)=>result?,
            _=cancel.changed()=>return Err(Cancelled.into()),
        }
        let mut after = 0;
        loop {
            ensure!(!*cancel.borrow(), Cancelled);
            let entries = source.catalog_page(after)?;
            if entries.is_empty() {
                break;
            }
            for entry in entries {
                after = entry.id;
                store.desired_album(&entry)?;
            }
        }
        store
            .db
            .execute(
                "INSERT OR IGNORE INTO desired_albums(id,name) SELECT s.id,json_extract(s.record,'$.name') FROM album_sources s WHERE EXISTS(SELECT 1 FROM albums a WHERE a.id=s.id)",
                [],
            )?;
        store
            .db
            .execute(
                "INSERT OR IGNORE INTO desired_albums(id,name) SELECT id,name FROM albums ORDER BY retained",
                [],
            )?;
        store
            .db
            .execute(
                "INSERT OR IGNORE INTO desired_albums(id,name) SELECT album,name FROM pending WHERE file IS NULL AND retained=0",
                [],
            )?;
        if let Some(index) = &index {
            let mut albums = index.db.prepare("SELECT id,json_extract(record,'$.album.name') FROM adoption_album ORDER BY retained")?;
            for row in
                albums.query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?)))?
            {
                let (id, name) = row?;
                store.db.execute(
                    "INSERT OR IGNORE INTO desired_albums(id,name) VALUES(?1,?2)",
                    params![id, name],
                )?;
            }
        }
        if self.adopting {
            legacy::scope(&store, &self.options, index.as_ref())?;
        } else {
            failures.finish()?;
            select(&store, &self.options)?;
        }
        if !self.adopting {
            if self.root_lock.is_none() {
                self.root_lock = Some(initialize(&self.destination, &self.expected_root, false)?);
            }
            if !initial {
                store
                    .db
                    .execute("UPDATE export SET bound=1 WHERE id=1 AND bound=0", [])?;
            }
        }
        let refresh_cancel = cancel.clone();
        let refreshed = tokio::select! {
            result=refresh(&store,source,session,&refresh_cancel,report)=>result,
            _=cancel.changed()=>Err(Cancelled.into()),
        };
        if self.adopting {
            refreshed?;
            if let Some(index) = &index {
                report("Verifying every existing active legacy original before adoption.");
                legacy::Preflight {
                    root: &self.destination,
                    store: &store,
                    session,
                    index,
                    cancel,
                    matching_root: self.root_lock.is_some(),
                }
                .run(source, failures)
                .await?;
                if self.root_lock.is_none() {
                    self.root_lock =
                        Some(initialize(&self.destination, &self.expected_root, true)?);
                }
                legacy::move_leftovers(&self.destination, index, cancel)?;
                adopt::accept(index, &store, false)?;
            }
            self.prepared = Some((store, Ok(())));
            return Ok(());
        }
        if let Some(index) = &index {
            adopt::accept(index, &store, true)?;
        }
        self.prepared = Some((store, refreshed));
        Ok(())
    }

    pub fn execute(
        &mut self,
        session: &ente_core::Session,
        cancel_send: &watch::Sender<bool>,
        cancel: &watch::Receiver<bool>,
        report: &(dyn Fn(&str) + Sync),
    ) -> Result<Summary> {
        let (store, refreshed) = self.prepared.take().context("export is not prepared")?;
        let prepared = refreshed.is_ok();
        let shared = Mutex::new(store);
        let run = reconcile::Run {
            root: &self.destination,
            store: &shared,
            cancel,
            report,
        };
        let result = (|| {
            refreshed?;
            run.recover()?;
            run.albums()?;
            transfers(
                &self.destination,
                &shared,
                session,
                cancel_send,
                cancel,
                self.options.jobs.get(),
                report,
            )?;
            run.check_cancel()?;
            run.retain_removed()
        })();
        if let Err(error) = result {
            run.report("run", &error)?;
        }
        if let Err(error) = run.cleanup(None) {
            run.report("run", &error)?;
        }
        let store = shared
            .into_inner()
            .map_err(|_| anyhow::anyhow!("export database mutex poisoned"))?;
        if self.adopting
            && work_complete(&store, prepared)?
            && let Err(error) = legacy::finish(&self.destination, &store, cancel)
        {
            record_outcome(&store, "run", &error)?;
            report(&format!("run: {error:#}"));
        }
        summary(&store, &self.destination, prepared)
    }
}

fn destination(path: &Path) -> Result<PathBuf> {
    let absolute = if path.is_absolute() {
        path.to_owned()
    } else {
        std::env::current_dir()?.join(path)
    };
    let mut base = absolute.as_path();
    let mut tail = Vec::new();
    while !base.try_exists()? {
        tail.push(
            base.file_name()
                .context("destination has no directory name")?
                .to_owned(),
        );
        base = base
            .parent()
            .context("destination has no existing parent")?;
    }
    if tail.is_empty() {
        ensure!(
            !std::fs::symlink_metadata(base)?.is_symlink(),
            "export destination is a symlink"
        );
    }
    let mut resolved = std::fs::canonicalize(base)?;
    for part in tail.into_iter().rev() {
        resolved.push(part);
    }
    Ok(resolved)
}

fn open_root(destination: &Path, expected: &Root) -> Result<Option<File>> {
    if !destination.try_exists()? {
        return Ok(None);
    }
    ensure!(
        destination.is_dir(),
        "export destination is not a directory"
    );
    let path = names::check(destination, "export.json")?;
    if !path.try_exists()? {
        return Ok(None);
    }
    let file = OpenOptions::new().read(true).write(true).open(&path)?;
    file.try_lock()
        .context("another writer is maintaining this export")?;
    let record: Root = serde_json::from_reader(&file).context("invalid export.json")?;
    ensure!(
        record.format == expected.format && record.version == expected.version,
        "unsupported export format"
    );
    ensure!(
        record.source_verifier == expected.source_verifier,
        "this export belongs to another source account"
    );
    Ok(Some(file))
}

fn initialize(destination: &Path, root: &Root, legacy: bool) -> Result<File> {
    fs::create_directory(destination)?;
    let path = names::check(destination, "export.json")?;
    let mut file = OpenOptions::new()
        .read(true)
        .write(true)
        .create_new(true)
        .open(&path)
        .context("destination was initialized by another writer; retry")?;
    file.lock().context("cannot lock the new export")?;
    ensure!(
        legacy
            || std::fs::read_dir(destination)?
                .all(|entry| entry.is_ok_and(|entry| entry.file_name() == "export.json")),
        "destination became nonempty during initialization"
    );
    serde_json::to_writer_pretty(&mut file, root)?;
    file.write_all(b"\n")?;
    file.sync_all()?;
    fs::sync_parent(&path)?;
    Ok(file)
}

fn select(store: &Store, options: &Options) -> Result<()> {
    if options.albums.is_empty() {
        store
            .db
            .execute("UPDATE desired_albums SET selected=1", [])?;
    }
    for (selectors, include) in [(&options.albums, true), (&options.exclude_albums, false)] {
        for selector in selectors {
            let mut query = store.db.prepare(
                "SELECT id,name FROM desired_albums WHERE id=?1 OR name=?2 ORDER BY id LIMIT 11",
            )?;
            let candidates: Vec<(i64, Option<String>)> = query
                .query_map(params![canonical_id(selector), selector], |r| {
                    Ok((r.get(0)?, r.get(1)?))
                })?
                .collect::<rusqlite::Result<_>>()?;
            ensure!(!candidates.is_empty(), "no album matches {selector:?}");
            if candidates.len() != 1 {
                bail!(
                    "album {selector:?} is ambiguous: {}",
                    candidates
                        .iter()
                        .map(|(id, name)| format!(
                            "{id} {:?}",
                            name.as_deref().unwrap_or("unavailable")
                        ))
                        .collect::<Vec<_>>()
                        .join(", ")
                );
            }
            store.db.execute(
                "UPDATE desired_albums SET selected=?1 WHERE id=?2",
                params![include, candidates[0].0],
            )?;
        }
    }
    Ok(())
}

async fn refresh(
    store: &Store,
    source: &mut impl Source,
    session: &ente_core::Session,
    cancel: &watch::Receiver<bool>,
    report: &(dyn Fn(&str) + Sync),
) -> Result<()> {
    let need_favorites: bool = store.db.query_row(
        "SELECT EXISTS(SELECT 1 FROM desired_albums WHERE selected=1 AND present=1)",
        [],
        |r| r.get(0),
    )?;
    let mut favorites_known = true;
    let mut after = 0;
    report("Refreshing selected albums and Favorites.");
    loop {
        ensure!(!*cancel.borrow(), Cancelled);
        let next: Option<(i64, bool, bool)> = store
            .db
            .query_row(
                "SELECT id,selected,favorites FROM desired_albums WHERE present=1 AND (selected=1 OR (favorites=1 AND ?1)) AND id>?2 ORDER BY id LIMIT 1",
                params![need_favorites, after],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
            )
            .optional()?;
        let Some((id, selected, favorites)) = next else {
            break;
        };
        after = id;
        let refreshed = source.refresh_album(session, id).await;
        if refreshed.is_err() && favorites {
            favorites_known = false;
        }
        let result = refreshed.and_then(|entry| {
            store.desired_album(&entry)?;
            let (album, documents) = entry.value?;
            if selected {
                store.snapshot_album(&album, &documents, session.user_id)?;
            }
            store
                .db
                .execute("UPDATE desired_albums SET ready=1 WHERE id=?1", [id])?;
            Ok(())
        });
        if let Err(error) = result {
            store.db.execute(
                "UPDATE desired_albums SET failure=?1 WHERE id=?2",
                params![error.to_string(), id],
            )?;
            if selected {
                record_outcome(store, &format!("album:{id}"), &error)?;
                report(&format!("album:{id}: {error:#}"));
            }
            if fatal(&error) {
                return Err(error);
            }
        }
    }
    store.db.execute(
        "UPDATE desired_albums SET ready=1 WHERE selected=1 AND present=0",
        [],
    )?;
    if need_favorites && favorites_known {
        let mut after = 0;
        loop {
            let ids = source.favorite_page(after)?;
            if ids.is_empty() {
                break;
            }
            let transaction = store.db.unchecked_transaction()?;
            for id in ids {
                after = id;
                store.db.execute("INSERT INTO favorites VALUES(?1)", [id])?;
            }
            transaction.commit()?;
        }
    }
    after = 0;
    loop {
        let id: Option<i64> = store
            .db
            .query_row(
                "SELECT id FROM desired_albums WHERE selected=1 AND ready=1 AND present=1 AND failure IS NULL AND id>?1 ORDER BY id LIMIT 1",
                [after],
                |r| r.get(0),
            )
            .optional()?;
        let Some(id) = id else { break };
        after = id;
        let mut after_file = 0;
        loop {
            ensure!(!*cancel.borrow(), Cancelled);
            let records = source.file_page(id, after_file)?;
            if records.is_empty() {
                break;
            }
            let transaction = store.db.unchecked_transaction()?;
            for record in records {
                after_file = record.id;
                let file = record
                    .value
                    .and_then(|(file, documents)| FileSnapshot::new(file, &documents));
                let failure = if !favorites_known {
                    Some("favorite state is incomplete".to_owned())
                } else {
                    file.as_ref().err().map(ToString::to_string)
                };
                store.db.execute(
                    "INSERT INTO desired_files(album,file,favorited,failure) VALUES(?1,?2,?3,?4)",
                    params![
                        id,
                        record.id,
                        if favorites_known { Some(false) } else { None },
                        failure
                    ],
                )?;
                if failure.is_none() {
                    let file = file?;
                    store.db.execute(
                        "INSERT INTO chosen_files VALUES(?1,?2,?3) ON CONFLICT(file) DO UPDATE SET album=excluded.album,version=excluded.version WHERE excluded.version>chosen_files.version OR (excluded.version=chosen_files.version AND excluded.album<chosen_files.album)",
                        params![file.id, id, file.updated_at_micros],
                    )?;
                }
            }
            transaction.commit()?;
        }
    }
    store
        .db
        .execute(
            "UPDATE desired_files SET favorited=EXISTS(SELECT 1 FROM favorites WHERE favorites.file=desired_files.file) WHERE favorited IS NOT NULL",
            [],
        )?;
    let mut after_file = 0;
    loop {
        ensure!(!*cancel.borrow(), Cancelled);
        let mut query = store
            .db
            .prepare("SELECT album,file FROM chosen_files WHERE file>?1 ORDER BY file LIMIT 128")?;
        let chosen: Vec<(i64, i64)> = query
            .query_map([after_file], |r| Ok((r.get(0)?, r.get(1)?)))?
            .collect::<rusqlite::Result<_>>()?;
        drop(query);
        if chosen.is_empty() {
            break;
        }
        let transaction = store.db.unchecked_transaction()?;
        for (album, id) in chosen {
            after_file = id;
            let (file, documents) = source.file(album, id)?.value?;
            store.snapshot_file(&FileSnapshot::new(file, &documents)?)?;
        }
        transaction.commit()?;
    }
    let transaction = store.db.unchecked_transaction()?;
    store.db.execute(
        "DELETE FROM sources WHERE file NOT IN (SELECT file FROM chosen_files)",
        [],
    )?;
    store
        .db
        .execute(
            "DELETE FROM album_sources WHERE id NOT IN (SELECT id FROM desired_albums WHERE selected=1 AND ready=1 AND present=1 AND failure IS NULL) AND NOT EXISTS(SELECT 1 FROM albums WHERE albums.id=album_sources.id) AND NOT EXISTS(SELECT 1 FROM pending WHERE album=album_sources.id)",
            [],
        )?;
    transaction.commit()?;
    let mut query = store
        .db
        .prepare("SELECT album,file,failure FROM desired_files WHERE failure IS NOT NULL")?;
    let mut rows = query.query([])?;
    while let Some(row) = rows.next()? {
        let unit = format!("file:{}:{}", row.get::<_, i64>(0)?, row.get::<_, i64>(1)?);
        let error = anyhow::anyhow!(row.get::<_, String>(2)?);
        record_outcome(store, &unit, &error)?;
        report(&format!("{unit}: {error:#}"));
    }
    Ok(())
}

struct CancelWorkers<'a>(&'a watch::Sender<bool>);

impl Drop for CancelWorkers<'_> {
    fn drop(&mut self) {
        if std::thread::panicking() {
            self.0.send_replace(true);
        }
    }
}

fn transfers(
    root: &Path,
    store: &Mutex<Store>,
    session: &ente_core::Session,
    cancel_send: &watch::Sender<bool>,
    cancel: &watch::Receiver<bool>,
    jobs: usize,
    report: &(dyn Fn(&str) + Sync),
) -> Result<()> {
    let (expected, files): (i64, i64) = store::lock(store)?.db.query_row(
        "SELECT count(*),count(DISTINCT file) FROM desired_files WHERE failure IS NULL",
        [],
        |r| Ok((r.get(0)?, r.get(1)?)),
    )?;
    report(&format!("Maintaining {expected} selected copies."));
    let runtime = tokio::runtime::Handle::current();
    let last_report = Mutex::new(None::<Instant>);
    std::thread::scope(|scope| {
        let mut workers = Vec::new();
        for _ in 0..jobs.min(files as usize) {
            let runtime = &runtime;
            let last_report = &last_report;
            workers.push(scope.spawn(move || {
                let _cancel_on_panic = CancelWorkers(cancel_send);
                let run = reconcile::Run { root, store, cancel, report };
                let result = (|| {
                    loop {
                        if *cancel.borrow() {
                            break;
                        }
                        let file = {
                            let store = store::lock(store)?;
                            let transaction = store.db.unchecked_transaction()?;
                            let id: Option<i64> = store
                                .db
                                .query_row(
                                    "SELECT file FROM desired_files WHERE failure IS NULL AND claimed=0 ORDER BY file LIMIT 1",
                                    [],
                                    |r| r.get(0),
                                )
                                .optional()?;
                            let Some(id) = id else {
                                break;
                            };
                            store
                                .db
                                .execute(
                                    "UPDATE desired_files SET claimed=1 WHERE file=?1",
                                    [id],
                                )?;
                            let file: FileSnapshot = store::json(&store.db,"SELECT record FROM sources WHERE file=?1", [id])?
                                .context("missing file source snapshot")?;
                            transaction.commit()?;
                            file
                        };
                        let id = file.id;
                        let result = runtime.block_on(run.file(session, file));
                        if result.as_ref().err().is_some_and(fatal) {
                            cancel_send.send_replace(true);
                        }
                        let reported = result.or_else(|error| run.block_file(id, error));
                        let cleaned = run.cleanup(Some(id));
                        reported?;
                        cleaned?;
                        let completed = {
                            let mut last = last_report.lock().map_err(|_| anyhow::anyhow!("progress mutex poisoned"))?;
                            if last.is_none_or(|time| time.elapsed() >= Duration::from_secs(2)) {
                                *last = Some(Instant::now());
                                Some(store::lock(store)?.db.query_row(
                                    "SELECT count(*) FROM desired_files WHERE completed=1",
                                    [],
                                    |r| r.get::<_, i64>(0),
                                )?)
                            } else {
                                None
                            }
                        };
                        if let Some(completed) = completed {
                            report(&format!("Completed {completed}/{expected} selected copies."));
                        }
                    }
                    Ok(())
                })();
                if result.is_err() {
                    cancel_send.send_replace(true);
                }
                result
            }));
        }
        let mut result = Ok(());
        for worker in workers {
            let completed = worker
                .join()
                .unwrap_or_else(|_| Err(anyhow::anyhow!("export worker panicked")));
            if result.is_ok() {
                result = completed;
            }
        }
        result
    })
}

fn record_outcome(store: &Store, unit: &str, error: &anyhow::Error) -> Result<()> {
    let conflict = error.downcast_ref::<Conflict>().is_some();
    store
        .db
        .execute(
            "INSERT INTO outcomes VALUES(?1,?2) ON CONFLICT(unit) DO UPDATE SET conflict=max(conflict,excluded.conflict)",
            params![unit, conflict],
        )?;
    Ok(())
}

fn fatal(error: &anyhow::Error) -> bool {
    fatal_cause(error.as_ref())
}

fn fatal_cause(cause: &(dyn std::error::Error + 'static)) -> bool {
    if cause.is::<rusqlite::Error>()
        || cause.is::<Cancelled>()
        || cause
            .downcast_ref::<ente_core::http::Error>()
            .is_some_and(|error| error.status_code() == Some(401))
    {
        return true;
    }
    if let Some(error) = cause.downcast_ref::<std::io::Error>() {
        return error.kind() == std::io::ErrorKind::StorageFull
            || error.get_ref().is_some_and(|inner| fatal_cause(inner));
    }
    if let Some(error) = cause.downcast_ref::<ente_photos::files::Error>() {
        use ente_photos::files::Error;
        match error {
            Error::Http(error) => return fatal_cause(error),
            Error::Io(error) => return fatal_cause(error),
            Error::Collections(error) => return fatal_cause(error),
            _ => {}
        }
    }
    if let Some(ente_collections::Error::Http(error)) = cause.downcast_ref() {
        return fatal_cause(error);
    }
    if let Some(error) = cause.downcast_ref::<crate::live_photo::Error>() {
        match error {
            crate::live_photo::Error::Io(error) => return fatal_cause(error),
            crate::live_photo::Error::Zip(error) => return fatal_cause(error),
            crate::live_photo::Error::Components | crate::live_photo::Error::ExpansionLimit => {}
        }
    }
    cause.source().is_some_and(fatal_cause)
}

fn work_complete(store: &Store, prepared: bool) -> Result<bool> {
    Ok(prepared && store.db.query_row("SELECT NOT EXISTS(SELECT 1 FROM desired_albums WHERE selected=1 AND (ready=0 OR failure IS NOT NULL)) AND NOT EXISTS(SELECT 1 FROM desired_files WHERE completed=0 OR failure IS NOT NULL) AND NOT EXISTS(SELECT 1 FROM outcomes) AND NOT EXISTS(SELECT 1 FROM pending p JOIN desired_albums a ON a.id=p.album WHERE a.selected=1)",[],|r|r.get::<_,bool>(0))?)
}

fn summary(store: &Store, destination: &Path, prepared: bool) -> Result<Summary> {
    let unknown: bool = !prepared
        || store.db.query_row(
            "SELECT EXISTS(SELECT 1 FROM desired_albums WHERE selected=1 AND ready=0)",
            [],
            |r| r.get(0),
        )?;
    let (files, expected, completed): (i64, i64, i64) = store.db.query_row(
        "SELECT count(DISTINCT file),count(*),coalesce(sum(completed),0) FROM desired_files",
        [],
        |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
    )?;
    let (failures, conflicts): (i64, i64) = store.db.query_row(
        "SELECT count(*),coalesce(sum(conflict),0) FROM outcomes",
        [],
        |r| Ok((r.get(0)?, r.get(1)?)),
    )?;
    let (exported, metadata_updated, renamed, retained): (i64, i64, i64, i64) = store
        .db
        .query_row(
            "SELECT coalesce(sum(exported),0),coalesce(sum(metadata_updated),0),coalesce(sum(renamed),0),coalesce(sum(retained),0) FROM events",
            [],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)),
        )?;
    let bound: bool = store
        .db
        .query_row("SELECT bound FROM export WHERE id=1", [], |r| r.get(0))?;
    let complete = bound && work_complete(store, prepared)?;
    let result = json!({"destination":destination.to_string_lossy(),"complete":complete,"files":if unknown {None}else{Some(files)},"copies":if unknown {None}else{Some(json!({"expected":expected,"completed":completed,"pending":expected-completed}))},"changes":{"exported":exported,"metadataUpdated":metadata_updated,"renamed":renamed,"retained":retained},"failures":failures,"conflicts":conflicts});
    Ok(Summary {
        json: result,
        complete,
        completed,
        expected,
    })
}

fn canonical_id(selector: &str) -> rusqlite::types::Value {
    selector
        .parse::<i64>()
        .ok()
        .filter(|id| id.to_string() == selector)
        .map(rusqlite::types::Value::Integer)
        .unwrap_or(rusqlite::types::Value::Null)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn transparent_errors_preserve_fatal_classification() {
        for status in [401, 404] {
            let error = ente_core::http::Error::Http {
                status,
                path: "/files".into(),
            };
            let error =
                ente_photos::files::Error::Collections(ente_collections::Error::Http(error));
            let error = anyhow::Error::new(error).context("download failed");
            assert_eq!(fatal(&error), status == 401);
            assert_eq!(
                format!("{error:#}"),
                format!("download failed: HTTP {status} at /files")
            );
        }
        let cancelled = crate::live_photo::Error::Io(std::io::Error::other(Cancelled));
        assert!(fatal(&anyhow::Error::new(cancelled)));
        let full = crate::live_photo::Error::Io(std::io::ErrorKind::StorageFull.into());
        assert!(fatal(&anyhow::Error::new(full)));
        let zip = crate::live_photo::Error::Zip(zip::result::ZipError::Io(
            std::io::ErrorKind::StorageFull.into(),
        ));
        assert!(fatal(&anyhow::Error::new(zip)));
        let sqlite = rusqlite::Error::InvalidQuery;
        assert!(fatal(&anyhow::Error::new(sqlite)));
        let local = ente_photos::files::Error::Io(std::io::ErrorKind::PermissionDenied.into());
        assert!(!fatal(&anyhow::Error::new(local)));
    }
}
