use std::path::Path;

use ente_ml::vecdb;
use flutter_rust_bridge::frb;

#[derive(Clone, Debug)]
pub enum RustVecDbError {
    Io { message: String },
    Corrupt { message: String },
    Locked { message: String },
    ReadOnly { message: String },
    Closed { message: String },
    InvalidKey { message: String },
    InvalidVector { message: String },
    InvalidAttributes { message: String },
    DimensionMismatch { message: String },
    InvalidDimensions { message: String },
    UnboundedSearch { message: String },
    LengthMismatch { message: String },
    StorageMismatch { message: String },
    MetricMismatch { message: String },
}

impl From<vecdb::VecDbError> for RustVecDbError {
    fn from(value: vecdb::VecDbError) -> Self {
        let message = value.to_string();
        match value {
            vecdb::VecDbError::Io { .. } => Self::Io { message },
            vecdb::VecDbError::Corrupt(_) => Self::Corrupt { message },
            vecdb::VecDbError::Locked(_) => Self::Locked { message },
            vecdb::VecDbError::ReadOnly => Self::ReadOnly { message },
            vecdb::VecDbError::Closed => Self::Closed { message },
            vecdb::VecDbError::InvalidKey(_) => Self::InvalidKey { message },
            vecdb::VecDbError::InvalidVector(_) => Self::InvalidVector { message },
            vecdb::VecDbError::InvalidAttributes(_) => Self::InvalidAttributes { message },
            vecdb::VecDbError::DimensionMismatch { .. } => Self::DimensionMismatch { message },
            vecdb::VecDbError::InvalidDimensions { .. } => Self::InvalidDimensions { message },
            vecdb::VecDbError::UnboundedSearch => Self::UnboundedSearch { message },
            vecdb::VecDbError::LengthMismatch { .. } => Self::LengthMismatch { message },
            vecdb::VecDbError::StorageMismatch { .. } => Self::StorageMismatch { message },
            vecdb::VecDbError::MetricMismatch { .. } => Self::MetricMismatch { message },
        }
    }
}

#[derive(Clone, Copy, Debug)]
pub enum VecDbStorage {
    F32,
    I8,
}

fn to_engine_storage(storage: VecDbStorage) -> vecdb::StorageKind {
    match storage {
        VecDbStorage::F32 => vecdb::StorageKind::F32,
        VecDbStorage::I8 => vecdb::StorageKind::I8,
    }
}

fn to_api_storage(storage: vecdb::StorageKind) -> VecDbStorage {
    match storage {
        vecdb::StorageKind::F32 => VecDbStorage::F32,
        vecdb::StorageKind::I8 => VecDbStorage::I8,
    }
}

#[derive(Clone, Copy, Debug)]
pub enum VecDbMetric {
    InnerProduct,
    Cosine,
}

fn to_engine_metric(metric: VecDbMetric) -> vecdb::DistanceMetric {
    match metric {
        VecDbMetric::InnerProduct => vecdb::DistanceMetric::InnerProduct,
        VecDbMetric::Cosine => vecdb::DistanceMetric::Cosine,
    }
}

fn to_api_metric(metric: vecdb::DistanceMetric) -> VecDbMetric {
    match metric {
        vecdb::DistanceMetric::InnerProduct => VecDbMetric::InnerProduct,
        vecdb::DistanceMetric::Cosine => VecDbMetric::Cosine,
    }
}

#[derive(Clone, Debug)]
pub enum VecDbAttrValue {
    Str(String),
    Bool(bool),
    I64(i64),
    F64(f64),
}

#[derive(Clone, Debug)]
pub struct VecDbAttr {
    pub name: String,
    pub value: VecDbAttrValue,
}

fn to_engine_attr(attr: VecDbAttr) -> vecdb::Attribute {
    vecdb::Attribute {
        name: attr.name,
        value: match attr.value {
            VecDbAttrValue::Str(value) => vecdb::AttrValue::Str(value),
            VecDbAttrValue::Bool(value) => vecdb::AttrValue::Bool(value),
            VecDbAttrValue::I64(value) => vecdb::AttrValue::I64(value),
            VecDbAttrValue::F64(value) => vecdb::AttrValue::F64(value),
        },
    }
}

fn to_engine_attrs(attrs: Vec<VecDbAttr>) -> Vec<vecdb::Attribute> {
    attrs.into_iter().map(to_engine_attr).collect()
}

fn to_api_attrs(attrs: Vec<vecdb::Attribute>) -> Vec<VecDbAttr> {
    attrs
        .into_iter()
        .map(|attr| VecDbAttr {
            name: attr.name,
            value: match attr.value {
                vecdb::AttrValue::Str(value) => VecDbAttrValue::Str(value),
                vecdb::AttrValue::Bool(value) => VecDbAttrValue::Bool(value),
                vecdb::AttrValue::I64(value) => VecDbAttrValue::I64(value),
                vecdb::AttrValue::F64(value) => VecDbAttrValue::F64(value),
            },
        })
        .collect()
}

#[derive(Clone, Debug)]
pub struct VecDbMatch {
    pub key: String,
    pub distance: f32,
}

