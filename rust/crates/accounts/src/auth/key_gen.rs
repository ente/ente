use ente_core::b64;
use ente_core::crypto::{self, Key, SecretString, SecretVec, argon, kdf, secretbox};

use super::{KeyAttributes, KeyGenResult, PrivateKeyAttributes};
use crate::error::Result;

#[derive(Debug, Clone, Copy, Default)]
pub enum KeyDerivationStrength {
    Interactive,
    #[default]
    Sensitive,
}

// Account APIs expect the nonce separately from the encrypted data.
fn encrypt_to_b64(plaintext: &[u8], key: &Key) -> Result<(String, String)> {
    let encrypted = secretbox::encrypt(plaintext, key);
    Ok((
        b64::encode(&encrypted.encrypted_data),
        b64::encode(encrypted.nonce.as_bytes()),
    ))
}

pub fn generate_keys_with_strength(
    password: &str,
    strength: KeyDerivationStrength,
) -> Result<KeyGenResult> {
    let master_key = Key::generate();
    let recovery_key = Key::generate();

    let (enc_master_with_recovery, nonce_master_recovery) =
        encrypt_to_b64(master_key.as_bytes(), &recovery_key)?;
    let (enc_recovery_with_master, nonce_recovery_master) =
        encrypt_to_b64(recovery_key.as_bytes(), &master_key)?;

    let derived = match strength {
        KeyDerivationStrength::Interactive => argon::derive_interactive_key(password)?,
        KeyDerivationStrength::Sensitive => argon::derive_sensitive_key(password)?,
    };
    let login_key = kdf::derive_login_key(&derived.key);

    let (enc_key, key_nonce) = encrypt_to_b64(master_key.as_bytes(), &derived.key)?;

    let secret_key = crypto::SecretKey::generate();
    let public_key = secret_key.public_key();

    let (enc_secret_key, secret_key_nonce) = encrypt_to_b64(secret_key.as_bytes(), &master_key)?;

    let key_attributes = KeyAttributes {
        kek_salt: b64::encode(derived.salt.as_bytes()),
        kek_hash: None,
        encrypted_key: enc_key,
        key_decryption_nonce: key_nonce,
        public_key: b64::encode(public_key.as_bytes()),
        encrypted_secret_key: enc_secret_key,
        secret_key_decryption_nonce: secret_key_nonce,
        mem_limit: derived.params.mem_limit,
        ops_limit: derived.params.ops_limit,
        master_key_encrypted_with_recovery_key: Some(enc_master_with_recovery),
        master_key_decryption_nonce: Some(nonce_master_recovery),
        recovery_key_encrypted_with_master_key: Some(enc_recovery_with_master),
        recovery_key_decryption_nonce: Some(nonce_recovery_master),
    };

    let private_key_attributes = PrivateKeyAttributes {
        key: SecretString::new(b64::encode(master_key.as_bytes())),
        recovery_key: SecretString::new(hex::encode(recovery_key.as_bytes())),
        secret_key: SecretString::new(b64::encode(secret_key.as_bytes())),
    };

    Ok(KeyGenResult {
        key_attributes,
        private_key_attributes,
        key_encryption_key: SecretVec::new(derived.key.as_bytes().to_vec()),
        login_key,
    })
}

pub fn generate_key_attributes_for_new_password(
    master_key: &[u8],
    existing_attributes: &KeyAttributes,
    password: &str,
) -> Result<(KeyAttributes, SecretVec)> {
    generate_key_attributes_for_new_password_with_strength(
        master_key,
        existing_attributes,
        password,
        KeyDerivationStrength::Sensitive,
    )
}

// Changing the password must not rotate the account or recovery keys.
pub fn generate_key_attributes_for_new_password_with_strength(
    master_key: &[u8],
    existing_attributes: &KeyAttributes,
    password: &str,
    strength: KeyDerivationStrength,
) -> Result<(KeyAttributes, SecretVec)> {
    let derived = match strength {
        KeyDerivationStrength::Interactive => argon::derive_interactive_key(password)?,
        KeyDerivationStrength::Sensitive => argon::derive_sensitive_key(password)?,
    };
    let login_key = kdf::derive_login_key(&derived.key);

    let (enc_key, key_nonce) = encrypt_to_b64(master_key, &derived.key)?;

    let key_attributes = KeyAttributes {
        kek_salt: b64::encode(derived.salt.as_bytes()),
        kek_hash: None,
        encrypted_key: enc_key,
        key_decryption_nonce: key_nonce,
        mem_limit: derived.params.mem_limit,
        ops_limit: derived.params.ops_limit,
        public_key: existing_attributes.public_key.clone(),
        encrypted_secret_key: existing_attributes.encrypted_secret_key.clone(),
        secret_key_decryption_nonce: existing_attributes.secret_key_decryption_nonce.clone(),
        master_key_encrypted_with_recovery_key: existing_attributes
            .master_key_encrypted_with_recovery_key
            .clone(),
        master_key_decryption_nonce: existing_attributes.master_key_decryption_nonce.clone(),
        recovery_key_encrypted_with_master_key: existing_attributes
            .recovery_key_encrypted_with_master_key
            .clone(),
        recovery_key_decryption_nonce: existing_attributes.recovery_key_decryption_nonce.clone(),
    };

    Ok((key_attributes, login_key))
}

