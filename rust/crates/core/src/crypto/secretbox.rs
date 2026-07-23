//! Authenticated encryption with XSalsa20-Poly1305.
//!
//! SecretBox encrypts and authenticates a single, self-contained value with a
//! 256-bit key. It suits small, independent pieces of data such as a wrapped
//! key or a short field. Ente uses [`blob`](super::blob) for data attached to
//! an object (file or collection metadata and the like), and
//! [`stream`](super::stream) for file contents, which are encrypted in chunks.
//!
//! The name comes from libsodium, which exposes this same construction as
//! `crypto_secretbox`; the implementation here is pure Rust but wire-compatible
//! (recorded per function below).
//!
//! Every message uses a 192-bit nonce, generated fresh on each call. It is not
//! secret, but it is needed to decrypt.
//!
//! Two payload shapes are offered, differing only in how the nonce travels:
//!
//! - Split ([`encrypt`] / [`decrypt`]): the ciphertext (`MAC ‖ ct`) and the
//!   nonce are returned separately.
//!
//! - Combined ([`encrypt_combined`] / [`decrypt_combined`]): the nonce is
//!   prepended to the ciphertext to form one self-contained buffer
//!   (`nonce ‖ MAC ‖ ct`).

use xsalsa20poly1305::XSalsa20Poly1305;
use xsalsa20poly1305::aead::generic_array::GenericArray;
use xsalsa20poly1305::aead::{Aead, KeyInit};

use crate::crypto::{Error, Key, Nonce, Result};

/// Size in bytes of the Poly1305 authentication tag that prefixes every
/// ciphertext.
///
/// Same as libsodium's `crypto_secretbox_MACBYTES`.
pub const MAC_BYTES: usize = 16;

/// A secretbox ciphertext together with the nonce needed to open it, as
/// returned by [`encrypt`].
///
/// This is the split shape, with the nonce held separately from the ciphertext;
/// see the module docs for the combined alternative.
#[derive(Debug, Clone, PartialEq)]
pub struct EncryptedBox {
    /// The Poly1305 tag followed by the ciphertext: `MAC (16 bytes) ‖ ciphertext`.
    pub encrypted_data: Vec<u8>,
    /// The nonce that encrypted [`encrypted_data`](Self::encrypted_data). Needed
    /// to decrypt, and not secret, but never reused with the same key.
    pub nonce: Nonce,
}

impl EncryptedBox {
    /// Decrypt this box with `key`, returning the plaintext.
    ///
    /// A convenience wrapper over [`decrypt`] using the stored ciphertext and
    /// nonce; see it for the error cases.
    pub fn decrypt(&self, key: &Key) -> Result<Vec<u8>> {
        decrypt(&self.encrypted_data, &self.nonce, key)
    }
}

/// Encrypt `data` with `key` and a freshly generated random nonce.
///
/// Returns the ciphertext and the nonce; decrypt with [`decrypt`] or
/// [`EncryptedBox::decrypt`]. The plaintext is not padded, so the ciphertext
/// length reveals the exact plaintext length.
///
/// Wire-compatible with libsodium's `crypto_secretbox_easy`.
pub fn encrypt(data: &[u8], key: &Key) -> EncryptedBox {
    let nonce = Nonce::generate();
    let encrypted_data = encrypt_with_nonce(data, &nonce, key);
    EncryptedBox {
        encrypted_data,
        nonce,
    }
}

/// Shared back end for [`encrypt`] and [`encrypt_combined`]: encrypts `data`
/// with `key` and the given `nonce`, returning `MAC ‖ ciphertext`. Both
/// callers generate a fresh nonce, so a (key, nonce) pair is never reused.
fn encrypt_with_nonce(data: &[u8], nonce: &Nonce, key: &Key) -> Vec<u8> {
    let cipher = XSalsa20Poly1305::new(GenericArray::from_slice(key.as_bytes()));
    let nonce_ga = GenericArray::from_slice(nonce.as_bytes());

    // The underlying AEAD encrypt only fails on plaintexts exceeding the
    // cipher's size bounds, which cannot be reached with in-memory slices.
    cipher
        .encrypt(nonce_ga, data)
        .expect("XSalsa20-Poly1305 encryption cannot fail for in-memory plaintexts")
}

/// Decrypt a ciphertext produced by [`encrypt`].
///
/// Pass the same `nonce` and `key` that encrypted it. `data` is
/// `MAC (16 bytes) ‖ ciphertext`. The Poly1305 tag is verified before any
/// plaintext is returned, so a successful result is also proof that the
/// ciphertext was not altered.
///
/// # Errors
///
/// Returns [`CiphertextTooShort`](Error::CiphertextTooShort) if `data` is
/// smaller than the tag, or [`DecryptionFailed`](Error::DecryptionFailed)
/// if the tag does not verify, which is the case whenever the key, nonce, or
/// ciphertext is wrong or the data was tampered with.
///
/// Wire-compatible with libsodium's `crypto_secretbox_open_easy`.
pub fn decrypt(data: &[u8], nonce: &Nonce, key: &Key) -> Result<Vec<u8>> {
    if data.len() < MAC_BYTES {
        return Err(Error::CiphertextTooShort {
            minimum: MAC_BYTES,
            actual: data.len(),
        });
    }

    let cipher = XSalsa20Poly1305::new(GenericArray::from_slice(key.as_bytes()));
    let nonce_ga = GenericArray::from_slice(nonce.as_bytes());

    cipher
        .decrypt(nonce_ga, data)
        .map_err(|_| Error::DecryptionFailed)
}

