use std::collections::HashSet;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};

use usearch::{Index, IndexOptions, MetricKind, ScalarKind};

const FAST_SEARCH_STEP_COUNTS: [usize; 5] = [200, 500, 2000, 5000, 10000];
static INDEX_SAVE_TEMP_COUNTER: AtomicU64 = AtomicU64::new(0);

type SearchMatch = (Vec<u64>, Vec<f32>);
type BulkSearchMatch = (Vec<Vec<u64>>, Vec<Vec<f32>>);
type BulkSearchByKeyMatch = (Vec<u64>, Vec<Vec<u64>>, Vec<Vec<f32>>);

pub struct VectorDB {
    index: Index,
    path: PathBuf,
}

impl VectorDB {
    pub fn new(file_path: &str, dimensions: usize) -> Result<Self, String> {
        let path = PathBuf::from(file_path);
        let file_exists = path.try_exists().map_err(|e| {
            format!(
                "Failed to check index file existence at {}: {e}",
                path.display()
            )
        })?;

        let options = IndexOptions {
            dimensions,
            metric: MetricKind::IP,
            quantization: ScalarKind::F32,
            connectivity: 0,     // auto
            expansion_add: 0,    // auto
            expansion_search: 0, // auto
            ..IndexOptions::default()
        };

        let index = Index::new(&options).map_err(|e| format!("Failed to create index: {e}"))?;
        index
            .reserve(1000)
            .map_err(|e| format!("Failed to reserve space in index: {e}"))?;

        let db = Self { index, path };

        if file_exists {
            println!("Loading index from disk.");
            // Must use load() instead of view() because:
            // - view() creates a read-only memory-mapped view (immutable)
            // - load() loads the index into RAM for read/write operations (mutable)
            // Using view() causes "Can't add to an immutable index" error
            db.index
                .load(file_path)
                .map_err(|e| format!("Failed to load index from {file_path}: {e}"))?;
        } else {
            println!("Creating new index.");
            db.save_index()?;
        }
        Ok(db)
    }

