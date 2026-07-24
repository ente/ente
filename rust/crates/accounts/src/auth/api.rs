//! High-level authentication API for applications.
//!
//! This module provides the main entry points that CLI/GUI applications should use
//! for authentication flows. It wraps the lower-level crypto operations.

use std::fmt;

use ente_core::crypto::{self, Salt, SecretVec, argon, kdf, sealed, secretbox};
use sha2::Sha256;
use srp::ClientG4096;

use super::{AuthError, KeyAttributes, Result, SrpAttributes};

/// Credentials derived from password for SRP authentication.
pub struct SrpCredentials {
    /// Key encryption key (32 bytes) - used to decrypt master key after auth.
    pub kek: SecretVec,
    /// Login key (16 bytes) - used as password in SRP protocol.
    pub login_key: SecretVec,
}

impl fmt::Debug for SrpCredentials {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("SrpCredentials")
            .field("kek", &"[REDACTED]")
            .field("login_key", &"[REDACTED]")
            .finish()
    }
}

/// Decrypted secrets after successful authentication.
pub struct DecryptedSecrets {
    /// Master key for encrypting/decrypting data.
    pub master_key: SecretVec,
    /// Secret key (private key) for asymmetric operations.
    pub secret_key: SecretVec,
    /// Authentication token (decrypted).
    pub token: SecretVec,
}

impl fmt::Debug for DecryptedSecrets {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("DecryptedSecrets")
            .field("master_key", &"[REDACTED]")
            .field("secret_key", &"[REDACTED]")
            .field("token", &"[REDACTED]")
            .finish()
    }
}

/// A derived key-encryption-key and the parameters used to derive it.
pub struct GeneratedKek {
    /// Derived KEK bytes.
    pub key: SecretVec,
    /// Salt used for Argon2 derivation.
    pub salt: Vec<u8>,
    /// Argon2 memory limit in bytes.
    pub mem_limit: u32,
    /// Argon2 operations limit.
    pub ops_limit: u32,
}

impl fmt::Debug for GeneratedKek {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("GeneratedKek")
            .field("key", &"[REDACTED]")
            .field("salt_len", &self.salt.len())
            .field("mem_limit", &self.mem_limit)
            .field("ops_limit", &self.ops_limit)
            .finish()
    }
}

/// Attributes needed to register or update SRP for a user.
pub struct GeneratedSrpSetup {
    /// SRP salt bytes.
    pub srp_salt: Vec<u8>,
    /// SRP verifier bytes.
    pub srp_verifier: Vec<u8>,
    /// Derived 16-byte login sub-key bytes.
    pub login_sub_key: SecretVec,
}

impl fmt::Debug for GeneratedSrpSetup {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("GeneratedSrpSetup")
            .field("srp_salt_len", &self.srp_salt.len())
            .field("srp_verifier", &"[REDACTED]")
            .field("login_sub_key", &"[REDACTED]")
            .finish()
    }
}

/// Derive SRP credentials from password.
///
/// This is the first step in the SRP login flow. Call this after password entry
/// to get the credentials needed for the SRP protocol.
///
/// # Arguments
/// * `password` - User's password
/// * `srp_attrs` - SRP attributes from the server
///
/// # Returns
/// * `SrpCredentials` containing KEK (for later decryption) and login_key (for SRP)
pub fn derive_srp_credentials(password: &str, srp_attrs: &SrpAttributes) -> Result<SrpCredentials> {
    let kek_salt = crypto::decode_b64(&srp_attrs.kek_salt)
        .map_err(|e| AuthError::Decode(format!("kek_salt: {}", e)))?;
    let salt = crypto::Salt::try_from_slice(&kek_salt)?;

    let kek = argon::derive_key(
        password,
        &salt,
        argon::Params {
            mem_limit: srp_attrs.mem_limit,
            ops_limit: srp_attrs.ops_limit,
        },
    )?;

    let login_key = kdf::derive_login_key(&kek);

    Ok(SrpCredentials {
        kek: SecretVec::new(kek.as_bytes().to_vec()),
        login_key,
    })
}

