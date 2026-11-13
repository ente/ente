use crate::session::Session;

use super::types::{LegacyContactState, LegacyError, LegacyInfo};

pub async fn info(session: &Session) -> Result<LegacyInfo, LegacyError> {
    Ok(ente_legacy::info(session.as_ref()).await?.into())
}

pub async fn add_contact(
    session: &Session,
    email: String,
    recovery_notice_in_days: i32,
) -> Result<(), LegacyError> {
    ente_legacy::add_contact(session.as_ref(), &email, Some(recovery_notice_in_days))
        .await
        .map_err(Into::into)
}

pub async fn update_contact(
    session: &Session,
    user_id: i64,
    emergency_contact_id: i64,
    state: LegacyContactState,
) -> Result<(), LegacyError> {
    ente_legacy::update_contact(
        session.as_ref(),
        user_id,
        emergency_contact_id,
        state.into(),
    )
    .await
    .map_err(Into::into)
}

pub async fn update_recovery_notice(
    session: &Session,
    emergency_contact_id: i64,
    recovery_notice_in_days: i32,
) -> Result<(), LegacyError> {
    ente_legacy::update_recovery_notice(
        session.as_ref(),
        emergency_contact_id,
        recovery_notice_in_days,
    )
    .await
    .map_err(Into::into)
}
