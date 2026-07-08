use std::sync::{Arc, RwLock};

use ente_core::auth::{self, KeyAttributes, SrpSession};
use ente_core::crypto::{self, SecretVec, sealed, secretbox};
use ente_core::http_legacy::{Error as HttpError, HttpClient, HttpConfig};
use sha2::{Digest, Sha256};
use uuid::Uuid;

use crate::crypto as contacts_crypto;
use crate::error::{ContactsError, Result};
use crate::legacy_kit::{
    create_legacy_kit_request, decode_download_content, decode_legacy_kit_record,
    validate_notice_period,
};
use crate::legacy_kit_models::{
    LegacyKit, LegacyKitCreateResult, LegacyKitOwnerRecoverySession, LegacyKitShare,
};
use crate::legacy_kit_transport::{
    LegacyKitDownloadContentResponse, LegacyKitOwnerActionRequest,
    LegacyKitOwnerRecoverySessionResponse, LegacyKitRecordResponse,
    LegacyKitUpdateRecoveryNoticeRequest, ListLegacyKitsResponse,
};
use crate::legacy_models::{LegacyContactState, LegacyInfo, LegacyRecoveryBundle};
use crate::legacy_transport::{
    LegacyAddContactRequest, LegacyChangePasswordRequest, LegacyChangePasswordResponse,
    LegacyContactIdentifier, LegacyInfoResponse, LegacyInitChangePasswordRequest,
    LegacyPublicKeyResponse, LegacyRecoveryIdentifier, LegacyRecoveryInfoResponse,
    LegacySetupSrpRequest, LegacySetupSrpResponse, LegacyUpdateContactRequest,
    LegacyUpdateRecoveryNoticeRequest, LegacyUpdateSrpAndKeysRequest, LegacyUpdatedKeyAttr,
};
use crate::models::{AttachmentType, ContactData, ContactRecord, WrappedRootContactKey};
use crate::transport::{
    AttachmentUploadUrlRequest, AttachmentUploadUrlResponse, CommitAttachmentRequest,
    ContactDiffResponse, ContactEntityResponse, CreateContactRequest, CreateRootKeyRequest,
    RootKeyResponse, SignedUrlResponse, UpdateContactRequest,
};

const CONTACT_TYPE: &str = "contact";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RootKeySource {
    Cache,
    Unresolved,
}

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

pub struct OpenContactsCtxResult {
    pub ctx: ContactsCtx,
    pub wrapped_root_contact_key: Option<WrappedRootContactKey>,
    pub root_key_source: RootKeySource,
}

pub struct ContactsCtx {
    user_id: i64,
    http: HttpClient,
    object_store_http: ente_core::http_legacy::ObjectStoreHttpClient,
    master_key: Arc<RwLock<SecretVec>>,
    root_contact_key: Arc<RwLock<Option<SecretVec>>>,
    wrapped_root_contact_key: Arc<RwLock<Option<WrappedRootContactKey>>>,
}

fn wrapped_root_contact_key_from_response(
    remote_root_key: RootKeyResponse,
) -> WrappedRootContactKey {
    WrappedRootContactKey {
        encrypted_key: remote_root_key.encrypted_key,
        header: remote_root_key.header,
    }
}

impl ContactsCtx {
    pub async fn open(input: OpenContactsCtxInput) -> Result<OpenContactsCtxResult> {
        let http = HttpClient::new_with_config(HttpConfig {
            base_url: input.base_url,
            auth_token: Some(input.auth_token),
            user_agent: input.user_agent,
            client_package: input.client_package,
            client_version: input.client_version,
            timeout_secs: Some(30),
        })?;

        let (root_contact_key, wrapped_root_contact_key, root_key_source) =
            if let Some(cached_wrapped_root_contact_key) = input.cached_wrapped_root_contact_key {
                let root_contact_key = contacts_crypto::decrypt_root_contact_key(
                    &cached_wrapped_root_contact_key,
                    &input.master_key,
                )?;
                (
                    Some(SecretVec::new(root_contact_key)),
                    Some(cached_wrapped_root_contact_key),
                    RootKeySource::Cache,
                )
            } else {
                (None, None, RootKeySource::Unresolved)
            };
        let ctx = Self {
            user_id: input.user_id,
            object_store_http: http.object_store(),
            http,
            master_key: Arc::new(RwLock::new(SecretVec::new(input.master_key))),
            root_contact_key: Arc::new(RwLock::new(root_contact_key)),
            wrapped_root_contact_key: Arc::new(RwLock::new(wrapped_root_contact_key.clone())),
        };

        Ok(OpenContactsCtxResult {
            ctx,
            wrapped_root_contact_key,
            root_key_source,
        })
    }

