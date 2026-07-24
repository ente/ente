pub mod auth;
pub mod contacts;
pub mod legacy;
pub mod legacy_kit;

use ente_test_support::HARDCODED_OTT_EMAIL_SUFFIX;
use uuid::Uuid;

pub fn unique_test_email(prefix: &str) -> String {
    format!("{prefix}-{}{HARDCODED_OTT_EMAIL_SUFFIX}", Uuid::new_v4())
}

pub fn unique_password(prefix: &str) -> String {
    format!("{prefix}-{}!", Uuid::new_v4().simple())
}
