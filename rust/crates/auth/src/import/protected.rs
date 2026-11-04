use aes_gcm::{
    Aes256Gcm,
    aead::{Aead, KeyInit, Payload},
};
use argon2::{Algorithm as ArgonAlgorithm, Argon2, Params as ArgonParams, Version};
use ente_core::b64;
use hmac::{Hmac, Mac};
use pbkdf2::pbkdf2_hmac;
use serde_json::Value;
use sha1::Sha1;
use sha2::Sha256;
use subtle::ConstantTimeEq;
use zeroize::Zeroizing;

use super::{
    Batch, Display, Error, ImportedCode, Otp, Result, build_uri, optional_int, parse_aegis,
    parse_andotp, parse_proton, parse_two_fas, string,
};

const PROTON_AAD: &[u8] = b"proton.authenticator.export.v1";
const AEGIS_SCRYPT_LOG_N: u8 = 15;
const AEGIS_SCRYPT_N: u64 = 1 << AEGIS_SCRYPT_LOG_N;
const AEGIS_SCRYPT_R: u32 = 8;
const AEGIS_SCRYPT_P: u32 = 1;
const ANDOTP_MAX_ITERATIONS: u32 = 160_000;

pub fn import_aegis(input: &str, password: Option<&str>) -> Result<Batch> {
    let root: Value =
        serde_json::from_str(input).map_err(|_| Error::invalid("Invalid Aegis export"))?;
    let header = root
        .get("header")
        .and_then(Value::as_object)
        .ok_or_else(|| Error::invalid("Invalid Aegis export"))?;
    let database = if let Some(slots) = header.get("slots").filter(|value| !value.is_null()) {
        let password = password.ok_or_else(Error::password_required)?;
        let slots = slots
            .as_array()
            .ok_or_else(|| Error::invalid("Invalid Aegis key slots"))?;
        let mut master_key = None;
        for slot in slots {
            if slot.get("type").and_then(Value::as_i64) != Some(1) {
                continue;
            }
            let Some(key) = decrypt_aegis_slot(slot, password)? else {
                continue;
            };
            master_key = Some(key);
            break;
        }
        let master_key = master_key.ok_or_else(Error::incorrect_password)?;
        let params = header
            .get("params")
            .ok_or_else(|| Error::invalid("Invalid Aegis database parameters"))?;
        let nonce = decode_hex_field(params, "nonce")?;
        let tag = decode_hex_field(params, "tag")?;
        let mut encrypted = b64::decode(
            root.get("db")
                .and_then(Value::as_str)
                .ok_or_else(|| Error::invalid("Invalid Aegis database"))?,
        )
        .map_err(|_| Error::invalid("Invalid Aegis database"))?;
        encrypted.extend_from_slice(&tag);
        let plaintext = decrypt_gcm(&master_key, &nonce, &encrypted, &[])
            .map_err(|_| Error::incorrect_password())?;
        String::from_utf8(plaintext)
            .map_err(|_| Error::invalid("Invalid Aegis database contents"))?
    } else {
        serde_json::to_string(
            root.get("db")
                .ok_or_else(|| Error::invalid("Invalid Aegis database"))?,
        )
        .map_err(|_| Error::invalid("Invalid Aegis database"))?
    };
    parse_aegis(&database)
}

