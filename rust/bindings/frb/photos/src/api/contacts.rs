use std::sync::Arc;

use flutter_rust_bridge::frb;

#[frb]
pub enum ContactsError {
    Network { message: String },
    Http { message: String },
    Parse { message: String },
    Crypto { message: String },
    Auth { message: String },
    InvalidInput { message: String },
    MissingEncryptedData { message: String },
    MissingEncryptedKey { message: String },
    ProfilePictureNotFound { message: String },
    ActiveRecoverySession { message: String },
}

impl From<ente_contacts::Error> for ContactsError {
    fn from(e: ente_contacts::Error) -> Self {
        use ente_contacts::ErrorKind as K;
        let message = ente_core::error::chain(&e);
        match e.kind() {
            K::Network => Self::Network { message },
            K::Http => Self::Http { message },
            K::Parse => Self::Parse { message },
            K::Crypto => Self::Crypto { message },
            K::Auth => Self::Auth { message },
            K::InvalidInput => Self::InvalidInput { message },
            K::MissingEncryptedData => Self::MissingEncryptedData { message },
            K::MissingEncryptedKey => Self::MissingEncryptedKey { message },
            K::ProfilePictureNotFound => Self::ProfilePictureNotFound { message },
            K::ActiveRecoverySession => Self::ActiveRecoverySession { message },
        }
    }
}

#[frb]
#[derive(Clone)]
pub struct WrappedRootContactKey {
    pub encrypted_key: String,
    pub header: String,
}

impl From<ente_contacts::WrappedRootContactKey> for WrappedRootContactKey {
    fn from(value: ente_contacts::WrappedRootContactKey) -> Self {
        Self {
            encrypted_key: value.encrypted_key,
            header: value.header,
        }
    }
}

impl From<WrappedRootContactKey> for ente_contacts::WrappedRootContactKey {
    fn from(value: WrappedRootContactKey) -> Self {
        Self {
            encrypted_key: value.encrypted_key,
            header: value.header,
        }
    }
}

#[frb]
#[derive(Clone)]
pub struct ContactData {
    pub contact_user_id: i64,
    pub name: String,
}

impl From<ContactData> for ente_contacts::ContactData {
    fn from(value: ContactData) -> Self {
        Self {
            contact_user_id: value.contact_user_id,
            name: value.name,
        }
    }
}

#[frb]
#[derive(Clone)]
pub struct ContactRecord {
    pub id: String,
    pub contact_user_id: i64,
    pub email: Option<String>,
    pub name: Option<String>,
    pub profile_picture_attachment_id: Option<String>,
    pub is_deleted: bool,
    pub created_at: i64,
    pub updated_at: i64,
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
            created_at: value.created_at,
            updated_at: value.updated_at,
        }
    }
}

#[frb]
#[derive(Clone)]
pub enum RootKeySource {
    Cache,
    Unresolved,
}

impl From<ente_contacts::RootKeySource> for RootKeySource {
    fn from(value: ente_contacts::RootKeySource) -> Self {
        match value {
            ente_contacts::RootKeySource::Cache => RootKeySource::Cache,
            ente_contacts::RootKeySource::Unresolved => RootKeySource::Unresolved,
        }
    }
}

#[frb]
#[derive(Clone, Copy)]
pub enum AttachmentType {
    ProfilePicture,
}

impl From<AttachmentType> for ente_contacts::AttachmentType {
    fn from(value: AttachmentType) -> Self {
        match value {
            AttachmentType::ProfilePicture => ente_contacts::AttachmentType::ProfilePicture,
        }
    }
}

#[frb]
pub struct OpenContactsCtxInput {
    pub base_url: String,
    pub auth_token: String,
    pub user_id: i64,
    pub master_key: Vec<u8>,
    pub cached_wrapped_root_contact_key: Option<WrappedRootContactKey>,
    pub user_agent: Option<String>,
    pub client_package: Option<String>,
    pub client_version: Option<String>,
}

