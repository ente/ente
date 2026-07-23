//! Shared request and response models for account APIs.

use std::fmt;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

fn default_email_mfa_enabled() -> bool {
    true
}

/// `/users/srp/attributes` response payload.
#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct SrpAttributes {
    /// SRP user ID.
    #[serde(rename = "srpUserID")]
    pub srp_user_id: Uuid,
    /// Base64 SRP salt.
    #[serde(rename = "srpSalt")]
    pub srp_salt: String,
    /// Argon memory limit.
    #[serde(rename = "memLimit")]
    pub mem_limit: i32,
    /// Argon ops limit.
    #[serde(rename = "opsLimit")]
    pub ops_limit: i32,
    /// Base64 KEK salt.
    #[serde(rename = "kekSalt")]
    pub kek_salt: String,
    /// Whether email MFA is enabled.
    #[serde(rename = "isEmailMFAEnabled", default = "default_email_mfa_enabled")]
    pub is_email_mfa_enabled: bool,
}

/// Outer wrapper for SRP attributes.
#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GetSrpAttributesResponse {
    /// Nested attributes payload.
    pub attributes: SrpAttributes,
}

/// Shared remote key attributes.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct KeyAttributes {
    /// Base64 KEK salt.
    pub kek_salt: String,
    /// Optional legacy field.
    pub kek_hash: Option<String>,
    /// Base64 encrypted master key.
    pub encrypted_key: String,
    /// Base64 nonce for encrypted key.
    pub key_decryption_nonce: String,
    /// Base64 public key.
    pub public_key: String,
    /// Base64 encrypted secret key.
    pub encrypted_secret_key: String,
    /// Base64 secret-key nonce.
    pub secret_key_decryption_nonce: String,
    /// Argon memory limit.
    pub mem_limit: i32,
    /// Argon ops limit.
    pub ops_limit: i32,
    /// Base64 encrypted master key with recovery key.
    pub master_key_encrypted_with_recovery_key: Option<String>,
    /// Base64 nonce for recovery-key-encrypted master key.
    pub master_key_decryption_nonce: Option<String>,
    /// Base64 encrypted recovery key with master key.
    pub recovery_key_encrypted_with_master_key: Option<String>,
    /// Base64 nonce for recovery key.
    pub recovery_key_decryption_nonce: Option<String>,
}

/// Auth response emitted by login and verification endpoints.
#[derive(Deserialize, Serialize, Clone)]
#[serde(try_from = "AuthResponseWire")]
#[serde(rename_all = "camelCase")]
pub struct AuthResponse {
    /// User ID.
    pub id: i64,
    /// Optional key attributes.
    pub key_attributes: Option<KeyAttributes>,
    /// Optional encrypted auth token.
    pub encrypted_token: Option<String>,
    /// Optional plain auth token.
    pub token: Option<String>,
    /// V1 two-factor session ID.
    #[serde(rename = "twoFactorSessionID")]
    pub two_factor_session_id: Option<String>,
    /// V2 two-factor session ID.
    #[serde(rename = "twoFactorSessionIDV2")]
    pub two_factor_session_id_v2: Option<String>,
    /// Passkey verification session ID.
    #[serde(rename = "passkeySessionID")]
    pub passkey_session_id: Option<String>,
    /// Optional SRP M2 server proof.
    pub srp_m2: Option<String>,
    /// Optional accounts broker URL.
    pub accounts_url: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct AuthResponseWire {
    id: i64,
    key_attributes: Option<KeyAttributes>,
    encrypted_token: Option<String>,
    token: Option<String>,
    #[serde(rename = "twoFactorSessionID")]
    two_factor_session_id: Option<String>,
    #[serde(rename = "twoFactorSessionIDV2")]
    two_factor_session_id_v2: Option<String>,
    #[serde(rename = "passkeySessionID")]
    passkey_session_id: Option<String>,
    srp_m2: Option<String>,
    accounts_url: Option<String>,
}

impl TryFrom<AuthResponseWire> for AuthResponse {
    type Error = String;

