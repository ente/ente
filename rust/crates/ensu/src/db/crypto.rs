use ente_core::crypto::{self, Header, Key, blob};

use crate::db::{Error, Result};

pub const HEADER_BYTES: usize = blob::HEADER_BYTES;
pub const KEY_BYTES: usize = blob::KEY_BYTES;

pub fn encrypt_blob(plaintext: &[u8], key: &[u8]) -> Result<Vec<u8>> {
    Ok(blob::encrypt_combined(
        plaintext,
        &Key::try_from_slice(key)?,
    )?)
}

pub fn decrypt_blob(data: &[u8], key: &[u8]) -> Result<Vec<u8>> {
    if data.len() < HEADER_BYTES {
        return Err(Error::InvalidBlobLength {
            minimum: HEADER_BYTES,
            actual: data.len(),
        });
    }
    let (header, ciphertext) = data.split_at(HEADER_BYTES);
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
    let plaintext = decrypt_blob(data, key)?;
    Ok(String::from_utf8(plaintext)?)
}

pub fn encrypt_json_field(value: &str, key: &[u8]) -> Result<String> {
    let encrypted = blob::encrypt(value.as_bytes(), &Key::try_from_slice(key)?)?;
    let ciphertext_b64 = crypto::encode_b64(&encrypted.encrypted_data);
    let header_b64 = crypto::encode_b64(encrypted.decryption_header.as_bytes());
    Ok(format!("enc:v1:{ciphertext_b64}:{header_b64}"))
}

pub fn decrypt_json_field(value: &str, key: &[u8]) -> Result<String> {
    let mut parts = value.split(':');
    let prefix = parts.next();
    let version = parts.next();
    let ciphertext_b64 = parts.next();
    let header_b64 = parts.next();
    if prefix != Some("enc") || version != Some("v1") || parts.next().is_some() {
        return Err(Error::InvalidEncryptedField);
    }
    let ciphertext_b64 = ciphertext_b64.ok_or(Error::InvalidEncryptedField)?;
    let header_b64 = header_b64.ok_or(Error::InvalidEncryptedField)?;
    let ciphertext = crypto::decode_b64(ciphertext_b64)?;
    let header = crypto::decode_b64(header_b64)?;
    let header = Header::try_from_slice(&header).map_err(|_| Error::InvalidEncryptedField)?;
    let plaintext = blob::decrypt(&ciphertext, &header, &Key::try_from_slice(key)?)?;
    Ok(String::from_utf8(plaintext)?)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn blob_roundtrip() {
        let key = vec![7u8; KEY_BYTES];
        let plaintext = b"hello";

        let encrypted = encrypt_blob(plaintext, &key).unwrap();
        assert!(encrypted.len() > plaintext.len());

        let decrypted = decrypt_blob(&encrypted, &key).unwrap();
        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn json_field_roundtrip() {
        let key = vec![9u8; KEY_BYTES];
        let plaintext = "file-name.png";

        let encrypted = encrypt_json_field(plaintext, &key).unwrap();
        assert!(encrypted.starts_with("enc:v1:"));

        let decrypted = decrypt_json_field(&encrypted, &key).unwrap();
        assert_eq!(decrypted, plaintext);
    }
}
