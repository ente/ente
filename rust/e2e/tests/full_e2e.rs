mod support;

use ente_accounts::Error as CliError;
use ente_contacts::models::ContactData;
use ente_contacts::{
    LegacyKitRecoveryClient, LegacyKitRecoveryStatus,
    legacy_models::{LegacyContactState, LegacyRecoveryStatus},
};
use ente_core::http::Error as CoreHttpError;
use ente_rs::models::account::App;
use ente_test_support::{Museum, TestResult};
use serde::{Deserialize, Serialize};
use serde_json::json;
use uuid::Uuid;

use support::{auth, contacts, legacy, legacy_kit};

const STAGE_AUTH_CONTACTS: &str = "auth_contacts_e2e";
const STAGE_LEGACY_CONTACT_RECOVERY: &str = "legacy_contact_recovery_e2e";
const STAGE_LEGACY_KIT_RECOVERY: &str = "legacy_kit_recovery_e2e";

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LegacyKitChallengeRequest {
    #[serde(rename = "kitID")]
    kit_id: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LegacyKitChallengeResponse {
    #[serde(rename = "encryptedChallenge")]
    encrypted_challenge: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LegacyKitOpenRecoveryRequest {
    #[serde(rename = "kitID")]
    kit_id: String,
    challenge: String,
    used_part_indexes: Option<Vec<u8>>,
    email: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CreateLegacyKitRequest {
    id: String,
    variant: i32,
    notice_period_in_hours: i32,
    encrypted_recovery_blob: String,
    auth_public_key: String,
    encrypted_owner_blob: String,
}

#[test]
fn full_e2e() -> TestResult {
    Museum::run(|museum| run_stages(museum.endpoint()))
}

fn run_stages(endpoint: &str) -> TestResult {
    tokio::runtime::Runtime::new()?.block_on(async {
        let auth_contacts = support::stage_enabled(STAGE_AUTH_CONTACTS);
        let legacy_recovery = support::stage_enabled(STAGE_LEGACY_CONTACT_RECOVERY);

        let pair_state = if auth_contacts || legacy_recovery {
            Some(legacy::create_accepted_pair_state(endpoint, 14).await)
        } else {
            None
        };

        if auth_contacts {
            let pair = legacy::open_pair(endpoint, pair_state.as_ref().unwrap()).await;
            run_auth_stage(endpoint, &pair.owner).await;
            run_contacts_stage(&pair).await;
        }

        if legacy_recovery {
            let mut pair = legacy::open_pair(endpoint, pair_state.as_ref().unwrap()).await;
            ensure_totp_enabled(endpoint, &pair.owner).await;
            run_legacy_reject_stage(&pair).await;
            run_legacy_stop_stage(&pair).await;
            run_legacy_reinvite_stage(&pair).await;
            run_legacy_reset_stage(endpoint, &mut pair).await;
        }

        if support::stage_enabled(STAGE_LEGACY_KIT_RECOVERY) {
            let mut owner = legacy_kit::create_owner(endpoint).await;
            ensure_totp_enabled(endpoint, &owner.owner).await;
            run_legacy_kit_stage(endpoint, &mut owner).await;
        }

        Ok(())
    })
}

async fn run_auth_stage(endpoint: &str, owner: &auth::TestAccount) {
    let first_login = auth::login_without_totp(endpoint, &owner.email, &owner.password)
        .await
        .expect("initial login failed");
    assert_eq!(first_login.user_id, owner.user_id);
    assert_eq!(first_login.secrets.master_key, owner.master_key);

    let totp_secret = auth::enable_totp(endpoint, owner).await;

    let second_login = auth::login_with_totp(endpoint, &owner.email, &owner.password, &totp_secret)
        .await
        .expect("two-factor login failed");
    assert_eq!(second_login.user_id, owner.user_id);
    assert_eq!(second_login.secrets.master_key, owner.master_key);
    assert!(
        auth::fetch_two_factor_status(endpoint, owner)
            .await
            .expect("two-factor status fetch failed")
    );
}

async fn ensure_totp_enabled(endpoint: &str, owner: &auth::TestAccount) {
    if auth::fetch_two_factor_status(endpoint, owner)
        .await
        .expect("two-factor status fetch before recovery failed")
    {
        return;
    }
    let _secret = auth::enable_totp(endpoint, owner).await;
    assert!(
        auth::fetch_two_factor_status(endpoint, owner)
            .await
            .expect("two-factor status fetch after enable failed")
    );
}

async fn run_contacts_stage(pair: &legacy::LegacyPair) {
    let initial_data = ContactData {
        contact_user_id: pair.trusted.user_id,
        name: "Trusted Contact".to_string(),
        birth_date: Some("2001-04-01".to_string()),
    };

    let contact = pair.owner_ctx.create_contact(&initial_data).await.unwrap();
    assert_eq!(contact.contact_user_id, pair.trusted.user_id);
    assert_eq!(contact.email.as_deref(), Some(pair.trusted.email.as_str()));

    let fetched = pair.owner_ctx.get_contact(&contact.id).await.unwrap();
    assert_eq!(fetched.id, contact.id);
    assert_eq!(fetched.name.as_deref(), Some("Trusted Contact"));

    let updated = pair
        .owner_ctx
        .update_contact(
            &contact.id,
            &ContactData {
                contact_user_id: pair.trusted.user_id,
                name: "Trusted Contact Updated".to_string(),
                birth_date: Some("2001-04-02".to_string()),
            },
        )
        .await
        .unwrap();
    assert_eq!(updated.name.as_deref(), Some("Trusted Contact Updated"));
    assert_eq!(updated.birth_date.as_deref(), Some("2001-04-02"));

    let diff = pair.owner_ctx.get_diff(0, 5000).await.unwrap();
    assert!(diff.iter().any(|entry| entry.id == contact.id));

    match pair.trusted_ctx.get_contact(&contact.id).await {
        Err(ente_contacts::ContactsError::Http(CoreHttpError::Http { status: 404, .. })) => {}
        other => panic!("expected trusted account to get 404 for owner contact, got {other:?}"),
    }

    pair.owner_ctx.delete_contact(&contact.id).await.unwrap();
}

async fn run_legacy_reject_stage(pair: &legacy::LegacyPair) {
    pair.trusted_ctx
        .legacy_start_recovery(pair.owner.user_id, pair.trusted.user_id)
        .await
        .unwrap();

    let owner_info = pair.owner_ctx.legacy_info().await.unwrap();
    let recovery =
        contacts::owner_recovery_session(&owner_info, pair.owner.user_id, pair.trusted.user_id)
            .expect("owner recovery session missing");
    assert_eq!(recovery.status, LegacyRecoveryStatus::Waiting);

    pair.owner_ctx
        .legacy_reject_recovery(&recovery.id, pair.owner.user_id, pair.trusted.user_id)
        .await
        .unwrap();

    let owner_info = pair.owner_ctx.legacy_info().await.unwrap();
    let trusted_info = pair.trusted_ctx.legacy_info().await.unwrap();
    assert!(
        contacts::owner_recovery_session(&owner_info, pair.owner.user_id, pair.trusted.user_id)
            .is_none()
    );
    assert!(
        contacts::trusted_recovery_session(&trusted_info, pair.owner.user_id, pair.trusted.user_id)
            .is_none()
    );

    let owner_contact =
        contacts::owner_contact(&owner_info, pair.owner.user_id, pair.trusted.user_id)
            .expect("legacy contact should stay accepted after rejection");
    assert_eq!(owner_contact.state, LegacyContactState::Accepted);
}

async fn run_legacy_stop_stage(pair: &legacy::LegacyPair) {
    pair.trusted_ctx
        .legacy_start_recovery(pair.owner.user_id, pair.trusted.user_id)
        .await
        .unwrap();

    let trusted_info = pair.trusted_ctx.legacy_info().await.unwrap();
    let recovery =
        contacts::trusted_recovery_session(&trusted_info, pair.owner.user_id, pair.trusted.user_id)
            .expect("trusted recovery session missing");
    assert_eq!(recovery.status, LegacyRecoveryStatus::Waiting);

    pair.trusted_ctx
        .legacy_stop_recovery(&recovery.id, pair.owner.user_id, pair.trusted.user_id)
        .await
        .unwrap();

    let owner_info = pair.owner_ctx.legacy_info().await.unwrap();
    let trusted_info = pair.trusted_ctx.legacy_info().await.unwrap();
    assert!(
        contacts::owner_recovery_session(&owner_info, pair.owner.user_id, pair.trusted.user_id)
            .is_none()
    );
    assert!(
        contacts::trusted_recovery_session(&trusted_info, pair.owner.user_id, pair.trusted.user_id)
            .is_none()
    );
}

async fn run_legacy_reinvite_stage(pair: &legacy::LegacyPair) {
    pair.owner_ctx
        .legacy_update_contact(
            pair.owner.user_id,
            pair.trusted.user_id,
            LegacyContactState::Revoked,
        )
        .await
        .unwrap();

    let owner_info = pair.owner_ctx.legacy_info().await.unwrap();
    let trusted_info = pair.trusted_ctx.legacy_info().await.unwrap();
    assert!(
        contacts::owner_contact(&owner_info, pair.owner.user_id, pair.trusted.user_id).is_none()
    );
    assert!(
        contacts::trusted_contact(&trusted_info, pair.owner.user_id, pair.trusted.user_id)
            .is_none()
    );

    pair.owner_ctx
        .legacy_add_contact(
            &pair.trusted.email,
            &contacts::to_core_key_attributes(&pair.owner.key_attributes),
            Some(14),
        )
        .await
        .unwrap();
    pair.trusted_ctx
        .legacy_update_contact(
            pair.owner.user_id,
            pair.trusted.user_id,
            LegacyContactState::Accepted,
        )
        .await
        .unwrap();

    let owner_info = pair.owner_ctx.legacy_info().await.unwrap();
    let trusted_info = pair.trusted_ctx.legacy_info().await.unwrap();
    let owner_contact =
        contacts::owner_contact(&owner_info, pair.owner.user_id, pair.trusted.user_id)
            .expect("reinvited contact missing from owner view");
    let trusted_contact =
        contacts::trusted_contact(&trusted_info, pair.owner.user_id, pair.trusted.user_id)
            .expect("reinvited contact missing from trusted view");
    assert_eq!(owner_contact.state, LegacyContactState::Accepted);
    assert_eq!(trusted_contact.state, LegacyContactState::Accepted);
}

async fn run_legacy_reset_stage(endpoint: &str, pair: &mut legacy::LegacyPair) {
    assert!(
        auth::fetch_two_factor_status(endpoint, &pair.owner)
            .await
            .expect("two-factor status before recovery fetch failed")
    );

    pair.trusted_ctx
        .legacy_start_recovery(pair.owner.user_id, pair.trusted.user_id)
        .await
        .unwrap();

    let owner_info = pair.owner_ctx.legacy_info().await.unwrap();
    let recovery =
        contacts::owner_recovery_session(&owner_info, pair.owner.user_id, pair.trusted.user_id)
            .expect("owner recovery session missing");
    assert_eq!(recovery.status, LegacyRecoveryStatus::Waiting);

    pair.owner_ctx
        .legacy_approve_recovery(&recovery.id, pair.owner.user_id, pair.trusted.user_id)
        .await
        .unwrap();

    let owner_info = pair.owner_ctx.legacy_info().await.unwrap();
    let recovery =
        contacts::owner_recovery_session(&owner_info, pair.owner.user_id, pair.trusted.user_id)
            .expect("approved recovery session missing");
    assert_eq!(recovery.status, LegacyRecoveryStatus::Ready);

    let previous_password = pair.owner.password.clone();
    let new_password = support::unique_password("LegacyRecovered");
    pair.trusted_ctx
        .legacy_change_password(
            &recovery.id,
            &contacts::to_core_key_attributes(&pair.trusted.key_attributes),
            &new_password,
        )
        .await
        .unwrap();

    match auth::login_without_totp(endpoint, &pair.owner.email, &previous_password).await {
        Err(CliError::AuthenticationFailed(message)) => {
            assert_eq!(message, "Incorrect password");
        }
        Err(error) if error.is_http_status(&[401]) => {}
        other => panic!("expected old password login to fail, got {other:?}"),
    }

    let recovered_login = auth::login_without_totp(endpoint, &pair.owner.email, &new_password)
        .await
        .expect("new password login should succeed after recovery");
    assert_eq!(recovered_login.user_id, pair.owner.user_id);
    assert_eq!(recovered_login.secrets.master_key, pair.owner.master_key);

    let recovered_owner = auth::test_account_from_authenticated(
        pair.owner.email.clone(),
        new_password,
        recovered_login,
    );
    assert!(
        !auth::fetch_two_factor_status(endpoint, &recovered_owner)
            .await
            .expect("two-factor status after recovery fetch failed")
    );

    let recovered_owner_ctx = contacts::open_ctx(endpoint, &recovered_owner).await;
    let owner_info = recovered_owner_ctx.legacy_info().await.unwrap();
    let trusted_info = pair.trusted_ctx.legacy_info().await.unwrap();
    assert!(
        contacts::owner_recovery_session(&owner_info, pair.owner.user_id, pair.trusted.user_id)
            .is_none()
    );
    assert!(
        contacts::trusted_recovery_session(&trusted_info, pair.owner.user_id, pair.trusted.user_id)
            .is_none()
    );

    let owner_contact =
        contacts::owner_contact(&owner_info, pair.owner.user_id, pair.trusted.user_id)
            .expect("legacy contact should remain configured after recovery");
    assert_eq!(owner_contact.state, LegacyContactState::Accepted);

    pair.owner = recovered_owner;
    pair.owner_ctx = recovered_owner_ctx;
}

async fn run_legacy_kit_stage(endpoint: &str, owner: &mut legacy_kit::LegacyKitOwner) {
    let recovery_client = LegacyKitRecoveryClient::new(endpoint).expect("legacy kit client");
    let public_client = reqwest::Client::new();
    let missing_notice_period = public_client
        .post(format!("{endpoint}/legacy-kits"))
        .header("X-Auth-Token", owner.owner.auth_token.clone())
        .header("X-Client-Package", App::Photos.client_package())
        .json(&json!({
            "id": Uuid::new_v4().to_string(),
            "variant": 1,
            "encryptedRecoveryBlob": "AA==",
            "authPublicKey": "not-a-valid-public-key",
            "encryptedOwnerBlob": "AA=="
        }))
        .send()
        .await
        .expect("legacy kit missing notice period request failed");
    assert_eq!(
        missing_notice_period.status(),
        reqwest::StatusCode::BAD_REQUEST
    );

    let invalid_create = public_client
        .post(format!("{endpoint}/legacy-kits"))
        .header("X-Auth-Token", owner.owner.auth_token.clone())
        .header("X-Client-Package", App::Photos.client_package())
        .json(&CreateLegacyKitRequest {
            id: Uuid::new_v4().to_string(),
            variant: 1,
            notice_period_in_hours: 24,
            encrypted_recovery_blob: "AA==".into(),
            auth_public_key: "not-a-valid-public-key".into(),
            encrypted_owner_blob: "AA==".into(),
        })
        .send()
        .await
        .expect("legacy kit invalid create request failed");
    assert_eq!(invalid_create.status(), reqwest::StatusCode::BAD_REQUEST);

    let waiting_kit = owner
        .owner_ctx
        .legacy_kit_create(
            &contacts::to_core_key_attributes(&owner.owner.key_attributes),
            ["North".into(), "East".into(), "West".into()],
            24,
        )
        .await
        .expect("waiting legacy kit create failed");
    assert_eq!(waiting_kit.kit.notice_period_in_hours, 24);
    assert_eq!(waiting_kit.kit.metadata.parts.len(), 3);
    assert_eq!(waiting_kit.shares.len(), 3);

    let listed = owner
        .owner_ctx
        .legacy_kits()
        .await
        .expect("legacy kit list failed");
    let listed_waiting_kit = listed
        .iter()
        .find(|kit| kit.id == waiting_kit.kit.id)
        .expect("created waiting legacy kit missing from list");
    assert_eq!(listed_waiting_kit.metadata.parts.len(), 3);
    assert_eq!(listed_waiting_kit.metadata.parts[0].name, "North");

    let downloaded_shares = owner
        .owner_ctx
        .legacy_kit_download_shares(&waiting_kit.kit.id)
        .await
        .expect("legacy kit share download failed");
    assert_eq!(downloaded_shares.len(), 3);
    assert_eq!(downloaded_shares[0].kit_id, waiting_kit.kit.id);
    assert_eq!(
        downloaded_shares[1].checksum,
        waiting_kit.shares[1].checksum
    );

    let invalid_challenge = public_client
        .post(format!("{endpoint}/legacy-kits/recovery/challenge"))
        .json(&LegacyKitChallengeRequest {
            kit_id: waiting_kit.kit.id.clone(),
        })
        .send()
        .await
        .expect("legacy kit challenge request failed");
    assert!(
        invalid_challenge.status().is_success(),
        "challenge request should succeed, got {}",
        invalid_challenge.status()
    );
    let invalid_challenge: LegacyKitChallengeResponse = invalid_challenge
        .json()
        .await
        .expect("legacy kit challenge response decode failed");
    let invalid_open = public_client
        .post(format!("{endpoint}/legacy-kits/recovery/open"))
        .json(&LegacyKitOpenRecoveryRequest {
            kit_id: waiting_kit.kit.id.clone(),
            challenge: invalid_challenge.encrypted_challenge,
            used_part_indexes: None,
            email: Some("bad-beneficiary@example.org".into()),
        })
        .send()
        .await
        .expect("legacy kit invalid recovery open request failed");
    assert_eq!(invalid_open.status(), reqwest::StatusCode::BAD_REQUEST);

    let listed_after_invalid_open = owner
        .owner_ctx
        .legacy_kits()
        .await
        .expect("legacy kit list after invalid challenge failed");
    let listed_waiting_after_invalid_open = listed_after_invalid_open
        .iter()
        .find(|kit| kit.id == waiting_kit.kit.id)
        .expect("waiting legacy kit missing after invalid challenge");
    assert!(
        listed_waiting_after_invalid_open
            .active_recovery_session
            .is_none(),
        "invalid challenge must not create a recovery session"
    );

    let first_waiting_challenge = public_client
        .post(format!("{endpoint}/legacy-kits/recovery/challenge"))
        .json(&LegacyKitChallengeRequest {
            kit_id: waiting_kit.kit.id.clone(),
        })
        .send()
        .await
        .expect("first waiting legacy kit challenge request failed");
    assert!(
        first_waiting_challenge.status().is_success(),
        "first waiting challenge request should succeed, got {}",
        first_waiting_challenge.status()
    );
    let first_waiting_challenge: LegacyKitChallengeResponse = first_waiting_challenge
        .json()
        .await
        .expect("first waiting challenge response decode failed");

    let second_waiting_challenge = public_client
        .post(format!("{endpoint}/legacy-kits/recovery/challenge"))
        .json(&LegacyKitChallengeRequest {
            kit_id: waiting_kit.kit.id.clone(),
        })
        .send()
        .await
        .expect("second waiting legacy kit challenge request failed");
    assert!(
        second_waiting_challenge.status().is_success(),
        "second waiting challenge request should succeed, got {}",
        second_waiting_challenge.status()
    );
    let second_waiting_challenge: LegacyKitChallengeResponse = second_waiting_challenge
        .json()
        .await
        .expect("second waiting challenge response decode failed");

    let waiting_handle = recovery_client
        .open_from_encrypted_challenge(
            &downloaded_shares[0..2],
            &first_waiting_challenge.encrypted_challenge,
            Some("beneficiary@example.org"),
        )
        .await
        .expect("legacy kit waiting recovery open failed");
    assert_eq!(
        waiting_handle.session().status,
        LegacyKitRecoveryStatus::Waiting
    );
    assert!(
        waiting_handle.session().wait_till > 0,
        "legacy kit waitTill should be remaining wait duration"
    );
    assert!(
        waiting_handle.session().wait_till <= 24 * 60 * 60 * 1_000_000,
        "legacy kit waitTill should not be an epoch timestamp"
    );

    let resumed_waiting_handle = recovery_client
        .open_from_encrypted_challenge(
            &downloaded_shares[1..3],
            &second_waiting_challenge.encrypted_challenge,
            None,
        )
        .await
        .expect("legacy kit resumed recovery open failed");
    assert_eq!(
        resumed_waiting_handle.session().id,
        waiting_handle.session().id
    );
    assert_eq!(
        resumed_waiting_handle.session().status,
        LegacyKitRecoveryStatus::Waiting
    );
    let original_waiting_session = waiting_handle
        .refresh_session()
        .await
        .expect("original legacy kit session fetch after resume failed");
    assert_eq!(
        original_waiting_session.status,
        LegacyKitRecoveryStatus::Waiting
    );
    let resumed_session = resumed_waiting_handle
        .refresh_session()
        .await
        .expect("resumed legacy kit session fetch failed");
    assert_eq!(resumed_session.status, LegacyKitRecoveryStatus::Waiting);
    let owner_recovery_session = owner
        .owner_ctx
        .legacy_kit_recovery_session(&waiting_kit.kit.id)
        .await
        .expect("owner legacy kit recovery session fetch failed");
    let owner_active_session = owner_recovery_session
        .session
        .as_ref()
        .expect("owner recovery session should be present while waiting");
    assert_eq!(owner_active_session.id, waiting_handle.session().id);
    assert_eq!(owner_recovery_session.initiators.len(), 2);
    assert_eq!(
        owner_recovery_session.initiators[0].used_part_indexes,
        vec![1, 2]
    );
    assert_eq!(
        owner_recovery_session.initiators[1].used_part_indexes,
        vec![2, 3]
    );
    assert!(
        owner_recovery_session
            .initiators
            .iter()
            .all(|initiator| !initiator.ip.is_empty())
    );
    assert!(
        owner_recovery_session
            .initiators
            .iter()
            .all(|initiator| !initiator.user_agent.is_empty())
    );

    owner
        .owner_ctx
        .legacy_kit_block_recovery(&waiting_kit.kit.id)
        .await
        .expect("legacy kit block failed");
    let blocked_session = resumed_waiting_handle
        .refresh_session()
        .await
        .expect("legacy kit blocked session fetch failed");
    assert_eq!(blocked_session.status, LegacyKitRecoveryStatus::Blocked);
    let blocked_original_session = waiting_handle
        .refresh_session()
        .await
        .expect("legacy kit blocked session fetch for original browser failed");
    assert_eq!(
        blocked_original_session.status,
        LegacyKitRecoveryStatus::Blocked
    );
    let blocked_owner_recovery_session = owner
        .owner_ctx
        .legacy_kit_recovery_session(&waiting_kit.kit.id)
        .await
        .expect("owner legacy kit recovery session fetch after block failed");
    assert!(blocked_owner_recovery_session.session.is_none());
    assert!(blocked_owner_recovery_session.initiators.is_empty());

    owner
        .owner_ctx
        .legacy_kit_delete(&waiting_kit.kit.id)
        .await
        .expect("legacy kit delete failed");
    let listed_after_delete = owner
        .owner_ctx
        .legacy_kits()
        .await
        .expect("legacy kit list after delete failed");
    assert!(
        listed_after_delete
            .iter()
            .all(|kit| kit.id != waiting_kit.kit.id)
    );

    let immediate_kit = owner
        .owner_ctx
        .legacy_kit_create(
            &contacts::to_core_key_attributes(&owner.owner.key_attributes),
            ["Alpha".into(), "Bravo".into(), "Charlie".into()],
            0,
        )
        .await
        .expect("immediate legacy kit create failed");
    let ready_handle = recovery_client
        .open_from_shares(&immediate_kit.shares[0..2], Some("beneficiary@example.org"))
        .await
        .expect("immediate legacy kit recovery open failed");
    assert_eq!(
        ready_handle.session().status,
        LegacyKitRecoveryStatus::Ready
    );

    let bundle = ready_handle
        .recovery_bundle()
        .await
        .expect("legacy kit recovery bundle fetch failed");
    assert!(
        !bundle.recovery_key.is_empty(),
        "legacy kit recovery key should be returned once ready"
    );

    let previous_password = owner.owner.password.clone();
    let recovery_password = support::unique_password("LegacyKitRecovered");
    ready_handle
        .change_password(&recovery_password)
        .await
        .expect("legacy kit password reset failed");

    match auth::login_without_totp(endpoint, &owner.owner.email, &previous_password).await {
        Err(CliError::AuthenticationFailed(message)) => {
            assert_eq!(message, "Incorrect password");
        }
        Err(error) if error.is_http_status(&[401]) => {}
        other => panic!("expected old legacy kit password login to fail, got {other:?}"),
    }

    let recovered_login =
        auth::login_without_totp(endpoint, &owner.owner.email, &recovery_password)
            .await
            .expect("new password login should succeed after legacy kit recovery");
    assert_eq!(recovered_login.user_id, owner.owner.user_id);
    assert_eq!(recovered_login.secrets.master_key, owner.owner.master_key);

    let recovered_owner = auth::test_account_from_authenticated(
        owner.owner.email.clone(),
        recovery_password,
        recovered_login,
    );
    assert!(
        !auth::fetch_two_factor_status(endpoint, &recovered_owner)
            .await
            .expect("two-factor status after legacy kit recovery fetch failed")
    );

    owner.owner = recovered_owner;
}
