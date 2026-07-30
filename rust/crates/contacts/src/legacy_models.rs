use ente_accounts::auth::KeyAttributes;
use ente_core::crypto::SecretVec;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum LegacyContactState {
    Invited,
    Revoked,
    Accepted,
    ContactLeft,
    ContactDenied,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum LegacyRecoveryStatus {
    Initiated,
    Waiting,
    Rejected,
    Recovered,
    Stopped,
    Ready,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct LegacyUser {
    pub id: i64,
    pub email: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct LegacyContactRecord {
    pub user: LegacyUser,
    pub emergency_contact: LegacyUser,
    pub state: LegacyContactState,
    pub recovery_notice_in_days: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct LegacyRecoverySession {
    pub id: String,
    pub user: LegacyUser,
    pub emergency_contact: LegacyUser,
    pub status: LegacyRecoveryStatus,
    pub wait_till: i64,
    pub created_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct LegacyInfo {
    pub contacts: Vec<LegacyContactRecord>,
    #[serde(rename = "recoverSessions")]
    pub recover_sessions: Vec<LegacyRecoverySession>,
    pub others_emergency_contact: Vec<LegacyContactRecord>,
    #[serde(rename = "othersRecoverySession")]
    pub others_recovery_session: Vec<LegacyRecoverySession>,
}

#[derive(Debug)]
pub struct LegacyRecoveryBundle {
    pub recovery_key: SecretVec,
    pub user_key_attributes: KeyAttributes,
}
