//! Anonymous public-key encryption (sealed boxes).
//!
//! A sealed box lets anyone encrypt a message to a recipient's public key so
//! that only the holder of the matching secret key can read it, while the
//! recipient learns nothing about who sent it. Each message uses a fresh
//! ephemeral key pair whose public half is included in the output; the
//! ephemeral secret is discarded, so even the sender cannot decrypt afterwards.
//!
//! The construction is libsodium's `crypto_box_seal`; the implementation here
//! is pure Rust but wire-compatible (recorded per function below).
//!
//! # Wire format
//!
//! `ephemeral_pk (32 bytes) ‖ MAC (16 bytes) ‖ ciphertext`, where:
//!
//! - the nonce is `BLAKE2b-24(ephemeral_pk ‖ recipient_pk)`,
//! - the shared secret is `X25519(ephemeral_sk, recipient_pk)`,
//! - the symmetric key is `HSalsa20(shared_secret, zero_nonce)`, and
//! - the body is the `MAC ‖ ciphertext` of XSalsa20-Poly1305.

use blake2b_simd::Params as Blake2bParams;
use rand_core::{OsRng, RngCore};
use salsa20::hsalsa;
use subtle::ConstantTimeEq;
use x25519_dalek::StaticSecret;
use xsalsa20poly1305::XSalsa20Poly1305;
use xsalsa20poly1305::aead::generic_array::GenericArray;
use xsalsa20poly1305::aead::{Aead, KeyInit};
use zeroize::Zeroize;

use crate::crypto::{CryptoError, PublicKey, Result, SecretKey};

/// Size of a public key in bytes.
pub const PUBLIC_KEY_BYTES: usize = PublicKey::BYTES;

/// Size of a secret key in bytes.
pub const SECRET_KEY_BYTES: usize = SecretKey::BYTES;

/// Overhead added by sealing (ephemeral_pk + MAC).
pub const SEAL_OVERHEAD: usize = 32 + 16;

/// Derive nonce from ephemeral and recipient public keys.
///
/// Nonce = BLAKE2b-24(ephemeral_pk || recipient_pk)
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

/// Derive crypto_box key from X25519 shared secret.
///
/// Key = HSalsa20(shared_secret, zero_nonce)
fn derive_box_key(shared_secret: &[u8; 32]) -> [u8; 32] {
    use salsa20::cipher::consts::U10;

    let zero_nonce = [0u8; 16];

    // HSalsa20 core function with 20 rounds (U10 * 2)
    let result = hsalsa::<U10>(shared_secret.into(), (&zero_nonce).into());

    result.into()
}

/// Check if shared secret is contributory (not all zeros).
///
/// This prevents attacks using small-order points.
/// Uses constant-time comparison to avoid leaking information about the
/// shared secret through timing.
fn is_contributory(shared_secret: &[u8; 32]) -> bool {
    shared_secret.ct_ne(&[0u8; 32]).into()
}

