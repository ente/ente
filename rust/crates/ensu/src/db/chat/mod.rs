mod migrations;
#[cfg(feature = "sqlite")]
mod retired_storage;
mod schema;

use std::collections::BTreeSet;
use std::sync::Arc;

use uuid::Uuid;
use zeroize::Zeroizing;

use crate::db::backend::{Backend, BackendTx, RowExt, Value};
use crate::db::crypto;
use crate::db::models::{
    AttachmentMeta, EntityType, Message, Sender, Session, SessionWithPreview, StoredAttachment,
};
use crate::db::traits::{Clock, RandomUuidGen, SystemClock, UuidGen};
use crate::db::{Error, Result};

pub struct ChatDb<B: Backend> {
    backend: B,
    key: Zeroizing<Vec<u8>>,
    clock: Arc<dyn Clock>,
    uuid_gen: Arc<dyn UuidGen>,
}

impl<B: Backend> ChatDb<B> {
    pub fn new(
        backend: B,
        key: Vec<u8>,
        clock: Arc<dyn Clock>,
        uuid_gen: Arc<dyn UuidGen>,
    ) -> Result<Self> {
        let key = validate_key(key)?;
        migrations::migrate(&backend)?;
        Ok(Self {
            backend,
            key,
            clock,
            uuid_gen,
        })
    }

    pub fn new_with_defaults(backend: B, key: Vec<u8>) -> Result<Self> {
        Self::new(backend, key, Arc::new(SystemClock), Arc::new(RandomUuidGen))
    }

    pub fn create_session(&self, title: &str) -> Result<Session> {
        let now = self.clock.now_us();
        let uuid = self.uuid_gen.new_uuid();
        let affected = self.backend.execute(
            "INSERT INTO sessions (session_uuid, title, created_at, updated_at) VALUES (?, ?, ?, ?)",
            &[
                Value::Text(uuid.to_string()),
                Value::Blob(crypto::encrypt_string(title, &self.key)?),
                Value::Integer(now),
                Value::Integer(now),
            ],
        )?;
        ensure_row_updated(affected, EntityType::Session, uuid)?;
        Ok(Session {
            uuid,
            title: title.to_string(),
            created_at: now,
            updated_at: now,
        })
    }

    pub fn get_session(&self, uuid: Uuid) -> Result<Option<Session>> {
        let row = self.backend.query_row(
            "SELECT session_uuid, title, created_at, updated_at FROM sessions WHERE session_uuid = ?",
            &[Value::Text(uuid.to_string())],
        )?;
        row.map(|row| self.session_from_row(&row)).transpose()
    }

    pub fn list_sessions(&self) -> Result<Vec<Session>> {
        let rows = self.backend.query(
            "SELECT session_uuid, title, created_at, updated_at FROM sessions ORDER BY updated_at DESC",
            &[],
        )?;
        rows.iter().map(|row| self.session_from_row(row)).collect()
    }

    pub fn list_sessions_with_preview(&self) -> Result<Vec<SessionWithPreview>> {
        self.list_sessions()?
            .into_iter()
            .map(|session| {
                let last_message_preview = self
                    .get_messages(session.uuid)?
                    .last()
                    .map(|message| message.text.clone());
                Ok(SessionWithPreview {
                    uuid: session.uuid,
                    title: session.title,
                    created_at: session.created_at,
                    updated_at: session.updated_at,
                    last_message_preview,
                })
            })
            .collect()
    }

    pub fn update_session_title(&self, uuid: Uuid, title: &str) -> Result<()> {
        let affected = self.backend.execute(
            "UPDATE sessions SET title = ?, updated_at = ? WHERE session_uuid = ?",
            &[
                Value::Blob(crypto::encrypt_string(title, &self.key)?),
                Value::Integer(self.clock.now_us()),
                Value::Text(uuid.to_string()),
            ],
        )?;
        ensure_row_updated(affected, EntityType::Session, uuid)
    }

