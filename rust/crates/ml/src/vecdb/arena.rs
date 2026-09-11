use std::collections::HashMap;

use super::kernel::{
    F32Kernel, I8Kernel, Lane, LaneI8, StoredVector, VectorKernel, VectorPayload, dequantize,
    pack_lanes, pack_lanes_i8, pack_lanes_i8_into, pack_lanes_into, quantize_for, unpack_lanes,
    unpack_lanes_i8, validate_dims,
};
use super::{DistanceMetric, StorageKind, VecDbError};

pub(crate) const VECTORS_PER_CHUNK: usize = 4096;
pub(crate) const MAX_KEY_BYTES: usize = 256;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum UpsertOutcome {
    NewSlot(u32),
    RecycledSlot(u32),
    ReplacedInPlace(u32),
}

pub(crate) fn validate_key(key: &str) -> Result<(), VecDbError> {
    if key.is_empty() {
        return Err(VecDbError::InvalidKey("key is empty".to_string()));
    }
    if key.len() > MAX_KEY_BYTES {
        return Err(VecDbError::InvalidKey(format!(
            "key is {} bytes, limit is {MAX_KEY_BYTES}",
            key.len()
        )));
    }
    Ok(())
}

enum Storage {
    F32 {
        chunks: Vec<Vec<Lane>>,
    },
    I8 {
        chunks: Vec<Vec<LaneI8>>,
        scales: Vec<f32>,
    },
}

impl Storage {
    fn kind(&self) -> StorageKind {
        match self {
            Self::F32 { .. } => StorageKind::F32,
            Self::I8 { .. } => StorageKind::I8,
        }
    }

    fn chunk_count(&self) -> usize {
        match self {
            Self::F32 { chunks } => chunks.len(),
            Self::I8 { chunks, .. } => chunks.len(),
        }
    }

    fn push_chunk(&mut self, lanes_per_vector: usize) {
        match self {
            Self::F32 { chunks } => {
                chunks.push(vec![Lane::ZERO; VECTORS_PER_CHUNK * lanes_per_vector]);
            }
            Self::I8 { chunks, .. } => {
                chunks.push(vec![LaneI8::ZERO; VECTORS_PER_CHUNK * lanes_per_vector]);
            }
        }
    }
}

pub(crate) enum PackedQuery {
    F32(Vec<Lane>, f64),
    I8 {
        scale: f32,
        lanes: Vec<LaneI8>,
        norm: f64,
    },
}

impl PackedQuery {
    pub(crate) fn as_query(&self) -> Query<'_> {
        match self {
            Self::F32(lanes, norm) => Query::F32(lanes, *norm),
            Self::I8 { scale, lanes, norm } => Query::I8 {
                scale: *scale,
                lanes,
                norm: *norm,
            },
        }
    }
}

#[derive(Clone, Copy)]
pub(crate) enum Query<'a> {
    F32(&'a [Lane], f64),
    I8 {
        scale: f32,
        lanes: &'a [LaneI8],
        norm: f64,
    },
}

impl Query<'_> {
    pub(crate) fn is_finite(&self) -> bool {
        match self {
            Self::F32(lanes, _) => lanes
                .iter()
                .all(|lane| lane.to_array().iter().all(|value| value.is_finite())),
            Self::I8 { scale, .. } => scale.is_finite(),
        }
    }
}

pub(crate) struct VectorArena {
    dims: usize,
    lanes_per_vector: usize,
    storage: Storage,
    metric: DistanceMetric,
    norms: Vec<f64>,
    keys_to_slots: HashMap<Box<str>, u32>,
    slots_to_keys: Vec<Box<str>>,
    alive: Vec<u64>,
    free_slots: Vec<u32>,
    live_count: usize,
}

impl VectorArena {
    #[cfg(test)]
    pub(crate) fn new(dims: usize) -> Result<Self, VecDbError> {
        Self::with_storage(dims, StorageKind::F32)
    }

    #[cfg(test)]
    pub(crate) fn with_storage(dims: usize, storage: StorageKind) -> Result<Self, VecDbError> {
        Self::with_metric(dims, storage, DistanceMetric::InnerProduct)
    }

    pub(crate) fn with_metric(
        dims: usize,
        storage: StorageKind,
        metric: DistanceMetric,
    ) -> Result<Self, VecDbError> {
        validate_dims(dims, storage)?;
        let storage = match storage {
            StorageKind::F32 => Storage::F32 { chunks: Vec::new() },
            StorageKind::I8 => Storage::I8 {
                chunks: Vec::new(),
                scales: Vec::new(),
            },
        };
        Ok(Self {
            dims,
            lanes_per_vector: dims / storage.kind().lane_width(),
            storage,
            metric,
            norms: Vec::new(),
            keys_to_slots: HashMap::new(),
            slots_to_keys: Vec::new(),
            alive: Vec::new(),
            free_slots: Vec::new(),
            live_count: 0,
        })
    }

    pub(crate) fn metric(&self) -> DistanceMetric {
        self.metric
    }

    pub(crate) fn dims(&self) -> usize {
        self.dims
    }

    pub(crate) fn storage_kind(&self) -> StorageKind {
        self.storage.kind()
    }

    pub(crate) fn live_count(&self) -> usize {
        self.live_count
    }

    pub(crate) fn dead_count(&self) -> usize {
        self.free_slots.len()
    }

    pub(crate) fn slot_count(&self) -> usize {
        self.slots_to_keys.len()
    }

    pub(crate) fn is_empty(&self) -> bool {
        self.live_count == 0
    }

    pub(crate) fn vector_memory_bytes(&self) -> usize {
        let vectors = self.storage.chunk_count() * VECTORS_PER_CHUNK;
        self.norms.capacity() * size_of::<f64>()
            + match &self.storage {
                Storage::F32 { .. } => vectors * self.dims * size_of::<f32>(),
                Storage::I8 { .. } => vectors * self.dims + self.slot_count() * size_of::<f32>(),
            }
    }

    #[cfg(test)]
    pub(crate) fn upsert(
        &mut self,
        key: &str,
        vector: &[f32],
    ) -> Result<UpsertOutcome, VecDbError> {
        match quantize_for(self.storage_kind(), vector) {
            Some(quantized) => self.upsert_payload(key, quantized.as_payload()),
            None => self.upsert_payload(key, VectorPayload::F32(vector)),
        }
    }

