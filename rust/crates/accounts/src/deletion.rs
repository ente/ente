use ente_core::{Session, b64, crypto::sealed, http};
use serde::{Deserialize, Serialize};

use crate::{Error, Result, auth::payload};

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AccountDeletionSummary {
    pub photos_and_videos_count: i64,
    pub authenticator_codes_count: i64,
    pub locker_records_count: i64,
}

pub async fn get_deletion_summary(session: &Session) -> Result<Option<AccountDeletionSummary>> {
    let response = send_request(session.api.get("/users/deletion-summary")).await;
    match response {
        Ok(response) => Ok(Some(response.json().await?)),
        Err(error) if error.status_code() == Some(404) => Ok(None),
        Err(error) => Err(error.into()),
    }
}

pub async fn get_delete_challenge(session: &Session) -> Result<String> {
    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct Response {
        encrypted_challenge: String,
    }

    let response: Response = send_request(session.api.get("/users/delete-challenge"))
        .await?
        .json()
        .await?;
    Ok(response.encrypted_challenge)
}

pub async fn delete_account(
    session: &Session,
    encrypted_challenge: &str,
    reason: &str,
    feedback: Option<&str>,
) -> Result<()> {
    #[derive(Serialize)]
    #[serde(rename_all = "camelCase")]
    struct Request<'a> {
        challenge: &'a str,
        reason_category: &'a str,
        #[serde(skip_serializing_if = "Option::is_none")]
        feedback: Option<&'a str>,
    }

    let challenge = sealed::open(
        &b64::decode(encrypted_challenge)?,
        &session.secret_key.public_key(),
        &session.secret_key,
    )?;
    let challenge = String::from_utf8(challenge).map_err(|e| Error::Decode(e.to_string()))?;
    let challenge = payload::deletion_challenge(&session.api, &challenge)?;
    send_request(session.api.delete("/users/delete").json(&Request {
        challenge,
        reason_category: reason,
        feedback: feedback.filter(|value| !value.is_empty()),
    }))
    .await?;
    Ok(())
}

async fn send_request(
    request: http::RequestBuilder,
) -> std::result::Result<http::SuccessResponse, http::Error> {
    request.send().await?.error_for_code().await
}
