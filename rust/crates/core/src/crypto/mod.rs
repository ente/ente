//! Cryptographic primitives for Ente.
//!
//! This module provides all the cryptographic primitives used by Ente clients.
//!
//! # Implementation
//!
//! Every primitive is implemented in pure Rust, with no libsodium or other C
//! dependency, drawing on established crates such as those from the RustCrypto
//! project, `blake2b_simd`, and `crypto_secretstream`. All of them keep
//! byte-for-byte wire compatibility with libsodium, so keys and ciphertext
//! interoperate with the existing mobile and web clients.
//!
//! # Overview
//!
//! Authenticated encryption:
//! - [`secretbox`] - a single small, independent value
//! - [`blob`] - a single value attached to an Ente object, such as metadata
//! - [`stream`] - file contents of any size, encrypted in chunks
//!
//! Public-key:
//! - [`sealed`] - anonymous encryption to a recipient's public key
//!
//! Key derivation and hashing:
//! - [`argon`] - derive a key from a password (Argon2id)
//! - [`kdf`] - derive subkeys from a high-entropy key (BLAKE2b)
//! - [`hash`] - BLAKE2b hashing
//!
//! Base64 helpers ([`encode_b64`] and friends) are available directly on this
//! module. Key material is typed ([`Key`],
//! [`Nonce`], [`Salt`], [`Header`], [`PublicKey`], [`SecretKey`]), with lengths
//! validated at construction, and secrets are held in zeroizing [`SecretVec`] /
//! [`SecretString`].
//!
//! # Example
//!
//! ```rust
//! use ente_core::crypto::{Key, secretbox};
//!
//! let key = Key::generate();
//! let encrypted = secretbox::encrypt(b"a secret", &key);
//!
//! let decrypted = encrypted.decrypt(&key).unwrap();
//! assert_eq!(decrypted, b"a secret");
//! ```

mod encoding;
mod error;
mod secret;
mod types;

pub mod argon;
pub mod blob;
pub mod hash;
pub mod kdf;
pub mod sealed;
pub mod secretbox;
pub mod stream;

pub use encoding::{
    decode_b64, decode_b64_url_safe_no_padding, encode_b64, encode_b64_url_safe,
    encode_b64_url_safe_no_padding,
};
pub use error::{Error, Result};
pub use secret::{SecretString, SecretVec};
pub use types::{Header, Key, Nonce, PublicKey, Salt, SecretKey, random_bytes};
