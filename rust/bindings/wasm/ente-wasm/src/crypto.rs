//! WASM bindings for pure-Rust cryptography.

use ente_core::crypto as core_crypto;
use md5::{Digest, Md5};
use wasm_bindgen::prelude::*;

/// Crypto error.
#[wasm_bindgen]
pub struct CryptoError {
    code: String,
    message: String,
}

#[wasm_bindgen]
impl CryptoError {
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

impl From<core_crypto::Error> for CryptoError {
    fn from(e: core_crypto::Error) -> Self {
        use core_crypto::Error as E;

        let code = match &e {
            E::Base64Decode(_) => "base64_decode",
            E::HexDecode(_) => "hex_decode",
            E::InvalidKeyLength { .. } => "invalid_key_length",
            E::InvalidNonceLength { .. } => "invalid_nonce_length",
            E::InvalidSaltLength { .. } => "invalid_salt_length",
            E::InvalidHeaderLength { .. } => "invalid_header_length",
            E::CiphertextTooShort { .. } => "ciphertext_too_short",
            E::InvalidKeyDerivationParams(_) => "invalid_kdf_params",
            E::KeyDerivationFailed => "key_derivation_failed",
            E::EncryptionFailed => "encryption_failed",
            E::DecryptionFailed => "decryption_failed",
            E::StreamInitFailed => "stream_init_failed",
            E::StreamPushFailed => "stream_push_failed",
            E::StreamPullFailed => "stream_pull_failed",
            E::StreamTruncated => "stream_truncated",
            E::StreamTrailingData => "stream_trailing_data",
            E::SealedBoxOpenFailed => "sealed_box_open_failed",
            E::InvalidPublicKey => "invalid_public_key",
            E::Json(_) => "json",
            E::Argon2(_) => "argon2",
            E::Aead => "aead",
            E::ArrayConversion => "array_conversion",
            E::Io(_) => "io",
        }
        .to_string();

        Self {
            code,
            message: e.to_string(),
        }
    }
}

/// No-op, kept only for binding compatibility.
///
/// The pure-Rust crypto needs no initialization; existing web callers invoke
/// this before using the other functions. Remove once the web callers drop it.
#[wasm_bindgen]
pub fn crypto_init() -> Result<(), CryptoError> {
    Ok(())
}

/// Generate a random 32-byte SecretBox key and return it as base64.
#[wasm_bindgen]
pub fn crypto_generate_key() -> String {
    core_crypto::encode_b64(core_crypto::Key::generate().as_bytes())
}

/// Generate a random 32-byte SecretStream key and return it as base64.
#[wasm_bindgen]
pub fn crypto_generate_stream_key() -> String {
    core_crypto::encode_b64(core_crypto::Key::generate().as_bytes())
}

/// Incremental chunk encryptor for large file uploads.
///
/// The browser reads the file in chunks and passes each chunk to this object,
/// which keeps the secretstream state in Rust and returns encrypted bytes for
/// the caller to upload.
#[wasm_bindgen]
pub struct CryptoStreamEncryptor {
    encryptor: core_crypto::stream::Encryptor,
    key: String,
    decryption_header: String,
}

#[wasm_bindgen]
impl CryptoStreamEncryptor {
    #[wasm_bindgen(constructor)]
    pub fn new() -> Result<CryptoStreamEncryptor, CryptoError> {
        let key = core_crypto::Key::generate();
        let encryptor = core_crypto::stream::Encryptor::new(&key);
        let decryption_header = core_crypto::encode_b64(encryptor.header().as_bytes());

        Ok(Self {
            encryptor,
            key: core_crypto::encode_b64(key.as_bytes()),
            decryption_header,
        })
    }

    #[wasm_bindgen(getter)]
    pub fn key(&self) -> String {
        self.key.clone()
    }

    #[wasm_bindgen(getter)]
    pub fn decryption_header(&self) -> String {
        self.decryption_header.clone()
    }

