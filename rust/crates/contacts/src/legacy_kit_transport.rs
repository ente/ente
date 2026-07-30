use ente_accounts::auth::KeyAttributes;
use serde::{Deserialize, Serialize};

use crate::legacy_kit_models::{
    LegacyKitOwnerRecoverySession, LegacyKitRecoverySession, LegacyKitVariant,
};

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateLegacyKitRequest {
    pub id: String,
    pub variant: LegacyKitVariant,
    pub notice_period_in_hours: i32,
    pub encrypted_recovery_blob: String,
    pub auth_public_key: String,
    pub encrypted_owner_blob: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacyKitRecordResponse {
    pub id: String,
    pub variant: LegacyKitVariant,
    pub notice_period_in_hours: i32,
    pub legacy_url: String,
    pub encrypted_owner_blob: String,
    pub created_at: i64,
    pub updated_at: i64,
    pub active_recovery_session: Option<LegacyKitRecoverySession>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ListLegacyKitsResponse {
    pub kits: Vec<LegacyKitRecordResponse>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacyKitDownloadContentResponse {
    pub id: String,
    pub variant: LegacyKitVariant,
    pub encrypted_owner_blob: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacyKitOwnerActionRequest {
    #[serde(rename = "kitID")]
    pub kit_id: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacyKitUpdateRecoveryNoticeRequest {
    #[serde(rename = "kitID")]
    pub kit_id: String,
    pub notice_period_in_hours: i32,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacyKitChallengeRequest {
    #[serde(rename = "kitID")]
    pub kit_id: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacyKitChallengeResponse {
    #[serde(rename = "kitID")]
    pub kit_id: String,
    pub encrypted_challenge: String,
    pub expires_at: i64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacyKitOpenRecoveryRequest {
    #[serde(rename = "kitID")]
    pub kit_id: String,
    pub challenge: String,
    pub used_part_indexes: Option<Vec<u8>>,
    pub email: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacyKitOpenRecoveryResponse {
    pub session: LegacyKitRecoverySession,
    pub session_token: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacyKitOwnerRecoverySessionResponse {
    pub session: Option<LegacyKitRecoverySession>,
    pub initiators: Vec<crate::legacy_kit_models::LegacyKitRecoveryInitiator>,
}

impl From<LegacyKitOwnerRecoverySessionResponse> for LegacyKitOwnerRecoverySession {
    fn from(value: LegacyKitOwnerRecoverySessionResponse) -> Self {
        Self {
            session: value.session,
            initiators: value.initiators,
        }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacyKitSessionRequest {
    #[serde(rename = "sessionID")]
    pub session_id: String,
    pub session_token: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacyKitRecoveryInfoResponse {
    pub encrypted_recovery_blob: String,
    #[serde(rename = "userKeyAttr")]
    pub user_key_attr: KeyAttributes,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacyKitSetupSrpRequest {
    #[serde(rename = "srpUserID")]
    pub srp_user_id: String,
    pub srp_salt: String,
    pub srp_verifier: String,
    #[serde(rename = "srpA")]
    pub srp_a: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacyKitInitChangePasswordRequest {
    #[serde(rename = "sessionID")]
    pub session_id: String,
    pub session_token: String,
    #[serde(rename = "setupSRPRequest")]
    pub setup_srp_request: LegacyKitSetupSrpRequest,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacyKitSetupSrpResponse {
    #[serde(rename = "setupID")]
    pub setup_id: String,
    #[serde(rename = "srpB")]
    pub srp_b: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacyKitUpdatedKeyAttr {
    pub kek_salt: String,
    pub encrypted_key: String,
    pub key_decryption_nonce: String,
    pub mem_limit: u32,
    pub ops_limit: u32,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacyKitUpdateSrpAndKeysRequest {
    #[serde(rename = "setupID")]
    pub setup_id: String,
    #[serde(rename = "srpM1")]
    pub srp_m1: String,
    #[serde(rename = "updatedKeyAttr")]
    pub updated_key_attr: LegacyKitUpdatedKeyAttr,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacyKitChangePasswordRequest {
    #[serde(rename = "sessionID")]
    pub session_id: String,
    pub session_token: String,
    #[serde(rename = "updateSrpAndKeysRequest")]
    pub update_srp_and_keys_request: LegacyKitUpdateSrpAndKeysRequest,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacyKitChangePasswordResponse {
    #[serde(rename = "setupID")]
    pub setup_id: String,
    #[serde(rename = "srpM2")]
    pub srp_m2: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn legacy_kit_record_response_requires_legacy_url() {
        let response = serde_json::from_str::<LegacyKitRecordResponse>(
            r#"{
                "id":"kit-id",
                "variant":1,
                "noticePeriodInHours":168,
                "encryptedOwnerBlob":"owner-blob",
                "createdAt":1,
                "updatedAt":2,
                "activeRecoverySession":null
            }"#,
        );

        assert!(response.is_err());
    }

    #[test]
    fn legacy_kit_record_response_uses_configured_legacy_url() {
        let response = serde_json::from_str::<LegacyKitRecordResponse>(
            r#"{
                "id":"kit-id",
                "variant":1,
                "noticePeriodInHours":168,
                "legacyUrl":"http://localhost:3013",
                "encryptedOwnerBlob":"owner-blob",
                "createdAt":1,
                "updatedAt":2,
                "activeRecoverySession":null
            }"#,
        )
        .unwrap();

        assert_eq!(response.legacy_url, "http://localhost:3013");
    }
}
