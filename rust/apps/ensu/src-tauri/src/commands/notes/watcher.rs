use std::collections::{BTreeSet, hash_map::Entry};
use std::fs;
use std::path::{Component, Path, PathBuf};
use std::sync::PoisonError;

use ente_ensu::notes::{
    NotesCollectionIndex, NotesError, NotesIndexWriter, notes_content_revision,
    prepare_notes_document,
};
use notify::event::{CreateKind, ModifyKind, RemoveKind};
use notify::{Config, Event, EventKind, RecommendedWatcher, RecursiveMode, Watcher};
use tauri::async_runtime;
use tauri::{AppHandle, Emitter, Manager};

use crate::commands::common::ApiError;

use super::registry::RegisteredCollection;
use super::source::{
    canonical_source_root, inventory_source_root, is_supported_file, read_collection_source,
    relative_document_id, source_root_is_available, walk_source_tree,
};
use super::{
    CollectionWatcher, DesktopUpdateState, NOTES_MAX_WATCH_DIRECTORIES, NOTES_STATE_CHANGED_EVENT,
    NotesCollectionStatusDto, State, notes_error, now_ms,
};

#[derive(Default)]
pub(super) struct WatchChange {
    pub(super) forced_document_ids: BTreeSet<String>,
    pub(super) force_full_hash: bool,
    pub(super) reattach_root: bool,
    pub(super) refresh_watches: bool,
}

impl WatchChange {
    fn merge(&mut self, change: Self) {
        self.forced_document_ids.extend(change.forced_document_ids);
        self.force_full_hash |= change.force_full_hash;
        self.reattach_root |= change.reattach_root;
        self.refresh_watches |= change.refresh_watches;
    }
}

pub(super) struct WatchWork {
    pending: Option<WatchChange>,
}

pub(super) struct StartupInspection {
    pub(super) initial_complete: bool,
    pub(super) changed: bool,
    pub(super) forced_document_ids: BTreeSet<String>,
    pub(super) opened_index: Option<NotesCollectionIndex>,
}

pub async fn initialize_for_app(app: AppHandle) {
    let Some(state) = app.try_state::<State>() else {
        return;
    };
    let collections = state
        .registry
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .registry
        .collections
        .clone();
    for collection in collections {
        let lifecycle = app.state::<State>().collection_lifecycle(&collection.id);
        let _collection_lifecycle = lifecycle.lock().await;
        if app
            .state::<State>()
            .registered_collection(&collection.id)
            .is_err()
        {
            continue;
        }
        let install_app = app.clone();
        let install_collection = collection.clone();
        let install_result = async_runtime::spawn_blocking(move || {
            install_collection_watcher(&install_app, &install_collection)
        })
        .await;
        let install_result = match install_result {
            Ok(result) => result,
            Err(_) => Err(ApiError::new("watcher_thread", "Notes watcher task failed")),
        };
        match install_result {
            Ok(()) => {
                app.state::<State>().set_watcher_error(&collection.id, None);
            }
            Err(error) => {
                let state = app.state::<State>();
                state.set_watcher_error(&collection.id, Some(&error));
                crate::logging::log(
                    "Notes",
                    format!(
                        "watcher unavailable collection={} error={}",
                        collection.id, error.message
                    ),
                );
            }
        }
        inspect_collection_on_startup(app.clone(), collection).await;
    }
}

