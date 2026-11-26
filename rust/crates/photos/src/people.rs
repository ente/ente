use std::collections::{BTreeSet, HashSet};
use std::io::Read;
use std::ops::Range;

use ente_core::crypto::{self, Header, Key, Nonce, SecretVec, blob, secretbox};
use ente_core::{Session, b64, http};
use flate2::read::GzDecoder;
use serde::de::Error as _;
use serde::{Deserialize, Deserializer};
use serde_json::{Map, Number, Value};

use crate::ml_db::try_file_id_from_face_id;

const ENTITY_TYPE: &str = "cgroup";
const PAGE_SIZE: usize = 500;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Http(#[from] http::Error),
    #[error(transparent)]
    Crypto(#[from] crypto::Error),
    #[error(transparent)]
    Base64(#[from] b64::DecodeError),
    #[error("person data could not be decompressed: {0}")]
    Decompress(std::io::Error),
    #[error("person data is not valid: {0}")]
    Json(#[from] serde_json::Error),
    #[error("the account has people but no people key")]
    MissingKey,
    #[error("invalid people diff: {0}")]
    InvalidDiff(&'static str),
}

pub type Result<T> = std::result::Result<T, Error>;

pub struct Page {
    pub updated: Vec<RemotePerson>,
    pub deleted: Vec<String>,
    pub cursor: i64,
    pub has_more: bool,
}

pub struct RemotePerson {
    pub id: String,
    pub updated_at: i64,
    pub data: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Person {
    pub name: String,
    pub hidden: bool,
    pub clusters: Vec<Cluster>,
    pub rejected_face_ids: Vec<String>,
    pub manually_assigned: Vec<i64>,
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize)]
pub struct Cluster {
    pub id: String,
    #[serde(rename = "faces")]
    pub face_ids: Vec<String>,
}

impl Person {
    pub fn from_json(data: &str) -> Result<Self> {
        let object: Map<String, Value> = serde_json::from_str(data)?;
        let wire = WirePerson::deserialize(Value::Object(object))?;
        let name = wire.name.unwrap_or_default();
        Ok(Self {
            hidden: wire.is_hidden.unwrap_or_default()
                || matches!(name.as_str(), "" | "(hidden)" | "(ignored)"),
            name,
            clusters: wire.assigned,
            rejected_face_ids: wire.rejected_face_ids.unwrap_or_default(),
            manually_assigned: wire.manually_assigned,
        })
    }

    pub fn file_ids(&self) -> BTreeSet<i64> {
        let rejected: HashSet<&str> = self.rejected_face_ids.iter().map(String::as_str).collect();
        self.clusters
            .iter()
            .flat_map(|cluster| &cluster.face_ids)
            .map(String::as_str)
            .filter(|face_id| !rejected.contains(face_id))
            .filter_map(try_file_id_from_face_id)
            .chain(self.manually_assigned.iter().copied())
            .collect()
    }
}

pub async fn diff(session: &Session, since: i64) -> Result<Page> {
    let entities = fetch_diff(session, since).await?;
    let key = if entities.iter().any(|entity| !entity.is_deleted) {
        Some(fetch_key(session).await?.ok_or(Error::MissingKey)?)
    } else {
        None
    };
    page(entities, since, key.as_ref())
}

#[derive(Deserialize)]
struct WirePerson {
    name: Option<String>,
    #[serde(rename = "isHidden")]
    is_hidden: Option<bool>,
    #[serde(default, deserialize_with = "deserialize_clusters")]
    assigned: Vec<Cluster>,
    #[serde(rename = "rejectedFaceIDs")]
    rejected_face_ids: Option<Vec<String>>,
    #[serde(
        default,
        rename = "manuallyAssigned",
        deserialize_with = "deserialize_file_ids"
    )]
    manually_assigned: Vec<i64>,
}

fn deserialize_clusters<'de, D: Deserializer<'de>>(
    deserializer: D,
) -> std::result::Result<Vec<Cluster>, D::Error> {
    let Value::Array(entries) = Value::deserialize(deserializer)? else {
        return Ok(Vec::new());
    };
    entries
        .into_iter()
        .filter(Value::is_object)
        .map(|entry| Cluster::deserialize(entry).map_err(D::Error::custom))
        .collect()
}

fn deserialize_file_ids<'de, D: Deserializer<'de>>(
    deserializer: D,
) -> std::result::Result<Vec<i64>, D::Error> {
    let Value::Array(entries) = Value::deserialize(deserializer)? else {
        return Ok(Vec::new());
    };
    Ok(entries
        .iter()
        .filter_map(|entry| match entry {
            Value::Number(number) => whole_number(number),
            Value::String(text) => text.trim().parse().ok(),
            _ => None,
        })
        .collect())
}

fn whole_number(number: &Number) -> Option<i64> {
    const I64_RANGE: Range<f64> = i64::MIN as f64..-(i64::MIN as f64);
    number.as_i64().or_else(|| {
        let value = number.as_f64()?;
        (value.fract() == 0.0 && I64_RANGE.contains(&value)).then_some(value as i64)
    })
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Entity {
    id: String,
    encrypted_data: Option<String>,
    header: Option<String>,
    is_deleted: bool,
    updated_at: i64,
}

async fn fetch_diff(session: &Session, since: i64) -> Result<Vec<Entity>> {
    #[derive(Deserialize)]
    struct Response {
        diff: Vec<Entity>,
    }
    let query = [
        ("sinceTime", since.to_string()),
        ("limit", PAGE_SIZE.to_string()),
        ("type", ENTITY_TYPE.to_owned()),
    ];
    let response: Response = http::retry(|| async {
        session
            .api
            .get("/user-entity/entity/diff")
            .query(&query)
            .send()
            .await?
            .error_for_code()
            .await?
            .json()
            .await
    })
    .await?;
    Ok(response.diff)
}

async fn fetch_key(session: &Session) -> Result<Option<Key>> {
    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct WrappedKey {
        encrypted_key: String,
        header: String,
    }
    let wrapped: Option<WrappedKey> = http::retry(|| async {
        let response = session
            .api
            .get("/user-entity/key")
            .query(&[("type", ENTITY_TYPE)])
            .send()
            .await?;
        if response.status() == 404 {
            return Ok(None);
        }
        response.error_for_code().await?.json().await.map(Some)
    })
    .await?;
    wrapped
        .map(|wrapped| {
            let key = SecretVec::new(secretbox::decrypt(
                &b64::decode(&wrapped.encrypted_key)?,
                &Nonce::try_from_slice(&b64::decode(&wrapped.header)?)?,
                &session.master_key,
            )?);
            Ok(Key::try_from_slice(&key)?)
        })
        .transpose()
}

fn page(entities: Vec<Entity>, since: i64, key: Option<&Key>) -> Result<Page> {
    if entities.iter().any(|entity| entity.updated_at <= since) {
        return Err(Error::InvalidDiff("entity is not newer than the cursor"));
    }
    let has_more = entities.len() >= PAGE_SIZE;
    let cursor = next_cursor(&entities, since, has_more)?;
    let mut updated = Vec::new();
    let mut deleted = Vec::new();
    for entity in entities {
        if entity.is_deleted {
            deleted.push(entity.id);
        } else {
            let data = decrypt(&entity, key.ok_or(Error::MissingKey)?)?;
            updated.push(RemotePerson {
                id: entity.id,
                updated_at: entity.updated_at,
                data,
            });
        }
    }
    Ok(Page {
        updated,
        deleted,
        cursor,
        has_more,
    })
}

fn next_cursor(entities: &[Entity], since: i64, has_more: bool) -> Result<i64> {
    let Some(newest) = entities.iter().map(|entity| entity.updated_at).max() else {
        return Ok(since);
    };
    if !has_more {
        return Ok(newest);
    }
    if entities.iter().all(|entity| entity.updated_at == newest) {
        return Err(Error::InvalidDiff(
            "a full page of people shares one timestamp",
        ));
    }
    Ok(newest - 1)
}

fn decrypt(entity: &Entity, key: &Key) -> Result<String> {
    let (Some(data), Some(header)) = (&entity.encrypted_data, &entity.header) else {
        return Err(Error::InvalidDiff("live entity without encrypted data"));
    };
    let compressed = blob::decrypt(
        &b64::decode(data)?,
        &Header::try_from_slice(&b64::decode(header)?)?,
        key,
    )?;
    let mut json = String::new();
    GzDecoder::new(compressed.as_slice())
        .read_to_string(&mut json)
        .map_err(Error::Decompress)?;
    Ok(json)
}

#[cfg(test)]
mod tests {
    use std::io::Write;

    use flate2::Compression;
    use flate2::write::GzEncoder;
    use serde_json::json;

    use super::*;

    fn person(value: Value) -> Person {
        Person::from_json(&value.to_string()).unwrap()
    }

    fn sealed(id: &str, updated_at: i64, plaintext: &[u8], key: &Key) -> Entity {
        let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
        encoder.write_all(plaintext).unwrap();
        let encrypted = blob::encrypt(&encoder.finish().unwrap(), key).unwrap();
        Entity {
            id: id.to_owned(),
            encrypted_data: Some(b64::encode(&encrypted.encrypted_data)),
            header: Some(b64::encode(encrypted.decryption_header.as_bytes())),
            is_deleted: false,
            updated_at,
        }
    }

    fn tombstone(id: &str, updated_at: i64) -> Entity {
        Entity {
            id: id.to_owned(),
            encrypted_data: None,
            header: None,
            is_deleted: true,
            updated_at,
        }
    }

    #[test]
    fn reads_every_field_people_are_built_from() {
        let parsed = person(json!({
            "name": "Ada",
            "isHidden": true,
            "assigned": [{"id": "c1", "faces": ["10_a", "11_b"]}],
            "rejectedFaceIDs": ["11_b"],
            "manuallyAssigned": [12],
            "avatarFaceID": "10_a",
            "isPinned": true,
        }));
        assert_eq!(
            parsed,
            Person {
                name: "Ada".to_owned(),
                hidden: true,
                clusters: vec![Cluster {
                    id: "c1".to_owned(),
                    face_ids: vec!["10_a".to_owned(), "11_b".to_owned()],
                }],
                rejected_face_ids: vec!["11_b".to_owned()],
                manually_assigned: vec![12],
            }
        );
    }

    #[test]
    fn missing_and_null_fields_take_their_defaults() {
        for value in [
            json!({}),
            json!({"name": null, "isHidden": null, "assigned": null, "rejectedFaceIDs": null, "manuallyAssigned": null}),
        ] {
            assert_eq!(
                person(value),
                Person {
                    name: String::new(),
                    hidden: true,
                    clusters: Vec::new(),
                    rejected_face_ids: Vec::new(),
                    manually_assigned: Vec::new(),
                }
            );
        }
    }

    #[test]
    fn tolerates_the_loose_shapes_other_clients_accept() {
        let parsed = person(json!({
            "assigned": [{"id": "c1", "faces": ["1_a"]}, "stray", 7, null],
            "manuallyAssigned": [3, "4", " 5 ", "six", true, null, 6.5],
        }));
        assert_eq!(parsed.clusters.len(), 1);
        assert_eq!(parsed.manually_assigned, [3, 4, 5]);
        for assigned in [json!({"id": "c1"}), json!("c1"), json!(3)] {
            assert!(person(json!({"assigned": assigned})).clusters.is_empty());
        }
        assert!(
            person(json!({"manuallyAssigned": {"0": 1}}))
                .manually_assigned
                .is_empty()
        );
    }

    #[test]
    fn whole_numbers_count_in_any_notation_and_fractions_do_not() {
        let parsed = Person::from_json(
            r#"{"manuallyAssigned": [104.0, 1.05e2, 1e2, -7.0, 104.7, 1e19, -1e19, 9223372036854775807]}"#,
        )
        .unwrap();
        assert_eq!(parsed.manually_assigned, [104, 105, 100, -7, i64::MAX]);
    }

    #[test]
    fn rejects_fields_with_the_wrong_type() {
        for value in [
            json!({"name": 3}),
            json!({"isHidden": "yes"}),
            json!({"rejectedFaceIDs": [1]}),
            json!({"assigned": [{"id": 1, "faces": []}]}),
            json!({"assigned": [{"id": "c1", "faces": [1]}]}),
            json!({"assigned": [{"faces": []}]}),
            json!([]),
            json!(["Ada", false, [], [], [104]]),
            json!("Ada"),
            json!(null),
        ] {
            assert!(Person::from_json(&value.to_string()).is_err(), "{value}");
        }
        assert!(Person::from_json("not json").is_err());
    }

    #[test]
    fn hides_people_marked_hidden_or_with_legacy_names() {
        for (value, hidden) in [
            (json!({"name": "Ada"}), false),
            (json!({"name": "Ada", "isHidden": true}), true),
            (json!({"name": ""}), true),
            (json!({}), true),
            (json!({"name": "(hidden)"}), true),
            (json!({"name": "(ignored)"}), true),
            (json!({"name": " (hidden)"}), false),
        ] {
            assert_eq!(person(value.clone()).hidden, hidden, "{value}");
        }
    }

    #[test]
    fn files_come_from_assigned_faces_minus_rejected_plus_manual() {
        let parsed = person(json!({
            "name": "Ada",
            "assigned": [
                {"id": "c1", "faces": ["10_a", "10_b", "11_a"]},
                {"id": "c2", "faces": ["12_a", "13_a", "bad", "_x"]},
            ],
            "rejectedFaceIDs": ["11_a", "13_a", "99_a"],
            "manuallyAssigned": [14, 10],
        }));
        assert_eq!(parsed.file_ids(), BTreeSet::from([10, 12, 14]));
    }

    #[test]
    fn a_file_with_one_rejected_face_stays_through_another_face() {
        let parsed = person(json!({
            "assigned": [{"id": "c1", "faces": ["10_a", "10_b"]}],
            "rejectedFaceIDs": ["10_a"],
        }));
        assert_eq!(parsed.file_ids(), BTreeSet::from([10]));
    }

    #[test]
    fn page_decrypts_live_people_and_lists_deletions() {
        let key = Key::generate();
        let data = br#"{"name":"Ada"}"#;
        let page = page(
            vec![
                sealed("p1", 20, data, &key),
                tombstone("p2", 30),
                sealed("p3", 25, b"{}", &key),
            ],
            10,
            Some(&key),
        )
        .unwrap();
        let updated: Vec<_> = page
            .updated
            .iter()
            .map(|person| (person.id.as_str(), person.updated_at, person.data.as_str()))
            .collect();
        assert_eq!(updated, [("p1", 20, r#"{"name":"Ada"}"#), ("p3", 25, "{}")]);
        assert_eq!(page.deleted, ["p2"]);
        assert_eq!(page.cursor, 30);
        assert!(!page.has_more);
    }

    #[test]
    fn empty_page_keeps_the_cursor() {
        let page = page(Vec::new(), 42, None).unwrap();
        assert!(page.updated.is_empty() && page.deleted.is_empty());
        assert_eq!(page.cursor, 42);
        assert!(!page.has_more);
    }

    #[test]
    fn deletions_need_no_key() {
        let page = page(vec![tombstone("p1", 5)], 0, None).unwrap();
        assert_eq!(page.deleted, ["p1"]);
    }

    #[test]
    fn a_full_page_reports_more_and_rereads_its_newest_timestamp() {
        let entities = (1..=PAGE_SIZE as i64)
            .map(|updated_at| tombstone(&updated_at.to_string(), updated_at))
            .collect();
        let page = page(entities, 0, None).unwrap();
        assert!(page.has_more);
        assert_eq!(page.cursor, PAGE_SIZE as i64 - 1);
    }

    #[test]
    fn a_full_page_cut_inside_a_tie_resumes_before_the_tie() {
        let entities = (1..PAGE_SIZE as i64)
            .chain([1000])
            .map(|updated_at| tombstone(&updated_at.to_string(), updated_at))
            .collect();
        let page = page(entities, 0, None).unwrap();
        assert!(page.has_more);
        assert_eq!(page.cursor, 999);
    }

    #[test]
    fn a_full_page_sharing_one_timestamp_is_an_error() {
        let entities = (0..PAGE_SIZE)
            .map(|index| tombstone(&index.to_string(), 7))
            .collect();
        assert!(matches!(
            page(entities, 0, None),
            Err(Error::InvalidDiff(_))
        ));
    }

    #[test]
    fn live_people_without_a_key_are_an_error() {
        let key = Key::generate();
        assert!(matches!(
            page(vec![sealed("p1", 5, b"{}", &key)], 0, None),
            Err(Error::MissingKey)
        ));
    }

    #[test]
    fn rejects_entities_that_do_not_advance_the_cursor() {
        assert!(matches!(
            page(vec![tombstone("p1", 10)], 10, None),
            Err(Error::InvalidDiff(_))
        ));
    }

    #[test]
    fn rejects_live_entities_without_encrypted_data() {
        let key = Key::generate();
        let mut entity = sealed("p1", 5, b"{}", &key);
        entity.header = None;
        assert!(matches!(
            page(vec![entity], 0, Some(&key)),
            Err(Error::InvalidDiff(_))
        ));
    }

    #[test]
    fn wrong_key_or_uncompressed_data_fails() {
        let key = Key::generate();
        assert!(matches!(
            page(
                vec![sealed("p1", 5, b"{}", &key)],
                0,
                Some(&Key::generate())
            ),
            Err(Error::Crypto(_))
        ));
        let encrypted = blob::encrypt(b"{}", &key).unwrap();
        let plain = Entity {
            id: "p1".to_owned(),
            encrypted_data: Some(b64::encode(&encrypted.encrypted_data)),
            header: Some(b64::encode(encrypted.decryption_header.as_bytes())),
            is_deleted: false,
            updated_at: 5,
        };
        assert!(matches!(
            page(vec![plain], 0, Some(&key)),
            Err(Error::Decompress(_))
        ));
    }
}
