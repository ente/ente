//! Account recovery using recovery key.

use bip39::{Language, Mnemonic};

use ente_core::b64;
use ente_core::crypto::{self, SecretVec, secretbox};

use super::{Error, KeyAttributes, Result};

/// Get the recovery key from stored encrypted form.
pub fn get_recovery_key(master_key: &[u8], attributes: &KeyAttributes) -> Result<String> {
    let encrypted_recovery_key = attributes
        .recovery_key_encrypted_with_master_key
        .as_ref()
        .ok_or(Error::MissingField(
            "recovery_key_encrypted_with_master_key",
        ))?;

    let nonce = attributes
        .recovery_key_decryption_nonce
        .as_ref()
        .ok_or(Error::MissingField("recovery_key_decryption_nonce"))?;

    let encrypted_bytes = b64::decode(encrypted_recovery_key)
        .map_err(|e| Error::Decode(format!("recovery_key_encrypted_with_master_key: {}", e)))?;
    let nonce_bytes = b64::decode(nonce)
        .map_err(|e| Error::Decode(format!("recovery_key_decryption_nonce: {}", e)))?;

    let recovery_key = SecretVec::new(
        secretbox::decrypt(
            &encrypted_bytes,
            &crypto::Nonce::try_from_slice(&nonce_bytes)?,
            &crypto::Key::try_from_slice(master_key)?,
        )
        .map_err(|_| Error::InvalidKeyAttributes)?,
    );

    Ok(hex::encode(&recovery_key))
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
            return Err(Error::IncorrectRecoveryKey);
        }

        let mnemonic = Mnemonic::parse_in_normalized(Language::English, &trimmed_input)
            .map_err(|_| Error::IncorrectRecoveryKey)?;
        mnemonic.to_entropy()
    } else {
        hex::decode(&trimmed_input).map_err(|_| Error::IncorrectRecoveryKey)?
    });

    if recovery_key.len() != 32 {
        return Err(Error::IncorrectRecoveryKey);
    }

    Ok(recovery_key)
}

/// Convert a base64-encoded recovery key into its 24-word English mnemonic.
pub fn recovery_key_to_mnemonic(recovery_key_b64: &str) -> Result<String> {
    let recovery_key = SecretVec::new(
        b64::decode(recovery_key_b64).map_err(|e| Error::Decode(format!("recovery_key: {}", e)))?,
    );

    if recovery_key.len() != 32 {
        return Err(Error::IncorrectRecoveryKey);
    }

    Mnemonic::from_entropy_in(Language::English, &recovery_key)
        .map(|mnemonic| mnemonic.to_string())
        .map_err(|e| Error::InvalidKey(format!("recovery_key: {}", e)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::auth::{KeyDerivationStrength, generate_keys_with_strength};

    fn generate_test_keys(password: &str) -> super::super::KeyGenResult {
        generate_keys_with_strength(password, KeyDerivationStrength::Interactive).unwrap()
    }

    #[test]
    fn test_get_recovery_key() {
        let gen_result = generate_test_keys("password");
        let master_key = b64::decode(&gen_result.private_key_attributes.key).unwrap();

        let recovered = get_recovery_key(&master_key, &gen_result.key_attributes).unwrap();
        assert_eq!(
            recovered,
            gen_result.private_key_attributes.recovery_key.as_ref()
        );
    }

    #[test]
    fn test_recovery_key_mnemonic_roundtrip() {
        let gen_result = generate_test_keys("password");
        let master_key = b64::decode(&gen_result.private_key_attributes.key).unwrap();
        let recovery_key_hex = get_recovery_key(&master_key, &gen_result.key_attributes).unwrap();
        let recovery_key_b64 = b64::encode(&hex::decode(&recovery_key_hex).unwrap());

        let mnemonic = recovery_key_to_mnemonic(&recovery_key_b64).unwrap();
        let decoded = recovery_key_from_mnemonic_or_hex(&mnemonic).unwrap();

        assert_eq!(
            decoded.as_ref(),
            hex::decode(&recovery_key_hex).unwrap().as_slice()
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
            hex::decode(&*gen_result.private_key_attributes.recovery_key)
                .unwrap()
                .as_slice()
        );
    }
}
