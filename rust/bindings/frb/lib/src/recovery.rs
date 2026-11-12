use crate::accounts::AccountsError;
use ente_accounts::auth;
use flutter_rust_bridge::frb;

#[frb(sync)]
pub fn recovery_key_to_mnemonic(recovery_key_hex: String) -> Result<String, AccountsError> {
    let recovery_key = hex::decode(&recovery_key_hex)
        .map_err(|e| ente_accounts::Error::Decode(format!("recovery_key: {e}")))?;
    auth::recovery_key_to_mnemonic(&recovery_key).map_err(Into::into)
}