    pub fn encrypt_chunk(
        &mut self,
        plaintext: Vec<u8>,
        is_final: bool,
    ) -> Result<Vec<u8>, CryptoError> {
        self.encryptor
            .push(&plaintext, is_final)
            .map_err(Into::into)
    }
}

/// Incremental chunk decryptor for large file downloads.
#[wasm_bindgen]
pub struct CryptoStreamDecryptor {
    decryptor: core_crypto::stream::Decryptor,
    finalized: bool,
}

#[wasm_bindgen]
impl CryptoStreamDecryptor {
    #[wasm_bindgen(constructor)]
    pub fn new(
        decryption_header_b64: &str,
        key_b64: &str,
    ) -> Result<CryptoStreamDecryptor, CryptoError> {
        let header = core_crypto::decode_b64(decryption_header_b64)?;
        let key = core_crypto::decode_b64(key_b64)?;
        let decryptor = core_crypto::stream::Decryptor::new(
            &core_crypto::Header::try_from_slice(&header)?,
            &core_crypto::Key::try_from_slice(&key)?,
        );

        Ok(Self {
            decryptor,
            finalized: false,
        })
    }

    #[wasm_bindgen(getter)]
    pub fn decryption_chunk_size(&self) -> usize {
        core_crypto::stream::DECRYPTION_CHUNK_SIZE
    }

    #[wasm_bindgen(getter)]
    pub fn is_finalized(&self) -> bool {
        self.finalized
    }

    pub fn decrypt_chunk(&mut self, ciphertext: Vec<u8>) -> Result<Vec<u8>, CryptoError> {
        let (plaintext, is_final) = self.decryptor.pull(&ciphertext)?;
        self.finalized = is_final;
        Ok(plaintext)
    }
}

/// Generate a random 16-byte salt and return it as base64.
#[wasm_bindgen]
pub fn crypto_generate_salt() -> String {
    core_crypto::encode_b64(core_crypto::Salt::generate().as_bytes())
}

/// Compute the MD5 digest of the provided bytes and return it as base64.
#[wasm_bindgen]
pub fn crypto_md5_base64(data: Vec<u8>) -> String {
    let digest = Md5::digest(&data);
    core_crypto::encode_b64(&digest)
}

/// A X25519 public/secret keypair.
#[wasm_bindgen]
pub struct CryptoKeyPair {
    public_key: String,
    secret_key: String,
}

#[wasm_bindgen]
impl CryptoKeyPair {
    #[wasm_bindgen(getter)]
    pub fn public_key(&self) -> String {
        self.public_key.clone()
    }

    #[wasm_bindgen(getter)]
    pub fn secret_key(&self) -> String {
        self.secret_key.clone()
    }
}

/// Generate a random X25519 keypair and return it as base64.
#[wasm_bindgen]
pub fn crypto_generate_keypair() -> CryptoKeyPair {
    let secret_key = core_crypto::SecretKey::generate();
    CryptoKeyPair {
        public_key: core_crypto::encode_b64(secret_key.public_key().as_bytes()),
        secret_key: core_crypto::encode_b64(secret_key.as_bytes()),
    }
}

/// A SecretBox encryption result.
///
/// Wire format is compatible with libsodium's `crypto_secretbox_easy`.
#[wasm_bindgen]
pub struct EncryptedBox {
    encrypted_data: String,
    nonce: String,
}

#[wasm_bindgen]
impl EncryptedBox {
    #[wasm_bindgen(getter)]
    pub fn encrypted_data(&self) -> String {
        self.encrypted_data.clone()
    }

