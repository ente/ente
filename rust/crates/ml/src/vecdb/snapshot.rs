use std::fs::File;
use std::io::{ErrorKind, Write};
use std::path::{Path, PathBuf};

use super::VecDbError;
use super::crc::crc32;
use super::graph::{Graph, GraphNodeParts};
use super::log::{remove_if_present, rename_with_windows_fallback, sync_parent_dir};

const MAGIC: [u8; 4] = *b"EVDG";
const FORMAT_VERSION: u16 = 1;
const NO_ENTRY_POINT: u32 = u32::MAX;
const CRC_LEN: usize = 4;
const FIXED_PREFIX_LEN: usize = 47;
const MIN_SNAPSHOT_LEN: usize = FIXED_PREFIX_LEN + CRC_LEN;
const MIN_NODE_LEN: usize = 7;

pub(crate) struct LoadedSnapshot {
    pub(crate) covered_log_offset: u64,
    pub(crate) insert_ordinal: u64,
    pub(crate) entry_point: Option<u32>,
    pub(crate) parts: Vec<GraphNodeParts>,
}

pub(crate) fn snapshot_path(log_path: &Path) -> PathBuf {
    append_suffix(log_path, ".graph")
}

pub(crate) fn write_snapshot(
    log_path: &Path,
    generation: [u8; 16],
    covered_log_offset: u64,
    graph: &Graph,
) -> Result<(), VecDbError> {
    let bytes = encode_snapshot(&generation, covered_log_offset, graph);
    let target = snapshot_path(log_path);
    let temp = temp_snapshot_path(log_path);
    write_and_swap(&bytes, &temp, &target).inspect_err(|_| {
        let _ = std::fs::remove_file(&temp);
    })
}

pub(crate) fn load_snapshot(
    log_path: &Path,
    expected_generation: [u8; 16],
) -> Option<LoadedSnapshot> {
    let path = snapshot_path(log_path);
    let bytes = match std::fs::read(&path) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == ErrorKind::NotFound => return None,
        Err(error) => {
            log::debug!("discarding snapshot {}: {error}", path.display());
            return None;
        }
    };
    match decode_snapshot(&bytes, &expected_generation) {
        Ok(loaded) => Some(loaded),
        Err(reason) => {
            log::debug!("discarding snapshot {}: {reason}", path.display());
            None
        }
    }
}

pub(crate) fn remove_snapshot(log_path: &Path) -> Result<(), VecDbError> {
    remove_if_present(&snapshot_path(log_path))?;
    remove_if_present(&temp_snapshot_path(log_path))
}

fn encode_snapshot(generation: &[u8; 16], covered_log_offset: u64, graph: &Graph) -> Vec<u8> {
    let mut bytes = Vec::new();
    bytes.extend_from_slice(&MAGIC);
    bytes.extend_from_slice(&FORMAT_VERSION.to_le_bytes());
    bytes.extend_from_slice(generation);
    bytes.extend_from_slice(&covered_log_offset.to_le_bytes());
    bytes.extend_from_slice(&graph.insert_ordinal().to_le_bytes());
    let entry_marker = graph.entry_point().unwrap_or(NO_ENTRY_POINT);
    bytes.extend_from_slice(&entry_marker.to_le_bytes());
    let top_level = graph
        .entry_point()
        .and_then(|slot| graph.level_of(slot))
        .unwrap_or(0);
    bytes.push(top_level);
    bytes.extend_from_slice(&(graph.node_count() as u32).to_le_bytes());
    for slot in graph.slots() {
        let level = graph.level_of(slot).unwrap_or(0);
        bytes.extend_from_slice(&slot.to_le_bytes());
        bytes.push(level);
        for layer in 0..=level {
            let neighbors = graph.neighbors_of(slot, layer);
            bytes.extend_from_slice(&(neighbors.len() as u16).to_le_bytes());
            for &neighbor in neighbors {
                bytes.extend_from_slice(&neighbor.to_le_bytes());
            }
        }
    }
    let crc = crc32(&bytes[MAGIC.len()..]);
    bytes.extend_from_slice(&crc.to_le_bytes());
    bytes
}