async fn inspect_collection_on_startup(app: AppHandle, collection: RegisteredCollection) {
    let index_root = app.state::<State>().index_root.clone();
    if app
        .state::<State>()
        .registered_collection(&collection.id)
        .is_err()
    {
        return;
    }
    let inspection_collection = collection.clone();
    let inspection = async_runtime::spawn_blocking(move || {
        inspect_startup_freshness(&index_root, &inspection_collection)
    })
    .await;
    let Ok(inspection) = inspection else {
        return;
    };
    let state = app.state::<State>();
    if state.registered_collection(&collection.id).is_err() {
        return;
    }
    match inspection {
        Ok(inspection) => {
            let StartupInspection {
                initial_complete,
                changed,
                forced_document_ids,
                opened_index,
            } = inspection;
            let mut runtime = state.runtime(&collection.id);
            runtime.index_available = opened_index.is_some();
            runtime.indexed_document_count = opened_index
                .as_ref()
                .map_or(0, |index| index.document_count() as u64);
            runtime.last_updated_at_ms = opened_index
                .as_ref()
                .and_then(NotesCollectionIndex::last_updated_at_ms);
            runtime.indexing_progress = None;
            if runtime.index_available {
                runtime.status = NotesCollectionStatusDto::Ready;
                runtime.last_error = None;
            } else if initial_complete {
                runtime.status = NotesCollectionStatusDto::Error;
                runtime.last_error =
                    Some("No supported non-empty UTF-8 notes were found".to_string());
            } else {
                runtime.status = NotesCollectionStatusDto::Pending;
                runtime.last_error = None;
            }
            state.set_runtime(&collection.id, runtime);
            if let Some(index) = opened_index {
                state
                    .cached_indexes
                    .lock()
                    .unwrap_or_else(PoisonError::into_inner)
                    .insert(collection.id.clone(), index);
            }
            if changed && initial_complete {
                mark_collection_dirty(&app, &collection.id, forced_document_ids, false);
            } else {
                emit_state_changed(&app, &collection.id);
            }
        }
        Err(error) => {
            let mut runtime = state.runtime(&collection.id);
            runtime.status = if source_root_is_available(&collection.source_root) {
                NotesCollectionStatusDto::Error
            } else {
                NotesCollectionStatusDto::Unavailable
            };
            runtime.last_error = Some(error.message);
            state.set_runtime(&collection.id, runtime);
            emit_state_changed(&app, &collection.id);
        }
    }
}

pub(super) fn inspect_startup_freshness(
    index_root: &Path,
    collection: &RegisteredCollection,
) -> Result<StartupInspection, ApiError> {
    let canonical_root = canonical_source_root(&collection.source_root)?;
    if canonical_root != collection.source_root {
        return Err(ApiError::new(
            "source_changed",
            "Notes source folder identity changed",
        ));
    }
    let inventory = inventory_source_root(&canonical_root, || Ok(()))?;
    let writer = match NotesIndexWriter::open(index_root, collection.id.clone()) {
        Ok(writer) => writer,
        Err(NotesError::IncompatibleIndex) => {
            return Ok(StartupInspection {
                initial_complete: false,
                changed: true,
                forced_document_ids: BTreeSet::new(),
                opened_index: None,
            });
        }
        Err(error) => return Err(notes_error(error)),
    };
    let plan = writer
        .plan_reconciliation(&inventory, &[], false)
        .map_err(notes_error)?;
    let planned = plan
        .content_required_document_ids
        .iter()
        .map(String::as_str)
        .collect::<BTreeSet<_>>();
    let mut changed = !plan.deleted_document_ids.is_empty();
    let mut forced_document_ids = BTreeSet::new();
    for source in &inventory {
        if planned.contains(source.document_id.as_str()) {
            if writer.indexed_revision(&source.document_id).is_some() {
                changed = true;
                continue;
            }
            match read_collection_source(&canonical_root, &source.document_id) {
                Ok((_, bytes, _)) => {
                    changed |= prepare_notes_document(&source.document_id, &bytes).is_ok();
                }
                Err(error) if error.name == Some("source_changed") => {
                    changed = true;
                }
                Err(error) => return Err(error),
            }
            continue;
        }
        let Some(indexed_revision) = writer.indexed_revision(&source.document_id) else {
            continue;
        };
        match read_collection_source(&canonical_root, &source.document_id) {
            Ok((_, bytes, _)) if notes_content_revision(&bytes) == indexed_revision => {}
            Ok(_) => {
                forced_document_ids.insert(source.document_id.clone());
            }
            Err(error) if error.name == Some("source_changed") => {
                forced_document_ids.insert(source.document_id.clone());
            }
            Err(error) => return Err(error),
        }
    }
    let initial_complete = writer.initial_inventory_complete();
    let opened_index = if initial_complete {
        match NotesCollectionIndex::open(index_root, collection.id.clone()) {
            Ok(index) => Some(index),
            Err(NotesError::NotReady) => None,
            Err(error) => return Err(notes_error(error)),
        }
    } else {
        None
    };
    Ok(StartupInspection {
        initial_complete,
        changed: changed || !forced_document_ids.is_empty(),
        forced_document_ids,
        opened_index,
    })
}

