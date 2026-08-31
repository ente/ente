mod models;
mod recovery;
mod shares;

pub use models::{
    LEGACY_KIT_PAYLOAD_VERSION, LegacyKit, LegacyKitCreateResult, LegacyKitMetadata,
    LegacyKitOwnerRecoverySession, LegacyKitPart, LegacyKitRecoveryBundle,
    LegacyKitRecoveryInitiator, LegacyKitRecoverySession, LegacyKitRecoveryStatus, LegacyKitShare,
    LegacyKitVariant,
};
pub use recovery::{LegacyKitRecoveryClient, LegacyKitRecoveryHandle};

use ente_core::crypto::{self, SecretVec, kdf};

use crate::{Error, Result};

pub(crate) use shares::{
    checksum, reconstruct_secret_2_of_3, split_secret_2_of_3, used_part_indexes,
};

pub(crate) fn derive_kit_encryption_key(kit_secret: &[u8]) -> Result<SecretVec> {
    let kit_key = crypto::Key::try_from_slice(kit_secret)?;
    kdf::derive_subkey(&kit_key, 32, 1, b"lgkenc01").map_err(Error::from)
}

pub(crate) fn derive_kit_auth_keypair(
    kit_secret: &[u8],
) -> Result<(crypto::PublicKey, crypto::SecretKey)> {
    let kit_key = crypto::Key::try_from_slice(kit_secret)?;
    let seed = kdf::derive_subkey(&kit_key, 32, 2, b"lgkauth1").map_err(Error::from)?;
    let secret_key = crypto::SecretKey::from_seed(seed.as_ref())?;
    Ok((secret_key.public_key(), secret_key))
}