fn decode_snapshot(bytes: &[u8], expected_generation: &[u8; 16]) -> Result<LoadedSnapshot, String> {
    if bytes.len() < MIN_SNAPSHOT_LEN {
        return Err(format!(
            "{} bytes is shorter than the {MIN_SNAPSHOT_LEN}-byte minimum",
            bytes.len()
        ));
    }
    if bytes[0..4] != MAGIC {
        return Err(format!("bad magic {:02x?}", &bytes[0..4]));
    }
    let body_end = bytes.len() - CRC_LEN;
    let stored_crc = u32::from_le_bytes([
        bytes[body_end],
        bytes[body_end + 1],
        bytes[body_end + 2],
        bytes[body_end + 3],
    ]);
    let computed_crc = crc32(&bytes[MAGIC.len()..body_end]);
    if stored_crc != computed_crc {
        return Err(format!(
            "crc mismatch: stored {stored_crc:08x}, computed {computed_crc:08x}"
        ));
    }
    let mut reader = BodyReader {
        bytes: &bytes[..body_end],
        position: MAGIC.len(),
    };
    let version = reader.read_u16().ok_or("truncated header")?;
    if version != FORMAT_VERSION {
        return Err(format!("unsupported snapshot format version {version}"));
    }
    let generation: [u8; 16] = reader
        .take(16)
        .and_then(|slice| slice.try_into().ok())
        .ok_or("truncated header")?;
    if generation != *expected_generation {
        return Err("generation does not match the log".to_string());
    }
    let covered_log_offset = reader.read_u64().ok_or("truncated header")?;
    let insert_ordinal = reader.read_u64().ok_or("truncated header")?;
    let entry_marker = reader.read_u32().ok_or("truncated header")?;
    let top_level = reader.read_u8().ok_or("truncated header")?;
    let node_count = reader.read_u32().ok_or("truncated header")? as usize;
    let mut parts = Vec::with_capacity(node_count.min(reader.remaining() / MIN_NODE_LEN));
    for _ in 0..node_count {
        let slot = reader.read_u32().ok_or("truncated node")?;
        let level = reader.read_u8().ok_or("truncated node")?;
        let mut neighbors = Vec::with_capacity(level as usize + 1);
        for _ in 0..=level {
            let count = reader.read_u16().ok_or("truncated neighbor list")? as usize;
            let raw = reader
                .take(count * size_of::<u32>())
                .ok_or("truncated neighbor list")?;
            neighbors.push(
                raw.as_chunks::<4>()
                    .0
                    .iter()
                    .map(|chunk| u32::from_le_bytes(*chunk))
                    .collect(),
            );
        }
        parts.push(GraphNodeParts {
            slot,
            level,
            neighbors,
        });
    }
    if !reader.is_exhausted() {
        return Err(format!(
            "{} unparsed bytes after {node_count} nodes",
            reader.remaining()
        ));
    }
    let entry_point = (entry_marker != NO_ENTRY_POINT).then_some(entry_marker);
    if entry_point.is_none() != parts.is_empty() {
        return Err(format!(
            "entry point marker {entry_marker:08x} disagrees with node count {node_count}"
        ));
    }
    let max_level = parts.iter().map(|part| part.level).max().unwrap_or(0);
    if top_level != max_level {
        return Err(format!(
            "top level {top_level} disagrees with the nodes' max level {max_level}"
        ));
    }
    Ok(LoadedSnapshot {
        covered_log_offset,
        insert_ordinal,
        entry_point,
        parts,
    })
}

struct BodyReader<'a> {
    bytes: &'a [u8],
    position: usize,
}

