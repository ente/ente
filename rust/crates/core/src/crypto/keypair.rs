use crate::crypto::{Error, Key, PublicKey, Result, SecretKey, secretbox::EncryptedBox};

impl SecretKey {
    pub fn open(
        encrypted_secret_key: &EncryptedBox,
        master_key: &Key,
        expected_public_key: &PublicKey,
    ) -> Result<Self> {
        let secret_key = Self::try_from_slice(&encrypted_secret_key.decrypt(master_key)?)?;
        if secret_key.public_key() != *expected_public_key {
            return Err(Error::KeyPairMismatch);
        }
        Ok(secret_key)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::secretbox;

    #[test]
    fn opens_and_validates_secret_key() {
        let master_key = Key::generate();
        let secret_key = SecretKey::generate();
        let encrypted_secret_key = secretbox::encrypt(secret_key.as_bytes(), &master_key);

        let opened =
            SecretKey::open(&encrypted_secret_key, &master_key, &secret_key.public_key()).unwrap();
        assert_eq!(opened, secret_key);

        let wrong_public_key = SecretKey::generate().public_key();
        assert!(matches!(
            SecretKey::open(&encrypted_secret_key, &master_key, &wrong_public_key),
            Err(Error::KeyPairMismatch)
        ));
    }
}
