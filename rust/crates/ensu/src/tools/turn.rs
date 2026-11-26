use crate::todo::Refusal;
use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::conversation::{ToolTurnHistory, TurnTools};
use crate::db::backend::{Backend, BackendTx};
use crate::db::chat::ConversationSnapshot;
use crate::db::models::{AttachmentMeta, EntityType, Message, Sender};
use crate::db::{ChatDb, Error, Result};
use crate::llm::{ToolCall, ToolOutcome};
use crate::todo::tool::{self, TodoTurnData};

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

pub(crate) fn turn_tools<B: Backend>(
    db: &ChatDb<B>,
    snapshot: &ConversationSnapshot,
    user_text: &str,
    zone: &impl chrono::TimeZone,
) -> Result<TurnTools> {
    let messages = snapshot.messages();
    let (request, applied) = request_text(db, db.reader(), messages, user_text)?;
    Ok(TurnTools {
        tools: (!applied).then(|| tool::request(db, snapshot.todos(), request, zone)),
        history: history(db, messages)?,
        current_override: (!applied && request != user_text).then(|| request.to_owned()),
    })
}

fn request_text<'a, B: Backend, T: BackendTx>(
    db: &ChatDb<B>,
    tx: &T,
    messages: &'a [Message],
    user_text: &'a str,
) -> Result<(&'a str, bool)> {
    let mut applied = false;
    let text = crate::todo::request_text(messages, user_text, |reply| {
        let Some(turn) = db.turn::<_, TurnRecord>(tx, reply.uuid)? else {
            return Ok::<_, Error>(false);
        };
        applied |= turn.live() || turn.undone.is_some_and(|undone| undone.kept_edits);
        Ok(true)
    })?;
    Ok((text, applied))
}

pub fn finish_reply<B: Backend>(
    db: &ChatDb<B>,
    snapshot: &ConversationSnapshot,
    text: &str,
    attachments: Vec<AttachmentMeta>,
    tools: Option<&ToolOutcome>,
    zone: &impl chrono::TimeZone,
) -> Result<FinishedReply> {
    finish_reply_inner(db, snapshot, text, attachments, tools, &|_, _| true, zone)
}