    pub fn delete_session(&self, uuid: Uuid) -> Result<Vec<String>> {
        self.backend.transaction(|tx| {
            let rows = tx.query(
                "SELECT attachments FROM messages WHERE session_uuid = ?",
                &[Value::Text(uuid.to_string())],
            )?;
            let mut attachment_ids = BTreeSet::new();
            for row in rows {
                for attachment in parse_stored_attachments(row.get_optional_string(0)?)? {
                    attachment_ids.insert(attachment.id);
                }
            }

            let affected = tx.execute(
                "DELETE FROM sessions WHERE session_uuid = ?",
                &[Value::Text(uuid.to_string())],
            )?;
            ensure_row_updated(affected, EntityType::Session, uuid)?;
            Ok(attachment_ids.into_iter().collect())
        })
    }

    pub fn upsert_session(
        &self,
        uuid: Uuid,
        title: &str,
        created_at: i64,
        updated_at: i64,
    ) -> Result<Session> {
        self.backend.execute(
            "INSERT INTO sessions (session_uuid, title, created_at, updated_at)
             VALUES (?, ?, ?, ?)
             ON CONFLICT(session_uuid) DO UPDATE SET
               title = CASE
                 WHEN excluded.updated_at >= sessions.updated_at THEN excluded.title
                 ELSE sessions.title
               END,
               created_at = MIN(sessions.created_at, excluded.created_at),
               updated_at = MAX(sessions.updated_at, excluded.updated_at)",
            &[
                Value::Text(uuid.to_string()),
                Value::Blob(crypto::encrypt_string(title, &self.key)?),
                Value::Integer(created_at),
                Value::Integer(updated_at),
            ],
        )?;
        self.get_session(uuid)?.ok_or(Error::NotFound {
            entity: EntityType::Session,
            id: uuid,
        })
    }

    pub fn insert_message(
        &self,
        session_uuid: Uuid,
        sender: &str,
        text: &str,
        parent: Option<Uuid>,
        attachments: Vec<AttachmentMeta>,
    ) -> Result<Message> {
        let sender: Sender = sender.parse()?;
        let created_at = self.clock.now_us();
        let uuid = self.uuid_gen.new_uuid();
        let encrypted_text = crypto::encrypt_string(text, &self.key)?;
        let attachments_json = self.serialize_attachments(&attachments)?;

        self.backend.transaction(|tx| {
            tx.execute(
                "INSERT INTO messages (
                   message_uuid, session_uuid, parent_message_uuid, sender,
                   text, attachments, created_at
                 ) VALUES (?, ?, ?, ?, ?, ?, ?)",
                &[
                    Value::Text(uuid.to_string()),
                    Value::Text(session_uuid.to_string()),
                    optional_uuid(parent),
                    Value::Text(sender.as_str().to_string()),
                    Value::Blob(encrypted_text),
                    attachments_json.map(Value::Text).unwrap_or(Value::Null),
                    Value::Integer(created_at),
                ],
            )?;
            self.touch_session(tx, session_uuid, created_at)
        })?;

