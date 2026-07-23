//! Account recovery using recovery key.

use bip39::{Language, Mnemonic};

use crate::crypto::{self, SecretVec, sealed, secretbox};

use super::{AuthError, KeyAttributes, LoginResult, Result};

/// Recover account using recovery key.
///
/// The recovery key should be provided as a hex string (64 characters).
pub fn recover_with_key(
    recovery_key_hex: &str,
    attributes: &KeyAttributes,
    encrypted_token: &str,
) -> Result<LoginResult> {
    let recovery_key = SecretVec::new(
        crypto::decode_hex(recovery_key_hex)
            .map_err(|e| AuthError::Decode(format!("recovery_key: {}", e)))?,
    );

    if recovery_key.len() != 32 {
        return Err(AuthError::IncorrectRecoveryKey);
    }

    let encrypted_master_key = attributes
        .master_key_encrypted_with_recovery_key
        .as_ref()
        .ok_or(AuthError::MissingField(
            "master_key_encrypted_with_recovery_key",
        ))?;

    let master_key_nonce = attributes
        .master_key_decryption_nonce
        .as_ref()
        .ok_or(AuthError::MissingField("master_key_decryption_nonce"))?;

    let encrypted_master_key_bytes = crypto::decode_b64(encrypted_master_key)
        .map_err(|e| AuthError::Decode(format!("master_key_encrypted_with_recovery_key: {}", e)))?;
    let master_key_nonce_bytes = crypto::decode_b64(master_key_nonce)
        .map_err(|e| AuthError::Decode(format!("master_key_decryption_nonce: {}", e)))?;

    let master_key = SecretVec::new(
        secretbox::decrypt(
            &encrypted_master_key_bytes,
            &crypto::Nonce::try_from_slice(&master_key_nonce_bytes)?,
            &crypto::Key::try_from_slice(&recovery_key)?,
        )
        .map_err(|_| AuthError::IncorrectRecoveryKey)?,
    );

    let encrypted_secret_key = crypto::decode_b64(&attributes.encrypted_secret_key)
        .map_err(|e| AuthError::Decode(format!("encrypted_secret_key: {}", e)))?;
    let secret_key_nonce = crypto::decode_b64(&attributes.secret_key_decryption_nonce)
        .map_err(|e| AuthError::Decode(format!("secret_key_decryption_nonce: {}", e)))?;

    let secret_key = SecretVec::new(
        secretbox::decrypt(
            &encrypted_secret_key,
            &crypto::Nonce::try_from_slice(&secret_key_nonce)?,
            &crypto::Key::try_from_slice(&master_key)?,
        )
        .map_err(|_| AuthError::InvalidKeyAttributes)?,
    );

    let public_key = crypto::decode_b64(&attributes.public_key)
        .map_err(|e| AuthError::Decode(format!("public_key: {}", e)))?;
    let sealed_token = crypto::decode_b64(encrypted_token)
        .map_err(|e| AuthError::Decode(format!("encrypted_token: {}", e)))?;

    let token = SecretVec::new(
        sealed::open(
            &sealed_token,
            &crypto::PublicKey::try_from_slice(&public_key)?,
            &crypto::SecretKey::try_from_slice(&secret_key)?,
        )
        .map_err(|_| AuthError::InvalidKeyAttributes)?,
    );

    Ok(LoginResult {
        master_key,
        secret_key,
        token,
        key_encryption_key: SecretVec::new(Vec::new()),
    })
}

/// Get the recovery key from stored encrypted form.
pub fn get_recovery_key(master_key: &[u8], attributes: &KeyAttributes) -> Result<String> {
    let encrypted_recovery_key = attributes
        .recovery_key_encrypted_with_master_key
        .as_ref()
        .ok_or(AuthError::MissingField(
            "recovery_key_encrypted_with_master_key",
        ))?;

    let nonce = attributes
        .recovery_key_decryption_nonce
        .as_ref()
        .ok_or(AuthError::MissingField("recovery_key_decryption_nonce"))?;

    let encrypted_bytes = crypto::decode_b64(encrypted_recovery_key)
        .map_err(|e| AuthError::Decode(format!("recovery_key_encrypted_with_master_key: {}", e)))?;
    let nonce_bytes = crypto::decode_b64(nonce)
        .map_err(|e| AuthError::Decode(format!("recovery_key_decryption_nonce: {}", e)))?;

    let recovery_key = SecretVec::new(
        secretbox::decrypt(
            &encrypted_bytes,
            &crypto::Nonce::try_from_slice(&nonce_bytes)?,
            &crypto::Key::try_from_slice(master_key)?,
        )
        .map_err(|_| AuthError::InvalidKeyAttributes)?,
    );

    Ok(crypto::encode_hex(&recovery_key))
}

