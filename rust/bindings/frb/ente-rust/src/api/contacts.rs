//! FRB bindings for contacts APIs.

use std::sync::Arc;

use ente_contacts::{
    AttachmentType as CoreAttachmentType, ContactData as CoreContactData,
    ContactRecord as CoreContactRecord, ContactsCtx as CoreContactsCtx,
    ContactsError as CoreContactsError, LegacyKit as CoreLegacyKit,
    LegacyKitCreateResult as CoreLegacyKitCreateResult, LegacyKitMetadata as CoreLegacyKitMetadata,
    LegacyKitOwnerRecoverySession, LegacyKitPart as CoreLegacyKitPart, LegacyKitRecoveryInitiator,
    LegacyKitRecoverySession as CoreLegacyKitRecoverySession,
    LegacyKitRecoveryStatus as CoreLegacyKitRecoveryStatus, LegacyKitShare as CoreLegacyKitShare,
    LegacyKitVariant as CoreLegacyKitVariant, OpenContactsCtxInput as CoreOpenContactsCtxInput,
    RootKeySource as CoreRootKeySource, WrappedRootContactKey as CoreWrappedRootContactKey,
};
use ente_core::auth::KeyAttributes as CoreKeyAttributes;
use flutter_rust_bridge::frb;

#[frb]
/// Contact API errors exposed over Flutter Rust Bridge.
pub enum ContactsError {
    /// API HTTP error with status and message.
    Http {
        /// Error response body or summary message.
        message: String,
        /// HTTP status code returned by the API.
        status: u16,
    },
    /// Network transport error.
    Network {
        /// Underlying network error description.
        message: String,
    },
    /// Response or payload parse error.
    Parse {
        /// Parse failure description.
        message: String,
    },
    /// Invalid request or base URL error.
    InvalidUrl {
        /// Invalid URL description.
        message: String,
    },
    /// Cryptographic operation failed.
    Crypto {
        /// Cryptographic error description.
        message: String,
    },
    /// Authentication or recovery crypto operation failed.
    Auth {
        /// Authentication error description.
        message: String,
    },
    /// Input validation failed.
    InvalidInput {
        /// Validation failure description.
        message: String,
    },
    /// Missing encrypted contact payload on a live contact response.
    MissingEncryptedData,
    /// Missing encrypted contact key on a live contact response.
    MissingEncryptedKey,
    /// Contact profile picture does not exist.
    ProfilePictureNotFound,
}

impl From<CoreContactsError> for ContactsError {
    fn from(value: CoreContactsError) -> Self {
        match value {
            CoreContactsError::Http(ente_core::http::Error::Http {
                status, message, ..
            }) => ContactsError::Http { message, status },
            CoreContactsError::Http(ente_core::http::Error::Network(message)) => {
                ContactsError::Network { message }
            }
            CoreContactsError::Http(ente_core::http::Error::Parse(message)) => {
                ContactsError::Parse { message }
            }
            CoreContactsError::Http(ente_core::http::Error::InvalidUrl(message)) => {
                ContactsError::InvalidUrl { message }
            }
            CoreContactsError::Crypto(message) => ContactsError::Crypto {
                message: message.to_string(),
            },
            CoreContactsError::Auth(message) => ContactsError::Auth {
                message: message.to_string(),
            },
            CoreContactsError::InvalidInput(message) => ContactsError::InvalidInput { message },
            CoreContactsError::MissingEncryptedData => ContactsError::MissingEncryptedData,
            CoreContactsError::MissingEncryptedKey => ContactsError::MissingEncryptedKey,
            CoreContactsError::ProfilePictureNotFound => ContactsError::ProfilePictureNotFound,
        }
    }
}

#[frb]
#[derive(Clone)]
/// Persistable wrapped root contact key returned from Rust.
pub struct WrappedRootContactKey {
    /// Wrapped root contact key bytes encoded as base64.
    pub encrypted_key: String,
    /// Blob header used to unwrap the root contact key.
    pub header: String,
}

