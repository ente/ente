use ente_core::crypto as core_crypto;
use wasm_bindgen::prelude::*;

#[wasm_bindgen]
pub struct EncryptedBlob {
    encrypted_data: Vec<u8>,
    decryption_header: Vec<u8>,
}

#[wasm_bindgen]
impl EncryptedBlob {
    #[wasm_bindgen(getter, js_name = encryptedData)]
    pub fn encrypted_data(&self) -> Vec<u8> {
        self.encrypted_data.clone()
    }

    #[wasm_bindgen(getter, js_name = decryptionHeader)]
    pub fn decryption_header(&self) -> Vec<u8> {
        self.decryption_header.clone()
    }
}

#[wasm_bindgen(js_name = blobEncrypt)]
pub fn blob_encrypt(data: &[u8], key: &[u8]) -> Result<EncryptedBlob, JsError> {
    let out = core_crypto::blob::encrypt(data, &core_crypto::Key::try_from_slice(key)?)?;
    Ok(EncryptedBlob {
        encrypted_data: out.encrypted_data,
        decryption_header: out.decryption_header.as_bytes().to_vec(),
    })
}

#[wasm_bindgen(js_name = blobDecrypt)]
pub fn blob_decrypt(data: &[u8], header: &[u8], key: &[u8]) -> Result<Vec<u8>, JsError> {
    Ok(core_crypto::blob::decrypt(
        data,
        &core_crypto::Header::try_from_slice(header)?,
        &core_crypto::Key::try_from_slice(key)?,
    )?)
}

#[wasm_bindgen(js_name = blobEncryptCombined)]
pub fn blob_encrypt_combined(data: &[u8], key: &[u8]) -> Result<Vec<u8>, JsError> {
    Ok(core_crypto::blob::encrypt_combined(
        data,
        &core_crypto::Key::try_from_slice(key)?,
    )?)
}

#[wasm_bindgen(js_name = blobDecryptCombined)]
pub fn blob_decrypt_combined(data: &[u8], key: &[u8]) -> Result<Vec<u8>, JsError> {
    Ok(core_crypto::blob::decrypt_combined(
        data,
        &core_crypto::Key::try_from_slice(key)?,
    )?)
}