/// Convert a user-provided recovery key mnemonic or hex string into raw bytes.
///
/// The mnemonic form must be a 24-word English BIP-39 phrase. The legacy hex
/// form is still accepted for compatibility.
pub fn recovery_key_from_mnemonic_or_hex(recovery_key_mnemonic_or_hex: &str) -> Result<SecretVec> {
    let trimmed_input = recovery_key_mnemonic_or_hex
        .split_whitespace()
        .map(str::trim)
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join(" ");

    let recovery_key = SecretVec::new(if trimmed_input.contains(' ') {
        if trimmed_input.split(' ').count() != 24 {
            return Err(AuthError::IncorrectRecoveryKey);
        }

        let mnemonic = Mnemonic::parse_in_normalized(Language::English, &trimmed_input)
            .map_err(|_| AuthError::IncorrectRecoveryKey)?;
        mnemonic.to_entropy()
    } else {
        crypto::decode_hex(&trimmed_input).map_err(|_| AuthError::IncorrectRecoveryKey)?
    });

    if recovery_key.len() != 32 {
        return Err(AuthError::IncorrectRecoveryKey);
    }

    Ok(recovery_key)
}

/// Convert a base64-encoded recovery key into its 24-word English mnemonic.
pub fn recovery_key_to_mnemonic(recovery_key_b64: &str) -> Result<String> {
    let recovery_key = SecretVec::new(
        crypto::decode_b64(recovery_key_b64)
            .map_err(|e| AuthError::Decode(format!("recovery_key: {}", e)))?,
    );

    if recovery_key.len() != 32 {
        return Err(AuthError::IncorrectRecoveryKey);
    }

    Mnemonic::from_entropy_in(Language::English, &recovery_key)
        .map(|mnemonic| mnemonic.to_string())
        .map_err(|e| AuthError::InvalidKey(format!("recovery_key: {}", e)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::auth::{KeyDerivationStrength, generate_keys_with_strength};
    use crate::crypto::Key;

    fn generate_test_keys(password: &str) -> super::super::KeyGenResult {
        generate_keys_with_strength(password, KeyDerivationStrength::Interactive).unwrap()
    }

    fn create_sealed_token(token: &[u8], public_key: &[u8]) -> String {
        let pk = crypto::PublicKey::try_from_slice(public_key).unwrap();
        let sealed = sealed::seal(token, &pk).unwrap();
        crypto::encode_b64(&sealed)
    }

    #[test]
    fn test_recovery_roundtrip() {
        let gen_result = generate_test_keys("original_password");
        let public_key = crypto::decode_b64(&gen_result.key_attributes.public_key).unwrap();
        let encrypted_token = create_sealed_token(b"my_token", &public_key);

        let recovery_result = recover_with_key(
            &gen_result.private_key_attributes.recovery_key,
            &gen_result.key_attributes,
            &encrypted_token,
        )
        .unwrap();

        let expected_master = crypto::decode_b64(&gen_result.private_key_attributes.key).unwrap();
        assert_eq!(
            recovery_result.master_key.as_ref(),
            expected_master.as_slice()
        );
        assert_eq!(recovery_result.token.as_ref(), b"my_token");
    }

    #[test]
    fn test_wrong_recovery_key() {
        let gen_result = generate_test_keys("password");
        let public_key = crypto::decode_b64(&gen_result.key_attributes.public_key).unwrap();
        let encrypted_token = create_sealed_token(b"token", &public_key);

        let wrong_key = crypto::encode_hex(Key::generate().as_bytes());
        let result = recover_with_key(&wrong_key, &gen_result.key_attributes, &encrypted_token);
        assert!(matches!(result, Err(AuthError::IncorrectRecoveryKey)));
    }

    #[test]
    fn test_get_recovery_key() {
        let gen_result = generate_test_keys("password");
        let master_key = crypto::decode_b64(&gen_result.private_key_attributes.key).unwrap();

        let recovered = get_recovery_key(&master_key, &gen_result.key_attributes).unwrap();
        assert_eq!(
            recovered,
            gen_result.private_key_attributes.recovery_key.as_ref()
        );
    }

    #[test]
    fn test_recovery_key_mnemonic_roundtrip() {
        let gen_result = generate_test_keys("password");
        let master_key = crypto::decode_b64(&gen_result.private_key_attributes.key).unwrap();
        let recovery_key_hex = get_recovery_key(&master_key, &gen_result.key_attributes).unwrap();
        let recovery_key_b64 = crypto::encode_b64(&crypto::decode_hex(&recovery_key_hex).unwrap());

        let mnemonic = recovery_key_to_mnemonic(&recovery_key_b64).unwrap();
        let decoded = recovery_key_from_mnemonic_or_hex(&mnemonic).unwrap();

        assert_eq!(
            decoded.as_ref(),
            crypto::decode_hex(&recovery_key_hex).unwrap().as_slice()
        );
    }

    #[test]
    fn test_recovery_key_from_hex_accepts_legacy_format() {
        let gen_result = generate_test_keys("password");
        let decoded =
            recovery_key_from_mnemonic_or_hex(&gen_result.private_key_attributes.recovery_key)
                .unwrap();

        assert_eq!(
            decoded.as_ref(),
            crypto::decode_hex(&gen_result.private_key_attributes.recovery_key)
                .unwrap()
                .as_slice()
        );
    }
}