        Ok(Message {
            uuid,
            session_uuid,
            parent_message_uuid: parent,
            sender,
            text: text.to_string(),
            attachments,
            created_at,
        })
    }

    #[allow(clippy::too_many_arguments)]
    pub fn insert_message_with_uuid(
        &self,
        uuid: Uuid,
        session_uuid: Uuid,
        sender: &str,
        text: &str,
        parent: Option<Uuid>,
        attachments: Vec<AttachmentMeta>,
        created_at: i64,
    ) -> Result<Message> {
        let sender: Sender = sender.parse()?;
        let encrypted_text = crypto::encrypt_string(text, &self.key)?;
        let attachments_json = self.serialize_attachments(&attachments)?;

        self.backend.transaction(|tx| {
            let inserted = tx.execute(
                "INSERT INTO messages (
                   message_uuid, session_uuid, parent_message_uuid, sender,
                   text, attachments, created_at
                 ) VALUES (?, ?, ?, ?, ?, ?, ?)
                 ON CONFLICT(message_uuid) DO NOTHING",
                &[
                    Value::Text(uuid.to_string()),
                    Value::Text(session_uuid.to_string()),
                    optional_uuid(parent),
                    Value::Text(sender.as_str().to_string()),
                    Value::Blob(encrypted_text),
                    attachments_json.map(Value::Text).unwrap_or(Value::Null),
                    Value::Integer(created_at),
                ],
            )?;
            if inserted == 1 {
                self.touch_session_at_least(tx, session_uuid, created_at)?;
            }
            Ok(())
        })?;

        self.get_message(uuid)?.ok_or(Error::NotFound {
            entity: EntityType::Message,
            id: uuid,
        })
    }

    pub fn get_message(&self, uuid: Uuid) -> Result<Option<Message>> {
        let row = self.backend.query_row(
            "SELECT message_uuid, session_uuid, parent_message_uuid, sender,
                    text, attachments, created_at
             FROM messages WHERE message_uuid = ?",
            &[Value::Text(uuid.to_string())],
        )?;
        row.map(|row| self.message_from_row(&row)).transpose()
    }

    pub fn get_messages(&self, session_uuid: Uuid) -> Result<Vec<Message>> {
        let rows = self.backend.query(
            "SELECT message_uuid, session_uuid, parent_message_uuid, sender,
                    text, attachments, created_at
             FROM messages
             WHERE session_uuid = ?
             ORDER BY created_at ASC, message_uuid ASC",
            &[Value::Text(session_uuid.to_string())],
        )?;
        rows.iter().map(|row| self.message_from_row(row)).collect()
    }

    pub fn update_message_text(&self, uuid: Uuid, text: &str) -> Result<()> {
        let updated_at = self.clock.now_us();
        let encrypted_text = crypto::encrypt_string(text, &self.key)?;
        self.backend.transaction(|tx| {
            let session_uuid = message_session_uuid(tx, uuid)?;
            let affected = tx.execute(
                "UPDATE messages SET text = ? WHERE message_uuid = ?",
                &[Value::Blob(encrypted_text), Value::Text(uuid.to_string())],
            )?;
            ensure_row_updated(affected, EntityType::Message, uuid)?;
            self.touch_session(tx, session_uuid, updated_at)
        })
    }

    fn session_from_row(&self, row: &crate::db::backend::Row) -> Result<Session> {
        Ok(Session {
            uuid: Uuid::parse_str(&row.get_string(0)?)?,
            title: crypto::decrypt_string(&row.get_blob(1)?, &self.key)?,
            created_at: row.get_i64(2)?,
            updated_at: row.get_i64(3)?,
        })
    }

    fn message_from_row(&self, row: &crate::db::backend::Row) -> Result<Message> {
        let parent_message_uuid = row
            .get_optional_string(2)?
            .map(|value| Uuid::parse_str(&value))
            .transpose()?;
        Ok(Message {
            uuid: Uuid::parse_str(&row.get_string(0)?)?,
            session_uuid: Uuid::parse_str(&row.get_string(1)?)?,
            parent_message_uuid,
            sender: row.get_string(3)?.parse()?,
            text: crypto::decrypt_string(&row.get_blob(4)?, &self.key)?,
            attachments: self.deserialize_attachments(row.get_optional_string(5)?)?,
            created_at: row.get_i64(6)?,
        })
    }

    fn serialize_attachments(&self, attachments: &[AttachmentMeta]) -> Result<Option<String>> {
        if attachments.is_empty() {
            return Ok(None);
        }
        let stored = attachments
            .iter()
            .map(|attachment| {
                Ok(StoredAttachment {
                    id: attachment.id.clone(),
                    kind: attachment.kind,
                    size: attachment.size,
                    encrypted_name: crypto::encrypt_json_field(&attachment.name, &self.key)?,
                })
            })
            .collect::<Result<Vec<_>>>()?;
        Ok(Some(serde_json::to_string(&stored)?))
    }

    fn deserialize_attachments(&self, raw: Option<String>) -> Result<Vec<AttachmentMeta>> {
        parse_stored_attachments(raw)?
            .into_iter()
            .map(|attachment| {
                Ok(AttachmentMeta {
                    id: attachment.id,
                    kind: attachment.kind,
                    size: attachment.size,
                    name: crypto::decrypt_json_field(&attachment.encrypted_name, &self.key)?,
                })
            })
            .collect()
    }

    fn touch_session<T: BackendTx>(
        &self,
        backend: &T,
        session_uuid: Uuid,
        updated_at: i64,
    ) -> Result<()> {
        let affected = backend.execute(
            "UPDATE sessions SET updated_at = ? WHERE session_uuid = ?",
            &[
                Value::Integer(updated_at),
                Value::Text(session_uuid.to_string()),
            ],
        )?;
        ensure_row_updated(affected, EntityType::Session, session_uuid)
    }

    fn touch_session_at_least<T: BackendTx>(
        &self,
        backend: &T,
        session_uuid: Uuid,
        updated_at: i64,
    ) -> Result<()> {
        let affected = backend.execute(
            "UPDATE sessions SET updated_at = MAX(updated_at, ?) WHERE session_uuid = ?",
            &[
                Value::Integer(updated_at),
                Value::Text(session_uuid.to_string()),
            ],
        )?;
        ensure_row_updated(affected, EntityType::Session, session_uuid)
    }
}

