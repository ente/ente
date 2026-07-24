//! Shared Rust account identity, transport, and flow orchestration for Ente
//! clients.
//!
//! Preferred usage:
//! - Use [`auth`] for the account key hierarchy: key generation, secret
//!   decryption, recovery keys, and the SRP login protocol.
//! - Use [`AccountsClient`] when a caller needs raw server failures, including
//!   the HTTP status and API error code.
//! - Use [`AuthFlow`] for CLI/e2e-style interactive orchestration where the
//!   library drives OTP/TOTP/passkey steps via a UI adapter.

pub mod auth;
pub mod client;
pub mod error;
pub mod flow;
pub mod models;
pub mod types;

pub use auth::KeyAttributes;
pub use client::AccountsClient;
pub use error::{Error, Result};
pub use flow::{
    AuthFlow, AuthFlowUi, AuthenticatedAccount, ChangePasswordParams, ChangePasswordResult,
    CheckSessionValidityParams, CreateAccountParams, LoginParams, OtpPurpose, RecoveryKeyResult,
    SecondFactorMethod, SessionValidity, SetupTwoFactorParams, SetupTwoFactorResult, TotpPurpose,
};
pub use types::{AccountSecrets, AccountsClientConfig};
