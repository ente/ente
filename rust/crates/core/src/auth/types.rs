//! Data types for authentication operations.

use std::fmt;

use serde::{Deserialize, Serialize};

use crate::crypto::{SecretString, SecretVec};

/// Attributes stored on server for key derivation and encrypted keys.
#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct KeyAttributes {
    /// Salt for deriving key-encryption-key from password (base64)
    pub kek_salt: String,
    /// Master key encrypted with KEK (base64)
    pub encrypted_key: String,
    /// Nonce for master key decryption (base64)
    pub key_decryption_nonce: String,
    /// X25519 public key (base64)
    pub public_key: String,
    /// Secret key encrypted with master key (base64)
    pub encrypted_secret_key: String,
    /// Nonce for secret key decryption (base64)
    pub secret_key_decryption_nonce: String,
    /// Argon2 memory limit
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mem_limit: Option<u32>,
    /// Argon2 ops limit
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ops_limit: Option<u32>,
    /// Master key encrypted with recovery key (base64)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub master_key_encrypted_with_recovery_key: Option<String>,
    /// Nonce for master key decryption with recovery key (base64)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub master_key_decryption_nonce: Option<String>,
    /// Recovery key encrypted with master key (base64)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub recovery_key_encrypted_with_master_key: Option<String>,
    /// Nonce for recovery key decryption (base64)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub recovery_key_decryption_nonce: Option<String>,
}

impl fmt::Debug for KeyAttributes {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("KeyAttributes")
            .field("kek_salt", &"[REDACTED]")
            .field("encrypted_key", &"[REDACTED]")
            .field("key_decryption_nonce", &"[REDACTED]")
            .field("public_key", &"[REDACTED]")
            .field("encrypted_secret_key", &"[REDACTED]")
            .field("secret_key_decryption_nonce", &"[REDACTED]")
            .field("mem_limit", &self.mem_limit)
            .field("ops_limit", &self.ops_limit)
            .field(
                "master_key_encrypted_with_recovery_key",
                &self
                    .master_key_encrypted_with_recovery_key
                    .as_ref()
                    .map(|_| "[REDACTED]"),
            )
            .field(
                "master_key_decryption_nonce",
                &self
                    .master_key_decryption_nonce
                    .as_ref()
                    .map(|_| "[REDACTED]"),
            )
            .field(
                "recovery_key_encrypted_with_master_key",
                &self
                    .recovery_key_encrypted_with_master_key
                    .as_ref()
                    .map(|_| "[REDACTED]"),
            )
            .field(
                "recovery_key_decryption_nonce",
                &self
                    .recovery_key_decryption_nonce
                    .as_ref()
                    .map(|_| "[REDACTED]"),
            )
            .finish()
    }
}

/// Private key material (never sent to server).
pub struct PrivateKeyAttributes {
    /// Master key (base64)
    pub key: SecretString,
    /// Recovery key (hex for display to user)
    pub recovery_key: SecretString,
    /// X25519 secret key (base64)
    pub secret_key: SecretString,
}

impl fmt::Debug for PrivateKeyAttributes {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("PrivateKeyAttributes")
            .field("key", &"[REDACTED]")
            .field("recovery_key", &"[REDACTED]")
            .field("secret_key", &"[REDACTED]")
            .finish()
    }
}

/// Result of key generation during sign-up.
pub struct KeyGenResult {
    /// Attributes to send to server
    pub key_attributes: KeyAttributes,
    /// Private keys to store locally
    pub private_key_attributes: PrivateKeyAttributes,
    /// Key-encryption-key used to encrypt the master key and seed SRP setup.
    pub key_encryption_key: SecretVec,
    /// Login key for SRP registration (16 bytes)
    pub login_key: SecretVec,
}

impl fmt::Debug for KeyGenResult {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("KeyGenResult")
            .field("key_attributes", &self.key_attributes)
            .field("private_key_attributes", &self.private_key_attributes)
            .field("key_encryption_key", &"[REDACTED]")
            .field("login_key", &"[REDACTED]")
            .finish()
    }
}

/// Result of successful login/decryption.
pub struct LoginResult {
    /// Decrypted master key
    pub master_key: SecretVec,
    /// Decrypted X25519 secret key
    pub secret_key: SecretVec,
    /// Decrypted auth token
    pub token: SecretVec,
    /// Key-encryption-key (for SRP setup if needed)
    pub key_encryption_key: SecretVec,
}

impl fmt::Debug for LoginResult {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("LoginResult")
            .field("master_key", &"[REDACTED]")
            .field("secret_key", &"[REDACTED]")
            .field("token", &"[REDACTED]")
            .field("key_encryption_key", &"[REDACTED]")
            .finish()
    }
}

fn default_email_mfa_enabled() -> bool {
    true
}

