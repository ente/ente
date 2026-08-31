use std::fmt;

use argon2::{Algorithm, Argon2, Params as Argon2Params, Version};

use crate::crypto::{Error, Key, Result, Salt};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Params {
    pub mem_limit: u32,
    pub ops_limit: u32,
}

impl Params {
    pub const INTERACTIVE: Self = Self {
        mem_limit: 67_108_864,
        ops_limit: 2,
    };

    pub const MODERATE: Self = Self {
        mem_limit: 268_435_456,
        ops_limit: 3,
    };

    pub const SENSITIVE: Self = Self {
        mem_limit: 1_073_741_824,
        ops_limit: 4,
    };

    // Only for inputs that are already high-entropy, never passwords.
    pub const MIN: Self = Self {
        mem_limit: 8_192,
        ops_limit: 1,
    };
}

const MEMLIMIT_SENSITIVE_MIN: u32 = 134_217_728;

pub struct DerivedKey {
    pub key: Key,
    pub salt: Salt,
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

// Produces the same key as libsodium's `crypto_pwhash` with
// `crypto_pwhash_ALG_ARGON2ID13`.
pub fn derive_key(password: &str, salt: &Salt, params: Params) -> Result<Key> {
    derive_key_impl(password.as_bytes(), salt, params)
}

fn derive_key_impl(password: &[u8], salt: &Salt, params: Params) -> Result<Key> {
    if params.mem_limit < Params::MIN.mem_limit {
        return Err(Error::InvalidKeyDerivationParams(format!(
            "Memory limit {} is below minimum {}",
            params.mem_limit,
            Params::MIN.mem_limit
        )));
    }

    if !params.mem_limit.is_multiple_of(1024) {
        return Err(Error::InvalidKeyDerivationParams(format!(
            "Memory limit {} must be a multiple of 1024 bytes",
            params.mem_limit
        )));
    }

    if params.ops_limit < Params::MIN.ops_limit {
        return Err(Error::InvalidKeyDerivationParams(format!(
            "Operations limit {} is below minimum {}",
            params.ops_limit,
            Params::MIN.ops_limit
        )));
    }

    let m_cost = params.mem_limit / 1024;
    let t_cost = params.ops_limit;
    let p_cost = 1;

    let argon2_params = Argon2Params::new(m_cost, t_cost, p_cost, Some(Key::BYTES))
        .map_err(|e| Error::InvalidKeyDerivationParams(e.to_string()))?;

    let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, argon2_params);

    let mut key = [0u8; Key::BYTES];
    argon2
        .hash_password_into(password, salt.as_bytes(), &mut key)
        .map_err(Error::Argon2)?;

    Ok(Key::from_bytes(key))
}

pub fn derive_interactive_key(password: &str) -> Result<DerivedKey> {
    let salt = Salt::generate();
    let key = derive_key(password, &salt, Params::INTERACTIVE)?;
    Ok(DerivedKey {
        key,
        salt,
        params: Params::INTERACTIVE,
    })
}

pub fn derive_moderate_key(password: &str) -> Result<DerivedKey> {
    let salt = Salt::generate();
    let key = derive_key(password, &salt, Params::MODERATE)?;
    Ok(DerivedKey {
        key,
        salt,
        params: Params::MODERATE,
    })
}

pub fn derive_sensitive_key(password: &str) -> Result<DerivedKey> {
    let salt = Salt::generate();
    derive_sensitive_adaptive(password.as_bytes(), &salt)
}

fn derive_sensitive_adaptive(password: &[u8], salt: &Salt) -> Result<DerivedKey> {
    if !Params::SENSITIVE
        .mem_limit
        .is_multiple_of(Params::MODERATE.mem_limit)
    {
        return Err(Error::InvalidKeyDerivationParams(format!(
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
            Error::InvalidKeyDerivationParams("Operations limit overflow".to_string())
        })?;

    if u64::from(mem_limit) * u64::from(ops_limit) != desired_strength {
        return Err(Error::InvalidKeyDerivationParams(format!(
            "Unexpected mem/ops limits: mem_limit {}, ops_limit {}",
            mem_limit, ops_limit
        )));
    }

    // The server rejects account key attributes below 128 MiB. Halving memory
    // and doubling ops matches the web and Flutter fallback policy.
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

    Err(last_error.unwrap_or(Error::KeyDerivationFailed))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_salt() -> Salt {
        Salt::from_bytes([0x42u8; Salt::BYTES])
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
        assert!(matches!(result, Err(Error::InvalidKeyDerivationParams(_))));
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
