use flutter_rust_bridge::frb;

use ente_frb_lib::legacy::{LegacyError, LegacyKit, LegacyKitCreateResult, LegacyKitShare};
use ente_frb_lib::session::Session;

#[frb]
#[derive(Clone)]
pub struct AccountKeyAttributes {
    pub kek_salt: String,
    pub encrypted_key: String,
    pub key_decryption_nonce: String,
    pub public_key: String,
    pub encrypted_secret_key: String,
    pub secret_key_decryption_nonce: String,
    pub mem_limit: u32,
    pub ops_limit: u32,
    pub master_key_encrypted_with_recovery_key: Option<String>,
    pub master_key_decryption_nonce: Option<String>,
    pub recovery_key_encrypted_with_master_key: Option<String>,
    pub recovery_key_decryption_nonce: Option<String>,
}

impl From<AccountKeyAttributes> for ente_accounts::auth::KeyAttributes {
    fn from(value: AccountKeyAttributes) -> Self {
        Self {
            kek_salt: value.kek_salt,
            kek_hash: None,
            encrypted_key: value.encrypted_key,
            key_decryption_nonce: value.key_decryption_nonce,
            public_key: value.public_key,
            encrypted_secret_key: value.encrypted_secret_key,
            secret_key_decryption_nonce: value.secret_key_decryption_nonce,
            mem_limit: value.mem_limit,
            ops_limit: value.ops_limit,
            master_key_encrypted_with_recovery_key: value.master_key_encrypted_with_recovery_key,
            master_key_decryption_nonce: value.master_key_decryption_nonce,
            recovery_key_encrypted_with_master_key: value.recovery_key_encrypted_with_master_key,
            recovery_key_decryption_nonce: value.recovery_key_decryption_nonce,
        }
    }
}

pub async fn kits(session: &Session) -> Result<Vec<LegacyKit>, LegacyError> {
    ente_legacy::kits(session.as_ref())
        .await
        .map(|kits| kits.into_iter().map(Into::into).collect())
        .map_err(Into::into)
}

pub async fn create_kit(
    session: &Session,
    current_user_key_attrs: AccountKeyAttributes,
    part_names: Vec<String>,
    notice_period_in_hours: i32,
) -> Result<LegacyKitCreateResult, LegacyError> {
    let part_names: [String; 3] = part_names.try_into().map_err(|_| LegacyError::Other {
        message: "legacy kit requires exactly three part names".into(),
    })?;
    ente_legacy::create_kit(
        session.as_ref(),
        &current_user_key_attrs.into(),
        part_names,
        notice_period_in_hours,
    )
    .await
    .map(Into::into)
    .map_err(Into::into)
}

pub async fn download_kit_shares(
    session: &Session,
    kit_id: String,
) -> Result<Vec<LegacyKitShare>, LegacyError> {
    ente_legacy::download_kit_shares(session.as_ref(), &kit_id)
        .await
        .map(|shares| shares.into_iter().map(Into::into).collect())
        .map_err(Into::into)
}

pub async fn update_kit_recovery_notice(
    session: &Session,
    kit_id: String,
    notice_period_in_hours: i32,
) -> Result<(), LegacyError> {
    ente_legacy::update_kit_recovery_notice(session.as_ref(), &kit_id, notice_period_in_hours)
        .await
        .map_err(Into::into)
}

pub async fn block_kit_recovery(session: &Session, kit_id: String) -> Result<(), LegacyError> {
    ente_legacy::block_kit_recovery(session.as_ref(), &kit_id)
        .await
        .map_err(Into::into)
}

pub async fn delete_kit(session: &Session, kit_id: String) -> Result<(), LegacyError> {
    ente_legacy::delete_kit(session.as_ref(), &kit_id)
        .await
        .map_err(Into::into)
}
