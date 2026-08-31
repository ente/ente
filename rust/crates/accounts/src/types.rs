use ente_core::urls::PRODUCTION_API_ORIGIN;
use serde::{Deserialize, Serialize};
use zeroize::ZeroizeOnDrop;

pub const DEFAULT_API_ORIGIN: &str = PRODUCTION_API_ORIGIN;

#[derive(Clone)]
pub struct AccountsClientConfig {
    pub origin: String,
    pub auth_token: Option<String>,
    pub client_package: String,
    pub client_version: Option<String>,
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
    pub fn new(client_package: impl Into<String>) -> Self {
        Self {
            origin: DEFAULT_API_ORIGIN.to_string(),
            auth_token: None,
            client_package: client_package.into(),
            client_version: None,
            user_agent: None,
        }
    }

    pub fn with_origin(mut self, origin: impl Into<String>) -> Self {
        self.origin = origin.into();
        self
    }

    pub fn with_auth_token(mut self, auth_token: impl Into<String>) -> Self {
        self.auth_token = Some(auth_token.into());
        self
    }

    pub fn with_client_version(mut self, client_version: impl Into<String>) -> Self {
        self.client_version = Some(client_version.into());
        self
    }

    pub fn with_user_agent(mut self, user_agent: impl Into<String>) -> Self {
        self.user_agent = Some(user_agent.into());
        self
    }
}

#[derive(Serialize, Deserialize, ZeroizeOnDrop)]
pub struct AccountSecrets {
    pub token: Vec<u8>,
    pub master_key: Vec<u8>,
    pub secret_key: Vec<u8>,
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
