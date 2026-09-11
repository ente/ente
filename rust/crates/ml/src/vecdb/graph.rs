use std::cmp::{Ordering, Reverse};
use std::collections::{BinaryHeap, HashSet};

use super::arena::{PackedQuery, Query, VectorArena};
use super::kernel::splitmix64;
use super::{Match, SearchParams, VecDbError};

const M: usize = 16;
const LEVEL_ZERO_NEIGHBOR_CAP: usize = 2 * M;
const UPPER_LEVEL_NEIGHBOR_CAP: usize = M;
const EF_CONSTRUCTION: usize = 96;
const SELECTION_WINDOW_FACTOR: usize = 2;
const EF_SEARCH_UPPER: usize = 1;
const EF_SEARCH_FLOOR_SMALL: usize = 72;
const EF_SEARCH_FLOOR_LARGE: usize = 56;
const EF_SEARCH_FLOOR_CROSSOVER: usize = 20_000;
const EF_SEARCH_LIMIT_FACTOR: usize = 4;
const SMALL_FILTER_FLOOR: usize = 1024;
const SMALL_FILTER_LIMIT_FACTOR: usize = 4;
const RANGE_SEARCH_FLOOR: usize = 200;
const RANGE_EXPANSION_SLACK: f32 = 0.10;
const LEVEL_SEED: u64 = 0x9E37_79B9_7F4A_7C15;
const NEIGHBOR_BATCH: usize = LEVEL_ZERO_NEIGHBOR_CAP;
const ABSENT_LEVEL: u16 = u16::MAX;
const ABSENT_DENSE: u32 = u32::MAX;
const MIN_GROWTH_SPARE: usize = 1024;

fn grow_amortized<T: Clone>(values: &mut Vec<T>, len: usize, fill: T) {
    debug_assert!(len >= values.len());
    if values.capacity() < len {
        let spare = (values.len() / 8).max(MIN_GROWTH_SPARE);
        let target = len.max(values.len() + spare);
        values.reserve_exact(target - values.len());
    }
    values.resize(len, fill);
}

fn neighbor_cap(level: usize) -> usize {
    if level == 0 {
        LEVEL_ZERO_NEIGHBOR_CAP
    } else {
        UPPER_LEVEL_NEIGHBOR_CAP
    }
}

fn select_neighbors(
    arena: &VectorArena,
    candidates: &[Scored],
    cap: usize,
    selected: &mut [u32; LEVEL_ZERO_NEIGHBOR_CAP],
) -> usize {
    let window = candidates
        .len()
        .min(cap.saturating_mul(SELECTION_WINDOW_FACTOR));
    let mut count = 0;
    for candidate in &candidates[..window] {
        if count == cap {
            break;
        }
        let diverse = selected[..count]
            .iter()
            .all(|&kept| arena.distance_between_slots(candidate.slot, kept) > candidate.distance);
        if diverse {
            selected[count] = candidate.slot;
            count += 1;
        }
    }
    for candidate in candidates {
        if count == cap {
            break;
        }
        if !selected[..count].contains(&candidate.slot) {
            selected[count] = candidate.slot;
            count += 1;
        }
    }
    count
}

#[derive(Clone, Copy)]
struct Scored {
    distance: f32,
    slot: u32,
}

impl PartialEq for Scored {
    fn eq(&self, other: &Self) -> bool {
        self.cmp(other) == Ordering::Equal
    }
}

impl Eq for Scored {}

impl PartialOrd for Scored {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for Scored {
    fn cmp(&self, other: &Self) -> Ordering {
        self.distance
            .total_cmp(&other.distance)
            .then_with(|| self.slot.cmp(&other.slot))
    }
}

struct VisitedSet {
    words: Vec<u64>,
}

impl VisitedSet {
    fn with_capacity(slots: usize) -> Self {
        Self {
            words: vec![0; slots.div_ceil(64)],
        }
    }

    fn insert(&mut self, slot: u32) -> bool {
        let word = slot as usize / 64;
        let mask = 1u64 << (slot % 64);
        if self.words[word] & mask != 0 {
            return false;
        }
        self.words[word] |= mask;
        true
    }
}

struct UpperLevel {
    dense_of_slot: Vec<u32>,
    neighbors: Vec<u32>,
    lengths: Vec<u16>,
    free: Vec<u32>,
}

impl UpperLevel {
    fn new() -> Self {
        Self {
            dense_of_slot: Vec::new(),
            neighbors: Vec::new(),
            lengths: Vec::new(),
            free: Vec::new(),
        }
    }

    fn memory_bytes(&self) -> usize {
        self.dense_of_slot.capacity() * size_of::<u32>()
            + self.neighbors.capacity() * size_of::<u32>()
            + self.lengths.capacity() * size_of::<u16>()
            + self.free.capacity() * size_of::<u32>()
    }
}

pub(crate) struct GraphNodeParts {
    pub(crate) slot: u32,
    pub(crate) level: u8,
    pub(crate) neighbors: Vec<Vec<u32>>,
}

pub(crate) struct Graph {
    node_levels: Vec<u16>,
    zero_neighbors: Vec<u32>,
    zero_lengths: Vec<u16>,
    upper: Vec<UpperLevel>,
    entry_point: Option<u32>,
    insert_ordinal: u64,
}

impl Graph {
    pub(crate) fn new() -> Self {
        Self {
            node_levels: Vec::new(),
            zero_neighbors: Vec::new(),
            zero_lengths: Vec::new(),
            upper: Vec::new(),
            entry_point: None,
            insert_ordinal: 0,
        }
    }

    pub(crate) fn rebuild(arena: &VectorArena) -> Self {
        let mut graph = Self::new();
        for slot in arena.live_slots() {
            graph.insert(slot, arena);
        }
        graph
    }

    pub(crate) fn from_parts(
        entry_point: Option<u32>,
        parts: Vec<GraphNodeParts>,
        slot_count: usize,
        insert_ordinal: u64,
    ) -> Result<Self, VecDbError> {
        let mut slots: HashSet<u32> = HashSet::with_capacity(parts.len());
        for part in &parts {
            if part.slot as usize >= slot_count {
                return Err(VecDbError::Corrupt(format!(
                    "graph node {} is beyond the {slot_count} arena slots",
                    part.slot
                )));
            }
            if part.neighbors.len() != part.level as usize + 1 {
                return Err(VecDbError::Corrupt(format!(
                    "graph node {} level {} has {} adjacency lists",
                    part.slot,
                    part.level,
                    part.neighbors.len()
                )));
            }
            if !slots.insert(part.slot) {
                return Err(VecDbError::Corrupt(format!(
                    "duplicate graph node for slot {}",
                    part.slot
                )));
            }
            for (layer, list) in part.neighbors.iter().enumerate() {
                let cap = neighbor_cap(layer);
                if list.len() > cap {
                    return Err(VecDbError::Corrupt(format!(
                        "graph node {} level {layer} has {} neighbors above the {cap} cap",
                        part.slot,
                        list.len()
                    )));
                }
            }
        }
        for part in &parts {
            for list in &part.neighbors {
                for neighbor in list {
                    if !slots.contains(neighbor) {
                        return Err(VecDbError::Corrupt(format!(
                            "graph node {} links to unknown slot {neighbor}",
                            part.slot
                        )));
                    }
                }
            }
        }
        match entry_point {
            Some(slot) if !slots.contains(&slot) => {
                return Err(VecDbError::Corrupt(format!(
                    "graph entry point {slot} has no node"
                )));
            }
            None if !parts.is_empty() => {
                return Err(VecDbError::Corrupt(
                    "non-empty graph has no entry point".to_string(),
                ));
            }
            _ => {}
        }
        let capacity = parts
            .iter()
            .map(|part| part.slot as usize + 1)
            .max()
            .unwrap_or(0);
        let mut graph = Self::new();
        graph.entry_point = entry_point;
        graph.insert_ordinal = insert_ordinal;
        graph.reserve_slots(capacity);
        for part in parts {
            graph.attach_empty_node(part.slot, part.level as usize);
            for (layer, list) in part.neighbors.iter().enumerate() {
                graph.write_level_list(part.slot, layer, list);
            }
        }
        Ok(graph)
    }

    pub(crate) fn insert(&mut self, slot: u32, arena: &VectorArena) {
        let level = self.next_level();
        self.reserve_slots(arena.slot_count().max(slot as usize + 1));
        self.attach_empty_node(slot, level);
        let Some(entry) = self.entry_point else {
            self.entry_point = Some(slot);
            return;
        };
        let query = arena.stored_query(slot);
        let entry_level = self.level_of(entry).map_or(0, usize::from);
        let mut entries = {
            let context = QueryContext {
                graph: self,
                arena,
                query,
            };
            let mut nearest = context.scored(entry);
            for descend_level in (level + 1..=entry_level).rev() {
                nearest = context.greedy_descend(nearest, descend_level, Some(slot));
            }
            vec![nearest]
        };
        for link_level in (0..=level.min(entry_level)).rev() {
            let candidates = {
                let context = QueryContext {
                    graph: self,
                    arena,
                    query,
                };
                context.search_layer(&entries, link_level, EF_CONSTRUCTION, Some(slot), &|_| true)
            };
            let cap = neighbor_cap(link_level);
            let mut selected = [0u32; LEVEL_ZERO_NEIGHBOR_CAP];
            let count = select_neighbors(arena, &candidates, cap, &mut selected);
            if self.holds_level(slot, link_level) {
                self.write_level_list(slot, link_level, &selected[..count]);
            }
            for &neighbor in &selected[..count] {
                self.link_back(neighbor, link_level, slot, cap, arena);
            }
            entries = candidates;
        }
        if level > entry_level {
            self.entry_point = Some(slot);
        }
    }

    pub(crate) fn reinsert(&mut self, slot: u32, arena: &VectorArena) {
        self.detach(slot);
        self.insert(slot, arena);
    }

    pub(crate) fn entry_point(&self) -> Option<u32> {
        self.entry_point
    }

    pub(crate) fn insert_ordinal(&self) -> u64 {
        self.insert_ordinal
    }

    pub(crate) fn node_count(&self) -> usize {
        self.slots().count()
    }

    pub(crate) fn slots(&self) -> impl Iterator<Item = u32> {
        self.node_levels
            .iter()
            .enumerate()
            .filter_map(|(index, &level)| (level != ABSENT_LEVEL).then_some(index as u32))
    }

    pub(crate) fn level_of(&self, slot: u32) -> Option<u8> {
        match self.node_levels.get(slot as usize) {
            Some(&level) if level != ABSENT_LEVEL => Some(level as u8),
            _ => None,
        }
    }

    pub(crate) fn neighbors_of(&self, slot: u32, level: u8) -> &[u32] {
        self.level_neighbors(slot, level as usize)
    }

