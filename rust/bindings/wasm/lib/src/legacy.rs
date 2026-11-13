use serde::{Deserialize, Serialize};
use serde_wasm_bindgen as swb;
use tsify::Tsify;
use wasm_bindgen::prelude::*;

use crate::session::Session;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Legacy(#[from] ente_legacy::Error),
    #[error(transparent)]
    Serde(#[from] swb::Error),
}

impl Error {
    fn name(&self) -> Option<&'static str> {
        match self {
            Self::Legacy(ente_legacy::Error::ContactNotOnEnte) => Some("contact_not_on_ente"),
            Self::Legacy(ente_legacy::Error::ActiveRecoverySession) => {
                Some("active_recovery_session")
            }
            _ => None,
        }
    }
}

impl From<Error> for JsValue {
    fn from(error: Error) -> Self {
        crate::js_error(&error, error.name())
    }
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct LegacyInfo {
    contacts: Vec<LegacyContactRecord>,
    recover_sessions: Vec<LegacyRecoverySession>,
    others_emergency_contact: Vec<LegacyContactRecord>,
    others_recovery_session: Vec<LegacyRecoverySession>,
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

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
struct LegacyContactRecord {
    user: LegacyUser,
    emergency_contact: LegacyUser,
    state: LegacyContactState,
    recovery_notice_in_days: i32,
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

#[derive(Serialize, Deserialize, Tsify)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
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

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
struct LegacyRecoverySession {
    id: String,
    user: LegacyUser,
    emergency_contact: LegacyUser,
    status: LegacyRecoveryStatus,
    wait_till: i64,
    created_at: i64,
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

#[derive(Serialize, Tsify)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
enum LegacyRecoveryStatus {
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

#[derive(Serialize, Tsify)]
struct LegacyUser {
    id: i64,
    email: String,
}

impl From<ente_legacy::LegacyUser> for LegacyUser {
    fn from(value: ente_legacy::LegacyUser) -> Self {
        Self {
            id: value.id,
            email: value.email,
        }
    }
}

#[wasm_bindgen(js_name = legacyGetInfo)]
pub async fn legacy_get_info(session: &Session) -> Result<<LegacyInfo as Tsify>::JsType, Error> {
    LegacyInfo::from(ente_legacy::info(session.inner()).await?)
        .into_js()
        .map_err(Into::into)
}

#[wasm_bindgen(js_name = legacyPublicKey)]
pub async fn legacy_public_key(session: &Session, email: String) -> Result<Option<String>, Error> {
    ente_legacy::public_key(session.inner(), &email)
        .await
        .map_err(Into::into)
}

#[wasm_bindgen(js_name = legacyVerificationID)]
pub fn legacy_verification_id(public_key_b64: String) -> Result<String, Error> {
    ente_legacy::verification_id(&public_key_b64).map_err(Into::into)
}

#[wasm_bindgen(js_name = legacyAddContact)]
pub async fn legacy_add_contact(
    session: &Session,
    email: String,
    recovery_notice_in_days: Option<i32>,
) -> Result<(), Error> {
    ente_legacy::add_contact(session.inner(), &email, recovery_notice_in_days)
        .await
        .map_err(Into::into)
}

#[wasm_bindgen(js_name = legacyUpdateContact)]
pub async fn legacy_update_contact(
    session: &Session,
    user_id: i64,
    emergency_contact_id: i64,
    state: <LegacyContactState as Tsify>::JsType,
) -> Result<(), Error> {
    let state = LegacyContactState::from_js(state)?;
    ente_legacy::update_contact(session.inner(), user_id, emergency_contact_id, state.into())
        .await
        .map_err(Into::into)
}

#[wasm_bindgen(js_name = legacyUpdateRecoveryNotice)]
pub async fn legacy_update_recovery_notice(
    session: &Session,
    emergency_contact_id: i64,
    recovery_notice_in_days: i32,
) -> Result<(), Error> {
    ente_legacy::update_recovery_notice(
        session.inner(),
        emergency_contact_id,
        recovery_notice_in_days,
    )
    .await
    .map_err(Into::into)
}

#[wasm_bindgen(js_name = legacyStartRecovery)]
pub async fn legacy_start_recovery(
    session: &Session,
    user_id: i64,
    emergency_contact_id: i64,
) -> Result<(), Error> {
    ente_legacy::start_recovery(session.inner(), user_id, emergency_contact_id)
        .await
        .map_err(Into::into)
}

#[wasm_bindgen(js_name = legacyStopRecovery)]
pub async fn legacy_stop_recovery(
    session: &Session,
    recovery_id: String,
    user_id: i64,
    emergency_contact_id: i64,
) -> Result<(), Error> {
    ente_legacy::stop_recovery(session.inner(), &recovery_id, user_id, emergency_contact_id)
        .await
        .map_err(Into::into)
}

#[wasm_bindgen(js_name = legacyRejectRecovery)]
pub async fn legacy_reject_recovery(
    session: &Session,
    recovery_id: String,
    user_id: i64,
    emergency_contact_id: i64,
) -> Result<(), Error> {
    ente_legacy::reject_recovery(session.inner(), &recovery_id, user_id, emergency_contact_id)
        .await
        .map_err(Into::into)
}

#[wasm_bindgen(js_name = legacyChangePassword)]
pub async fn legacy_change_password(
    session: &Session,
    recovery_id: String,
    new_password: String,
) -> Result<(), Error> {
    ente_legacy::change_password(session.inner(), &recovery_id, &new_password)
        .await
        .map_err(Into::into)
}
