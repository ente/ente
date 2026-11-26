use std::collections::HashMap;

use serde::Serialize;
use serde::de::DeserializeOwned;
use uuid::Uuid;

use super::{ChatDb, ConversationSnapshot};
use crate::db::backend::{Backend, BackendTx, RowExt, Value};
use crate::db::crypto;
use crate::db::models::{Message, Sender};
use crate::db::{Error, Result};

impl<B: Backend> ChatDb<B> {
    pub(crate) fn now_ms(&self) -> i64 {
        self.now_us() / 1000
    }

    pub(super) fn open<T: DeserializeOwned>(&self, blob: &[u8]) -> Result<T> {
        Ok(serde_json::from_slice(&crypto::decrypt_blob(
            blob, &self.key,
        )?)?)
    }

    pub(super) fn seal<T: Serialize>(&self, value: &T) -> Result<Vec<u8>> {
        crypto::encrypt_blob(&serde_json::to_vec(value)?, &self.key)
    }

    pub(crate) fn commit_tool_turn<R: Serialize, S>(
        &self,
        snapshot: &ConversationSnapshot,
        request: &Message,
        created_at: i64,
        decide: impl for<'a> FnOnce(&B::Tx<'a>) -> Result<(String, R, S)>,
    ) -> Result<(Message, S)> {
        self.transaction(|tx| {
            if !super::conversation::snapshot_matches(tx, snapshot, false)? {
                return Err(Error::ConversationChanged);
            }
            let (text, record, state) = decide(tx)?;
            let reply = Message {
                uuid: self.new_uuid(),
                session_uuid: request.session_uuid,
                parent_message_uuid: Some(request.uuid),
                sender: Sender::Other,
                text,
                attachments: Vec::new(),
                created_at,
            };
            self.write_message(tx, &reply)?;
            self.touch_session_at_least(tx, reply.session_uuid, created_at)?;
            self.put_turn(tx, reply.uuid, request.uuid, &record)?;
            Ok((reply, state))
        })
    }

    pub(crate) fn reply_edited<T: BackendTx>(&self, tx: &T, reply: Uuid) -> Result<()> {
        let row = tx.query_row(
            "SELECT session_uuid FROM messages WHERE message_uuid = ?",
            &[Value::Text(reply.to_string())],
        )?;
        match row {
            Some(row) => self.invalidate_conversation_for_edit(
                tx,
                Uuid::parse_str(&row.get_string(0)?)?,
                reply,
            ),
            None => Ok(()),
        }
    }

    pub(crate) fn session_turns<R: DeserializeOwned>(
        &self,
        session: Uuid,
    ) -> Result<Vec<(Uuid, R)>> {
        self.reader()
            .query(
                "SELECT t.reply_id, t.record FROM tool_turns t
                 JOIN messages m ON m.message_uuid = t.reply_id
                 WHERE m.session_uuid = ?",
                &[Value::Text(session.to_string())],
            )?
            .iter()
            .map(|row| {
                Ok((
                    Uuid::parse_str(&row.get_string(0)?)?,
                    self.open(&row.get_blob(1)?)?,
                ))
            })
            .collect()
    }

    pub(crate) fn turn<T: BackendTx, R: DeserializeOwned>(
        &self,
        tx: &T,
        reply: Uuid,
    ) -> Result<Option<R>> {
        tx.query_row(
            "SELECT record FROM tool_turns WHERE reply_id = ?",
            &[Value::Text(reply.to_string())],
        )?
        .map(|row| self.open(&row.get_blob(0)?))
        .transpose()
    }

    pub(crate) fn put_turn<T: BackendTx, R: Serialize>(
        &self,
        tx: &T,
        reply: Uuid,
        source: Uuid,
        record: &R,
    ) -> Result<()> {
        tx.execute(
            "INSERT INTO tool_turns (reply_id, source_id, record) VALUES (?, ?, ?)
             ON CONFLICT(reply_id) DO UPDATE SET record = excluded.record",
            &[
                Value::Text(reply.to_string()),
                Value::Text(source.to_string()),
                Value::Blob(self.seal(record)?),
            ],
        )?;
        Ok(())
    }

    pub(crate) fn turns_for<R: DeserializeOwned>(
        &self,
        replies: &[Uuid],
    ) -> Result<HashMap<Uuid, R>> {
        let mut turns = HashMap::new();
        for batch in replies.chunks(super::conversation::MESSAGE_QUERY_BATCH_SIZE) {
            let placeholders = vec!["?"; batch.len()].join(", ");
            let ids: Vec<_> = batch.iter().map(|id| Value::Text(id.to_string())).collect();
            for row in self.backend.query(
                &format!(
                    "SELECT reply_id, record FROM tool_turns WHERE reply_id IN ({placeholders})"
                ),
                &ids,
            )? {
                turns.insert(
                    Uuid::parse_str(&row.get_string(0)?)?,
                    self.open(&row.get_blob(1)?)?,
                );
            }
        }
        Ok(turns)
    }

    pub(crate) fn turns_by_source<T: BackendTx, R: DeserializeOwned>(
        &self,
        tx: &T,
        source: Uuid,
    ) -> Result<Vec<(Uuid, R)>> {
        tx.query(
            "SELECT reply_id, record FROM tool_turns WHERE source_id = ?",
            &[Value::Text(source.to_string())],
        )?
        .iter()
        .map(|row| {
            Ok((
                Uuid::parse_str(&row.get_string(0)?)?,
                self.open(&row.get_blob(1)?)?,
            ))
        })
        .collect()
    }
}
