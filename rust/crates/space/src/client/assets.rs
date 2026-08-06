//! Space asset upload and download.
//!
//! Posts and profiles store their media in an object store fronted by presigned
//! URLs. These methods presign an upload, push the encrypted bytes, and fetch
//! and decrypt them back. Post assets are keyed by a per-post key; profile
//! avatar/cover assets by the Space key. Photo bytes are validated before
//! upload (posts are photo-only).

use super::{
    AccountSpaceCtx, PostPhotoAssetOptions, UPLOAD_PURPOSE_AVATAR, UPLOAD_PURPOSE_COVER,
    encrypt_post_object_metadata, ensure_space_upload_size, ensure_supported_photo_bytes,
    ensure_supported_photo_media_type, profile_object_id_from_key,
};
use crate::crypto::{content_md5_base64, encrypt_asset_payload};
use crate::error::{Result, SpaceError};
use crate::models::PostObjectMetadata;
use crate::transport::{
    AssetDownloadResponse, PostObjectPayload, PresignUploadRequest, PresignUploadResponse,
    ProfileAvatarPayload, ProfileCoverPayload,
};
use crate::{
    MAX_SPACE_AVATAR_UPLOAD_BYTES, MAX_SPACE_COVER_UPLOAD_BYTES, MAX_SPACE_POST_UPLOAD_BYTES,
};

impl AccountSpaceCtx {
    pub async fn presign_post_upload(
        &self,
        space_id: &str,
        size: usize,
        content_md5: &str,
    ) -> Result<PresignUploadResponse> {
        ensure_space_upload_size("post", size, MAX_SPACE_POST_UPLOAD_BYTES)?;
        let request = PresignUploadRequest {
            size: size as i64,
            content_md5: content_md5.to_owned(),
            purpose: None,
        };
        let path = format!("/spaces/{space_id}/uploads/presign");
        Ok(self
            .api()
            .post(&path)
            .json(&request)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?)
    }

    pub async fn presign_avatar_upload(
        &self,
        space_id: &str,
        size: usize,
        content_md5: &str,
    ) -> Result<PresignUploadResponse> {
        ensure_space_upload_size("avatar", size, MAX_SPACE_AVATAR_UPLOAD_BYTES)?;
        let request = PresignUploadRequest {
            size: size as i64,
            content_md5: content_md5.to_owned(),
            purpose: Some(UPLOAD_PURPOSE_AVATAR.to_owned()),
        };
        let path = format!("/spaces/{space_id}/uploads/presign");
        Ok(self
            .api()
            .post(&path)
            .json(&request)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?)
    }

    pub async fn presign_cover_upload(
        &self,
        space_id: &str,
        size: usize,
        content_md5: &str,
    ) -> Result<PresignUploadResponse> {
        ensure_space_upload_size("cover", size, MAX_SPACE_COVER_UPLOAD_BYTES)?;
        let request = PresignUploadRequest {
            size: size as i64,
            content_md5: content_md5.to_owned(),
            purpose: Some(UPLOAD_PURPOSE_COVER.to_owned()),
        };
        let path = format!("/spaces/{space_id}/uploads/presign");
        Ok(self
            .api()
            .post(&path)
            .json(&request)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?)
    }

    pub async fn upload_bytes(&self, presign: &PresignUploadResponse, body: &[u8]) -> Result<()> {
        let request = presign.headers.iter().fold(
            self.api().http().put(&presign.url),
            |request, (name, value)| request.header(name, value),
        );
        request
            .body(body.to_vec())
            .send()
            .await?
            .error_for_status()?;
        Ok(())
    }

    pub async fn upload_post_asset(
        &self,
        space_id: &str,
        post_key: &[u8],
        plaintext: &[u8],
        position: Option<i32>,
    ) -> Result<PostObjectPayload> {
        let encrypted = encrypt_asset_payload(post_key, plaintext)?;
        let content_md5 = content_md5_base64(&encrypted);
        let presign = self
            .presign_post_upload(space_id, encrypted.len(), &content_md5)
            .await?;
        self.upload_bytes(&presign, &encrypted).await?;
        Ok(PostObjectPayload {
            object_key: presign.object_key,
            size: Some(encrypted.len() as i64),
            position,
            metadata_cipher: None,
        })
    }

    pub async fn upload_post_photo_asset(
        &self,
        space_id: &str,
        post_key: &[u8],
        plaintext: &[u8],
        options: PostPhotoAssetOptions,
    ) -> Result<PostObjectPayload> {
        let inferred_media_type = ensure_supported_photo_bytes(plaintext)?;
        let media_type = ensure_supported_photo_media_type(options.media_type.as_deref())?
            .unwrap_or_else(|| inferred_media_type.to_owned());
        let mut object = self
            .upload_post_asset(space_id, post_key, plaintext, Some(0))
            .await?;
        object.metadata_cipher = Some(encrypt_post_object_metadata(
            post_key,
            &PostObjectMetadata {
                width: options.width.filter(|value| *value > 0),
                height: options.height.filter(|value| *value > 0),
                media_type: Some(media_type),
                thumb_hash: options.thumb_hash,
                ..Default::default()
            },
        )?);
        Ok(object)
    }