pub(super) fn watch_directories(root: &Path) -> Result<BTreeSet<PathBuf>, ApiError> {
    if !source_root_is_available(root) {
        return Ok(BTreeSet::new());
    }
    let mut directories = BTreeSet::new();
    walk_source_tree(
        root,
        || Ok(()),
        || {
            ApiError::new(
                "watcher",
                "The Notes folder contains too many filesystem entries to watch",
            )
        },
        |directory| {
            if directories.len() >= NOTES_MAX_WATCH_DIRECTORIES {
                return Err(ApiError::new(
                    "watcher",
                    "The Notes folder contains too many directories to watch",
                ));
            }
            directories.insert(directory.to_path_buf());
            Ok(())
        },
        |_, _| Ok(()),
    )?;
    Ok(directories)
}

pub(super) fn install_collection_watcher(
    app: &AppHandle,
    collection: &RegisteredCollection,
) -> Result<(), ApiError> {
    let collection_id = collection.id.clone();
    let source_root = collection.source_root.clone();
    let callback_app = app.clone();
    let callback_collection_id = collection_id.clone();
    let callback_root = source_root.clone();
    let mut watcher = RecommendedWatcher::new(
        move |result| {
            handle_watch_event(
                &callback_app,
                &callback_collection_id,
                &callback_root,
                result,
            );
        },
        Config::default(),
    )
    .map_err(notify_error)?;

    let watched_directories = watch_directories(&source_root)?;
    for directory in &watched_directories {
        watcher
            .watch(directory, RecursiveMode::NonRecursive)
            .map_err(notify_error)?;
    }
    let parent_watched = source_root
        .parent()
        .is_some_and(|parent| watcher.watch(parent, RecursiveMode::NonRecursive).is_ok());
    if watched_directories.is_empty() && !parent_watched {
        return Err(ApiError::new(
            "watcher",
            "The Notes folder could not be watched",
        ));
    }
    app.state::<State>()
        .watchers
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .insert(
            collection_id,
            CollectionWatcher {
                watcher,
                watched_directories,
            },
        );
    Ok(())
}

fn handle_watch_event(
    app: &AppHandle,
    collection_id: &str,
    source_root: &Path,
    result: notify::Result<Event>,
) {
    let change = match result {
        Ok(event) => classify_watch_event(source_root, &event),
        Err(_) => Some(WatchChange {
            force_full_hash: true,
            reattach_root: true,
            refresh_watches: true,
            ..WatchChange::default()
        }),
    };
    let Some(change) = change else {
        return;
    };
    let should_spawn = {
        let state = app.state::<State>();
        let mut work = state
            .watch_work
            .lock()
            .unwrap_or_else(PoisonError::into_inner);
        match work.entry(collection_id.to_string()) {
            Entry::Occupied(mut entry) => {
                match &mut entry.get_mut().pending {
                    Some(pending) => pending.merge(change),
                    pending => *pending = Some(change),
                }
                false
            }
            Entry::Vacant(entry) => {
                entry.insert(WatchWork {
                    pending: Some(change),
                });
                true
            }
        }
    };
    if !should_spawn {
        return;
    }
    let event_app = app.clone();
    let event_collection_id = collection_id.to_string();
    let event_source_root = source_root.to_path_buf();
    async_runtime::spawn(async move {
        process_watch_changes(event_app, event_collection_id, event_source_root).await;
    });
}

