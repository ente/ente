use blake2b_simd::Params as Blake2bParams;
use crypto_secretbox::XSalsa20Poly1305;
use crypto_secretbox::aead::generic_array::GenericArray;
use crypto_secretbox::aead::{Aead, KeyInit};
use salsa20::hsalsa;
use subtle::ConstantTimeEq;
use x25519_dalek::StaticSecret;
use zeroize::Zeroize;

use crate::crypto::{Error, PublicKey, Result, SecretKey, fill_random};

pub const PUBLIC_KEY_BYTES: usize = PublicKey::BYTES;

pub const SECRET_KEY_BYTES: usize = SecretKey::BYTES;

pub const SEAL_OVERHEAD: usize = 32 + 16;

fn seal_nonce(ephemeral_pk: &[u8; 32], recipient_pk: &[u8; 32]) -> [u8; 24] {
    let hash = Blake2bParams::new()
        .hash_length(24)
        .to_state()
        .update(ephemeral_pk)
        .update(recipient_pk)
        .finalize();

    let mut nonce = [0u8; 24];
    nonce.copy_from_slice(hash.as_bytes());
    nonce
}

fn derive_box_key(shared_secret: &[u8; 32]) -> [u8; 32] {
    use salsa20::cipher::consts::U10;

    let zero_nonce = [0u8; 16];

    // U10 runs the 20 rounds required by libsodium's crypto_box construction.
    let result = hsalsa::<U10>(shared_secret.into(), (&zero_nonce).into());

    result.into()
}

fn is_contributory(shared_secret: &[u8; 32]) -> bool {
    shared_secret.ct_ne(&[0u8; 32]).into()
}

// Returns `ephemeral_pk || MAC || ciphertext`, wire-compatible with libsodium's
// `crypto_box_seal`.
pub fn seal(plaintext: &[u8], recipient_pk: &PublicKey) -> Result<Vec<u8>> {
    let recipient_pk_arr: [u8; 32] = *recipient_pk.as_bytes();
    let recipient_pk_point = x25519_dalek::PublicKey::from(recipient_pk_arr);

    let mut ephemeral_secret_bytes = [0u8; 32];
    fill_random(&mut ephemeral_secret_bytes);
    let ephemeral_secret = StaticSecret::from(ephemeral_secret_bytes);
    let ephemeral_public = x25519_dalek::PublicKey::from(&ephemeral_secret);

    let shared_secret = ephemeral_secret.diffie_hellman(&recipient_pk_point);

    // Reject small-order points that produce an all-zero shared secret.
    if !is_contributory(shared_secret.as_bytes()) {
        ephemeral_secret_bytes.zeroize();
        return Err(Error::InvalidPublicKey);
    }

    let mut box_key = derive_box_key(shared_secret.as_bytes());

    let nonce = seal_nonce(ephemeral_public.as_bytes(), &recipient_pk_arr);

    // RustCrypto and libsodium both encode this as MAC || ciphertext.
    let cipher = XSalsa20Poly1305::new(GenericArray::from_slice(&box_key));
    let encrypted = cipher
        .encrypt(GenericArray::from_slice(&nonce), plaintext)
        .map_err(|_| {
            box_key.zeroize();
            Error::EncryptionFailed
        })?;

    let mut result = Vec::with_capacity(32 + encrypted.len());
    result.extend_from_slice(ephemeral_public.as_bytes());
    result.extend_from_slice(&encrypted);

    ephemeral_secret_bytes.zeroize();
    box_key.zeroize();

    Ok(result)
}

