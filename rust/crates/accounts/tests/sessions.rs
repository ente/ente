#![cfg(test)]
#![cfg(feature = "museum")]

use ente_accounts::{
    AccountsClient, AccountsClientConfig, Error,
    sessions::{self, SessionId},
};
use ente_core::{
    Session, b64,
    crypto::{Key, SecretKey},
    http::{ApiConfig, Auth},
};
use ente_test_support::{
    Museum, TestResult,
    account_fixture::{TestAccount, create_account},
};

const SECOND_DEVICE: &str = "ente-sessions-second-device";

#[test]
fn sessions() -> TestResult {
    Museum::run_async(|endpoint| async move {
        let account = create_account(&endpoint, "sessions").await?;
        let first = open_session(
            &endpoint,
            &account,
            account.auth_token.clone(),
            "ente-tests",
        )?;

        let listed = sessions::list(&first).await?;
        assert_eq!(listed.len(), 1);
        assert!(listed[0].is_current);
        let first_id = listed[0].id.hashed().unwrap().to_owned();
        assert!(first_id.starts_with("th:"), "{first_id}");
        assert!(listed[0].created_at > 0);
        assert!(listed[0].last_used_at >= listed[0].created_at);

        let client = AccountsClient::new(
            AccountsClientConfig::new("io.ente.photos")
                .with_origin(endpoint.clone())
                .with_user_agent(SECOND_DEVICE),
        )?;
        let attributes = client.get_srp_attributes(&account.email).await?;
        let (response, kek) = client
            .login_with_srp(&account.password, &attributes)
            .await?;
        let token = b64::encode_url_safe(&client.unlock(&response, &kek)?.secrets.token);
        let second = open_session(&endpoint, &account, token, SECOND_DEVICE)?;

        let listed = sessions::list(&first).await?;
        assert_eq!(listed.len(), 2);
        let other = listed.iter().find(|s| s.id != hashed(&first_id)).unwrap();
        assert!(
            listed
                .iter()
                .find(|s| s.id == hashed(&first_id))
                .unwrap()
                .is_current
        );
        assert!(!other.is_current);
        assert_eq!(other.user_agent, SECOND_DEVICE);
        assert!(!other.pretty_user_agent.is_empty());
        let second_id = other.id.hashed().unwrap().to_owned();
        let seen_by_second = sessions::list(&second).await?;
        assert!(
            seen_by_second
                .iter()
                .all(|s| s.is_current == (s.id == hashed(&second_id)))
        );

        assert_eq!(
            status(sessions::revoke(&first, &hashed(&first_id)).await),
            Some(400)
        );
        assert_eq!(sessions::list(&first).await?.len(), 2);

        sessions::revoke(&first, &hashed(&second_id)).await?;
        assert_eq!(status(sessions::list(&second).await), Some(401));
        let listed = sessions::list(&first).await?;
        assert_eq!(listed.len(), 1);
        assert_eq!(listed[0].id, hashed(&first_id));

        sessions::revoke(&first, &hashed(&second_id)).await?;
        sessions::revoke(&first, &hashed(&format!("th:{}", "A".repeat(43)))).await?;
        assert_eq!(
            status(sessions::revoke(&first, &hashed("th:not-a-hash")).await),
            Some(400)
        );
        assert_eq!(sessions::list(&first).await?.len(), 1);
        Ok(())
    })
}

fn hashed(id: &str) -> SessionId {
    SessionId::Hashed(id.to_owned())
}

fn status<T>(result: ente_accounts::Result<T>) -> Option<u16> {
    match result {
        Err(Error::Http(error)) => error.status_code(),
        Err(error) => panic!("unexpected error: {error}"),
        Ok(_) => None,
    }
}

fn open_session(
    endpoint: &str,
    account: &TestAccount,
    token: String,
    user_agent: &str,
) -> TestResult<Session> {
    Ok(Session::new(
        ApiConfig {
            client_package: Some("io.ente.photos".into()),
            user_agent: Some(user_agent.into()),
            auth: Some(Auth::User(token)),
            ..ApiConfig::new(endpoint.into())
        },
        account.user_id,
        Key::try_from_slice(&account.master_key)?,
        Key::try_from_slice(&account.recovery_key)?,
        SecretKey::try_from_slice(&account.secret_key)?,
    )?)
}
