use ente_core::crypto::{self, PublicKey, SecretKey, hpke};
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

const HPKE_INFO: &[u8] = b"ente-cast";

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
    pq_secret_key: hpke::SecretKey,
}

impl ReceiverCredentials {
    pub fn generate() -> Self {
        Self {
            secret_key: SecretKey::generate(),
            pq_secret_key: hpke::SecretKey::generate(),
        }
    }

    pub fn public_key(&self) -> String {
        b64::encode(self.secret_key.public_key().as_bytes())
    }

    pub fn pq_public_key(&self) -> String {
        b64::encode(self.pq_secret_key.public_key().as_bytes())
    }

    pub fn open_payload(&self, encrypted_payload: &str) -> Result<CastPayload> {
        let ciphertext = b64::decode(encrypted_payload)?;
        let plaintext = hpke::open(&ciphertext, &self.pq_secret_key, HPKE_INFO).or_else(|_| {
            crypto::sealed::open(&ciphertext, &self.secret_key.public_key(), &self.secret_key)
        })?;
        Ok(serde_json::from_slice(&plaintext)?)
    }
}

pub fn prepare_payload(
    public_key: &str,
    pq_public_key: Option<&str>,
    collection_id: i64,
    collection_key: &str,
) -> Result<PreparedCastPayload> {
    let cast_token = id::random("cast");
    let encrypted_payload = seal_payload(
        public_key,
        pq_public_key,
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

fn seal_payload(
    public_key: &str,
    pq_public_key: Option<&str>,
    payload: &CastPayload,
) -> Result<String> {
    let plaintext = serde_json::to_vec(payload)?;
    let ciphertext = if let Some(pq_public_key) = pq_public_key {
        let public_key = hpke::PublicKey::try_from_slice(&b64::decode(pq_public_key)?)?;
        hpke::seal(&plaintext, &public_key, HPKE_INFO)?
    } else {
        let public_key = PublicKey::try_from_slice(&b64::decode(public_key)?)?;
        crypto::sealed::seal(&plaintext, &public_key)?
    };
    Ok(b64::encode(&ciphertext))
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
    fn pq_round_trip() {
        let receiver = ReceiverCredentials::generate();
        let prepared = prepare_payload(
            &receiver.public_key(),
            Some(&receiver.pq_public_key()),
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
            pq_secret_key: hpke::SecretKey::generate(),
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
        assert!(prepare_payload("not base64", None, 42, "collection_key").is_err());

        let receiver = ReceiverCredentials::generate();
        assert!(receiver.open_payload("not base64").is_err());
        assert!(receiver.open_payload(&b64::encode(&[0; 48])).is_err());
    }

    #[test]
    fn sender_does_not_fallback_from_invalid_pq_key() {
        let receiver = ReceiverCredentials::generate();
        assert!(
            prepare_payload(
                &receiver.public_key(),
                Some("not base64"),
                42,
                "collection_key"
            )
            .is_err()
        );
    }

    #[test]
    fn sender_uses_classical_without_pq_key() {
        let receiver = ReceiverCredentials::generate();
        let prepared = prepare_payload(
            &receiver.public_key(),
            None,
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
    fn corrupted_payloads_fail() {
        let receiver = ReceiverCredentials::generate();
        for pq_public_key in [Some(receiver.pq_public_key()), None] {
            let prepared = prepare_payload(
                &receiver.public_key(),
                pq_public_key.as_deref(),
                42,
                "collection_key",
            )
            .unwrap();
            let mut ciphertext = b64::decode(&prepared.encrypted_payload).unwrap();
            *ciphertext.last_mut().unwrap() ^= 1;
            assert!(receiver.open_payload(&b64::encode(&ciphertext)).is_err());
        }
    }

    #[test]
    fn wrong_hpke_domain_fails() {
        let receiver = ReceiverCredentials::generate();
        let ciphertext = hpke::seal(
            &serde_json::to_vec(&payload()).unwrap(),
            &receiver.pq_secret_key.public_key(),
            b"other-domain",
        )
        .unwrap();

        assert!(receiver.open_payload(&b64::encode(&ciphertext)).is_err());
    }

    #[test]
    fn invalid_pq_plaintext_is_not_retried_as_classical() {
        let receiver = ReceiverCredentials::generate();
        let ciphertext =
            hpke::seal(b"not JSON", &receiver.pq_secret_key.public_key(), HPKE_INFO).unwrap();

        assert!(matches!(
            receiver.open_payload(&b64::encode(&ciphertext)),
            Err(Error::Payload(_))
        ));
    }

    #[test]
    fn generates_cast_token() {
        let receiver = ReceiverCredentials::generate();
        let first = prepare_payload(&receiver.public_key(), None, 42, "collection_key").unwrap();
        let second = prepare_payload(&receiver.public_key(), None, 42, "collection_key").unwrap();

        assert_eq!(first.cast_token.len(), 27);
        assert!(first.cast_token.starts_with("cast_"));
        assert_ne!(first.cast_token, second.cast_token);
    }
}
