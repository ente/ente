use ente_core::crypto::Key;
use flutter_rust_bridge::frb;

use crate::session::Session;

#[frb(non_opaque)]
pub enum LockerError {
    Other { message: String },
}

impl From<ente_locker::Error> for LockerError {
    fn from(error: ente_locker::Error) -> Self {
        Self::Other {
            message: ente_core::error::chain(&error),
        }
    }
}

#[frb(non_opaque)]
pub struct PreparedFileLink {
    pub fragment: String,
    pub encrypted_file_key: String,
    pub encrypted_file_key_nonce: String,
    pub kdf_nonce: String,
    pub kdf_mem_limit: u64,
    pub kdf_ops_limit: u32,
    pub encrypted_share_key: String,
}

pub fn prepare_file_link(
    session: &Session,
    file_key: Vec<u8>,
) -> Result<PreparedFileLink, LockerError> {
    let file_key = Key::try_from_slice(&file_key).map_err(ente_locker::Error::from)?;
    let (fragment, payload) = ente_locker::prepare_file_link_payload(&file_key)?;
    let encrypted_share_key = ente_locker::seal_file_link_secret(session.as_ref(), &fragment)?;
    Ok(PreparedFileLink {
        fragment,
        encrypted_file_key: payload.encrypted_file_key,
        encrypted_file_key_nonce: payload.encrypted_file_key_nonce,
        kdf_nonce: payload.kdf_nonce,
        kdf_mem_limit: payload.kdf_mem_limit,
        kdf_ops_limit: payload.kdf_ops_limit,
        encrypted_share_key,
    })
}

pub fn open_file_link_secret(
    session: &Session,
    encrypted_share_key: String,
) -> Result<String, LockerError> {
    ente_locker::open_file_link_secret(session.as_ref(), &encrypted_share_key).map_err(Into::into)
}
