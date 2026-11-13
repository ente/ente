use flutter_rust_bridge::frb;

#[frb(non_opaque)]
pub enum LegacyError {
    ContactNotOnEnte { message: String },
    ActiveRecoverySession { message: String },
    Other { message: String },
}

impl From<ente_legacy::Error> for LegacyError {
    fn from(error: ente_legacy::Error) -> Self {
        let message = ente_core::error::chain(&error);
        match error {
            ente_legacy::Error::ContactNotOnEnte => Self::ContactNotOnEnte { message },
            ente_legacy::Error::ActiveRecoverySession => Self::ActiveRecoverySession { message },
            _ => Self::Other { message },
        }
    }
}

#[frb(unignore)]
#[derive(Clone)]
pub struct LegacyUser {
    pub id: i64,
    pub email: String,
}

impl From<ente_legacy::LegacyUser> for LegacyUser {
    fn from(value: ente_legacy::LegacyUser) -> Self {
        Self {
            id: value.id,
            email: value.email,
        }
    }
}

#[frb(unignore)]
#[derive(Clone)]
pub struct LegacyContactRecord {
    pub user: LegacyUser,
    pub emergency_contact: LegacyUser,
    pub state: LegacyContactState,
    pub recovery_notice_in_days: i32,
}

impl From<ente_legacy::LegacyContactRecord> for LegacyContactRecord {
    fn from(value: ente_legacy::LegacyContactRecord) -> Self {
        Self {
            user: value.user.into(),
            emergency_contact: value.emergency_contact.into(),
            state: value.state.into(),
            recovery_notice_in_days: value.recovery_notice_in_days,
        }
    }
}

#[frb(unignore)]
#[derive(Clone)]
pub struct LegacyRecoverySession {
    pub id: String,
    pub user: LegacyUser,
    pub emergency_contact: LegacyUser,
    pub status: LegacyRecoveryStatus,
    pub wait_till: i64,
    pub created_at: i64,
}

impl From<ente_legacy::LegacyRecoverySession> for LegacyRecoverySession {
    fn from(value: ente_legacy::LegacyRecoverySession) -> Self {
        Self {
            id: value.id,
            user: value.user.into(),
            emergency_contact: value.emergency_contact.into(),
            status: value.status.into(),
            wait_till: value.wait_till,
            created_at: value.created_at,
        }
    }
}

#[frb(unignore)]
#[derive(Clone)]
pub struct LegacyInfo {
    pub contacts: Vec<LegacyContactRecord>,
    pub recover_sessions: Vec<LegacyRecoverySession>,
    pub others_emergency_contact: Vec<LegacyContactRecord>,
    pub others_recovery_session: Vec<LegacyRecoverySession>,
}

impl From<ente_legacy::LegacyInfo> for LegacyInfo {
    fn from(value: ente_legacy::LegacyInfo) -> Self {
        Self {
            contacts: value.contacts.into_iter().map(Into::into).collect(),
            recover_sessions: value.recover_sessions.into_iter().map(Into::into).collect(),
            others_emergency_contact: value
                .others_emergency_contact
                .into_iter()
                .map(Into::into)
                .collect(),
            others_recovery_session: value
                .others_recovery_session
                .into_iter()
                .map(Into::into)
                .collect(),
        }
    }
}

#[frb(unignore)]
#[derive(Clone, Copy)]
pub enum LegacyContactState {
    Invited,
    Revoked,
    Accepted,
    ContactLeft,
    ContactDenied,
}

impl From<ente_legacy::LegacyContactState> for LegacyContactState {
    fn from(value: ente_legacy::LegacyContactState) -> Self {
        match value {
            ente_legacy::LegacyContactState::Invited => Self::Invited,
            ente_legacy::LegacyContactState::Revoked => Self::Revoked,
            ente_legacy::LegacyContactState::Accepted => Self::Accepted,
            ente_legacy::LegacyContactState::ContactLeft => Self::ContactLeft,
            ente_legacy::LegacyContactState::ContactDenied => Self::ContactDenied,
        }
    }
}

impl From<LegacyContactState> for ente_legacy::LegacyContactState {
    fn from(value: LegacyContactState) -> Self {
        match value {
            LegacyContactState::Invited => Self::Invited,
            LegacyContactState::Revoked => Self::Revoked,
            LegacyContactState::Accepted => Self::Accepted,
            LegacyContactState::ContactLeft => Self::ContactLeft,
            LegacyContactState::ContactDenied => Self::ContactDenied,
        }
    }
}

#[frb(unignore)]
#[derive(Clone, Copy)]
pub enum LegacyRecoveryStatus {
    Initiated,
    Waiting,
    Rejected,
    Recovered,
    Stopped,
    Ready,
}

impl From<ente_legacy::LegacyRecoveryStatus> for LegacyRecoveryStatus {
    fn from(value: ente_legacy::LegacyRecoveryStatus) -> Self {
        match value {
            ente_legacy::LegacyRecoveryStatus::Initiated => Self::Initiated,
            ente_legacy::LegacyRecoveryStatus::Waiting => Self::Waiting,
            ente_legacy::LegacyRecoveryStatus::Rejected => Self::Rejected,
            ente_legacy::LegacyRecoveryStatus::Recovered => Self::Recovered,
            ente_legacy::LegacyRecoveryStatus::Stopped => Self::Stopped,
            ente_legacy::LegacyRecoveryStatus::Ready => Self::Ready,
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

impl TryFrom<ente_legacy::LegacyKitCreateResult> for LegacyKitCreateResult {
    type Error = LegacyError;

    fn try_from(value: ente_legacy::LegacyKitCreateResult) -> Result<Self, Self::Error> {
        Ok(Self {
            kit: value.kit.into(),
            shares: value
                .shares
                .into_iter()
                .map(TryInto::try_into)
                .collect::<Result<_, _>>()?,
        })
    }
}

#[frb(unignore)]
#[derive(Clone)]
pub struct LegacyKitShare {
    pub share_index: u8,
    pub part_name: String,
    pub qr_payload: String,
    pub copy_code: String,
}

impl TryFrom<ente_legacy::LegacyKitShare> for LegacyKitShare {
    type Error = LegacyError;

    fn try_from(value: ente_legacy::LegacyKitShare) -> Result<Self, Self::Error> {
        Ok(Self {
            qr_payload: value.to_qr_payload()?,
            copy_code: value.to_copy_code()?,
            share_index: value.share_index,
            part_name: value.part_name,
        })
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
