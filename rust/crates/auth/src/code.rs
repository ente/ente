use ente_core::otp::{self, Algorithm};
use serde::Deserialize;
use url::Url;
use zeroize::Zeroizing;

use crate::{Error, Result};

#[derive(Clone, Copy)]
pub enum Kind {
    Totp,
    Hotp,
    Steam,
}

impl Kind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Totp => "totp",
            Self::Hotp => "hotp",
            Self::Steam => "steam",
        }
    }
}

pub struct Code {
    pub issuer: String,
    pub account_name: String,
    pub kind: Kind,
    pub trashed: bool,
    secret: Zeroizing<String>,
    algorithm: String,
    digits: String,
    period: String,
}

impl Code {
    pub fn from_uri(uri: &str) -> Result<Self> {
        let uri = Zeroizing::new(uri.trim_end().replace('#', "%23"));
        let parsed = Url::parse(&uri).map_err(|_| Error::InvalidRecord)?;
        let query: std::collections::HashMap<_, _> = parsed.query_pairs().collect();
        let label = urlencoding::decode(parsed.path().strip_prefix('/').unwrap_or(parsed.path()))
            .map_err(|_| Error::InvalidRecord)?;
        let mut issuer = query.get("issuer").map_or_else(
            || {
                label
                    .split_once(':')
                    .map_or(label.as_ref(), |(issuer, _)| issuer)
                    .to_owned()
            },
            ToString::to_string,
        );
        if query.contains_key("issuer")
            && let Some((name, digits)) = issuer.rsplit_once("period=")
            && !digits.is_empty()
            && digits.bytes().all(|byte| byte.is_ascii_digit())
        {
            let name = name.strip_suffix('&').unwrap_or(name);
            if !name.is_empty() && !name.ends_with(char::is_whitespace) {
                issuer.truncate(name.len());
            }
        }
        let account_name = label
            .strip_prefix(&format!("{issuer}:"))
            .or_else(|| label.split_once(':').map(|(_, account)| account))
            .unwrap_or(&label)
            .to_owned();
        let kind = match parsed
            .host_str()
            .unwrap_or_default()
            .to_ascii_lowercase()
            .as_str()
        {
            "totp" if issuer.eq_ignore_ascii_case("steam") => Kind::Steam,
            "totp" => Kind::Totp,
            "steam" => Kind::Steam,
            "hotp" => Kind::Hotp,
            _ => return Err(Error::InvalidRecord),
        };
        #[derive(Default, Deserialize)]
        struct Display {
            trashed: Option<bool>,
        }
        let display = query
            .get("codeDisplay")
            .map(|value| {
                Option::<Display>::deserialize(&mut serde_json::Deserializer::from_str(value))
            })
            .transpose()
            .map_err(|_| Error::InvalidRecord)?
            .flatten()
            .unwrap_or_default();
        Ok(Self {
            issuer,
            account_name,
            kind,
            trashed: display.trashed.unwrap_or(false),
            secret: Zeroizing::new(query.get("secret").ok_or(Error::InvalidRecord)?.to_string()),
            algorithm: query
                .get("algorithm")
                .map_or("sha1", |s| s.as_ref())
                .to_owned(),
            digits: query.get("digits").map_or("6", |s| s.as_ref()).to_owned(),
            period: query.get("period").map_or("30", |s| s.as_ref()).to_owned(),
        })
    }

    pub fn name(&self) -> String {
        match (self.issuer.is_empty(), self.account_name.is_empty()) {
            (true, _) => self.account_name.clone(),
            (_, true) => self.issuer.clone(),
            _ => format!("{} ({})", self.issuer, self.account_name),
        }
    }

    pub fn matches(&self, query: &str) -> bool {
        let query = query.to_lowercase();
        let issuer = self.issuer.to_lowercase();
        let account = self.account_name.to_lowercase();
        self.name().to_lowercase() == query
            || query
                .split_whitespace()
                .all(|word| issuer.contains(word) || account.contains(word))
    }

