//! Authenticated encryption of a single value with XChaCha20-Poly1305.
//!
//! A blob is one secretstream message: the data is encrypted and authenticated
//! in a single shot, without the chunking that [`stream`](super::stream) applies
//! to large file contents. Ente uses it for the small, bounded values attached
//! to an object, such as file or collection metadata.
//! ([`secretbox`](super::secretbox) fills the same single-value role for data
//! not tied to an object.)
//!
//! The construction is libsodium's secretstream
//! (`crypto_secretstream_xchacha20poly1305`), driven here for a single message
//! tagged final; the implementation is pure Rust but wire-compatible (recorded
//! per function below). Unlike a secretbox nonce, the per-message randomness
//! lives in a `header` that secretstream generates during encryption.
//!
//! Two payload shapes are offered, differing only in how the header travels:
//!
//! - Split ([`encrypt`] / [`decrypt`]): the ciphertext and the decryption
//!   header are returned separately.
//!
//! - Combined ([`encrypt_combined`] / [`decrypt_combined`]): the header is
//!   prepended to the ciphertext to form one self-contained buffer
//!   (`header ‖ ciphertext`).

use super::stream::{Decryptor, Encryptor};
use crate::crypto::{CryptoError, Header, Key, Result};

/// Size of the encryption key in bytes.
pub const KEY_BYTES: usize = Key::BYTES;

/// Size of the decryption header in bytes.
pub const HEADER_BYTES: usize = Header::BYTES;

/// Overhead (tag + MAC) added to the plaintext by encryption.
pub use super::stream::ABYTES;

/// A blob ciphertext together with the header needed to open it, as returned by
/// [`encrypt`].
///
/// This is the split shape, with the header held separately from the
/// ciphertext; see the module docs for the combined alternative.
#[derive(Debug, Clone)]
pub struct EncryptedBlob {
    /// The encrypted data: one secretstream message, [`ABYTES`] bytes longer
    /// than the plaintext.
    pub encrypted_data: Vec<u8>,
    /// The header that secretstream produced while encrypting. Needed to
    /// decrypt, and not secret.
    pub decryption_header: Header,
}

impl EncryptedBlob {
    /// Decrypt this blob with `key`, returning the plaintext.
    ///
    /// A convenience wrapper over [`decrypt`] using the stored ciphertext and
    /// header; see it for the error cases.
    pub fn decrypt(&self, key: &Key) -> Result<Vec<u8>> {
        decrypt(&self.encrypted_data, &self.decryption_header, key)
    }
}

/// Encrypt `data` with `key` as a single secretstream message.
///
/// A fresh header is generated for every call. The message is tagged final, so
/// [`decrypt`] can later confirm the ciphertext is complete. Returns the
/// ciphertext and that header; decrypt with [`decrypt`] or
/// [`EncryptedBlob::decrypt`].
///
/// Wire-compatible with libsodium's secretstream, as one message tagged
/// `TAG_FINAL` (`crypto_secretstream_xchacha20poly1305`).
pub fn encrypt(data: &[u8], key: &Key) -> Result<EncryptedBlob> {
    let mut encryptor = Encryptor::new(key);
    let decryption_header = *encryptor.header();
    let encrypted_data = encryptor.push(data, true)?;

    Ok(EncryptedBlob {
        encrypted_data,
        decryption_header,
    })
}

/// Decrypt a blob produced by [`encrypt`], using its `header` and `key`.
///
/// The message must carry the secretstream final tag, which proves it was not
/// truncated; its Poly1305 MAC proves it was not otherwise altered. Data
/// written by older clients without the final tag is rejected here; use
/// [`decrypt_legacy`] for it.
///
/// # Errors
///
/// Returns [`CiphertextTooShort`](CryptoError::CiphertextTooShort) if `data` is
/// smaller than the per-message overhead,
/// [`StreamTruncated`](CryptoError::StreamTruncated) if the final tag is absent,
/// or [`StreamPullFailed`](CryptoError::StreamPullFailed) if the MAC does not
/// verify, which happens when the key or header is wrong or the data was
/// tampered with.
///
/// Wire-compatible with libsodium's `crypto_secretstream_xchacha20poly1305`.
pub fn decrypt(data: &[u8], header: &Header, key: &Key) -> Result<Vec<u8>> {
    let (plaintext, is_final) = decrypt_impl(data, header, key)?;
    if !is_final {
        return Err(CryptoError::StreamTruncated);
    }
    Ok(plaintext)
}

/// Decrypt a blob that might be missing the secretstream final tag.
///
/// Same as [`decrypt`], but it doesn't require the final tag, so it can't tell
/// whether the blob was cut short. The MAC still guarantees that whatever it
/// returns wasn't tampered with. Use this only to read old data written without
/// the tag; use [`decrypt`] everywhere else.
///
/// Affected blobs: Auth's authenticator entities, pre Nov-2025. Locker also
/// briefly did this, but only in internal builds pre-launch; no public Locker
/// release was affected.
///
/// # Errors
///
/// Same as [`decrypt`], except it never returns
/// [`StreamTruncated`](CryptoError::StreamTruncated).
pub fn decrypt_legacy(data: &[u8], header: &Header, key: &Key) -> Result<Vec<u8>> {
    Ok(decrypt_impl(data, header, key)?.0)
}