impl From<CoreWrappedRootContactKey> for WrappedRootContactKey {
    fn from(value: CoreWrappedRootContactKey) -> Self {
        Self {
            encrypted_key: value.encrypted_key,
            header: value.header,
        }
    }
}

impl From<WrappedRootContactKey> for CoreWrappedRootContactKey {
    fn from(value: WrappedRootContactKey) -> Self {
        Self {
            encrypted_key: value.encrypted_key,
            header: value.header,
        }
    }
}

#[frb]
#[derive(Clone)]
/// Account key attributes required to decrypt the owner's recovery key.
pub struct AccountKeyAttributes {
    /// Salt for deriving key-encryption-key from password (base64).
    pub kek_salt: String,
    /// Master key encrypted with KEK (base64).
    pub encrypted_key: String,
    /// Nonce for master key decryption (base64).
    pub key_decryption_nonce: String,
    /// X25519 public key (base64).
    pub public_key: String,
    /// Secret key encrypted with master key (base64).
    pub encrypted_secret_key: String,
    /// Nonce for secret key decryption (base64).
    pub secret_key_decryption_nonce: String,
    /// Argon2 memory limit.
    pub mem_limit: Option<u32>,
    /// Argon2 ops limit.
    pub ops_limit: Option<u32>,
    /// Master key encrypted with recovery key (base64).
    pub master_key_encrypted_with_recovery_key: Option<String>,
    /// Nonce for master key decryption with recovery key (base64).
    pub master_key_decryption_nonce: Option<String>,
    /// Recovery key encrypted with master key (base64).
    pub recovery_key_encrypted_with_master_key: Option<String>,
    /// Nonce for recovery key decryption (base64).
    pub recovery_key_decryption_nonce: Option<String>,
}

impl From<AccountKeyAttributes> for CoreKeyAttributes {
    fn from(value: AccountKeyAttributes) -> Self {
        Self {
            kek_salt: value.kek_salt,
            encrypted_key: value.encrypted_key,
            key_decryption_nonce: value.key_decryption_nonce,
            public_key: value.public_key,
            encrypted_secret_key: value.encrypted_secret_key,
            secret_key_decryption_nonce: value.secret_key_decryption_nonce,
            mem_limit: value.mem_limit,
            ops_limit: value.ops_limit,
            master_key_encrypted_with_recovery_key: value.master_key_encrypted_with_recovery_key,
            master_key_decryption_nonce: value.master_key_decryption_nonce,
            recovery_key_encrypted_with_master_key: value.recovery_key_encrypted_with_master_key,
            recovery_key_decryption_nonce: value.recovery_key_decryption_nonce,
        }
    }
}

#[frb]
#[derive(Clone)]
/// Encrypted contact payload fields managed by the client.
pub struct ContactData {
    /// User id of the contact being referenced.
    pub contact_user_id: i64,
    /// User-chosen display name for the contact.
    pub name: String,
    /// Optional birthday in `yyyy-MM-dd` format.
    pub birth_date: Option<String>,
}

impl From<ContactData> for CoreContactData {
    fn from(value: ContactData) -> Self {
        Self {
            contact_user_id: value.contact_user_id,
            name: value.name,
            birth_date: value.birth_date,
        }
    }
}

#[frb]
#[derive(Clone)]
/// Fully decoded contact record returned by Rust.
pub struct ContactRecord {
    /// Stable contact entity id.
    pub id: String,
    /// User id of the referenced contact.
    pub contact_user_id: i64,
    /// Server-resolved mutable email for the referenced user.
    pub email: Option<String>,
    /// Client-managed display name from the encrypted payload.
    pub name: Option<String>,
    /// Optional birthday from the encrypted payload.
    pub birth_date: Option<String>,
    /// Current profile picture attachment id, if any.
    pub profile_picture_attachment_id: Option<String>,
    /// Whether this record is a tombstone.
    pub is_deleted: bool,
    /// Contact creation timestamp in microseconds.
    pub created_at: i64,
    /// Last update timestamp in microseconds.
    pub updated_at: i64,
}