/// Encrypt `plaintext` so that only the holder of `recipient_pk`'s secret key
/// can read it.
///
/// A fresh ephemeral key pair is generated per call and its secret discarded,
/// so the output carries no sender identity and the sender cannot decrypt it
/// afterwards. Open it with [`open`].
///
/// # Errors
///
/// Returns [`InvalidPublicKey`](CryptoError::InvalidPublicKey) if `recipient_pk`
/// is a low-order point, which would make the X25519 exchange yield an all-zero
/// shared secret and provide no security.
///
/// Returns `ephemeral_pk ‖ MAC ‖ ciphertext`, wire-compatible with libsodium's
/// `crypto_box_seal`.
pub fn seal(plaintext: &[u8], recipient_pk: &PublicKey) -> Result<Vec<u8>> {
    let recipient_pk_arr: [u8; 32] = *recipient_pk.as_bytes();
    let recipient_pk_point = x25519_dalek::PublicKey::from(recipient_pk_arr);

    // Generate ephemeral keypair
    let mut ephemeral_secret_bytes = [0u8; 32];
    OsRng.fill_bytes(&mut ephemeral_secret_bytes);
    let ephemeral_secret = StaticSecret::from(ephemeral_secret_bytes);
    let ephemeral_public = x25519_dalek::PublicKey::from(&ephemeral_secret);

    // Compute shared secret
    let shared_secret = ephemeral_secret.diffie_hellman(&recipient_pk_point);

    // SECURITY: Reject non-contributory (small-order point)
    if !is_contributory(shared_secret.as_bytes()) {
        ephemeral_secret_bytes.zeroize();
        return Err(CryptoError::InvalidPublicKey);
    }

    // Derive encryption key
    let mut box_key = derive_box_key(shared_secret.as_bytes());

    // Compute nonce
    let nonce = seal_nonce(ephemeral_public.as_bytes(), &recipient_pk_arr);

    // Encrypt with XSalsa20-Poly1305
    // RustCrypto outputs: MAC || ciphertext (same as libsodium)
    let cipher = XSalsa20Poly1305::new(GenericArray::from_slice(&box_key));
    let encrypted = cipher
        .encrypt(GenericArray::from_slice(&nonce), plaintext)
        .map_err(|_| {
            box_key.zeroize();
            CryptoError::EncryptionFailed
        })?;

    // Build output: ephemeral_pk || MAC || ciphertext
    let mut result = Vec::with_capacity(32 + encrypted.len());
    result.extend_from_slice(ephemeral_public.as_bytes());
    result.extend_from_slice(&encrypted);

    // Clean up sensitive data
    ephemeral_secret_bytes.zeroize();
    box_key.zeroize();

    Ok(result)
}

