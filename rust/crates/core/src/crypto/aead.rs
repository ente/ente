use chacha20poly1305::XChaCha20Poly1305;
use chacha20poly1305::aead::{AeadInOut, KeyInit};

use crate::crypto::{Error, Key, Nonce, Result};

pub const TAG_BYTES: usize = 16;

pub type Tag = [u8; TAG_BYTES];

pub fn encrypt_detached(
    buffer: &mut [u8],
    additional_data: &[u8],
    key: &Key,
) -> Result<(Nonce, Tag)> {
    let nonce = Nonce::generate();
    let tag = encrypt_detached_with_nonce(buffer, additional_data, &nonce, key)?;
    Ok((nonce, tag))
}

fn encrypt_detached_with_nonce(
    buffer: &mut [u8],
    additional_data: &[u8],
    nonce: &Nonce,
    key: &Key,
) -> Result<Tag> {
    let cipher = XChaCha20Poly1305::new(key.as_bytes().into());
    cipher
        .encrypt_inout_detached(nonce.as_bytes().into(), additional_data, buffer.into())
        .map(Into::into)
        .map_err(|_| Error::EncryptionFailed)
}

pub fn decrypt_detached(
    buffer: &mut [u8],
    additional_data: &[u8],
    tag: &Tag,
    nonce: &Nonce,
    key: &Key,
) -> Result<()> {
    let cipher = XChaCha20Poly1305::new(key.as_bytes().into());
    cipher
        .decrypt_inout_detached(
            nonce.as_bytes().into(),
            additional_data,
            buffer.into(),
            tag.into(),
        )
        .map_err(|_| Error::DecryptionFailed)
}

#[cfg(test)]
mod tests {
    use super::*;

    const KEY: [u8; 32] = [
        0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8a, 0x8b, 0x8c, 0x8d, 0x8e,
        0x8f, 0x90, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0x9b, 0x9c, 0x9d,
        0x9e, 0x9f,
    ];

    const NONCE: [u8; 24] = [
        0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x4b, 0x4c, 0x4d, 0x4e,
        0x4f, 0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57,
    ];

    const ADDITIONAL_DATA: [u8; 12] = [
        0x50, 0x51, 0x52, 0x53, 0xc0, 0xc1, 0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc7,
    ];

    const PLAINTEXT: &[u8] = b"Ladies and Gentlemen of the class of '99: \
        If I could offer you only one tip for the future, sunscreen would be it.";

    const CIPHERTEXT: [u8; 114] = [
        0xbd, 0x6d, 0x17, 0x9d, 0x3e, 0x83, 0xd4, 0x3b, 0x95, 0x76, 0x57, 0x94, 0x93, 0xc0, 0xe9,
        0x39, 0x57, 0x2a, 0x17, 0x00, 0x25, 0x2b, 0xfa, 0xcc, 0xbe, 0xd2, 0x90, 0x2c, 0x21, 0x39,
        0x6c, 0xbb, 0x73, 0x1c, 0x7f, 0x1b, 0x0b, 0x4a, 0xa6, 0x44, 0x0b, 0xf3, 0xa8, 0x2f, 0x4e,
        0xda, 0x7e, 0x39, 0xae, 0x64, 0xc6, 0x70, 0x8c, 0x54, 0xc2, 0x16, 0xcb, 0x96, 0xb7, 0x2e,
        0x12, 0x13, 0xb4, 0x52, 0x2f, 0x8c, 0x9b, 0xa4, 0x0d, 0xb5, 0xd9, 0x45, 0xb1, 0x1b, 0x69,
        0xb9, 0x82, 0xc1, 0xbb, 0x9e, 0x3f, 0x3f, 0xac, 0x2b, 0xc3, 0x69, 0x48, 0x8f, 0x76, 0xb2,
        0x38, 0x35, 0x65, 0xd3, 0xff, 0xf9, 0x21, 0xf9, 0x66, 0x4c, 0x97, 0x63, 0x7d, 0xa9, 0x76,
        0x88, 0x12, 0xf6, 0x15, 0xc6, 0x8b, 0x13, 0xb5, 0x2e,
    ];

