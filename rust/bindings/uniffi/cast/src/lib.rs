uniffi::setup_scaffolding!("cast");

pub mod log;

use std::sync::Arc;

use ente_core::crypto;
use thiserror::Error;

#[derive(Debug, Error, uniffi::Error)]
pub enum CastCryptoError {
    #[error("{detail}")]
    Other { detail: String },
}

impl From<crypto::Error> for CastCryptoError {
    fn from(err: crypto::Error) -> Self {
        CastCryptoError::Other {
            detail: ente_core::error::chain(&err),
        }
    }
}

impl From<ente_cast::Error> for CastCryptoError {
    fn from(err: ente_cast::Error) -> Self {
        CastCryptoError::Other {
            detail: ente_core::error::chain(&err),
        }
    }
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct CastPayload {
    pub collection_id: i64,
    pub cast_token: String,
    pub collection_key: String,
}

impl From<ente_cast::CastPayload> for CastPayload {
    fn from(payload: ente_cast::CastPayload) -> Self {
        Self {
            collection_id: payload.collection_id,
            cast_token: payload.cast_token,
            collection_key: payload.collection_key,
        }
    }
}

#[derive(uniffi::Object)]
pub struct CastReceiver {
    inner: ente_cast::ReceiverCredentials,
}

#[uniffi::export]
impl CastReceiver {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            inner: ente_cast::ReceiverCredentials::generate(),
        })
    }

    pub fn public_key(&self) -> String {
        self.inner.public_key()
    }

    pub fn pq_public_key(&self) -> String {
        self.inner.pq_public_key()
    }

    pub fn open_payload(&self, encrypted_payload: String) -> Result<CastPayload, CastCryptoError> {
        Ok(self.inner.open_payload(&encrypted_payload)?.into())
    }
}

#[uniffi::export]
pub fn open_secret_box(
    ciphertext: Vec<u8>,
    nonce: Vec<u8>,
    key: Vec<u8>,
) -> Result<Vec<u8>, CastCryptoError> {
    let nonce = crypto::Nonce::try_from_slice(&nonce)?;
    let key = crypto::Key::try_from_slice(&key)?;
    Ok(crypto::secretbox::decrypt(&ciphertext, &nonce, &key)?)
}

#[uniffi::export]
pub fn decrypt_secret_stream(
    encrypted_data: Vec<u8>,
    header: Vec<u8>,
    key: Vec<u8>,
) -> Result<Vec<u8>, CastCryptoError> {
    let header = crypto::Header::try_from_slice(&header)?;
    let key = crypto::Key::try_from_slice(&key)?;
    Ok(crypto::stream::decrypt_file_data(
        &encrypted_data,
        &header,
        &key,
    )?)
}
