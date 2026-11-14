use std::collections::HashMap;

use serde_json::Value;

use super::{
    Batch, DEFAULT_DIGITS, Display, Error, ImportedCode, Otp, Result, STEAM_DIGITS, build_uri,
    display_from_uri, int, optional_int, otp_uri_identity, query_int, rebuild_uri, string,
    uri_with_display,
};

pub fn parse_aegis(database: &str) -> Result<Batch> {
    let database: Value =
        serde_json::from_str(database).map_err(|_| Error::invalid("Invalid Aegis database"))?;
    let database = database
        .as_object()
        .ok_or_else(|| Error::invalid("Invalid Aegis database"))?;
    let groups = database
        .get("groups")
        .and_then(Value::as_array)
        .map(|groups| {
            groups
                .iter()
                .filter_map(|group| {
                    Some((
                        string(group.get("uuid"))?.to_owned(),
                        string(group.get("name"))?.to_owned(),
                    ))
                })
                .collect::<HashMap<_, _>>()
        })
        .unwrap_or_default();
    let entries = database
        .get("entries")
        .and_then(Value::as_array)
        .ok_or_else(|| Error::invalid("Invalid Aegis database"))?;
    let mut codes = Vec::with_capacity(entries.len());
    for entry in entries {
        let result: Result<ImportedCode> = (|| {
            let info = entry
                .get("info")
                .filter(|info| info.is_object())
                .ok_or_else(|| Error::invalid("Invalid Aegis entry"))?;
            let uri = build_uri(Otp {
                kind: required_string(entry, "type")?,
                issuer: required_string(entry, "issuer")?,
                account: required_string(entry, "name")?,
                secret: required_string(info, "secret")?,
                algorithm: required_string(info, "algo")?,
                digits: optional_int(info.get("digits"), "OTP digits")?,
                period: optional_int(info.get("period"), "OTP period")?,
                counter: optional_int(info.get("counter"), "HOTP counter")?,
                allow_steam: true,
            })?;
            let tags: Vec<String> = entry
                .get("groups")
                .and_then(Value::as_array)
                .into_iter()
                .flatten()
                .filter_map(Value::as_str)
                .filter_map(|id| groups.get(id).cloned())
                .collect();
            Ok(ImportedCode {
                uri,
                display: Some(Display {
                    pinned: entry
                        .get("favorite")
                        .and_then(Value::as_bool)
                        .unwrap_or(false),
                    tags,
                    note: string(entry.get("note")).unwrap_or_default().to_owned(),
                    ..Display::default()
                }),
            })
        })();
        codes.push(result.map_err(|error| Error::entry(entry, error))?);
    }
    Ok(batch(codes))
}

pub fn parse_andotp(entries: &str) -> Result<Batch> {
    let entries: Value =
        serde_json::from_str(entries).map_err(|_| Error::invalid("Invalid andOTP export"))?;
    let entries = entries
        .as_array()
        .ok_or_else(|| Error::invalid("Invalid andOTP export"))?;
    let mut codes = Vec::new();
    let mut skipped = 0;
    for entry in entries {
        let kind = required_string(entry, "type")?.to_ascii_lowercase();
        if !matches!(kind.as_str(), "totp" | "hotp" | "steam") {
            skipped += 1;
            continue;
        }
        let result: Result<ImportedCode> = (|| {
            let issuer = string(entry.get("issuer")).unwrap_or_default();
            let account = string(entry.get("label")).unwrap_or_default();
            let digits = optional_int(entry.get("digits"), "OTP digits")?;
            let period = optional_int(entry.get("period"), "OTP period")?;
            let uri = build_uri(Otp {
                kind: &kind,
                issuer,
                account,
                secret: required_string(entry, "secret")?,
                algorithm: string(entry.get("algorithm")).unwrap_or("SHA1"),
                digits: digits.filter(|digits| *digits != 0),
                period: period.filter(|period| *period != 0),
                counter: optional_int(entry.get("counter"), "HOTP counter")?,
                allow_steam: true,
            })?;
            let tags: Vec<String> = entry
                .get("tags")
                .and_then(Value::as_array)
                .map(|values| values.iter().map(value_string).collect())
                .unwrap_or_default();
            Ok(ImportedCode {
                uri,
                display: (!tags.is_empty()).then_some(Display {
                    tags,
                    ..Display::default()
                }),
            })
        })();
        codes.push(result.map_err(|error| Error::entry(entry, error))?);
    }
    Ok(Batch { codes, skipped })
}

