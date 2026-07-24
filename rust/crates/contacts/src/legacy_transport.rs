use ente_accounts::auth::KeyAttributes;
use serde::{Deserialize, Serialize};

use crate::legacy_models::{LegacyContactState, LegacyInfo};

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacyPublicKeyResponse {
    pub public_key: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacyAddContactRequest {
    pub email: String,
    pub encrypted_key: String,
    pub recovery_notice_in_days: Option<i32>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacyUpdateContactRequest {
    #[serde(rename = "userID")]
    pub user_id: i64,
    #[serde(rename = "emergencyContactID")]
    pub emergency_contact_id: i64,
    pub state: LegacyContactState,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacyUpdateRecoveryNoticeRequest {
    #[serde(rename = "emergencyContactID")]
    pub emergency_contact_id: i64,
    pub recovery_notice_in_days: i32,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacyContactIdentifier {
    #[serde(rename = "userID")]
    pub user_id: i64,
    #[serde(rename = "emergencyContactID")]
    pub emergency_contact_id: i64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacyRecoveryIdentifier {
    pub id: String,
    #[serde(rename = "userID")]
    pub user_id: i64,
    #[serde(rename = "emergencyContactID")]
    pub emergency_contact_id: i64,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacyRecoveryInfoResponse {
    pub encrypted_key: String,
    #[serde(rename = "userKeyAttr")]
    pub user_key_attr: KeyAttributes,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacySetupSrpRequest {
    #[serde(rename = "srpUserID")]
    pub srp_user_id: String,
    pub srp_salt: String,
    pub srp_verifier: String,
    #[serde(rename = "srpA")]
    pub srp_a: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacyInitChangePasswordRequest {
    #[serde(rename = "recoveryID")]
    pub recovery_id: String,
    #[serde(rename = "setupSRPRequest")]
    pub setup_srp_request: LegacySetupSrpRequest,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacySetupSrpResponse {
    #[serde(rename = "setupID")]
    pub setup_id: String,
    #[serde(rename = "srpB")]
    pub srp_b: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacyUpdatedKeyAttr {
    pub kek_salt: String,
    pub encrypted_key: String,
    pub key_decryption_nonce: String,
    pub mem_limit: u32,
    pub ops_limit: u32,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacyUpdateSrpAndKeysRequest {
    #[serde(rename = "setupID")]
    pub setup_id: String,
    #[serde(rename = "srpM1")]
    pub srp_m1: String,
    #[serde(rename = "updatedKeyAttr")]
    pub updated_key_attr: LegacyUpdatedKeyAttr,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacyChangePasswordRequest {
    #[serde(rename = "recoveryID")]
    pub recovery_id: String,
    #[serde(rename = "updateSrpAndKeysRequest")]
    pub update_srp_and_keys_request: LegacyUpdateSrpAndKeysRequest,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LegacyChangePasswordResponse {
    #[serde(rename = "setupID")]
    pub setup_id: String,
    #[serde(rename = "srpM2")]
    pub srp_m2: String,
}

pub type LegacyInfoResponse = LegacyInfo;

#[cfg(test)]
mod tests {
    use serde_json::{json, to_value};

    use super::*;

    #[test]
    fn serializes_legacy_contact_identifiers_with_canonical_id_keys() {
        let request = LegacyUpdateContactRequest {
            user_id: 1,
            emergency_contact_id: 2,
            state: LegacyContactState::Accepted,
        };
        assert_eq!(
            to_value(request).unwrap(),
            json!({
                "userID": 1,
                "emergencyContactID": 2,
                "state": "ACCEPTED",
            })
        );

        let request = LegacyUpdateRecoveryNoticeRequest {
            emergency_contact_id: 2,
            recovery_notice_in_days: 14,
        };
        assert_eq!(
            to_value(request).unwrap(),
            json!({
                "emergencyContactID": 2,
                "recoveryNoticeInDays": 14,
            })
        );

        let request = LegacyContactIdentifier {
            user_id: 1,
            emergency_contact_id: 2,
        };
        assert_eq!(
            to_value(request).unwrap(),
            json!({
                "userID": 1,
                "emergencyContactID": 2,
            })
        );

        let request = LegacyRecoveryIdentifier {
            id: "session".to_string(),
            user_id: 1,
            emergency_contact_id: 2,
        };
        assert_eq!(
            to_value(request).unwrap(),
            json!({
                "id": "session",
                "userID": 1,
                "emergencyContactID": 2,
            })
        );
    }

    #[test]
    fn serializes_legacy_password_reset_requests_with_recovery_id_keys() {
        let setup = LegacySetupSrpRequest {
            srp_user_id: "user".to_string(),
            srp_salt: "salt".to_string(),
            srp_verifier: "verifier".to_string(),
            srp_a: "a".to_string(),
        };
        let request = LegacyInitChangePasswordRequest {
            recovery_id: "session".to_string(),
            setup_srp_request: setup,
        };
        assert_eq!(
            to_value(request).unwrap(),
            json!({
                "recoveryID": "session",
                "setupSRPRequest": {
                    "srpUserID": "user",
                    "srpSalt": "salt",
                    "srpVerifier": "verifier",
                    "srpA": "a",
                },
            })
        );

        let request = LegacyChangePasswordRequest {
            recovery_id: "session".to_string(),
            update_srp_and_keys_request: LegacyUpdateSrpAndKeysRequest {
                setup_id: "setup".to_string(),
                srp_m1: "m1".to_string(),
                updated_key_attr: LegacyUpdatedKeyAttr {
                    kek_salt: "kek".to_string(),
                    encrypted_key: "encrypted".to_string(),
                    key_decryption_nonce: "nonce".to_string(),
                    mem_limit: 1,
                    ops_limit: 2,
                },
            },
        };
        assert_eq!(
            to_value(request).unwrap(),
            json!({
                "recoveryID": "session",
                "updateSrpAndKeysRequest": {
                    "setupID": "setup",
                    "srpM1": "m1",
                    "updatedKeyAttr": {
                        "kekSalt": "kek",
                        "encryptedKey": "encrypted",
                        "keyDecryptionNonce": "nonce",
                        "memLimit": 1,
                        "opsLimit": 2,
                    },
                },
            })
        );
    }
}
