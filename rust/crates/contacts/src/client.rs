use std::sync::{Arc, RwLock};

use ente_accounts::auth::{self, KeyAttributes, SrpSession};
use ente_core::b64;
use ente_core::crypto::{self, SecretVec, sealed, secretbox};
use ente_core::http::{self, Api, ApiConfig, Auth, Http};
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
    api: Api,
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
        let api = Api::new(
            Http::new()?,
            ApiConfig {
                origin: input.base_url,
                client_package: input.client_package,
                client_version: input.client_version,
                user_agent: input.user_agent,
                auth: Some(Auth::User(input.auth_token)),
            },
        );

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
            api,
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
        self.api.set_auth(Some(Auth::User(auth_token)));
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
            .api
            .post("/contacts")
            .json(&CreateContactRequest {
                contact_user_id: data.contact_user_id,
                encrypted_key: &wrapped_contact_key,
                encrypted_data: &encrypted_data,
            })
            .send()
            .await?
            .error_for_status()?
            .json::<ContactEntityResponse>()
            .await?;

        self.decode_contact(response)
    }

    pub async fn get_contact(&self, contact_id: &str) -> Result<ContactRecord> {
        let response = self
            .api
            .get(&format!("/contacts/{contact_id}"))
            .send()
            .await?
            .error_for_status()?
            .json::<ContactEntityResponse>()
            .await?;
        if !response.is_deleted {
            self.ensure_confirmed_root_contact_key().await?;
        }
        self.decode_contact(response)
    }

    pub async fn get_diff(&self, since_time: i64, limit: u16) -> Result<Vec<ContactRecord>> {
        let response = self
            .api
            .get("/contacts/diff")
            .query(&[
                ("sinceTime", since_time.to_string()),
                ("limit", limit.to_string()),
            ])
            .send()
            .await?
            .error_for_status()?
            .json::<ContactDiffResponse>()
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
            .api
            .get(&format!("/contacts/{contact_id}"))
            .send()
            .await?
            .error_for_status()?
            .json::<ContactEntityResponse>()
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
            .api
            .put(&format!("/contacts/{contact_id}"))
            .json(&UpdateContactRequest {
                contact_user_id: data.contact_user_id,
                encrypted_data: &encrypted_data,
            })
            .send()
            .await?
            .error_for_status()?
            .json::<ContactEntityResponse>()
            .await?;

        self.decode_contact(response)
    }

    pub async fn delete_contact(&self, contact_id: &str) -> Result<()> {
        self.api
            .delete(&format!("/contacts/{contact_id}"))
            .send()
            .await?
            .error_for_status()?;
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
            .api
            .get(&format!("/contacts/{contact_id}"))
            .send()
            .await?
            .error_for_status()?
            .json::<ContactEntityResponse>()
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
        let size = encrypted_attachment.len() as i64;

        let upload = self
            .api
            .post(&format!(
                "/attachments/{}/upload-url",
                attachment_type.as_str()
            ))
            .json(&AttachmentUploadUrlRequest {
                content_length: size,
                content_md5: content_md5.clone(),
            })
            .send()
            .await?
            .error_for_status()?
            .json::<AttachmentUploadUrlResponse>()
            .await?;

        self.api
            .http()
            .put(&upload.url)
            .header("Content-MD5", &content_md5)
            .body(encrypted_attachment)
            .send()
            .await?
            .error_for_status()?;

        let response = self
            .api
            .put(&format!(
                "/contacts/{contact_id}/attachments/{}",
                attachment_type.as_str()
            ))
            .json(&CommitAttachmentRequest {
                attachment_id: &upload.attachment_id,
                size,
            })
            .send()
            .await?
            .error_for_status()?
            .json::<ContactEntityResponse>()
            .await?;

        self.decode_contact(response)
    }

    pub async fn get_attachment_encrypted(
        &self,
        attachment_type: AttachmentType,
        attachment_id: &str,
    ) -> Result<Vec<u8>> {
        let download = self
            .api
            .get(&format!(
                "/attachments/{}/{attachment_id}",
                attachment_type.as_str()
            ))
            .send()
            .await?
            .error_for_status()?
            .json::<SignedUrlResponse>()
            .await?;
        Ok(self
            .api
            .http()
            .get(&download.url)
            .send()
            .await?
            .error_for_status()?
            .bytes()
            .await?)
    }

    pub async fn get_profile_picture(&self, contact_id: &str) -> Result<Vec<u8>> {
        let current = self
            .api
            .get(&format!("/contacts/{contact_id}"))
            .send()
            .await?
            .error_for_status()?
            .json::<ContactEntityResponse>()
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
            .api
            .delete(&format!(
                "/contacts/{contact_id}/attachments/{}",
                attachment_type.as_str()
            ))
            .send()
            .await?
            .error_for_status()?
            .json::<ContactEntityResponse>()
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
        Ok(self
            .api
            .get("/emergency-contacts/info")
            .send()
            .await?
            .error_for_status()?
            .json::<LegacyInfoResponse>()
            .await?)
    }

    pub async fn legacy_public_key(&self, email: &str) -> Result<Option<String>> {
        let response = self
            .api
            .get("/users/public-key")
            .query(&[("email", email.trim())])
            .send()
            .await?;
        if response.status() == 404 {
            return Ok(None);
        }
        let response = response
            .error_for_status()?
            .json::<LegacyPublicKeyResponse>()
            .await?;
        Ok(Some(response.public_key))
    }

    pub fn legacy_verification_id(&self, public_key_b64: &str) -> Result<String> {
        let public_key = b64::decode(public_key_b64)?;
        let digest = Sha256::digest(&public_key);
        auth::recovery_key_to_mnemonic(&b64::encode(digest.as_slice())).map_err(Into::into)
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
        let recipient_public_key = b64::decode(&public_key)?;
        let encrypted_key = sealed::seal(
            &recovery_key,
            &crypto::PublicKey::try_from_slice(&recipient_public_key)?,
        )?;

        self.api
            .post("/emergency-contacts/add")
            .json(&LegacyAddContactRequest {
                email: email.trim().to_string(),
                encrypted_key: b64::encode(&encrypted_key),
                recovery_notice_in_days,
            })
            .send()
            .await?
            .error_for_status()?;
        Ok(())
    }

    pub async fn legacy_update_contact(
        &self,
        user_id: i64,
        emergency_contact_id: i64,
        state: LegacyContactState,
    ) -> Result<()> {
        self.api
            .post("/emergency-contacts/update")
            .json(&LegacyUpdateContactRequest {
                user_id,
                emergency_contact_id,
                state,
            })
            .send()
            .await?
            .error_for_status()?;
        Ok(())
    }

    pub async fn legacy_update_recovery_notice(
        &self,
        emergency_contact_id: i64,
        recovery_notice_in_days: i32,
    ) -> Result<()> {
        self.api
            .post("/emergency-contacts/update-recovery-notice")
            .json(&LegacyUpdateRecoveryNoticeRequest {
                emergency_contact_id,
                recovery_notice_in_days,
            })
            .send()
            .await?
            .error_for_status()?;
        Ok(())
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
        )
        .await
    }

    pub async fn legacy_recovery_bundle(
        &self,
        recovery_id: &str,
        current_user_key_attrs: &KeyAttributes,
    ) -> Result<LegacyRecoveryBundle> {
        let response = self.legacy_recovery_info(recovery_id).await?;
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
            .api
            .post("/emergency-contacts/init-change-password")
            .json(&LegacyInitChangePasswordRequest {
                recovery_id: recovery_id.to_string(),
                setup_srp_request: setup_request,
            })
            .send()
            .await?
            .error_for_status()?
            .json::<LegacySetupSrpResponse>()
            .await?;
        let srp_m1 = srp_session_m1(&mut srp_session, &init_response)?;
        let updated_key_attr = LegacyUpdatedKeyAttr {
            kek_salt: updated_key_attrs.kek_salt.clone(),
            encrypted_key: updated_key_attrs.encrypted_key.clone(),
            key_decryption_nonce: updated_key_attrs.key_decryption_nonce.clone(),
            mem_limit: updated_key_attrs.mem_limit,
            ops_limit: updated_key_attrs.ops_limit,
        };

        let change_response = self
            .api
            .post("/emergency-contacts/change-password")
            .json(&LegacyChangePasswordRequest {
                recovery_id: recovery_id.to_string(),
                update_srp_and_keys_request: LegacyUpdateSrpAndKeysRequest {
                    setup_id: init_response.setup_id,
                    srp_m1,
                    updated_key_attr,
                },
            })
            .send()
            .await?
            .error_for_status()?
            .json::<LegacyChangePasswordResponse>()
            .await?;

        let server_m2 = b64::decode(&change_response.srp_m2)?;
        srp_session.verify_m2(&server_m2)?;
        Ok(())
    }

    pub async fn legacy_kits(&self) -> Result<Vec<LegacyKit>> {
        let response = self
            .api
            .get("/legacy-kits")
            .send()
            .await?
            .error_for_status()?
            .json::<ListLegacyKitsResponse>()
            .await?;
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
            .api
            .post("/legacy-kits")
            .json(&request)
            .send()
            .await?
            .error_for_status()?
            .json::<LegacyKitRecordResponse>()
            .await?;
        let master_key = self.master_key.read().expect("master key lock poisoned");
        let kit = decode_legacy_kit_record(response, &master_key)?;
        Ok(LegacyKitCreateResult { kit, shares })
    }

    pub async fn legacy_kit_download_shares(&self, kit_id: &str) -> Result<Vec<LegacyKitShare>> {
        let response = self
            .api
            .get(&format!("/legacy-kits/{kit_id}/download-content"))
            .send()
            .await?
            .error_for_status()?
            .json::<LegacyKitDownloadContentResponse>()
            .await?;
        let master_key = self.master_key.read().expect("master key lock poisoned");
        decode_download_content(response, &master_key)
    }

    pub async fn legacy_kit_recovery_session(
        &self,
        kit_id: &str,
    ) -> Result<LegacyKitOwnerRecoverySession> {
        let response = self
            .api
            .get(&format!("/legacy-kits/{kit_id}/recovery-session"))
            .send()
            .await?
            .error_for_status()?
            .json::<LegacyKitOwnerRecoverySessionResponse>()
            .await?;
        Ok(response.into())
    }

    pub async fn legacy_kit_update_recovery_notice(
        &self,
        kit_id: &str,
        notice_period_in_hours: i32,
    ) -> Result<()> {
        validate_notice_period(notice_period_in_hours)?;
        let path = "/legacy-kits/update-recovery-notice";
        let response = self
            .api
            .post(path)
            .json(&LegacyKitUpdateRecoveryNoticeRequest {
                kit_id: kit_id.to_string(),
                notice_period_in_hours,
            })
            .send()
            .await?;
        if response.status() == 400 {
            return if response.text().await?.contains("active recovery session") {
                Err(ContactsError::ActiveRecoverySession)
            } else {
                Err(http::Error::Http {
                    status: 400,
                    path: path.into(),
                }
                .into())
            };
        }
        response.error_for_status()?;
        Ok(())
    }

    pub async fn legacy_kit_block_recovery(&self, kit_id: &str) -> Result<()> {
        self.api
            .post("/legacy-kits/block-recovery")
            .json(&LegacyKitOwnerActionRequest {
                kit_id: kit_id.to_string(),
            })
            .send()
            .await?
            .error_for_status()?;
        Ok(())
    }

    pub async fn legacy_kit_delete(&self, kit_id: &str) -> Result<()> {
        self.api
            .delete(&format!("/legacy-kits/{kit_id}"))
            .send()
            .await?
            .error_for_status()?;
        Ok(())
    }

    fn decode_contact(&self, entity: ContactEntityResponse) -> Result<ContactRecord> {
        if entity.is_deleted {
            return Ok(ContactRecord {
                id: entity.id,
                contact_user_id: entity.contact_user_id,
                email: None,
                name: None,
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

        if let Some(remote_root_key) = fetch_root_key(&self.api).await? {
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
                create_root_key(&self.api, &generated_wrapped_root_contact_key).await?
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
    ) -> Result<()> {
        self.api
            .post(path)
            .json(&LegacyContactIdentifier {
                user_id,
                emergency_contact_id,
            })
            .send()
            .await?
            .error_for_status()?;
        Ok(())
    }

    async fn legacy_recovery_action(
        &self,
        path: &str,
        recovery_id: &str,
        user_id: i64,
        emergency_contact_id: i64,
    ) -> Result<()> {
        self.api
            .post(path)
            .json(&LegacyRecoveryIdentifier {
                id: recovery_id.to_string(),
                user_id,
                emergency_contact_id,
            })
            .send()
            .await?
            .error_for_status()?;
        Ok(())
    }

    async fn legacy_recovery_info(&self, recovery_id: &str) -> Result<LegacyRecoveryInfoResponse> {
        Ok(self
            .api
            .get(&format!("/emergency-contacts/recovery-info/{recovery_id}"))
            .send()
            .await?
            .error_for_status()?
            .json::<LegacyRecoveryInfoResponse>()
            .await?)
    }

    fn current_recovery_key(&self, current_user_key_attrs: &KeyAttributes) -> Result<SecretVec> {
        let master_key = self.master_key.read().expect("master key lock poisoned");
        let recovery_key_hex = auth::get_recovery_key(&master_key, current_user_key_attrs)?;
        Ok(auth::recovery_key_from_mnemonic_or_hex(&recovery_key_hex)?)
    }

    fn decrypt_legacy_recovery_key(
        &self,
        encrypted_key_b64: &str,
        current_user_key_attrs: &KeyAttributes,
    ) -> Result<SecretVec> {
        let public_key = b64::decode(&current_user_key_attrs.public_key)?;
        let encrypted_key = b64::decode(encrypted_key_b64)?;
        let secret_key = self.current_secret_key(current_user_key_attrs)?;
        let decrypted = sealed::open(
            &encrypted_key,
            &crypto::PublicKey::try_from_slice(&public_key)?,
            &crypto::SecretKey::try_from_slice(&secret_key)?,
        )?;
        Ok(SecretVec::new(decrypted))
    }

    fn current_secret_key(&self, current_user_key_attrs: &KeyAttributes) -> Result<SecretVec> {
        let encrypted_secret_key = b64::decode(&current_user_key_attrs.encrypted_secret_key)?;
        let secret_key_nonce = b64::decode(&current_user_key_attrs.secret_key_decryption_nonce)?;
        let master_key = self.master_key.read().expect("master key lock poisoned");
        let secret_key = secretbox::decrypt(
            &encrypted_secret_key,
            &crypto::Nonce::try_from_slice(&secret_key_nonce)?,
            &crypto::Key::try_from_slice(&master_key)?,
        )?;
        Ok(SecretVec::new(secret_key))
    }
}

async fn fetch_root_key(api: &Api) -> Result<Option<RootKeyResponse>> {
    let response = api
        .get("/user-entity/key")
        .query(&[("type", CONTACT_TYPE)])
        .send()
        .await?;
    if response.status() == 404 {
        return Ok(None);
    }
    Ok(Some(response.error_for_status()?.json().await?))
}

async fn create_root_key(
    api: &Api,
    wrapped_root_contact_key: &WrappedRootContactKey,
) -> Result<Option<RootKeyResponse>> {
    let request = CreateRootKeyRequest {
        r#type: CONTACT_TYPE,
        encrypted_key: &wrapped_root_contact_key.encrypted_key,
        header: &wrapped_root_contact_key.header,
    };

    let response = api.post("/user-entity/key").json(&request).send().await?;
    if response.status() == 409
        && let Some(remote_root_key) = fetch_root_key(api).await?
    {
        return Ok(Some(remote_root_key));
    }
    response.error_for_status()?;
    Ok(None)
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
    let encrypted_master_key = b64::decode(encrypted_master_key)?;
    let master_key_nonce = b64::decode(master_key_nonce)?;
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
    let srp_a = b64::encode(&srp_session.public_a());

    Ok((
        srp_session,
        LegacySetupSrpRequest {
            srp_user_id: srp_user_id.to_string(),
            srp_salt: b64::encode(&generated_srp.srp_salt),
            srp_verifier: b64::encode(&generated_srp.srp_verifier),
            srp_a,
        },
    ))
}

fn srp_session_m1(
    srp_session: &mut SrpSession,
    init_response: &LegacySetupSrpResponse,
) -> Result<String> {
    let server_b = b64::decode(&init_response.srp_b)?;
    let client_m1 = srp_session.compute_m1(&server_b)?;
    Ok(b64::encode(&client_m1))
}
