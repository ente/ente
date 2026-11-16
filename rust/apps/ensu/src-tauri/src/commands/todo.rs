//! To Do commands. The store, matching and receipts live in `ente_ensu`;
//! these commands only convert identifiers and shapes for the web layer.

use std::collections::HashMap;

use ente_ensu::db::chat::TodoTurnState;
use ente_ensu::llm::ToolCall;
use ente_ensu::todo::{Todo, TodoAlarm};
use serde::{Deserialize, Serialize};
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
    /// The reply offers tasks to add.
    pending: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TodoTurnStatusDto {
    changed: bool,
    undone: bool,
    pending: bool,
}

impl From<TodoTurnState> for TodoTurnStatusDto {
    fn from(state: TodoTurnState) -> Self {
        Self {
            changed: state.changed,
            undone: state.undone,
            pending: state.pending,
        }
    }
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

/// The calls a generation returned for `source_id`, the user's message.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ApplyCallsInput {
    source_id: String,
    calls: Vec<ToolCall>,
    now_ms: i64,
    /// The model's confidence in the calls; below a threshold, changes are
    /// offered for confirmation instead of made.
    call_probability: Option<f32>,
    preparation_token: Option<String>,
}

/// Applies a generation's To Do calls and saves the receipt as the assistant
/// reply. The receipt takes the place of the prepared answer, so the
/// preparation is released.
#[tauri::command]
pub async fn todo_apply_calls(
    window: WebviewWindow,
    state: State<'_, ChatDbState>,
    conversation_state: State<'_, super::conversation::State>,
    input: ApplyCallsInput,
) -> Result<TodoTurnDto, ApiError> {
    let app = window.app_handle();
    let source = parse_uuid(&input.source_id)?;
    if let Some(token) = input.preparation_token.as_deref() {
        conversation_state.take_answer(app, window.label(), token)?;
    }
    let (calls, now_ms, call_probability) = (input.calls, input.now_ms, input.call_probability);
    let turn = with_chat_db_async(&state, move |db| {
        db.apply_todo_calls(source, &calls, now_ms, call_probability)
    })
    .await?;
    let changed = !turn.changes.is_empty();
    if changed {
        notify(app);
    }
    Ok(TodoTurnDto {
        reply: turn.reply.into(),
        changed,
        pending: !turn.proposed.is_empty(),
    })
}

/// Makes the changes a reply offered.
#[tauri::command]
pub async fn todo_confirm(
    app: AppHandle,
    state: State<'_, ChatDbState>,
    reply_id: String,
) -> Result<(), ApiError> {
    let reply = parse_uuid(&reply_id)?;
    with_chat_db_async(&state, move |db| db.confirm_todo_turn(reply)).await?;
    notify(&app);
    Ok(())
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
        Ok(db.todo_turn_state(reply)?.map(TodoTurnStatusDto::from))
    })
    .await
}

/// Add and Undo state for the given replies; replies that weren't To Do
/// turns are left out, so the chat view can look up each message it shows
/// in one call.
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
                statuses.insert(id, TodoTurnStatusDto::from(s));
            }
        }
        Ok(statuses)
    })
    .await
}
