use crate::db::Result;

pub fn encrypt_blob(plaintext: &[u8], key: &[u8]) -> Result<Vec<u8>> {
    ente_ensu_crypto::encrypt_blob(plaintext, key).map_err(Into::into)
}

pub fn decrypt_blob(data: &[u8], key: &[u8]) -> Result<Vec<u8>> {
    ente_ensu_crypto::decrypt_blob(data, key).map_err(Into::into)
}

pub fn encrypt_string(value: &str, key: &[u8]) -> Result<Vec<u8>> {
    ente_ensu_crypto::encrypt_string(value, key).map_err(Into::into)
}

pub fn decrypt_string(data: &[u8], key: &[u8]) -> Result<String> {
    ente_ensu_crypto::decrypt_string(data, key).map_err(Into::into)
}

pub fn encrypt_json_field(value: &str, key: &[u8]) -> Result<String> {
    ente_ensu_crypto::encrypt_json_field(value, key).map_err(Into::into)
}

pub fn decrypt_json_field(value: &str, key: &[u8]) -> Result<String> {
    ente_ensu_crypto::decrypt_json_field(value, key).map_err(Into::into)
}

#[cfg(test)]
mod tests {
    use super::*;
    use ente_core::crypto::Key;

    #[test]
    fn blob_roundtrip() {
        let key = vec![7u8; Key::BYTES];
        let plaintext = b"hello";

        let encrypted = encrypt_blob(plaintext, &key).unwrap();
        assert!(encrypted.len() > plaintext.len());

        let decrypted = decrypt_blob(&encrypted, &key).unwrap();
        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn json_field_roundtrip() {
        let key = vec![9u8; Key::BYTES];
        let plaintext = "file-name.png";

        let encrypted = encrypt_json_field(plaintext, &key).unwrap();
        assert!(encrypted.starts_with("enc:v1:"));

        let decrypted = decrypt_json_field(&encrypted, &key).unwrap();
        assert_eq!(decrypted, plaintext);
    }
}