    pub(crate) fn memory_bytes(&self) -> usize {
        self.node_levels.capacity() * size_of::<u16>()
            + self.zero_neighbors.capacity() * size_of::<u32>()
            + self.zero_lengths.capacity() * size_of::<u16>()
            + self.upper.capacity() * size_of::<UpperLevel>()
            + self
                .upper
                .iter()
                .map(UpperLevel::memory_bytes)
                .sum::<usize>()
    }

    fn slot_span(&self) -> usize {
        self.node_levels.len()
    }

    fn level_neighbors(&self, slot: u32, level: usize) -> &[u32] {
        if level == 0 {
            let Some(&length) = self.zero_lengths.get(slot as usize) else {
                return &[];
            };
            let base = slot as usize * LEVEL_ZERO_NEIGHBOR_CAP;
            return &self.zero_neighbors[base..base + length as usize];
        }
        let Some(upper) = self.upper.get(level - 1) else {
            return &[];
        };
        let Some(&dense) = upper.dense_of_slot.get(slot as usize) else {
            return &[];
        };
        if dense == ABSENT_DENSE {
            return &[];
        }
        let base = dense as usize * UPPER_LEVEL_NEIGHBOR_CAP;
        &upper.neighbors[base..base + upper.lengths[dense as usize] as usize]
    }

    fn holds_level(&self, slot: u32, level: usize) -> bool {
        self.level_of(slot)
            .is_some_and(|node_level| usize::from(node_level) >= level)
    }

    fn write_level_list(&mut self, slot: u32, level: usize, values: &[u32]) {
        debug_assert!(values.len() <= neighbor_cap(level));
        if level == 0 {
            let base = slot as usize * LEVEL_ZERO_NEIGHBOR_CAP;
            self.zero_neighbors[base..base + values.len()].copy_from_slice(values);
            self.zero_lengths[slot as usize] = values.len() as u16;
            return;
        }
        let upper = &mut self.upper[level - 1];
        let dense = upper.dense_of_slot[slot as usize] as usize;
        let base = dense * UPPER_LEVEL_NEIGHBOR_CAP;
        upper.neighbors[base..base + values.len()].copy_from_slice(values);
        upper.lengths[dense] = values.len() as u16;
    }

    fn reserve_slots(&mut self, capacity: usize) {
        if self.node_levels.len() >= capacity {
            return;
        }
        grow_amortized(&mut self.node_levels, capacity, ABSENT_LEVEL);
        grow_amortized(&mut self.zero_lengths, capacity, 0);
        grow_amortized(
            &mut self.zero_neighbors,
            capacity * LEVEL_ZERO_NEIGHBOR_CAP,
            0,
        );
    }

    fn attach_empty_node(&mut self, slot: u32, level: usize) {
        self.reserve_slots(slot as usize + 1);
        debug_assert!(self.node_levels[slot as usize] == ABSENT_LEVEL);
        self.node_levels[slot as usize] = level as u16;
        self.zero_lengths[slot as usize] = 0;
        for layer in 1..=level {
            self.claim_upper_block(slot, layer);
        }
    }

    fn claim_upper_block(&mut self, slot: u32, layer: usize) {
        while self.upper.len() < layer {
            self.upper.push(UpperLevel::new());
        }
        let span = self.node_levels.len();
        let upper = &mut self.upper[layer - 1];
        if upper.dense_of_slot.len() < span {
            grow_amortized(&mut upper.dense_of_slot, span, ABSENT_DENSE);
        }
        let dense = match upper.free.pop() {
            Some(dense) => dense,
            None => {
                let dense = upper.lengths.len() as u32;
                upper.lengths.push(0);
                upper
                    .neighbors
                    .resize(upper.lengths.len() * UPPER_LEVEL_NEIGHBOR_CAP, 0);
                dense
            }
        };
        upper.lengths[dense as usize] = 0;
        upper.dense_of_slot[slot as usize] = dense;
    }

    fn release_node(&mut self, slot: u32, level: usize) {
        self.zero_lengths[slot as usize] = 0;
        for layer in 1..=level {
            let upper = &mut self.upper[layer - 1];
            let dense = upper.dense_of_slot[slot as usize];
            if dense == ABSENT_DENSE {
                continue;
            }
            upper.dense_of_slot[slot as usize] = ABSENT_DENSE;
            upper.lengths[dense as usize] = 0;
            upper.free.push(dense);
        }
    }

    fn detach(&mut self, slot: u32) {
        let Some(level) = self.level_of(slot).map(usize::from) else {
            return;
        };
        self.node_levels[slot as usize] = ABSENT_LEVEL;
        for layer in 0..=level {
            let mut buffer = [0u32; LEVEL_ZERO_NEIGHBOR_CAP];
            let count = {
                let list = self.level_neighbors(slot, layer);
                buffer[..list.len()].copy_from_slice(list);
                list.len()
            };
            for &neighbor in &buffer[..count] {
                self.unlink(neighbor, layer, slot);
            }
        }
        self.release_node(slot, level);
        if self.entry_point == Some(slot) {
            self.entry_point = self.highest_slot();
        }
    }

    fn unlink(&mut self, slot: u32, level: usize, other: u32) {
        if !self.holds_level(slot, level) {
            return;
        }
        let mut buffer = [0u32; LEVEL_ZERO_NEIGHBOR_CAP];
        let count = {
            let list = self.level_neighbors(slot, level);
            if !list.contains(&other) {
                return;
            }
            let mut count = 0;
            for &value in list {
                if value != other {
                    buffer[count] = value;
                    count += 1;
                }
            }
            count
        };
        self.write_level_list(slot, level, &buffer[..count]);
    }

    fn link_back(&mut self, slot: u32, level: usize, other: u32, cap: usize, arena: &VectorArena) {
        if !self.holds_level(slot, level) {
            return;
        }
        let mut buffer = [0u32; LEVEL_ZERO_NEIGHBOR_CAP + 1];
        let count = {
            let list = self.level_neighbors(slot, level);
            if list.contains(&other) {
                return;
            }
            buffer[..list.len()].copy_from_slice(list);
            list.len() + 1
        };
        buffer[count - 1] = other;
        if count <= cap {
            self.write_level_list(slot, level, &buffer[..count]);
            return;
        }
        let mut scored = [Scored {
            distance: 0.0,
            slot: 0,
        }; LEVEL_ZERO_NEIGHBOR_CAP + 1];
        for (entry, &neighbor) in scored.iter_mut().zip(&buffer[..count]) {
            *entry = Scored {
                distance: arena.distance_between_slots(slot, neighbor),
                slot: neighbor,
            };
        }
        scored[..count].sort_unstable();
        let mut kept = [0u32; LEVEL_ZERO_NEIGHBOR_CAP];
        let kept_count = select_neighbors(arena, &scored[..count], cap, &mut kept);
        self.write_level_list(slot, level, &kept[..kept_count]);
    }

    fn highest_slot(&self) -> Option<u32> {
        let mut best: Option<(u16, u32)> = None;
        for (index, &level) in self.node_levels.iter().enumerate() {
            if level == ABSENT_LEVEL {
                continue;
            }
            if best.is_none_or(|(best_level, _)| level > best_level) {
                best = Some((level, index as u32));
            }
        }
        best.map(|(_, slot)| slot)
    }

    fn next_level(&mut self) -> usize {
        let mut state = LEVEL_SEED ^ self.insert_ordinal;
        self.insert_ordinal = self.insert_ordinal.wrapping_add(1);
        let raw = splitmix64(&mut state);
        let unit = ((raw >> 11) + 1) as f64 / (1u64 << 53) as f64;
        (-unit.ln() * (M as f64).ln().recip()) as usize
    }
}

struct QueryContext<'a> {
    graph: &'a Graph,
    arena: &'a VectorArena,
    query: Query<'a>,
}

impl QueryContext<'_> {
    fn scored(&self, slot: u32) -> Scored {
        Scored {
            distance: self.arena.distance_to_query(self.query, slot),
            slot,
        }
    }

    fn evaluate_batch(
        &self,
        chunk: &[u32],
        visited: &mut VisitedSet,
        slots: &mut [u32; NEIGHBOR_BATCH],
        distances: &mut [f32; NEIGHBOR_BATCH],
    ) -> usize {
        let mut count = 0;
        for &neighbor in chunk {
            if visited.insert(neighbor) {
                slots[count] = neighbor;
                count += 1;
            }
        }
        for (distance, &slot) in distances.iter_mut().zip(slots.iter()).take(count) {
            *distance = self.arena.distance_to_query(self.query, slot);
        }
        count
    }

    fn greedy_descend(&self, mut best: Scored, level: usize, banned: Option<u32>) -> Scored {
        loop {
            let mut improved = false;
            for &neighbor in self.graph.level_neighbors(best.slot, level) {
                if banned == Some(neighbor) {
                    continue;
                }
                let candidate = self.scored(neighbor);
                if candidate < best {
                    best = candidate;
                    improved = true;
                }
            }
            if !improved {
                return best;
            }
        }
    }

    fn search_layer(
        &self,
        entries: &[Scored],
        level: usize,
        ef: usize,
        banned: Option<u32>,
        admit: &impl Fn(u32) -> bool,
    ) -> Vec<Scored> {
        debug_assert!(ef > 0);
        let mut visited = VisitedSet::with_capacity(self.graph.slot_span());
        if let Some(banned) = banned {
            visited.insert(banned);
        }
        let mut candidates: BinaryHeap<Reverse<Scored>> = BinaryHeap::new();
        let mut results: BinaryHeap<Scored> = BinaryHeap::new();
        for &entry in entries {
            if !visited.insert(entry.slot) {
                continue;
            }
            candidates.push(Reverse(entry));
            if admit(entry.slot) {
                results.push(entry);
                if results.len() > ef {
                    results.pop();
                }
            }
        }
        let mut slots = [0u32; NEIGHBOR_BATCH];
        let mut distances = [0.0f32; NEIGHBOR_BATCH];
        while let Some(Reverse(current)) = candidates.pop() {
            if results.len() >= ef && results.peek().is_some_and(|worst| current > *worst) {
                break;
            }
            for chunk in self
                .graph
                .level_neighbors(current.slot, level)
                .chunks(NEIGHBOR_BATCH)
            {
                let count = self.evaluate_batch(chunk, &mut visited, &mut slots, &mut distances);
                for (&distance, &slot) in distances.iter().zip(slots.iter()).take(count) {
                    let scored = Scored { distance, slot };
                    if results.len() >= ef && results.peek().is_some_and(|worst| scored > *worst) {
                        continue;
                    }
                    candidates.push(Reverse(scored));
                    if admit(slot) {
                        results.push(scored);
                        if results.len() > ef {
                            results.pop();
                        }
                    }
                }
            }
        }
        results.into_sorted_vec()
    }

    fn level_zero_entries(&self) -> Vec<Scored> {
        let Some(entry) = self.graph.entry_point else {
            return Vec::new();
        };
        let top = self.graph.level_of(entry).map_or(0, usize::from);
        let mut entries = vec![self.scored(entry)];
        for level in (1..=top).rev() {
            entries = self.search_layer(&entries, level, EF_SEARCH_UPPER, None, &|_| true);
        }
        entries
    }

    fn top_scored(&self, ef: usize, admit: &impl Fn(u32) -> bool) -> Vec<Scored> {
        let entries = self.level_zero_entries();
        if entries.is_empty() {
            return Vec::new();
        }
        self.search_layer(&entries, 0, ef, None, admit)
    }

    fn top_scored_near(
        &self,
        slot: u32,
        ef: usize,
        fill: usize,
        admit: &impl Fn(u32) -> bool,
    ) -> Vec<Scored> {
        if self.graph.level_neighbors(slot, 0).is_empty() {
            return self.top_scored(ef, admit);
        }
        let near = self.search_layer(&[self.scored(slot)], 0, ef, None, admit);
        if near.len() >= fill {
            return near;
        }
        let mut entries = vec![self.scored(slot)];
        entries.extend(self.level_zero_entries());
        self.search_layer(&entries, 0, ef, None, admit)
    }

    fn range_scored(&self, max_distance: f32, admit: &impl Fn(u32) -> bool) -> Vec<Scored> {
        let expansion_bound = max_distance * (1.0 + RANGE_EXPANSION_SLACK);
        let mut visited = VisitedSet::with_capacity(self.graph.slot_span());
        let mut candidates: BinaryHeap<Reverse<Scored>> = BinaryHeap::new();
        let mut frontier: BinaryHeap<Scored> = BinaryHeap::new();
        let mut results: Vec<Scored> = Vec::new();
        for entry in self.level_zero_entries() {
            if !visited.insert(entry.slot) {
                continue;
            }
            if entry.distance <= max_distance && admit(entry.slot) {
                results.push(entry);
            }
            candidates.push(Reverse(entry));
            keep_frontier(&mut frontier, entry);
        }
        let mut slots = [0u32; NEIGHBOR_BATCH];
        let mut distances = [0.0f32; NEIGHBOR_BATCH];
        while let Some(Reverse(current)) = candidates.pop() {
            if current.distance > expansion_bound && trails_frontier(&frontier, current) {
                break;
            }
            for chunk in self
                .graph
                .level_neighbors(current.slot, 0)
                .chunks(NEIGHBOR_BATCH)
            {
                let count = self.evaluate_batch(chunk, &mut visited, &mut slots, &mut distances);
                for (&distance, &slot) in distances.iter().zip(slots.iter()).take(count) {
                    let scored = Scored { distance, slot };
                    if scored.distance <= max_distance && admit(slot) {
                        results.push(scored);
                    }
                    let trails = trails_frontier(&frontier, scored);
                    if !trails || scored.distance <= expansion_bound {
                        candidates.push(Reverse(scored));
                    }
                    if !trails {
                        keep_frontier(&mut frontier, scored);
                    }
                }
            }
        }
        results.sort_unstable();
        results
    }
}