// Wire-compatible with libsodium's `crypto_box_seal_open`.
pub fn open(
    ciphertext: &[u8],
    recipient_pk: &PublicKey,
    recipient_sk: &SecretKey,
) -> Result<Vec<u8>> {
    if ciphertext.len() < SEAL_OVERHEAD {
        return Err(Error::CiphertextTooShort {
            minimum: SEAL_OVERHEAD,
            actual: ciphertext.len(),
        });
    }

    let ephemeral_pk_bytes: [u8; 32] = ciphertext[..32]
        .try_into()
        .map_err(|_| Error::ArrayConversion)?;
    let encrypted = &ciphertext[32..];

    let ephemeral_pk = x25519_dalek::PublicKey::from(ephemeral_pk_bytes);
    let recipient_sk_key = StaticSecret::from(*recipient_sk.as_bytes());
    let recipient_pk_arr: [u8; 32] = *recipient_pk.as_bytes();

    let shared_secret = recipient_sk_key.diffie_hellman(&ephemeral_pk);

    // Reject small-order points that produce an all-zero shared secret.
    if !is_contributory(shared_secret.as_bytes()) {
        return Err(Error::InvalidPublicKey);
    }

    let mut box_key = derive_box_key(shared_secret.as_bytes());

    let nonce = seal_nonce(&ephemeral_pk_bytes, &recipient_pk_arr);

    let cipher = XSalsa20Poly1305::new(GenericArray::from_slice(&box_key));
    let plaintext = cipher
        .decrypt(GenericArray::from_slice(&nonce), encrypted)
        .map_err(|_| {
            box_key.zeroize();
            Error::DecryptionFailed
        })?;
    box_key.zeroize();
    Ok(plaintext)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn generate_keypair() -> (PublicKey, SecretKey) {
        let sk = SecretKey::generate();
        (sk.public_key(), sk)
    }

    #[test]
    fn test_seal_open() {
        let (pk, sk) = generate_keypair();
        let plaintext = b"Hello, sealed world!";

        let sealed = seal(plaintext, &pk).unwrap();
        let opened = open(&sealed, &pk, &sk).unwrap();

        assert_eq!(opened, plaintext);
    }

    #[test]
    fn test_seal_overhead() {
        let (pk, _sk) = generate_keypair();
        let plaintext = b"Test";

        let sealed = seal(plaintext, &pk).unwrap();
        assert_eq!(sealed.len(), plaintext.len() + SEAL_OVERHEAD);
    }

    #[test]
    fn test_seal_non_deterministic() {
        let (pk, _sk) = generate_keypair();
        let plaintext = b"Same message";

        let sealed1 = seal(plaintext, &pk).unwrap();
        let sealed2 = seal(plaintext, &pk).unwrap();

        assert_ne!(sealed1, sealed2);
    }

    #[test]
    fn test_wrong_secret_key() {
        let (pk1, _sk1) = generate_keypair();
        let (_pk2, sk2) = generate_keypair();
        let plaintext = b"Secret";

        let sealed = seal(plaintext, &pk1).unwrap();
        let result = open(&sealed, &pk1, &sk2);

        assert!(result.is_err());
    }

    #[test]
    fn test_wrong_public_key() {
        let (pk1, sk1) = generate_keypair();
        let (pk2, _sk2) = generate_keypair();
        let plaintext = b"Secret";

        let sealed = seal(plaintext, &pk1).unwrap();
        let result = open(&sealed, &pk2, &sk1);

        assert!(result.is_err());
    }

    #[test]
    fn test_corrupted_ciphertext() {
        let (pk, sk) = generate_keypair();
        let plaintext = b"Original";

        let mut sealed = seal(plaintext, &pk).unwrap();

        let mid = sealed.len() / 2;
        sealed[mid] ^= 1;

        let result = open(&sealed, &pk, &sk);
        assert!(result.is_err());
    }

    #[test]
    fn test_corrupted_ephemeral_key() {
        let (pk, sk) = generate_keypair();
        let plaintext = b"Original";

        let mut sealed = seal(plaintext, &pk).unwrap();

        sealed[0] ^= 1;

        let result = open(&sealed, &pk, &sk);
        assert!(result.is_err());
    }

    #[test]
    fn test_corrupted_mac() {
        let (pk, sk) = generate_keypair();
        let plaintext = b"Original";

        let mut sealed = seal(plaintext, &pk).unwrap();

        sealed[40] ^= 1;

        let result = open(&sealed, &pk, &sk);
        assert!(result.is_err());
    }

    #[test]
    fn test_ciphertext_too_short() {
        let (pk, sk) = generate_keypair();
        let bad_ciphertext = vec![0u8; 40];

        let result = open(&bad_ciphertext, &pk, &sk);
        assert!(matches!(result, Err(Error::CiphertextTooShort { .. })));
    }

    #[test]
    fn test_empty_plaintext() {
        let (pk, sk) = generate_keypair();
        let plaintext = b"";

        let sealed = seal(plaintext, &pk).unwrap();
        let opened = open(&sealed, &pk, &sk).unwrap();

        assert_eq!(opened, plaintext);
        assert_eq!(sealed.len(), SEAL_OVERHEAD);
    }

    #[test]
    fn test_large_plaintext() {
        let (pk, sk) = generate_keypair();
        let plaintext = vec![0x42u8; 1024 * 1024];

        let sealed = seal(&plaintext, &pk).unwrap();
        let opened = open(&sealed, &pk, &sk).unwrap();

        assert_eq!(opened, plaintext);
    }

    #[test]
    fn test_seal_rejects_small_order_point() {
        let zero_pk = PublicKey::from_bytes([0u8; 32]);
        let result = seal(b"test", &zero_pk);
        assert!(
            matches!(result, Err(Error::InvalidPublicKey)),
            "seal() should reject small-order public key, got: {:?}",
            result
        );
    }

    #[test]
    fn test_open_rejects_small_order_ephemeral_key() {
        let (pk, sk) = generate_keypair();

        let mut fake_ciphertext = vec![0u8; SEAL_OVERHEAD + 16];
        for b in &mut fake_ciphertext[32..] {
            *b = 0xFF;
        }

        let result = open(&fake_ciphertext, &pk, &sk);
        assert!(
            matches!(result, Err(Error::InvalidPublicKey)),
            "open() should reject small-order ephemeral key, got: {:?}",
            result
        );
    }

    #[test]
    fn test_multiple_recipients() {
        let (pk1, sk1) = generate_keypair();
        let (pk2, sk2) = generate_keypair();
        let plaintext = b"Broadcast message";

        let sealed1 = seal(plaintext, &pk1).unwrap();
        let sealed2 = seal(plaintext, &pk2).unwrap();

        let opened1 = open(&sealed1, &pk1, &sk1).unwrap();
        let opened2 = open(&sealed2, &pk2, &sk2).unwrap();

        assert_eq!(opened1, plaintext);
        assert_eq!(opened2, plaintext);

        assert!(open(&sealed1, &pk2, &sk2).is_err());
        assert!(open(&sealed2, &pk1, &sk1).is_err());
    }
}