    pub fn generate(&self, time: u64) -> Result<(String, u64)> {
        if matches!(self.kind, Kind::Hotp) {
            return Err(Error::UnsupportedHotp);
        }
        let secret = otp::decode_secret(&self.secret)?;
        let (value, period) = if matches!(self.kind, Kind::Steam) {
            (otp::steam(&secret, time)?, 30)
        } else {
            let algorithm = match self.algorithm.to_ascii_lowercase().as_str() {
                "sha1" | "algorithm.sha1" => Algorithm::Sha1,
                "sha256" | "algorithm.sha256" => Algorithm::Sha256,
                "sha512" | "algorithm.sha512" => Algorithm::Sha512,
                _ => return Err(Error::InvalidCodeParameters),
            };
            let digits = self
                .digits
                .parse()
                .map_err(|_| Error::InvalidCodeParameters)?;
            let period = self
                .period
                .parse()
                .map_err(|_| Error::InvalidCodeParameters)?;
            (otp::totp(&secret, time, period, digits, algorithm)?, period)
        };
        let valid_until = time
            .checked_add(period - time % period)
            .ok_or(Error::InvalidCodeParameters)?;
        Ok((value, valid_until))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ente_core::{
        b64,
        crypto::{Key, blob},
    };
    use serde_json::json;

    #[test]
    fn saved_forms_preserve_labels_and_generate_with_stored_parameters() {
        let uri = "otpauth://totp/Work:alice%2B%252C#tag?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&digits=8&period=60&algorithm=Algorithm.SHA1";
        let key = Key::generate();
        for (value, trashed) in [
            (json!(uri), false),
            (
                json!({"rawData": uri, "display": {"note": "literal%2C"}}),
                false,
            ),
            (
                json!(format!("{uri}&codeDisplay={{\"trashed\":true}}#suffix")),
                true,
            ),
        ] {
            let encrypted = blob::encrypt(&serde_json::to_vec(&value).unwrap(), &key).unwrap();
            let line = crate::record::uri_line(
                Some(&b64::encode(&encrypted.encrypted_data)),
                Some(&b64::encode(encrypted.decryption_header.as_bytes())),
                &key,
            )
            .unwrap();
            let code = Code::from_uri(&line).unwrap();
            assert_eq!(code.name(), "Work (alice+%2C#tag)");
            assert_eq!(code.trashed, trashed);
            assert_eq!(
                code.generate(2_222_222_219).unwrap(),
                ("07081804".into(), 2_222_222_220)
            );
            assert_eq!(code.generate(2_222_222_220).unwrap().1, 2_222_222_280);
        }
        for uri in [
            "otpauth://steam/alice?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
            "otpauth://totp/alice?issuer=sTeAm&secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
        ] {
            let code = Code::from_uri(uri).unwrap();
            assert!(matches!(code.kind, Kind::Steam));
            assert_eq!(code.generate(59).unwrap(), ("PV9M4".into(), 60));
        }
        for (issuer, name, value) in [
            ("Steamperiod=30", "Steam", "PV9M4"),
            ("Steam%26period=30", "Steam", "PV9M4"),
            ("Steam%20period=30", "Steam period=30", "287082"),
        ] {
            let code = Code::from_uri(&format!(
                "otpauth://totp/alice?issuer={issuer}&secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
            ))
            .unwrap();
            let name = format!("{name} (alice)");
            assert_eq!(code.name(), name);
            assert!(code.matches(&name));
            assert_eq!(code.generate(59).unwrap(), (value.into(), 60));
        }
        let code =
            Code::from_uri("otpauth://hotp/alice?issuer=Steam&secret=MY&counter=12").unwrap();
        assert!(matches!(code.kind, Kind::Hotp));
        assert!(matches!(code.generate(59), Err(Error::UnsupportedHotp)));
        for parameter in ["algorithm=md5", "digits=11", "period=0", "period=oops"] {
            let code =
                Code::from_uri(&format!("otpauth://totp/alice?secret=MY&{parameter}")).unwrap();
            assert!(code.generate(59).is_err());
        }
    }
}
