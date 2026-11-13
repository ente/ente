use wasm_bindgen::prelude::*;

use crate::session::Session;

#[derive(Debug, thiserror::Error)]
#[error(transparent)]
pub struct Error(#[from] ente_collections::Error);

impl From<Error> for JsValue {
    fn from(error: Error) -> Self {
        crate::js_error(&error, None)
    }
}

#[wasm_bindgen(js_name = collectionsOpenKey)]
pub fn open_key(
    session: &Session,
    owner_id: i64,
    encrypted_key: &str,
    key_decryption_nonce: Option<String>,
) -> Result<String, Error> {
    Ok(ente_core::b64::encode(
        ente_collections::open_collection_key(
            session.inner(),
            owner_id,
            encrypted_key,
            key_decryption_nonce.as_deref(),
        )?
        .as_bytes(),
    ))
}