impl From<CoreContactRecord> for ContactRecord {
    fn from(value: CoreContactRecord) -> Self {
        Self {
            id: value.id,
            contact_user_id: value.contact_user_id,
            email: value.email,
            name: value.name,
            birth_date: value.birth_date,
            profile_picture_attachment_id: value.profile_picture_attachment_id,
            is_deleted: value.is_deleted,
            created_at: value.created_at,
            updated_at: value.updated_at,
        }
    }
}

#[frb]
#[derive(Clone, Copy)]
/// Offline legacy kit split variant.
pub enum LegacyKitVariant {
    /// Any two of three sheets can recover the account.
    TwoOfThree,
}

impl From<CoreLegacyKitVariant> for LegacyKitVariant {
    fn from(value: CoreLegacyKitVariant) -> Self {
        match value {
            CoreLegacyKitVariant::TwoOfThree => Self::TwoOfThree,
        }
    }
}

#[frb]
#[derive(Clone, Copy)]
/// Owner-visible recovery session status for an offline legacy kit.
pub enum LegacyKitRecoveryStatus {
    /// Waiting for the selected recovery time.
    Waiting,
    /// Recovery bundle is available.
    Ready,
    /// Owner blocked this recovery attempt.
    Blocked,
    /// Recovery was cancelled.
    Cancelled,
    /// Recovery completed.
    Recovered,
}

impl From<CoreLegacyKitRecoveryStatus> for LegacyKitRecoveryStatus {
    fn from(value: CoreLegacyKitRecoveryStatus) -> Self {
        match value {
            CoreLegacyKitRecoveryStatus::Waiting => Self::Waiting,
            CoreLegacyKitRecoveryStatus::Ready => Self::Ready,
            CoreLegacyKitRecoveryStatus::Blocked => Self::Blocked,
            CoreLegacyKitRecoveryStatus::Cancelled => Self::Cancelled,
            CoreLegacyKitRecoveryStatus::Recovered => Self::Recovered,
        }
    }
}

#[frb]
#[derive(Clone)]
/// Owner-visible recovery session for an offline legacy kit.
pub struct LegacyKitRecoverySession {
    /// Recovery session id.
    pub id: String,
    /// Kit id being recovered.
    pub kit_id: String,
    /// Current recovery status.
    pub status: LegacyKitRecoveryStatus,
    /// Remaining microseconds until the recovery becomes usable.
    pub wait_till: i64,
    /// Session creation timestamp.
    pub created_at: i64,
}

impl From<CoreLegacyKitRecoverySession> for LegacyKitRecoverySession {
    fn from(value: CoreLegacyKitRecoverySession) -> Self {
        Self {
            id: value.id,
            kit_id: value.kit_id,
            status: value.status.into(),
            wait_till: value.wait_till,
            created_at: value.created_at,
        }
    }
}

#[frb]
#[derive(Clone)]
/// Owner-facing audit hint for a successful legacy kit recovery open.
pub struct LegacyKitRecoveryInitiatorHint {
    /// Client-reported sheet indexes used by the recovery flow.
    pub used_part_indexes: Vec<u8>,
    /// Server-observed IP address.
    pub ip: String,
    /// Server-observed user agent.
    pub user_agent: String,
}

impl From<LegacyKitRecoveryInitiator> for LegacyKitRecoveryInitiatorHint {
    fn from(value: LegacyKitRecoveryInitiator) -> Self {
        Self {
            used_part_indexes: value.used_part_indexes,
            ip: value.ip,
            user_agent: value.user_agent,
        }
    }
}

#[frb]
#[derive(Clone)]
/// Owner-facing recovery session details for a legacy kit.
pub struct LegacyKitOwnerRecoverySessionDetails {
    /// Active session, if one exists.
    pub session: Option<LegacyKitRecoverySession>,
    /// Server-captured audit hints for successful recovery opens.
    pub initiators: Vec<LegacyKitRecoveryInitiatorHint>,
}

