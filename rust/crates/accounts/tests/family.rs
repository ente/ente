#![cfg(test)]
#![cfg(feature = "museum")]

use ente_accounts::{
    AccountsClient, AccountsClientConfig, Error,
    family::{self, Family, Member, MemberStatus},
};
use ente_core::{
    Session,
    crypto::{Key, SecretKey},
    http::{ApiConfig, Auth},
};
use ente_test_support::{
    HARDCODED_OTT_EMAIL_SUFFIX, Museum, TestResult,
    account_fixture::{TestAccount, create_account},
};
use serde_json::json;
use uuid::Uuid;

const GB: i64 = 1 << 30;
const FAR_FUTURE: i64 = 4_942_020_944_746_699;
// Test Museum has no pricing data; this is the paid product it resolves without one.
const PAID_PLAN: &str = "family";

#[test]
fn family_plan() -> TestResult {
    Museum::run(|museum| tokio::runtime::Runtime::new()?.block_on(run(museum)))
}

async fn run(museum: &Museum) -> TestResult {
    let endpoint = museum.endpoint();
    let operator = create_account(endpoint, "family-operator").await?;
    let admin_account = create_account(endpoint, "family-admin").await?;
    let member_account = create_account(endpoint, "family-member").await?;
    let mut invitees = Vec::new();
    for _ in 0..4 {
        invitees.push(create_account(endpoint, "family-invitee").await?);
    }
    let operator = accounts_client(endpoint, &operator);
    let admin = session(endpoint, &admin_account)?;
    let member = session(endpoint, &member_account)?;

    assert!(family::get(&admin).await?.is_none());
    assert!(matches!(
        family::invite(&member, &admin_account.email).await,
        Err(Error::NotFamilyAdmin)
    ));
    set_plan(&operator, &admin_account, "free", 1).await?;
    assert!(matches!(
        family::create(&admin).await,
        Err(Error::PaidPlanRequired)
    ));
    set_plan(&operator, &admin_account, PAID_PLAN, FAR_FUTURE).await?;
    family::create(&admin).await?;
    family::create(&admin).await?;
    let created = get(&admin).await?;
    assert_eq!(created.members.len(), 1);
    assert_eq!(created.members[0].email, admin_account.email);
    assert_eq!(created.members[0].status, MemberStatus::Admin);
    assert!(created.members[0].is_admin);
    assert_eq!(created.storage, 200 * GB);
    assert_eq!(created.expiry_time, FAR_FUTURE);
    assert!(matches!(
        family::leave(&admin).await,
        Err(Error::FamilyAdminCannotLeave)
    ));

    // Museum allows ten invites a minute per admin; this test sends nine.
    let unregistered = format!(
        "family-nobody-{}{HARDCODED_OTT_EMAIL_SUFFIX}",
        Uuid::new_v4()
    );
    assert!(matches!(
        family::invite(&admin, &unregistered).await,
        Err(Error::NotRegistered)
    ));
    set_plan(&operator, &invitees[0], PAID_PLAN, FAR_FUTURE).await?;
    assert!(matches!(
        family::invite(&admin, &invitees[0].email).await,
        Err(Error::InviteeHasPaidPlan)
    ));
    set_plan(&operator, &invitees[0], "free", FAR_FUTURE).await?;

    family::invite(&admin, &member_account.email).await?;
    let invited = get(&admin).await?;
    assert_eq!(invited.members.len(), 2);
    let id = find(&invited, &member_account.email).id;
    assert_eq!(
        find(&invited, &member_account.email).status,
        MemberStatus::Invited
    );
    assert!(family::get(&member).await?.is_none());

    accept(museum, &member, id).await?;
    let joined = get(&member).await?;
    let joined_member = find(&joined, &member_account.email);
    assert_eq!(joined_member.id, id);
    assert_eq!(joined_member.status, MemberStatus::Accepted);
    assert_eq!(joined_member.storage_limit, None);
    assert!(matches!(
        family::create(&member).await,
        Err(Error::InAnotherFamily)
    ));
    assert!(matches!(
        family::invite(&admin, &member_account.email).await,
        Err(Error::InviteeInFamily)
    ));
    assert!(matches!(
        family::revoke_invite(&admin, id).await,
        Err(Error::Http(error)) if error.status_code() == Some(400)
    ));

    family::set_storage_limit(&admin, id, Some(5 * GB)).await?;
    assert_eq!(
        find(&get(&member).await?, &member_account.email).storage_limit,
        Some(5 * GB)
    );
    assert!(matches!(
        family::set_storage_limit(&admin, id, Some(joined.total_storage() + 1)).await,
        Err(Error::StorageLimitAboveFamilyStorage)
    ));
    museum.execute_sql(&format!(
        "INSERT INTO usage (user_id, storage_consumed) VALUES ({}, {})
         ON CONFLICT (user_id) DO UPDATE SET storage_consumed = EXCLUDED.storage_consumed",
        member_account.user_id,
        2 * GB
    ))?;
    assert!(matches!(
        family::set_storage_limit(&admin, id, Some(GB)).await,
        Err(Error::StorageLimitBelowUsage)
    ));
    assert!(matches!(
        family::set_storage_limit(&member, id, None).await,
        Err(Error::NotFamilyAdmin)
    ));
    family::set_storage_limit(&admin, id, None).await?;
    let unlimited = get(&admin).await?;
    assert_eq!(find(&unlimited, &member_account.email).storage_limit, None);
    assert_eq!(find(&unlimited, &member_account.email).usage, 2 * GB);
    assert_eq!(unlimited.usage(), 2 * GB);
    assert!(matches!(
        family::set_storage_limit(&admin, Uuid::new_v4(), None).await,
        Err(Error::FamilyMemberNotFound)
    ));

    for invitee in &invitees {
        family::invite(&admin, &invitee.email).await?;
    }
    let full = get(&admin).await?;
    assert_eq!(full.members.len(), 6);
    assert!(matches!(
        family::invite(&admin, &unregistered).await,
        Err(Error::FamilyFull)
    ));
    let removed = find(&full, &invitees[1].email).id;
    let removed_member = session(endpoint, &invitees[1])?;
    accept(museum, &removed_member, removed).await?;
    for invitee in [&invitees[0], &invitees[2], &invitees[3]] {
        family::revoke_invite(&admin, find(&full, &invitee.email).id).await?;
    }
    assert!(matches!(
        family::revoke_invite(&member, removed).await,
        Err(Error::NotFamilyAdmin)
    ));
    assert!(matches!(
        family::remove_member(&member, removed).await,
        Err(Error::NotFamilyAdmin)
    ));
    family::remove_member(&admin, removed).await?;
    assert!(family::get(&removed_member).await?.is_none());
    assert!(matches!(
        family::remove_member(&admin, Uuid::new_v4()).await,
        Err(Error::FamilyMemberNotFound)
    ));
    let remaining = get(&admin).await?;
    assert_eq!(remaining.members.len(), 2);
    assert!(remaining.members.iter().any(|member| member.id == id));

    family::leave(&member).await?;
    assert!(family::get(&member).await?.is_none());
    assert_eq!(get(&admin).await?.members.len(), 1);
    family::leave(&member).await?;
    Ok(())
}

