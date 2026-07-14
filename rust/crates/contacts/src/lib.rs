pub mod client;
pub mod crypto;
pub mod error;
pub mod legacy_kit;
pub mod legacy_kit_models;
pub mod legacy_kit_transport;
pub mod legacy_models;
pub mod legacy_transport;
pub mod models;
pub mod transport;

pub use client::{ContactsCtx, OpenContactsCtxInput, OpenContactsCtxResult, RootKeySource};
pub use error::{ContactsError, ErrorKind, Result};
pub use legacy_kit::{LegacyKitRecoveryClient, LegacyKitRecoveryHandle};
pub use legacy_kit_models::{
    LEGACY_KIT_PAYLOAD_VERSION, LegacyKit, LegacyKitCreateResult, LegacyKitMetadata,
    LegacyKitOwnerRecoverySession, LegacyKitPart, LegacyKitRecoveryBundle,
    LegacyKitRecoveryInitiator, LegacyKitRecoverySession, LegacyKitRecoveryStatus, LegacyKitShare,
    LegacyKitVariant,
};
pub use legacy_models::{
    LegacyContactRecord, LegacyContactState, LegacyInfo, LegacyRecoveryBundle,
    LegacyRecoverySession, LegacyRecoveryStatus, LegacyUser,
};
pub use models::{AttachmentType, ContactData, ContactRecord, WrappedRootContactKey};