    pub fn user_id(&self) -> i64 {
        self.user_id
    }

    pub fn update_auth_token(&self, auth_token: String) {
        self.http.set_auth_token(Some(auth_token));
    }

    pub fn current_wrapped_root_contact_key(&self) -> Option<WrappedRootContactKey> {
        self.wrapped_root_contact_key
            .read()
            .expect("wrapped root key lock poisoned")
            .clone()
    }

    fn apply_wrapped_root_contact_key(
        &self,
        wrapped_root_contact_key: WrappedRootContactKey,
    ) -> Result<()> {
        let master_key = self.master_key.read().expect("master key lock poisoned");
        let decrypted_root_key =
            contacts_crypto::decrypt_root_contact_key(&wrapped_root_contact_key, &master_key)?;
        *self
            .root_contact_key
            .write()
            .expect("root contact key lock poisoned") = Some(SecretVec::new(decrypted_root_key));
        *self
            .wrapped_root_contact_key
            .write()
            .expect("wrapped root key lock poisoned") = Some(wrapped_root_contact_key);
        Ok(())
    }

    pub async fn create_contact(&self, data: &ContactData) -> Result<ContactRecord> {
        contacts_crypto::validate_contact_data(data)?;
        self.ensure_confirmed_root_contact_key().await?;

        let contact_key = SecretVec::new(crypto::random_bytes(32));
        let wrapped_contact_key = {
            let root_contact_key_guard = self
                .root_contact_key
                .read()
                .expect("root contact key lock poisoned");
            let root_contact_key = root_contact_key_guard.as_ref().ok_or_else(|| {
                ContactsError::InvalidInput("contacts root key is unresolved".into())
            })?;
            contacts_crypto::wrap_contact_key(&contact_key, root_contact_key)?
        };
        let encrypted_data = contacts_crypto::encrypt_contact_data(data, &contact_key)?;
        let response = self
            .http
            .post_json::<ContactEntityResponse, _>(
                "/contacts",
                &CreateContactRequest {
                    contact_user_id: data.contact_user_id,
                    encrypted_key: &wrapped_contact_key,
                    encrypted_data: &encrypted_data,
                },
            )
            .await?;

        self.decode_contact(response)
    }

    pub async fn get_contact(&self, contact_id: &str) -> Result<ContactRecord> {
        let response = self
            .http
            .get_json::<ContactEntityResponse>(&format!("/contacts/{contact_id}"), &[])
            .await?;
        if !response.is_deleted {
            self.ensure_confirmed_root_contact_key().await?;
        }
        self.decode_contact(response)
    }

    pub async fn get_diff(&self, since_time: i64, limit: u16) -> Result<Vec<ContactRecord>> {
        let response = self
            .http
            .get_json::<ContactDiffResponse>(
                "/contacts/diff",
                &[
                    ("sinceTime", since_time.to_string()),
                    ("limit", limit.to_string()),
                ],
            )
            .await?;
        if response.diff.iter().any(|entity| !entity.is_deleted) {
            self.ensure_confirmed_root_contact_key().await?;
        }

        response
            .diff
            .into_iter()
            .map(|entity| self.decode_contact(entity))
            .collect()
    }

    pub async fn update_contact(
        &self,
        contact_id: &str,
        data: &ContactData,
    ) -> Result<ContactRecord> {
        contacts_crypto::validate_contact_data(data)?;
        self.ensure_confirmed_root_contact_key().await?;

        let current = self
            .http
            .get_json::<ContactEntityResponse>(&format!("/contacts/{contact_id}"), &[])
            .await?;
        let encrypted_key = current
            .encrypted_key
            .as_deref()
            .ok_or(ContactsError::MissingEncryptedKey)?;
        let contact_key = {
            let root_contact_key_guard = self
                .root_contact_key
                .read()
                .expect("root contact key lock poisoned");
            let root_contact_key = root_contact_key_guard.as_ref().ok_or_else(|| {
                ContactsError::InvalidInput("contacts root key is unresolved".into())
            })?;
            contacts_crypto::unwrap_contact_key(encrypted_key, root_contact_key)?
        };
        let encrypted_data = contacts_crypto::encrypt_contact_data(data, &contact_key)?;

        let response = self
            .http
            .put_json::<ContactEntityResponse, _>(
                &format!("/contacts/{contact_id}"),
                &UpdateContactRequest {
                    contact_user_id: data.contact_user_id,
                    encrypted_data: &encrypted_data,
                },
            )
            .await?;

        self.decode_contact(response)
    }

