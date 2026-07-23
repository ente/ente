use ente_core::crypto::{self, SecretVec};
use sha2::{Digest, Sha256};

use crate::{
    ContactsError, Result,
    legacy_kit_models::{LEGACY_KIT_PAYLOAD_VERSION, LegacyKitShare, LegacyKitVariant},
};

pub(super) fn checksum(
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
    crypto::encode_b64(&hash[..8])
}

pub(super) fn split_secret_2_of_3(secret: &[u8]) -> Result<Vec<Vec<u8>>> {
    if secret.len() != 32 {
        return Err(ContactsError::InvalidInput(
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

pub(super) fn reconstruct_secret_2_of_3(shares: &[LegacyKitShare]) -> Result<SecretVec> {
    if shares.len() < 2 {
        return Err(ContactsError::InvalidInput(
            "at least two legacy kit shares are required".into(),
        ));
    }
    let first = &shares[0];
    let second = &shares[1];
    validate_share_header(first)?;
    validate_share_header(second)?;
    if first.payload_version != second.payload_version {
        return Err(ContactsError::InvalidInput(
            "legacy kit share payload version mismatch".into(),
        ));
    }
    if first.variant != second.variant {
        return Err(ContactsError::InvalidInput(
            "legacy kit share variant mismatch".into(),
        ));
    }
    if first.kit_id != second.kit_id {
        return Err(ContactsError::InvalidInput(
            "legacy kit shares must belong to the same kit".into(),
        ));
    }
    if first.checksum != second.checksum {
        return Err(ContactsError::InvalidInput(
            "legacy kit share checksum mismatch".into(),
        ));
    }
    if first.share_index == second.share_index {
        return Err(ContactsError::InvalidInput(
            "legacy kit shares must use different indices".into(),
        ));
    }

    let y1 = crypto::decode_b64(&first.share)?;
    let y2 = crypto::decode_b64(&second.share)?;
    if y1.len() != 32 || y2.len() != 32 {
        return Err(ContactsError::InvalidInput(
            "legacy kit shares must be 32 bytes".into(),
        ));
    }

    let x1 = first.share_index;
    let x2 = second.share_index;
    let denom = x1 ^ x2;
    if denom == 0 {
        return Err(ContactsError::InvalidInput(
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
        return Err(ContactsError::InvalidInput(
            "legacy kit shares failed checksum verification".into(),
        ));
    }
    Ok(SecretVec::new(secret))
}

pub(super) fn used_part_indexes(shares: &[LegacyKitShare]) -> Result<Vec<u8>> {
    let first = shares.first().ok_or_else(|| {
        ContactsError::InvalidInput("at least two legacy kit shares are required".into())
    })?;
    validate_share_header(first)?;
    if shares.len() < first.variant.threshold() {
        return Err(ContactsError::InvalidInput(
            "at least two legacy kit shares are required".into(),
        ));
    }
    Ok(vec![shares[0].share_index, shares[1].share_index])
}

fn validate_share_header(share: &LegacyKitShare) -> Result<()> {
    if share.payload_version != LEGACY_KIT_PAYLOAD_VERSION {
        return Err(ContactsError::InvalidInput(
            "unsupported legacy kit share payload version".into(),
        ));
    }
    if share.variant != LegacyKitVariant::TwoOfThree {
        return Err(ContactsError::InvalidInput(
            "unsupported legacy kit share variant".into(),
        ));
    }
    if share.share_index == 0 || share.share_index as usize > share.variant.part_count() {
        return Err(ContactsError::InvalidInput(
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
        return Err(ContactsError::InvalidInput(
            "cannot invert zero in GF(256)".into(),
        ));
    }
    Ok(gf_pow(value, 254))
}

fn gf_div(value: u8, divisor: u8) -> Result<u8> {
    Ok(gf_mul(value, gf_inv(divisor)?))
}
