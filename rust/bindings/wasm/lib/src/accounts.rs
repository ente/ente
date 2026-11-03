use serde_wasm_bindgen as swb;
use wasm_bindgen::prelude::*;

#[cfg(feature = "prelogin")]
mod client;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Accounts(#[from] ente_accounts::Error),
    #[error(transparent)]
    Serde(#[from] swb::Error),
    #[error(transparent)]
    Input(#[from] tsify::Error),
}

impl Error {
    fn name(&self) -> Option<&'static str> {
        use ente_accounts::Error;
        let Self::Accounts(error) = self else {
            return None;
        };
        match error {
            Error::InsufficientMemory => Some("insufficient_memory"),
            Error::IncorrectRecoveryKey => Some("incorrect_recovery_key"),
            Error::MalformedRecoveryKey => Some("malformed_recovery_key"),
            Error::IncorrectPassword => Some("incorrect_password"),
            Error::NotRegistered => Some("not_registered"),
            Error::AlreadyRegistered => Some("already_registered"),
            Error::SignupIncomplete => Some("signup_incomplete"),
            Error::EmailAlreadyInUse => Some("email_already_in_use"),
            Error::SrpNotConfigured => Some("srp_not_configured"),
            Error::IncorrectEmailVerificationCode => Some("incorrect_email_code"),
            Error::EmailVerificationCodeExpired => Some("email_code_expired"),
            Error::EmailVerificationRateLimited => Some("email_code_rate_limited"),
            Error::IncorrectTotp => Some("incorrect_totp"),
            Error::TotpRateLimited => Some("totp_rate_limited"),
            Error::SessionInvalid => Some("session_invalid"),
            Error::SecondFactorSessionExpired => Some("session_expired"),
            Error::TwoFactorRecoveryNotConfigured => Some("two_factor_recovery_not_configured"),
            _ => None,
        }
    }
}

impl From<Error> for JsValue {
    fn from(error: Error) -> Self {
        crate::js_error(&error, error.name())
    }
}
