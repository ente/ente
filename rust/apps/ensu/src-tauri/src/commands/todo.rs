use std::collections::HashMap;

use ente_ensu::todo::Todo;
use ente_ensu::tools::turn::{self as tool_turn, Confirm, ToolTurnState, Undo};
use serde::Serialize;
use tauri::{AppHandle, Emitter, State};

use crate::commands::chat_db::{ChatDbState, parse_uuid, with_chat_db_async};
use crate::commands::common::ApiError;

const CHANGED_EVENT: &str = "todo-changed";

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TodoDto {
    id: String,
    title: String,
    due_at_ms: Option<i64>,
    completed_at_ms: Option<i64>,
    version: u64,
}

impl From<Todo> for TodoDto {
    fn from(todo: Todo) -> Self {
        Self {
            id: todo.id.to_string(),
            title: todo.title,
            due_at_ms: todo.due_at_ms,
            completed_at_ms: todo.completed_at_ms,
            version: todo.version,
        }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ToolTurnStatusDto {
    undo: &'static str,
    confirm: &'static str,
    can_retry: bool,
}

impl From<ToolTurnState> for ToolTurnStatusDto {
    fn from(state: ToolTurnState) -> Self {
        Self {
            undo: match state.undo {
                Undo::None => "none",
                Undo::Available => "available",
                Undo::Undone => "undone",
                Undo::PartlyUndone => "partlyUndone",
                Undo::Stale => "stale",
            },
            confirm: match state.confirm {
                Confirm::None => "none",
                Confirm::Offered => "offered",
                Confirm::Stale => "stale",
            },
            can_retry: state.can_retry,
        }
    }
}

pub(crate) fn notify(app: &AppHandle) {
    let _ = app.emit(CHANGED_EVENT, ());
}

#[tauri::command]
pub async fn todo_list(state: State<'_, ChatDbState>) -> Result<Vec<TodoDto>, ApiError> {
    with_chat_db_async(&state, |db| {
        Ok(db.list_todos()?.into_iter().map(TodoDto::from).collect())
    })
    .await
}

#[tauri::command]
pub async fn todo_create(
    state: State<'_, ChatDbState>,
    title: String,
    due_at_ms: Option<i64>,
) -> Result<TodoDto, ApiError> {
    let todo = with_chat_db_async(&state, move |db| db.create_todo(&title, due_at_ms)).await?;
    Ok(todo.into())
}

#[tauri::command]
pub async fn todo_update(
    state: State<'_, ChatDbState>,
    id: String,
    version: u64,
    title: String,
    due_at_ms: Option<i64>,
) -> Result<TodoDto, ApiError> {
    let id = parse_uuid(&id)?;
    let todo = with_chat_db_async(&state, move |db| {
        db.update_todo(id, version, &title, due_at_ms)
    })
    .await?;
    Ok(todo.into())
}

#[tauri::command]
pub async fn todo_set_completed(
    state: State<'_, ChatDbState>,
    id: String,
    version: u64,
    completed: bool,
) -> Result<TodoDto, ApiError> {
    let id = parse_uuid(&id)?;
    let todo = with_chat_db_async(&state, move |db| {
        db.set_todo_completed(id, version, completed)
    })
    .await?;
    Ok(todo.into())
}

#[tauri::command]
pub async fn todo_delete(
    state: State<'_, ChatDbState>,
    id: String,
    version: u64,
) -> Result<(), ApiError> {
    let id = parse_uuid(&id)?;
    with_chat_db_async(&state, move |db| db.delete_todo(id, version)).await?;
    Ok(())
}

#[tauri::command]
pub async fn tool_turn_confirm(
    state: State<'_, ChatDbState>,
    reply_id: String,
) -> Result<ToolTurnStatusDto, ApiError> {
    let reply = parse_uuid(&reply_id)?;
    let turn = with_chat_db_async(&state, move |db| tool_turn::confirm(db, reply)).await?;
    Ok(turn.into())
}

#[tauri::command]
pub async fn tool_turn_undo(
    state: State<'_, ChatDbState>,
    reply_id: String,
) -> Result<ToolTurnStatusDto, ApiError> {
    let reply = parse_uuid(&reply_id)?;
    let turn = with_chat_db_async(&state, move |db| tool_turn::undo(db, reply)).await?;
    Ok(turn.into())
}

#[tauri::command]
pub async fn tool_turn_statuses(
    state: State<'_, ChatDbState>,
    session_id: String,
) -> Result<HashMap<String, ToolTurnStatusDto>, ApiError> {
    let session = parse_uuid(&session_id)?;
    with_chat_db_async(&state, move |db| {
        Ok(tool_turn::states(db, session)?
            .into_iter()
            .map(|(reply, state)| (reply.to_string(), state.into()))
            .collect())
    })
    .await
}