impl<'a> BodyReader<'a> {
    fn take(&mut self, len: usize) -> Option<&'a [u8]> {
        let end = self.position.checked_add(len)?;
        if end > self.bytes.len() {
            return None;
        }
        let slice = &self.bytes[self.position..end];
        self.position = end;
        Some(slice)
    }

    fn read_u8(&mut self) -> Option<u8> {
        Some(self.take(1)?[0])
    }

    fn read_u16(&mut self) -> Option<u16> {
        self.take(2)?.try_into().ok().map(u16::from_le_bytes)
    }

    fn read_u32(&mut self) -> Option<u32> {
        self.take(4)?.try_into().ok().map(u32::from_le_bytes)
    }

    fn read_u64(&mut self) -> Option<u64> {
        self.take(8)?.try_into().ok().map(u64::from_le_bytes)
    }

    fn remaining(&self) -> usize {
        self.bytes.len() - self.position
    }

    fn is_exhausted(&self) -> bool {
        self.position == self.bytes.len()
    }
}

fn write_and_swap(bytes: &[u8], temp: &Path, target: &Path) -> Result<(), VecDbError> {
    let mut file = File::create(temp).map_err(|source| VecDbError::io(temp, source))?;
    file.write_all(bytes)
        .map_err(|source| VecDbError::io(temp, source))?;
    file.sync_all()
        .map_err(|source| VecDbError::io(temp, source))?;
    drop(file);
    rename_with_windows_fallback(temp, target)?;
    let _ = sync_parent_dir(target);
    Ok(())
}

fn temp_snapshot_path(log_path: &Path) -> PathBuf {
    append_suffix(log_path, ".graph.tmp")
}

fn append_suffix(path: &Path, suffix: &str) -> PathBuf {
    let mut extended = path.as_os_str().to_os_string();
    extended.push(suffix);
    PathBuf::from(extended)
}

#[cfg(test)]
mod tests {
    use tempfile::TempDir;

    use super::super::SearchParams;
    use super::super::arena::{UpsertOutcome, VectorArena};
    use super::super::graph::{PendingSlots, search};
    use super::super::kernel::splitmix64;
    use super::super::test_support::{assert_identical_graphs, stale_downward_edge_exists};
    use super::*;

    const GOLDEN: [u8; 94] = [
        0x45, 0x56, 0x44, 0x47, 0x01, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x2c, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x03, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00,
        0x00, 0x00, 0x01, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x01, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00,
        0x10, 0xe9, 0x5e, 0xe7,
    ];

    fn golden_generation() -> [u8; 16] {
        std::array::from_fn(|index| index as u8)
    }

    fn golden_graph() -> Graph {
        Graph::from_parts(
            Some(1),
            vec![
                GraphNodeParts {
                    slot: 0,
                    level: 0,
                    neighbors: vec![vec![1]],
                },
                GraphNodeParts {
                    slot: 1,
                    level: 1,
                    neighbors: vec![vec![0, 2], vec![0]],
                },
                GraphNodeParts {
                    slot: 2,
                    level: 0,
                    neighbors: vec![vec![1]],
                },
            ],
            3,
            7,
        )
        .unwrap()
    }

    fn load_golden(log_path: &Path) -> Option<LoadedSnapshot> {
        load_snapshot(log_path, golden_generation())
    }

    fn refresh_crc(bytes: &mut [u8]) {
        let body_end = bytes.len() - CRC_LEN;
        let crc = crc32(&bytes[MAGIC.len()..body_end]);
        bytes[body_end..].copy_from_slice(&crc.to_le_bytes());
    }

    fn assert_discarded(mutate: impl FnOnce(&mut Vec<u8>)) {
        let dir = TempDir::new().unwrap();
        let log_path = dir.path().join("log");
        let mut bytes = GOLDEN.to_vec();
        mutate(&mut bytes);
        std::fs::write(snapshot_path(&log_path), &bytes).unwrap();
        assert!(load_golden(&log_path).is_none());
    }

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

    fn build_arena(count: usize, dims: usize, seed: u64) -> VectorArena {
        let mut arena = VectorArena::new(dims).unwrap();
        for index in 0..count {
            arena
                .upsert(
                    &format!("key-{index}"),
                    &seeded_unit_vector(seed + index as u64, dims),
                )
                .unwrap();
        }
        arena
    }

