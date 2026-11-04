mod binary_plist;
mod formats;
mod google;
mod otp_auth;
mod protected;

use std::fmt;

use serde::{Deserialize, Serialize};
use serde_json::Value;
use url::form_urlencoded;

pub use google::{GoogleMigration, parse_google_migration};

const DEFAULT_DIGITS: i64 = 6;
const STEAM_DIGITS: i64 = 5;
const DEFAULT_PERIOD: i64 = 30;
const MAX_DIGITS: i64 = 10;

#[derive(Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Display {
    #[serde(default)]
    pub pinned: bool,
    #[serde(default)]
    pub trashed: bool,
    #[serde(default)]
    pub last_used_at: i64,
    #[serde(default)]
    pub tap_count: i64,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub note: String,
    #[serde(default)]
    pub position: i64,
    #[serde(default = "default_icon_src")]
    pub icon_src: String,
    #[serde(default, rename = "iconID")]
    pub icon_id: String,
}

fn default_icon_src() -> String {
    "ente".to_owned()
}

pub struct ImportedCode {
    pub uri: String,
    pub display: Option<Display>,
}

pub struct Batch {
    pub codes: Vec<ImportedCode>,
    pub skipped: u32,
}

pub struct Error {
    kind: ErrorKind,
    message: String,
    entry: Option<String>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ErrorKind {
    Invalid,
    PasswordRequired,
    IncorrectPassword,
    FileTooLarge { max_bytes: u64 },
}

impl Error {
    fn invalid(message: impl Into<String>) -> Self {
        Self {
            kind: ErrorKind::Invalid,
            message: message.into(),
            entry: None,
        }
    }

    fn password_required() -> Self {
        Self {
            kind: ErrorKind::PasswordRequired,
            message: "Password required".to_owned(),
            entry: None,
        }
    }

    fn incorrect_password() -> Self {
        Self {
            kind: ErrorKind::IncorrectPassword,
            message: "Incorrect password".to_owned(),
            entry: None,
        }
    }

    fn file_too_large(max_bytes: u64) -> Self {
        Self {
            kind: ErrorKind::FileTooLarge { max_bytes },
            message: format!("Import file exceeds {max_bytes} bytes"),
            entry: None,
        }
    }

    fn entry(entry: &(impl serde::Serialize + ?Sized), error: impl fmt::Display) -> Self {
        Self {
            kind: ErrorKind::Invalid,
            message: error.to_string(),
            entry: serde_json::to_string_pretty(entry).ok(),
        }
    }

    pub fn kind(&self) -> ErrorKind {
        self.kind
    }

    pub fn message(&self) -> &str {
        &self.message
    }

