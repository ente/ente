use std::collections::{HashMap, HashSet};

use aes::Aes256;
use cbc::cipher::{BlockModeDecrypt, KeyIvInit, block_padding::Pkcs7};
use hmac::{Hmac, Mac};
use pbkdf2::pbkdf2_hmac;
use serde_json::{Map, Number, Value};
use sha1::{Digest, Sha1};
use sha2::Sha256;
use zeroize::Zeroizing;

use super::{
    Batch, Error, ImportedCode, Otp, Result, base32,
    binary_plist::{self, Dictionary, EXPANSION_ERROR, Value as PlistValue},
    build_uri,
};

pub const OTP_AUTH_MAX_BYTES: u64 = 10 * 1024 * 1024;
const MAX_ARCHIVE_NESTING: usize = 128;

pub fn import_otp_auth(input: &[u8], password: &str) -> Result<Batch> {
    if u64::try_from(input.len()).unwrap_or(u64::MAX) > OTP_AUTH_MAX_BYTES {
        return Err(Error::file_too_large(OTP_AUTH_MAX_BYTES));
    }
    let outer = decrypt_outer_archive(input)?;
    let outer = object(&outer)?;
    let is_backup = outer.contains_key("WrappedData");
    let encrypted = bytes(
        outer
            .get(if is_backup { "WrappedData" } else { "Data" })
            .ok_or_else(|| Error::invalid("Invalid OTP Auth export"))?,
    )?;
    let version = number(outer.get("Version"));
    let legacy = (is_backup && version == Some(1.0)) || (!is_backup && version == Some(1.1));
    let plaintext = if legacy {
        let result = (|| {
            let iv_source = if is_backup {
                text(outer.get("IV"))?.as_bytes().to_vec()
            } else {
                bytes(
                    outer
                        .get("IV")
                        .ok_or_else(|| Error::invalid("Invalid OTP Auth IV"))?,
                )?
            };
            let salt = text(outer.get("Salt"))?;
            let key = Sha256::digest(format!("{salt}-{password}").as_bytes());
            let digest = Sha1::digest(iv_source);
            decrypt_cbc(&encrypted, key.as_slice(), &digest[..16])
        })();
        result.map_err(|_| Error::incorrect_password())?
    } else if (is_backup && version == Some(1.1)) || (!is_backup && version == Some(1.2)) {
        decrypt_rnc_cryptor(&encrypted, password)?
    } else {
        return Err(Error::invalid(format!(
            "Unsupported OTP Auth export version: {}",
            version.map_or_else(|| "null".to_owned(), |value| value.to_string())
        )));
    };
    let root = match unarchive(&plaintext) {
        Ok(root) => root,
        Err(error) if legacy && error.message() != EXPANSION_ERROR => {
            return Err(Error::incorrect_password());
        }
        Err(error) => return Err(error),
    };
    let accounts = if is_backup {
        backup_accounts(&root)?
    } else {
        vec![root]
    };
    let mut codes = Vec::with_capacity(accounts.len());
    for account in accounts {
        let code = account_to_code(&account).map_err(|error| Error::entry(&account, error))?;
        codes.push(code);
    }
    Ok(Batch { codes, skipped: 0 })
}

fn decrypt_outer_archive(input: &[u8]) -> Result<Value> {
    for magic in [b"Authenticator".as_slice(), b"OTPAuth".as_slice()] {
        let key = Sha256::digest(magic);
        let Ok(plaintext) = decrypt_cbc(input, key.as_slice(), &[0; 16]) else {
            continue;
        };
        let Ok(root) = unarchive(&plaintext) else {
            continue;
        };
        let Ok(root_object) = object(&root) else {
            continue;
        };
        if root_object.contains_key("WrappedData") || root_object.contains_key("Data") {
            return Ok(root);
        }
    }
    Err(Error::invalid("Invalid OTP Auth export"))
}