    const TAG: Tag = [
        0xc0, 0x87, 0x59, 0x24, 0xc1, 0xc7, 0x98, 0x79, 0x47, 0xde, 0xaf, 0xd8, 0x78, 0x0a, 0xcf,
        0x49,
    ];

    fn sealed(plaintext: &[u8], additional_data: &[u8], key: &Key) -> (Vec<u8>, Nonce, Tag) {
        let mut buffer = plaintext.to_vec();
        let (nonce, tag) = encrypt_detached(&mut buffer, additional_data, key).unwrap();
        (buffer, nonce, tag)
    }

    #[test]
    fn matches_the_xchacha20_poly1305_draft_vector() {
        let key = Key::from_bytes(KEY);
        let nonce = Nonce::from_bytes(NONCE);

        let mut ciphertext = PLAINTEXT.to_vec();
        let tag =
            encrypt_detached_with_nonce(&mut ciphertext, &ADDITIONAL_DATA, &nonce, &key).unwrap();
        assert_eq!(ciphertext, CIPHERTEXT);
        assert_eq!(tag, TAG);

        let mut buffer = CIPHERTEXT.to_vec();
        decrypt_detached(&mut buffer, &ADDITIONAL_DATA, &TAG, &nonce, &key).unwrap();
        assert_eq!(buffer, PLAINTEXT);
    }

    #[test]
    fn round_trips_with_a_fresh_nonce_per_call() {
        let key = Key::generate();
        let (first, first_nonce, first_tag) = sealed(b"payload", b"context", &key);
        let (second, second_nonce, _) = sealed(b"payload", b"context", &key);
        assert_ne!(first_nonce, second_nonce);
        assert_ne!(first, second);

        let mut buffer = first;
        decrypt_detached(&mut buffer, b"context", &first_tag, &first_nonce, &key).unwrap();
        assert_eq!(buffer, b"payload");
    }

    #[test]
    fn rejects_changed_additional_data() {
        let key = Key::generate();
        let (mut ciphertext, nonce, tag) = sealed(b"payload", b"context", &key);

        assert!(matches!(
            decrypt_detached(&mut ciphertext, b"contexu", &tag, &nonce, &key),
            Err(Error::DecryptionFailed)
        ));
    }

    #[test]
    fn rejects_a_wrong_key_nonce_or_tag() {
        let key = Key::generate();
        let (ciphertext, nonce, tag) = sealed(b"payload", b"context", &key);

        let mut buffer = ciphertext.clone();
        assert!(decrypt_detached(&mut buffer, b"context", &tag, &nonce, &Key::generate()).is_err());

        let mut buffer = ciphertext.clone();
        assert!(decrypt_detached(&mut buffer, b"context", &tag, &Nonce::generate(), &key).is_err());

        let mut flipped = tag;
        flipped[0] ^= 1;
        let mut buffer = ciphertext;
        assert!(decrypt_detached(&mut buffer, b"context", &flipped, &nonce, &key).is_err());
    }

    #[test]
    fn rejects_a_changed_ciphertext() {
        let key = Key::generate();
        let (mut ciphertext, nonce, tag) = sealed(b"payload", b"context", &key);
        ciphertext[3] ^= 1;

        assert!(decrypt_detached(&mut ciphertext, b"context", &tag, &nonce, &key).is_err());
    }

    #[test]
    fn authenticates_additional_data_without_a_plaintext() {
        let key = Key::generate();
        let (nonce, tag) = encrypt_detached(&mut [], b"header", &key).unwrap();

        assert!(decrypt_detached(&mut [], b"header", &tag, &nonce, &key).is_ok());
        assert!(decrypt_detached(&mut [], b"headex", &tag, &nonce, &key).is_err());
    }
}
