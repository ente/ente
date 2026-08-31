use ente_core::Session;

use crate::support::{
    auth::{self, TestAccount},
    legacy,
};

pub struct LegacyKitOwner {
    pub owner: TestAccount,
    pub owner_session: Session,
}

pub async fn create_owner(endpoint: &str) -> LegacyKitOwner {
    let owner = auth::create_fixture_account(endpoint, "legacy-kit-owner").await;
    let owner_session = legacy::open_session(endpoint, &owner);
    LegacyKitOwner {
        owner,
        owner_session,
    }
}
