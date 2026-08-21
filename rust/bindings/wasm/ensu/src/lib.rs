use ente_wasm_log as _;
use wasm_bindgen::prelude::*;

pub struct WasmError(ente_ensu_crypto::Error);

impl From<ente_ensu_crypto::Error> for WasmError {
    fn from(error: ente_ensu_crypto::Error) -> Self {
        Self(error)
    }
}

impl From<WasmError> for JsValue {
    fn from(error: WasmError) -> Self {
        let js_error = js_sys::Error::new(&error.0.to_string());
        js_error.set_name(error.0.code());
        js_error.into()
    }
}

#[wasm_bindgen]
pub struct EncryptedChatPayload(ente_ensu_crypto::EncryptedChatPayload);

#[wasm_bindgen]
impl EncryptedChatPayload {
    #[wasm_bindgen(getter, js_name = encryptedData)]
    pub fn encrypted_data(&self) -> String {
        self.0.encrypted_data.clone()
    }

    #[wasm_bindgen(getter)]
    pub fn header(&self) -> String {
        self.0.header.clone()
    }
}

#[wasm_bindgen(js_name = generateChatKey)]
pub fn generate_chat_key() -> String {
    ente_ensu_crypto::generate_chat_key()
}

#[wasm_bindgen(js_name = encryptChatPayload)]
pub fn encrypt_chat_payload(value: &str, key_b64: &str) -> Result<EncryptedChatPayload, WasmError> {
    ente_ensu_crypto::encrypt_payload(value, key_b64)
        .map(EncryptedChatPayload)
        .map_err(Into::into)
}

#[wasm_bindgen(js_name = decryptChatPayload)]
pub fn decrypt_chat_payload(
    encrypted_data_b64: &str,
    header_b64: &str,
    key_b64: &str,
) -> Result<String, WasmError> {
    ente_ensu_crypto::decrypt_payload(encrypted_data_b64, header_b64, key_b64).map_err(Into::into)
}

#[wasm_bindgen(js_name = encryptChatField)]
pub fn encrypt_chat_field(value: &str, key_b64: &str) -> Result<String, WasmError> {
    ente_ensu_crypto::encrypt_field_b64(value, key_b64).map_err(Into::into)
}

#[wasm_bindgen(js_name = decryptChatField)]
pub fn decrypt_chat_field(value: &str, key_b64: &str) -> Result<String, WasmError> {
    ente_ensu_crypto::decrypt_field_b64(value, key_b64).map_err(Into::into)
}

#[wasm_bindgen(js_name = encryptChatAttachment)]
pub fn encrypt_chat_attachment(
    data: &[u8],
    key_b64: &str,
    session_uuid: &str,
) -> Result<Vec<u8>, WasmError> {
    ente_ensu_crypto::encrypt_attachment(data, key_b64, session_uuid).map_err(Into::into)
}

#[wasm_bindgen(js_name = decryptChatAttachment)]
pub fn decrypt_chat_attachment(
    data: &[u8],
    key_b64: &str,
    session_uuid: &str,
) -> Result<Vec<u8>, WasmError> {
    ente_ensu_crypto::decrypt_attachment(data, key_b64, session_uuid).map_err(Into::into)
}