    fn churned_fixture(dims: usize) -> (VectorArena, Graph) {
        let mut arena = build_arena(600, dims, 0x00A1_0000);
        let mut graph = Graph::rebuild(&arena);
        for index in [3, 41, 87, 150, 199] {
            arena.remove(&format!("key-{index}")).unwrap();
        }
        let mut stale_seen = false;
        for round in 0..40u64 {
            let victim = graph
                .entry_point()
                .filter(|&slot| arena.is_alive(slot))
                .unwrap_or_else(|| arena.live_slots().next().unwrap());
            let key = arena.key_of_slot(victim).unwrap().to_string();
            assert_eq!(
                arena
                    .upsert(&key, &seeded_unit_vector(0x00A2_0000 + round, dims))
                    .unwrap(),
                UpsertOutcome::ReplacedInPlace(victim)
            );
            graph.reinsert(victim, &arena);
            stale_seen |= stale_downward_edge_exists(&graph);
        }
        let UpsertOutcome::RecycledSlot(recycled) = arena
            .upsert("recycled", &seeded_unit_vector(0x00A3_0000, dims))
            .unwrap()
        else {
            panic!("expected a recycled slot");
        };
        graph.reinsert(recycled, &arena);
        assert!(stale_seen);
        (arena, graph)
    }

    fn params(limit: Option<usize>, max_distance: Option<f32>) -> SearchParams {
        SearchParams {
            limit,
            max_distance,
            exact: false,
            allowed_keys: None,
        }
    }

    #[test]
    fn snapshot_path_appends_the_graph_extension() {
        assert_eq!(
            snapshot_path(Path::new("/a/vectors")),
            Path::new("/a/vectors.graph")
        );
        assert_eq!(
            snapshot_path(Path::new("/a/vectors.db")),
            Path::new("/a/vectors.db.graph")
        );
        assert_eq!(
            temp_snapshot_path(Path::new("/a/vectors.db")),
            Path::new("/a/vectors.db.graph.tmp")
        );
    }

    #[test]
    fn golden_bytes_pin_format_v1() {
        let dir = TempDir::new().unwrap();
        let written_path = dir.path().join("written");
        write_snapshot(&written_path, golden_generation(), 300, &golden_graph()).unwrap();
        assert_eq!(std::fs::read(snapshot_path(&written_path)).unwrap(), GOLDEN);
        let literal_path = dir.path().join("literal");
        std::fs::write(snapshot_path(&literal_path), GOLDEN).unwrap();
        let loaded = load_golden(&literal_path).unwrap();
        assert_eq!(loaded.covered_log_offset, 300);
        assert_eq!(loaded.insert_ordinal, 7);
        assert_eq!(loaded.entry_point, Some(1));
        assert_eq!(loaded.parts.len(), 3);
        let expected: [(u32, u8, Vec<Vec<u32>>); 3] = [
            (0, 0, vec![vec![1]]),
            (1, 1, vec![vec![0, 2], vec![0]]),
            (2, 0, vec![vec![1]]),
        ];
        for (part, (slot, level, neighbors)) in loaded.parts.iter().zip(&expected) {
            assert_eq!(part.slot, *slot);
            assert_eq!(part.level, *level);
            assert_eq!(&part.neighbors, neighbors);
        }
        let rebuilt =
            Graph::from_parts(loaded.entry_point, loaded.parts, 3, loaded.insert_ordinal).unwrap();
        assert_identical_graphs(&rebuilt, &golden_graph());
        assert_eq!(rebuilt.insert_ordinal(), 7);
    }

