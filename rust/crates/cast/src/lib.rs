use ente_core::crypto::{self, PublicKey, SecretKey};
use ente_core::{b64, id};
use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum Error {
    #[error("Invalid base64: {0}")]
    Base64(#[from] b64::DecodeError),

    #[error(transparent)]
    Crypto(#[from] crypto::Error),

    #[error("Invalid cast payload: {0}")]
    Payload(#[from] serde_json::Error),
}

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CastPayload {
    #[serde(rename = "collectionID")]
    pub collection_id: i64,
    pub cast_token: String,
    pub collection_key: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct PreparedCastPayload {
    pub cast_token: String,
    pub encrypted_payload: String,
}

pub struct ReceiverCredentials {
    secret_key: SecretKey,
}

impl ReceiverCredentials {
    pub fn generate() -> Self {
        Self {
            secret_key: SecretKey::generate(),
        }
    }

    pub fn public_key(&self) -> String {
        b64::encode(self.secret_key.public_key().as_bytes())
    }

    pub fn open_payload(&self, encrypted_payload: &str) -> Result<CastPayload> {
        let ciphertext = b64::decode(encrypted_payload)?;
        let public_key = self.secret_key.public_key();
        let plaintext = crypto::sealed::open(&ciphertext, &public_key, &self.secret_key)?;
        Ok(serde_json::from_slice(&plaintext)?)
    }
}

pub fn prepare_payload(
    public_key: &str,
    collection_id: i64,
    collection_key: &str,
) -> Result<PreparedCastPayload> {
    let cast_token = id::random("cast");
    let encrypted_payload = seal_payload(
        public_key,
        &CastPayload {
            collection_id,
            cast_token: cast_token.clone(),
            collection_key: collection_key.to_owned(),
        },
    )?;
    Ok(PreparedCastPayload {
        cast_token,
        encrypted_payload,
    })
}

fn seal_payload(public_key: &str, payload: &CastPayload) -> Result<String> {
    let public_key = PublicKey::try_from_slice(&b64::decode(public_key)?)?;
    let plaintext = serde_json::to_vec(payload)?;
    Ok(b64::encode(&crypto::sealed::seal(&plaintext, &public_key)?))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn payload() -> CastPayload {
        CastPayload {
            collection_id: 42,
            cast_token: "cast_token".into(),
            collection_key: "collection_key".into(),
        }
    }

    #[test]
    fn round_trip() {
        let receiver = ReceiverCredentials::generate();
        let prepared = prepare_payload(
            &receiver.public_key(),
            payload().collection_id,
            &payload().collection_key,
        )
        .unwrap();
        assert_eq!(
            receiver.open_payload(&prepared.encrypted_payload).unwrap(),
            CastPayload {
                cast_token: prepared.cast_token,
                ..payload()
            }
        );
    }

    #[test]
    fn payload_uses_existing_wire_names() {
        assert_eq!(
            serde_json::to_string(&payload()).unwrap(),
            r#"{"collectionID":42,"castToken":"cast_token","collectionKey":"collection_key"}"#
        );
    }

    #[test]
    fn opens_existing_libsodium_payload() {
        let secret_key: [u8; 32] = std::array::from_fn(|index| index as u8);
        let receiver = ReceiverCredentials {
            secret_key: SecretKey::from_seed(&secret_key).unwrap(),
        };
        assert_eq!(
            receiver.public_key(),
            "j0DFrbaPJWJK5bIU6nZ6bslNgp09e14a0bpvPiE4KF8="
        );

        let encrypted = "kWxjziNMQxuQ/vqdErOGA3Rw14SfGgCy/wRRbsIIRncPWMHB52ezfFT+403RPw5oKuQonUgwWlQNBVcNOnKn54v8nkJuTxMyrqH2YLghbnhVFV/L+JICvFwZvcBBCN7tNNtjtOENJXn/hHaLbT+LwUAtrwwOPWiuca0vRdg=";
        assert_eq!(receiver.open_payload(encrypted).unwrap(), payload());
    }

    #[test]
    fn rejects_invalid_inputs() {
        assert!(prepare_payload("not base64", 42, "collection_key").is_err());

        let receiver = ReceiverCredentials::generate();
        assert!(receiver.open_payload("not base64").is_err());
        assert!(receiver.open_payload(&b64::encode(&[0; 48])).is_err());
    }

    #[test]
    fn generates_cast_token() {
        let receiver = ReceiverCredentials::generate();
        let first = prepare_payload(&receiver.public_key(), 42, "collection_key").unwrap();
        let second = prepare_payload(&receiver.public_key(), 42, "collection_key").unwrap();

        assert_eq!(first.cast_token.len(), 27);
        assert!(first.cast_token.starts_with("cast_"));
        assert_ne!(first.cast_token, second.cast_token);
    }
}
