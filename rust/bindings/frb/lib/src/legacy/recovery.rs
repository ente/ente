use crate::session::Session;

use super::types::LegacyError;

pub async fn start_recovery(
    session: &Session,
    user_id: i64,
    emergency_contact_id: i64,
) -> Result<(), LegacyError> {
    ente_legacy::start_recovery(session.as_ref(), user_id, emergency_contact_id)
        .await
        .map_err(Into::into)
}

pub async fn stop_recovery(
    session: &Session,
    recovery_id: String,
    user_id: i64,
    emergency_contact_id: i64,
) -> Result<(), LegacyError> {
    ente_legacy::stop_recovery(
        session.as_ref(),
        &recovery_id,
        user_id,
        emergency_contact_id,
    )
    .await
    .map_err(Into::into)
}

pub async fn reject_recovery(
    session: &Session,
    recovery_id: String,
    user_id: i64,
    emergency_contact_id: i64,
) -> Result<(), LegacyError> {
    ente_legacy::reject_recovery(
        session.as_ref(),
        &recovery_id,
        user_id,
        emergency_contact_id,
    )
    .await
    .map_err(Into::into)
}

pub async fn approve_recovery(
    session: &Session,
    recovery_id: String,
    user_id: i64,
    emergency_contact_id: i64,
) -> Result<(), LegacyError> {
    ente_legacy::approve_recovery(
        session.as_ref(),
        &recovery_id,
        user_id,
        emergency_contact_id,
    )
    .await
    .map_err(Into::into)
}

pub async fn change_password(
    session: &Session,
    recovery_id: String,
    new_password: String,
) -> Result<(), LegacyError> {
    ente_legacy::change_password(session.as_ref(), &recovery_id, &new_password)
        .await
        .map_err(Into::into)
}
