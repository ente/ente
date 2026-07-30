//! Shared reusable types for account clients.

use ente_core::urls::PRODUCTION_API_ORIGIN;
use serde::{Deserialize, Serialize};
use zeroize::Zeroize;

/// Default origin for Ente's public API.
pub const DEFAULT_API_ORIGIN: &str = PRODUCTION_API_ORIGIN;

/// Configuration for constructing an [`crate::client::AccountsClient`].
#[derive(Clone)]
pub struct AccountsClientConfig {
    /// Ente API origin.
    pub origin: String,
    /// Optional auth token for authenticated requests.
    pub auth_token: Option<String>,
    /// Concrete client package header value.
    pub client_package: String,
    /// Optional client version header.
    pub client_version: Option<String>,
    /// Optional user agent.
    pub user_agent: Option<String>,
}

impl std::fmt::Debug for AccountsClientConfig {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("AccountsClientConfig")
            .field("origin", &self.origin)
            .field(
                "auth_token",
                &self.auth_token.as_ref().map(|_| "<redacted>"),
            )
            .field("client_package", &self.client_package)
            .field("client_version", &self.client_version)
            .field("user_agent", &self.user_agent)
            .finish()
    }
}

impl AccountsClientConfig {
    /// Create a config for the given client package.
    pub fn new(client_package: impl Into<String>) -> Self {
        Self {
            origin: DEFAULT_API_ORIGIN.to_string(),
            auth_token: None,
            client_package: client_package.into(),
            client_version: None,
            user_agent: None,
        }
    }

    /// Override the API origin.
    pub fn with_origin(mut self, origin: impl Into<String>) -> Self {
        self.origin = origin.into();
        self
    }

    /// Attach an auth token.
    pub fn with_auth_token(mut self, auth_token: impl Into<String>) -> Self {
        self.auth_token = Some(auth_token.into());
        self
    }

    /// Set a client version header.
    pub fn with_client_version(mut self, client_version: impl Into<String>) -> Self {
        self.client_version = Some(client_version.into());
        self
    }

    /// Set a user agent.
    pub fn with_user_agent(mut self, user_agent: impl Into<String>) -> Self {
        self.user_agent = Some(user_agent.into());
        self
    }
}

/// Decrypted account secrets.
#[derive(Serialize, Deserialize, Zeroize)]
#[zeroize(drop)]
pub struct AccountSecrets {
    /// Plain auth token bytes.
    pub token: Vec<u8>,
    /// Master key bytes.
    pub master_key: Vec<u8>,
    /// X25519 secret key bytes.
    pub secret_key: Vec<u8>,
    /// X25519 public key bytes.
    pub public_key: Vec<u8>,
}

impl std::fmt::Debug for AccountSecrets {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("AccountSecrets")
            .field("token", &"[REDACTED]")
            .field("master_key", &"[REDACTED]")
            .field("secret_key", &"[REDACTED]")
            .field("public_key_len", &self.public_key.len())
            .finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn account_secrets_debug_redacts_secret_material() {
        let secrets = AccountSecrets {
            token: vec![1, 2, 3],
            master_key: vec![4, 5, 6],
            secret_key: vec![7, 8, 9],
            public_key: vec![10, 11, 12],
        };

        let debug = format!("{secrets:?}");
        assert!(debug.contains("[REDACTED]"));
        assert!(!debug.contains("[1, 2, 3]"));
        assert!(!debug.contains("[4, 5, 6]"));
        assert!(!debug.contains("[7, 8, 9]"));
    }
}
