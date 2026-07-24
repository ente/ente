use ente_core::crypto;
use serde::{Deserialize, Serialize};

use crate::commands::common::ApiError;

impl From<crypto::Error> for ApiError {
    fn from(e: crypto::Error) -> Self {
        use crypto::Error as E;

        let code = match &e {
            E::Base64Decode(_) => "base64_decode",
            E::InvalidKeyLength { .. } => "invalid_key_length",
            E::InvalidNonceLength { .. } => "invalid_nonce_length",
            E::InvalidSaltLength { .. } => "invalid_salt_length",
            E::InvalidHeaderLength { .. } => "invalid_header_length",
            E::CiphertextTooShort { .. } => "ciphertext_too_short",
            E::InvalidKeyDerivationParams(_) => "invalid_kdf_params",
            E::KeyDerivationFailed => "key_derivation_failed",
            E::EncryptionFailed => "encryption_failed",
            E::DecryptionFailed => "decryption_failed",
            E::StreamInitFailed => "stream_init_failed",
            E::StreamPushFailed => "stream_push_failed",
            E::StreamPullFailed => "stream_pull_failed",
            E::StreamTruncated => "stream_truncated",
            E::StreamTrailingData => "stream_trailing_data",
            E::SealedBoxOpenFailed => "sealed_box_open_failed",
            E::InvalidPublicKey => "invalid_public_key",
            E::Json(_) => "json",
            E::Argon2(_) => "argon2",
            E::Aead => "aead",
            E::ArrayConversion => "array_conversion",
            E::Io(_) => "io",
        };

        ApiError::new(code, e.to_string())
    }
}

#[derive(Serialize)]
pub struct EncryptedBlob {
    encrypted_data: String,
    decryption_header: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CryptoBlobInput {
    data_b64: String,
    key_b64: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CryptoBlobDecryptInput {
    encrypted_data_b64: String,
    header_b64: String,
    key_b64: String,
}

#[tauri::command]
pub fn crypto_init() -> Result<(), ApiError> {
    // No-op, kept only for frontend compatibility: the pure-Rust crypto
    // needs no initialization.
    Ok(())
}

#[tauri::command]
pub fn crypto_generate_key() -> String {
    crypto::encode_b64(crypto::Key::generate().as_bytes())
}

#[tauri::command]
pub fn crypto_encrypt_blob(input: CryptoBlobInput) -> Result<EncryptedBlob, ApiError> {
    let data = crypto::decode_b64(&input.data_b64).map_err(ApiError::from)?;
    let key = crypto::decode_b64(&input.key_b64).map_err(ApiError::from)?;
    let key = crypto::Key::try_from_slice(&key).map_err(ApiError::from)?;
    let out = crypto::blob::encrypt(&data, &key).map_err(ApiError::from)?;
    Ok(EncryptedBlob {
        encrypted_data: crypto::encode_b64(&out.encrypted_data),
        decryption_header: crypto::encode_b64(out.decryption_header.as_bytes()),
    })
}

#[tauri::command]
pub fn crypto_decrypt_blob(input: CryptoBlobDecryptInput) -> Result<String, ApiError> {
    let ciphertext = crypto::decode_b64(&input.encrypted_data_b64).map_err(ApiError::from)?;
    let header = crypto::decode_b64(&input.header_b64).map_err(ApiError::from)?;
    let key = crypto::decode_b64(&input.key_b64).map_err(ApiError::from)?;
    let header = crypto::Header::try_from_slice(&header).map_err(ApiError::from)?;
    let key = crypto::Key::try_from_slice(&key).map_err(ApiError::from)?;
    let plaintext = crypto::blob::decrypt(&ciphertext, &header, &key).map_err(ApiError::from)?;
    Ok(crypto::encode_b64(&plaintext))
}
