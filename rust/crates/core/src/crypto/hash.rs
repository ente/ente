//! Cryptographic hashing with BLAKE2b.
//!
//! BLAKE2b maps data of any length to a fixed-size digest (16 to 64 bytes, 32
//! by default). Supplying a key turns it into a MAC. Hashing is available
//! one-shot ([`hash`]), incrementally for data that arrives in pieces
//! ([`HashState`]), or straight from a reader ([`hash_reader`]).
//!
//! The construction is libsodium's `crypto_generichash`; the implementation
//! here wraps the pure-Rust `blake2b_simd` crate and produces the same digests.

use blake2b_simd::{Params as Blake2bParams, State as Blake2bState};
use std::io::Read;

use crate::crypto::{CryptoError, Result};

/// Minimum hash output length in bytes.
pub const HASH_BYTES_MIN: usize = 16;

/// Maximum hash output length in bytes.
pub const HASH_BYTES_MAX: usize = 64;

/// Default hash output length (libsodium default is 32 bytes).
pub const HASH_BYTES: usize = 32;

/// Hash chunk size for streaming (4 MB).
pub const HASH_CHUNK_SIZE: usize = 4 * 1024 * 1024;

/// Minimum key length in bytes for keyed hashing.
pub const KEY_BYTES_MIN: usize = 16;

/// Maximum key length in bytes for keyed hashing.
pub const KEY_BYTES_MAX: usize = 64;

/// Hash `data` with BLAKE2b.
///
/// `out_len` chooses the digest length (16 to 64 bytes), defaulting to 32.
/// Passing a `key` of 16 to 64 bytes computes a keyed hash (a MAC); `None` or
/// an empty key hashes without one.
///
/// # Errors
///
/// Returns [`InvalidKeyLength`](CryptoError::InvalidKeyLength) if `out_len` is
/// outside 16 to 64 bytes, or if a non-empty `key` is outside that range.
///
/// Produces the same digest as libsodium's `crypto_generichash`.
pub fn hash(data: &[u8], out_len: Option<usize>, key: Option<&[u8]>) -> Result<Vec<u8>> {
    let out_len = out_len.unwrap_or(HASH_BYTES);

    if !(HASH_BYTES_MIN..=HASH_BYTES_MAX).contains(&out_len) {
        return Err(CryptoError::InvalidKeyLength {
            expected: HASH_BYTES_MAX,
            actual: out_len,
        });
    }

    let mut params = Blake2bParams::new();
    params.hash_length(out_len);

    if let Some(k) = key {
        // libsodium: key must be 0 OR 16-64 bytes
        if !k.is_empty() && (k.len() < KEY_BYTES_MIN || k.len() > KEY_BYTES_MAX) {
            return Err(CryptoError::InvalidKeyLength {
                expected: KEY_BYTES_MAX,
                actual: k.len(),
            });
        }
        if !k.is_empty() {
            params.key(k);
        }
    }

    let hash = params.to_state().update(data).finalize();
    Ok(hash.as_bytes()[..out_len].to_vec())
}

/// Hash `data` with BLAKE2b using the defaults: a 32-byte digest and no key.
///
/// Shorthand for [`hash`] with `out_len` 32 and no key.
pub fn hash_default(data: &[u8]) -> Result<Vec<u8>> {
    hash(data, Some(HASH_BYTES), None)
}

/// Incremental BLAKE2b hasher, for data that arrives in pieces.
///
/// Build it with [`new`](Self::new), feed chunks with [`update`](Self::update),
/// and produce the digest with [`finalize`](Self::finalize). The result is
/// identical to passing the concatenation of the chunks to [`hash`], so a large
/// input can be hashed without holding it all in memory.
pub struct HashState {
    state: Blake2bState,
    out_len: usize,
}

impl HashState {
    /// Create a hasher with the given digest length and optional key.
    ///
    /// `out_len` and `key` follow the same rules and defaults as [`hash`].
    ///
    /// # Errors
    ///
    /// Returns [`InvalidKeyLength`](CryptoError::InvalidKeyLength) if `out_len`
    /// or a non-empty `key` is outside 16 to 64 bytes.
    pub fn new(out_len: Option<usize>, key: Option<&[u8]>) -> Result<Self> {
        let out_len = out_len.unwrap_or(HASH_BYTES);

        if !(HASH_BYTES_MIN..=HASH_BYTES_MAX).contains(&out_len) {
            return Err(CryptoError::InvalidKeyLength {
                expected: HASH_BYTES_MAX,
                actual: out_len,
            });
        }

        let mut params = Blake2bParams::new();
        params.hash_length(out_len);

        if let Some(k) = key {
            // libsodium: key must be 0 OR 16-64 bytes
            if !k.is_empty() && (k.len() < KEY_BYTES_MIN || k.len() > KEY_BYTES_MAX) {
                return Err(CryptoError::InvalidKeyLength {
                    expected: KEY_BYTES_MAX,
                    actual: k.len(),
                });
            }
            if !k.is_empty() {
                params.key(k);
            }
        }

        let state = params.to_state();

        Ok(HashState { state, out_len })
    }