    pub(crate) fn upsert_payload(
        &mut self,
        key: &str,
        payload: VectorPayload<'_>,
    ) -> Result<UpsertOutcome, VecDbError> {
        validate_key(key)?;
        if payload.storage() != self.storage_kind() {
            return Err(VecDbError::StorageMismatch {
                expected: self.storage_kind(),
                actual: payload.storage(),
            });
        }
        if payload.dims() != self.dims {
            return Err(VecDbError::DimensionMismatch {
                expected: self.dims,
                actual: payload.dims(),
            });
        }
        if let Some(&slot) = self.keys_to_slots.get(key) {
            self.write_vector(slot, payload);
            return Ok(UpsertOutcome::ReplacedInPlace(slot));
        }
        if let Some(slot) = self.free_slots.pop() {
            self.slots_to_keys[slot as usize] = Box::from(key);
            self.keys_to_slots.insert(Box::from(key), slot);
            self.mark_alive(slot);
            self.live_count += 1;
            self.write_vector(slot, payload);
            return Ok(UpsertOutcome::RecycledSlot(slot));
        }
        let slot = self.slots_to_keys.len() as u32;
        if slot as usize == self.storage.chunk_count() * VECTORS_PER_CHUNK {
            self.storage.push_chunk(self.lanes_per_vector);
        }
        if let Storage::I8 { scales, .. } = &mut self.storage {
            scales.push(0.0);
        }
        if slot as usize / 64 == self.alive.len() {
            self.alive.push(0);
        }
        if self.metric == DistanceMetric::Cosine {
            self.norms.push(0.0);
        }
        self.slots_to_keys.push(Box::from(key));
        self.keys_to_slots.insert(Box::from(key), slot);
        self.mark_alive(slot);
        self.live_count += 1;
        self.write_vector(slot, payload);
        Ok(UpsertOutcome::NewSlot(slot))
    }

    pub(crate) fn remove(&mut self, key: &str) -> Option<u32> {
        let slot = self.keys_to_slots.remove(key)?;
        self.mark_dead(slot);
        self.live_count -= 1;
        self.free_slots.push(slot);
        Some(slot)
    }

    pub(crate) fn compact_in_place(&mut self) {
        let mut dense: u32 = 0;
        for slot in 0..self.slots_to_keys.len() as u32 {
            if !self.is_alive(slot) {
                continue;
            }
            if dense != slot {
                self.move_vector(slot, dense);
                let key = std::mem::take(&mut self.slots_to_keys[slot as usize]);
                if let Some(mapped) = self.keys_to_slots.get_mut(&key) {
                    *mapped = dense;
                }
                self.slots_to_keys[dense as usize] = key;
            }
            dense += 1;
        }
        let live = dense as usize;
        debug_assert_eq!(live, self.live_count);
        self.slots_to_keys.truncate(live);
        self.slots_to_keys.shrink_to_fit();
        self.keys_to_slots.shrink_to_fit();
        let chunk_count = live.div_ceil(VECTORS_PER_CHUNK);
        match &mut self.storage {
            Storage::F32 { chunks } => {
                chunks.truncate(chunk_count);
                chunks.shrink_to_fit();
            }
            Storage::I8 { chunks, scales } => {
                chunks.truncate(chunk_count);
                chunks.shrink_to_fit();
                scales.truncate(live);
                scales.shrink_to_fit();
            }
        }
        self.norms.truncate(live);
        self.norms.shrink_to_fit();
        self.alive.clear();
        self.alive.resize(live.div_ceil(64), u64::MAX);
        self.alive.shrink_to_fit();
        if !live.is_multiple_of(64)
            && let Some(word) = self.alive.last_mut()
        {
            *word = (1u64 << (live % 64)) - 1;
        }
        self.free_slots = Vec::new();
    }

    fn move_vector(&mut self, src: u32, dst: u32) {
        if self.metric == DistanceMetric::Cosine {
            self.norms[dst as usize] = self.norms[src as usize];
        }
        let lanes = self.lanes_per_vector;
        match &mut self.storage {
            Storage::F32 { chunks } => move_lanes(chunks, lanes, src, dst),
            Storage::I8 { chunks, scales } => {
                move_lanes(chunks, lanes, src, dst);
                scales[dst as usize] = scales[src as usize];
            }
        }
    }

    pub(crate) fn slot_of_key(&self, key: &str) -> Option<u32> {
        self.keys_to_slots.get(key).copied()
    }

    pub(crate) fn key_of_slot(&self, slot: u32) -> Option<&str> {
        if self.is_alive(slot) {
            Some(&self.slots_to_keys[slot as usize])
        } else {
            None
        }
    }

    pub(crate) fn is_alive(&self, slot: u32) -> bool {
        self.alive
            .get(slot as usize / 64)
            .is_some_and(|word| word & (1u64 << (slot % 64)) != 0)
    }

    pub(crate) fn live_slots(&self) -> impl Iterator<Item = u32> {
        (0..self.slots_to_keys.len() as u32).filter(|slot| self.is_alive(*slot))
    }

