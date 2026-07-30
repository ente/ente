//! Zeroizing wrappers for sensitive material.

use std::fmt;
use std::ops::{Deref, DerefMut};

use subtle::ConstantTimeEq;
use zeroize::{Zeroize, ZeroizeOnDrop};

/// A heap-allocated byte buffer for sensitive material.
///
/// `SecretVec` zeroizes its contents on drop and requires an explicit
/// [`SecretVec::into_vec`] when crossing out of the trusted Rust layer.
#[repr(transparent)]
#[derive(Default, Zeroize, ZeroizeOnDrop)]
pub struct SecretVec(Vec<u8>);

impl PartialEq for SecretVec {
    /// Constant-time comparison (the length itself is not hidden).
    fn eq(&self, other: &Self) -> bool {
        self.0.ct_eq(&other.0).into()
    }
}

impl Eq for SecretVec {}

impl std::hash::Hash for SecretVec {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        self.0.hash(state);
    }
}

impl SecretVec {
    /// Wrap a byte vector so it is zeroized on drop.
    pub fn new(value: Vec<u8>) -> Self {
        Self(value)
    }

    /// Explicitly unwrap the secret bytes when crossing a trust boundary.
    pub fn into_vec(mut self) -> Vec<u8> {
        std::mem::take(&mut self.0)
    }
}

impl fmt::Debug for SecretVec {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("[REDACTED]")
    }
}

impl Deref for SecretVec {
    type Target = [u8];

    fn deref(&self) -> &Self::Target {
        self.0.as_slice()
    }
}

impl DerefMut for SecretVec {
    fn deref_mut(&mut self) -> &mut Self::Target {
        self.0.as_mut_slice()
    }
}

impl AsRef<[u8]> for SecretVec {
    fn as_ref(&self) -> &[u8] {
        self.0.as_slice()
    }
}

impl AsMut<[u8]> for SecretVec {
    fn as_mut(&mut self) -> &mut [u8] {
        self.0.as_mut_slice()
    }
}

impl From<Vec<u8>> for SecretVec {
    fn from(value: Vec<u8>) -> Self {
        Self::new(value)
    }
}

/// A heap-allocated string for sensitive material.
///
/// `SecretString` zeroizes its contents on drop and requires an explicit
/// [`SecretString::into_string`] when crossing out of the trusted Rust layer.
#[repr(transparent)]
#[derive(Default, Zeroize, ZeroizeOnDrop)]
pub struct SecretString(String);

impl PartialEq for SecretString {
    /// Constant-time comparison (the length itself is not hidden).
    fn eq(&self, other: &Self) -> bool {
        self.0.as_bytes().ct_eq(other.0.as_bytes()).into()
    }
}

impl Eq for SecretString {}

impl std::hash::Hash for SecretString {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        self.0.hash(state);
    }
}

impl SecretString {
    /// Wrap a string so it is zeroized on drop.
    pub fn new(value: String) -> Self {
        Self(value)
    }

    /// Explicitly unwrap the secret string when crossing a trust boundary.
    pub fn into_string(mut self) -> String {
        std::mem::take(&mut self.0)
    }
}

impl fmt::Debug for SecretString {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("[REDACTED]")
    }
}

impl Deref for SecretString {
    type Target = str;

    fn deref(&self) -> &Self::Target {
        self.0.as_str()
    }
}

impl DerefMut for SecretString {
    fn deref_mut(&mut self) -> &mut Self::Target {
        self.0.as_mut_str()
    }
}

impl AsRef<str> for SecretString {
    fn as_ref(&self) -> &str {
        self.0.as_str()
    }
}

impl From<String> for SecretString {
    fn from(value: String) -> Self {
        Self::new(value)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_secret_vec_zeroize_clears_buffer() {
        // Verify that calling zeroize() (which Drop invokes) zeroes the
        // buffer while we still own the memory; no UB from reading freed
        // allocations.
        let mut secret = SecretVec::new(vec![0xABu8; 64]);
        assert!(secret.iter().any(|&b| b != 0), "precondition: non-zero");
        secret.zeroize();
        assert!(
            secret.iter().all(|&b| b == 0),
            "SecretVec buffer was not zeroed by zeroize()"
        );
    }

    #[test]
    fn test_secret_vec_into_vec_preserves_contents() {
        let secret = SecretVec::new(vec![0xCDu8; 32]);
        let vec = secret.into_vec();
        // The extracted vec should still have the original contents
        assert!(vec.iter().all(|&b| b == 0xCD));
    }

    #[test]
    fn test_secret_vec_into_vec_leaves_empty_inner() {
        // After into_vec(), the SecretVec's inner buffer is empty, so
        // Drop won't zeroize the extracted data; that's the caller's
        // responsibility now.
        let secret = SecretVec::new(vec![0xEFu8; 16]);
        let vec = secret.into_vec();
        assert_eq!(vec.len(), 16);
        // No panic on implicit drop of the now-empty SecretVec
    }

    #[test]
    fn test_secret_vec_debug_redacts() {
        let secret = SecretVec::new(vec![42u8; 16]);
        let debug = format!("{:?}", secret);
        assert_eq!(debug, "[REDACTED]");
        assert!(!debug.contains("42"));
    }

    #[test]
    fn test_secret_vec_deref_and_len() {
        let secret = SecretVec::new(vec![1, 2, 3]);
        assert_eq!(secret.len(), 3);
        assert_eq!(&*secret, &[1, 2, 3]);
        assert_eq!(secret.as_ref(), &[1, 2, 3]);
    }
}
