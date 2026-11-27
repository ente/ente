use serde::Serialize;
use serde_json::Value;

use crate::Result;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct VersionedJson {
    pub version: i64,
    pub data: Value,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct FileDocuments {
    pub metadata: Value,
    pub pub_magic_metadata: Option<VersionedJson>,
    pub magic_metadata: Option<VersionedJson>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CollectionDocuments {
    pub private: Option<VersionedJson>,
    pub public: Option<VersionedJson>,
    pub shared: Option<VersionedJson>,
}

pub(crate) fn parse_json(bytes: &[u8]) -> Result<Value> {
    Ok(serde_json::from_slice(bytes)?)
}
