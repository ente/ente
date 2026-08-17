use crate::{b64, crypto};

const RANDOM_BYTES: usize = 16;

pub fn random(prefix: &str) -> String {
    format!(
        "{prefix}_{}",
        b64::encode_url_safe_no_padding(&crypto::random_bytes(RANDOM_BYTES))
    )
}