    pub fn entry_text(&self) -> Option<&str> {
        self.entry.as_deref()
    }
}

impl fmt::Display for Error {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl fmt::Debug for Error {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("ImportError")
            .field("kind", &self.kind)
            .field("message", &self.message)
            .field("has_entry", &self.entry.is_some())
            .finish()
    }
}

impl std::error::Error for Error {}

pub type Result<T> = std::result::Result<T, Error>;

pub use formats::{
    parse_aegis, parse_andotp, parse_bitwarden, parse_lastpass, parse_proton, parse_raivo,
    parse_two_fas,
};
pub use otp_auth::{OTP_AUTH_MAX_BYTES, import_otp_auth};
pub use protected::{
    import_aegis, import_andotp, import_open_authenticator, import_proton, import_two_fas,
    validate_open_authenticator,
};

pub fn validate_ente_backup(input: &[u8]) -> Result<()> {
    crate::backup::validate_encrypted(input).map_err(|error| Error::invalid(error.to_string()))
}

pub fn decrypt_ente_backup(input: &[u8], password: &str) -> Result<Batch> {
    let plaintext = crate::backup::decrypt(input, password).map_err(|error| match error {
        crate::Error::Crypto(ente_core::crypto::Error::StreamPullFailed) => {
            Error::incorrect_password()
        }
        error => Error::invalid(error.to_string()),
    })?;
    let plaintext = std::str::from_utf8(&plaintext)
        .map_err(|_| Error::invalid("Invalid Ente Auth backup contents"))?;
    parse_plain_text(plaintext)
}

pub fn parse_plain_text(content: &str) -> Result<Batch> {
    let content = content.trim();
    if content.is_empty() {
        return Ok(Batch {
            codes: Vec::new(),
            skipped: 0,
        });
    }
    if content.starts_with("otpauth://") {
        let mut codes = Vec::new();
        let mut skipped = 0;
        for line in split_uri_list(content) {
            if validate_uri(line).is_ok() {
                codes.push(ImportedCode {
                    uri: line.to_owned(),
                    display: None,
                });
            } else {
                skipped += 1;
            }
        }
        return Ok(Batch { codes, skipped });
    }

    let root: Value = serde_json::from_str(content)
        .map_err(|_| Error::invalid("Expected an export object containing items"))?;
    let items = root
        .get("items")
        .and_then(Value::as_array)
        .ok_or_else(|| Error::invalid("Expected an export object containing items"))?;
    let mut codes = Vec::new();
    let mut skipped = 0;
    for item in items {
        let Some(object) = item.as_object() else {
            skipped += 1;
            continue;
        };
        let Some(uri) = object.get("rawData").and_then(Value::as_str) else {
            skipped += 1;
            continue;
        };
        if validate_uri_without_display(uri).is_err() {
            skipped += 1;
            continue;
        }
        let display = match object.get("display") {
            None | Some(Value::Null) => Display::default(),
            Some(value @ Value::Object(_)) => match serde_json::from_value(value.clone()) {
                Ok(display) => display,
                Err(_) => {
                    skipped += 1;
                    continue;
                }
            },
            Some(_) => {
                skipped += 1;
                continue;
            }
        };
        codes.push(ImportedCode {
            uri: uri.to_owned(),
            display: Some(display),
        });
    }
    Ok(Batch { codes, skipped })
}

fn split_uri_list(content: &str) -> Vec<&str> {
    let mut entries = Vec::new();
    for line in content.split(['\r', '\n']) {
        let mut remaining = line.trim();
        while let Some(index) = remaining.char_indices().find_map(|(index, character)| {
            if character != ',' {
                return None;
            }
            remaining[index + 1..]
                .trim_start()
                .starts_with("otpauth://")
                .then_some(index)
        }) {
            let entry = remaining[..index].trim();
            if !entry.is_empty() {
                entries.push(entry);
            }
            remaining = remaining[index + 1..].trim_start();
        }
        if !remaining.is_empty() {
            entries.push(remaining);
        }
    }
    entries
}

fn validate_uri(uri: &str) -> Result<()> {
    let parsed = parse_supported_uri(uri)?;
    if crate::code::Code::from_uri(uri).is_ok() {
        return Ok(());
    }
    let legacy_display = parsed
        .query_pairs()
        .find(|(name, _)| name == "codeDisplay")
        .is_some_and(|(_, value)| {
            value
                .rfind("}#")
                .is_some_and(|index| serde_json::from_str::<Display>(&value[..=index]).is_ok())
        });
    if legacy_display {
        return validate_uri_without_display_parsed(parsed);
    }
    Err(Error::invalid("Invalid OTP URI"))
}

fn validate_uri_without_display(uri: &str) -> Result<()> {
    validate_uri_without_display_parsed(parse_supported_uri(uri)?)
}

fn validate_uri_without_display_parsed(mut parsed: url::Url) -> Result<()> {
    let query: Vec<(String, String)> = parsed
        .query_pairs()
        .filter(|(name, _)| name != "codeDisplay")
        .map(|(name, value)| (name.into_owned(), value.into_owned()))
        .collect();
    let mut serializer = form_urlencoded::Serializer::new(String::new());
    serializer.extend_pairs(query);
    let query = serializer.finish();
    parsed.set_query((!query.is_empty()).then_some(&query));
    crate::code::Code::from_uri(parsed.as_str())
        .map(|_| ())
        .map_err(|_| Error::invalid("Invalid OTP URI"))
}

fn parse_supported_uri(uri: &str) -> Result<url::Url> {
    let parsed = url::Url::parse(&uri.trim_end().replace('#', "%23"))
        .map_err(|_| Error::invalid("Invalid OTP URI"))?;
    if parsed.scheme() != "otpauth"
        || !matches!(
            parsed
                .host_str()
                .unwrap_or_default()
                .to_ascii_lowercase()
                .as_str(),
            "totp" | "hotp" | "steam"
        )
        || !parsed.query_pairs().any(|(name, _)| name == "secret")
    {
        return Err(Error::invalid("Invalid OTP URI"));
    }
    Ok(parsed)
}

fn rebuild_uri(
    uri: &str,
    issuer: Option<&str>,
    account: Option<&str>,
    secret: Option<&str>,
) -> Result<String> {
    let parsed =
        url::Url::parse(&uri.replace('#', "%23")).map_err(|_| Error::invalid("Invalid OTP URI"))?;
    if parsed.scheme() != "otpauth" {
        return Err(Error::invalid("Invalid OTP URI"));
    }
    let query: std::collections::HashMap<String, String> = parsed
        .query_pairs()
        .map(|(name, value)| (name.into_owned(), value.into_owned()))
        .collect();
    let label = urlencoding::decode(parsed.path().trim_start_matches('/'))
        .map_err(|_| Error::invalid("Invalid OTP label"))?;
    let parsed_issuer = query
        .get("issuer")
        .cloned()
        .or_else(|| label.split_once(':').map(|(issuer, _)| issuer.to_owned()))
        .unwrap_or_else(|| label.to_string());
    let parsed_account = label
        .strip_prefix(&format!("{parsed_issuer}:"))
        .or_else(|| label.split_once(':').map(|(_, account)| account))
        .unwrap_or(&label);
    build_uri(Otp {
        kind: parsed.host_str().unwrap_or_default(),
        issuer: issuer.unwrap_or(&parsed_issuer),
        account: account.unwrap_or(parsed_account),
        secret: secret
            .or_else(|| query.get("secret").map(String::as_str))
            .ok_or_else(|| Error::invalid("Missing OTP secret"))?,
        algorithm: query.get("algorithm").map_or("SHA1", String::as_str),
        digits: query_int(&query, "digits")?,
        period: query_int(&query, "period")?,
        counter: query_int(&query, "counter")?,
        allow_steam: true,
    })
}

fn query_int(query: &std::collections::HashMap<String, String>, name: &str) -> Result<Option<i64>> {
    query
        .get(name)
        .map(|value| {
            value
                .parse()
                .map_err(|_| Error::invalid(format!("Invalid OTP {name}: {value}")))
        })
        .transpose()
}

struct Otp<'a> {
    kind: &'a str,
    issuer: &'a str,
    account: &'a str,
    secret: &'a str,
    algorithm: &'a str,
    digits: Option<i64>,
    period: Option<i64>,
    counter: Option<i64>,
    allow_steam: bool,
}

