use crate::commands::common::ApiError;

const SECURE_STORAGE_SERVICE: &str = "io.ente.ensu";

fn secure_storage_entry(key: &str) -> Result<keyring::Entry, ApiError> {
    keyring::Entry::new(SECURE_STORAGE_SERVICE, key)
        .map_err(|err| ApiError::new("secure_storage", err.to_string()))
}

#[tauri::command]
pub fn secure_storage_get(key: String) -> Result<Option<String>, ApiError> {
    let entry = secure_storage_entry(&key)?;
    match entry.get_password() {
        Ok(value) => Ok(Some(value)),
        Err(keyring::Error::NoEntry) => Ok(None),
        Err(err) => Err(ApiError::new("secure_storage", err.to_string())),
    }
}

#[tauri::command]
pub fn secure_storage_set(key: String, value: String) -> Result<(), ApiError> {
    let entry = secure_storage_entry(&key)?;
    entry
        .set_password(&value)
        .map_err(|err| ApiError::new("secure_storage", err.to_string()))
}

#[tauri::command]
pub fn secure_storage_delete(key: String) -> Result<(), ApiError> {
    let entry = secure_storage_entry(&key)?;
    match entry.delete_credential() {
        Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
        Err(err) => Err(ApiError::new("secure_storage", err.to_string())),
    }
}