    pub(crate) fn stored_query(&self, slot: u32) -> Query<'_> {
        let norm = self.norms.get(slot as usize).copied().unwrap_or(0.0);
        let lanes = self.lanes_per_vector;
        match &self.storage {
            Storage::F32 { chunks } => Query::F32(slot_lanes(chunks, lanes, slot), norm),
            Storage::I8 { chunks, scales } => Query::I8 {
                scale: scales[slot as usize],
                lanes: slot_lanes(chunks, lanes, slot),
                norm,
            },
        }
    }

    pub(crate) fn vector_values(&self, slot: u32) -> Vec<f32> {
        match self.stored_query(slot) {
            Query::F32(lanes, _) => unpack_lanes(lanes),
            Query::I8 { scale, lanes, .. } => dequantize(scale, &unpack_lanes_i8(lanes)),
        }
    }

    pub(crate) fn stored_vector(&self, slot: u32) -> StoredVector {
        match self.stored_query(slot) {
            Query::F32(lanes, _) => StoredVector::F32(unpack_lanes(lanes)),
            Query::I8 { scale, lanes, .. } => StoredVector::I8 {
                scale,
                values: unpack_lanes_i8(lanes),
            },
        }
    }

    pub(crate) fn pack_query(&self, values: &[f32]) -> Result<PackedQuery, VecDbError> {
        if values.len() != self.dims {
            return Err(VecDbError::DimensionMismatch {
                expected: self.dims,
                actual: values.len(),
            });
        }
        Ok(match quantize_for(self.storage_kind(), values) {
            Some(StoredVector::I8 { scale, values }) => {
                let norm = self.payload_norm(VectorPayload::I8 {
                    scale,
                    values: &values,
                });
                PackedQuery::I8 {
                    scale,
                    lanes: pack_lanes_i8(&values),
                    norm,
                }
            }
            Some(StoredVector::F32(_)) | None => PackedQuery::F32(
                pack_lanes(values),
                self.payload_norm(VectorPayload::F32(values)),
            ),
        })
    }

    pub(crate) fn distance_between_slots(&self, a: u32, b: u32) -> f32 {
        self.distance_to_query(self.stored_query(a), b)
    }

    pub(crate) fn distance_to_query(&self, query: Query<'_>, slot: u32) -> f32 {
        match (query, self.stored_query(slot)) {
            (Query::F32(a, norm_a), Query::F32(b, norm_b)) => {
                if self.metric == DistanceMetric::InnerProduct {
                    return F32Kernel::distance(a, b);
                }
                let denominator = norm_a * norm_b;
                let dot = if denominator >= f64::from(f32::MIN_POSITIVE)
                    && denominator <= f64::from(f32::MAX)
                {
                    f64::from(F32Kernel::dot(a, b))
                } else {
                    a.iter()
                        .zip(b)
                        .flat_map(|(a, b)| a.to_array().into_iter().zip(b.to_array()))
                        .map(|(a, b)| f64::from(a) * f64::from(b))
                        .sum()
                };
                cosine_distance(dot, denominator)
            }
            (
                Query::I8 {
                    scale: scale_a,
                    lanes: a,
                    norm: norm_a,
                },
                Query::I8 {
                    scale: scale_b,
                    lanes: b,
                    norm: norm_b,
                },
            ) => {
                if self.metric == DistanceMetric::InnerProduct {
                    return I8Kernel::distance(a, scale_a, b, scale_b);
                }
                cosine_distance(f64::from(I8Kernel::dot(a, b)), norm_a * norm_b)
            }
            _ => unreachable!("queries are packed by the arena that searches them"),
        }
    }

    fn payload_norm(&self, payload: VectorPayload<'_>) -> f64 {
        if self.metric == DistanceMetric::InnerProduct {
            return 0.0;
        }
        match payload {
            VectorPayload::F32(values) => values
                .iter()
                .map(|&value| f64::from(value).powi(2))
                .sum::<f64>()
                .sqrt(),
            VectorPayload::I8 { scale, values } => {
                if scale == 0.0 {
                    return 0.0;
                }
                values
                    .iter()
                    .map(|&value| f64::from(value).powi(2))
                    .sum::<f64>()
                    .sqrt()
            }
        }
    }

    fn write_vector(&mut self, slot: u32, payload: VectorPayload<'_>) {
        if self.metric == DistanceMetric::Cosine {
            self.norms[slot as usize] = self.payload_norm(payload);
        }
        let lanes = self.lanes_per_vector;
        match (&mut self.storage, payload) {
            (Storage::F32 { chunks }, VectorPayload::F32(values)) => {
                pack_lanes_into(values, slot_lanes_mut(chunks, lanes, slot));
            }
            (Storage::I8 { chunks, scales }, VectorPayload::I8 { scale, values }) => {
                pack_lanes_i8_into(values, slot_lanes_mut(chunks, lanes, slot));
                scales[slot as usize] = scale;
            }
            (Storage::F32 { .. }, VectorPayload::I8 { .. })
            | (Storage::I8 { .. }, VectorPayload::F32(_)) => {
                unreachable!("payload kind is validated before a slot is written")
            }
        }
    }

    fn mark_alive(&mut self, slot: u32) {
        self.alive[slot as usize / 64] |= 1u64 << (slot % 64);
    }

    fn mark_dead(&mut self, slot: u32) {
        self.alive[slot as usize / 64] &= !(1u64 << (slot % 64));
    }
}

fn cosine_distance(dot: f64, denominator: f64) -> f32 {
    if denominator == 0.0 {
        return 1.0;
    }
    (1.0 - (dot / denominator).clamp(-1.0, 1.0)) as f32
}

fn slot_lanes<T>(chunks: &[Vec<T>], lanes_per_vector: usize, slot: u32) -> &[T] {
    let start = (slot as usize % VECTORS_PER_CHUNK) * lanes_per_vector;
    &chunks[slot as usize / VECTORS_PER_CHUNK][start..start + lanes_per_vector]
}

fn slot_lanes_mut<T>(chunks: &mut [Vec<T>], lanes_per_vector: usize, slot: u32) -> &mut [T] {
    let start = (slot as usize % VECTORS_PER_CHUNK) * lanes_per_vector;
    &mut chunks[slot as usize / VECTORS_PER_CHUNK][start..start + lanes_per_vector]
}

fn move_lanes<T: Copy>(chunks: &mut [Vec<T>], lanes: usize, src: u32, dst: u32) {
    let src_chunk = src as usize / VECTORS_PER_CHUNK;
    let dst_chunk = dst as usize / VECTORS_PER_CHUNK;
    let src_start = (src as usize % VECTORS_PER_CHUNK) * lanes;
    let dst_start = (dst as usize % VECTORS_PER_CHUNK) * lanes;
    if src_chunk == dst_chunk {
        chunks[src_chunk].copy_within(src_start..src_start + lanes, dst_start);
    } else {
        let (front, back) = chunks.split_at_mut(src_chunk);
        front[dst_chunk][dst_start..dst_start + lanes]
            .copy_from_slice(&back[0][src_start..src_start + lanes]);
    }
}

#[cfg(test)]
mod tests {
    use super::super::kernel::splitmix64;
    use super::*;

