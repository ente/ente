use ente_core::{b64, crypto};
use serde::Serialize;
use tsify::Tsify;

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct EncryptedBox {
    pub encrypted_data: String,
    pub nonce: String,
}

#[cfg(any(feature = "contacts", feature = "crypto-file"))]
pub(crate) fn serialize_bytes<S>(bytes: &[u8], serializer: S) -> Result<S::Ok, S::Error>
where
    S: serde::Serializer,
{
    serializer.serialize_bytes(bytes)
}

impl From<crypto::secretbox::EncryptedBox> for EncryptedBox {
    fn from(value: crypto::secretbox::EncryptedBox) -> Self {
        Self {
            encrypted_data: b64::encode(&value.encrypted_data),
            nonce: b64::encode(value.nonce.as_bytes()),
        }
    }
}