    pub async fn delete_contact(&self, contact_id: &str) -> Result<()> {
        self.http
            .delete_empty(&format!("/contacts/{contact_id}"), &[])
            .await?;
        Ok(())
    }

    pub async fn set_attachment(
        &self,
        contact_id: &str,
        attachment_type: AttachmentType,
        attachment_bytes: &[u8],
    ) -> Result<ContactRecord> {
        self.ensure_confirmed_root_contact_key().await?;

        let current = self
            .http
            .get_json::<ContactEntityResponse>(&format!("/contacts/{contact_id}"), &[])
            .await?;
        let encrypted_key = current
            .encrypted_key
            .as_deref()
            .ok_or(ContactsError::MissingEncryptedKey)?;
        let contact_key = {
            let root_contact_key_guard = self
                .root_contact_key
                .read()
                .expect("root contact key lock poisoned");
            let root_contact_key = root_contact_key_guard.as_ref().ok_or_else(|| {
                ContactsError::InvalidInput("contacts root key is unresolved".into())
            })?;
            contacts_crypto::unwrap_contact_key(encrypted_key, root_contact_key)?
        };
        let encrypted_attachment =
            contacts_crypto::encrypt_profile_picture(attachment_bytes, &contact_key)?;
        let content_md5 = contacts_crypto::content_md5_base64(&encrypted_attachment);

        let upload = self
            .http
            .post_json::<AttachmentUploadUrlResponse, _>(
                &format!("/attachments/{}/upload-url", attachment_type.as_str()),
                &AttachmentUploadUrlRequest {
                    content_length: encrypted_attachment.len() as i64,
                    content_md5: content_md5.clone(),
                },
            )
            .await?;

        self.object_store_http
            .put_bytes(
                &upload.url,
                &encrypted_attachment,
                &[("Content-MD5", content_md5)],
            )
            .await?;

        let response = self
            .http
            .put_json::<ContactEntityResponse, _>(
                &format!(
                    "/contacts/{contact_id}/attachments/{}",
                    attachment_type.as_str()
                ),
                &CommitAttachmentRequest {
                    attachment_id: &upload.attachment_id,
                    size: encrypted_attachment.len() as i64,
                },
            )
            .await?;

        self.decode_contact(response)
    }

    pub async fn get_attachment_encrypted(
        &self,
        attachment_type: AttachmentType,
        attachment_id: &str,
    ) -> Result<Vec<u8>> {
        let download = self
            .http
            .get_json::<SignedUrlResponse>(
                &format!("/attachments/{}/{attachment_id}", attachment_type.as_str()),
                &[],
            )
            .await?;
        self.object_store_http
            .get_bytes(&download.url)
            .await
            .map_err(Into::into)
    }

    pub async fn get_profile_picture(&self, contact_id: &str) -> Result<Vec<u8>> {
        let current = self
            .http
            .get_json::<ContactEntityResponse>(&format!("/contacts/{contact_id}"), &[])
            .await?;
        if current.is_deleted || current.profile_picture_attachment_id.is_none() {
            return Err(ContactsError::ProfilePictureNotFound);
        }
        self.ensure_confirmed_root_contact_key().await?;

        let encrypted_key = current
            .encrypted_key
            .as_deref()
            .ok_or(ContactsError::MissingEncryptedKey)?;
        let contact_key = {
            let root_contact_key_guard = self
                .root_contact_key
                .read()
                .expect("root contact key lock poisoned");
            let root_contact_key = root_contact_key_guard.as_ref().ok_or_else(|| {
                ContactsError::InvalidInput("contacts root key is unresolved".into())
            })?;
            contacts_crypto::unwrap_contact_key(encrypted_key, root_contact_key)?
        };
        let encrypted_picture = self
            .get_attachment_encrypted(
                AttachmentType::ProfilePicture,
                current.profile_picture_attachment_id.as_deref().unwrap(),
            )
            .await?;
        contacts_crypto::decrypt_profile_picture(&encrypted_picture, &contact_key)
    }

    pub async fn delete_attachment(
        &self,
        contact_id: &str,
        attachment_type: AttachmentType,
    ) -> Result<ContactRecord> {
        self.ensure_confirmed_root_contact_key().await?;
        let response = self
            .http
            .delete_json::<ContactEntityResponse>(
                &format!(
                    "/contacts/{contact_id}/attachments/{}",
                    attachment_type.as_str()
                ),
                &[],
            )
            .await?;
        self.decode_contact(response)
    }