    #[test]
    fn roundtrip_reconstructs_identical_graph_and_results() {
        let dims = 16;
        let (arena, graph) = churned_fixture(dims);
        let dir = TempDir::new().unwrap();
        let log_path = dir.path().join("log");
        let generation = [7u8; 16];
        write_snapshot(&log_path, generation, 4096, &graph).unwrap();
        assert!(!temp_snapshot_path(&log_path).exists());
        let loaded = load_snapshot(&log_path, generation).unwrap();
        assert_eq!(loaded.covered_log_offset, 4096);
        assert_eq!(loaded.insert_ordinal, graph.insert_ordinal());
        assert_eq!(loaded.entry_point, graph.entry_point());
        let rebuilt = Graph::from_parts(
            loaded.entry_point,
            loaded.parts,
            arena.slot_count(),
            loaded.insert_ordinal,
        )
        .unwrap();
        assert_identical_graphs(&rebuilt, &graph);
        assert_eq!(rebuilt.insert_ordinal(), graph.insert_ordinal());
        for seed in 0..6u64 {
            let query = arena
                .pack_query(&seeded_unit_vector(0x00A4_0000 + seed, dims))
                .unwrap();
            for search_params in [
                params(Some(10), None),
                params(None, Some(0.9)),
                params(Some(3), Some(1.2)),
            ] {
                let original = search(
                    &graph,
                    &arena,
                    &query,
                    &search_params,
                    None,
                    &PendingSlots::default(),
                );
                let reconstructed = search(
                    &rebuilt,
                    &arena,
                    &query,
                    &search_params,
                    None,
                    &PendingSlots::default(),
                );
                assert_eq!(original, reconstructed);
                assert!(!original.is_empty());
            }
        }
    }

    #[test]
    fn empty_graph_round_trips() {
        let dir = TempDir::new().unwrap();
        let log_path = dir.path().join("log");
        write_snapshot(&log_path, [3u8; 16], 32, &Graph::new()).unwrap();
        assert_eq!(
            std::fs::read(snapshot_path(&log_path)).unwrap().len(),
            MIN_SNAPSHOT_LEN
        );
        let loaded = load_snapshot(&log_path, [3u8; 16]).unwrap();
        assert_eq!(loaded.covered_log_offset, 32);
        assert_eq!(loaded.insert_ordinal, 0);
        assert_eq!(loaded.entry_point, None);
        assert!(loaded.parts.is_empty());
        let rebuilt =
            Graph::from_parts(loaded.entry_point, loaded.parts, 0, loaded.insert_ordinal).unwrap();
        assert_eq!(rebuilt.entry_point(), None);
        assert_eq!(rebuilt.node_count(), 0);
    }

    #[test]
    fn identical_graphs_serialize_to_identical_bytes() {
        let dims = 16;
        let arena = build_arena(150, dims, 0x00B1_0000);
        let first = Graph::rebuild(&arena);
        let second = Graph::rebuild(&arena);
        let dir = TempDir::new().unwrap();
        let first_path = dir.path().join("first");
        let second_path = dir.path().join("second");
        write_snapshot(&first_path, [5u8; 16], 777, &first).unwrap();
        write_snapshot(&second_path, [5u8; 16], 777, &second).unwrap();
        let first_bytes = std::fs::read(snapshot_path(&first_path)).unwrap();
        let second_bytes = std::fs::read(snapshot_path(&second_path)).unwrap();
        assert_eq!(first_bytes, second_bytes);
    }

    #[test]
    fn missing_snapshot_loads_none() {
        let dir = TempDir::new().unwrap();
        let log_path = dir.path().join("log");
        assert!(load_golden(&log_path).is_none());
    }

    #[test]
    fn every_truncation_loads_none() {
        let dir = TempDir::new().unwrap();
        let log_path = dir.path().join("log");
        let path = snapshot_path(&log_path);
        for cut in 0..GOLDEN.len() {
            std::fs::write(&path, &GOLDEN[..cut]).unwrap();
            assert!(load_golden(&log_path).is_none(), "cut at {cut} parsed");
        }
        std::fs::write(&path, GOLDEN).unwrap();
        assert!(load_golden(&log_path).is_some());
    }