pub fn import_andotp(input: &[u8], password: Option<&str>) -> Result<Batch> {
    if let Ok(plaintext) = std::str::from_utf8(input)
        && serde_json::from_str::<Vec<Value>>(plaintext).is_ok()
    {
        return parse_andotp(plaintext);
    }
    let password = password.ok_or_else(Error::password_required)?;
    if input.len() < 28 {
        return Err(Error::invalid("Invalid andOTP encrypted file"));
    }
    let iterations = u32::from_be_bytes(
        input[..4]
            .try_into()
            .map_err(|_| Error::invalid("Invalid andOTP encrypted file"))?,
    );
    if iterations == 0 || iterations > ANDOTP_MAX_ITERATIONS {
        return Err(Error::invalid("Invalid andOTP iteration count"));
    }
    let salt = &input[4..16];
    let nonce = &input[16..28];
    let mut key = Zeroizing::new([0u8; 32]);
    pbkdf2_hmac::<Sha1>(password.as_bytes(), salt, iterations, key.as_mut());
    let plaintext = decrypt_gcm(key.as_ref(), nonce, &input[28..], &[])
        .map_err(|_| Error::incorrect_password())?;
    let plaintext = String::from_utf8(plaintext).map_err(|_| Error::incorrect_password())?;
    parse_andotp(&plaintext)
}

pub fn import_proton(input: &str, password: Option<&str>) -> Result<Batch> {
    let root: Value =
        serde_json::from_str(input).map_err(|_| Error::invalid("Invalid Proton export"))?;
    if root.get("version").and_then(Value::as_i64) != Some(1) {
        return Err(Error::invalid("Invalid Proton export"));
    }
    if root.get("entries").is_some() {
        return parse_proton(input);
    }
    let password = password.ok_or_else(Error::password_required)?;
    let salt = decode_b64_string(root.get("salt"), "Invalid Proton export salt")?;
    if salt.len() != 16 {
        return Err(Error::invalid("Invalid Proton export salt"));
    }
    let encrypted = decode_b64_string(root.get("content"), "Invalid Proton export content")?;
    if encrypted.len() <= 12 {
        return Err(Error::invalid("Invalid Proton export content"));
    }
    let key = derive_argon(password, &salt, 19 * 1024, 2, 1)?;
    let plaintext = decrypt_gcm(key.as_ref(), &encrypted[..12], &encrypted[12..], PROTON_AAD)
        .map_err(|_| Error::incorrect_password())?;
    let plaintext = String::from_utf8(plaintext).map_err(|_| Error::incorrect_password())?;
    parse_proton(&plaintext)
}

pub fn import_two_fas(input: &str, password: Option<&str>) -> Result<Batch> {
    if input.trim_start().starts_with("otpauth://") {
        return super::parse_plain_text(input);
    }
    let root: Value =
        serde_json::from_str(input).map_err(|_| Error::invalid("Invalid 2FAS export"))?;
    let version = root
        .get("schemaVersion")
        .and_then(Value::as_i64)
        .unwrap_or(0);
    if !matches!(version, 3 | 4) {
        return Err(Error::invalid(format!(
            "Unsupported 2FAS export version: {version}"
        )));
    }
    if root.get("reference").is_none() || root.get("reference") == Some(&Value::Null) {
        return parse_two_fas(input, None);
    }
    let password = password.ok_or_else(Error::password_required)?;
    let encrypted = root
        .get("servicesEncrypted")
        .and_then(Value::as_str)
        .ok_or_else(|| Error::invalid("Invalid 2FAS encrypted services"))?;
    let mut parts = encrypted.split(':');
    let ciphertext = decode_b64_part(parts.next())?;
    let salt = decode_b64_part(parts.next())?;
    let nonce = decode_b64_part(parts.next())?;
    if parts.next().is_some() {
        return Err(Error::invalid("Invalid 2FAS encrypted services"));
    }
    let mut key = Zeroizing::new([0u8; 32]);
    pbkdf2_hmac::<Sha256>(password.as_bytes(), &salt, 10_000, key.as_mut());
    let plaintext = decrypt_gcm(key.as_ref(), &nonce, &ciphertext, &[])
        .map_err(|_| Error::incorrect_password())?;
    let plaintext = String::from_utf8(plaintext).map_err(|_| Error::incorrect_password())?;
    parse_two_fas(input, Some(&plaintext))
}

struct OpenAuthenticatorExport {
    salt: Vec<u8>,
    signature: Vec<u8>,
    entries: Vec<Value>,
}