fn trails_frontier(frontier: &BinaryHeap<Scored>, scored: Scored) -> bool {
    frontier.len() >= RANGE_SEARCH_FLOOR && frontier.peek().is_some_and(|worst| scored > *worst)
}

fn keep_frontier(frontier: &mut BinaryHeap<Scored>, scored: Scored) {
    frontier.push(scored);
    if frontier.len() > RANGE_SEARCH_FLOOR {
        frontier.pop();
    }
}

pub(crate) fn search(
    graph: &Graph,
    arena: &VectorArena,
    query: &PackedQuery,
    params: &SearchParams,
    allowed_slots: Option<&HashSet<u32>>,
) -> Vec<Match> {
    search_from(graph, arena, query.as_query(), params, allowed_slots, None)
}

pub(crate) fn search_stored(
    graph: &Graph,
    arena: &VectorArena,
    slot: u32,
    params: &SearchParams,
    allowed_slots: Option<&HashSet<u32>>,
) -> Vec<Match> {
    search_from(
        graph,
        arena,
        arena.stored_query(slot),
        params,
        allowed_slots,
        Some(slot),
    )
}

fn search_from(
    graph: &Graph,
    arena: &VectorArena,
    query: Query<'_>,
    params: &SearchParams,
    allowed_slots: Option<&HashSet<u32>>,
    stored_slot: Option<u32>,
) -> Vec<Match> {
    debug_assert!(params.limit.is_some() || params.max_distance.is_some());
    if let Some(max_distance) = params.max_distance {
        debug_assert!(max_distance.is_finite() && max_distance >= 0.0);
    }
    if arena.live_count() == 0
        || params.limit == Some(0)
        || allowed_slots.is_some_and(HashSet::is_empty)
        || !query.is_finite()
    {
        return Vec::new();
    }
    if params.exact {
        return brute_force(arena, query, params, allowed_slots, stored_slot);
    }
    if let Some(allowed) = allowed_slots
        && allowed.len() <= small_filter_cap(params.limit)
    {
        return brute_force(arena, query, params, allowed_slots, stored_slot);
    }
    if graph.entry_point.is_none() {
        return brute_force(arena, query, params, allowed_slots, stored_slot);
    }
    let context = QueryContext {
        graph,
        arena,
        query,
    };
    match params.limit {
        Some(limit) => approx_limited(&context, limit, params, allowed_slots, stored_slot),
        None => approx_threshold(
            &context,
            params.max_distance.unwrap_or(f32::MAX),
            allowed_slots,
            stored_slot,
        ),
    }
}

fn small_filter_cap(limit: Option<usize>) -> usize {
    limit.map_or(SMALL_FILTER_FLOOR, |limit| {
        limit
            .saturating_mul(SMALL_FILTER_LIMIT_FACTOR)
            .max(SMALL_FILTER_FLOOR)
    })
}

fn result_bound(arena: &VectorArena, allowed: Option<&HashSet<u32>>) -> usize {
    let live = arena.live_count();
    allowed.map_or(live, |set| set.len().min(live))
}

fn ef_search_floor(live: usize) -> usize {
    if live < EF_SEARCH_FLOOR_CROSSOVER {
        EF_SEARCH_FLOOR_SMALL
    } else {
        EF_SEARCH_FLOOR_LARGE
    }
}

fn admissible(arena: &VectorArena, allowed: Option<&HashSet<u32>>, slot: u32) -> bool {
    arena.is_alive(slot) && allowed.is_none_or(|set| set.contains(&slot))
}

fn admission<'a>(
    arena: &'a VectorArena,
    allowed: Option<&'a HashSet<u32>>,
    banned: Option<u32>,
) -> impl Fn(u32) -> bool + 'a {
    move |slot| banned != Some(slot) && admissible(arena, allowed, slot)
}

fn approx_limited(
    context: &QueryContext<'_>,
    limit: usize,
    params: &SearchParams,
    allowed: Option<&HashSet<u32>>,
    stored_slot: Option<u32>,
) -> Vec<Match> {
    let bound = result_bound(context.arena, allowed);
    let ef = match stored_slot {
        Some(_) => limit,
        None => limit.saturating_mul(EF_SEARCH_LIMIT_FACTOR),
    }
    .max(ef_search_floor(context.arena.live_count()))
    .min(bound);
    let admit = admission(context.arena, allowed, stored_slot);
    let excluded = stored_slot.is_some_and(|slot| admissible(context.arena, allowed, slot));
    let available = bound - usize::from(excluded);
    let scored = match stored_slot {
        Some(slot) => context.top_scored_near(slot, ef, ef.min(available), &admit),
        None => context.top_scored(ef, &admit),
    };
    if scored.len() < limit.min(available) {
        return brute_force(context.arena, context.query, params, allowed, stored_slot);
    }
    to_matches(context.arena, scored, Some(limit), params.max_distance)
}

fn approx_threshold(
    context: &QueryContext<'_>,
    max_distance: f32,
    allowed: Option<&HashSet<u32>>,
    banned: Option<u32>,
) -> Vec<Match> {
    let admit = admission(context.arena, allowed, banned);
    let scored = context.range_scored(max_distance, &admit);
    to_matches(context.arena, scored, None, Some(max_distance))
}

fn brute_force(
    arena: &VectorArena,
    query: Query<'_>,
    params: &SearchParams,
    allowed: Option<&HashSet<u32>>,
    banned: Option<u32>,
) -> Vec<Match> {
    let mut top: BinaryHeap<Scored> = BinaryHeap::new();
    let mut all: Vec<Scored> = Vec::new();
    let mut consider = |slot: u32| {
        if banned == Some(slot) || !arena.is_alive(slot) {
            return;
        }
        let distance = arena.distance_to_query(query, slot);
        if params.max_distance.is_some_and(|cap| distance > cap) {
            return;
        }
        let scored = Scored { distance, slot };
        match params.limit {
            Some(limit) => {
                top.push(scored);
                if top.len() > limit {
                    top.pop();
                }
            }
            None => all.push(scored),
        }
    };
    match allowed {
        Some(set) => {
            for &slot in set {
                consider(slot);
            }
        }
        None => {
            for slot in arena.live_slots() {
                consider(slot);
            }
        }
    }
    let scored = if params.limit.is_some() {
        top.into_sorted_vec()
    } else {
        all.sort_unstable();
        all
    };
    to_matches(arena, scored, None, None)
}

