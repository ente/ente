use std::collections::{BTreeSet, HashMap};
#[cfg(unix)]
use std::fs::TryLockError;
use std::fs::{self, File, OpenOptions};
#[cfg(unix)]
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
#[cfg(windows)]
use std::os::windows::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex, PoisonError};
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use ente_ensu::model;
use ente_ensu::notes::{
    NoteSourceReference, NotesCollectionIndex, NotesError, NotesIndexOutcome, NotesIndexProgress,
    cleanup_unreferenced_notes_shards, notes_content_revision, remove_notes_collection,
};
use notify::RecommendedWatcher;
use serde::Serialize;
use tauri::async_runtime;
use tauri::{AppHandle, Manager, State as TauriState};
use tauri_plugin_fs::FsExt;
use tauri_plugin_opener::OpenerExt;
use uuid::Uuid;
#[cfg(windows)]
use windows_sys::Win32::Foundation::ERROR_SHARING_VIOLATION;

use crate::commands::common::ApiError;
use crate::commands::llm::ModelDownloadState;

mod indexing;
mod registry;
mod source;
mod watcher;

use indexing::{index_collection, should_rebuild_derived_index};
use registry::{RegisteredCollection, RegistryStore};
use source::{
    canonical_source_root, cleanup_unregistered_indexes, compact_source_location,
    is_supported_file, read_collection_source, source_root_is_available, validate_new_source_root,
};
pub use watcher::initialize_for_app;
use watcher::{emit_state_changed, ensure_collection_watcher, install_collection_watcher};
pub(crate) use watcher::{mark_collection_dirty, mark_reference_stale};

const NOTES_DIRECTORY: &str = "notes";
const NOTES_INDEX_DIRECTORY: &str = "indexes";
const NOTES_OWNERSHIP_LOCK_FILE: &str = ".owner.lock";
const NOTES_QUIET_PERIOD_MS: i64 = 5 * 60 * 1_000;
const NOTES_STATE_CHANGED_EVENT: &str = "notes-state-changed";
const NOTES_MAX_SCAN_ENTRIES: usize = 250_000;
const NOTES_MAX_WATCH_DIRECTORIES: usize = 20_000;
const NOTES_INDEX_CACHE_MAX_BYTES: usize = 256 * 1024 * 1024;

#[cfg(test)]
struct TestDirectory(PathBuf);

#[cfg(test)]
impl TestDirectory {
    fn new() -> Self {
        let path = std::env::temp_dir().join(format!("ensu-notes-{}", Uuid::new_v4()));
        fs::create_dir(&path).unwrap();
        Self(path)
    }

    fn path(&self) -> &Path {
        &self.0
    }
}

#[cfg(test)]
impl Drop for TestDirectory {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum NotesCollectionStatusDto {
    Indexing,
    Updating,
    Ready,
    Pending,
    Unavailable,
    Error,
}

#[derive(Debug, Clone)]
struct CollectionRuntime {
    status: NotesCollectionStatusDto,
    index_available: bool,
    indexing_progress: Option<u8>,
    indexed_document_count: u64,
    last_updated_at_ms: Option<i64>,
    last_error: Option<String>,
    watcher_error: Option<String>,
}

impl CollectionRuntime {
    fn pending() -> Self {
        Self {
            status: NotesCollectionStatusDto::Pending,
            index_available: false,
            indexing_progress: None,
            indexed_document_count: 0,
            last_updated_at_ms: None,
            last_error: None,
            watcher_error: None,
        }
    }

