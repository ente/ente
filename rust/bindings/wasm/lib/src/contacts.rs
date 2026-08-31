use serde::{Serialize, Serializer};
use serde_wasm_bindgen as swb;
use tsify::Tsify;
use wasm_bindgen::prelude::*;

use crate::session::Session;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Contacts(#[from] ente_contacts::Error),
    #[error(transparent)]
    Serde(#[from] swb::Error),
}

impl Error {
    fn name(&self) -> Option<&'static str> {
        None
    }

    fn message(&self) -> String {
        ente_core::error::chain(self)
    }
}

impl From<Error> for JsValue {
    fn from(error: Error) -> Self {
        let js_error = js_sys::Error::new(&error.message());
        if let Some(name) = error.name() {
            js_error.set_name(name);
        }
        js_error.into()
    }
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
struct ContactRecord {
    id: String,
    contact_user_id: i64,
    email: Option<String>,
    name: Option<String>,
    #[serde(rename = "profilePictureAttachmentID")]
    profile_picture_attachment_id: Option<String>,
    is_deleted: bool,
    updated_at: i64,
}

impl From<ente_contacts::ContactRecord> for ContactRecord {
    fn from(value: ente_contacts::ContactRecord) -> Self {
        Self {
            id: value.id,
            contact_user_id: value.contact_user_id,
            email: value.email,
            name: value.name,
            profile_picture_attachment_id: value.profile_picture_attachment_id,
            is_deleted: value.is_deleted,
            updated_at: value.updated_at,
        }
    }
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct ContactsDiffOutput {
    records: Vec<ContactRecord>,
    wrapped_root_contact_key: Option<WrappedRootContactKey>,
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct ProfilePictureOutput {
    #[serde(serialize_with = "serialize_bytes")]
    #[tsify(type = "Uint8Array")]
    bytes: Vec<u8>,
    wrapped_root_contact_key: Option<WrappedRootContactKey>,
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
struct WrappedRootContactKey {
    encrypted_key: String,
    header: String,
}

impl From<ente_contacts::WrappedRootContactKey> for WrappedRootContactKey {
    fn from(value: ente_contacts::WrappedRootContactKey) -> Self {
        Self {
            encrypted_key: value.encrypted_key,
            header: value.header,
        }
    }
}

#[wasm_bindgen(js_name = contactsGetDiff)]
pub async fn contacts_get_diff(
    session: &Session,
    cached_encrypted_key: Option<String>,
    cached_header: Option<String>,
    since_time: i64,
    limit: u16,
) -> Result<<ContactsDiffOutput as Tsify>::JsType, Error> {
    let cached = wrapped_root_contact_key(cached_encrypted_key, cached_header);
    let output =
        ente_contacts::get_diff(session.inner(), cached.as_ref(), since_time, limit).await?;
    let output = ContactsDiffOutput {
        records: output.value.into_iter().map(Into::into).collect(),
        wrapped_root_contact_key: output.wrapped_root_contact_key.map(Into::into),
    };
    output.into_js().map_err(Into::into)
}

#[wasm_bindgen(js_name = contactsGetProfilePicture)]
pub async fn contacts_get_profile_picture(
    session: &Session,
    cached_encrypted_key: Option<String>,
    cached_header: Option<String>,
    contact_id: &str,
) -> Result<<ProfilePictureOutput as Tsify>::JsType, Error> {
    let cached = wrapped_root_contact_key(cached_encrypted_key, cached_header);
    let output =
        ente_contacts::get_profile_picture(session.inner(), cached.as_ref(), contact_id).await?;
    ProfilePictureOutput {
        bytes: output.value,
        wrapped_root_contact_key: output.wrapped_root_contact_key.map(Into::into),
    }
    .into_js()
    .map_err(Into::into)
}

fn wrapped_root_contact_key(
    encrypted_key: Option<String>,
    header: Option<String>,
) -> Option<ente_contacts::WrappedRootContactKey> {
    encrypted_key.zip(header).map(
        |(encrypted_key, header)| ente_contacts::WrappedRootContactKey {
            encrypted_key,
            header,
        },
    )
}

fn serialize_bytes<S>(bytes: &[u8], serializer: S) -> Result<S::Ok, S::Error>
where
    S: Serializer,
{
    serializer.serialize_bytes(bytes)
}
