//! Encrypted storage for the To Do list and the chat turns that changed it.

use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::{ChatDb, ensure_row_updated, optional_uuid};
use crate::conversation::ToolTurnHistory;
use crate::db::backend::{Backend, BackendTx, RowExt, Value};
use crate::db::crypto;
use crate::db::models::{EntityType, Message, Sender};
use crate::db::{Error, Result};
use crate::llm::{ToolCall, ToolRequest};
use crate::todo::{
    self, COMPLETE_TOOL, LIST_LIMIT, LIST_TOOL, ListFilter, SAVE_TOOL, Todo, TodoAlarm, TodoChange,
    timing,
};

/// What a chat turn did to the To Do list.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TodoTurn {
    /// The assistant reply saved for the turn.
    pub reply: Message,
    pub changes: Vec<TodoChange>,
    /// Changes the reply offers (new tasks, completions), made only once the
    /// user confirms them with [`ChatDb::confirm_todo_turn`].
    pub proposed: Vec<TodoChange>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
struct TurnRecord {
    source_id: Uuid,
    calls: Vec<ToolCall>,
    changes: Vec<TodoChange>,
    /// Task ids in the order the reply numbered them.
    shown: Vec<Uuid>,
    undone: bool,
    /// Changes offered for confirmation instead of made.
    proposed: Vec<TodoChange>,
    /// True once the user confirmed the proposed changes.
    confirmed: bool,
}

/// A To Do turn's state, for showing its Add or Undo control.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TodoTurnState {
    pub changed: bool,
    pub undone: bool,
    /// The reply offers tasks the user hasn't added yet.
    pub pending: bool,
}

fn conflict() -> Error {
    Error::UnsupportedOperation("This To Do changed. Refresh and try again.".into())
}

fn not_found(id: Uuid) -> Error {
    Error::NotFound {
        entity: EntityType::Todo,
        id,
    }
}

impl<B: Backend> ChatDb<B> {
    fn now_ms(&self) -> i64 {
        self.clock.now_us() / 1000
    }

    fn read_todo<T: BackendTx>(&self, tx: &T, id: Uuid) -> Result<Option<Todo>> {
        tx.query_row(
            "SELECT record FROM todos WHERE todo_id = ?",
            &[Value::Text(id.to_string())],
        )?
        .map(|row| {
            Ok(serde_json::from_slice(&crypto::decrypt_blob(
                &row.get_blob(0)?,
                &self.key,
            )?)?)
        })
        .transpose()
    }

    fn read_todos<T: BackendTx>(&self, tx: &T) -> Result<Vec<Todo>> {
        tx.query("SELECT record FROM todos ORDER BY created_at, rowid", &[])?
            .into_iter()
            .map(|row| {
                Ok(serde_json::from_slice(&crypto::decrypt_blob(
                    &row.get_blob(0)?,
                    &self.key,
                )?)?)
            })
            .collect()
    }

    fn write_todo<T: BackendTx>(&self, tx: &T, todo: &Todo) -> Result<()> {
        tx.execute(
            "INSERT INTO todos (todo_id, record, created_at) VALUES (?, ?, ?)
             ON CONFLICT(todo_id) DO UPDATE SET record = excluded.record",
            &[
                Value::Text(todo.id.to_string()),
                Value::Blob(crypto::encrypt_blob(&serde_json::to_vec(todo)?, &self.key)?),
                Value::Integer(todo.created_at_ms),
            ],
        )?;
        Ok(())
    }

    fn remove_todo<T: BackendTx>(&self, tx: &T, id: Uuid) -> Result<()> {
        let affected = tx.execute(
            "DELETE FROM todos WHERE todo_id = ?",
            &[Value::Text(id.to_string())],
        )?;
        if affected == 1 {
            Ok(())
        } else {
            Err(not_found(id))
        }
    }

    fn new_todo(&self, title: String, due_at_ms: Option<i64>, now_ms: i64) -> Todo {
        Todo {
            id: self.uuid_gen.new_uuid(),
            title,
            due_at_ms,
            completed_at_ms: None,
            created_at_ms: now_ms,
            updated_at_ms: now_ms,
            version: 1,
        }
    }

