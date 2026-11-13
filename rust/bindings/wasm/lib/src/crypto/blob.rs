use ente_core::{b64, crypto};
use serde::Serialize;
use tsify::Tsify;
use wasm_bindgen::prelude::*;

use super::Error;

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct EncryptedBlob {
    pub encrypted_data: String,
    pub decryption_header: String,
}

#[wasm_bindgen(js_name = cryptoEncryptBlob)]
pub fn crypto_encrypt_blob(
    data: &[u8],
    key_b64: &str,
) -> Result<<EncryptedBlob as Tsify>::JsType, Error> {
    let key = b64::decode(key_b64)?;

    let out = crypto::blob::encrypt(data, &crypto::Key::try_from_slice(&key)?)?;
    EncryptedBlob {
        encrypted_data: b64::encode(&out.encrypted_data),
        decryption_header: b64::encode(out.decryption_header.as_bytes()),
    }
    .into_js()
    .map_err(Into::into)
}

#[wasm_bindgen(js_name = cryptoDecryptBlobLegacy)]
pub fn crypto_decrypt_blob_legacy(
    encrypted_data_b64: &str,
    decryption_header_b64: &str,
    key_b64: &str,
) -> Result<Vec<u8>, Error> {
    crypto_decrypt_blob_legacy_bytes(
        &b64::decode(encrypted_data_b64)?,
        &b64::decode(decryption_header_b64)?,
        &b64::decode(key_b64)?,
    )
}

#[wasm_bindgen(js_name = cryptoDecryptBlobLegacyBytes)]
pub fn crypto_decrypt_blob_legacy_bytes(
    encrypted_data: &[u8],
    decryption_header: &[u8],
    key: &[u8],
) -> Result<Vec<u8>, Error> {
    Ok(crypto::blob::decrypt_legacy(
        encrypted_data,
        &crypto::Header::try_from_slice(decryption_header)?,
        &crypto::Key::try_from_slice(key)?,
    )?)
}
