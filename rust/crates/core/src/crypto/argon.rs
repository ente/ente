//! Deriving keys from passwords with Argon2id.
//!
//! Argon2id stretches a low-entropy, human-chosen password into a key, spending
//! tunable memory and time to make brute-force guessing expensive. Use it to
//! turn a passphrase into a key; to derive subkeys from a key that is already
//! high-entropy, use [`kdf`](super::kdf) instead.
//!
//! The same password, salt, and [`Params`] always produce the same key, so the
//! salt and parameters must be stored alongside the data for other clients to
//! reproduce it (see [`DerivedKey`]).

use std::fmt;

use argon2::{Algorithm, Argon2, Params as Argon2Params, Version};

use crate::crypto::{CryptoError, Key, Result, Salt};

/// Argon2id cost parameters: how much memory to use and how many passes to make.
///
/// Higher values cost an attacker more but also slow legitimate derivation. Use
/// the presets ([`INTERACTIVE`](Self::INTERACTIVE), [`MODERATE`](Self::MODERATE),
/// [`SENSITIVE`](Self::SENSITIVE)) unless re-deriving a key with parameters that
/// were stored alongside it, such as the server's key attributes.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Params {
    /// Memory limit in bytes.
    pub mem_limit: u32,
    /// Operations (iterations) limit.
    pub ops_limit: u32,
}

impl Params {
    /// Parameters for interactive use (64 MiB, 2 ops): fast, for UI
    /// responsiveness.
    pub const INTERACTIVE: Self = Self {
        mem_limit: 67_108_864,
        ops_limit: 2,
    };

    /// Parameters for moderate-cost password gates (256 MiB, 3 ops).
    pub const MODERATE: Self = Self {
        mem_limit: 268_435_456,
        ops_limit: 3,
    };

    /// Parameters for sensitive keys (1 GiB, 4 ops).
    ///
    /// New sensitive derivations should normally go through
    /// [`derive_sensitive_key`], which adaptively trades memory for ops while
    /// preserving this strength.
    pub const SENSITIVE: Self = Self {
        mem_limit: 1_073_741_824,
        ops_limit: 4,
    };

    /// The cheapest parameters Argon2 accepts (8 KiB, 1 op).
    ///
    /// These provide essentially no brute-force protection, and are only for
    /// inputs that are already high-entropy keys (where the KDF is a
    /// formality), never for human-chosen passwords.
    pub const MIN: Self = Self {
        mem_limit: 8_192,
        ops_limit: 1,
    };
}

/// Minimum memory limit for adaptive sensitive derivation (128 MiB).
///
/// This matches the server-side floor for accepted account key attributes.
const MEMLIMIT_SENSITIVE_MIN: u32 = 134_217_728;

/// A key derived from a passphrase, along with the salt and parameters used.
///
/// The salt and parameters must be stored alongside the encrypted data: other
/// clients need them to re-derive the same key.
pub struct DerivedKey {
    /// The derived key.
    pub key: Key,
    /// The salt used for derivation.
    pub salt: Salt,
    /// The Argon2 parameters used for derivation.
    pub params: Params,
}

impl fmt::Debug for DerivedKey {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("DerivedKey")
            .field("key", &"[REDACTED]")
            .field("salt", &self.salt)
            .field("params", &self.params)
            .finish()
    }
}

/// Derive a key from `password` and `salt` with the given Argon2id `params`.
///
/// Deterministic: the same inputs always yield the same key, which is how other
/// clients reproduce it. The result is a [`Key`], zeroized on drop. To make a
/// new key, the `derive_*_key` helpers choose parameters and a salt for you.
///
/// # Errors
///
/// Returns
/// [`InvalidKeyDerivationParams`](CryptoError::InvalidKeyDerivationParams) if
/// `params` fall below the accepted minimum or memory is not a multiple of 1024
/// bytes.
///
/// Produces the same key as libsodium's `crypto_pwhash` with
/// `crypto_pwhash_ALG_ARGON2ID13`.
pub fn derive_key(password: &str, salt: &Salt, params: Params) -> Result<Key> {
    derive_key_impl(password.as_bytes(), salt, params)
}

fn derive_key_impl(password: &[u8], salt: &Salt, params: Params) -> Result<Key> {
    if params.mem_limit < Params::MIN.mem_limit {
        return Err(CryptoError::InvalidKeyDerivationParams(format!(
            "Memory limit {} is below minimum {}",
            params.mem_limit,
            Params::MIN.mem_limit
        )));
    }

    if !params.mem_limit.is_multiple_of(1024) {
        return Err(CryptoError::InvalidKeyDerivationParams(format!(
            "Memory limit {} must be a multiple of 1024 bytes",
            params.mem_limit
        )));
    }

    if params.ops_limit < Params::MIN.ops_limit {
        return Err(CryptoError::InvalidKeyDerivationParams(format!(
            "Operations limit {} is below minimum {}",
            params.ops_limit,
            Params::MIN.ops_limit
        )));
    }

    // Convert bytes to KiB (Argon2 uses KiB internally)
    let m_cost = params.mem_limit / 1024;
    let t_cost = params.ops_limit;
    let p_cost = 1; // Parallelism degree

    let argon2_params = Argon2Params::new(m_cost, t_cost, p_cost, Some(Key::BYTES))
        .map_err(|e| CryptoError::InvalidKeyDerivationParams(e.to_string()))?;

    let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, argon2_params);

    let mut key = [0u8; Key::BYTES];
    argon2
        .hash_password_into(password, salt.as_bytes(), &mut key)
        .map_err(CryptoError::Argon2)?;

    Ok(Key::from_bytes(key))
}

