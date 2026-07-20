//! Space key versions and rotation.
//!
//! Each Space key has a version; older posts and profiles stay readable by
//! walking the wrapped key chain back from the current version. These methods
//! list versions, reconstruct the version-to-key history, and rotate the Space
//! key (re-wrapping the profile and previous key under the new one). The private
//! key-resolution spine lives in [`super`](super::AccountSpaceCtx).

use std::collections::BTreeMap;

use super::{AccountSpaceCtx, build_space_key_history_map};
use crate::crypto::{encrypt_secretbox_payload, generate_key};
use crate::error::{Result, SpaceError};
use crate::models::CreatedSpace;
use crate::transport::{RotateSpaceKeyRequest, SpaceKeyResponse, SpaceKeyVersionResponse};
use ente_core::crypto::encode_b64;

impl AccountSpaceCtx {
    pub async fn list_space_key_versions(
        &self,
        space_id: &str,
        viewer_space_id: Option<&str>,
    ) -> Result<Vec<SpaceKeyVersionResponse>> {
        let mut query = Vec::new();
        if let Some(value) = viewer_space_id.filter(|value| !value.trim().is_empty()) {
            query.push(("viewerSpaceId", value.to_owned()));
        }
        let path = format!("/spaces/{space_id}/versions");
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

    pub fn build_space_key_history(
        &self,
        current_version: i32,
        current_key: &[u8],
        versions: &[SpaceKeyVersionResponse],
    ) -> Result<BTreeMap<i32, Vec<u8>>> {
        build_space_key_history_map(current_version, current_key, versions)
    }

    pub async fn build_space_key_history_for_space(
        &self,
        space_id: &str,
    ) -> Result<BTreeMap<i32, Vec<u8>>> {
        let access = self
            .resolve_space_access(space_id)
            .await?
            .ok_or_else(|| SpaceError::InvalidInput(format!("no access to space {space_id}")))?;
        let versions = self.list_space_key_versions(space_id, None).await?;
        build_space_key_history_map(access.key_version, &access.space_key, &versions)
    }

    pub async fn build_space_key_history_for_space_for_viewer(
        &self,
        space_id: &str,
        viewer_space_id: Option<&str>,
    ) -> Result<BTreeMap<i32, Vec<u8>>> {
        let access = match viewer_space_id.filter(|value| !value.trim().is_empty()) {
            Some(viewer_space_id) => {
                self.resolve_space_access_for(viewer_space_id, space_id)
                    .await?
            }
            None => self.resolve_space_access(space_id).await?,
        }
        .ok_or_else(|| SpaceError::InvalidInput(format!("no access to space {space_id}")))?;
        let versions = self
            .list_space_key_versions(space_id, viewer_space_id)
            .await?;
        build_space_key_history_map(access.key_version, &access.space_key, &versions)
    }

    pub async fn rotate_space_key(
        &self,
        space_id: &str,
        profile: Option<&[u8]>,
    ) -> Result<CreatedSpace> {
        let current = self
            .resolve_owned_space_access(space_id)
            .await?
            .ok_or_else(|| {
                SpaceError::InvalidInput(format!("space {space_id} is not owned by the account"))
            })?;
        let current_profile = if profile.is_none() {
            Some(
                self.get_space_profile_decrypted(space_id, None, None)
                    .await?,
            )
        } else {
            None
        };
        let next_profile = match profile {
            Some(value) => value.to_vec(),
            None => current_profile
                .as_ref()
                .map(|value| value.profile.clone())
                .ok_or_else(|| SpaceError::InvalidInput("missing current profile".into()))?,
        };
        let next_space_key = generate_key();
        let space_root_key = self.get_or_create_space_root_key().await?;
        let request = RotateSpaceKeyRequest {
            key_version: current.key_version,
            root_wrapped_space_key: encode_b64(&encrypt_secretbox_payload(
                &space_root_key,
                &next_space_key,
            )?),
            wrapped_prev_key: encode_b64(&encrypt_secretbox_payload(
                &next_space_key,
                &current.space_key,
            )?),
            encrypted_profile: encode_b64(&encrypt_secretbox_payload(
                &next_space_key,
                &next_profile,
            )?),
        };
        let path = format!("/spaces/{space_id}/rotate");
        let response = self
            .api()
            .post(&path)
            .json(&request)
            .send()
            .await?
            .error_for_status()?
            .json::<SpaceKeyResponse>()
            .await?;
        self.clear_owned_space_cache()?;
        Ok(CreatedSpace {
            space_id: response.space_id,
            space_slug: response.space_slug,
            key_version: response.key_version,
            space_key: next_space_key,
            root_wrapped_space_key: request.root_wrapped_space_key,
            encrypted_profile: request.encrypted_profile,
        })
    }
}