    pub async fn set_profile_picture(
        &self,
        contact_id: &str,
        profile_picture: &[u8],
    ) -> Result<ContactRecord> {
        self.set_attachment(contact_id, AttachmentType::ProfilePicture, profile_picture)
            .await
    }

    pub async fn delete_profile_picture(&self, contact_id: &str) -> Result<ContactRecord> {
        self.delete_attachment(contact_id, AttachmentType::ProfilePicture)
            .await
    }

    pub async fn legacy_info(&self) -> Result<LegacyInfo> {
        self.http
            .get_json::<LegacyInfoResponse>("/emergency-contacts/info", &[])
            .await
            .map_err(Into::into)
            .map_err(|error| with_http_context("legacy info fetch failed", error))
    }

    pub async fn legacy_public_key(&self, email: &str) -> Result<Option<String>> {
        self.http
            .get_json_optional::<LegacyPublicKeyResponse>(
                "/users/public-key",
                &[("email", email.trim().to_string())],
            )
            .await
            .map(|response| response.map(|result| result.public_key))
            .map_err(Into::into)
            .map_err(|error| with_http_context("legacy public key fetch failed", error))
    }

    pub fn legacy_verification_id(&self, public_key_b64: &str) -> Result<String> {
        let public_key = crypto::decode_b64(public_key_b64)?;
        let digest = Sha256::digest(&public_key);
        auth::recovery_key_to_mnemonic(&crypto::encode_b64(digest.as_slice())).map_err(Into::into)
    }

    pub async fn legacy_add_contact(
        &self,
        email: &str,
        current_user_key_attrs: &KeyAttributes,
        recovery_notice_in_days: Option<i32>,
    ) -> Result<()> {
        let public_key = self
            .legacy_public_key(email)
            .await?
            .ok_or_else(|| ContactsError::InvalidInput("legacy contact is not on Ente".into()))?;
        let recovery_key = self.current_recovery_key(current_user_key_attrs)?;
        let recipient_public_key = crypto::decode_b64(&public_key)?;
        let encrypted_key = sealed::seal(
            &recovery_key,
            &crypto::PublicKey::try_from_slice(&recipient_public_key)?,
        )?;

        self.http
            .post_empty(
                "/emergency-contacts/add",
                &LegacyAddContactRequest {
                    email: email.trim().to_string(),
                    encrypted_key: crypto::encode_b64(&encrypted_key),
                    recovery_notice_in_days,
                },
            )
            .await
            .map_err(Into::into)
            .map_err(|error| with_http_context("legacy contact add failed", error))
    }

    pub async fn legacy_update_contact(
        &self,
        user_id: i64,
        emergency_contact_id: i64,
        state: LegacyContactState,
    ) -> Result<()> {
        self.http
            .post_empty(
                "/emergency-contacts/update",
                &LegacyUpdateContactRequest {
                    user_id,
                    emergency_contact_id,
                    state,
                },
            )
            .await
            .map_err(Into::into)
            .map_err(|error| with_http_context("legacy contact update failed", error))
    }

    pub async fn legacy_update_recovery_notice(
        &self,
        emergency_contact_id: i64,
        recovery_notice_in_days: i32,
    ) -> Result<()> {
        self.http
            .post_empty(
                "/emergency-contacts/update-recovery-notice",
                &LegacyUpdateRecoveryNoticeRequest {
                    emergency_contact_id,
                    recovery_notice_in_days,
                },
            )
            .await
            .map_err(Into::into)
            .map_err(|error| with_http_context("legacy recovery notice update failed", error))
    }

    pub async fn legacy_start_recovery(
        &self,
        user_id: i64,
        emergency_contact_id: i64,
    ) -> Result<()> {
        self.legacy_contact_action(
            "/emergency-contacts/start-recovery",
            user_id,
            emergency_contact_id,
            "legacy recovery start failed",
        )
        .await
    }

    pub async fn legacy_stop_recovery(
        &self,
        recovery_id: &str,
        user_id: i64,
        emergency_contact_id: i64,
    ) -> Result<()> {
        self.legacy_recovery_action(
            "/emergency-contacts/stop-recovery",
            recovery_id,
            user_id,
            emergency_contact_id,
            "legacy recovery stop failed",
        )
        .await
    }