/// Derive a key from `password` with [`Params::INTERACTIVE`] and a freshly
/// generated salt.
///
/// Returns the key together with the salt and parameters used, which must be
/// stored to reproduce it.
pub fn derive_interactive_key(password: &str) -> Result<DerivedKey> {
    let salt = Salt::generate();
    let key = derive_key(password, &salt, Params::INTERACTIVE)?;
    Ok(DerivedKey {
        key,
        salt,
        params: Params::INTERACTIVE,
    })
}

/// Derive a key from `password` with [`Params::MODERATE`] and a freshly
/// generated salt.
///
/// Returns the key together with the salt and parameters used, which must be
/// stored to reproduce it.
pub fn derive_moderate_key(password: &str) -> Result<DerivedKey> {
    let salt = Salt::generate();
    let key = derive_key(password, &salt, Params::MODERATE)?;
    Ok(DerivedKey {
        key,
        salt,
        params: Params::MODERATE,
    })
}

/// Derive a high-security key from `password`, adapting the cost to the device.
///
/// Aims for [`Params::SENSITIVE`] strength but starts at moderate memory
/// (256 MiB) with the ops limit scaled up to compensate, then halves memory and
/// doubles ops whenever allocation fails, down to a 128 MiB floor (the
/// server-side minimum for accepted account key attributes). Holding the
/// product of memory and ops constant preserves the work factor while fitting
/// low-memory devices, and matches the policy used by the web and Flutter
/// clients so the same account derives consistently everywhere.
///
/// Returns the key together with the salt and parameters actually used, which
/// must be stored to reproduce it.
pub fn derive_sensitive_key(password: &str) -> Result<DerivedKey> {
    let salt = Salt::generate();
    derive_sensitive_adaptive(password.as_bytes(), &salt)
}

