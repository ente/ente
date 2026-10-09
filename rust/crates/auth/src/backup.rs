use ente_core::{
    b64,
    crypto::{Header, Salt, argon, blob},
};
use serde::{Deserialize, Serialize};
use zeroize::Zeroizing;

use crate::{Error, Result};

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct Backup {
    version: u32,
    kdf_params: KdfParams,
    encrypted_data: String,
    encryption_nonce: String,
}

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct KdfParams {
    mem_limit: u32,
    ops_limit: u32,
    salt: String,
}

fn validate_params(params: argon::Params) -> Result<()> {
    params.validate()?;
    let strength = u64::from(params.mem_limit) * u64::from(params.ops_limit);
    if params.mem_limit > argon::Params::SENSITIVE.mem_limit || strength > 1_u64 << 32 {
        return Err(Error::UnsafeKdf);
    }
    Ok(())
}

pub fn encrypt(plaintext: &[u8], password: &str) -> Result<Vec<u8>> {
    let derived = argon::derive_sensitive_key(password)?;
    let encrypted = blob::encrypt(plaintext, &derived.key)?;
    serde_json::to_vec(&Backup {
        version: 1,
        kdf_params: KdfParams {
            mem_limit: derived.params.mem_limit,
            ops_limit: derived.params.ops_limit,
            salt: b64::encode(derived.salt.as_bytes()),
        },
        encrypted_data: b64::encode(&encrypted.encrypted_data),
        encryption_nonce: b64::encode(encrypted.decryption_header.as_bytes()),
    })
    .map_err(|_| Error::InvalidBackup)
}

pub fn decrypt(input: &[u8], password: &str) -> Result<Zeroizing<Vec<u8>>> {
    let backup: Backup = serde_json::from_slice(input).map_err(|_| Error::InvalidBackup)?;
    if backup.version != 1 {
        return Err(Error::UnsupportedVersion);
    }
    let params = argon::Params {
        mem_limit: backup.kdf_params.mem_limit,
        ops_limit: backup.kdf_params.ops_limit,
    };
    validate_params(params)?;
    let salt = Salt::try_from_slice(&b64::decode(&backup.kdf_params.salt)?)?;
    let header = Header::try_from_slice(&b64::decode(&backup.encryption_nonce)?)?;
    let encrypted = b64::decode(&backup.encrypted_data)?;
    if encrypted.len() < blob::ABYTES {
        return Err(Error::InvalidBackup);
    }
    let key = argon::derive_key(password, &salt, params)?;
    Ok(Zeroizing::new(blob::decrypt_legacy(
        &encrypted, &header, &key,
    )?))
}

#[cfg(test)]
mod tests {
    use super::*;
    use ente_core::crypto::stream::Encryptor;

    #[test]
    fn admits_existing_producer_profiles_without_deriving_keys() {
        let mut memory = 1 << 30;
        let mut operations = 4;
        while memory >= 8192 {
            assert!(
                validate_params(argon::Params {
                    mem_limit: memory,
                    ops_limit: operations
                })
                .is_ok()
            );
            memory /= 2;
            operations *= 2;
        }
        for (memory, operations) in [
            (8191, 1),
            (8193, 1),
            (8192, 0),
            (1 << 30, 5),
            ((1 << 30) + 1024, 1),
            (8192, u32::MAX),
        ] {
            assert!(
                validate_params(argon::Params {
                    mem_limit: memory,
                    ops_limit: operations
                })
                .is_err()
            );
        }
    }

    #[test]
    fn decryption_authenticates_legacy_bytes_without_interpreting_them() {
        let password = "  preserve whitespace  ";
        let salt = Salt::generate();
        let key = argon::derive_key(password, &salt, argon::Params::MIN).unwrap();
        let bytes = b"\xff\0original\r\nbytes without final newline";
        let mut stream = Encryptor::new(&key);
        let encrypted = stream.push(bytes, false).unwrap();
        let mut backup = Backup {
            version: 1,
            kdf_params: KdfParams {
                mem_limit: 8192,
                ops_limit: 1,
                salt: b64::encode(salt.as_bytes()),
            },
            encrypted_data: b64::encode(&encrypted),
            encryption_nonce: b64::encode(stream.header().as_bytes()),
        };
        let encoded = serde_json::to_vec(&backup).unwrap();
        assert_eq!(decrypt(&encoded, password).unwrap().as_slice(), bytes);
        assert!(decrypt(&encoded, "wrong").is_err());
        let mut damaged = encrypted;
        damaged[0] ^= 1;
        backup.encrypted_data = b64::encode(&damaged);
        assert!(decrypt(&serde_json::to_vec(&backup).unwrap(), password).is_err());
        backup.version = 2;
        assert!(matches!(
            decrypt(&serde_json::to_vec(&backup).unwrap(), password),
            Err(Error::UnsupportedVersion)
        ));
        backup.version = 1;
        backup.encryption_nonce = b64::encode(&[0; 23]);
        assert!(decrypt(&serde_json::to_vec(&backup).unwrap(), password).is_err());
    }
}