    /// Loads `id` and checks it still has `version`.
    fn current<T: BackendTx>(&self, tx: &T, id: Uuid, version: u64) -> Result<Todo> {
        let todo = self.read_todo(tx, id)?.ok_or_else(|| not_found(id))?;
        if todo.version != version {
            return Err(conflict());
        }
        Ok(todo)
    }

    fn changed(before: &Todo, now_ms: i64, change: impl FnOnce(&mut Todo)) -> Todo {
        let mut after = before.clone();
        change(&mut after);
        after.version = before.version + 1;
        after.updated_at_ms = now_ms;
        after
    }

    pub fn list_todos(&self) -> Result<Vec<Todo>> {
        self.read_todos(&self.backend)
    }

    /// The To Do tools for a chat turn answering `user_text`, naming the open
    /// tasks in list order so the model can mark them done.
    pub fn todo_chat_tools(&self, user_text: &str) -> Result<ToolRequest> {
        let todos = self.list_todos()?;
        let open = todo::select_tasks(&todos, ListFilter::Open, None, self.now_ms());
        let titles: Vec<&str> = open.iter().map(|todo| todo.title.as_str()).collect();
        Ok(todo::chat_tools(user_text, &titles))
    }

    pub fn get_todo(&self, id: Uuid) -> Result<Option<Todo>> {
        self.read_todo(&self.backend, id)
    }

    pub fn create_todo(&self, title: &str, due_at_ms: Option<i64>) -> Result<Todo> {
        let title = todo::clean_title(title)
            .ok_or_else(|| Error::UnsupportedOperation("A To Do needs a title".into()))?;
        let todo = self.new_todo(title, due_at_ms, self.now_ms());
        self.write_todo(&self.backend, &todo)?;
        Ok(todo)
    }

    pub fn update_todo(
        &self,
        id: Uuid,
        version: u64,
        title: &str,
        due_at_ms: Option<i64>,
    ) -> Result<Todo> {
        let title = todo::clean_title(title)
            .ok_or_else(|| Error::UnsupportedOperation("A To Do needs a title".into()))?;
        let now = self.now_ms();
        self.backend.transaction(|tx| {
            let before = self.current(tx, id, version)?;
            let after = Self::changed(&before, now, |todo| {
                todo.title = title;
                todo.due_at_ms = due_at_ms;
            });
            self.write_todo(tx, &after)?;
            Ok(after)
        })
    }

    pub fn set_todo_completed(&self, id: Uuid, version: u64, completed: bool) -> Result<Todo> {
        let now = self.now_ms();
        self.backend.transaction(|tx| {
            let before = self.current(tx, id, version)?;
            if before.is_open() != completed {
                return Ok(before);
            }
            let after = Self::changed(&before, now, |todo| {
                todo.completed_at_ms = completed.then_some(now);
            });
            self.write_todo(tx, &after)?;
            Ok(after)
        })
    }

    pub fn delete_todo(&self, id: Uuid, version: u64) -> Result<()> {
        self.backend.transaction(|tx| {
            self.current(tx, id, version)?;
            self.remove_todo(tx, id)
        })
    }

    /// Reminders for the earliest open tasks due after `now_ms`.
    pub fn todo_alarms(&self, now_ms: i64, limit: usize) -> Result<Vec<TodoAlarm>> {
        let mut alarms: Vec<_> = self
            .list_todos()?
            .into_iter()
            .filter(Todo::is_open)
            .filter_map(|todo| {
                let due = todo.due_at_ms.filter(|due| *due > now_ms)?;
                Some(TodoAlarm {
                    key: format!("{}:{due}:{}", todo.id, todo.version),
                    todo_id: todo.id,
                    title: todo.title,
                    due_at_ms: due,
                })
            })
            .collect();
        alarms.sort_by_key(|alarm| (alarm.due_at_ms, alarm.todo_id));
        alarms.truncate(limit);
        Ok(alarms)
    }

