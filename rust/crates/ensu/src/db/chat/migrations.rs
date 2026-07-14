use crate::db::backend::{BackendTx, RowExt};
use crate::db::{Backend, Error, Result};

use super::schema;

pub const LATEST_VERSION: i64 = 5;

pub fn migrate<B: Backend>(backend: &B) -> Result<()> {
    match user_version(backend)? {
        0 => {
            backend.execute_batch(schema::CREATE_ALL)?;
            backend.execute(&format!("PRAGMA user_version = {LATEST_VERSION};"), &[])?;
            Ok(())
        }
        1..=4 => migrate_to_local_schema(backend),
        LATEST_VERSION => Ok(()),
        other => Err(Error::Migration(format!(
            "unsupported schema version {other}"
        ))),
    }
}

fn migrate_to_local_schema<B: Backend>(backend: &B) -> Result<()> {
    backend.execute_batch("PRAGMA foreign_keys = OFF;")?;
    let result = backend.transaction(|tx| {
        tx.execute_batch(
            "CREATE TABLE sessions_v5 (
               session_uuid TEXT PRIMARY KEY NOT NULL,
               title        BLOB NOT NULL,
               created_at   INTEGER NOT NULL,
               updated_at   INTEGER NOT NULL
             );
             CREATE TABLE messages_v5 (
               message_uuid        TEXT PRIMARY KEY NOT NULL,
               session_uuid        TEXT NOT NULL,
               parent_message_uuid TEXT,
               sender              TEXT NOT NULL CHECK(sender IN ('self','other')),
               text                BLOB NOT NULL,
               attachments         TEXT,
               created_at          INTEGER NOT NULL,
               FOREIGN KEY (session_uuid) REFERENCES sessions(session_uuid) ON DELETE CASCADE
             );
             INSERT INTO sessions_v5 (session_uuid, title, created_at, updated_at)
               SELECT session_uuid, title, created_at, updated_at
               FROM sessions
               WHERE deleted_at IS NULL;
             INSERT INTO messages_v5 (
               message_uuid, session_uuid, parent_message_uuid, sender, text, attachments, created_at
             )
               SELECT m.message_uuid, m.session_uuid, m.parent_message_uuid, m.sender,
                      m.text, m.attachments, m.created_at
               FROM messages m
               JOIN sessions s ON s.session_uuid = m.session_uuid
               WHERE m.deleted_at IS NULL AND s.deleted_at IS NULL;
             DROP TABLE messages;
             DROP TABLE sessions;
             ALTER TABLE sessions_v5 RENAME TO sessions;
             ALTER TABLE messages_v5 RENAME TO messages;",
        )?;
        tx.execute_batch(schema::CREATE_INDEXES)?;
        tx.execute(&format!("PRAGMA user_version = {LATEST_VERSION};"), &[])?;
        Ok(())
    });
    let enable_result = backend.execute_batch("PRAGMA foreign_keys = ON;");
    result?;
    enable_result
}

fn user_version<B: Backend>(backend: &B) -> Result<i64> {
    let row = backend
        .query_row("PRAGMA user_version;", &[])?
        .ok_or_else(|| Error::Migration("missing user_version pragma".to_string()))?;
    row.get_i64(0)
}

#[cfg(all(test, feature = "sqlite"))]
mod tests {
    use super::*;
    use crate::db::backend::sqlite::SqliteBackend;
    use crate::db::backend::{BackendTx, RowExt, Value};

    #[test]
    fn creates_schema_and_indexes() {
        let backend = SqliteBackend::open_in_memory().unwrap();
        migrate(&backend).unwrap();

        for table in ["sessions", "messages"] {
            let row = backend
                .query_row(
                    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
                    &[Value::Text(table.to_string())],
                )
                .unwrap();
            assert!(row.is_some(), "missing table {table}");
        }

        for index in ["idx_messages_order", "idx_sessions_updated"] {
            let row = backend
                .query_row(
                    "SELECT name FROM sqlite_master WHERE type = 'index' AND name = ?",
                    &[Value::Text(index.to_string())],
                )
                .unwrap();
            assert!(row.is_some(), "missing index {index}");
        }

        let row = backend.query_row("PRAGMA user_version;", &[]).unwrap();
        let version = row.unwrap().get_i64(0).unwrap();
        assert_eq!(version, LATEST_VERSION);
    }

