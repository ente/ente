use ente_core::b64;
use ente_core::crypto;
use md5::{Digest, Md5};
use wasm_bindgen::prelude::*;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Crypto(#[from] crypto::Error),
    #[error(transparent)]
    Decode(#[from] b64::DecodeError),
}

impl Error {
    fn name(&self) -> Option<&'static str> {
        match self {
            Self::Crypto(crypto::Error::StreamTruncated) => Some("stream_truncated"),
            _ => None,
        }
    }

    fn message(&self) -> String {
        ente_core::error::chain(self)
    }
}

impl From<Error> for JsValue {
    fn from(error: Error) -> Self {
        let js_error = js_sys::Error::new(&error.message());
        if let Some(name) = error.name() {
            js_error.set_name(name);
        }
        js_error.into()
    }
}

#[wasm_bindgen]
pub fn crypto_generate_key() -> String {
    b64::encode(crypto::Key::generate().as_bytes())
}

#[wasm_bindgen]
pub struct CryptoStreamEncryptor {
    encryptor: crypto::stream::Encryptor,
    key: String,
    decryption_header: String,
}

#[wasm_bindgen]
impl CryptoStreamEncryptor {
    #[wasm_bindgen(constructor)]
    pub fn new() -> Result<CryptoStreamEncryptor, Error> {
        let key = crypto::Key::generate();
        let encryptor = crypto::stream::Encryptor::new(&key);
        let decryption_header = b64::encode(encryptor.header().as_bytes());

        Ok(Self {
            encryptor,
            key: b64::encode(key.as_bytes()),
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

    pub fn encrypt_chunk(&mut self, plaintext: Vec<u8>, is_final: bool) -> Result<Vec<u8>, Error> {
        self.encryptor
            .push(&plaintext, is_final)
            .map_err(Into::into)
    }
}

#[wasm_bindgen]
pub struct CryptoStreamDecryptor {
    decryptor: crypto::stream::Decryptor,
    finalized: bool,
}

#[wasm_bindgen]
impl CryptoStreamDecryptor {
    #[wasm_bindgen(constructor)]
    pub fn new(decryption_header_b64: &str, key_b64: &str) -> Result<CryptoStreamDecryptor, Error> {
        let header = b64::decode(decryption_header_b64)?;
        let key = b64::decode(key_b64)?;
        let decryptor = crypto::stream::Decryptor::new(
            &crypto::Header::try_from_slice(&header)?,
            &crypto::Key::try_from_slice(&key)?,
        );

        Ok(Self {
            decryptor,
            finalized: false,
        })
    }

    #[wasm_bindgen(getter)]
    pub fn decryption_chunk_size(&self) -> usize {
        crypto::stream::DECRYPTION_CHUNK_SIZE
    }

    #[wasm_bindgen(getter)]
    pub fn is_finalized(&self) -> bool {
        self.finalized
    }

    pub fn decrypt_chunk(&mut self, ciphertext: Vec<u8>) -> Result<Vec<u8>, Error> {
        let (plaintext, is_final) = self.decryptor.pull(&ciphertext)?;
        self.finalized = is_final;
        Ok(plaintext)
    }
}

#[wasm_bindgen]
pub fn crypto_md5_base64(data: Vec<u8>) -> String {
    let digest = Md5::digest(&data);
    b64::encode(&digest)
}

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

#[wasm_bindgen]
pub fn crypto_generate_keypair() -> CryptoKeyPair {
    let secret_key = crypto::SecretKey::generate();
    CryptoKeyPair {
        public_key: b64::encode(secret_key.public_key().as_bytes()),
        secret_key: b64::encode(secret_key.as_bytes()),
    }
}

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

#[wasm_bindgen]
pub fn crypto_encrypt_box(data_b64: &str, key_b64: &str) -> Result<EncryptedBox, Error> {
    let data = b64::decode(data_b64)?;
    let key = b64::decode(key_b64)?;

    let out = crypto::secretbox::encrypt(&data, &crypto::Key::try_from_slice(&key)?);

    Ok(EncryptedBox {
        encrypted_data: b64::encode(&out.encrypted_data),
        nonce: b64::encode(out.nonce.as_bytes()),
    })
}

#[wasm_bindgen]
pub fn crypto_decrypt_box(
    encrypted_data_b64: &str,
    nonce_b64: &str,
    key_b64: &str,
) -> Result<String, Error> {
    let ciphertext = b64::decode(encrypted_data_b64)?;
    let nonce = b64::decode(nonce_b64)?;
    let key = b64::decode(key_b64)?;

    let plaintext = crypto::secretbox::decrypt(
        &ciphertext,
        &crypto::Nonce::try_from_slice(&nonce)?,
        &crypto::Key::try_from_slice(&key)?,
    )?;
    Ok(b64::encode(&plaintext))
}

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

#[wasm_bindgen]
pub fn crypto_encrypt_blob(data_b64: &str, key_b64: &str) -> Result<EncryptedBlob, Error> {
    let data = b64::decode(data_b64)?;
    let key = b64::decode(key_b64)?;

    let out = crypto::blob::encrypt(&data, &crypto::Key::try_from_slice(&key)?)?;
    Ok(EncryptedBlob {
        encrypted_data: b64::encode(&out.encrypted_data),
        decryption_header: b64::encode(out.decryption_header.as_bytes()),
    })
}

#[wasm_bindgen]
pub fn crypto_decrypt_blob(
    encrypted_data_b64: &str,
    decryption_header_b64: &str,
    key_b64: &str,
) -> Result<String, Error> {
    let ciphertext = b64::decode(encrypted_data_b64)?;
    let header = b64::decode(decryption_header_b64)?;
    let key = b64::decode(key_b64)?;

    let plaintext = crypto::blob::decrypt(
        &ciphertext,
        &crypto::Header::try_from_slice(&header)?,
        &crypto::Key::try_from_slice(&key)?,
    )?;
    Ok(b64::encode(&plaintext))
}

#[wasm_bindgen]
pub fn crypto_decrypt_blob_legacy(
    encrypted_data_b64: &str,
    decryption_header_b64: &str,
    key_b64: &str,
) -> Result<String, Error> {
    let ciphertext = b64::decode(encrypted_data_b64)?;
    let header = b64::decode(decryption_header_b64)?;
    let key = b64::decode(key_b64)?;

    let plaintext = crypto::blob::decrypt_legacy(
        &ciphertext,
        &crypto::Header::try_from_slice(&header)?,
        &crypto::Key::try_from_slice(&key)?,
    )?;
    Ok(b64::encode(&plaintext))
}

#[wasm_bindgen]
pub fn crypto_decrypt_stream(
    encrypted_data_b64: &str,
    decryption_header_b64: &str,
    key_b64: &str,
) -> Result<String, Error> {
    let ciphertext = b64::decode(encrypted_data_b64)?;
    let header = b64::decode(decryption_header_b64)?;
    let key = b64::decode(key_b64)?;

    let plaintext = crypto::stream::decrypt_file_data(
        &ciphertext,
        &crypto::Header::try_from_slice(&header)?,
        &crypto::Key::try_from_slice(&key)?,
    )?;
    Ok(b64::encode(&plaintext))
}

#[wasm_bindgen]
pub fn crypto_box_seal(data_b64: &str, recipient_public_key_b64: &str) -> Result<String, Error> {
    let data = b64::decode(data_b64)?;
    let pk = b64::decode(recipient_public_key_b64)?;
    let sealed = crypto::sealed::seal(&data, &crypto::PublicKey::try_from_slice(&pk)?)?;
    Ok(b64::encode(&sealed))
}

#[wasm_bindgen]
pub fn crypto_box_seal_open(
    sealed_b64: &str,
    recipient_public_key_b64: &str,
    recipient_secret_key_b64: &str,
) -> Result<String, Error> {
    let sealed = b64::decode(sealed_b64)?;
    let pk = b64::decode(recipient_public_key_b64)?;
    let sk = b64::decode(recipient_secret_key_b64)?;
    let opened = crypto::sealed::open(
        &sealed,
        &crypto::PublicKey::try_from_slice(&pk)?,
        &crypto::SecretKey::try_from_slice(&sk)?,
    )?;
    Ok(b64::encode(&opened))
}

#[wasm_bindgen]
pub fn crypto_derive_subkey(
    key_b64: &str,
    subkey_len: usize,
    subkey_id: u64,
    context: &str,
) -> Result<String, Error> {
    let key = b64::decode(key_b64)?;
    let context: [u8; 8] = context.as_bytes().try_into().map_err(|_| {
        crypto::Error::InvalidKeyDerivationParams("KDF context must be exactly 8 bytes".into())
    })?;
    let subkey = crypto::kdf::derive_subkey(
        &crypto::Key::try_from_slice(&key)?,
        subkey_len,
        subkey_id,
        &context,
    )?;
    Ok(b64::encode(&subkey))
}

#[wasm_bindgen]
pub struct EncryptedStreamResult {
    encrypted_data: String,
    decryption_header: String,
    md5_hash: String,
    key: String,
}

#[wasm_bindgen]
impl EncryptedStreamResult {
    #[wasm_bindgen(getter)]
    pub fn encrypted_data(&self) -> String {
        self.encrypted_data.clone()
    }

    #[wasm_bindgen(getter)]
    pub fn decryption_header(&self) -> String {
        self.decryption_header.clone()
    }

    #[wasm_bindgen(getter)]
    pub fn md5_hash(&self) -> String {
        self.md5_hash.clone()
    }

    #[wasm_bindgen(getter)]
    pub fn key(&self) -> String {
        self.key.clone()
    }
}

#[wasm_bindgen]
pub fn crypto_encrypt_stream(data_b64: &str) -> Result<EncryptedStreamResult, Error> {
    let plaintext = b64::decode(data_b64)?;

    let key = crypto::Key::generate();
    let mut reader = std::io::Cursor::new(&plaintext);
    let mut writer = ente_core::io::Md5Writer::new(Vec::new());

    let header = crypto::stream::encrypt_file(&mut reader, &mut writer, &key)?;
    let (encrypted, md5) = writer.finalize();

    Ok(EncryptedStreamResult {
        encrypted_data: b64::encode(&encrypted),
        decryption_header: b64::encode(header.as_bytes()),
        md5_hash: b64::encode(&md5),
        key: b64::encode(key.as_bytes()),
    })
}

#[wasm_bindgen]
pub fn crypto_encrypt_stream_with_key(
    data_b64: &str,
    key_b64: &str,
) -> Result<EncryptedStreamResult, Error> {
    let plaintext = b64::decode(data_b64)?;
    let key = crypto::Key::try_from_slice(&b64::decode(key_b64)?)?;

    let mut reader = std::io::Cursor::new(&plaintext);
    let mut writer = ente_core::io::Md5Writer::new(Vec::new());

    let header = crypto::stream::encrypt_file(&mut reader, &mut writer, &key)?;
    let (encrypted, md5) = writer.finalize();

    Ok(EncryptedStreamResult {
        encrypted_data: b64::encode(&encrypted),
        decryption_header: b64::encode(header.as_bytes()),
        md5_hash: b64::encode(&md5),
        key: b64::encode(key.as_bytes()),
    })
}
