use ente_ensu::{db, todo};
use uuid::Uuid;

use crate::db::{DbError, DbMessage, EnsuDb, to_message};
use crate::llm::LlmToolCall;

fn parse(id: &str) -> Result<Uuid, DbError> {
    Uuid::parse_str(id).map_err(|error| DbError::from(db::Error::from(error)))
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct TodoItem {
    pub id: String,
    pub title: String,
    pub due_at_ms: Option<i64>,
    pub completed_at_ms: Option<i64>,
    pub created_at_ms: i64,
    pub version: u64,
}

impl From<todo::Todo> for TodoItem {
    fn from(todo: todo::Todo) -> Self {
        Self {
            id: todo.id.to_string(),
            title: todo.title,
            due_at_ms: todo.due_at_ms,
            completed_at_ms: todo.completed_at_ms,
            created_at_ms: todo.created_at_ms,
            version: todo.version,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct TodoAlarmItem {
    pub todo_id: String,
    pub title: String,
    pub due_at_ms: i64,
    pub key: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct TodoTurnResult {
    /// The assistant reply saved for the turn.
    pub reply: DbMessage,
    /// True when the turn changed tasks and can be undone.
    pub changed: bool,
    /// True when the reply offers changes to make with `confirm_todo_turn`.
    pub pending: bool,
}

#[derive(Debug, Clone, Copy, uniffi::Record)]
pub struct TodoTurnStatus {
    pub changed: bool,
    pub undone: bool,
    pub pending: bool,
}

#[uniffi::export]
impl EnsuDb {
    pub fn list_todos(&self) -> Result<Vec<TodoItem>, DbError> {
        Ok(self
            .inner
            .list_todos()?
            .into_iter()
            .map(Into::into)
            .collect())
    }

    pub fn create_todo(&self, title: String, due_at_ms: Option<i64>) -> Result<TodoItem, DbError> {
        Ok(self.inner.create_todo(&title, due_at_ms)?.into())
    }

    pub fn update_todo(
        &self,
        id: String,
        version: u64,
        title: String,
        due_at_ms: Option<i64>,
    ) -> Result<TodoItem, DbError> {
        Ok(self
            .inner
            .update_todo(parse(&id)?, version, &title, due_at_ms)?
            .into())
    }

    pub fn set_todo_completed(
        &self,
        id: String,
        version: u64,
        completed: bool,
    ) -> Result<TodoItem, DbError> {
        Ok(self
            .inner
            .set_todo_completed(parse(&id)?, version, completed)?
            .into())
    }

    pub fn delete_todo(&self, id: String, version: u64) -> Result<(), DbError> {
        Ok(self.inner.delete_todo(parse(&id)?, version)?)
    }

    /// Reminders the OS should hold: the earliest `limit` open tasks due
    /// after `now_ms`.
    pub fn todo_alarms(&self, now_ms: i64, limit: u32) -> Result<Vec<TodoAlarmItem>, DbError> {
        Ok(self
            .inner
            .todo_alarms(now_ms, limit as usize)?
            .into_iter()
            .map(|alarm| TodoAlarmItem {
                todo_id: alarm.todo_id.to_string(),
                title: alarm.title,
                due_at_ms: alarm.due_at_ms,
                key: alarm.key,
            })
            .collect())
    }

    /// Applies a generation's To Do calls for the user message `source_id`
    /// and saves the reply. `call_probability` is the generation's confidence
    /// in the calls; below a threshold, changes are offered for confirmation
    /// with `confirm_todo_turn` instead of made.
    pub fn apply_todo_calls(
        &self,
        source_id: String,
        calls: Vec<LlmToolCall>,
        now_ms: i64,
        call_probability: Option<f32>,
    ) -> Result<TodoTurnResult, DbError> {
        let calls: Vec<_> = calls.into_iter().map(Into::into).collect();
        let turn =
            self.inner
                .apply_todo_calls(parse(&source_id)?, &calls, now_ms, call_probability)?;
        Ok(TodoTurnResult {
            changed: !turn.changes.is_empty(),
            pending: !turn.proposed.is_empty(),
            reply: to_message(turn.reply),
        })
    }

    /// Makes the changes a reply offered.
    pub fn confirm_todo_turn(&self, reply_id: String) -> Result<(), DbError> {
        self.inner.confirm_todo_turn(parse(&reply_id)?)?;
        Ok(())
    }

    pub fn undo_todo_turn(&self, reply_id: String) -> Result<(), DbError> {
        self.inner.undo_todo_turn(parse(&reply_id)?)?;
        Ok(())
    }

    pub fn todo_turn_status(&self, reply_id: String) -> Result<Option<TodoTurnStatus>, DbError> {
        Ok(self
            .inner
            .todo_turn_state(parse(&reply_id)?)?
            .map(|state| TodoTurnStatus {
                changed: state.changed,
                undone: state.undone,
                pending: state.pending,
            }))
    }
}