    fn read_turn<T: BackendTx>(&self, tx: &T, reply: Uuid) -> Result<Option<TurnRecord>> {
        tx.query_row(
            "SELECT record FROM todo_turns WHERE reply_id = ?",
            &[Value::Text(reply.to_string())],
        )?
        .map(|row| {
            Ok(serde_json::from_slice(&crypto::decrypt_blob(
                &row.get_blob(0)?,
                &self.key,
            )?)?)
        })
        .transpose()
    }

    fn write_turn<T: BackendTx>(&self, tx: &T, reply: Uuid, record: &TurnRecord) -> Result<()> {
        tx.execute(
            "INSERT INTO todo_turns (reply_id, source_id, record) VALUES (?, ?, ?)
             ON CONFLICT(reply_id) DO UPDATE SET record = excluded.record",
            &[
                Value::Text(reply.to_string()),
                Value::Text(record.source_id.to_string()),
                Value::Blob(crypto::encrypt_blob(
                    &serde_json::to_vec(record)?,
                    &self.key,
                )?),
            ],
        )?;
        Ok(())
    }

    fn message_in<T: BackendTx>(&self, tx: &T, id: Uuid) -> Result<Message> {
        let row = tx
            .query_row(
                "SELECT message_uuid, session_uuid, parent_message_uuid, sender,
                        text, attachments, created_at
                 FROM messages WHERE message_uuid = ?",
                &[Value::Text(id.to_string())],
            )?
            .ok_or(Error::NotFound {
                entity: EntityType::Message,
                id,
            })?;
        self.message_from_row(&row)
    }