fn decrypt_impl(data: &[u8], header: &Header, key: &Key) -> Result<(Vec<u8>, bool)> {
    if data.len() < ABYTES {
        return Err(CryptoError::CiphertextTooShort {
            minimum: ABYTES,
            actual: data.len(),
        });
    }

    let mut decryptor = Decryptor::new(header, key);
    decryptor.pull(data)
}

/// Encrypt `data` with `key` into one self-contained buffer.
///
/// Like [`encrypt`], but prepends the decryption header to the ciphertext,
/// returning `header ‖ ciphertext`: everything needed to decrypt except the
/// key. Prefer this when a single opaque blob is easier to store or pass around
/// than a separate ciphertext and header. Decrypt with [`decrypt_combined`].
///
/// Wire-compatible with libsodium's secretstream, storing the header ahead of
/// the single message.
pub fn encrypt_combined(data: &[u8], key: &Key) -> Result<Vec<u8>> {
    let encrypted = encrypt(data, key)?;
    let mut combined = Vec::with_capacity(Header::BYTES + encrypted.encrypted_data.len());
    combined.extend_from_slice(encrypted.decryption_header.as_bytes());
    combined.extend_from_slice(&encrypted.encrypted_data);
    Ok(combined)
}

/// Decrypt a combined buffer produced by [`encrypt_combined`].
///
/// Splits the leading header from the ciphertext, then decrypts as [`decrypt`]
/// does.
///
/// # Errors
///
/// Returns [`CiphertextTooShort`](CryptoError::CiphertextTooShort) if `data` is
/// too short to hold a header and one message, otherwise the same errors as
/// [`decrypt`].
pub fn decrypt_combined(data: &[u8], key: &Key) -> Result<Vec<u8>> {
    if data.len() < Header::BYTES + ABYTES {
        return Err(CryptoError::CiphertextTooShort {
            minimum: Header::BYTES + ABYTES,
            actual: data.len(),
        });
    }

    let (header, ciphertext) = data.split_at(Header::BYTES);
    decrypt(ciphertext, &Header::try_from_slice(header)?, key)
}

/// Serialize `value` to JSON and encrypt it as a blob.
///
/// The inverse is [`decrypt_json`].
pub fn encrypt_json<T: serde::Serialize>(value: &T, key: &Key) -> Result<EncryptedBlob> {
    let json = serde_json::to_vec(value)
        .map_err(|e| CryptoError::Json(format!("JSON serialization failed: {}", e)))?;
    encrypt(&json, key)
}

/// Serialize `value` to JSON and encrypt it into one combined buffer.
///
/// Like [`encrypt_json`] but using [`encrypt_combined`]; the inverse is
/// [`decrypt_json_combined`].
pub fn encrypt_json_combined<T: serde::Serialize>(value: &T, key: &Key) -> Result<Vec<u8>> {
    let json = serde_json::to_vec(value)
        .map_err(|e| CryptoError::Json(format!("JSON serialization failed: {}", e)))?;
    encrypt_combined(&json, key)
}

/// Decrypt a blob and deserialize its plaintext from JSON into `T`.
///
/// The inverse of [`encrypt_json`].
pub fn decrypt_json<T: serde::de::DeserializeOwned>(blob: &EncryptedBlob, key: &Key) -> Result<T> {
    let plaintext = blob.decrypt(key)?;
    serde_json::from_slice(&plaintext)
        .map_err(|e| CryptoError::Json(format!("JSON deserialization failed: {}", e)))
}

