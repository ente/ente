//! Space profiles.
//!
//! A Space profile is an encrypted blob (display name, bio, and the like) plus
//! optional avatar and cover assets, all keyed by the Space key for its
//! version. These methods fetch the raw or decrypted profile and update it,
//! re-using the cached owned-Space key via the spine in
//! [`super`](super::AccountSpaceCtx).

use super::{AccountSpaceCtx, decrypt_space_profile};
use crate::crypto::encrypt_secretbox_payload;
use crate::error::{Result, SpaceError};
use crate::models::DecryptedSpaceProfile;
use crate::transport::{
    ProfileAvatarPayload, ProfileCoverPayload, SpaceProfileResponse, UpdateSpaceProfileRequest,
    UpdateSpaceProfileResponse,
};
use ente_core::crypto::encode_b64;

impl AccountSpaceCtx {
    pub async fn get_space_profile_raw(
        &self,
        space_id: &str,
        viewer_space_id: Option<&str>,
        version: Option<i32>,
    ) -> Result<SpaceProfileResponse> {
        let mut query = Vec::new();
        if let Some(value) = viewer_space_id.filter(|value| !value.trim().is_empty()) {
            query.push(("viewerSpaceId", value.to_owned()));
        }
        if let Some(value) = version {
            query.push(("version", value.to_string()));
        }
        let path = format!("/spaces/{space_id}/profile");
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

    pub async fn get_space_profile_decrypted(
        &self,
        space_id: &str,
        viewer_space_id: Option<&str>,
        version: Option<i32>,
    ) -> Result<DecryptedSpaceProfile> {
        let profile = self
            .get_space_profile_raw(space_id, viewer_space_id, version)
            .await?;
        let space_key = self
            .resolve_space_key_for_version_for_viewer(
                space_id,
                viewer_space_id,
                Some(profile.version),
            )
            .await?;
        let Some(space_key) = space_key else {
            return Ok(fallback_space_profile(profile));
        };
        match decrypt_space_profile(&profile, &space_key) {
            Ok(profile) => Ok(profile),
            Err(error) if error.is_unavailable_record() => Ok(fallback_space_profile(profile)),
            Err(error) => Err(error),
        }
    }

    pub async fn update_space_profile(
        &self,
        space_id: &str,
        profile: &[u8],
        avatar: Option<ProfileAvatarPayload>,
        remove_avatar: bool,
    ) -> Result<UpdateSpaceProfileResponse> {
        self.update_space_profile_assets(space_id, profile, avatar, None, remove_avatar, false)
            .await
    }

    pub async fn update_space_profile_assets(
        &self,
        space_id: &str,
        profile: &[u8],
        avatar: Option<ProfileAvatarPayload>,
        cover: Option<ProfileCoverPayload>,
        remove_avatar: bool,
        remove_cover: bool,
    ) -> Result<UpdateSpaceProfileResponse> {
        let space_key = self
            .resolve_owned_space_access(space_id)
            .await?
            .ok_or_else(|| {
                SpaceError::InvalidInput(format!("space {space_id} is not owned by the account"))
            })?;
        let request = UpdateSpaceProfileRequest {
            key_version: space_key.key_version,
            encrypted_profile: encode_b64(&encrypt_secretbox_payload(
                &space_key.space_key,
                profile,
            )?),
            avatar,
            cover,
            remove_avatar,
            remove_cover,
        };
        let path = format!("/spaces/{space_id}/profile");
        let response = self
            .api()
            .post(&path)
            .json(&request)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        self.update_cached_owned_space_profile(space_id, request.encrypted_profile)?;
        Ok(response)
    }
}

fn fallback_space_profile(profile: SpaceProfileResponse) -> DecryptedSpaceProfile {
    DecryptedSpaceProfile {
        space_id: profile.space_id,
        space_slug: profile.space_slug,
        version: profile.version,
        friends: profile.friends,
        profile: Vec::new(),
        avatar: profile.avatar,
        cover: profile.cover,
        updated_at: (!profile.updated_at.is_empty()).then_some(profile.updated_at),
    }
}