    fn unavailable() -> Self {
        Self {
            status: NotesCollectionStatusDto::Unavailable,
            last_error: Some("Source folder is unavailable".to_string()),
            ..Self::pending()
        }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NotesCollectionDto {
    id: String,
    label: String,
    status: NotesCollectionStatusDto,
    indexing_progress: Option<u8>,
    indexed_document_count: u64,
    last_updated_at_ms: Option<i64>,
    update_due_at_ms: Option<i64>,
    last_error: Option<String>,
    watcher_error: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NotesIndexResultDto {
    collection: NotesCollectionDto,
    needs_rerun: bool,
}

struct CollectionWatcher {
    watcher: RecommendedWatcher,
    watched_directories: BTreeSet<PathBuf>,
}

struct CachedIndex {
    index: NotesCollectionIndex,
    bytes: usize,
    last_used: u64,
}

struct IndexCache {
    entries: HashMap<String, CachedIndex>,
    max_bytes: usize,
    total_bytes: usize,
    clock: u64,
}

impl IndexCache {
    fn new(max_bytes: usize) -> Self {
        Self {
            entries: HashMap::new(),
            max_bytes,
            total_bytes: 0,
            clock: 0,
        }
    }

    fn search(
        &mut self,
        collection_id: &str,
        query: &[f32],
    ) -> Option<Result<Vec<ente_ensu::notes::NotesSearchHit>, NotesError>> {
        self.clock = self.clock.wrapping_add(1);
        let entry = self.entries.get_mut(collection_id)?;
        entry.last_used = self.clock;
        Some(entry.index.search(query))
    }

    fn insert(&mut self, collection_id: String, index: NotesCollectionIndex) {
        self.remove(&collection_id);
        let bytes = index.estimated_heap_bytes();
        if bytes > self.max_bytes {
            return;
        }
        while self.total_bytes.saturating_add(bytes) > self.max_bytes {
            let Some(oldest) = self
                .entries
                .iter()
                .min_by_key(|(_, entry)| entry.last_used)
                .map(|(collection_id, _)| collection_id.clone())
            else {
                break;
            };
            self.remove(&oldest);
        }
        self.clock = self.clock.wrapping_add(1);
        self.total_bytes = self.total_bytes.saturating_add(bytes);
        self.entries.insert(
            collection_id,
            CachedIndex {
                index,
                bytes,
                last_used: self.clock,
            },
        );
    }

    fn remove(&mut self, collection_id: &str) {
        if let Some(entry) = self.entries.remove(collection_id) {
            self.total_bytes = self.total_bytes.saturating_sub(entry.bytes);
        }
    }

    fn clear(&mut self) {
        self.entries.clear();
        self.total_bytes = 0;
    }
}

#[derive(Default)]
struct DesktopUpdateState {
    forced_document_ids: BTreeSet<String>,
    force_full_hash: bool,
    rebuild_derived_index: bool,
    quiet_deadline_ms: i64,
    generation: u64,
    bypass_quiet_period: bool,
}

impl DesktopUpdateState {
    fn record_change(
        &mut self,
        now_ms: i64,
        forced_document_ids: impl IntoIterator<Item = String>,
        force_full_hash: bool,
    ) {
        self.forced_document_ids.extend(forced_document_ids);
        self.force_full_hash |= force_full_hash;
        self.quiet_deadline_ms = if self.rebuild_derived_index {
            now_ms
        } else {
            now_ms.saturating_add(NOTES_QUIET_PERIOD_MS)
        };
        self.generation = self.generation.wrapping_add(1);
        self.bypass_quiet_period = false;
    }

    fn record_stale_reference(&mut self, now_ms: i64, document_id: String) -> bool {
        let deadline_changed = self.quiet_deadline_ms > now_ms;
        let document_changed =
            !self.force_full_hash && self.forced_document_ids.insert(document_id);
        if !deadline_changed && !document_changed {
            return false;
        }
        if document_changed {
            self.generation = self.generation.wrapping_add(1);
        }
        self.quiet_deadline_ms = now_ms;
        self.bypass_quiet_period = false;
        true
    }

    fn record_unreadable_index(&mut self, now_ms: i64) -> bool {
        if self.rebuild_derived_index {
            return false;
        }
        self.rebuild_derived_index = true;
        self.quiet_deadline_ms = now_ms;
        self.generation = self.generation.wrapping_add(1);
        self.bypass_quiet_period = false;
        true
    }
}

#[derive(Default)]
struct UpdateSnapshot {
    generation: u64,
    forced_document_ids: Vec<String>,
    force_full_hash: bool,
    rebuild_derived_index: bool,
}

pub struct State {
    registry: Arc<Mutex<RegistryStore>>,
    runtimes: Arc<Mutex<HashMap<String, CollectionRuntime>>>,
    cached_indexes: Arc<Mutex<IndexCache>>,
    index_root: PathBuf,
    collection_lifecycles: Mutex<HashMap<String, Arc<async_runtime::Mutex<()>>>>,
    watchers: Mutex<HashMap<String, CollectionWatcher>>,
    watch_work: Mutex<HashMap<String, watcher::WatchWork>>,
    updates: Mutex<HashMap<String, DesktopUpdateState>>,
    _ownership_lock: File,
}

#[derive(Clone)]
pub(crate) struct RetrievalHandle {
    registry: Arc<Mutex<RegistryStore>>,
    cached_indexes: Arc<Mutex<IndexCache>>,
    index_root: PathBuf,
}

impl State {
    pub fn new(app_data_dir: PathBuf) -> Result<Self, ApiError> {
        let notes_directory = app_data_dir.join(NOTES_DIRECTORY);
        ensure_directory(&notes_directory)?;
        let ownership_lock = acquire_notes_ownership(&notes_directory)?;
        let index_root = notes_directory.join(NOTES_INDEX_DIRECTORY);
        ensure_directory(&index_root)?;
        let registry = RegistryStore::open(notes_directory)?;
        if registry.incompatible_error.is_none() {
            cleanup_unregistered_indexes(&index_root, &registry.registry.collections);
        }
        let mut runtimes = HashMap::new();
        for collection in &registry.registry.collections {
            let runtime = if !collection.source_root.is_dir() {
                CollectionRuntime::unavailable()
            } else {
                match NotesCollectionIndex::inspect(&index_root, collection.id.clone()) {
                    Ok(summary) => {
                        let count = summary.document_count;
                        if count == 0 {
                            CollectionRuntime {
                                status: NotesCollectionStatusDto::Error,
                                last_error: Some(
                                    "No supported non-empty UTF-8 notes were found".to_string(),
                                ),
                                ..CollectionRuntime::pending()
                            }
                        } else {
                            CollectionRuntime {
                                status: NotesCollectionStatusDto::Ready,
                                index_available: true,
                                indexed_document_count: count as u64,
                                last_updated_at_ms: summary.last_updated_at_ms,
                                ..CollectionRuntime::pending()
                            }
                        }
                    }
                    Err(
                        NotesError::NotReady | NotesError::IncompatibleIndex | NotesError::Io(_),
                    ) => CollectionRuntime::pending(),
                    Err(_) => CollectionRuntime {
                        status: NotesCollectionStatusDto::Error,
                        last_error: Some("The local index needs to be rebuilt".to_string()),
                        ..CollectionRuntime::pending()
                    },
                }
            };
            runtimes.insert(collection.id.clone(), runtime);
        }
        Ok(Self {
            registry: Arc::new(Mutex::new(registry)),
            runtimes: Arc::new(Mutex::new(runtimes)),
            cached_indexes: Arc::new(Mutex::new(IndexCache::new(NOTES_INDEX_CACHE_MAX_BYTES))),
            index_root,
            collection_lifecycles: Mutex::new(HashMap::new()),
            watchers: Mutex::new(HashMap::new()),
            watch_work: Mutex::new(HashMap::new()),
            updates: Mutex::new(HashMap::new()),
            _ownership_lock: ownership_lock,
        })
    }

    fn collection_lifecycle(&self, collection_id: &str) -> Arc<async_runtime::Mutex<()>> {
        Arc::clone(
            self.collection_lifecycles
                .lock()
                .unwrap_or_else(PoisonError::into_inner)
                .entry(collection_id.to_string())
                .or_default(),
        )
    }

    fn registered_collection(&self, collection_id: &str) -> Result<RegisteredCollection, ApiError> {
        let store = self.registry.lock().unwrap_or_else(PoisonError::into_inner);
        store.ensure_compatible()?;
        store
            .registry
            .collections
            .iter()
            .find(|collection| collection.id == collection_id)
            .cloned()
            .ok_or_else(|| ApiError::new("not_found", "Notes collection was not found"))
    }

    fn collection_dto(&self, collection_id: &str) -> Result<NotesCollectionDto, ApiError> {
        let collection = self.registered_collection(collection_id)?;
        let runtime = self
            .runtimes
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .get(collection_id)
            .cloned()
            .unwrap_or_else(CollectionRuntime::pending);
        let update_due_at_ms = self
            .updates
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .get(collection_id)
            .map(|update| update.quiet_deadline_ms);
        Ok(collection_dto(&collection, &runtime, update_due_at_ms))
    }

    fn set_runtime(&self, collection_id: &str, runtime: CollectionRuntime) {
        self.runtimes
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .insert(collection_id.to_string(), runtime);
    }

    fn runtime(&self, collection_id: &str) -> CollectionRuntime {
        self.runtimes
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .get(collection_id)
            .cloned()
            .unwrap_or_else(CollectionRuntime::pending)
    }

    fn set_watcher_error(&self, collection_id: &str, error: Option<&ApiError>) -> bool {
        let mut runtimes = self.runtimes.lock().unwrap_or_else(PoisonError::into_inner);
        let Some(runtime) = runtimes.get_mut(collection_id) else {
            return false;
        };
        let watcher_error = error.map(|_| {
            "Changes cannot be watched automatically. Refresh this folder manually.".to_string()
        });
        if runtime.watcher_error == watcher_error {
            return false;
        }
        runtime.watcher_error = watcher_error;
        true
    }

    fn prepare_update(
        &self,
        collection_id: &str,
        force: bool,
        wait_for_quiet_period: bool,
    ) -> Result<UpdateSnapshot, ApiError> {
        let mut updates = self.updates.lock().unwrap_or_else(PoisonError::into_inner);
        let Some(update) = updates.get_mut(collection_id) else {
            return Ok(UpdateSnapshot {
                force_full_hash: force,
                ..UpdateSnapshot::default()
            });
        };
        if force {
            update.bypass_quiet_period = true;
        }
        if !force
            && wait_for_quiet_period
            && !update.bypass_quiet_period
            && update.quiet_deadline_ms > now_ms()
        {
            return Err(ApiError::new(
                "not_due",
                "Notes update is waiting for the quiet period",
            ));
        }
        Ok(UpdateSnapshot {
            generation: update.generation,
            forced_document_ids: update.forced_document_ids.iter().cloned().collect(),
            force_full_hash: force || update.force_full_hash,
            rebuild_derived_index: update.rebuild_derived_index,
        })
    }

    fn cancel_update(&self, collection_id: &str) {
        self.updates
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .remove(collection_id);
    }

    fn evict_cached_index(&self, collection_id: &str) {
        self.cached_indexes
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .remove(collection_id);
    }

    fn has_available_index(&self, collection_id: &str) -> bool {
        self.runtimes
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .get(collection_id)
            .is_some_and(|runtime| runtime.index_available)
    }

    fn has_newer_update(&self, collection_id: &str, generation: u64) -> bool {
        self.updates
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .get(collection_id)
            .is_some_and(|update| update.generation != generation)
    }

    fn retain_unchecked_hints(
        &self,
        collection_id: &str,
        generation: u64,
        unchecked_document_ids: &[String],
    ) {
        let mut updates = self.updates.lock().unwrap_or_else(PoisonError::into_inner);
        let Some(update) = updates.get_mut(collection_id) else {
            return;
        };
        if update.generation != generation {
            return;
        }
        update.forced_document_ids = unchecked_document_ids.iter().cloned().collect();
        update.force_full_hash = false;
    }

    fn apply_index_outcome(
        &self,
        collection_id: &str,
        update_generation: u64,
        outcome: &NotesIndexOutcome,
        had_index: bool,
        completed_index_updated_at_ms: Option<i64>,
    ) -> (bool, bool) {
        let mut updates = self.updates.lock().unwrap_or_else(PoisonError::into_inner);
        let generation_unchanged = updates
            .get(collection_id)
            .is_none_or(|update| update.generation == update_generation);
        let reconciliation_complete = outcome.changed_during_indexing.is_none();
        let ready = outcome.ready();
        let update_completed = reconciliation_complete && generation_unchanged;
        if update_completed {
            updates.remove(collection_id);
        }
        let needs_rerun = !had_index && !generation_unchanged;
        let mut runtime = self.runtime(collection_id);
        if update_completed {
            runtime.index_available = ready;
            runtime.last_updated_at_ms = ready.then_some(completed_index_updated_at_ms).flatten();
        }
        runtime.indexing_progress = needs_rerun.then_some(runtime.indexing_progress).flatten();
        runtime.indexed_document_count = outcome.indexed_document_count;
        runtime.status = if update_completed && ready {
            NotesCollectionStatusDto::Ready
        } else if update_completed {
            NotesCollectionStatusDto::Error
        } else if needs_rerun {
            if had_index {
                NotesCollectionStatusDto::Updating
            } else {
                NotesCollectionStatusDto::Indexing
            }
        } else {
            NotesCollectionStatusDto::Pending
        };
        runtime.last_error = (update_completed && !ready)
            .then(|| "No supported non-empty UTF-8 notes were found".to_string());
        self.set_runtime(collection_id, runtime);
        (needs_rerun, update_completed)
    }

    fn report_indexing_progress(
        app: &AppHandle,
        collection_id: &str,
        progress: NotesIndexProgress,
    ) {
        let state = app.state::<State>();
        let mut runtime = state.runtime(collection_id);
        let previous_progress = runtime.indexing_progress;
        if !matches!(
            runtime.status,
            NotesCollectionStatusDto::Indexing | NotesCollectionStatusDto::Updating
        ) || previous_progress == Some(progress.percentage)
        {
            return;
        }
        runtime.indexing_progress = Some(progress.percentage);
        runtime.indexed_document_count = progress.indexed_document_count;
        state.set_runtime(collection_id, runtime);
        if progress.percentage == 100
            || previous_progress.is_none_or(|previous| previous / 10 != progress.percentage / 10)
        {
            crate::logging::log(
                "Notes",
                format!(
                    "index progress collection={collection_id} percent={} processed={} indexed={} total={}",
                    progress.percentage,
                    progress.processed_document_count,
                    progress.indexed_document_count,
                    progress.total_document_count
                ),
            );
        }
        emit_state_changed(app, collection_id);
    }

    pub(crate) fn available_index_collection_ids(&self) -> Vec<String> {
        let available_ids = self
            .runtimes
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .iter()
            .filter_map(|(collection_id, runtime)| {
                (runtime.index_available
                    && !matches!(
                        runtime.status,
                        NotesCollectionStatusDto::Unavailable | NotesCollectionStatusDto::Error
                    ))
                .then_some(collection_id.clone())
            })
            .collect::<BTreeSet<_>>();
        let collections = self
            .registry
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .registry
            .collections
            .clone();
        collections
            .into_iter()
            .filter(|collection| available_ids.contains(&collection.id))
            .map(|collection| collection.id)
            .collect()
    }

    pub(crate) fn retrieval_handle(&self) -> RetrievalHandle {
        RetrievalHandle {
            registry: Arc::clone(&self.registry),
            cached_indexes: Arc::clone(&self.cached_indexes),
            index_root: self.index_root.clone(),
        }
    }
}

pub(crate) fn mark_index_unreadable(app: &AppHandle, collection_id: &str) {
    let state = app.state::<State>();
    if state.registered_collection(collection_id).is_err() {
        return;
    }
    state.evict_cached_index(collection_id);
    {
        let mut updates = state.updates.lock().unwrap_or_else(PoisonError::into_inner);
        updates
            .entry(collection_id.to_string())
            .or_default()
            .record_unreadable_index(now_ms());
    }
    {
        let mut runtimes = state
            .runtimes
            .lock()
            .unwrap_or_else(PoisonError::into_inner);
        let Some(runtime) = runtimes.get_mut(collection_id) else {
            return;
        };
        runtime.status = NotesCollectionStatusDto::Pending;
        runtime.index_available = false;
        runtime.indexing_progress = None;
        runtime.last_error = None;
    }
    emit_state_changed(app, collection_id);
}

impl RetrievalHandle {
    pub(crate) fn collection_label(&self, collection_id: &str) -> Option<String> {
        self.registry
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .registry
            .collections
            .iter()
            .find(|collection| collection.id == collection_id)
            .map(|collection| compact_source_location(&collection.source_root))
    }

    pub(crate) fn search_collection(
        &self,
        collection_id: &str,
        query: &[f32],
    ) -> Result<Vec<ente_ensu::notes::NotesSearchHit>, NotesError> {
        if let Some(result) = self
            .cached_indexes
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .search(collection_id, query)
        {
            return result;
        }
        let index = NotesCollectionIndex::open(&self.index_root, collection_id.to_string())?;
        let hits = index.search(query)?;
        self.cached_indexes
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .insert(collection_id.to_string(), index);
        Ok(hits)
    }

    pub(crate) fn verify_source_reference(&self, reference: &NoteSourceReference) -> bool {
        let collection = self
            .registry
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .registry
            .collections
            .iter()
            .find(|collection| collection.id == reference.collection_id)
            .cloned();
        let Some(collection) = collection else {
            return false;
        };
        read_collection_source(&collection.source_root, &reference.document_id)
            .map(|(_, bytes, _)| bytes)
            .map(|bytes| notes_content_revision(&bytes) == reference.indexed_revision)
            .unwrap_or(false)
    }
}

fn collection_dto(
    collection: &RegisteredCollection,
    runtime: &CollectionRuntime,
    update_due_at_ms: Option<i64>,
) -> NotesCollectionDto {
    NotesCollectionDto {
        id: collection.id.clone(),
        label: compact_source_location(&collection.source_root),
        status: runtime.status,
        indexing_progress: runtime.indexing_progress,
        indexed_document_count: runtime.indexed_document_count,
        last_updated_at_ms: runtime.last_updated_at_ms,
        update_due_at_ms,
        last_error: runtime.last_error.clone(),
        watcher_error: runtime.watcher_error.clone(),
    }
}

#[tauri::command]
pub fn notes_list_collections(app: AppHandle) -> Result<Vec<NotesCollectionDto>, ApiError> {
    let notes_state = available_state(&app)?;
    let store = notes_state
        .registry
        .lock()
        .unwrap_or_else(PoisonError::into_inner);
    store.ensure_compatible()?;
    let collections = store.registry.collections.clone();
    drop(store);
    let runtimes = notes_state
        .runtimes
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .clone();
    let updates = notes_state
        .updates
        .lock()
        .unwrap_or_else(PoisonError::into_inner);
    Ok(collections
        .iter()
        .map(|collection| {
            collection_dto(
                collection,
                &runtimes
                    .get(&collection.id)
                    .cloned()
                    .unwrap_or_else(CollectionRuntime::pending),
                updates
                    .get(&collection.id)
                    .map(|update| update.quiet_deadline_ms),
            )
        })
        .collect())
}

#[tauri::command]
pub async fn notes_add_collection(
    app: AppHandle,
    source_root: String,
) -> Result<NotesCollectionDto, ApiError> {
    async_runtime::spawn_blocking(move || {
        let root = canonical_source_root(Path::new(&source_root))?;
        if !app.fs_scope().is_allowed(&root) {
            return Err(ApiError::new(
                "io_scope",
                "Notes folder is outside the allowed filesystem scope",
            ));
        }
        let notes_state = available_state(&app)?;
        register_collection(&app, &notes_state, root)
    })
    .await
    .map_err(|_| ApiError::new("io_thread", "Notes folder registration task failed"))?
}

fn register_collection(
    app: &AppHandle,
    notes_state: &State,
    root: PathBuf,
) -> Result<NotesCollectionDto, ApiError> {
    let notes_directory = notes_state
        .index_root
        .parent()
        .ok_or_else(|| ApiError::new("notes_storage", "Notes storage path is invalid"))?;
    let notes_directory = fs::canonicalize(notes_directory)
        .map_err(|_| ApiError::new("notes_storage", "Notes storage path is unavailable"))?;
    if root.starts_with(&notes_directory) || notes_directory.starts_with(&root) {
        return Err(ApiError::new(
            "invalid_folder",
            "Choose a folder outside Ensu's private Notes storage",
        ));
    }
    let collection = RegisteredCollection {
        id: Uuid::new_v4().hyphenated().to_string(),
        source_root: root,
    };
    {
        let mut store = notes_state
            .registry
            .lock()
            .unwrap_or_else(PoisonError::into_inner);
        validate_new_source_root(&store.registry.collections, &collection.source_root)?;
        let mut registry = store.registry.clone();
        registry.collections.push(collection.clone());
        store.replace(registry)?;
    }
    notes_state.set_runtime(&collection.id, CollectionRuntime::pending());
    if let Err(error) = install_collection_watcher(app, &collection) {
        notes_state.set_watcher_error(&collection.id, Some(&error));
        crate::logging::log(
            "Notes",
            format!(
                "watcher unavailable collection={} error={}",
                collection.id, error.message
            ),
        );
    }
    let dto = notes_state.collection_dto(&collection.id)?;
    crate::logging::log(
        "Notes",
        format!("collection registered collection={}", collection.id),
    );
    Ok(dto)
}

#[tauri::command]
pub async fn notes_remove_collection(
    app: AppHandle,
    collection_id: String,
) -> Result<(), ApiError> {
    let notes_state = available_state(&app)?;
    let lifecycle = notes_state.collection_lifecycle(&collection_id);
    let _lifecycle = lifecycle.lock().await;
    async_runtime::spawn_blocking(move || {
        let notes_state = available_state(&app)?;
        remove_collection(&notes_state, &collection_id)
    })
    .await
    .map_err(|_| ApiError::new("io_thread", "Notes folder removal task failed"))?
}

fn remove_collection(notes_state: &State, collection_id: &str) -> Result<(), ApiError> {
    let collection = notes_state.registered_collection(collection_id)?;
    {
        let mut store = notes_state
            .registry
            .lock()
            .unwrap_or_else(PoisonError::into_inner);
        let mut registry = store.registry.clone();
        registry
            .collections
            .retain(|candidate| candidate.id != collection_id);
        store.replace(registry)?;
    }
    notes_state
        .watchers
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .remove(collection_id);
    notes_state
        .watch_work
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .remove(collection_id);
    notes_state.cancel_update(collection_id);
    notes_state.evict_cached_index(collection_id);
    notes_state
        .runtimes
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .remove(collection_id);
    if let Err(error) = remove_notes_collection(&notes_state.index_root, &collection.id) {
        crate::logging::log(
            "Notes",
            format!(
                "removed collection but could not clean derived index collection={} error={}",
                collection_id, error
            ),
        );
    }
    notes_state
        .collection_lifecycles
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .remove(collection_id);
    crate::logging::log(
        "Notes",
        format!("collection removed collection={collection_id}"),
    );
    Ok(())
}

fn report_index_error(
    app: &AppHandle,
    state: &State,
    collection_id: &str,
    update_generation: Option<u64>,
    error: &ApiError,
) {
    let cancelled = error.name == Some("cancelled");
    let unavailable = matches!(
        error.name,
        Some("unavailable" | "source_unavailable" | "source_changed")
    );
    let superseded_file_error = error.name == Some("source_unavailable")
        && update_generation.is_some_and(|generation| {
            state.has_newer_update(collection_id, generation)
                && state
                    .registered_collection(collection_id)
                    .is_ok_and(|collection| source_root_is_available(&collection.source_root))
        });
    let mut runtime = state.runtime(collection_id);
    if !cancelled {
        runtime.indexing_progress = None;
    }
    runtime.status = if cancelled || superseded_file_error {
        NotesCollectionStatusDto::Pending
    } else if unavailable {
        NotesCollectionStatusDto::Unavailable
    } else {
        NotesCollectionStatusDto::Error
    };
    runtime.last_error = (!cancelled && !superseded_file_error).then(|| error.message.clone());
    state.set_runtime(collection_id, runtime);
    crate::logging::log(
        "Notes",
        format!(
            "index stopped collection={collection_id} reason={}",
            error.name.unwrap_or("unknown")
        ),
    );
    emit_state_changed(app, collection_id);
}

#[tauri::command]
pub async fn notes_index_collection(
    app: AppHandle,
    model_state: TauriState<'_, ModelDownloadState>,
    llm_state: TauriState<'_, crate::commands::llm::State>,
    collection_id: String,
    force: bool,
    retrieval_epoch: u64,
) -> Result<NotesIndexResultDto, ApiError> {
    let request_started_at = Instant::now();
    crate::logging::log(
        "Notes",
        format!("index requested collection={collection_id} force={force}"),
    );
    let notes_state = available_state(&app)?;
    let lifecycle = notes_state.collection_lifecycle(&collection_id);
    let _collection_lifecycle = lifecycle.lock().await;
    let collection = notes_state.registered_collection(&collection_id)?;
    let watcher_app = app.clone();
    let watcher_collection = collection.clone();
    let watcher_result = async_runtime::spawn_blocking(move || {
        ensure_collection_watcher(&watcher_app, &watcher_collection)
    })
    .await
    .unwrap_or_else(|_| Err(ApiError::new("watcher_thread", "Notes watcher task failed")));
    match watcher_result {
        Ok(()) => {
            notes_state.set_watcher_error(&collection_id, None);
        }
        Err(error) => {
            notes_state.set_watcher_error(&collection_id, Some(&error));
            crate::logging::log(
                "Notes",
                format!(
                    "watcher unavailable collection={collection_id} error={}",
                    error.message
                ),
            );
        }
    }
    let had_index = notes_state.has_available_index(&collection_id);
    let rebuild_derived_index =
        should_rebuild_derived_index(&notes_state.index_root, &collection_id, force, had_index)?;
    let mut update = notes_state.prepare_update(&collection_id, force, had_index)?;
    update.rebuild_derived_index |= rebuild_derived_index;
    let cancellation_epoch = llm_state.retrieval_epoch();
    if let Err(error) = check_cancelled(&cancellation_epoch, retrieval_epoch) {
        crate::logging::log(
            "Notes",
            format!("index cancelled before start collection={collection_id}"),
        );
        return Err(error);
    }
    let _model_lifecycle = llm_state.lifecycle().lock().await;
    if let Err(error) = check_cancelled(&cancellation_epoch, retrieval_epoch) {
        crate::logging::log(
            "Notes",
            format!("index cancelled while waiting collection={collection_id}"),
        );
        return Err(error);
    }
    crate::commands::llm::replace_state(&llm_state, None, None)?;

    let mut runtime = notes_state.runtime(&collection_id);
    if !matches!(
        runtime.status,
        NotesCollectionStatusDto::Indexing | NotesCollectionStatusDto::Updating
    ) && runtime.indexing_progress.is_none()
    {
        runtime.indexing_progress = Some(0);
    }
    runtime.status = if had_index {
        NotesCollectionStatusDto::Updating
    } else {
        NotesCollectionStatusDto::Indexing
    };
    runtime.last_error = None;
    notes_state.set_runtime(&collection_id, runtime);
    crate::logging::log(
        "Notes",
        format!(
            "index started collection={collection_id} updating={had_index} rebuild={rebuild_derived_index}"
        ),
    );
    emit_state_changed(&app, &collection_id);
    let store = model_state.store();
    let embedding_asset = model::knowledge_embedding_model_asset();
    let embedding_path = model::llm_model_path(&store, &embedding_asset);
    let index_root = notes_state.index_root.clone();
    let update_generation = update.generation;
    let progress_app = app.clone();
    let progress_collection_id = collection_id.clone();
    let result = async_runtime::spawn_blocking(move || {
        index_collection(
            &index_root,
            &collection,
            embedding_path.as_deref(),
            &cancellation_epoch,
            retrieval_epoch,
            &update,
            |progress| {
                State::report_indexing_progress(&progress_app, &progress_collection_id, progress);
            },
        )
    })
    .await
    .map_err(|_| ApiError::new("index_thread", "Notes indexing task failed"))
    .and_then(|result| result);
    let outcome = match result {
        Ok(outcome) => outcome,
        Err(error) => {
            report_index_error(
                &app,
                &notes_state,
                &collection_id,
                Some(update_generation),
                &error,
            );
            return Err(error);
        }
    };

    let opened_index = if outcome.ready() {
        notes_state.evict_cached_index(&collection_id);
        match NotesCollectionIndex::open(&notes_state.index_root, collection_id.clone()) {
            Ok(index) => {
                let _ = cleanup_unreferenced_notes_shards(&notes_state.index_root, &collection_id);
                Some(index)
            }
            Err(error) => {
                let error = notes_error(error);
                report_index_error(
                    &app,
                    &notes_state,
                    &collection_id,
                    Some(update_generation),
                    &error,
                );
                return Err(error);
            }
        }
    } else {
        None
    };

    notes_state.retain_unchecked_hints(
        &collection_id,
        update_generation,
        &outcome.unchecked_document_ids,
    );
    if let Some(document_id) = outcome.changed_during_indexing.clone() {
        mark_collection_dirty(&app, &collection_id, [document_id], false);
    }
    let completed_index_updated_at_ms = opened_index
        .as_ref()
        .and_then(NotesCollectionIndex::last_updated_at_ms);
    let (needs_rerun, update_completed) = notes_state.apply_index_outcome(
        &collection_id,
        update_generation,
        &outcome,
        had_index,
        completed_index_updated_at_ms,
    );
    if update_completed {
        if let Some(index) = opened_index {
            notes_state
                .cached_indexes
                .lock()
                .unwrap_or_else(PoisonError::into_inner)
                .insert(collection_id.clone(), index);
        } else {
            notes_state.evict_cached_index(&collection_id);
            let _ = cleanup_unreferenced_notes_shards(&notes_state.index_root, &collection_id);
        }
    }
    emit_state_changed(&app, &collection_id);
    let dto = notes_state.collection_dto(&collection_id)?;
    crate::logging::log(
        "Notes",
        format!(
            "index completed collection={collection_id} indexed={} needs_rerun={needs_rerun} elapsed_ms={}",
            outcome.indexed_document_count,
            request_started_at.elapsed().as_millis()
        ),
    );
    Ok(NotesIndexResultDto {
        collection: dto,
        needs_rerun,
    })
}

#[tauri::command]
pub async fn notes_open_document(
    app: AppHandle,
    collection_id: String,
    document_id: String,
    indexed_revision: String,
) -> Result<(), ApiError> {
    let verification_app = app.clone();
    let path = async_runtime::spawn_blocking(move || {
        let notes_state = available_state(&verification_app)?;
        let collection = notes_state.registered_collection(&collection_id)?;
        let (path, bytes, _) = read_collection_source(&collection.source_root, &document_id)?;
        if !is_supported_file(&path) {
            return Err(ApiError::new(
                "invalid_document",
                "Unsupported note document",
            ));
        }
        if notes_content_revision(&bytes) != indexed_revision {
            return Err(ApiError::new(
                "source_changed",
                "Source note changed after this answer was generated",
            ));
        }
        Ok(path)
    })
    .await
    .map_err(|_| ApiError::new("io_thread", "Source note verification task failed"))??;
    app.opener()
        .open_path(path.to_string_lossy().into_owned(), None::<String>)
        .map_err(|_| ApiError::new("open_failed", "Source note could not be opened"))
}

fn check_cancelled(
    cancellation_epoch: &std::sync::atomic::AtomicU64,
    retrieval_epoch: u64,
) -> Result<(), ApiError> {
    if cancellation_epoch.load(Ordering::Relaxed) == retrieval_epoch {
        Ok(())
    } else {
        Err(ApiError::new("cancelled", "Notes indexing cancelled"))
    }
}

fn notes_error(error: NotesError) -> ApiError {
    let (code, message) = match error {
        NotesError::InvalidInput(_) => ("invalid_input", "Notes input is invalid"),
        NotesError::InvalidIndex(_) => ("invalid_index", "The Notes index is invalid"),
        NotesError::IncompatibleIndex => {
            ("incompatible_index", "The Notes index needs to be rebuilt")
        }
        NotesError::NotReady => ("not_ready", "The Notes collection is not ready"),
        NotesError::CollectionTooLarge(message) => {
            return ApiError::new("collection_too_large", message);
        }
        NotesError::Io(_) => ("io", "The Notes index could not be accessed"),
        NotesError::Json(_) => ("json", "The Notes index could not be read"),
    };
    ApiError::new(code, message)
}

fn available_state(app: &AppHandle) -> Result<TauriState<'_, State>, ApiError> {
    app.try_state::<State>().ok_or_else(|| {
        ApiError::new(
            "notes_unavailable",
            "Notes are unavailable because local storage could not be initialized",
        )
    })
}

fn acquire_notes_ownership(notes_directory: &Path) -> Result<File, ApiError> {
    let mut options = OpenOptions::new();
    options.read(true).write(true).create(true);
    #[cfg(unix)]
    options.mode(0o600);
    #[cfg(windows)]
    options.share_mode(0);

    let file = options
        .open(notes_directory.join(NOTES_OWNERSHIP_LOCK_FILE))
        .map_err(notes_ownership_open_error)?;

    #[cfg(unix)]
    file.try_lock().map_err(|error| match error {
        TryLockError::WouldBlock => notes_in_use_error(),
        TryLockError::Error(error) => io_error(error),
    })?;

    Ok(file)
}

fn notes_ownership_open_error(error: std::io::Error) -> ApiError {
    #[cfg(windows)]
    if error.raw_os_error() == Some(ERROR_SHARING_VIOLATION as i32) {
        return notes_in_use_error();
    }
    io_error(error)
}

fn notes_in_use_error() -> ApiError {
    ApiError::new(
        "notes_in_use",
        "Your Notes is already open in another Ensu instance",
    )
}

fn ensure_directory(path: &Path) -> Result<(), ApiError> {
    if !path_exists(path)? {
        fs::create_dir_all(path).map_err(io_error)?;
    }
    if !fs::symlink_metadata(path).map_err(io_error)?.is_dir() {
        return Err(ApiError::new(
            "invalid_path",
            "Notes storage path is invalid",
        ));
    }
    #[cfg(unix)]
    fs::set_permissions(path, fs::Permissions::from_mode(0o700)).map_err(io_error)?;
    Ok(())
}

fn path_exists(path: &Path) -> Result<bool, ApiError> {
    match fs::symlink_metadata(path) {
        Ok(_) => Ok(true),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(io_error(error)),
    }
}

fn remove_owned_entry(path: &Path) -> Result<(), ApiError> {
    let metadata = fs::symlink_metadata(path).map_err(io_error)?;
    if metadata.is_dir() {
        fs::remove_dir_all(path).map_err(io_error)
    } else {
        fs::remove_file(path).map_err(io_error)
    }
}

fn io_error(_: std::io::Error) -> ApiError {
    ApiError::new("io", "Notes storage operation failed")
}

fn source_scan_error(_: std::io::Error) -> ApiError {
    ApiError::new(
        "source_unavailable",
        "Notes source folder could not be read",
    )
}

fn now_ms() -> i64 {
    system_time_ms(SystemTime::now()).unwrap_or(0)
}

fn system_time_ms(time: SystemTime) -> Option<i64> {
    let millis = time.duration_since(UNIX_EPOCH).ok()?.as_millis();
    i64::try_from(millis).ok()
}

pub(crate) fn clear_for_exit(app: &AppHandle) {
    let Some(state) = app.try_state::<State>() else {
        return;
    };
    state
        .watchers
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .clear();
    state
        .watch_work
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .clear();
    state
        .updates
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .clear();
    state
        .cached_indexes
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .clear();
}

#[cfg(test)]
mod tests {
    use super::*;
    use ente_ensu::notes::{NotesIndexWriter, NotesSourceDocument, prepare_notes_document};

    const COLLECTION_ID: &str = "123e4567-e89b-12d3-a456-426614174000";
    const SECOND_COLLECTION_ID: &str = "123e4567-e89b-12d3-a456-426614174001";

    fn publish_test_index(index_root: &Path, collection_id: &str, document_id: &str) {
        let prepared = prepare_notes_document(document_id, b"test note").unwrap();
        let mut embedding = vec![0.0; 512];
        embedding[0] = 1.0;
        let metadata = NotesSourceDocument {
            document_id: document_id.to_string(),
            size: 9,
            modified_at_ms: Some(1),
        };
        let mut writer = NotesIndexWriter::open(index_root, collection_id.to_string()).unwrap();
        writer
            .commit_document(&prepared, &[embedding], &metadata)
            .unwrap();
        writer.publish(true).unwrap();
    }

    #[test]
    fn ownership_lock_excludes_another_owner_until_release() {
        let temp = TestDirectory::new();
        let first = acquire_notes_ownership(temp.path()).unwrap();

        let error = acquire_notes_ownership(temp.path()).unwrap_err();
        assert_eq!(error.name, Some("notes_in_use"));
        assert_eq!(
            error.message,
            "Your Notes is already open in another Ensu instance"
        );

        drop(first);
        acquire_notes_ownership(temp.path()).unwrap();
    }

    #[test]
    fn watcher_warning_does_not_replace_ready_index_state() {
        let temp = TestDirectory::new();
        let collection = RegisteredCollection {
            id: COLLECTION_ID.to_string(),
            source_root: temp.path().to_path_buf(),
        };
        let runtime = CollectionRuntime {
            status: NotesCollectionStatusDto::Ready,
            index_available: true,
            indexing_progress: None,
            indexed_document_count: 1,
            last_updated_at_ms: Some(1),
            last_error: None,
            watcher_error: Some("Watcher unavailable".to_string()),
        };

        let dto = collection_dto(&collection, &runtime, None);

        assert_eq!(dto.status, NotesCollectionStatusDto::Ready);
        assert_eq!(dto.watcher_error.as_deref(), Some("Watcher unavailable"));
        assert_eq!(dto.last_error, None);
    }

    #[test]
    fn unreadable_index_requests_one_immediate_derived_rebuild() {
        let mut update = DesktopUpdateState::default();

        assert!(update.record_unreadable_index(42));
        assert!(update.rebuild_derived_index);
        assert_eq!(update.quiet_deadline_ms, 42);
        assert_eq!(update.generation, 1);
        assert!(!update.record_unreadable_index(84));
        assert_eq!(update.quiet_deadline_ms, 42);
        assert_eq!(update.generation, 1);
    }

    #[test]
    fn retrieval_cache_evicts_the_least_recently_used_index_at_its_budget() {
        let temp = TestDirectory::new();
        let index_root = temp.path().join("indexes");
        publish_test_index(&index_root, COLLECTION_ID, "first.md");
        publish_test_index(&index_root, SECOND_COLLECTION_ID, "other.md");
        let first = NotesCollectionIndex::open(&index_root, COLLECTION_ID.to_string()).unwrap();
        let second =
            NotesCollectionIndex::open(&index_root, SECOND_COLLECTION_ID.to_string()).unwrap();
        let mut cache = IndexCache::new(first.estimated_heap_bytes());

        cache.insert(COLLECTION_ID.to_string(), first);
        cache.insert(SECOND_COLLECTION_ID.to_string(), second);

        assert!(!cache.entries.contains_key(COLLECTION_ID));
        assert!(cache.entries.contains_key(SECOND_COLLECTION_ID));
    }
}