impl From<LegacyKitOwnerRecoverySession> for LegacyKitOwnerRecoverySessionDetails {
    fn from(value: LegacyKitOwnerRecoverySession) -> Self {
        Self {
            session: value.session.map(Into::into),
            initiators: value.initiators.into_iter().map(Into::into).collect(),
        }
    }
}

#[frb]
#[derive(Clone)]
/// One named part of an offline legacy kit.
pub struct LegacyKitPart {
    /// One-based part index encoded in the recovery sheet.
    pub index: u8,
    /// Human-readable part holder/storage name.
    pub name: String,
}

impl From<CoreLegacyKitPart> for LegacyKitPart {
    fn from(value: CoreLegacyKitPart) -> Self {
        Self {
            index: value.index,
            name: value.name,
        }
    }
}

#[frb]
#[derive(Clone)]
/// Decrypted owner metadata for an offline legacy kit.
pub struct LegacyKitMetadata {
    /// Named recovery parts.
    pub parts: Vec<LegacyKitPart>,
}

impl From<CoreLegacyKitMetadata> for LegacyKitMetadata {
    fn from(value: CoreLegacyKitMetadata) -> Self {
        Self {
            parts: value.parts.into_iter().map(Into::into).collect(),
        }
    }
}

#[frb]
#[derive(Clone)]
/// Offline legacy kit record visible to the owner.
pub struct LegacyKit {
    /// Stable kit id.
    pub id: String,
    /// Split variant.
    pub variant: LegacyKitVariant,
    /// Configured notice period in hours.
    pub notice_period_in_hours: i32,
    /// Public URL of the legacy recovery web app for this server.
    pub legacy_url: String,
    /// Decrypted owner metadata.
    pub metadata: LegacyKitMetadata,
    /// Kit creation timestamp.
    pub created_at: i64,
    /// Kit update timestamp.
    pub updated_at: i64,
    /// Active owner-visible recovery session, if any.
    pub active_recovery_session: Option<LegacyKitRecoverySession>,
}

impl From<CoreLegacyKit> for LegacyKit {
    fn from(value: CoreLegacyKit) -> Self {
        Self {
            id: value.id,
            variant: value.variant.into(),
            notice_period_in_hours: value.notice_period_in_hours,
            legacy_url: value.legacy_url,
            metadata: value.metadata.into(),
            created_at: value.created_at,
            updated_at: value.updated_at,
            active_recovery_session: value.active_recovery_session.map(Into::into),
        }
    }
}

#[frb]
#[derive(Clone)]
/// One offline legacy kit recovery share to encode into a recovery sheet.
pub struct LegacyKitShare {
    /// Payload version.
    pub payload_version: u8,
    /// Split variant.
    pub variant: LegacyKitVariant,
    /// Kit id.
    pub kit_id: String,
    /// One-based share index.
    pub share_index: u8,
    /// Encoded share bytes.
    pub share: String,
    /// Share checksum.
    pub checksum: String,
    /// Human-readable part name.
    pub part_name: String,
}

impl From<CoreLegacyKitShare> for LegacyKitShare {
    fn from(value: CoreLegacyKitShare) -> Self {
        Self {
            payload_version: value.payload_version,
            variant: value.variant.into(),
            kit_id: value.kit_id,
            share_index: value.share_index,
            share: value.share,
            checksum: value.checksum,
            part_name: value.part_name,
        }
    }
}

#[frb]
#[derive(Clone)]
/// Result of creating an offline legacy kit.
pub struct LegacyKitCreateResult {
    /// Created kit record.
    pub kit: LegacyKit,
    /// Recovery shares that must be exported immediately.
    pub shares: Vec<LegacyKitShare>,
}

impl From<CoreLegacyKitCreateResult> for LegacyKitCreateResult {
    fn from(value: CoreLegacyKitCreateResult) -> Self {
        Self {
            kit: value.kit.into(),
            shares: value.shares.into_iter().map(Into::into).collect(),
        }
    }
}

#[frb]
#[derive(Clone)]
/// Source used to obtain the root contact key during open.
pub enum RootKeySource {
    /// Reused the caller-provided cached wrapped root key.
    Cache,
    /// Opened without a cached wrapped root key; Rust will resolve it lazily.
    Unresolved,
}