    pub async fn legacy_reject_recovery(
        &self,
        recovery_id: &str,
        user_id: i64,
        emergency_contact_id: i64,
    ) -> Result<()> {
        self.legacy_recovery_action(
            "/emergency-contacts/reject-recovery",
            recovery_id,
            user_id,
            emergency_contact_id,
            "legacy recovery reject failed",
        )
        .await
    }

    pub async fn legacy_approve_recovery(
        &self,
        recovery_id: &str,
        user_id: i64,
        emergency_contact_id: i64,
    ) -> Result<()> {
        self.legacy_recovery_action(
            "/emergency-contacts/approve-recovery",
            recovery_id,
            user_id,
            emergency_contact_id,
            "legacy recovery approve failed",
        )
        .await
    }

    pub async fn legacy_recovery_bundle(
        &self,
        recovery_id: &str,
        current_user_key_attrs: &KeyAttributes,
    ) -> Result<LegacyRecoveryBundle> {
        let response = self
            .legacy_recovery_info(recovery_id)
            .await
            .map_err(|error| with_http_context("legacy recovery info fetch failed", error))?;
        let recovery_key =
            self.decrypt_legacy_recovery_key(&response.encrypted_key, current_user_key_attrs)?;

        Ok(LegacyRecoveryBundle {
            recovery_key,
            user_key_attributes: response.user_key_attr,
        })
    }

    pub async fn legacy_change_password(
        &self,
        recovery_id: &str,
        current_user_key_attrs: &KeyAttributes,
        new_password: &str,
    ) -> Result<()> {
        let bundle = self
            .legacy_recovery_bundle(recovery_id, current_user_key_attrs)
            .await?;
        let target_master_key = decrypt_master_key_with_recovery_key(
            &bundle.user_key_attributes,
            &bundle.recovery_key,
        )?;
        let (updated_key_attrs, login_key) = auth::generate_key_attributes_for_new_password(
            &target_master_key,
            &bundle.user_key_attributes,
            new_password,
        )?;
        let srp_user_id = Uuid::new_v4().to_string();
        let (mut srp_session, setup_request) =
            password_reset_setup_request(&srp_user_id, &login_key)?;
        let init_response = self
            .http
            .post_json::<LegacySetupSrpResponse, _>(
                "/emergency-contacts/init-change-password",
                &LegacyInitChangePasswordRequest {
                    recovery_id: recovery_id.to_string(),
                    setup_srp_request: setup_request,
                },
            )
            .await
            .map_err(Into::into)
            .map_err(|error| with_http_context("legacy password reset init failed", error))?;
        let srp_m1 = srp_session_m1(&mut srp_session, &init_response)?;
        let updated_key_attr = LegacyUpdatedKeyAttr {
            kek_salt: updated_key_attrs.kek_salt.clone(),
            encrypted_key: updated_key_attrs.encrypted_key.clone(),
            key_decryption_nonce: updated_key_attrs.key_decryption_nonce.clone(),
            mem_limit: updated_key_attrs.mem_limit.ok_or_else(|| {
                ContactsError::InvalidInput("updated key attributes missing memLimit".into())
            })?,
            ops_limit: updated_key_attrs.ops_limit.ok_or_else(|| {
                ContactsError::InvalidInput("updated key attributes missing opsLimit".into())
            })?,
        };

        let change_response = self
            .http
            .post_json::<LegacyChangePasswordResponse, _>(
                "/emergency-contacts/change-password",
                &LegacyChangePasswordRequest {
                    recovery_id: recovery_id.to_string(),
                    update_srp_and_keys_request: LegacyUpdateSrpAndKeysRequest {
                        setup_id: init_response.setup_id,
                        srp_m1,
                        updated_key_attr,
                    },
                },
            )
            .await
            .map_err(Into::into)
            .map_err(|error| with_http_context("legacy password reset failed", error))?;

        let server_m2 = crypto::decode_b64(&change_response.srp_m2)?;
        srp_session.verify_m2(&server_m2)?;
        Ok(())
    }

    pub async fn legacy_kits(&self) -> Result<Vec<LegacyKit>> {
        let response = self
            .http
            .get_json::<ListLegacyKitsResponse>("/legacy-kits", &[])
            .await
            .map_err(Into::into)
            .map_err(|error| with_http_context("legacy kit list failed", error))?;
        let master_key = self.master_key.read().expect("master key lock poisoned");
        response
            .kits
            .into_iter()
            .map(|kit| decode_legacy_kit_record(kit, &master_key))
            .collect()
    }

