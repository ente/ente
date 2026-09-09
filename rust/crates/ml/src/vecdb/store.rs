use std::collections::{HashMap, HashSet};
use std::fs::File;
use std::io::{ErrorKind, Read};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{
    Arc, LazyLock, Mutex, MutexGuard, PoisonError, RwLock, RwLockReadGuard, RwLockWriteGuard,
    TryLockError, Weak,
};
use std::time::{Duration, Instant};

use super::arena::{UpsertOutcome, VECTORS_PER_CHUNK, VectorArena};
use super::graph::{Graph, search as graph_search, search_stored};
use super::lock::WriterLock;
use super::log::{
    HEADER_LEN, Log, LogEntry, LogRecord, header_generation, remove_if_present,
    remove_stale_temp_sibling, sync_parent_dir,
};
use super::snapshot::{
    LoadedSnapshot, load_snapshot, remove_snapshot, snapshot_path, write_snapshot,
};
use super::{AttrValue, Attribute, KeyMatches, Match, SearchParams, VecDbError};

const SNAPSHOT_HARD_CAP: usize = 5000;
const SNAPSHOT_QUIET_THRESHOLD: usize = 1000;
const SNAPSHOT_QUIET_GAP: Duration = Duration::from_secs(10);
const COMPACTION_MIN_DEAD_RECORDS: u64 = 64;
const COMPACTION_DEAD_RATIO: u64 = 10;
const COMPACTION_BATCH_SIZE: usize = 1000;
const HANDOFF_WAIT_ROUNDS: u32 = 750;
const HANDOFF_CLOSE_WAIT_ROUNDS: u32 = 2500;
const HANDOFF_WAIT_PARK: Duration = Duration::from_millis(2);
const KEY_TABLE_COPIES: usize = 2;
const KEY_ENTRY_OVERHEAD_BYTES: usize = 48;

static REGISTRY: LazyLock<Mutex<HashMap<PathBuf, Arc<Mutex<PathSlot>>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

static PENDING_SEARCH_GRAPH: LazyLock<Graph> = LazyLock::new(Graph::new);

struct PathSlot {
    live: Option<Weak<Shared>>,
}

impl PathSlot {
    fn holds_live(&self) -> bool {
        self.live
            .as_ref()
            .is_some_and(|weak| weak.strong_count() > 0)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OpenCost {
    Ready,
    NeedsRebuild,
    Absent,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Stats {
    pub live_count: usize,
    pub dead_count: usize,
    pub dims: usize,
    pub log_bytes: u64,
    pub records_since_snapshot: usize,
    pub approximate_memory_bytes: usize,
}

pub struct VecDb {
    shared: Arc<Shared>,
    read_only: bool,
}

struct Shared {
    path: PathBuf,
    dims: usize,
    registry_key: Option<PathBuf>,
    closed: AtomicBool,
    writer: Mutex<WriterHalf>,
    state: RwLock<SearchState>,
}

struct SearchState {
    arena: VectorArena,
    graph: Option<Graph>,
    attrs: AttrTable,
    total_records: u64,
}

impl SearchState {
    fn search_graph(&self) -> &Graph {
        self.graph.as_ref().unwrap_or(&PENDING_SEARCH_GRAPH)
    }
}

#[derive(Default)]
struct AttrTable(Option<Vec<Option<Box<[Attribute]>>>>);

impl AttrTable {
    fn set(&mut self, slot: u32, attrs: &[Attribute]) {
        if attrs.is_empty() {
            self.clear(slot);
            return;
        }
        let table = self.0.get_or_insert_with(Vec::new);
        let index = slot as usize;
        if table.len() <= index {
            table.resize_with(index + 1, || None);
        }
        table[index] = Some(attrs.to_vec().into_boxed_slice());
    }

    fn clear(&mut self, slot: u32) {
        if let Some(table) = &mut self.0
            && let Some(entry) = table.get_mut(slot as usize)
        {
            *entry = None;
        }
    }

    fn get(&self, slot: u32) -> Option<&[Attribute]> {
        self.0.as_ref()?.get(slot as usize)?.as_deref()
    }

    fn repack(&mut self, live_slots: impl Iterator<Item = u32>) {
        let Some(table) = &mut self.0 else {
            return;
        };
        let mut dense = 0usize;
        for slot in live_slots {
            let moved = table.get_mut(slot as usize).and_then(Option::take);
            match table.get_mut(dense) {
                Some(entry) => *entry = moved,
                None => debug_assert!(moved.is_none()),
            }
            dense += 1;
        }
        table.truncate(dense);
        table.shrink_to_fit();
    }

    fn reset(&mut self) {
        self.0 = None;
    }

    fn memory_bytes(&self) -> usize {
        let Some(table) = &self.0 else {
            return 0;
        };
        let mut bytes = table.capacity() * size_of::<Option<Box<[Attribute]>>>();
        for entry in table.iter().flatten() {
            bytes += entry.len() * size_of::<Attribute>();
            for attr in entry.iter() {
                bytes += attr.name.len();
                if let AttrValue::Str(value) = &attr.value {
                    bytes += value.len();
                }
            }
        }
        bytes
    }
}

fn slot_of_outcome(outcome: UpsertOutcome) -> u32 {
    match outcome {
        UpsertOutcome::NewSlot(slot)
        | UpsertOutcome::RecycledSlot(slot)
        | UpsertOutcome::ReplacedInPlace(slot) => slot,
    }
}

struct WriterHalf {
    compaction_retry_at_dead: u64,
    mode: WriterMode,
}

enum WriterMode {
    Active(WriterState),
    ReadOnly { log_bytes: u64 },
}

struct WriterState {
    lock: WriterLock,
    log: Log,
    mutations_since_snapshot: usize,
    last_write: Option<Instant>,
}

impl Shared {
    fn writer_half(&self) -> MutexGuard<'_, WriterHalf> {
        self.writer.lock().unwrap_or_else(PoisonError::into_inner)
    }

    fn state_read(&self) -> RwLockReadGuard<'_, SearchState> {
        self.state.read().unwrap_or_else(PoisonError::into_inner)
    }

    fn state_write(&self) -> RwLockWriteGuard<'_, SearchState> {
        self.state.write().unwrap_or_else(PoisonError::into_inner)
    }

    fn is_closed(&self) -> bool {
        self.closed.load(Ordering::Acquire)
    }

    fn ensure_open(&self) -> Result<(), VecDbError> {
        if self.closed.load(Ordering::Acquire) {
            Err(VecDbError::Closed)
        } else {
            Ok(())
        }
    }
}

impl Drop for Shared {
    fn drop(&mut self) {
        let half = self
            .writer
            .get_mut()
            .unwrap_or_else(PoisonError::into_inner);
        half.mode = WriterMode::ReadOnly { log_bytes: 0 };
        let Some(key) = &self.registry_key else {
            return;
        };
        let mut registry = registry();
        let Some(slot) = registry.get(key).map(Arc::clone) else {
            return;
        };
        let mut guard = lock_slot(&slot);
        if guard
            .live
            .as_ref()
            .is_some_and(|weak| std::ptr::eq(weak.as_ptr(), self))
        {
            guard.live = None;
        }
        let removable = !guard.holds_live() && Arc::strong_count(&slot) == 2;
        drop(guard);
        if removable {
            registry.remove(key);
        }
    }
}

fn registry() -> MutexGuard<'static, HashMap<PathBuf, Arc<Mutex<PathSlot>>>> {
    REGISTRY.lock().unwrap_or_else(PoisonError::into_inner)
}

fn lock_slot(slot: &Mutex<PathSlot>) -> MutexGuard<'_, PathSlot> {
    slot.lock().unwrap_or_else(PoisonError::into_inner)
}

fn path_slot(key: &Path) -> Arc<Mutex<PathSlot>> {
    let mut registry = registry();
    match registry.get(key) {
        Some(slot) => Arc::clone(slot),
        None => {
            let slot = Arc::new(Mutex::new(PathSlot { live: None }));
            registry.insert(key.to_path_buf(), Arc::clone(&slot));
            slot
        }
    }
}

fn existing_path_slot(key: &Path) -> Option<Arc<Mutex<PathSlot>>> {
    registry().get(key).map(Arc::clone)
}

fn remove_path_slot_if_unused(key: &Path) {
    let mut registry = registry();
    let Some(slot) = registry.get(key).map(Arc::clone) else {
        return;
    };
    let removable = !lock_slot(&slot).holds_live() && Arc::strong_count(&slot) == 2;
    if removable {
        registry.remove(key);
    }
}

fn registry_key_for(path: &Path) -> Result<PathBuf, VecDbError> {
    if let Ok(canonical) = std::fs::canonicalize(path) {
        return Ok(canonical);
    }
    let file_name = path.file_name().ok_or_else(|| {
        VecDbError::io(
            path,
            std::io::Error::new(ErrorKind::InvalidInput, "path has no file name"),
        )
    })?;
    let parent = match path.parent() {
        Some(parent) if !parent.as_os_str().is_empty() => parent,
        _ => Path::new("."),
    };
    let canonical_parent =
        std::fs::canonicalize(parent).map_err(|source| VecDbError::io(path, source))?;
    Ok(canonical_parent.join(file_name))
}

fn join_live(shared: Arc<Shared>, dims: usize, read_only: bool) -> Result<VecDb, VecDbError> {
    if shared.dims != dims {
        return Err(VecDbError::DimensionMismatch {
            expected: dims,
            actual: shared.dims,
        });
    }
    Ok(VecDb { shared, read_only })
}

enum SlotHandoff<'a> {
    Join(Arc<Shared>),
    Released(MutexGuard<'a, PathSlot>),
    Expired(MutexGuard<'a, PathSlot>),
}

fn wait_for_teardown_handoff<'a>(slot: &'a Mutex<PathSlot>, path: &Path) -> SlotHandoff<'a> {
    let mut dead_rounds = HANDOFF_WAIT_ROUNDS;
    let mut close_rounds = HANDOFF_CLOSE_WAIT_ROUNDS;
    loop {
        let guard = lock_slot(slot);
        let observed = match &guard.live {
            None => return SlotHandoff::Released(guard),
            Some(weak) => weak.upgrade(),
        };
        match observed {
            Some(shared) if !shared.is_closed() => return SlotHandoff::Join(shared),
            Some(closing) => {
                drop(guard);
                drop(closing);
                if close_rounds == 0 {
                    warn_handoff_cap(path);
                    return SlotHandoff::Expired(lock_slot(slot));
                }
                close_rounds -= 1;
            }
            None => {
                if dead_rounds == 0 {
                    warn_handoff_cap(path);
                    return SlotHandoff::Expired(guard);
                }
                drop(guard);
                dead_rounds -= 1;
            }
        }
        std::thread::sleep(HANDOFF_WAIT_PARK);
    }
}

fn warn_handoff_cap(path: &Path) {
    log::warn!(
        "teardown handoff for {} did not complete within the wait cap; acquiring directly",
        path.display()
    );
}

impl VecDb {
    pub fn open(path: &Path, dims: usize) -> Result<Self, VecDbError> {
        let key = registry_key_for(path)?;
        let slot = path_slot(&key);
        let mut guard = lock_slot(&slot);
        if guard.live.is_some() {
            let observed = guard.live.as_ref().and_then(Weak::upgrade);
            drop(guard);
            match observed {
                Some(shared) if !shared.is_closed() => return join_live(shared, dims, false),
                observed => drop(observed),
            }
            match wait_for_teardown_handoff(&slot, &key) {
                SlotHandoff::Join(shared) => return join_live(shared, dims, false),
                SlotHandoff::Released(reacquired) | SlotHandoff::Expired(reacquired) => {
                    guard = reacquired;
                }
            }
        }
        let built = match build_writer(&key, key.clone(), dims) {
            Ok(built) => built,
            Err(error) => {
                drop(guard);
                drop(slot);
                remove_path_slot_if_unused(&key);
                return Err(error);
            }
        };
        match built {
            BuiltWriter::Complete(shared) => {
                let shared = Arc::new(shared);
                guard.live = Some(Arc::downgrade(&shared));
                drop(guard);
                Ok(Self {
                    shared,
                    read_only: false,
                })
            }
            BuiltWriter::Pending {
                shared,
                snapshot_stale,
                pending_records,
            } => {
                let shared = Arc::new(shared);
                let half = shared.writer_half();
                guard.live = Some(Arc::downgrade(&shared));
                drop(guard);
                finish_pending_open(&shared, half, snapshot_stale, pending_records);
                Ok(Self {
                    shared,
                    read_only: false,
                })
            }
        }
    }

    pub fn open_cost(path: &Path) -> OpenCost {
        let key = registry_key_for(path).unwrap_or_else(|_| path.to_path_buf());
        if registry_holds_live(&key) {
            return OpenCost::Ready;
        }
        open_cost_from_files(&key)
    }

    pub fn open_read_only(path: &Path, dims: usize) -> Result<Self, VecDbError> {
        let resolved = registry_key_for(path).unwrap_or_else(|_| path.to_path_buf());
        if let Some(slot) = existing_path_slot(&resolved) {
            let observed = lock_slot(&slot).live.as_ref().and_then(Weak::upgrade);
            match observed {
                Some(shared) if !shared.is_closed() => return join_live(shared, dims, true),
                Some(closing) => {
                    drop(closing);
                    match wait_for_teardown_handoff(&slot, &resolved) {
                        SlotHandoff::Join(shared) => return join_live(shared, dims, true),
                        SlotHandoff::Released(released) | SlotHandoff::Expired(released) => {
                            drop(released);
                        }
                    }
                }
                None => {}
            }
        }
        Ok(Self {
            shared: Arc::new(build_read_only(&resolved, dims)?),
            read_only: true,
        })
    }

    pub fn add(&self, key: &str, vector: &[f32]) -> Result<(), VecDbError> {
        self.add_with_attrs(key, vector, &[])
    }

    pub fn add_with_attrs(
        &self,
        key: &str,
        vector: &[f32],
        attrs: &[Attribute],
    ) -> Result<(), VecDbError> {
        let now = Instant::now();
        let mut half = self.writable_half()?;
        let state = active_state(&mut half)?;
        ensure_finite(key, vector)?;
        state.log.append(&[LogEntry::Add { key, vector, attrs }])?;
        apply_add(&self.shared, key, vector, attrs)?;
        apply_policy(&self.shared, &mut half, 1, now)
    }

    pub fn bulk_add(&self, keys: &[String], vectors: &[Vec<f32>]) -> Result<(), VecDbError> {
        self.bulk_add_internal(keys, vectors, None)
    }

    pub fn bulk_add_with_attrs(
        &self,
        keys: &[String],
        vectors: &[Vec<f32>],
        attrs: &[Option<Vec<Attribute>>],
    ) -> Result<(), VecDbError> {
        if attrs.len() != keys.len() {
            return Err(VecDbError::LengthMismatch {
                keys: keys.len(),
                vectors: attrs.len(),
            });
        }
        self.bulk_add_internal(keys, vectors, Some(attrs))
    }

    fn bulk_add_internal(
        &self,
        keys: &[String],
        vectors: &[Vec<f32>],
        attrs: Option<&[Option<Vec<Attribute>>]>,
    ) -> Result<(), VecDbError> {
        if keys.len() != vectors.len() {
            return Err(VecDbError::LengthMismatch {
                keys: keys.len(),
                vectors: vectors.len(),
            });
        }
        let attrs_of = |index: usize| -> &[Attribute] {
            attrs
                .and_then(|entries| entries[index].as_deref())
                .unwrap_or(&[])
        };
        let now = Instant::now();
        let mut half = self.writable_half()?;
        let state = active_state(&mut half)?;
        if keys.is_empty() {
            return Ok(());
        }
        for (key, vector) in keys.iter().zip(vectors) {
            ensure_finite(key, vector)?;
        }
        let records: Vec<LogEntry<'_>> = keys
            .iter()
            .zip(vectors)
            .enumerate()
            .map(|(index, (key, vector))| LogEntry::Add {
                key,
                vector,
                attrs: attrs_of(index),
            })
            .collect();
        state.log.append(&records)?;
        for (index, (key, vector)) in keys.iter().zip(vectors).enumerate() {
            apply_add(&self.shared, key, vector, attrs_of(index))?;
        }
        apply_policy(&self.shared, &mut half, keys.len(), now)
    }

    pub fn remove(&self, key: &str) -> Result<bool, VecDbError> {
        let now = Instant::now();
        let mut half = self.writable_half()?;
        let state = active_state(&mut half)?;
        if self.shared.state_read().arena.slot_of_key(key).is_none() {
            return Ok(false);
        }
        state.log.append(&[LogEntry::Tombstone { key }])?;
        apply_remove(&self.shared, key);
        apply_policy(&self.shared, &mut half, 1, now)?;
        Ok(true)
    }

    pub fn bulk_remove(&self, keys: &[String]) -> Result<usize, VecDbError> {
        let now = Instant::now();
        let mut half = self.writable_half()?;
        let state = active_state(&mut half)?;
        let scheduled: Vec<&str> = {
            let st = self.shared.state_read();
            let mut scheduled: Vec<&str> = Vec::new();
            let mut seen: HashSet<&str> = HashSet::new();
            for key in keys {
                if st.arena.slot_of_key(key).is_some() && seen.insert(key.as_str()) {
                    scheduled.push(key);
                }
            }
            scheduled
        };
        if scheduled.is_empty() {
            return Ok(0);
        }
        let records: Vec<LogEntry<'_>> = scheduled
            .iter()
            .map(|key| LogEntry::Tombstone { key })
            .collect();
        state.log.append(&records)?;
        for key in &scheduled {
            apply_remove(&self.shared, key);
        }
        let count = scheduled.len();
        apply_policy(&self.shared, &mut half, count, now)?;
        Ok(count)
    }

    pub fn contains(&self, key: &str) -> bool {
        self.shared.state_read().arena.slot_of_key(key).is_some()
    }

    pub fn get(&self, key: &str) -> Option<Vec<f32>> {
        let st = self.shared.state_read();
        let slot = st.arena.slot_of_key(key)?;
        Some(st.arena.vector_values(slot))
    }

    pub fn get_attrs(&self, key: &str) -> Option<Vec<Attribute>> {
        let st = self.shared.state_read();
        let slot = st.arena.slot_of_key(key)?;
        st.attrs.get(slot).map(<[Attribute]>::to_vec)
    }

    pub fn bulk_get_attrs(&self, keys: &[String]) -> Vec<Option<Vec<Attribute>>> {
        let st = self.shared.state_read();
        keys.iter()
            .map(|key| {
                let slot = st.arena.slot_of_key(key)?;
                st.attrs.get(slot).map(<[Attribute]>::to_vec)
            })
            .collect()
    }

    pub fn search(&self, query: &[f32], params: &SearchParams) -> Result<Vec<Match>, VecDbError> {
        self.shared.ensure_open()?;
        if degenerate_distance_cut(params)? {
            return Ok(Vec::new());
        }
        let st = self.shared.state_read();
        self.shared.ensure_open()?;
        let allowed_slots = resolve_allowed_slots(&st, params.allowed_keys.as_deref());
        search_in_state(&st, query, params, allowed_slots.as_ref())
    }

    pub fn bulk_search(
        &self,
        queries: &[Vec<f32>],
        params: &SearchParams,
    ) -> Result<Vec<Vec<Match>>, VecDbError> {
        self.shared.ensure_open()?;
        if degenerate_distance_cut(params)? {
            return Ok(queries.iter().map(|_| Vec::new()).collect());
        }
        let st = self.shared.state_read();
        self.shared.ensure_open()?;
        let allowed_slots = resolve_allowed_slots(&st, params.allowed_keys.as_deref());
        queries
            .iter()
            .map(|query| search_in_state(&st, query, params, allowed_slots.as_ref()))
            .collect()
    }

    pub fn bulk_search_varied(
        &self,
        queries: &[Vec<f32>],
        params: &[SearchParams],
    ) -> Result<Vec<Vec<Match>>, VecDbError> {
        if queries.len() != params.len() {
            return Err(VecDbError::LengthMismatch {
                keys: queries.len(),
                vectors: params.len(),
            });
        }
        self.shared.ensure_open()?;
        let st = self.shared.state_read();
        self.shared.ensure_open()?;
        queries
            .iter()
            .zip(params)
            .map(|(query, query_params)| {
                if degenerate_distance_cut(query_params)? {
                    return Ok(Vec::new());
                }
                let allowed_slots =
                    resolve_allowed_slots(&st, query_params.allowed_keys.as_deref());
                search_in_state(&st, query, query_params, allowed_slots.as_ref())
            })
            .collect()
    }

