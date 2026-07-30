use ente_accounts::auth::KeyAttributes;
use ente_core::crypto::SecretVec;
use serde::{Deserialize, Deserializer, Serialize, Serializer, de};

pub const LEGACY_KIT_PAYLOAD_VERSION: u8 = 1;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LegacyKitVariant {
    TwoOfThree,
}

impl LegacyKitVariant {
    pub const TWO_OF_THREE_CODE: u8 = 1;

    pub fn code(self) -> u8 {
        match self {
            Self::TwoOfThree => Self::TWO_OF_THREE_CODE,
        }
    }

    pub fn threshold(self) -> usize {
        match self {
            Self::TwoOfThree => 2,
        }
    }

    pub fn part_count(self) -> usize {
        match self {
            Self::TwoOfThree => 3,
        }
    }

    pub fn from_code(code: u8) -> Option<Self> {
        match code {
            Self::TWO_OF_THREE_CODE => Some(Self::TwoOfThree),
            _ => None,
        }
    }
}

impl Serialize for LegacyKitVariant {
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_u8(self.code())
    }
}

impl<'de> Deserialize<'de> for LegacyKitVariant {
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let code = u8::deserialize(deserializer)?;
        Self::from_code(code).ok_or_else(|| de::Error::custom("invalid legacy kit variant"))
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum LegacyKitRecoveryStatus {
    Waiting,
    Ready,
    Blocked,
    Cancelled,
    Recovered,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct LegacyKitRecoverySession {
    pub id: String,
    #[serde(rename = "kitID")]
    pub kit_id: String,
    pub status: LegacyKitRecoveryStatus,
    /// Remaining microseconds until recovery is ready, matching the existing
    /// emergency legacy recovery API response contract.
    pub wait_till: i64,
    pub created_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct LegacyKitRecoveryInitiator {
    #[serde(default)]
    pub used_part_indexes: Vec<u8>,
    pub ip: String,
    pub user_agent: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct LegacyKitOwnerRecoverySession {
    pub session: Option<LegacyKitRecoverySession>,
    pub initiators: Vec<LegacyKitRecoveryInitiator>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct LegacyKitPart {
    pub index: u8,
    pub name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct LegacyKitMetadata {
    pub parts: Vec<LegacyKitPart>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct LegacyKit {
    pub id: String,
    pub variant: LegacyKitVariant,
    pub notice_period_in_hours: i32,
    pub legacy_url: String,
    pub metadata: LegacyKitMetadata,
    pub created_at: i64,
    pub updated_at: i64,
    pub active_recovery_session: Option<LegacyKitRecoverySession>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct LegacyKitShare {
    #[serde(rename = "pv")]
    pub payload_version: u8,
    #[serde(rename = "kv")]
    pub variant: LegacyKitVariant,
    #[serde(rename = "k")]
    pub kit_id: String,
    #[serde(rename = "i")]
    pub share_index: u8,
    #[serde(rename = "s")]
    pub share: String,
    #[serde(rename = "c")]
    pub checksum: String,
    #[serde(rename = "n")]
    pub part_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct LegacyKitCreateResult {
    pub kit: LegacyKit,
    pub shares: Vec<LegacyKitShare>,
}

#[derive(Debug)]
pub struct LegacyKitRecoveryBundle {
    pub recovery_key: SecretVec,
    pub user_key_attributes: KeyAttributes,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn legacy_kit_share_serializes_with_compact_qr_keys() {
        let share = LegacyKitShare {
            payload_version: LEGACY_KIT_PAYLOAD_VERSION,
            variant: LegacyKitVariant::TwoOfThree,
            kit_id: "kit-id".into(),
            share_index: 1,
            share: "share".into(),
            checksum: "checksum".into(),
            part_name: "North".into(),
        };

        let json = serde_json::to_string(&share).unwrap();
        assert_eq!(
            json,
            r#"{"pv":1,"kv":1,"k":"kit-id","i":1,"s":"share","c":"checksum","n":"North"}"#
        );
        let decoded: LegacyKitShare = serde_json::from_str(&json).unwrap();
        assert_eq!(decoded, share);
    }

    #[test]
    fn legacy_kit_share_rejects_unknown_variant() {
        let result = serde_json::from_str::<LegacyKitShare>(
            r#"{"pv":1,"kv":9,"k":"kit-id","i":1,"s":"share","c":"checksum","n":"North"}"#,
        );
        assert!(result.is_err());
    }
}