#[cfg(feature = "sqlite")]
impl ChatDb<crate::db::backend::sqlite::SqliteBackend> {
    pub fn open_sqlite(
        path: impl AsRef<std::path::Path>,
        key: Vec<u8>,
        clock: Arc<dyn Clock>,
        uuid_gen: Arc<dyn UuidGen>,
    ) -> Result<Self> {
        let path = path.as_ref();
        let backend = crate::db::backend::sqlite::SqliteBackend::open(path)?;
        let db = Self::new(backend, key, clock, uuid_gen)?;
        retired_storage::cleanup(path);
        Ok(db)
    }

    pub fn open_sqlite_with_defaults(
        path: impl AsRef<std::path::Path>,
        key: Vec<u8>,
    ) -> Result<Self> {
        Self::open_sqlite(path, key, Arc::new(SystemClock), Arc::new(RandomUuidGen))
    }

    pub fn open_in_memory(key: Vec<u8>) -> Result<Self> {
        let backend = crate::db::backend::sqlite::SqliteBackend::open_in_memory()?;
        Self::new_with_defaults(backend, key)
    }
}

fn validate_key(key: Vec<u8>) -> Result<Zeroizing<Vec<u8>>> {
    if key.len() != crypto::KEY_BYTES {
        return Err(Error::InvalidKeyLength {
            expected: crypto::KEY_BYTES,
            actual: key.len(),
        });
    }
    Ok(Zeroizing::new(key))
}

fn optional_uuid(value: Option<Uuid>) -> Value {
    value
        .map(|uuid| Value::Text(uuid.to_string()))
        .unwrap_or(Value::Null)
}

fn message_session_uuid<T: BackendTx>(backend: &T, uuid: Uuid) -> Result<Uuid> {
    let row = backend.query_row(
        "SELECT session_uuid FROM messages WHERE message_uuid = ?",
        &[Value::Text(uuid.to_string())],
    )?;
    let row = row.ok_or(Error::NotFound {
        entity: EntityType::Message,
        id: uuid,
    })?;
    Ok(Uuid::parse_str(&row.get_string(0)?)?)
}

fn ensure_row_updated(affected: usize, entity: EntityType, id: Uuid) -> Result<()> {
    if affected == 0 {
        return Err(Error::NotFound { entity, id });
    }
    Ok(())
}

