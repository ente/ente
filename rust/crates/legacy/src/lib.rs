mod client;
mod error;
mod kit;

pub use client::{
    LegacyContactRecord, LegacyContactState, LegacyInfo, LegacyRecoveryBundle,
    LegacyRecoverySession, LegacyRecoveryStatus, LegacyUser, add_contact, approve_recovery,
    block_kit_recovery, change_password, create_kit, delete_kit, download_kit_shares, info,
    kit_recovery_session, kits, public_key, recovery_bundle, reject_recovery, start_recovery,
    stop_recovery, update_contact, update_kit_recovery_notice, update_recovery_notice,
    verification_id,
};
pub use error::{Error, Result};
pub use kit::{
    LEGACY_KIT_PAYLOAD_VERSION, LegacyKit, LegacyKitCreateResult, LegacyKitMetadata,
    LegacyKitOwnerRecoverySession, LegacyKitPart, LegacyKitRecoveryBundle, LegacyKitRecoveryClient,
    LegacyKitRecoveryHandle, LegacyKitRecoveryInitiator, LegacyKitRecoverySession,
    LegacyKitRecoveryStatus, LegacyKitShare, LegacyKitVariant,
};