    fn try_from(value: AuthResponseWire) -> std::result::Result<Self, Self::Error> {
        if value
            .passkey_session_id
            .as_ref()
            .is_some_and(|session_id| !session_id.is_empty())
            && value
                .accounts_url
                .as_ref()
                .is_none_or(|accounts_url| accounts_url.is_empty())
        {
            return Err("accountsUrl is required when passkeySessionID is present".into());
        }

        Ok(Self {
            id: value.id,
            key_attributes: value.key_attributes,
            encrypted_token: value.encrypted_token,
            token: value.token,
            two_factor_session_id: value.two_factor_session_id,
            two_factor_session_id_v2: value.two_factor_session_id_v2,
            passkey_session_id: value.passkey_session_id,
            srp_m2: value.srp_m2,
            accounts_url: value.accounts_url,
        })
    }
}

impl fmt::Debug for AuthResponse {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("AuthResponse")
            .field("id", &self.id)
            .field("has_key_attributes", &self.key_attributes.is_some())
            .field(
                "encrypted_token",
                &self.encrypted_token.as_ref().map(|_| "[REDACTED]"),
            )
            .field("token", &self.token.as_ref().map(|_| "[REDACTED]"))
            .field(
                "two_factor_session_id",
                &self.two_factor_session_id.as_ref().map(|_| "[REDACTED]"),
            )
            .field(
                "two_factor_session_id_v2",
                &self.two_factor_session_id_v2.as_ref().map(|_| "[REDACTED]"),
            )
            .field(
                "passkey_session_id",
                &self.passkey_session_id.as_ref().map(|_| "[REDACTED]"),
            )
            .field("srp_m2", &self.srp_m2.as_ref().map(|_| "[REDACTED]"))
            .field("accounts_url", &self.accounts_url)
            .finish()
    }
}

impl AuthResponse {
    /// Return either v1 or v2 two-factor session ID, if present.
    pub fn get_two_factor_session_id(&self) -> Option<&String> {
        self.two_factor_session_id
            .as_ref()
            .filter(|s| !s.is_empty())
            .or_else(|| {
                self.two_factor_session_id_v2
                    .as_ref()
                    .filter(|s| !s.is_empty())
            })
    }

    /// Whether the response requires second-factor verification.
    pub fn is_mfa_required(&self) -> bool {
        self.get_two_factor_session_id().is_some()
    }

    /// Whether the response requires passkey verification.
    pub fn is_passkey_required(&self) -> bool {
        self.passkey_session_id
            .as_ref()
            .is_some_and(|s| !s.is_empty())
    }
}

/// Request body for sending OTP/OTT.
#[derive(Debug, Serialize)]
pub struct SendOtpRequest {
    /// Email address.
    pub email: String,
    /// OTP purpose.
    pub purpose: String,
}

/// Request body for email verification.
#[derive(Serialize)]
pub struct VerifyEmailRequest {
    /// Email address.
    pub email: String,
    /// One-time token.
    pub ott: String,
    /// Optional signup referral source.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source: Option<String>,
}

impl fmt::Debug for VerifyEmailRequest {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("VerifyEmailRequest")
            .field("email", &self.email)
            .field("ott", &"[REDACTED]")
            .field("source", &self.source)
            .finish()
    }
}

/// Request for SRP session creation.
#[derive(Debug, Serialize)]
pub struct CreateSrpSessionRequest {
    /// SRP user ID.
    #[serde(rename = "srpUserID")]
    pub srp_user_id: String,
    /// Client A public value.
    #[serde(rename = "srpA")]
    pub srp_a: String,
}

/// Response for SRP session creation.
#[derive(Debug, Deserialize, Serialize)]
pub struct CreateSrpSessionResponse {
    /// Session ID.
    #[serde(rename = "sessionID")]
    pub session_id: Uuid,
    /// Base64 SRP B value.
    #[serde(rename = "srpB")]
    pub srp_b: String,
}

/// Request for SRP session verification.
#[derive(Debug, Serialize)]
pub struct VerifySrpSessionRequest {
    /// SRP user ID.
    #[serde(rename = "srpUserID")]
    pub srp_user_id: String,
    /// Session ID.
    #[serde(rename = "sessionID")]
    pub session_id: String,
    /// Client M1 proof.
    #[serde(rename = "srpM1")]
    pub srp_m1: String,
}