    #[wasm_bindgen(getter)]
    pub fn nonce(&self) -> String {
        self.nonce.clone()
    }
}

/// Encrypt `data_b64` using SecretBox with `key_b64`.
///
/// Returns ciphertext (`encrypted_data`) and nonce as base64.
#[wasm_bindgen]
pub fn crypto_encrypt_box(data_b64: &str, key_b64: &str) -> Result<EncryptedBox, CryptoError> {
    let data = core_crypto::decode_b64(data_b64)?;
    let key = core_crypto::decode_b64(key_b64)?;

    let out = core_crypto::secretbox::encrypt(&data, &core_crypto::Key::try_from_slice(&key)?);

    Ok(EncryptedBox {
        encrypted_data: core_crypto::encode_b64(&out.encrypted_data),
        nonce: core_crypto::encode_b64(out.nonce.as_bytes()),
    })
}

/// Decrypt a SecretBox ciphertext using `key_b64` and `nonce_b64`.
///
/// Returns the plaintext as base64.
#[wasm_bindgen]
pub fn crypto_decrypt_box(
    encrypted_data_b64: &str,
    nonce_b64: &str,
    key_b64: &str,
) -> Result<String, CryptoError> {
    let ciphertext = core_crypto::decode_b64(encrypted_data_b64)?;
    let nonce = core_crypto::decode_b64(nonce_b64)?;
    let key = core_crypto::decode_b64(key_b64)?;

    let plaintext = core_crypto::secretbox::decrypt(
        &ciphertext,
        &core_crypto::Nonce::try_from_slice(&nonce)?,
        &core_crypto::Key::try_from_slice(&key)?,
    )?;
    Ok(core_crypto::encode_b64(&plaintext))
}

/// A SecretStream (blob) encryption result.
#[wasm_bindgen]
pub struct EncryptedBlob {
    encrypted_data: String,
    decryption_header: String,
}

#[wasm_bindgen]
impl EncryptedBlob {
    #[wasm_bindgen(getter)]
    pub fn encrypted_data(&self) -> String {
        self.encrypted_data.clone()
    }

