use blake2b_simd::Params as Blake2bParams;

use crate::crypto::{Key, Result, SecretVec};

pub const CONTEXT_BYTES: usize = 8;

pub const SUBKEY_BYTES_MIN: usize = 16;

pub const SUBKEY_BYTES_MAX: usize = 64;

pub const LOGIN_SUBKEY_LEN: usize = 32;

pub const LOGIN_SUBKEY_ID: u64 = 1;

pub const LOGIN_SUBKEY_CONTEXT: &[u8; CONTEXT_BYTES] = b"loginctx";

// Produces the same subkey as libsodium's `crypto_kdf_derive_from_key`.
pub fn derive_subkey(
    key: &Key,
    subkey_len: usize,
    subkey_id: u64,
    context: &[u8; CONTEXT_BYTES],
) -> Result<SecretVec> {
    if !(SUBKEY_BYTES_MIN..=SUBKEY_BYTES_MAX).contains(&subkey_len) {
        return Err(crate::crypto::Error::InvalidKeyLength {
            expected: SUBKEY_BYTES_MAX,
            actual: subkey_len,
        });
    }

    // Match libsodium's salt and personalization layout exactly.
    // Salt: subkey_id (8 bytes LE) || zeros (8 bytes).
    let mut salt = [0u8; 16];
    salt[0..8].copy_from_slice(&subkey_id.to_le_bytes());

    // Personalization: context (8 bytes) || zeros (8 bytes).
    let mut personal = [0u8; 16];
    personal[0..CONTEXT_BYTES].copy_from_slice(context);

    let hash = Blake2bParams::new()
        .hash_length(subkey_len)
        .key(key.as_bytes())
        .salt(&salt)
        .personal(&personal)
        .to_state()
        .finalize();

    Ok(SecretVec::new(hash.as_bytes()[..subkey_len].to_vec()))
}

pub fn derive_login_key(master_key: &Key) -> SecretVec {
    let subkey = derive_subkey(
        master_key,
        LOGIN_SUBKEY_LEN,
        LOGIN_SUBKEY_ID,
        LOGIN_SUBKEY_CONTEXT,
    )
    .expect("login subkey parameters are statically valid");
    SecretVec::new(subkey[..16].to_vec())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_key() -> Key {
        Key::from_bytes([0x42u8; Key::BYTES])
    }

    #[test]
    fn test_derive_subkey_deterministic() {
        let subkey1 = derive_subkey(&test_key(), 32, 1, b"context0").unwrap();
        let subkey2 = derive_subkey(&test_key(), 32, 1, b"context0").unwrap();
        assert_eq!(subkey1, subkey2);
    }

    #[test]
    fn test_different_subkey_ids() {
        let subkey1 = derive_subkey(&test_key(), 32, 1, b"context0").unwrap();
        let subkey2 = derive_subkey(&test_key(), 32, 2, b"context0").unwrap();
        assert_ne!(subkey1, subkey2);
    }

    #[test]
    fn test_different_contexts() {
        let subkey1 = derive_subkey(&test_key(), 32, 1, b"context1").unwrap();
        let subkey2 = derive_subkey(&test_key(), 32, 1, b"context2").unwrap();
        assert_ne!(subkey1, subkey2);
    }

    #[test]
    fn test_different_master_keys() {
        let key2 = Key::from_bytes([0x43u8; Key::BYTES]);
        let subkey1 = derive_subkey(&test_key(), 32, 1, b"context0").unwrap();
        let subkey2 = derive_subkey(&key2, 32, 1, b"context0").unwrap();
        assert_ne!(subkey1, subkey2);
    }

    #[test]
    fn test_different_lengths() {
        for &len in &[16, 24, 32, 48, 64] {
            let subkey = derive_subkey(&test_key(), len, 1, b"testctx0").unwrap();
            assert_eq!(subkey.len(), len);
        }
    }

    #[test]
    fn test_login_key_is_subkey() {
        let login_key = derive_login_key(&test_key());
        let subkey = derive_subkey(&test_key(), 32, 1, b"loginctx").unwrap();

        assert_eq!(login_key.as_ref(), &subkey[..16]);
    }

    #[test]
    fn test_invalid_subkey_lengths() {
        assert!(derive_subkey(&test_key(), 8, 1, b"testctx0").is_err());
        assert!(derive_subkey(&test_key(), 128, 1, b"testctx0").is_err());
    }
}