/// Request for uploading key attributes.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SetUserAttributesRequest {
    /// Full user key attributes.
    pub key_attributes: KeyAttributes,
}

/// Request for uploading recovery-key attributes.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SetRecoveryKeyRequest {
    /// Encrypted master key with recovery key.
    pub master_key_encrypted_with_recovery_key: String,
    /// Nonce for encrypted master key.
    pub master_key_decryption_nonce: String,
    /// Encrypted recovery key with master key.
    pub recovery_key_encrypted_with_master_key: String,
    /// Nonce for encrypted recovery key.
    pub recovery_key_decryption_nonce: String,
}

/// Request for initial SRP setup.
#[derive(Debug, Serialize)]
pub struct SetupSrpRequest {
    /// SRP user ID.
    #[serde(rename = "srpUserID")]
    pub srp_user_id: String,
    /// Base64 SRP salt.
    #[serde(rename = "srpSalt")]
    pub srp_salt: String,
    /// Base64 SRP verifier.
    #[serde(rename = "srpVerifier")]
    pub srp_verifier: String,
    /// Base64 padded A public value.
    #[serde(rename = "srpA")]
    pub srp_a: String,
}

/// Response for initial SRP setup.
#[derive(Debug, Deserialize, Serialize)]
pub struct SetupSrpResponse {
    /// Setup ID.
    #[serde(rename = "setupID")]
    pub setup_id: Uuid,
    /// Base64 SRP B.
    #[serde(rename = "srpB")]
    pub srp_b: String,
}

/// Request for completing SRP setup.
#[derive(Debug, Serialize)]
pub struct CompleteSrpSetupRequest {
    /// Setup ID.
    #[serde(rename = "setupID")]
    pub setup_id: String,
    /// Base64 M1.
    #[serde(rename = "srpM1")]
    pub srp_m1: String,
}

/// Response for completing SRP setup.
#[derive(Debug, Deserialize, Serialize)]
pub struct CompleteSrpSetupResponse {
    /// Setup ID.
    #[serde(rename = "setupID")]
    pub setup_id: Uuid,
    /// Base64 M2.
    #[serde(rename = "srpM2")]
    pub srp_m2: String,
}

/// Mutable subset of key attributes used during password changes.
#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct UpdatedKeyAttr {
    /// Base64 KEK salt.
    pub kek_salt: String,
    /// Base64 encrypted master key.
    pub encrypted_key: String,
    /// Base64 nonce.
    pub key_decryption_nonce: String,
    /// Argon ops limit.
    pub ops_limit: i32,
    /// Argon memory limit.
    pub mem_limit: i32,
}

impl From<&KeyAttributes> for UpdatedKeyAttr {
    fn from(value: &KeyAttributes) -> Self {
        Self {
            kek_salt: value.kek_salt.clone(),
            encrypted_key: value.encrypted_key.clone(),
            key_decryption_nonce: value.key_decryption_nonce.clone(),
            ops_limit: value.ops_limit,
            mem_limit: value.mem_limit,
        }
    }
}

/// Request for updating SRP and key attributes.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateSrpAndKeysRequest {
    /// Setup ID.
    pub setup_id: String,
    /// Base64 client proof.
    pub srp_m1: String,
    /// Updated key-attribute subset.
    pub updated_key_attr: UpdatedKeyAttr,
    /// Whether other devices should be logged out.
    pub log_out_other_devices: bool,
}

/// Response for SRP/key update.
#[derive(Debug, Deserialize, Serialize)]
pub struct UpdateSrpAndKeysResponse {
    /// Base64 server proof.
    #[serde(rename = "srpM2")]
    pub srp_m2: String,
    /// Setup ID.
    #[serde(rename = "setupID")]
    pub setup_id: Uuid,
}

/// Session validity response.
#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionValidityResponse {
    /// Whether server-side key attributes exist.
    pub has_set_keys: bool,
    /// Optional server-side key attributes.
    pub key_attributes: Option<KeyAttributes>,
}