pub fn create_new_recovery_key(
    master_key: &[u8],
) -> Result<(String, String, String, String, String)> {
    let recovery_key = Key::generate();
    let master_key_typed = Key::try_from_slice(master_key)?;

    let (enc_master, nonce_master) = encrypt_to_b64(master_key, &recovery_key)?;
    let (enc_recovery, nonce_recovery) =
        encrypt_to_b64(recovery_key.as_bytes(), &master_key_typed)?;

    Ok((
        hex::encode(recovery_key.as_bytes()),
        enc_master,
        nonce_master,
        enc_recovery,
        nonce_recovery,
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use ente_core::crypto::Nonce;

    fn decrypt_raw(data: &[u8], nonce: &[u8], key: &[u8]) -> Vec<u8> {
        secretbox::decrypt(
            data,
            &Nonce::try_from_slice(nonce).unwrap(),
            &Key::try_from_slice(key).unwrap(),
        )
        .unwrap()
    }

    fn generate_test_keys(password: &str) -> Result<KeyGenResult> {
        generate_keys_with_strength(password, KeyDerivationStrength::Interactive)
    }

    #[test]
    fn test_generate_keys_recovery_key_can_decrypt_master() {
        let result = generate_test_keys("password").unwrap();
        let recovery_key = hex::decode(&*result.private_key_attributes.recovery_key).unwrap();

        let encrypted = b64::decode(
            result
                .key_attributes
                .master_key_encrypted_with_recovery_key
                .as_ref()
                .unwrap(),
        )
        .unwrap();
        let nonce = b64::decode(
            result
                .key_attributes
                .master_key_decryption_nonce
                .as_ref()
                .unwrap(),
        )
        .unwrap();
        let decrypted = decrypt_raw(&encrypted, &nonce, &recovery_key);

        let original = b64::decode(&result.private_key_attributes.key).unwrap();
        assert_eq!(decrypted, original);
    }

    #[test]
    fn test_generate_keys_master_can_decrypt_recovery() {
        let result = generate_test_keys("password").unwrap();
        let master_key = b64::decode(&result.private_key_attributes.key).unwrap();

        let encrypted = b64::decode(
            result
                .key_attributes
                .recovery_key_encrypted_with_master_key
                .as_ref()
                .unwrap(),
        )
        .unwrap();
        let nonce = b64::decode(
            result
                .key_attributes
                .recovery_key_decryption_nonce
                .as_ref()
                .unwrap(),
        )
        .unwrap();
        let decrypted = decrypt_raw(&encrypted, &nonce, &master_key);

        let original = hex::decode(&*result.private_key_attributes.recovery_key).unwrap();
        assert_eq!(decrypted, original);
    }

    #[test]
    fn test_password_change() {
        let initial = generate_test_keys("old_password").unwrap();
        let master_key = b64::decode(&initial.private_key_attributes.key).unwrap();

        let (new_attrs, new_login_key) = generate_key_attributes_for_new_password_with_strength(
            &master_key,
            &initial.key_attributes,
            "new_password",
            KeyDerivationStrength::Interactive,
        )
        .unwrap();

        assert_ne!(new_attrs.kek_salt, initial.key_attributes.kek_salt);
        assert_ne!(new_login_key, initial.login_key);

        let kek_salt = b64::decode(&new_attrs.kek_salt).unwrap();
        let salt = crypto::Salt::try_from_slice(&kek_salt).unwrap();
        let kek = argon::derive_key(
            "new_password",
            &salt,
            argon::Params {
                mem_limit: new_attrs.mem_limit,
                ops_limit: new_attrs.ops_limit,
            },
        )
        .unwrap();
        let encrypted = b64::decode(&new_attrs.encrypted_key).unwrap();
        let nonce = b64::decode(&new_attrs.key_decryption_nonce).unwrap();
        let decrypted = decrypt_raw(&encrypted, &nonce, kek.as_bytes());
        assert_eq!(decrypted, master_key);
    }

    #[test]
    fn test_create_new_recovery_key() {
        let master_key = Key::generate().as_bytes().to_vec();
        let (recovery_hex, enc_master, nonce_master, enc_recovery, nonce_recovery) =
            create_new_recovery_key(&master_key).unwrap();

        assert_eq!(recovery_hex.len(), 64);

        let recovery_key = hex::decode(&recovery_hex).unwrap();
        let decrypted = decrypt_raw(
            &b64::decode(&enc_master).unwrap(),
            &b64::decode(&nonce_master).unwrap(),
            &recovery_key,
        );
        assert_eq!(decrypted, master_key);

        let decrypted_recovery = decrypt_raw(
            &b64::decode(&enc_recovery).unwrap(),
            &b64::decode(&nonce_recovery).unwrap(),
            &master_key,
        );
        assert_eq!(decrypted_recovery, recovery_key);
    }
}
