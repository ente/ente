use ente_core::{b64, crypto};
use wasm_bindgen::prelude::*;

#[wasm_bindgen(getter_with_clone)]
pub struct EncryptedBox {
    #[wasm_bindgen(readonly, js_name = encryptedData)]
    pub encrypted_data: String,
    #[wasm_bindgen(readonly)]
    pub nonce: String,
}

impl From<crypto::secretbox::EncryptedBox> for EncryptedBox {
    fn from(value: crypto::secretbox::EncryptedBox) -> Self {
        Self {
            encrypted_data: b64::encode(&value.encrypted_data),
            nonce: b64::encode(value.nonce.as_bytes()),
        }
    }
}
