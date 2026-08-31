use flutter_rust_bridge::frb;

#[frb(non_opaque)]
pub enum LegacyError {
    ActiveRecoverySession { message: String },
    Other { message: String },
}

impl From<ente_legacy::Error> for LegacyError {
    fn from(error: ente_legacy::Error) -> Self {
        let message = ente_core::error::chain(&error);
        match error {
            ente_legacy::Error::ActiveRecoverySession => Self::ActiveRecoverySession { message },
            _ => Self::Other { message },
        }
    }
}

#[frb(unignore)]
#[derive(Clone)]
pub struct LegacyKit {
    pub id: String,
    pub notice_period_in_hours: i32,
    pub legacy_url: String,
    pub parts: Vec<LegacyKitPart>,
    pub created_at: i64,
    pub updated_at: i64,
    pub active_recovery_session: Option<LegacyKitRecoverySession>,
}

impl From<ente_legacy::LegacyKit> for LegacyKit {
    fn from(value: ente_legacy::LegacyKit) -> Self {
        Self {
            id: value.id,
            notice_period_in_hours: value.notice_period_in_hours,
            legacy_url: value.legacy_url,
            parts: value.metadata.parts.into_iter().map(Into::into).collect(),
            created_at: value.created_at,
            updated_at: value.updated_at,
            active_recovery_session: value.active_recovery_session.map(Into::into),
        }
    }
}

#[frb(unignore)]
#[derive(Clone)]
pub struct LegacyKitCreateResult {
    pub kit: LegacyKit,
    pub shares: Vec<LegacyKitShare>,
}

impl From<ente_legacy::LegacyKitCreateResult> for LegacyKitCreateResult {
    fn from(value: ente_legacy::LegacyKitCreateResult) -> Self {
        Self {
            kit: value.kit.into(),
            shares: value.shares.into_iter().map(Into::into).collect(),
        }
    }
}

#[frb(unignore)]
#[derive(Clone)]
pub struct LegacyKitShare {
    pub payload_version: u8,
    pub variant: u8,
    pub kit_id: String,
    pub share_index: u8,
    pub share: String,
    pub checksum: String,
    pub part_name: String,
}

impl From<ente_legacy::LegacyKitShare> for LegacyKitShare {
    fn from(value: ente_legacy::LegacyKitShare) -> Self {
        Self {
            payload_version: value.payload_version,
            variant: value.variant.code(),
            kit_id: value.kit_id,
            share_index: value.share_index,
            share: value.share,
            checksum: value.checksum,
            part_name: value.part_name,
        }
    }
}

#[frb(unignore)]
#[derive(Clone)]
pub struct LegacyKitPart {
    pub index: u8,
    pub name: String,
}

impl From<ente_legacy::LegacyKitPart> for LegacyKitPart {
    fn from(value: ente_legacy::LegacyKitPart) -> Self {
        Self {
            index: value.index,
            name: value.name,
        }
    }
}

#[frb(unignore)]
#[derive(Clone)]
pub struct LegacyKitRecoverySession {
    pub id: String,
    pub kit_id: String,
    pub status: LegacyKitRecoveryStatus,
    pub wait_till: i64,
    pub created_at: i64,
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

#[frb(unignore)]
#[derive(Clone, Copy)]
pub enum LegacyKitRecoveryStatus {
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
