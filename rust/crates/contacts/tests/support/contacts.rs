use ente_contacts::{
    client::{ContactsCtx, OpenContactsCtxInput},
    legacy_models::{LegacyContactRecord, LegacyInfo, LegacyRecoverySession},
};

use crate::CLIENT_PACKAGE;
use crate::support::auth::TestAccount;

pub async fn open_ctx(endpoint: &str, account: &TestAccount) -> ContactsCtx {
    ContactsCtx::open(OpenContactsCtxInput {
        base_url: endpoint.to_string(),
        auth_token: account.auth_token.clone(),
        user_id: account.user_id,
        master_key: account.master_key.clone(),
        cached_wrapped_root_contact_key: None,
        user_agent: Some("ente-contacts-e2e".to_string()),
        client_package: Some(CLIENT_PACKAGE.to_string()),
        client_version: Some("0.0.1".to_string()),
    })
    .await
    .unwrap()
    .ctx
}

pub async fn establish_legacy_contact(
    owner_ctx: &ContactsCtx,
    owner: &TestAccount,
    trusted_ctx: &ContactsCtx,
    trusted: &TestAccount,
    recovery_notice_in_days: i32,
) {
    owner_ctx
        .legacy_add_contact(
            &trusted.email,
            &owner.key_attributes,
            Some(recovery_notice_in_days),
        )
        .await
        .unwrap();
    trusted_ctx
        .legacy_update_contact(
            owner.user_id,
            trusted.user_id,
            ente_contacts::legacy_models::LegacyContactState::Accepted,
        )
        .await
        .unwrap();
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
