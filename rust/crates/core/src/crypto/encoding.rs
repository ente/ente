//! Base64 encoding and decoding.
//!
//! Conversions between bytes and their textual forms: standard and URL-safe
//! base64. These move key material and ciphertext across text boundaries such
//! as JSON and URLs; they are plumbing, not themselves cryptographic.

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
/// Returns [`Base64Decode`](crate::crypto::Error::Base64Decode) if
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
/// Returns [`Base64Decode`](crate::crypto::Error::Base64Decode) if
/// `input` is not valid unpadded URL-safe base64.
pub fn decode_b64_url_safe_no_padding(input: &str) -> Result<Vec<u8>> {
    Ok(BASE64_URL_SAFE_NO_PAD.decode(input)?)
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
}
