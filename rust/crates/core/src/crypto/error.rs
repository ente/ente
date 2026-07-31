//! The error type shared by the crypto module.

use thiserror::Error;

/// An error from a cryptographic operation.
///
/// Each variant is returned by the operations documented to produce it.
/// [`code`](Self::code) maps a variant to a stable string identifier that
/// bindings forward to non-Rust callers.
#[derive(Error, Debug)]
pub enum Error {
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

impl Error {
    /// A stable, machine-readable identifier for this error, suitable for
    /// programmatic matching (e.g. `"invalid_key_length"`).
    pub fn code(&self) -> &'static str {
        match self {
            Error::InvalidKeyLength { .. } => "invalid_key_length",
            Error::InvalidNonceLength { .. } => "invalid_nonce_length",
            Error::InvalidSaltLength { .. } => "invalid_salt_length",
            Error::InvalidHeaderLength { .. } => "invalid_header_length",
            Error::CiphertextTooShort { .. } => "ciphertext_too_short",
            Error::InvalidKeyDerivationParams(_) => "invalid_kdf_params",
            Error::KeyDerivationFailed => "key_derivation_failed",
            Error::EncryptionFailed => "encryption_failed",
            Error::DecryptionFailed => "decryption_failed",
            Error::StreamInitFailed => "stream_init_failed",
            Error::StreamPushFailed => "stream_push_failed",
            Error::StreamPullFailed => "stream_pull_failed",
            Error::StreamTruncated => "stream_truncated",
            Error::StreamTrailingData => "stream_trailing_data",
            Error::SealedBoxOpenFailed => "sealed_box_open_failed",
            Error::InvalidPublicKey => "invalid_public_key",
            Error::Json(_) => "json",
            Error::Argon2(_) => "argon2",
            Error::Aead => "aead",
            Error::ArrayConversion => "array_conversion",
            Error::Io(_) => "io",
        }
    }
}

/// Result type for crypto operations.
pub type Result<T> = std::result::Result<T, Error>;

impl From<std::array::TryFromSliceError> for Error {
    fn from(_: std::array::TryFromSliceError) -> Self {
        Error::ArrayConversion
    }
}
