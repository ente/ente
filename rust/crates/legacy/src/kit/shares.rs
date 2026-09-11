use ente_core::b64;
use ente_core::crypto::{self, SecretVec};
use sha2::{Digest, Sha256};

use crate::{Error, Result};

use super::models::{LEGACY_KIT_PAYLOAD_VERSION, LegacyKitShare, LegacyKitVariant};

impl LegacyKitShare {
    pub fn parse(input: &str) -> Result<Self> {
        let input = input.trim_matches(sheet_whitespace);
        let json = if input.starts_with('{') {
            input.to_owned()
        } else {
            let mut encoded = compact(input).replace('-', "+").replace('_', "/");
            while !encoded.len().is_multiple_of(4) {
                encoded.push('=');
            }
            let bytes = b64::decode_allow_trailing_bits(&encoded)?;
            let decoded = String::from_utf8_lossy(&bytes);
            decoded
                .strip_prefix('\u{feff}')
                .unwrap_or(&decoded)
                .to_owned()
        };
        // JSON.parse accepts duplicate keys and integer-valued floats.
        let mut value: serde_json::Value =
            serde_json::from_str(&json).map_err(|error| Error::InvalidInput(error.to_string()))?;
        for field in ["pv", "kv", "i"] {
            if let Some(number) = value.get(field).and_then(serde_json::Value::as_f64)
                && number.fract() == 0.0
                && (0.0..=255.0).contains(&number)
            {
                value[field] = serde_json::Value::from(number as u8);
            }
        }
        let mut share: Self = serde_json::from_value(value)
            .map_err(|error| Error::InvalidInput(error.to_string()))?;
        share.compact_fields();
        validate_share_header(&share)?;
        if share.kit_id.is_empty() || share.part_name.is_empty() {
            return Err(Error::InvalidInput(
                "legacy kit ID and part name must be non-empty".into(),
            ));
        }
        if b64::decode_allow_trailing_bits(&share.share)?.len() != 32
            || b64::decode_allow_trailing_bits(&share.checksum)?.len() != 8
        {
            return Err(Error::InvalidInput(
                "invalid legacy kit share or checksum length".into(),
            ));
        }
        Ok(share)
    }

    pub fn to_qr_payload(&self) -> Result<String> {
        let mut share = self.clone();
        share.compact_fields();
        serde_json::to_string(&share).map_err(|error| Error::InvalidInput(error.to_string()))
    }

    pub fn to_copy_code(&self) -> Result<String> {
        Ok(b64::encode_url_safe_no_padding(
            self.to_qr_payload()?.as_bytes(),
        ))
    }

    fn compact_fields(&mut self) {
        self.kit_id = compact(&self.kit_id);
        self.share = compact(&self.share);
        self.checksum = compact(&self.checksum);
    }
}

fn compact(value: &str) -> String {
    value
        .chars()
        .filter(|character| !sheet_whitespace(*character))
        .collect()
}

fn sheet_whitespace(character: char) -> bool {
    (character.is_whitespace() && character != '\u{0085}') || character == '\u{feff}'
}

pub fn validate_share_pair(first: &LegacyKitShare, second: &LegacyKitShare) -> Result<()> {
    if first.kit_id != second.kit_id {
        return Err(Error::DifferentLegacyKits);
    }
    if first.share_index == second.share_index {
        return Err(Error::DuplicateLegacyKitShare);
    }
    Ok(())
}

pub(crate) fn checksum(
    payload_version: u8,
    variant: LegacyKitVariant,
    kit_id: &str,
    kit_secret: &[u8],
) -> String {
    let mut digest = Sha256::new();
    digest.update([payload_version, variant.code()]);
    digest.update(kit_id.as_bytes());
    digest.update(kit_secret);
    let hash = digest.finalize();
    b64::encode(&hash[..8])
}

pub(crate) fn split_secret_2_of_3(secret: &[u8]) -> Result<Vec<Vec<u8>>> {
    if secret.len() != 32 {
        return Err(Error::InvalidInput(
            "legacy kit secret must be 32 bytes".into(),
        ));
    }
    let slope = crypto::SecretVec::new(crypto::random_bytes(32));
    let xs = [1u8, 2u8, 3u8];
    let mut shares = Vec::with_capacity(3);
    for x in xs {
        let share = secret
            .iter()
            .zip(slope.iter())
            .map(|(s, a)| *s ^ gf_mul(*a, x))
            .collect::<Vec<_>>();
        shares.push(share);
    }
    Ok(shares)
}

