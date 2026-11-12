use crate::session::{Session, SessionError};
use ente_accounts::deletion;

pub mod types;
pub use types::AccountDeletionSummary;

pub async fn get_deletion_summary(
    session: &Session,
) -> Result<Option<AccountDeletionSummary>, SessionError> {
    Ok(deletion::get_deletion_summary(session.as_ref())
        .await?
        .map(|summary| AccountDeletionSummary {
            photos_and_videos_count: summary.photos_and_videos_count,
            authenticator_codes_count: summary.authenticator_codes_count,
            locker_records_count: summary.locker_records_count,
        }))
}

pub async fn get_delete_challenge(session: &Session) -> Result<String, SessionError> {
    Ok(deletion::get_delete_challenge(session.as_ref()).await?)
}

pub async fn delete_account(
    session: &Session,
    encrypted_challenge: String,
    reason: String,
    feedback: Option<String>,
) -> Result<(), SessionError> {
    deletion::delete_account(
        session.as_ref(),
        &encrypted_challenge,
        &reason,
        feedback.as_deref(),
    )
    .await
    .map_err(Into::into)
}
