use ente_ml::vector_db;
use flutter_rust_bridge::frb;

type SearchMatch = (Vec<u64>, Vec<f32>);
type BulkSearchMatch = (Vec<Vec<u64>>, Vec<Vec<f32>>);
type BulkSearchByKeyMatch = (Vec<u64>, Vec<Vec<u64>>, Vec<Vec<f32>>);

#[frb(opaque)]
pub struct VectorDB {
    inner: vector_db::VectorDB,
}

impl VectorDB {
    #[frb(sync)]
    pub fn new(file_path: &str, dimensions: usize) -> Result<Self, String> {
        Ok(Self {
            inner: vector_db::VectorDB::new(file_path, dimensions)?,
        })
    }

    pub fn add_vector(&mut self, key: u64, vector: &[f32]) -> Result<(), String> {
        self.inner.add_vector(key, vector)
    }

    pub fn bulk_add_vectors(&mut self, keys: Vec<u64>, vectors: &[Vec<f32>]) -> Result<(), String> {
        self.inner.bulk_add_vectors(keys, vectors)
    }

    pub fn search_vectors(
        &self,
        query: &[f32],
        count: usize,
        exact: bool,
    ) -> Result<SearchMatch, String> {
        self.inner.search_vectors(query, count, exact)
    }

    pub fn approx_search_vectors_within_similarity(
        &self,
        query: &[f32],
        minimum_similarity: f32,
    ) -> Result<SearchMatch, String> {
        self.inner
            .approx_search_vectors_within_similarity(query, minimum_similarity)
    }

    pub fn approx_filtered_search_vectors_within_distance(
        &self,
        query: &[f32],
        allowed_keys: &[u64],
        count: usize,
        max_distance: f32,
    ) -> Result<SearchMatch, String> {
        self.inner.approx_filtered_search_vectors_within_distance(
            query,
            allowed_keys,
            count,
            max_distance,
        )
    }

    pub fn bulk_approx_filtered_search_vectors_within_distance(
        &self,
        queries: &Vec<Vec<f32>>,
        allowed_keys: &[u64],
        count: usize,
        max_distance: f32,
    ) -> Result<BulkSearchMatch, String> {
        self.inner
            .bulk_approx_filtered_search_vectors_within_distance(
                queries,
                allowed_keys,
                count,
                max_distance,
            )
    }

    pub fn bulk_search_vectors(
        &self,
        queries: &Vec<Vec<f32>>,
        count: usize,
        exact: bool,
    ) -> Result<BulkSearchMatch, String> {
        self.inner.bulk_search_vectors(queries, count, exact)
    }

    pub fn bulk_search_keys(
        &self,
        potential_keys: &Vec<u64>,
        count: usize,
        exact: bool,
    ) -> Result<BulkSearchByKeyMatch, String> {
        self.inner.bulk_search_keys(potential_keys, count, exact)
    }

    pub fn contains_vector(&self, key: u64) -> bool {
        self.inner.contains_vector(key)
    }

    pub fn get_vector(&self, key: u64) -> Result<Vec<f32>, String> {
        self.inner.get_vector(key)
    }

    pub fn bulk_get_vectors(&self, keys: Vec<u64>) -> Result<Vec<Vec<f32>>, String> {
        self.inner.bulk_get_vectors(keys)
    }

    pub fn remove_vector(&mut self, key: u64) -> Result<usize, String> {
        self.inner.remove_vector(key)
    }

    pub fn bulk_remove_vectors(&mut self, keys: Vec<u64>) -> Result<usize, String> {
        self.inner.bulk_remove_vectors(keys)
    }

    pub fn reset_index(&mut self) -> Result<(), String> {
        self.inner.reset_index()
    }

    pub fn delete_index(self) -> Result<(), String> {
        self.inner.delete_index()
    }

    pub fn get_index_stats(&self) -> (usize, usize, usize, usize, usize, usize, usize) {
        self.inner.get_index_stats()
    }
}