async fn process_watch_changes(app: AppHandle, collection_id: String, source_root: PathBuf) {
    loop {
        let change = {
            let state = app.state::<State>();
            let mut work = state
                .watch_work
                .lock()
                .unwrap_or_else(PoisonError::into_inner);
            let Some(change) = work
                .get_mut(&collection_id)
                .and_then(|work| work.pending.take())
            else {
                work.remove(&collection_id);
                return;
            };
            change
        };
        if change.refresh_watches {
            let lifecycle = app.state::<State>().collection_lifecycle(&collection_id);
            let _collection_lifecycle = lifecycle.lock().await;
            if app
                .state::<State>()
                .registered_collection(&collection_id)
                .is_err()
            {
                continue;
            }
            let refresh_app = app.clone();
            let refresh_collection_id = collection_id.clone();
            let refresh_source_root = source_root.clone();
            let refresh_result = async_runtime::spawn_blocking(move || {
                refresh_collection_watches(
                    &refresh_app,
                    &refresh_collection_id,
                    &refresh_source_root,
                    change.reattach_root,
                )
            })
            .await;
            let refresh_result = match refresh_result {
                Ok(Ok(true)) => Ok(()),
                Ok(Ok(false)) => Err(ApiError::new(
                    "watcher",
                    "The Notes folder could not be watched",
                )),
                Ok(Err(error)) => Err(error),
                Err(_) => Err(ApiError::new("watcher_thread", "Notes watcher task failed")),
            };
            let state = app.state::<State>();
            match refresh_result {
                Ok(()) => {
                    if state.set_watcher_error(&collection_id, None) {
                        emit_state_changed(&app, &collection_id);
                    }
                }
                Err(error) => {
                    let changed = state.set_watcher_error(&collection_id, Some(&error));
                    crate::logging::log(
                        "Notes",
                        format!(
                            "watcher refresh failed collection={collection_id} error={}",
                            error.message
                        ),
                    );
                    if changed {
                        emit_state_changed(&app, &collection_id);
                    }
                }
            }
        }
        mark_collection_dirty(
            &app,
            &collection_id,
            change.forced_document_ids,
            change.force_full_hash,
        );
    }
}

fn refresh_collection_watches(
    app: &AppHandle,
    collection_id: &str,
    source_root: &Path,
    reattach_root: bool,
) -> Result<bool, ApiError> {
    let desired = watch_directories(source_root)?;
    let state = app.state::<State>();
    let mut watchers = state
        .watchers
        .lock()
        .unwrap_or_else(PoisonError::into_inner);
    let Some(entry) = watchers.get_mut(collection_id) else {
        return Ok(false);
    };
    if reattach_root {
        for directory in std::mem::take(&mut entry.watched_directories) {
            let _ = entry.watcher.unwatch(&directory);
        }
    }
    let removed = entry
        .watched_directories
        .difference(&desired)
        .cloned()
        .collect::<Vec<_>>();
    for directory in removed {
        let _ = entry.watcher.unwatch(&directory);
        entry.watched_directories.remove(&directory);
    }
    let added = desired
        .difference(&entry.watched_directories)
        .cloned()
        .collect::<Vec<_>>();
    for directory in added {
        entry
            .watcher
            .watch(&directory, RecursiveMode::NonRecursive)
            .map_err(notify_error)?;
        entry.watched_directories.insert(directory);
    }
    Ok(entry.watched_directories.contains(source_root))
}

pub(super) fn ensure_collection_watcher(
    app: &AppHandle,
    collection: &RegisteredCollection,
) -> Result<(), ApiError> {
    if !source_root_is_available(&collection.source_root) {
        return Err(ApiError::new(
            "source_unavailable",
            "Source folder is unavailable",
        ));
    }
    if refresh_collection_watches(app, &collection.id, &collection.source_root, false)
        .unwrap_or(false)
    {
        return Ok(());
    }
    let state = app.state::<State>();
    state
        .watchers
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .remove(&collection.id);
    install_collection_watcher(app, collection)
}

pub(super) fn classify_watch_event(source_root: &Path, event: &Event) -> Option<WatchChange> {
    if matches!(event.kind, EventKind::Access(_)) {
        return None;
    }
    let ambiguous = matches!(
        event.kind,
        EventKind::Any
            | EventKind::Other
            | EventKind::Create(CreateKind::Folder)
            | EventKind::Remove(RemoveKind::Any | RemoveKind::Folder | RemoveKind::Other)
            | EventKind::Modify(ModifyKind::Name(_))
    );
    classify_watch_paths(source_root, &event.paths, ambiguous)
}

