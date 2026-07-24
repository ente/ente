use ente_contacts::client::ContactsCtx;

use crate::support::{
    auth::{self, TestAccount},
    contacts,
};

pub struct LegacyKitOwner {
    pub owner: TestAccount,
    pub owner_ctx: ContactsCtx,
}

pub async fn create_owner(endpoint: &str) -> LegacyKitOwner {
    let owner = auth::create_fixture_account(endpoint, "legacy-kit-owner").await;
    let owner_ctx = contacts::open_ctx(endpoint, &owner).await;
    LegacyKitOwner { owner, owner_ctx }
}
