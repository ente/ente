// This BLAKE2b implementation produces the same digests as libsodium's
// `crypto_generichash`.

use blake2b_simd::{Params as Blake2bParams, State as Blake2bState};
use std::io::Read;

use crate::crypto::{Error, Result};

pub const HASH_BYTES_MIN: usize = 16;

pub const HASH_BYTES_MAX: usize = 64;

// Libsodium's default hash output length is 32 bytes.
pub const HASH_BYTES: usize = 32;

pub const HASH_CHUNK_SIZE: usize = 4 * 1024 * 1024;

pub const KEY_BYTES_MIN: usize = 16;

pub const KEY_BYTES_MAX: usize = 64;

pub fn hash(data: &[u8], out_len: Option<usize>, key: Option<&[u8]>) -> Result<Vec<u8>> {
    let out_len = out_len.unwrap_or(HASH_BYTES);

    if !(HASH_BYTES_MIN..=HASH_BYTES_MAX).contains(&out_len) {
        return Err(Error::InvalidKeyLength {
            expected: HASH_BYTES_MAX,
            actual: out_len,
        });
    }

    let mut params = Blake2bParams::new();
    params.hash_length(out_len);

    if let Some(k) = key {
        // Libsodium accepts an empty key or 16-64 bytes.
        if !k.is_empty() && (k.len() < KEY_BYTES_MIN || k.len() > KEY_BYTES_MAX) {
            return Err(Error::InvalidKeyLength {
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

pub fn hash_default(data: &[u8]) -> Result<Vec<u8>> {
    hash(data, Some(HASH_BYTES), None)
}

pub struct HashState {
    state: Blake2bState,
    out_len: usize,
}

impl HashState {
    pub fn new(out_len: Option<usize>, key: Option<&[u8]>) -> Result<Self> {
        let out_len = out_len.unwrap_or(HASH_BYTES);

        if !(HASH_BYTES_MIN..=HASH_BYTES_MAX).contains(&out_len) {
            return Err(Error::InvalidKeyLength {
                expected: HASH_BYTES_MAX,
                actual: out_len,
            });
        }

        let mut params = Blake2bParams::new();
        params.hash_length(out_len);

        if let Some(k) = key {
            // Libsodium accepts an empty key or 16-64 bytes.
            if !k.is_empty() && (k.len() < KEY_BYTES_MIN || k.len() > KEY_BYTES_MAX) {
                return Err(Error::InvalidKeyLength {
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

    pub fn update(&mut self, data: &[u8]) -> Result<()> {
        self.state.update(data);
        Ok(())
    }

    pub fn finalize(self) -> Result<Vec<u8>> {
        let hash = self.state.finalize();
        Ok(hash.as_bytes()[..self.out_len].to_vec())
    }
}

pub fn hash_state_new() -> Result<HashState> {
    HashState::new(Some(HASH_BYTES), None)
}

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
        let bad_key = vec![0u8; 8];

        let result = hash(data, Some(64), Some(&bad_key));
        assert!(result.is_err());
    }

    #[test]
    fn test_key_min_max_length() {
        let data = b"Test";

        let key_min = vec![0u8; KEY_BYTES_MIN];
        let hash1 = hash(data, Some(64), Some(&key_min)).unwrap();
        assert_eq!(hash1.len(), 64);

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
}