pub fn validate_open_authenticator(input: &str) -> Result<()> {
    parse_open_authenticator(input).map(|_| ())
}

fn parse_open_authenticator(input: &str) -> Result<OpenAuthenticatorExport> {
    let root: Value = serde_json::from_str(input)
        .map_err(|_| Error::invalid("Invalid Open Authenticator backup"))?;
    let root = root
        .as_object()
        .ok_or_else(|| Error::invalid("Invalid Open Authenticator backup"))?;
    let salt = decode_b64_string(
        root.get("salt"),
        "Invalid Open Authenticator salt or signature",
    )?;
    let signature = decode_b64_string(
        root.get("passwordSignature"),
        "Invalid Open Authenticator salt or signature",
    )?;
    if salt.len() != 32 || signature.len() != 32 {
        return Err(Error::invalid(
            "Invalid Open Authenticator salt or signature",
        ));
    }
    let entries = root
        .get("totps")
        .and_then(Value::as_array)
        .ok_or_else(|| Error::invalid("Invalid Open Authenticator backup"))?;
    Ok(OpenAuthenticatorExport {
        salt,
        signature,
        entries: entries.clone(),
    })
}

pub fn import_open_authenticator(input: &str, password: &str) -> Result<Batch> {
    let export = parse_open_authenticator(input)?;
    let key = derive_argon(password, &export.salt, 4096, 3, 8)?;
    let mut mac = <Hmac<Sha256> as hmac::KeyInit>::new_from_slice(key.as_ref())
        .map_err(|_| Error::invalid("Invalid Open Authenticator key"))?;
    mac.update(password.as_bytes());
    if !bool::from(mac.finalize().into_bytes().ct_eq(&export.signature)) {
        return Err(Error::incorrect_password());
    }
    let mut codes = Vec::with_capacity(export.entries.len());
    for entry in &export.entries {
        let code = decrypt_open_authenticator_entry(entry, key.as_ref())
            .map_err(|error| Error::entry(entry, error))?;
        codes.push(code);
    }
    Ok(Batch { codes, skipped: 0 })
}

fn decrypt_aegis_slot(slot: &Value, password: &str) -> Result<Option<Zeroizing<Vec<u8>>>> {
    let (Some(n), Some(r), Some(p)) = (
        slot.get("n").and_then(Value::as_u64),
        slot.get("r").and_then(Value::as_u64),
        slot.get("p").and_then(Value::as_u64),
    ) else {
        return Ok(None);
    };
    let (Ok(r), Ok(p)) = (u32::try_from(r), u32::try_from(p)) else {
        return Err(Error::invalid("Unsupported Aegis scrypt parameters"));
    };
    if (n, r, p) != (AEGIS_SCRYPT_N, AEGIS_SCRYPT_R, AEGIS_SCRYPT_P) {
        return Err(Error::invalid("Unsupported Aegis scrypt parameters"));
    }
    let params = scrypt::Params::new(AEGIS_SCRYPT_LOG_N, AEGIS_SCRYPT_R, AEGIS_SCRYPT_P)
        .map_err(|_| Error::invalid("Unsupported Aegis scrypt parameters"))?;
    let Some(salt) = slot
        .get("salt")
        .and_then(Value::as_str)
        .and_then(|salt| hex::decode(salt).ok())
    else {
        return Ok(None);
    };
    let mut key = Zeroizing::new([0u8; 32]);
    if scrypt::scrypt(password.as_bytes(), &salt, &params, key.as_mut()).is_err() {
        return Ok(None);
    }
    let Some(key_params) = slot.get("key_params") else {
        return Ok(None);
    };
    let Ok(nonce) = decode_hex_field(key_params, "nonce") else {
        return Ok(None);
    };
    let Ok(tag) = decode_hex_field(key_params, "tag") else {
        return Ok(None);
    };
    let Some(mut encrypted) = slot
        .get("key")
        .and_then(Value::as_str)
        .and_then(|key| hex::decode(key).ok())
    else {
        return Ok(None);
    };
    encrypted.extend_from_slice(&tag);
    Ok(decrypt_gcm(key.as_ref(), &nonce, &encrypted, &[])
        .ok()
        .map(Zeroizing::new))
}

