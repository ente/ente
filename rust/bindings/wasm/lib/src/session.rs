use std::sync::Arc;

use ente_core::{
    Session as InnerSession, b64,
    crypto::{self, Key, Nonce, PublicKey, SecretKey},
    http::{ApiConfig, Auth},
};
use serde::Deserialize;
use tsify::{Ts, Tsify};
use wasm_bindgen::prelude::*;

use crate::EncryptedBox;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Accounts(#[from] ente_accounts::Error),
    #[error(transparent)]
    Input(#[from] tsify::Error),
    #[error(transparent)]
    Http(#[from] ente_core::http::Error),
    #[error(transparent)]
    Decode(#[from] b64::DecodeError),
    #[error(transparent)]
    Crypto(#[from] crypto::Error),
    #[error("Missing recovery key")]
    MissingRecoveryKey,
}

impl Error {
    fn name(&self) -> Option<&'static str> {
        match self {
            Self::MissingRecoveryKey => Some("missing_recovery_key"),
            _ => None,
        }
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

#[derive(Deserialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct SessionKeyAttributes {
    public_key: String,
    encrypted_secret_key: String,
    secret_key_decryption_nonce: String,
    #[tsify(optional)]
    recovery_key_encrypted_with_master_key: Option<String>,
    #[tsify(optional)]
    recovery_key_decryption_nonce: Option<String>,
}

#[derive(Deserialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct OpenSessionInput {
    base_url: String,
    auth_token: String,
    #[serde(rename = "userID")]
    user_id: i64,
    master_key_b64: String,
    key_attributes: SessionKeyAttributes,
    #[tsify(optional)]
    client_package: Option<String>,
    #[tsify(optional)]
    client_version: Option<String>,
}

#[wasm_bindgen(js_name = openSession)]
pub fn open_session(input: Ts<OpenSessionInput>) -> Result<Session, Error> {
    let OpenSessionInput {
        base_url,
        auth_token,
        user_id,
        master_key_b64,
        key_attributes,
        client_package,
        client_version,
    } = input.to_rust()?;
    let master_key = Key::try_from_slice(&b64::decode(&master_key_b64)?)?;
    let encrypted_recovery_key = key_attributes
        .recovery_key_encrypted_with_master_key
        .filter(|value| !value.is_empty())
        .ok_or(Error::MissingRecoveryKey)?;
    let recovery_key_nonce = key_attributes
        .recovery_key_decryption_nonce
        .filter(|value| !value.is_empty())
        .ok_or(Error::MissingRecoveryKey)?;
    let recovery_key = crypto::secretbox::decrypt(
        &b64::decode(&encrypted_recovery_key)?,
        &Nonce::try_from_slice(&b64::decode(&recovery_key_nonce)?)?,
        &master_key,
    )?;
    let recovery_key = Key::try_from_slice(&recovery_key)?;
    let secret_key = SecretKey::open(
        &crypto::secretbox::EncryptedBox {
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
            user_agent: None,
            auth: Some(Auth::User(auth_token)),
        },
        user_id,
        master_key,
        recovery_key,
        secret_key,
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
    #[wasm_bindgen(js_name = encryptWithRecoveryKey)]
    pub fn encrypt_with_recovery_key(&self, data_b64: &str) -> Result<EncryptedBox, Error> {
        Ok(crypto::secretbox::encrypt(&b64::decode(data_b64)?, &self.0.recovery_key).into())
    }

    #[wasm_bindgen(js_name = recoveryKeyMnemonic)]
    pub fn recovery_key_mnemonic(&self) -> Result<String, Error> {
        ente_accounts::auth::recovery_key_to_mnemonic(self.0.recovery_key.as_bytes())
            .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = updateAuthToken)]
    pub fn update_auth_token(&self, auth_token: String) {
        self.0.api.set_auth(Some(Auth::User(auth_token)));
    }
}
