//! Base64 encoding and decoding.

use base64::{
    Engine,
    engine::general_purpose::{STANDARD, URL_SAFE, URL_SAFE_NO_PAD},
};

pub use base64::DecodeError;

/// Decode a standard base64 string to bytes, the inverse of [`encode`].
pub fn decode(input: &str) -> Result<Vec<u8>, DecodeError> {
    STANDARD.decode(input)
}

/// Encode bytes to a standard base64 string, the inverse of [`decode`].
///
/// Standard base64 (RFC 4648 §4), matching libsodium's
/// `sodium_base64_VARIANT_ORIGINAL`.
pub fn encode(input: &[u8]) -> String {
    STANDARD.encode(input)
}

/// Encode bytes to a URL-safe base64 string.
///
/// This uses the URL-safe alphabet (RFC 4648 §5) with padding, matching
/// libsodium's `sodium_base64_VARIANT_URLSAFE` and Go's `base64.URLEncoding`.
pub fn encode_url_safe(input: &[u8]) -> String {
    URL_SAFE.encode(input)
}

/// Decode a URL-safe base64 string to bytes, the inverse of
/// [`encode_url_safe`].
pub fn decode_url_safe(input: &str) -> Result<Vec<u8>, DecodeError> {
    URL_SAFE.decode(input)
}

/// Encode bytes to an unpadded URL-safe base64 string.
///
/// Like [`encode_url_safe`] but without trailing "=" padding, as required
/// e.g. when serializing WebAuthn binary values.
pub fn encode_url_safe_no_padding(input: &[u8]) -> String {
    URL_SAFE_NO_PAD.encode(input)
}

/// Decode an unpadded URL-safe base64 string to bytes, the inverse of
/// [`encode_url_safe_no_padding`].
pub fn decode_url_safe_no_padding(input: &str) -> Result<Vec<u8>, DecodeError> {
    URL_SAFE_NO_PAD.decode(input)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_base64_roundtrip() {
        let original = b"Hello, World!";
        let encoded = encode(original);
        let decoded = decode(&encoded).unwrap();
        assert_eq!(decoded, original);
    }

    #[test]
    fn test_invalid_base64() {
        let result = decode("not valid base64!!!");
        assert!(result.is_err());
    }

    #[test]
    fn test_url_safe_variants() {
        // 0xfb 0xef exercises the -_ alphabet; 2 bytes forces padding
        let bytes = [0xfbu8, 0xef];
        assert_eq!(encode_url_safe(&bytes), "--8=");
        assert_eq!(encode_url_safe_no_padding(&bytes), "--8");
        assert_eq!(decode_url_safe_no_padding("--8").unwrap(), bytes);
    }
}
