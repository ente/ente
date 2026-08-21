use serde::{Deserialize, Serialize};
use tauri::ipc::{InvokeBody, Request, Response};

use crate::commands::common::ApiError;

const CHAT_KEY_HEADER: &str = "chat-key";
const SESSION_UUID_HEADER: &str = "session-uuid";

impl From<ente_ensu_crypto::Error> for ApiError {
    fn from(error: ente_ensu_crypto::Error) -> Self {
        ApiError::new(error.code(), error.to_string())
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EncryptedChatPayload {
    encrypted_data: String,
    header: String,
}

impl From<ente_ensu_crypto::EncryptedChatPayload> for EncryptedChatPayload {
    fn from(payload: ente_ensu_crypto::EncryptedChatPayload) -> Self {
        Self {
            encrypted_data: payload.encrypted_data,
            header: payload.header,
        }
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PayloadEncryptInput {
    value: String,
    key_b64: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PayloadDecryptInput {
    encrypted_data_b64: String,
    header_b64: String,
    key_b64: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FieldInput {
    value: String,
    key_b64: String,
}

#[tauri::command]
pub fn chat_crypto_generate_key() -> String {
    ente_ensu_crypto::generate_chat_key()
}

#[tauri::command]
pub fn chat_crypto_encrypt_payload(
    input: PayloadEncryptInput,
) -> Result<EncryptedChatPayload, ApiError> {
    ente_ensu_crypto::encrypt_payload(&input.value, &input.key_b64)
        .map(Into::into)
        .map_err(Into::into)
}

#[tauri::command]
pub fn chat_crypto_decrypt_payload(input: PayloadDecryptInput) -> Result<String, ApiError> {
    ente_ensu_crypto::decrypt_payload(&input.encrypted_data_b64, &input.header_b64, &input.key_b64)
        .map_err(Into::into)
}

#[tauri::command]
pub fn chat_crypto_encrypt_field(input: FieldInput) -> Result<String, ApiError> {
    ente_ensu_crypto::encrypt_field_b64(&input.value, &input.key_b64).map_err(Into::into)
}

#[tauri::command]
pub fn chat_crypto_decrypt_field(input: FieldInput) -> Result<String, ApiError> {
    ente_ensu_crypto::decrypt_field_b64(&input.value, &input.key_b64).map_err(Into::into)
}

#[tauri::command]
pub fn chat_crypto_encrypt_attachment(request: Request<'_>) -> Result<Response, ApiError> {
    transform_attachment(request, ente_ensu_crypto::encrypt_attachment)
}

#[tauri::command]
pub fn chat_crypto_decrypt_attachment(request: Request<'_>) -> Result<Response, ApiError> {
    transform_attachment(request, ente_ensu_crypto::decrypt_attachment)
}

fn transform_attachment(
    request: Request<'_>,
    transform: impl FnOnce(&[u8], &str, &str) -> ente_ensu_crypto::Result<Vec<u8>>,
) -> Result<Response, ApiError> {
    let InvokeBody::Raw(data) = request.body() else {
        return Err(ApiError::new("invalid_args", "Expected attachment bytes"));
    };
    let header = |name| {
        request
            .headers()
            .get(name)
            .and_then(|value| value.to_str().ok())
            .ok_or_else(|| ApiError::new("invalid_args", format!("Missing {name} header")))
    };
    transform(data, header(CHAT_KEY_HEADER)?, header(SESSION_UUID_HEADER)?)
        .map(Response::new)
        .map_err(Into::into)
}