/// Two-factor setup secret response.
#[derive(Deserialize, Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct TwoFactorSecret {
    /// TOTP secret code.
    pub secret_code: String,
    /// QR code image payload.
    pub qr_code: String,
}

impl fmt::Debug for TwoFactorSecret {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("TwoFactorSecret")
            .field("secret_code", &"[REDACTED]")
            .field("qr_code", &"[REDACTED]")
            .finish()
    }
}

/// Request for TOTP enablement.
#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct EnableTwoFactorRequest {
    /// Current TOTP code.
    pub code: String,
    /// Encrypted TOTP secret.
    pub encrypted_two_factor_secret: String,
    /// Nonce for encrypted TOTP secret.
    pub two_factor_secret_decryption_nonce: String,
}

impl fmt::Debug for EnableTwoFactorRequest {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("EnableTwoFactorRequest")
            .field("code", &"[REDACTED]")
            .field("encrypted_two_factor_secret", &"[REDACTED]")
            .field("two_factor_secret_decryption_nonce", &"[REDACTED]")
            .finish()
    }
}

/// Request for TOTP verification.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct VerifyTotpRequest {
    /// Session ID.
    pub session_id: String,
    /// TOTP code.
    pub code: String,
}

impl fmt::Debug for VerifyTotpRequest {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("VerifyTotpRequest")
            .field("session_id", &"[REDACTED]")
            .field("code", &"[REDACTED]")
            .finish()
    }
}

/// Response for `/users/two-factor/status`.
#[derive(Debug, Deserialize, Serialize)]
pub struct TwoFactorStatusResponse {
    /// Whether two-factor is enabled.
    pub status: bool,
}

/// Supported second-factor kinds.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum TwoFactorType {
    /// TOTP second factor.
    Totp,
    /// Passkey second factor.
    Passkey,
}

/// Response for `/users/two-factor/recover`.
#[derive(Debug, Deserialize, Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct TwoFactorRecoveryResponse {
    /// Secret encrypted with the user's recovery key.
    pub encrypted_secret: String,
    /// Nonce for the encrypted secret.
    pub secret_decryption_nonce: String,
}

/// Request for `/users/two-factor/remove`.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoveTwoFactorRequest {
    /// Session ID.
    pub session_id: String,
    /// Plain recovery secret.
    pub secret: String,
    /// Factor type to remove.
    pub two_factor_type: TwoFactorType,
}

/// Response after 2FA verification/removal/passkey completion.
#[derive(Debug, Deserialize, Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct TwoFactorAuthorizationResponse {
    /// User ID.
    pub id: i64,
    /// Key attributes.
    pub key_attributes: KeyAttributes,
    /// Encrypted auth token.
    pub encrypted_token: String,
}

/// Response for passkey recovery status.
#[derive(Debug, Deserialize, Serialize)]
pub struct TwoFactorRecoveryStatusResponse {
    /// Whether passkey recovery has been configured.
    #[serde(rename = "isPasskeyRecoveryEnabled")]
    pub is_passkey_recovery_enabled: bool,
}

/// Request body for passkey recovery configuration.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ConfigurePasskeyRecoveryRequest {
    /// Plain server recovery secret.
    pub secret: String,
    /// Encrypted user secret.
    pub user_secret_cipher: String,
    /// Nonce for the encrypted user secret.
    pub user_secret_nonce: String,
}

/// Response for `/users/accounts-token`.
#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AccountsTokenResponse {
    /// Accounts broker URL.
    pub accounts_url: String,
    /// JWT for the accounts app.
    pub accounts_token: String,
}

#[cfg(test)]
mod tests {
    use super::AuthResponse;

    #[test]
    fn auth_response_requires_accounts_url_for_passkey() {
        let error =
            serde_json::from_str::<AuthResponse>(r#"{"id":1,"passkeySessionID":"session"}"#)
                .unwrap_err();

        assert!(error.to_string().contains("accountsUrl is required"));
    }

    #[test]
    fn auth_response_allows_missing_accounts_url_without_passkey() {
        let response = serde_json::from_str::<AuthResponse>(r#"{"id":1}"#).unwrap();

        assert_eq!(response.id, 1);
        assert!(response.accounts_url.is_none());
    }
}