impl From<CoreRootKeySource> for RootKeySource {
    fn from(value: CoreRootKeySource) -> Self {
        match value {
            CoreRootKeySource::Cache => RootKeySource::Cache,
            CoreRootKeySource::Unresolved => RootKeySource::Unresolved,
        }
    }
}

#[frb]
#[derive(Clone, Copy)]
/// Attachment types supported by the contacts subsystem.
pub enum AttachmentType {
    /// Current contact profile picture.
    ProfilePicture,
}

impl From<AttachmentType> for CoreAttachmentType {
    fn from(value: AttachmentType) -> Self {
        match value {
            AttachmentType::ProfilePicture => CoreAttachmentType::ProfilePicture,
        }
    }
}

#[frb]
/// Input required to open an account-scoped contacts context.
pub struct OpenContactsCtxInput {
    /// Base Ente API URL.
    pub base_url: String,
    /// Auth token for Ente API requests.
    pub auth_token: String,
    /// Logged-in owner user id.
    pub user_id: i64,
    /// Logged-in account key used to unwrap or create the root contact key.
    pub master_key: Vec<u8>,
    /// Optional cached wrapped root key for the current user.
    pub cached_wrapped_root_contact_key: Option<WrappedRootContactKey>,
    /// Optional user agent to send to Ente API endpoints.
    pub user_agent: Option<String>,
    /// Optional client package header to send to Ente API endpoints.
    pub client_package: Option<String>,
    /// Optional client version header to send to Ente API endpoints.
    pub client_version: Option<String>,
}

#[frb]
/// Result returned when opening a contacts context.
pub struct OpenContactsCtxResult {
    /// Opaque contacts context bound to the current account/session.
    pub ctx: ContactsCtx,
    /// Current wrapped root key that the caller may persist, if already resolved.
    pub wrapped_root_contact_key: Option<WrappedRootContactKey>,
    /// State of the root key during open.
    pub root_key_source: RootKeySource,
}

#[frb(opaque)]
#[derive(Clone)]
/// Opaque account-scoped contacts context exposed to Flutter.
pub struct ContactsCtx {
    inner: Arc<CoreContactsCtx>,
}