    fn seeded_vector(seed: u64, dims: usize) -> Vec<f32> {
        let mut state = seed;
        (0..dims)
            .map(|_| {
                let unit = (splitmix64(&mut state) >> 40) as f32 / (1u64 << 24) as f32;
                unit * 2.0 - 1.0
            })
            .collect()
    }

    fn seeded_unit_vector(seed: u64, dims: usize) -> Vec<f32> {
        let mut values = seeded_vector(seed, dims);
        let norm = values.iter().map(|value| value * value).sum::<f32>().sqrt();
        for value in &mut values {
            *value /= norm;
        }
        values
    }

    fn basis_vector(dims: usize, axis: usize) -> Vec<f32> {
        let mut values = vec![0.0; dims];
        values[axis] = 1.0;
        values
    }

    fn arena_with_keys(dims: usize, keys: &[&str]) -> VectorArena {
        let mut arena = VectorArena::new(dims).unwrap();
        for (index, key) in keys.iter().enumerate() {
            arena
                .upsert(key, &seeded_vector(index as u64, dims))
                .unwrap();
        }
        arena
    }

    fn lane_address(query: Query<'_>) -> usize {
        match query {
            Query::F32(lanes, _) => lanes.as_ptr() as usize,
            Query::I8 { lanes, .. } => lanes.as_ptr() as usize,
        }
    }

    fn stored_i8(arena: &VectorArena, slot: u32) -> (f32, Vec<i8>) {
        match arena.stored_vector(slot) {
            StoredVector::I8 { scale, values } => (scale, values),
            StoredVector::F32(_) => panic!("expected i8 storage"),
        }
    }

    #[test]
    fn rejects_invalid_dimensions() {
        assert!(matches!(
            VectorArena::new(0),
            Err(VecDbError::InvalidDimensions {
                dims: 0,
                storage: StorageKind::F32
            })
        ));
        assert!(matches!(
            VectorArena::new(12),
            Err(VecDbError::InvalidDimensions {
                dims: 12,
                storage: StorageKind::F32
            })
        ));
        assert!(VectorArena::new(8).is_ok());
        assert!(VectorArena::new(512).is_ok());
    }

    #[test]
    fn i8_storage_requires_a_nonzero_multiple_of_32_dims() {
        for dims in [0usize, 8, 16, 24, 40, 100] {
            assert!(matches!(
                VectorArena::with_storage(dims, StorageKind::I8),
                Err(VecDbError::InvalidDimensions {
                    dims: rejected,
                    storage: StorageKind::I8
                }) if rejected == dims
            ));
        }
        for dims in [32usize, 64, 512, 1024] {
            let arena = VectorArena::with_storage(dims, StorageKind::I8).unwrap();
            assert_eq!(arena.storage_kind(), StorageKind::I8);
            assert_eq!(arena.dims(), dims);
        }
        assert_eq!(
            VectorArena::with_storage(8, StorageKind::F32)
                .unwrap()
                .storage_kind(),
            StorageKind::F32
        );
        assert_eq!(
            VectorArena::new(8).unwrap().storage_kind(),
            StorageKind::F32
        );
        let Err(error) = VectorArena::with_storage(8, StorageKind::I8) else {
            panic!("expected an invalid dimensions error");
        };
        let message = error.to_string();
        assert!(message.contains("i8"));
        assert!(message.contains("32"));
    }

    #[test]
    fn rejects_invalid_keys() {
        let mut arena = VectorArena::new(8).unwrap();
        let vector = seeded_vector(1, 8);
        assert!(matches!(
            arena.upsert("", &vector),
            Err(VecDbError::InvalidKey(_))
        ));
        let at_limit = "k".repeat(256);
        assert!(arena.upsert(&at_limit, &vector).is_ok());
        let over_limit = "k".repeat(257);
        assert!(matches!(
            arena.upsert(&over_limit, &vector),
            Err(VecDbError::InvalidKey(_))
        ));
        let multibyte_over_limit = format!("{}é", "k".repeat(255));
        assert_eq!(multibyte_over_limit.len(), 257);
        assert!(matches!(
            arena.upsert(&multibyte_over_limit, &vector),
            Err(VecDbError::InvalidKey(_))
        ));
    }

    #[test]
    fn rejects_dimension_mismatch() {
        let mut arena = VectorArena::new(16).unwrap();
        assert!(matches!(
            arena.upsert("key", &seeded_vector(1, 8)),
            Err(VecDbError::DimensionMismatch {
                expected: 16,
                actual: 8
            })
        ));
        assert!(matches!(
            arena.pack_query(&seeded_vector(1, 24)),
            Err(VecDbError::DimensionMismatch {
                expected: 16,
                actual: 24
            })
        ));
        let mut i8_arena = VectorArena::with_storage(32, StorageKind::I8).unwrap();
        assert!(matches!(
            i8_arena.upsert("key", &seeded_vector(1, 64)),
            Err(VecDbError::DimensionMismatch {
                expected: 32,
                actual: 64
            })
        ));
        assert!(matches!(
            i8_arena.pack_query(&seeded_vector(1, 8)),
            Err(VecDbError::DimensionMismatch {
                expected: 32,
                actual: 8
            })
        ));
        assert_eq!(i8_arena.slot_count(), 0);
    }

    #[test]
    fn payload_kind_must_match_the_arena_storage() {
        let mut f32_arena = VectorArena::new(32).unwrap();
        let mut i8_arena = VectorArena::with_storage(32, StorageKind::I8).unwrap();
        let values = seeded_vector(3, 32);
        let quantized = StoredVector::quantize(&values);
        assert!(matches!(
            f32_arena.upsert_payload("k", quantized.as_payload()),
            Err(VecDbError::StorageMismatch {
                expected: StorageKind::F32,
                actual: StorageKind::I8
            })
        ));
        assert!(matches!(
            i8_arena.upsert_payload("k", VectorPayload::F32(&values)),
            Err(VecDbError::StorageMismatch {
                expected: StorageKind::I8,
                actual: StorageKind::F32
            })
        ));
        assert_eq!(f32_arena.slot_count(), 0);
        assert_eq!(i8_arena.slot_count(), 0);
        assert!(f32_arena.slot_of_key("k").is_none());
        assert!(i8_arena.slot_of_key("k").is_none());
        assert_eq!(
            f32_arena
                .upsert_payload("k", VectorPayload::F32(&values))
                .unwrap(),
            UpsertOutcome::NewSlot(0)
        );
        assert_eq!(
            i8_arena
                .upsert_payload("k", quantized.as_payload())
                .unwrap(),
            UpsertOutcome::NewSlot(0)
        );
        assert_eq!(f32_arena.vector_values(0), values);
        assert_eq!(i8_arena.stored_vector(0), quantized);
    }

