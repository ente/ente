use flutter_rust_bridge::frb;

use crate::session::Session;

pub mod types;
pub use types::{
    AttachmentType, ContactData, ContactDiffOutput, ContactRecord, ContactRecordOutput,
    ProfilePictureOutput, WrappedRootContactKey,
};

#[frb(non_opaque)]
pub enum ContactsError {
    Other { message: String },
}

impl From<ente_contacts::Error> for ContactsError {
    fn from(error: ente_contacts::Error) -> Self {
        Self::Other {
            message: ente_core::error::chain(&error),
        }
    }
}

pub async fn create_contact(
    session: &Session,
    wrapped_root_contact_key: Option<WrappedRootContactKey>,
    data: ContactData,
) -> Result<ContactRecordOutput, ContactsError> {
    let key = wrapped_root_contact_key.map(Into::into);
    let output =
        ente_contacts::create_contact(session.as_ref(), key.as_ref(), &data.into()).await?;
    Ok(ContactRecordOutput {
        record: output.value.into(),
        wrapped_root_contact_key: output.wrapped_root_contact_key.map(Into::into),
    })
}

pub async fn get_diff(
    session: &Session,
    wrapped_root_contact_key: Option<WrappedRootContactKey>,
    since_time: i64,
    limit: u16,
) -> Result<ContactDiffOutput, ContactsError> {
    let key = wrapped_root_contact_key.map(Into::into);
    let output = ente_contacts::get_diff(session.as_ref(), key.as_ref(), since_time, limit).await?;
    Ok(ContactDiffOutput {
        records: output.value.into_iter().map(Into::into).collect(),
        wrapped_root_contact_key: output.wrapped_root_contact_key.map(Into::into),
    })
}

pub async fn update_contact(
    session: &Session,
    wrapped_root_contact_key: Option<WrappedRootContactKey>,
    contact_id: String,
    data: ContactData,
) -> Result<ContactRecordOutput, ContactsError> {
    let key = wrapped_root_contact_key.map(Into::into);
    let output =
        ente_contacts::update_contact(session.as_ref(), key.as_ref(), &contact_id, &data.into())
            .await?;
    Ok(ContactRecordOutput {
        record: output.value.into(),
        wrapped_root_contact_key: output.wrapped_root_contact_key.map(Into::into),
    })
}

pub async fn delete_contact(session: &Session, contact_id: String) -> Result<(), ContactsError> {
    ente_contacts::delete_contact(session.as_ref(), &contact_id)
        .await
        .map_err(Into::into)
}

pub async fn set_attachment(
    session: &Session,
    wrapped_root_contact_key: Option<WrappedRootContactKey>,
    contact_id: String,
    attachment_type: AttachmentType,
    attachment_bytes: Vec<u8>,
) -> Result<ContactRecordOutput, ContactsError> {
    let key = wrapped_root_contact_key.map(Into::into);
    let output = ente_contacts::set_attachment(
        session.as_ref(),
        key.as_ref(),
        &contact_id,
        attachment_type.into(),
        &attachment_bytes,
    )
    .await?;
    Ok(ContactRecordOutput {
        record: output.value.into(),
        wrapped_root_contact_key: output.wrapped_root_contact_key.map(Into::into),
    })
}

pub async fn delete_attachment(
    session: &Session,
    wrapped_root_contact_key: Option<WrappedRootContactKey>,
    contact_id: String,
    attachment_type: AttachmentType,
) -> Result<ContactRecordOutput, ContactsError> {
    let key = wrapped_root_contact_key.map(Into::into);
    let output = ente_contacts::delete_attachment(
        session.as_ref(),
        key.as_ref(),
        &contact_id,
        attachment_type.into(),
    )
    .await?;
    Ok(ContactRecordOutput {
        record: output.value.into(),
        wrapped_root_contact_key: output.wrapped_root_contact_key.map(Into::into),
    })
}

pub async fn get_profile_picture(
    session: &Session,
    wrapped_root_contact_key: Option<WrappedRootContactKey>,
    contact_id: String,
) -> Result<ProfilePictureOutput, ContactsError> {
    let key = wrapped_root_contact_key.map(Into::into);
    let output =
        ente_contacts::get_profile_picture(session.as_ref(), key.as_ref(), &contact_id).await?;
    Ok(ProfilePictureOutput {
        bytes: output.value,
        wrapped_root_contact_key: output.wrapped_root_contact_key.map(Into::into),
    })
}