fn decrypt_open_authenticator_entry(entry: &Value, key: &[u8]) -> Result<ImportedCode> {
    let object = entry
        .as_object()
        .ok_or_else(|| Error::invalid("Invalid Open Authenticator entry"))?;
    let secret = decrypt_json_field(
        key,
        object
            .get("secret")
            .ok_or_else(|| Error::invalid("Missing secret"))?,
    )?;
    let label = object
        .get("label")
        .map(|value| decrypt_json_field(key, value))
        .transpose()?
        .unwrap_or_default();
    let issuer = object
        .get("issuer")
        .map(|value| decrypt_json_field(key, value))
        .transpose()?
        .unwrap_or_default();
    let account = if label.is_empty() {
        string(object.get("uuid")).unwrap_or_default()
    } else {
        &label
    };
    let digits = match object.get("digits") {
        None => Some(6),
        Some(Value::Number(value)) => value.as_i64(),
        Some(_) => None,
    }
    .ok_or_else(|| Error::invalid("Invalid OTP digits"))?;
    if !(1..=10).contains(&digits) {
        return Err(Error::invalid(format!("Invalid OTP digits: {digits}")));
    }
    let algorithm = match object.get("algorithm") {
        None | Some(Value::Null) => "sha1",
        Some(Value::String(value)) => value,
        Some(_) => return Err(Error::invalid("Invalid OTP algorithm")),
    };
    let uri = build_uri(Otp {
        kind: "totp",
        issuer: &issuer,
        account,
        secret: &secret,
        algorithm,
        digits: Some(digits),
        period: optional_int(object.get("validity"), "OTP period")?,
        counter: None,
        allow_steam: true,
    })?;
    Ok(ImportedCode {
        uri,
        display: Some(Display::default()),
    })
}

fn decrypt_json_field(key: &[u8], value: &Value) -> Result<String> {
    let bytes = json_bytes(value)?;
    if bytes.len() < 28 {
        return Err(Error::invalid("Truncated encrypted field"));
    }
    let plaintext = decrypt_gcm(key, &bytes[..12], &bytes[12..], &[])
        .map_err(|_| Error::invalid("Invalid encrypted field"))?;
    String::from_utf8(plaintext).map_err(|_| Error::invalid("Invalid encrypted text"))
}

fn json_bytes(value: &Value) -> Result<Vec<u8>> {
    value
        .as_array()
        .ok_or_else(|| Error::invalid("Invalid byte array"))?
        .iter()
        .map(|value| {
            value
                .as_u64()
                .and_then(|value| u8::try_from(value).ok())
                .ok_or_else(|| Error::invalid("Invalid byte array"))
        })
        .collect()
}

fn derive_argon(
    password: &str,
    salt: &[u8],
    memory: u32,
    iterations: u32,
    lanes: u32,
) -> Result<Zeroizing<[u8; 32]>> {
    let params = ArgonParams::new(memory, iterations, lanes, Some(32))
        .map_err(|_| Error::invalid("Invalid Argon2 parameters"))?;
    let argon = Argon2::new(ArgonAlgorithm::Argon2id, Version::V0x13, params);
    let mut key = Zeroizing::new([0u8; 32]);
    argon
        .hash_password_into(password.as_bytes(), salt, key.as_mut())
        .map_err(|_| Error::invalid("Failed to derive import key"))?;
    Ok(key)
}