    pub fn bulk_search_stored(
        &self,
        keys: &[String],
        count: usize,
        max_distance: Option<f32>,
        exact: bool,
        restrict_to_input: bool,
    ) -> Result<Vec<KeyMatches>, VecDbError> {
        self.shared.ensure_open()?;
        let st = self.shared.state_read();
        self.shared.ensure_open()?;
        let resolved: Vec<(&String, u32)> = keys
            .iter()
            .filter_map(|key| st.arena.slot_of_key(key).map(|slot| (key, slot)))
            .collect();
        let degenerate =
            max_distance.is_some_and(|distance| !distance.is_finite() || distance < 0.0);
        let allowed_slots: Option<HashSet<u32>> =
            restrict_to_input.then(|| resolved.iter().map(|(_, slot)| *slot).collect());
        let params = SearchParams {
            limit: Some(count),
            max_distance: None,
            exact,
            allowed_keys: None,
        };
        let mut results = Vec::with_capacity(resolved.len());
        for (key, slot) in resolved {
            if degenerate {
                results.push(KeyMatches {
                    key: key.clone(),
                    matches: Vec::new(),
                });
                continue;
            }
            let mut matches = search_stored(
                st.search_graph(),
                &st.arena,
                slot,
                &params,
                allowed_slots.as_ref(),
            );
            if let Some(cap) = max_distance {
                let keep = matches.partition_point(|entry| entry.distance <= cap);
                matches.truncate(keep);
            }
            results.push(KeyMatches {
                key: key.clone(),
                matches,
            });
        }
        Ok(results)
    }

    pub fn flush(&self) -> Result<(), VecDbError> {
        let mut half = self.writable_half()?;
        let state = active_state(&mut half)?;
        if state.mutations_since_snapshot == 0 {
            return Ok(());
        }
        write_snapshot_now(&self.shared, &mut half)
    }

    pub fn reset(&self) -> Result<(), VecDbError> {
        let mut half = self.writable_half()?;
        let WriterState {
            lock,
            log,
            mutations_since_snapshot,
            ..
        } = take_writer_state(&mut half)?;
        let old_generation = log.generation();
        drop(log);
        let dims = self.shared.dims;
        let recreated = remove_data_files(&self.shared.path)
            .and_then(|()| Log::create(&self.shared.path, dims));
        let log = match recreated {
            Ok(log) => log,
            Err(error) => {
                recover_after_failed_reset(
                    &self.shared,
                    &mut half,
                    lock,
                    old_generation,
                    mutations_since_snapshot,
                );
                return Err(error);
            }
        };
        let arena = VectorArena::new(dims)?;
        {
            let mut st = self.shared.state_write();
            st.arena = arena;
            st.graph = Some(Graph::new());
            st.attrs.reset();
            st.total_records = 0;
        }
        half.compaction_retry_at_dead = 0;
        half.mode = WriterMode::Active(WriterState {
            lock,
            log,
            mutations_since_snapshot: 0,
            last_write: None,
        });
        Ok(())
    }

    pub fn delete(self) -> Result<(), VecDbError> {
        self.shared.ensure_open()?;
        if self.read_only {
            return Err(VecDbError::ReadOnly);
        }
        close_live_instance(&self.shared)
    }

    pub fn purge(path: &Path) -> Result<(), VecDbError> {
        let key = match registry_key_for(path) {
            Ok(key) => key,
            Err(VecDbError::Io { source, .. }) if source.kind() == ErrorKind::NotFound => {
                return Ok(());
            }
            Err(error) => return Err(error),
        };
        if let Some(slot) = existing_path_slot(&key) {
            for _ in 0..3 {
                let guard = lock_slot(&slot);
                if guard.live.is_none() {
                    break;
                }
                let observed = guard.live.as_ref().and_then(Weak::upgrade);
                drop(guard);
                match observed {
                    Some(shared) if !shared.is_closed() => match close_live_instance(&shared) {
                        Ok(()) => return Ok(()),
                        Err(VecDbError::Closed) => {}
                        Err(error) => return Err(error),
                    },
                    observed => {
                        drop(observed);
                        match wait_for_teardown_handoff(&slot, &key) {
                            SlotHandoff::Join(joined) => drop(joined),
                            SlotHandoff::Released(reacquired)
                            | SlotHandoff::Expired(reacquired) => {
                                drop(reacquired);
                                break;
                            }
                        }
                    }
                }
            }
        }
        let lock = WriterLock::acquire(&key)?;
        remove_data_files(&key)?;
        drop(lock);
        Ok(())
    }

    pub fn stats(&self) -> Result<Stats, VecDbError> {
        self.shared.ensure_open()?;
        let half = self.shared.writer_half();
        self.shared.ensure_open()?;
        let (log_bytes, records_since_snapshot) = match &half.mode {
            WriterMode::Active(state) => (
                state.log.current_end_offset(),
                state.mutations_since_snapshot,
            ),
            WriterMode::ReadOnly { log_bytes } => (*log_bytes, 0),
        };
        let st = self.shared.state_read();
        let live_count = st.arena.live_count();
        Ok(Stats {
            live_count,
            dead_count: st.total_records.saturating_sub(live_count as u64) as usize,
            dims: st.arena.dims(),
            log_bytes,
            records_since_snapshot,
            approximate_memory_bytes: approximate_memory_bytes(&st),
        })
    }

    pub fn len(&self) -> usize {
        self.shared.state_read().arena.live_count()
    }

    pub fn is_empty(&self) -> bool {
        self.shared.state_read().arena.is_empty()
    }

    fn writable_half(&self) -> Result<MutexGuard<'_, WriterHalf>, VecDbError> {
        self.shared.ensure_open()?;
        if self.read_only {
            return Err(VecDbError::ReadOnly);
        }
        let half = self.shared.writer_half();
        self.shared.ensure_open()?;
        Ok(half)
    }
}

fn active_state(half: &mut WriterHalf) -> Result<&mut WriterState, VecDbError> {
    match &mut half.mode {
        WriterMode::Active(state) => Ok(state),
        WriterMode::ReadOnly { .. } => Err(VecDbError::ReadOnly),
    }
}

fn take_writer_state(half: &mut WriterHalf) -> Result<WriterState, VecDbError> {
    match std::mem::replace(&mut half.mode, WriterMode::ReadOnly { log_bytes: 0 }) {
        WriterMode::Active(state) => Ok(state),
        WriterMode::ReadOnly { log_bytes } => {
            half.mode = WriterMode::ReadOnly { log_bytes };
            Err(VecDbError::ReadOnly)
        }
    }
}

fn degenerate_distance_cut(params: &SearchParams) -> Result<bool, VecDbError> {
    if params.limit.is_none() && params.max_distance.is_none() {
        return Err(VecDbError::UnboundedSearch);
    }
    Ok(params
        .max_distance
        .is_some_and(|max_distance| !max_distance.is_finite() || max_distance < 0.0))
}

fn resolve_allowed_slots(
    state: &SearchState,
    allowed_keys: Option<&[String]>,
) -> Option<HashSet<u32>> {
    allowed_keys.map(|keys| {
        keys.iter()
            .filter_map(|key| state.arena.slot_of_key(key))
            .collect()
    })
}

fn search_in_state(
    state: &SearchState,
    query: &[f32],
    params: &SearchParams,
    allowed_slots: Option<&HashSet<u32>>,
) -> Result<Vec<Match>, VecDbError> {
    let packed = state.arena.pack_query(query)?;
    Ok(graph_search(
        state.search_graph(),
        &state.arena,
        &packed,
        params,
        allowed_slots,
    ))
}

fn registry_holds_live(key: &Path) -> bool {
    let Some(slot) = existing_path_slot(key) else {
        return false;
    };
    match slot.try_lock() {
        Ok(guard) => guard.holds_live(),
        Err(TryLockError::Poisoned(poisoned)) => poisoned.into_inner().holds_live(),
        Err(TryLockError::WouldBlock) => false,
    }
}

fn open_cost_from_files(path: &Path) -> OpenCost {
    let mut file = match File::open(path) {
        Ok(file) => file,
        Err(_) => return OpenCost::Absent,
    };
    let log_len = match file.metadata() {
        Ok(meta) => meta.len(),
        Err(_) => return OpenCost::Absent,
    };
    if log_len < HEADER_LEN as u64 {
        return OpenCost::Absent;
    }
    let mut header = [0u8; HEADER_LEN];
    if file.read_exact(&mut header).is_err() {
        return OpenCost::Absent;
    }
    drop(file);
    let Ok(generation) = header_generation(&header) else {
        return OpenCost::NeedsRebuild;
    };
    let snapshot_present = std::fs::metadata(snapshot_path(path)).is_ok();
    match load_snapshot(path, generation) {
        Some(loaded) if loaded.covered_log_offset <= log_len => OpenCost::Ready,
        Some(_) => OpenCost::NeedsRebuild,
        None if snapshot_present => OpenCost::NeedsRebuild,
        None if log_len > HEADER_LEN as u64 => OpenCost::NeedsRebuild,
        None => OpenCost::Ready,
    }
}

fn close_live_instance(shared: &Arc<Shared>) -> Result<(), VecDbError> {
    let mut half = shared.writer_half();
    shared.ensure_open()?;
    let WriterState { lock, log, .. } = take_writer_state(&mut half)?;
    let mut st = shared.state_write();
    shared.closed.store(true, Ordering::Release);
    drop(log);
    let removed = remove_data_files(&shared.path);
    if let Ok(empty) = VectorArena::new(shared.dims) {
        st.arena = empty;
        st.graph = Some(Graph::new());
        st.attrs.reset();
        st.total_records = 0;
    }
    drop(lock);
    if let Some(key) = &shared.registry_key
        && let Some(slot) = existing_path_slot(key)
    {
        let mut guard = lock_slot(&slot);
        if guard
            .live
            .as_ref()
            .is_some_and(|weak| std::ptr::eq(weak.as_ptr(), Arc::as_ptr(shared)))
        {
            guard.live = None;
        }
    }
    drop(st);
    drop(half);
    removed
}

fn apply_add(
    shared: &Shared,
    key: &str,
    vector: &[f32],
    attrs: &[Attribute],
) -> Result<(), VecDbError> {
    let mut st = shared.state_write();
    let SearchState {
        arena,
        graph,
        attrs: attr_table,
        total_records,
    } = &mut *st;
    let outcome = arena.upsert(key, vector)?;
    attr_table.set(slot_of_outcome(outcome), attrs);
    if let Some(graph) = graph {
        apply_outcome(graph, arena, outcome);
    }
    *total_records += 1;
    Ok(())
}

fn apply_remove(shared: &Shared, key: &str) {
    let mut st = shared.state_write();
    if let Some(slot) = st.arena.remove(key) {
        st.attrs.clear(slot);
    }
    st.total_records += 1;
}

fn apply_policy(
    shared: &Shared,
    half: &mut WriterHalf,
    count: usize,
    now: Instant,
) -> Result<(), VecDbError> {
    let (live, total) = {
        let st = shared.state_read();
        (st.arena.live_count() as u64, st.total_records)
    };
    let (quiet, mutations) = {
        let state = active_state(half)?;
        state.mutations_since_snapshot += count;
        let quiet = state
            .last_write
            .is_some_and(|previous| now.duration_since(previous) >= SNAPSHOT_QUIET_GAP);
        state.last_write = Some(now);
        (quiet, state.mutations_since_snapshot)
    };
    let dead = total.saturating_sub(live);
    if dead >= COMPACTION_MIN_DEAD_RECORDS
        && dead.saturating_mul(COMPACTION_DEAD_RATIO) >= total
        && dead >= half.compaction_retry_at_dead
    {
        match compact(shared, half) {
            Ok(()) => half.compaction_retry_at_dead = 0,
            Err(error) => {
                log::warn!("compaction of {} failed: {error}", shared.path.display());
                half.compaction_retry_at_dead = dead + COMPACTION_MIN_DEAD_RECORDS;
            }
        }
        return Ok(());
    }
    if (mutations >= SNAPSHOT_HARD_CAP || (mutations >= SNAPSHOT_QUIET_THRESHOLD && quiet))
        && let Err(error) = write_snapshot_now(shared, half)
    {
        log::warn!("snapshot of {} failed: {error}", shared.path.display());
    }
    Ok(())
}

fn write_snapshot_now(shared: &Shared, half: &mut WriterHalf) -> Result<(), VecDbError> {
    let state = active_state(half)?;
    {
        let st = shared.state_read();
        let Some(graph) = &st.graph else {
            return Ok(());
        };
        write_snapshot(
            state.log.path(),
            state.log.generation(),
            state.log.current_end_offset(),
            graph,
        )?;
    }
    state.mutations_since_snapshot = 0;
    Ok(())
}

fn compact(shared: &Shared, half: &mut WriterHalf) -> Result<(), VecDbError> {
    active_state(half)?;
    let dims = shared.dims;
    let (mut temp_log, temp_path) = Log::create_temp_sibling(&shared.path, dims)?;
    let staged = {
        let st = shared.state_read();
        stage_live_entries(&st, &mut temp_log)
    };
    if let Err(error) = staged {
        drop(temp_log);
        let _ = std::fs::remove_file(&temp_path);
        return Err(error);
    }
    let temp_file = temp_log.into_file();
    if let Err(source) = temp_file.sync_all() {
        drop(temp_file);
        let _ = std::fs::remove_file(&temp_path);
        return Err(VecDbError::io(&temp_path, source));
    }
    drop(temp_file);
    let WriterState {
        lock,
        log,
        mutations_since_snapshot,
        last_write,
    } = take_writer_state(half)?;
    drop(log);
    let promoted = promote_compacted_log(&temp_path, &shared.path);
    let pending = if temp_path.exists() {
        let _ = std::fs::remove_file(&temp_path);
        mutations_since_snapshot
    } else {
        let live_records = {
            let mut st = shared.state_write();
            let SearchState {
                arena,
                graph,
                attrs,
                total_records,
            } = &mut *st;
            attrs.repack(arena.live_slots());
            arena.compact_in_place();
            *graph = None;
            *total_records = arena.live_count() as u64;
            *total_records as usize
        };
        let graph = {
            let st = shared.state_read();
            Graph::rebuild(&st.arena)
        };
        shared.state_write().graph = Some(graph);
        live_records
    };
    let restored = restore_writer_mode(shared, half, lock, last_write, pending);
    promoted?;
    restored?;
    write_snapshot_now(shared, half)
}

fn restore_writer_mode(
    shared: &Shared,
    half: &mut WriterHalf,
    lock: WriterLock,
    last_write: Option<Instant>,
    mutations_since_snapshot: usize,
) -> Result<(), VecDbError> {
    match reopen_log(&shared.path, shared.dims) {
        Ok(log) => {
            half.mode = WriterMode::Active(WriterState {
                lock,
                log,
                mutations_since_snapshot,
                last_write,
            });
            Ok(())
        }
        Err(error) => {
            let log_bytes = std::fs::metadata(&shared.path)
                .map(|meta| meta.len())
                .unwrap_or(0);
            log::warn!(
                "degrading {} to read-only after failing to restore its writer: {error}",
                shared.path.display()
            );
            half.mode = WriterMode::ReadOnly { log_bytes };
            Err(error)
        }
    }
}

fn recover_after_failed_reset(
    shared: &Shared,
    half: &mut WriterHalf,
    lock: WriterLock,
    old_generation: [u8; 16],
    old_pending: usize,
) {
    let old_log_restored = restore_writer_mode(shared, half, lock, None, old_pending).is_ok()
        && matches!(&half.mode, WriterMode::Active(state) if state.log.generation() == old_generation);
    if old_log_restored {
        return;
    }
    if let Ok(empty) = VectorArena::new(shared.dims) {
        let mut st = shared.state_write();
        st.arena = empty;
        st.graph = Some(Graph::new());
        st.attrs.reset();
        st.total_records = 0;
        half.compaction_retry_at_dead = 0;
    }
    if let WriterMode::Active(state) = &mut half.mode {
        state.mutations_since_snapshot = 0;
    }
}

enum BuiltWriter {
    Complete(Shared),
    Pending {
        shared: Shared,
        snapshot_stale: bool,
        pending_records: usize,
    },
}

fn build_writer(
    path: &Path,
    registry_key: PathBuf,
    dims: usize,
) -> Result<BuiltWriter, VecDbError> {
    let lock = WriterLock::acquire(path)?;
    let mut log = match Log::create(path, dims) {
        Ok(created) => created,
        Err(VecDbError::Io { source, .. }) if source.kind() == ErrorKind::AlreadyExists => {
            reopen_log(path, dims)?
        }
        Err(error) => return Err(error),
    };
    remove_stale_temp_sibling(path)?;
    let snapshot_present = std::fs::metadata(snapshot_path(path)).is_ok();
    let replayed = replay(&mut log, dims, ReplayMode::Writer)?;
    if replayed.recoverable_end < log.current_end_offset() {
        log.truncate_to(replayed.recoverable_end)?;
    }
    let ReplayedState {
        arena,
        graph,
        attrs,
        total_records,
        tail_records,
        ..
    } = replayed;
    match graph {
        Some(graph) => {
            let mut mutations_since_snapshot = 0;
            if tail_records > 0
                && let Err(error) = write_snapshot(
                    log.path(),
                    log.generation(),
                    log.current_end_offset(),
                    &graph,
                )
            {
                log::warn!(
                    "continuing without an open-time snapshot for {}: {error}",
                    path.display()
                );
                mutations_since_snapshot = (tail_records as usize).max(1);
            }
            Ok(BuiltWriter::Complete(writer_shared(
                path,
                registry_key,
                dims,
                WriterState {
                    lock,
                    log,
                    mutations_since_snapshot,
                    last_write: None,
                },
                SearchState {
                    arena,
                    graph: Some(graph),
                    attrs,
                    total_records,
                },
            )))
        }
        None => Ok(BuiltWriter::Pending {
            shared: writer_shared(
                path,
                registry_key,
                dims,
                WriterState {
                    lock,
                    log,
                    mutations_since_snapshot: 0,
                    last_write: None,
                },
                SearchState {
                    arena,
                    graph: None,
                    attrs,
                    total_records,
                },
            ),
            snapshot_stale: total_records > 0 || snapshot_present,
            pending_records: total_records as usize,
        }),
    }
}

fn writer_shared(
    path: &Path,
    registry_key: PathBuf,
    dims: usize,
    writer: WriterState,
    state: SearchState,
) -> Shared {
    Shared {
        path: path.to_path_buf(),
        dims,
        registry_key: Some(registry_key),
        closed: AtomicBool::new(false),
        writer: Mutex::new(WriterHalf {
            compaction_retry_at_dead: 0,
            mode: WriterMode::Active(writer),
        }),
        state: RwLock::new(state),
    }
}

fn finish_pending_open(
    shared: &Shared,
    mut half: MutexGuard<'_, WriterHalf>,
    snapshot_stale: bool,
    pending_records: usize,
) {
    let graph = {
        let st = shared.state_read();
        Graph::rebuild(&st.arena)
    };
    install_graph(shared, graph);
    if !snapshot_stale {
        return;
    }
    if let Err(error) = write_snapshot_now(shared, &mut half) {
        log::warn!(
            "continuing without an open-time snapshot for {}: {error}",
            shared.path.display()
        );
        if let WriterMode::Active(state) = &mut half.mode {
            state.mutations_since_snapshot = pending_records.max(1);
        }
    }
}

fn install_graph(shared: &Shared, graph: Graph) {
    let mut installable = Some(graph);
    loop {
        match shared.state.try_write() {
            Ok(mut st) => {
                st.graph = installable.take();
                return;
            }
            Err(TryLockError::Poisoned(poisoned)) => {
                poisoned.into_inner().graph = installable.take();
                return;
            }
            Err(TryLockError::WouldBlock) => std::thread::yield_now(),
        }
    }
}

fn build_read_only(path: &Path, dims: usize) -> Result<Shared, VecDbError> {
    let file = match File::open(path) {
        Ok(file) => file,
        Err(error) if error.kind() == ErrorKind::NotFound => {
            return empty_read_only(path, dims);
        }
        Err(source) => return Err(VecDbError::io(path, source)),
    };
    let file_len = file
        .metadata()
        .map_err(|source| VecDbError::io(path, source))?
        .len();
    if file_len < HEADER_LEN as u64 {
        return empty_read_only(path, dims);
    }
    let mut log = Log::open(file, path, dims)?;
    let replayed = replay(&mut log, dims, ReplayMode::ReadOnly)?;
    drop(log);
    let ReplayedState {
        arena,
        graph,
        attrs,
        total_records,
        recoverable_end,
        ..
    } = replayed;
    let graph = graph.unwrap_or_else(|| Graph::rebuild(&arena));
    Ok(read_only_shared(
        path,
        dims,
        arena,
        graph,
        attrs,
        total_records,
        recoverable_end,
    ))
}

