use ente_core::{
    Session,
    crypto::{Key, SecretKey},
    http::{ApiConfig, Auth},
};
use ente_test_support::account_fixture::TestAccount;

use crate::CLIENT_PACKAGE;

pub fn open_session(endpoint: &str, account: &TestAccount) -> Session {
    Session::new(
        ApiConfig {
            origin: endpoint.to_string(),
            client_package: Some(CLIENT_PACKAGE.to_string()),
            client_version: Some("0.0.1".to_string()),
            user_agent: Some("ente-contacts-e2e".to_string()),
            auth: Some(Auth::User(account.auth_token.clone())),
        },
        account.user_id,
        Key::try_from_slice(&account.master_key).unwrap(),
        Key::try_from_slice(&account.recovery_key).unwrap(),
        SecretKey::try_from_slice(&account.secret_key).unwrap(),
    )
    .unwrap()
}