    #[test]
    fn fuzzed_bytes_never_panic_decode_from_parts_or_search() {
        let dims = 8;
        let arena = build_arena(3, dims, 0x00F0_0000);
        let query = arena
            .pack_query(&seeded_unit_vector(0x00F1_0000, dims))
            .unwrap();
        let generation = golden_generation();
        let mut decoded = 0usize;
        let mut searched = 0usize;
        let mut exercise = |bytes: &[u8]| {
            let Ok(loaded) = decode_snapshot(bytes, &generation) else {
                return;
            };
            decoded += 1;
            let Ok(graph) = Graph::from_parts(
                loaded.entry_point,
                loaded.parts,
                arena.slot_count(),
                loaded.insert_ordinal,
            ) else {
                return;
            };
            for search_params in [params(Some(2), None), params(None, Some(2.5))] {
                let found = search(
                    &graph,
                    &arena,
                    &query,
                    &search_params,
                    None,
                    &PendingSlots::default(),
                );
                assert!(found.len() <= 3);
            }
            searched += 1;
        };
        exercise(&GOLDEN);
        let mut state = 0x00F2_0000u64;
        for round in 0..4000u64 {
            let mut bytes = GOLDEN.to_vec();
            let flips = 1 + (splitmix64(&mut state) % 4) as usize;
            for _ in 0..flips {
                let index = (splitmix64(&mut state) as usize) % bytes.len();
                bytes[index] ^= (splitmix64(&mut state) % 255 + 1) as u8;
            }
            if round % 2 == 0 {
                refresh_crc(&mut bytes);
            }
            exercise(&bytes);
        }
        for _ in 0..2000u64 {
            let len = (splitmix64(&mut state) % 160) as usize;
            let bytes: Vec<u8> = (0..len).map(|_| splitmix64(&mut state) as u8).collect();
            exercise(&bytes);
        }
        assert!(decoded >= 1);
        assert!(searched >= 1);
    }

    #[test]
    fn forged_out_of_range_slot_is_rejected_by_from_parts() {
        let slot = u32::MAX - 1;
        let mut bytes = Vec::new();
        bytes.extend_from_slice(&MAGIC);
        bytes.extend_from_slice(&FORMAT_VERSION.to_le_bytes());
        bytes.extend_from_slice(&golden_generation());
        bytes.extend_from_slice(&300u64.to_le_bytes());
        bytes.extend_from_slice(&7u64.to_le_bytes());
        bytes.extend_from_slice(&slot.to_le_bytes());
        bytes.push(0);
        bytes.extend_from_slice(&1u32.to_le_bytes());
        bytes.extend_from_slice(&slot.to_le_bytes());
        bytes.push(0);
        bytes.extend_from_slice(&0u16.to_le_bytes());
        let crc = crc32(&bytes[MAGIC.len()..]);
        bytes.extend_from_slice(&crc.to_le_bytes());
        let loaded = decode_snapshot(&bytes, &golden_generation()).unwrap();
        assert_eq!(loaded.entry_point, Some(slot));
        assert!(
            Graph::from_parts(loaded.entry_point, loaded.parts, 3, loaded.insert_ordinal).is_err()
        );
    }

    #[test]
    fn bad_magic_is_discarded() {
        assert_discarded(|bytes| bytes[0] = b'X');
    }

    #[test]
    fn bad_version_is_discarded() {
        assert_discarded(|bytes| {
            bytes[4..6].copy_from_slice(&2u16.to_le_bytes());
            refresh_crc(bytes);
        });
    }

    #[test]
    fn generation_mismatch_is_discarded() {
        let dir = TempDir::new().unwrap();
        let log_path = dir.path().join("log");
        std::fs::write(snapshot_path(&log_path), GOLDEN).unwrap();
        assert!(load_snapshot(&log_path, [9u8; 16]).is_none());
        assert!(load_golden(&log_path).is_some());
    }

    #[test]
    fn loading_exposes_the_covered_offset_for_the_caller_to_judge() {
        let dir = TempDir::new().unwrap();
        let log_path = dir.path().join("log");
        std::fs::write(snapshot_path(&log_path), GOLDEN).unwrap();
        let loaded = load_snapshot(&log_path, golden_generation()).unwrap();
        assert_eq!(loaded.covered_log_offset, 300);
    }

    #[test]
    fn flipped_body_byte_is_discarded() {
        assert_discarded(|bytes| bytes[65] ^= 0x01);
    }