fn derive_sensitive_adaptive(password: &[u8], salt: &Salt) -> Result<DerivedKey> {
    if !Params::SENSITIVE
        .mem_limit
        .is_multiple_of(Params::MODERATE.mem_limit)
    {
        return Err(CryptoError::InvalidKeyDerivationParams(format!(
            "Memory limit {} must be divisible by {}",
            Params::SENSITIVE.mem_limit,
            Params::MODERATE.mem_limit
        )));
    }

    let desired_strength =
        u64::from(Params::SENSITIVE.mem_limit) * u64::from(Params::SENSITIVE.ops_limit);
    let factor = Params::SENSITIVE.mem_limit / Params::MODERATE.mem_limit;
    let mut mem_limit = Params::MODERATE.mem_limit;
    let mut ops_limit = Params::SENSITIVE
        .ops_limit
        .checked_mul(factor)
        .ok_or_else(|| {
            CryptoError::InvalidKeyDerivationParams("Operations limit overflow".to_string())
        })?;

    if u64::from(mem_limit) * u64::from(ops_limit) != desired_strength {
        return Err(CryptoError::InvalidKeyDerivationParams(format!(
            "Unexpected mem/ops limits: mem_limit {}, ops_limit {}",
            mem_limit, ops_limit
        )));
    }

    let mut last_error = None;
    while mem_limit >= MEMLIMIT_SENSITIVE_MIN {
        let params = Params {
            mem_limit,
            ops_limit,
        };
        match derive_key_impl(password, salt, params) {
            Ok(key) => {
                return Ok(DerivedKey {
                    key,
                    salt: *salt,
                    params,
                });
            }
            Err(err) => {
                last_error = Some(err);
            }
        }

        mem_limit /= 2;
        ops_limit = match ops_limit.checked_mul(2) {
            Some(value) => value,
            None => break,
        };
    }

    Err(last_error.unwrap_or(CryptoError::KeyDerivationFailed))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_salt() -> Salt {
        Salt::from_bytes([0x42u8; Salt::BYTES])
    }

    #[test]
    fn test_derive_key() {
        let password = "correct horse battery staple";
        let salt = Salt::generate();

        // Just checks the derivation succeeds; determinism and length are
        // covered below (length is in the type).
        derive_key(password, &salt, Params::INTERACTIVE).unwrap();
    }

    #[test]
    fn test_derive_key_deterministic() {
        let password = "test password";
        let salt = test_salt();

        let key1 = derive_key(password, &salt, Params::INTERACTIVE).unwrap();
        let key2 = derive_key(password, &salt, Params::INTERACTIVE).unwrap();

        assert_eq!(key1, key2);
    }

    #[test]
    fn test_different_passwords() {
        let salt = test_salt();

        let key1 = derive_key("password1", &salt, Params::INTERACTIVE).unwrap();
        let key2 = derive_key("password2", &salt, Params::INTERACTIVE).unwrap();

        assert_ne!(key1, key2);
    }

    #[test]
    fn test_different_salts() {
        let password = "same password";
        let salt1 = test_salt();
        let salt2 = Salt::from_bytes([0x43u8; Salt::BYTES]);

        let key1 = derive_key(password, &salt1, Params::INTERACTIVE).unwrap();
        let key2 = derive_key(password, &salt2, Params::INTERACTIVE).unwrap();

        assert_ne!(key1, key2);
    }

    #[test]
    fn test_different_params() {
        let password = "test";
        let salt = test_salt();

        let base = derive_key(password, &salt, Params::INTERACTIVE).unwrap();
        let more_mem = derive_key(
            password,
            &salt,
            Params {
                mem_limit: Params::MODERATE.mem_limit,
                ops_limit: Params::INTERACTIVE.ops_limit,
            },
        )
        .unwrap();
        let more_ops = derive_key(
            password,
            &salt,
            Params {
                mem_limit: Params::INTERACTIVE.mem_limit,
                ops_limit: Params::MODERATE.ops_limit,
            },
        )
        .unwrap();

        assert_ne!(base, more_mem);
        assert_ne!(base, more_ops);
    }

    #[test]
    fn test_derive_interactive_key() {
        let result = derive_interactive_key("interactive test").unwrap();
        assert_eq!(result.params, Params::INTERACTIVE);
    }

    #[test]
    fn test_derive_moderate_key() {
        let result = derive_moderate_key("moderate test").unwrap();
        assert_eq!(result.params, Params::MODERATE);
    }

    #[test]
    #[ignore] // Slow: uses high memory/ops settings
    fn test_derive_sensitive_key() {
        let result = derive_sensitive_key("sensitive test").unwrap();

        let desired_strength =
            u64::from(Params::SENSITIVE.mem_limit) * u64::from(Params::SENSITIVE.ops_limit);
        assert_eq!(
            u64::from(result.params.mem_limit) * u64::from(result.params.ops_limit),
            desired_strength
        );
        assert!(result.params.mem_limit <= Params::MODERATE.mem_limit);
        assert!(result.params.ops_limit >= Params::SENSITIVE.ops_limit);
        assert!(result.params.mem_limit >= MEMLIMIT_SENSITIVE_MIN);
    }

    #[test]
    fn test_sensitive_policy_matches_existing_client_bounds() {
        let desired_strength =
            u64::from(Params::SENSITIVE.mem_limit) * u64::from(Params::SENSITIVE.ops_limit);
        let factor = Params::SENSITIVE.mem_limit / Params::MODERATE.mem_limit;
        let mut mem_limit = Params::MODERATE.mem_limit;
        let mut ops_limit = Params::SENSITIVE.ops_limit * factor;
        let mut attempts = Vec::new();

        while mem_limit >= MEMLIMIT_SENSITIVE_MIN {
            attempts.push((mem_limit, ops_limit));
            mem_limit /= 2;
            ops_limit *= 2;
        }

        assert_eq!(
            attempts.first(),
            Some(&(
                Params::MODERATE.mem_limit,
                Params::SENSITIVE.ops_limit * factor
            ))
        );
        assert_eq!(attempts.last(), Some(&(MEMLIMIT_SENSITIVE_MIN, 32)));
        assert!(
            attempts
                .iter()
                .all(|(mem, ops)| u64::from(*mem) * u64::from(*ops) == desired_strength)
        );
    }

    #[test]
    fn test_derived_key_debug_redacts_secret_material() {
        let result = DerivedKey {
            key: Key::from_bytes([1u8; Key::BYTES]),
            salt: test_salt(),
            params: Params::INTERACTIVE,
        };

        let debug = format!("{result:?}");
        assert!(debug.contains("[REDACTED]"));
        assert!(!debug.contains("[1, 1, 1"));
    }

    #[test]
    fn test_memlimit_too_low() {
        let result = derive_key(
            "test",
            &Salt::generate(),
            Params {
                mem_limit: 4096,
                ops_limit: Params::INTERACTIVE.ops_limit,
            },
        );
        assert!(result.is_err());
    }

    #[test]
    fn test_memlimit_not_aligned() {
        let result = derive_key(
            "test",
            &Salt::generate(),
            Params {
                mem_limit: Params::INTERACTIVE.mem_limit + 1,
                ops_limit: Params::INTERACTIVE.ops_limit,
            },
        );
        assert!(matches!(
            result,
            Err(CryptoError::InvalidKeyDerivationParams(_))
        ));
    }

    #[test]
    fn test_opslimit_zero() {
        let result = derive_key(
            "test",
            &Salt::generate(),
            Params {
                mem_limit: Params::INTERACTIVE.mem_limit,
                ops_limit: 0,
            },
        );
        assert!(result.is_err());
    }

    #[test]
    fn test_unusual_passwords() {
        let salt = Salt::generate();
        for password in ["", &"a".repeat(1000), "пароль 密码 🔐"] {
            derive_key(password, &salt, Params::MIN).unwrap();
        }
    }
}
