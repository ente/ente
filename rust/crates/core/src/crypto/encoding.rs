//! Base64 and hex encoding and decoding.
//!
//! Conversions between bytes and their textual forms: standard and URL-safe
//! base64, hexadecimal, and base64 to hex. These move key material and
//! ciphertext across text boundaries such as JSON and URLs; they are plumbing,
//! not themselves cryptographic.

use base64::{
    Engine,
    engine::general_purpose::{
        STANDARD as BASE64, URL_SAFE as BASE64_URL_SAFE, URL_SAFE_NO_PAD as BASE64_URL_SAFE_NO_PAD,
    },
};

use crate::crypto::Result;

/// Decode a standard base64 string to bytes, the inverse of [`encode_b64`].
///
/// # Errors
///
/// Returns [`Base64Decode`](crate::crypto::CryptoError::Base64Decode) if
/// `input` is not valid standard base64.
pub fn decode_b64(input: &str) -> Result<Vec<u8>> {
    Ok(BASE64.decode(input)?)
}

/// Encode bytes to a standard base64 string, the inverse of [`decode_b64`].
///
/// Standard base64 (RFC 4648 §4), matching libsodium's
/// `sodium_base64_VARIANT_ORIGINAL`.
pub fn encode_b64(input: &[u8]) -> String {
    BASE64.encode(input)
}

/// Decode a base64 string to bytes.
///
/// Alias for [`decode_b64`], matching libsodium's `base642bin()` naming.
pub fn base642bin(input: &str) -> Result<Vec<u8>> {
    decode_b64(input)
}

/// Encode bytes to a URL-safe base64 string.
///
/// This uses the URL-safe alphabet (RFC 4648 §5) with padding, matching
/// libsodium's `sodium_base64_VARIANT_URLSAFE` and Go's `base64.URLEncoding`.
pub fn encode_b64_url_safe(input: &[u8]) -> String {
    BASE64_URL_SAFE.encode(input)
}

/// Encode bytes to an unpadded URL-safe base64 string.
///
/// Like [`encode_b64_url_safe`] but without trailing "=" padding, as required
/// e.g. when serializing WebAuthn binary values.
pub fn encode_b64_url_safe_no_padding(input: &[u8]) -> String {
    BASE64_URL_SAFE_NO_PAD.encode(input)
}

/// Decode an unpadded URL-safe base64 string to bytes, the inverse of
/// [`encode_b64_url_safe_no_padding`].
///
/// # Errors
///
/// Returns [`Base64Decode`](crate::crypto::CryptoError::Base64Decode) if
/// `input` is not valid unpadded URL-safe base64.
pub fn decode_b64_url_safe_no_padding(input: &str) -> Result<Vec<u8>> {
    Ok(BASE64_URL_SAFE_NO_PAD.decode(input)?)
}

/// Return the UTF-8 bytes of `input`.
pub fn str_to_bin(input: &str) -> Vec<u8> {
    input.as_bytes().to_vec()
}

/// Decode a hex string to bytes, the inverse of [`encode_hex`].
///
/// # Errors
///
/// Returns [`HexDecode`](crate::crypto::CryptoError::HexDecode) if `input` is
/// not valid hexadecimal.
pub fn decode_hex(input: &str) -> Result<Vec<u8>> {
    Ok(hex::decode(input)?)
}

/// Encode bytes to a lowercase hex string, the inverse of [`decode_hex`].
pub fn encode_hex(input: &[u8]) -> String {
    hex::encode(input)
}

/// Re-encode a standard base64 string as lowercase hex, the inverse of
/// [`hex_to_b64`].
///
/// # Errors
///
/// Returns [`Base64Decode`](crate::crypto::CryptoError::Base64Decode) if `b64`
/// is not valid standard base64.
pub fn b64_to_hex(b64: &str) -> Result<String> {
    let bytes = decode_b64(b64)?;
    Ok(encode_hex(&bytes))
}

/// Re-encode a hex string as standard base64, the inverse of [`b64_to_hex`].
///
/// # Errors
///
/// Returns [`HexDecode`](crate::crypto::CryptoError::HexDecode) if `hex_str` is
/// not valid hexadecimal.
pub fn hex_to_b64(hex_str: &str) -> Result<String> {
    let bytes = decode_hex(hex_str)?;
    Ok(encode_b64(&bytes))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_base64_roundtrip() {
        let original = b"Hello, World!";
        let encoded = encode_b64(original);
        let decoded = decode_b64(&encoded).unwrap();
        assert_eq!(decoded, original);
    }

    #[test]
    fn test_hex_roundtrip() {
        let original = b"Hello, World!";
        let encoded = encode_hex(original);
        let decoded = decode_hex(&encoded).unwrap();
        assert_eq!(decoded, original);
    }

    #[test]
    fn test_b64_to_hex() {
        let original = b"Test";
        let b64 = encode_b64(original);
        let hex = b64_to_hex(&b64).unwrap();
        assert_eq!(hex, "54657374"); // "Test" in hex
    }

    #[test]
    fn test_hex_to_b64() {
        let hex = "54657374"; // "Test" in hex
        let b64 = hex_to_b64(hex).unwrap();
        let decoded = decode_b64(&b64).unwrap();
        assert_eq!(decoded, b"Test");
    }

    #[test]
    fn test_str_to_bin_ascii() {
        let bytes = str_to_bin("Hello");
        assert_eq!(bytes, b"Hello");
    }

    #[test]
    fn test_str_to_bin_unicode() {
        let bytes = str_to_bin("✓");
        assert_eq!(bytes, vec![0xE2, 0x9C, 0x93]);
    }

    #[test]
    fn test_invalid_base64() {
        let result = decode_b64("not valid base64!!!");
        assert!(result.is_err());
    }

    #[test]
    fn test_url_safe_variants() {
        // 0xfb 0xef exercises the -_ alphabet; 2 bytes forces padding
        let bytes = [0xfbu8, 0xef];
        assert_eq!(encode_b64_url_safe(&bytes), "--8=");
        assert_eq!(encode_b64_url_safe_no_padding(&bytes), "--8");
        assert_eq!(decode_b64_url_safe_no_padding("--8").unwrap(), bytes);
    }

    #[test]
    fn test_invalid_hex() {
        let result = decode_hex("not valid hex!!!");
        assert!(result.is_err());
    }
}