/// Derive only the KEK from password.
///
/// Use this for email MFA flow where SRP is skipped. The KEK is used
/// to decrypt the master key after email/TOTP verification.
///
/// # Arguments
/// * `password` - User's password
/// * `kek_salt` - Base64-encoded salt from key attributes
/// * `mem_limit` - Argon2 memory limit
/// * `ops_limit` - Argon2 operations limit
pub fn derive_kek(
    password: &str,
    kek_salt: &str,
    mem_limit: u32,
    ops_limit: u32,
) -> Result<SecretVec> {
    let salt_bytes =
        crypto::decode_b64(kek_salt).map_err(|e| AuthError::Decode(format!("kek_salt: {}", e)))?;
    let salt = crypto::Salt::try_from_slice(&salt_bytes)?;

    let key = argon::derive_key(
        password,
        &salt,
        argon::Params {
            mem_limit,
            ops_limit,
        },
    )?;
    Ok(SecretVec::new(key.as_bytes().to_vec()))
}

/// Generate a KEK using the current adaptive sensitive client policy.
pub fn generate_sensitive_kek(password: &str) -> Result<GeneratedKek> {
    let derived = argon::derive_sensitive_key(password).map_err(|e| match e {
        crypto::Error::InvalidKeyDerivationParams(_) => AuthError::Crypto(e),
        _ => AuthError::InsufficientMemory,
    })?;

    Ok(generated_kek(derived))
}

/// Generate a KEK using the current interactive web policy.
pub fn generate_interactive_kek(password: &str) -> Result<GeneratedKek> {
    let derived = argon::derive_interactive_key(password)?;

    Ok(generated_kek(derived))
}

fn generated_kek(derived: argon::DerivedKey) -> GeneratedKek {
    GeneratedKek {
        key: SecretVec::new(derived.key.as_bytes().to_vec()),
        salt: derived.salt.as_bytes().to_vec(),
        mem_limit: derived.params.mem_limit,
        ops_limit: derived.params.ops_limit,
    }
}

/// Generate the SRP setup payload for a given KEK and SRP user ID.
pub fn generate_srp_setup(kek: &[u8], srp_user_id: &str) -> Result<GeneratedSrpSetup> {
    let login_sub_key = kdf::derive_login_key(&crypto::Key::try_from_slice(kek)?);
    generate_srp_setup_with_login_key(&login_sub_key, srp_user_id)
}

/// Generate the SRP setup payload from an already-derived login key.
pub fn generate_srp_setup_with_login_key(
    login_key: &[u8],
    srp_user_id: &str,
) -> Result<GeneratedSrpSetup> {
    if login_key.len() != 16 {
        return Err(AuthError::InvalidKey(format!(
            "Login key must be 16 bytes, got {}",
            login_key.len()
        )));
    }

    let srp_salt = Salt::generate().as_bytes().to_vec();
    let client = ClientG4096::<Sha256>::new();
    let srp_verifier = client.compute_verifier(srp_user_id.as_bytes(), login_key, &srp_salt);

    Ok(GeneratedSrpSetup {
        srp_salt,
        srp_verifier,
        login_sub_key: SecretVec::new(login_key.to_vec()),
    })
}

