use std::sync::Arc;

use ente_core::{
    Session as InnerSession, b64,
    crypto::{Key, Nonce, PublicKey, SecretKey, secretbox, secretbox::EncryptedBox},
    http::{ApiConfig, Auth},
};
use flutter_rust_bridge::frb;

#[frb(non_opaque)]
pub enum SessionError {
    Other { message: String },
}

impl<E: std::error::Error> From<E> for SessionError {
    fn from(error: E) -> Self {
        Self::Other {
            message: ente_core::error::chain(&error),
        }
    }
}

#[frb(opaque)]
#[derive(Clone)]
pub struct Session(Arc<InnerSession>);

#[frb(non_opaque)]
pub struct SessionKeyAttributes {
    pub public_key: String,
    pub encrypted_secret_key: String,
    pub secret_key_decryption_nonce: String,
    pub recovery_key_encrypted_with_master_key: String,
    pub recovery_key_decryption_nonce: String,
}

#[frb(non_opaque)]
pub struct OpenSessionInput {
    pub base_url: String,
    pub auth_token: String,
    pub user_id: i64,
    pub master_key: Vec<u8>,
    pub key_attributes: SessionKeyAttributes,
    pub user_agent: Option<String>,
    pub client_package: Option<String>,
    pub client_version: Option<String>,
}

#[frb(sync)]
pub fn open_session(input: OpenSessionInput) -> Result<Session, SessionError> {
    let OpenSessionInput {
        base_url,
        auth_token,
        user_id,
        master_key,
        key_attributes,
        user_agent,
        client_package,
        client_version,
    } = input;
    let master_key = Key::try_from_slice(&master_key)?;
    let recovery_key = secretbox::decrypt(
        &b64::decode(&key_attributes.recovery_key_encrypted_with_master_key)?,
        &Nonce::try_from_slice(&b64::decode(&key_attributes.recovery_key_decryption_nonce)?)?,
        &master_key,
    )?;
    let recovery_key = Key::try_from_slice(&recovery_key)?;
    let secret_key = SecretKey::open(
        &EncryptedBox {
            encrypted_data: b64::decode(&key_attributes.encrypted_secret_key)?,
            nonce: Nonce::try_from_slice(&b64::decode(
                &key_attributes.secret_key_decryption_nonce,
            )?)?,
        },
        &master_key,
        &PublicKey::try_from_slice(&b64::decode(&key_attributes.public_key)?)?,
    )?;
    Ok(Session(Arc::new(InnerSession::new(
        ApiConfig {
            origin: base_url,
            client_package,
            client_version,
            user_agent,
            auth: Some(Auth::User(auth_token)),
        },
        user_id,
        master_key,
        recovery_key,
        secret_key,
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
