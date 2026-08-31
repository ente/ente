use crate::{
    crypto::SecretVec,
    http::{Api, ApiConfig, Error, Http},
};

pub struct Session {
    pub api: Api,
    pub master_key: SecretVec,
}

impl Session {
    pub fn new(config: ApiConfig, master_key: SecretVec) -> Result<Self, Error> {
        Ok(Self {
            api: Api::new(Http::new()?, config),
            master_key,
        })
    }
}