fn classify_watch_paths(
    source_root: &Path,
    paths: &[PathBuf],
    overflow_or_ambiguity: bool,
) -> Option<WatchChange> {
    if paths.is_empty() {
        return overflow_or_ambiguity.then_some(WatchChange {
            force_full_hash: true,
            refresh_watches: true,
            ..WatchChange::default()
        });
    }
    let mut change = WatchChange {
        refresh_watches: overflow_or_ambiguity,
        ..WatchChange::default()
    };
    let mut saw_relevant_path = false;
    for path in paths {
        if path == source_root {
            saw_relevant_path = true;
            change.force_full_hash = true;
            change.reattach_root = true;
            change.refresh_watches = true;
            continue;
        }
        let Ok(relative) = path.strip_prefix(source_root) else {
            continue;
        };
        if relative.components().any(|component| {
            matches!(component, Component::Normal(name) if name.to_string_lossy().starts_with('.'))
        }) {
            continue;
        }
        let metadata = fs::symlink_metadata(path).ok();
        if metadata
            .as_ref()
            .is_some_and(|metadata| metadata.file_type().is_symlink())
        {
            saw_relevant_path = true;
            change.force_full_hash = true;
            change.refresh_watches = true;
            continue;
        }
        saw_relevant_path = true;
        if is_supported_file(path) {
            if let Some(document_id) = relative_document_id(source_root, path) {
                change.forced_document_ids.insert(document_id);
            }
            continue;
        }
        if metadata.as_ref().is_some_and(fs::Metadata::is_dir)
            || (metadata.is_none() && overflow_or_ambiguity)
        {
            change.force_full_hash = true;
            change.refresh_watches = true;
        }
    }
    change.force_full_hash |= overflow_or_ambiguity && saw_relevant_path;
    (!change.forced_document_ids.is_empty() || change.force_full_hash).then_some(change)
}

fn mark_collection_for_update(
    app: &AppHandle,
    collection_id: &str,
    record_update: impl FnOnce(&mut DesktopUpdateState) -> bool,
) {
    let state = app.state::<State>();
    let Ok(collection) = state.registered_collection(collection_id) else {
        return;
    };
    let changed = {
        let mut updates = state.updates.lock().unwrap_or_else(PoisonError::into_inner);
        let update = updates.entry(collection_id.to_string()).or_default();
        record_update(update)
    };
    if !changed {
        return;
    }

    let available = source_root_is_available(&collection.source_root);
    let mut runtime = state.runtime(collection_id);
    if !available
        && !matches!(
            runtime.status,
            NotesCollectionStatusDto::Indexing | NotesCollectionStatusDto::Updating
        )
    {
        runtime.status = NotesCollectionStatusDto::Unavailable;
    } else if available
        && matches!(
            runtime.status,
            NotesCollectionStatusDto::Unavailable | NotesCollectionStatusDto::Error
        )
    {
        runtime.status = if runtime.index_available {
            NotesCollectionStatusDto::Ready
        } else {
            NotesCollectionStatusDto::Pending
        };
    }
    runtime.last_error = (!available).then(|| "Source folder is unavailable".to_string());
    state.set_runtime(collection_id, runtime);
    emit_state_changed(app, collection_id);
}

pub(crate) fn mark_collection_dirty(
    app: &AppHandle,
    collection_id: &str,
    forced_document_ids: impl IntoIterator<Item = String>,
    force_full_hash: bool,
) {
    mark_collection_for_update(app, collection_id, move |update| {
        update.record_change(now_ms(), forced_document_ids, force_full_hash);
        true
    });
}

pub(crate) fn mark_reference_stale(app: &AppHandle, collection_id: &str, document_id: String) {
    mark_collection_for_update(app, collection_id, move |update| {
        update.record_stale_reference(now_ms(), document_id)
    });
}

pub(super) fn emit_state_changed(app: &AppHandle, collection_id: &str) {
    let state = app.state::<State>();
    if let Ok(collection) = state.collection_dto(collection_id) {
        let _ = app.emit(NOTES_STATE_CHANGED_EVENT, collection);
    }
}

fn notify_error(_: notify::Error) -> ApiError {
    ApiError::new("watcher", "The Notes folder could not be watched")
}

#[cfg(test)]
mod tests {
    use super::super::TestDirectory;
    use super::*;
    use ente_ensu::notes::NotesSourceDocument;
    use notify::event::RenameMode;

    const COLLECTION_ID: &str = "123e4567-e89b-12d3-a456-426614174000";