pub fn parse_bitwarden(export: &str) -> Result<Batch> {
    let export: Value =
        serde_json::from_str(export).map_err(|_| Error::invalid("Invalid Bitwarden export"))?;
    if export.get("encrypted").and_then(Value::as_bool) == Some(true) {
        return Err(Error::invalid(
            "Encrypted Bitwarden exports are not supported",
        ));
    }
    let folders = export
        .get("folders")
        .and_then(Value::as_array)
        .map(|folders| {
            folders
                .iter()
                .filter_map(|folder| {
                    Some((
                        string(folder.get("id"))?.to_owned(),
                        string(folder.get("name"))?.to_owned(),
                    ))
                })
                .collect::<HashMap<_, _>>()
        })
        .unwrap_or_default();
    let items = export
        .get("items")
        .and_then(Value::as_array)
        .ok_or_else(|| Error::invalid("Invalid Bitwarden export"))?;
    let mut codes = Vec::new();
    for item in items {
        let Some(login) = item.get("login").and_then(Value::as_object) else {
            continue;
        };
        let Some(totp) = string(login.get("totp")) else {
            continue;
        };
        let result: Result<ImportedCode> = (|| {
            let mut display = None;
            let uri = if totp.contains("otpauth://") {
                display = display_from_uri(totp)?;
                rebuild_uri(totp, None, None, None)?
            } else if let Some(index) = totp.find("steam://") {
                build_uri(Otp {
                    kind: "steam",
                    issuer: string(item.get("name")).unwrap_or_default(),
                    account: string(login.get("username")).unwrap_or_default(),
                    secret: &totp[index + "steam://".len()..],
                    algorithm: "SHA1",
                    digits: Some(STEAM_DIGITS),
                    period: None,
                    counter: None,
                    allow_steam: true,
                })?
            } else {
                build_uri(Otp {
                    kind: "totp",
                    issuer: string(item.get("name")).unwrap_or_default(),
                    account: string(login.get("username")).unwrap_or_default(),
                    secret: totp,
                    algorithm: "SHA1",
                    digits: Some(DEFAULT_DIGITS),
                    period: None,
                    counter: None,
                    allow_steam: true,
                })?
            };
            let folder = string(item.get("folderId")).and_then(|id| folders.get(id).cloned());
            let note = string(item.get("notes"));
            if let Some(folder) = folder {
                display.get_or_insert_with(Display::default).tags = vec![folder];
            }
            if let Some(note) = note {
                display.get_or_insert_with(Display::default).note = note.to_owned();
            }
            Ok(ImportedCode { uri, display })
        })();
        codes.push(result.map_err(|error| Error::entry(item, error))?);
    }
    Ok(batch(codes))
}

pub fn parse_lastpass(export: &str) -> Result<Batch> {
    let export: Value =
        serde_json::from_str(export).map_err(|_| Error::invalid("Invalid LastPass export"))?;
    let accounts = export
        .get("accounts")
        .and_then(Value::as_array)
        .ok_or_else(|| Error::invalid("Invalid LastPass export"))?;
    let mut codes = Vec::with_capacity(accounts.len());
    for account in accounts {
        let uri = build_uri(Otp {
            kind: "totp",
            issuer: required_string(account, "issuerName")?,
            account: required_string(account, "userName")?,
            secret: required_string(account, "secret")?,
            algorithm: required_string(account, "algorithm")?,
            digits: optional_int(account.get("digits"), "OTP digits")?,
            period: optional_int(account.get("timeStep"), "OTP period")?,
            counter: None,
            allow_steam: true,
        })
        .map_err(|error| Error::entry(account, error))?;
        codes.push(ImportedCode { uri, display: None });
    }
    Ok(batch(codes))
}

