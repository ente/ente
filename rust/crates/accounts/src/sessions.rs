use ente_core::Session;
use serde::{Deserialize, Deserializer};
use zeroize::Zeroize;

use crate::{Error, Result};

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ActiveSession {
    #[serde(rename = "token", deserialize_with = "hashed_id")]
    pub id: String,
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

fn hashed_id<'de, D: Deserializer<'de>>(deserializer: D) -> std::result::Result<String, D::Error> {
    let mut id = String::deserialize(deserializer)?;
    if !id.starts_with("th:") {
        id.zeroize();
    }
    Ok(id)
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
    if response.sessions.iter().any(|s| !s.id.starts_with("th:")) {
        return Err(Error::SessionIdsUnsupported);
    }
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

#[cfg(test)]
mod tests {
    use ente_core::{
        crypto::{Key, SecretKey},
        http::{ApiConfig, Auth},
    };
    use mockito::Server;
    use serde_json::json;

    use super::*;

    #[tokio::test]
    async fn raw_tokens_fail_the_list_without_being_kept() {
        let mut server = Server::new_async().await;
        let entry = |token: &str| {
            json!({"token": token, "isCurrent": false, "creationTime": 1, "lastUsedTime": 2,
                "ip": "203.0.113.7", "ua": "ente-cli", "prettyUA": "Other, Other"})
        };
        let listed = server
            .mock("GET", "/users/sessions")
            .with_body(
                json!({"sessions": [entry("th:hash"), entry("raw-bearer-token")]}).to_string(),
            )
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

        let error = list(&session).await.unwrap_err();
        assert!(matches!(error, Error::SessionIdsUnsupported), "{error:?}");
        for output in [error.to_string(), format!("{error:?}")] {
            assert!(!output.contains("raw-bearer-token"), "{output}");
        }
        listed.assert_async().await;
    }
}