#[derive(Clone, Debug)]
pub struct VecDbKeyMatches {
    pub key: String,
    pub matches: Vec<VecDbMatch>,
}

#[derive(Clone, Debug)]
pub struct VecDbStats {
    pub live_count: u32,
    pub dead_count: u32,
    pub dims: u32,
    pub storage: VecDbStorage,
    pub metric: VecDbMetric,
    pub log_bytes: u64,
    pub records_since_snapshot: u32,
    pub approximate_memory_bytes: u64,
}

fn to_api_match(entry: vecdb::Match) -> VecDbMatch {
    VecDbMatch {
        key: entry.key,
        distance: entry.distance,
    }
}

fn to_api_matches(matches: Vec<vecdb::Match>) -> Vec<VecDbMatch> {
    matches.into_iter().map(to_api_match).collect()
}

pub fn delete_vec_db_files(file_path: String) -> Result<(), RustVecDbError> {
    Ok(vecdb::VecDb::purge(Path::new(&file_path))?)
}

#[derive(Clone, Copy, Debug)]
pub enum VecDbOpenCost {
    Ready,
    NeedsRebuild,
    Absent,
}

pub fn check_open_cost(file_path: String) -> VecDbOpenCost {
    match vecdb::VecDb::open_cost(Path::new(&file_path)) {
        vecdb::OpenCost::Ready => VecDbOpenCost::Ready,
        vecdb::OpenCost::NeedsRebuild => VecDbOpenCost::NeedsRebuild,
        vecdb::OpenCost::Absent => VecDbOpenCost::Absent,
    }
}

#[frb(opaque)]
pub struct VecDb {
    inner: vecdb::VecDb,
}

impl VecDb {
    pub fn new(
        file_path: String,
        dimensions: u32,
        storage: Option<VecDbStorage>,
        metric: VecDbMetric,
    ) -> Result<Self, RustVecDbError> {
        let path = Path::new(&file_path);
        let dims = dimensions as usize;
        let inner = vecdb::VecDb::open(
            path,
            dims,
            storage.map(to_engine_storage),
            to_engine_metric(metric),
        )?;
        Ok(Self { inner })
    }

    pub fn open_read_only(
        file_path: String,
        dimensions: u32,
        storage: Option<VecDbStorage>,
        metric: VecDbMetric,
    ) -> Result<Self, RustVecDbError> {
        Ok(Self {
            inner: vecdb::VecDb::open_read_only(
                Path::new(&file_path),
                dimensions as usize,
                storage.map(to_engine_storage),
                to_engine_metric(metric),
            )?,
        })
    }

    pub fn search(
        &self,
        query: Vec<f32>,
        limit: Option<u32>,
        max_distance: Option<f32>,
        exact: bool,
        allowed_keys: Option<Vec<String>>,
    ) -> Result<Vec<VecDbMatch>, RustVecDbError> {
        let params = vecdb::SearchParams {
            limit: limit.map(|value| value as usize),
            max_distance,
            exact,
            allowed_keys,
        };
        Ok(to_api_matches(self.inner.search(&query, &params)?))
    }

    pub fn add_vector(&self, key: String, vector: Vec<f32>) -> Result<(), RustVecDbError> {
        Ok(self.inner.add(&key, &vector)?)
    }

    pub fn bulk_add_vectors(
        &self,
        keys: Vec<String>,
        vectors: Vec<Vec<f32>>,
    ) -> Result<(), RustVecDbError> {
        Ok(self.inner.bulk_add(&keys, &vectors)?)
    }

    pub fn add_vector_with_attrs(
        &self,
        key: String,
        vector: Vec<f32>,
        attrs: Vec<VecDbAttr>,
    ) -> Result<(), RustVecDbError> {
        Ok(self
            .inner
            .add_with_attrs(&key, &vector, &to_engine_attrs(attrs))?)
    }

    pub fn bulk_add_vectors_with_attrs(
        &self,
        keys: Vec<String>,
        vectors: Vec<Vec<f32>>,
        attrs: Vec<Option<Vec<VecDbAttr>>>,
    ) -> Result<(), RustVecDbError> {
        let attrs: Vec<Option<Vec<vecdb::Attribute>>> = attrs
            .into_iter()
            .map(|entry| entry.map(to_engine_attrs))
            .collect();
        Ok(self.inner.bulk_add_with_attrs(&keys, &vectors, &attrs)?)
    }

    pub fn get_attrs(&self, key: String) -> Option<Vec<VecDbAttr>> {
        self.inner.get_attrs(&key).map(to_api_attrs)
    }

    pub fn bulk_get_attrs(&self, keys: Vec<String>) -> Vec<Option<Vec<VecDbAttr>>> {
        self.inner
            .bulk_get_attrs(&keys)
            .into_iter()
            .map(|entry| entry.map(to_api_attrs))
            .collect()
    }

    pub fn approx_search_vectors_within_similarity(
        &self,
        query: Vec<f32>,
        minimum_similarity: f32,
    ) -> Result<Vec<VecDbMatch>, RustVecDbError> {
        self.search(query, None, Some(1.0 - minimum_similarity), false, None)
    }