pub fn parse_proton(export: &str) -> Result<Batch> {
    let export: Value =
        serde_json::from_str(export).map_err(|_| Error::invalid("Invalid Proton export"))?;
    if int(export.get("version")) != Some(1) {
        return Err(Error::invalid("Invalid Proton export"));
    }
    let entries = export
        .get("entries")
        .and_then(Value::as_array)
        .ok_or_else(|| Error::invalid("Password protected or invalid Proton export"))?;
    let mut codes = Vec::new();
    let mut skipped = 0;
    for entry in entries {
        let result = (|| {
            let content = entry.get("content")?.as_object()?;
            let kind = string(content.get("entry_type"))?;
            let source_uri = string(content.get("uri"))?;
            let uri = match kind {
                "Steam" if source_uri.starts_with("steam://") => build_uri(Otp {
                    kind: "steam",
                    issuer: string(content.get("name"))
                        .filter(|name| !name.trim().is_empty())
                        .unwrap_or("Steam")
                        .trim(),
                    account: "",
                    secret: &source_uri["steam://".len()..],
                    algorithm: "SHA1",
                    digits: Some(STEAM_DIGITS),
                    period: None,
                    counter: None,
                    allow_steam: true,
                })
                .ok()?,
                "Totp" if source_uri.starts_with("otpauth://") => {
                    canonical_totp(source_uri).ok()?
                }
                _ => return None,
            };
            let display = Display {
                note: string(entry.get("note")).unwrap_or_default().to_owned(),
                ..Display::default()
            };
            Some(ImportedCode {
                uri: uri_with_display(&uri, &display).ok()?,
                display: None,
            })
        })();
        match result {
            Some(code) => codes.push(code),
            None => skipped += 1,
        }
    }
    Ok(Batch { codes, skipped })
}

pub fn parse_raivo(export: &str) -> Result<Batch> {
    let export: Value =
        serde_json::from_str(export).map_err(|_| Error::invalid("Invalid Raivo export"))?;
    let entries = export
        .as_array()
        .ok_or_else(|| Error::invalid("Invalid Raivo export"))?;
    let mut codes = Vec::with_capacity(entries.len());
    for entry in entries {
        let uri = build_uri(Otp {
            kind: required_string(entry, "kind")?,
            issuer: required_string(entry, "issuer")?,
            account: required_string(entry, "account")?,
            secret: required_string(entry, "secret")?,
            algorithm: required_string(entry, "algorithm")?,
            digits: optional_int(entry.get("digits"), "OTP digits")?,
            period: optional_int(entry.get("timer"), "OTP period")?,
            counter: optional_int(entry.get("counter"), "HOTP counter")?,
            allow_steam: false,
        })
        .map_err(|error| Error::entry(entry, error))?;
        codes.push(ImportedCode { uri, display: None });
    }
    Ok(batch(codes))
}

pub fn parse_two_fas(export: &str, decrypted_services: Option<&str>) -> Result<Batch> {
    if export.trim_start().starts_with("otpauth://") {
        return super::parse_plain_text(export);
    }
    let export: Value =
        serde_json::from_str(export).map_err(|_| Error::invalid("Invalid 2FAS export"))?;
    let version = int(export.get("schemaVersion")).unwrap_or(0);
    if !matches!(version, 3 | 4) {
        return Err(Error::invalid(format!(
            "Unsupported 2FAS export version: {version}"
        )));
    }
    let groups = export
        .get("groups")
        .and_then(Value::as_array)
        .map(|groups| {
            groups
                .iter()
                .filter_map(|group| {
                    Some((
                        string(group.get("id"))?.to_owned(),
                        string(group.get("name"))?.to_owned(),
                    ))
                })
                .collect::<HashMap<_, _>>()
        })
        .unwrap_or_default();
    let services_value: Value;
    let services = if let Some(decrypted) = decrypted_services {
        services_value = serde_json::from_str(decrypted)
            .map_err(|_| Error::invalid("Invalid decrypted 2FAS services"))?;
        services_value.as_array()
    } else {
        export.get("services").and_then(Value::as_array)
    }
    .ok_or_else(|| Error::invalid("Invalid 2FAS export"))?;
    let mut codes = Vec::with_capacity(services.len());
    for service in services {
        let result: Result<ImportedCode> = (|| {
            let otp = service
                .get("otp")
                .and_then(Value::as_object)
                .ok_or_else(|| Error::invalid("Invalid 2FAS service"))?;
            let kind = string(otp.get("tokenType")).unwrap_or("TOTP");
            let issuer = string(service.get("name"))
                .filter(|name| !name.is_empty())
                .or_else(|| string(otp.get("issuer")).filter(|issuer| !issuer.is_empty()));
            let account = string(otp.get("account")).or_else(|| string(otp.get("label")));
            let secret = required_string(service, "secret")?;
            let link = string(otp.get("link")).filter(|link| !link.is_empty());
            let source_is_link =
                string(otp.get("source")).is_some_and(|source| source.eq_ignore_ascii_case("link"));
            let link_identity = if source_is_link && (issuer.is_none() || account.is_none()) {
                link.map(otp_uri_identity).transpose()?
            } else {
                None
            };
            let issuer =
                issuer.or_else(|| link_identity.as_ref().map(|(issuer, _)| issuer.as_str()));
            let account =
                account.or_else(|| link_identity.as_ref().map(|(_, account)| account.as_str()));
            let uri = build_uri(Otp {
                kind,
                issuer: issuer.unwrap_or_default(),
                account: account.unwrap_or_default(),
                secret,
                algorithm: string(otp.get("algorithm")).unwrap_or("SHA1"),
                digits: optional_int(otp.get("digits"), "OTP digits")?,
                period: optional_int(otp.get("period"), "OTP period")?,
                counter: optional_int(otp.get("counter"), "HOTP counter")?,
                allow_steam: true,
            })?;
            let group = string(service.get("groupId")).and_then(|id| groups.get(id).cloned());
            Ok(ImportedCode {
                uri,
                display: group.map(|group| Display {
                    tags: vec![group],
                    ..Display::default()
                }),
            })
        })();
        codes.push(result.map_err(|error| Error::entry(service, error))?);
    }
    Ok(batch(codes))
}

