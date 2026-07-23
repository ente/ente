use ente_photos::ml::vector_db;
use flutter_rust_bridge::frb;

type SearchMatch = (Vec<u64>, Vec<f32>);
type BulkSearchMatch = (Vec<Vec<u64>>, Vec<Vec<f32>>);
type BulkSearchByKeyMatch = (Vec<u64>, Vec<Vec<u64>>, Vec<Vec<f32>>);

// USearch already vendors and links SimSIMD. Call that single exported symbol
// directly to avoid pulling a second copy of SimSIMD into the final app binary.
unsafe extern "C" {
    fn simsimd_dot_f32(a: *const f32, b: *const f32, n: u64, d: *mut f64);
}

fn simsimd_dot_product(a: &[f32], b: &[f32]) -> f64 {
    debug_assert_eq!(a.len(), b.len());
    let mut score = 0.0_f64;
    // SAFETY:
    // - `a` and `b` are valid, non-null slices for `a.len()` elements.
    // - SimSIMD only reads from the input buffers and writes one f64 to `score`.
    unsafe {
        simsimd_dot_f32(a.as_ptr(), b.as_ptr(), a.len() as u64, &mut score);
    }
    score
}

fn validate_semantic_search_exact_image_embeddings(
    image_file_ids: &[i64],
    image_embeddings: &[Vec<f32>],
) -> Result<Option<usize>, String> {
    if image_file_ids.len() != image_embeddings.len() {
        return Err(format!(
            "image_file_ids length {} does not match image_embeddings length {}",
            image_file_ids.len(),
            image_embeddings.len()
        ));
    }

    let Some(first_image_embedding) = image_embeddings.first() else {
        return Ok(None);
    };
    let expected_dimension = first_image_embedding.len();

    for (file_id, image_embedding) in image_file_ids.iter().zip(image_embeddings.iter()) {
        if image_embedding.len() != expected_dimension {
            return Err(format!(
                "image embedding dimension mismatch for file_id {file_id}: image={} expected={expected_dimension}",
                image_embedding.len(),
            ));
        }
    }

    Ok(Some(expected_dimension))
}

fn validate_semantic_search_exact_queries(
    query_embeddings: &[Vec<f32>],
    minimum_similarities: &[f32],
    expected_dimension: Option<usize>,
) -> Result<(), String> {
    if query_embeddings.len() != minimum_similarities.len() {
        return Err(format!(
            "query_embeddings length {} does not match minimum_similarities length {}",
            query_embeddings.len(),
            minimum_similarities.len()
        ));
    }

    let Some(expected_dimension) = expected_dimension else {
        return Ok(());
    };

    for (query_index, query_embedding) in query_embeddings.iter().enumerate() {
        if query_embedding.len() != expected_dimension {
            return Err(format!(
                "query embedding dimension mismatch at index {query_index}: query={} expected={expected_dimension}",
                query_embedding.len(),
            ));
        }
    }

    Ok(())
}

fn flatten_semantic_search_exact_image_embeddings(
    image_embeddings: &[Vec<f32>],
    expected_dimension: Option<usize>,
) -> Vec<f32> {
    let Some(expected_dimension) = expected_dimension else {
        return Vec::new();
    };

    let mut flattened_image_embeddings =
        Vec::with_capacity(image_embeddings.len() * expected_dimension);
    for image_embedding in image_embeddings {
        flattened_image_embeddings.extend_from_slice(image_embedding);
    }
    flattened_image_embeddings
}

fn semantic_search_exact_impl(
    image_file_ids: &[i64],
    image_embeddings: &[Vec<f32>],
    query_embeddings: &[Vec<f32>],
    minimum_similarities: &[f32],
) -> Result<SemanticSearchExactResponse, String> {
    let expected_dimension =
        validate_semantic_search_exact_image_embeddings(image_file_ids, image_embeddings)?;
    validate_semantic_search_exact_queries(
        query_embeddings,
        minimum_similarities,
        expected_dimension,
    )?;

    let matches_per_query = query_embeddings
        .iter()
        .zip(minimum_similarities.iter())
        .map(|(query_embedding, minimum_similarity)| {
            let minimum_similarity = f64::from(*minimum_similarity);
            let mut query_matches = Vec::with_capacity(image_embeddings.len());

            for (file_id, image_embedding) in image_file_ids.iter().zip(image_embeddings.iter()) {
                let score = simsimd_dot_product(image_embedding, query_embedding);

                if score >= minimum_similarity {
                    query_matches.push(SemanticSearchExactMatch {
                        file_id: *file_id,
                        score,
                    });
                }
            }

            query_matches.sort_by(|left, right| right.score.total_cmp(&left.score));
            query_matches
        })
        .collect();

    Ok(SemanticSearchExactResponse { matches_per_query })
}