fn parse_stored_attachments(raw: Option<String>) -> Result<Vec<StoredAttachment>> {
    match raw {
        Some(raw) if !raw.trim().is_empty() => Ok(serde_json::from_str(&raw)?),
        _ => Ok(Vec::new()),
    }
}

#[cfg(all(test, feature = "sqlite"))]
mod tests {
    use std::collections::VecDeque;
    use std::sync::atomic::{AtomicI64, Ordering};
    use std::sync::{Arc, Mutex};

    use super::*;
    use crate::db::backend::sqlite::SqliteBackend;
    use crate::db::backend::{BackendTx, RowExt, Value};
    use crate::db::crypto::KEY_BYTES;
    use crate::db::models::{AttachmentKind, AttachmentMeta};

    #[derive(Debug)]
    struct StepClock {
        current: AtomicI64,
        step: i64,
    }

    impl StepClock {
        fn new(start: i64, step: i64) -> Self {
            Self {
                current: AtomicI64::new(start),
                step,
            }
        }
    }

    impl Clock for StepClock {
        fn now_us(&self) -> i64 {
            self.current.fetch_add(self.step, Ordering::SeqCst)
        }
    }

    #[derive(Debug)]
    struct TestUuidGen {
        uuids: Mutex<VecDeque<Uuid>>,
    }

    impl TestUuidGen {
        fn new(uuids: Vec<Uuid>) -> Self {
            Self {
                uuids: Mutex::new(uuids.into()),
            }
        }
    }

    impl UuidGen for TestUuidGen {
        fn new_uuid(&self) -> Uuid {
            self.uuids
                .lock()
                .expect("uuid lock poisoned")
                .pop_front()
                .expect("uuid queue empty")
        }
    }

    fn make_db(uuids: Vec<Uuid>, clock: Arc<dyn Clock>) -> ChatDb<SqliteBackend> {
        ChatDb::new(
            SqliteBackend::open_in_memory().unwrap(),
            vec![1u8; KEY_BYTES],
            clock,
            Arc::new(TestUuidGen::new(uuids)),
        )
        .unwrap()
    }

    #[test]
    fn create_and_get_session_encrypts_title() {
        let session_id = Uuid::from_u128(1);
        let db = make_db(vec![session_id], Arc::new(StepClock::new(100, 1)));

        let session = db.create_session("hello").unwrap();
        assert_eq!(session.uuid, session_id);
        assert_eq!(session.title, "hello");
        assert_eq!(db.get_session(session_id).unwrap().unwrap().title, "hello");

        let row = db
            .backend
            .query_row(
                "SELECT title FROM sessions WHERE session_uuid = ?",
                &[Value::Text(session_id.to_string())],
            )
            .unwrap()
            .unwrap();
        let stored = row.get_blob(0).unwrap();
        assert!(stored.len() >= crypto::HEADER_BYTES);
        assert_ne!(stored, b"hello".to_vec());
    }

    #[test]
    fn message_updates_touch_session() {
        let session_id = Uuid::from_u128(2);
        let message_id = Uuid::from_u128(3);
        let db = make_db(
            vec![session_id, message_id],
            Arc::new(StepClock::new(10, 1)),
        );

        db.create_session("title").unwrap();
        let after_create = db.get_session(session_id).unwrap().unwrap().updated_at;
        let message = db
            .insert_message(session_id, "self", "hello", None, Vec::new())
            .unwrap();
        assert_eq!(message.uuid, message_id);
        let after_insert = db.get_session(session_id).unwrap().unwrap().updated_at;
        assert!(after_insert > after_create);

        db.update_message_text(message_id, "updated").unwrap();
        assert!(db.get_session(session_id).unwrap().unwrap().updated_at > after_insert);
    }

