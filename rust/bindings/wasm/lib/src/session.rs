use std::sync::Arc;

use ente_core::{
    Session as InnerSession, b64,
    crypto::SecretVec,
    http::{ApiConfig, Auth},
};
use wasm_bindgen::prelude::*;

#[wasm_bindgen(js_name = openSession)]
pub fn open_session(
    base_url: String,
    auth_token: String,
    master_key_b64: String,
    client_package: Option<String>,
    client_version: Option<String>,
) -> Result<Session, Error> {
    Ok(Session(Arc::new(InnerSession::new(
        ApiConfig {
            origin: base_url,
            client_package,
            client_version,
            user_agent: None,
            auth: Some(Auth::User(auth_token)),
        },
        SecretVec::new(b64::decode(&master_key_b64)?),
    )?)))
}

#[wasm_bindgen]
pub struct Session(Arc<InnerSession>);

impl Session {
    pub fn inner(&self) -> &InnerSession {
        &self.0
    }
}

#[wasm_bindgen]
impl Session {
    #[wasm_bindgen(js_name = updateAuthToken)]
    pub fn update_auth_token(&self, auth_token: String) {
        self.0.api.set_auth(Some(Auth::User(auth_token)));
    }
}

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Http(#[from] ente_core::http::Error),
    #[error(transparent)]
    Decode(#[from] b64::DecodeError),
}

impl Error {
    fn name(&self) -> Option<&'static str> {
        None
    }

    fn message(&self) -> String {
        ente_core::error::chain(self)
    }
}

impl From<Error> for JsValue {
    fn from(error: Error) -> Self {
        let js_error = js_sys::Error::new(&error.message());
        if let Some(name) = error.name() {
            js_error.set_name(name);
        }
        js_error.into()
    }
}
