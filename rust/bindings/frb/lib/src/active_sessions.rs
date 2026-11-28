use crate::session::{Session, SessionError};
use ente_accounts::sessions;

pub mod types;
pub use types::ActiveSession;

pub async fn list_active_sessions(session: &Session) -> Result<Vec<ActiveSession>, SessionError> {
    Ok(sessions::list(session.as_ref())
        .await?
        .into_iter()
        .map(Into::into)
        .collect())
}

pub async fn revoke_active_session(session: &Session, id: String) -> Result<(), SessionError> {
    sessions::revoke(session.as_ref(), &id)
        .await
        .map_err(Into::into)
}
