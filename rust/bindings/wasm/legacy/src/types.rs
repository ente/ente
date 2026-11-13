use serde::{Deserialize, Serialize};
use tsify::Tsify;

#[derive(Deserialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct OpenKitRecoveryInput {
    pub base_url: String,
    pub shares: Vec<LegacyKitShare>,
    #[tsify(optional)]
    pub email: Option<String>,
    #[tsify(optional)]
    pub client_package: Option<String>,
    #[tsify(optional)]
    pub client_version: Option<String>,
}

#[derive(Serialize, Deserialize, Tsify)]
pub struct LegacyKitShare {
    #[serde(rename = "pv")]
    payload_version: u8,
    #[serde(rename = "kv")]
    #[tsify(type = "number")]
    variant: ente_legacy::LegacyKitVariant,
    #[serde(rename = "k")]
    kit_id: String,
    #[serde(rename = "i")]
    share_index: u8,
    #[serde(rename = "s")]
    share: String,
    #[serde(rename = "c")]
    checksum: String,
    #[serde(rename = "n")]
    part_name: String,
}

impl From<ente_legacy::LegacyKitShare> for LegacyKitShare {
    fn from(value: ente_legacy::LegacyKitShare) -> Self {
        Self {
            payload_version: value.payload_version,
            variant: value.variant,
            kit_id: value.kit_id,
            share_index: value.share_index,
            share: value.share,
            checksum: value.checksum,
            part_name: value.part_name,
        }
    }
}

impl From<LegacyKitShare> for ente_legacy::LegacyKitShare {
    fn from(value: LegacyKitShare) -> Self {
        Self {
            payload_version: value.payload_version,
            variant: value.variant,
            kit_id: value.kit_id,
            share_index: value.share_index,
            share: value.share,
            checksum: value.checksum,
            part_name: value.part_name,
        }
    }
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct LegacyKitRecoverySession {
    id: String,
    #[serde(rename = "kitID")]
    kit_id: String,
    status: LegacyKitRecoveryStatus,
    // Remaining microseconds, not an epoch timestamp.
    wait_till: i64,
    created_at: i64,
}

impl From<ente_legacy::LegacyKitRecoverySession> for LegacyKitRecoverySession {
    fn from(value: ente_legacy::LegacyKitRecoverySession) -> Self {
        Self {
            id: value.id,
            kit_id: value.kit_id,
            status: value.status.into(),
            wait_till: value.wait_till,
            created_at: value.created_at,
        }
    }
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
enum LegacyKitRecoveryStatus {
    Waiting,
    Ready,
    Blocked,
    Cancelled,
    Recovered,
}

impl From<ente_legacy::LegacyKitRecoveryStatus> for LegacyKitRecoveryStatus {
    fn from(value: ente_legacy::LegacyKitRecoveryStatus) -> Self {
        match value {
            ente_legacy::LegacyKitRecoveryStatus::Waiting => Self::Waiting,
            ente_legacy::LegacyKitRecoveryStatus::Ready => Self::Ready,
            ente_legacy::LegacyKitRecoveryStatus::Blocked => Self::Blocked,
            ente_legacy::LegacyKitRecoveryStatus::Cancelled => Self::Cancelled,
            ente_legacy::LegacyKitRecoveryStatus::Recovered => Self::Recovered,
        }
    }
}