fn build_uri(otp: Otp<'_>) -> Result<String> {
    let kind = otp.kind.to_ascii_lowercase();
    let digits = match otp.digits {
        None => DEFAULT_DIGITS,
        Some(value @ 1..=MAX_DIGITS) => value,
        Some(value) => return Err(Error::invalid(format!("Invalid OTP digits: {value}"))),
    };
    let algorithm = otp.algorithm.trim().to_ascii_lowercase();
    let algorithm = algorithm.strip_prefix("algorithm.").unwrap_or(&algorithm);
    let algorithm = match algorithm.replace('-', "").as_str() {
        "sha1" => "SHA1",
        "sha256" => "SHA256",
        "sha512" => "SHA512",
        _ => {
            return Err(Error::invalid(format!(
                "Unsupported OTP algorithm: {}",
                otp.algorithm
            )));
        }
    };
    ente_core::otp::decode_secret(otp.secret).map_err(|_| Error::invalid("Invalid OTP secret"))?;
    let mut uri = format!(
        "otpauth://{kind}/{}:{}?secret={}&issuer={}&algorithm={}&digits={digits}",
        encode(otp.issuer),
        encode(otp.account),
        encode(otp.secret),
        encode(otp.issuer),
        algorithm,
    );
    match kind.as_str() {
        "totp" | "steam" if kind == "totp" || otp.allow_steam => {
            let period = match otp.period {
                None => DEFAULT_PERIOD,
                Some(value @ i64::MIN..=0) => {
                    return Err(Error::invalid(format!("Invalid OTP period: {value}")));
                }
                Some(value) => value,
            };
            uri.push_str(&format!("&period={period}"));
        }
        "hotp" => {
            let counter = otp.counter.unwrap_or(0);
            if counter < 0 {
                return Err(Error::invalid(format!("Invalid HOTP counter: {counter}")));
            }
            uri.push_str(&format!("&counter={counter}"));
        }
        _ => return Err(Error::invalid(format!("Invalid OTP type: {kind}"))),
    }
    Ok(uri)
}