fn semantic_search_exact_flattened_impl(
    image_file_ids: &[i64],
    flattened_image_embeddings: &[f32],
    image_embedding_dimension: Option<usize>,
    query_embeddings: &[Vec<f32>],
    minimum_similarities: &[f32],
) -> Result<SemanticSearchExactResponse, String> {
    validate_semantic_search_exact_queries(
        query_embeddings,
        minimum_similarities,
        image_embedding_dimension,
    )?;

    let matches_per_query = query_embeddings
        .iter()
        .zip(minimum_similarities.iter())
        .map(|(query_embedding, minimum_similarity)| {
            let minimum_similarity = f64::from(*minimum_similarity);
            let mut query_matches = Vec::with_capacity(image_file_ids.len());

            if let Some(image_embedding_dimension) = image_embedding_dimension {
                for (index, file_id) in image_file_ids.iter().enumerate() {
                    let offset = index * image_embedding_dimension;
                    let image_embedding =
                        &flattened_image_embeddings[offset..offset + image_embedding_dimension];
                    let score = simsimd_dot_product(image_embedding, query_embedding);

                    if score >= minimum_similarity {
                        query_matches.push(SemanticSearchExactMatch {
                            file_id: *file_id,
                            score,
                        });
                    }
                }
            }

            query_matches.sort_by(|left, right| right.score.total_cmp(&left.score));
            query_matches
        })
        .collect();

    Ok(SemanticSearchExactResponse { matches_per_query })
}

#[derive(Clone, Debug)]
pub struct SemanticSearchExactRequest {
    pub image_file_ids: Vec<i64>,
    pub image_embeddings: Vec<Vec<f32>>,
    pub query_embeddings: Vec<Vec<f32>>,
    pub minimum_similarities: Vec<f32>,
}

#[derive(Clone, Debug)]
pub struct SemanticSearchExactMatch {
    pub file_id: i64,
    pub score: f64,
}

#[derive(Clone, Debug)]
pub struct SemanticSearchExactResponse {
    pub matches_per_query: Vec<Vec<SemanticSearchExactMatch>>,
}

#[frb(opaque)]
pub struct SemanticSearchExactCache {
    image_file_ids: Vec<i64>,
    image_embedding_dimension: Option<usize>,
    flattened_image_embeddings: Vec<f32>,
}

impl SemanticSearchExactCache {
    #[frb(sync)]
    pub fn new(image_file_ids: Vec<i64>, image_embeddings: Vec<Vec<f32>>) -> Result<Self, String> {
        let image_embedding_dimension =
            validate_semantic_search_exact_image_embeddings(&image_file_ids, &image_embeddings)?;
        let flattened_image_embeddings = flatten_semantic_search_exact_image_embeddings(
            &image_embeddings,
            image_embedding_dimension,
        );

        Ok(Self {
            image_file_ids,
            image_embedding_dimension,
            flattened_image_embeddings,
        })
    }

    pub fn search(
        &self,
        query_embeddings: Vec<Vec<f32>>,
        minimum_similarities: Vec<f32>,
    ) -> Result<SemanticSearchExactResponse, String> {
        semantic_search_exact_flattened_impl(
            &self.image_file_ids,
            &self.flattened_image_embeddings,
            self.image_embedding_dimension,
            &query_embeddings,
            &minimum_similarities,
        )
    }
}