    #[test]
    fn delete_session_cascades_messages() {
        let session_id = Uuid::from_u128(4);
        let message_id = Uuid::from_u128(5);
        let db = make_db(vec![session_id, message_id], Arc::new(StepClock::new(1, 1)));

        db.create_session("title").unwrap();
        db.insert_message(
            session_id,
            "other",
            "hi",
            None,
            vec![AttachmentMeta {
                id: "attachment".to_string(),
                kind: AttachmentKind::Document,
                size: 1,
                name: "note.txt".to_string(),
            }],
        )
        .unwrap();
        assert_eq!(
            db.delete_session(session_id).unwrap(),
            vec!["attachment".to_string()]
        );

        assert!(db.get_session(session_id).unwrap().is_none());
        assert!(db.get_message(message_id).unwrap().is_none());
    }

    #[test]
    fn on_disk_v4_migration_survives_reopen() {
        let root = std::env::temp_dir().join(format!("ensu-v4-{}", Uuid::new_v4()));
        std::fs::create_dir_all(&root).unwrap();
        let path = root.join("llmchat.db");
        let key = vec![2u8; KEY_BYTES];
        let (session_id, message_id) = {
            let db = ChatDb::open_sqlite_with_defaults(&path, key.clone()).unwrap();
            let session = db.create_session("Before migration").unwrap();
            let message = db
                .insert_message(session.uuid, "self", "Still here", None, Vec::new())
                .unwrap();
            (session.uuid, message.uuid)
        };
        {
            let backend = SqliteBackend::open(&path).unwrap();
            backend
                .execute_batch(
                    "ALTER TABLE sessions ADD COLUMN server_updated_at INTEGER;
                     ALTER TABLE sessions ADD COLUMN remote_id TEXT;
                     ALTER TABLE sessions ADD COLUMN needs_sync INTEGER NOT NULL DEFAULT 1;
                     ALTER TABLE sessions ADD COLUMN deleted_at INTEGER;
                     ALTER TABLE messages ADD COLUMN remote_id TEXT;
                     ALTER TABLE messages ADD COLUMN server_updated_at INTEGER;
                     ALTER TABLE messages ADD COLUMN needs_sync INTEGER NOT NULL DEFAULT 1;
                     ALTER TABLE messages ADD COLUMN deleted_at INTEGER;
                     PRAGMA user_version = 4;",
                )
                .unwrap();
        }

        for _ in 0..2 {
            let db = ChatDb::open_sqlite_with_defaults(&path, key.clone()).unwrap();
            assert_eq!(
                db.get_session(session_id).unwrap().unwrap().title,
                "Before migration"
            );
            assert_eq!(
                db.get_message(message_id).unwrap().unwrap().text,
                "Still here"
            );
        }
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn attachment_metadata_is_encrypted_in_json() {
        let session_id = Uuid::from_u128(6);
        let message_id = Uuid::from_u128(7);
        let db = make_db(
            vec![session_id, message_id],
            Arc::new(StepClock::new(50, 1)),
        );
        db.create_session("title").unwrap();
        db.insert_message(
            session_id,
            "self",
            "hello",
            None,
            vec![AttachmentMeta {
                id: "att-1".to_string(),
                kind: AttachmentKind::Image,
                size: 123,
                name: "photo.jpg".to_string(),
            }],
        )
        .unwrap();

        let row = db
            .backend
            .query_row(
                "SELECT attachments FROM messages WHERE message_uuid = ?",
                &[Value::Text(message_id.to_string())],
            )
            .unwrap()
            .unwrap();
        let stored: Vec<StoredAttachment> =
            serde_json::from_str(&row.get_optional_string(0).unwrap().unwrap()).unwrap();
        assert!(stored[0].encrypted_name.starts_with("enc:v1:"));
        assert!(!stored[0].encrypted_name.contains("photo.jpg"));
    }

    #[test]
    fn invalid_sender_is_rejected() {
        let session_id = Uuid::from_u128(8);
        let message_id = Uuid::from_u128(9);
        let db = make_db(vec![session_id, message_id], Arc::new(StepClock::new(1, 1)));
        db.create_session("title").unwrap();
        assert!(matches!(
            db.insert_message(session_id, "invalid", "hello", None, Vec::new()),
            Err(Error::InvalidSender(_))
        ));
    }
}