    /// Feed more data into the hash.
    pub fn update(&mut self, data: &[u8]) -> Result<()> {
        self.state.update(data);
        Ok(())
    }

    /// Consume the hasher and return the digest, of the configured length.
    pub fn finalize(self) -> Result<Vec<u8>> {
        let hash = self.state.finalize();
        Ok(hash.as_bytes()[..self.out_len].to_vec())
    }
}

/// Create an incremental [`HashState`] with the defaults: a 32-byte digest and
/// no key.
pub fn hash_state_new() -> Result<HashState> {
    HashState::new(Some(HASH_BYTES), None)
}

/// Hash everything from `reader` with BLAKE2b.
///
/// Reads to EOF, hashing as it goes, so the source is never fully held in
/// memory. `out_len` is the digest length (16 to 64 bytes, default 32).
///
/// # Errors
///
/// Returns [`InvalidKeyLength`](CryptoError::InvalidKeyLength) if `out_len` is
/// out of range, or an [`Io`](CryptoError::Io) error if the reader fails.
pub fn hash_reader<R: Read>(reader: &mut R, out_len: Option<usize>) -> Result<Vec<u8>> {
    let mut state = HashState::new(out_len, None)?;
    let mut buffer = vec![0u8; 4096];

    loop {
        let bytes_read = reader.read(&mut buffer)?;
        if bytes_read == 0 {
            break;
        }
        state.update(&buffer[..bytes_read])?;
    }

    state.finalize()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hash_default() {
        let data = b"Hello, World!";
        let hash = hash_default(data).unwrap();
        assert_eq!(hash.len(), HASH_BYTES);
    }

    #[test]
    fn test_hash_with_length() {
        let data = b"Test data";

        // Test various output lengths
        for &len in &[16, 32, 48, 64] {
            let hash = hash(data, Some(len), None).unwrap();
            assert_eq!(hash.len(), len);
        }
    }

    #[test]
    fn test_hash_deterministic() {
        let data = b"Deterministic test";
        let hash1 = hash_default(data).unwrap();
        let hash2 = hash_default(data).unwrap();
        assert_eq!(hash1, hash2);
    }

    #[test]
    fn test_hash_different_data() {
        let data1 = b"First";
        let data2 = b"Second";

        let hash1 = hash_default(data1).unwrap();
        let hash2 = hash_default(data2).unwrap();

        assert_ne!(hash1, hash2);
    }

    #[test]
    fn test_keyed_hash() {
        let data = b"Keyed data";
        let key = vec![0x42u8; 32];

        let hash1 = hash(data, Some(64), Some(&key)).unwrap();
        let hash2 = hash(data, Some(64), None).unwrap();

        // Keyed and unkeyed hashes should be different
        assert_ne!(hash1, hash2);
    }

    #[test]
    fn test_keyed_hash_different_keys() {
        let data = b"Same data";
        let key1 = vec![0x42u8; 32];
        let key2 = vec![0x43u8; 32];

        let hash1 = hash(data, Some(64), Some(&key1)).unwrap();
        let hash2 = hash(data, Some(64), Some(&key2)).unwrap();

        assert_ne!(hash1, hash2);
    }

    #[test]
    fn test_empty_key_same_as_no_key() {
        let data = b"Test";

        let hash1 = hash(data, Some(64), Some(&[])).unwrap();
        let hash2 = hash(data, Some(64), None).unwrap();

        assert_eq!(hash1, hash2);
    }

    #[test]
    fn test_invalid_key_length() {
        let data = b"Test";
        let bad_key = vec![0u8; 8]; // Too short

        let result = hash(data, Some(64), Some(&bad_key));
        assert!(result.is_err());
    }

    #[test]
    fn test_key_min_max_length() {
        let data = b"Test";

        // Min length should work
        let key_min = vec![0u8; KEY_BYTES_MIN];
        let hash1 = hash(data, Some(64), Some(&key_min)).unwrap();
        assert_eq!(hash1.len(), 64);

        // Max length should work
        let key_max = vec![0u8; KEY_BYTES_MAX];
        let hash2 = hash(data, Some(64), Some(&key_max)).unwrap();
        assert_eq!(hash2.len(), 64);
    }

    #[test]
    fn test_empty_data() {
        let data = b"";
        let hash = hash_default(data).unwrap();
        assert_eq!(hash.len(), HASH_BYTES);
    }

    #[test]
    fn test_large_data() {
        let data = vec![0x42u8; 1024 * 1024]; // 1 MB
        let hash = hash_default(&data).unwrap();
        assert_eq!(hash.len(), HASH_BYTES);
    }

    #[test]
    fn test_avalanche_effect() {
        let data1 = b"Test";
        let data2 = b"Test "; // One extra space

        let hash1 = hash_default(data1).unwrap();
        let hash2 = hash_default(data2).unwrap();

        // Count differing bytes
        let diff_count = hash1
            .iter()
            .zip(hash2.iter())
            .filter(|(a, b)| a != b)
            .count();

        // Should have significant differences (avalanche effect)
        assert!(diff_count > 15); // Expect ~50% different
    }
}
