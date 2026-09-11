use ente_core::{b64, crypto};
use md5::{Digest, Md5};
use wasm_bindgen::prelude::*;

use super::Error;

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

    #[wasm_bindgen(getter, js_name = decryptionHeader)]
    pub fn decryption_header(&self) -> String {
        self.decryption_header.clone()
    }

    #[wasm_bindgen(js_name = encryptChunk)]
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

    #[wasm_bindgen(getter, js_name = decryptionChunkSize)]
    pub fn decryption_chunk_size(&self) -> usize {
        crypto::stream::DECRYPTION_CHUNK_SIZE
    }

    #[wasm_bindgen(js_name = isFinalized)]
    pub fn is_finalized(&self) -> bool {
        self.finalized
    }

    #[wasm_bindgen(js_name = decryptChunk)]
    pub fn decrypt_chunk(&mut self, ciphertext: Vec<u8>) -> Result<Vec<u8>, Error> {
        let (plaintext, is_final) = self.decryptor.pull(&ciphertext)?;
        self.finalized = is_final;
        Ok(plaintext)
    }
}

#[wasm_bindgen(js_name = cryptoMd5Base64)]
pub fn crypto_md5_base64(data: Vec<u8>) -> String {
    let digest = Md5::digest(&data);
    b64::encode(&digest)
}

#[wasm_bindgen(getter_with_clone)]
pub struct EncryptedBlob {
    #[wasm_bindgen(readonly, js_name = encryptedData)]
    pub encrypted_data: String,
    #[wasm_bindgen(readonly, js_name = decryptionHeader)]
    pub decryption_header: String,
}

#[wasm_bindgen(js_name = cryptoEncryptBlob)]
pub fn crypto_encrypt_blob(data: &[u8], key_b64: &str) -> Result<EncryptedBlob, Error> {
    let key = b64::decode(key_b64)?;

    let out = crypto::blob::encrypt(data, &crypto::Key::try_from_slice(&key)?)?;
    Ok(EncryptedBlob {
        encrypted_data: b64::encode(&out.encrypted_data),
        decryption_header: b64::encode(out.decryption_header.as_bytes()),
    })
}

#[wasm_bindgen(js_name = cryptoDecryptBlob)]
pub fn crypto_decrypt_blob(
    encrypted_data_b64: &str,
    decryption_header_b64: &str,
    key_b64: &str,
) -> Result<Vec<u8>, Error> {
    let ciphertext = b64::decode(encrypted_data_b64)?;
    let header = b64::decode(decryption_header_b64)?;
    let key = b64::decode(key_b64)?;

    Ok(crypto::blob::decrypt(
        &ciphertext,
        &crypto::Header::try_from_slice(&header)?,
        &crypto::Key::try_from_slice(&key)?,
    )?)
}

#[wasm_bindgen(js_name = cryptoDecryptBlobLegacy)]
pub fn crypto_decrypt_blob_legacy(
    encrypted_data_b64: &str,
    decryption_header_b64: &str,
    key_b64: &str,
) -> Result<Vec<u8>, Error> {
    let ciphertext = b64::decode(encrypted_data_b64)?;
    let header = b64::decode(decryption_header_b64)?;
    let key = b64::decode(key_b64)?;

    Ok(crypto::blob::decrypt_legacy(
        &ciphertext,
        &crypto::Header::try_from_slice(&header)?,
        &crypto::Key::try_from_slice(&key)?,
    )?)
}

#[wasm_bindgen(getter_with_clone)]
pub struct EncryptedStreamResult {
    #[wasm_bindgen(readonly, js_name = encryptedData)]
    pub encrypted_data: Vec<u8>,
    #[wasm_bindgen(readonly, js_name = decryptionHeader)]
    pub decryption_header: String,
    #[wasm_bindgen(readonly, js_name = md5Hash)]
    pub md5_hash: String,
}

#[wasm_bindgen(js_name = cryptoEncryptStreamWithKey)]
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
        encrypted_data: encrypted,
        decryption_header: b64::encode(header.as_bytes()),
        md5_hash: b64::encode(&md5),
    })
}
