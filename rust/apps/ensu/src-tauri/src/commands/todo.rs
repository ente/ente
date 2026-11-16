//! To Do commands. The store, matching and receipts live in `ente_ensu`;
//! these commands only convert identifiers and shapes for the web layer.

use std::collections::HashMap;

use ente_ensu::llm::ToolCall;
use ente_ensu::todo::{Todo, TodoAlarm};
use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager, State, WebviewWindow};

use crate::commands::chat_db::{ChatDbState, ChatMessageDto, parse_uuid, with_chat_db_async};
use crate::commands::common::ApiError;

/// Sent whenever the To Do list changes, so open views can reload.
const CHANGED_EVENT: &str = "todo-changed";

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TodoDto {
    id: String,
    title: String,
    due_at_ms: Option<i64>,
    completed_at_ms: Option<i64>,
    created_at_ms: i64,
    updated_at_ms: i64,
    version: u64,
}

impl From<Todo> for TodoDto {
    fn from(todo: Todo) -> Self {
        Self {
            id: todo.id.to_string(),
            title: todo.title,
            due_at_ms: todo.due_at_ms,
            completed_at_ms: todo.completed_at_ms,
            created_at_ms: todo.created_at_ms,
            updated_at_ms: todo.updated_at_ms,
            version: todo.version,
        }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TodoAlarmDto {
    todo_id: String,
    title: String,
    due_at_ms: i64,
    key: String,
}

impl From<TodoAlarm> for TodoAlarmDto {
    fn from(alarm: TodoAlarm) -> Self {
        Self {
            todo_id: alarm.todo_id.to_string(),
            title: alarm.title,
            due_at_ms: alarm.due_at_ms,
            key: alarm.key,
        }
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TodoTurnDto {
    reply: ChatMessageDto,
    changed: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TodoTurnStatusDto {
    changed: bool,
    undone: bool,
}

fn notify(app: &AppHandle) {
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
    app: AppHandle,
    state: State<'_, ChatDbState>,
    title: String,
    due_at_ms: Option<i64>,
) -> Result<TodoDto, ApiError> {
    let todo = with_chat_db_async(&state, move |db| db.create_todo(&title, due_at_ms)).await?;
    notify(&app);
    Ok(todo.into())
}

#[tauri::command]
pub async fn todo_update(
    app: AppHandle,
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
    notify(&app);
    Ok(todo.into())
}

#[tauri::command]
pub async fn todo_set_completed(
    app: AppHandle,
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
    notify(&app);
    Ok(todo.into())
}

#[tauri::command]
pub async fn todo_delete(
    app: AppHandle,
    state: State<'_, ChatDbState>,
    id: String,
    version: u64,
) -> Result<(), ApiError> {
    let id = parse_uuid(&id)?;
    with_chat_db_async(&state, move |db| db.delete_todo(id, version)).await?;
    notify(&app);
    Ok(())
}

#[tauri::command]
pub async fn todo_alarms(
    state: State<'_, ChatDbState>,
    now_ms: i64,
    limit: usize,
) -> Result<Vec<TodoAlarmDto>, ApiError> {
    with_chat_db_async(&state, move |db| {
        Ok(db
            .todo_alarms(now_ms, limit)?
            .into_iter()
            .map(TodoAlarmDto::from)
            .collect())
    })
    .await
}

/// Applies the calls a generation returned for `source_id` (the user's
/// message) and saves the receipt as the assistant reply. The receipt takes
/// the place of the prepared answer, so the preparation is released.
#[tauri::command]
pub async fn todo_apply_calls(
    window: WebviewWindow,
    state: State<'_, ChatDbState>,
    conversation_state: State<'_, super::conversation::State>,
    source_id: String,
    calls: Vec<ToolCall>,
    now_ms: i64,
    preparation_token: Option<String>,
) -> Result<TodoTurnDto, ApiError> {
    let app = window.app_handle();
    let source = parse_uuid(&source_id)?;
    if let Some(token) = preparation_token.as_deref() {
        conversation_state.take_answer(app, window.label(), token)?;
    }
    let turn = with_chat_db_async(&state, move |db| {
        db.apply_todo_calls(source, &calls, now_ms)
    })
    .await?;
    let changed = !turn.changes.is_empty();
    if changed {
        notify(app);
    }
    Ok(TodoTurnDto {
        reply: turn.reply.into(),
        changed,
    })
}

#[tauri::command]
pub async fn todo_undo(
    app: AppHandle,
    state: State<'_, ChatDbState>,
    reply_id: String,
) -> Result<(), ApiError> {
    let reply = parse_uuid(&reply_id)?;
    with_chat_db_async(&state, move |db| db.undo_todo_turn(reply)).await?;
    notify(&app);
    Ok(())
}

#[tauri::command]
pub async fn todo_turn_status(
    state: State<'_, ChatDbState>,
    reply_id: String,
) -> Result<Option<TodoTurnStatusDto>, ApiError> {
    let reply = parse_uuid(&reply_id)?;
    with_chat_db_async(&state, move |db| {
        Ok(db.todo_turn_state(reply)?.map(|s| TodoTurnStatusDto {
            changed: s.changed,
            undone: s.undone,
        }))
    })
    .await
}

/// Undo state for the given replies; replies without To Do changes are left
/// out, so the chat view can look up each message it shows in one call.
#[tauri::command]
pub async fn todo_turn_statuses(
    state: State<'_, ChatDbState>,
    reply_ids: Vec<String>,
) -> Result<HashMap<String, TodoTurnStatusDto>, ApiError> {
    let replies = reply_ids
        .iter()
        .map(|id| parse_uuid(id).map(|uuid| (id.clone(), uuid)))
        .collect::<Result<Vec<_>, _>>()?;
    with_chat_db_async(&state, move |db| {
        let mut statuses = HashMap::new();
        for (id, reply) in replies {
            if let Some(s) = db.todo_turn_state(reply)? {
                statuses.insert(
                    id,
                    TodoTurnStatusDto {
                        changed: s.changed,
                        undone: s.undone,
                    },
                );
            }
        }
        Ok(statuses)
    })
    .await
}