fn find<'a>(family: &'a Family, email: &str) -> &'a Member {
    family
        .members
        .iter()
        .find(|member| member.email == email)
        .unwrap()
}

async fn get(session: &Session) -> TestResult<Family> {
    Ok(family::get(session).await?.ok_or("expected a family")?)
}

// Museum only emails the invite token, so plant a known one and accept it as the invite link would.
async fn accept(museum: &Museum, session: &Session, id: Uuid) -> TestResult {
    let token = Uuid::new_v4().simple().to_string();
    museum.execute_sql(&format!(
        "UPDATE families SET token = '{token}' WHERE id = '{id}'"
    ))?;
    session
        .api
        .post("/family/accept-invite")
        .json(&json!({"token": token}))
        .send()
        .await?
        .error_for_code()
        .await?;
    Ok(())
}

async fn set_plan(
    operator: &AccountsClient,
    account: &TestAccount,
    product_id: &str,
    expiry_time: i64,
) -> TestResult {
    let mut subscription = operator
        .admin_user(&account.user_id.to_string())
        .await?
        .subscription
        .ok_or("expected a subscription")?;
    subscription.product_id = product_id.into();
    subscription.storage = 200 * GB;
    subscription.expiry_time = expiry_time;
    operator
        .admin_update_subscription(account.user_id, &subscription)
        .await?;
    Ok(())
}

fn accounts_client(endpoint: &str, account: &TestAccount) -> AccountsClient {
    AccountsClient::new(
        AccountsClientConfig::new("io.ente.photos")
            .with_origin(endpoint)
            .with_user_agent("ente-accounts-e2e"),
    )
    .unwrap()
    .with_auth_token(account.auth_token.clone())
}

fn session(endpoint: &str, account: &TestAccount) -> TestResult<Session> {
    Ok(Session::new(
        ApiConfig {
            auth: Some(Auth::User(account.auth_token.clone())),
            client_package: Some("io.ente.photos".into()),
            ..ApiConfig::new(endpoint.into())
        },
        account.user_id,
        Key::try_from_slice(&account.master_key)?,
        Key::try_from_slice(&account.recovery_key)?,
        SecretKey::try_from_slice(&account.secret_key)?,
    )?)
}
