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

use ente_core::http;

use crate::Error;

fn map_recovery_notice_error(error: http::Error) -> Error {
    match &error {
        http::Error::Api { code, .. } if code == "ACTIVE_RECOVERY_SESSION" => {
            Error::ActiveRecoverySession
        }
        _ => error.into(),
    }
}
