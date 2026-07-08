//! Deriving independent subkeys from a high-entropy key, with BLAKE2b.
//!
//! Given one high-entropy key, this produces subkeys such that knowing a
//! derived subkey reveals nothing about the parent key or its sibling subkeys.
//! Each subkey is selected by a numeric id and an 8-byte context, so a single
//! parent key can safely key many separate purposes.
//!
//! Unlike [`argon`](super::argon), the input must already be high-entropy (a
//! key, not a password): this is fast keyed hashing, not password stretching.
//!
//! The construction is libsodium's `crypto_kdf_derive_from_key`; this pure-Rust
//! implementation derives the same subkeys.

use blake2b_simd::Params as Blake2bParams;

use crate::crypto::{Key, Result, SecretVec};

/// Size of KDF context in bytes.
pub const CONTEXT_BYTES: usize = 8;

/// Size of master key in bytes.
pub const KEY_BYTES: usize = Key::BYTES;

/// Minimum subkey length in bytes.
pub const SUBKEY_BYTES_MIN: usize = 16;

/// Maximum subkey length in bytes.
pub const SUBKEY_BYTES_MAX: usize = 64;

/// Login subkey length in bytes (used by derive_login_key).
pub const LOGIN_SUBKEY_LEN: usize = 32;

/// Login subkey ID (used by derive_login_key).
pub const LOGIN_SUBKEY_ID: u64 = 1;

/// Login subkey context (used by derive_login_key).
pub const LOGIN_SUBKEY_CONTEXT: &[u8; CONTEXT_BYTES] = b"loginctx";

/// Derive a `subkey_len`-byte subkey of `key`, selected by `subkey_id` and
/// `context`.
///
/// `subkey_id` and `context` together name the subkey: the same `key` yields
/// independent subkeys for different ids or contexts, so `context` acts as a
/// domain separator (conventionally a short, fixed application label).
/// `subkey_len` must be between 16 and 64 bytes. The result is a [`SecretVec`],
/// zeroized on drop.
///
/// # Wire format
///
/// BLAKE2b keyed with `key`, salt `subkey_id` (8 bytes little-endian followed
/// by 8 zero bytes), personalization `context` (8 bytes followed by 8 zero
/// bytes).
///
/// # Errors
///
/// Returns [`InvalidKeyLength`](crate::crypto::CryptoError::InvalidKeyLength) if
/// `subkey_len` is outside 16 to 64 bytes.
///
/// Produces the same subkey as libsodium's `crypto_kdf_derive_from_key`.
pub fn derive_subkey(
    key: &Key,
    subkey_len: usize,
    subkey_id: u64,
    context: &[u8; CONTEXT_BYTES],
) -> Result<SecretVec> {
    if !(SUBKEY_BYTES_MIN..=SUBKEY_BYTES_MAX).contains(&subkey_len) {
        return Err(crate::crypto::CryptoError::InvalidKeyLength {
            expected: SUBKEY_BYTES_MAX,
            actual: subkey_len,
        });
    }

    // Build salt: subkey_id (8 bytes LE) || zeros (8 bytes)
    let mut salt = [0u8; 16];
    salt[0..8].copy_from_slice(&subkey_id.to_le_bytes());

    // Build personal: context (8 bytes) || zeros (8 bytes)
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

/// Derive the SRP login key from the user's master key.
///
/// A fixed specialization of [`derive_subkey`]: the first 16 bytes of the
/// 32-byte subkey with id 1 and context `loginctx`. The login key is what the
/// client proves knowledge of during SRP authentication, which keeps the master
/// key itself off the wire. The result is a [`SecretVec`], zeroized on drop.
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
    fn test_derive_subkey() {
        let subkey = derive_subkey(&test_key(), 32, 1, b"testctx0").unwrap();
        assert_eq!(subkey.len(), 32);
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
    fn test_derive_login_key() {
        let login_key = derive_login_key(&test_key());
        assert_eq!(login_key.len(), 16);
        assert_eq!(login_key, derive_login_key(&test_key()));
    }

    #[test]
    fn test_login_key_is_subkey() {
        let login_key = derive_login_key(&test_key());
        let subkey = derive_subkey(&test_key(), 32, 1, b"loginctx").unwrap();

        // Login key should be first 16 bytes of subkey
        assert_eq!(login_key.as_ref(), &subkey[..16]);
    }

    #[test]
    fn test_invalid_subkey_lengths() {
        assert!(derive_subkey(&test_key(), 8, 1, b"testctx0").is_err());
        assert!(derive_subkey(&test_key(), 128, 1, b"testctx0").is_err());
    }
}