fn uri_with_display(uri: &str, display: &Display) -> Result<String> {
    validate_uri(uri)?;
    let mut parsed =
        url::Url::parse(&uri.replace('#', "%23")).map_err(|_| Error::invalid("Invalid OTP URI"))?;
    let display = serde_json::to_string(display)
        .map_err(|_| Error::invalid("Invalid imported display metadata"))?;
    let existing: Vec<(String, String)> = parsed
        .query_pairs()
        .filter(|(name, _)| name != "codeDisplay")
        .map(|(name, value)| (name.into_owned(), value.into_owned()))
        .collect();
    let mut query = form_urlencoded::Serializer::new(String::new());
    query.extend_pairs(existing);
    query.append_pair("codeDisplay", &display);
    parsed.set_query(Some(&query.finish()));
    Ok(parsed.to_string())
}

fn encode(value: &str) -> String {
    urlencoding::encode(value).into_owned()
}

fn string(value: Option<&Value>) -> Option<&str> {
    value.and_then(Value::as_str)
}

fn int(value: Option<&Value>) -> Option<i64> {
    match value {
        Some(Value::Number(value)) => value.as_i64(),
        Some(Value::String(value)) => value.parse().ok(),
        _ => None,
    }
}

fn optional_int(value: Option<&Value>, name: &str) -> Result<Option<i64>> {
    match value {
        None | Some(Value::Null) => Ok(None),
        Some(Value::Number(value)) => value
            .as_i64()
            .map(Some)
            .ok_or_else(|| Error::invalid(format!("Invalid {name}"))),
        Some(Value::String(value)) => value
            .parse()
            .map(Some)
            .map_err(|_| Error::invalid(format!("Invalid {name}: {value}"))),
        Some(_) => Err(Error::invalid(format!("Invalid {name}"))),
    }
}

