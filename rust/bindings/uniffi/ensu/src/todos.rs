use std::collections::HashMap;

use ente_ensu::{db, todo};

use crate::db::{DbError, DbMessage, EnsuDb, parse_uuid};

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

#[derive(Debug, Clone, uniffi::Record)]
pub struct FinishedReply {
    pub message: DbMessage,
    pub tool_turn: Option<ToolTurnStatus>,
}

#[derive(Debug, Clone, Copy, uniffi::Enum)]
pub enum ToolTurnUndo {
    None,
    Available,
    Undone,
    PartlyUndone,
    Stale,
}

#[derive(Debug, Clone, Copy, uniffi::Enum)]
pub enum ToolTurnConfirm {
    None,
    Offered,
    Stale,
}

#[derive(Debug, Clone, Copy, uniffi::Record)]
pub struct ToolTurnStatus {
    pub undo: ToolTurnUndo,
    pub confirm: ToolTurnConfirm,
    pub can_retry: bool,
}

impl From<db::chat::ToolTurnState> for ToolTurnStatus {
    fn from(state: db::chat::ToolTurnState) -> Self {
        use db::chat::{Confirm, Undo};
        Self {
            undo: match state.undo {
                Undo::None => ToolTurnUndo::None,
                Undo::Available => ToolTurnUndo::Available,
                Undo::Undone => ToolTurnUndo::Undone,
                Undo::PartlyUndone => ToolTurnUndo::PartlyUndone,
                Undo::Stale => ToolTurnUndo::Stale,
            },
            confirm: match state.confirm {
                Confirm::None => ToolTurnConfirm::None,
                Confirm::Offered => ToolTurnConfirm::Offered,
                Confirm::Stale => ToolTurnConfirm::Stale,
            },
            can_retry: state.can_retry,
        }
    }
}

#[uniffi::export(with_foreign)]
pub trait ToolsObserver: Send + Sync {
    fn on_change(&self);
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
            .update_todo(parse_uuid(&id)?, version, &title, due_at_ms)?
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
            .set_todo_completed(parse_uuid(&id)?, version, completed)?
            .into())
    }

    pub fn delete_todo(&self, id: String, version: u64) -> Result<(), DbError> {
        Ok(self.inner.delete_todo(parse_uuid(&id)?, version)?)
    }

    pub fn confirm_tool_turn(&self, reply_id: String) -> Result<ToolTurnStatus, DbError> {
        Ok(self.inner.confirm_tool_turn(parse_uuid(&reply_id)?)?.into())
    }

    pub fn undo_tool_turn(&self, reply_id: String) -> Result<ToolTurnStatus, DbError> {
        Ok(self.inner.undo_tool_turn(parse_uuid(&reply_id)?)?.into())
    }

    pub fn tool_turn_statuses(
        &self,
        session_id: String,
    ) -> Result<HashMap<String, ToolTurnStatus>, DbError> {
        Ok(self
            .inner
            .tool_turn_states(parse_uuid(&session_id)?)?
            .into_iter()
            .map(|(reply, state)| (reply.to_string(), state.into()))
            .collect())
    }

    pub fn observe_tools(&self, observer: std::sync::Arc<dyn ToolsObserver>) {
        self.inner
            .observe_tools(std::sync::Arc::new(move || observer.on_change()));
    }
}