/// Decrypt only the master key and secret key.
///
/// Use this when you only need access to the decrypted keys (e.g. when the
/// auth token comes from a different source than a sealed box).
pub fn decrypt_keys_only(kek: &[u8], key_attrs: &KeyAttributes) -> Result<(SecretVec, SecretVec)> {
    let encrypted_key = crypto::decode_b64(&key_attrs.encrypted_key)
        .map_err(|e| AuthError::Decode(format!("encrypted_key: {}", e)))?;
    let key_nonce = crypto::decode_b64(&key_attrs.key_decryption_nonce)
        .map_err(|e| AuthError::Decode(format!("key_decryption_nonce: {}", e)))?;

    let master_key = SecretVec::new(
        secretbox::decrypt(
            &encrypted_key,
            &crypto::Nonce::try_from_slice(&key_nonce)?,
            &crypto::Key::try_from_slice(kek)?,
        )
        .map_err(|_| AuthError::IncorrectPassword)?,
    );

    let encrypted_secret_key = crypto::decode_b64(&key_attrs.encrypted_secret_key)
        .map_err(|e| AuthError::Decode(format!("encrypted_secret_key: {}", e)))?;
    let secret_key_nonce = crypto::decode_b64(&key_attrs.secret_key_decryption_nonce)
        .map_err(|e| AuthError::Decode(format!("secret_key_decryption_nonce: {}", e)))?;

    let secret_key = SecretVec::new(
        secretbox::decrypt(
            &encrypted_secret_key,
            &crypto::Nonce::try_from_slice(&secret_key_nonce)?,
            &crypto::Key::try_from_slice(&master_key)?,
        )
        .map_err(|_| AuthError::InvalidKeyAttributes)?,
    );

    Ok((master_key, secret_key))
}

