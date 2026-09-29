pub mod auth;
pub mod client;
pub mod error;
pub mod lifecycle;
pub mod login;
pub mod models;
pub mod signup;
pub mod types;

#[cfg(test)]
mod test_support;

pub use auth::KeyAttributes;
pub use client::AccountsClient;
pub use error::{Error, Result};
pub use lifecycle::{
    ChangePasswordParams, ChangePasswordResult, CheckSessionValidityParams, RecoveryKeyResult,
    SessionValidity, TwoFactorSetup,
};
pub use types::{AccountSecrets, AccountsClientConfig, AuthenticatedAccount, DEFAULT_API_ORIGIN};