    pub async fn upload_avatar(
        &self,
        space_id: &str,
        space_key: &[u8],
        plaintext: &[u8],
    ) -> Result<ProfileAvatarPayload> {
        self.upload_profile_asset(space_id, space_key, plaintext, UPLOAD_PURPOSE_AVATAR)
            .await
    }

    pub async fn upload_cover(
        &self,
        space_id: &str,
        space_key: &[u8],
        plaintext: &[u8],
    ) -> Result<ProfileCoverPayload> {
        self.upload_profile_asset(space_id, space_key, plaintext, UPLOAD_PURPOSE_COVER)
            .await
    }

    async fn upload_profile_asset(
        &self,
        space_id: &str,
        space_key: &[u8],
        plaintext: &[u8],
        purpose: &str,
    ) -> Result<ProfileAvatarPayload> {
        ensure_supported_photo_bytes(plaintext)?;
        let encrypted = encrypt_asset_payload(space_key, plaintext)?;
        let content_md5 = content_md5_base64(&encrypted);
        let presign = match purpose {
            UPLOAD_PURPOSE_AVATAR => {
                self.presign_avatar_upload(space_id, encrypted.len(), &content_md5)
                    .await?
            }
            UPLOAD_PURPOSE_COVER => {
                self.presign_cover_upload(space_id, encrypted.len(), &content_md5)
                    .await?
            }
            _ => {
                return Err(SpaceError::InvalidInput(
                    "invalid profile asset purpose".into(),
                ));
            }
        };
        self.upload_bytes(&presign, &encrypted).await?;
        Ok(ProfileAvatarPayload {
            object_id: profile_object_id_from_key(&presign.object_key)?,
            size: Some(encrypted.len() as i64),
        })
    }

    pub async fn get_profile_asset_url(
        &self,
        space_id: &str,
        viewer_space_id: Option<&str>,
        asset_type: &str,
        object_id: &str,
    ) -> Result<AssetDownloadResponse> {
        let mut query = vec![
            ("assetType", asset_type.to_owned()),
            ("objectID", object_id.to_owned()),
        ];
        if let Some(value) = viewer_space_id.filter(|value| !value.trim().is_empty()) {
            query.push(("viewerSpaceId", value.to_owned()));
        }
        let path = format!("/spaces/{space_id}/assets/redirect");
        Ok(self
            .api()
            .get(&path)
            .query(&query)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?)
    }

    pub async fn download_profile_asset(
        &self,
        space_id: &str,
        viewer_space_id: Option<&str>,
        asset_type: &str,
        object_id: &str,
        key_version: i32,
    ) -> Result<Vec<u8>> {
        let space_key = self
            .resolve_space_key_for_version_for_viewer(space_id, viewer_space_id, Some(key_version))
            .await?
            .ok_or_else(|| {
                SpaceError::InvalidInput(format!(
                    "no space key available for {space_id} version {key_version}"
                ))
            })?;
        let download = self
            .get_profile_asset_url(space_id, viewer_space_id, asset_type, object_id)
            .await?;
        let encrypted = self
            .api()
            .http()
            .get(&download.url)
            .send()
            .await?
            .error_for_status()?
            .bytes()
            .await?;
        crate::crypto::decrypt_asset_payload(&space_key, &encrypted)
    }

    pub async fn get_asset_url(
        &self,
        space_id: &str,
        viewer_space_id: Option<&str>,
        object_key: &str,
    ) -> Result<AssetDownloadResponse> {
        let mut query = vec![("objectKey", object_key.to_owned())];
        if let Some(value) = viewer_space_id.filter(|value| !value.trim().is_empty()) {
            query.push(("viewerSpaceId", value.to_owned()));
        }
        let path = format!("/spaces/{space_id}/assets/redirect");
        Ok(self
            .api()
            .get(&path)
            .query(&query)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?)
    }

    pub async fn download_encrypted_asset(
        &self,
        space_id: &str,
        viewer_space_id: Option<&str>,
        object_key: &str,
    ) -> Result<Vec<u8>> {
        let download = self
            .get_asset_url(space_id, viewer_space_id, object_key)
            .await?;
        Ok(self
            .api()
            .http()
            .get(&download.url)
            .send()
            .await?
            .error_for_status()?
            .bytes()
            .await?)
    }

    pub async fn download_decrypted_asset(
        &self,
        space_id: &str,
        viewer_space_id: Option<&str>,
        object_key: &str,
        key: &[u8],
    ) -> Result<Vec<u8>> {
        let encrypted = self
            .download_encrypted_asset(space_id, viewer_space_id, object_key)
            .await?;
        crate::crypto::decrypt_asset_payload(key, &encrypted)
    }
}