fn canonical_totp(uri: &str) -> Result<String> {
    let parsed = url::Url::parse(&uri.replace('#', "%23"))
        .map_err(|_| Error::invalid("Invalid Proton OTP URI"))?;
    if parsed.host_str() != Some("totp") {
        return Err(Error::invalid("Invalid Proton OTP URI"));
    }
    let query: HashMap<String, String> = parsed
        .query_pairs()
        .map(|(name, value)| (name.into_owned(), value.into_owned()))
        .collect();
    let label = urlencoding::decode(parsed.path().trim_start_matches('/'))
        .map_err(|_| Error::invalid("Invalid Proton OTP label"))?;
    let issuer = query
        .get("issuer")
        .map(ToString::to_string)
        .or_else(|| label.split_once(':').map(|(issuer, _)| issuer.to_owned()))
        .unwrap_or_else(|| label.to_string());
    let account = label
        .strip_prefix(&format!("{issuer}:"))
        .or_else(|| label.split_once(':').map(|(_, account)| account))
        .unwrap_or(&label);
    build_uri(Otp {
        kind: "totp",
        issuer: &issuer,
        account,
        secret: query
            .get("secret")
            .ok_or_else(|| Error::invalid("Invalid Proton OTP URI"))?,
        algorithm: query.get("algorithm").map_or("SHA1", AsRef::as_ref),
        digits: query_int(&query, "digits")?,
        period: query_int(&query, "period")?,
        counter: None,
        allow_steam: true,
    })
}

fn batch(codes: Vec<ImportedCode>) -> Batch {
    Batch { codes, skipped: 0 }
}

fn required_string<'a>(value: &'a Value, name: &str) -> Result<&'a str> {
    string(value.get(name)).ok_or_else(|| Error::invalid(format!("Missing {name}")))
}