    #[wasm_bindgen(getter)]
    pub fn decryption_header(&self) -> String {
        self.decryption_header.clone()
    }
}

/// Encrypt `data_b64` using SecretStream (single-message blob) with `key_b64`.
#[wasm_bindgen]
pub fn crypto_encrypt_blob(data_b64: &str, key_b64: &str) -> Result<EncryptedBlob, CryptoError> {
    let data = core_crypto::decode_b64(data_b64)?;
    let key = core_crypto::decode_b64(key_b64)?;

    let out = core_crypto::blob::encrypt(&data, &core_crypto::Key::try_from_slice(&key)?)?;
    Ok(EncryptedBlob {
        encrypted_data: core_crypto::encode_b64(&out.encrypted_data),
        decryption_header: core_crypto::encode_b64(out.decryption_header.as_bytes()),
    })
}

/// Decrypt a SecretStream (blob) ciphertext.
///
/// Returns the plaintext as base64.
#[wasm_bindgen]
pub fn crypto_decrypt_blob(
    encrypted_data_b64: &str,
    decryption_header_b64: &str,
    key_b64: &str,
) -> Result<String, CryptoError> {
    let ciphertext = core_crypto::decode_b64(encrypted_data_b64)?;
    let header = core_crypto::decode_b64(decryption_header_b64)?;
    let key = core_crypto::decode_b64(key_b64)?;

    let plaintext = core_crypto::blob::decrypt(
        &ciphertext,
        &core_crypto::Header::try_from_slice(&header)?,
        &core_crypto::Key::try_from_slice(&key)?,
    )?;
    Ok(core_crypto::encode_b64(&plaintext))
}

/// Legacy decrypt for SecretStream (blob) ciphertext that may not carry
/// a final tag.
///
/// Prefer using [`crypto_decrypt_blob`]. This function exists as a migration
/// fallback for older data written without the final secretstream tag.
#[wasm_bindgen]
pub fn crypto_decrypt_blob_legacy(
    encrypted_data_b64: &str,
    decryption_header_b64: &str,
    key_b64: &str,
) -> Result<String, CryptoError> {
    let ciphertext = core_crypto::decode_b64(encrypted_data_b64)?;
    let header = core_crypto::decode_b64(decryption_header_b64)?;
    let key = core_crypto::decode_b64(key_b64)?;

    let plaintext = core_crypto::blob::decrypt_legacy(
        &ciphertext,
        &core_crypto::Header::try_from_slice(&header)?,
        &core_crypto::Key::try_from_slice(&key)?,
    )?;
    Ok(core_crypto::encode_b64(&plaintext))
}

/// Decrypt chunked SecretStream data (file content).
///
/// Unlike `crypto_decrypt_blob` which handles single-message blobs, this
/// function handles multi-chunk streaming data encrypted with 4 MB chunks
/// (the format used for encrypted file content).
///
/// Returns the plaintext as base64.
#[wasm_bindgen]
pub fn crypto_decrypt_stream(
    encrypted_data_b64: &str,
    decryption_header_b64: &str,
    key_b64: &str,
) -> Result<String, CryptoError> {
    let ciphertext = core_crypto::decode_b64(encrypted_data_b64)?;
    let header = core_crypto::decode_b64(decryption_header_b64)?;
    let key = core_crypto::decode_b64(key_b64)?;

    let plaintext = core_crypto::stream::decrypt_file_data(
        &ciphertext,
        &core_crypto::Header::try_from_slice(&header)?,
        &core_crypto::Key::try_from_slice(&key)?,
    )?;
    Ok(core_crypto::encode_b64(&plaintext))
}

/// Seal (anonymous public-key encrypt) `data_b64` for `recipient_public_key_b64`.
///
/// Wire format matches libsodium `crypto_box_seal`.
#[wasm_bindgen]
pub fn crypto_box_seal(
    data_b64: &str,
    recipient_public_key_b64: &str,
) -> Result<String, CryptoError> {
    let data = core_crypto::decode_b64(data_b64)?;
    let pk = core_crypto::decode_b64(recipient_public_key_b64)?;
    let sealed = core_crypto::sealed::seal(&data, &core_crypto::PublicKey::try_from_slice(&pk)?)?;
    Ok(core_crypto::encode_b64(&sealed))
}

/// Open (decrypt) a sealed box.
///
/// Returns the plaintext as base64.
#[wasm_bindgen]
pub fn crypto_box_seal_open(
    sealed_b64: &str,
    recipient_public_key_b64: &str,
    recipient_secret_key_b64: &str,
) -> Result<String, CryptoError> {
    let sealed = core_crypto::decode_b64(sealed_b64)?;
    let pk = core_crypto::decode_b64(recipient_public_key_b64)?;
    let sk = core_crypto::decode_b64(recipient_secret_key_b64)?;
    let opened = core_crypto::sealed::open(
        &sealed,
        &core_crypto::PublicKey::try_from_slice(&pk)?,
        &core_crypto::SecretKey::try_from_slice(&sk)?,
    )?;
    Ok(core_crypto::encode_b64(&opened))
}

/// Derive a 32-byte key from `password` using Argon2id.
///
/// Returns the derived key as base64.
#[wasm_bindgen]
pub fn crypto_derive_key(
    password: &str,
    salt_b64: &str,
    mem_limit: u32,
    ops_limit: u32,
) -> Result<String, CryptoError> {
    let salt = core_crypto::decode_b64(salt_b64)?;
    let salt = core_crypto::Salt::try_from_slice(&salt)?;
    let key = core_crypto::argon::derive_key(
        password,
        &salt,
        core_crypto::argon::Params {
            mem_limit,
            ops_limit,
        },
    )?;
    Ok(core_crypto::encode_b64(key.as_bytes()))
}

/// Derive a subkey using BLAKE2b KDF (libsodium compatible).
///
/// Returns the derived subkey as base64.
#[wasm_bindgen]
pub fn crypto_derive_subkey(
    key_b64: &str,
    subkey_len: usize,
    subkey_id: u64,
    context: &str,
) -> Result<String, CryptoError> {
    let key = core_crypto::decode_b64(key_b64)?;
    let context: [u8; 8] = context.as_bytes().try_into().map_err(|_| {
        core_crypto::Error::InvalidKeyDerivationParams("KDF context must be exactly 8 bytes".into())
    })?;
    let subkey = core_crypto::kdf::derive_subkey(
        &core_crypto::Key::try_from_slice(&key)?,
        subkey_len,
        subkey_id,
        &context,
    )?;
    Ok(core_crypto::encode_b64(&subkey))
}

/// A chunked SecretStream encryption result (for file content).
///
/// Unlike [`EncryptedBlob`] which encrypts data as a single message, this
/// encrypts data in 4 MB chunks using the streaming API — the same format used
/// for encrypted file content throughout Ente.
#[wasm_bindgen]
pub struct EncryptedStreamResult {
    encrypted_data: String,
    decryption_header: String,
    md5_hash: String,
    key: String,
}

#[wasm_bindgen]
impl EncryptedStreamResult {
    /// The encrypted ciphertext as base64.
    #[wasm_bindgen(getter)]
    pub fn encrypted_data(&self) -> String {
        self.encrypted_data.clone()
    }

