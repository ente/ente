//! The account key hierarchy and login protocol.
//!
//! Key generation at sign-up, secret decryption at login, recovery keys, and
//! the SRP handshake ([`SrpSession`]).

mod api;
mod key_gen;
mod recovery;
mod srp;
mod types;

pub use srp::SrpSession;

// High-level API (recommended for applications)
pub use api::{DecryptedSecrets, GeneratedKek, GeneratedSrpSetup, SrpCredentials};
pub use api::{
    decrypt_keys_only, decrypt_secrets, derive_kek, derive_srp_credentials,
    generate_interactive_kek, generate_sensitive_kek, generate_srp_setup,
    generate_srp_setup_with_login_key,
};

// Key generation (for signup)
pub use key_gen::{
    KeyDerivationStrength, create_new_recovery_key, generate_key_attributes_for_new_password,
    generate_key_attributes_for_new_password_with_strength, generate_keys_with_strength,
};

// Recovery
pub use recovery::{get_recovery_key, recovery_key_from_mnemonic_or_hex, recovery_key_to_mnemonic};

// Types
pub use types::{
    AuthError, KeyAttributes, KeyGenResult, PrivateKeyAttributes, Result, SrpAttributes,
};