    /// Applies the model's calls for the user message `source` and saves the
    /// receipt as the assistant reply, all in one transaction.
    /// `call_probability` is the model's confidence in the calls; below
    /// [`todo::DIRECT_CALL_PROBABILITY`], saves and completions are offered
    /// for confirmation instead of made.
    pub fn apply_todo_calls(
        &self,
        source: Uuid,
        calls: &[ToolCall],
        now_ms: i64,
        call_probability: Option<f32>,
    ) -> Result<TodoTurn> {
        let propose = todo::confirm_changes(call_probability);
        let created_at = self.clock.now_us();
        let reply_id = self.uuid_gen.new_uuid();
        self.backend.transaction(|tx| {
            let request = self.message_in(tx, source)?;
            if request.sender != Sender::SelfUser {
                return Err(Error::UnsupportedOperation(
                    "To Do calls need a user message".into(),
                ));
            }
            if tx
                .query_row(
                    "SELECT 1 FROM todo_turns WHERE source_id = ?",
                    &[Value::Text(source.to_string())],
                )?
                .is_some()
            {
                return Err(Error::UnsupportedOperation(
                    "This request was already handled".into(),
                ));
            }
            let shown = match request.parent_message_uuid {
                Some(parent) => self
                    .read_turn(tx, parent)?
                    .map(|turn| turn.shown)
                    .unwrap_or_default(),
                None => Vec::new(),
            };
            let calls = match timing::local_time(now_ms) {
                Some(now) => todo::refine_calls(calls, &request.text, shown.len(), now),
                None => calls.to_vec(),
            };
            let mut todos = self.read_todos(tx)?;
            let mut record = TurnRecord {
                source_id: source,
                calls: calls.clone(),
                ..Default::default()
            };
            let mut lines = Vec::new();
            for call in &calls {
                let mut outcome = self.apply_call(call, &mut todos, &shown, now_ms, propose)?;
                if propose {
                    // Offered, not made: put the list back as it was.
                    for change in std::mem::take(&mut outcome.changes) {
                        match (&change.before, &change.after) {
                            (Some(before), _) => {
                                if let Some(stored) =
                                    todos.iter_mut().find(|stored| stored.id == before.id)
                                {
                                    *stored = before.clone();
                                }
                            }
                            (None, Some(after)) => todos.retain(|stored| stored.id != after.id),
                            (None, None) => {}
                        }
                        record.proposed.push(change);
                    }
                }
                for change in &outcome.changes {
                    match &change.after {
                        Some(after) => self.write_todo(tx, after)?,
                        None => {
                            if let Some(before) = &change.before {
                                self.remove_todo(tx, before.id)?;
                            }
                        }
                    }
                }
                record.changes.extend(outcome.changes);
                if !outcome.shown.is_empty() {
                    record.shown = outcome.shown;
                }
                lines.push(outcome.text);
            }
            let reply = Message {
                uuid: reply_id,
                session_uuid: request.session_uuid,
                parent_message_uuid: Some(source),
                sender: Sender::Other,
                text: lines.join("\n"),
                attachments: Vec::new(),
                created_at,
            };
            let inserted = tx.execute(
                "INSERT INTO messages (
                   message_uuid, session_uuid, parent_message_uuid, sender,
                   text, attachments, created_at
                 ) VALUES (?, ?, ?, ?, ?, NULL, ?)",
                &[
                    Value::Text(reply.uuid.to_string()),
                    Value::Text(reply.session_uuid.to_string()),
                    optional_uuid(reply.parent_message_uuid),
                    Value::Text(Sender::Other.as_str().into()),
                    Value::Blob(crypto::encrypt_string(&reply.text, &self.key)?),
                    Value::Integer(created_at),
                ],
            )?;
            ensure_row_updated(inserted, EntityType::Message, reply.uuid)?;
            self.touch_session_at_least(tx, reply.session_uuid, created_at)?;
            self.write_turn(tx, reply.uuid, &record)?;
            Ok(TodoTurn {
                reply,
                changes: record.changes,
                proposed: record.proposed,
            })
        })
    }

    /// Makes the changes a reply offered. Undo then works as for changes made
    /// directly.
    pub fn confirm_todo_turn(&self, reply: Uuid) -> Result<Vec<TodoChange>> {
        let now = self.now_ms();
        self.backend.transaction(|tx| {
            let mut record = self.read_turn(tx, reply)?.ok_or(Error::NotFound {
                entity: EntityType::Message,
                id: reply,
            })?;
            if record.proposed.is_empty() {
                return Err(Error::UnsupportedOperation(
                    "This reply didn't offer any changes".into(),
                ));
            }
            if record.confirmed {
                return Err(Error::UnsupportedOperation(
                    "These changes were already made".into(),
                ));
            }
            let mut changes = Vec::new();
            for proposed in &record.proposed {
                let Some(after) = &proposed.after else {
                    continue;
                };
                let current = self.read_todo(tx, after.id)?;
                // A task edited since the offer, or one that appeared, is a
                // conflict rather than something to overwrite.
                if current.as_ref().map(|todo| todo.version)
                    != proposed.before.as_ref().map(|todo| todo.version)
                {
                    return Err(conflict());
                }
                let mut todo = after.clone();
                todo.updated_at_ms = now;
                match &proposed.before {
                    None => todo.created_at_ms = now,
                    Some(_) => {
                        if todo.completed_at_ms.is_some() {
                            todo.completed_at_ms = Some(now);
                        }
                    }
                }
                self.write_todo(tx, &todo)?;
                changes.push(TodoChange {
                    before: current,
                    after: Some(todo),
                });
            }
            record.changes.extend(changes.iter().cloned());
            record.confirmed = true;
            self.write_turn(tx, reply, &record)?;
            Ok(changes)
        })
    }

    fn apply_call(
        &self,
        call: &ToolCall,
        todos: &mut Vec<Todo>,
        shown: &[Uuid],
        now_ms: i64,
        propose: bool,
    ) -> Result<CallOutcome> {
        let invalid = || Error::UnsupportedOperation(format!("Unknown To Do call {}", call.name));
        match call.name.as_str() {
            SAVE_TOOL => {
                let Some(title) = call.text("title").and_then(todo::clean_title) else {
                    return Ok(CallOutcome::text("I couldn't save a task without a title."));
                };
                let mut note = String::new();
                let due = match call.text("when") {
                    None => None,
                    Some(when) => {
                        let parsed = timing::local_time(now_ms)
                            .and_then(|now| timing::parse_deadline(when, now));
                        match parsed.and_then(|deadline| {
                            Some((timing::local_millis(deadline.at)?, deadline.default_time))
                        }) {
                            Some((due, default_time)) => {
                                if default_time {
                                    note = " No time was given, so I used 9:00.".into();
                                }
                                Some(due)
                            }
                            None => {
                                note = format!(
                                    " I couldn't work out the deadline “{when}”, so it has no due date."
                                );
                                None
                            }
                        }
                    }
                };
                let todo = self.new_todo(title, due, now_ms);
                let due_text = todo.due_at_ms.map_or_else(String::new, |due| {
                    format!(", due {}", todo::describe_due(due))
                });
                let text = if propose {
                    format!("Add “{}”{due_text} to your To Dos?{note}", todo.title)
                } else {
                    format!("Saved “{}”{due_text}.{note}", todo.title)
                };
                todos.push(todo.clone());
                Ok(CallOutcome {
                    text,
                    changes: vec![TodoChange {
                        before: None,
                        after: Some(todo),
                    }],
                    shown: Vec::new(),
                })
            }
            LIST_TOOL => {
                let filter = call
                    .text("filter")
                    .and_then(ListFilter::from_name)
                    .ok_or_else(invalid)?;
                let selected = todo::select_tasks(todos, filter, call.text("query"), now_ms);
                if selected.is_empty() {
                    return Ok(CallOutcome::text("No tasks match."));
                }
                let mut lines: Vec<_> = selected
                    .iter()
                    .take(LIST_LIMIT)
                    .enumerate()
                    .map(|(i, todo)| todo::list_line(i + 1, todo))
                    .collect();
                if selected.len() > LIST_LIMIT {
                    lines.push(format!("Showing {LIST_LIMIT} of {} tasks.", selected.len()));
                }
                Ok(CallOutcome {
                    text: lines.join("\n"),
                    changes: Vec::new(),
                    shown: selected
                        .iter()
                        .take(LIST_LIMIT)
                        .map(|todo| todo.id)
                        .collect(),
                })
            }
            COMPLETE_TOOL => {
                let target = if let Some(number) = call.integer("number") {
                    let id = usize::try_from(number)
                        .ok()
                        .and_then(|n| n.checked_sub(1))
                        .and_then(|i| shown.get(i));
                    match id.and_then(|id| todos.iter().find(|todo| todo.id == *id)) {
                        Some(todo) => vec![todo.clone()],
                        None => {
                            return Ok(CallOutcome::text(&format!(
                                "There's no task {number} in the last list. Ask me to list your tasks again."
                            )));
                        }
                    }
                } else if let Some(task) = call.text("task") {
                    let open: Vec<_> = todos
                        .iter()
                        .filter(|todo| todo.is_open())
                        .cloned()
                        .collect();
                    let found: Vec<_> =
                        todo::find_tasks(&open, task).into_iter().cloned().collect();
                    if found.is_empty() {
                        return Ok(CallOutcome::text(&format!(
                            "I couldn't find an open task matching “{task}”."
                        )));
                    }
                    found
                } else {
                    return Ok(CallOutcome::text("Which task should I mark as done?"));
                };
                match target.as_slice() {
                    [todo] if !todo.is_open() => Ok(CallOutcome::text(&format!(
                        "“{}” is already done.",
                        todo.title
                    ))),
                    [todo] => {
                        let after =
                            Self::changed(todo, now_ms, |todo| todo.completed_at_ms = Some(now_ms));
                        if let Some(stored) = todos.iter_mut().find(|stored| stored.id == todo.id) {
                            *stored = after.clone();
                        }
                        Ok(CallOutcome {
                            text: if propose {
                                format!("Mark “{}” as done?", todo.title)
                            } else {
                                format!("Marked “{}” as done.", todo.title)
                            },
                            changes: vec![TodoChange {
                                before: Some(todo.clone()),
                                after: Some(after),
                            }],
                            shown: Vec::new(),
                        })
                    }
                    many => {
                        let refs: Vec<_> = many.iter().collect();
                        let lines: Vec<_> = refs
                            .iter()
                            .take(LIST_LIMIT)
                            .enumerate()
                            .map(|(i, todo)| todo::list_line(i + 1, todo))
                            .collect();
                        Ok(CallOutcome {
                            text: format!("Which one should I mark as done?\n{}", lines.join("\n")),
                            changes: Vec::new(),
                            shown: refs.iter().take(LIST_LIMIT).map(|todo| todo.id).collect(),
                        })
                    }
                }
            }
            _ => Err(invalid()),
        }
    }

    /// Reverts the changes a To Do turn made, provided none of those tasks
    /// changed since.
    pub fn undo_todo_turn(&self, reply: Uuid) -> Result<Vec<TodoChange>> {
        let now = self.now_ms();
        self.backend.transaction(|tx| {
            let mut record = self.read_turn(tx, reply)?.ok_or(Error::NotFound {
                entity: EntityType::Message,
                id: reply,
            })?;
            if record.undone {
                return Err(Error::UnsupportedOperation(
                    "This change was already undone".into(),
                ));
            }
            if record.changes.is_empty() {
                return Err(Error::UnsupportedOperation(
                    "This reply didn't change any tasks".into(),
                ));
            }
            let mut reverted = Vec::new();
            for change in record.changes.iter().rev() {
                let id = change
                    .after
                    .as_ref()
                    .or(change.before.as_ref())
                    .map(|todo| todo.id)
                    .ok_or_else(conflict)?;
                let current = self.read_todo(tx, id)?;
                if current.as_ref().map(|todo| todo.version)
                    != change.after.as_ref().map(|todo| todo.version)
                {
                    return Err(conflict());
                }
                let restored = match (&change.before, &current) {
                    (None, _) => {
                        self.remove_todo(tx, id)?;
                        None
                    }
                    (Some(before), current) => {
                        let mut restored = before.clone();
                        restored.version =
                            current.as_ref().map_or(before.version, |todo| todo.version) + 1;
                        restored.updated_at_ms = now;
                        self.write_todo(tx, &restored)?;
                        Some(restored)
                    }
                };
                reverted.push(TodoChange {
                    before: current,
                    after: restored,
                });
            }
            record.undone = true;
            self.write_turn(tx, reply, &record)?;
            Ok(reverted)
        })
    }

    pub fn todo_turn_state(&self, reply: Uuid) -> Result<Option<TodoTurnState>> {
        Ok(self
            .read_turn(&self.backend, reply)?
            .map(|record| TodoTurnState {
                changed: !record.changes.is_empty(),
                undone: record.undone,
                pending: !record.proposed.is_empty() && !record.confirmed,
            }))
    }

    /// The tool calls behind any assistant replies in `messages`, for
    /// rendering history in the model's native tool format.
    pub fn tool_history(&self, messages: &[Message]) -> Result<HashMap<Uuid, ToolTurnHistory>> {
        let replies: Vec<_> = messages
            .iter()
            .filter(|message| message.sender == Sender::Other)
            .map(|message| Value::Text(message.uuid.to_string()))
            .collect();
        let mut history = HashMap::new();
        for batch in replies.chunks(super::conversation::MESSAGE_QUERY_BATCH_SIZE) {
            let placeholders = vec!["?"; batch.len()].join(", ");
            for row in self.backend.query(
                &format!(
                    "SELECT reply_id, record FROM todo_turns WHERE reply_id IN ({placeholders})"
                ),
                batch,
            )? {
                let record: TurnRecord =
                    serde_json::from_slice(&crypto::decrypt_blob(&row.get_blob(1)?, &self.key)?)?;
                history.insert(
                    Uuid::parse_str(&row.get_string(0)?)?,
                    ToolTurnHistory {
                        calls: record.calls,
                        undone: record.undone,
                        proposal: (!record.proposed.is_empty()).then_some(record.confirmed),
                    },
                );
            }
        }
        Ok(history)
    }
}

struct CallOutcome {
    text: String,
    changes: Vec<TodoChange>,
    shown: Vec<Uuid>,
}

impl CallOutcome {
    fn text(text: &str) -> Self {
        Self {
            text: text.to_owned(),
            changes: Vec::new(),
            shown: Vec::new(),
        }
    }
}

#[cfg(test)]
#[cfg(feature = "sqlite")]
#[path = "todo_tests.rs"]
mod tests;