    pub fn bulk_search_within_similarity(
        &self,
        queries: Vec<Vec<f32>>,
        minimum_similarities: Vec<f32>,
        limit: Option<u32>,
        exact: bool,
    ) -> Result<Vec<Vec<VecDbMatch>>, RustVecDbError> {
        if queries.len() != minimum_similarities.len() {
            return Err(RustVecDbError::LengthMismatch {
                message: format!(
                    "queries length {} does not match similarities length {}",
                    queries.len(),
                    minimum_similarities.len()
                ),
            });
        }
        let params: Vec<vecdb::SearchParams> = minimum_similarities
            .iter()
            .map(|similarity| vecdb::SearchParams {
                limit: limit.map(|value| value as usize),
                max_distance: Some(1.0 - similarity),
                exact,
                allowed_keys: None,
            })
            .collect();
        let results = self.inner.bulk_search_varied(&queries, &params)?;
        Ok(results.into_iter().map(to_api_matches).collect())
    }

    pub fn bulk_approx_filtered_search_vectors_within_distance(
        &self,
        queries: Vec<Vec<f32>>,
        allowed_keys: Vec<String>,
        count: u32,
        max_distance: f32,
    ) -> Result<Vec<Vec<VecDbMatch>>, RustVecDbError> {
        let params = vecdb::SearchParams {
            limit: Some(count as usize),
            max_distance: Some(max_distance),
            exact: false,
            allowed_keys: Some(allowed_keys),
        };
        let results = self.inner.bulk_search(&queries, &params)?;
        Ok(results.into_iter().map(to_api_matches).collect())
    }

    pub fn bulk_search_keys(
        &self,
        potential_keys: Vec<String>,
        count: u32,
        max_distance: Option<f32>,
        exact: bool,
        restrict_to_input: bool,
    ) -> Result<Vec<VecDbKeyMatches>, RustVecDbError> {
        let results = self.inner.bulk_search_stored(
            &potential_keys,
            count as usize,
            max_distance,
            exact,
            restrict_to_input,
        )?;
        Ok(results
            .into_iter()
            .map(|entry| VecDbKeyMatches {
                key: entry.key,
                matches: to_api_matches(entry.matches),
            })
            .collect())
    }

    pub fn bulk_get_vectors(&self, keys: Vec<String>) -> Vec<Option<Vec<f32>>> {
        keys.iter().map(|key| self.inner.get(key)).collect()
    }

    pub fn bulk_remove_vectors(&self, keys: Vec<String>) -> Result<u32, RustVecDbError> {
        Ok(self.inner.bulk_remove(&keys)? as u32)
    }

    pub fn flush(&self) -> Result<(), RustVecDbError> {
        Ok(self.inner.flush()?)
    }

    pub fn reset_index(&self) -> Result<(), RustVecDbError> {
        Ok(self.inner.reset()?)
    }

    pub fn delete_index(self) -> Result<(), RustVecDbError> {
        Ok(self.inner.delete()?)
    }

