uniffi::setup_scaffolding!("ente_notification_uniffi");

use ente_core::crypto::hpke;

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum NotificationError {
    #[error("Invalid notification payload")]
    InvalidPayload,
}

#[uniffi::export]
pub fn decrypt_notification(
    ciphertext: Vec<u8>,
    private_key: Vec<u8>,
) -> Result<Vec<u8>, NotificationError> {
    if ciphertext.len() <= hpke::OVERHEAD || ciphertext.len() > 4096 {
        return Err(NotificationError::InvalidPayload);
    }
    let private_key = hpke::SecretKey::try_from_slice(&private_key)
        .map_err(|_| NotificationError::InvalidPayload)?;
    hpke::open(&ciphertext, &private_key, b"ente-push")
        .map_err(|_| NotificationError::InvalidPayload)
}
