use subtle::ConstantTimeEq;
use zeroize::{Zeroize, ZeroizeOnDrop};

use crate::crypto::{Error, Result, SecretVec};

#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct Key([u8; Self::BYTES]);

impl Key {
    pub const BYTES: usize = 32;

    pub fn generate() -> Self {
        let mut bytes = [0u8; Self::BYTES];
        fill_random(&mut bytes);
        Self(bytes)
    }

    pub fn from_bytes(bytes: [u8; Self::BYTES]) -> Self {
        Self(bytes)
    }

    pub fn try_from_slice(bytes: &[u8]) -> Result<Self> {
        Ok(Self(bytes.try_into().map_err(|_| {
            Error::InvalidKeyLength {
                expected: Self::BYTES,
                actual: bytes.len(),
            }
        })?))
    }

    pub fn as_bytes(&self) -> &[u8; Self::BYTES] {
        &self.0
    }
}

impl TryFrom<SecretVec> for Key {
    type Error = Error;

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
    fn eq(&self, other: &Self) -> bool {
        self.0.ct_eq(&other.0).into()
    }
}

impl Eq for Key {}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Nonce([u8; Self::BYTES]);

impl Nonce {
    pub const BYTES: usize = 24;

    pub fn generate() -> Self {
        let mut bytes = [0u8; Self::BYTES];
        fill_random(&mut bytes);
        Self(bytes)
    }

    pub fn from_bytes(bytes: [u8; Self::BYTES]) -> Self {
        Self(bytes)
    }

    pub fn try_from_slice(bytes: &[u8]) -> Result<Self> {
        Ok(Self(bytes.try_into().map_err(|_| {
            Error::InvalidNonceLength {
                expected: Self::BYTES,
                actual: bytes.len(),
            }
        })?))
    }

    pub fn as_bytes(&self) -> &[u8; Self::BYTES] {
        &self.0
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Salt([u8; Self::BYTES]);

impl Salt {
    pub const BYTES: usize = 16;

    pub fn generate() -> Self {
        let mut bytes = [0u8; Self::BYTES];
        fill_random(&mut bytes);
        Self(bytes)
    }

    pub fn from_bytes(bytes: [u8; Self::BYTES]) -> Self {
        Self(bytes)
    }

    pub fn try_from_slice(bytes: &[u8]) -> Result<Self> {
        Ok(Self(bytes.try_into().map_err(|_| {
            Error::InvalidSaltLength {
                expected: Self::BYTES,
                actual: bytes.len(),
            }
        })?))
    }

    pub fn as_bytes(&self) -> &[u8; Self::BYTES] {
        &self.0
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Header([u8; Self::BYTES]);

impl Header {
    pub const BYTES: usize = 24;

    pub fn try_from_slice(bytes: &[u8]) -> Result<Self> {
        Ok(Self(bytes.try_into().map_err(|_| {
            Error::InvalidHeaderLength {
                expected: Self::BYTES,
                actual: bytes.len(),
            }
        })?))
    }

    pub fn from_bytes(bytes: [u8; Self::BYTES]) -> Self {
        Self(bytes)
    }

    pub fn as_bytes(&self) -> &[u8; Self::BYTES] {
        &self.0
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PublicKey([u8; Self::BYTES]);

impl PublicKey {
    pub const BYTES: usize = 32;

    pub fn try_from_slice(bytes: &[u8]) -> Result<Self> {
        Ok(Self(bytes.try_into().map_err(|_| {
            Error::InvalidKeyLength {
                expected: Self::BYTES,
                actual: bytes.len(),
            }
        })?))
    }

    pub fn from_bytes(bytes: [u8; Self::BYTES]) -> Self {
        Self(bytes)
    }

    pub fn as_bytes(&self) -> &[u8; Self::BYTES] {
        &self.0
    }
}

#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct SecretKey([u8; Self::BYTES]);

impl SecretKey {
    pub const BYTES: usize = 32;

    pub fn generate() -> Self {
        let mut bytes = [0u8; Self::BYTES];
        fill_random(&mut bytes);
        Self(bytes)
    }

    // Store the seed unchanged; X25519 clamps it during scalar multiplication.
    pub fn from_seed(seed: &[u8]) -> Result<Self> {
        Ok(Self(seed.try_into().map_err(|_| {
            Error::InvalidKeyLength {
                expected: Self::BYTES,
                actual: seed.len(),
            }
        })?))
    }

    pub fn try_from_slice(bytes: &[u8]) -> Result<Self> {
        Self::from_seed(bytes)
    }

    pub fn public_key(&self) -> PublicKey {
        let secret = x25519_dalek::StaticSecret::from(self.0);
        PublicKey(*x25519_dalek::PublicKey::from(&secret).as_bytes())
    }

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
    fn eq(&self, other: &Self) -> bool {
        self.0.ct_eq(&other.0).into()
    }
}

impl Eq for SecretKey {}

pub fn random_bytes(len: usize) -> Vec<u8> {
    let mut buf = vec![0u8; len];
    fill_random(&mut buf);
    buf
}

pub(crate) fn fill_random(buf: &mut [u8]) {
    getrandom::fill(buf).expect("failed to generate random bytes");
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
            Err(Error::InvalidKeyLength { .. })
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