    pub fn get_index_stats(&self) -> Result<VecDbStats, RustVecDbError> {
        let stats = self.inner.stats()?;
        Ok(VecDbStats {
            live_count: stats.live_count as u32,
            dead_count: stats.dead_count as u32,
            dims: stats.dims as u32,
            storage: to_api_storage(stats.storage),
            metric: to_api_metric(stats.metric),
            log_bytes: stats.log_bytes,
            records_since_snapshot: stats.records_since_snapshot as u32,
            approximate_memory_bytes: stats.approximate_memory_bytes as u64,
        })
    }
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicU32, Ordering};

    use super::*;

    const DIMS: u32 = 8;

    static TEST_DIR_COUNTER: AtomicU32 = AtomicU32::new(0);

    struct TestDir(PathBuf);

    impl TestDir {
        fn create() -> Self {
            let sequence = TEST_DIR_COUNTER.fetch_add(1, Ordering::Relaxed);
            let path = std::env::temp_dir().join(format!(
                "ente-photos-frb-vecdb-{}-{sequence}",
                std::process::id()
            ));
            let _ = std::fs::remove_dir_all(&path);
            std::fs::create_dir_all(&path).unwrap();
            Self(path)
        }

        fn db_path(&self) -> String {
            self.0.join("db").to_str().unwrap().to_string()
        }
    }

    impl Drop for TestDir {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    fn basis(axis: usize) -> Vec<f32> {
        let mut vector = vec![0.0; DIMS as usize];
        vector[axis] = 1.0;
        vector
    }

    fn key(name: &str) -> String {
        name.to_string()
    }

    #[test]
    fn omitted_storage_defaults_to_i8_with_a_required_metric() {
        let dir = TestDir::create();
        let db = VecDb::new(dir.db_path(), 32, None, VecDbMetric::InnerProduct).unwrap();
        assert!(matches!(
            db.get_index_stats().unwrap().storage,
            VecDbStorage::I8
        ));
        assert!(matches!(
            db.get_index_stats().unwrap().metric,
            VecDbMetric::InnerProduct
        ));
        drop(db);
        let reader =
            VecDb::open_read_only(dir.db_path(), 32, None, VecDbMetric::InnerProduct).unwrap();
        assert!(matches!(
            reader.get_index_stats().unwrap().storage,
            VecDbStorage::I8
        ));
        drop(reader);
        let dir = TestDir::create();
        drop(
            VecDb::new(
                dir.db_path(),
                32,
                Some(VecDbStorage::F32),
                VecDbMetric::Cosine,
            )
            .unwrap(),
        );
        for open in [VecDb::new, VecDb::open_read_only] {
            assert!(matches!(
                open(dir.db_path(), 32, None, VecDbMetric::Cosine),
                Err(RustVecDbError::StorageMismatch { .. })
            ));
        }
    }

    #[test]
    fn read_only_verifies_explicit_configuration() {
        for (storage, metric, wrong_storage, wrong_metric) in [
            (
                VecDbStorage::F32,
                VecDbMetric::InnerProduct,
                VecDbStorage::I8,
                VecDbMetric::Cosine,
            ),
            (
                VecDbStorage::I8,
                VecDbMetric::Cosine,
                VecDbStorage::F32,
                VecDbMetric::InnerProduct,
            ),
        ] {
            let dir = TestDir::create();
            let db = VecDb::new(dir.db_path(), 32, Some(storage), metric).unwrap();
            db.add_vector(key("kept"), vec![1.0; 32]).unwrap();
            db.flush().unwrap();
            let verify = || {
                assert!(matches!(
                    VecDb::open_read_only(dir.db_path(), 32, Some(wrong_storage), metric),
                    Err(RustVecDbError::StorageMismatch { .. })
                ));
                assert!(matches!(
                    VecDb::open_read_only(dir.db_path(), 32, Some(storage), wrong_metric),
                    Err(RustVecDbError::MetricMismatch { .. })
                ));
                assert!(matches!(
                    VecDb::open_read_only(dir.db_path(), 64, Some(storage), metric),
                    Err(RustVecDbError::DimensionMismatch { .. })
                ));
                let reader =
                    VecDb::open_read_only(dir.db_path(), 32, Some(storage), metric).unwrap();
                assert_eq!(reader.get_index_stats().unwrap().live_count, 1);
                assert!(matches!(
                    reader.add_vector(key("no"), vec![1.0; 32]),
                    Err(RustVecDbError::ReadOnly { .. })
                ));
            };
            verify();
            drop(db);
            verify();
        }
    }

    #[test]
    fn explicitly_selected_metrics_are_immutable() {
        let dir = TestDir::create();
        let db = VecDb::new(
            dir.db_path(),
            32,
            Some(VecDbStorage::I8),
            VecDbMetric::Cosine,
        )
        .unwrap();
        assert!(matches!(
            db.get_index_stats().unwrap().metric,
            VecDbMetric::Cosine
        ));
        assert!(matches!(
            VecDb::new(
                dir.db_path(),
                32,
                Some(VecDbStorage::I8),
                VecDbMetric::InnerProduct
            ),
            Err(RustVecDbError::MetricMismatch { .. })
        ));
        drop(db);
        let dir = TestDir::create();
        let db = VecDb::new(
            dir.db_path(),
            DIMS,
            Some(VecDbStorage::F32),
            VecDbMetric::InnerProduct,
        )
        .unwrap();
        let vector: Vec<f32> = basis(0).iter().map(|value| value * 3.0).collect();
        db.add_vector(key("a"), vector.clone()).unwrap();
        assert_eq!(
            db.search(vector.clone(), Some(1), None, true, None)
                .unwrap()[0]
                .distance,
            -8.0
        );
        db.flush().unwrap();
        drop(db);
        assert!(matches!(
            VecDb::new(dir.db_path(), DIMS, Some(VecDbStorage::F32), VecDbMetric::Cosine),
            Err(RustVecDbError::MetricMismatch { message }) if message.contains("cosine") && message.contains("inner product")
        ));
        let db = VecDb::new(
            dir.db_path(),
            DIMS,
            Some(VecDbStorage::F32),
            VecDbMetric::InnerProduct,
        )
        .unwrap();
        assert!(matches!(
            db.get_index_stats().unwrap().metric,
            VecDbMetric::InnerProduct
        ));
        assert_eq!(
            db.search(vector, Some(1), None, false, None).unwrap()[0].distance,
            -8.0
        );
    }

    #[test]
    fn add_search_stats_round_trip() {
        let dir = TestDir::create();
        let db = VecDb::new(
            dir.db_path(),
            DIMS,
            Some(VecDbStorage::F32),
            VecDbMetric::Cosine,
        )
        .unwrap();
        db.add_vector(key("a"), basis(0)).unwrap();
        db.bulk_add_vectors(vec![key("b"), key("c")], vec![basis(1), basis(2)])
            .unwrap();
        assert_eq!(
            db.bulk_get_vectors(vec![key("c"), key("missing")]),
            vec![Some(basis(2)), None]
        );
        let matches = db.search(basis(0), Some(2), None, true, None).unwrap();
        assert_eq!(matches[0].key, "a");
        assert!(matches[0].distance.abs() < 1.0e-6);
        let within = db.search(basis(0), None, Some(0.5), true, None).unwrap();
        assert_eq!(within.len(), 1);
        assert_eq!(within[0].key, "a");
        let filtered = db
            .search(
                basis(0),
                Some(3),
                Some(2.0),
                false,
                Some(vec![key("b"), key("c")]),
            )
            .unwrap();
        assert!(filtered.iter().all(|found| found.key != "a"));
        assert_eq!(filtered.len(), 2);
        let stats = db.get_index_stats().unwrap();
        assert_eq!(stats.live_count, 3);
        assert_eq!(stats.dead_count, 0);
        assert_eq!(stats.dims, DIMS);
        assert!(stats.log_bytes > 32);
        assert!(stats.approximate_memory_bytes > 0);
        db.flush().unwrap();
        assert_eq!(db.get_index_stats().unwrap().records_since_snapshot, 0);
        let read_only = VecDb::open_read_only(
            dir.db_path(),
            DIMS,
            Some(VecDbStorage::F32),
            VecDbMetric::Cosine,
        )
        .unwrap();
        assert_eq!(read_only.get_index_stats().unwrap().live_count, 3);
        assert!(matches!(
            read_only.add_vector(key("x"), basis(3)),
            Err(RustVecDbError::ReadOnly { .. })
        ));
        assert_eq!(
            db.bulk_remove_vectors(vec![key("a"), key("b"), key("nope")])
                .unwrap(),
            2
        );
        assert_eq!(db.get_index_stats().unwrap().live_count, 1);
        db.reset_index().unwrap();
        assert_eq!(db.get_index_stats().unwrap().live_count, 0);
        db.add_vector(key("again"), basis(3)).unwrap();
        db.delete_index().unwrap();
        assert!(!PathBuf::from(dir.db_path()).exists());
    }

    #[test]
    fn bulk_add_rejects_length_mismatch() {
        let dir = TestDir::create();
        let db = VecDb::new(
            dir.db_path(),
            DIMS,
            Some(VecDbStorage::F32),
            VecDbMetric::Cosine,
        )
        .unwrap();
        let error = db
            .bulk_add_vectors(vec![key("a")], vec![basis(0), basis(1)])
            .unwrap_err();
        assert!(matches!(error, RustVecDbError::LengthMismatch { .. }));
        assert_eq!(db.get_index_stats().unwrap().live_count, 0);
    }

    #[test]
    fn similarity_threshold_conversion_edges() {
        let dir = TestDir::create();
        let db = VecDb::new(
            dir.db_path(),
            DIMS,
            Some(VecDbStorage::F32),
            VecDbMetric::Cosine,
        )
        .unwrap();
        db.add_vector(key("a"), basis(0)).unwrap();
        db.add_vector(key("b"), basis(1)).unwrap();
        let close = db
            .approx_search_vectors_within_similarity(basis(0), 0.5)
            .unwrap();
        assert_eq!(close.len(), 1);
        assert_eq!(close[0].key, "a");
        let all = db
            .approx_search_vectors_within_similarity(basis(0), -1.0)
            .unwrap();
        assert_eq!(all.len(), 2);
        for degenerate in [f32::NAN, f32::INFINITY, f32::NEG_INFINITY, 2.0] {
            assert!(
                db.approx_search_vectors_within_similarity(basis(0), degenerate)
                    .unwrap()
                    .is_empty()
            );
        }
    }

    #[test]
    fn bulk_search_within_similarity_honors_per_query_thresholds() {
        let dir = TestDir::create();
        let db = VecDb::new(
            dir.db_path(),
            DIMS,
            Some(VecDbStorage::F32),
            VecDbMetric::Cosine,
        )
        .unwrap();
        db.bulk_add_vectors(
            vec![key("a"), key("b"), key("c")],
            vec![basis(0), basis(1), basis(2)],
        )
        .unwrap();
        let queries = vec![basis(0), basis(0), basis(1)];
        let results = db
            .bulk_search_within_similarity(queries.clone(), vec![0.5, -1.0, 0.5], None, true)
            .unwrap();
        assert_eq!(results.len(), 3);
        assert_eq!(results[0].len(), 1);
        assert_eq!(results[0][0].key, "a");
        assert_eq!(results[1].len(), 3);
        assert_eq!(results[2].len(), 1);
        assert_eq!(results[2][0].key, "b");
        let limited = db
            .bulk_search_within_similarity(queries.clone(), vec![-1.0, -1.0, -1.0], Some(2), false)
            .unwrap();
        assert!(limited.iter().all(|matches| matches.len() == 2));
        let mixed = vec![0.5, -1.0, 0.9];
        for exact in [true, false] {
            let bulk = db
                .bulk_search_within_similarity(queries.clone(), mixed.clone(), Some(2), exact)
                .unwrap();
            for ((query, similarity), matches) in queries.iter().zip(&mixed).zip(&bulk) {
                let direct = db
                    .search(query.clone(), Some(2), Some(1.0 - similarity), exact, None)
                    .unwrap();
                assert_eq!(matches.len(), direct.len());
                for (found, expected) in matches.iter().zip(&direct) {
                    assert_eq!(found.key, expected.key);
                    assert_eq!(found.distance, expected.distance);
                }
            }
        }
        assert!(matches!(
            db.bulk_search_within_similarity(queries.clone(), vec![0.5], None, false),
            Err(RustVecDbError::LengthMismatch { .. })
        ));
        let degenerate = db
            .bulk_search_within_similarity(
                queries.clone(),
                vec![f32::NAN, 1.5, -1.0],
                Some(3),
                true,
            )
            .unwrap();
        assert!(degenerate[0].is_empty());
        assert!(degenerate[1].is_empty());
        assert_eq!(degenerate[2].len(), 3);
        let all_degenerate = db
            .bulk_search_within_similarity(
                queries,
                vec![f32::NAN, f32::INFINITY, 3.0],
                Some(3),
                false,
            )
            .unwrap();
        assert_eq!(all_degenerate.len(), 3);
        assert!(all_degenerate.iter().all(Vec::is_empty));
    }

    #[test]
    fn bulk_filtered_search_stays_query_aligned() {
        let dir = TestDir::create();
        let db = VecDb::new(
            dir.db_path(),
            DIMS,
            Some(VecDbStorage::F32),
            VecDbMetric::Cosine,
        )
        .unwrap();
        db.bulk_add_vectors(
            vec![key("a"), key("b"), key("c")],
            vec![basis(0), basis(1), basis(2)],
        )
        .unwrap();
        let queries = vec![basis(0), basis(1), basis(5)];
        let aligned = db
            .bulk_approx_filtered_search_vectors_within_distance(
                queries.clone(),
                vec![key("a"), key("b"), key("absent")],
                2,
                0.5,
            )
            .unwrap();
        assert_eq!(aligned.len(), 3);
        assert_eq!(aligned[0].len(), 1);
        assert_eq!(aligned[0][0].key, "a");
        assert_eq!(aligned[1].len(), 1);
        assert_eq!(aligned[1][0].key, "b");
        assert!(aligned[2].is_empty());
        let empty_allowed = db
            .bulk_approx_filtered_search_vectors_within_distance(
                queries.clone(),
                Vec::new(),
                2,
                0.5,
            )
            .unwrap();
        assert_eq!(empty_allowed.len(), 3);
        assert!(empty_allowed.iter().all(Vec::is_empty));
        for degenerate_distance in [f32::NAN, f32::INFINITY, -0.5] {
            let degenerate = db
                .bulk_approx_filtered_search_vectors_within_distance(
                    queries.clone(),
                    vec![key("a")],
                    2,
                    degenerate_distance,
                )
                .unwrap();
            assert_eq!(degenerate.len(), 3);
            assert!(degenerate.iter().all(Vec::is_empty));
        }
        let unfiltered = db.search(basis(0), Some(3), None, false, None).unwrap();
        assert_eq!(unfiltered.len(), 3);
        let filtered_empty = db
            .search(basis(0), Some(3), None, false, Some(Vec::new()))
            .unwrap();
        assert!(filtered_empty.is_empty());
    }

    #[test]
    fn bulk_search_keys_excludes_self_and_honors_the_filters() {
        let dir = TestDir::create();
        let db = VecDb::new(
            dir.db_path(),
            DIMS,
            Some(VecDbStorage::F32),
            VecDbMetric::Cosine,
        )
        .unwrap();
        db.bulk_add_vectors(
            vec![key("a"), key("b"), key("c")],
            vec![basis(0), basis(1), basis(2)],
        )
        .unwrap();
        let results = db
            .bulk_search_keys(
                vec![key("missing"), key("b"), key("a")],
                2,
                None,
                true,
                false,
            )
            .unwrap();
        assert_eq!(results.len(), 2);
        assert_eq!(results[0].key, "b");
        assert_eq!(results[0].matches.len(), 2);
        assert!(results[0].matches.iter().all(|found| found.key != "b"));
        assert_eq!(results[1].key, "a");
        assert!(results[1].matches.iter().all(|found| found.key != "a"));
        let restricted = db
            .bulk_search_keys(vec![key("a"), key("b")], 5, None, true, true)
            .unwrap();
        for entry in &restricted {
            assert_eq!(entry.matches.len(), 1);
        }
        assert_eq!(restricted[0].matches[0].key, "b");
        assert_eq!(restricted[1].matches[0].key, "a");
        let cut = db
            .bulk_search_keys(vec![key("a")], 2, Some(0.5), false, false)
            .unwrap();
        assert!(cut[0].matches.is_empty());
    }

    #[test]
    fn attrs_round_trip_through_the_api() {
        let dir = TestDir::create();
        let db = VecDb::new(
            dir.db_path(),
            DIMS,
            Some(VecDbStorage::F32),
            VecDbMetric::Cosine,
        )
        .unwrap();
        let attrs = vec![
            VecDbAttr {
                name: key("model"),
                value: VecDbAttrValue::Str("clip".to_string()),
            },
            VecDbAttr {
                name: key("version"),
                value: VecDbAttrValue::I64(3),
            },
            VecDbAttr {
                name: key("indexed"),
                value: VecDbAttrValue::Bool(true),
            },
            VecDbAttr {
                name: key("score"),
                value: VecDbAttrValue::F64(0.75),
            },
        ];
        db.add_vector_with_attrs(key("a"), basis(0), attrs).unwrap();
        let fetched = db.get_attrs(key("a")).unwrap();
        assert_eq!(fetched.len(), 4);
        assert!(matches!(
            &fetched[0],
            VecDbAttr { name, value: VecDbAttrValue::Str(value) }
                if name == "model" && value == "clip"
        ));
        assert!(matches!(
            &fetched[1],
            VecDbAttr { name, value: VecDbAttrValue::I64(3) } if name == "version"
        ));
        assert!(matches!(
            &fetched[2],
            VecDbAttr { name, value: VecDbAttrValue::Bool(true) } if name == "indexed"
        ));
        assert!(matches!(
            &fetched[3],
            VecDbAttr { name, value: VecDbAttrValue::F64(value) } if name == "score" && *value == 0.75
        ));
        db.bulk_add_vectors_with_attrs(
            vec![key("b"), key("c")],
            vec![basis(1), basis(2)],
            vec![
                Some(vec![VecDbAttr {
                    name: key("only"),
                    value: VecDbAttrValue::Bool(false),
                }]),
                None,
            ],
        )
        .unwrap();
        let bulk = db.bulk_get_attrs(vec![key("b"), key("c"), key("missing")]);
        assert_eq!(bulk.len(), 3);
        assert!(matches!(
            bulk[0].as_deref(),
            Some([VecDbAttr { name, value: VecDbAttrValue::Bool(false) }]) if name == "only"
        ));
        assert!(bulk[1].is_none());
        assert!(bulk[2].is_none());
        db.add_vector(key("a"), basis(0)).unwrap();
        assert!(db.get_attrs(key("a")).is_none());
        assert!(matches!(
            db.add_vector_with_attrs(
                key("a"),
                basis(0),
                vec![
                    VecDbAttr {
                        name: key("dup"),
                        value: VecDbAttrValue::Bool(true),
                    },
                    VecDbAttr {
                        name: key("dup"),
                        value: VecDbAttrValue::Bool(false),
                    },
                ],
            ),
            Err(RustVecDbError::InvalidAttributes { .. })
        ));
        assert!(matches!(
            db.bulk_add_vectors_with_attrs(vec![key("x")], vec![basis(3)], vec![None, None]),
            Err(RustVecDbError::LengthMismatch { .. })
        ));
        assert_eq!(db.get_index_stats().unwrap().live_count, 3);
    }

    #[test]
    fn check_open_cost_mirrors_the_engine_decision() {
        let dir = TestDir::create();
        assert!(matches!(
            check_open_cost(dir.db_path()),
            VecDbOpenCost::Absent
        ));
        let db = VecDb::new(
            dir.db_path(),
            DIMS,
            Some(VecDbStorage::F32),
            VecDbMetric::Cosine,
        )
        .unwrap();
        db.add_vector(key("a"), basis(0)).unwrap();
        assert!(matches!(
            check_open_cost(dir.db_path()),
            VecDbOpenCost::Ready
        ));
        db.flush().unwrap();
        drop(db);
        assert!(matches!(
            check_open_cost(dir.db_path()),
            VecDbOpenCost::Ready
        ));
        std::fs::remove_file(format!("{}.graph", dir.db_path())).unwrap();
        assert!(matches!(
            check_open_cost(dir.db_path()),
            VecDbOpenCost::NeedsRebuild
        ));
    }

    #[test]
    fn delete_vec_db_files_purges_with_and_without_live_instances() {
        let dir = TestDir::create();
        let db = VecDb::new(
            dir.db_path(),
            DIMS,
            Some(VecDbStorage::F32),
            VecDbMetric::Cosine,
        )
        .unwrap();
        db.add_vector(key("a"), basis(0)).unwrap();
        db.flush().unwrap();
        delete_vec_db_files(dir.db_path()).unwrap();
        assert!(!PathBuf::from(dir.db_path()).exists());
        assert!(!PathBuf::from(format!("{}.graph", dir.db_path())).exists());
        assert!(PathBuf::from(format!("{}.lock", dir.db_path())).exists());
        assert!(matches!(
            db.get_index_stats(),
            Err(RustVecDbError::Closed { .. })
        ));
        let reopened = VecDb::new(
            dir.db_path(),
            DIMS,
            Some(VecDbStorage::F32),
            VecDbMetric::Cosine,
        )
        .unwrap();
        assert_eq!(reopened.get_index_stats().unwrap().live_count, 0);
        reopened.add_vector(key("b"), basis(1)).unwrap();
        drop(reopened);
        delete_vec_db_files(dir.db_path()).unwrap();
        assert!(!PathBuf::from(dir.db_path()).exists());
        delete_vec_db_files(dir.db_path()).unwrap();
    }

    fn i8_vector(seed: u32) -> Vec<f32> {
        let raw: Vec<f32> = (0..32)
            .map(|index| ((index * 7 + seed * 13) % 23) as f32 - 11.0)
            .collect();
        let norm = raw.iter().map(|value| value * value).sum::<f32>().sqrt();
        raw.into_iter().map(|value| value / norm).collect()
    }

    #[test]
    fn storage_is_chosen_at_creation_reported_in_stats_and_verified_on_reopen() {
        let dir = TestDir::create();
        let db = VecDb::new(
            dir.db_path(),
            32,
            Some(VecDbStorage::I8),
            VecDbMetric::Cosine,
        )
        .unwrap();
        assert!(matches!(
            db.get_index_stats().unwrap().storage,
            VecDbStorage::I8
        ));
        let vector = i8_vector(1);
        db.add_vector(key("a"), vector.clone()).unwrap();
        db.bulk_add_vectors(vec![key("b"), key("c")], vec![i8_vector(2), i8_vector(3)])
            .unwrap();
        let max_abs = vector
            .iter()
            .fold(0.0f32, |acc, value| acc.max(value.abs()));
        let fetched = db.bulk_get_vectors(vec![key("a"), key("missing")]);
        assert!(fetched[1].is_none());
        for (restored, original) in fetched[0].as_ref().unwrap().iter().zip(&vector) {
            assert!((restored - original).abs() <= max_abs / 254.0 + 1.0e-6);
        }
        let found = db
            .search(vector.clone(), Some(1), None, true, None)
            .unwrap();
        assert_eq!(found[0].key, "a");
        assert!(found[0].distance.abs() < 0.02);
        let stats = db.get_index_stats().unwrap();
        assert_eq!(stats.live_count, 3);
        assert_eq!(stats.dims, 32);
        assert!(matches!(stats.storage, VecDbStorage::I8));
        assert!(matches!(
            VecDb::new(
                dir.db_path(),
                32,
                Some(VecDbStorage::F32),
                VecDbMetric::Cosine
            ),
            Err(RustVecDbError::StorageMismatch { .. })
        ));
        let joined = VecDb::new(
            dir.db_path(),
            32,
            Some(VecDbStorage::I8),
            VecDbMetric::Cosine,
        )
        .unwrap();
        assert!(matches!(
            joined.get_index_stats().unwrap().storage,
            VecDbStorage::I8
        ));
        drop(joined);
        db.flush().unwrap();
        drop(db);
        let read_only = VecDb::open_read_only(
            dir.db_path(),
            32,
            Some(VecDbStorage::I8),
            VecDbMetric::Cosine,
        )
        .unwrap();
        assert!(matches!(
            read_only.get_index_stats().unwrap().storage,
            VecDbStorage::I8
        ));
        assert_eq!(read_only.get_index_stats().unwrap().live_count, 3);
        drop(read_only);
        assert!(matches!(
            VecDb::new(dir.db_path(), 32, Some(VecDbStorage::F32), VecDbMetric::Cosine),
            Err(RustVecDbError::StorageMismatch { message }) if message.contains("f32") && message.contains("i8")
        ));
        let reopened = VecDb::new(
            dir.db_path(),
            32,
            Some(VecDbStorage::I8),
            VecDbMetric::Cosine,
        )
        .unwrap();
        assert!(matches!(
            reopened.get_index_stats().unwrap().storage,
            VecDbStorage::I8
        ));
        let again = reopened.search(vector, Some(1), None, false, None).unwrap();
        assert_eq!(again[0].key, "a");
    }

    #[test]
    fn explicit_i8_storage_rejects_dims_off_the_lane_grid() {
        let dir = TestDir::create();
        let db = VecDb::new(
            dir.db_path(),
            32,
            Some(VecDbStorage::I8),
            VecDbMetric::Cosine,
        )
        .unwrap();
        assert!(matches!(
            db.get_index_stats().unwrap().storage,
            VecDbStorage::I8
        ));
        let explicit = VecDb::new(
            dir.db_path(),
            32,
            Some(VecDbStorage::I8),
            VecDbMetric::Cosine,
        )
        .unwrap();
        assert!(matches!(
            explicit.get_index_stats().unwrap().storage,
            VecDbStorage::I8
        ));
        assert!(matches!(
            VecDb::new(
                dir.db_path(),
                32,
                Some(VecDbStorage::F32),
                VecDbMetric::Cosine
            ),
            Err(RustVecDbError::StorageMismatch { .. })
        ));
        let other = TestDir::create();
        assert!(matches!(
            VecDb::new(other.db_path(), DIMS, Some(VecDbStorage::I8), VecDbMetric::Cosine),
            Err(RustVecDbError::InvalidDimensions { message }) if message.contains("i8") && message.contains("32")
        ));
        assert!(!PathBuf::from(other.db_path()).exists());
        assert!(
            VecDb::new(
                other.db_path(),
                DIMS,
                Some(VecDbStorage::F32),
                VecDbMetric::Cosine
            )
            .is_ok()
        );
    }
}