fn decrypt_gcm(key: &[u8], nonce: &[u8], ciphertext: &[u8], aad: &[u8]) -> Result<Vec<u8>> {
    let key: [u8; 32] = key
        .try_into()
        .map_err(|_| Error::invalid("Invalid AES key"))?;
    let nonce: [u8; 12] = nonce
        .try_into()
        .map_err(|_| Error::invalid("Invalid AES-GCM nonce"))?;
    Aes256Gcm::new(&key.into())
        .decrypt(
            &nonce.into(),
            Payload {
                msg: ciphertext,
                aad,
            },
        )
        .map_err(|_| Error::invalid("AES-GCM authentication failed"))
}

fn decode_hex_field(value: &Value, field: &str) -> Result<Vec<u8>> {
    hex::decode(
        value
            .get(field)
            .and_then(Value::as_str)
            .ok_or_else(|| Error::invalid(format!("Missing {field}")))?,
    )
    .map_err(|_| Error::invalid(format!("Invalid {field}")))
}

fn decode_b64_string(value: Option<&Value>, message: &str) -> Result<Vec<u8>> {
    b64::decode(
        value
            .and_then(Value::as_str)
            .ok_or_else(|| Error::invalid(message))?,
    )
    .map_err(|_| Error::invalid(message))
}