fn empty_read_only(path: &Path, dims: usize) -> Result<Shared, VecDbError> {
    Ok(read_only_shared(
        path,
        dims,
        VectorArena::new(dims)?,
        Graph::new(),
        AttrTable::default(),
        0,
        0,
    ))
}

fn read_only_shared(
    path: &Path,
    dims: usize,
    arena: VectorArena,
    graph: Graph,
    attrs: AttrTable,
    total_records: u64,
    log_bytes: u64,
) -> Shared {
    Shared {
        path: path.to_path_buf(),
        dims,
        registry_key: None,
        closed: AtomicBool::new(false),
        writer: Mutex::new(WriterHalf {
            compaction_retry_at_dead: 0,
            mode: WriterMode::ReadOnly { log_bytes },
        }),
        state: RwLock::new(SearchState {
            arena,
            graph: Some(graph),
            attrs,
            total_records,
        }),
    }
}

fn approximate_memory_bytes(state: &SearchState) -> usize {
    let vector_bytes = state.arena.slot_count().div_ceil(VECTORS_PER_CHUNK)
        * VECTORS_PER_CHUNK
        * state.arena.dims()
        * size_of::<f32>();
    let key_bytes: usize = state
        .arena
        .live_slots()
        .filter_map(|slot| state.arena.key_of_slot(slot))
        .map(|key| KEY_TABLE_COPIES * (key.len() + KEY_ENTRY_OVERHEAD_BYTES))
        .sum();
    let free_list_bytes = state.arena.dead_count() * size_of::<u32>();
    let graph_bytes = state.graph.as_ref().map_or(0, Graph::memory_bytes);
    vector_bytes + key_bytes + free_list_bytes + graph_bytes + state.attrs.memory_bytes()
}

struct ReplayedState {
    arena: VectorArena,
    graph: Option<Graph>,
    attrs: AttrTable,
    total_records: u64,
    recoverable_end: u64,
    tail_records: u64,
}

enum ReplayMode {
    Writer,
    ReadOnly,
}

fn replay(log: &mut Log, dims: usize, mode: ReplayMode) -> Result<ReplayedState, VecDbError> {
    let mut snapshot = load_snapshot(log.path(), log.generation());
    if let Some(loaded) = &snapshot
        && loaded.covered_log_offset > log.current_end_offset()
    {
        match mode {
            ReplayMode::Writer => {}
            ReplayMode::ReadOnly => log.extend_end_offset_to(loaded.covered_log_offset)?,
        }
        if loaded.covered_log_offset > log.current_end_offset() {
            return Err(VecDbError::Corrupt(format!(
                "{}: snapshot covers {} bytes but the log is only {} bytes; preserving the file",
                log.path().display(),
                loaded.covered_log_offset,
                log.current_end_offset()
            )));
        }
    }
    let snapshot_covered = snapshot.as_ref().map(|loaded| loaded.covered_log_offset);
    let covered = snapshot_covered.unwrap_or(u64::MAX);
    let path = log.path().to_path_buf();
    let mut arena = VectorArena::new(dims)?;
    let mut attrs = AttrTable::default();
    let mut graph: Option<Graph> = None;
    let mut tail_records = 0u64;
    let mut total_records = 0u64;
    let recoverable_end;
    {
        let mut scanner = log.scan()?;
        while let Some((record, offset)) = scanner.next_record()? {
            total_records += 1;
            if offset >= covered {
                attach_snapshot_graph(&mut graph, &mut snapshot, &arena, &path);
                tail_records += 1;
            }
            match record {
                LogRecord::Add {
                    key,
                    vector,
                    attrs: record_attrs,
                } => {
                    let outcome = arena.upsert(&key, &vector)?;
                    attrs.set(slot_of_outcome(outcome), &record_attrs);
                    if let Some(graph) = &mut graph {
                        apply_outcome(graph, &arena, outcome);
                    }
                }
                LogRecord::Tombstone { key } => {
                    if let Some(slot) = arena.remove(&key) {
                        attrs.clear(slot);
                    }
                }
            }
        }
        recoverable_end = scanner.recoverable_end();
    }
    let physical_end = log.current_end_offset();
    if recoverable_end < physical_end {
        if let Some(snapshot_covered) = snapshot_covered
            && snapshot_covered > recoverable_end
        {
            return Err(VecDbError::Corrupt(format!(
                "{}: log unreadable past offset {recoverable_end}, but its snapshot covers {snapshot_covered} of {physical_end} bytes; preserving the file",
                log.path().display()
            )));
        }
        if log.tail_contains_valid_record(recoverable_end)? {
            return Err(VecDbError::Corrupt(format!(
                "{}: log unreadable at offset {recoverable_end} despite intact records before the end at {physical_end}; preserving the file",
                log.path().display()
            )));
        }
    }
    if covered <= recoverable_end {
        attach_snapshot_graph(&mut graph, &mut snapshot, &arena, &path);
    }
    Ok(ReplayedState {
        arena,
        graph,
        attrs,
        total_records,
        recoverable_end,
        tail_records,
    })
}

fn attach_snapshot_graph(
    graph: &mut Option<Graph>,
    snapshot: &mut Option<LoadedSnapshot>,
    arena: &VectorArena,
    path: &Path,
) {
    let Some(loaded) = snapshot.take() else {
        return;
    };
    match Graph::from_parts(
        loaded.entry_point,
        loaded.parts,
        arena.slot_count(),
        loaded.insert_ordinal,
    ) {
        Ok(attached) => *graph = Some(attached),
        Err(error) => {
            log::debug!("discarding snapshot for {}: {error}", path.display());
        }
    }
}

fn apply_outcome(graph: &mut Graph, arena: &VectorArena, outcome: UpsertOutcome) {
    match outcome {
        UpsertOutcome::NewSlot(slot) => graph.insert(slot, arena),
        UpsertOutcome::RecycledSlot(slot) | UpsertOutcome::ReplacedInPlace(slot) => {
            graph.reinsert(slot, arena);
        }
    }
}

fn ensure_finite(key: &str, vector: &[f32]) -> Result<(), VecDbError> {
    if let Some(index) = vector.iter().position(|value| !value.is_finite()) {
        return Err(VecDbError::InvalidVector(format!(
            "component {index} of the vector for key {key:?} is not finite"
        )));
    }
    Ok(())
}

fn reopen_log(path: &Path, dims: usize) -> Result<Log, VecDbError> {
    let file = File::options()
        .read(true)
        .write(true)
        .open(path)
        .map_err(|source| VecDbError::io(path, source))?;
    Log::open(file, path, dims)
}

fn promote_compacted_log(temp_path: &Path, path: &Path) -> Result<(), VecDbError> {
    std::fs::rename(temp_path, path).map_err(|source| VecDbError::io(temp_path, source))?;
    sync_parent_dir(path)
}

fn remove_data_files(path: &Path) -> Result<(), VecDbError> {
    remove_if_present(path)?;
    remove_snapshot(path)?;
    remove_stale_temp_sibling(path)?;
    sync_parent_dir(path)
}

fn stage_live_entries(source: &SearchState, log: &mut Log) -> Result<(), VecDbError> {
    let mut batch: Vec<(String, Vec<f32>, Vec<Attribute>)> =
        Vec::with_capacity(COMPACTION_BATCH_SIZE);
    for slot in source.arena.live_slots() {
        let Some(key) = source.arena.key_of_slot(slot) else {
            continue;
        };
        batch.push((
            key.to_string(),
            source.arena.vector_values(slot),
            source
                .attrs
                .get(slot)
                .map(<[Attribute]>::to_vec)
                .unwrap_or_default(),
        ));
        if batch.len() == COMPACTION_BATCH_SIZE {
            flush_stage_batch(&mut batch, log)?;
        }
    }
    flush_stage_batch(&mut batch, log)
}

