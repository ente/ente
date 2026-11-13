use serde::{Deserialize, Deserializer, Serializer};
use uuid::Uuid;

pub(super) fn serialize<S: Serializer>(uuid: &Uuid, serializer: S) -> Result<S::Ok, S::Error> {
    serializer.collect_str(uuid)
}

pub(super) fn deserialize<'de, D: Deserializer<'de>>(deserializer: D) -> Result<Uuid, D::Error> {
    String::deserialize(deserializer)?
        .parse()
        .map_err(serde::de::Error::custom)
}
