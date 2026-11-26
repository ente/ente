use std::sync::Arc;

use ente_core::crypto::aead::{self, TAG_BYTES, Tag};
use ente_core::crypto::{Key, Nonce};

use super::EncryptionMismatch;

pub(crate) const NONCE_LEN: usize = Nonce::BYTES;
pub(crate) const TAG_LEN: usize = TAG_BYTES;

#[derive(Debug, Clone)]
pub(crate) struct Cipher(Arc<Key>);

impl Cipher {
    pub(crate) fn new(key: &Key) -> Self {
        Self(Arc::new(Key::from_bytes(*key.as_bytes())))
    }

    pub(crate) fn seal(
        &self,
        buffer: &mut [u8],
        additional_data: &[u8],
    ) -> ente_core::crypto::Result<(Nonce, Tag)> {
        aead::encrypt_detached(buffer, additional_data, &self.0)
    }

    pub(crate) fn open(
        &self,
        buffer: &mut [u8],
        additional_data: &[u8],
        nonce: &[u8],
        tag: &[u8],
    ) -> bool {
        let (Ok(nonce), Ok(tag)) = (Nonce::try_from_slice(nonce), <&Tag>::try_from(tag)) else {
            return false;
        };
        aead::decrypt_detached(buffer, additional_data, tag, &nonce, &self.0).is_ok()
    }
}

pub(crate) fn encryption_mismatch(
    actual: Option<&Cipher>,
    given: Option<&Cipher>,
) -> Option<EncryptionMismatch> {
    match (actual, given) {
        (None, None) => None,
        (Some(_), None) => Some(EncryptionMismatch::MissingKey),
        (None, Some(_)) => Some(EncryptionMismatch::UnexpectedKey),
        (Some(actual), Some(given)) => {
            (actual.0 != given.0).then_some(EncryptionMismatch::WrongKey)
        }
    }
}
