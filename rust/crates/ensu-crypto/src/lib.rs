use ente_core::{
    b64,
    crypto::{self, Header, Key, blob},
};
use hkdf::Hkdf;
use sha2::Sha256;
use thiserror::Error;

const ATTACHMENT_KEY_INFO: &[u8] = b"llmchat_attachment_v1";

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Debug, Error)]
pub enum Error {
    #[error("invalid blob length: expected at least {minimum} bytes, got {actual}")]
    InvalidBlobLength { minimum: usize, actual: usize },

    #[error("invalid encrypted field format")]
    InvalidEncryptedField,

    #[error(transparent)]
    Crypto(#[from] crypto::Error),

    #[error(transparent)]
    Base64Decode(#[from] b64::DecodeError),

    #[error(transparent)]
    Utf8(#[from] std::string::FromUtf8Error),
}

impl Error {
    pub fn code(&self) -> &'static str {
        match self {
            Self::InvalidBlobLength { .. } => "invalid_blob_length",
            Self::InvalidEncryptedField => "invalid_encrypted_field",
            Self::Crypto(error) => error.code(),
            Self::Base64Decode(_) => "base64_decode",
            Self::Utf8(_) => "invalid_utf8",
        }
    }
}

pub struct EncryptedChatPayload {
    pub encrypted_data: String,
    pub header: String,
}

pub fn generate_chat_key() -> String {
    b64::encode(Key::generate().as_bytes())
}

pub fn encrypt_payload(value: &str, key_b64: &str) -> Result<EncryptedChatPayload> {
    let encrypted = blob::encrypt(value.as_bytes(), &key_from_b64(key_b64)?)?;
    Ok(EncryptedChatPayload {
        encrypted_data: b64::encode(&encrypted.encrypted_data),
        header: b64::encode(encrypted.decryption_header.as_bytes()),
    })
}

pub fn decrypt_payload(
    encrypted_data_b64: &str,
    header_b64: &str,
    key_b64: &str,
) -> Result<String> {
    let encrypted_data = b64::decode(encrypted_data_b64)?;
    let header = b64::decode(header_b64)?;
    let plaintext = blob::decrypt(
        &encrypted_data,
        &Header::try_from_slice(&header)?,
        &key_from_b64(key_b64)?,
    )?;
    Ok(String::from_utf8(plaintext)?)
}

pub fn encrypt_field_b64(value: &str, key_b64: &str) -> Result<String> {
    encrypt_json_field(value, &b64::decode(key_b64)?)
}

pub fn decrypt_field_b64(value: &str, key_b64: &str) -> Result<String> {
    decrypt_json_field(value, &b64::decode(key_b64)?)
}

pub fn encrypt_attachment(data: &[u8], chat_key_b64: &str, session_uuid: &str) -> Result<Vec<u8>> {
    encrypt_blob(data, attachment_key(chat_key_b64, session_uuid)?.as_bytes())
}

pub fn decrypt_attachment(data: &[u8], chat_key_b64: &str, session_uuid: &str) -> Result<Vec<u8>> {
    decrypt_blob(data, attachment_key(chat_key_b64, session_uuid)?.as_bytes())
}

pub fn encrypt_blob(plaintext: &[u8], key: &[u8]) -> Result<Vec<u8>> {
    Ok(blob::encrypt_combined(
        plaintext,
        &Key::try_from_slice(key)?,
    )?)
}

pub fn decrypt_blob(data: &[u8], key: &[u8]) -> Result<Vec<u8>> {
    if data.len() < Header::BYTES {
        return Err(Error::InvalidBlobLength {
            minimum: Header::BYTES,
            actual: data.len(),
        });
    }
    let (header, ciphertext) = data.split_at(Header::BYTES);
    Ok(blob::decrypt(
        ciphertext,
        &Header::try_from_slice(header)?,
        &Key::try_from_slice(key)?,
    )?)
}

pub fn encrypt_string(value: &str, key: &[u8]) -> Result<Vec<u8>> {
    encrypt_blob(value.as_bytes(), key)
}

pub fn decrypt_string(data: &[u8], key: &[u8]) -> Result<String> {
    Ok(String::from_utf8(decrypt_blob(data, key)?)?)
}

pub fn encrypt_json_field(value: &str, key: &[u8]) -> Result<String> {
    let encrypted = blob::encrypt(value.as_bytes(), &Key::try_from_slice(key)?)?;
    let ciphertext_b64 = b64::encode(&encrypted.encrypted_data);
    let header_b64 = b64::encode(encrypted.decryption_header.as_bytes());
    Ok(format!("enc:v1:{ciphertext_b64}:{header_b64}"))
}

pub fn decrypt_json_field(value: &str, key: &[u8]) -> Result<String> {
    let mut parts = value.split(':');
    if parts.next() != Some("enc") || parts.next() != Some("v1") {
        return Err(Error::InvalidEncryptedField);
    }
    let ciphertext = parts.next().ok_or(Error::InvalidEncryptedField)?;
    let header = parts.next().ok_or(Error::InvalidEncryptedField)?;
    if parts.next().is_some() {
        return Err(Error::InvalidEncryptedField);
    }
    let ciphertext = b64::decode(ciphertext)?;
    let header = b64::decode(header)?;
    let header = Header::try_from_slice(&header).map_err(|_| Error::InvalidEncryptedField)?;
    let plaintext = blob::decrypt(&ciphertext, &header, &Key::try_from_slice(key)?)?;
    Ok(String::from_utf8(plaintext)?)
}

fn key_from_b64(value: &str) -> Result<Key> {
    Ok(Key::try_from_slice(&b64::decode(value)?)?)
}

fn attachment_key(chat_key_b64: &str, session_uuid: &str) -> Result<Key> {
    let chat_key = b64::decode(chat_key_b64)?;
    let mut key = [0; 32];
    Hkdf::<Sha256>::new(Some(session_uuid.as_bytes()), &chat_key)
        .expand(ATTACHMENT_KEY_INFO, &mut key)
        .map_err(|_| crypto::Error::KeyDerivationFailed)?;
    Ok(Key::try_from_slice(&key)?)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn payload_roundtrip() {
        let key = generate_chat_key();
        let encrypted = encrypt_payload(r#"{"text":"hello"}"#, &key).unwrap();
        assert_eq!(
            decrypt_payload(&encrypted.encrypted_data, &encrypted.header, &key).unwrap(),
            r#"{"text":"hello"}"#
        );
    }

    #[test]
    fn field_roundtrip() {
        let key = generate_chat_key();
        let encrypted = encrypt_field_b64("file-name.png", &key).unwrap();
        assert!(encrypted.starts_with("enc:v1:"));
        assert_eq!(
            decrypt_field_b64(&encrypted, &key).unwrap(),
            "file-name.png"
        );
    }

    #[test]
    fn attachment_roundtrip() {
        let key = generate_chat_key();
        let encrypted = encrypt_attachment(b"attachment", &key, "session-id").unwrap();
        assert_eq!(
            decrypt_attachment(&encrypted, &key, "session-id").unwrap(),
            b"attachment"
        );
    }

    #[test]
    fn attachment_key_matches_web_crypto() {
        let key = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=";
        let derived = attachment_key(key, "session-id").unwrap();
        assert_eq!(
            b64::encode(derived.as_bytes()),
            "zUVLxgcjyPjOhZIESIXtjOaA8z9L7BCVIBG2wkar5NI="
        );
    }
}