    #[test]
    fn assigns_slots_in_encounter_order() {
        let arena = arena_with_keys(8, &["a", "b", "c"]);
        assert_eq!(arena.slot_of_key("a"), Some(0));
        assert_eq!(arena.slot_of_key("b"), Some(1));
        assert_eq!(arena.slot_of_key("c"), Some(2));
    }

    #[test]
    fn upsert_replaces_in_place() {
        let mut arena = VectorArena::new(8).unwrap();
        let first = seeded_vector(1, 8);
        let second = seeded_vector(2, 8);
        assert_eq!(
            arena.upsert("key", &first).unwrap(),
            UpsertOutcome::NewSlot(0)
        );
        assert_eq!(
            arena.upsert("key", &second).unwrap(),
            UpsertOutcome::ReplacedInPlace(0)
        );
        assert_eq!(arena.vector_values(0), second);
        assert_eq!(arena.live_count(), 1);
        assert_eq!(arena.slot_count(), 1);
    }

    #[test]
    fn free_list_reuses_most_recently_freed_slot_first() {
        let mut arena = arena_with_keys(8, &["a", "b", "c"]);
        assert_eq!(arena.remove("a"), Some(0));
        assert_eq!(arena.remove("c"), Some(2));
        assert_eq!(
            arena.upsert("d", &seeded_vector(4, 8)).unwrap(),
            UpsertOutcome::RecycledSlot(2)
        );
        assert_eq!(
            arena.upsert("e", &seeded_vector(5, 8)).unwrap(),
            UpsertOutcome::RecycledSlot(0)
        );
        assert_eq!(
            arena.upsert("f", &seeded_vector(6, 8)).unwrap(),
            UpsertOutcome::NewSlot(3)
        );
    }

    #[test]
    fn remove_is_noop_for_absent_key() {
        let mut arena = arena_with_keys(8, &["a"]);
        assert_eq!(arena.remove("missing"), None);
        assert_eq!(arena.remove("a"), Some(0));
        assert_eq!(arena.remove("a"), None);
    }

    #[test]
    fn lookups_work_in_both_directions() {
        let mut arena = arena_with_keys(8, &["a", "b"]);
        assert_eq!(arena.slot_of_key("b"), Some(1));
        assert_eq!(arena.key_of_slot(1), Some("b"));
        assert!(arena.is_alive(1));
        arena.remove("b");
        assert_eq!(arena.slot_of_key("b"), None);
        assert_eq!(arena.key_of_slot(1), None);
        assert!(!arena.is_alive(1));
        assert_eq!(arena.key_of_slot(999), None);
        assert!(!arena.is_alive(999));
    }

    #[test]
    fn tracks_live_and_dead_counts() {
        let mut arena = arena_with_keys(8, &["a", "b", "c"]);
        assert_eq!(arena.live_count(), 3);
        assert_eq!(arena.dead_count(), 0);
        assert!(!arena.is_empty());
        arena.remove("b");
        assert_eq!(arena.live_count(), 2);
        assert_eq!(arena.dead_count(), 1);
        arena.upsert("d", &seeded_vector(9, 8)).unwrap();
        assert_eq!(arena.live_count(), 3);
        assert_eq!(arena.dead_count(), 0);
        assert_eq!(arena.live_slots().collect::<Vec<_>>(), vec![0, 1, 2]);
    }

    #[test]
    fn dead_slot_vectors_stay_readable_for_routing() {
        let mut arena = VectorArena::new(8).unwrap();
        let vector = seeded_vector(3, 8);
        arena.upsert("a", &vector).unwrap();
        arena.remove("a");
        assert_eq!(arena.vector_values(0), vector);
    }

    #[test]
    fn readding_a_removed_key_recycles_like_any_new_key() {
        let mut arena = arena_with_keys(8, &["a", "b"]);
        assert_eq!(arena.remove("a"), Some(0));
        let vector = seeded_vector(9, 8);
        assert_eq!(
            arena.upsert("a", &vector).unwrap(),
            UpsertOutcome::RecycledSlot(0)
        );
        assert_eq!(arena.key_of_slot(0), Some("a"));
        assert_eq!(arena.vector_values(0), vector);
        assert_eq!(arena.live_count(), 2);
        assert_eq!(arena.dead_count(), 0);
        assert_eq!(arena.remove("b"), Some(1));
        assert_eq!(
            arena.upsert("c", &seeded_vector(10, 8)).unwrap(),
            UpsertOutcome::RecycledSlot(1)
        );
        assert_eq!(
            arena.upsert("b", &seeded_vector(11, 8)).unwrap(),
            UpsertOutcome::NewSlot(2)
        );
    }

    #[test]
    fn identical_operation_sequences_assign_identical_slots() {
        let mut first = VectorArena::new(8).unwrap();
        let mut second = VectorArena::new(8).unwrap();
        let mut state = 42u64;
        let mut keys: Vec<String> = Vec::new();
        let mut removed: Vec<String> = Vec::new();
        let mut operations = Vec::new();
        for step in 0..2000 {
            let roll = splitmix64(&mut state);
            match roll % 4 {
                0 if !keys.is_empty() => {
                    let key = keys.remove(roll as usize % keys.len());
                    removed.push(key.clone());
                    operations.push((key, None));
                }
                1 if !removed.is_empty() => {
                    let key = removed.remove(roll as usize % removed.len());
                    keys.push(key.clone());
                    operations.push((key, Some(seeded_vector(roll, 8))));
                }
                _ => {
                    let key = format!("key-{step}");
                    keys.push(key.clone());
                    operations.push((key, Some(seeded_vector(roll, 8))));
                }
            }
        }
        for (key, vector) in &operations {
            match vector {
                Some(values) => {
                    let a = first.upsert(key, values).unwrap();
                    let b = second.upsert(key, values).unwrap();
                    assert_eq!(a, b);
                }
                None => assert_eq!(first.remove(key), second.remove(key)),
            }
        }
        assert_eq!(first.live_count(), second.live_count());
        assert_eq!(first.slot_count(), second.slot_count());
        for slot in first.live_slots() {
            assert_eq!(first.key_of_slot(slot), second.key_of_slot(slot));
            assert_eq!(first.vector_values(slot), second.vector_values(slot));
        }
    }