    #[test]
    fn trailing_garbage_is_discarded() {
        assert_discarded(|bytes| bytes.extend_from_slice(&[0x5A; 5]));
        assert_discarded(|bytes| {
            let crc_start = bytes.len() - CRC_LEN;
            bytes.splice(crc_start..crc_start, [0u8; 4]);
            refresh_crc(bytes);
        });
    }

    #[test]
    fn wrong_node_count_is_discarded() {
        assert_discarded(|bytes| {
            bytes[43] = 4;
            refresh_crc(bytes);
        });
        assert_discarded(|bytes| {
            bytes[43] = 2;
            refresh_crc(bytes);
        });
    }

    #[test]
    fn oversized_neighbor_count_is_discarded() {
        assert_discarded(|bytes| {
            bytes[52..54].copy_from_slice(&u16::MAX.to_le_bytes());
            refresh_crc(bytes);
        });
    }

    #[test]
    fn wrong_top_level_is_discarded() {
        assert_discarded(|bytes| {
            bytes[42] = 0;
            refresh_crc(bytes);
        });
        assert_discarded(|bytes| {
            bytes[42] = 2;
            refresh_crc(bytes);
        });
    }

    #[test]
    fn entry_marker_inconsistencies_are_discarded() {
        assert_discarded(|bytes| {
            bytes[38..42].copy_from_slice(&NO_ENTRY_POINT.to_le_bytes());
            refresh_crc(bytes);
        });
        let dir = TempDir::new().unwrap();
        let log_path = dir.path().join("log");
        write_snapshot(&log_path, golden_generation(), 300, &Graph::new()).unwrap();
        let path = snapshot_path(&log_path);
        let mut bytes = std::fs::read(&path).unwrap();
        bytes[38..42].copy_from_slice(&0u32.to_le_bytes());
        refresh_crc(&mut bytes);
        std::fs::write(&path, &bytes).unwrap();
        assert!(load_golden(&log_path).is_none());
    }

    #[test]
    fn failed_write_leaves_no_temp_file() {
        let dir = TempDir::new().unwrap();
        let log_path = dir.path().join("log");
        std::fs::create_dir(snapshot_path(&log_path)).unwrap();
        let error = write_snapshot(&log_path, [1u8; 16], 0, &Graph::new()).unwrap_err();
        assert!(matches!(error, VecDbError::Io { .. }));
        assert!(!temp_snapshot_path(&log_path).exists());
        assert!(snapshot_path(&log_path).is_dir());
        let orphan_path = dir.path().join("absent").join("log");
        assert!(write_snapshot(&orphan_path, [1u8; 16], 0, &Graph::new()).is_err());
        assert!(!temp_snapshot_path(&orphan_path).exists());
        assert!(!snapshot_path(&orphan_path).exists());
    }

    #[test]
    fn rewrite_replaces_the_previous_snapshot() {
        let dir = TempDir::new().unwrap();
        let log_path = dir.path().join("log");
        let generation = golden_generation();
        write_snapshot(&log_path, generation, 100, &golden_graph()).unwrap();
        write_snapshot(&log_path, generation, 999, &golden_graph()).unwrap();
        assert!(!temp_snapshot_path(&log_path).exists());
        let loaded = load_snapshot(&log_path, generation).unwrap();
        assert_eq!(loaded.covered_log_offset, 999);
        assert_eq!(loaded.parts.len(), 3);
    }

    #[test]
    fn remove_snapshot_deletes_both_files_and_tolerates_absence() {
        let dir = TempDir::new().unwrap();
        let log_path = dir.path().join("log");
        remove_snapshot(&log_path).unwrap();
        write_snapshot(&log_path, [2u8; 16], 0, &Graph::new()).unwrap();
        std::fs::write(temp_snapshot_path(&log_path), b"leftover").unwrap();
        assert!(snapshot_path(&log_path).exists());
        assert!(temp_snapshot_path(&log_path).exists());
        remove_snapshot(&log_path).unwrap();
        assert!(!snapshot_path(&log_path).exists());
        assert!(!temp_snapshot_path(&log_path).exists());
        remove_snapshot(&log_path).unwrap();
    }
}