fn decrypt_rnc_cryptor(input: &[u8], password: &str) -> Result<Vec<u8>> {
    const HEADER: usize = 34;
    const HMAC: usize = 32;
    if input.len() < HEADER + 16 + HMAC || input[..2] != [3, 1] {
        return Err(Error::invalid("Invalid OTP Auth encryption"));
    }
    let encryption_key = pbkdf2_sha1(password, &input[2..10]);
    let hmac_key = pbkdf2_sha1(password, &input[10..18]);
    let authenticated = &input[..input.len() - HMAC];
    let expected = &input[input.len() - HMAC..];
    let mut mac = <Hmac<Sha256> as hmac::KeyInit>::new_from_slice(hmac_key.as_ref())
        .map_err(|_| Error::invalid("Invalid OTP Auth HMAC key"))?;
    mac.update(authenticated);
    mac.verify_slice(expected)
        .map_err(|_| Error::incorrect_password())?;
    decrypt_cbc(
        &input[HEADER..input.len() - HMAC],
        encryption_key.as_ref(),
        &input[18..HEADER],
    )
    .map_err(|_| Error::incorrect_password())
}

fn pbkdf2_sha1(password: &str, salt: &[u8]) -> Zeroizing<[u8; 32]> {
    let mut key = Zeroizing::new([0u8; 32]);
    pbkdf2_hmac::<Sha1>(password.as_bytes(), salt, 10_000, key.as_mut());
    key
}

fn decrypt_cbc(input: &[u8], key: &[u8], iv: &[u8]) -> Result<Vec<u8>> {
    let key: [u8; 32] = key
        .try_into()
        .map_err(|_| Error::invalid("Invalid AES key"))?;
    let iv: [u8; 16] = iv
        .try_into()
        .map_err(|_| Error::invalid("Invalid AES-CBC IV"))?;
    cbc::Decryptor::<Aes256>::new(&key.into(), &iv.into())
        .decrypt_padded_vec::<Pkcs7>(input)
        .map_err(|_| Error::invalid("Invalid encrypted data"))
}

fn unarchive(input: &[u8]) -> Result<Value> {
    let capacity = input
        .len()
        .checked_mul(16)
        .ok_or_else(|| Error::invalid(EXPANSION_ERROR))?;
    let (archive, remaining) = binary_plist::parse(input, capacity)?;
    KeyedArchive::new(archive, remaining)?.root()
}

fn backup_accounts(root: &Value) -> Result<Vec<Value>> {
    let folders = object(root)?
        .get("Folders")
        .and_then(Value::as_array)
        .ok_or_else(|| Error::invalid("Invalid OTP Auth backup"))?;
    let mut accounts = Vec::new();
    for folder in folders {
        if let Some(values) = object(folder)?.get("accounts").and_then(Value::as_array) {
            accounts.extend(values.iter().cloned());
        }
    }
    Ok(accounts)
}

fn account_to_code(account: &Value) -> Result<ImportedCode> {
    let account = object(account)?;
    let kind = match integer(account.get("type")) {
        Some(1) => "hotp",
        Some(2) => "totp",
        _ => return Err(Error::invalid("Unsupported OTP type")),
    };
    let algorithm = match integer(account.get("algorithm")) {
        Some(0 | 1) => "SHA1",
        Some(2) => "SHA256",
        Some(3) => "SHA512",
        _ => return Err(Error::invalid("Unsupported OTP algorithm")),
    };
    let issuer = account
        .get("issuer")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let label = text(account.get("label"))?;
    let secret = base32(&bytes(
        account
            .get("secret")
            .ok_or_else(|| Error::invalid("Missing OTP secret"))?,
    )?);
    let uri = build_uri(Otp {
        kind,
        issuer,
        account: label,
        secret: &secret,
        algorithm,
        digits: integer(account.get("digits")).filter(|value| *value != 0),
        period: integer(account.get("period")).filter(|value| *value != 0),
        counter: integer(account.get("counter")),
        allow_steam: true,
    })?;
    Ok(ImportedCode { uri, display: None })
}

