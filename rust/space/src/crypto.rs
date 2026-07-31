use ente_core::b64;
use ente_core::crypto::{Key, Nonce, PublicKey, SecretKey, blob, sealed, secretbox};
use md5::{Digest, Md5};

use crate::error::Result;

pub(crate) const SECRETBOX_PAYLOAD_OVERHEAD_BYTES: usize = Nonce::BYTES + secretbox::MAC_BYTES;
pub(crate) const ASSET_PAYLOAD_OVERHEAD_BYTES: usize = blob::HEADER_BYTES + blob::ABYTES;

pub(crate) fn generate_key() -> Vec<u8> {
    Key::generate().as_bytes().to_vec()
}

pub(crate) fn generate_keypair() -> Result<(Vec<u8>, Vec<u8>)> {
    let secret_key = SecretKey::generate();
    let public_key = secret_key.public_key();
    Ok((
        public_key.as_bytes().to_vec(),
        secret_key.as_bytes().to_vec(),
    ))
}

pub(crate) fn seal_with_public_key(plaintext: &[u8], public_key: &[u8]) -> Result<Vec<u8>> {
    let public_key = PublicKey::try_from_slice(public_key)?;
    sealed::seal(plaintext, &public_key).map_err(Into::into)
}

pub(crate) fn open_with_keypair(
    ciphertext: &[u8],
    public_key: &[u8],
    secret_key: &[u8],
) -> Result<Vec<u8>> {
    let public_key = PublicKey::try_from_slice(public_key)?;
    let secret_key = SecretKey::try_from_slice(secret_key)?;
    sealed::open(ciphertext, &public_key, &secret_key).map_err(Into::into)
}

pub(crate) fn content_md5_base64(bytes: &[u8]) -> String {
    let digest = Md5::digest(bytes);
    b64::encode(&digest)
}

pub(crate) fn encrypt_secretbox_payload(key: &[u8], plaintext: &[u8]) -> Result<Vec<u8>> {
    let key = Key::try_from_slice(key)?;
    Ok(secretbox::encrypt_combined(plaintext, &key))
}

pub(crate) fn decrypt_secretbox_payload(key: &[u8], payload: &[u8]) -> Result<Vec<u8>> {
    let key = Key::try_from_slice(key)?;
    secretbox::decrypt_combined(payload, &key).map_err(Into::into)
}

pub(crate) fn encrypt_asset_payload(key: &[u8], plaintext: &[u8]) -> Result<Vec<u8>> {
    let key = Key::try_from_slice(key)?;
    blob::encrypt_combined(plaintext, &key).map_err(Into::into)
}

pub(crate) fn decrypt_asset_payload(key: &[u8], payload: &[u8]) -> Result<Vec<u8>> {
    let key = Key::try_from_slice(key)?;
    blob::decrypt_combined(payload, &key).map_err(Into::into)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn secretbox_payload_round_trip() {
        let key = generate_key();
        let plaintext = b"hello space";
        let payload = encrypt_secretbox_payload(&key, plaintext).unwrap();
        let decrypted = decrypt_secretbox_payload(&key, &payload).unwrap();
        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn asset_round_trip() {
        let key = generate_key();
        let plaintext = b"asset-bytes";
        let encrypted = encrypt_asset_payload(&key, plaintext).unwrap();
        let decrypted = decrypt_asset_payload(&key, &encrypted).unwrap();
        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn content_md5_base64_matches_vector() {
        assert_eq!(content_md5_base64(b"hello"), "XUFAKrxLKna5cZ2REBfFkg==");
    }
}
