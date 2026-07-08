//! Typed key material and related fixed-size values.
//!
//! These newtypes carry their size in the type, so length validation happens
//! once, at the boundary where raw bytes enter ([`Key::try_from_slice`] and
//! friends), rather than inside every operation. Secret types zeroize on drop
//! and redact their `Debug` output; non-secret types (`Nonce`, `Salt`,
//! [`Header`]) are plain `Copy` values.

use rand_core::{OsRng, RngCore};
use subtle::ConstantTimeEq;
use zeroize::{Zeroize, ZeroizeOnDrop};

use crate::crypto::{CryptoError, Result, SecretVec};

/// A 256-bit symmetric encryption key.
///
/// One key type serves the secretbox, blob and stream operations: both
/// algorithm families take 256-bit keys, and Ente's data model shares key
/// material across them (e.g. a collection key wraps file keys via secretbox
/// and encrypts collection metadata via blob).
///
/// `Clone` is provided because real pipelines cache and share keys; `Copy` is
/// deliberately not, so every duplication of secret material is explicit.
#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct Key([u8; Self::BYTES]);

impl Key {
    /// Size of a key in bytes.
    pub const BYTES: usize = 32;

    /// Generate a new random key.
    pub fn generate() -> Self {
        let mut bytes = [0u8; Self::BYTES];
        OsRng.fill_bytes(&mut bytes);
        Self(bytes)
    }

    /// Wrap an existing 32-byte array as a key.
    pub fn from_bytes(bytes: [u8; Self::BYTES]) -> Self {
        Self(bytes)
    }

    /// Construct a key from a byte slice, validating its length.
    pub fn try_from_slice(bytes: &[u8]) -> Result<Self> {
        Ok(Self(bytes.try_into().map_err(|_| {
            CryptoError::InvalidKeyLength {
                expected: Self::BYTES,
                actual: bytes.len(),
            }
        })?))
    }

    /// The raw key bytes.
    pub fn as_bytes(&self) -> &[u8; Self::BYTES] {
        &self.0
    }
}

/// Consumes the source, so it zeroizes on drop.
impl TryFrom<SecretVec> for Key {
    type Error = CryptoError;

    fn try_from(secret: SecretVec) -> Result<Self> {
        Self::try_from_slice(&secret)
    }
}

impl std::fmt::Debug for Key {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("Key([REDACTED])")
    }
}

impl PartialEq for Key {
    /// Constant-time comparison.
    fn eq(&self, other: &Self) -> bool {
        self.0.ct_eq(&other.0).into()
    }
}

impl Eq for Key {}

/// A 192-bit SecretBox nonce. Not secret.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Nonce([u8; Self::BYTES]);

impl Nonce {
    /// Size of a nonce in bytes.
    pub const BYTES: usize = 24;

    /// Generate a new random nonce.
    pub fn generate() -> Self {
        let mut bytes = [0u8; Self::BYTES];
        OsRng.fill_bytes(&mut bytes);
        Self(bytes)
    }

    /// Wrap an existing 24-byte array as a nonce.
    pub fn from_bytes(bytes: [u8; Self::BYTES]) -> Self {
        Self(bytes)
    }

    /// Construct a nonce from a byte slice, validating its length.
    pub fn try_from_slice(bytes: &[u8]) -> Result<Self> {
        Ok(Self(bytes.try_into().map_err(|_| {
            CryptoError::InvalidNonceLength {
                expected: Self::BYTES,
                actual: bytes.len(),
            }
        })?))
    }

    /// The raw nonce bytes.
    pub fn as_bytes(&self) -> &[u8; Self::BYTES] {
        &self.0
    }
}

/// A 128-bit key derivation salt. Not secret.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Salt([u8; Self::BYTES]);

impl Salt {
    /// Size of a salt in bytes.
    pub const BYTES: usize = 16;

    /// Generate a new random salt.
    pub fn generate() -> Self {
        let mut bytes = [0u8; Self::BYTES];
        OsRng.fill_bytes(&mut bytes);
        Self(bytes)
    }

    /// Wrap an existing 16-byte array as a salt.
    pub fn from_bytes(bytes: [u8; Self::BYTES]) -> Self {
        Self(bytes)
    }

    /// Construct a salt from a byte slice, validating its length.
    pub fn try_from_slice(bytes: &[u8]) -> Result<Self> {
        Ok(Self(bytes.try_into().map_err(|_| {
            CryptoError::InvalidSaltLength {
                expected: Self::BYTES,
                actual: bytes.len(),
            }
        })?))
    }

    /// The raw salt bytes.
    pub fn as_bytes(&self) -> &[u8; Self::BYTES] {
        &self.0
    }
}

/// A 192-bit SecretStream decryption header. Not secret.
///
/// While the exact contents are an implementation detail of the secretstream
/// construction, it effectively contains the random nonce generated during
/// encryption, and is required for decryption.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Header([u8; Self::BYTES]);

impl Header {
    /// Size of a header in bytes.
    pub const BYTES: usize = 24;

    /// Construct a header from a byte slice, validating its length.
    pub fn try_from_slice(bytes: &[u8]) -> Result<Self> {
        Ok(Self(bytes.try_into().map_err(|_| {
            CryptoError::InvalidHeaderLength {
                expected: Self::BYTES,
                actual: bytes.len(),
            }
        })?))
    }

    /// Wrap an existing 24-byte array as a header.
    pub fn from_bytes(bytes: [u8; Self::BYTES]) -> Self {
        Self(bytes)
    }

