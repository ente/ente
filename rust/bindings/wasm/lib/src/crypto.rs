use ente_core::{b64, crypto};
use serde_wasm_bindgen as swb;
use tsify::Tsify;
use wasm_bindgen::prelude::*;

use crate::EncryptedBox;

#[cfg(feature = "crypto-blob")]
mod blob;
#[cfg(feature = "crypto-file")]
mod file;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Crypto(#[from] crypto::Error),
    #[error(transparent)]
    Decode(#[from] b64::DecodeError),
    #[error(transparent)]
    Serde(#[from] swb::Error),
}

impl Error {
    fn name(&self) -> Option<&'static str> {
        match self {
            Self::Crypto(crypto::Error::StreamTruncated) => Some("stream_truncated"),
            _ => None,
        }
    }
}

impl From<Error> for JsValue {
    fn from(error: Error) -> Self {
        crate::js_error(&error, error.name())
    }
}

#[wasm_bindgen(js_name = cryptoGenerateKey)]
pub fn crypto_generate_key() -> String {
    b64::encode(crypto::Key::generate().as_bytes())
}

#[wasm_bindgen(js_name = cryptoEncryptBox)]
pub fn crypto_encrypt_box(
    data_b64: &str,
    key_b64: &str,
) -> Result<<EncryptedBox as Tsify>::JsType, Error> {
    crypto_encrypt_box_bytes(&b64::decode(data_b64)?, key_b64)
}

#[wasm_bindgen(js_name = cryptoEncryptBoxBytes)]
pub fn crypto_encrypt_box_bytes(
    data: &[u8],
    key_b64: &str,
) -> Result<<EncryptedBox as Tsify>::JsType, Error> {
    let key = b64::decode(key_b64)?;
    EncryptedBox::from(crypto::secretbox::encrypt(
        data,
        &crypto::Key::try_from_slice(&key)?,
    ))
    .into_js()
    .map_err(Into::into)
}

#[wasm_bindgen(js_name = cryptoDecryptBox)]
pub fn crypto_decrypt_box(
    encrypted_data_b64: &str,
    nonce_b64: &str,
    key_b64: &str,
) -> Result<String, Error> {
    Ok(b64::encode(&crypto_decrypt_box_bytes(
        encrypted_data_b64,
        nonce_b64,
        key_b64,
    )?))
}

#[wasm_bindgen(js_name = cryptoDecryptBoxBytes)]
pub fn crypto_decrypt_box_bytes(
    encrypted_data_b64: &str,
    nonce_b64: &str,
    key_b64: &str,
) -> Result<Vec<u8>, Error> {
    let ciphertext = b64::decode(encrypted_data_b64)?;
    let nonce = b64::decode(nonce_b64)?;
    let key = b64::decode(key_b64)?;

    Ok(crypto::secretbox::decrypt(
        &ciphertext,
        &crypto::Nonce::try_from_slice(&nonce)?,
        &crypto::Key::try_from_slice(&key)?,
    )?)
}

#[cfg(feature = "crypto-seal")]
#[wasm_bindgen(js_name = cryptoBoxSeal)]
pub fn crypto_box_seal(data_b64: &str, recipient_public_key_b64: &str) -> Result<String, Error> {
    let data = b64::decode(data_b64)?;
    let pk = b64::decode(recipient_public_key_b64)?;
    let sealed = crypto::sealed::seal(&data, &crypto::PublicKey::try_from_slice(&pk)?)?;
    Ok(b64::encode(&sealed))
}