fn to_matches(
    arena: &VectorArena,
    mut scored: Vec<Scored>,
    limit: Option<usize>,
    max_distance: Option<f32>,
) -> Vec<Match> {
    if let Some(max_distance) = max_distance {
        let keep = scored.partition_point(|entry| entry.distance <= max_distance);
        scored.truncate(keep);
    }
    if let Some(limit) = limit {
        scored.truncate(limit);
    }
    scored
        .into_iter()
        .filter_map(|entry| {
            arena.key_of_slot(entry.slot).map(|key| Match {
                key: key.to_string(),
                distance: entry.distance,
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use std::f32::consts::FRAC_1_SQRT_2;
    use std::sync::LazyLock;

    use super::super::StorageKind;
    use super::super::arena::UpsertOutcome;
    use super::super::test_support::{assert_identical_graphs, stale_downward_edge_exists};
    use super::*;

    const FIXTURE_DIMS: usize = 16;
    const FIXTURE_COUNT: usize = 1500;

    static FIXTURE: LazyLock<(VectorArena, Graph)> =
        LazyLock::new(|| build_fixture(FIXTURE_COUNT, FIXTURE_DIMS, 0x00F1_0000));

    fn normalized(mut values: Vec<f32>) -> Vec<f32> {
        let norm = values.iter().map(|value| value * value).sum::<f32>().sqrt();
        for value in &mut values {
            *value /= norm;
        }
        values
    }

    fn seeded_unit_vector(seed: u64, dims: usize) -> Vec<f32> {
        let mut state = seed;
        normalized(
            (0..dims)
                .map(|_| {
                    let unit = (splitmix64(&mut state) >> 40) as f32 / (1u64 << 24) as f32;
                    unit * 2.0 - 1.0
                })
                .collect(),
        )
    }

    fn clustered_unit_vector(center_seed: u64, noise_seed: u64, dims: usize) -> Vec<f32> {
        let center = seeded_unit_vector(center_seed, dims);
        let noise = seeded_unit_vector(noise_seed, dims);
        let mut spread_state = noise_seed ^ 0xD1B5_4A32_D192_ED03;
        let spread = 0.6 + (splitmix64(&mut spread_state) >> 40) as f32 / (1u64 << 24) as f32;
        normalized(
            center
                .iter()
                .zip(&noise)
                .map(|(center, noise)| center + spread * noise)
                .collect(),
        )
    }

    fn build_clustered_fixture(
        count: usize,
        dims: usize,
        clusters: u64,
        seed: u64,
    ) -> (VectorArena, Graph) {
        build_clustered_fixture_with(count, dims, clusters, seed, StorageKind::F32)
    }

    fn build_clustered_fixture_with(
        count: usize,
        dims: usize,
        clusters: u64,
        seed: u64,
        storage: StorageKind,
    ) -> (VectorArena, Graph) {
        let mut arena = VectorArena::with_storage(dims, storage).unwrap();
        for index in 0..count as u64 {
            arena
                .upsert(
                    &format!("key-{index}"),
                    &clustered_unit_vector(
                        seed + index % clusters,
                        seed + 0x0100_0000 + index,
                        dims,
                    ),
                )
                .unwrap();
        }
        let graph = Graph::rebuild(&arena);
        (arena, graph)
    }

    const LATENT_DIMS: usize = 24;

    fn latent_projection(seed: u64, dims: usize) -> Vec<Vec<f32>> {
        (0..LATENT_DIMS as u64)
            .map(|axis| seeded_unit_vector(seed + 0x0300_0000 + axis, dims))
            .collect()
    }

    fn projected_unit_vector(projection: &[Vec<f32>], latent: &[f32]) -> Vec<f32> {
        let dims = projection[0].len();
        let mut values = vec![0.0f32; dims];
        for (weight, basis) in latent.iter().zip(projection) {
            for (value, basis_value) in values.iter_mut().zip(basis) {
                *value += weight * basis_value;
            }
        }
        normalized(values)
    }

    fn build_latent_fixture(
        count: usize,
        dims: usize,
        clusters: u64,
        seed: u64,
    ) -> (VectorArena, Graph) {
        let projection = latent_projection(seed, dims);
        let mut arena = VectorArena::new(dims).unwrap();
        for index in 0..count as u64 {
            let latent = clustered_unit_vector(
                seed + index % clusters,
                seed + 0x0100_0000 + index,
                LATENT_DIMS,
            );
            arena
                .upsert(
                    &format!("key-{index}"),
                    &projected_unit_vector(&projection, &latent),
                )
                .unwrap();
        }
        let graph = Graph::rebuild(&arena);
        (arena, graph)
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

    fn build_fixture(count: usize, dims: usize, seed: u64) -> (VectorArena, Graph) {
        let arena = build_arena(count, dims, seed);
        let graph = Graph::rebuild(&arena);
        (arena, graph)
    }

    const DUPLICATE_GROUP_SEED: u64 = 0x1DEA_0000;

    fn build_duplicate_groups(groups: usize, per_group: usize) -> (VectorArena, Graph) {
        let mut arena = VectorArena::new(16).unwrap();
        for index in 0..groups * per_group {
            let vector = seeded_unit_vector(DUPLICATE_GROUP_SEED + (index / per_group) as u64, 16);
            arena.upsert(&format!("key-{index}"), &vector).unwrap();
        }
        let graph = Graph::rebuild(&arena);
        (arena, graph)
    }

    fn group_of(arena: &VectorArena, key: &str, per_group: usize) -> usize {
        arena.slot_of_key(key).unwrap() as usize / per_group
    }

    fn assert_leading_group(
        arena: &VectorArena,
        found: &[Match],
        count: usize,
        group: usize,
        per_group: usize,
    ) {
        let (head, tail) = found.split_at(count);
        for hit in head {
            assert_eq!(group_of(arena, &hit.key, per_group), group);
            assert_eq!(hit.distance, head[0].distance);
        }
        for hit in tail {
            assert!(hit.distance > head[0].distance);
        }
    }

    fn params(limit: Option<usize>, max_distance: Option<f32>, exact: bool) -> SearchParams {
        SearchParams {
            limit,
            max_distance,
            exact,
            allowed_keys: None,
        }
    }

    fn reference_ranking(
        arena: &VectorArena,
        query: &PackedQuery,
        allowed: Option<&HashSet<u32>>,
    ) -> Vec<(f32, u32)> {
        let mut scored: Vec<(f32, u32)> = arena
            .live_slots()
            .filter(|slot| allowed.is_none_or(|set| set.contains(slot)))
            .map(|slot| (arena.distance_to_query(query.as_query(), slot), slot))
            .collect();
        scored.sort_unstable_by(|a, b| a.0.total_cmp(&b.0).then_with(|| a.1.cmp(&b.1)));
        scored
    }

    fn keys(matches: &[Match]) -> Vec<&str> {
        matches.iter().map(|found| found.key.as_str()).collect()
    }

    fn assert_sorted(matches: &[Match]) {
        for pair in matches.windows(2) {
            assert!(pair[0].distance <= pair[1].distance);
        }
    }

    fn apply_upsert(arena: &mut VectorArena, graph: &mut Graph, key: &str, vector: &[f32]) {
        match arena.upsert(key, vector).unwrap() {
            UpsertOutcome::NewSlot(slot) => graph.insert(slot, arena),
            UpsertOutcome::RecycledSlot(slot) | UpsertOutcome::ReplacedInPlace(slot) => {
                graph.reinsert(slot, arena);
            }
        }
    }

    fn graph_parts(graph: &Graph) -> Vec<GraphNodeParts> {
        graph
            .slots()
            .map(|slot| {
                let level = graph.level_of(slot).unwrap();
                GraphNodeParts {
                    slot,
                    level,
                    neighbors: (0..=level)
                        .map(|layer| graph.neighbors_of(slot, layer).to_vec())
                        .collect(),
                }
            })
            .collect()
    }

    fn assert_graph_invariants(graph: &Graph) {
        for slot in graph.slots() {
            let level = graph.level_of(slot).unwrap();
            for layer in 0..=level {
                let neighbors = graph.neighbors_of(slot, layer);
                assert!(neighbors.len() <= neighbor_cap(layer as usize));
                for &neighbor in neighbors {
                    assert_ne!(neighbor, slot);
                    assert!(graph.level_of(neighbor).is_some());
                }
            }
        }
    }

    fn axis_vector(dims: usize, axis: usize) -> Vec<f32> {
        let mut values = vec![0.0; dims];
        values[axis] = 1.0;
        values
    }

    fn two_axis_vector(first: (usize, f32), second: (usize, f32)) -> Vec<f32> {
        let mut values = vec![0.0f32; 8];
        values[first.0] = first.1;
        values[second.0] = second.1;
        values
    }

    fn handcrafted() -> (VectorArena, Graph) {
        let mut arena = VectorArena::new(8).unwrap();
        arena.upsert("a", &axis_vector(8, 0)).unwrap();
        arena
            .upsert(
                "b",
                &two_axis_vector((0, FRAC_1_SQRT_2), (1, FRAC_1_SQRT_2)),
            )
            .unwrap();
        arena.upsert("c", &axis_vector(8, 1)).unwrap();
        arena
            .upsert("d", &two_axis_vector((0, -1.0), (1, 0.0)))
            .unwrap();
        arena
            .upsert("t1", &two_axis_vector((0, 0.5), (2, 0.866_025_4)))
            .unwrap();
        arena
            .upsert("t2", &two_axis_vector((0, 0.5), (3, 0.866_025_4)))
            .unwrap();
        let graph = Graph::rebuild(&arena);
        (arena, graph)
    }

    fn measured_recall(
        arena: &VectorArena,
        graph: &Graph,
        queries: u64,
        make_query: impl Fn(u64) -> Vec<f32>,
    ) -> f64 {
        let mut hits = 0usize;
        for index in 0..queries {
            let query = arena.pack_query(&make_query(index)).unwrap();
            let reference = reference_ranking(arena, &query, None);
            let expected: HashSet<&str> = reference[..10]
                .iter()
                .map(|&(_, slot)| arena.key_of_slot(slot).unwrap())
                .collect();
            let found = search(graph, arena, &query, &params(Some(10), None, false), None);
            assert_eq!(found.len(), 10);
            hits += found
                .iter()
                .filter(|found| expected.contains(found.key.as_str()))
                .count();
        }
        hits as f64 / (queries as usize * 10) as f64
    }

    #[test]
    fn exact_search_matches_handcrafted_ground_truth() {
        let (arena, graph) = handcrafted();
        let query = arena.pack_query(&axis_vector(8, 0)).unwrap();
        let all = search(&graph, &arena, &query, &params(Some(10), None, true), None);
        assert_eq!(keys(&all), ["a", "b", "t1", "t2", "c", "d"]);
        let expected = [0.0, 1.0 - FRAC_1_SQRT_2, 0.5, 0.5, 1.0, 2.0];
        for (found, expected) in all.iter().zip(expected) {
            assert_eq!(found.distance, expected);
        }
        let inclusive = search(&graph, &arena, &query, &params(None, Some(0.5), true), None);
        assert_eq!(keys(&inclusive), ["a", "b", "t1", "t2"]);
        let below_ties = search(
            &graph,
            &arena,
            &query,
            &params(None, Some(0.499), true),
            None,
        );
        assert_eq!(keys(&below_ties), ["a", "b"]);
        let tie_cut = search(
            &graph,
            &arena,
            &query,
            &params(Some(3), Some(0.5), true),
            None,
        );
        assert_eq!(keys(&tie_cut), ["a", "b", "t1"]);
        let closest = search(
            &graph,
            &arena,
            &query,
            &params(Some(1), Some(2.0), true),
            None,
        );
        assert_eq!(keys(&closest), ["a"]);
    }

    #[test]
    fn tiny_index_approx_equals_exact() {
        let (arena, graph) = handcrafted();
        let query = arena.pack_query(&axis_vector(8, 0)).unwrap();
        let all = search(&graph, &arena, &query, &params(Some(10), None, false), None);
        assert_eq!(keys(&all), ["a", "b", "t1", "t2", "c", "d"]);
        let inclusive = search(
            &graph,
            &arena,
            &query,
            &params(None, Some(0.5), false),
            None,
        );
        assert_eq!(keys(&inclusive), ["a", "b", "t1", "t2"]);
        let tie_cut = search(
            &graph,
            &arena,
            &query,
            &params(Some(3), Some(0.5), false),
            None,
        );
        assert_eq!(keys(&tie_cut), ["a", "b", "t1"]);
        let closest = search(
            &graph,
            &arena,
            &query,
            &params(Some(1), Some(2.0), false),
            None,
        );
        assert_eq!(keys(&closest), ["a"]);
    }

    #[test]
    fn empty_index_returns_empty_for_all_modes() {
        let arena = VectorArena::new(8).unwrap();
        let graph = Graph::new();
        let query = arena.pack_query(&axis_vector(8, 0)).unwrap();
        for exact in [false, true] {
            for (limit, max_distance) in [(Some(5), None), (None, Some(1.0)), (Some(1), Some(0.5))]
            {
                let found = search(
                    &graph,
                    &arena,
                    &query,
                    &params(limit, max_distance, exact),
                    None,
                );
                assert!(found.is_empty());
            }
        }
        assert_eq!(graph.entry_point(), None);
        assert_eq!(graph.node_count(), 0);
    }

    #[test]
    fn single_element_serves_every_mode() {
        let mut arena = VectorArena::new(8).unwrap();
        arena.upsert("only", &axis_vector(8, 0)).unwrap();
        let graph = Graph::rebuild(&arena);
        let query = arena.pack_query(&axis_vector(8, 0)).unwrap();
        for exact in [false, true] {
            let by_limit = search(&graph, &arena, &query, &params(Some(10), None, exact), None);
            assert_eq!(keys(&by_limit), ["only"]);
            assert_eq!(by_limit[0].distance, 0.0);
            let by_threshold = search(
                &graph,
                &arena,
                &query,
                &params(None, Some(0.0), exact),
                None,
            );
            assert_eq!(keys(&by_threshold), ["only"]);
        }
        let without_graph = search(
            &Graph::new(),
            &arena,
            &query,
            &params(Some(3), None, false),
            None,
        );
        assert_eq!(keys(&without_graph), ["only"]);
    }

    #[test]
    fn banned_entry_point_is_excluded_yet_still_routes_traversal() {
        let (arena, graph) = (&FIXTURE.0, &FIXTURE.1);
        let entry = graph.entry_point().unwrap();
        let entry_key = arena.key_of_slot(entry).unwrap();
        let query = arena.pack_query(&arena.vector_values(entry)).unwrap();
        let reference = reference_ranking(arena, &query, None);
        assert_eq!(reference[0].1, entry);
        for exact in [true, false] {
            let found = search_stored(graph, arena, entry, &params(Some(10), None, exact), None);
            assert_eq!(found.len(), 10);
            assert_sorted(&found);
            assert!(found.iter().all(|hit| hit.key != entry_key));
            if exact {
                let expected: Vec<&str> = reference[1..11]
                    .iter()
                    .map(|&(_, slot)| arena.key_of_slot(slot).unwrap())
                    .collect();
                assert_eq!(keys(&found), expected);
            }
        }
        let everything = search_stored(graph, arena, entry, &params(None, Some(2.5), false), None);
        assert_eq!(everything.len(), FIXTURE_COUNT - 1);
        assert!(everything.iter().all(|hit| hit.key != entry_key));
        let large_filter: HashSet<u32> = (0..1200).chain([entry]).collect();
        assert!(large_filter.len() > small_filter_cap(Some(10)));
        let filtered = search_stored(
            graph,
            arena,
            entry,
            &params(Some(10), None, false),
            Some(&large_filter),
        );
        assert_eq!(filtered.len(), 10);
        assert!(filtered.iter().all(|hit| hit.key != entry_key));
        let small_filter: HashSet<u32> = reference[..12].iter().map(|&(_, slot)| slot).collect();
        let brute = search_stored(
            graph,
            arena,
            entry,
            &params(Some(12), None, false),
            Some(&small_filter),
        );
        let expected: Vec<&str> = reference[1..12]
            .iter()
            .map(|&(_, slot)| arena.key_of_slot(slot).unwrap())
            .collect();
        assert_eq!(keys(&brute), expected);
    }

    #[test]
    fn banned_only_node_yields_empty_in_every_mode() {
        let mut arena = VectorArena::new(8).unwrap();
        arena.upsert("only", &axis_vector(8, 0)).unwrap();
        let graph = Graph::rebuild(&arena);
        let allowed: HashSet<u32> = [0].into_iter().collect();
        for exact in [true, false] {
            for filter in [None, Some(&allowed)] {
                let by_limit =
                    search_stored(&graph, &arena, 0, &params(Some(5), None, exact), filter);
                assert!(by_limit.is_empty());
                let by_threshold =
                    search_stored(&graph, &arena, 0, &params(None, Some(2.5), exact), filter);
                assert!(by_threshold.is_empty());
            }
        }
    }

    #[test]
    fn stored_key_search_fills_across_duplicate_groups() {
        let (arena, graph) = build_duplicate_groups(4, 80);
        let stored = 120;
        let found = search_stored(
            &graph,
            &arena,
            stored,
            &params(Some(100), None, false),
            None,
        );
        assert_eq!(found.len(), 100.min(arena.live_count() - 1));
        assert_sorted(&found);
        assert!(found.iter().all(|hit| hit.key != "key-120"));
        assert_leading_group(&arena, &found, 79, 1, 80);
    }

    #[test]
    fn stored_key_search_reaches_its_own_group_from_a_node_linked_elsewhere() {
        let (arena, graph) = build_duplicate_groups(4, 80);
        let stray = 80;
        assert!(
            graph
                .neighbors_of(stray, 0)
                .iter()
                .all(|&neighbor| neighbor / 80 == 0)
        );
        let found = search_stored(&graph, &arena, stray, &params(Some(10), None, false), None);
        assert_eq!(found.len(), 10);
        assert_leading_group(&arena, &found, 10, 1, 80);
    }

    #[test]
    fn filtered_stored_key_search_fills_from_other_duplicate_groups() {
        let (arena, graph) = build_duplicate_groups(4, 400);
        let stored = 600;
        let allowed: HashSet<u32> = arena.live_slots().filter(|slot| slot / 400 != 1).collect();
        assert!(allowed.len() > small_filter_cap(Some(100)));
        let found = search_stored(
            &graph,
            &arena,
            stored,
            &params(Some(100), None, false),
            Some(&allowed),
        );
        assert_eq!(found.len(), 100);
        assert_sorted(&found);
        for hit in &found {
            assert!(allowed.contains(&arena.slot_of_key(&hit.key).unwrap()));
        }
        let nearest = group_of(&arena, &found[0].key, 400);
        assert_ne!(nearest, 1);
        assert_leading_group(&arena, &found, 100, nearest, 400);
    }

    #[test]
    fn cold_search_fills_across_duplicate_groups() {
        let (arena, graph) = build_duplicate_groups(4, 80);
        let query = arena
            .pack_query(&seeded_unit_vector(DUPLICATE_GROUP_SEED, 16))
            .unwrap();
        let ten = search(&graph, &arena, &query, &params(Some(10), None, false), None);
        assert_eq!(ten.len(), 10);
        assert_leading_group(&arena, &ten, 10, 0, 80);
        let hundred = search(
            &graph,
            &arena,
            &query,
            &params(Some(100), None, false),
            None,
        );
        assert_eq!(hundred.len(), 100);
        assert_sorted(&hundred);
        assert_leading_group(&arena, &hundred, 80, 0, 80);
    }

    #[test]
    fn all_dead_index_returns_empty() {
        let mut arena = build_arena(5, 8, 0x0B00_0000);
        let graph = Graph::rebuild(&arena);
        for index in 0..5 {
            arena.remove(&format!("key-{index}")).unwrap();
        }
        let query = arena.pack_query(&axis_vector(8, 0)).unwrap();
        for exact in [false, true] {
            let by_limit = search(&graph, &arena, &query, &params(Some(3), None, exact), None);
            assert!(by_limit.is_empty());
            let by_threshold = search(
                &graph,
                &arena,
                &query,
                &params(None, Some(2.5), exact),
                None,
            );
            assert!(by_threshold.is_empty());
        }
    }

    #[test]
    fn tombstoned_nearest_neighbors_never_surface() {
        let (mut arena, graph) = build_fixture(300, 16, 0x3000_0000);
        let query = arena
            .pack_query(&seeded_unit_vector(0x3111_0000, 16))
            .unwrap();
        let reference = reference_ranking(&arena, &query, None);
        let removed: Vec<String> = reference[..10]
            .iter()
            .map(|&(_, slot)| arena.key_of_slot(slot).unwrap().to_string())
            .collect();
        let survivors: Vec<String> = reference[10..20]
            .iter()
            .map(|&(_, slot)| arena.key_of_slot(slot).unwrap().to_string())
            .collect();
        for key in &removed {
            arena.remove(key).unwrap();
        }
        for exact in [false, true] {
            let found = search(&graph, &arena, &query, &params(Some(10), None, exact), None);
            assert_eq!(found.len(), 10);
            for hit in &found {
                assert!(!removed.contains(&hit.key));
            }
            if exact {
                assert_eq!(keys(&found), survivors);
            }
        }
        let nearest_distance = reference[0].0;
        let within = search(
            &graph,
            &arena,
            &query,
            &params(None, Some(nearest_distance), false),
            None,
        );
        for hit in &within {
            assert!(!removed.contains(&hit.key));
        }
        let allowed: HashSet<u32> = reference[..12].iter().map(|&(_, slot)| slot).collect();
        let filtered = search(
            &graph,
            &arena,
            &query,
            &params(Some(12), None, false),
            Some(&allowed),
        );
        assert_eq!(keys(&filtered), survivors[..2]);
    }

    #[test]
    fn reinsert_moves_key_to_its_new_position() {
        let (mut arena, mut graph) = build_fixture(300, 16, 0x4000_0000);
        let old_vector = arena.vector_values(7);
        let new_vector = seeded_unit_vector(0x4222_0000, 16);
        let outcome = arena.upsert("key-7", &new_vector).unwrap();
        assert_eq!(outcome, UpsertOutcome::ReplacedInPlace(7));
        graph.reinsert(7, &arena);
        let new_query = arena.pack_query(&new_vector).unwrap();
        for exact in [false, true] {
            let top = search(
                &graph,
                &arena,
                &new_query,
                &params(Some(1), None, exact),
                None,
            );
            assert_eq!(keys(&top), ["key-7"]);
            assert!(top[0].distance < 1e-3);
        }
        let old_query = arena.pack_query(&old_vector).unwrap();
        let moved_distance = arena.distance_to_query(old_query.as_query(), 7);
        assert!(moved_distance > 0.3);
        let near_old = search(
            &graph,
            &arena,
            &old_query,
            &params(None, Some(0.3), false),
            None,
        );
        for hit in &near_old {
            assert_ne!(hit.key, "key-7");
        }
        let everything = search(
            &graph,
            &arena,
            &new_query,
            &params(None, Some(2.5), false),
            None,
        );
        assert_eq!(everything.len(), 300);
    }

    #[test]
    fn reinsert_of_entry_point_keeps_graph_searchable() {
        let (mut arena, mut graph) = build_fixture(300, 16, 0x5000_0000);
        let entry_slot = graph.entry_point().unwrap();
        let entry_key = arena.key_of_slot(entry_slot).unwrap().to_string();
        let new_vector = seeded_unit_vector(0x5222_0000, 16);
        let outcome = arena.upsert(&entry_key, &new_vector).unwrap();
        assert_eq!(outcome, UpsertOutcome::ReplacedInPlace(entry_slot));
        graph.reinsert(entry_slot, &arena);
        assert!(graph.entry_point().is_some());
        let query = arena.pack_query(&new_vector).unwrap();
        let top = search(&graph, &arena, &query, &params(Some(1), None, false), None);
        assert_eq!(keys(&top), [entry_key.as_str()]);
        let everything = search(
            &graph,
            &arena,
            &query,
            &params(None, Some(2.5), false),
            None,
        );
        assert_eq!(everything.len(), 300);
    }

    #[test]
    fn reinsert_recycled_slot_serves_the_new_key() {
        let (mut arena, mut graph) = build_fixture(300, 16, 0x6000_0000);
        assert_eq!(arena.remove("key-3"), Some(3));
        let new_vector = seeded_unit_vector(0x6222_0000, 16);
        let outcome = arena.upsert("fresh", &new_vector).unwrap();
        assert_eq!(outcome, UpsertOutcome::RecycledSlot(3));
        graph.reinsert(3, &arena);
        let query = arena.pack_query(&new_vector).unwrap();
        for exact in [false, true] {
            let top = search(&graph, &arena, &query, &params(Some(1), None, exact), None);
            assert_eq!(keys(&top), ["fresh"]);
        }
        let everything = search(
            &graph,
            &arena,
            &query,
            &params(None, Some(2.5), false),
            None,
        );
        assert_eq!(everything.len(), 300);
        assert!(everything.iter().all(|hit| hit.key != "key-3"));
        assert!(everything.iter().any(|hit| hit.key == "fresh"));
    }

    #[test]
    fn reinsert_of_the_only_node_resets_entry_point() {
        let mut arena = VectorArena::new(8).unwrap();
        arena.upsert("solo", &axis_vector(8, 0)).unwrap();
        let mut graph = Graph::rebuild(&arena);
        assert_eq!(graph.entry_point(), Some(0));
        arena.upsert("solo", &axis_vector(8, 3)).unwrap();
        graph.reinsert(0, &arena);
        assert_eq!(graph.entry_point(), Some(0));
        let query = arena.pack_query(&axis_vector(8, 3)).unwrap();
        let found = search(&graph, &arena, &query, &params(Some(5), None, false), None);
        assert_eq!(keys(&found), ["solo"]);
        assert_eq!(found[0].distance, 0.0);
    }

    #[test]
    fn small_filter_takes_the_exact_path_within_the_filter() {
        let (arena, graph) = (&FIXTURE.0, &FIXTURE.1);
        let query = arena
            .pack_query(&seeded_unit_vector(0x00DD_0001, FIXTURE_DIMS))
            .unwrap();
        let allowed: HashSet<u32> = (0..FIXTURE_COUNT as u32)
            .filter(|slot| slot % 150 == 3)
            .collect();
        assert_eq!(allowed.len(), 10);
        let reference = reference_ranking(arena, &query, Some(&allowed));
        let found = search(
            graph,
            arena,
            &query,
            &params(Some(3), None, false),
            Some(&allowed),
        );
        assert_eq!(found.len(), 3);
        for (hit, &(distance, slot)) in found.iter().zip(&reference) {
            assert_eq!(hit.key, arena.key_of_slot(slot).unwrap());
            assert_eq!(hit.distance, distance);
            assert!(allowed.contains(&slot));
        }
    }

    #[test]
    fn usize_max_limit_does_not_overflow_with_or_without_filter() {
        let (arena, graph) = (&FIXTURE.0, &FIXTURE.1);
        let query = arena
            .pack_query(&seeded_unit_vector(0x00DD_0006, FIXTURE_DIMS))
            .unwrap();
        let allowed: HashSet<u32> = (0..3).collect();
        let filtered = search(
            graph,
            arena,
            &query,
            &params(Some(usize::MAX), None, false),
            Some(&allowed),
        );
        assert_eq!(filtered.len(), 3);
        let unfiltered = search(
            graph,
            arena,
            &query,
            &params(Some(usize::MAX), None, false),
            None,
        );
        assert_eq!(unfiltered.len(), FIXTURE_COUNT);
    }

    #[test]
    fn large_filter_traverses_the_graph_and_respects_the_filter() {
        let (arena, graph) = (&FIXTURE.0, &FIXTURE.1);
        let query = arena
            .pack_query(&seeded_unit_vector(0x00DD_0002, FIXTURE_DIMS))
            .unwrap();
        let allowed: HashSet<u32> = (0..1200).collect();
        assert!(allowed.len() > small_filter_cap(Some(10)));
        let reference = reference_ranking(arena, &query, Some(&allowed));
        let found = search(
            graph,
            arena,
            &query,
            &params(Some(10), None, false),
            Some(&allowed),
        );
        assert_eq!(found.len(), 10);
        assert_sorted(&found);
        for hit in &found {
            assert!(allowed.contains(&arena.slot_of_key(&hit.key).unwrap()));
        }
        let expected: HashSet<&str> = reference[..10]
            .iter()
            .map(|&(_, slot)| arena.key_of_slot(slot).unwrap())
            .collect();
        let hits = found
            .iter()
            .filter(|hit| expected.contains(hit.key.as_str()))
            .count();
        assert!(hits >= 9, "filtered recall@10 was {hits}/10");
        let within = search(
            graph,
            arena,
            &query,
            &params(None, Some(0.9), false),
            Some(&allowed),
        );
        assert!(!within.is_empty());
        assert_sorted(&within);
        for hit in &within {
            assert!(hit.distance <= 0.9);
            assert!(allowed.contains(&arena.slot_of_key(&hit.key).unwrap()));
        }
    }

    #[test]
    fn every_params_combination_upholds_result_contracts() {
        let (arena, graph) = (&FIXTURE.0, &FIXTURE.1);
        let query = arena
            .pack_query(&seeded_unit_vector(0x00DD_0003, FIXTURE_DIMS))
            .unwrap();
        let small_filter: HashSet<u32> = (0..600).collect();
        let large_filter: HashSet<u32> = (0..1200).collect();
        let filters: [Option<&HashSet<u32>>; 3] = [None, Some(&small_filter), Some(&large_filter)];
        for allowed in filters {
            let reference = reference_ranking(arena, &query, allowed);
            for exact in [true, false] {
                for limit in [None, Some(1), Some(7), Some(5000)] {
                    for max_distance in [None, Some(0.9)] {
                        if limit.is_none() && max_distance.is_none() {
                            continue;
                        }
                        let found = search(
                            graph,
                            arena,
                            &query,
                            &params(limit, max_distance, exact),
                            allowed,
                        );
                        assert_sorted(&found);
                        if let Some(cap) = limit {
                            assert!(found.len() <= cap);
                        }
                        for hit in &found {
                            let slot = arena.slot_of_key(&hit.key).unwrap();
                            assert!(arena.is_alive(slot));
                            if let Some(set) = allowed {
                                assert!(set.contains(&slot));
                            }
                            if let Some(threshold) = max_distance {
                                assert!(hit.distance <= threshold);
                            }
                            assert_eq!(
                                hit.distance,
                                arena.distance_to_query(query.as_query(), slot)
                            );
                        }
                        let expected: Vec<(f32, u32)> = reference
                            .iter()
                            .copied()
                            .filter(|(distance, _)| {
                                max_distance.is_none_or(|threshold| *distance <= threshold)
                            })
                            .take(limit.unwrap_or(usize::MAX))
                            .collect();
                        if exact {
                            assert_eq!(found.len(), expected.len());
                            for (hit, (distance, slot)) in found.iter().zip(&expected) {
                                assert_eq!(hit.key, arena.key_of_slot(*slot).unwrap());
                                assert_eq!(hit.distance, *distance);
                            }
                        } else if max_distance.is_none() {
                            assert_eq!(found.len(), expected.len());
                        } else if !expected.is_empty() {
                            assert!(!found.is_empty());
                        }
                    }
                }
            }
        }
    }

    #[test]
    fn stepped_threshold_search_expands_to_cover_the_live_set() {
        let (arena, graph) = (&FIXTURE.0, &FIXTURE.1);
        let query = arena
            .pack_query(&seeded_unit_vector(0x00DD_0004, FIXTURE_DIMS))
            .unwrap();
        let everything = search(graph, arena, &query, &params(None, Some(2.5), false), None);
        assert_eq!(everything.len(), FIXTURE_COUNT);
        assert_sorted(&everything);
    }

    #[test]
    fn tight_threshold_search_stops_early_and_finds_the_head() {
        let (arena, graph) = (&FIXTURE.0, &FIXTURE.1);
        let query = arena
            .pack_query(&seeded_unit_vector(0x00DD_0005, FIXTURE_DIMS))
            .unwrap();
        let reference = reference_ranking(arena, &query, None);
        let threshold = reference[4].0;
        let found = search(
            graph,
            arena,
            &query,
            &params(None, Some(threshold), false),
            None,
        );
        let expected: Vec<&str> = reference
            .iter()
            .take_while(|(distance, _)| *distance <= threshold)
            .map(|&(_, slot)| arena.key_of_slot(slot).unwrap())
            .collect();
        assert_eq!(keys(&found), expected);
    }

    #[test]
    fn reserve_slots_grows_the_slot_arrays_a_bounded_number_of_times() {
        let mut graph = Graph::new();
        let mut reallocations = 0;
        let mut capacity = graph.zero_neighbors.capacity();
        for slots in 1..=20_000 {
            graph.reserve_slots(slots);
            if graph.zero_neighbors.capacity() != capacity {
                capacity = graph.zero_neighbors.capacity();
                reallocations += 1;
            }
        }
        assert!(reallocations < 64, "{reallocations} reallocations");
        assert_eq!(graph.node_levels.len(), 20_000);
        for (len, capacity) in [
            (graph.node_levels.len(), graph.node_levels.capacity()),
            (graph.zero_lengths.len(), graph.zero_lengths.capacity()),
            (graph.zero_neighbors.len(), graph.zero_neighbors.capacity()),
        ] {
            assert!(
                capacity <= len + len / 8 + MIN_GROWTH_SPARE,
                "{capacity} reserved for {len}"
            );
        }
    }

    #[test]
    fn from_parts_reserves_the_slot_arrays_exactly() {
        let (arena, graph) = build_fixture(1500, 16, 0x8100_0000);
        let slots = arena.slot_count();
        assert!(slots >= 1024);
        let rebuilt = Graph::from_parts(
            graph.entry_point(),
            graph_parts(&graph),
            slots,
            graph.insert_ordinal(),
        )
        .unwrap();
        assert_eq!(rebuilt.node_levels.capacity(), slots);
        assert_eq!(rebuilt.zero_lengths.capacity(), slots);
        assert_eq!(
            rebuilt.zero_neighbors.capacity(),
            slots * LEVEL_ZERO_NEIGHBOR_CAP
        );
        for upper in &rebuilt.upper {
            assert_eq!(upper.dense_of_slot.capacity(), slots);
        }
    }

    #[test]
    fn identical_insert_sequences_build_identical_graphs() {
        let arena = build_arena(500, 16, 0x7000_0000);
        let first = Graph::rebuild(&arena);
        let second = Graph::rebuild(&arena);
        assert_identical_graphs(&first, &second);
        assert_graph_invariants(&first);
    }

    #[test]
    fn from_parts_round_trips_the_snapshot_accessors() {
        let (arena, graph) = build_fixture(300, 16, 0x8000_0000);
        let parts = graph_parts(&graph);
        assert_eq!(parts.len(), graph.node_count());
        let rebuilt = Graph::from_parts(
            graph.entry_point(),
            parts,
            arena.slot_count(),
            graph.insert_ordinal(),
        )
        .unwrap();
        assert_identical_graphs(&rebuilt, &graph);
        let query = arena
            .pack_query(&seeded_unit_vector(0x8111_0000, 16))
            .unwrap();
        let from_original = search(&graph, &arena, &query, &params(Some(10), None, false), None);
        let from_rebuilt = search(
            &rebuilt,
            &arena,
            &query,
            &params(Some(10), None, false),
            None,
        );
        assert_eq!(from_original, from_rebuilt);
    }

    #[test]
    fn inserts_after_a_maximal_persisted_ordinal_wrap_instead_of_panicking() {
        let arena = build_arena(2, 8, 0x00D0_0000);
        let mut graph = Graph::from_parts(None, Vec::new(), arena.slot_count(), u64::MAX).unwrap();
        graph.insert(0, &arena);
        assert_eq!(graph.insert_ordinal(), 0);
        graph.insert(1, &arena);
        assert_eq!(graph.insert_ordinal(), 1);
        assert!(graph.level_of(0).is_some());
        assert!(graph.level_of(1).is_some());
    }

    #[test]
    fn from_parts_rejects_malformed_parts() {
        let node = |slot: u32, level: u8, neighbors: Vec<Vec<u32>>| GraphNodeParts {
            slot,
            level,
            neighbors,
        };
        assert!(Graph::from_parts(None, Vec::new(), 0, 0).is_ok());
        assert!(Graph::from_parts(Some(0), vec![node(0, 0, vec![Vec::new()])], 1, 0).is_ok());
        assert!(Graph::from_parts(Some(0), vec![node(0, 1, vec![Vec::new()])], 1, 0).is_err());
        assert!(Graph::from_parts(Some(0), vec![node(0, 0, vec![vec![9]])], 10, 0).is_err());
        assert!(Graph::from_parts(None, vec![node(0, 0, vec![Vec::new()])], 1, 0).is_err());
        assert!(Graph::from_parts(Some(5), vec![node(0, 0, vec![Vec::new()])], 6, 0).is_err());
        assert!(
            Graph::from_parts(
                Some(0),
                vec![node(0, 0, vec![Vec::new()]), node(0, 0, vec![Vec::new()])],
                1,
                0
            )
            .is_err()
        );
        assert!(
            Graph::from_parts(
                Some(1),
                vec![
                    node(0, 0, vec![vec![1]]),
                    node(1, 1, vec![vec![0], Vec::new()])
                ],
                2,
                0
            )
            .is_ok()
        );
    }

    #[test]
    fn from_parts_rejects_slots_beyond_the_arena() {
        let node = |slot: u32, level: u8, neighbors: Vec<Vec<u32>>| GraphNodeParts {
            slot,
            level,
            neighbors,
        };
        assert!(Graph::from_parts(Some(0), vec![node(0, 0, vec![Vec::new()])], 0, 0).is_err());
        assert!(Graph::from_parts(Some(2), vec![node(2, 0, vec![Vec::new()])], 2, 0).is_err());
        assert!(
            Graph::from_parts(
                Some(u32::MAX - 1),
                vec![node(u32::MAX - 1, 0, vec![Vec::new()])],
                3,
                0
            )
            .is_err()
        );
    }

    #[test]
    fn from_parts_tolerates_stale_edges_to_shrunken_levels() {
        let node = |slot: u32, level: u8, neighbors: Vec<Vec<u32>>| GraphNodeParts {
            slot,
            level,
            neighbors,
        };
        let graph = Graph::from_parts(
            Some(1),
            vec![
                node(0, 0, vec![vec![1]]),
                node(1, 1, vec![vec![0, 2], vec![0]]),
                node(2, 0, vec![vec![1]]),
            ],
            3,
            0,
        )
        .unwrap();
        let mut arena = VectorArena::new(8).unwrap();
        arena.upsert("a", &axis_vector(8, 0)).unwrap();
        arena
            .upsert(
                "b",
                &two_axis_vector((0, FRAC_1_SQRT_2), (1, FRAC_1_SQRT_2)),
            )
            .unwrap();
        arena.upsert("c", &axis_vector(8, 1)).unwrap();
        let query = arena.pack_query(&axis_vector(8, 1)).unwrap();
        let found = search(&graph, &arena, &query, &params(Some(3), None, false), None);
        assert_eq!(keys(&found), ["c", "b", "a"]);
    }

    #[test]
    fn overfull_neighbor_lists_are_rejected() {
        let parts: Vec<GraphNodeParts> = (0..40u32)
            .map(|slot| GraphNodeParts {
                slot,
                level: 0,
                neighbors: vec![if slot == 0 {
                    (0..40).collect()
                } else {
                    vec![0]
                }],
            })
            .collect();
        assert!(Graph::from_parts(Some(0), parts, 40, 0).is_err());
    }

    #[test]
    fn tolerated_self_edges_and_duplicates_stay_safe() {
        let dims = 16;
        let mut arena = build_arena(40, dims, 0x00E0_0000);
        let parts: Vec<GraphNodeParts> = (0..40u32)
            .map(|slot| GraphNodeParts {
                slot,
                level: 0,
                neighbors: vec![vec![0, 0, slot, (slot + 1) % 40]],
            })
            .collect();
        let graph = Graph::from_parts(Some(0), parts, arena.slot_count(), 0).unwrap();
        assert_eq!(graph.neighbors_of(0, 0), [0, 0, 0, 1]);
        let query = arena
            .pack_query(&seeded_unit_vector(0x00E1_0000, dims))
            .unwrap();
        let reference = reference_ranking(&arena, &query, None);
        let top = search(&graph, &arena, &query, &params(Some(10), None, false), None);
        for (hit, &(distance, slot)) in top.iter().zip(&reference) {
            assert_eq!(hit.key, arena.key_of_slot(slot).unwrap());
            assert_eq!(hit.distance, distance);
        }
        let everything = search(
            &graph,
            &arena,
            &query,
            &params(None, Some(2.5), false),
            None,
        );
        assert_eq!(everything.len(), 40);
        let mut graph = graph;
        apply_upsert(
            &mut arena,
            &mut graph,
            "fresh",
            &seeded_unit_vector(0x00E2_0000, dims),
        );
        let fresh_query = arena
            .pack_query(&seeded_unit_vector(0x00E2_0000, dims))
            .unwrap();
        let found = search(
            &graph,
            &arena,
            &fresh_query,
            &params(Some(1), None, false),
            None,
        );
        assert_eq!(keys(&found), ["fresh"]);
        let all = search(
            &graph,
            &arena,
            &fresh_query,
            &params(None, Some(2.5), false),
            None,
        );
        assert_sorted(&all);
        assert!(all.len() <= 41);
        assert!(all.iter().any(|hit| hit.key == "fresh"));
    }

    #[test]
    fn entry_point_below_the_top_level_still_reaches_every_node() {
        let node = |slot: u32, level: u8, neighbors: Vec<Vec<u32>>| GraphNodeParts {
            slot,
            level,
            neighbors,
        };
        let graph = Graph::from_parts(
            Some(1),
            vec![
                node(0, 2, vec![vec![1, 2], vec![2], vec![2]]),
                node(1, 0, vec![vec![0]]),
                node(2, 2, vec![vec![0], vec![0], vec![0]]),
            ],
            3,
            0,
        )
        .unwrap();
        let mut arena = VectorArena::new(8).unwrap();
        arena.upsert("a", &axis_vector(8, 0)).unwrap();
        arena.upsert("b", &axis_vector(8, 1)).unwrap();
        arena.upsert("c", &axis_vector(8, 2)).unwrap();
        let query = arena.pack_query(&axis_vector(8, 2)).unwrap();
        let found = search(&graph, &arena, &query, &params(Some(3), None, false), None);
        assert_eq!(found.len(), 3);
        assert_eq!(found[0].key, "c");
    }

    #[test]
    fn repeated_reinserts_shrink_levels_yet_keep_every_node_reachable() {
        let (mut arena, mut graph) = build_fixture(600, 16, 0xB000_0000);
        let mut stale_seen = false;
        for round in 0..40u64 {
            let victim = graph.entry_point().unwrap();
            let key = arena.key_of_slot(victim).unwrap().to_string();
            let vector = seeded_unit_vector(0xB100_0000 + round, 16);
            assert_eq!(
                arena.upsert(&key, &vector).unwrap(),
                UpsertOutcome::ReplacedInPlace(victim)
            );
            graph.reinsert(victim, &arena);
            stale_seen |= stale_downward_edge_exists(&graph);
            assert_graph_invariants(&graph);
            let reloaded = Graph::from_parts(
                graph.entry_point(),
                graph_parts(&graph),
                arena.slot_count(),
                graph.insert_ordinal(),
            )
            .unwrap();
            assert_identical_graphs(&reloaded, &graph);
            let query = arena.pack_query(&vector).unwrap();
            let top = search(&graph, &arena, &query, &params(Some(1), None, false), None);
            assert_eq!(keys(&top), [key.as_str()]);
            let everything = search(
                &graph,
                &arena,
                &query,
                &params(None, Some(2.5), false),
                None,
            );
            assert_eq!(everything.len(), 600);
        }
        assert!(stale_seen);
        let rebuilt = Graph::from_parts(
            graph.entry_point(),
            graph_parts(&graph),
            arena.slot_count(),
            graph.insert_ordinal(),
        )
        .unwrap();
        assert_identical_graphs(&rebuilt, &graph);
        let query = arena
            .pack_query(&seeded_unit_vector(0xB200_0000, 16))
            .unwrap();
        let from_churned = search(&graph, &arena, &query, &params(Some(10), None, false), None);
        let from_rebuilt = search(
            &rebuilt,
            &arena,
            &query,
            &params(Some(10), None, false),
            None,
        );
        assert_eq!(from_churned, from_rebuilt);
    }

    #[test]
    fn randomized_churn_upholds_contracts_determinism_and_connectivity() {
        let dims = 16;
        let mut primary = (VectorArena::new(dims).unwrap(), Graph::new());
        let mut shadow = (VectorArena::new(dims).unwrap(), Graph::new());
        let mut state = 0xC000_0000u64;
        let mut live: Vec<String> = Vec::new();
        let mut dead: Vec<String> = Vec::new();
        let mut next_id = 0u64;
        for _ in 0..12 {
            for _ in 0..50 {
                let roll = splitmix64(&mut state);
                let action = roll % 10;
                if action < 4 || live.is_empty() {
                    let key = format!("key-{next_id}");
                    next_id += 1;
                    let vector = seeded_unit_vector(splitmix64(&mut state), dims);
                    for pair in [&mut primary, &mut shadow] {
                        apply_upsert(&mut pair.0, &mut pair.1, &key, &vector);
                    }
                    live.push(key);
                } else if action < 7 {
                    let key = live[roll as usize % live.len()].clone();
                    let vector = seeded_unit_vector(splitmix64(&mut state), dims);
                    for pair in [&mut primary, &mut shadow] {
                        apply_upsert(&mut pair.0, &mut pair.1, &key, &vector);
                    }
                } else if action < 9 {
                    let key = live.swap_remove(roll as usize % live.len());
                    for pair in [&mut primary, &mut shadow] {
                        assert!(pair.0.remove(&key).is_some());
                    }
                    dead.push(key);
                } else if let Some(key) = dead.pop() {
                    let vector = seeded_unit_vector(splitmix64(&mut state), dims);
                    for pair in [&mut primary, &mut shadow] {
                        apply_upsert(&mut pair.0, &mut pair.1, &key, &vector);
                    }
                    live.push(key);
                }
            }
            let (arena, graph) = (&primary.0, &primary.1);
            assert_graph_invariants(graph);
            assert_eq!(arena.live_count(), live.len());
            let reloaded = Graph::from_parts(
                graph.entry_point(),
                graph_parts(graph),
                arena.slot_count(),
                graph.insert_ordinal(),
            )
            .unwrap();
            assert_identical_graphs(&reloaded, graph);
            for _ in 0..3 {
                let query_vector = seeded_unit_vector(splitmix64(&mut state), dims);
                let query = arena.pack_query(&query_vector).unwrap();
                let reference = reference_ranking(arena, &query, None);
                let top = search(graph, arena, &query, &params(Some(10), None, false), None);
                assert_sorted(&top);
                assert_eq!(top.len(), reference.len().min(10));
                for hit in &top {
                    let slot = arena.slot_of_key(&hit.key).unwrap();
                    assert!(arena.is_alive(slot));
                    assert_eq!(
                        hit.distance,
                        arena.distance_to_query(query.as_query(), slot)
                    );
                }
                let expected: HashSet<&str> = reference
                    .iter()
                    .take(10)
                    .map(|&(_, slot)| arena.key_of_slot(slot).unwrap())
                    .collect();
                let hits = top
                    .iter()
                    .filter(|hit| expected.contains(hit.key.as_str()))
                    .count();
                assert!(
                    hits + 1 >= top.len(),
                    "churn recall was {hits}/{}",
                    top.len()
                );
                let everything =
                    search(graph, arena, &query, &params(None, Some(2.5), false), None);
                assert_sorted(&everything);
                assert_eq!(everything.len(), live.len());
                if reference.len() >= 5 {
                    let threshold = reference[4].0;
                    let within = search(
                        graph,
                        arena,
                        &query,
                        &params(None, Some(threshold), false),
                        None,
                    );
                    assert_sorted(&within);
                    let expected_within: HashSet<&str> = reference
                        .iter()
                        .take_while(|(distance, _)| *distance <= threshold)
                        .map(|&(_, slot)| arena.key_of_slot(slot).unwrap())
                        .collect();
                    for hit in &within {
                        assert!(hit.distance <= threshold);
                        assert!(expected_within.contains(hit.key.as_str()));
                    }
                }
                let allowed: HashSet<u32> =
                    arena.live_slots().filter(|slot| slot % 2 == 0).collect();
                if !allowed.is_empty() {
                    let filtered = search(
                        graph,
                        arena,
                        &query,
                        &params(Some(5), None, false),
                        Some(&allowed),
                    );
                    assert_sorted(&filtered);
                    assert_eq!(filtered.len(), allowed.len().min(5));
                    for hit in &filtered {
                        assert!(allowed.contains(&arena.slot_of_key(&hit.key).unwrap()));
                    }
                }
            }
        }
        assert_identical_graphs(&primary.1, &shadow.1);
        let (arena, graph) = (&primary.0, &primary.1);
        let rebuilt = Graph::from_parts(
            graph.entry_point(),
            graph_parts(graph),
            arena.slot_count(),
            graph.insert_ordinal(),
        )
        .unwrap();
        assert_identical_graphs(&rebuilt, graph);
        let query = arena
            .pack_query(&seeded_unit_vector(0xC900_0000, dims))
            .unwrap();
        let from_churned = search(graph, arena, &query, &params(Some(10), None, false), None);
        let from_rebuilt = search(
            &rebuilt,
            arena,
            &query,
            &params(Some(10), None, false),
            None,
        );
        assert_eq!(from_churned, from_rebuilt);
    }

    #[test]
    fn nearly_all_dead_graph_terminates_with_only_the_living() {
        let (mut arena, graph) = build_fixture(400, 16, 0xD000_0000);
        for index in 0..400 {
            if index % 80 != 0 {
                arena.remove(&format!("key-{index}")).unwrap();
            }
        }
        assert_eq!(arena.live_count(), 5);
        let query = arena
            .pack_query(&seeded_unit_vector(0xD100_0000, 16))
            .unwrap();
        let reference = reference_ranking(&arena, &query, None);
        let expected: Vec<&str> = reference
            .iter()
            .map(|&(_, slot)| arena.key_of_slot(slot).unwrap())
            .collect();
        let top = search(&graph, &arena, &query, &params(Some(10), None, false), None);
        assert_eq!(keys(&top), expected);
        let everything = search(
            &graph,
            &arena,
            &query,
            &params(None, Some(2.5), false),
            None,
        );
        assert_eq!(keys(&everything), expected);
    }

    #[test]
    fn non_finite_queries_return_empty_without_panicking() {
        let (arena, graph) = handcrafted();
        for value in [f32::NAN, f32::INFINITY, f32::NEG_INFINITY] {
            let mut bad = axis_vector(8, 0);
            bad[3] = value;
            let query = arena.pack_query(&bad).unwrap();
            for exact in [false, true] {
                for (limit, max_distance) in [(Some(3), None), (None, Some(1.0))] {
                    let found = search(
                        &graph,
                        &arena,
                        &query,
                        &params(limit, max_distance, exact),
                        None,
                    );
                    assert!(found.is_empty());
                }
            }
        }
    }

    #[test]
    fn approx_recall_at_10_meets_the_bar_on_8k_vectors() {
        let seed = 0x9000_0000u64;
        let (arena, graph) = build_clustered_fixture(8000, 64, 64, seed);
        let recall = measured_recall(&arena, &graph, 50, |index| {
            clustered_unit_vector(seed + index % 64, seed + 0x0200_0000 + index, 64)
        });
        assert!(recall >= 0.98, "recall@10 was {recall}");
    }

    #[test]
    fn uniform_random_recall_stays_above_the_documented_floor() {
        let (arena, graph) = build_fixture(8000, 64, 0x9500_0000);
        let recall = measured_recall(&arena, &graph, 50, |index| {
            seeded_unit_vector(0x9511_0000 + index, 64)
        });
        assert!(recall >= 0.90, "recall@10 was {recall}");
    }

    #[test]
    #[ignore]
    fn approx_recall_at_10_meets_the_bar_on_100k_vectors() {
        let seed = 0xA000_0000u64;
        let (arena, graph) = build_latent_fixture(100_000, 512, 512, seed);
        let projection = latent_projection(seed, 512);
        let recall = measured_recall(&arena, &graph, 50, |index| {
            let latent =
                clustered_unit_vector(seed + index % 512, seed + 0x0200_0000 + index, LATENT_DIMS);
            projected_unit_vector(&projection, &latent)
        });
        assert!(recall >= 0.97, "recall@10 was {recall}");
    }

    #[test]
    fn i8_approx_recall_at_10_meets_the_bar_on_8k_vectors() {
        let seed = 0x9000_0000u64;
        let (arena, graph) = build_clustered_fixture_with(8000, 64, 64, seed, StorageKind::I8);
        assert_eq!(arena.storage_kind(), StorageKind::I8);
        let recall = measured_recall(&arena, &graph, 50, |index| {
            clustered_unit_vector(seed + index % 64, seed + 0x0200_0000 + index, 64)
        });
        assert!(recall >= 0.975, "i8 recall@10 was {recall}");
    }

    #[test]
    fn i8_uniform_random_recall_stays_above_the_documented_floor() {
        let mut arena = VectorArena::with_storage(64, StorageKind::I8).unwrap();
        for index in 0..8000u64 {
            arena
                .upsert(
                    &format!("key-{index}"),
                    &seeded_unit_vector(0x9500_0000 + index, 64),
                )
                .unwrap();
        }
        let graph = Graph::rebuild(&arena);
        let recall = measured_recall(&arena, &graph, 50, |index| {
            seeded_unit_vector(0x9511_0000 + index, 64)
        });
        assert!(recall >= 0.895, "i8 recall@10 was {recall}");
    }

    #[test]
    fn i8_exact_search_recovers_the_f32_ground_truth_at_10() {
        let seed = 0x9000_0000u64;
        let (f32_arena, _) = build_clustered_fixture(8000, 64, 64, seed);
        let (i8_arena, i8_graph) =
            build_clustered_fixture_with(8000, 64, 64, seed, StorageKind::I8);
        let mut hits = 0usize;
        for index in 0..50u64 {
            let values = clustered_unit_vector(seed + index % 64, seed + 0x0200_0000 + index, 64);
            let f32_query = f32_arena.pack_query(&values).unwrap();
            let truth: HashSet<&str> = reference_ranking(&f32_arena, &f32_query, None)[..10]
                .iter()
                .map(|&(_, slot)| f32_arena.key_of_slot(slot).unwrap())
                .collect();
            let i8_query = i8_arena.pack_query(&values).unwrap();
            let exact = search(
                &i8_graph,
                &i8_arena,
                &i8_query,
                &params(Some(10), None, true),
                None,
            );
            assert_eq!(exact.len(), 10);
            let reference = reference_ranking(&i8_arena, &i8_query, None);
            for (hit, &(distance, slot)) in exact.iter().zip(&reference) {
                assert_eq!(hit.key, i8_arena.key_of_slot(slot).unwrap());
                assert_eq!(hit.distance, distance);
            }
            hits += exact
                .iter()
                .filter(|hit| truth.contains(hit.key.as_str()))
                .count();
        }
        let recall = hits as f64 / 500.0;
        assert!(
            recall >= 0.99,
            "i8-exact vs f32 truth recall@10 was {recall}"
        );
    }
}
