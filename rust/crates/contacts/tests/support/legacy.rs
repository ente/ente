use ente_core::{
    Session,
    crypto::SecretVec,
    http::{ApiConfig, Auth},
};
use ente_legacy::{LegacyContactRecord, LegacyContactState, LegacyInfo, LegacyRecoverySession};

use crate::CLIENT_PACKAGE;
use crate::support::auth::{self, TestAccount};

pub struct LegacyPairState {
    pub owner: TestAccount,
    pub trusted: TestAccount,
}

pub struct LegacyPair {
    pub owner: TestAccount,
    pub trusted: TestAccount,
    pub owner_session: Session,
    pub trusted_session: Session,
}

pub fn open_session(endpoint: &str, account: &TestAccount) -> Session {
    Session::new(
        ApiConfig {
            origin: endpoint.to_string(),
            client_package: Some(CLIENT_PACKAGE.to_string()),
            client_version: Some("0.0.1".to_string()),
            user_agent: Some("ente-legacy-e2e".to_string()),
            auth: Some(Auth::User(account.auth_token.clone())),
        },
        SecretVec::new(account.master_key.clone()),
    )
    .unwrap()
}

pub async fn create_accepted_pair_state(
    endpoint: &str,
    recovery_notice_in_days: i32,
) -> LegacyPairState {
    let owner = auth::create_account_strict(endpoint, "legacy-owner", "LegacyOwner").await;
    let trusted = auth::create_fixture_account(endpoint, "legacy-trusted").await;

    let owner_session = open_session(endpoint, &owner);
    let trusted_session = open_session(endpoint, &trusted);

    ente_legacy::add_contact(
        &owner_session,
        &trusted.email,
        &owner.key_attributes,
        Some(recovery_notice_in_days),
    )
    .await
    .unwrap();
    ente_legacy::update_contact(
        &trusted_session,
        owner.user_id,
        trusted.user_id,
        LegacyContactState::Accepted,
    )
    .await
    .unwrap();

    LegacyPairState { owner, trusted }
}

pub fn open_pair(endpoint: &str, state: &LegacyPairState) -> LegacyPair {
    let owner = state.owner.clone();
    let trusted = state.trusted.clone();
    let owner_session = open_session(endpoint, &owner);
    let trusted_session = open_session(endpoint, &trusted);

    LegacyPair {
        owner,
        trusted,
        owner_session,
        trusted_session,
    }
}

pub fn owner_contact(
    info: &LegacyInfo,
    owner_user_id: i64,
    trusted_user_id: i64,
) -> Option<&LegacyContactRecord> {
    info.contacts.iter().find(|record| {
        record.user.id == owner_user_id && record.emergency_contact.id == trusted_user_id
    })
}

pub fn trusted_contact(
    info: &LegacyInfo,
    owner_user_id: i64,
    trusted_user_id: i64,
) -> Option<&LegacyContactRecord> {
    info.others_emergency_contact.iter().find(|record| {
        record.user.id == owner_user_id && record.emergency_contact.id == trusted_user_id
    })
}

pub fn owner_recovery_session(
    info: &LegacyInfo,
    owner_user_id: i64,
    trusted_user_id: i64,
) -> Option<&LegacyRecoverySession> {
    info.recover_sessions.iter().find(|session| {
        session.user.id == owner_user_id && session.emergency_contact.id == trusted_user_id
    })
}

pub fn trusted_recovery_session(
    info: &LegacyInfo,
    owner_user_id: i64,
    trusted_user_id: i64,
) -> Option<&LegacyRecoverySession> {
    info.others_recovery_session.iter().find(|session| {
        session.user.id == owner_user_id && session.emergency_contact.id == trusted_user_id
    })
}
