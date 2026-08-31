use std::sync::Arc;

use ente_core::{
    Session as InnerSession,
    crypto::SecretVec,
    http::{ApiConfig, Auth},
};
use flutter_rust_bridge::frb;

#[frb(non_opaque)]
pub enum SessionError {
    Other { message: String },
}

impl From<ente_core::http::Error> for SessionError {
    fn from(error: ente_core::http::Error) -> Self {
        Self::Other {
            message: ente_core::error::chain(&error),
        }
    }
}

#[frb(opaque)]
#[derive(Clone)]
pub struct Session(Arc<InnerSession>);

#[frb(sync)]
pub fn open_session(
    base_url: String,
    auth_token: String,
    master_key: Vec<u8>,
    user_agent: Option<String>,
    client_package: Option<String>,
    client_version: Option<String>,
) -> Result<Session, SessionError> {
    Ok(Session(Arc::new(InnerSession::new(
        ApiConfig {
            origin: base_url,
            client_package,
            client_version,
            user_agent,
            auth: Some(Auth::User(auth_token)),
        },
        SecretVec::new(master_key),
    )?)))
}

impl Session {
    #[frb(sync)]
    pub fn update_auth_token(&self, auth_token: String) {
        self.0.api.set_auth(Some(Auth::User(auth_token)));
    }
}

impl AsRef<InnerSession> for Session {
    fn as_ref(&self) -> &InnerSession {
        &self.0
    }
}
