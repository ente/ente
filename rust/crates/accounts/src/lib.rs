//! Shared Rust account transport and flow orchestration for Ente clients.
//!
//! Preferred usage:
//! - Use [`AccountsClient`] when a caller needs raw server failures, including
//!   the HTTP status and API error code.
//! - Use [`AuthFlow`] for CLI/e2e-style interactive orchestration where the
//!   library drives OTP/TOTP/passkey steps via a UI adapter.

pub mod client;
pub mod error;
pub mod flow;
pub mod models;
pub mod types;

pub use client::AccountsClient;
pub use error::{Error, Result};
pub use flow::{
    AuthFlow, AuthFlowUi, AuthenticatedAccount, ChangePasswordParams, ChangePasswordResult,
    CheckSessionValidityParams, CreateAccountParams, LoginParams, OtpPurpose, RecoveryKeyResult,
    SecondFactorMethod, SessionValidity, SetupTwoFactorParams, SetupTwoFactorResult, TotpPurpose,
};
pub use models::KeyAttributes;
pub use types::{AccountSecrets, AccountsClientConfig};