    pub async fn legacy_kit_create(
        &self,
        current_user_key_attrs: &KeyAttributes,
        part_names: [String; 3],
        notice_period_in_hours: i32,
    ) -> Result<LegacyKitCreateResult> {
        let (request, shares) = {
            let recovery_key = self.current_recovery_key(current_user_key_attrs)?;
            let master_key = self.master_key.read().expect("master key lock poisoned");
            create_legacy_kit_request(
                &recovery_key,
                &master_key,
                part_names,
                notice_period_in_hours,
            )?
        };

        let response = self
            .http
            .post_json::<LegacyKitRecordResponse, _>("/legacy-kits", &request)
            .await
            .map_err(Into::into)
            .map_err(|error| with_http_context("legacy kit create failed", error))?;
        let master_key = self.master_key.read().expect("master key lock poisoned");
        let kit = decode_legacy_kit_record(response, &master_key)?;
        Ok(LegacyKitCreateResult { kit, shares })
    }

    pub async fn legacy_kit_download_shares(&self, kit_id: &str) -> Result<Vec<LegacyKitShare>> {
        let response = self
            .http
            .get_json::<LegacyKitDownloadContentResponse>(
                &format!("/legacy-kits/{kit_id}/download-content"),
                &[],
            )
            .await
            .map_err(Into::into)
            .map_err(|error| with_http_context("legacy kit download failed", error))?;
        let master_key = self.master_key.read().expect("master key lock poisoned");
        decode_download_content(response, &master_key)
    }

    pub async fn legacy_kit_recovery_session(
        &self,
        kit_id: &str,
    ) -> Result<LegacyKitOwnerRecoverySession> {
        let response = self
            .http
            .get_json::<LegacyKitOwnerRecoverySessionResponse>(
                &format!("/legacy-kits/{kit_id}/recovery-session"),
                &[],
            )
            .await
            .map_err(Into::into)
            .map_err(|error| {
                with_http_context("legacy kit recovery session fetch failed", error)
            })?;
        Ok(response.into())
    }

    pub async fn legacy_kit_update_recovery_notice(
        &self,
        kit_id: &str,
        notice_period_in_hours: i32,
    ) -> Result<()> {
        validate_notice_period(notice_period_in_hours)?;
        self.http
            .post_empty(
                "/legacy-kits/update-recovery-notice",
                &LegacyKitUpdateRecoveryNoticeRequest {
                    kit_id: kit_id.to_string(),
                    notice_period_in_hours,
                },
            )
            .await
            .map_err(Into::into)
            .map_err(|error| with_http_context("legacy kit recovery notice update failed", error))
    }

    pub async fn legacy_kit_block_recovery(&self, kit_id: &str) -> Result<()> {
        self.http
            .post_empty(
                "/legacy-kits/block-recovery",
                &LegacyKitOwnerActionRequest {
                    kit_id: kit_id.to_string(),
                },
            )
            .await
            .map_err(Into::into)
            .map_err(|error| with_http_context("legacy kit block failed", error))
    }

    pub async fn legacy_kit_delete(&self, kit_id: &str) -> Result<()> {
        self.http
            .delete_empty(&format!("/legacy-kits/{kit_id}"), &[])
            .await
            .map_err(Into::into)
            .map_err(|error| with_http_context("legacy kit delete failed", error))
    }

    fn decode_contact(&self, entity: ContactEntityResponse) -> Result<ContactRecord> {
        if entity.is_deleted {
            return Ok(ContactRecord {
                id: entity.id,
                contact_user_id: entity.contact_user_id,
                email: None,
                name: None,
                birth_date: None,
                profile_picture_attachment_id: None,
                is_deleted: true,
                created_at: entity.created_at,
                updated_at: entity.updated_at,
            });
        }

        let encrypted_key = entity
            .encrypted_key
            .as_deref()
            .ok_or(ContactsError::MissingEncryptedKey)?;
        let encrypted_data = entity
            .encrypted_data
            .as_deref()
            .ok_or(ContactsError::MissingEncryptedData)?;
        let root_contact_key_guard = self
            .root_contact_key
            .read()
            .expect("root contact key lock poisoned");
        let root_contact_key = root_contact_key_guard
            .as_ref()
            .ok_or_else(|| ContactsError::InvalidInput("contacts root key is unresolved".into()))?;
        let contact_key = contacts_crypto::unwrap_contact_key(encrypted_key, root_contact_key)?;
        let data = contacts_crypto::decrypt_contact_data(encrypted_data, &contact_key)?;

        Ok(ContactRecord {
            id: entity.id,
            contact_user_id: entity.contact_user_id,
            email: entity.email,
            name: Some(data.name),
            birth_date: data.birth_date,
            profile_picture_attachment_id: entity.profile_picture_attachment_id,
            is_deleted: false,
            created_at: entity.created_at,
            updated_at: entity.updated_at,
        })
    }

