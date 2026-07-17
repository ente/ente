//! WASM bindings for authentication and account crypto.

use ente_core::{auth as core_auth, crypto as core_crypto};
use serde_wasm_bindgen as swb;
use wasm_bindgen::prelude::*;

/// Auth error.
#[wasm_bindgen]
pub struct AuthError {
    code: String,
    message: String,
}

#[wasm_bindgen]
impl AuthError {
    /// A machine-readable error code.
    #[wasm_bindgen(getter)]
    pub fn code(&self) -> String {
        self.code.clone()
    }

    /// Human-readable error message.
    #[wasm_bindgen(getter)]
    pub fn message(&self) -> String {
        self.message.clone()
    }
}

impl From<core_auth::AuthError> for AuthError {
    fn from(e: core_auth::AuthError) -> Self {
        use core_auth::AuthError as E;

        let code = match &e {
            E::IncorrectPassword => "incorrect_password",
            E::IncorrectRecoveryKey => "incorrect_recovery_key",
            E::InvalidKeyAttributes => "invalid_key_attributes",
            E::InsufficientMemory => "insufficient_memory",
            E::MissingField(_) => "missing_field",
            E::Crypto(_) => "crypto",
            E::Decode(_) => "decode",
            E::InvalidKey(_) => "invalid_key",
            E::Srp(_) => "srp",
        }
        .to_string();

        Self {
            code,
            message: ente_core::error::chain(&e),
        }
    }
}

impl From<swb::Error> for AuthError {
    fn from(e: swb::Error) -> Self {
        Self {
            code: "serde".to_string(),
            message: e.to_string(),
        }
    }
}

/// SRP credentials derived from a password.
#[wasm_bindgen]
pub struct SrpCredentials {
    kek: String,
    login_key: String,
}

#[wasm_bindgen]
impl SrpCredentials {
    /// Key-encryption-key (base64).
    #[wasm_bindgen(getter)]
    pub fn kek(&self) -> String {
        self.kek.clone()
    }

    /// SRP login key (base64, 16 bytes).
    #[wasm_bindgen(getter)]
    pub fn login_key(&self) -> String {
        self.login_key.clone()
    }
}

/// Decrypted secrets after successful authentication.
#[wasm_bindgen]
pub struct DecryptedSecrets {
    master_key: String,
    secret_key: String,
    token: String,
}

#[wasm_bindgen]
impl DecryptedSecrets {
    /// Master key (base64).
    #[wasm_bindgen(getter)]
    pub fn master_key(&self) -> String {
        self.master_key.clone()
    }

    /// Secret key (base64).
    #[wasm_bindgen(getter)]
    pub fn secret_key(&self) -> String {
        self.secret_key.clone()
    }

    /// Auth token (URL-safe base64).
    #[wasm_bindgen(getter)]
    pub fn token(&self) -> String {
        self.token.clone()
    }
}

/// A generated KEK and its derivation parameters.
#[wasm_bindgen]
pub struct GeneratedKek {
    key: String,
    salt: String,
    mem_limit: u32,
    ops_limit: u32,
}

#[wasm_bindgen]
impl GeneratedKek {
    /// Derived KEK (base64).
    #[wasm_bindgen(getter)]
    pub fn key(&self) -> String {
        self.key.clone()
    }

    /// Salt used for derivation (base64).
    #[wasm_bindgen(getter)]
    pub fn salt(&self) -> String {
        self.salt.clone()
    }

    /// Argon2 memory limit in bytes.
    #[wasm_bindgen(getter)]
    pub fn mem_limit(&self) -> u32 {
        self.mem_limit
    }

    /// Argon2 operations limit.
    #[wasm_bindgen(getter)]
    pub fn ops_limit(&self) -> u32 {
        self.ops_limit
    }
}

/// SRP setup payload generated from a KEK.
#[wasm_bindgen]
pub struct GeneratedSrpSetup {
    srp_salt: String,
    srp_verifier: String,
    login_sub_key: String,
}

#[wasm_bindgen]
impl GeneratedSrpSetup {
    /// SRP salt (base64).
    #[wasm_bindgen(getter)]
    pub fn srp_salt(&self) -> String {
        self.srp_salt.clone()
    }

    /// SRP verifier (base64).
    #[wasm_bindgen(getter)]
    pub fn srp_verifier(&self) -> String {
        self.srp_verifier.clone()
    }