/// SRP attributes received from server.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SrpAttributes {
    /// SRP user ID (UUID)
    #[serde(rename = "srpUserID")]
    pub srp_user_id: String,
    /// SRP salt (base64)
    pub srp_salt: String,
    /// Argon2 memory limit
    pub mem_limit: u32,
    /// Argon2 ops limit
    pub ops_limit: u32,
    /// KEK salt (base64) - same as in KeyAttributes
    pub kek_salt: String,
    /// Whether email MFA is enabled (use email OTT instead of SRP)
    #[serde(rename = "isEmailMFAEnabled", default = "default_email_mfa_enabled")]
    pub is_email_mfa_enabled: bool,
}

/// Error types for auth operations.
#[derive(Debug, thiserror::Error)]
pub enum AuthError {
    /// Password verification failed.
    #[error("Incorrect password")]
    IncorrectPassword,

    /// Recovery key verification failed.
    #[error("Incorrect recovery key")]
    IncorrectRecoveryKey,

    /// Key attributes are invalid or corrupted.
    #[error("Invalid key attributes")]
    InvalidKeyAttributes,

    /// The device could not derive a sensitive key with the required policy.
    #[error("Failed to derive key (insufficient memory)")]
    InsufficientMemory,

    /// A required field is missing from the key attributes.
    #[error("Missing required field: {0}")]
    MissingField(&'static str),

    /// Underlying cryptographic operation failed.
    #[error("Crypto error: {0}")]
    Crypto(#[from] crate::crypto::CryptoError),

    /// Failed to decode base64 or hex data.
    #[error("Decode error: {0}")]
    Decode(String),

    /// Invalid key format or length.
    #[error("Invalid key: {0}")]
    InvalidKey(String),

    /// SRP protocol error.
    #[error("SRP error: {0}")]
    Srp(String),
}

/// Result type for auth operations.
pub type Result<T> = std::result::Result<T, AuthError>;

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_key_attributes() -> KeyAttributes {
        KeyAttributes {
            kek_salt: "server-kek-salt".to_string(),
            encrypted_key: "server-encrypted-key".to_string(),
            key_decryption_nonce: "server-key-nonce".to_string(),
            public_key: "server-public-key".to_string(),
            encrypted_secret_key: "server-encrypted-secret-key".to_string(),
            secret_key_decryption_nonce: "server-secret-key-nonce".to_string(),
            mem_limit: Some(1),
            ops_limit: Some(2),
            master_key_encrypted_with_recovery_key: None,
            master_key_decryption_nonce: None,
            recovery_key_encrypted_with_master_key: None,
            recovery_key_decryption_nonce: None,
        }
    }

    #[test]
    fn test_key_attributes_debug_redacts_server_material() {
        let attrs = sample_key_attributes();

        let debug = format!("{attrs:?}");
        assert!(debug.contains("[REDACTED]"));
        assert!(!debug.contains("server-kek-salt"));
        assert!(!debug.contains("server-encrypted-key"));
        assert!(!debug.contains("server-key-nonce"));
        assert!(!debug.contains("server-public-key"));
        assert!(!debug.contains("server-encrypted-secret-key"));
        assert!(!debug.contains("server-secret-key-nonce"));
        assert!(debug.contains("Some(1)"));
        assert!(debug.contains("Some(2)"));
    }

    #[test]
    fn test_key_gen_result_debug_redacts_secret_material() {
        let result = KeyGenResult {
            key_attributes: sample_key_attributes(),
            private_key_attributes: PrivateKeyAttributes {
                key: SecretString::new("private-master-key".to_string()),
                recovery_key: SecretString::new("private-recovery-key".to_string()),
                secret_key: SecretString::new("private-secret-key".to_string()),
            },
            key_encryption_key: SecretVec::new(vec![1, 2, 3]),
            login_key: SecretVec::new(vec![4, 5, 6]),
        };

        let debug = format!("{result:?}");
        assert!(debug.contains("[REDACTED]"));
        assert!(!debug.contains("private-master-key"));
        assert!(!debug.contains("private-recovery-key"));
        assert!(!debug.contains("private-secret-key"));
        assert!(!debug.contains("[1, 2, 3]"));
        assert!(!debug.contains("[4, 5, 6]"));
        assert!(!debug.contains("server-kek-salt"));
        assert!(!debug.contains("server-encrypted-key"));
        assert!(!debug.contains("server-key-nonce"));
        assert!(!debug.contains("server-public-key"));
        assert!(!debug.contains("server-encrypted-secret-key"));
        assert!(!debug.contains("server-secret-key-nonce"));
        assert!(debug.contains("key_attributes"));
    }

    #[test]
    fn test_login_result_debug_redacts_secret_material() {
        let result = LoginResult {
            master_key: SecretVec::new(vec![1, 2, 3]),
            secret_key: SecretVec::new(vec![4, 5, 6]),
            token: SecretVec::new(vec![7, 8, 9]),
            key_encryption_key: SecretVec::new(vec![10, 11, 12]),
        };

        let debug = format!("{result:?}");
        assert!(debug.contains("[REDACTED]"));
        assert!(!debug.contains("[1, 2, 3]"));
        assert!(!debug.contains("[4, 5, 6]"));
        assert!(!debug.contains("[7, 8, 9]"));
        assert!(!debug.contains("[10, 11, 12]"));
    }
}
