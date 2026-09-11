use std::path::{Path, PathBuf};

use thiserror::Error;

mod arena;
mod crc;
mod graph;
mod kernel;
mod lock;
mod log;
mod snapshot;
mod store;

pub use store::{OpenCost, Stats, VecDb};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DistanceMetric {
    InnerProduct,
    Cosine,
}

impl DistanceMetric {
    pub(crate) fn header_tag(self) -> u8 {
        match self {
            Self::InnerProduct => 0,
            Self::Cosine => 1,
        }
    }

    pub(crate) fn from_header_tag(tag: u8) -> Option<Self> {
        match tag {
            0 => Some(Self::InnerProduct),
            1 => Some(Self::Cosine),
            _ => None,
        }
    }
}

impl std::fmt::Display for DistanceMetric {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(match self {
            Self::InnerProduct => "inner product",
            Self::Cosine => "cosine",
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StorageKind {
    F32,
    I8,
}

impl StorageKind {
    pub(crate) fn lane_width(self) -> usize {
        match self {
            Self::F32 => kernel::LANE_WIDTH,
            Self::I8 => kernel::LANE_WIDTH_I8,
        }
    }

    pub(crate) fn max_dims(self) -> usize {
        match self {
            Self::F32 => u32::MAX as usize,
            Self::I8 => kernel::MAX_DIMS_I8,
        }
    }

    pub(crate) fn header_tag(self) -> u8 {
        match self {
            Self::F32 => 0,
            Self::I8 => 1,
        }
    }

    pub(crate) fn from_header_tag(tag: u8) -> Option<Self> {
        match tag {
            0 => Some(Self::F32),
            1 => Some(Self::I8),
            _ => None,
        }
    }
}

impl std::fmt::Display for StorageKind {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(match self {
            Self::F32 => "f32",
            Self::I8 => "i8",
        })
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum AttrValue {
    Str(String),
    Bool(bool),
    I64(i64),
    F64(f64),
}

#[derive(Debug, Clone, PartialEq)]
pub struct Attribute {
    pub name: String,
    pub value: AttrValue,
}

#[derive(Debug, Clone, Default)]
pub struct SearchParams {
    pub limit: Option<usize>,
    pub max_distance: Option<f32>,
    pub exact: bool,
    pub allowed_keys: Option<Vec<String>>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Match {
    pub key: String,
    pub distance: f32,
}

#[derive(Debug, Clone, PartialEq)]
pub struct KeyMatches {
    pub key: String,
    pub matches: Vec<Match>,
}

#[derive(Debug, Error)]
pub enum VecDbError {
    #[error("{}: {source}", path.display())]
    Io {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("corrupt vector db: {0}")]
    Corrupt(String),
    #[error("{}: locked by another writer", .0.display())]
    Locked(PathBuf),
    #[error("vector db was opened read-only")]
    ReadOnly,
    #[error("vector db was deleted")]
    Closed,
    #[error("invalid key: {0}")]
    InvalidKey(String),
    #[error("invalid vector: {0}")]
    InvalidVector(String),
    #[error("invalid attributes: {0}")]
    InvalidAttributes(String),
    #[error("dimension mismatch: expected {expected}, got {actual}")]
    DimensionMismatch { expected: usize, actual: usize },
    #[error("invalid dimensions {dims}: {storage} storage needs a nonzero multiple of {} no larger than {}", .storage.lane_width(), .storage.max_dims())]
    InvalidDimensions { dims: usize, storage: StorageKind },
    #[error("storage mismatch: expected {expected}, found {actual}")]
    StorageMismatch {
        expected: StorageKind,
        actual: StorageKind,
    },
    #[error("distance metric mismatch: expected {expected}, found {actual}")]
    MetricMismatch {
        expected: DistanceMetric,
        actual: DistanceMetric,
    },
    #[error("search requires a limit or a max distance")]
    UnboundedSearch,
    #[error("length mismatch: {keys} keys, {vectors} vectors")]
    LengthMismatch { keys: usize, vectors: usize },
}

impl VecDbError {
    pub(crate) fn io(path: &Path, source: std::io::Error) -> Self {
        Self::Io {
            path: path.to_path_buf(),
            source,
        }
    }
}

#[cfg(test)]
pub(crate) mod test_support {
    use super::graph::Graph;

    pub(crate) fn assert_identical_graphs(first: &Graph, second: &Graph) {
        assert_eq!(first.entry_point(), second.entry_point());
        assert_eq!(
            first.slots().collect::<Vec<_>>(),
            second.slots().collect::<Vec<_>>()
        );
        for slot in first.slots() {
            assert_eq!(first.level_of(slot), second.level_of(slot));
            let level = first.level_of(slot).unwrap();
            for layer in 0..=level {
                assert_eq!(
                    first.neighbors_of(slot, layer),
                    second.neighbors_of(slot, layer)
                );
            }
        }
    }

    pub(crate) fn stale_downward_edge_exists(graph: &Graph) -> bool {
        graph.slots().any(|slot| {
            let level = graph.level_of(slot).unwrap();
            (0..=level).any(|layer| {
                graph
                    .neighbors_of(slot, layer)
                    .iter()
                    .any(|&neighbor| graph.level_of(neighbor).unwrap() < layer)
            })
        })
    }
}
