use ente_core::{Session, crypto::SecretString};
use serde::{Deserialize, Deserializer};

use crate::Result;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ActiveSession {
    #[serde(rename = "token")]
    pub id: SessionId,
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

#[derive(Debug, PartialEq, Eq)]
pub enum SessionId {
    Hashed(String),
    /// A live bearer token, which Museum releases without `th:` IDs return; never display it.
    LegacyToken(SecretString),
}

impl SessionId {
    pub fn hashed(&self) -> Option<&str> {
        match self {
            Self::Hashed(id) => Some(id),
            Self::LegacyToken(_) => None,
        }
    }

    fn wire(&self) -> &str {
        match self {
            Self::Hashed(id) => id,
            Self::LegacyToken(token) => token,
        }
    }
}

impl<'de> Deserialize<'de> for SessionId {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> std::result::Result<Self, D::Error> {
        let value = String::deserialize(deserializer)?;
        Ok(if value.starts_with("th:") {
            Self::Hashed(value)
        } else {
            Self::LegacyToken(value.into())
        })
    }
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

pub async fn revoke(session: &Session, id: &SessionId) -> Result<()> {
    session
        .api
        .delete("/users/session")
        .query(&[("token", id.wire())])
        .send()
        .await?
        .error_for_code()
        .await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use ente_core::{
        crypto::{Key, SecretKey},
        http::{ApiConfig, Auth},
    };
    use mockito::{Matcher, Server};
    use serde_json::json;

    use super::*;

    #[tokio::test]
    async fn legacy_tokens_revoke_without_being_debug_printed() {
        let mut server = Server::new_async().await;
        let entry = |token: &str| {
            json!({"token": token, "creationTime": 1, "lastUsedTime": 2, "ip": "203.0.113.7",
                "ua": "ente-cli", "prettyUA": "Other, Other"})
        };
        let listed = server
            .mock("GET", "/users/sessions")
            .with_body(
                json!({"sessions": [entry("raw-bearer-token"), entry("th:hash")]}).to_string(),
            )
            .create_async()
            .await;
        let revoked = server
            .mock("DELETE", "/users/session")
            .match_query(Matcher::UrlEncoded(
                "token".into(),
                "raw-bearer-token".into(),
            ))
            .create_async()
            .await;
        let session = Session::new(
            ApiConfig {
                auth: Some(Auth::User("token".into())),
                ..ApiConfig::new(server.url())
            },
            1,
            Key::try_from_slice(&[0; 32]).unwrap(),
            Key::try_from_slice(&[0; 32]).unwrap(),
            SecretKey::try_from_slice(&[0; 32]).unwrap(),
        )
        .unwrap();

        let sessions = list(&session).await.unwrap();
        assert_eq!(
            sessions[0].id,
            SessionId::LegacyToken("raw-bearer-token".to_owned().into())
        );
        assert!(!sessions[0].is_current);
        assert_eq!(sessions[1].id.hashed(), Some("th:hash"));
        assert!(!format!("{sessions:?}").contains("raw-bearer-token"));
        revoke(&session, &sessions[0].id).await.unwrap();
        listed.assert_async().await;
        revoked.assert_async().await;
    }
}
