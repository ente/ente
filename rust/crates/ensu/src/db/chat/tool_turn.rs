use std::collections::HashMap;

use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::todo::TodoTurnData;
use super::{ChatDb, ConversationSnapshot};
use crate::conversation::{ToolTurnHistory, TurnTools};
use crate::db::backend::{Backend, BackendTx, RowExt, Value};
use crate::db::crypto;
use crate::db::models::{AttachmentMeta, EntityType, Message, Sender};
use crate::db::{Error, Refusal, Result};
use crate::llm::{ToolCall, ToolOutcome};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FinishedReply {
    pub message: Message,
    pub tool_turn: Option<ToolTurnState>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Undo {
    None,
    Available,
    Undone,
    PartlyUndone,
    Stale,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Confirm {
    None,
    Offered,
    Stale,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ToolTurnState {
    pub undo: Undo,
    pub confirm: Confirm,
    pub can_retry: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Offer {
    Pending,
    Withdrawn,
    Confirmed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Undone {
    kept_edits: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(from = "StoredTurn", into = "StoredTurn")]
struct TurnRecord {
    source_id: Uuid,
    calls: Vec<ToolCall>,
    offer: Option<Offer>,
    undone: Option<Undone>,
    todo: TodoTurnData,
}

#[derive(Default, Serialize, Deserialize)]
#[serde(default)]
struct StoredTurn {
    source_id: Uuid,
    calls: Vec<ToolCall>,
    undone: bool,
    confirmed: bool,
    withdrawn: bool,
    kept_edits: bool,
    todo: TodoTurnData,
}

impl From<StoredTurn> for TurnRecord {
    fn from(stored: StoredTurn) -> Self {
        let offer = if stored.todo.proposed.is_empty() {
            None
        } else if stored.confirmed {
            Some(Offer::Confirmed)
        } else if stored.withdrawn {
            Some(Offer::Withdrawn)
        } else {
            Some(Offer::Pending)
        };
        Self {
            source_id: stored.source_id,
            calls: stored.calls,
            offer,
            undone: stored.undone.then_some(Undone {
                kept_edits: stored.kept_edits,
            }),
            todo: stored.todo,
        }
    }
}

impl From<TurnRecord> for StoredTurn {
    fn from(record: TurnRecord) -> Self {
        Self {
            source_id: record.source_id,
            calls: record.calls,
            undone: record.undone.is_some(),
            confirmed: record.offer == Some(Offer::Confirmed),
            withdrawn: record.offer == Some(Offer::Withdrawn),
            kept_edits: record.undone.is_some_and(|undone| undone.kept_edits),
            todo: record.todo,
        }
    }
}

impl TurnRecord {
    fn new(source_id: Uuid, calls: Vec<ToolCall>, todo: TodoTurnData) -> Self {
        Self {
            source_id,
            calls,
            offer: (!todo.proposed.is_empty()).then_some(Offer::Pending),
            undone: None,
            todo,
        }
    }

    fn changed(&self) -> bool {
        !self.todo.changes.is_empty()
    }

    fn pending(&self) -> bool {
        self.offer == Some(Offer::Pending)
    }

    fn live(&self) -> bool {
        self.changed() && self.undone.is_none()
    }
}

fn no_turn(reply: Uuid) -> Error {
    Error::NotFound {
        entity: EntityType::Message,
        id: reply,
    }
}

impl<B: Backend> ChatDb<B> {
    pub fn tool_exchange(
        &self,
        snapshot: &ConversationSnapshot,
        request: crate::llm::ToolRequest,
    ) -> crate::llm::ToolExchange {
        let continuation = crate::todo::continuation::ListContinuation::new(
            snapshot.todos.clone(),
            self.now_ms(),
            request.quote_source.clone(),
        );
        crate::llm::ToolExchange::new(request).with_continuation(continuation)
    }

    pub(crate) fn now_ms(&self) -> i64 {
        self.clock.now_us() / 1000
    }

    pub(super) fn open<T: DeserializeOwned>(&self, blob: &[u8]) -> Result<T> {
        Ok(serde_json::from_slice(&crypto::decrypt_blob(
            blob, &self.key,
        )?)?)
    }

    pub(super) fn seal<T: Serialize>(&self, value: &T) -> Result<Vec<u8>> {
        crypto::encrypt_blob(&serde_json::to_vec(value)?, &self.key)
    }

    pub fn turn_tools(
        &self,
        snapshot: &ConversationSnapshot,
        user_text: &str,
    ) -> Result<TurnTools> {
        let messages = snapshot.messages();
        let (request, applied) = self.request_text(&self.backend, messages, user_text)?;
        Ok(TurnTools {
            tools: (!applied).then(|| self.todo_tools(&snapshot.todos, request)),
            history: self.tool_history(messages)?,
            current_override: (!applied && request != user_text).then(|| request.to_owned()),
        })
    }

    fn request_text<'a, T: BackendTx>(
        &self,
        tx: &T,
        messages: &'a [Message],
        user_text: &'a str,
    ) -> Result<(&'a str, bool)> {
        let mut applied = false;
        let text = crate::todo::request_text(messages, user_text, |reply| {
            let Some(turn) = self.read_turn(tx, reply.uuid)? else {
                return Ok::<_, Error>(false);
            };
            applied |= turn.live() || turn.undone.is_some_and(|undone| undone.kept_edits);
            Ok(true)
        })?;
        Ok((text, applied))
    }

    pub fn finish_reply(
        &self,
        snapshot: &ConversationSnapshot,
        text: &str,
        attachments: Vec<AttachmentMeta>,
        tools: Option<&ToolOutcome>,
    ) -> Result<FinishedReply> {
        self.finish_reply_inner(snapshot, text, attachments, tools, &|_, _| true)
    }

    pub fn finish_exchange(
        &self,
        snapshot: &ConversationSnapshot,
        text: &str,
        attachments: Vec<AttachmentMeta>,
        tools: Option<&crate::llm::ToolExchange>,
    ) -> Result<FinishedReply> {
        let outcome = tools.and_then(crate::llm::ToolExchange::outcome);
        self.finish_reply_inner(
            snapshot,
            text,
            attachments,
            outcome.as_ref(),
            &|outcome, now| {
                tools
                    .and_then(|tools| tools.continuation.as_deref())
                    .is_none_or(|continuation| continuation.can_finish(outcome, now))
            },
        )
    }

    pub(crate) fn finish_reply_inner(
        &self,
        snapshot: &ConversationSnapshot,
        text: &str,
        attachments: Vec<AttachmentMeta>,
        tools: Option<&ToolOutcome>,
        can_finish: &dyn Fn(&ToolOutcome, i64) -> bool,
    ) -> Result<FinishedReply> {
        let user_text = snapshot
            .messages()
            .last()
            .map_or("", |message| message.text.as_str());
        let (_, applied) = self.request_text(&self.backend, snapshot.messages(), user_text)?;
        if applied || tools.is_some_and(|tools| !tools.calls.is_empty()) {
            let finished = self.apply_tool_calls(snapshot, tools, text, can_finish)?;
            self.tools_changed();
            return Ok(finished);
        }
        let message = self.insert_message_guarded(
            snapshot.session_uuid(),
            "other",
            text,
            snapshot.messages().last().map(|message| message.uuid),
            attachments,
            Some(snapshot),
        )?;
        Ok(FinishedReply {
            message,
            tool_turn: None,
        })
    }

    fn apply_tool_calls(
        &self,
        snapshot: &ConversationSnapshot,
        tools: Option<&ToolOutcome>,
        reply_text: &str,
        can_finish: &dyn Fn(&ToolOutcome, i64) -> bool,
    ) -> Result<FinishedReply> {
        let created_at = self.clock.now_us();
        let request = snapshot
            .messages()
            .last()
            .filter(|message| message.sender == Sender::SelfUser)
            .ok_or_else(|| Error::UnsupportedOperation("Tool calls need a user message".into()))?;
        let shown = snapshot
            .messages()
            .iter()
            .rev()
            .find(|message| message.sender == Sender::Other)
            .map(|reply| self.read_turn(&self.backend, reply.uuid))
            .transpose()?
            .flatten()
            .map(|turn| turn.todo.shown)
            .unwrap_or_default();
        self.backend.transaction(|tx| {
            if !super::conversation::snapshot_matches(tx, snapshot, false)? {
                return Err(Error::ConversationChanged);
            }
            if tools.is_some_and(|outcome| !can_finish(outcome, created_at / 1000)) {
                return Err(Error::ConversationChanged);
            }
            for (_, earlier) in self.read_turns_from(tx, request.uuid)? {
                if self.undoable(tx, &earlier)? {
                    return Err(Refusal::EarlierReplyStands.into());
                }
            }
            self.withdraw_offers(tx, request.uuid)?;
            let (user_text, applied) = self.request_text(tx, snapshot.messages(), &request.text)?;
            let (calls, mut text, todo) = if applied {
                (
                    Vec::new(),
                    "That action already succeeded.".to_owned(),
                    TodoTurnData::default(),
                )
            } else {
                self.apply_todo_calls(
                    tx,
                    tools.map_or(&[], |tools| &tools.calls),
                    (&snapshot.todos, user_text),
                    shown,
                    created_at / 1000,
                    tools.and_then(|tools| tools.call_probability),
                )?
            };
            if !calls.is_empty()
                && calls.iter().all(|call| call.name == crate::todo::LIST_TOOL)
                && !reply_text.trim().is_empty()
            {
                text.push_str("\n\n");
                text.push_str(reply_text.trim());
            }
            let record = TurnRecord::new(request.uuid, calls, todo);
            let reply = Message {
                uuid: self.uuid_gen.new_uuid(),
                session_uuid: request.session_uuid,
                parent_message_uuid: Some(request.uuid),
                sender: Sender::Other,
                text,
                attachments: Vec::new(),
                created_at,
            };
            self.write_message(tx, &reply)?;
            self.touch_session_at_least(tx, reply.session_uuid, created_at)?;
            self.write_turn(tx, reply.uuid, &record)?;
            Ok(FinishedReply {
                message: reply,
                tool_turn: Some(self.state(tx, &record)?),
            })
        })
    }

    fn reply_changed<T: BackendTx>(&self, tx: &T, reply: Uuid) -> Result<()> {
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

    pub(super) fn withdraw_offers<T: BackendTx>(&self, tx: &T, source: Uuid) -> Result<bool> {
        let mut withdrew = false;
        for (reply, mut earlier) in self.read_turns_from(tx, source)? {
            if earlier.pending() {
                earlier.offer = Some(Offer::Withdrawn);
                self.write_turn(tx, reply, &earlier)?;
                withdrew = true;
            }
        }
        Ok(withdrew)
    }

    pub fn confirm_tool_turn(&self, reply: Uuid) -> Result<ToolTurnState> {
        let now = self.now_ms();
        let (confirmed, changed) = self.backend.transaction(|tx| {
            let mut record = self.read_turn(tx, reply)?.ok_or_else(|| no_turn(reply))?;
            match record.offer {
                None => return Err(Refusal::NothingOffered.into()),
                Some(Offer::Confirmed) => return Ok((Ok(self.state(tx, &record)?), false)),
                Some(Offer::Withdrawn) => return Ok((Err(Refusal::OfferStale.into()), false)),
                Some(Offer::Pending) => {}
            }
            let stands = self.confirm_todo_offer(tx, &mut record.todo, now)?;
            record.offer = Some(if stands {
                Offer::Confirmed
            } else {
                Offer::Withdrawn
            });
            self.write_turn(tx, reply, &record)?;
            self.reply_changed(tx, reply)?;
            let confirmed = if stands {
                Ok(self.state(tx, &record)?)
            } else {
                Err(Refusal::OfferStale.into())
            };
            Ok((confirmed, true))
        })?;
        if changed {
            self.tools_changed();
        }
        confirmed
    }

    pub fn undo_tool_turn(&self, reply: Uuid) -> Result<ToolTurnState> {
        let now = self.now_ms();
        let (undone, changed) = self.backend.transaction(|tx| {
            let mut record = self.read_turn(tx, reply)?.ok_or_else(|| no_turn(reply))?;
            if record.undone.is_some() {
                return Ok((self.state(tx, &record)?, false));
            }
            if !record.changed() {
                return Err(Refusal::NothingChanged.into());
            }
            let reverted = self.undo_todo_changes(tx, &record.todo, now)?;
            if reverted == 0 {
                return Err(Refusal::UndoStale.into());
            }
            record.undone = Some(Undone {
                kept_edits: reverted < record.todo.changes.len(),
            });
            self.write_turn(tx, reply, &record)?;
            self.reply_changed(tx, reply)?;
            Ok((self.state(tx, &record)?, true))
        })?;
        if changed {
            self.tools_changed();
        }
        Ok(undone)
    }

    fn undoable<T: BackendTx>(&self, tx: &T, record: &TurnRecord) -> Result<bool> {
        Ok(record.live() && self.todo_changes_stand(tx, &record.todo)?)
    }

    fn state<T: BackendTx>(&self, tx: &T, record: &TurnRecord) -> Result<ToolTurnState> {
        let undo = match record.undone {
            _ if !record.changed() => Undo::None,
            Some(Undone { kept_edits: true }) => Undo::PartlyUndone,
            Some(Undone { kept_edits: false }) => Undo::Undone,
            None if self.todo_changes_stand(tx, &record.todo)? => Undo::Available,
            None => Undo::Stale,
        };
        let confirm = match record.offer {
            None | Some(Offer::Confirmed) => Confirm::None,
            Some(Offer::Pending) if self.todo_offer_stands(tx, &record.todo)? => Confirm::Offered,
            Some(Offer::Pending | Offer::Withdrawn) => Confirm::Stale,
        };
        Ok(ToolTurnState {
            undo,
            confirm,
            can_retry: undo != Undo::Available,
        })
    }

    pub fn tool_turn_states(&self, session: Uuid) -> Result<HashMap<Uuid, ToolTurnState>> {
        self.backend
            .query(
                "SELECT t.reply_id, t.record FROM tool_turns t
                 JOIN messages m ON m.message_uuid = t.reply_id
                 WHERE m.session_uuid = ?",
                &[Value::Text(session.to_string())],
            )?
            .iter()
            .map(|row| {
                let record: TurnRecord = self.open(&row.get_blob(1)?)?;
                Ok((
                    Uuid::parse_str(&row.get_string(0)?)?,
                    self.state(&self.backend, &record)?,
                ))
            })
            .collect()
    }

    pub fn tool_history(&self, messages: &[Message]) -> Result<HashMap<Uuid, ToolTurnHistory>> {
        let replies: Vec<_> = messages
            .iter()
            .filter(|message| message.sender == Sender::Other)
            .map(|message| message.uuid)
            .collect();
        Ok(self
            .read_turns(&replies)?
            .into_iter()
            .map(|(reply, record)| {
                let history = ToolTurnHistory {
                    proposal: record.offer.map(|offer| offer == Offer::Confirmed),
                    undone: record.undone.is_some(),
                    kept_edits: record.undone.is_some_and(|undone| undone.kept_edits),
                    calls: record.calls,
                    responses: record.todo.responses,
                };
                (reply, history)
            })
            .collect())
    }

    fn read_turn<T: BackendTx>(&self, tx: &T, reply: Uuid) -> Result<Option<TurnRecord>> {
        tx.query_row(
            "SELECT record FROM tool_turns WHERE reply_id = ?",
            &[Value::Text(reply.to_string())],
        )?
        .map(|row| self.open(&row.get_blob(0)?))
        .transpose()
    }

    fn write_turn<T: BackendTx>(&self, tx: &T, reply: Uuid, record: &TurnRecord) -> Result<()> {
        tx.execute(
            "INSERT INTO tool_turns (reply_id, source_id, record) VALUES (?, ?, ?)
             ON CONFLICT(reply_id) DO UPDATE SET record = excluded.record",
            &[
                Value::Text(reply.to_string()),
                Value::Text(record.source_id.to_string()),
                Value::Blob(self.seal(record)?),
            ],
        )?;
        Ok(())
    }

    fn read_turns(&self, replies: &[Uuid]) -> Result<HashMap<Uuid, TurnRecord>> {
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

    fn read_turns_from<T: BackendTx>(
        &self,
        tx: &T,
        source: Uuid,
    ) -> Result<Vec<(Uuid, TurnRecord)>> {
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::todo::TodoChange;

    #[test]
    fn stored_turns_keep_their_format_and_read_into_one_state() {
        let stored = |json: &str| serde_json::from_str::<TurnRecord>(json).unwrap();
        let plain = stored(r#"{"undone":true,"kept_edits":true,"confirmed":true}"#);
        assert_eq!(plain.offer, None);
        assert_eq!(plain.undone, Some(Undone { kept_edits: true }));
        let change = TodoChange {
            before: None,
            after: None,
        };
        for offer in [Offer::Pending, Offer::Withdrawn, Offer::Confirmed] {
            for undone in [None, Some(Undone { kept_edits: false })] {
                let mut record = TurnRecord::new(Uuid::nil(), Vec::new(), TodoTurnData::default());
                record.todo.proposed.push(change.clone());
                record.offer = Some(offer);
                record.undone = undone;
                let json = serde_json::to_string(&record).unwrap();
                let read = stored(&json);
                assert_eq!((read.offer, read.undone), (Some(offer), undone), "{json}");
            }
        }
        let both = stored(
            r#"{"confirmed":true,"withdrawn":true,"todo":{"proposed":[{"before":null,"after":null}]}}"#,
        );
        assert_eq!(both.offer, Some(Offer::Confirmed));
    }
}