struct Budget {
    remaining: usize,
}

impl Budget {
    fn new(remaining: usize) -> Self {
        Self { remaining }
    }

    fn consume(&mut self, amount: usize) -> Result<()> {
        self.remaining = self
            .remaining
            .checked_sub(amount)
            .ok_or_else(|| Error::invalid(EXPANSION_ERROR))?;
        Ok(())
    }
}

struct KeyedArchive {
    objects: Vec<PlistValue>,
    top: Dictionary,
    cache: HashMap<usize, (Value, usize)>,
    resolving: HashSet<usize>,
    depth: usize,
    budget: Budget,
}

impl KeyedArchive {
    fn new(archive: PlistValue, capacity: usize) -> Result<Self> {
        let PlistValue::Dictionary(mut archive) = archive else {
            return Err(Error::invalid("Invalid keyed archive"));
        };
        if archive.get("$archiver").and_then(plist_string) != Some("NSKeyedArchiver") {
            return Err(Error::invalid("Invalid keyed archive"));
        }
        let Some(PlistValue::Array(objects)) = archive.remove("$objects") else {
            return Err(Error::invalid("Invalid keyed archive"));
        };
        let Some(PlistValue::Dictionary(top)) = archive.remove("$top") else {
            return Err(Error::invalid("Invalid keyed archive"));
        };
        Ok(Self {
            objects,
            top,
            cache: HashMap::new(),
            resolving: HashSet::new(),
            depth: 0,
            budget: Budget::new(capacity),
        })
    }

    fn root(mut self) -> Result<Value> {
        let root = self
            .top
            .remove("root")
            .ok_or_else(|| Error::invalid("Invalid keyed archive root"))?;
        self.resolve(&root)
    }

    fn resolve(&mut self, value: &PlistValue) -> Result<Value> {
        if self.depth >= MAX_ARCHIVE_NESTING {
            return Err(Error::invalid("OTP Auth archive nesting limit exceeded"));
        }
        self.depth += 1;
        let result = self.resolve_value(value);
        self.depth -= 1;
        result
    }

    fn resolve_value(&mut self, value: &PlistValue) -> Result<Value> {
        self.budget.consume(1)?;
        match value {
            PlistValue::String(value) => {
                self.budget.consume(value.len())?;
                Ok(Value::String(value.clone()))
            }
            PlistValue::Data(value) => {
                self.budget.consume(value.len())?;
                Ok(Value::Array(
                    value.iter().copied().map(Value::from).collect(),
                ))
            }
            PlistValue::Uid(value) => self.resolve_uid(*value),
            PlistValue::Array(values) => values
                .iter()
                .map(|value| self.resolve(value))
                .collect::<Result<Vec<_>>>()
                .map(Value::Array),
            PlistValue::Dictionary(values) => values
                .iter()
                .map(|(key, value)| Ok((key.clone(), self.resolve(value)?)))
                .collect::<Result<Map<_, _>>>()
                .map(Value::Object),
            PlistValue::Boolean(value) => Ok(Value::Bool(*value)),
            PlistValue::Integer(value) => Ok(Value::Number((*value).into())),
            PlistValue::Real(value) => Number::from_f64(*value)
                .map(Value::Number)
                .ok_or_else(|| Error::invalid("Invalid archive number")),
            PlistValue::Date(_) => Err(Error::invalid("Unsupported archive date")),
            PlistValue::Null => Ok(Value::Null),
        }
    }

