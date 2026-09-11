use std::string::FromUtf8Error;

use ente_core::{
    Session, b64,
    crypto::{self, Key, argon, sealed, secretbox},
};

const FRAGMENT_LENGTH: usize = 12;
const FRAGMENT_ALPHABET: &[u8] = b"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
const MAX_UNBIASED_BYTE: u8 = (256 - 256 % FRAGMENT_ALPHABET.len()) as u8;

pub struct FileLinkPayload {
    pub encrypted_file_key: String,
    pub encrypted_file_key_nonce: String,
    pub kdf_nonce: String,
    pub kdf_mem_limit: u32,
    pub kdf_ops_limit: u32,
}

pub fn prepare_file_link_payload(file_key: &Key) -> Result<(String, FileLinkPayload)> {
    let fragment = generate_fragment();
    let derived = argon::derive_interactive_key(&fragment)?;
    let encrypted = secretbox::encrypt(file_key.as_bytes(), &derived.key);
    let payload = FileLinkPayload {
        encrypted_file_key: b64::encode(&encrypted.encrypted_data),
        encrypted_file_key_nonce: b64::encode(encrypted.nonce.as_bytes()),
        kdf_nonce: b64::encode(derived.salt.as_bytes()),
        kdf_mem_limit: derived.params.mem_limit,
        kdf_ops_limit: derived.params.ops_limit,
    };
    Ok((fragment, payload))
}

pub fn seal_file_link_secret(session: &Session, fragment: &str) -> Result<String> {
    let encoded = b64::encode(fragment.as_bytes());
    let encrypted = sealed::seal(encoded.as_bytes(), &session.secret_key.public_key())?;
    Ok(b64::encode(&encrypted))
}

pub fn open_file_link_secret(session: &Session, encrypted_share_key: &str) -> Result<String> {
    let encrypted = b64::decode(encrypted_share_key)?;
    let encoded = sealed::open(
        &encrypted,
        &session.secret_key.public_key(),
        &session.secret_key,
    )?;
    let encoded = String::from_utf8(encoded)?;
    Ok(String::from_utf8(b64::decode(&encoded)?)?)
}

fn generate_fragment() -> String {
    let mut fragment = String::with_capacity(FRAGMENT_LENGTH);
    while fragment.len() < FRAGMENT_LENGTH {
        for byte in crypto::random_bytes(FRAGMENT_LENGTH - fragment.len()) {
            if byte < MAX_UNBIASED_BYTE {
                fragment.push(FRAGMENT_ALPHABET[(byte as usize) % FRAGMENT_ALPHABET.len()] as char);
            }
        }
    }
    fragment
}

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Decode(#[from] b64::DecodeError),
    #[error(transparent)]
    Crypto(#[from] crypto::Error),
    #[error(transparent)]
    Utf8(#[from] FromUtf8Error),
}

#[cfg(test)]
mod tests {
    use super::*;
    use ente_core::{
        crypto::{Nonce, Salt, SecretKey},
        http::ApiConfig,
    };

    #[test]
    fn prepares_and_opens_file_link_secrets() {
        let session = Session::new(
            ApiConfig {
                origin: "http://localhost".into(),
                client_package: None,
                client_version: None,
                user_agent: None,
                auth: None,
            },
            1,
            Key::generate(),
            Key::generate(),
            SecretKey::generate(),
        )
        .unwrap();
        let file_key = Key::generate();

        let (fragment, payload) = prepare_file_link_payload(&file_key).unwrap();
        assert_eq!(fragment.len(), FRAGMENT_LENGTH);
        assert!(fragment.bytes().all(|byte| byte.is_ascii_alphanumeric()));

        let derived = argon::derive_key(
            &fragment,
            &Salt::try_from_slice(&b64::decode(&payload.kdf_nonce).unwrap()).unwrap(),
            argon::Params {
                mem_limit: payload.kdf_mem_limit,
                ops_limit: payload.kdf_ops_limit,
            },
        )
        .unwrap();
        let opened_file_key = secretbox::decrypt(
            &b64::decode(&payload.encrypted_file_key).unwrap(),
            &Nonce::try_from_slice(&b64::decode(&payload.encrypted_file_key_nonce).unwrap())
                .unwrap(),
            &derived,
        )
        .unwrap();
        assert_eq!(opened_file_key, file_key.as_bytes());

        let encrypted_share_key = seal_file_link_secret(&session, &fragment).unwrap();
        let sealed_plaintext = sealed::open(
            &b64::decode(&encrypted_share_key).unwrap(),
            &session.secret_key.public_key(),
            &session.secret_key,
        )
        .unwrap();
        assert_eq!(
            sealed_plaintext,
            b64::encode(fragment.as_bytes()).as_bytes()
        );
        assert_eq!(
            open_file_link_secret(&session, &encrypted_share_key).unwrap(),
            fragment,
        );
    }
}
