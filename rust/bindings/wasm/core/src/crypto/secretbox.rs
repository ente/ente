use ente_core::crypto as core_crypto;
use wasm_bindgen::prelude::*;

#[wasm_bindgen]
pub struct EncryptedBox {
    encrypted_data: Vec<u8>,
    nonce: Vec<u8>,
}

#[wasm_bindgen]
impl EncryptedBox {
    #[wasm_bindgen(getter, js_name = encryptedData)]
    pub fn encrypted_data(&self) -> Vec<u8> {
        self.encrypted_data.clone()
    }

    #[wasm_bindgen(getter)]
    pub fn nonce(&self) -> Vec<u8> {
        self.nonce.clone()
    }
}

#[wasm_bindgen(js_name = secretboxEncrypt)]
pub fn secretbox_encrypt(data: &[u8], key: &[u8]) -> Result<EncryptedBox, JsError> {
    let out = core_crypto::secretbox::encrypt(data, &core_crypto::Key::try_from_slice(key)?);
    Ok(EncryptedBox {
        encrypted_data: out.encrypted_data,
        nonce: out.nonce.as_bytes().to_vec(),
    })
}

#[wasm_bindgen(js_name = secretboxDecrypt)]
pub fn secretbox_decrypt(data: &[u8], nonce: &[u8], key: &[u8]) -> Result<Vec<u8>, JsError> {
    Ok(core_crypto::secretbox::decrypt(
        data,
        &core_crypto::Nonce::try_from_slice(nonce)?,
        &core_crypto::Key::try_from_slice(key)?,
    )?)
}

#[wasm_bindgen(js_name = secretboxEncryptCombined)]
pub fn secretbox_encrypt_combined(data: &[u8], key: &[u8]) -> Result<Vec<u8>, JsError> {
    Ok(core_crypto::secretbox::encrypt_combined(
        data,
        &core_crypto::Key::try_from_slice(key)?,
    ))
}

#[wasm_bindgen(js_name = secretboxDecryptCombined)]
pub fn secretbox_decrypt_combined(data: &[u8], key: &[u8]) -> Result<Vec<u8>, JsError> {
    Ok(core_crypto::secretbox::decrypt_combined(
        data,
        &core_crypto::Key::try_from_slice(key)?,
    )?)
}