/// Decrypt secrets after successful authentication.
///
/// Call this after SRP + 2FA is complete, when you have the key attributes
/// and encrypted token from the server.
///
/// # Arguments
/// * `kek` - Key encryption key (from `derive_srp_credentials` or `derive_kek`)
/// * `key_attrs` - Key attributes from the server
/// * `encrypted_token` - Base64-encoded encrypted authentication token
///
/// # Returns
/// * `DecryptedSecrets` containing master_key, secret_key, and token
pub fn decrypt_secrets(
    kek: &[u8],
    key_attrs: &KeyAttributes,
    encrypted_token: &str,
) -> Result<DecryptedSecrets> {
    let (master_key, secret_key) = decrypt_keys_only(kek, key_attrs)?;

    // Decrypt token with sealed box (public key crypto)
    let public_key = crypto::decode_b64(&key_attrs.public_key)
        .map_err(|e| AuthError::Decode(format!("public_key: {}", e)))?;
    let sealed_token = crypto::decode_b64(encrypted_token)
        .map_err(|e| AuthError::Decode(format!("encrypted_token: {}", e)))?;

    let token = sealed::open(
        &sealed_token,
        &crypto::PublicKey::try_from_slice(&public_key)?,
        &crypto::SecretKey::try_from_slice(&secret_key)?,
    )
    .map_err(|_| AuthError::InvalidKeyAttributes)?;

    Ok(DecryptedSecrets {
        master_key,
        secret_key,
        token: SecretVec::new(token),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::auth::{KeyDerivationStrength, generate_keys_with_strength};

    #[test]
    fn test_derive_srp_credentials() {
        let password = "test_password";
        let gen_result =
            generate_keys_with_strength(password, KeyDerivationStrength::Interactive).unwrap();

        let srp_attrs = SrpAttributes {
            srp_user_id: uuid::Uuid::nil(),
            srp_salt: crypto::encode_b64(&[0u8; 16]),
            mem_limit: gen_result.key_attributes.mem_limit,
            ops_limit: gen_result.key_attributes.ops_limit,
            kek_salt: gen_result.key_attributes.kek_salt.clone(),
            is_email_mfa_enabled: false,
        };

        let creds = derive_srp_credentials(password, &srp_attrs).unwrap();

        assert_eq!(creds.kek.len(), 32);
        assert_eq!(creds.login_key.len(), 16);
        assert_eq!(creds.login_key.as_ref(), gen_result.login_key.as_ref());
    }

    #[test]
    fn test_decrypt_secrets_roundtrip() {
        let password = "test_password";
        let gen_result =
            generate_keys_with_strength(password, KeyDerivationStrength::Interactive).unwrap();

        // Create a sealed token
        let token = b"auth_token_12345";
        let public_key = crypto::decode_b64(&gen_result.key_attributes.public_key).unwrap();
        let sealed_token = sealed::seal(
            token,
            &crypto::PublicKey::try_from_slice(&public_key).unwrap(),
        )
        .unwrap();
        let encrypted_token = crypto::encode_b64(&sealed_token);

        // Derive KEK
        let kek = derive_kek(
            password,
            &gen_result.key_attributes.kek_salt,
            gen_result.key_attributes.mem_limit,
            gen_result.key_attributes.ops_limit,
        )
        .unwrap();

        // Decrypt secrets
        let secrets = decrypt_secrets(&kek, &gen_result.key_attributes, &encrypted_token).unwrap();

        // Verify
        let original_master_key =
            crypto::decode_b64(&gen_result.private_key_attributes.key).unwrap();
        assert_eq!(secrets.master_key.as_ref(), original_master_key.as_slice());

        let original_secret_key =
            crypto::decode_b64(&gen_result.private_key_attributes.secret_key).unwrap();
        assert_eq!(secrets.secret_key.as_ref(), original_secret_key.as_slice());

        assert_eq!(secrets.token.as_ref(), token);
    }

    #[test]
    fn test_wrong_password_fails() {
        let gen_result =
            generate_keys_with_strength("correct_password", KeyDerivationStrength::Interactive)
                .unwrap();

        let public_key = crypto::decode_b64(&gen_result.key_attributes.public_key).unwrap();
        let sealed_token = sealed::seal(
            b"token",
            &crypto::PublicKey::try_from_slice(&public_key).unwrap(),
        )
        .unwrap();
        let encrypted_token = crypto::encode_b64(&sealed_token);

        // Derive KEK with wrong password
        let kek = derive_kek(
            "wrong_password",
            &gen_result.key_attributes.kek_salt,
            gen_result.key_attributes.mem_limit,
            gen_result.key_attributes.ops_limit,
        )
        .unwrap();

        // Decryption should fail
        let result = decrypt_secrets(&kek, &gen_result.key_attributes, &encrypted_token);
        assert!(matches!(result, Err(AuthError::IncorrectPassword)));
    }

    #[test]
    fn test_generated_kek_debug_redacts_secret_material() {
        let generated = GeneratedKek {
            key: SecretVec::new(vec![1, 2, 3]),
            salt: vec![4, 5, 6],
            mem_limit: 123,
            ops_limit: 456,
        };

        let debug = format!("{generated:?}");
        assert!(debug.contains("[REDACTED]"));
        assert!(!debug.contains("[1, 2, 3]"));
        assert!(debug.contains("salt_len"));
    }

    #[test]
    fn test_generate_interactive_kek() {
        let generated = generate_interactive_kek("test_password").unwrap();

        assert_eq!(generated.key.len(), 32);
        assert_eq!(generated.salt.len(), 16);
        assert_eq!(generated.mem_limit, argon::Params::INTERACTIVE.mem_limit);
        assert_eq!(generated.ops_limit, argon::Params::INTERACTIVE.ops_limit);
    }

    #[test]
    fn test_generate_srp_setup() {
        let srp_setup = generate_srp_setup(&[1; 32], "test-user-id").unwrap();

        assert_eq!(srp_setup.srp_salt.len(), 16);
        assert_eq!(srp_setup.login_sub_key.len(), 16);
        assert!(!srp_setup.srp_verifier.is_empty());
    }

    #[test]
    fn test_generate_srp_setup_with_login_key() {
        let login_key = [1u8; 16];
        let srp_setup = generate_srp_setup_with_login_key(&login_key, "test-user-id").unwrap();

        assert_eq!(srp_setup.srp_salt.len(), 16);
        assert_eq!(srp_setup.login_sub_key.as_ref(), login_key);
        assert!(!srp_setup.srp_verifier.is_empty());
    }
}
