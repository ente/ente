use ente_core::{Session, http};
use serde::{Deserialize, Serialize};

use crate::{Error, Result};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
pub struct EmailMfaStatus {
    #[serde(rename = "isEmailMFAEnabled")]
    pub enabled: bool,
    #[serde(rename = "canDisableEmailMFA")]
    pub can_disable: bool,
}

pub async fn get_email_mfa_status(session: &Session) -> Result<EmailMfaStatus> {
    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct Details {
        profile_data: EmailMfaStatus,
    }

    let details: Details = session
        .api
        .get("/users/details/v2")
        .query(&[("memoryCount", false)])
        .send()
        .await?
        .error_for_code()
        .await?
        .json()
        .await?;
    Ok(details.profile_data)
}

pub async fn set_email_mfa(session: &Session, enabled: bool) -> Result<()> {
    #[derive(Serialize)]
    #[serde(rename_all = "camelCase")]
    struct Request {
        is_enabled: bool,
    }

    session
        .api
        .put("/users/email-mfa")
        .json(&Request {
            is_enabled: enabled,
        })
        .send()
        .await?
        .error_for_code()
        .await
        .map_err(|error| match error.status_code() {
            Some(409) => Error::SrpNotConfigured,
            _ => error.into(),
        })?;
    Ok(())
}

pub async fn change_email(session: &Session, email: &str, ott: &str) -> Result<()> {
    #[derive(Serialize)]
    struct Request<'a> {
        email: &'a str,
        ott: &'a str,
    }

    session
        .api
        .post("/users/change-email")
        .json(&Request { email, ott })
        .send()
        .await?
        .error_for_code()
        .await
        .map_err(|error| match error {
            http::Error::Api {
                status: 401,
                ref code,
                ..
            } if code == "INCORRECT_OTT" => Error::IncorrectEmailVerificationCode,
            error if error.status_code() == Some(401) => Error::SessionInvalid,
            error if error.status_code() == Some(403) => Error::EmailAlreadyInUse,
            error if error.status_code() == Some(410) => Error::EmailVerificationCodeExpired,
            error if error.status_code() == Some(429) => Error::EmailVerificationRateLimited,
            error => error.into(),
        })?;
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

    fn session(origin: String) -> Session {
        let mut config = ApiConfig::new(origin);
        config.auth = Some(Auth::User("token".into()));
        Session::new(
            config,
            1,
            Key::generate(),
            Key::generate(),
            SecretKey::generate(),
        )
        .unwrap()
    }

    #[tokio::test]
    async fn email_mfa_status_reads_the_profile_and_updates_send_the_flag() {
        let mut server = Server::new_async().await;
        let details = server
            .mock("GET", "/users/details/v2")
            .match_query(Matcher::UrlEncoded("memoryCount".into(), "false".into()))
            .match_header("x-auth-token", "token")
            .with_body(
                json!({"email": "a@example.org", "profileData": {"isEmailMFAEnabled": true,
                "canDisableEmailMFA": false, "isTwoFactorEnabled": false, "passkeyCount": 0}})
                .to_string(),
            )
            .create_async()
            .await;
        let update = server
            .mock("PUT", "/users/email-mfa")
            .match_body(Matcher::Json(json!({"isEnabled": false})))
            .with_status(409)
            .with_body(r#"{"code":"CONFLICT"}"#)
            .create_async()
            .await;
        let session = session(server.url());
        assert_eq!(
            get_email_mfa_status(&session).await.unwrap(),
            EmailMfaStatus {
                enabled: true,
                can_disable: false
            }
        );
        assert!(matches!(
            set_email_mfa(&session, false).await,
            Err(Error::SrpNotConfigured)
        ));
        details.assert_async().await;
        update.assert_async().await;
    }

    #[tokio::test]
    async fn change_email_classifies_verification_failures() {
        type Expected = fn(&Error) -> bool;
        let cases: [(usize, &str, Expected); 5] = [
            (
                401,
                r#"{"code":"INCORRECT_OTT","message":"Incorrect OTT"}"#,
                |error| matches!(error, Error::IncorrectEmailVerificationCode),
            ),
            (401, r#"{"error":"invalid token"}"#, |error| {
                matches!(error, Error::SessionInvalid)
            }),
            (403, "{}", |error| matches!(error, Error::EmailAlreadyInUse)),
            (410, "{}", |error| {
                matches!(error, Error::EmailVerificationCodeExpired)
            }),
            (429, "{}", |error| {
                matches!(error, Error::EmailVerificationRateLimited)
            }),
        ];
        for (status, body, expected) in cases {
            let mut server = Server::new_async().await;
            let change = server
                .mock("POST", "/users/change-email")
                .match_body(Matcher::Json(
                    json!({"email": "b@example.org", "ott": "123456"}),
                ))
                .with_status(status)
                .with_body(body)
                .expect(1)
                .create_async()
                .await;
            let error = change_email(&session(server.url()), "b@example.org", "123456")
                .await
                .unwrap_err();
            assert!(expected(&error), "{status} {body}: {error:?}");
            change.assert_async().await;
        }
    }
}
