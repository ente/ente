uniffi::setup_scaffolding!("cast");

use ente_core::crypto;
use thiserror::Error;

#[derive(Debug, Error, uniffi::Error)]
pub enum CastCryptoError {
    #[error("{0}")]
    Message(String),
}

impl From<crypto::Error> for CastCryptoError {
    fn from(err: crypto::Error) -> Self {
        CastCryptoError::Message(ente_core::error::chain(&err))
    }
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct CastKeyPair {
    pub public_key: Vec<u8>,
    pub private_key: Vec<u8>,
}

#[uniffi::export]
pub fn generate_key_pair() -> CastKeyPair {
    let private_key = crypto::SecretKey::generate();
    let public_key = private_key.public_key();
    CastKeyPair {
        public_key: public_key.as_bytes().to_vec(),
        private_key: private_key.as_bytes().to_vec(),
    }
}

#[uniffi::export]
pub fn open_sealed_box(
    ciphertext: Vec<u8>,
    public_key: Vec<u8>,
    private_key: Vec<u8>,
) -> Result<Vec<u8>, CastCryptoError> {
    let public_key = crypto::PublicKey::try_from_slice(&public_key)?;
    let private_key = crypto::SecretKey::try_from_slice(&private_key)?;
    Ok(crypto::sealed::open(
        &ciphertext,
        &public_key,
        &private_key,
    )?)
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
