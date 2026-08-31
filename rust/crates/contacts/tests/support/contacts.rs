use std::sync::RwLock;

use ente_contacts::{ContactData, ContactOutput, ContactRecord, WrappedRootContactKey};
use ente_core::{
    Session,
    crypto::SecretVec,
    http::{Api, ApiConfig, Auth, Http},
};

use crate::CLIENT_PACKAGE;
use crate::support::auth::TestAccount;

pub struct Client {
    session: Session,
    wrapped_root_contact_key: RwLock<Option<WrappedRootContactKey>>,
}

impl Client {
    pub async fn create_contact(&self, data: &ContactData) -> ente_contacts::Result<ContactRecord> {
        let cached = self.wrapped_root_contact_key();
        Ok(self.value(ente_contacts::create_contact(&self.session, cached.as_ref(), data).await?))
    }

    pub async fn get_contact(&self, contact_id: &str) -> ente_contacts::Result<ContactRecord> {
        let cached = self.wrapped_root_contact_key();
        Ok(self
            .value(ente_contacts::get_contact(&self.session, cached.as_ref(), contact_id).await?))
    }

    pub async fn update_contact(
        &self,
        contact_id: &str,
        data: &ContactData,
    ) -> ente_contacts::Result<ContactRecord> {
        let cached = self.wrapped_root_contact_key();
        Ok(self.value(
            ente_contacts::update_contact(&self.session, cached.as_ref(), contact_id, data).await?,
        ))
    }

    pub async fn delete_contact(&self, contact_id: &str) -> ente_contacts::Result<()> {
        ente_contacts::delete_contact(&self.session, contact_id).await
    }

    pub async fn get_diff(
        &self,
        since_time: i64,
        limit: u16,
    ) -> ente_contacts::Result<Vec<ContactRecord>> {
        let cached = self.wrapped_root_contact_key();
        Ok(self.value(
            ente_contacts::get_diff(&self.session, cached.as_ref(), since_time, limit).await?,
        ))
    }

    fn wrapped_root_contact_key(&self) -> Option<WrappedRootContactKey> {
        self.wrapped_root_contact_key.read().unwrap().clone()
    }

    fn value<T>(&self, output: ContactOutput<T>) -> T {
        if let Some(key) = output.wrapped_root_contact_key {
            *self.wrapped_root_contact_key.write().unwrap() = Some(key);
        }
        output.value
    }
}

pub fn open_client(endpoint: &str, account: &TestAccount) -> Client {
    let api = Api::new(
        Http::new().unwrap(),
        ApiConfig {
            origin: endpoint.to_string(),
            client_package: Some(CLIENT_PACKAGE.to_string()),
            client_version: Some("0.0.1".to_string()),
            user_agent: Some("ente-contacts-e2e".to_string()),
            auth: Some(Auth::User(account.auth_token.clone())),
        },
    );
    Client {
        session: Session {
            api,
            master_key: SecretVec::new(account.master_key.clone()),
        },
        wrapped_root_contact_key: RwLock::new(None),
    }
}
