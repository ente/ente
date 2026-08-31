mod contact;
mod kit;
mod recovery;

pub use contact::{
    LegacyContactRecord, LegacyContactState, LegacyInfo, LegacyRecoverySession,
    LegacyRecoveryStatus, LegacyUser, add_contact, info, public_key, update_contact,
    update_recovery_notice, verification_id,
};
pub use kit::{
    block_kit_recovery, create_kit, delete_kit, download_kit_shares, kit_recovery_session, kits,
    update_kit_recovery_notice,
};
pub use recovery::{
    LegacyRecoveryBundle, approve_recovery, change_password, recovery_bundle, reject_recovery,
    start_recovery, stop_recovery,
};

use ente_accounts::auth::{self, KeyAttributes};
use ente_core::{Session, crypto::SecretVec};

use crate::Result;

fn current_recovery_key(session: &Session, key_attributes: &KeyAttributes) -> Result<SecretVec> {
    let recovery_key = auth::get_recovery_key(&session.master_key, key_attributes)?;
    Ok(auth::recovery_key_from_mnemonic_or_hex(&recovery_key)?)
}