fn decode_b64_part(value: Option<&str>) -> Result<Vec<u8>> {
    b64::decode(value.ok_or_else(|| Error::invalid("Invalid 2FAS encrypted services"))?)
        .map_err(|_| Error::invalid("Invalid 2FAS encrypted services"))
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::super::ErrorKind;
    use super::*;

    #[test]
    fn decrypts_aegis_export() {
        let password = "password";
        let salt = [3u8; 16];
        let params =
            scrypt::Params::new(AEGIS_SCRYPT_LOG_N, AEGIS_SCRYPT_R, AEGIS_SCRYPT_P).unwrap();
        let mut password_key = [0u8; 32];
        scrypt::scrypt(password.as_bytes(), &salt, &params, &mut password_key).unwrap();
        let master_key = [7u8; 32];
        let slot_nonce = [4u8; 12];
        let slot = encrypt_gcm(&password_key, &slot_nonce, &master_key, &[]);
        let database = json!({
            "entries": [{
                "type": "totp",
                "name": "alice",
                "issuer": "Example",
                "info": {"algo": "SHA1", "secret": "MY", "digits": 6}
            }]
        })
        .to_string();
        let database_nonce = [5u8; 12];
        let encrypted_database =
            encrypt_gcm(&master_key, &database_nonce, database.as_bytes(), &[]);
        let input = json!({
            "header": {
                "slots": [{
                    "type": 1,
                    "n": AEGIS_SCRYPT_N,
                    "r": AEGIS_SCRYPT_R,
                    "p": AEGIS_SCRYPT_P,
                    "salt": hex::encode(salt),
                    "key": hex::encode(&slot[..slot.len() - 16]),
                    "key_params": {
                        "nonce": hex::encode(slot_nonce),
                        "tag": hex::encode(&slot[slot.len() - 16..])
                    }
                }],
                "params": {
                    "nonce": hex::encode(database_nonce),
                    "tag": hex::encode(&encrypted_database[encrypted_database.len() - 16..])
                }
            },
            "db": b64::encode(&encrypted_database[..encrypted_database.len() - 16])
        })
        .to_string();
        assert_eq!(import_aegis(&input, Some(password)).unwrap().codes.len(), 1);
        assert_password_errors(|password| import_aegis(&input, password));
    }

    #[test]
    fn rejects_unsupported_aegis_scrypt_parameters() {
        for (n, r, p) in [
            (1_u64 << 30, AEGIS_SCRYPT_R, AEGIS_SCRYPT_P),
            (AEGIS_SCRYPT_N, 9, AEGIS_SCRYPT_P),
            (AEGIS_SCRYPT_N, AEGIS_SCRYPT_R, 2),
        ] {
            let input = json!({
                "header": {
                    "slots": [{
                        "type": 1,
                        "n": n,
                        "r": r,
                        "p": p
                    }]
                },
                "db": ""
            })
            .to_string();
            let error = import_aegis(&input, Some("password")).err().unwrap();
            assert_eq!(error.kind(), ErrorKind::Invalid);
            assert_eq!(error.message, "Unsupported Aegis scrypt parameters");
        }
    }

    #[test]
    fn accepts_plain_aegis_export_with_null_slots() {
        let input = json!({
            "header": {"slots": null},
            "db": {
                "entries": [{
                    "type": "totp",
                    "name": "alice",
                    "issuer": "Example",
                    "info": {"algo": "SHA1", "secret": "MY", "digits": 6}
                }]
            }
        })
        .to_string();
        assert_eq!(import_aegis(&input, None).unwrap().codes.len(), 1);
    }

    #[test]
    fn decrypts_andotp_export() {
        let password = "password";
        let salt = [6u8; 12];
        let nonce = [7u8; 12];
        let mut key = [0u8; 32];
        pbkdf2_hmac::<Sha1>(password.as_bytes(), &salt, 2, &mut key);
        let plaintext = br#"[{"type":"TOTP","issuer":"Example","label":"alice","secret":"MY"}]"#;
        let encrypted = encrypt_gcm(&key, &nonce, plaintext, &[]);
        let mut input = 2u32.to_be_bytes().to_vec();
        input.extend_from_slice(&salt);
        input.extend_from_slice(&nonce);
        input.extend_from_slice(&encrypted);
        assert_eq!(
            import_andotp(&input, Some(password)).unwrap().codes.len(),
            1
        );
        assert_password_errors(|password| import_andotp(&input, password));
    }

    #[test]
    fn rejects_excessive_andotp_iterations() {
        for iterations in [ANDOTP_MAX_ITERATIONS + 1, u32::MAX] {
            let mut input = iterations.to_be_bytes().to_vec();
            input.resize(28, 0);
            let error = import_andotp(&input, Some("password")).err().unwrap();
            assert_eq!(error.kind(), ErrorKind::Invalid);
            assert_eq!(error.message(), "Invalid andOTP iteration count");
        }
    }

    #[test]
    fn decrypts_two_fas_export() {
        let password = "password";
        let salt = [8u8; 16];
        let nonce = [9u8; 12];
        let mut key = [0u8; 32];
        pbkdf2_hmac::<Sha256>(password.as_bytes(), &salt, 10_000, &mut key);
        let services = json!([{
            "name": "Example",
            "groupId": "g",
            "secret": "MY",
            "otp": {"tokenType": "TOTP", "account": "alice", "digits": 6}
        }])
        .to_string();
        let encrypted = encrypt_gcm(&key, &nonce, services.as_bytes(), &[]);
        let input = json!({
            "schemaVersion": 4,
            "reference": "encrypted",
            "groups": [{"id": "g", "name": "Work"}],
            "servicesEncrypted": format!(
                "{}:{}:{}",
                b64::encode(&encrypted),
                b64::encode(&salt),
                b64::encode(&nonce)
            )
        })
        .to_string();
        let batch = import_two_fas(&input, Some(password)).unwrap();
        assert_eq!(batch.codes.len(), 1);
        assert_eq!(batch.codes[0].display.as_ref().unwrap().tags, ["Work"]);
        assert_password_errors(|password| import_two_fas(&input, password));
    }

    #[test]
    fn rejects_unsupported_two_fas_version_before_requesting_password() {
        let input = json!({
            "schemaVersion": 5,
            "reference": "encrypted",
            "servicesEncrypted": ""
        })
        .to_string();
        assert_eq!(
            import_two_fas(&input, None).err().unwrap().kind(),
            ErrorKind::Invalid
        );
    }

    #[test]
    fn decrypts_proton_fixture() {
        let plaintext = include_str!(
            "../../../../../mobile/apps/auth/test/ui/settings/data/import/fixtures/proton_authenticator_backup.json"
        );
        let encrypted = include_str!(
            "../../../../../mobile/apps/auth/test/ui/settings/data/import/fixtures/proton_authenticator_backup_encrypted_1231246.json"
        );
        let expected = import_proton(plaintext, None).unwrap();
        let actual = import_proton(encrypted, Some("1231246")).unwrap();
        assert_eq!(actual.codes.len(), 4);
        assert_eq!(
            actual
                .codes
                .iter()
                .map(|code| &code.uri)
                .collect::<Vec<_>>(),
            expected
                .codes
                .iter()
                .map(|code| &code.uri)
                .collect::<Vec<_>>()
        );
        assert_eq!(
            import_proton(encrypted, None).err().unwrap().kind(),
            ErrorKind::PasswordRequired
        );
        assert_eq!(
            import_proton(encrypted, Some("wrong"))
                .err()
                .unwrap()
                .kind(),
            ErrorKind::IncorrectPassword
        );
    }

    #[test]
    fn decrypts_open_authenticator_fixture() {
        let input = include_str!(
            "../../../../../mobile/apps/auth/test/ui/settings/data/import/fixtures/dummy-open-authenticator.bak"
        );
        validate_open_authenticator(input).unwrap();
        let batch = import_open_authenticator(input, "dummy").unwrap();
        assert_eq!(batch.codes.len(), 3);
        assert!(
            batch.codes[0]
                .uri
                .contains("team%3Aalice%20%2B%40%E4%BE%8B%23%2F%25")
        );
        assert_eq!(
            import_open_authenticator(input, "wrong")
                .err()
                .unwrap()
                .kind(),
            ErrorKind::IncorrectPassword
        );
    }

    #[test]
    fn validates_open_authenticator_structure_without_a_password() {
        assert!(validate_open_authenticator("not json").is_err());
        let invalid = json!({
            "salt": b64::encode(&[0; 32]),
            "passwordSignature": b64::encode(&[0; 32])
        })
        .to_string();
        assert!(validate_open_authenticator(&invalid).is_err());
    }

    #[test]
    fn rejects_invalid_open_authenticator_parameters() {
        let key = [3u8; 32];
        let nonce = [4u8; 12];
        let mut secret = nonce.to_vec();
        secret.extend(encrypt_gcm(&key, &nonce, b"MY", &[]));
        let unsupported = json!({
            "secret": secret,
            "uuid": "alice",
            "algorithm": "SHA224",
            "digits": 6
        });
        assert!(decrypt_open_authenticator_entry(&unsupported, &key).is_err());

        let mut secret = nonce.to_vec();
        secret.extend(encrypt_gcm(&key, &nonce, b"MY", &[]));
        let zero_period = json!({
            "secret": secret,
            "uuid": "alice",
            "algorithm": "SHA1",
            "digits": 6,
            "validity": 0
        });
        assert!(decrypt_open_authenticator_entry(&zero_period, &key).is_err());
    }

    fn encrypt_gcm(key: &[u8], nonce: &[u8], plaintext: &[u8], aad: &[u8]) -> Vec<u8> {
        let key: [u8; 32] = key.try_into().unwrap();
        let nonce: [u8; 12] = nonce.try_into().unwrap();
        Aes256Gcm::new(&key.into())
            .encrypt(
                &nonce.into(),
                Payload {
                    msg: plaintext,
                    aad,
                },
            )
            .unwrap()
    }

    fn assert_password_errors(mut import: impl FnMut(Option<&str>) -> Result<Batch>) {
        assert_eq!(
            import(None).err().unwrap().kind(),
            ErrorKind::PasswordRequired
        );
        assert_eq!(
            import(Some("wrong")).err().unwrap().kind(),
            ErrorKind::IncorrectPassword
        );
    }
}