    fn resolve_uid(&mut self, uid: u64) -> Result<Value> {
        if uid == 0 {
            return Ok(Value::Null);
        }
        let index = usize::try_from(uid)
            .ok()
            .filter(|index| *index < self.objects.len())
            .ok_or_else(|| Error::invalid("Invalid keyed archive reference"))?;
        if let Some((value, cost)) = self.cache.get(&index).cloned() {
            self.budget.consume(cost)?;
            return Ok(value);
        }
        if !self.resolving.insert(index) {
            return Err(Error::invalid("Invalid keyed archive reference"));
        }
        let remaining = self.budget.remaining;
        let result = self.resolve_object(index);
        self.resolving.remove(&index);
        let result = result?;
        let cost = remaining - self.budget.remaining;
        self.cache.insert(index, (result.clone(), cost));
        Ok(result)
    }

    fn resolve_object(&mut self, index: usize) -> Result<Value> {
        let raw = self.objects[index].clone();
        let PlistValue::Dictionary(object) = raw else {
            return self.resolve(&raw);
        };
        let class_uid = match object.get("$class") {
            Some(PlistValue::Uid(value)) => *value,
            _ => return Err(Error::invalid("Missing keyed archive class")),
        };
        let class = usize::try_from(class_uid)
            .ok()
            .and_then(|index| self.objects.get(index))
            .and_then(|value| match value {
                PlistValue::Dictionary(value) => value.get("$classname"),
                _ => None,
            })
            .and_then(plist_string)
            .ok_or_else(|| Error::invalid("Invalid keyed archive class"))?
            .to_owned();
        match class.as_str() {
            "NSDictionary" | "NSMutableDictionary" => self.resolve_dictionary(&object),
            "NSArray" | "NSMutableArray" | "NSSet" | "NSMutableSet" => self.resolve(
                object
                    .get("NS.objects")
                    .ok_or_else(|| Error::invalid("Invalid keyed archive array"))?,
            ),
            "NSData" | "NSMutableData" => self.resolve(
                object
                    .get("NS.data")
                    .or_else(|| object.get("NS.bytes"))
                    .ok_or_else(|| Error::invalid("Invalid keyed archive data"))?,
            ),
            "NSString" | "NSMutableString" => self.resolve(
                object
                    .get("NS.string")
                    .ok_or_else(|| Error::invalid("Invalid keyed archive string"))?,
            ),
            "NSDate" => self.resolve(
                object
                    .get("NS.time")
                    .ok_or_else(|| Error::invalid("Invalid keyed archive date"))?,
            ),
            "ACOTPAccount" | "ACOTPFolder" => object
                .iter()
                .filter(|(key, _)| key.as_str() != "$class")
                .map(|(key, value)| Ok((key.clone(), self.resolve(value)?)))
                .collect::<Result<Map<_, _>>>()
                .map(Value::Object),
            _ => Err(Error::invalid(format!(
                "Unsupported keyed archive class: {class}"
            ))),
        }
    }

    fn resolve_dictionary(&mut self, object: &Dictionary) -> Result<Value> {
        let Value::Array(keys) = self.resolve(
            object
                .get("NS.keys")
                .ok_or_else(|| Error::invalid("Invalid keyed archive dictionary"))?,
        )?
        else {
            return Err(Error::invalid("Invalid keyed archive dictionary"));
        };
        let Value::Array(values) = self.resolve(
            object
                .get("NS.objects")
                .ok_or_else(|| Error::invalid("Invalid keyed archive dictionary"))?,
        )?
        else {
            return Err(Error::invalid("Invalid keyed archive dictionary"));
        };
        if keys.len() != values.len() {
            return Err(Error::invalid("Invalid keyed archive dictionary"));
        }
        keys.into_iter()
            .zip(values)
            .map(|(key, value)| {
                key.as_str()
                    .map(|key| (key.to_owned(), value))
                    .ok_or_else(|| Error::invalid("Invalid keyed archive dictionary key"))
            })
            .collect::<Result<Map<_, _>>>()
            .map(Value::Object)
    }
}

fn plist_string(value: &PlistValue) -> Option<&str> {
    match value {
        PlistValue::String(value) => Some(value),
        _ => None,
    }
}