    /// SRP login sub-key (base64, 16 bytes).
    #[wasm_bindgen(getter)]
    pub fn login_sub_key(&self) -> String {
        self.login_sub_key.clone()
    }
}

/// Derive SRP credentials (KEK + login key) from a password and SRP attributes.
///
/// `srp_attrs` must match the shape returned by the Ente API's
/// `/users/srp/attributes` endpoint (i.e. camelCased fields).
#[wasm_bindgen]
pub fn auth_derive_srp_credentials(
    password: &str,
    srp_attrs: JsValue,
) -> Result<SrpCredentials, AuthError> {
    let srp_attrs: core_auth::SrpAttributes = swb::from_value(srp_attrs)?;

    let creds = core_auth::derive_srp_credentials(password, &srp_attrs)?;

    Ok(SrpCredentials {
        kek: core_crypto::encode_b64(&creds.kek),
        login_key: core_crypto::encode_b64(&creds.login_key),
    })
}

/// Derive the key-encryption-key (KEK) from password and KEK parameters.
///
/// Returns the KEK as base64.
#[wasm_bindgen]
pub fn auth_derive_kek(
    password: &str,
    kek_salt_b64: &str,
    mem_limit: u32,
    ops_limit: u32,
) -> Result<String, AuthError> {
    let kek = core_auth::derive_kek(password, kek_salt_b64, mem_limit, ops_limit)?;
    Ok(core_crypto::encode_b64(&kek))
}

/// Generate a KEK using the current sensitive web derivation policy.
#[wasm_bindgen]
pub fn auth_generate_sensitive_kek(password: &str) -> Result<GeneratedKek, AuthError> {
    let generated = core_auth::generate_sensitive_kek(password)?;
    Ok(GeneratedKek {
        key: core_crypto::encode_b64(&generated.key),
        salt: core_crypto::encode_b64(&generated.salt),
        mem_limit: generated.mem_limit,
        ops_limit: generated.ops_limit,
    })
}

/// Generate a KEK using the current interactive web derivation policy.
#[wasm_bindgen]
pub fn auth_generate_interactive_kek(password: &str) -> Result<GeneratedKek, AuthError> {
    let generated = core_auth::generate_interactive_kek(password)?;
    Ok(GeneratedKek {
        key: core_crypto::encode_b64(&generated.key),
        salt: core_crypto::encode_b64(&generated.salt),
        mem_limit: generated.mem_limit,
        ops_limit: generated.ops_limit,
    })
}

/// Generate the SRP setup payload for a given KEK and SRP user ID.
#[wasm_bindgen]
pub fn auth_generate_srp_setup(
    kek_b64: &str,
    srp_user_id: &str,
) -> Result<GeneratedSrpSetup, AuthError> {
    let kek = core_crypto::decode_b64(kek_b64).map_err(|e| AuthError {
        code: "decode".to_string(),
        message: format!("kek: {}", e),
    })?;

    let generated = core_auth::generate_srp_setup(&kek, srp_user_id)?;
    Ok(GeneratedSrpSetup {
        srp_salt: core_crypto::encode_b64(&generated.srp_salt),
        srp_verifier: core_crypto::encode_b64(&generated.srp_verifier),
        login_sub_key: core_crypto::encode_b64(&generated.login_sub_key),
    })
}

/// Convert a recovery key mnemonic or legacy hex string into base64 bytes.
#[wasm_bindgen]
pub fn auth_recovery_key_from_mnemonic_or_hex(input: &str) -> Result<String, AuthError> {
    let recovery_key = core_auth::recovery_key_from_mnemonic_or_hex(input)?;
    Ok(core_crypto::encode_b64(&recovery_key))
}

/// Convert a base64-encoded recovery key into its English mnemonic.
#[wasm_bindgen]
pub fn auth_recovery_key_to_mnemonic(recovery_key_b64: &str) -> Result<String, AuthError> {
    core_auth::recovery_key_to_mnemonic(recovery_key_b64).map_err(Into::into)
}

