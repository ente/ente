use ente_core::{
    b64,
    crypto::{Header, Key, blob},
};
use serde::Deserialize;
use serde_json::value::RawValue;
use url::{Url, form_urlencoded};
use zeroize::Zeroizing;

use crate::{Error, Result};

pub fn uri_line(
    encrypted_data: Option<&str>,
    header: Option<&str>,
    key: &Key,
) -> Result<Zeroizing<String>> {
    let data = b64::decode(encrypted_data.ok_or(Error::InvalidRecord)?)?;
    let header = Header::try_from_slice(&b64::decode(header.ok_or(Error::InvalidRecord)?)?)?;
    let plaintext = Zeroizing::new(blob::decrypt_legacy(&data, &header, key)?);
    interpret(&plaintext)
}

fn interpret(plaintext: &[u8]) -> Result<Zeroizing<String>> {
    #[derive(Deserialize)]
    struct Legacy<'a> {
        #[serde(rename = "rawData")]
        raw_data: String,
        #[serde(borrow)]
        display: Option<&'a RawValue>,
    }

    let value: &RawValue = serde_json::from_slice(plaintext).map_err(|_| Error::InvalidRecord)?;
    let mut line = match value.get().as_bytes().first() {
        Some(b'"') => {
            let uri = Zeroizing::new(
                serde_json::from_str::<String>(value.get()).map_err(|_| Error::InvalidRecord)?,
            );
            validate_uri(&uri)?;
            uri
        }
        Some(b'{') => {
            let legacy: Legacy<'_> =
                serde_json::from_str(value.get()).map_err(|_| Error::InvalidRecord)?;
            let raw = Zeroizing::new(legacy.raw_data);
            let raw = Zeroizing::new(raw.replace('#', "%23"));
            validate_uri(&raw)?;
            let display = match legacy.display {
                Some(display) if display.get().starts_with('{') => display.get(),
                None => {
                    r#"{"pinned":false,"trashed":false,"lastUsedAt":0,"tapCount":0,"tags":[],"note":"","position":0,"iconSrc":"","iconID":""}"#
                }
                Some(_) => return Err(Error::InvalidRecord),
            };
            let (prefix, query) = raw.split_once('?').unwrap_or((&raw, ""));
            let mut uri = Zeroizing::new(String::from(prefix));
            uri.push('?');
            for pair in query.split('&').filter(|pair| !pair.is_empty()) {
                if form_urlencoded::parse(pair.as_bytes()).any(|(name, _)| name == "codeDisplay") {
                    continue;
                }
                uri.push_str(pair);
                uri.push('&');
            }
            uri.push_str(
                &form_urlencoded::Serializer::new(String::new())
                    .append_pair("codeDisplay", display)
                    .finish(),
            );
            uri
        }
        _ => return Err(Error::InvalidRecord),
    };
    line.push('\n');
    Ok(line)
}

fn validate_uri(uri: &str) -> Result<()> {
    if !uri.starts_with("otpauth://") || uri.chars().any(char::is_control) {
        return Err(Error::InvalidRecord);
    }
    let parsed = Url::parse(uri).map_err(|_| Error::InvalidRecord)?;
    if parsed.host_str().is_none()
        || !parsed
            .query_pairs()
            .any(|(name, value)| name == "secret" && !value.is_empty())
    {
        return Err(Error::InvalidRecord);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use ente_core::crypto::stream::Encryptor;
    use serde_json::{Value, json};

    #[test]
    fn records_preserve_uri_text_and_legacy_display() {
        let uri = "otpauth://hotp/Issuer:label?secret=JBSWY3DPEHPK3PXP&counter=19&digits=8&algorithm=SHA512&x=%252C&x=two&codeDisplay=%7B%22note%22%3A%22literal%252C%22%7D";
        assert_eq!(
            interpret(&serde_json::to_vec(uri).unwrap())
                .unwrap()
                .as_str(),
            format!("{uri}\n")
        );
        let display = json!({"note": "literal%2C, + # 😀", "tags": ["one,two", "%2C"], "pinned": true,
            "trashed": true, "position": 45, "lastUsedAt": 123, "tapCount": 7,
            "iconSrc": "custom", "iconID": "saved", "future": {"unknown": true}});
        for kind in ["totp", "hotp", "steam"] {
            let raw = format!(
                "otpauth://{kind}/Issuer:label?secret=JBSWY3DPEHPK3PXP&period=60&counter=19&digits=8&algorithm=SHA512&x=%252C&x=two&codeDisplay=old"
            );
            let line = interpret(
                &serde_json::to_vec(&json!({"rawData": raw, "display": display})).unwrap(),
            )
            .unwrap();
            assert!(line.starts_with(raw.strip_suffix("&codeDisplay=old").unwrap()));
            let parsed = Url::parse(line.trim_end()).unwrap();
            let metadata: Vec<_> = parsed
                .query_pairs()
                .filter(|(name, _)| name == "codeDisplay")
                .collect();
            assert_eq!(metadata.len(), 1);
            assert_eq!(
                serde_json::from_str::<Value>(&metadata[0].1).unwrap(),
                display
            );
        }
        for object in [
            json!({"rawData": uri}),
            json!({"rawData": uri, "display": null}),
        ] {
            let line = interpret(&serde_json::to_vec(&object).unwrap()).unwrap();
            let parsed = Url::parse(line.trim_end()).unwrap();
            let display = parsed
                .query_pairs()
                .find(|(name, _)| name == "codeDisplay")
                .unwrap()
                .1;
            assert_eq!(
                serde_json::from_str::<Value>(&display).unwrap(),
                json!({
                    "pinned": false, "trashed": false, "lastUsedAt": 0, "tapCount": 0, "tags": [],
                    "note": "", "position": 0, "iconSrc": "", "iconID": ""
                })
            );
        }
        let display = r#"{"unknown":184467440737095516160001,"decimal":0.123456789012345678901}"#;
        let legacy = format!(r#"{{"rawData":"{uri}","display":{display}}}"#);
        let line = interpret(legacy.as_bytes()).unwrap();
        let parsed = Url::parse(line.trim_end()).unwrap();
        assert_eq!(
            parsed
                .query_pairs()
                .find(|(name, _)| name == "codeDisplay")
                .unwrap()
                .1,
            display
        );
        let key = Key::generate();
        let mut stream = Encryptor::new(&key);
        let ciphertext = stream
            .push(&serde_json::to_vec(uri).unwrap(), false)
            .unwrap();
        assert_eq!(
            uri_line(
                Some(&b64::encode(&ciphertext)),
                Some(&b64::encode(stream.header().as_bytes())),
                &key
            )
            .unwrap()
            .as_str(),
            format!("{uri}\n")
        );
    }

    #[test]
    fn malformed_records_fail_without_disclosing_plaintext() {
        for value in [
            json!("private-secret"),
            json!("otpauth://totp/a?secret=private-secret\nsecond"),
            json!({"rawData": "otpauth://totp/a?secret=private-secret", "display": "private-secret"}),
            json!(["private-secret"]),
            json!({"rawData": 123}),
        ] {
            let error = interpret(&serde_json::to_vec(&value).unwrap()).unwrap_err();
            assert_eq!(error.to_string(), "unreadable Auth record");
            assert!(!format!("{error:?}").contains("private-secret"));
        }
        assert_eq!(
            interpret(b"{\"private-secret\"").unwrap_err().to_string(),
            "unreadable Auth record"
        );
    }
}