fn base32(bytes: &[u8]) -> String {
    const ALPHABET: &[u8; 32] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
    let mut output = String::with_capacity(bytes.len().div_ceil(5) * 8);
    let mut buffer = 0u32;
    let mut bits = 0;
    for byte in bytes {
        buffer = (buffer << 8) | u32::from(*byte);
        bits += 8;
        while bits >= 5 {
            bits -= 5;
            output.push(ALPHABET[((buffer >> bits) & 31) as usize] as char);
        }
    }
    if bits > 0 {
        output.push(ALPHABET[((buffer << (5 - bits)) & 31) as usize] as char);
    }
    output
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plain_text_supports_lines_commas_and_rich_json() {
        let secret = "JBSWY3DPEHPK3PXP";
        let batch = parse_plain_text(&format!(
            "otpauth://bad/a?secret={secret}\notpauth://totp/alice?secret={secret}&issuer=Example,%20Inc,  otpauth://hotp/bob?secret={secret}&counter=2"
        ))
        .unwrap();
        assert_eq!(batch.codes.len(), 2);
        assert_eq!(batch.skipped, 1);
        assert!(batch.codes[0].uri.contains("Example,%20Inc"));

        let batch = parse_plain_text(
            r#"{"items":[{"rawData":"otpauth://totp/alice?secret=MY","display":{"pinned":true,"tags":["Work"],"note":"Keep"}},{"rawData":"invalid"},{"rawData":"otpauth://totp/bob?secret=MY","display":null},{"rawData":"otpauth://totp/carol?secret=MY","display":{"note":"Partial"}},{"rawData":"otpauth://totp/dave?secret=MY","display":"invalid"},{"rawData":"otpauth://totp/eve?secret=MY&algorithm=SHA224"},{}]}"#,
        )
        .unwrap();
        assert_eq!(batch.codes.len(), 4);
        assert_eq!(batch.skipped, 3);
        let display = batch.codes[0].display.as_ref().unwrap();
        assert!(display.pinned);
        assert_eq!(display.tags, ["Work"]);
        assert_eq!(display.note, "Keep");
        assert_eq!(batch.codes[1].display.as_ref().unwrap().icon_src, "");
        assert_eq!(batch.codes[2].display.as_ref().unwrap().icon_src, "ente");
        assert!(batch.codes[3].uri.contains("algorithm=SHA224"));
    }

    #[test]
    fn structured_otp_parameters_are_validated() {
        assert!(
            build_uri(Otp {
                kind: "totp",
                issuer: "Example",
                account: "a:b +#/%",
                secret: "MY",
                algorithm: "sha-1",
                digits: None,
                period: None,
                counter: None,
                allow_steam: true,
            })
            .unwrap()
            .contains("Example:a%3Ab%20%2B%23%2F%25")
        );
        for digits in [-1, 0, 11] {
            assert!(
                build_uri(Otp {
                    kind: "totp",
                    issuer: "",
                    account: "a",
                    secret: "MY",
                    algorithm: "SHA1",
                    digits: Some(digits),
                    period: None,
                    counter: None,
                    allow_steam: true,
                })
                .is_err()
            );
        }
        for period in [-1, 0] {
            assert!(
                build_uri(Otp {
                    kind: "totp",
                    issuer: "",
                    account: "a",
                    secret: "MY",
                    algorithm: "SHA1",
                    digits: None,
                    period: Some(period),
                    counter: None,
                    allow_steam: true,
                })
                .is_err()
            );
        }
        for algorithm in ["SHA1", "sha-1", "Algorithm.SHA256", "algorithm.sha-512"] {
            let uri = build_uri(Otp {
                kind: "totp",
                issuer: "",
                account: "a",
                secret: "MY",
                algorithm,
                digits: None,
                period: None,
                counter: None,
                allow_steam: true,
            })
            .unwrap();
            assert!(uri.contains("algorithm=SHA"));
        }
        for algorithm in ["MD5", "SHA224", "SHA384", "unknown"] {
            assert!(
                build_uri(Otp {
                    kind: "totp",
                    issuer: "",
                    account: "a",
                    secret: "MY",
                    algorithm,
                    digits: None,
                    period: None,
                    counter: None,
                    allow_steam: true,
                })
                .is_err()
            );
        }
        assert!(
            build_uri(Otp {
                kind: "totp",
                issuer: "",
                account: "a",
                secret: "not base32!",
                algorithm: "SHA1",
                digits: None,
                period: None,
                counter: None,
                allow_steam: true,
            })
            .is_err()
        );
    }

    #[test]
    fn raw_uri_restoration_preserves_legacy_compatibility() {
        let historical = [
            "otpauth://totp/Example:alice?secret=MY&issuer=Example&algorithm=Algorithm.SHA256&digits=8&period=60&codeDisplay=%7B%22note%22%3A%22keep%22%7D",
            "otpauth://steam/alice?secret=MY",
            "otpauth://totp/a?secret=MY&algorithm=SHA224",
            "otpauth://totp/b?secret=not!",
            "otpauth://totp/c?secret=MY&digits=0",
            "otpauth://totp/d?secret=MY&digits=invalid",
            "otpauth://totp/e?secret=MY&period=0",
            "otpauth://totp/f?secret=MY&period=invalid",
            "otpauth://totp/g?secret=MY&codeDisplay=%7B%22note%22%3A%22old%22%7D#suffix",
        ];
        let batch = parse_plain_text(&format!(
            "{}\notpauth://totp/bad-display?secret=MY&codeDisplay=not-json}}#suffix\notpauth://totp/after?secret=MY\notpauth://totp/missing-secret",
            historical.join("\n")
        ))
        .unwrap();

        assert_eq!(batch.codes.len(), historical.len() + 1);
        assert_eq!(batch.skipped, 2);
        assert_eq!(
            batch
                .codes
                .iter()
                .take(historical.len())
                .map(|code| code.uri.as_str())
                .collect::<Vec<_>>(),
            historical
        );
        assert_eq!(
            batch.codes.last().unwrap().uri,
            "otpauth://totp/after?secret=MY"
        );
    }

    #[test]
    fn raw_uri_lists_support_lone_carriage_returns() {
        let first = "otpauth://totp/first?secret=MY";
        let second = "otpauth://totp/second?secret=MY";
        let batch = parse_plain_text(&format!("{first}\r{second}")).unwrap();

        assert_eq!(batch.codes.len(), 2);
        assert_eq!(batch.codes[0].uri, first);
        assert_eq!(batch.codes[1].uri, second);
    }

    #[test]
    fn rebuilt_colonless_labels_preserve_issuer_and_account_fallbacks() {
        let uri = rebuild_uri("otpauth://totp/whole-label?secret=MY", None, None, None).unwrap();

        assert!(uri.starts_with("otpauth://totp/whole-label:whole-label?"));
        assert!(uri.contains("issuer=whole-label"));
    }

    #[test]
    fn rich_restoration_uses_separate_display_with_legacy_embedded_metadata() {
        let uri = "otpauth://totp/alice?secret=MY&codeDisplay=%7B%22note%22%3A%22old%22%7D#suffix";
        let batch = parse_plain_text(&format!(
            r#"{{"items":[{{"rawData":"{uri}","display":{{"note":"separate"}}}}]}}"#
        ))
        .unwrap();

        assert_eq!(batch.codes.len(), 1);
        assert_eq!(batch.codes[0].uri, uri);
        assert_eq!(batch.codes[0].display.as_ref().unwrap().note, "separate");
    }

    #[test]
    fn decrypts_and_parses_ente_backups() {
        use ente_core::{
            b64,
            crypto::{Salt, argon, blob},
        };
        use serde_json::json;

        let plaintext = b"otpauth://totp/alice?secret=MY\ninvalid\n";
        let salt = Salt::generate();
        let key = argon::derive_key("password", &salt, argon::Params::MIN).unwrap();
        let encrypted = blob::encrypt(plaintext, &key).unwrap();
        let backup = serde_json::to_vec(&json!({
            "version": 1,
            "kdfParams": {
                "memLimit": argon::Params::MIN.mem_limit,
                "opsLimit": argon::Params::MIN.ops_limit,
                "salt": b64::encode(salt.as_bytes()),
            },
            "encryptedData": b64::encode(&encrypted.encrypted_data),
            "encryptionNonce": b64::encode(encrypted.decryption_header.as_bytes()),
        }))
        .unwrap();
        let batch = decrypt_ente_backup(&backup, "password").unwrap();
        assert_eq!(batch.codes.len(), 1);
        assert_eq!(batch.skipped, 1);
        assert_eq!(
            decrypt_ente_backup(&backup, "wrong").err().unwrap().kind(),
            ErrorKind::IncorrectPassword
        );
        assert_eq!(
            validate_ente_backup(b"{}").unwrap_err().kind(),
            ErrorKind::Invalid
        );
    }
}
