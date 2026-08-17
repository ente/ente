use crypto_secretbox::XSalsa20Poly1305;
use crypto_secretbox::aead::generic_array::GenericArray;
use crypto_secretbox::aead::{Aead, KeyInit};

use crate::crypto::{Error, Key, Nonce, Result};

// Same as libsodium's `crypto_secretbox_MACBYTES`.
pub const MAC_BYTES: usize = 16;

#[derive(Debug, Clone, PartialEq)]
pub struct EncryptedBox {
    pub encrypted_data: Vec<u8>,
    pub nonce: Nonce,
}

impl EncryptedBox {
    pub fn decrypt(&self, key: &Key) -> Result<Vec<u8>> {
        decrypt(&self.encrypted_data, &self.nonce, key)
    }
}

// Wire-compatible with libsodium's `crypto_secretbox_easy`.
pub fn encrypt(data: &[u8], key: &Key) -> EncryptedBox {
    let nonce = Nonce::generate();
    let encrypted_data = encrypt_with_nonce(data, &nonce, key);
    EncryptedBox {
        encrypted_data,
        nonce,
    }
}

fn encrypt_with_nonce(data: &[u8], nonce: &Nonce, key: &Key) -> Vec<u8> {
    let cipher = XSalsa20Poly1305::new(GenericArray::from_slice(key.as_bytes()));
    let nonce_ga = GenericArray::from_slice(nonce.as_bytes());

    // The underlying AEAD encrypt only fails on plaintexts exceeding the
    // cipher's size bounds, which cannot be reached with in-memory slices.
    cipher
        .encrypt(nonce_ga, data)
        .expect("XSalsa20-Poly1305 encryption cannot fail for in-memory plaintexts")
}

// Wire-compatible with libsodium's `crypto_secretbox_open_easy`.
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

// The MAC || ciphertext body is wire-compatible with libsodium's
// `crypto_secretbox_easy`; prepending the nonce is an Ente convention.
pub fn encrypt_combined(data: &[u8], key: &Key) -> Vec<u8> {
    let nonce = Nonce::generate();
    let encrypted = encrypt_with_nonce(data, &nonce, key);

    let mut combined = Vec::with_capacity(Nonce::BYTES + encrypted.len());
    combined.extend_from_slice(nonce.as_bytes());
    combined.extend_from_slice(&encrypted);
    combined
}

// The body is wire-compatible with libsodium's `crypto_secretbox_open_easy`;
// the leading nonce is an Ente convention.
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
    fn test_nacl_vector() {
        // NaCl's tests/secretbox.c vector.
        let key = Key::try_from_slice(
            &crate::b64::decode("GydVZHPphdRizVEZeppGx2AJVJ6sZHTyBsTuCET2g4k=").unwrap(),
        )
        .unwrap();
        let nonce =
            Nonce::try_from_slice(&crate::b64::decode("aWlu6VW2K3PNYr2odfxz1oIZ4ANregs3").unwrap())
                .unwrap();
        let plaintext = crate::b64::decode(
            "vgdfxTyB8tXPFBMW6+sMe1IoxSpMYsvUS2aEm2QkT/zl7LqvM711GhrHKNRebGEpbNw8ASM1YfQdtmzOMUrbMQ476CUMRvBtzuo6f6E0gFfi9lVq1rExigJKg48hrx/eBIl360j1n/1JJMocYJAuUvCgibx2iXBA4IL5N3Y4SGReBwU=",
        )
        .unwrap();
        let ciphertext = crate::b64::decode(
            "8//HcD+UAOUqfftLPTMF2Y6ZO59IaBJzwpZQujL8ds5IMy6nFk2WpEdvuMUxoRhqwN/BfJjc6HtNp/AR7EjJcnHSwg+bko/iJw1vuGPVFzi0ju7jFKfMirkyFkVI5SaukCJDaFF6z+q9a7NzK8Dp2pmDK2HKAbbeViRKnojV+bN5c/YipD0UplmbH2VMtFp041Wl",
        )
        .unwrap();

        assert_eq!(encrypt_with_nonce(&plaintext, &nonce, &key), ciphertext);
        assert_eq!(decrypt(&ciphertext, &nonce, &key).unwrap(), plaintext);
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
        let plaintext = vec![0x42u8; 1024 * 1024];

        let encrypted = encrypt(&plaintext, &key);
        assert_eq!(encrypted.decrypt(&key).unwrap(), plaintext);
    }
}
