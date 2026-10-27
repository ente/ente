use ente_core::crypto::hpke;

const HPKE_INFO: &[u8] = b"ente-push";

#[flutter_rust_bridge::frb(sync)]
pub fn generate_notification_private_key() -> Vec<u8> {
    hpke::SecretKey::generate().as_bytes().to_vec()
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_notification_public_key(private_key: Vec<u8>) -> Result<Vec<u8>, String> {
    let private_key =
        hpke::SecretKey::try_from_slice(&private_key).map_err(|error| error.to_string())?;
    Ok(private_key.public_key().as_bytes().to_vec())
}

#[flutter_rust_bridge::frb(sync)]
pub fn decrypt_notification(ciphertext: Vec<u8>, private_key: Vec<u8>) -> Result<Vec<u8>, String> {
    let private_key =
        hpke::SecretKey::try_from_slice(&private_key).map_err(|error| error.to_string())?;
    hpke::open(&ciphertext, &private_key, HPKE_INFO).map_err(|error| error.to_string())
}