    #[test]
    fn compact_in_place_repacks_live_entries_densely_in_order() {
        let mut arena = VectorArena::new(8).unwrap();
        for index in 0..10u64 {
            arena
                .upsert(&format!("key-{index}"), &seeded_vector(index, 8))
                .unwrap();
        }
        assert_eq!(arena.remove("key-0"), Some(0));
        assert_eq!(arena.remove("key-4"), Some(4));
        assert_eq!(arena.remove("key-9"), Some(9));
        assert_eq!(
            arena.upsert("key-5", &seeded_vector(50, 8)).unwrap(),
            UpsertOutcome::ReplacedInPlace(5)
        );
        assert_eq!(
            arena.upsert("extra", &seeded_vector(60, 8)).unwrap(),
            UpsertOutcome::RecycledSlot(9)
        );
        assert_eq!(arena.remove("key-2"), Some(2));
        let expected: Vec<(String, Vec<f32>)> = arena
            .live_slots()
            .map(|slot| {
                (
                    arena.key_of_slot(slot).unwrap().to_string(),
                    arena.vector_values(slot),
                )
            })
            .collect();
        assert_eq!(expected.len(), 7);
        assert_eq!(arena.dead_count(), 3);
        arena.compact_in_place();
        assert_eq!(arena.live_count(), 7);
        assert_eq!(arena.slot_count(), 7);
        assert_eq!(arena.dead_count(), 0);
        assert!(arena.free_slots.is_empty());
        for (index, (key, vector)) in expected.iter().enumerate() {
            let slot = index as u32;
            assert!(arena.is_alive(slot));
            assert_eq!(arena.key_of_slot(slot), Some(key.as_str()));
            assert_eq!(arena.slot_of_key(key), Some(slot));
            assert_eq!(&arena.vector_values(slot), vector);
        }
        assert!(!arena.is_alive(7));
        assert_eq!(
            arena.live_slots().collect::<Vec<_>>(),
            (0..7).collect::<Vec<_>>()
        );
        assert_eq!(
            arena.upsert("fresh", &seeded_vector(70, 8)).unwrap(),
            UpsertOutcome::NewSlot(7)
        );
        let recycled = arena.slot_of_key("key-5").unwrap();
        assert_eq!(arena.remove("key-5"), Some(recycled));
        assert_eq!(arena.dead_count(), 1);
        assert_eq!(
            arena.upsert("reused", &seeded_vector(80, 8)).unwrap(),
            UpsertOutcome::RecycledSlot(recycled)
        );
    }

    #[test]
    fn compact_in_place_moves_vectors_across_chunks_and_frees_the_tail() {
        let mut arena = VectorArena::new(8).unwrap();
        let count = VECTORS_PER_CHUNK + 300;
        for index in 0..count as u64 {
            arena
                .upsert(&format!("key-{index}"), &seeded_vector(index, 8))
                .unwrap();
        }
        assert_eq!(arena.storage.chunk_count(), 2);
        for index in (0..1000u64).step_by(2) {
            assert!(arena.remove(&format!("key-{index}")).is_some());
        }
        let expected: Vec<(String, Vec<f32>)> = arena
            .live_slots()
            .map(|slot| {
                (
                    arena.key_of_slot(slot).unwrap().to_string(),
                    arena.vector_values(slot),
                )
            })
            .collect();
        arena.compact_in_place();
        let live = count - 500;
        assert_eq!(arena.live_count(), live);
        assert_eq!(arena.slot_count(), live);
        assert_eq!(arena.storage.chunk_count(), 1);
        assert_eq!(arena.alive.len(), live.div_ceil(64));
        assert!(arena.free_slots.is_empty());
        for (index, (key, vector)) in expected.iter().enumerate() {
            assert_eq!(arena.slot_of_key(key), Some(index as u32));
            assert_eq!(&arena.vector_values(index as u32), vector);
        }
        for slot in arena.live_slots() {
            assert_eq!(lane_address(arena.stored_query(slot)) % 32, 0);
        }
    }

    #[test]
    fn compact_in_place_with_no_dead_slots_preserves_everything() {
        let mut arena = arena_with_keys(8, &["a", "b", "c"]);
        arena.compact_in_place();
        assert_eq!(arena.live_count(), 3);
        assert_eq!(arena.slot_count(), 3);
        assert_eq!(arena.dead_count(), 0);
        for (index, key) in ["a", "b", "c"].iter().enumerate() {
            assert_eq!(arena.key_of_slot(index as u32), Some(*key));
            assert_eq!(
                arena.vector_values(index as u32),
                seeded_vector(index as u64, 8)
            );
        }
        assert_eq!(
            arena.upsert("d", &seeded_vector(9, 8)).unwrap(),
            UpsertOutcome::NewSlot(3)
        );
    }

    #[test]
    fn compact_in_place_empties_a_fully_dead_arena() {
        let mut arena = arena_with_keys(8, &["a", "b", "c"]);
        for key in ["a", "b", "c"] {
            assert!(arena.remove(key).is_some());
        }
        arena.compact_in_place();
        assert!(arena.is_empty());
        assert_eq!(arena.live_count(), 0);
        assert_eq!(arena.slot_count(), 0);
        assert_eq!(arena.dead_count(), 0);
        assert_eq!(arena.storage.chunk_count(), 0);
        assert!(arena.alive.is_empty());
        assert_eq!(
            arena.upsert("d", &seeded_vector(4, 8)).unwrap(),
            UpsertOutcome::NewSlot(0)
        );
        assert_eq!(arena.vector_values(0), seeded_vector(4, 8));
    }

