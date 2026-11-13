use serde::Serialize;
use serde_wasm_bindgen as swb;
use tsify::Tsify;
use wasm_bindgen::prelude::*;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Crypto(#[from] ente_ensu_crypto::Error),
    #[error(transparent)]
    Serde(#[from] swb::Error),
}

impl From<Error> for JsValue {
    fn from(error: Error) -> Self {
        ente_wasm_lib::js_error(&error, None)
    }
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct EncryptedChatPayload {
    encrypted_data: String,
    header: String,
}

#[wasm_bindgen(js_name = generateChatKey)]
pub fn generate_chat_key() -> String {
    ente_ensu_crypto::generate_chat_key()
}

#[wasm_bindgen(js_name = encryptChatPayload)]
pub fn encrypt_chat_payload(
    value: &str,
    key_b64: &str,
) -> Result<<EncryptedChatPayload as Tsify>::JsType, Error> {
    let payload = ente_ensu_crypto::encrypt_payload(value, key_b64)?;
    EncryptedChatPayload {
        encrypted_data: payload.encrypted_data,
        header: payload.header,
    }
    .into_js()
    .map_err(Into::into)
}

#[wasm_bindgen(js_name = decryptChatPayload)]
pub fn decrypt_chat_payload(
    encrypted_data_b64: &str,
    header_b64: &str,
    key_b64: &str,
) -> Result<String, Error> {
    ente_ensu_crypto::decrypt_payload(encrypted_data_b64, header_b64, key_b64).map_err(Into::into)
}

#[wasm_bindgen(js_name = encryptChatField)]
pub fn encrypt_chat_field(value: &str, key_b64: &str) -> Result<String, Error> {
    ente_ensu_crypto::encrypt_field_b64(value, key_b64).map_err(Into::into)
}

#[wasm_bindgen(js_name = decryptChatField)]
pub fn decrypt_chat_field(value: &str, key_b64: &str) -> Result<String, Error> {
    ente_ensu_crypto::decrypt_field_b64(value, key_b64).map_err(Into::into)
}

#[wasm_bindgen(js_name = encryptChatAttachment)]
pub fn encrypt_chat_attachment(
    data: &[u8],
    key_b64: &str,
    session_uuid: &str,
) -> Result<Vec<u8>, Error> {
    ente_ensu_crypto::encrypt_attachment(data, key_b64, session_uuid).map_err(Into::into)
}

#[wasm_bindgen(js_name = decryptChatAttachment)]
pub fn decrypt_chat_attachment(
    data: &[u8],
    key_b64: &str,
    session_uuid: &str,
) -> Result<Vec<u8>, Error> {
    ente_ensu_crypto::decrypt_attachment(data, key_b64, session_uuid).map_err(Into::into)
}
