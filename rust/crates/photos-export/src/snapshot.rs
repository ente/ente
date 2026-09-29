use anyhow::Result;
use ente_core::crypto::{Header, Key};
use ente_photos::{files::File, source::Documents};
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::metadata;

#[derive(Serialize, Deserialize)]
pub(crate) struct FileSnapshot {
    pub id: i64,
    pub updated_at_micros: i64,
    pub name: String,
    pub kind: String,
    pub hash: Option<String>,
    #[serde(with = "key")]
    pub key: Key,
    #[serde(with = "header")]
    pub header: Header,
    pub intended_time: i64,
    pub metadata: Value,
    pub warnings: Vec<String>,
}

impl FileSnapshot {
    pub fn new(file: File, documents: &Documents) -> Result<Self> {
        let (metadata, warnings) = metadata::file(&file, documents)?;
        Ok(Self {
            id: file.id,
            updated_at_micros: file.updated_at_micros,
            name: file.name,
            kind: file.kind.name().into(),
            hash: file.hash,
            key: file.key,
            header: file.header,
            intended_time: file.modified_at_micros.unwrap_or(file.created_at_micros),
            metadata,
            warnings,
        })
    }
}

mod key {
    use ente_core::crypto::Key;
    use serde::{Deserialize, Deserializer, Serializer, de::Error};

    pub fn serialize<S: Serializer>(key: &Key, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(&ente_core::b64::encode(key.as_bytes()))
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(deserializer: D) -> Result<Key, D::Error> {
        Key::try_from_slice(
            &ente_core::b64::decode(&String::deserialize(deserializer)?)
                .map_err(D::Error::custom)?,
        )
        .map_err(D::Error::custom)
    }
}

mod header {
    use ente_core::crypto::Header;
    use serde::{Deserialize, Deserializer, Serializer, de::Error};

    pub fn serialize<S: Serializer>(header: &Header, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(&ente_core::b64::encode(header.as_bytes()))
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(deserializer: D) -> Result<Header, D::Error> {
        Header::try_from_slice(
            &ente_core::b64::decode(&String::deserialize(deserializer)?)
                .map_err(D::Error::custom)?,
        )
        .map_err(D::Error::custom)
    }
}
