use std::fmt;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

pub use crate::auth::{KeyAttributes, SrpAttributes};

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GetSrpAttributesResponse {
    pub attributes: SrpAttributes,
}

#[derive(Deserialize, Serialize, Clone)]
#[serde(try_from = "AuthResponseWire")]
#[serde(rename_all = "camelCase")]
pub struct AuthResponse {
    pub id: i64,
    pub key_attributes: Option<KeyAttributes>,
    pub encrypted_token: Option<String>,
    pub token: Option<String>,
    #[serde(rename = "twoFactorSessionID")]
    pub two_factor_session_id: Option<String>,
    #[serde(rename = "twoFactorSessionIDV2")]
    pub two_factor_session_id_v2: Option<String>,
    #[serde(rename = "passkeySessionID")]
    pub passkey_session_id: Option<String>,
    pub srp_m2: Option<String>,
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
            && value.accounts_url.as_ref().is_none_or(String::is_empty)
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

    pub fn is_mfa_required(&self) -> bool {
        self.get_two_factor_session_id().is_some()
    }

    pub fn is_passkey_required(&self) -> bool {
        self.passkey_session_id
            .as_ref()
            .is_some_and(|s| !s.is_empty())
    }
}

#[derive(Debug, Serialize)]
pub struct SendOtpRequest {
    pub email: String,
    pub purpose: String,
}

#[derive(Serialize)]
pub struct VerifyEmailRequest {
    pub email: String,
    pub ott: String,
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

#[derive(Debug, Serialize)]
pub struct CreateSrpSessionRequest {
    #[serde(rename = "srpUserID")]
    pub srp_user_id: String,
    #[serde(rename = "srpA")]
    pub srp_a: String,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct CreateSrpSessionResponse {
    #[serde(rename = "sessionID")]
    pub session_id: Uuid,
    #[serde(rename = "srpB")]
    pub srp_b: String,
}

#[derive(Debug, Serialize)]
pub struct VerifySrpSessionRequest {
    #[serde(rename = "srpUserID")]
    pub srp_user_id: String,
    #[serde(rename = "sessionID")]
    pub session_id: String,
    #[serde(rename = "srpM1")]
    pub srp_m1: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SetUserAttributesRequest {
    pub key_attributes: KeyAttributes,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SetRecoveryKeyRequest {
    pub master_key_encrypted_with_recovery_key: String,
    pub master_key_decryption_nonce: String,
    pub recovery_key_encrypted_with_master_key: String,
    pub recovery_key_decryption_nonce: String,
}

#[derive(Debug, Serialize)]
pub struct SetupSrpRequest {
    #[serde(rename = "srpUserID")]
    pub srp_user_id: String,
    #[serde(rename = "srpSalt")]
    pub srp_salt: String,
    #[serde(rename = "srpVerifier")]
    pub srp_verifier: String,
    #[serde(rename = "srpA")]
    pub srp_a: String,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct SetupSrpResponse {
    #[serde(rename = "setupID")]
    pub setup_id: Uuid,
    #[serde(rename = "srpB")]
    pub srp_b: String,
}

#[derive(Debug, Serialize)]
pub struct CompleteSrpSetupRequest {
    #[serde(rename = "setupID")]
    pub setup_id: String,
    #[serde(rename = "srpM1")]
    pub srp_m1: String,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct CompleteSrpSetupResponse {
    #[serde(rename = "setupID")]
    pub setup_id: Uuid,
    #[serde(rename = "srpM2")]
    pub srp_m2: String,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct UpdatedKeyAttr {
    pub kek_salt: String,
    pub encrypted_key: String,
    pub key_decryption_nonce: String,
    pub ops_limit: u32,
    pub mem_limit: u32,
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

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateSrpAndKeysRequest {
    pub setup_id: String,
    pub srp_m1: String,
    pub updated_key_attr: UpdatedKeyAttr,
    pub log_out_other_devices: bool,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct UpdateSrpAndKeysResponse {
    #[serde(rename = "srpM2")]
    pub srp_m2: String,
    #[serde(rename = "setupID")]
    pub setup_id: Uuid,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionValidityResponse {
    pub has_set_keys: bool,
    pub key_attributes: Option<KeyAttributes>,
}

#[derive(Deserialize, Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct TwoFactorSecret {
    pub secret_code: String,
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

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct EnableTwoFactorRequest {
    pub code: String,
    pub encrypted_two_factor_secret: String,
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

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct VerifyTotpRequest {
    pub session_id: String,
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

#[derive(Debug, Deserialize, Serialize)]
pub struct TwoFactorStatusResponse {
    pub status: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum TwoFactorType {
    Totp,
    Passkey,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct TwoFactorRecoveryResponse {
    pub encrypted_secret: String,
    pub secret_decryption_nonce: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoveTwoFactorRequest {
    pub session_id: String,
    pub secret: String,
    pub two_factor_type: TwoFactorType,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct TwoFactorAuthorizationResponse {
    pub id: i64,
    pub key_attributes: KeyAttributes,
    pub encrypted_token: String,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct TwoFactorRecoveryStatusResponse {
    #[serde(rename = "isPasskeyRecoveryEnabled")]
    pub is_passkey_recovery_enabled: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ConfigurePasskeyRecoveryRequest {
    pub secret: String,
    pub user_secret_cipher: String,
    pub user_secret_nonce: String,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AccountsTokenResponse {
    pub accounts_url: String,
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