    async fn ensure_confirmed_root_contact_key(&self) -> Result<()> {
        if self
            .root_contact_key
            .read()
            .expect("root contact key lock poisoned")
            .is_some()
        {
            return Ok(());
        }

        if let Some(remote_root_key) = fetch_root_key(&self.http).await? {
            self.apply_wrapped_root_contact_key(wrapped_root_contact_key_from_response(
                remote_root_key,
            ))?;
        } else {
            let generated_root_contact_key = SecretVec::new(crypto::random_bytes(32));
            let generated_wrapped_root_contact_key = {
                let master_key = self.master_key.read().expect("master key lock poisoned");
                contacts_crypto::encrypt_root_contact_key(&generated_root_contact_key, &master_key)?
            };
            if let Some(remote_root_key) =
                create_root_key(&self.http, &generated_wrapped_root_contact_key).await?
            {
                self.apply_wrapped_root_contact_key(wrapped_root_contact_key_from_response(
                    remote_root_key,
                ))?;
            } else {
                self.apply_wrapped_root_contact_key(generated_wrapped_root_contact_key)?;
            }
        }

        Ok(())
    }

    async fn legacy_contact_action(
        &self,
        path: &str,
        user_id: i64,
        emergency_contact_id: i64,
        error_context: &'static str,
    ) -> Result<()> {
        self.http
            .post_empty(
                path,
                &LegacyContactIdentifier {
                    user_id,
                    emergency_contact_id,
                },
            )
            .await
            .map_err(Into::into)
            .map_err(|error| with_http_context(error_context, error))
    }

    async fn legacy_recovery_action(
        &self,
        path: &str,
        recovery_id: &str,
        user_id: i64,
        emergency_contact_id: i64,
        error_context: &'static str,
    ) -> Result<()> {
        self.http
            .post_empty(
                path,
                &LegacyRecoveryIdentifier {
                    id: recovery_id.to_string(),
                    user_id,
                    emergency_contact_id,
                },
            )
            .await
            .map_err(Into::into)
            .map_err(|error| with_http_context(error_context, error))
    }

    async fn legacy_recovery_info(&self, recovery_id: &str) -> Result<LegacyRecoveryInfoResponse> {
        self.http
            .get_json::<LegacyRecoveryInfoResponse>(
                &format!("/emergency-contacts/recovery-info/{recovery_id}"),
                &[],
            )
            .await
            .map_err(Into::into)
    }

    fn current_recovery_key(&self, current_user_key_attrs: &KeyAttributes) -> Result<SecretVec> {
        let master_key = self.master_key.read().expect("master key lock poisoned");
        let recovery_key_hex = auth::get_recovery_key(&master_key, current_user_key_attrs)?;
        Ok(SecretVec::new(crypto::decode_hex(&recovery_key_hex)?))
    }

    fn decrypt_legacy_recovery_key(
        &self,
        encrypted_key_b64: &str,
        current_user_key_attrs: &KeyAttributes,
    ) -> Result<SecretVec> {
        let public_key = crypto::decode_b64(&current_user_key_attrs.public_key)?;
        let encrypted_key = crypto::decode_b64(encrypted_key_b64)?;
        let secret_key = self.current_secret_key(current_user_key_attrs)?;
        let decrypted = sealed::open(
            &encrypted_key,
            &crypto::PublicKey::try_from_slice(&public_key)?,
            &crypto::SecretKey::try_from_slice(&secret_key)?,
        )?;
        Ok(SecretVec::new(decrypted))
    }

    fn current_secret_key(&self, current_user_key_attrs: &KeyAttributes) -> Result<SecretVec> {
        let encrypted_secret_key =
            crypto::decode_b64(&current_user_key_attrs.encrypted_secret_key)?;
        let secret_key_nonce =
            crypto::decode_b64(&current_user_key_attrs.secret_key_decryption_nonce)?;
        let master_key = self.master_key.read().expect("master key lock poisoned");
        let secret_key = secretbox::decrypt(
            &encrypted_secret_key,
            &crypto::Nonce::try_from_slice(&secret_key_nonce)?,
            &crypto::Key::try_from_slice(&master_key)?,
        )?;
        Ok(SecretVec::new(secret_key))
    }
}