/// Decrypt the master key, secret key and auth token.
///
/// `key_attrs` should be the `keyAttributes` object from the auth response.
/// `encrypted_token_b64` is the `encryptedToken` string from the auth response.
#[wasm_bindgen]
pub fn auth_decrypt_secrets(
    kek_b64: &str,
    key_attrs: JsValue,
    encrypted_token_b64: &str,
) -> Result<DecryptedSecrets, AuthError> {
    let kek = core_crypto::decode_b64(kek_b64).map_err(|e| AuthError {
        code: "decode".to_string(),
        message: format!("kek: {}", e),
    })?;

    let key_attrs: core_auth::KeyAttributes = swb::from_value(key_attrs)?;

    let secrets = core_auth::decrypt_secrets(&kek, &key_attrs, encrypted_token_b64)?;

    Ok(DecryptedSecrets {
        master_key: core_crypto::encode_b64(&secrets.master_key),
        secret_key: core_crypto::encode_b64(&secrets.secret_key),
        token: core_crypto::encode_b64_url_safe(&secrets.token),
    })
}

/// Result of decrypting only the master key and secret key.
#[wasm_bindgen]
pub struct DecryptedKeys {
    master_key: String,
    secret_key: String,
}

#[wasm_bindgen]
impl DecryptedKeys {
    /// Master key (base64).
    #[wasm_bindgen(getter)]
    pub fn master_key(&self) -> String {
        self.master_key.clone()
    }

    /// Secret key (base64).
    #[wasm_bindgen(getter)]
    pub fn secret_key(&self) -> String {
        self.secret_key.clone()
    }
}

/// Decrypt only the master key and secret key.
///
/// Useful when the auth token is obtained separately.
#[wasm_bindgen]
pub fn auth_decrypt_keys_only(
    kek_b64: &str,
    key_attrs: JsValue,
) -> Result<DecryptedKeys, AuthError> {
    let kek = core_crypto::decode_b64(kek_b64).map_err(|e| AuthError {
        code: "decode".to_string(),
        message: format!("kek: {}", e),
    })?;
    let key_attrs: core_auth::KeyAttributes = swb::from_value(key_attrs)?;

    let (master_key, secret_key) = core_auth::decrypt_keys_only(&kek, &key_attrs)?;

    Ok(DecryptedKeys {
        master_key: core_crypto::encode_b64(&master_key),
        secret_key: core_crypto::encode_b64(&secret_key),
    })
}

/// SRP (Secure Remote Password) session.
///
/// This is a small state machine:
/// - Create session
/// - Send `public_a()` to server
/// - Receive `srpB` from server, compute `srpM1`
/// - Receive `srpM2` from server, verify
#[wasm_bindgen]
pub struct SrpSession {
    inner: core_auth::SrpSession,
}

#[wasm_bindgen]
impl SrpSession {
    /// Create a new SRP session.
    ///
    /// All inputs are base64 strings except `srp_user_id`.
    #[wasm_bindgen(constructor)]
    pub fn new(
        srp_user_id: &str,
        srp_salt_b64: &str,
        login_key_b64: &str,
    ) -> Result<SrpSession, AuthError> {
        let srp_salt = core_crypto::decode_b64(srp_salt_b64)
            .map_err(|e| core_auth::AuthError::Decode(format!("srp_salt: {}", e)))?;
        let login_key = core_crypto::decode_b64(login_key_b64)
            .map_err(|e| core_auth::AuthError::Decode(format!("login_key: {}", e)))?;

        let inner = core_auth::SrpSession::new(srp_user_id, &srp_salt, &login_key)?;
        Ok(Self { inner })
    }

    /// Get the public ephemeral value A as base64.
    pub fn public_a(&self) -> String {
        core_crypto::encode_b64(&self.inner.public_a())
    }

    /// Compute the client proof M1 from the server's public value B (base64).
    pub fn compute_m1(&mut self, srp_b_b64: &str) -> Result<String, AuthError> {
        let srp_b = core_crypto::decode_b64(srp_b_b64)
            .map_err(|e| core_auth::AuthError::Decode(format!("srpB: {}", e)))?;
        let m1 = self.inner.compute_m1(&srp_b)?;
        Ok(core_crypto::encode_b64(&m1))
    }

    /// Verify the server proof M2 (base64).
    pub fn verify_m2(&self, srp_m2_b64: &str) -> Result<(), AuthError> {
        let srp_m2 = core_crypto::decode_b64(srp_m2_b64)
            .map_err(|e| core_auth::AuthError::Decode(format!("srpM2: {}", e)))?;
        self.inner.verify_m2(&srp_m2)?;
        Ok(())
    }
}