/// Decrypt a combined buffer and deserialize its plaintext from JSON into `T`.
///
/// The inverse of [`encrypt_json_combined`].
pub fn decrypt_json_combined<T: serde::de::DeserializeOwned>(
    combined: &[u8],
    key: &Key,
) -> Result<T> {
    let plaintext = decrypt_combined(combined, key)?;
    serde_json::from_slice(&plaintext)
        .map_err(|e| CryptoError::Json(format!("JSON deserialization failed: {}", e)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encrypt_decrypt() {
        let key = Key::generate();
        let plaintext = b"Hello, World!";

        let encrypted = encrypt(plaintext, &key).unwrap();
        assert_eq!(encrypted.encrypted_data.len(), plaintext.len() + ABYTES);

        let decrypted = encrypted.decrypt(&key).unwrap();
        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn test_decrypt_requires_final_tag() {
        let key = Key::generate();
        let mut encryptor = Encryptor::new(&key);
        let header = *encryptor.header();
        let ciphertext = encryptor.push(b"partial", false).unwrap();

        assert!(matches!(
            decrypt(&ciphertext, &header, &key),
            Err(CryptoError::StreamTruncated)
        ));
    }

    #[test]
    fn test_decrypt_legacy_tolerates_missing_final_tag() {
        let key = Key::generate();
        let mut encryptor = Encryptor::new(&key);
        let header = *encryptor.header();
        let ciphertext = encryptor.push(b"partial", false).unwrap();

        let decrypted = decrypt_legacy(&ciphertext, &header, &key).unwrap();
        assert_eq!(decrypted, b"partial");
    }

    #[test]
    fn test_encrypt_decrypt_large() {
        let key = Key::generate();
        let plaintext = vec![0x42u8; 1024 * 1024]; // 1 MB

        let encrypted = encrypt(&plaintext, &key).unwrap();
        assert_eq!(encrypted.decrypt(&key).unwrap(), plaintext);
    }

    #[test]
    fn test_encrypt_decrypt_combined() {
        let key = Key::generate();
        let plaintext = b"Combined blob payload";

        let encrypted = encrypt_combined(plaintext, &key).unwrap();
        assert_eq!(decrypt_combined(&encrypted, &key).unwrap(), plaintext);
    }

    #[test]
    fn test_encrypt_decrypt_json_combined() {
        let key = Key::generate();
        let value = serde_json::json!({
            "name": "Alice",
            "birthDate": "2001-04-01"
        });

        let encrypted = encrypt_json_combined(&value, &key).unwrap();
        let decrypted: serde_json::Value = decrypt_json_combined(&encrypted, &key).unwrap();

        assert_eq!(decrypted, value);
    }

    #[test]
    fn test_wrong_key_fails() {
        let key1 = Key::generate();
        let key2 = Key::generate();

        let encrypted = encrypt(b"Secret message", &key1).unwrap();
        assert!(matches!(
            encrypted.decrypt(&key2),
            Err(CryptoError::StreamPullFailed)
        ));
    }

    #[test]
    fn test_empty_plaintext() {
        let key = Key::generate();

        let encrypted = encrypt(b"", &key).unwrap();
        assert_eq!(encrypted.decrypt(&key).unwrap(), b"");
    }

    #[test]
    fn test_encrypt_decrypt_json() {
        let key = Key::generate();

        #[derive(serde::Serialize, serde::Deserialize, Debug, PartialEq)]
        struct TestData {
            name: String,
            value: i32,
        }

        let data = TestData {
            name: "test".to_string(),
            value: 42,
        };

        let encrypted = encrypt_json(&data, &key).unwrap();
        let decrypted: TestData = decrypt_json(&encrypted, &key).unwrap();
        assert_eq!(decrypted, data);
    }

    #[test]
    fn test_decrypt_json_wrong_type_returns_json_error() {
        let key = Key::generate();

        #[derive(serde::Serialize)]
        struct Original {
            name: String,
        }

        #[derive(serde::Deserialize, Debug)]
        #[allow(dead_code)]
        struct Different {
            count: u64,
        }

        let encrypted = encrypt_json(
            &Original {
                name: "test".to_string(),
            },
            &key,
        )
        .unwrap();

        // Decrypt into a mismatched type; should be CryptoError::Json
        let result: std::result::Result<Different, _> = decrypt_json(&encrypted, &key);
        assert!(
            matches!(result, Err(CryptoError::Json(_))),
            "Expected CryptoError::Json, got: {:?}",
            result
        );
    }

    #[test]
    fn test_ciphertext_too_short() {
        let key = Key::generate();
        let header = Header::try_from_slice(&[0u8; Header::BYTES]).unwrap();

        assert!(matches!(
            decrypt(&[0u8; ABYTES - 1], &header, &key),
            Err(CryptoError::CiphertextTooShort { .. })
        ));
    }

    #[test]
    fn test_corrupted_ciphertext() {
        let key = Key::generate();

        let mut encrypted = encrypt(b"Original data", &key).unwrap();
        encrypted.encrypted_data[10] ^= 1;

        assert!(encrypted.decrypt(&key).is_err());
    }

    #[test]
    fn test_corrupted_header() {
        let key = Key::generate();

        let encrypted = encrypt(b"Original data", &key).unwrap();
        let mut header_bytes = *encrypted.decryption_header.as_bytes();
        header_bytes[5] ^= 1;

        assert!(
            decrypt(
                &encrypted.encrypted_data,
                &Header::from_bytes(header_bytes),
                &key
            )
            .is_err()
        );
    }

    #[test]
    fn test_same_plaintext_produces_different_ciphertexts() {
        let key = Key::generate();
        let plaintext = b"Same message";

        let encrypted1 = encrypt(plaintext, &key).unwrap();
        let encrypted2 = encrypt(plaintext, &key).unwrap();

        // Different headers (random) -> different ciphertexts
        assert_ne!(encrypted1.decryption_header, encrypted2.decryption_header);
        assert_ne!(encrypted1.encrypted_data, encrypted2.encrypted_data);

        assert_eq!(encrypted1.decrypt(&key).unwrap(), plaintext);
        assert_eq!(encrypted2.decrypt(&key).unwrap(), plaintext);
    }
}
