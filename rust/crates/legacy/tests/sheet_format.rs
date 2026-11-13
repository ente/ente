#![cfg(test)]

use ente_core::b64;
use ente_legacy::{Error, LegacyKitRecoveryClient, LegacyKitShare, validate_share_pair};
use serde::Deserialize;
use serde_json::json;

#[derive(Deserialize)]
struct MobileSheet {
    qr_payload: String,
    copy_code: String,
}

fn mobile_sheets() -> Vec<MobileSheet> {
    serde_json::from_str(include_str!("fixtures/mobile-sheets.json"))
        .expect("mobile sheet fixtures should be valid JSON")
}

#[test]
fn reads_and_reproduces_existing_mobile_sheets() {
    let sheets = mobile_sheets();
    for sheet in &sheets {
        let share = LegacyKitShare::parse(&sheet.qr_payload).unwrap();
        assert_eq!(LegacyKitShare::parse(&sheet.copy_code).unwrap(), share);
        assert_eq!(share.to_qr_payload().unwrap(), sheet.qr_payload);
        assert_eq!(share.to_copy_code().unwrap(), sheet.copy_code);
    }
    for pair in [[0, 1], [0, 2], [1, 2]] {
        let shares = pair.map(|index| LegacyKitShare::parse(&sheets[index].copy_code).unwrap());
        validate_share_pair(&shares[0], &shares[1]).unwrap();
        assert_eq!(
            LegacyKitRecoveryClient::reconstruct_secret(&shares)
                .unwrap()
                .as_ref(),
            &[7; 32],
        );
    }
}

#[test]
fn preserves_copying_and_json_variations() {
    let sheet = &mobile_sheets()[3];
    let share = LegacyKitShare::parse(&sheet.qr_payload).unwrap();
    for encoded in [
        b64::encode(sheet.qr_payload.as_bytes()),
        b64::encode_url_safe(sheet.qr_payload.as_bytes()),
        sheet.copy_code.clone(),
    ] {
        let wrapped = encoded
            .chars()
            .map(|c| format!("{c}\n\u{feff}"))
            .collect::<String>();
        assert_eq!(LegacyKitShare::parse(&wrapped).unwrap(), share);
    }

    let mut spaced = share.clone();
    spaced.kit_id = format!(" \u{feff}{}\t", share.kit_id);
    spaced.share = share.share.chars().map(|c| format!("{c}\n")).collect();
    spaced.checksum = format!("\u{a0}{}\r", share.checksum);
    assert_eq!(spaced.to_qr_payload().unwrap(), sheet.qr_payload);
    assert_eq!(
        LegacyKitShare::parse(&serde_json::to_string(&spaced).unwrap()).unwrap(),
        share,
    );
    let json = sheet
        .qr_payload
        .replace("\"pv\":1", "\"pv\":9,\"pv\":1.0")
        .replace("\"kv\":1", "\"kv\":1e0");
    assert_eq!(LegacyKitShare::parse(&json).unwrap(), share);
    let encoded = b64::encode(format!("\u{feff}{}", sheet.qr_payload).as_bytes());
    assert_eq!(LegacyKitShare::parse(&encoded).unwrap(), share);
    let encoded = b64::encode(format!("\u{feff}\u{feff}{}", sheet.qr_payload).as_bytes());
    assert!(LegacyKitShare::parse(&encoded).is_err());
}

#[test]
fn rejects_invalid_sheet_fields() {
    let payload: serde_json::Value = serde_json::from_str(&mobile_sheets()[0].qr_payload).unwrap();
    for (field, value) in [
        ("pv", json!(2)),
        ("kv", json!(2)),
        ("i", json!(0)),
        ("i", json!(4)),
        ("i", json!(1.5)),
        ("k", json!(" \n")),
        ("n", json!("")),
        ("s", json!(b64::encode(&[0; 31]))),
        ("c", json!(b64::encode(&[0; 7]))),
        ("s", json!("A".repeat(43))),
        ("c", json!("!!!!!!!!!!!=")),
    ] {
        let mut invalid = payload.clone();
        invalid[field] = value;
        assert!(
            LegacyKitShare::parse(&invalid.to_string()).is_err(),
            "{field}"
        );
    }
    for field in ["pv", "kv", "k", "i", "s", "c", "n"] {
        let mut invalid = payload.clone();
        invalid.as_object_mut().unwrap().remove(field);
        assert!(
            LegacyKitShare::parse(&invalid.to_string()).is_err(),
            "missing {field}"
        );
    }
}

#[test]
fn pair_errors_remain_distinct_from_checksum_verification() {
    let sheets = mobile_sheets();
    let first = LegacyKitShare::parse(&sheets[0].copy_code).unwrap();
    let mut second = LegacyKitShare::parse(&sheets[1].copy_code).unwrap();
    assert!(matches!(
        validate_share_pair(&first, &first),
        Err(Error::DuplicateLegacyKitShare)
    ));
    second.kit_id = "another-kit".into();
    assert!(matches!(
        validate_share_pair(&first, &second),
        Err(Error::DifferentLegacyKits)
    ));
    second.kit_id = first.kit_id.clone();
    second.checksum = b64::encode(&[0; 8]);
    validate_share_pair(&first, &second).unwrap();
    assert!(LegacyKitRecoveryClient::reconstruct_secret(&[first, second]).is_err());
}