    fn save_index(&self) -> Result<(), String> {
        // Ensure directory exists
        if let Some(parent) = self.path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| {
                format!(
                    "Failed to create index parent directory {}: {e}",
                    parent.display()
                )
            })?;
        }

        // Use atomic write: save to temp file first, then rename
        // Use a unique temp path per save so concurrent saves can never race
        // by clobbering the same temporary file.
        let save_sequence = INDEX_SAVE_TEMP_COUNTER.fetch_add(1, Ordering::Relaxed);
        let temp_path =
            self.path
                .with_extension(format!("tmp.{}.{}", std::process::id(), save_sequence));
        let temp_path_str = temp_path
            .to_str()
            .ok_or_else(|| format!("Invalid temp path: {}", temp_path.display()))?;

        // Save to temporary file
        self.index.save(temp_path_str).map_err(|e| {
            let _ = std::fs::remove_file(&temp_path);
            format!(
                "Failed to save index to temp file {}: {e}",
                temp_path.display()
            )
        })?;

        // Atomic rename - guaranteed atomic on iOS/Android
        // This will atomically replace the existing file
        // The rename ensures we never have a partially written file,
        // even if the app is suspended or crashes
        if let Err(e) = std::fs::rename(&temp_path, &self.path) {
            let _ = std::fs::remove_file(&temp_path);
            return Err(format!(
                "Failed to atomically save index (rename {} -> {}): {e}",
                temp_path.display(),
                self.path.display()
            ));
        }

        println!("Successfully saved index atomically");
        Ok(())
    }

    fn ensure_capacity(&self, margin: usize) -> Result<(), String> {
        let current_size = self.index.size();
        let capacity = self.index.capacity();
        if current_size + margin + 1000 >= capacity {
            self.index
                .reserve(current_size + margin)
                .map_err(|e| format!("Failed to reserve space in index: {e}"))?;
        }
        Ok(())
    }

    pub fn add_vector(&mut self, key: u64, vector: &[f32]) -> Result<(), String> {
        if self.contains_vector(key) {
            self.index
                .remove(key)
                .map_err(|e| format!("Failed to remove existing vector for key {key}: {e}"))?;
        } else {
            self.ensure_capacity(1)?;
        }
        self.index
            .add(key, vector)
            .map_err(|e| format!("Failed to add vector for key {key}: {e}"))?;
        self.save_index()
    }

    pub fn bulk_add_vectors(&mut self, keys: Vec<u64>, vectors: &[Vec<f32>]) -> Result<(), String> {
        self.ensure_capacity(keys.len())?;
        for (key, vector) in keys.iter().zip(vectors.iter()) {
            if self.contains_vector(*key) {
                self.index.remove(*key).map_err(|e| {
                    format!("Failed to remove existing vector for key {key} before bulk add: {e}")
                })?;
            }
            self.index
                .add(*key, vector)
                .map_err(|e| format!("Failed to bulk add vector for key {key}: {e}"))?;
        }
        self.save_index()
    }

    pub fn search_vectors(
        &self,
        query: &[f32],
        count: usize,
        exact: bool,
    ) -> Result<SearchMatch, String> {
        let matches = if exact {
            self.index
                .exact_search(query, count)
                .map_err(|e| format!("Failed to exact search vectors: {e}"))?
        } else {
            self.index
                .search(query, count)
                .map_err(|e| format!("Failed to search vectors: {e}"))?
        };
        Ok((matches.keys, matches.distances))
    }

    pub fn approx_search_vectors_within_similarity(
        &self,
        query: &[f32],
        minimum_similarity: f32,
    ) -> Result<SearchMatch, String> {
        let index_size = self.index.size();
        if index_size == 0 || !minimum_similarity.is_finite() {
            return Ok((Vec::new(), Vec::new()));
        }

        let max_distance = 1.0_f32 - minimum_similarity;
        if !max_distance.is_finite() || max_distance < 0.0 {
            return Ok((Vec::new(), Vec::new()));
        }

        self.fast_search_vectors_within_distance(query, max_distance)
    }

    pub fn approx_filtered_search_vectors_within_distance(
        &self,
        query: &[f32],
        allowed_keys: &[u64],
        count: usize,
        max_distance: f32,
    ) -> Result<SearchMatch, String> {
        let index_size = self.index.size();
        if index_size == 0 || count == 0 || allowed_keys.is_empty() {
            return Ok((Vec::new(), Vec::new()));
        }
        if !max_distance.is_finite() || max_distance < 0.0 {
            return Ok((Vec::new(), Vec::new()));
        }

        let allowed = allowed_keys.iter().copied().collect::<HashSet<u64>>();
        let search_count = count.min(allowed.len()).min(index_size);
        if search_count == 0 {
            return Ok((Vec::new(), Vec::new()));
        }

        let matches = self
            .index
            .filtered_search(query, search_count, |key| allowed.contains(&key))
            .map_err(|e| format!("Failed to run filtered vector search: {e}"))?;

        Ok(Self::truncate_sorted_matches_within_distance(
            matches.keys,
            matches.distances,
            max_distance,
        ))
    }

    pub fn bulk_approx_filtered_search_vectors_within_distance(
        &self,
        queries: &Vec<Vec<f32>>,
        allowed_keys: &[u64],
        count: usize,
        max_distance: f32,
    ) -> Result<BulkSearchMatch, String> {
        let query_count = queries.len();
        if query_count == 0 {
            return Ok((Vec::new(), Vec::new()));
        }

        let empty_aligned_results = || {
            (
                vec![Vec::<u64>::new(); query_count],
                vec![Vec::<f32>::new(); query_count],
            )
        };

        let index_size = self.index.size();
        if index_size == 0 || count == 0 || allowed_keys.is_empty() {
            return Ok(empty_aligned_results());
        }
        if !max_distance.is_finite() || max_distance < 0.0 {
            return Ok(empty_aligned_results());
        }

        let allowed = allowed_keys.iter().copied().collect::<HashSet<u64>>();
        let search_count = count.min(allowed.len()).min(index_size);
        if search_count == 0 {
            return Ok(empty_aligned_results());
        }

        let mut all_keys = Vec::with_capacity(query_count);
        let mut all_distances = Vec::with_capacity(query_count);

        for query in queries {
            let matches = self
                .index
                .filtered_search(query, search_count, |key| allowed.contains(&key))
                .map_err(|e| format!("Failed to run filtered vector search: {e}"))?;

            let (keys, distances) = Self::truncate_sorted_matches_within_distance(
                matches.keys,
                matches.distances,
                max_distance,
            );
            all_keys.push(keys);
            all_distances.push(distances);
        }

        Ok((all_keys, all_distances))
    }

    fn fast_search_vectors_within_distance(
        &self,
        query: &[f32],
        max_distance: f32,
    ) -> Result<SearchMatch, String> {
        let index_size = self.index.size();
        if index_size == 0 {
            return Ok((Vec::new(), Vec::new()));
        }

        let mut previous_count = 0_usize;
        for step_count in FAST_SEARCH_STEP_COUNTS {
            let count = step_count.min(index_size);
            if count <= previous_count {
                continue;
            }
            previous_count = count;

            let matches = self
                .index
                .search(query, count)
                .map_err(|e| format!("Failed to search vectors: {e}"))?;

            let should_expand = count < index_size
                && matches
                    .distances
                    .last()
                    .map(|d| *d <= max_distance)
                    .unwrap_or(false);
            if should_expand {
                continue;
            }

            return Ok(Self::truncate_sorted_matches_within_distance(
                matches.keys,
                matches.distances,
                max_distance,
            ));
        }

        if previous_count < index_size {
            let matches = self
                .index
                .search(query, index_size)
                .map_err(|e| format!("Failed to search vectors: {e}"))?;
            return Ok(Self::truncate_sorted_matches_within_distance(
                matches.keys,
                matches.distances,
                max_distance,
            ));
        }

        Ok((Vec::new(), Vec::new()))
    }

    fn truncate_sorted_matches_within_distance(
        mut keys: Vec<u64>,
        mut distances: Vec<f32>,
        max_distance: f32,
    ) -> SearchMatch {
        let aligned_len = keys.len().min(distances.len());
        keys.truncate(aligned_len);
        distances.truncate(aligned_len);

        let keep_len = distances.partition_point(|distance| *distance <= max_distance);
        keys.truncate(keep_len);
        distances.truncate(keep_len);
        (keys, distances)
    }

    pub fn bulk_search_vectors(
        &self,
        queries: &Vec<Vec<f32>>,
        count: usize,
        exact: bool,
    ) -> Result<BulkSearchMatch, String> {
        let mut keys = Vec::new();
        let mut distances = Vec::new();

        for query in queries {
            let (keys_result, distances_result) = self.search_vectors(query, count, exact)?;
            keys.push(keys_result);
            distances.push(distances_result);
        }
        Ok((keys, distances))
    }

    pub fn bulk_search_keys(
        &self,
        potential_keys: &Vec<u64>,
        count: usize,
        exact: bool,
    ) -> Result<BulkSearchByKeyMatch, String> {
        let dimensions = self.index.dimensions();
        let mut embedding_data = vec![0.0f32; potential_keys.len() * dimensions];
        let mut contained_keys = Vec::with_capacity(potential_keys.len());
        let mut actual_query_count = 0;

        // Fill embeddings directly into flat storage using slices
        for key in potential_keys {
            if self.index.contains(*key) {
                let start_idx = actual_query_count * dimensions;
                let end_idx = start_idx + dimensions;
                let embedding_slice = &mut embedding_data[start_idx..end_idx];

                self.index
                    .get(*key, embedding_slice)
                    .map_err(|e| format!("Failed to get vector for key {key}: {e}"))?;
                contained_keys.push(*key);
                actual_query_count += 1;
            }
        }
        embedding_data.truncate(actual_query_count * dimensions);

        let max_result_size = std::cmp::min(self.index.size(), count);
        let mut closeby_keys = vec![Vec::with_capacity(max_result_size); actual_query_count];
        let mut distances = vec![Vec::with_capacity(max_result_size); actual_query_count];

        // Search using slices and fill pre-allocated containers
        for i in 0..actual_query_count {
            let start_idx = i * dimensions;
            let end_idx = start_idx + dimensions;
            let query_slice = &embedding_data[start_idx..end_idx];
            let (keys_result, distances_result) = self.search_vectors(query_slice, count, exact)?;
            closeby_keys[i] = keys_result;
            distances[i] = distances_result;
        }

        Ok((contained_keys, closeby_keys, distances))
    }

    /// Check if a vector with the given key exists in the index.
    /// `true` if the index contains the vector with the given key, `false` otherwise.
    pub fn contains_vector(&self, key: u64) -> bool {
        self.index.contains(key)
    }

    pub fn get_vector(&self, key: u64) -> Result<Vec<f32>, String> {
        let mut vector: Vec<f32> = vec![0.0; self.index.dimensions()];
        self.index
            .get(key, &mut vector)
            .map_err(|e| format!("Failed to get vector for key {key}: {e}"))?;
        Ok(vector)
    }

    pub fn bulk_get_vectors(&self, keys: Vec<u64>) -> Result<Vec<Vec<f32>>, String> {
        let mut vectors = Vec::new();
        for key in keys {
            let vector = self.get_vector(key)?;
            vectors.push(vector);
        }
        Ok(vectors)
    }

    pub fn remove_vector(&mut self, key: u64) -> Result<usize, String> {
        let removed_count = self
            .index
            .remove(key)
            .map_err(|e| format!("Failed to remove vector for key {key}: {e}"))?;
        self.save_index()?;
        Ok(removed_count)
    }

    pub fn bulk_remove_vectors(&mut self, keys: Vec<u64>) -> Result<usize, String> {
        let mut removed_count = 0;
        for key in keys {
            removed_count += self
                .index
                .remove(key)
                .map_err(|e| format!("Failed to bulk remove vector for key {key}: {e}"))?;
        }
        self.save_index()?;
        Ok(removed_count)
    }

    pub fn reset_index(&mut self) -> Result<(), String> {
        self.index
            .reset()
            .map_err(|e| format!("Failed to reset index: {e}"))?;
        self.index
            .reserve(1000)
            .map_err(|e| format!("Failed to reserve space in index after reset: {e}"))?;
        self.save_index()
    }

    pub fn delete_index(self) -> Result<(), String> {
        if self.path.exists() {
            std::fs::remove_file(&self.path)
                .map_err(|e| format!("Failed to delete index file {}: {e}", self.path.display()))?;
        } else {
            println!("Index file does not exist.");
        }
        Ok(())
    }

    pub fn get_index_stats(&self) -> (usize, usize, usize, usize, usize, usize, usize) {
        let size = self.index.size();
        let capacity = self.index.capacity();
        let dimensions = self.index.dimensions();

        let file_size = self.index.serialized_length();
        let memory_usage = self.index.memory_usage();

        let expansion_add = self.index.expansion_add();
        let expansion_search = self.index.expansion_search();

        (
            size,
            capacity,
            dimensions,
            file_size,
            memory_usage,
            expansion_add,
            expansion_search,
        )
    }
}