#[frb]
/// Open a contacts context for the current account.
pub async fn open_contacts_ctx(
    input: OpenContactsCtxInput,
) -> Result<OpenContactsCtxResult, ContactsError> {
    let opened = CoreContactsCtx::open(CoreOpenContactsCtxInput {
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
    /// Return the owner user id for this contacts context.
    pub fn user_id(&self) -> i64 {
        self.inner.user_id()
    }

    /// Replace the auth token used for subsequent API requests.
    pub fn update_auth_token(&self, auth_token: String) {
        self.inner.update_auth_token(auth_token);
    }

    #[frb(sync)]
    /// Return the current wrapped root key for caller-managed persistence, if resolved.
    pub fn current_wrapped_root_contact_key(&self) -> Option<WrappedRootContactKey> {
        self.inner
            .current_wrapped_root_contact_key()
            .map(Into::into)
    }

    /// Create a contact for the referenced user.
    pub async fn create_contact(&self, data: ContactData) -> Result<ContactRecord, ContactsError> {
        self.inner
            .create_contact(&data.into())
            .await
            .map(Into::into)
            .map_err(Into::into)
    }

    /// Fetch a single contact by id.
    pub async fn get_contact(&self, contact_id: String) -> Result<ContactRecord, ContactsError> {
        self.inner
            .get_contact(&contact_id)
            .await
            .map(Into::into)
            .map_err(Into::into)
    }

    /// Fetch a contacts diff since the provided timestamp.
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

    /// Update the encrypted payload for an existing contact.
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

    /// Tombstone a contact by id.
    pub async fn delete_contact(&self, contact_id: String) -> Result<(), ContactsError> {
        self.inner
            .delete_contact(&contact_id)
            .await
            .map_err(Into::into)
    }

    /// Encrypt and upload a new attachment for the contact.
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

    /// Download an encrypted attachment by type and attachment id.
    pub async fn get_attachment_encrypted(
        &self,
        attachment_type: AttachmentType,
        attachment_id: String,
    ) -> Result<Vec<u8>, ContactsError> {
        self.inner
            .get_attachment_encrypted(attachment_type.into(), &attachment_id)
            .await
            .map_err(Into::into)
    }

    /// Remove the current attachment for a contact and type.
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

    /// Encrypt and upload a new contact profile picture.
    pub async fn set_profile_picture(
        &self,
        contact_id: String,
        profile_picture: Vec<u8>,
    ) -> Result<ContactRecord, ContactsError> {
        self.set_attachment(contact_id, AttachmentType::ProfilePicture, profile_picture)
            .await
    }

    /// Download and decrypt the current contact profile picture.
    pub async fn get_profile_picture(&self, contact_id: String) -> Result<Vec<u8>, ContactsError> {
        self.inner
            .get_profile_picture(&contact_id)
            .await
            .map_err(Into::into)
    }

    /// Remove the current contact profile picture.
    pub async fn delete_profile_picture(
        &self,
        contact_id: String,
    ) -> Result<ContactRecord, ContactsError> {
        self.delete_attachment(contact_id, AttachmentType::ProfilePicture)
            .await
    }

    /// List owner-created offline legacy kits.
    pub async fn legacy_kits(&self) -> Result<Vec<LegacyKit>, ContactsError> {
        self.inner
            .legacy_kits()
            .await
            .map(|kits| kits.into_iter().map(Into::into).collect())
            .map_err(Into::into)
    }

    /// Create an offline legacy kit and return the printable recovery shares.
    pub async fn legacy_kit_create(
        &self,
        current_user_key_attrs: AccountKeyAttributes,
        part_names: Vec<String>,
        notice_period_in_hours: i32,
    ) -> Result<LegacyKitCreateResult, ContactsError> {
        let part_names: [String; 3] =
            part_names
                .try_into()
                .map_err(|_| ContactsError::InvalidInput {
                    message: "legacy kit requires exactly three part names".into(),
                })?;
        self.inner
            .legacy_kit_create(
                &current_user_key_attrs.into(),
                part_names,
                notice_period_in_hours,
            )
            .await
            .map(Into::into)
            .map_err(Into::into)
    }

    /// Download the printable recovery shares for an existing offline legacy kit.
    pub async fn legacy_kit_download_shares(
        &self,
        kit_id: String,
    ) -> Result<Vec<LegacyKitShare>, ContactsError> {
        self.inner
            .legacy_kit_download_shares(&kit_id)
            .await
            .map(|shares| shares.into_iter().map(Into::into).collect())
            .map_err(Into::into)
    }

    /// Fetch owner-visible active recovery session details for a legacy kit.
    pub async fn legacy_kit_recovery_session(
        &self,
        kit_id: String,
    ) -> Result<LegacyKitOwnerRecoverySessionDetails, ContactsError> {
        self.inner
            .legacy_kit_recovery_session(&kit_id)
            .await
            .map(Into::into)
            .map_err(Into::into)
    }

    /// Update the recovery wait time for a legacy kit.
    pub async fn legacy_kit_update_recovery_notice(
        &self,
        kit_id: String,
        notice_period_in_hours: i32,
    ) -> Result<(), ContactsError> {
        self.inner
            .legacy_kit_update_recovery_notice(&kit_id, notice_period_in_hours)
            .await
            .map_err(Into::into)
    }

    /// Block the active recovery session for a legacy kit.
    pub async fn legacy_kit_block_recovery(&self, kit_id: String) -> Result<(), ContactsError> {
        self.inner
            .legacy_kit_block_recovery(&kit_id)
            .await
            .map_err(Into::into)
    }

    /// Delete an offline legacy kit.
    pub async fn legacy_kit_delete(&self, kit_id: String) -> Result<(), ContactsError> {
        self.inner
            .legacy_kit_delete(&kit_id)
            .await
            .map_err(Into::into)
    }
}
