use std::fmt;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use ente_core::{
    b64,
    crypto::{SecretString, SecretVec},
};

use crate::{Error, Result};

#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct KeyAttributes {
    pub kek_salt: String,
    pub encrypted_key: String,
    pub key_decryption_nonce: String,
    pub public_key: String,
    pub encrypted_secret_key: String,
    pub secret_key_decryption_nonce: String,
    pub mem_limit: u32,
    pub ops_limit: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub master_key_encrypted_with_recovery_key: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub master_key_decryption_nonce: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub recovery_key_encrypted_with_master_key: Option<String>,
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

pub struct PrivateKeyAttributes {
    pub key: SecretString,
    pub recovery_key: SecretString,
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

pub struct KeyGenResult {
    pub key_attributes: KeyAttributes,
    pub private_key_attributes: PrivateKeyAttributes,
    pub key_encryption_key: SecretVec,
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

fn default_email_mfa_enabled() -> bool {
    true
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SrpAttributes {
    #[serde(rename = "srpUserID")]
    pub srp_user_id: Uuid,
    pub srp_salt: String,
    pub mem_limit: u32,
    pub ops_limit: u32,
    pub kek_salt: String,
    #[serde(rename = "isEmailMFAEnabled", default = "default_email_mfa_enabled")]
    pub is_email_mfa_enabled: bool,
}

impl SrpAttributes {
    pub(crate) fn validate_setup(
        &self,
        srp_user_id: Uuid,
        srp_salt: &[u8],
        keys: &KeyAttributes,
        operation: &str,
    ) -> Result<()> {
        let mut mismatches = Vec::new();
        if self.srp_user_id != srp_user_id {
            mismatches.push("srpUserID");
        }
        if self.srp_salt != b64::encode(srp_salt) {
            mismatches.push("srpSalt");
        }
        if self.kek_salt != keys.kek_salt {
            mismatches.push("kekSalt");
        }
        if self.mem_limit != keys.mem_limit {
            mismatches.push("memLimit");
        }
        if self.ops_limit != keys.ops_limit {
            mismatches.push("opsLimit");
        }
        if !mismatches.is_empty() {
            return Err(Error::Protocol(format!(
                "Remote SRP attributes mismatched after {operation}: {}",
                mismatches.join(", ")
            )));
        }
        Ok(())
    }
}

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
            mem_limit: 1,
            ops_limit: 2,
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
        assert!(debug.contains("mem_limit: 1"));
        assert!(debug.contains("ops_limit: 2"));
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
}