/// Decrypt a sealed box addressed to `recipient_pk` / `recipient_sk`.
///
/// `ciphertext` is the `ephemeral_pk ‖ MAC ‖ ciphertext` produced by [`seal`].
/// Both halves of the recipient key pair are needed: the secret key performs
/// the X25519 exchange, and the public key reconstructs the nonce.
///
/// # Errors
///
/// Returns [`CiphertextTooShort`](CryptoError::CiphertextTooShort) if
/// `ciphertext` is smaller than [`SEAL_OVERHEAD`],
/// [`InvalidPublicKey`](CryptoError::InvalidPublicKey) if the embedded ephemeral
/// key is low-order, or [`DecryptionFailed`](CryptoError::DecryptionFailed) if
/// the MAC does not verify, which happens with the wrong key pair or tampering.
///
/// Wire-compatible with libsodium's `crypto_box_seal_open`.
pub fn open(
    ciphertext: &[u8],
    recipient_pk: &PublicKey,
    recipient_sk: &SecretKey,
) -> Result<Vec<u8>> {
    if ciphertext.len() < SEAL_OVERHEAD {
        return Err(CryptoError::CiphertextTooShort {
            minimum: SEAL_OVERHEAD,
            actual: ciphertext.len(),
        });
    }

    // Parse: ephemeral_pk (32) || MAC (16) || ciphertext
    let ephemeral_pk_bytes: [u8; 32] = ciphertext[..32]
        .try_into()
        .map_err(|_| CryptoError::ArrayConversion)?;
    let encrypted = &ciphertext[32..]; // MAC || ciphertext

    let ephemeral_pk = x25519_dalek::PublicKey::from(ephemeral_pk_bytes);
    let recipient_sk_key = StaticSecret::from(*recipient_sk.as_bytes());
    let recipient_pk_arr: [u8; 32] = *recipient_pk.as_bytes();

    // Compute shared secret
    let shared_secret = recipient_sk_key.diffie_hellman(&ephemeral_pk);

    // SECURITY: Reject non-contributory (small-order point)
    if !is_contributory(shared_secret.as_bytes()) {
        return Err(CryptoError::InvalidPublicKey);
    }

    // Derive encryption key
    let mut box_key = derive_box_key(shared_secret.as_bytes());

    // Compute nonce
    let nonce = seal_nonce(&ephemeral_pk_bytes, &recipient_pk_arr);

    // Decrypt (RustCrypto expects same format: MAC || ciphertext)
    let cipher = XSalsa20Poly1305::new(GenericArray::from_slice(&box_key));
    let plaintext = cipher
        .decrypt(GenericArray::from_slice(&nonce), encrypted)
        .map_err(|_| {
            box_key.zeroize();
            CryptoError::DecryptionFailed
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

        // Different ephemeral keys -> different ciphertexts
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

        // Corrupt a byte in the middle
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

        // Corrupt ephemeral public key
        sealed[0] ^= 1;

        let result = open(&sealed, &pk, &sk);
        assert!(result.is_err());
    }

    #[test]
    fn test_corrupted_mac() {
        let (pk, sk) = generate_keypair();
        let plaintext = b"Original";

        let mut sealed = seal(plaintext, &pk).unwrap();

        // Corrupt MAC (at position 32-47)
        sealed[40] ^= 1;

        let result = open(&sealed, &pk, &sk);
        assert!(result.is_err());
    }

    #[test]
    fn test_ciphertext_too_short() {
        let (pk, sk) = generate_keypair();
        let bad_ciphertext = vec![0u8; 40]; // Less than SEAL_OVERHEAD

        let result = open(&bad_ciphertext, &pk, &sk);
        assert!(matches!(
            result,
            Err(CryptoError::CiphertextTooShort { .. })
        ));
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
        let plaintext = vec![0x42u8; 1024 * 1024]; // 1 MB

        let sealed = seal(&plaintext, &pk).unwrap();
        let opened = open(&sealed, &pk, &sk).unwrap();

        assert_eq!(opened, plaintext);
    }

    #[test]
    fn test_seal_rejects_small_order_point() {
        // The all-zero public key is a small-order point. X25519 DH with it
        // produces an all-zero shared secret, which is_contributory must reject.
        let zero_pk = PublicKey::from_bytes([0u8; 32]);
        let result = seal(b"test", &zero_pk);
        assert!(
            matches!(result, Err(CryptoError::InvalidPublicKey)),
            "seal() should reject small-order public key, got: {:?}",
            result
        );
    }

    #[test]
    fn test_open_rejects_small_order_ephemeral_key() {
        let (pk, sk) = generate_keypair();

        // Craft a ciphertext with an all-zero ephemeral public key (32 zero
        // bytes) followed by enough garbage to pass the length check.
        let mut fake_ciphertext = vec![0u8; SEAL_OVERHEAD + 16];
        // Fill the MAC + ciphertext portion with non-zero data so we know
        // the rejection is from is_contributory, not from decryption.
        for b in &mut fake_ciphertext[32..] {
            *b = 0xFF;
        }

        let result = open(&fake_ciphertext, &pk, &sk);
        assert!(
            matches!(result, Err(CryptoError::InvalidPublicKey)),
            "open() should reject small-order ephemeral key, got: {:?}",
            result
        );
    }

    #[test]
    fn test_multiple_recipients() {
        let (pk1, sk1) = generate_keypair();
        let (pk2, sk2) = generate_keypair();
        let plaintext = b"Broadcast message";

        // Seal for different recipients
        let sealed1 = seal(plaintext, &pk1).unwrap();
        let sealed2 = seal(plaintext, &pk2).unwrap();

        // Each recipient can decrypt their own
        let opened1 = open(&sealed1, &pk1, &sk1).unwrap();
        let opened2 = open(&sealed2, &pk2, &sk2).unwrap();

        assert_eq!(opened1, plaintext);
        assert_eq!(opened2, plaintext);

        // But not each other's
        assert!(open(&sealed1, &pk2, &sk2).is_err());
        assert!(open(&sealed2, &pk1, &sk1).is_err());
    }
}
