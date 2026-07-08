//! Shared reusable types for account clients.

use ente_core::{http::HttpConfig, urls::PRODUCTION_API_BASE_URL};
use futures_timer::Delay;
use serde::{Deserialize, Serialize};
use std::{future::Future, pin::Pin, sync::Arc, time::Duration};
use zeroize::Zeroize;

/// Default base URL for Ente's public API.
pub const DEFAULT_API_BASE_URL: &str = PRODUCTION_API_BASE_URL;

/// Boxed future returned by a configured sleep hook.
pub type SleepFuture = Pin<Box<dyn Future<Output = ()> + 'static>>;

/// Async sleep hook used by high-level account flows for retry/backoff waits.
pub type SleepFn = Arc<dyn Fn(Duration) -> SleepFuture + 'static>;

fn default_sleep_fn() -> SleepFn {
    Arc::new(|duration| {
        Box::pin(async move {
            Delay::new(duration).await;
        })
    })
}

/// Configuration for constructing an [`crate::client::AccountsClient`].
#[derive(Clone)]
pub struct AccountsClientConfig {
    /// Base Ente API URL.
    pub base_url: String,
    /// Optional auth token for authenticated requests.
    pub auth_token: Option<String>,
    /// Concrete client package header value.
    pub client_package: String,
    /// Optional client version header.
    pub client_version: Option<String>,
    /// Optional user agent.
    pub user_agent: Option<String>,
    /// Optional request timeout.
    pub timeout_secs: Option<u64>,
    sleep_fn: SleepFn,
}

impl std::fmt::Debug for AccountsClientConfig {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("AccountsClientConfig")
            .field("base_url", &self.base_url)
            .field(
                "auth_token",
                &self.auth_token.as_ref().map(|_| "<redacted>"),
            )
            .field("client_package", &self.client_package)
            .field("client_version", &self.client_version)
            .field("user_agent", &self.user_agent)
            .field("timeout_secs", &self.timeout_secs)
            .field("sleep_fn", &"<configured>")
            .finish()
    }
}

impl AccountsClientConfig {
    /// Create a config for the given client package.
    pub fn new(client_package: impl Into<String>) -> Self {
        Self {
            base_url: DEFAULT_API_BASE_URL.to_string(),
            auth_token: None,
            client_package: client_package.into(),
            client_version: None,
            user_agent: None,
            timeout_secs: None,
            sleep_fn: default_sleep_fn(),
        }
    }

    /// Override the API base URL.
    pub fn with_base_url(mut self, base_url: impl Into<String>) -> Self {
        self.base_url = base_url.into();
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

    /// Set a request timeout in seconds.
    pub fn with_timeout_secs(mut self, timeout_secs: u64) -> Self {
        self.timeout_secs = Some(timeout_secs);
        self
    }

    /// Override the async sleep implementation used for retry/backoff waits.
    pub fn with_sleep_fn<F, Fut>(mut self, sleep_fn: F) -> Self
    where
        F: Fn(Duration) -> Fut + 'static,
        Fut: Future<Output = ()> + 'static,
    {
        self.sleep_fn = Arc::new(move |duration| Box::pin(sleep_fn(duration)));
        self
    }

    pub(crate) fn sleep_fn(&self) -> SleepFn {
        Arc::clone(&self.sleep_fn)
    }
}

impl From<AccountsClientConfig> for HttpConfig {
    fn from(value: AccountsClientConfig) -> Self {
        HttpConfig {
            base_url: value.base_url,
            auth_token: value.auth_token,
            user_agent: value.user_agent,
            client_package: Some(value.client_package),
            client_version: value.client_version,
            timeout_secs: value.timeout_secs,
        }
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