    #[test]
    fn compact_in_place_reclaims_key_map_capacity() {
        let mut arena = VectorArena::new(8).unwrap();
        for index in 0..5000u64 {
            arena
                .upsert(&format!("key-{index}"), &seeded_vector(index, 8))
                .unwrap();
        }
        for index in 0..4900u64 {
            assert!(arena.remove(&format!("key-{index}")).is_some());
        }
        let before = arena.keys_to_slots.capacity();
        assert!(before > arena.live_count() * 4);
        arena.compact_in_place();
        let after = arena.keys_to_slots.capacity();
        assert_eq!(arena.live_count(), 100);
        assert!(after < before);
        assert!(after >= arena.live_count());
        assert!(after <= arena.live_count() * 4);
        assert_eq!(arena.slot_of_key("key-4999"), Some(99));
    }

    #[test]
    fn compact_in_place_on_an_empty_arena_is_a_noop() {
        let mut arena = VectorArena::new(8).unwrap();
        arena.compact_in_place();
        assert!(arena.is_empty());
        assert_eq!(arena.slot_count(), 0);
        assert_eq!(
            arena.upsert("a", &seeded_vector(0, 8)).unwrap(),
            UpsertOutcome::NewSlot(0)
        );
    }

    #[test]
    fn grows_across_chunks_with_correct_addressing() {
        let mut arena = VectorArena::new(8).unwrap();
        for index in 0..4100u64 {
            arena
                .upsert(&format!("key-{index}"), &seeded_vector(index, 8))
                .unwrap();
        }
        assert_eq!(arena.slot_count(), 4100);
        assert_eq!(arena.live_count(), 4100);
        assert_eq!(arena.slot_of_key("key-4099"), Some(4099));
        assert_eq!(arena.key_of_slot(4097), Some("key-4097"));
        assert_eq!(arena.vector_values(0), seeded_vector(0, 8));
        assert_eq!(arena.vector_values(4099), seeded_vector(4099, 8));
    }

    #[test]
    fn every_slotted_vector_is_32_byte_aligned() {
        let mut arena = VectorArena::new(16).unwrap();
        for index in 0..4200u64 {
            arena
                .upsert(&format!("key-{index}"), &seeded_vector(index, 16))
                .unwrap();
        }
        for slot in arena.live_slots() {
            assert_eq!(lane_address(arena.stored_query(slot)) % 32, 0);
        }
    }

    #[test]
    fn every_i8_slotted_vector_is_32_byte_aligned_across_chunks() {
        let mut arena = VectorArena::with_storage(32, StorageKind::I8).unwrap();
        for index in 0..4200u64 {
            arena
                .upsert(&format!("key-{index}"), &seeded_vector(index, 32))
                .unwrap();
        }
        assert_eq!(arena.storage.chunk_count(), 2);
        assert_eq!(arena.slot_of_key("key-4199"), Some(4199));
        for slot in arena.live_slots() {
            assert_eq!(lane_address(arena.stored_query(slot)) % 32, 0);
        }
        let Storage::I8 { scales, .. } = &arena.storage else {
            panic!("expected i8 storage");
        };
        assert_eq!(scales.len(), 4200);
    }

    #[test]
    fn distances_use_the_kernel_metric() {
        let mut arena = VectorArena::new(16).unwrap();
        arena.upsert("x", &basis_vector(16, 0)).unwrap();
        arena.upsert("y", &basis_vector(16, 9)).unwrap();
        assert_eq!(arena.distance_between_slots(0, 0), 0.0);
        assert_eq!(arena.distance_between_slots(0, 1), 1.0);
        let query = arena.pack_query(&basis_vector(16, 0)).unwrap();
        assert_eq!(arena.distance_to_query(query.as_query(), 0), 0.0);
        assert_eq!(arena.distance_to_query(query.as_query(), 1), 1.0);
    }

    #[test]
    fn i8_upsert_quantizes_and_reads_back_within_half_a_step() {
        let dims = 64;
        let mut arena = VectorArena::with_storage(dims, StorageKind::I8).unwrap();
        for seed in 0..20u64 {
            let values = seeded_unit_vector(seed, dims);
            let key = format!("key-{seed}");
            assert_eq!(
                arena.upsert(&key, &values).unwrap(),
                UpsertOutcome::NewSlot(seed as u32)
            );
            let expected = StoredVector::quantize(&values);
            assert_eq!(arena.stored_vector(seed as u32), expected);
            let StoredVector::I8 { scale, .. } = expected else {
                panic!("expected i8 storage");
            };
            let read_back = arena.vector_values(seed as u32);
            assert_eq!(read_back.len(), dims);
            for (original, restored) in values.iter().zip(&read_back) {
                assert!((original - restored).abs() <= scale / 2.0 + scale * 1.0e-6);
            }
        }
        assert_eq!(arena.storage_kind(), StorageKind::I8);
    }

    #[test]
    fn i8_payloads_are_stored_and_returned_bit_for_bit() {
        let dims = 32;
        let mut arena = VectorArena::with_storage(dims, StorageKind::I8).unwrap();
        let mut values: Vec<i8> = (0..dims as i32)
            .map(|index| (index * 9 - 127) as i8)
            .collect();
        values[0] = -127;
        values[1] = 127;
        values[2] = 0;
        values[3] = -1;
        let scale = f32::from_bits(0x3a1f_8f3c);
        let payload = VectorPayload::I8 {
            scale,
            values: &values,
        };
        assert_eq!(
            arena.upsert_payload("exact", payload).unwrap(),
            UpsertOutcome::NewSlot(0)
        );
        let (stored_scale, stored_values) = stored_i8(&arena, 0);
        assert_eq!(stored_scale.to_bits(), scale.to_bits());
        assert_eq!(stored_values, values);
        assert_eq!(arena.vector_values(0), dequantize(scale, &values));
        assert_eq!(
            arena.upsert_payload("exact", payload).unwrap(),
            UpsertOutcome::ReplacedInPlace(0)
        );
        assert_eq!(stored_i8(&arena, 0), (scale, values.clone()));
        assert_eq!(arena.remove("exact"), Some(0));
        assert_eq!(stored_i8(&arena, 0), (scale, values.clone()));
        let other = VectorPayload::I8 {
            scale: 0.5,
            values: &vec![3i8; dims],
        };
        assert_eq!(
            arena.upsert_payload("recycled", other).unwrap(),
            UpsertOutcome::RecycledSlot(0)
        );
        assert_eq!(stored_i8(&arena, 0), (0.5, vec![3i8; dims]));
    }

