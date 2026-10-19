use hmac::{Hmac, KeyInit, Mac};
use sha1::Sha1;
use sha2::{Sha256, Sha512};
use zeroize::Zeroizing;

use crate::crypto::SecretVec;

#[derive(thiserror::Error, Debug)]
pub enum Error {
    #[error("Invalid Base32 OTP secret")]
    InvalidSecret,
    #[error("OTP requires one to ten digits and a positive period")]
    InvalidParameters,
}

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Clone, Copy)]
pub enum Algorithm {
    Sha1,
    Sha256,
    Sha512,
}

pub fn decode_secret(secret: &str) -> Result<SecretVec> {
    let secret = Zeroizing::new(secret.trim().replace(' ', ""));
    let mut bytes = Zeroizing::new(Vec::new());
    let mut buffer = 0u32;
    let mut bits = 0;
    for byte in secret
        .trim_end_matches('=')
        .bytes()
        .map(|b| b.to_ascii_uppercase())
    {
        let value = match byte {
            b'A'..=b'Z' => byte - b'A',
            b'2'..=b'7' => byte - b'2' + 26,
            _ => return Err(Error::InvalidSecret),
        };
        buffer = (buffer << 5) | u32::from(value);
        bits += 5;
        if bits >= 8 {
            bits -= 8;
            bytes.push((buffer >> bits) as u8);
        }
    }
    if bytes.is_empty() {
        return Err(Error::InvalidSecret);
    }
    Ok(SecretVec::new(std::mem::take(&mut *bytes)))
}

pub fn totp(
    secret: &[u8],
    time: u64,
    period: u64,
    digits: u32,
    algorithm: Algorithm,
) -> Result<String> {
    if period == 0 || !(1..=10).contains(&digits) {
        return Err(Error::InvalidParameters);
    }
    let value = u64::from(truncate(secret, time / period, algorithm)?);
    Ok(format!(
        "{:0width$}",
        value % 10u64.pow(digits),
        width = digits as usize
    ))
}

pub fn steam(secret: &[u8], time: u64) -> Result<String> {
    let alphabet = b"23456789BCDFGHJKMNPQRTVWXY";
    let mut value = truncate(secret, time / 30, Algorithm::Sha1)?;
    Ok((0..5)
        .map(|_| {
            let letter = alphabet[value as usize % alphabet.len()] as char;
            value /= alphabet.len() as u32;
            letter
        })
        .collect())
}

fn digest<M: Mac + KeyInit>(secret: &[u8], counter: u64) -> Result<Zeroizing<Vec<u8>>> {
    let mut mac = M::new_from_slice(secret).map_err(|_| Error::InvalidSecret)?;
    mac.update(&counter.to_be_bytes());
    Ok(Zeroizing::new(mac.finalize().into_bytes().to_vec()))
}

fn truncate(secret: &[u8], counter: u64, algorithm: Algorithm) -> Result<u32> {
    let digest = match algorithm {
        Algorithm::Sha1 => digest::<Hmac<Sha1>>(secret, counter),
        Algorithm::Sha256 => digest::<Hmac<Sha256>>(secret, counter),
        Algorithm::Sha512 => digest::<Hmac<Sha512>>(secret, counter),
    }?;
    let offset = (digest[digest.len() - 1] & 15) as usize;
    let bytes = &digest[offset..offset + 4];
    Ok(u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]) & 0x7fff_ffff)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rfc6238_vectors_and_extended_formats() {
        let sha1 = b"12345678901234567890";
        let sha256 = b"12345678901234567890123456789012";
        let sha512 = b"1234567890123456789012345678901234567890123456789012345678901234";
        for (time, expected) in [
            (59, ["94287082", "46119246", "90693936"]),
            (20_000_000_000, ["65353130", "77737706", "47863826"]),
        ] {
            for ((secret, algorithm), expected) in [
                (sha1.as_slice(), Algorithm::Sha1),
                (sha256.as_slice(), Algorithm::Sha256),
                (sha512.as_slice(), Algorithm::Sha512),
            ]
            .into_iter()
            .zip(expected)
            {
                assert_eq!(totp(secret, time, 30, 8, algorithm).unwrap(), expected);
            }
        }
        assert_eq!(totp(sha1, 59, 30, 1, Algorithm::Sha1).unwrap(), "2");
        assert_eq!(
            totp(sha1, 59, 30, 10, Algorithm::Sha1).unwrap(),
            "1094287082"
        );
        assert_eq!(steam(sha1, 59).unwrap(), "PV9M4");
        assert_eq!(steam(sha1, 60).unwrap(), "B26KJ");
        for (period, digits) in [(0, 6), (30, 0), (30, 11)] {
            assert!(totp(sha1, 59, period, digits, Algorithm::Sha1).is_err());
        }
    }

    #[test]
    fn secrets_allow_app_normalization_and_short_keys() {
        let secret = decode_secret("  my= = ====  ").unwrap();
        assert_eq!(&*secret, b"f");
        assert_eq!(totp(&secret, 59, 30, 6, Algorithm::Sha1).unwrap(), "300412");
        assert_eq!(&*decode_secret("mzxw 6ytb").unwrap(), b"fooba");
        for invalid in ["", "!secret!", "AAAA1", "A"] {
            assert!(decode_secret(invalid).is_err());
        }
    }
}