    #[test]
    fn incompatible_startup_index_remains_eligible_for_automatic_rebuild() {
        let temp = TestDirectory::new();
        let source_root = temp.path().join("source");
        fs::create_dir(&source_root).unwrap();
        fs::write(source_root.join("note.md"), "note").unwrap();
        let source_root = fs::canonicalize(source_root).unwrap();
        let index_root = temp.path().join("indexes");
        let mut writer = NotesIndexWriter::open(&index_root, COLLECTION_ID.to_string()).unwrap();
        writer.publish(false).unwrap();
        let manifest_path = index_root.join(COLLECTION_ID).join("manifest.json");
        let manifest = fs::read_to_string(&manifest_path).unwrap();
        let incompatible = manifest.replacen("\"schema_version\": 2", "\"schema_version\": 1", 1);
        assert_ne!(manifest, incompatible);
        fs::write(manifest_path, incompatible).unwrap();

        let inspection = inspect_startup_freshness(
            &index_root,
            &RegisteredCollection {
                id: COLLECTION_ID.to_string(),
                source_root,
            },
        )
        .unwrap();
        assert!(!inspection.initial_complete);
        assert!(inspection.changed);
    }

    #[cfg(unix)]
    #[test]
    fn watcher_directory_enumeration_does_not_follow_symlinks() {
        use std::os::unix::fs::symlink;

        let temp = TestDirectory::new();
        let root = temp.path().join("root");
        let nested = root.join("nested");
        let outside = temp.path().join("outside");
        fs::create_dir_all(&nested).unwrap();
        fs::create_dir(&outside).unwrap();
        symlink(&outside, root.join("linked")).unwrap();
        let root = fs::canonicalize(root).unwrap();
        let nested = root.join("nested");

        let directories = watch_directories(&root).unwrap();

        assert_eq!(directories, BTreeSet::from([root, nested]));
        assert!(!directories.contains(&outside));
    }

    #[test]
    fn structural_watch_events_force_reconciliation_and_refresh() {
        let temp = TestDirectory::new();
        let root = temp.path().join("root");
        fs::create_dir(&root).unwrap();

        let event = Event::new(EventKind::Create(CreateKind::Folder)).add_path(root.clone());
        let change = classify_watch_event(&root, &event).unwrap();
        assert!(change.force_full_hash);
        assert!(change.refresh_watches);
        assert!(change.reattach_root);

        let path = root.join("moved");
        let event =
            Event::new(EventKind::Modify(ModifyKind::Name(RenameMode::From))).add_path(path);
        let change = classify_watch_event(&root, &event).unwrap();
        assert!(change.force_full_hash);
        assert!(change.refresh_watches);

        #[cfg(unix)]
        {
            use std::os::unix::fs::symlink;

            let outside = temp.path().join("outside");
            fs::write(&outside, "outside").unwrap();
            let path = root.join("note.md");
            symlink(outside, &path).unwrap();
            let event = Event::new(EventKind::Modify(ModifyKind::Any)).add_path(path);
            let change = classify_watch_event(&root, &event).unwrap();
            assert!(change.force_full_hash);
            assert!(change.refresh_watches);
        }
    }

    #[test]
    fn startup_hashes_files_even_when_metadata_hints_match() {
        let temp = TestDirectory::new();
        let source_root = temp.path().join("source");
        fs::create_dir(&source_root).unwrap();
        let source_path = source_root.join("note.md");
        fs::write(&source_path, "new!").unwrap();
        let source_root = fs::canonicalize(source_root).unwrap();
        let metadata = fs::metadata(&source_path).unwrap();
        let source = NotesSourceDocument {
            document_id: "note.md".to_string(),
            size: metadata.len(),
            modified_at_ms: metadata
                .modified()
                .ok()
                .and_then(super::super::system_time_ms),
        };
        let prepared = prepare_notes_document("note.md", b"old!").unwrap();
        let mut embedding = vec![0.0; 512];
        embedding[0] = 1.0;
        let index_root = temp.path().join("indexes");
        let mut writer = NotesIndexWriter::open(&index_root, COLLECTION_ID.to_string()).unwrap();
        writer
            .commit_document(&prepared, &[embedding], &source)
            .unwrap();
        writer.publish(true).unwrap();

        let inspection = inspect_startup_freshness(
            &index_root,
            &RegisteredCollection {
                id: COLLECTION_ID.to_string(),
                source_root,
            },
        )
        .unwrap();

        assert!(inspection.changed);
        assert_eq!(
            inspection.forced_document_ids,
            BTreeSet::from(["note.md".to_string()])
        );
        assert!(inspection.opened_index.is_some());
    }
}
