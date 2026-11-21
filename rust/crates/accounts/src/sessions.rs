use ente_core::Session;
use serde::Deserialize;

use crate::Result;

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ActiveSession {
    #[serde(rename = "token")]
    pub id: String,
    // Older Museum releases omit isCurrent.
    #[serde(default)]
    pub is_current: bool,
    #[serde(rename = "creationTime")]
    pub created_at: i64,
    #[serde(rename = "lastUsedTime")]
    pub last_used_at: i64,
    pub ip: String,
    #[serde(rename = "ua")]
    pub user_agent: String,
    #[serde(rename = "prettyUA")]
    pub pretty_user_agent: String,
}

pub async fn list(session: &Session) -> Result<Vec<ActiveSession>> {
    #[derive(Deserialize)]
    struct Response {
        sessions: Vec<ActiveSession>,
    }

    let response: Response = session
        .api
        .get("/users/sessions")
        .send()
        .await?
        .error_for_code()
        .await?
        .json()
        .await?;
    Ok(response.sessions)
}

pub async fn revoke(session: &Session, id: &str) -> Result<()> {
    session
        .api
        .delete("/users/session")
        .query(&[("token", id)])
        .send()
        .await?
        .error_for_code()
        .await?;
    Ok(())
}
