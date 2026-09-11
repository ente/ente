use ente_core::{
    Session, b64,
    crypto::{self, Key, Nonce, sealed, secretbox},
};

pub fn open_collection_key(
    session: &Session,
    owner_id: i64,
    encrypted_key: &str,
    key_decryption_nonce: Option<&str>,
) -> Result<Key> {
    let encrypted_key = b64::decode(encrypted_key)?;
    let key = if owner_id == session.user_id {
        let nonce = key_decryption_nonce.ok_or(Error::MissingKeyDecryptionNonce)?;
        secretbox::decrypt(
            &encrypted_key,
            &Nonce::try_from_slice(&b64::decode(nonce)?)?,
            &session.master_key,
        )?
    } else {
        sealed::open(
            &encrypted_key,
            &session.secret_key.public_key(),
            &session.secret_key,
        )?
    };
    Ok(Key::try_from_slice(&key)?)
}

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Decode(#[from] b64::DecodeError),
    #[error(transparent)]
    Crypto(#[from] crypto::Error),
    #[error("Owned collection is missing its key decryption nonce")]
    MissingKeyDecryptionNonce,
}

#[cfg(test)]
mod tests {
    use super::*;
    use ente_core::{crypto::SecretKey, http::ApiConfig};

    #[test]
    fn opens_owned_and_shared_collection_keys() {
        let master_key = Key::generate();
        let secret_key = SecretKey::generate();
        let session = Session::new(
            ApiConfig {
                origin: "http://localhost".into(),
                client_package: None,
                client_version: None,
                user_agent: None,
                auth: None,
            },
            42,
            master_key,
            Key::generate(),
            secret_key,
        )
        .unwrap();

        let owned_key = Key::generate();
        let encrypted_owned_key = secretbox::encrypt(owned_key.as_bytes(), &session.master_key);
        assert_eq!(
            open_collection_key(
                &session,
                42,
                &b64::encode(&encrypted_owned_key.encrypted_data),
                Some(&b64::encode(encrypted_owned_key.nonce.as_bytes())),
            )
            .unwrap(),
            owned_key,
        );

        let shared_key = Key::generate();
        let encrypted_shared_key =
            sealed::seal(shared_key.as_bytes(), &session.secret_key.public_key()).unwrap();
        assert_eq!(
            open_collection_key(&session, 7, &b64::encode(&encrypted_shared_key), None).unwrap(),
            shared_key,
        );
    }
}