pub(crate) fn finish_reply_inner<B: Backend>(
    db: &ChatDb<B>,
    snapshot: &ConversationSnapshot,
    text: &str,
    attachments: Vec<AttachmentMeta>,
    tools: Option<&ToolOutcome>,
    can_finish: &dyn Fn(&ToolOutcome, i64) -> bool,
    zone: &impl chrono::TimeZone,
) -> Result<FinishedReply> {
    let user_text = snapshot
        .messages()
        .last()
        .map_or("", |message| message.text.as_str());
    let (_, applied) = request_text(db, db.reader(), snapshot.messages(), user_text)?;
    if applied || tools.is_some_and(|tools| !tools.calls.is_empty()) {
        let finished = apply_tool_calls(db, snapshot, tools, text, can_finish, zone)?;
        db.tools_changed();
        return Ok(finished);
    }
    let message = db.insert_message_guarded(
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

fn apply_tool_calls<B: Backend>(
    db: &ChatDb<B>,
    snapshot: &ConversationSnapshot,
    tools: Option<&ToolOutcome>,
    reply_text: &str,
    can_finish: &dyn Fn(&ToolOutcome, i64) -> bool,
    zone: &impl chrono::TimeZone,
) -> Result<FinishedReply> {
    let created_at = db.now_us();
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
        .map(|reply| db.turn::<_, TurnRecord>(db.reader(), reply.uuid))
        .transpose()?
        .flatten()
        .map(|turn| turn.todo.shown)
        .unwrap_or_default();
    let (message, state) = db.commit_tool_turn(snapshot, request, created_at, |tx| {
        if tools.is_some_and(|outcome| !can_finish(outcome, created_at / 1000)) {
            return Err(Error::ConversationChanged);
        }
        for (_, earlier) in db.turns_by_source::<_, TurnRecord>(tx, request.uuid)? {
            if undoable(db, tx, &earlier)? {
                return Err(Refusal::EarlierReplyStands.into());
            }
        }
        withdraw_offers(db, tx, request.uuid)?;
        let (user_text, applied) = request_text(db, tx, snapshot.messages(), &request.text)?;
        let (calls, mut text, todo) = if applied {
            (
                Vec::new(),
                "That action already succeeded.".to_owned(),
                TodoTurnData::default(),
            )
        } else {
            tool::apply(
                db,
                tx,
                tools.map_or(&[], |tools| &tools.calls),
                (snapshot.todos(), user_text),
                shown,
                (created_at / 1000, zone),
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
        let state = state(db, tx, &record)?;
        Ok((text, record, state))
    })?;
    Ok(FinishedReply {
        message,
        tool_turn: Some(state),
    })
}

pub(crate) fn withdraw_offers<B: Backend, T: BackendTx>(
    db: &ChatDb<B>,
    tx: &T,
    source: Uuid,
) -> Result<bool> {
    let mut withdrew = false;
    for (reply, mut earlier) in db.turns_by_source::<_, TurnRecord>(tx, source)? {
        if earlier.pending() {
            earlier.offer = Some(Offer::Withdrawn);
            db.put_turn(tx, reply, earlier.source_id, &earlier)?;
            withdrew = true;
        }
    }
    Ok(withdrew)
}

pub fn confirm<B: Backend>(db: &ChatDb<B>, reply: Uuid) -> Result<ToolTurnState> {
    let now = db.now_ms();
    let (confirmed, changed) = db.transaction(|tx| {
        let mut record = db
            .turn::<_, TurnRecord>(tx, reply)?
            .ok_or_else(|| no_turn(reply))?;
        match record.offer {
            None => return Err(Refusal::NothingOffered.into()),
            Some(Offer::Confirmed) => return Ok((Ok(state(db, tx, &record)?), false)),
            Some(Offer::Withdrawn) => return Ok((Err(Refusal::OfferStale.into()), false)),
            Some(Offer::Pending) => {}
        }
        let stands = tool::confirm(db, tx, &mut record.todo, now)?;
        record.offer = Some(if stands {
            Offer::Confirmed
        } else {
            Offer::Withdrawn
        });
        db.put_turn(tx, reply, record.source_id, &record)?;
        db.reply_edited(tx, reply)?;
        let confirmed = if stands {
            Ok(state(db, tx, &record)?)
        } else {
            Err(Refusal::OfferStale.into())
        };
        Ok((confirmed, true))
    })?;
    if changed {
        db.tools_changed();
    }
    confirmed
}

pub fn undo<B: Backend>(db: &ChatDb<B>, reply: Uuid) -> Result<ToolTurnState> {
    let now = db.now_ms();
    let (undone, changed) = db.transaction(|tx| {
        let mut record = db
            .turn::<_, TurnRecord>(tx, reply)?
            .ok_or_else(|| no_turn(reply))?;
        if record.undone.is_some() {
            return Ok((state(db, tx, &record)?, false));
        }
        if !record.changed() {
            return Err(Refusal::NothingChanged.into());
        }
        let reverted = tool::undo(db, tx, &record.todo, now)?;
        if reverted == 0 {
            return Err(Refusal::UndoStale.into());
        }
        record.undone = Some(Undone {
            kept_edits: reverted < record.todo.changes.len(),
        });
        db.put_turn(tx, reply, record.source_id, &record)?;
        db.reply_edited(tx, reply)?;
        Ok((state(db, tx, &record)?, true))
    })?;
    if changed {
        db.tools_changed();
    }
    Ok(undone)
}

fn undoable<B: Backend, T: BackendTx>(db: &ChatDb<B>, tx: &T, record: &TurnRecord) -> Result<bool> {
    Ok(record.live() && tool::changes_stand(db, tx, &record.todo)?)
}

fn state<B: Backend, T: BackendTx>(
    db: &ChatDb<B>,
    tx: &T,
    record: &TurnRecord,
) -> Result<ToolTurnState> {
    let undo = match record.undone {
        _ if !record.changed() => Undo::None,
        Some(Undone { kept_edits: true }) => Undo::PartlyUndone,
        Some(Undone { kept_edits: false }) => Undo::Undone,
        None if tool::changes_stand(db, tx, &record.todo)? => Undo::Available,
        None => Undo::Stale,
    };
    let confirm = match record.offer {
        None | Some(Offer::Confirmed) => Confirm::None,
        Some(Offer::Pending) if tool::offer_stands(db, tx, &record.todo)? => Confirm::Offered,
        Some(Offer::Pending | Offer::Withdrawn) => Confirm::Stale,
    };
    Ok(ToolTurnState {
        undo,
        confirm,
        can_retry: undo != Undo::Available,
    })
}

pub fn states<B: Backend>(db: &ChatDb<B>, session: Uuid) -> Result<HashMap<Uuid, ToolTurnState>> {
    db.session_turns::<TurnRecord>(session)?
        .into_iter()
        .map(|(reply, record)| Ok((reply, state(db, db.reader(), &record)?)))
        .collect()
}

pub fn history<B: Backend>(
    db: &ChatDb<B>,
    messages: &[Message],
) -> Result<HashMap<Uuid, ToolTurnHistory>> {
    let replies: Vec<_> = messages
        .iter()
        .filter(|message| message.sender == Sender::Other)
        .map(|message| message.uuid)
        .collect();
    Ok(db
        .turns_for::<TurnRecord>(&replies)?
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

#[cfg(test)]
#[cfg(feature = "sqlite")]
#[path = "turn_tests.rs"]
mod turn_tests;
