use hpke::{Deserializable, Kem as HpkeKem, OpModeR, OpModeS, Serializable};
use subtle::ConstantTimeEq;
use zeroize::ZeroizeOnDrop;

use crate::crypto::{Error, Result, fill_random};

type Aead = ::hpke::aead::ChaCha20Poly1305;
type Kdf = ::hpke::kdf::HkdfSha256;
type Kem = ::hpke::kem::XWing;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PublicKey([u8; Self::BYTES]);

impl PublicKey {
    pub const BYTES: usize = 1216;

    pub fn try_from_slice(bytes: &[u8]) -> Result<Self> {
        if bytes.len() != Self::BYTES {
            return Err(Error::InvalidKeyLength {
                expected: Self::BYTES,
                actual: bytes.len(),
            });
        }
        <Kem as HpkeKem>::PublicKey::from_bytes(bytes).map_err(|_| Error::InvalidPublicKey)?;
        Ok(Self(bytes.try_into()?))
    }

    pub fn as_bytes(&self) -> &[u8; Self::BYTES] {
        &self.0
    }

    fn hpke_key(&self) -> <Kem as HpkeKem>::PublicKey {
        <Kem as HpkeKem>::PublicKey::from_bytes(&self.0)
            .expect("PublicKey is validated when constructed")
    }
}

#[derive(ZeroizeOnDrop)]
pub struct SecretKey([u8; Self::BYTES]);

impl SecretKey {
    pub const BYTES: usize = 32;

    pub fn generate() -> Self {
        let mut bytes = [0u8; Self::BYTES];
        fill_random(&mut bytes);
        Self(bytes)
    }

    pub fn from_bytes(bytes: [u8; Self::BYTES]) -> Self {
        Self(bytes)
    }

    pub fn try_from_slice(bytes: &[u8]) -> Result<Self> {
        Ok(Self(bytes.try_into().map_err(|_| {
            Error::InvalidKeyLength {
                expected: Self::BYTES,
                actual: bytes.len(),
            }
        })?))
    }

    pub fn public_key(&self) -> PublicKey {
        let bytes = Kem::sk_to_pk(&self.hpke_key()).to_bytes();
        PublicKey(bytes.as_slice().try_into().expect("X-Wing public key size"))
    }

    pub fn as_bytes(&self) -> &[u8; Self::BYTES] {
        &self.0
    }

    fn hpke_key(&self) -> <Kem as HpkeKem>::PrivateKey {
        <Kem as HpkeKem>::PrivateKey::from_bytes(&self.0)
            .expect("X-Wing accepts every 32-byte private key")
    }
}

impl std::fmt::Debug for SecretKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("SecretKey([REDACTED])")
    }
}

impl PartialEq for SecretKey {
    fn eq(&self, other: &Self) -> bool {
        self.0.ct_eq(&other.0).into()
    }
}

impl Eq for SecretKey {}

pub const OVERHEAD: usize = 1136;
const ENCAPSULATED_KEY_BYTES: usize = 1120;

pub fn seal(plaintext: &[u8], public_key: &PublicKey, info: &[u8]) -> Result<Vec<u8>> {
    let (encapped_key, ciphertext) = ::hpke::single_shot_seal::<Aead, Kdf, Kem>(
        &OpModeS::Base,
        &public_key.hpke_key(),
        info,
        plaintext,
        &[],
    )
    .map_err(|_| Error::EncryptionFailed)?;

    let mut sealed = encapped_key.to_bytes().to_vec();
    sealed.extend_from_slice(&ciphertext);
    Ok(sealed)
}

pub fn open(ciphertext: &[u8], secret_key: &SecretKey, info: &[u8]) -> Result<Vec<u8>> {
    if ciphertext.len() < OVERHEAD {
        return Err(Error::CiphertextTooShort {
            minimum: OVERHEAD,
            actual: ciphertext.len(),
        });
    }
    let (encapped_key, ciphertext) = ciphertext.split_at(ENCAPSULATED_KEY_BYTES);
    let encapped_key = <Kem as HpkeKem>::EncappedKey::from_bytes(encapped_key)
        .map_err(|_| Error::DecryptionFailed)?;

    ::hpke::single_shot_open::<Aead, Kdf, Kem>(
        &OpModeR::Base,
        &secret_key.hpke_key(),
        &encapped_key,
        info,
        ciphertext,
        &[],
    )
    .map_err(|_| Error::DecryptionFailed)
}

#[cfg(test)]
mod tests {
    use base64::Engine;

    use super::*;

    const INFO: &[u8] = b"ente-test";

    #[test]
    fn seal_and_open() {
        let secret_key = SecretKey::generate();
        let public_key = secret_key.public_key();
        let plaintext = b"hello";

        let ciphertext = seal(plaintext, &public_key, INFO).unwrap();

        assert_eq!(ciphertext.len(), plaintext.len() + OVERHEAD);
        assert_ne!(ciphertext, seal(plaintext, &public_key, INFO).unwrap());
        assert_eq!(open(&ciphertext, &secret_key, INFO).unwrap(), plaintext);
        assert_eq!(
            SecretKey::try_from_slice(secret_key.as_bytes()).unwrap(),
            secret_key
        );
        assert_eq!(
            PublicKey::try_from_slice(public_key.as_bytes()).unwrap(),
            public_key
        );
    }

    #[test]
    fn authentication_failures() {
        let secret_key = SecretKey::generate();
        let ciphertext = seal(b"hello", &secret_key.public_key(), INFO).unwrap();

        assert!(open(&ciphertext, &SecretKey::generate(), INFO).is_err());
        assert!(open(&ciphertext, &secret_key, b"other-info").is_err());
        assert!(matches!(
            open(&ciphertext[..OVERHEAD - 1], &secret_key, INFO),
            Err(Error::CiphertextTooShort { .. })
        ));

        let mut corrupted = ciphertext;
        *corrupted.last_mut().unwrap() ^= 1;
        assert!(open(&corrupted, &secret_key, INFO).is_err());
    }

    #[test]
    fn opens_go_ciphertext() {
        // Generated with Go 1.26's crypto/hpke and private-key bytes 0..31.
        let secret_key = SecretKey::from_bytes(std::array::from_fn(|i| i as u8));
        let ciphertext = base64::engine::general_purpose::STANDARD
            .decode(include_str!("../../tests/data/hpke_go.sealed.b64").trim())
            .unwrap();

        assert_eq!(
            open(&ciphertext, &secret_key, b"ente-go-interop").unwrap(),
            b"sealed by Go"
        );
    }
}
