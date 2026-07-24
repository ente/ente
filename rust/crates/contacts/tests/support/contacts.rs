use ente_accounts::KeyAttributes as ApiKeyAttributes;
use ente_contacts::{
    client::{ContactsCtx, OpenContactsCtxInput},
    legacy_models::{LegacyContactRecord, LegacyInfo, LegacyRecoverySession},
};
use ente_core::auth::KeyAttributes as CoreKeyAttributes;

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
            &to_core_key_attributes(&owner.key_attributes),
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

pub fn to_core_key_attributes(attributes: &ApiKeyAttributes) -> CoreKeyAttributes {
    CoreKeyAttributes {
        kek_salt: attributes.kek_salt.clone(),
        encrypted_key: attributes.encrypted_key.clone(),
        key_decryption_nonce: attributes.key_decryption_nonce.clone(),
        public_key: attributes.public_key.clone(),
        encrypted_secret_key: attributes.encrypted_secret_key.clone(),
        secret_key_decryption_nonce: attributes.secret_key_decryption_nonce.clone(),
        mem_limit: Some(attributes.mem_limit as u32),
        ops_limit: Some(attributes.ops_limit as u32),
        master_key_encrypted_with_recovery_key: attributes
            .master_key_encrypted_with_recovery_key
            .clone(),
        master_key_decryption_nonce: attributes.master_key_decryption_nonce.clone(),
        recovery_key_encrypted_with_master_key: attributes
            .recovery_key_encrypted_with_master_key
            .clone(),
        recovery_key_decryption_nonce: attributes.recovery_key_decryption_nonce.clone(),
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
