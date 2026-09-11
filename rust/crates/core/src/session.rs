use crate::{
    crypto::{Key, SecretKey},
    http::{Api, ApiConfig, Error, Http},
};

pub struct Session {
    pub api: Api,
    pub user_id: i64,
    pub master_key: Key,
    pub recovery_key: Key,
    pub secret_key: SecretKey,
}

impl Session {
    pub fn new(
        config: ApiConfig,
        user_id: i64,
        master_key: Key,
        recovery_key: Key,
        secret_key: SecretKey,
    ) -> Result<Self, Error> {
        Ok(Self {
            api: Api::new(Http::new()?, config),
            user_id,
            master_key,
            recovery_key,
            secret_key,
        })
    }
}