#[frb]
pub struct OpenContactsCtxResult {
    pub ctx: ContactsCtx,
    pub wrapped_root_contact_key: Option<WrappedRootContactKey>,
    pub root_key_source: RootKeySource,
}

#[frb(opaque)]
#[derive(Clone)]
pub struct ContactsCtx {
    inner: Arc<ente_contacts::ContactsCtx>,
}

#[frb]
pub async fn open_contacts_ctx(
    input: OpenContactsCtxInput,
) -> Result<OpenContactsCtxResult, ContactsError> {
    let opened = ente_contacts::ContactsCtx::open(ente_contacts::OpenContactsCtxInput {
        base_url: input.base_url,
        auth_token: input.auth_token,
        user_id: input.user_id,
        master_key: input.master_key,
        cached_wrapped_root_contact_key: input.cached_wrapped_root_contact_key.map(Into::into),
        user_agent: input.user_agent,
        client_package: input.client_package,
        client_version: input.client_version,
    })
    .await
    .map_err(ContactsError::from)?;

    Ok(OpenContactsCtxResult {
        ctx: ContactsCtx {
            inner: Arc::new(opened.ctx),
        },
        wrapped_root_contact_key: opened.wrapped_root_contact_key.map(Into::into),
        root_key_source: opened.root_key_source.into(),
    })
}

impl ContactsCtx {
    #[frb(sync)]
    pub fn user_id(&self) -> i64 {
        self.inner.user_id()
    }

    pub fn update_auth_token(&self, auth_token: String) {
        self.inner.update_auth_token(auth_token);
    }

    #[frb(sync)]
    pub fn current_wrapped_root_contact_key(&self) -> Option<WrappedRootContactKey> {
        self.inner
            .current_wrapped_root_contact_key()
            .map(Into::into)
    }

    pub async fn create_contact(&self, data: ContactData) -> Result<ContactRecord, ContactsError> {
        self.inner
            .create_contact(&data.into())
            .await
            .map(Into::into)
            .map_err(Into::into)
    }

    pub async fn get_contact(&self, contact_id: String) -> Result<ContactRecord, ContactsError> {
        self.inner
            .get_contact(&contact_id)
            .await
            .map(Into::into)
            .map_err(Into::into)
    }

    pub async fn get_diff(
        &self,
        since_time: i64,
        limit: u16,
    ) -> Result<Vec<ContactRecord>, ContactsError> {
        self.inner
            .get_diff(since_time, limit)
            .await
            .map(|records| records.into_iter().map(Into::into).collect())
            .map_err(Into::into)
    }

    pub async fn update_contact(
        &self,
        contact_id: String,
        data: ContactData,
    ) -> Result<ContactRecord, ContactsError> {
        self.inner
            .update_contact(&contact_id, &data.into())
            .await
            .map(Into::into)
            .map_err(Into::into)
    }

    pub async fn delete_contact(&self, contact_id: String) -> Result<(), ContactsError> {
        self.inner
            .delete_contact(&contact_id)
            .await
            .map_err(Into::into)
    }

    pub async fn set_attachment(
        &self,
        contact_id: String,
        attachment_type: AttachmentType,
        attachment_bytes: Vec<u8>,
    ) -> Result<ContactRecord, ContactsError> {
        self.inner
            .set_attachment(&contact_id, attachment_type.into(), &attachment_bytes)
            .await
            .map(Into::into)
            .map_err(Into::into)
    }

    pub async fn delete_attachment(
        &self,
        contact_id: String,
        attachment_type: AttachmentType,
    ) -> Result<ContactRecord, ContactsError> {
        self.inner
            .delete_attachment(&contact_id, attachment_type.into())
            .await
            .map(Into::into)
            .map_err(Into::into)
    }

    pub async fn get_profile_picture(&self, contact_id: String) -> Result<Vec<u8>, ContactsError> {
        self.inner
            .get_profile_picture(&contact_id)
            .await
            .map_err(Into::into)
    }
}