fn value_string(value: &Value) -> String {
    match value {
        Value::String(value) => value.clone(),
        _ => value.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn imports_plaintext_proton_fixture() {
        let export = include_str!(
            "../../../../../mobile/apps/auth/test/ui/settings/data/import/fixtures/proton_authenticator_backup.json"
        );
        let batch = parse_proton(export).unwrap();
        assert_eq!(batch.codes.len(), 4);
        assert_eq!(batch.skipped, 0);
        assert!(batch.codes[0].uri.contains(".env:example%40ente.io"));
        assert!(batch.codes[3].uri.contains("issuer=reddit"));
    }

    #[test]
    fn imports_supported_json_formats() {
        let aegis = r#"{"groups":[{"uuid":"g","name":"Work"}],"entries":[{"type":"totp","name":"alice","issuer":"Example","favorite":true,"groups":["g"],"note":"note","info":{"algo":"SHA1","secret":"MY","period":30,"digits":6}}]}"#;
        let code = &parse_aegis(aegis).unwrap().codes[0];
        let display = code.display.as_ref().unwrap();
        assert!(display.pinned);
        assert_eq!(display.tags, ["Work"]);
        assert_eq!(display.note, "note");

        let andotp = r#"[{"type":"TOTP","issuer":"Example","label":"alice","secret":"MY","tags":["Work"]},{"type":"YOTP"}]"#;
        let batch = parse_andotp(andotp).unwrap();
        assert_eq!(batch.codes.len(), 1);
        assert_eq!(batch.skipped, 1);

        let bitwarden = r#"{"folders":[{"id":"f","name":"Work"}],"items":[{"name":"Example","folderId":"f","notes":"note","login":{"username":"alice","totp":"MY"}}]}"#;
        let code = &parse_bitwarden(bitwarden).unwrap().codes[0];
        assert_eq!(code.display.as_ref().unwrap().tags, ["Work"]);

        let lastpass = r#"{"accounts":[{"issuerName":"Example","userName":"alice","secret":"MY","algorithm":"SHA1","digits":6,"timeStep":30}]}"#;
        assert_eq!(parse_lastpass(lastpass).unwrap().codes.len(), 1);

        let raivo = r#"[{"kind":"totp","issuer":"Example","account":"alice","secret":"MY","algorithm":"SHA1","digits":6,"timer":30}]"#;
        assert_eq!(parse_raivo(raivo).unwrap().codes.len(), 1);

        let two_fas = r#"{"schemaVersion":4,"groups":[{"id":"g","name":"Work"}],"services":[{"name":"Example","groupId":"g","secret":"MY","otp":{"tokenType":"TOTP","account":"alice","digits":6}}]}"#;
        let code = &parse_two_fas(two_fas, None).unwrap().codes[0];
        assert_eq!(code.display.as_ref().unwrap().tags, ["Work"]);
    }

    #[test]
    fn rejects_unsupported_algorithms_and_invalid_explicit_parameters() {
        let unsupported_aegis = r#"{"entries":[{"type":"totp","name":"alice","issuer":"Example","info":{"algo":"SHA224","secret":"MY","period":30,"digits":6}}]}"#;
        assert!(parse_aegis(unsupported_aegis).is_err());

        for entry in [
            r#"[{"type":"TOTP","secret":"MY","digits":"invalid"}]"#,
            r#"[{"type":"TOTP","secret":"MY","algorithm":"SHA384"}]"#,
        ] {
            assert!(parse_andotp(entry).is_err());
        }

        let code = &parse_andotp(r#"[{"type":"TOTP","secret":"MY","period":-30}]"#)
            .unwrap()
            .codes[0]
            .uri;
        assert!(code.contains("period=30"));

        let code = &parse_andotp(r#"[{"type":"TOTP","secret":"MY"}]"#)
            .unwrap()
            .codes[0]
            .uri;
        assert!(code.contains("algorithm=SHA1"));
        assert!(code.contains("digits=6"));
        assert!(code.contains("period=30"));

        let code = &parse_andotp(r#"[{"type":"TOTP","secret":"MY","digits":0,"period":0}]"#)
            .unwrap()
            .codes[0]
            .uri;
        assert!(code.contains("digits=6"));
        assert!(code.contains("period=30"));

        let unsupported_uri = r#"{"folders":[],"items":[{"name":"Broken","login":{"totp":"otpauth://totp/alice?secret=MY&algorithm=SHA224"}}]}"#;
        let error = parse_bitwarden(unsupported_uri).err().unwrap();
        assert!(error.entry_text().unwrap().contains("Broken"));

        let invalid_secret =
            r#"{"folders":[],"items":[{"name":"Broken","login":{"totp":"not base32!"}}]}"#;
        let error = parse_bitwarden(invalid_secret).err().unwrap();
        assert!(error.entry_text().unwrap().contains("Broken"));
    }

    #[test]
    fn rejects_encrypted_bitwarden_exports_clearly() {
        for export in [
            r#"{"encrypted":true,"folders":[],"items":[{"login":{"totp":"2.encrypted|value"}}]}"#,
            r#"{"encrypted":true,"passwordProtected":true,"salt":"salt","kdfIterations":600000,"kdfType":0,"encKeyValidation_DO_NOT_EDIT":"2.validation","data":"2.encrypted"}"#,
        ] {
            let error = parse_bitwarden(export).err().unwrap();
            assert_eq!(
                error.message(),
                "Encrypted Bitwarden exports are not supported"
            );
        }
    }

    #[test]
    fn bitwarden_preserves_embedded_display_when_adding_folder_and_note() {
        let embedded = serde_json::json!({
            "pinned": true,
            "trashed": true,
            "tags": ["Old"],
            "note": "old note",
            "iconSrc": "custom",
            "iconID": "icon"
        })
        .to_string();
        let export = serde_json::json!({
            "folders": [{"id": "f", "name": "Work"}],
            "items": [{
                "name": "Example",
                "folderId": "f",
                "notes": "new note",
                "login": {
                    "totp": format!(
                        "otpauth://totp/alice?secret=MY&codeDisplay={}#suffix",
                        urlencoding::encode(&embedded)
                    )
                }
            }]
        })
        .to_string();

        let code = &parse_bitwarden(&export).unwrap().codes[0];
        let display = code.display.as_ref().unwrap();
        assert!(display.pinned);
        assert!(display.trashed);
        assert_eq!(display.tags, ["Work"]);
        assert_eq!(display.note, "new note");
        assert_eq!(display.icon_src, "custom");
        assert_eq!(display.icon_id, "icon");
    }

    #[test]
    fn two_fas_uses_current_parameters_with_edited_labels() {
        let export = r#"{
            "schemaVersion": 4,
            "services": [{
                "name": "Edited Name",
                "secret": "MY",
                "otp": {
                    "source": "Link",
                    "link": "otpauth://totp/Original:original%40example.com?secret=%5Bhidden%5D&issuer=Original&algorithm=SHA256&digits=8&period=60",
                    "issuer": "Stale Issuer",
                    "account": "edited@example.com",
                    "algorithm": "SHA1",
                    "digits": 6,
                    "period": 30
                }
            }]
        }"#;
        let uri = &parse_two_fas(export, None).unwrap().codes[0].uri;
        assert!(uri.starts_with("otpauth://totp/Edited%20Name:edited%40example.com?"));
        assert!(uri.contains("secret=MY"));
        assert!(uri.contains("issuer=Edited%20Name"));
        assert!(uri.contains("algorithm=SHA1"));
        assert!(uri.contains("digits=6"));
        assert!(uri.contains("period=30"));
    }

    #[test]
    fn two_fas_uses_link_labels_and_manual_fallbacks() {
        let link_only = r#"{
            "schemaVersion": 4,
            "services": [{
                "name": "",
                "secret": "MY",
                "otp": {
                    "source": "link",
                    "link": "otpauth://totp/LinkIssuer:link-account?secret=%5Bhidden%5D&issuer=LinkIssuer"
                }
            }]
        }"#;
        let uri = &parse_two_fas(link_only, None).unwrap().codes[0].uri;
        assert!(uri.starts_with("otpauth://totp/LinkIssuer:link-account?"));

        let manual = r#"{
            "schemaVersion": 4,
            "services": [{
                "name": "Manual Name",
                "secret": "MY",
                "otp": {
                    "source": "manual",
                    "link": "otpauth://totp/Wrong:wrong?secret=MY&algorithm=SHA224",
                    "label": "manual-account",
                    "issuer": "Stale Issuer",
                    "algorithm": "SHA512",
                    "digits": 8,
                    "period": 60
                }
            }]
        }"#;
        let uri = &parse_two_fas(manual, None).unwrap().codes[0].uri;
        assert!(uri.starts_with("otpauth://totp/Manual%20Name:manual-account?"));
        assert!(uri.contains("algorithm=SHA512"));
        assert!(uri.contains("digits=8"));
        assert!(uri.contains("period=60"));
    }

    #[test]
    fn canonical_totp_rejects_malformed_explicit_numbers() {
        let base = "otpauth://totp/Example:alice?secret=MY&issuer=Example";
        let uri = canonical_totp(base).unwrap();
        assert!(uri.contains("digits=6"));
        assert!(uri.contains("period=30"));

        for parameter in ["digits=invalid", "period=invalid"] {
            assert!(canonical_totp(&format!("{base}&{parameter}")).is_err());
        }

        for parameter in ["digits=0", "period=0"] {
            let uri = canonical_totp(&format!("{base}&{parameter}")).unwrap();
            assert!(uri.contains("digits=6"));
            assert!(uri.contains("period=30"));
        }

        let uri = canonical_totp("otpauth://totp/whole-label?secret=MY").unwrap();
        assert!(uri.starts_with("otpauth://totp/whole-label:whole-label?"));
        assert!(uri.contains("issuer=whole-label"));
    }
}
