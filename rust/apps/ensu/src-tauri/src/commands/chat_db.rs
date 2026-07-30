use std::fs;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use ente_core::b64;
use ente_ensu::db::{self, ChatDb, SqliteBackend};
use serde::{Deserialize, Serialize};
use tauri::async_runtime;
use tauri::{AppHandle, Manager, State};
use tauri_plugin_fs::FsExt;
use uuid::Uuid;

use crate::commands::chat_db_migration;
use crate::commands::common::{ApiError, app_data_dir};
use crate::logging;

#[derive(Default)]
pub struct ChatDbState {
    inner: Arc<Mutex<Option<ChatDbHolder>>>,
}

struct ChatDbHolder {
    db: Arc<ChatDb<SqliteBackend>>,
}

const CHAT_DB_FILE_NAME: &str = "ensu_llmchat_v2.db";
const ATTACHMENTS_DIR_NAME: &str = "ensu_llmchat_attachments_v2";

fn chat_db_thread_error() -> ApiError {
    ApiError::new("db_thread", "Chat DB task failed")
}

fn image_thread_error() -> ApiError {
    ApiError::new("image_thread", "Image task failed")
}

impl From<db::Error> for ApiError {
    fn from(error: db::Error) -> Self {
        use db::Error as E;

        let code = match &error {
            E::InvalidKeyLength { .. } => "db_invalid_key_length",
            E::InvalidBlobLength { .. } => "db_invalid_blob_length",
            E::InvalidEncryptedField => "db_invalid_encrypted_field",
            E::UnsupportedValueType(_) => "db_unsupported_value_type",
            E::Row(_) => "db_row",
            E::InvalidSender(_) => "db_invalid_sender",
            E::NotFound { .. } => "db_not_found",
            E::Crypto(_) => "db_crypto",
            E::Base64Decode(_) => "db_base64_decode",
            E::SerdeJson(_) => "db_serde_json",
            E::Uuid(_) => "db_uuid",
            E::Utf8(_) => "db_utf8",
            E::Io(_) => "db_io",
            E::ReadonlyDatabase => "db_readonly",
            E::Sqlite(_) => "db_sqlite",
            E::UnsupportedOperation(_) => "db_unsupported_operation",
            E::Migration(_) => "db_migration",
        };

        ApiError::new(code, error.to_string())
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatSessionDto {
    session_uuid: String,
    title: String,
    created_at: i64,
    updated_at: i64,
}

impl From<db::Session> for ChatSessionDto {
    fn from(session: db::Session) -> Self {
        Self {
            session_uuid: session.uuid.to_string(),
            title: session.title,
            created_at: session.created_at,
            updated_at: session.updated_at,
        }
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatSessionPreviewDto {
    session_uuid: String,
    title: String,
    created_at: i64,
    updated_at: i64,
    last_message_preview: Option<String>,
}

impl From<db::SessionWithPreview> for ChatSessionPreviewDto {
    fn from(session: db::SessionWithPreview) -> Self {
        Self {
            session_uuid: session.uuid.to_string(),
            title: session.title,
            created_at: session.created_at,
            updated_at: session.updated_at,
            last_message_preview: session.last_message_preview,
        }
    }
}

#[derive(Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct ChatAttachmentDto {
    id: String,
    kind: String,
    size: i64,
    name: String,
}

impl From<db::AttachmentMeta> for ChatAttachmentDto {
    fn from(attachment: db::AttachmentMeta) -> Self {
        let kind = match attachment.kind {
            db::AttachmentKind::Image => "image",
            db::AttachmentKind::Document => "document",
        };
        Self {
            id: attachment.id,
            kind: kind.to_string(),
            size: attachment.size,
            name: attachment.name,
        }
    }
}

#[derive(Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct ChatAttachmentInput {
    id: String,
    kind: String,
    size: i64,
    name: String,
}

impl TryFrom<ChatAttachmentInput> for db::AttachmentMeta {
    type Error = ApiError;

    fn try_from(value: ChatAttachmentInput) -> Result<Self, Self::Error> {
        let kind = match value.kind.as_str() {
            "image" => db::AttachmentKind::Image,
            "document" => db::AttachmentKind::Document,
            other => {
                return Err(ApiError::new(
                    "db_invalid_attachment_kind",
                    format!("Unsupported attachment kind: {other}"),
                ));
            }
        };
        Ok(Self {
            id: value.id,
            kind,
            size: value.size,
            name: value.name,
        })
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatMessageDto {
    message_uuid: String,
    session_uuid: String,
    parent_message_uuid: Option<String>,
    sender: String,
    text: String,
    created_at: i64,
    attachments: Vec<ChatAttachmentDto>,
}

impl From<db::Message> for ChatMessageDto {
    fn from(message: db::Message) -> Self {
        let sender = match message.sender {
            db::Sender::SelfUser => "self",
            db::Sender::Other => "assistant",
        };
        Self {
            message_uuid: message.uuid.to_string(),
            session_uuid: message.session_uuid.to_string(),
            parent_message_uuid: message.parent_message_uuid.map(|value| value.to_string()),
            sender: sender.to_string(),
            text: message.text,
            created_at: message.created_at,
            attachments: message
                .attachments
                .into_iter()
                .map(ChatAttachmentDto::from)
                .collect(),
        }
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatMessageInsertInput {
    session_uuid: String,
    sender: String,
    text: String,
    parent_message_uuid: Option<String>,
    attachments: Option<Vec<ChatAttachmentInput>>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatSessionUpsertInput {
    session_uuid: String,
    title: String,
    created_at: i64,
    updated_at: i64,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatMessageUpsertInput {
    message_uuid: String,
    session_uuid: String,
    parent_message_uuid: Option<String>,
    sender: String,
    text: String,
    created_at: i64,
    attachments: Option<Vec<ChatAttachmentInput>>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatDbOpenInput {
    key_b64: String,
    recovery_keys_b64: Vec<String>,
}

#[tauri::command]
pub async fn chat_db_list_sessions(
    state: State<'_, ChatDbState>,
) -> Result<Vec<ChatSessionDto>, ApiError> {
    with_chat_db_async(&state, |db| {
        Ok(db
            .list_sessions()?
            .into_iter()
            .map(ChatSessionDto::from)
            .collect())
    })
    .await
}

#[tauri::command]
pub async fn chat_db_list_sessions_with_preview(
    state: State<'_, ChatDbState>,
) -> Result<Vec<ChatSessionPreviewDto>, ApiError> {
    with_chat_db_async(&state, |db| {
        Ok(db
            .list_sessions_with_preview()?
            .into_iter()
            .map(ChatSessionPreviewDto::from)
            .collect())
    })
    .await
}

#[tauri::command]
pub async fn chat_db_get_session(
    state: State<'_, ChatDbState>,
    session_uuid: String,
) -> Result<Option<ChatSessionDto>, ApiError> {
    let uuid = parse_uuid(&session_uuid)?;
    with_chat_db_async(&state, move |db| {
        Ok(db.get_session(uuid)?.map(ChatSessionDto::from))
    })
    .await
}

#[tauri::command]
pub async fn chat_db_create_session(
    state: State<'_, ChatDbState>,
    title: String,
) -> Result<ChatSessionDto, ApiError> {
    with_chat_db_async(&state, move |db| {
        Ok(ChatSessionDto::from(db.create_session(&title)?))
    })
    .await
}

#[tauri::command]
pub async fn chat_db_update_session_title(
    state: State<'_, ChatDbState>,
    session_uuid: String,
    title: String,
) -> Result<(), ApiError> {
    let uuid = parse_uuid(&session_uuid)?;
    with_chat_db_async(&state, move |db| db.update_session_title(uuid, &title)).await
}

#[tauri::command]
pub async fn chat_db_delete_session(
    state: State<'_, ChatDbState>,
    session_uuid: String,
) -> Result<Vec<String>, ApiError> {
    let uuid = parse_uuid(&session_uuid)?;
    with_chat_db_async(&state, move |db| db.delete_session(uuid)).await
}

#[tauri::command]
pub async fn chat_db_get_messages(
    state: State<'_, ChatDbState>,
    session_uuid: String,
) -> Result<Vec<ChatMessageDto>, ApiError> {
    let uuid = parse_uuid(&session_uuid)?;
    with_chat_db_async(&state, move |db| {
        Ok(db
            .get_messages(uuid)?
            .into_iter()
            .map(ChatMessageDto::from)
            .collect())
    })
    .await
}

#[tauri::command]
pub async fn chat_db_insert_message(
    state: State<'_, ChatDbState>,
    input: ChatMessageInsertInput,
) -> Result<ChatMessageDto, ApiError> {
    let session_uuid = parse_uuid(&input.session_uuid)?;
    let parent = optional_uuid(&input.parent_message_uuid)?;
    let sender = normalize_sender(&input.sender)?;
    let attachments = convert_attachments(input.attachments)?;
    with_chat_db_async(&state, move |db| {
        Ok(ChatMessageDto::from(db.insert_message(
            session_uuid,
            sender,
            &input.text,
            parent,
            attachments,
        )?))
    })
    .await
}

#[tauri::command]
pub async fn chat_db_update_message_text(
    state: State<'_, ChatDbState>,
    message_uuid: String,
    text: String,
) -> Result<(), ApiError> {
    let uuid = parse_uuid(&message_uuid)?;
    with_chat_db_async(&state, move |db| db.update_message_text(uuid, &text)).await
}

#[tauri::command]
pub async fn chat_db_upsert_session(
    state: State<'_, ChatDbState>,
    input: ChatSessionUpsertInput,
) -> Result<ChatSessionDto, ApiError> {
    let uuid = parse_uuid(&input.session_uuid)?;
    with_chat_db_async(&state, move |db| {
        Ok(ChatSessionDto::from(db.upsert_session(
            uuid,
            &input.title,
            input.created_at,
            input.updated_at,
        )?))
    })
    .await
}

#[tauri::command]
pub async fn chat_db_insert_message_with_uuid(
    state: State<'_, ChatDbState>,
    input: ChatMessageUpsertInput,
) -> Result<ChatMessageDto, ApiError> {
    let message_uuid = parse_uuid(&input.message_uuid)?;
    let session_uuid = parse_uuid(&input.session_uuid)?;
    let parent = optional_uuid(&input.parent_message_uuid)?;
    let sender = normalize_sender(&input.sender)?;
    let attachments = convert_attachments(input.attachments)?;
    with_chat_db_async(&state, move |db| {
        Ok(ChatMessageDto::from(db.insert_message_with_uuid(
            message_uuid,
            session_uuid,
            sender,
            &input.text,
            parent,
            attachments,
            input.created_at,
        )?))
    })
    .await
}

#[tauri::command]
pub async fn chat_db_open(
    state: State<'_, ChatDbState>,
    app: AppHandle,
    input: ChatDbOpenInput,
) -> Result<bool, ApiError> {
    let inner = state.inner.clone();
    async_runtime::spawn_blocking(move || {
        let root = app_data_dir(&app)?;
        let path = chat_db_path(&app)?;
        let attachments = attachments_dir_path(&app)?;
        let key = b64::decode(&input.key_b64).map_err(ApiError::from)?;
        let recovery_keys = input
            .recovery_keys_b64
            .iter()
            .filter_map(|value| b64::decode(value).ok())
            .collect::<Vec<_>>();
        let migrated =
            chat_db_migration::prepare(&root, &path, &attachments, key.clone(), recovery_keys)?;
        open_chat_db(&inner, path, key)?;
        Ok(migrated)
    })
    .await
    .map_err(|_| chat_db_thread_error())?
}

#[tauri::command]
pub fn chat_db_has_existing_store(app: AppHandle) -> Result<bool, ApiError> {
    let root = app_data_dir(&app)?;
    if root
        .join(CHAT_DB_FILE_NAME)
        .try_exists()
        .map_err(|error| ApiError::new("io", error.to_string()))?
        || chat_db_migration::has_store(&root)?
    {
        return Ok(true);
    }
    let attachments = root.join(ATTACHMENTS_DIR_NAME);
    if attachments
        .try_exists()
        .map_err(|error| ApiError::new("io", error.to_string()))?
        && fs::read_dir(attachments)
            .map_err(|error| ApiError::new("io", error.to_string()))?
            .next()
            .transpose()
            .map_err(|error| ApiError::new("io", error.to_string()))?
            .is_some()
    {
        return Ok(true);
    }
    Ok(false)
}

#[tauri::command]
pub async fn chat_db_compress_attachment_image_file(
    app: AppHandle,
    path: String,
) -> Result<Vec<u8>, ApiError> {
    let scope = app.fs_scope();
    async_runtime::spawn_blocking(move || {
        // Resolve relative symlinks from the link's parent, then read the exact path checked here.
        let canonical_path = fs::canonicalize(&path).map_err(|_| {
            ApiError::new(
                "io_scope",
                "image file is outside the allowed filesystem scope",
            )
        })?;
        if !scope.is_allowed(&canonical_path) {
            return Err(ApiError::new(
                "io_scope",
                "image file is outside the allowed filesystem scope",
            ));
        }
        let data = fs::read(canonical_path).map_err(|error| {
            ApiError::new("io", format!("failed to read image file '{path}': {error}"))
        })?;
        ente_ensu::image::compress_attachment_image(&data)
            .map_err(|error| ApiError::new("image", error.to_string()))
    })
    .await
    .map_err(|_| image_thread_error())?
}

fn convert_attachments(
    attachments: Option<Vec<ChatAttachmentInput>>,
) -> Result<Vec<db::AttachmentMeta>, ApiError> {
    attachments
        .unwrap_or_default()
        .into_iter()
        .map(db::AttachmentMeta::try_from)
        .collect()
}

fn normalize_sender(sender: &str) -> Result<&'static str, ApiError> {
    match sender {
        "self" => Ok("self"),
        "assistant" | "other" => Ok("other"),
        _ => Err(ApiError::new(
            "db_invalid_sender",
            format!("Unsupported sender: {sender}"),
        )),
    }
}

fn parse_uuid(value: &str) -> Result<Uuid, ApiError> {
    Uuid::parse_str(value).map_err(|error| ApiError::new("uuid", error.to_string()))
}

fn optional_uuid(value: &Option<String>) -> Result<Option<Uuid>, ApiError> {
    value.as_deref().map(parse_uuid).transpose()
}

fn chat_db_path(app: &AppHandle) -> Result<PathBuf, ApiError> {
    Ok(app_data_dir(app)?.join(CHAT_DB_FILE_NAME))
}

fn attachments_dir_path(app: &AppHandle) -> Result<PathBuf, ApiError> {
    let path = app_data_dir(app)?.join(ATTACHMENTS_DIR_NAME);
    fs::create_dir_all(&path).map_err(|error| ApiError::new("io", error.to_string()))?;
    Ok(path)
}

fn open_chat_db(
    inner: &Arc<Mutex<Option<ChatDbHolder>>>,
    path: PathBuf,
    key: Vec<u8>,
) -> Result<(), ApiError> {
    logging::log("ChatDb", format!("opening chat DB db={}", path.display()));
    let db = ChatDb::open_sqlite_with_defaults(path, key).map_err(|error| {
        logging::log("ChatDb", format!("failed to open chat DB error={error}"));
        ApiError::from(error)
    })?;
    db.list_sessions().map_err(ApiError::from)?;
    *inner
        .lock()
        .map_err(|_| ApiError::new("lock", "Failed to lock chat DB state"))? =
        Some(ChatDbHolder { db: Arc::new(db) });
    logging::log("ChatDb", "chat DB opened");
    Ok(())
}

fn with_chat_db<T, F>(inner: &Arc<Mutex<Option<ChatDbHolder>>>, operation: F) -> Result<T, ApiError>
where
    F: FnOnce(&ChatDb<SqliteBackend>) -> Result<T, db::Error>,
{
    let db = inner
        .lock()
        .map_err(|_| ApiError::new("lock", "Failed to lock chat DB state"))?
        .as_ref()
        .ok_or_else(|| ApiError::new("db", "Chat DB not initialized"))?
        .db
        .clone();
    operation(db.as_ref()).map_err(ApiError::from)
}

async fn with_chat_db_async<T, F>(state: &ChatDbState, operation: F) -> Result<T, ApiError>
where
    T: Send + 'static,
    F: FnOnce(&ChatDb<SqliteBackend>) -> Result<T, db::Error> + Send + 'static,
{
    let inner = state.inner.clone();
    async_runtime::spawn_blocking(move || with_chat_db(&inner, operation))
        .await
        .map_err(|_| chat_db_thread_error())?
}

pub(crate) fn clear_for_exit(app: &AppHandle) {
    if let Some(state) = app.try_state::<ChatDbState>() {
        match state.inner.lock() {
            Ok(mut guard) => {
                *guard = None;
                logging::log("App", "cleared chat DB state");
            }
            Err(_) => logging::log("App", "failed to lock chat DB state during exit"),
        }
    } else {
        logging::log("App", "chat DB state unavailable during exit");
    }
}
