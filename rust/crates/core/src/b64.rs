use base64::{
    Engine, alphabet,
    engine::general_purpose::{
        GeneralPurpose, GeneralPurposeConfig, STANDARD, URL_SAFE, URL_SAFE_NO_PAD,
    },
};

pub use base64::DecodeError;

pub fn decode(input: &str) -> Result<Vec<u8>, DecodeError> {
    STANDARD.decode(input)
}

// Browser atob ignores unused trailing bits in otherwise valid base64.
pub fn decode_allow_trailing_bits(input: &str) -> Result<Vec<u8>, DecodeError> {
    GeneralPurpose::new(
        &alphabet::STANDARD,
        GeneralPurposeConfig::new().with_decode_allow_trailing_bits(true),
    )
    .decode(input)
}

// Standard base64 (RFC 4648), matching libsodium's
// `sodium_base64_VARIANT_ORIGINAL`.
pub fn encode(input: &[u8]) -> String {
    STANDARD.encode(input)
}

// The URL-safe alphabet with padding matches libsodium's
// `sodium_base64_VARIANT_URLSAFE` and Go's `base64.URLEncoding`.
pub fn encode_url_safe(input: &[u8]) -> String {
    URL_SAFE.encode(input)
}

pub fn decode_url_safe(input: &str) -> Result<Vec<u8>, DecodeError> {
    URL_SAFE.decode(input)
}

pub fn encode_url_safe_no_padding(input: &[u8]) -> String {
    URL_SAFE_NO_PAD.encode(input)
}

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
        let bytes = [0xfbu8, 0xef];
        assert_eq!(encode_url_safe(&bytes), "--8=");
        assert_eq!(encode_url_safe_no_padding(&bytes), "--8");
        assert_eq!(decode_url_safe_no_padding("--8").unwrap(), bytes);
    }
}
