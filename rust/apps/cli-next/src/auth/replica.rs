use anyhow::{Context, Result, ensure};
use ente_auth::{WrappedKey, record};
use ente_core::Session;
use zeroize::Zeroizing;

use crate::core_db::{Db, OptionalExtension, params};

pub const SCHEMA: &str = "
    CREATE TABLE auth_sync (
        id INTEGER PRIMARY KEY CHECK(id=1), encrypted_key TEXT, key_header TEXT,
        cursor INTEGER NOT NULL, complete INTEGER NOT NULL
    );
    CREATE TABLE auth_entities (
        id TEXT PRIMARY KEY, updated_at INTEGER NOT NULL, encrypted_data TEXT, header TEXT
    );
";

struct Sync {
    key: Option<WrappedKey>,
    cursor: i64,
    complete: bool,
}

pub struct Payload {
    pub bytes: Zeroizing<Vec<u8>>,
    pub records: usize,
    pub failed: usize,
    pub failed_ids: Vec<String>,
}

fn sync_state(db: &Db) -> Result<Option<Sync>> {
    Ok(db.read(|db| {
        Ok(db
            .query_row(
                "SELECT encrypted_key, key_header, cursor, complete FROM auth_sync WHERE id=1",
                [],
                |row| {
                    let encrypted_key: Option<String> = row.get(0)?;
                    let key = encrypted_key
                        .map(|encrypted_key| {
                            Ok::<_, crate::core_db::SqliteError>(WrappedKey {
                                encrypted_key,
                                header: row.get(1)?,
                            })
                        })
                        .transpose()?;
                    Ok(Sync {
                        key,
                        cursor: row.get(2)?,
                        complete: row.get(3)?,
                    })
                },
            )
            .optional()?)
    })?)
}

pub async fn refresh(db: &mut Db, session: &Session) -> Result<()> {
    let key = ente_auth::fetch_key(session).await?;
    let saved = sync_state(db)?;
    let reset = saved.as_ref().is_none_or(|saved| saved.key != key);
    let mut cursor = saved.as_ref().map_or(0, |saved| saved.cursor);
    if reset {
        db.write(|tx| {
            tx.execute("DELETE FROM auth_entities", [])?;
            tx.execute(
                "INSERT INTO auth_sync(id, encrypted_key, key_header, cursor, complete)
                 VALUES(1, ?1, ?2, 0, ?3)
                 ON CONFLICT(id) DO UPDATE SET encrypted_key=excluded.encrypted_key,
                     key_header=excluded.key_header, cursor=0, complete=excluded.complete",
                params![
                    key.as_ref().map(|key| &key.encrypted_key),
                    key.as_ref().map(|key| &key.header),
                    key.is_none()
                ],
            )?;
            Ok(())
        })?;
        cursor = 0;
    }
    if key.is_none() {
        return Ok(());
    }
    loop {
        let page = ente_auth::diff(session, cursor).await?;
        let complete = page.len() < ente_auth::PAGE_SIZE;
        let next = page
            .last()
            .map_or(cursor, |entity| entity.updated_at.saturating_sub(1).max(0));
        db.write(|tx| {
            let mut upsert = tx.prepare_cached(
                "INSERT INTO auth_entities(id, updated_at, encrypted_data, header) VALUES(?1, ?2, ?3, ?4)
                 ON CONFLICT(id) DO UPDATE SET updated_at=excluded.updated_at,
                     encrypted_data=excluded.encrypted_data, header=excluded.header",
            )?;
            let mut delete = tx.prepare_cached("DELETE FROM auth_entities WHERE id=?1")?;
            for entity in &page {
                let id = entity.id.to_string();
                if entity.is_deleted {
                    delete.execute([&id])?;
                } else {
                    upsert.execute(params![id, entity.updated_at, entity.encrypted_data, entity.header])?;
                }
            }
            tx.execute(
                "UPDATE auth_sync SET cursor=?1, complete=?2 WHERE id=1",
                params![next, complete],
            )?;
            Ok(())
        })?;
        if complete {
            return Ok(());
        }
        ensure!(
            next > cursor,
            "Auth diff timestamp boundary did not advance; no new backup was written"
        );
        cursor = next;
    }
}

pub fn read_payload(db: &Db, session: &Session) -> Result<Payload> {
    let state = sync_state(db)?.context("no local Auth data; run export online first")?;
    ensure!(
        state.complete,
        "Auth refresh is incomplete; run export online first"
    );
    let mut payload = Payload {
        bytes: Zeroizing::new(Vec::new()),
        records: 0,
        failed: 0,
        failed_ids: Vec::new(),
    };
    let Some(wrapped) = state.key else {
        return Ok(payload);
    };
    let key = ente_auth::open_key(&wrapped, &session.master_key)?;
    db.read(|db| {
        let mut statement =
            db.prepare("SELECT id, encrypted_data, header FROM auth_entities ORDER BY id")?;
        let mut rows = statement.query([])?;
        while let Some(row) = rows.next()? {
            let id: String = row.get(0)?;
            let encrypted_data: Option<String> = row.get(1)?;
            let header: Option<String> = row.get(2)?;
            match record::uri_line(encrypted_data.as_deref(), header.as_deref(), &key) {
                Ok(line) => {
                    payload.bytes.extend_from_slice(line.as_bytes());
                    payload.records += 1;
                }
                Err(_) => {
                    payload.failed += 1;
                    if payload.failed_ids.len() < 10 {
                        payload.failed_ids.push(id);
                    }
                }
            }
        }
        Ok(())
    })?;
    Ok(payload)
}