    #[test]
    fn v1_migrates_directly_to_local_schema() {
        let backend = SqliteBackend::open_in_memory().unwrap();
        backend
            .execute_batch(
                "CREATE TABLE sessions (
                   session_uuid TEXT PRIMARY KEY NOT NULL,
                   title BLOB NOT NULL,
                   created_at INTEGER NOT NULL,
                   updated_at INTEGER NOT NULL,
                   remote_id TEXT UNIQUE,
                   needs_sync INTEGER NOT NULL DEFAULT 1,
                   deleted_at INTEGER
                 );
                 CREATE TABLE messages (
                   message_uuid TEXT PRIMARY KEY NOT NULL,
                   session_uuid TEXT NOT NULL,
                   parent_message_uuid TEXT,
                   sender TEXT NOT NULL,
                   text BLOB NOT NULL,
                   attachments TEXT,
                   created_at INTEGER NOT NULL,
                   deleted_at INTEGER
                 );
                 INSERT INTO sessions VALUES ('session', X'01', 1, 2, NULL, 1, NULL);
                 INSERT INTO messages VALUES ('message', 'session', NULL, 'self', X'02', NULL, 3, NULL);
                 PRAGMA user_version = 1;",
            )
            .unwrap();

        migrate(&backend).unwrap();

        assert!(
            backend
                .query_row("SELECT session_uuid FROM sessions", &[])
                .unwrap()
                .is_some()
        );
        assert!(
            backend
                .query_row("SELECT message_uuid FROM messages", &[])
                .unwrap()
                .is_some()
        );
    }

    #[test]
    fn v4_migration_keeps_only_visible_local_data() {
        let backend = SqliteBackend::open_in_memory().unwrap();
        backend.execute_batch(
            "CREATE TABLE sessions (
               session_uuid TEXT PRIMARY KEY NOT NULL,
               title BLOB NOT NULL,
               created_at INTEGER NOT NULL,
               updated_at INTEGER NOT NULL,
               server_updated_at INTEGER,
               remote_id TEXT UNIQUE,
               needs_sync INTEGER NOT NULL DEFAULT 1,
               deleted_at INTEGER
             );
             CREATE TABLE messages (
               message_uuid TEXT PRIMARY KEY NOT NULL,
               session_uuid TEXT NOT NULL,
               parent_message_uuid TEXT,
               sender TEXT NOT NULL,
               text BLOB NOT NULL,
               attachments TEXT,
               created_at INTEGER NOT NULL,
               remote_id TEXT,
               server_updated_at INTEGER,
               needs_sync INTEGER NOT NULL DEFAULT 1,
               deleted_at INTEGER
             );
             INSERT INTO sessions VALUES ('active', X'01', 1, 2, 3, 'remote-1', 0, NULL);
             INSERT INTO sessions VALUES ('deleted', X'02', 1, 2, NULL, NULL, 1, 4);
             INSERT INTO messages VALUES ('visible', 'active', NULL, 'self', X'03', NULL, 5, NULL, NULL, 1, NULL);
             INSERT INTO messages VALUES ('deleted-message', 'active', NULL, 'other', X'04', NULL, 6, NULL, NULL, 1, 7);
             INSERT INTO messages VALUES ('deleted-session-message', 'deleted', NULL, 'other', X'05', NULL, 8, NULL, NULL, 1, NULL);
             PRAGMA user_version = 4;",
        ).unwrap();

        migrate(&backend).unwrap();

        let sessions = backend
            .query("SELECT session_uuid FROM sessions", &[])
            .unwrap();
        assert_eq!(sessions, vec![vec![Value::Text("active".to_string())]]);
        let messages = backend
            .query("SELECT message_uuid FROM messages", &[])
            .unwrap();
        assert_eq!(messages, vec![vec![Value::Text("visible".to_string())]]);
        assert!(
            backend
                .query_row("SELECT remote_id FROM sessions", &[])
                .is_err()
        );
        assert!(
            backend
                .query("PRAGMA foreign_key_check", &[])
                .unwrap()
                .is_empty()
        );
        backend
            .execute("DELETE FROM sessions WHERE session_uuid = 'active'", &[])
            .unwrap();
        assert!(
            backend
                .query("SELECT * FROM messages", &[])
                .unwrap()
                .is_empty()
        );
    }
}
