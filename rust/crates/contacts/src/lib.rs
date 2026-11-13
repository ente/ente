mod client;
mod error;

pub use client::{
    AttachmentType, ContactData, ContactOutput, ContactRecord, WrappedRootContactKey,
    create_contact, delete_attachment, delete_contact, delete_profile_picture,
    get_attachment_encrypted, get_contact, get_diff, get_profile_picture, set_attachment,
    set_profile_picture, update_contact,
};
pub use error::{Error, Result};
