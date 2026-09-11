use bip39::{Language, Mnemonic};

use ente_core::b64;
use ente_core::crypto::{self, Key, SecretVec, secretbox};

use super::KeyAttributes;
use crate::error::{Error, Result};

pub fn get_recovery_key(master_key: &Key, attributes: &KeyAttributes) -> Result<String> {
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
        .map_err(|e| Error::Decode(format!("recovery_key_encrypted_with_master_key: {e}")))?;
    let nonce_bytes = b64::decode(nonce)
        .map_err(|e| Error::Decode(format!("recovery_key_decryption_nonce: {e}")))?;

    let recovery_key = SecretVec::new(
        secretbox::decrypt(
            &encrypted_bytes,
            &crypto::Nonce::try_from_slice(&nonce_bytes)?,
            master_key,
        )
        .map_err(|_| Error::InvalidKeyAttributes)?,
    );

    Ok(hex::encode(&recovery_key))
}

// Accept 24-word English BIP-39 mnemonics and legacy hex recovery keys.
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

pub fn recovery_key_to_mnemonic(recovery_key: &[u8]) -> Result<String> {
    if recovery_key.len() != 32 {
        return Err(Error::IncorrectRecoveryKey);
    }

    Mnemonic::from_entropy_in(Language::English, recovery_key)
        .map(|mnemonic| mnemonic.to_string())
        .map_err(|e| Error::InvalidKey(format!("recovery_key: {e}")))
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
        let master_key =
            Key::try_from_slice(&b64::decode(&gen_result.private_key_attributes.key).unwrap())
                .unwrap();

        let recovered = get_recovery_key(&master_key, &gen_result.key_attributes).unwrap();
        assert_eq!(
            recovered,
            gen_result.private_key_attributes.recovery_key.as_ref()
        );
    }

    #[test]
    fn test_recovery_key_mnemonic_roundtrip() {
        let gen_result = generate_test_keys("password");
        let master_key =
            Key::try_from_slice(&b64::decode(&gen_result.private_key_attributes.key).unwrap())
                .unwrap();
        let recovery_key_hex = get_recovery_key(&master_key, &gen_result.key_attributes).unwrap();
        let recovery_key = hex::decode(&recovery_key_hex).unwrap();

        let mnemonic = recovery_key_to_mnemonic(&recovery_key).unwrap();
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
