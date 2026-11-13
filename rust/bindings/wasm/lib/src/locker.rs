use ente_core::{b64, crypto::Key};
use serde::Serialize;
use serde_wasm_bindgen as swb;
use tsify::Tsify;
use wasm_bindgen::prelude::*;

use crate::session::Session;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Decode(#[from] b64::DecodeError),
    #[error(transparent)]
    Crypto(#[from] ente_core::crypto::Error),
    #[error(transparent)]
    Locker(#[from] ente_locker::Error),
    #[error(transparent)]
    Serde(#[from] swb::Error),
}

impl From<Error> for JsValue {
    fn from(error: Error) -> Self {
        crate::js_error(&error, None)
    }
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct PreparedFileLinkPayload {
    fragment: String,
    encrypted_file_key: String,
    encrypted_file_key_nonce: String,
    kdf_nonce: String,
    kdf_mem_limit: u64,
    kdf_ops_limit: u32,
}

#[wasm_bindgen(js_name = lockerPrepareFileLinkPayload)]
pub fn prepare_file_link_payload(
    file_key_b64: &str,
) -> Result<<PreparedFileLinkPayload as Tsify>::JsType, Error> {
    let file_key = Key::try_from_slice(&b64::decode(file_key_b64)?)?;
    let (fragment, payload) = ente_locker::prepare_file_link_payload(&file_key)?;
    PreparedFileLinkPayload {
        fragment,
        encrypted_file_key: payload.encrypted_file_key,
        encrypted_file_key_nonce: payload.encrypted_file_key_nonce,
        kdf_nonce: payload.kdf_nonce,
        kdf_mem_limit: payload.kdf_mem_limit,
        kdf_ops_limit: payload.kdf_ops_limit,
    }
    .into_js()
    .map_err(Into::into)
}

#[wasm_bindgen(js_name = lockerSealFileLinkSecret)]
pub fn seal_file_link_secret(session: &Session, fragment: &str) -> Result<String, Error> {
    Ok(ente_locker::seal_file_link_secret(
        session.inner(),
        fragment,
    )?)
}

#[wasm_bindgen(js_name = lockerOpenFileLinkSecret)]
pub fn open_file_link_secret(
    session: &Session,
    encrypted_share_key: &str,
) -> Result<String, Error> {
    Ok(ente_locker::open_file_link_secret(
        session.inner(),
        encrypted_share_key,
    )?)
}