fn flush_stage_batch(
    batch: &mut Vec<(String, Vec<f32>, Vec<Attribute>)>,
    log: &mut Log,
) -> Result<(), VecDbError> {
    if batch.is_empty() {
        return Ok(());
    }
    let records: Vec<LogEntry<'_>> = batch
        .iter()
        .map(|(key, vector, attrs)| LogEntry::Add { key, vector, attrs })
        .collect();
    log.append_unsynced_for_staging(&records)?;
    batch.clear();
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::sync::Barrier;
    use std::thread;

    use tempfile::TempDir;

    use super::super::crc::crc32;
    use super::super::kernel::splitmix64;
    use super::super::lock::lock_path;
    use super::super::test_support;
    use super::*;

    const DIMS: usize = 16;
    const ADD_RECORD_LEN: u64 = 3 + 5 + (DIMS as u64) * 4 + 1 + 4;
    const TOMBSTONE_RECORD_LEN: u64 = 3 + 5 + 4;

    fn seeded_unit_vector(seed: u64, dims: usize) -> Vec<f32> {
        let mut state = seed;
        let mut values: Vec<f32> = (0..dims)
            .map(|_| {
                let unit = (splitmix64(&mut state) >> 40) as f32 / (1u64 << 24) as f32;
                unit * 2.0 - 1.0
            })
            .collect();
        let norm = values.iter().map(|value| value * value).sum::<f32>().sqrt();
        for value in &mut values {
            *value /= norm;
        }
        values
    }

    fn basis_vector(axis: usize) -> Vec<f32> {
        let mut values = vec![0.0; DIMS];
        values[axis] = 1.0;
        values
    }

    fn negated(values: &[f32]) -> Vec<f32> {
        values.iter().map(|value| -value).collect()
    }

    fn bulk_entries(start: usize, count: usize, seed: u64) -> Vec<(String, Vec<f32>)> {
        (start..start + count)
            .map(|index| {
                (
                    format!("key-{index}"),
                    seeded_unit_vector(seed + index as u64, DIMS),
                )
            })
            .collect()
    }

    fn bulk_add(db: &VecDb, entries: &[(String, Vec<f32>)]) -> Result<(), VecDbError> {
        let (keys, vectors): (Vec<String>, Vec<Vec<f32>>) = entries.iter().cloned().unzip();
        db.bulk_add(&keys, &vectors)
    }

    fn limit_params(limit: usize) -> SearchParams {
        SearchParams {
            limit: Some(limit),
            ..SearchParams::default()
        }
    }

    fn open_writer(path: &Path) -> VecDb {
        VecDb::open(path, DIMS).unwrap()
    }

    fn generation_of(path: &Path) -> [u8; 16] {
        fs::read(path).unwrap()[12..28].try_into().unwrap()
    }

    fn temp_sibling(path: &Path) -> PathBuf {
        PathBuf::from(format!("{}.tmp", path.display()))
    }

    fn snapshot_exists(path: &Path) -> bool {
        snapshot_path(path).exists()
    }

    fn set_mutations(db: &VecDb, value: usize) {
        let mut half = db.shared.writer_half();
        match &mut half.mode {
            WriterMode::Active(state) => state.mutations_since_snapshot = value,
            WriterMode::ReadOnly { .. } => panic!("expected a writer instance"),
        }
    }

    fn mutations(db: &VecDb) -> usize {
        let half = db.shared.writer_half();
        match &half.mode {
            WriterMode::Active(state) => state.mutations_since_snapshot,
            WriterMode::ReadOnly { .. } => panic!("expected a writer instance"),
        }
    }

    fn record(db: &VecDb, count: usize, now: Instant) -> Result<(), VecDbError> {
        let mut half = db.shared.writer_half();
        apply_policy(&db.shared, &mut half, count, now)
    }

    fn take_writer(db: &VecDb) -> WriterState {
        let mut half = db.shared.writer_half();
        take_writer_state(&mut half).unwrap()
    }

    fn is_degraded(db: &VecDb) -> bool {
        matches!(db.shared.writer_half().mode, WriterMode::ReadOnly { .. })
    }

    fn assert_own_nearest(db: &VecDb, key: &str, vector: &[f32]) {
        let matches = db.search(vector, &limit_params(1)).unwrap();
        assert_eq!(matches[0].key, key);
        assert!(matches[0].distance.abs() < 1.0e-3);
    }

    fn search_shapes(allowed: Vec<String>) -> Vec<SearchParams> {
        vec![
            SearchParams {
                limit: Some(8),
                ..SearchParams::default()
            },
            SearchParams {
                limit: Some(8),
                exact: true,
                ..SearchParams::default()
            },
            SearchParams {
                max_distance: Some(1.05),
                ..SearchParams::default()
            },
            SearchParams {
                max_distance: Some(1.05),
                exact: true,
                ..SearchParams::default()
            },
            SearchParams {
                limit: Some(4),
                max_distance: Some(1.2),
                ..SearchParams::default()
            },
            SearchParams {
                limit: Some(4),
                max_distance: Some(1.2),
                exact: true,
                ..SearchParams::default()
            },
            SearchParams {
                limit: Some(6),
                allowed_keys: Some(allowed.clone()),
                ..SearchParams::default()
            },
            SearchParams {
                limit: None,
                max_distance: Some(1.5),
                exact: true,
                allowed_keys: Some(allowed),
            },
        ]
    }

    #[test]
    fn lifecycle_round_trip_preserves_search_results() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let probe = seeded_unit_vector(777, DIMS);
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 150, 100)).unwrap();
        db.add("probe", &probe).unwrap();
        assert_eq!(db.len(), 151);
        assert!(!db.is_empty());
        assert!(db.contains("probe"));
        assert!(db.contains("key-42"));
        assert!(!db.contains("key-999"));
        assert_eq!(db.get("probe").unwrap(), probe);
        assert_eq!(db.get("key-7").unwrap(), seeded_unit_vector(107, DIMS));
        assert!(db.get("missing").is_none());
        let stats = db.stats().unwrap();
        assert_eq!(stats.live_count, 151);
        assert_eq!(stats.dead_count, 0);
        assert_eq!(stats.dims, DIMS);
        assert_eq!(stats.records_since_snapshot, 151);
        assert!(stats.log_bytes > 32);
        assert!(stats.approximate_memory_bytes > 151 * DIMS * 4);
        let allowed = vec![
            "probe".to_string(),
            "key-3".to_string(),
            "key-77".to_string(),
            "absent".to_string(),
        ];
        let queries = [probe.clone(), seeded_unit_vector(555, DIMS)];
        let shapes = search_shapes(allowed);
        let mut expected = Vec::new();
        for query in &queries {
            for shape in &shapes {
                expected.push(db.search(query, shape).unwrap());
            }
        }
        assert!(expected.iter().any(|matches| !matches.is_empty()));
        assert_eq!(db.search(&probe, &limit_params(1)).unwrap()[0].key, "probe");
        db.flush().unwrap();
        assert_eq!(db.stats().unwrap().records_since_snapshot, 0);
        drop(db);
        let read_only = VecDb::open_read_only(&path, DIMS).unwrap();
        let reopened = open_writer(&path);
        let mut index = 0;
        for query in &queries {
            for shape in &search_shapes(vec![
                "probe".to_string(),
                "key-3".to_string(),
                "key-77".to_string(),
                "absent".to_string(),
            ]) {
                assert_eq!(reopened.search(query, shape).unwrap(), expected[index]);
                assert_eq!(read_only.search(query, shape).unwrap(), expected[index]);
                index += 1;
            }
        }
        assert_eq!(reopened.len(), 151);
        assert_eq!(read_only.len(), 151);
    }

    #[test]
    fn search_parameter_validation() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 5, 10)).unwrap();
        let query = seeded_unit_vector(1, DIMS);
        assert!(matches!(
            db.search(&query, &SearchParams::default()),
            Err(VecDbError::UnboundedSearch)
        ));
        for bad_distance in [f32::NAN, f32::INFINITY, -0.5] {
            let params = SearchParams {
                limit: Some(3),
                max_distance: Some(bad_distance),
                ..SearchParams::default()
            };
            assert!(db.search(&query, &params).unwrap().is_empty());
        }
        assert!(matches!(
            db.search(&seeded_unit_vector(1, 8), &limit_params(3)),
            Err(VecDbError::DimensionMismatch {
                expected: DIMS,
                actual: 8
            })
        ));
        assert!(db.search(&query, &limit_params(0)).unwrap().is_empty());
        let empty_filter = SearchParams {
            limit: Some(3),
            allowed_keys: Some(Vec::new()),
            ..SearchParams::default()
        };
        assert!(db.search(&query, &empty_filter).unwrap().is_empty());
        let missing_filter = SearchParams {
            limit: Some(3),
            allowed_keys: Some(vec!["nope".to_string(), "nada".to_string()]),
            ..SearchParams::default()
        };
        assert!(db.search(&query, &missing_filter).unwrap().is_empty());
        let empty_db = open_writer(&dir.path().join("empty"));
        assert!(
            empty_db
                .search(&query, &limit_params(3))
                .unwrap()
                .is_empty()
        );
    }

    #[test]
    fn acknowledged_writes_survive_drop_without_flush() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        for index in 0..4 {
            db.add(
                &format!("solo-{index}"),
                &seeded_unit_vector(index as u64, DIMS),
            )
            .unwrap();
        }
        bulk_add(&db, &bulk_entries(0, 6, 40)).unwrap();
        drop(db);
        let reopened = open_writer(&path);
        assert_eq!(reopened.len(), 10);
        for index in 0..4u64 {
            assert_eq!(
                reopened.get(&format!("solo-{index}")).unwrap(),
                seeded_unit_vector(index, DIMS)
            );
        }
        assert_own_nearest(&reopened, "key-2", &seeded_unit_vector(42, DIMS));
        assert_own_nearest(&reopened, "solo-3", &seeded_unit_vector(3, DIMS));
    }

    #[test]
    fn log_copy_taken_mid_session_opens_with_all_acknowledged_writes() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let copy = dir.path().join("copy");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 6, 60)).unwrap();
        fs::copy(&path, &copy).unwrap();
        let copied = open_writer(&copy);
        assert_eq!(copied.len(), 6);
        for index in 0..6 {
            assert_eq!(
                copied.get(&format!("key-{index}")).unwrap(),
                seeded_unit_vector(60 + index as u64, DIMS)
            );
        }
        db.add("late", &seeded_unit_vector(999, DIMS)).unwrap();
        assert!(db.contains("late"));
        assert!(!copied.contains("late"));
    }

    #[test]
    fn torn_tail_garbage_is_truncated_and_data_survives() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 4, 20)).unwrap();
        drop(db);
        let clean_len = fs::metadata(&path).unwrap().len();
        let mut bytes = fs::read(&path).unwrap();
        bytes.extend_from_slice(&[0xFF; 41]);
        fs::write(&path, &bytes).unwrap();
        let reopened = open_writer(&path);
        assert_eq!(reopened.len(), 4);
        assert_own_nearest(&reopened, "key-1", &seeded_unit_vector(21, DIMS));
        drop(reopened);
        assert_eq!(fs::metadata(&path).unwrap().len(), clean_len);
    }

    #[test]
    fn torn_tail_partial_record_is_truncated_and_data_survives() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 4, 30)).unwrap();
        db.flush().unwrap();
        drop(db);
        let clean_len = fs::metadata(&path).unwrap().len();
        let mut bytes = fs::read(&path).unwrap();
        bytes.extend_from_slice(&[1, 6, 0, b'a', b'b']);
        fs::write(&path, &bytes).unwrap();
        let reopened = open_writer(&path);
        assert_eq!(reopened.len(), 4);
        assert!(reopened.contains("key-3"));
        drop(reopened);
        assert_eq!(fs::metadata(&path).unwrap().len(), clean_len);
    }

    fn assert_corrupt_open_preserves(path: &Path) {
        let log_bytes = fs::read(path).unwrap();
        let snapshot_bytes = snapshot_exists(path).then(|| fs::read(snapshot_path(path)).unwrap());
        assert!(matches!(
            VecDb::open(path, DIMS),
            Err(VecDbError::Corrupt(_))
        ));
        assert!(matches!(
            VecDb::open_read_only(path, DIMS),
            Err(VecDbError::Corrupt(_))
        ));
        assert_eq!(fs::read(path).unwrap(), log_bytes);
        assert_eq!(
            snapshot_exists(path).then(|| fs::read(snapshot_path(path)).unwrap()),
            snapshot_bytes
        );
    }

    #[test]
    fn externally_shortened_log_below_the_snapshot_frontier_is_preserved() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        db.add("first", &seeded_unit_vector(1, DIMS)).unwrap();
        let boundary = db.stats().unwrap().log_bytes;
        db.add("second", &seeded_unit_vector(2, DIMS)).unwrap();
        db.flush().unwrap();
        drop(db);
        let clean = fs::read(&path).unwrap();
        fs::write(&path, &clean[..boundary as usize]).unwrap();
        assert_corrupt_open_preserves(&path);
        fs::write(&path, &clean).unwrap();
        let recovered = open_writer(&path);
        assert_eq!(recovered.len(), 2);
        assert!(recovered.contains("second"));
    }

    #[test]
    fn read_only_replay_adopts_records_a_foreign_writer_appended_after_capture() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 2, 500)).unwrap();
        db.flush().unwrap();
        drop(db);
        let mut captured_for_read_only = reopen_log(&path, DIMS).unwrap();
        let mut captured_for_writer = reopen_log(&path, DIMS).unwrap();
        let stale_end = captured_for_read_only.current_end_offset();
        let racer = open_writer(&path);
        bulk_add(&racer, &bulk_entries(2, 2, 500)).unwrap();
        racer.flush().unwrap();
        drop(racer);
        let grown_end = fs::metadata(&path).unwrap().len();
        assert!(grown_end > stale_end);
        let replayed = replay(&mut captured_for_read_only, DIMS, ReplayMode::ReadOnly).unwrap();
        assert_eq!(replayed.total_records, 4);
        assert_eq!(replayed.arena.live_count(), 4);
        assert_eq!(replayed.recoverable_end, grown_end);
        assert!(replayed.graph.is_some());
        for index in 0..4 {
            assert!(
                replayed
                    .arena
                    .slot_of_key(&format!("key-{index}"))
                    .is_some()
            );
        }
        assert!(matches!(
            replay(&mut captured_for_writer, DIMS, ReplayMode::Writer),
            Err(VecDbError::Corrupt(_))
        ));
    }

    #[test]
    fn read_only_replay_stops_at_the_snapshot_frontier_not_the_file_length() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 2, 700)).unwrap();
        db.flush().unwrap();
        drop(db);
        let mut captured_for_read_only = reopen_log(&path, DIMS).unwrap();
        let stale_end = captured_for_read_only.current_end_offset();
        let racer = open_writer(&path);
        bulk_add(&racer, &bulk_entries(2, 2, 700)).unwrap();
        racer.flush().unwrap();
        let covered_end = fs::metadata(&path).unwrap().len();
        bulk_add(&racer, &bulk_entries(4, 2, 700)).unwrap();
        drop(racer);
        let grown_end = fs::metadata(&path).unwrap().len();
        assert!(covered_end > stale_end);
        assert!(grown_end > covered_end);
        assert_eq!(
            load_snapshot(&path, generation_of(&path))
                .unwrap()
                .covered_log_offset,
            covered_end
        );
        let replayed = replay(&mut captured_for_read_only, DIMS, ReplayMode::ReadOnly).unwrap();
        assert_eq!(replayed.total_records, 4);
        assert_eq!(replayed.arena.live_count(), 4);
        assert_eq!(replayed.recoverable_end, covered_end);
        assert_eq!(replayed.tail_records, 0);
        assert!(replayed.graph.is_some());
        for index in 0..4 {
            assert!(
                replayed
                    .arena
                    .slot_of_key(&format!("key-{index}"))
                    .is_some()
            );
        }
        for index in 4..6 {
            assert!(
                replayed
                    .arena
                    .slot_of_key(&format!("key-{index}"))
                    .is_none()
            );
        }
    }

    #[test]
    fn shortened_log_copy_beside_a_newer_snapshot_is_corrupt_in_both_modes() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        db.add("first", &seeded_unit_vector(1, DIMS)).unwrap();
        let boundary = db.stats().unwrap().log_bytes;
        db.add("second", &seeded_unit_vector(2, DIMS)).unwrap();
        db.flush().unwrap();
        drop(db);
        let stale = dir.path().join("stale");
        let full = fs::read(&path).unwrap();
        fs::write(&stale, &full[..boundary as usize]).unwrap();
        fs::copy(snapshot_path(&path), snapshot_path(&stale)).unwrap();
        assert_corrupt_open_preserves(&stale);
    }

    #[test]
    fn mid_log_corruption_below_the_snapshot_frontier_is_preserved() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 5, 300)).unwrap();
        db.flush().unwrap();
        drop(db);
        let clean = fs::read(&path).unwrap();
        let mut bytes = clean.clone();
        bytes[HEADER_LEN + ADD_RECORD_LEN as usize + 10] ^= 0x01;
        fs::write(&path, &bytes).unwrap();
        assert_corrupt_open_preserves(&path);
        fs::write(&path, &clean).unwrap();
        let recovered = open_writer(&path);
        assert_eq!(recovered.len(), 5);
        assert_own_nearest(&recovered, "key-1", &seeded_unit_vector(301, DIMS));
    }

    #[test]
    fn corruption_at_the_first_record_with_a_snapshot_is_preserved() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 3, 420)).unwrap();
        db.flush().unwrap();
        drop(db);
        let mut bytes = fs::read(&path).unwrap();
        bytes[HEADER_LEN + 10] ^= 0x01;
        fs::write(&path, &bytes).unwrap();
        assert_corrupt_open_preserves(&path);
    }

    #[test]
    fn mid_log_corruption_in_the_unsnapshotted_tail_is_preserved() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 4, 320)).unwrap();
        drop(db);
        assert!(!snapshot_exists(&path));
        let clean = fs::read(&path).unwrap();
        let mut bytes = clean.clone();
        bytes[HEADER_LEN + ADD_RECORD_LEN as usize + 10] ^= 0x01;
        fs::write(&path, &bytes).unwrap();
        assert_corrupt_open_preserves(&path);
        assert!(!snapshot_exists(&path));
        fs::write(&path, &clean).unwrap();
        assert_eq!(open_writer(&path).len(), 4);
    }

    #[test]
    fn mid_log_corruption_above_the_snapshot_frontier_is_preserved() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 2, 340)).unwrap();
        db.flush().unwrap();
        bulk_add(&db, &bulk_entries(2, 2, 340)).unwrap();
        drop(db);
        let mut bytes = fs::read(&path).unwrap();
        bytes[HEADER_LEN + 2 * ADD_RECORD_LEN as usize + 10] ^= 0x01;
        fs::write(&path, &bytes).unwrap();
        assert_corrupt_open_preserves(&path);
    }

    #[test]
    fn unknown_record_type_mid_log_with_valid_records_after_is_preserved() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 3, 360)).unwrap();
        drop(db);
        let clean = fs::read(&path).unwrap();
        let first_end = HEADER_LEN + ADD_RECORD_LEN as usize;
        let mut bytes = clean[..first_end].to_vec();
        bytes.extend_from_slice(&[3, 5, 0, b'j', b'u', b'n', b'k', b'y', 9, 9, 9, 9]);
        bytes.extend_from_slice(&clean[first_end..]);
        fs::write(&path, &bytes).unwrap();
        assert_corrupt_open_preserves(&path);
    }

    #[test]
    fn damaged_final_record_truncates_even_with_a_snapshot_below_the_stop() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 3, 380)).unwrap();
        db.flush().unwrap();
        db.add("key-3", &seeded_unit_vector(383, DIMS)).unwrap();
        drop(db);
        let mut bytes = fs::read(&path).unwrap();
        let last_start = bytes.len() - ADD_RECORD_LEN as usize;
        bytes[last_start + 10] ^= 0x01;
        fs::write(&path, &bytes).unwrap();
        let read_only = VecDb::open_read_only(&path, DIMS).unwrap();
        assert_eq!(read_only.len(), 3);
        assert!(!read_only.contains("key-3"));
        drop(read_only);
        assert_eq!(fs::read(&path).unwrap(), bytes);
        let reopened = open_writer(&path);
        assert_eq!(reopened.len(), 3);
        assert!(!reopened.contains("key-3"));
        assert_own_nearest(&reopened, "key-2", &seeded_unit_vector(382, DIMS));
        drop(reopened);
        assert_eq!(fs::metadata(&path).unwrap().len(), last_start as u64);
    }

    #[test]
    fn future_format_version_is_rejected_with_the_file_preserved() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 3, 400)).unwrap();
        db.flush().unwrap();
        drop(db);
        let clean = fs::read(&path).unwrap();
        let mut bytes = clean.clone();
        bytes[4..6].copy_from_slice(&2u16.to_le_bytes());
        let crc = crc32(&bytes[0..28]);
        bytes[28..32].copy_from_slice(&crc.to_le_bytes());
        fs::write(&path, &bytes).unwrap();
        let snapshot_bytes = fs::read(snapshot_path(&path)).unwrap();
        assert!(matches!(
            VecDb::open(&path, DIMS),
            Err(VecDbError::Corrupt(message)) if message.contains("version")
        ));
        assert!(matches!(
            VecDb::open_read_only(&path, DIMS),
            Err(VecDbError::Corrupt(message)) if message.contains("version")
        ));
        assert_eq!(fs::read(&path).unwrap(), bytes);
        assert_eq!(fs::read(snapshot_path(&path)).unwrap(), snapshot_bytes);
        fs::write(&path, &clean).unwrap();
        assert_eq!(open_writer(&path).len(), 3);
    }

    #[test]
    fn deleted_snapshot_recovers_by_rebuild() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 8, 50)).unwrap();
        db.flush().unwrap();
        drop(db);
        fs::remove_file(snapshot_path(&path)).unwrap();
        let reopened = open_writer(&path);
        assert_eq!(reopened.len(), 8);
        assert_own_nearest(&reopened, "key-5", &seeded_unit_vector(55, DIMS));
        assert!(snapshot_exists(&path));
    }

    #[test]
    fn snapshot_from_an_older_generation_is_discarded() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 3, 70)).unwrap();
        db.flush().unwrap();
        drop(db);
        let stale_snapshot = fs::read(snapshot_path(&path)).unwrap();
        fs::remove_file(&path).unwrap();
        let db = open_writer(&path);
        assert!(db.is_empty());
        db.add("fresh", &seeded_unit_vector(1, DIMS)).unwrap();
        drop(db);
        fs::write(snapshot_path(&path), &stale_snapshot).unwrap();
        let reopened = open_writer(&path);
        assert_eq!(reopened.len(), 1);
        assert!(reopened.contains("fresh"));
        assert!(!reopened.contains("key-0"));
        assert_own_nearest(&reopened, "fresh", &seeded_unit_vector(1, DIMS));
    }

    #[test]
    fn corrupted_snapshot_bytes_are_discarded() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 5, 90)).unwrap();
        db.flush().unwrap();
        drop(db);
        let mut bytes = fs::read(snapshot_path(&path)).unwrap();
        bytes[20] ^= 0x5A;
        fs::write(snapshot_path(&path), &bytes).unwrap();
        let reopened = open_writer(&path);
        assert_eq!(reopened.len(), 5);
        assert_own_nearest(&reopened, "key-4", &seeded_unit_vector(94, DIMS));
    }

    #[test]
    fn stale_compaction_temp_files_are_removed_at_open() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 5, 110)).unwrap();
        db.flush().unwrap();
        drop(db);
        fs::write(temp_sibling(&path), [0xAB; 100]).unwrap();
        let db = open_writer(&path);
        assert!(!temp_sibling(&path).exists());
        assert_eq!(db.len(), 5);
        drop(db);
        fs::copy(&path, temp_sibling(&path)).unwrap();
        let db = open_writer(&path);
        assert!(!temp_sibling(&path).exists());
        assert_eq!(db.len(), 5);
        assert!(db.contains("key-2"));
    }

    #[test]
    fn second_open_joins_the_live_instance() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 3, 120)).unwrap();
        let joined = VecDb::open(&path, DIMS).unwrap();
        assert!(Arc::ptr_eq(&db.shared, &joined.shared));
        assert_eq!(joined.len(), 3);
        joined.add("joined", &seeded_unit_vector(9, DIMS)).unwrap();
        assert!(db.contains("joined"));
        assert!(matches!(
            WriterLock::acquire(&path),
            Err(VecDbError::Locked(_))
        ));
        drop(db);
        drop(joined);
        let reopened = open_writer(&path);
        assert_eq!(reopened.len(), 4);
        assert!(reopened.contains("joined"));
    }

    #[test]
    fn open_handles_alias_one_live_instance() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let first = open_writer(&path);
        let second = VecDb::open(&path, DIMS).unwrap();
        assert!(Arc::ptr_eq(&first.shared, &second.shared));
        let via_first = seeded_unit_vector(11, DIMS);
        let via_second = seeded_unit_vector(22, DIMS);
        first.add("via-first", &via_first).unwrap();
        assert!(second.contains("via-first"));
        assert_eq!(second.get("via-first").unwrap(), via_first);
        assert_eq!(
            second.search(&via_first, &limit_params(1)).unwrap()[0].key,
            "via-first"
        );
        second.add("via-second", &via_second).unwrap();
        assert!(first.contains("via-second"));
        assert_eq!(first.len(), 2);
        assert!(matches!(
            VecDb::open(&path, DIMS + 8),
            Err(VecDbError::DimensionMismatch {
                expected,
                actual
            }) if expected == DIMS + 8 && actual == DIMS
        ));
    }

    #[test]
    fn dotted_and_plain_paths_share_one_instance() {
        let dir = TempDir::new().unwrap();
        let subdir = dir.path().join("indexes");
        fs::create_dir(&subdir).unwrap();
        let plain = subdir.join("db");
        let dotted = subdir.join("..").join("indexes").join("db");
        let first = VecDb::open(&plain, DIMS).unwrap();
        let second = VecDb::open(&dotted, DIMS).unwrap();
        assert!(Arc::ptr_eq(&first.shared, &second.shared));
        let vector = seeded_unit_vector(5, DIMS);
        first.add("shared", &vector).unwrap();
        assert!(second.contains("shared"));
        assert_eq!(second.get("shared").unwrap(), vector);
    }

    #[test]
    fn dropping_every_handle_releases_the_instance() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let first = open_writer(&path);
        let second = VecDb::open(&path, DIMS).unwrap();
        first.add("kept", &seeded_unit_vector(3, DIMS)).unwrap();
        drop(first);
        assert!(second.contains("kept"));
        second
            .add("still-open", &seeded_unit_vector(4, DIMS))
            .unwrap();
        drop(second);
        let key = registry_key_for(&path).unwrap();
        assert!(!registry().contains_key(&key));
        let reopened = open_writer(&path);
        assert_eq!(reopened.len(), 2);
        assert!(reopened.contains("kept"));
        assert!(reopened.contains("still-open"));
        let again = VecDb::open(&path, DIMS).unwrap();
        assert!(Arc::ptr_eq(&reopened.shared, &again.shared));
    }

    #[test]
    fn racing_open_and_drop_churn_never_reports_locked() {
        const CYCLES: usize = 300;
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        open_writer(&path)
            .add("seed", &seeded_unit_vector(1, DIMS))
            .unwrap();
        let barrier = Arc::new(Barrier::new(2));
        let churners: Vec<_> = (0..2)
            .map(|_| {
                let path = path.clone();
                let barrier = Arc::clone(&barrier);
                thread::spawn(move || {
                    barrier.wait();
                    for _ in 0..CYCLES {
                        let db = VecDb::open(&path, DIMS).unwrap();
                        assert!(db.contains("seed"));
                        drop(db);
                    }
                })
            })
            .collect();
        for churner in churners {
            churner.join().unwrap();
        }
        let reopened = open_writer(&path);
        assert!(reopened.contains("seed"));
    }

    #[test]
    fn handoff_helper_joins_a_live_slot() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        let key = registry_key_for(&path).unwrap();
        let slot = existing_path_slot(&key).unwrap();
        match wait_for_teardown_handoff(&slot, &key) {
            SlotHandoff::Join(shared) => assert!(Arc::ptr_eq(&shared, &db.shared)),
            SlotHandoff::Released(_) => panic!("expected a join, saw a released slot"),
            SlotHandoff::Expired(_) => panic!("expected a join, saw an expired wait"),
        }
    }

    #[test]
    fn handoff_helper_proceeds_on_a_retired_slot() {
        let slot = Arc::new(Mutex::new(PathSlot { live: None }));
        match wait_for_teardown_handoff(&slot, Path::new("retired")) {
            SlotHandoff::Released(guard) => assert!(guard.live.is_none()),
            SlotHandoff::Join(_) => panic!("expected a release, saw a join"),
            SlotHandoff::Expired(_) => panic!("expected a release, saw an expired wait"),
        }
    }

    #[test]
    fn handoff_helper_caps_out_on_a_leaked_dead_marker() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        let weak = Arc::downgrade(&db.shared);
        drop(db);
        assert_eq!(weak.strong_count(), 0);
        let slot = Arc::new(Mutex::new(PathSlot { live: Some(weak) }));
        let started = Instant::now();
        let outcome = wait_for_teardown_handoff(&slot, &path);
        let waited = started.elapsed();
        match outcome {
            SlotHandoff::Expired(guard) => assert!(!guard.holds_live()),
            SlotHandoff::Join(_) => panic!("expected an expired wait, saw a join"),
            SlotHandoff::Released(_) => panic!("expected an expired wait, saw a release"),
        }
        assert!(waited >= HANDOFF_WAIT_PARK * HANDOFF_WAIT_ROUNDS);
        assert!(waited < HANDOFF_WAIT_PARK * HANDOFF_WAIT_ROUNDS * 2);
    }

    fn closed_instance(path: &Path) -> Arc<Shared> {
        let db = open_writer(path);
        db.add("doomed", &seeded_unit_vector(77, DIMS)).unwrap();
        let shared = Arc::clone(&db.shared);
        db.delete().unwrap();
        assert!(shared.is_closed());
        shared
    }

    fn plant_closed_marker(key: &Path, closed: &Arc<Shared>) -> Arc<Mutex<PathSlot>> {
        let slot = path_slot(key);
        lock_slot(&slot).live = Some(Arc::downgrade(closed));
        slot
    }

    #[test]
    fn handoff_helper_keeps_waiting_on_a_closed_instance() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let closed = closed_instance(&path);
        let slot = Arc::new(Mutex::new(PathSlot {
            live: Some(Arc::downgrade(&closed)),
        }));
        let started = Instant::now();
        let outcome = wait_for_teardown_handoff(&slot, &path);
        let waited = started.elapsed();
        match outcome {
            SlotHandoff::Expired(guard) => assert!(guard.holds_live()),
            SlotHandoff::Join(_) => panic!("expected an expired wait, saw a join"),
            SlotHandoff::Released(_) => panic!("expected an expired wait, saw a release"),
        }
        assert!(waited >= HANDOFF_WAIT_PARK * HANDOFF_CLOSE_WAIT_ROUNDS);
    }

    #[test]
    fn open_waits_out_a_planted_closed_marker_and_builds_a_usable_handle() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let closed = closed_instance(&path);
        let key = registry_key_for(&path).unwrap();
        let slot = plant_closed_marker(&key, &closed);
        let reopened = VecDb::open(&path, DIMS).unwrap();
        assert!(!Arc::ptr_eq(&reopened.shared, &closed));
        reopened
            .add("fresh", &seeded_unit_vector(78, DIMS))
            .unwrap();
        assert_eq!(reopened.len(), 1);
        assert!(lock_slot(&slot).holds_live());
    }

    #[test]
    fn purge_waits_out_a_planted_closed_marker_and_stays_ok() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let closed = closed_instance(&path);
        let key = registry_key_for(&path).unwrap();
        let slot = plant_closed_marker(&key, &closed);
        VecDb::purge(&path).unwrap();
        assert!(!path.exists());
        assert!(!snapshot_exists(&path));
        drop(closed);
        assert!(lock_slot(&slot).live.is_none());
        let fresh = open_writer(&path);
        fresh.add("anew", &seeded_unit_vector(79, DIMS)).unwrap();
        assert_eq!(fresh.len(), 1);
    }

    #[test]
    fn open_racing_a_parked_close_always_gets_a_usable_handle() {
        for _ in 0..5 {
            let dir = TempDir::new().unwrap();
            let path = dir.path().join("db");
            let db = open_writer(&path);
            db.add("doomed", &seeded_unit_vector(80, DIMS)).unwrap();
            let key = registry_key_for(&path).unwrap();
            let slot = existing_path_slot(&key).unwrap();
            let frozen = lock_slot(&slot);
            let deleter = thread::spawn(move || db.delete());
            let deadline = Instant::now() + Duration::from_secs(30);
            while path.exists() {
                assert!(Instant::now() < deadline);
                thread::yield_now();
            }
            let opener = {
                let path = path.clone();
                thread::spawn(move || VecDb::open(&path, DIMS))
            };
            thread::sleep(Duration::from_millis(5));
            drop(frozen);
            deleter.join().unwrap().unwrap();
            let reopened = opener.join().unwrap().unwrap();
            reopened
                .add("fresh", &seeded_unit_vector(81, DIMS))
                .unwrap();
            assert_eq!(reopened.len(), 1);
        }
    }

    #[test]
    fn dropping_the_last_handle_retires_the_marker_before_eviction() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        let key = registry_key_for(&path).unwrap();
        let slot = existing_path_slot(&key).unwrap();
        assert!(lock_slot(&slot).holds_live());
        drop(db);
        assert!(lock_slot(&slot).live.is_none());
        assert!(registry().contains_key(&key));
        drop(slot);
        remove_path_slot_if_unused(&key);
        assert!(!registry().contains_key(&key));
    }

    #[test]
    fn a_stalled_open_on_one_path_blocks_neither_other_paths_nor_forks_its_own() {
        let dir = TempDir::new().unwrap();
        let stalled_path = dir.path().join("stalled");
        let other_path = dir.path().join("other");
        let key = registry_key_for(&stalled_path).unwrap();
        let slot = path_slot(&key);
        let build_in_progress = lock_slot(&slot);
        let stalled_openers: Vec<_> = (0..2)
            .map(|_| {
                let path = stalled_path.clone();
                thread::spawn(move || VecDb::open(&path, DIMS).unwrap())
            })
            .collect();
        let other = VecDb::open(&other_path, DIMS).unwrap();
        other.add("other", &seeded_unit_vector(1, DIMS)).unwrap();
        assert_eq!(other.len(), 1);
        drop(build_in_progress);
        let handles: Vec<VecDb> = stalled_openers
            .into_iter()
            .map(|opener| opener.join().unwrap())
            .collect();
        assert!(Arc::ptr_eq(&handles[0].shared, &handles[1].shared));
        assert!(!Arc::ptr_eq(&handles[0].shared, &other.shared));
        handles[0]
            .add("stalled", &seeded_unit_vector(2, DIMS))
            .unwrap();
        assert!(handles[1].contains("stalled"));
        assert!(!other.contains("stalled"));
    }

    #[test]
    fn failed_open_leaves_no_registry_residue() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("dir-in-the-way");
        fs::create_dir(&path).unwrap();
        let key = registry_key_for(&path).unwrap();
        assert!(matches!(
            VecDb::open(&path, DIMS),
            Err(VecDbError::Io { .. })
        ));
        assert!(!registry().contains_key(&key));
    }

    #[test]
    fn writer_stays_locked_across_a_completed_compaction() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 120, 340)).unwrap();
        let generation_before = generation_of(&path);
        let removals: Vec<String> = (0..64).map(|index| format!("key-{index}")).collect();
        assert_eq!(db.bulk_remove(&removals).unwrap(), 64);
        assert_ne!(generation_of(&path), generation_before);
        assert_eq!(db.stats().unwrap().dead_count, 0);
        assert!(matches!(
            WriterLock::acquire(&path),
            Err(VecDbError::Locked(_))
        ));
        db.add("post", &seeded_unit_vector(7, DIMS)).unwrap();
        drop(db);
        let reopened = open_writer(&path);
        assert_eq!(reopened.len(), 57);
        assert!(reopened.contains("post"));
        assert!(!reopened.contains("key-0"));
    }

    #[test]
    fn stale_lock_file_with_garbage_bytes_is_reused_at_open() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        fs::write(lock_path(&path), [0xAB; 24]).unwrap();
        let db = open_writer(&path);
        db.add("fresh", &seeded_unit_vector(3, DIMS)).unwrap();
        assert!(matches!(
            WriterLock::acquire(&path),
            Err(VecDbError::Locked(_))
        ));
        drop(db);
        let reopened = open_writer(&path);
        assert_eq!(reopened.len(), 1);
        assert!(reopened.contains("fresh"));
    }

    #[test]
    fn read_only_open_aliases_a_live_writer() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 3, 130)).unwrap();
        let read_only = VecDb::open_read_only(&path, DIMS).unwrap();
        assert!(Arc::ptr_eq(&db.shared, &read_only.shared));
        assert_eq!(read_only.len(), 3);
        assert!(read_only.contains("key-1"));
        let later = seeded_unit_vector(9, DIMS);
        db.add("later", &later).unwrap();
        assert!(read_only.contains("later"));
        assert_eq!(read_only.get("later").unwrap(), later);
        assert_own_nearest(&read_only, "later", &later);
        assert!(matches!(
            read_only.add("x", &later),
            Err(VecDbError::ReadOnly)
        ));
        assert!(matches!(
            read_only.remove("later"),
            Err(VecDbError::ReadOnly)
        ));
        assert!(matches!(
            read_only.bulk_remove(&["later".to_string()]),
            Err(VecDbError::ReadOnly)
        ));
        assert!(matches!(read_only.flush(), Err(VecDbError::ReadOnly)));
        assert!(matches!(read_only.reset(), Err(VecDbError::ReadOnly)));
        let another = VecDb::open_read_only(&path, DIMS).unwrap();
        assert!(matches!(another.delete(), Err(VecDbError::ReadOnly)));
        assert!(db.contains("later"));
        assert!(path.exists());
    }

    #[test]
    fn read_only_open_of_missing_file_is_empty() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("absent");
        let db = VecDb::open_read_only(&path, DIMS).unwrap();
        assert_eq!(db.len(), 0);
        assert!(db.is_empty());
        assert!(!db.contains("anything"));
        assert!(db.get("anything").is_none());
        assert!(
            db.search(&seeded_unit_vector(1, DIMS), &limit_params(3))
                .unwrap()
                .is_empty()
        );
        assert_eq!(
            db.stats().unwrap(),
            Stats {
                live_count: 0,
                dead_count: 0,
                dims: DIMS,
                log_bytes: 0,
                records_since_snapshot: 0,
                approximate_memory_bytes: 0,
            }
        );
        assert!(!path.exists());
        assert!(!snapshot_exists(&path));
        assert!(!lock_path(&path).exists());
    }

    #[test]
    fn read_only_instance_rejects_writes() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        db.add("kept", &seeded_unit_vector(3, DIMS)).unwrap();
        drop(db);
        let read_only = VecDb::open_read_only(&path, DIMS).unwrap();
        let vector = seeded_unit_vector(4, DIMS);
        assert!(matches!(
            read_only.add("x", &vector),
            Err(VecDbError::ReadOnly)
        ));
        assert!(matches!(
            bulk_add(&read_only, &bulk_entries(0, 2, 5)),
            Err(VecDbError::ReadOnly)
        ));
        assert!(matches!(
            bulk_add(&read_only, &[]),
            Err(VecDbError::ReadOnly)
        ));
        assert!(matches!(
            read_only.remove("kept"),
            Err(VecDbError::ReadOnly)
        ));
        assert!(matches!(
            read_only.bulk_remove(&["kept".to_string()]),
            Err(VecDbError::ReadOnly)
        ));
        assert!(matches!(read_only.flush(), Err(VecDbError::ReadOnly)));
        assert!(matches!(read_only.reset(), Err(VecDbError::ReadOnly)));
        assert!(read_only.contains("kept"));
        assert!(matches!(read_only.delete(), Err(VecDbError::ReadOnly)));
        assert!(path.exists());
    }

    #[test]
    fn standalone_read_only_stays_point_in_time() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 100, 140)).unwrap();
        drop(db);
        let snapshot_view = VecDb::open_read_only(&path, DIMS).unwrap();
        assert_eq!(snapshot_view.len(), 100);
        let db = open_writer(&path);
        assert!(!Arc::ptr_eq(&snapshot_view.shared, &db.shared));
        let generation_before = generation_of(&path);
        for index in 0..32 {
            assert!(db.remove(&format!("key-{index}")).unwrap());
        }
        assert_ne!(generation_of(&path), generation_before);
        assert_eq!(db.len(), 68);
        assert_eq!(db.stats().unwrap().dead_count, 0);
        db.add("fresh", &seeded_unit_vector(7, DIMS)).unwrap();
        assert_own_nearest(&db, "key-50", &seeded_unit_vector(190, DIMS));
        assert_eq!(snapshot_view.len(), 100);
        assert!(snapshot_view.contains("key-5"));
        assert!(!snapshot_view.contains("fresh"));
        assert_own_nearest(&snapshot_view, "key-5", &seeded_unit_vector(145, DIMS));
        let live_view = VecDb::open_read_only(&path, DIMS).unwrap();
        assert!(Arc::ptr_eq(&live_view.shared, &db.shared));
        assert!(live_view.contains("fresh"));
        drop(db);
        let fresh_view = VecDb::open_read_only(&path, DIMS).unwrap();
        assert_eq!(fresh_view.len(), 69);
        assert!(!fresh_view.contains("key-5"));
        assert!(fresh_view.contains("fresh"));
    }

    #[test]
    fn upsert_changes_search_position_across_reopen() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        db.add("near", &basis_vector(0)).unwrap();
        for axis in 1..11 {
            db.add(&format!("other-{axis}"), &basis_vector(axis))
                .unwrap();
        }
        let query = basis_vector(0);
        assert_own_nearest(&db, "near", &query);
        db.add("near", &negated(&basis_vector(0))).unwrap();
        assert_eq!(db.len(), 11);
        assert_eq!(db.get("near").unwrap(), negated(&basis_vector(0)));
        let checks = |db: &VecDb| {
            assert_ne!(db.search(&query, &limit_params(1)).unwrap()[0].key, "near");
            let exact = SearchParams {
                limit: Some(1),
                exact: true,
                ..SearchParams::default()
            };
            assert_ne!(db.search(&query, &exact).unwrap()[0].key, "near");
            let threshold = SearchParams {
                max_distance: Some(1.5),
                ..SearchParams::default()
            };
            let within = db.search(&query, &threshold).unwrap();
            assert_eq!(within.len(), 10);
            assert!(within.iter().all(|found| found.key != "near"));
        };
        checks(&db);
        drop(db);
        let reopened = open_writer(&path);
        assert_eq!(reopened.get("near").unwrap(), negated(&basis_vector(0)));
        checks(&reopened);
    }

    #[test]
    fn removed_keys_are_hidden_everywhere_and_can_be_readded() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        for axis in 0..10 {
            db.add(&format!("key-{axis}"), &basis_vector(axis)).unwrap();
        }
        let query = basis_vector(4);
        assert_own_nearest(&db, "key-4", &query);
        assert!(db.remove("key-4").unwrap());
        assert!(!db.remove("key-4").unwrap());
        assert_eq!(db.len(), 9);
        assert!(!db.contains("key-4"));
        assert!(db.get("key-4").is_none());
        assert_eq!(db.stats().unwrap().dead_count, 2);
        assert_ne!(db.search(&query, &limit_params(1)).unwrap()[0].key, "key-4");
        let exact_all = SearchParams {
            limit: Some(10),
            exact: true,
            ..SearchParams::default()
        };
        let exact = db.search(&query, &exact_all).unwrap();
        assert_eq!(exact.len(), 9);
        assert!(exact.iter().all(|found| found.key != "key-4"));
        let threshold = SearchParams {
            max_distance: Some(0.5),
            ..SearchParams::default()
        };
        assert!(db.search(&query, &threshold).unwrap().is_empty());
        let filtered = SearchParams {
            limit: Some(5),
            allowed_keys: Some(vec!["key-4".to_string()]),
            ..SearchParams::default()
        };
        assert!(db.search(&query, &filtered).unwrap().is_empty());
        db.add("key-4", &basis_vector(4)).unwrap();
        assert_eq!(db.len(), 10);
        assert_own_nearest(&db, "key-4", &query);
        drop(db);
        let reopened = open_writer(&path);
        assert_eq!(reopened.len(), 10);
        assert_own_nearest(&reopened, "key-4", &query);
    }

    #[test]
    fn bulk_remove_counts_only_present_keys_and_absent_remove_does_no_io() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 5, 150)).unwrap();
        let log_bytes = db.stats().unwrap().log_bytes;
        assert!(!db.remove("missing").unwrap());
        assert_eq!(db.stats().unwrap().log_bytes, log_bytes);
        let removals = vec![
            "key-1".to_string(),
            "key-1".to_string(),
            "key-3".to_string(),
            "nope".to_string(),
        ];
        assert_eq!(db.bulk_remove(&removals).unwrap(), 2);
        assert_eq!(db.len(), 3);
        assert!(!db.contains("key-1"));
        assert!(!db.contains("key-3"));
        assert_eq!(
            db.stats().unwrap().log_bytes,
            log_bytes + 2 * TOMBSTONE_RECORD_LEN
        );
        assert_eq!(db.bulk_remove(&[]).unwrap(), 0);
        bulk_add(&db, &[]).unwrap();
        assert_eq!(
            db.stats().unwrap().log_bytes,
            log_bytes + 2 * TOMBSTONE_RECORD_LEN
        );
    }

    #[test]
    fn quiet_gap_snapshot_needs_a_thousand_mutations() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        db.add("seed", &seeded_unit_vector(1, DIMS)).unwrap();
        set_mutations(&db, 998);
        record(&db, 1, Instant::now() + Duration::from_secs(30)).unwrap();
        assert_eq!(mutations(&db), 999);
        assert!(!snapshot_exists(&path));
        record(&db, 1, Instant::now() + Duration::from_secs(60)).unwrap();
        assert_eq!(mutations(&db), 0);
        assert!(snapshot_exists(&path));
    }

    #[test]
    fn thousand_mutations_without_quiet_gap_do_not_snapshot() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        db.add("seed", &seeded_unit_vector(1, DIMS)).unwrap();
        set_mutations(&db, 999);
        record(&db, 1, Instant::now()).unwrap();
        assert_eq!(mutations(&db), 1000);
        assert!(!snapshot_exists(&path));
    }

    #[test]
    fn hard_cap_snapshots_regardless_of_gap() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        db.add("seed", &seeded_unit_vector(1, DIMS)).unwrap();
        set_mutations(&db, 4999);
        record(&db, 1, Instant::now()).unwrap();
        assert_eq!(mutations(&db), 0);
        assert!(snapshot_exists(&path));
    }

    #[test]
    fn flush_snapshots_pending_mutations_and_resets() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 2, 160)).unwrap();
        assert!(!snapshot_exists(&path));
        assert_eq!(db.stats().unwrap().records_since_snapshot, 2);
        db.flush().unwrap();
        assert!(snapshot_exists(&path));
        assert_eq!(db.stats().unwrap().records_since_snapshot, 0);
        fs::remove_file(snapshot_path(&path)).unwrap();
        db.flush().unwrap();
        assert!(!snapshot_exists(&path));
    }

    #[test]
    fn open_after_tail_replay_writes_a_fresh_snapshot() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 3, 170)).unwrap();
        drop(db);
        assert!(!snapshot_exists(&path));
        drop(open_writer(&path));
        assert!(snapshot_exists(&path));
        let log_len = fs::metadata(&path).unwrap().len();
        let loaded = load_snapshot(&path, generation_of(&path)).unwrap();
        assert_eq!(loaded.covered_log_offset, log_len);
        let snapshot_bytes = fs::read(snapshot_path(&path)).unwrap();
        drop(open_writer(&path));
        assert_eq!(fs::read(snapshot_path(&path)).unwrap(), snapshot_bytes);
    }

    #[test]
    fn interrupted_sessions_build_the_same_graph_as_one_uninterrupted_session() {
        let dir = TempDir::new().unwrap();
        let split_path = dir.path().join("split");
        let whole_path = dir.path().join("whole");
        let tail_new = seeded_unit_vector(4242, DIMS);
        let older_upsert = {
            let mut values = tail_new.clone();
            values[0] += 0.05;
            let norm = values.iter().map(|value| value * value).sum::<f32>().sqrt();
            for value in &mut values {
                *value /= norm;
            }
            values
        };
        {
            let db = open_writer(&split_path);
            bulk_add(&db, &bulk_entries(0, 40, 500)).unwrap();
            db.flush().unwrap();
        }
        assert_eq!(
            load_snapshot(&split_path, generation_of(&split_path))
                .unwrap()
                .insert_ordinal,
            40
        );
        {
            let db = open_writer(&split_path);
            db.add("tail-new", &tail_new).unwrap();
            db.add("key-3", &older_upsert).unwrap();
        }
        let split = open_writer(&split_path);
        let whole = open_writer(&whole_path);
        bulk_add(&whole, &bulk_entries(0, 40, 500)).unwrap();
        whole.add("tail-new", &tail_new).unwrap();
        whole.add("key-3", &older_upsert).unwrap();
        let split_state = split.shared.state_read();
        let whole_state = whole.shared.state_read();
        let split_graph = split_state.graph.as_ref().unwrap();
        let whole_graph = whole_state.graph.as_ref().unwrap();
        assert_eq!(split_graph.insert_ordinal(), 42);
        assert_eq!(whole_graph.insert_ordinal(), 42);
        for key in (0..40)
            .map(|index| format!("key-{index}"))
            .chain(["tail-new".to_string()])
        {
            assert_eq!(
                split_state.arena.slot_of_key(&key),
                whole_state.arena.slot_of_key(&key),
                "slot diverges for {key}"
            );
        }
        assert!(
            split_graph
                .slots()
                .any(|slot| split_graph.level_of(slot).unwrap() > 0)
        );
        test_support::assert_identical_graphs(split_graph, whole_graph);
    }

    #[test]
    fn compaction_rewrites_log_and_preserves_live_data() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 120, 1000)).unwrap();
        let generation_before = generation_of(&path);
        for index in 0..40u64 {
            db.add(
                &format!("key-{index}"),
                &seeded_unit_vector(5000 + index, DIMS),
            )
            .unwrap();
        }
        assert_eq!(generation_of(&path), generation_before);
        assert_eq!(db.stats().unwrap().dead_count, 40);
        let log_bytes_before = db.stats().unwrap().log_bytes;
        let removals: Vec<String> = (90..120).map(|index| format!("key-{index}")).collect();
        assert_eq!(db.bulk_remove(&removals).unwrap(), 30);
        let stats = db.stats().unwrap();
        assert_eq!(stats.live_count, 90);
        assert_eq!(stats.dead_count, 0);
        assert_eq!(stats.records_since_snapshot, 0);
        assert!(stats.log_bytes < log_bytes_before);
        assert_ne!(generation_of(&path), generation_before);
        let loaded = load_snapshot(&path, generation_of(&path)).unwrap();
        assert_eq!(loaded.covered_log_offset, stats.log_bytes);
        assert_eq!(loaded.insert_ordinal, 90);
        let live_vector = |index: u64| {
            if index < 40 {
                seeded_unit_vector(5000 + index, DIMS)
            } else {
                seeded_unit_vector(1000 + index, DIMS)
            }
        };
        let verify = |db: &VecDb| {
            assert_eq!(db.len(), 90);
            for index in 90..120 {
                assert!(!db.contains(&format!("key-{index}")));
            }
            for index in 0..90u64 {
                assert_own_nearest(db, &format!("key-{index}"), &live_vector(index));
            }
        };
        verify(&db);
        let query = seeded_unit_vector(31337, DIMS);
        let approx_before = db.search(&query, &limit_params(10)).unwrap();
        drop(db);
        let reopened = open_writer(&path);
        verify(&reopened);
        assert_eq!(
            reopened.search(&query, &limit_params(10)).unwrap(),
            approx_before
        );
        drop(reopened);
        fs::remove_file(snapshot_path(&path)).unwrap();
        let replayed = open_writer(&path);
        verify(&replayed);
    }

    #[test]
    fn compaction_streams_multiple_batches() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 1100, 3000)).unwrap();
        let generation_before = generation_of(&path);
        let removals: Vec<String> = (0..58).map(|index| format!("key-{index}")).collect();
        assert_eq!(db.bulk_remove(&removals).unwrap(), 58);
        assert_ne!(generation_of(&path), generation_before);
        let stats = db.stats().unwrap();
        assert_eq!(stats.live_count, 1042);
        assert_eq!(stats.dead_count, 0);
        for index in (58..1100u64).step_by(97) {
            assert_own_nearest(
                &db,
                &format!("key-{index}"),
                &seeded_unit_vector(3000 + index, DIMS),
            );
        }
        drop(db);
        let reopened = open_writer(&path);
        assert_eq!(reopened.len(), 1042);
        assert!(!reopened.contains("key-0"));
        assert!(reopened.contains("key-58"));
    }

    #[test]
    fn compaction_installs_the_graph_a_fresh_rebuild_of_the_compacted_log_builds() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let copy_path = dir.path().join("copy");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 300, 500)).unwrap();
        let removals: Vec<String> = (0..40).map(|index| format!("key-{}", index * 7)).collect();
        assert_eq!(db.bulk_remove(&removals).unwrap(), 40);
        assert_eq!(db.stats().unwrap().dead_count, 0);
        fs::copy(&path, &copy_path).unwrap();
        let rebuilt = open_writer(&copy_path);
        let st = db.shared.state_read();
        let rebuilt_st = rebuilt.shared.state_read();
        let installed = st.graph.as_ref().unwrap();
        let from_scratch = rebuilt_st.graph.as_ref().unwrap();
        assert_eq!(st.arena.live_count(), 260);
        assert_eq!(st.arena.slot_count(), 260);
        for slot in st.arena.live_slots() {
            assert_eq!(
                st.arena.key_of_slot(slot),
                rebuilt_st.arena.key_of_slot(slot)
            );
        }
        assert!(
            installed
                .slots()
                .any(|slot| installed.level_of(slot).unwrap() > 0)
        );
        test_support::assert_identical_graphs(installed, from_scratch);
    }

    #[test]
    fn a_repacked_state_with_no_graph_serves_exact_results_for_approx_searches() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        let entries = bulk_entries(0, 200, 640);
        let (keys, vectors): (Vec<String>, Vec<Vec<f32>>) = entries.iter().cloned().unzip();
        let attrs: Vec<Option<Vec<Attribute>>> = (0..200)
            .map(|index| (index % 3 == 0).then(|| sample_attrs(index)))
            .collect();
        db.bulk_add_with_attrs(&keys, &vectors, &attrs).unwrap();
        let removals: Vec<String> = (0..20).map(|index| format!("key-{}", index * 9)).collect();
        assert_eq!(db.bulk_remove(&removals).unwrap(), 20);
        let query = seeded_unit_vector(777, DIMS);
        let approx = limit_params(10);
        let exact = SearchParams {
            limit: Some(10),
            exact: true,
            ..SearchParams::default()
        };
        let expected = db.search(&query, &exact).unwrap();
        assert_eq!(expected.len(), 10);
        let stored_keys = vec![
            "key-1".to_string(),
            "key-50".to_string(),
            "key-100".to_string(),
        ];
        let expected_stored = db
            .bulk_search_stored(&stored_keys, 5, None, true, false)
            .unwrap();
        {
            let mut st = db.shared.state_write();
            let SearchState {
                arena,
                graph,
                attrs,
                total_records,
            } = &mut *st;
            attrs.repack(arena.live_slots());
            arena.compact_in_place();
            *graph = None;
            *total_records = arena.live_count() as u64;
        }
        {
            let st = db.shared.state_read();
            assert!(st.graph.is_none());
            assert_eq!(st.arena.slot_count(), 180);
        }
        assert_eq!(db.len(), 180);
        assert_eq!(db.search(&query, &approx).unwrap(), expected);
        assert_eq!(db.search(&query, &exact).unwrap(), expected);
        assert_eq!(
            db.bulk_search(std::slice::from_ref(&query), &approx)
                .unwrap(),
            vec![expected.clone()]
        );
        assert_eq!(
            db.bulk_search_stored(&stored_keys, 5, None, false, false)
                .unwrap(),
            expected_stored
        );
        for index in 0..200i64 {
            let key = format!("key-{index}");
            if index % 9 == 0 && index <= 171 {
                assert!(!db.contains(&key));
                assert_eq!(db.get_attrs(&key), None);
            } else if index % 3 == 0 {
                assert_eq!(db.get_attrs(&key).unwrap(), sample_attrs(index));
            } else {
                assert_eq!(db.get_attrs(&key), None);
            }
        }
    }

    #[test]
    fn stale_snapshot_left_by_interrupted_compaction_is_discarded_on_open() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 120, 210)).unwrap();
        db.flush().unwrap();
        let stale_snapshot = fs::read(snapshot_path(&path)).unwrap();
        let removals: Vec<String> = (0..64).map(|index| format!("key-{index}")).collect();
        assert_eq!(db.bulk_remove(&removals).unwrap(), 64);
        assert_eq!(db.stats().unwrap().dead_count, 0);
        drop(db);
        fs::write(snapshot_path(&path), &stale_snapshot).unwrap();
        let reopened = open_writer(&path);
        assert_eq!(reopened.len(), 56);
        for index in 64..120u64 {
            assert_eq!(
                reopened.get(&format!("key-{index}")).unwrap(),
                seeded_unit_vector(210 + index, DIMS)
            );
        }
        assert_own_nearest(&reopened, "key-100", &seeded_unit_vector(310, DIMS));
        let stats = reopened.stats().unwrap();
        assert_eq!(stats.dead_count, 0);
        let loaded = load_snapshot(&path, generation_of(&path)).unwrap();
        assert_eq!(loaded.covered_log_offset, stats.log_bytes);
        assert_ne!(fs::read(snapshot_path(&path)).unwrap(), stale_snapshot);
    }

    #[test]
    fn writer_open_reinitializes_a_file_shorter_than_the_header() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let partial = [0x45u8, 0x56, 0x44, 0x42, 0x01, 0x00, 0x00];
        fs::write(&path, partial).unwrap();
        let db = open_writer(&path);
        assert!(db.is_empty());
        assert_eq!(db.stats().unwrap().log_bytes, 32);
        db.add("fresh", &seeded_unit_vector(11, DIMS)).unwrap();
        drop(db);
        let reopened = open_writer(&path);
        assert_eq!(reopened.len(), 1);
        assert_own_nearest(&reopened, "fresh", &seeded_unit_vector(11, DIMS));
    }

    #[test]
    fn read_only_open_of_a_short_file_is_empty_and_unaltered() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let partial = [0x45u8, 0x56, 0x44, 0x42, 0x01, 0x00, 0x00];
        fs::write(&path, partial).unwrap();
        let db = VecDb::open_read_only(&path, DIMS).unwrap();
        assert!(db.is_empty());
        assert_eq!(db.stats().unwrap().log_bytes, 0);
        assert_eq!(fs::read(&path).unwrap(), partial);
        assert!(!snapshot_exists(&path));
        assert!(!lock_path(&path).exists());
    }

    #[test]
    fn promote_compacted_log_replaces_the_log_durably() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        drop(Log::create(&path, DIMS).unwrap().into_file());
        let old_generation = generation_of(&path);
        let temp = temp_sibling(&path);
        drop(Log::create(&temp, DIMS).unwrap().into_file());
        let new_generation = generation_of(&temp);
        promote_compacted_log(&temp, &path).unwrap();
        assert!(!temp.exists());
        assert_eq!(generation_of(&path), new_generation);
        assert_ne!(generation_of(&path), old_generation);
        let log = reopen_log(&path, DIMS).unwrap();
        assert_eq!(log.generation(), new_generation);
        drop(log);
        assert!(matches!(
            promote_compacted_log(&temp, &path),
            Err(VecDbError::Io { .. })
        ));
        assert_eq!(generation_of(&path), new_generation);
    }

    #[test]
    fn restore_writer_mode_reinstalls_the_kept_lock_and_reenables_writes() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 3, 260)).unwrap();
        let WriterState {
            lock,
            log,
            mutations_since_snapshot,
            ..
        } = take_writer(&db);
        drop(log);
        assert_eq!(mutations_since_snapshot, 3);
        assert!(is_degraded(&db));
        let vector = seeded_unit_vector(4, DIMS);
        assert!(matches!(
            db.add("blocked", &vector),
            Err(VecDbError::ReadOnly)
        ));
        assert!(matches!(
            WriterLock::acquire(&path),
            Err(VecDbError::Locked(_))
        ));
        {
            let mut half = db.shared.writer_half();
            restore_writer_mode(&db.shared, &mut half, lock, None, mutations_since_snapshot)
                .unwrap();
        }
        assert_eq!(mutations(&db), 3);
        db.add("after", &vector).unwrap();
        assert!(matches!(
            WriterLock::acquire(&path),
            Err(VecDbError::Locked(_))
        ));
        assert_eq!(db.len(), 4);
        drop(db);
        let reopened = open_writer(&path);
        assert_eq!(reopened.len(), 4);
        assert!(reopened.contains("after"));
    }

    #[test]
    fn restore_writer_mode_degrades_to_accurate_read_only_when_reopen_fails() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 3, 270)).unwrap();
        let WriterState { lock, log, .. } = take_writer(&db);
        drop(log);
        let mut bytes = fs::read(&path).unwrap();
        bytes[20] ^= 0x5A;
        fs::write(&path, &bytes).unwrap();
        {
            let mut half = db.shared.writer_half();
            assert!(matches!(
                restore_writer_mode(&db.shared, &mut half, lock, None, 3),
                Err(VecDbError::Corrupt(_))
            ));
            assert!(
                matches!(half.mode, WriterMode::ReadOnly { log_bytes } if log_bytes == bytes.len() as u64)
            );
        }
        assert_eq!(db.stats().unwrap().log_bytes, bytes.len() as u64);
        let vector = seeded_unit_vector(5, DIMS);
        assert!(matches!(db.add("x", &vector), Err(VecDbError::ReadOnly)));
    }

    #[test]
    fn snapshot_failure_degrades_the_write_and_flush_still_errors() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        db.add("seed", &seeded_unit_vector(1, DIMS)).unwrap();
        fs::create_dir(snapshot_path(&path)).unwrap();
        set_mutations(&db, 4999);
        record(&db, 1, Instant::now()).unwrap();
        assert_eq!(mutations(&db), 5000);
        assert!(matches!(db.flush(), Err(VecDbError::Io { .. })));
        db.add("more", &seeded_unit_vector(2, DIMS)).unwrap();
        drop(db);
        let reopened = open_writer(&path);
        assert_eq!(reopened.len(), 2);
        assert!(reopened.contains("seed"));
        assert!(reopened.contains("more"));
    }

    #[test]
    fn failed_compaction_keeps_the_write_ok_and_backs_off() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 100, 280)).unwrap();
        let generation_before = generation_of(&path);
        fs::create_dir(temp_sibling(&path)).unwrap();
        let removals: Vec<String> = (0..64).map(|index| format!("key-{index}")).collect();
        assert_eq!(db.bulk_remove(&removals).unwrap(), 64);
        assert_eq!(db.stats().unwrap().dead_count, 128);
        assert_eq!(generation_of(&path), generation_before);
        db.add("probe", &seeded_unit_vector(7, DIMS)).unwrap();
        assert!(matches!(
            WriterLock::acquire(&path),
            Err(VecDbError::Locked(_))
        ));
        fs::remove_dir(temp_sibling(&path)).unwrap();
        bulk_add(&db, &bulk_entries(64, 36, 290)).unwrap();
        assert_eq!(db.stats().unwrap().dead_count, 164);
        assert_eq!(generation_of(&path), generation_before);
        bulk_add(&db, &bulk_entries(64, 28, 295)).unwrap();
        assert_eq!(db.stats().unwrap().dead_count, 0);
        assert_ne!(generation_of(&path), generation_before);
        drop(db);
        let reopened = open_writer(&path);
        assert_eq!(reopened.len(), 37);
        assert!(reopened.contains("probe"));
        assert!(reopened.contains("key-64"));
        assert!(!reopened.contains("key-0"));
    }

    #[test]
    fn failed_post_compaction_snapshot_leaves_the_state_dirty_until_flush_succeeds() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 100, 970)).unwrap();
        fs::create_dir(snapshot_path(&path)).unwrap();
        let removals: Vec<String> = (0..64).map(|index| format!("key-{index}")).collect();
        assert_eq!(db.bulk_remove(&removals).unwrap(), 64);
        let stats = db.stats().unwrap();
        assert_eq!(stats.live_count, 36);
        assert_eq!(stats.dead_count, 0);
        assert_eq!(stats.records_since_snapshot, 36);
        assert!(matches!(db.flush(), Err(VecDbError::Io { .. })));
        assert_eq!(db.stats().unwrap().records_since_snapshot, 36);
        drop(db);
        let blocked = open_writer(&path);
        assert_eq!(blocked.len(), 36);
        assert!(blocked.contains("key-64"));
        assert!(!blocked.contains("key-0"));
        assert_eq!(blocked.stats().unwrap().records_since_snapshot, 36);
        fs::remove_dir(snapshot_path(&path)).unwrap();
        blocked.flush().unwrap();
        assert_eq!(blocked.stats().unwrap().records_since_snapshot, 0);
        assert!(snapshot_exists(&path));
        drop(blocked);
        let reopened = open_writer(&path);
        assert_eq!(reopened.len(), 36);
        assert_own_nearest(&reopened, "key-99", &seeded_unit_vector(970 + 99, DIMS));
    }

    #[test]
    fn open_succeeds_and_serves_data_when_the_snapshot_cannot_be_written() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 5, 300)).unwrap();
        drop(db);
        fs::create_dir(snapshot_path(&path)).unwrap();
        let db = open_writer(&path);
        assert_eq!(db.len(), 5);
        assert_own_nearest(&db, "key-2", &seeded_unit_vector(302, DIMS));
        assert!(matches!(db.flush(), Err(VecDbError::Io { .. })));
        drop(db);
        fs::remove_dir(snapshot_path(&path)).unwrap();
        drop(open_writer(&path));
        assert!(snapshot_exists(&path));
    }

    #[test]
    fn reset_empties_the_db_and_keeps_it_usable() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 20, 180)).unwrap();
        db.flush().unwrap();
        let generation_before = generation_of(&path);
        db.reset().unwrap();
        assert!(db.is_empty());
        assert!(!snapshot_exists(&path));
        assert_ne!(generation_of(&path), generation_before);
        assert_eq!(fs::metadata(&path).unwrap().len(), 32);
        assert_eq!(
            db.stats().unwrap(),
            Stats {
                live_count: 0,
                dead_count: 0,
                dims: DIMS,
                log_bytes: 32,
                records_since_snapshot: 0,
                approximate_memory_bytes: 0,
            }
        );
        db.add("again", &seeded_unit_vector(2, DIMS)).unwrap();
        assert_own_nearest(&db, "again", &seeded_unit_vector(2, DIMS));
        drop(db);
        let reopened = open_writer(&path);
        assert_eq!(reopened.len(), 1);
        assert!(reopened.contains("again"));
        assert!(!reopened.contains("key-0"));
    }

    #[test]
    fn reset_via_one_handle_keeps_aliases_live() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let first = open_writer(&path);
        let second = VecDb::open(&path, DIMS).unwrap();
        bulk_add(&first, &bulk_entries(0, 10, 220)).unwrap();
        assert_eq!(second.len(), 10);
        second.reset().unwrap();
        assert!(first.is_empty());
        assert!(!first.contains("key-0"));
        let fresh = seeded_unit_vector(6, DIMS);
        first.add("fresh", &fresh).unwrap();
        assert!(second.contains("fresh"));
        assert_eq!(second.len(), 1);
        assert_own_nearest(&second, "fresh", &fresh);
    }

    #[test]
    fn failed_reset_with_the_log_gone_becomes_an_accurate_empty_instance() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 5, 310)).unwrap();
        fs::create_dir(snapshot_path(&path)).unwrap();
        assert!(matches!(db.reset(), Err(VecDbError::Io { .. })));
        assert!(!path.exists());
        assert!(db.is_empty());
        assert_eq!(db.len(), 0);
        assert!(!db.contains("key-0"));
        assert_eq!(db.stats().unwrap().log_bytes, 0);
        let vector = seeded_unit_vector(1, DIMS);
        assert!(matches!(db.add("x", &vector), Err(VecDbError::ReadOnly)));
        assert!(db.search(&vector, &limit_params(3)).unwrap().is_empty());
        drop(db);
        fs::remove_dir(snapshot_path(&path)).unwrap();
        let reopened = open_writer(&path);
        assert!(reopened.is_empty());
    }

    #[cfg(unix)]
    #[test]
    fn failed_reset_that_cannot_remove_the_log_keeps_the_writer_and_data() {
        use std::os::unix::fs::PermissionsExt;

        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 5, 320)).unwrap();
        fs::set_permissions(dir.path(), fs::Permissions::from_mode(0o555)).unwrap();
        let outcome = db.reset();
        fs::set_permissions(dir.path(), fs::Permissions::from_mode(0o755)).unwrap();
        let Err(VecDbError::Io { .. }) = outcome else {
            return;
        };
        assert_eq!(db.len(), 5);
        assert!(db.contains("key-0"));
        assert_eq!(db.stats().unwrap().records_since_snapshot, 5);
        db.add("after", &seeded_unit_vector(6, DIMS)).unwrap();
        drop(db);
        let reopened = open_writer(&path);
        assert_eq!(reopened.len(), 6);
        assert!(reopened.contains("key-4"));
        assert!(reopened.contains("after"));
    }

    #[test]
    fn reset_recovery_over_a_recreated_log_clears_memory_to_match_disk() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 5, 330)).unwrap();
        let old_generation = generation_of(&path);
        let WriterState { lock, log, .. } = take_writer(&db);
        drop(log);
        remove_data_files(&path).unwrap();
        drop(Log::create(&path, DIMS).unwrap().into_file());
        {
            let mut half = db.shared.writer_half();
            recover_after_failed_reset(&db.shared, &mut half, lock, old_generation, 5);
        }
        assert!(db.is_empty());
        assert!(!db.contains("key-0"));
        assert_eq!(db.stats().unwrap().log_bytes, 32);
        assert_eq!(db.stats().unwrap().records_since_snapshot, 0);
        db.add("fresh", &seeded_unit_vector(7, DIMS)).unwrap();
        assert_eq!(db.len(), 1);
        drop(db);
        let reopened = open_writer(&path);
        assert_eq!(reopened.len(), 1);
        assert!(reopened.contains("fresh"));
        assert!(!reopened.contains("key-0"));
    }

    #[test]
    fn delete_removes_data_files_and_keeps_the_lock_sidecar() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 5, 190)).unwrap();
        db.flush().unwrap();
        fs::write(temp_sibling(&path), [7u8; 10]).unwrap();
        assert!(path.exists());
        assert!(snapshot_exists(&path));
        assert!(lock_path(&path).exists());
        db.delete().unwrap();
        assert!(!path.exists());
        assert!(!snapshot_exists(&path));
        assert!(!temp_sibling(&path).exists());
        assert!(lock_path(&path).exists());
    }

    #[test]
    fn reopen_after_delete_reuses_the_persistent_lock_sidecar() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        db.add("doomed", &seeded_unit_vector(2, DIMS)).unwrap();
        db.delete().unwrap();
        assert!(lock_path(&path).exists());
        #[cfg(unix)]
        let sidecar_inode = {
            use std::os::unix::fs::MetadataExt;
            fs::metadata(lock_path(&path)).unwrap().ino()
        };
        let reopened = open_writer(&path);
        assert!(reopened.is_empty());
        assert!(matches!(
            WriterLock::acquire(&path),
            Err(VecDbError::Locked(_))
        ));
        #[cfg(unix)]
        {
            use std::os::unix::fs::MetadataExt;
            assert_eq!(fs::metadata(lock_path(&path)).unwrap().ino(), sidecar_inode);
        }
        reopened.add("fresh", &seeded_unit_vector(3, DIMS)).unwrap();
        drop(reopened);
        let third = open_writer(&path);
        assert_eq!(third.len(), 1);
        assert!(third.contains("fresh"));
        assert!(lock_path(&path).exists());
    }

    #[test]
    fn delete_releases_the_writer_lock_before_retiring_the_slot_marker() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        db.add("doomed", &seeded_unit_vector(5, DIMS)).unwrap();
        let key = registry_key_for(&path).unwrap();
        let slot = existing_path_slot(&key).unwrap();
        let marker_blocked = lock_slot(&slot);
        let deleter = thread::spawn(move || db.delete());
        let deadline = Instant::now() + Duration::from_secs(30);
        while path.exists() {
            assert!(Instant::now() < deadline);
            thread::yield_now();
        }
        let mut reacquired = WriterLock::acquire(&path);
        while reacquired.is_err() && Instant::now() < deadline {
            reacquired = WriterLock::acquire(&path);
        }
        assert!(marker_blocked.holds_live());
        drop(reacquired.unwrap());
        drop(marker_blocked);
        deleter.join().unwrap().unwrap();
        assert!(lock_slot(&slot).live.is_none());
    }

    #[test]
    fn delete_leaves_surviving_handles_closed() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let first = open_writer(&path);
        bulk_add(&first, &bulk_entries(0, 5, 400)).unwrap();
        first.flush().unwrap();
        let survivor = VecDb::open(&path, DIMS).unwrap();
        let observer = VecDb::open_read_only(&path, DIMS).unwrap();
        first.delete().unwrap();
        assert!(!path.exists());
        assert!(!snapshot_exists(&path));
        assert!(lock_path(&path).exists());
        let query = seeded_unit_vector(1, DIMS);
        assert!(matches!(
            survivor.search(&query, &limit_params(3)),
            Err(VecDbError::Closed)
        ));
        assert!(matches!(
            survivor.bulk_search(std::slice::from_ref(&query), &limit_params(3)),
            Err(VecDbError::Closed)
        ));
        assert!(matches!(
            survivor.bulk_search_stored(&["key-0".to_string()], 3, None, false, false),
            Err(VecDbError::Closed)
        ));
        assert!(matches!(survivor.add("x", &query), Err(VecDbError::Closed)));
        assert!(matches!(
            bulk_add(&survivor, &bulk_entries(0, 2, 401)),
            Err(VecDbError::Closed)
        ));
        assert!(matches!(survivor.remove("key-0"), Err(VecDbError::Closed)));
        assert!(matches!(survivor.stats(), Err(VecDbError::Closed)));
        assert!(matches!(survivor.flush(), Err(VecDbError::Closed)));
        assert!(matches!(survivor.reset(), Err(VecDbError::Closed)));
        assert!(matches!(
            observer.search(&query, &limit_params(3)),
            Err(VecDbError::Closed)
        ));
        assert_eq!(survivor.len(), 0);
        assert!(!survivor.contains("key-0"));
        assert!(survivor.get("key-0").is_none());
        assert!(matches!(survivor.delete(), Err(VecDbError::Closed)));
        let fresh = open_writer(&path);
        assert!(fresh.is_empty());
        fresh.add("anew", &query).unwrap();
        assert_eq!(fresh.len(), 1);
    }

    #[test]
    fn concurrent_bulk_add_with_live_readers_and_flush() {
        const READERS: usize = 3;
        const BULK: usize = 2000;
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let writer = open_writer(&path);
        let pre = bulk_entries(10_000, 50, 900);
        bulk_add(&writer, &pre).unwrap();
        let bulk = bulk_entries(0, BULK, 700);
        let expected: Arc<HashMap<String, Vec<f32>>> =
            Arc::new(pre.iter().chain(bulk.iter()).cloned().collect());
        let stop = Arc::new(AtomicBool::new(false));
        let barrier = Arc::new(Barrier::new(READERS + 2));
        let mut readers = Vec::new();
        for reader_index in 0..READERS {
            let handle = VecDb::open(&path, DIMS).unwrap();
            let stop = Arc::clone(&stop);
            let barrier = Arc::clone(&barrier);
            let expected = Arc::clone(&expected);
            readers.push(thread::spawn(move || {
                let query = seeded_unit_vector(31_337 + reader_index as u64, DIMS);
                barrier.wait();
                let mut iterations = 0usize;
                loop {
                    let found = handle.search(&query, &limit_params(8)).unwrap();
                    for entry in &found {
                        let vector = handle.get(&entry.key).unwrap();
                        assert_eq!(&vector, expected.get(&entry.key).unwrap());
                    }
                    iterations += 1;
                    if stop.load(Ordering::Relaxed) {
                        break;
                    }
                }
                (handle, iterations)
            }));
        }
        let flusher = {
            let handle = VecDb::open(&path, DIMS).unwrap();
            let stop = Arc::clone(&stop);
            let barrier = Arc::clone(&barrier);
            thread::spawn(move || {
                barrier.wait();
                let mut flushes = 0usize;
                loop {
                    handle.flush().unwrap();
                    flushes += 1;
                    if stop.load(Ordering::Relaxed) {
                        break;
                    }
                }
                flushes
            })
        };
        barrier.wait();
        bulk_add(&writer, &bulk).unwrap();
        stop.store(true, Ordering::Relaxed);
        for reader in readers {
            let (handle, iterations) = reader.join().unwrap();
            assert!(iterations > 0);
            assert_eq!(handle.len(), 50 + BULK);
            assert!(handle.contains("key-0"));
            assert!(handle.contains(&format!("key-{}", BULK - 1)));
            assert!(handle.contains("key-10000"));
        }
        assert!(flusher.join().unwrap() > 0);
        assert_eq!(writer.len(), 50 + BULK);
        assert_eq!(writer.stats().unwrap().live_count, 50 + BULK);
    }

    #[test]
    fn searches_continue_while_a_compaction_is_in_flight() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 300, 500)).unwrap();
        let removals: Vec<String> = (0..30).map(|index| format!("key-{index}")).collect();
        assert_eq!(db.bulk_remove(&removals).unwrap(), 30);
        assert_eq!(db.stats().unwrap().dead_count, 60);
        let generation_before = generation_of(&path);
        let query = seeded_unit_vector(4242, DIMS);
        let exact = SearchParams {
            limit: Some(10),
            exact: true,
            ..SearchParams::default()
        };
        let before = db.search(&query, &exact).unwrap();
        assert_eq!(before.len(), 10);
        let held = db.shared.state_read();
        let shared = Arc::clone(&db.shared);
        let compactor = thread::spawn(move || {
            let mut half = shared.writer_half();
            compact(&shared, &mut half)
        });
        let deadline = Instant::now() + Duration::from_secs(60);
        while generation_of(&path) == generation_before {
            assert!(Instant::now() < deadline);
            thread::yield_now();
        }
        let packed = held.arena.pack_query(&query).unwrap();
        for _ in 0..25 {
            let during = graph_search(held.search_graph(), &held.arena, &packed, &exact, None);
            assert_eq!(during, before);
        }
        assert!(held.graph.is_some());
        assert!(!compactor.is_finished());
        drop(held);
        compactor.join().unwrap().unwrap();
        assert_ne!(generation_of(&path), generation_before);
        let stats = db.stats().unwrap();
        assert_eq!(stats.dead_count, 0);
        assert_eq!(stats.live_count, 270);
        assert_eq!(db.search(&query, &exact).unwrap(), before);
        assert!(!db.contains("key-0"));
        assert!(db.contains("key-30"));
    }

    #[test]
    fn non_finite_vectors_are_rejected_without_partial_state() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        db.add("key-0", &seeded_unit_vector(0, DIMS)).unwrap();
        let log_bytes = db.stats().unwrap().log_bytes;
        for bad_value in [f32::NAN, f32::INFINITY, f32::NEG_INFINITY] {
            let mut bad = seeded_unit_vector(9, DIMS);
            bad[3] = bad_value;
            assert!(matches!(
                db.add("bad", &bad),
                Err(VecDbError::InvalidVector(_))
            ));
            assert!(!db.contains("bad"));
        }
        let mut infected = bulk_entries(10, 3, 200);
        infected[1].1[0] = f32::INFINITY;
        assert!(matches!(
            bulk_add(&db, &infected),
            Err(VecDbError::InvalidVector(_))
        ));
        assert_eq!(db.len(), 1);
        assert!(!db.contains("key-10"));
        assert!(!db.contains("key-12"));
        assert_eq!(db.stats().unwrap().log_bytes, log_bytes);
        drop(db);
        let reopened = open_writer(&path);
        assert_eq!(reopened.len(), 1);
        assert!(reopened.contains("key-0"));
        assert!(!reopened.contains("bad"));
    }

    #[test]
    fn bulk_search_matches_per_query_search() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 200, 640)).unwrap();
        let allowed = vec![
            "key-3".to_string(),
            "key-77".to_string(),
            "key-77".to_string(),
            "key-150".to_string(),
            "absent".to_string(),
        ];
        let queries: Vec<Vec<f32>> = (0..6)
            .map(|index| seeded_unit_vector(9000 + index, DIMS))
            .collect();
        for shape in search_shapes(allowed) {
            let bulk = db.bulk_search(&queries, &shape).unwrap();
            assert_eq!(bulk.len(), queries.len());
            for (query, matches) in queries.iter().zip(&bulk) {
                assert_eq!(matches, &db.search(query, &shape).unwrap());
            }
        }
        assert!(matches!(
            db.bulk_search(&queries, &SearchParams::default()),
            Err(VecDbError::UnboundedSearch)
        ));
        for bad_distance in [f32::NAN, f32::INFINITY, -0.5] {
            let degenerate = SearchParams {
                limit: Some(3),
                max_distance: Some(bad_distance),
                ..SearchParams::default()
            };
            let empties = db.bulk_search(&queries, &degenerate).unwrap();
            assert_eq!(empties.len(), queries.len());
            assert!(empties.iter().all(Vec::is_empty));
        }
        let empty_allowed = SearchParams {
            limit: Some(5),
            allowed_keys: Some(Vec::new()),
            ..SearchParams::default()
        };
        let none_allowed = db.bulk_search(&queries, &empty_allowed).unwrap();
        assert_eq!(none_allowed.len(), queries.len());
        assert!(none_allowed.iter().all(Vec::is_empty));
        for query in &queries {
            assert!(db.search(query, &empty_allowed).unwrap().is_empty());
        }
        assert!(db.bulk_search(&[], &limit_params(3)).unwrap().is_empty());
    }

    #[test]
    fn bulk_search_varied_matches_per_query_search() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 200, 640)).unwrap();
        let queries: Vec<Vec<f32>> = (0..5)
            .map(|index| seeded_unit_vector(9600 + index, DIMS))
            .collect();
        let params = vec![
            SearchParams {
                limit: Some(8),
                max_distance: Some(2.0),
                exact: true,
                ..SearchParams::default()
            },
            SearchParams {
                limit: Some(4),
                max_distance: Some(0.9),
                exact: true,
                ..SearchParams::default()
            },
            SearchParams {
                limit: None,
                max_distance: Some(1.05),
                exact: true,
                ..SearchParams::default()
            },
            SearchParams {
                limit: Some(6),
                exact: true,
                allowed_keys: Some(vec![
                    "key-3".to_string(),
                    "key-77".to_string(),
                    "key-150".to_string(),
                    "absent".to_string(),
                ]),
                ..SearchParams::default()
            },
            SearchParams {
                limit: Some(3),
                max_distance: Some(-0.25),
                exact: true,
                ..SearchParams::default()
            },
        ];
        let varied = db.bulk_search_varied(&queries, &params).unwrap();
        assert_eq!(varied.len(), queries.len());
        for ((query, shape), matches) in queries.iter().zip(&params).zip(&varied) {
            assert_eq!(matches, &db.search(query, shape).unwrap());
        }
        assert_eq!(varied[0].len(), 8);
        assert!(varied[4].is_empty());
        assert!(varied[..4].iter().all(|matches| !matches.is_empty()));
        let approx: Vec<SearchParams> = params
            .iter()
            .cloned()
            .map(|shape| SearchParams {
                exact: false,
                ..shape
            })
            .collect();
        let approx_varied = db.bulk_search_varied(&queries, &approx).unwrap();
        for ((query, shape), matches) in queries.iter().zip(&approx).zip(&approx_varied) {
            assert_eq!(matches, &db.search(query, shape).unwrap());
        }
        assert!(approx_varied[4].is_empty());
        let mut unbounded = params.clone();
        unbounded[2] = SearchParams::default();
        assert!(matches!(
            db.bulk_search_varied(&queries, &unbounded),
            Err(VecDbError::UnboundedSearch)
        ));
        assert!(matches!(
            db.bulk_search_varied(&queries, &params[..3]),
            Err(VecDbError::LengthMismatch {
                keys: 5,
                vectors: 3
            })
        ));
        assert!(db.bulk_search_varied(&[], &[]).unwrap().is_empty());
    }

    #[test]
    fn bulk_search_stored_preserves_order_skips_absent_and_excludes_self() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 40, 820)).unwrap();
        let twin = seeded_unit_vector(31_000, DIMS);
        db.add("twin-a", &twin).unwrap();
        db.add("twin-b", &twin).unwrap();
        let input = vec![
            "key-5".to_string(),
            "missing".to_string(),
            "twin-a".to_string(),
            "key-0".to_string(),
            "key-31".to_string(),
        ];
        for exact in [false, true] {
            let results = db
                .bulk_search_stored(&input, 4, None, exact, false)
                .unwrap();
            let found: Vec<&str> = results.iter().map(|entry| entry.key.as_str()).collect();
            assert_eq!(found, vec!["key-5", "twin-a", "key-0", "key-31"]);
            for entry in &results {
                assert_eq!(entry.matches.len(), 4);
                assert!(entry.matches.iter().all(|found| found.key != entry.key));
            }
            assert_eq!(results[1].matches[0].key, "twin-b");
            assert!(results[1].matches[0].distance.abs() < 1.0e-6);
        }
        assert!(
            db.bulk_search_stored(&[], 3, None, false, false)
                .unwrap()
                .is_empty()
        );
        let absent = vec!["nope".to_string(), "nada".to_string()];
        assert!(
            db.bulk_search_stored(&absent, 3, None, true, true)
                .unwrap()
                .is_empty()
        );
    }

    #[test]
    fn bulk_search_stored_restricts_to_input_only_when_asked() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 30, 860)).unwrap();
        let input: Vec<String> = (1..=4).map(|index| format!("key-{index}")).collect();
        for exact in [false, true] {
            let restricted = db
                .bulk_search_stored(&input, 10, None, exact, true)
                .unwrap();
            assert_eq!(restricted.len(), 4);
            for entry in &restricted {
                assert_eq!(entry.matches.len(), 3);
                assert!(
                    entry
                        .matches
                        .iter()
                        .all(|found| input.contains(&found.key) && found.key != entry.key)
                );
            }
            let open = db
                .bulk_search_stored(&input, 10, None, exact, false)
                .unwrap();
            assert!(open.iter().all(|entry| entry.matches.len() == 10));
            assert!(open.iter().any(|entry| {
                entry
                    .matches
                    .iter()
                    .any(|found| !input.contains(&found.key))
            }));
        }
    }

    #[test]
    fn bulk_search_stored_applies_the_distance_cut() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        db.add("center", &basis_vector(0)).unwrap();
        let mut close = basis_vector(0);
        close[0] = 0.99;
        close[1] = (1.0f32 - 0.99 * 0.99).sqrt();
        db.add("close", &close).unwrap();
        for axis in 2..10 {
            db.add(&format!("far-{axis}"), &basis_vector(axis)).unwrap();
        }
        let center = vec!["center".to_string()];
        for exact in [false, true] {
            let cut = db
                .bulk_search_stored(&center, 5, Some(0.5), exact, false)
                .unwrap();
            assert_eq!(cut[0].matches.len(), 1);
            assert_eq!(cut[0].matches[0].key, "close");
            let uncut = db
                .bulk_search_stored(&center, 20, Some(0.5), exact, false)
                .unwrap();
            assert_eq!(uncut[0].matches.len(), 1);
            let complete = db
                .bulk_search_stored(&center, 9, None, exact, false)
                .unwrap();
            assert_eq!(complete[0].matches.len(), 9);
            let whole_index = db
                .bulk_search_stored(&center, 10, None, exact, false)
                .unwrap();
            assert_eq!(whole_index[0].matches.len(), 9);
            for bad_distance in [f32::NAN, f32::INFINITY, -0.5] {
                let degenerate = db
                    .bulk_search_stored(&center, 5, Some(bad_distance), exact, false)
                    .unwrap();
                assert_eq!(degenerate.len(), 1);
                assert!(degenerate[0].matches.is_empty());
            }
        }
    }

    #[test]
    fn bulk_search_stored_on_a_single_entry_index_finds_nothing() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        db.add("solo", &seeded_unit_vector(5, DIMS)).unwrap();
        let input = vec!["solo".to_string()];
        for exact in [false, true] {
            for restrict in [false, true] {
                let results = db
                    .bulk_search_stored(&input, 3, None, exact, restrict)
                    .unwrap();
                assert_eq!(results.len(), 1);
                assert_eq!(results[0].key, "solo");
                assert!(results[0].matches.is_empty());
            }
        }
    }

    #[test]
    fn bulk_add_length_mismatch_is_rejected_before_anything_else() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        db.add("seed", &seeded_unit_vector(1, DIMS)).unwrap();
        let log_bytes = db.stats().unwrap().log_bytes;
        let keys = vec!["x".to_string(), "y".to_string()];
        let vectors = vec![seeded_unit_vector(2, DIMS)];
        assert!(matches!(
            db.bulk_add(&keys, &vectors),
            Err(VecDbError::LengthMismatch {
                keys: 2,
                vectors: 1
            })
        ));
        assert_eq!(db.len(), 1);
        assert!(!db.contains("x"));
        assert_eq!(db.stats().unwrap().log_bytes, log_bytes);
        let read_only = VecDb::open_read_only(&path, DIMS).unwrap();
        assert!(matches!(
            read_only.bulk_add(&keys, &vectors),
            Err(VecDbError::LengthMismatch { .. })
        ));
    }

    #[test]
    fn purge_with_a_live_instance_behaves_like_delete() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let first = open_writer(&path);
        bulk_add(&first, &bulk_entries(0, 5, 950)).unwrap();
        first.flush().unwrap();
        fs::write(temp_sibling(&path), [7u8; 10]).unwrap();
        let survivor = VecDb::open(&path, DIMS).unwrap();
        let observer = VecDb::open_read_only(&path, DIMS).unwrap();
        VecDb::purge(&path).unwrap();
        assert!(!path.exists());
        assert!(!snapshot_exists(&path));
        assert!(!temp_sibling(&path).exists());
        assert!(lock_path(&path).exists());
        let query = seeded_unit_vector(1, DIMS);
        assert!(matches!(
            survivor.search(&query, &limit_params(3)),
            Err(VecDbError::Closed)
        ));
        assert!(matches!(
            survivor.bulk_search(std::slice::from_ref(&query), &limit_params(3)),
            Err(VecDbError::Closed)
        ));
        assert!(matches!(
            survivor.bulk_search_stored(&["key-0".to_string()], 3, None, false, false),
            Err(VecDbError::Closed)
        ));
        assert!(matches!(survivor.add("x", &query), Err(VecDbError::Closed)));
        assert!(matches!(
            bulk_add(&survivor, &bulk_entries(0, 2, 951)),
            Err(VecDbError::Closed)
        ));
        assert!(matches!(survivor.remove("key-0"), Err(VecDbError::Closed)));
        assert!(matches!(
            survivor.bulk_remove(&["key-0".to_string()]),
            Err(VecDbError::Closed)
        ));
        assert!(matches!(survivor.stats(), Err(VecDbError::Closed)));
        assert!(matches!(survivor.flush(), Err(VecDbError::Closed)));
        assert!(matches!(survivor.reset(), Err(VecDbError::Closed)));
        assert!(matches!(
            observer.search(&query, &limit_params(3)),
            Err(VecDbError::Closed)
        ));
        assert!(matches!(first.stats(), Err(VecDbError::Closed)));
        assert!(matches!(survivor.delete(), Err(VecDbError::Closed)));
        let fresh = open_writer(&path);
        assert!(fresh.is_empty());
        fresh.add("anew", &query).unwrap();
        assert_eq!(fresh.len(), 1);
    }

    #[test]
    fn purge_without_a_live_instance_removes_files_and_tolerates_missing_ones() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 5, 960)).unwrap();
        db.flush().unwrap();
        drop(db);
        fs::write(temp_sibling(&path), [7u8; 10]).unwrap();
        assert!(path.exists());
        assert!(snapshot_exists(&path));
        assert!(lock_path(&path).exists());
        VecDb::purge(&path).unwrap();
        assert!(!path.exists());
        assert!(!snapshot_exists(&path));
        assert!(!temp_sibling(&path).exists());
        assert!(lock_path(&path).exists());
        VecDb::purge(&path).unwrap();
        assert!(lock_path(&path).exists());
        let never_created = dir.path().join("never-created");
        VecDb::purge(&never_created).unwrap();
        assert!(lock_path(&never_created).exists());
        let fresh = open_writer(&path);
        assert!(fresh.is_empty());
        fresh.add("fresh", &seeded_unit_vector(3, DIMS)).unwrap();
        assert_eq!(fresh.len(), 1);
    }

    #[test]
    fn purge_refuses_while_a_foreign_writer_holds_the_lock() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        db.add("kept", &seeded_unit_vector(4, DIMS)).unwrap();
        db.flush().unwrap();
        drop(db);
        let held = WriterLock::acquire(&path).unwrap();
        assert!(matches!(VecDb::purge(&path), Err(VecDbError::Locked(_))));
        assert!(path.exists());
        assert!(snapshot_exists(&path));
        drop(held);
        VecDb::purge(&path).unwrap();
        assert!(!path.exists());
        assert!(lock_path(&path).exists());
    }

    #[test]
    fn purge_of_a_missing_parent_directory_is_ok() {
        let dir = TempDir::new().unwrap();
        VecDb::purge(&dir.path().join("absent").join("db")).unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn symlinked_paths_share_one_instance_and_one_lock() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let alias = dir.path().join("alias");
        let via_path = open_writer(&path);
        std::os::unix::fs::symlink(&path, &alias).unwrap();
        let via_alias = VecDb::open(&alias, DIMS).unwrap();
        via_path
            .add("through-real", &seeded_unit_vector(5, DIMS))
            .unwrap();
        via_alias
            .add("through-alias", &seeded_unit_vector(6, DIMS))
            .unwrap();
        assert!(via_path.contains("through-alias"));
        assert!(via_alias.contains("through-real"));
        assert_eq!(via_path.len(), 2);
        assert!(lock_path(&path).exists());
        assert!(!lock_path(&alias).exists());
        let read_alias = VecDb::open_read_only(&alias, DIMS).unwrap();
        via_path.add("late", &seeded_unit_vector(7, DIMS)).unwrap();
        assert!(read_alias.contains("late"));
    }

    #[cfg(unix)]
    #[test]
    fn purge_through_a_symlink_removes_the_real_files() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let alias = dir.path().join("alias");
        let db = open_writer(&path);
        db.add("gone", &seeded_unit_vector(8, DIMS)).unwrap();
        db.flush().unwrap();
        drop(db);
        std::os::unix::fs::symlink(&path, &alias).unwrap();
        VecDb::purge(&alias).unwrap();
        assert!(!path.exists());
        assert!(!snapshot_exists(&path));
        assert!(lock_path(&path).exists());
        assert!(!lock_path(&alias).exists());
        assert!(fs::symlink_metadata(&alias).is_ok());
    }

    #[test]
    fn open_cost_reports_ready_for_a_live_instance() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 5, 980)).unwrap();
        assert_eq!(VecDb::open_cost(&path), OpenCost::Ready);
        drop(db);
        assert_eq!(VecDb::open_cost(&path), OpenCost::NeedsRebuild);
    }

    #[test]
    fn open_cost_walks_every_file_branch() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        assert_eq!(VecDb::open_cost(&path), OpenCost::Absent);
        fs::write(&path, [0x45u8, 0x56, 0x44, 0x42, 0x01]).unwrap();
        assert_eq!(VecDb::open_cost(&path), OpenCost::Absent);
        fs::remove_file(&path).unwrap();
        drop(open_writer(&path));
        assert_eq!(VecDb::open_cost(&path), OpenCost::Ready);
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 4, 985)).unwrap();
        drop(db);
        assert_eq!(VecDb::open_cost(&path), OpenCost::NeedsRebuild);
        drop(open_writer(&path));
        assert!(snapshot_exists(&path));
        assert_eq!(VecDb::open_cost(&path), OpenCost::Ready);
        let healthy_snapshot = fs::read(snapshot_path(&path)).unwrap();
        let mut corrupted = healthy_snapshot.clone();
        corrupted[20] ^= 0x5A;
        fs::write(snapshot_path(&path), &corrupted).unwrap();
        assert_eq!(VecDb::open_cost(&path), OpenCost::NeedsRebuild);
        fs::remove_file(&path).unwrap();
        fs::remove_file(snapshot_path(&path)).unwrap();
        let db = open_writer(&path);
        db.add("fresh", &seeded_unit_vector(1, DIMS)).unwrap();
        drop(db);
        fs::write(snapshot_path(&path), &healthy_snapshot).unwrap();
        assert_eq!(VecDb::open_cost(&path), OpenCost::NeedsRebuild);
    }

    #[test]
    fn open_cost_flags_a_snapshot_covering_beyond_the_log() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        db.add("first", &seeded_unit_vector(1, DIMS)).unwrap();
        let boundary = db.stats().unwrap().log_bytes;
        db.add("second", &seeded_unit_vector(2, DIMS)).unwrap();
        db.flush().unwrap();
        drop(db);
        assert_eq!(VecDb::open_cost(&path), OpenCost::Ready);
        let clean = fs::read(&path).unwrap();
        fs::write(&path, &clean[..boundary as usize]).unwrap();
        assert_eq!(VecDb::open_cost(&path), OpenCost::NeedsRebuild);
    }

    #[test]
    fn open_cost_ignores_the_writer_lock_and_leaves_a_live_writer_undisturbed() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        bulk_add(&db, &bulk_entries(0, 3, 990)).unwrap();
        db.flush().unwrap();
        drop(db);
        let held = WriterLock::acquire(&path).unwrap();
        assert_eq!(VecDb::open_cost(&path), OpenCost::Ready);
        drop(held);
        let db = open_writer(&path);
        let log_before = fs::read(&path).unwrap();
        let snapshot_before = fs::read(snapshot_path(&path)).unwrap();
        assert_eq!(VecDb::open_cost(&path), OpenCost::Ready);
        assert_eq!(fs::read(&path).unwrap(), log_before);
        assert_eq!(fs::read(snapshot_path(&path)).unwrap(), snapshot_before);
        db.add("after", &seeded_unit_vector(7, DIMS)).unwrap();
        assert!(db.contains("after"));
        assert_own_nearest(&db, "after", &seeded_unit_vector(7, DIMS));
    }

    #[test]
    fn searches_serve_exact_results_while_the_graph_rebuild_is_pending() {
        const COUNT: usize = 2000;
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let control_path = dir.path().join("control");
        let entries = bulk_entries(0, COUNT, 8000);
        let replacement = seeded_unit_vector(31_415, DIMS);
        let query = seeded_unit_vector(4321, DIMS);
        let bulk_queries: Vec<Vec<f32>> = (0..3)
            .map(|index| seeded_unit_vector(5000 + index, DIMS))
            .collect();
        let stored_keys = vec![
            "key-10".to_string(),
            "missing".to_string(),
            "key-500".to_string(),
        ];
        let approx = limit_params(10);
        let exact = SearchParams {
            limit: Some(10),
            exact: true,
            ..SearchParams::default()
        };
        let control = open_writer(&control_path);
        bulk_add(&control, &entries).unwrap();
        let expected_single = control.search(&query, &exact).unwrap();
        let expected_bulk = control.bulk_search(&bulk_queries, &exact).unwrap();
        let expected_stored = control
            .bulk_search_stored(&stored_keys, 5, None, true, false)
            .unwrap();
        control.add("key-0", &replacement).unwrap();
        let expected_exact_after = control.search(&query, &exact).unwrap();
        let expected_approx_after = control.search(&query, &approx).unwrap();
        drop(control);
        {
            let db = open_writer(&path);
            bulk_add(&db, &entries).unwrap();
        }
        assert!(!snapshot_exists(&path));
        let opener = {
            let path = path.clone();
            thread::spawn(move || VecDb::open(&path, DIMS).unwrap())
        };
        let key = registry_key_for(&path).unwrap();
        let deadline = Instant::now() + Duration::from_secs(60);
        let joined = loop {
            assert!(Instant::now() < deadline);
            let registered =
                existing_path_slot(&key).is_some_and(|slot| lock_slot(&slot).holds_live());
            if registered {
                break VecDb::open_read_only(&path, DIMS).unwrap();
            }
            thread::yield_now();
        };
        let pin = joined.shared.state_read();
        assert!(pin.graph.is_none());
        assert_eq!(joined.search(&query, &approx).unwrap(), expected_single);
        assert_eq!(joined.search(&query, &exact).unwrap(), expected_single);
        assert_eq!(
            joined.bulk_search(&bulk_queries, &approx).unwrap(),
            expected_bulk
        );
        assert_eq!(
            joined
                .bulk_search_stored(&stored_keys, 5, None, false, false)
                .unwrap(),
            expected_stored
        );
        assert!(!opener.is_finished());
        let writer = VecDb::open(&path, DIMS).unwrap();
        assert!(Arc::ptr_eq(&writer.shared, &joined.shared));
        let adder = {
            let vector = replacement.clone();
            thread::spawn(move || {
                writer.add("key-0", &vector).unwrap();
                writer
            })
        };
        assert_eq!(joined.get("key-0").unwrap(), entries[0].1);
        assert!(!adder.is_finished());
        assert!(!opener.is_finished());
        drop(pin);
        let opened = opener.join().unwrap();
        assert!(snapshot_exists(&path));
        let writer = adder.join().unwrap();
        assert_eq!(writer.get("key-0").unwrap(), replacement);
        {
            let st = joined.shared.state_read();
            assert_eq!(
                st.graph.as_ref().unwrap().insert_ordinal(),
                COUNT as u64 + 1
            );
        }
        assert_eq!(opened.search(&query, &exact).unwrap(), expected_exact_after);
        assert_eq!(
            opened.search(&query, &approx).unwrap(),
            expected_approx_after
        );
        drop(opened);
        drop(writer);
        drop(joined);
        let reopened = open_writer(&path);
        {
            let st = reopened.shared.state_read();
            assert_eq!(
                st.graph.as_ref().unwrap().insert_ordinal(),
                COUNT as u64 + 1
            );
        }
        assert_eq!(
            reopened.search(&query, &approx).unwrap(),
            expected_approx_after
        );
    }

    fn attr(name: &str, value: AttrValue) -> Attribute {
        Attribute {
            name: name.to_string(),
            value,
        }
    }

    fn sample_attrs(seed: i64) -> Vec<Attribute> {
        vec![
            attr("model", AttrValue::Str(format!("model-{seed}"))),
            attr("version", AttrValue::I64(seed)),
            attr("indexed", AttrValue::Bool(seed % 2 == 0)),
            attr("score", AttrValue::F64(seed as f64 * 0.5)),
        ]
    }

    #[test]
    fn attrs_round_trip_and_upserts_replace_them_wholesale() {
        let dir = TempDir::new().unwrap();
        let db = open_writer(&dir.path().join("db"));
        let vector = seeded_unit_vector(1, DIMS);
        db.add_with_attrs("k", &vector, &sample_attrs(1)).unwrap();
        assert_eq!(db.get_attrs("k").unwrap(), sample_attrs(1));
        assert_eq!(db.get("k").unwrap(), vector);
        db.add_with_attrs("k", &vector, &[attr("only", AttrValue::Bool(true))])
            .unwrap();
        assert_eq!(
            db.get_attrs("k").unwrap(),
            vec![attr("only", AttrValue::Bool(true))]
        );
        db.add("k", &vector).unwrap();
        assert_eq!(db.get_attrs("k"), None);
        db.add_with_attrs("k", &vector, &sample_attrs(2)).unwrap();
        assert_eq!(db.get_attrs("k").unwrap(), sample_attrs(2));
        db.add_with_attrs("k", &vector, &[]).unwrap();
        assert_eq!(db.get_attrs("k"), None);
        db.add("plain", &vector).unwrap();
        assert_eq!(db.get_attrs("plain"), None);
        assert_eq!(db.get_attrs("missing"), None);
        assert!(matches!(
            db.add_with_attrs(
                "k",
                &vector,
                &[
                    attr("dup", AttrValue::Bool(true)),
                    attr("dup", AttrValue::Bool(false))
                ]
            ),
            Err(VecDbError::InvalidAttributes(_))
        ));
    }

    #[test]
    fn attrs_do_not_leak_across_remove_and_slot_recycle() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        let vector = seeded_unit_vector(2, DIMS);
        db.add_with_attrs("a", &vector, &sample_attrs(10)).unwrap();
        db.add_with_attrs("b", &vector, &sample_attrs(11)).unwrap();
        assert!(db.remove("a").unwrap());
        assert_eq!(db.get_attrs("a"), None);
        db.add("c", &vector).unwrap();
        assert_eq!(db.shared.state_read().arena.slot_of_key("c"), Some(0));
        assert_eq!(db.get_attrs("c"), None);
        assert!(db.remove("b").unwrap());
        db.add_with_attrs("d", &vector, &sample_attrs(12)).unwrap();
        assert_eq!(db.shared.state_read().arena.slot_of_key("d"), Some(1));
        assert_eq!(db.get_attrs("d").unwrap(), sample_attrs(12));
        db.add("a", &vector).unwrap();
        assert_eq!(db.get_attrs("a"), None);
        drop(db);
        let reopened = open_writer(&path);
        assert_eq!(reopened.get_attrs("a"), None);
        assert_eq!(reopened.get_attrs("b"), None);
        assert_eq!(reopened.get_attrs("c"), None);
        assert_eq!(reopened.get_attrs("d").unwrap(), sample_attrs(12));
    }

    #[test]
    fn attrs_replay_identically_across_reopen_and_read_only() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        let vector = seeded_unit_vector(3, DIMS);
        let ordered = vec![
            attr("zulu", AttrValue::I64(-5)),
            attr("alpha", AttrValue::Str("first".to_string())),
            attr("mike", AttrValue::F64(2.25)),
        ];
        db.add("plain", &vector).unwrap();
        db.add_with_attrs("rich", &vector, &ordered).unwrap();
        db.add_with_attrs("cleared", &vector, &sample_attrs(20))
            .unwrap();
        db.add("cleared", &vector).unwrap();
        db.add_with_attrs("removed", &vector, &sample_attrs(21))
            .unwrap();
        assert!(db.remove("removed").unwrap());
        db.add_with_attrs("recycled", &vector, &sample_attrs(22))
            .unwrap();
        db.flush().unwrap();
        drop(db);
        let verify = |db: &VecDb| {
            assert_eq!(db.get_attrs("plain"), None);
            assert_eq!(db.get_attrs("rich").unwrap(), ordered);
            assert_eq!(db.get_attrs("cleared"), None);
            assert_eq!(db.get_attrs("removed"), None);
            assert_eq!(db.get_attrs("recycled").unwrap(), sample_attrs(22));
        };
        let read_only = VecDb::open_read_only(&path, DIMS).unwrap();
        verify(&read_only);
        drop(read_only);
        let reopened = open_writer(&path);
        verify(&reopened);
        drop(reopened);
        fs::remove_file(snapshot_path(&path)).unwrap();
        let rebuilt = open_writer(&path);
        verify(&rebuilt);
    }

    #[test]
    fn attrs_follow_entries_through_compaction() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        let entries = bulk_entries(0, 120, 640);
        let (keys, vectors): (Vec<String>, Vec<Vec<f32>>) = entries.iter().cloned().unzip();
        let attrs: Vec<Option<Vec<Attribute>>> = (0..120)
            .map(|index| (index % 2 == 0).then(|| sample_attrs(index)))
            .collect();
        db.bulk_add_with_attrs(&keys, &vectors, &attrs).unwrap();
        let removals: Vec<String> = (0..64).map(|index| format!("key-{index}")).collect();
        assert_eq!(db.bulk_remove(&removals).unwrap(), 64);
        assert_eq!(db.stats().unwrap().dead_count, 0);
        let verify = |db: &VecDb| {
            for index in 64..120i64 {
                let key = format!("key-{index}");
                if index % 2 == 0 {
                    assert_eq!(db.get_attrs(&key).unwrap(), sample_attrs(index));
                } else {
                    assert_eq!(db.get_attrs(&key), None);
                }
            }
            for index in 0..64 {
                assert_eq!(db.get_attrs(&format!("key-{index}")), None);
            }
        };
        verify(&db);
        drop(db);
        let reopened = open_writer(&path);
        verify(&reopened);
    }

    #[test]
    fn attrs_survive_a_failed_compaction_and_its_retry() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        let entries = bulk_entries(0, 120, 910);
        let (keys, vectors): (Vec<String>, Vec<Vec<f32>>) = entries.iter().cloned().unzip();
        let attrs: Vec<Option<Vec<Attribute>>> =
            (0..120).map(|index| Some(sample_attrs(index))).collect();
        db.bulk_add_with_attrs(&keys, &vectors, &attrs).unwrap();
        let generation_before = generation_of(&path);
        fs::create_dir(temp_sibling(&path)).unwrap();
        let removals: Vec<String> = (0..64).map(|index| format!("key-{index}")).collect();
        assert_eq!(db.bulk_remove(&removals).unwrap(), 64);
        assert_eq!(db.stats().unwrap().dead_count, 128);
        assert_eq!(generation_of(&path), generation_before);
        let verify = |db: &VecDb| {
            for index in 64..120i64 {
                assert_eq!(
                    db.get_attrs(&format!("key-{index}")).unwrap(),
                    sample_attrs(index)
                );
            }
            for index in 0..64 {
                assert_eq!(db.get_attrs(&format!("key-{index}")), None);
            }
        };
        verify(&db);
        fs::remove_dir(temp_sibling(&path)).unwrap();
        let rewrite = |range: std::ops::Range<usize>| {
            let (keys, vectors): (Vec<String>, Vec<Vec<f32>>) =
                bulk_entries(range.start, range.len(), 910)
                    .iter()
                    .cloned()
                    .unzip();
            let attrs: Vec<Option<Vec<Attribute>>> = range
                .map(|index| Some(sample_attrs(index as i64)))
                .collect();
            db.bulk_add_with_attrs(&keys, &vectors, &attrs).unwrap();
        };
        rewrite(64..120);
        assert_eq!(db.stats().unwrap().dead_count, 184);
        assert_eq!(generation_of(&path), generation_before);
        verify(&db);
        rewrite(64..72);
        assert_eq!(db.stats().unwrap().dead_count, 0);
        assert_ne!(generation_of(&path), generation_before);
        verify(&db);
        drop(db);
        let reopened = open_writer(&path);
        verify(&reopened);
    }

    #[test]
    fn bulk_attrs_validate_before_any_io() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("db");
        let db = open_writer(&path);
        let vector = seeded_unit_vector(5, DIMS);
        db.add("seed", &vector).unwrap();
        let log_bytes = db.stats().unwrap().log_bytes;
        let keys = vec!["x".to_string(), "y".to_string()];
        let vectors = vec![vector.clone(), vector.clone()];
        assert!(matches!(
            db.bulk_add_with_attrs(&keys, &vectors, &[None]),
            Err(VecDbError::LengthMismatch {
                keys: 2,
                vectors: 1
            })
        ));
        let poisoned = vec![
            Some(sample_attrs(1)),
            Some(vec![
                attr("dup", AttrValue::Bool(true)),
                attr("dup", AttrValue::Bool(false)),
            ]),
        ];
        assert!(matches!(
            db.bulk_add_with_attrs(&keys, &vectors, &poisoned),
            Err(VecDbError::InvalidAttributes(_))
        ));
        assert_eq!(db.len(), 1);
        assert!(!db.contains("x"));
        assert_eq!(db.stats().unwrap().log_bytes, log_bytes);
        let valid = vec![Some(sample_attrs(7)), None];
        db.bulk_add_with_attrs(&keys, &vectors, &valid).unwrap();
        assert_eq!(
            db.bulk_get_attrs(&[
                "x".to_string(),
                "missing".to_string(),
                "y".to_string(),
                "seed".to_string()
            ]),
            vec![Some(sample_attrs(7)), None, None, None]
        );
        assert_eq!(db.get_attrs("x").unwrap(), sample_attrs(7));
        let read_only = VecDb::open_read_only(&path, DIMS).unwrap();
        assert!(matches!(
            read_only.bulk_add_with_attrs(&keys, &vectors, &[None]),
            Err(VecDbError::LengthMismatch { .. })
        ));
        assert!(matches!(
            read_only.bulk_add_with_attrs(&keys, &vectors, &valid),
            Err(VecDbError::ReadOnly)
        ));
    }

    #[test]
    fn reset_clears_attrs() {
        let dir = TempDir::new().unwrap();
        let db = open_writer(&dir.path().join("db"));
        let vector = seeded_unit_vector(6, DIMS);
        db.add_with_attrs("k", &vector, &sample_attrs(30)).unwrap();
        db.reset().unwrap();
        assert_eq!(db.get_attrs("k"), None);
        db.add("k", &vector).unwrap();
        assert_eq!(db.get_attrs("k"), None);
        db.add_with_attrs("k", &vector, &sample_attrs(31)).unwrap();
        assert_eq!(db.get_attrs("k").unwrap(), sample_attrs(31));
    }

    #[test]
    fn memory_estimate_counts_the_attr_table_once_allocated() {
        let dir = TempDir::new().unwrap();
        let db = open_writer(&dir.path().join("db"));
        let vector = seeded_unit_vector(7, DIMS);
        db.add("k", &vector).unwrap();
        let without_attrs = db.stats().unwrap().approximate_memory_bytes;
        db.add_with_attrs(
            "k",
            &vector,
            &[attr("blob", AttrValue::Str("x".repeat(512)))],
        )
        .unwrap();
        let with_attrs = db.stats().unwrap().approximate_memory_bytes;
        assert!(with_attrs > without_attrs + 512);
    }
}
