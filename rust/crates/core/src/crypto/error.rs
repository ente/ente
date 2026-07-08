//! The error type shared by the crypto module.

use thiserror::Error;

/// An error from a cryptographic operation.
///
/// Each variant is returned by the operations documented to produce it.
/// [`code`](Self::code) maps a variant to a stable string identifier that
/// bindings forward to non-Rust callers.
#[derive(Error, Debug)]
pub enum CryptoError {
    /// Base64 decoding failed.
    #[error("Base64 decode error: {0}")]
    Base64Decode(#[from] base64::DecodeError),

    /// Hex decoding failed.
    #[error("Hex decode error: {0}")]
    HexDecode(#[from] hex::FromHexError),

    /// Invalid key length.
    #[error("Invalid key length: expected {expected}, got {actual}")]
    InvalidKeyLength {
        /// Expected length.
        expected: usize,
        /// Actual length.
        actual: usize,
    },

    /// Invalid nonce length.
    #[error("Invalid nonce length: expected {expected}, got {actual}")]
    InvalidNonceLength {
        /// Expected length.
        expected: usize,
        /// Actual length.
        actual: usize,
    },

    /// Invalid salt length.
    #[error("Invalid salt length: expected {expected}, got {actual}")]
    InvalidSaltLength {
        /// Expected length.
        expected: usize,
        /// Actual length.
        actual: usize,
    },

    /// Invalid header length.
    #[error("Invalid header length: expected {expected}, got {actual}")]
    InvalidHeaderLength {
        /// Expected length.
        expected: usize,
        /// Actual length.
        actual: usize,
    },

    /// Ciphertext too short.
    #[error("Ciphertext too short: minimum {minimum}, got {actual}")]
    CiphertextTooShort {
        /// Minimum required length.
        minimum: usize,
        /// Actual length.
        actual: usize,
    },

    /// Invalid memory or operation limits for key derivation.
    #[error("Invalid key derivation parameters: {0}")]
    InvalidKeyDerivationParams(String),

    /// Key derivation failed.
    #[error("Key derivation failed")]
    KeyDerivationFailed,

    /// Encryption failed.
    #[error("Encryption failed")]
    EncryptionFailed,

    /// Decryption failed.
    #[error("Decryption failed")]
    DecryptionFailed,

    /// Stream initialization failed.
    #[error("Stream initialization failed")]
    StreamInitFailed,

    /// Stream push (encrypt) failed.
    #[error("Stream push failed")]
    StreamPushFailed,

    /// Stream pull (decrypt) failed.
    #[error("Stream pull failed")]
    StreamPullFailed,

    /// Stream was truncated (EOF before final tag).
    #[error("Stream truncated: EOF before final tag")]
    StreamTruncated,

    /// Stream had trailing ciphertext after the final tag.
    #[error("Stream has trailing data after final tag")]
    StreamTrailingData,

    /// Sealed box open failed.
    #[error("Sealed box open failed")]
    SealedBoxOpenFailed,

    /// Invalid public key (e.g., small-order point).
    #[error("Invalid public key")]
    InvalidPublicKey,

    /// JSON serialization or deserialization failed.
    #[error("JSON error: {0}")]
    Json(String),

    /// Argon2 error.
    #[error("Argon2 error: {0:?}")]
    Argon2(argon2::Error),

    /// AEAD error.
    #[error("AEAD error")]
    Aead,

    /// Array conversion error.
    #[error("Array conversion error")]
    ArrayConversion,

    /// IO error.
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
}

impl CryptoError {
    /// A stable, machine-readable identifier for this error, suitable for
    /// programmatic matching (e.g. `"invalid_key_length"`).
    pub fn code(&self) -> &'static str {
        match self {
            CryptoError::Base64Decode(_) => "base64_decode",
            CryptoError::HexDecode(_) => "hex_decode",
            CryptoError::InvalidKeyLength { .. } => "invalid_key_length",
            CryptoError::InvalidNonceLength { .. } => "invalid_nonce_length",
            CryptoError::InvalidSaltLength { .. } => "invalid_salt_length",
            CryptoError::InvalidHeaderLength { .. } => "invalid_header_length",
            CryptoError::CiphertextTooShort { .. } => "ciphertext_too_short",
            CryptoError::InvalidKeyDerivationParams(_) => "invalid_kdf_params",
            CryptoError::KeyDerivationFailed => "key_derivation_failed",
            CryptoError::EncryptionFailed => "encryption_failed",
            CryptoError::DecryptionFailed => "decryption_failed",
            CryptoError::StreamInitFailed => "stream_init_failed",
            CryptoError::StreamPushFailed => "stream_push_failed",
            CryptoError::StreamPullFailed => "stream_pull_failed",
            CryptoError::StreamTruncated => "stream_truncated",
            CryptoError::StreamTrailingData => "stream_trailing_data",
            CryptoError::SealedBoxOpenFailed => "sealed_box_open_failed",
            CryptoError::InvalidPublicKey => "invalid_public_key",
            CryptoError::Json(_) => "json",
            CryptoError::Argon2(_) => "argon2",
            CryptoError::Aead => "aead",
            CryptoError::ArrayConversion => "array_conversion",
            CryptoError::Io(_) => "io",
        }
    }
}

/// Result type for crypto operations.
pub type Result<T> = std::result::Result<T, CryptoError>;

impl From<std::array::TryFromSliceError> for CryptoError {
    fn from(_: std::array::TryFromSliceError) -> Self {
        CryptoError::ArrayConversion
    }
}