    /// The raw header bytes.
    pub fn as_bytes(&self) -> &[u8; Self::BYTES] {
        &self.0
    }
}

/// An X25519 public key. Not secret.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PublicKey([u8; Self::BYTES]);

impl PublicKey {
    /// Size of a public key in bytes.
    pub const BYTES: usize = 32;

    /// Construct a public key from a byte slice, validating its length.
    pub fn try_from_slice(bytes: &[u8]) -> Result<Self> {
        Ok(Self(bytes.try_into().map_err(|_| {
            CryptoError::InvalidKeyLength {
                expected: Self::BYTES,
                actual: bytes.len(),
            }
        })?))
    }

    /// Wrap an existing 32-byte array as a public key.
    pub fn from_bytes(bytes: [u8; Self::BYTES]) -> Self {
        Self(bytes)
    }

    /// The raw public key bytes.
    pub fn as_bytes(&self) -> &[u8; Self::BYTES] {
        &self.0
    }
}

/// An X25519 secret key. Zeroized on drop.
#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct SecretKey([u8; Self::BYTES]);

impl SecretKey {
    /// Size of a secret key in bytes.
    pub const BYTES: usize = 32;

    /// Generate a new random secret key.
    pub fn generate() -> Self {
        let mut bytes = [0u8; Self::BYTES];
        OsRng.fill_bytes(&mut bytes);
        Self(bytes)
    }

    /// Deterministically derive a secret key from a 32-byte seed.
    ///
    /// The seed bytes are stored as-is and used as the X25519 secret scalar
    /// (clamping happens during scalar multiplication, per the X25519
    /// construction). Suitable for deriving stable box keys from a
    /// higher-entropy master secret.
    pub fn from_seed(seed: &[u8]) -> Result<Self> {
        Ok(Self(seed.try_into().map_err(|_| {
            CryptoError::InvalidKeyLength {
                expected: Self::BYTES,
                actual: seed.len(),
            }
        })?))
    }

    /// Construct a secret key from a byte slice, validating its length.
    pub fn try_from_slice(bytes: &[u8]) -> Result<Self> {
        Self::from_seed(bytes)
    }

    /// The public key corresponding to this secret key.
    pub fn public_key(&self) -> PublicKey {
        let secret = x25519_dalek::StaticSecret::from(self.0);
        PublicKey(*x25519_dalek::PublicKey::from(&secret).as_bytes())
    }

    /// The raw secret key bytes.
    pub fn as_bytes(&self) -> &[u8; Self::BYTES] {
        &self.0
    }
}

impl std::fmt::Debug for SecretKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("SecretKey([REDACTED])")
    }
}

impl PartialEq for SecretKey {
    /// Constant-time comparison.
    fn eq(&self, other: &Self) -> bool {
        self.0.ct_eq(&other.0).into()
    }
}

impl Eq for SecretKey {}

/// Generate random bytes of specified length.
pub fn random_bytes(len: usize) -> Vec<u8> {
    let mut buf = vec![0u8; len];
    OsRng.fill_bytes(&mut buf);
    buf
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_key_generate() {
        let key = Key::generate();
        let key2 = Key::generate();
        assert_ne!(key, key2);
    }

    #[test]
    fn test_key_roundtrips() {
        let key = Key::generate();
        let copy = Key::try_from_slice(key.as_bytes()).unwrap();
        assert_eq!(key, copy);

        let via_secret_vec = Key::try_from(SecretVec::new(key.as_bytes().to_vec())).unwrap();
        assert_eq!(key, via_secret_vec);
    }

    #[test]
    fn test_key_rejects_wrong_length() {
        assert!(matches!(
            Key::try_from_slice(&[1u8; 16]),
            Err(CryptoError::InvalidKeyLength { .. })
        ));
    }

    #[test]
    fn test_key_debug_redacts() {
        let key = Key::from_bytes([42u8; 32]);
        let debug = format!("{key:?}");
        assert!(!debug.contains("42"));
    }

    #[test]
    fn test_key_zeroize() {
        let mut key = Key::from_bytes([0xABu8; 32]);
        key.zeroize();
        assert_eq!(key.as_bytes(), &[0u8; 32]);
    }

    #[test]
    fn test_nonce_salt_generate() {
        assert_ne!(Nonce::generate(), Nonce::generate());
        assert_ne!(Salt::generate(), Salt::generate());
    }

    #[test]
    fn test_non_secret_types_reject_wrong_length() {
        assert!(Nonce::try_from_slice(&[0u8; 12]).is_err());
        assert!(Salt::try_from_slice(&[0u8; 8]).is_err());
        assert!(Header::try_from_slice(&[0u8; 23]).is_err());
        assert!(PublicKey::try_from_slice(&[0u8; 31]).is_err());
    }

    #[test]
    fn test_secret_key_public_key_is_deterministic() {
        let sk = SecretKey::generate();
        assert_eq!(sk.public_key(), sk.public_key());

        let sk2 = SecretKey::generate();
        assert_ne!(sk.public_key(), sk2.public_key());
    }

    #[test]
    fn test_secret_key_from_seed_is_deterministic() {
        let seed = [7u8; 32];
        let sk1 = SecretKey::from_seed(&seed).unwrap();
        let sk2 = SecretKey::from_seed(&seed).unwrap();
        assert_eq!(sk1, sk2);
        assert_eq!(sk1.public_key(), sk2.public_key());
    }

    #[test]
    fn test_random_bytes() {
        let bytes = random_bytes(16);
        assert_eq!(bytes.len(), 16);
        assert_ne!(bytes, random_bytes(16));
    }
}