/// Encrypt `data` with `key` into one self-contained buffer.
///
/// Like [`encrypt`], but prepends a random nonce to the ciphertext,
/// returning `nonce (24 bytes) ‖ MAC (16 bytes) ‖ ciphertext`: everything
/// needed to decrypt except the key. Prefer this when a single opaque blob is
/// easier to store or pass around than a separate ciphertext and nonce. Decrypt
/// with [`decrypt_combined`].
///
/// The `MAC ‖ ciphertext` body is wire-compatible with libsodium's
/// `crypto_secretbox_easy`; prepending the nonce is an Ente convention, not part
/// of libsodium itself.
pub fn encrypt_combined(data: &[u8], key: &Key) -> Vec<u8> {
    let nonce = Nonce::generate();
    let encrypted = encrypt_with_nonce(data, &nonce, key);

    let mut combined = Vec::with_capacity(Nonce::BYTES + encrypted.len());
    combined.extend_from_slice(nonce.as_bytes());
    combined.extend_from_slice(&encrypted);
    combined
}

/// Decrypt a combined buffer produced by [`encrypt_combined`].
///
/// Splits the leading nonce from the `MAC ‖ ciphertext` body, then verifies the
/// tag and decrypts as [`decrypt`] does.
///
/// # Errors
///
/// Returns [`CiphertextTooShort`](Error::CiphertextTooShort) if `data` is
/// too short to hold a nonce and tag, otherwise the same errors as [`decrypt`].
///
/// The body is wire-compatible with libsodium's `crypto_secretbox_open_easy`;
/// the leading nonce is an Ente convention.
pub fn decrypt_combined(data: &[u8], key: &Key) -> Result<Vec<u8>> {
    if data.len() < Nonce::BYTES + MAC_BYTES {
        return Err(Error::CiphertextTooShort {
            minimum: Nonce::BYTES + MAC_BYTES,
            actual: data.len(),
        });
    }

    let (nonce, encrypted) = data.split_at(Nonce::BYTES);
    decrypt(encrypted, &Nonce::try_from_slice(nonce)?, key)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encrypt_decrypt() {
        let key = Key::generate();
        let plaintext = b"Hello, World!";

        let encrypted = encrypt(plaintext, &key);
        assert_eq!(encrypted.encrypted_data.len(), MAC_BYTES + plaintext.len());

        let decrypted = encrypted.decrypt(&key).unwrap();
        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn test_encrypt_with_nonce_is_deterministic() {
        let key = Key::generate();
        let nonce = Nonce::generate();
        let plaintext = b"Deterministic test";

        let encrypted1 = encrypt_with_nonce(plaintext, &nonce, &key);
        let encrypted2 = encrypt_with_nonce(plaintext, &nonce, &key);
        assert_eq!(encrypted1, encrypted2);

        let decrypted = decrypt(&encrypted1, &nonce, &key).unwrap();
        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn test_different_nonces_produce_different_ciphertexts() {
        let key = Key::generate();
        let plaintext = b"Same plaintext";

        let encrypted1 = encrypt(plaintext, &key);
        let encrypted2 = encrypt(plaintext, &key);
        assert_ne!(encrypted1, encrypted2);

        assert_eq!(encrypted1.decrypt(&key).unwrap(), plaintext);
        assert_eq!(encrypted2.decrypt(&key).unwrap(), plaintext);
    }

    #[test]
    fn test_combined_roundtrip() {
        let key = Key::generate();
        let plaintext = b"Combined format test";

        let combined = encrypt_combined(plaintext, &key);
        assert_eq!(combined.len(), Nonce::BYTES + MAC_BYTES + plaintext.len());

        let decrypted = decrypt_combined(&combined, &key).unwrap();
        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn test_combined_is_split_with_nonce_prefix() {
        // The combined format must be exactly nonce ‖ (split ciphertext), so
        // the two shapes stay interconvertible.
        let key = Key::generate();
        let plaintext = b"Interop test";

        let combined = encrypt_combined(plaintext, &key);
        let (nonce, encrypted) = combined.split_at(Nonce::BYTES);
        let decrypted = decrypt(encrypted, &Nonce::try_from_slice(nonce).unwrap(), &key).unwrap();
        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn test_wrong_key_fails() {
        let key = Key::generate();
        let wrong_key = Key::generate();

        let encrypted = encrypt(b"Secret", &key);
        assert!(encrypted.decrypt(&wrong_key).is_err());

        let combined = encrypt_combined(b"Secret", &key);
        assert!(decrypt_combined(&combined, &wrong_key).is_err());
    }

    #[test]
    fn test_corrupted_ciphertext_fails() {
        let key = Key::generate();

        let mut encrypted = encrypt(b"Original", &key);
        let mid = encrypted.encrypted_data.len() / 2;
        encrypted.encrypted_data[mid] ^= 1;

        assert!(matches!(
            encrypted.decrypt(&key),
            Err(Error::DecryptionFailed)
        ));
    }

    #[test]
    fn test_ciphertext_too_short() {
        let key = Key::generate();

        assert!(matches!(
            decrypt(&[0u8; 10], &Nonce::generate(), &key),
            Err(Error::CiphertextTooShort { .. })
        ));
        assert!(matches!(
            decrypt_combined(&[0u8; 30], &key),
            Err(Error::CiphertextTooShort { .. })
        ));
    }

    #[test]
    fn test_empty_plaintext() {
        let key = Key::generate();

        let encrypted = encrypt(b"", &key);
        assert_eq!(encrypted.decrypt(&key).unwrap(), b"");

        let combined = encrypt_combined(b"", &key);
        assert_eq!(decrypt_combined(&combined, &key).unwrap(), b"");
    }

    #[test]
    fn test_large_plaintext() {
        let key = Key::generate();
        let plaintext = vec![0x42u8; 1024 * 1024]; // 1 MB

        let encrypted = encrypt(&plaintext, &key);
        assert_eq!(encrypted.decrypt(&key).unwrap(), plaintext);
    }
}
