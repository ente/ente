use chrono::DateTime;
use ente_core::{
    b64,
    crypto::{Key, kdf},
};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value, json};

use ente_photos::{
    collections::{Collection, Visibility},
    files::{File, Kind},
    source::{self, Documents, MetadataError},
};

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Root {
    pub format: String,
    pub version: u32,
    pub source_verifier: String,
}

impl Root {
    pub fn new(master_key: &Key) -> ente_core::crypto::Result<Self> {
        Ok(Self {
            format: "ente-photos-export".into(),
            version: 1,
            source_verifier: b64::encode(&kdf::derive_subkey(master_key, 32, 1, b"photoexp")?),
        })
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Role {
    Original,
    Image,
    Video,
}

impl Role {
    pub fn name(&self) -> &'static str {
        match self {
            Self::Original => "original",
            Self::Image => "image",
            Self::Video => "video",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Component {
    pub role: Role,
    pub path: String,
    pub size: u64,
    pub hash: String,
}

pub fn album(album: &Collection, documents: &Documents) -> Result<Value, MetadataError> {
    let mut metadata = json!({"albumID": album.id.to_string(), "type": album.kind.name()});
    for (name, bytes) in [
        ("magicMetadata", &documents.private),
        ("pubMagicMetadata", &documents.public),
        ("sharedMagicMetadata", &documents.shared),
    ] {
        if let Some(bytes) = bytes {
            metadata[name] = json!(source::parse::<Map<String, Value>>(
                bytes,
                "invalid album metadata document",
            )?);
        }
    }
    Ok(json!({"title": album.name, "ente": metadata}))
}

pub fn album_categories(record: &Value) -> Result<(Option<bool>, bool), MetadataError> {
    let metadata = &record["ente"];
    for name in ["magicMetadata", "pubMagicMetadata", "sharedMagicMetadata"] {
        if let Some(document) = metadata.get(name)
            && !document.is_object()
        {
            return Err(MetadataError("invalid album metadata document"));
        }
    }
    let private = metadata.get("magicMetadata");
    let shared = metadata.get("sharedMagicMetadata");
    let visibility = private.or(shared).map_or(Ok(None), |document| {
        serde_json::from_value::<Option<u8>>(document["visibility"].clone())
            .map_err(|_| MetadataError("invalid album visibility"))
    })?;
    let hidden = metadata["type"] == "defaultHidden"
        || matches!(Visibility::from_value(visibility)?, Visibility::Hidden);
    Ok((private.map(|_| false).or(shared.map(|_| true)), hidden))
}

pub fn file(file: &File, documents: &Documents) -> Result<Value, MetadataError> {
    let mut original: Map<String, Value> =
        source::parse(&documents.original, "invalid original file metadata")?;
    let mut public: Map<String, Value> =
        source::optional(documents.public.as_deref(), "invalid public file metadata")?;
    for field in [
        "localID",
        "deviceFolder",
        "subType",
        "version",
        "exif",
        "hasStaticThumbnail",
    ] {
        original.remove(field);
    }
    for field in ["sv", "noThumb"] {
        public.remove(field);
    }
    if public.get("editedName").and_then(Value::as_str).is_some() {
        original.remove("title");
    }
    if public.get("lat").and_then(Value::as_f64).is_some()
        && public.get("long").and_then(Value::as_f64).is_some()
    {
        original.remove("latitude");
        original.remove("longitude");
    }
    if public
        .get("editedTime")
        .and_then(Value::as_i64)
        .is_some_and(|time| time != 0)
    {
        original.remove("creationTime");
    }
    if public.get("uploaderName").and_then(Value::as_str).is_some() {
        original.remove("uploaderName");
    }
    let mut metadata = json!({
        "fileID": file.id.to_string(),
        "type": if file.kind == Kind::LivePhoto { "livePhoto" } else { file.kind.name() },
        "metadata": original,
    });
    if documents.public.is_some() {
        metadata["pubMagicMetadata"] = json!(public);
    }
    if let Some(private) = &documents.private {
        metadata["magicMetadata"] = json!(source::parse::<Map<String, Value>>(
            private,
            "invalid private file metadata",
        )?);
    }
    let taken = common_time(file.created_at_micros)?;
    let (latitude, longitude) = file.location.as_ref().map_or((0.0, 0.0), |location| {
        (location.latitude, location.longitude)
    });
    let mut record = json!({
        "title": file.name,
        "photoTakenTime": taken,
        "creationTime": taken,
        "geoData": {"latitude": latitude, "longitude": longitude},
        "ente": metadata,
    });
    optional(
        &mut record,
        "modificationTime",
        file.modified_at_micros.map(common_time).transpose()?,
    );
    optional(
        &mut record,
        "description",
        file.caption
            .as_deref()
            .filter(|caption| !caption.is_empty()),
    );
    Ok(record)
}

fn optional(object: &mut Value, name: &str, value: Option<impl Into<Value>>) {
    if let Some(value) = value {
        object[name] = value.into();
    }
}

fn time(micros: i64) -> Result<DateTime<chrono::Utc>, MetadataError> {
    DateTime::from_timestamp_micros(micros)
        .ok_or(MetadataError("timestamp is outside the supported range"))
}

fn common_time(micros: i64) -> Result<Value, MetadataError> {
    let time = time(micros)?;
    Ok(
        json!({"timestamp":micros.div_euclid(1_000_000).to_string(),"formatted":time.format("%b %-d, %Y, %-I:%M:%S %p UTC").to_string()}),
    )
}

pub fn publish(
    template: &Value,
    components: &[Component],
    component: usize,
    favorited: bool,
) -> Result<Value, MetadataError> {
    let selected = components
        .get(component)
        .ok_or(MetadataError("missing media component"))?;
    let mut record = template.clone();
    record["favorited"] = json!(favorited);
    record["ente"]["component"] = json!(selected.role);
    record["ente"]["components"] = json!(components);
    Ok(record)
}