    #[test]
    fn i8_distances_follow_the_scaled_dot_formula() {
        let dims = 64;
        let mut arena = VectorArena::with_storage(dims, StorageKind::I8).unwrap();
        let a = seeded_unit_vector(11, dims);
        let b = seeded_unit_vector(12, dims);
        arena.upsert("a", &a).unwrap();
        arena.upsert("b", &b).unwrap();
        let (scale_a, values_a) = stored_i8(&arena, 0);
        let (scale_b, values_b) = stored_i8(&arena, 1);
        let dot: i32 = values_a
            .iter()
            .zip(&values_b)
            .map(|(x, y)| i32::from(*x) * i32::from(*y))
            .sum();
        let expected = 1.0 - dot as f32 * scale_a * scale_b;
        assert_eq!(
            arena.distance_between_slots(0, 1).to_bits(),
            expected.to_bits()
        );
        assert_eq!(
            arena.distance_between_slots(1, 0).to_bits(),
            expected.to_bits()
        );
        let query = arena.pack_query(&a).unwrap();
        assert_eq!(
            arena.distance_to_query(query.as_query(), 1).to_bits(),
            expected.to_bits()
        );
        assert_eq!(
            arena.distance_to_query(arena.stored_query(0), 1).to_bits(),
            expected.to_bits()
        );
        let f32_distance = 1.0 - a.iter().zip(&b).map(|(x, y)| x * y).sum::<f32>();
        assert!((expected - f32_distance).abs() < 0.01);
        assert!(arena.distance_between_slots(0, 0).abs() < 0.02);
    }

    #[test]
    fn i8_zero_vector_stores_scale_zero_and_sits_at_unit_distance() {
        let dims = 32;
        let mut arena = VectorArena::with_storage(dims, StorageKind::I8).unwrap();
        arena.upsert("zero", &vec![0.0; dims]).unwrap();
        arena.upsert("unit", &basis_vector(dims, 5)).unwrap();
        assert_eq!(stored_i8(&arena, 0), (0.0, vec![0i8; dims]));
        assert_eq!(arena.vector_values(0), vec![0.0; dims]);
        assert_eq!(arena.distance_between_slots(0, 1), 1.0);
        assert_eq!(arena.distance_between_slots(0, 0), 1.0);
        let query = arena.pack_query(&basis_vector(dims, 5)).unwrap();
        assert_eq!(arena.distance_to_query(query.as_query(), 0), 1.0);
        let zero_query = arena.pack_query(&vec![0.0; dims]).unwrap();
        assert!(zero_query.as_query().is_finite());
        assert_eq!(arena.distance_to_query(zero_query.as_query(), 1), 1.0);
    }

    #[test]
    fn non_finite_queries_pack_as_non_finite_for_both_storages() {
        let f32_arena = VectorArena::new(32).unwrap();
        let i8_arena = VectorArena::with_storage(32, StorageKind::I8).unwrap();
        for bad in [f32::NAN, f32::INFINITY, f32::NEG_INFINITY] {
            let mut values = seeded_vector(1, 32);
            values[7] = bad;
            assert!(
                !f32_arena
                    .pack_query(&values)
                    .unwrap()
                    .as_query()
                    .is_finite()
            );
            assert!(!i8_arena.pack_query(&values).unwrap().as_query().is_finite());
        }
        let values = seeded_vector(2, 32);
        assert!(
            f32_arena
                .pack_query(&values)
                .unwrap()
                .as_query()
                .is_finite()
        );
        assert!(i8_arena.pack_query(&values).unwrap().as_query().is_finite());
    }

    #[test]
    fn i8_compact_in_place_moves_scales_with_their_vectors_across_chunks() {
        let dims = 32;
        let mut arena = VectorArena::with_storage(dims, StorageKind::I8).unwrap();
        let count = VECTORS_PER_CHUNK + 200;
        for index in 0..count as u64 {
            arena
                .upsert(&format!("key-{index}"), &seeded_vector(index, dims))
                .unwrap();
        }
        assert_eq!(arena.storage.chunk_count(), 2);
        for index in (0..900u64).step_by(3) {
            assert!(arena.remove(&format!("key-{index}")).is_some());
        }
        let expected: Vec<(String, StoredVector)> = arena
            .live_slots()
            .map(|slot| {
                (
                    arena.key_of_slot(slot).unwrap().to_string(),
                    arena.stored_vector(slot),
                )
            })
            .collect();
        arena.compact_in_place();
        assert_eq!(arena.live_count(), count - 300);
        assert_eq!(arena.slot_count(), count - 300);
        assert_eq!(arena.storage.chunk_count(), 1);
        let Storage::I8 { scales, .. } = &arena.storage else {
            panic!("expected i8 storage");
        };
        assert_eq!(scales.len(), count - 300);
        for (index, (key, stored)) in expected.iter().enumerate() {
            let slot = index as u32;
            assert_eq!(arena.slot_of_key(key), Some(slot));
            assert_eq!(&arena.stored_vector(slot), stored);
            assert_eq!(lane_address(arena.stored_query(slot)) % 32, 0);
        }
        assert_eq!(
            arena.upsert("fresh", &seeded_vector(9999, dims)).unwrap(),
            UpsertOutcome::NewSlot((count - 300) as u32)
        );
    }

    #[test]
    fn i8_arena_reports_a_quarter_of_the_f32_vector_memory() {
        let dims = 512;
        let mut f32_arena = VectorArena::new(dims).unwrap();
        let mut i8_arena = VectorArena::with_storage(dims, StorageKind::I8).unwrap();
        assert_eq!(f32_arena.vector_memory_bytes(), 0);
        assert_eq!(i8_arena.vector_memory_bytes(), 0);
        for index in 0..100u64 {
            let values = seeded_vector(index, dims);
            f32_arena.upsert(&format!("key-{index}"), &values).unwrap();
            i8_arena.upsert(&format!("key-{index}"), &values).unwrap();
        }
        assert_eq!(
            f32_arena.vector_memory_bytes(),
            VECTORS_PER_CHUNK * dims * size_of::<f32>()
        );
        assert_eq!(
            i8_arena.vector_memory_bytes(),
            VECTORS_PER_CHUNK * dims + 100 * size_of::<f32>()
        );
    }
}