fn object(value: &Value) -> Result<&Map<String, Value>> {
    value
        .as_object()
        .ok_or_else(|| Error::invalid("Expected a dictionary"))
}

fn bytes(value: &Value) -> Result<Vec<u8>> {
    value
        .as_array()
        .ok_or_else(|| Error::invalid("Expected binary data"))?
        .iter()
        .map(|value| {
            value
                .as_u64()
                .and_then(|value| u8::try_from(value).ok())
                .ok_or_else(|| Error::invalid("Expected binary data"))
        })
        .collect()
}

fn text(value: Option<&Value>) -> Result<&str> {
    value
        .and_then(Value::as_str)
        .ok_or_else(|| Error::invalid("Expected text"))
}

fn integer(value: Option<&Value>) -> Option<i64> {
    value.and_then(Value::as_i64)
}

fn number(value: Option<&Value>) -> Option<f64> {
    value.and_then(Value::as_f64)
}

#[cfg(test)]
mod tests {
    use ente_core::b64;

    use super::*;

    #[test]
    fn imports_supported_otp_auth_exports() {
        for (name, count) in [
            ("backup-1.0.otpauthdb", 2),
            ("backup-1.1.otpauthdb", 2),
            ("account-1.1.otpauth", 1),
            ("account-1.2.otpauth", 1),
            ("backup-shared.otpauthdb", 6),
        ] {
            let input = fixture(name);
            assert_eq!(
                import_otp_auth(&input, "abc123").unwrap().codes.len(),
                count
            );
            assert_eq!(
                import_otp_auth(&input, "wrong-password")
                    .err()
                    .unwrap()
                    .kind(),
                super::super::ErrorKind::IncorrectPassword
            );
        }
    }

    #[test]
    fn bounds_otp_auth_archive_expansion() {
        for name in [
            "backup-expanded-uids.otpauthdb",
            "backup-expanded-inline.otpauthdb",
            "backup-expanded-binary.otpauthdb",
        ] {
            assert!(import_otp_auth(&fixture(name), "abc123").is_err());
        }
    }

    fn fixture(name: &str) -> Vec<u8> {
        let encoded = match name {
            "backup-1.0.otpauthdb" => include_str!(
                "../../../../../mobile/apps/auth/test/ui/settings/data/import/fixtures/backup-1.0.otpauthdb.b64"
            ),
            "backup-1.1.otpauthdb" => include_str!(
                "../../../../../mobile/apps/auth/test/ui/settings/data/import/fixtures/backup-1.1.otpauthdb.b64"
            ),
            "account-1.1.otpauth" => include_str!(
                "../../../../../mobile/apps/auth/test/ui/settings/data/import/fixtures/account-1.1.otpauth.b64"
            ),
            "account-1.2.otpauth" => include_str!(
                "../../../../../mobile/apps/auth/test/ui/settings/data/import/fixtures/account-1.2.otpauth.b64"
            ),
            "backup-shared.otpauthdb" => include_str!(
                "../../../../../mobile/apps/auth/test/ui/settings/data/import/fixtures/backup-shared.otpauthdb.b64"
            ),
            "backup-expanded-uids.otpauthdb" => include_str!(
                "../../../../../mobile/apps/auth/test/ui/settings/data/import/fixtures/backup-expanded-uids.otpauthdb.b64"
            ),
            "backup-expanded-inline.otpauthdb" => include_str!(
                "../../../../../mobile/apps/auth/test/ui/settings/data/import/fixtures/backup-expanded-inline.otpauthdb.b64"
            ),
            "backup-expanded-binary.otpauthdb" => include_str!(
                "../../../../../mobile/apps/auth/test/ui/settings/data/import/fixtures/backup-expanded-binary.otpauthdb.b64"
            ),
            _ => unreachable!(),
        };
        b64::decode(&encoded.split_whitespace().collect::<String>()).unwrap()
    }
}
