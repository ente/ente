use std::fmt;
use std::ops::{Deref, DerefMut};

use subtle::ConstantTimeEq;
use zeroize::{Zeroize, ZeroizeOnDrop};

#[repr(transparent)]
#[derive(Default, Zeroize, ZeroizeOnDrop)]
pub struct SecretVec(Vec<u8>);

impl PartialEq for SecretVec {
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
    pub fn new(value: Vec<u8>) -> Self {
        Self(value)
    }

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

#[repr(transparent)]
#[derive(Default, Zeroize, ZeroizeOnDrop)]
pub struct SecretString(String);

impl PartialEq for SecretString {
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
    pub fn new(value: String) -> Self {
        Self(value)
    }

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
        assert!(vec.iter().all(|&b| b == 0xCD));
    }

    #[test]
    fn test_secret_vec_debug_redacts() {
        let secret = SecretVec::new(vec![42u8; 16]);
        let debug = format!("{:?}", secret);
        assert_eq!(debug, "[REDACTED]");
        assert!(!debug.contains("42"));
    }
}