    /// The decryption header as base64.
    #[wasm_bindgen(getter)]
    pub fn decryption_header(&self) -> String {
        self.decryption_header.clone()
    }

    /// MD5 hash of the encrypted data as base64.
    #[wasm_bindgen(getter)]
    pub fn md5_hash(&self) -> String {
        self.md5_hash.clone()
    }

    /// The file encryption key (32 bytes) as base64.
    ///
    /// A new random key is generated for each encryption.
    #[wasm_bindgen(getter)]
    pub fn key(&self) -> String {
        self.key.clone()
    }
}

/// Encrypt file data using chunked SecretStream (4 MB chunks) and compute MD5.
///
/// Generates a new random stream key, encrypts the data in 4 MB chunks (the
/// same format produced by the mobile and desktop clients), and computes the
/// MD5 hash of the ciphertext.
///
/// Returns the encrypted data, decryption header, MD5 hash, and generated key
/// — all as base64 strings.
#[wasm_bindgen]
pub fn crypto_encrypt_stream(data_b64: &str) -> Result<EncryptedStreamResult, CryptoError> {
    let plaintext = core_crypto::decode_b64(data_b64)?;

    let key = core_crypto::Key::generate();
    let mut reader = std::io::Cursor::new(&plaintext);
    let mut writer = ente_core::io::Md5Writer::new(Vec::new());

    let header = core_crypto::stream::encrypt_file(&mut reader, &mut writer, &key)?;
    let (encrypted, md5) = writer.finalize();

    Ok(EncryptedStreamResult {
        encrypted_data: core_crypto::encode_b64(&encrypted),
        decryption_header: core_crypto::encode_b64(header.as_bytes()),
        md5_hash: core_crypto::encode_b64(&md5),
        key: core_crypto::encode_b64(key.as_bytes()),
    })
}

/// Encrypt data using chunked SecretStream with an existing key.
///
/// Same as [`crypto_encrypt_stream`] but uses the provided key instead of
/// generating a new one. Useful for encrypting thumbnails with the same file key.
#[wasm_bindgen]
pub fn crypto_encrypt_stream_with_key(
    data_b64: &str,
    key_b64: &str,
) -> Result<EncryptedStreamResult, CryptoError> {
    let plaintext = core_crypto::decode_b64(data_b64)?;
    let key = core_crypto::Key::try_from_slice(&core_crypto::decode_b64(key_b64)?)?;

    let mut reader = std::io::Cursor::new(&plaintext);
    let mut writer = ente_core::io::Md5Writer::new(Vec::new());

    let header = core_crypto::stream::encrypt_file(&mut reader, &mut writer, &key)?;
    let (encrypted, md5) = writer.finalize();

    Ok(EncryptedStreamResult {
        encrypted_data: core_crypto::encode_b64(&encrypted),
        decryption_header: core_crypto::encode_b64(header.as_bytes()),
        md5_hash: core_crypto::encode_b64(&md5),
        key: core_crypto::encode_b64(key.as_bytes()),
    })
}

/// Derive the SRP login key from a 32-byte master key.
///
/// Returns the 16-byte login key as base64.
#[wasm_bindgen]
pub fn crypto_derive_login_key(master_key_b64: &str) -> Result<String, CryptoError> {
    let key = core_crypto::decode_b64(master_key_b64)?;
    let login_key = core_crypto::kdf::derive_login_key(&core_crypto::Key::try_from_slice(&key)?);
    Ok(core_crypto::encode_b64(&login_key))
}