pub fn semantic_search_exact(
    req: SemanticSearchExactRequest,
) -> Result<SemanticSearchExactResponse, String> {
    let SemanticSearchExactRequest {
        image_file_ids,
        image_embeddings,
        query_embeddings,
        minimum_similarities,
    } = req;

    semantic_search_exact_impl(
        &image_file_ids,
        &image_embeddings,
        &query_embeddings,
        &minimum_similarities,
    )
}

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

    /// Check if a vector with the given key exists in the index.
    /// `true` if the index contains the vector with the given key, `false` otherwise.
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

#[cfg(test)]
mod tests {
    use super::{SemanticSearchExactCache, SemanticSearchExactRequest, semantic_search_exact};

    #[test]
    fn semantic_search_exact_filters_and_sorts_matches() {
        let response = semantic_search_exact(SemanticSearchExactRequest {
            image_file_ids: vec![101, 102, 103],
            image_embeddings: vec![
                vec![1.0, 0.0, 0.0],
                vec![0.8, 0.6, 0.0],
                vec![0.0, 1.0, 0.0],
            ],
            query_embeddings: vec![vec![1.0, 0.0, 0.0]],
            minimum_similarities: vec![0.7],
        })
        .expect("semantic search exact should succeed");

        let matches = &response.matches_per_query[0];
        assert_eq!(matches.len(), 2);
        assert_eq!(matches[0].file_id, 101);
        assert_eq!(matches[1].file_id, 102);
        assert!(matches[0].score > matches[1].score);
    }

    #[test]
    fn semantic_search_exact_supports_multiple_queries() {
        let response = semantic_search_exact(SemanticSearchExactRequest {
            image_file_ids: vec![201, 202, 203],
            image_embeddings: vec![vec![1.0, 0.0], vec![0.0, 1.0], vec![0.70710677, 0.70710677]],
            query_embeddings: vec![vec![1.0, 0.0], vec![0.0, 1.0]],
            minimum_similarities: vec![0.5, 0.5],
        })
        .expect("semantic search exact should succeed");

        assert_eq!(
            response.matches_per_query[0]
                .iter()
                .map(|entry| entry.file_id)
                .collect::<Vec<_>>(),
            vec![201, 203]
        );
        assert_eq!(
            response.matches_per_query[1]
                .iter()
                .map(|entry| entry.file_id)
                .collect::<Vec<_>>(),
            vec![202, 203]
        );
    }

    #[test]
    fn semantic_search_exact_cache_supports_searching_multiple_queries() {
        let cache = SemanticSearchExactCache::new(
            vec![401, 402, 403],
            vec![vec![1.0, 0.0], vec![0.0, 1.0], vec![0.70710677, 0.70710677]],
        )
        .expect("semantic search exact cache should succeed");

        let response = cache
            .search(vec![vec![1.0, 0.0], vec![0.0, 1.0]], vec![0.5, 0.5])
            .expect("semantic search exact cache search should succeed");

        assert_eq!(
            response.matches_per_query[0]
                .iter()
                .map(|entry| entry.file_id)
                .collect::<Vec<_>>(),
            vec![401, 403]
        );
        assert_eq!(
            response.matches_per_query[1]
                .iter()
                .map(|entry| entry.file_id)
                .collect::<Vec<_>>(),
            vec![402, 403]
        );
    }

    #[test]
    fn semantic_search_exact_cache_rejects_query_dimension_mismatch() {
        let cache = SemanticSearchExactCache::new(vec![501], vec![vec![1.0, 0.0]])
            .expect("semantic search exact cache should succeed");

        let err = cache
            .search(vec![vec![1.0, 0.0, 0.0]], vec![0.1])
            .expect_err("semantic search exact cache should fail on query dimension mismatch");

        assert!(err.contains("query embedding dimension mismatch"));
    }

    #[test]
    fn semantic_search_exact_rejects_dimension_mismatch() {
        let err = semantic_search_exact(SemanticSearchExactRequest {
            image_file_ids: vec![301],
            image_embeddings: vec![vec![1.0, 0.0]],
            query_embeddings: vec![vec![1.0, 0.0, 0.0]],
            minimum_similarities: vec![0.1],
        })
        .expect_err("semantic search exact should fail on dimension mismatch");

        assert!(err.contains("embedding dimension mismatch"));
    }
}