pub(crate) fn reconstruct_secret_2_of_3(shares: &[LegacyKitShare]) -> Result<SecretVec> {
    if shares.len() < 2 {
        return Err(Error::InvalidInput(
            "at least two legacy kit shares are required".into(),
        ));
    }
    let first = &shares[0];
    let second = &shares[1];
    validate_share_header(first)?;
    validate_share_header(second)?;
    if first.payload_version != second.payload_version {
        return Err(Error::InvalidInput(
            "legacy kit share payload version mismatch".into(),
        ));
    }
    if first.variant != second.variant {
        return Err(Error::InvalidInput(
            "legacy kit share variant mismatch".into(),
        ));
    }
    if first.kit_id != second.kit_id {
        return Err(Error::DifferentLegacyKits);
    }
    if first.checksum != second.checksum {
        return Err(Error::InvalidInput(
            "legacy kit share checksum mismatch".into(),
        ));
    }
    if first.share_index == second.share_index {
        return Err(Error::DuplicateLegacyKitShare);
    }

    let y1 = b64::decode(&first.share)?;
    let y2 = b64::decode(&second.share)?;
    if y1.len() != 32 || y2.len() != 32 {
        return Err(Error::InvalidInput(
            "legacy kit shares must be 32 bytes".into(),
        ));
    }

    let x1 = first.share_index;
    let x2 = second.share_index;
    let denom = x1 ^ x2;
    if denom == 0 {
        return Err(Error::InvalidInput(
            "legacy kit shares must use different x coordinates".into(),
        ));
    }
    let mut secret = vec![0u8; 32];
    for i in 0..32 {
        let slope = gf_div(y1[i] ^ y2[i], denom)?;
        secret[i] = y1[i] ^ gf_mul(slope, x1);
    }
    let expected = checksum(first.payload_version, first.variant, &first.kit_id, &secret);
    if expected != first.checksum {
        return Err(Error::InvalidInput(
            "legacy kit shares failed checksum verification".into(),
        ));
    }
    Ok(SecretVec::new(secret))
}

pub(crate) fn used_part_indexes(shares: &[LegacyKitShare]) -> Result<Vec<u8>> {
    let first = shares
        .first()
        .ok_or_else(|| Error::InvalidInput("at least two legacy kit shares are required".into()))?;
    validate_share_header(first)?;
    if shares.len() < first.variant.threshold() {
        return Err(Error::InvalidInput(
            "at least two legacy kit shares are required".into(),
        ));
    }
    Ok(vec![shares[0].share_index, shares[1].share_index])
}

fn validate_share_header(share: &LegacyKitShare) -> Result<()> {
    if share.payload_version != LEGACY_KIT_PAYLOAD_VERSION {
        return Err(Error::InvalidInput(
            "unsupported legacy kit share payload version".into(),
        ));
    }
    if share.variant != LegacyKitVariant::TwoOfThree {
        return Err(Error::InvalidInput(
            "unsupported legacy kit share variant".into(),
        ));
    }
    if share.share_index == 0 || share.share_index as usize > share.variant.part_count() {
        return Err(Error::InvalidInput(
            "legacy kit share index is out of range".into(),
        ));
    }
    Ok(())
}

fn gf_mul(mut a: u8, mut b: u8) -> u8 {
    let mut product = 0u8;
    while b != 0 {
        if b & 1 != 0 {
            product ^= a;
        }
        let high = a & 0x80;
        a <<= 1;
        if high != 0 {
            a ^= 0x1b;
        }
        b >>= 1;
    }
    product
}

fn gf_pow(mut base: u8, mut exp: u8) -> u8 {
    let mut acc = 1u8;
    while exp != 0 {
        if exp & 1 != 0 {
            acc = gf_mul(acc, base);
        }
        base = gf_mul(base, base);
        exp >>= 1;
    }
    acc
}

fn gf_inv(value: u8) -> Result<u8> {
    if value == 0 {
        return Err(Error::InvalidInput("cannot invert zero in GF(256)".into()));
    }
    Ok(gf_pow(value, 254))
}

fn gf_div(value: u8, divisor: u8) -> Result<u8> {
    Ok(gf_mul(value, gf_inv(divisor)?))
}