async fn fetch_root_key(http: &HttpClient) -> Result<Option<RootKeyResponse>> {
    http.get_json_optional("/user-entity/key", &[("type", CONTACT_TYPE.to_string())])
        .await
        .map_err(Into::into)
        .map_err(|error| with_http_context("contacts root key fetch failed", error))
}

async fn create_root_key(
    http: &HttpClient,
    wrapped_root_contact_key: &WrappedRootContactKey,
) -> Result<Option<RootKeyResponse>> {
    let request = CreateRootKeyRequest {
        r#type: CONTACT_TYPE,
        encrypted_key: &wrapped_root_contact_key.encrypted_key,
        header: &wrapped_root_contact_key.header,
    };

    match http.post_empty("/user-entity/key", &request).await {
        Ok(()) => Ok(None),
        Err(HttpError::Http {
            status,
            code,
            message,
        }) if status == 409 => {
            if let Some(remote_root_key) = fetch_root_key(http).await? {
                Ok(Some(remote_root_key))
            } else {
                Err(with_http_context(
                    "contacts root key create failed",
                    HttpError::Http {
                        status,
                        code,
                        message,
                    }
                    .into(),
                ))
            }
        }
        Err(HttpError::Http {
            status,
            code,
            message,
        }) => Err(with_http_context(
            "contacts root key create failed",
            HttpError::Http {
                status,
                code,
                message,
            }
            .into(),
        )),
        Err(err) => Err(with_http_context(
            "contacts root key create failed",
            err.into(),
        )),
    }
}

fn with_http_context(context: &'static str, error: ContactsError) -> ContactsError {
    match error {
        ContactsError::Http(HttpError::Network(message)) => {
            ContactsError::Http(HttpError::Network(format!("{context}: {message}")))
        }
        ContactsError::Http(HttpError::Http {
            status,
            code,
            message,
        }) => ContactsError::Http(HttpError::Http {
            status,
            code,
            message: format!("{context}: {message}"),
        }),
        ContactsError::Http(HttpError::Parse(message)) => {
            ContactsError::Http(HttpError::Parse(format!("{context}: {message}")))
        }
        ContactsError::Http(HttpError::InvalidUrl(message)) => {
            ContactsError::Http(HttpError::InvalidUrl(format!("{context}: {message}")))
        }
        other => other,
    }
}

fn decrypt_master_key_with_recovery_key(
    key_attributes: &KeyAttributes,
    recovery_key: &[u8],
) -> Result<SecretVec> {
    let encrypted_master_key = key_attributes
        .master_key_encrypted_with_recovery_key
        .as_ref()
        .ok_or_else(|| {
            ContactsError::InvalidInput(
                "target key attributes missing masterKeyEncryptedWithRecoveryKey".into(),
            )
        })?;
    let master_key_nonce = key_attributes
        .master_key_decryption_nonce
        .as_ref()
        .ok_or_else(|| {
            ContactsError::InvalidInput(
                "target key attributes missing masterKeyDecryptionNonce".into(),
            )
        })?;
    let encrypted_master_key = crypto::decode_b64(encrypted_master_key)?;
    let master_key_nonce = crypto::decode_b64(master_key_nonce)?;
    secretbox::decrypt(
        &encrypted_master_key,
        &crypto::Nonce::try_from_slice(&master_key_nonce)?,
        &crypto::Key::try_from_slice(recovery_key)?,
    )
    .map(SecretVec::new)
    .map_err(Into::into)
}

fn password_reset_setup_request(
    srp_user_id: &str,
    login_key: &[u8],
) -> Result<(SrpSession, LegacySetupSrpRequest)> {
    let generated_srp = auth::generate_srp_setup_with_login_key(login_key, srp_user_id)?;
    let srp_session = SrpSession::new(
        srp_user_id,
        &generated_srp.srp_salt,
        &generated_srp.login_sub_key,
    )?;
    let srp_a = crypto::encode_b64(&srp_session.public_a());

    Ok((
        srp_session,
        LegacySetupSrpRequest {
            srp_user_id: srp_user_id.to_string(),
            srp_salt: crypto::encode_b64(&generated_srp.srp_salt),
            srp_verifier: crypto::encode_b64(&generated_srp.srp_verifier),
            srp_a,
        },
    ))
}

fn srp_session_m1(
    srp_session: &mut SrpSession,
    init_response: &LegacySetupSrpResponse,
) -> Result<String> {
    let server_b = crypto::decode_b64(&init_response.srp_b)?;
    let client_m1 = srp_session.compute_m1(&server_b)?;
    Ok(crypto::encode_b64(&client_m1))
}
