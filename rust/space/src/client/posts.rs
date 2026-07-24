//! Space posts and feed.
//!
//! Posts carry a per-post key (wrapped to the Space key) plus an encrypted
//! caption and photo objects. These methods create and list posts, page the
//! cross-Space feed, decrypt post keys/captions/objects, and handle likes,
//! notifications, and post asset downloads. Key resolution and caching are
//! delegated to the spine in [`super`](super::AccountSpaceCtx).

use super::{
    AccountSpaceCtx, decrypt_post_object_metadata, ensure_post_objects_are_photos,
    post_response_from_feed_item,
};
use crate::crypto::{decrypt_secretbox_payload, encrypt_secretbox_payload, generate_key};
use crate::error::{Result, SpaceError};
use crate::models::{DecryptedPost, FeedItem, FeedPage, HydratedKeys, PostObjectMetadata};
use crate::transport::{
    CreatePostRequest, CreatePostResponse, LikePostResponse, PostObjectPayload, PostPage,
    PostResponse, SpaceActorResponse, SpaceUnreadStatusResponse, UpdatePostCaptionRequest,
};
use ente_core::crypto::{decode_b64, encode_b64};

impl AccountSpaceCtx {
    pub fn generate_post_key(&self) -> Vec<u8> {
        generate_key()
    }

    pub async fn create_post(
        &self,
        space_id: &str,
        objects: &[PostObjectPayload],
        caption_plaintext: Option<&[u8]>,
        post_key: Option<&[u8]>,
    ) -> Result<(i64, Vec<u8>)> {
        let post_key_bytes = post_key.map_or_else(generate_key, ToOwned::to_owned);
        ensure_post_objects_are_photos(objects, &post_key_bytes)?;
        let access = self
            .resolve_owned_space_access(space_id)
            .await?
            .ok_or_else(|| {
                SpaceError::InvalidInput(format!("space {space_id} is not owned by the account"))
            })?;
        let caption_cipher = match caption_plaintext {
            Some(value) => Some(encode_b64(&encrypt_secretbox_payload(
                &post_key_bytes,
                value,
            )?)),
            None => None,
        };
        let request = CreatePostRequest {
            encrypted_post_key: encode_b64(&encrypt_secretbox_payload(
                &access.space_key,
                &post_key_bytes,
            )?),
            key_version: access.key_version,
            caption_cipher,
            objects: objects.to_vec(),
        };
        let path = format!("/spaces/{space_id}/posts");
        let response = self
            .api()
            .post(&path)
            .json(&request)
            .send()
            .await?
            .error_for_status()?
            .json::<CreatePostResponse>()
            .await?;
        Ok((response.post_id, post_key_bytes))
    }

    pub async fn list_posts(
        &self,
        space_id: &str,
        viewer_space_id: Option<&str>,
        cursor: Option<String>,
        limit: Option<i32>,
    ) -> Result<PostPage> {
        let mut query = Vec::new();
        if let Some(value) = viewer_space_id.filter(|value| !value.trim().is_empty()) {
            query.push(("viewerSpaceId", value.to_owned()));
        }
        if let Some(value) = cursor.filter(|value| !value.trim().is_empty()) {
            query.push(("cursor", value));
        }
        if let Some(value) = limit {
            query.push(("limit", value.to_string()));
        }
        let path = format!("/spaces/{space_id}/posts");
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

    pub async fn list_feed(
        &self,
        space_id: &str,
        cursor: Option<String>,
        limit: Option<i32>,
    ) -> Result<FeedPage> {
        let mut query = Vec::new();
        if let Some(value) = cursor.filter(|value| !value.trim().is_empty()) {
            query.push(("cursor", value));
        }
        if let Some(value) = limit {
            query.push(("limit", value.to_string()));
        }
        let path = format!("/spaces/{space_id}/feed");
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

    pub async fn unread_status(&self, space_id: &str) -> Result<SpaceUnreadStatusResponse> {
        let path = format!("/spaces/{space_id}/unread");
        Ok(self
            .api()
            .get(&path)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?)
    }

    pub async fn mark_notifications_read(
        &self,
        space_id: impl Into<String>,
        friend_space_id: impl Into<String>,
    ) -> Result<SpaceUnreadStatusResponse> {
        let space_id = space_id.into();
        let friend_space_id = friend_space_id.into();
        if space_id.trim().is_empty() {
            return Err(SpaceError::InvalidInput("space id is required".into()));
        }
        if friend_space_id.trim().is_empty() {
            return Err(SpaceError::InvalidInput(
                "friend space id is required".into(),
            ));
        }
        let path = format!("/spaces/{space_id}/friends/{friend_space_id}/read");
        Ok(self
            .api()
            .post(&path)
            .json(&serde_json::json!({}))
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?)
    }

    pub async fn get_post(
        &self,
        space_id: &str,
        post_id: i64,
        viewer_space_id: Option<&str>,
    ) -> Result<PostResponse> {
        let path = format!("/spaces/{space_id}/posts/{post_id}");
        let mut query = Vec::new();
        if let Some(value) = viewer_space_id.filter(|value| !value.trim().is_empty()) {
            query.push(("viewerSpaceId", value.to_owned()));
        }
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

    pub async fn fetch_post_decrypted(
        &self,
        space_id: &str,
        post_id: i64,
        viewer_space_id: Option<&str>,
    ) -> Result<DecryptedPost> {
        let post = self.get_post(space_id, post_id, viewer_space_id).await?;
        self.decrypt_post_for_viewer(&post.space_id, viewer_space_id, &post)
            .await
    }

    pub async fn download_post_asset(
        &self,
        space_id: &str,
        post_id: i64,
        viewer_space_id: Option<&str>,
        object_key: &str,
    ) -> Result<Vec<u8>> {
        let post = self.get_post(space_id, post_id, viewer_space_id).await?;
        let decrypted = self
            .decrypt_post_for_viewer(&post.space_id, viewer_space_id, &post)
            .await?;
        self.download_decrypted_asset(
            &post.space_id,
            viewer_space_id,
            object_key,
            &decrypted.post_key,
        )
        .await
    }

    pub async fn download_post_asset_with_key(
        &self,
        space_id: &str,
        encrypted_post_key: &str,
        key_version: i32,
        viewer_space_id: Option<&str>,
        object_key: &str,
    ) -> Result<Vec<u8>> {
        let post_key = self
            .decrypt_post_key_fields(space_id, viewer_space_id, encrypted_post_key, key_version)
            .await?;
        self.download_decrypted_asset(space_id, viewer_space_id, object_key, &post_key)
            .await
    }

    pub async fn hydrate_space_keys(&self) -> Result<HydratedKeys> {
        let space_root_key = self.get_space_root_key().await?;
        let owned_records = self.list_owned_spaces().await?;
        let mut owned = Vec::with_capacity(owned_records.len());
        if let Some(space_root_key) = space_root_key {
            for record in owned_records {
                let packed = decode_b64(&record.root_wrapped_space_key)?;
                let space_key = decrypt_secretbox_payload(&space_root_key, &packed)?;
                owned.push((record.space_id, space_key));
            }
        }

        let mut friends = Vec::new();
        for (space_id, _) in &owned {
            let friends_records = self.list_friend_shares(space_id).await?;
            for record in &friends_records {
                match self.decrypt_friend_share(space_id, record).await {
                    Ok(share) => friends.push(share),
                    Err(error) if error.is_unavailable_record() => {}
                    Err(error) => return Err(error),
                }
            }
        }

        Ok(HydratedKeys { owned, friends })
    }

    pub fn decrypt_post_key(&self, space_key: &[u8], post: &PostResponse) -> Result<Vec<u8>> {
        let packed = decode_b64(&post.encrypted_post_key)?;
        decrypt_secretbox_payload(space_key, &packed)
    }

    pub async fn decrypt_post_key_fields(
        &self,
        space_id: &str,
        viewer_space_id: Option<&str>,
        encrypted_post_key: &str,
        key_version: i32,
    ) -> Result<Vec<u8>> {
        let space_key = self
            .resolve_space_key_for_version_for_viewer(space_id, viewer_space_id, Some(key_version))
            .await?
            .ok_or_else(|| SpaceError::InvalidInput("missing space key for post".into()))?;
        let packed = decode_b64(encrypted_post_key)?;
        decrypt_secretbox_payload(&space_key, &packed)
    }

    pub fn decrypt_post(&self, space_key: &[u8], post: &PostResponse) -> Result<DecryptedPost> {
        let post_key = self.decrypt_post_key(space_key, post)?;
        let caption_plaintext = if post.caption_cipher.is_empty() {
            None
        } else {
            let packed = decode_b64(&post.caption_cipher)?;
            Some(decrypt_secretbox_payload(&post_key, &packed)?)
        };
        Ok(DecryptedPost {
            post_key,
            caption_plaintext,
        })
    }

    pub fn decrypt_post_object_metadata(
        &self,
        post_key: &[u8],
        object: &PostObjectPayload,
    ) -> Result<Option<PostObjectMetadata>> {
        decrypt_post_object_metadata(post_key, object)
    }

    pub async fn decrypt_post_for_space(
        &self,
        space_id: &str,
        post: &PostResponse,
    ) -> Result<DecryptedPost> {
        self.decrypt_post_for_viewer(space_id, None, post).await
    }

    pub async fn decrypt_post_for_viewer(
        &self,
        space_id: &str,
        viewer_space_id: Option<&str>,
        post: &PostResponse,
    ) -> Result<DecryptedPost> {
        let space_key = self
            .resolve_space_key_for_version_for_viewer(
                space_id,
                viewer_space_id,
                Some(post.key_version),
            )
            .await?
            .ok_or_else(|| {
                SpaceError::InvalidInput(format!(
                    "no space key available for post {}",
                    post.post_id
                ))
            })?;
        self.decrypt_post(&space_key, post)
    }

    pub async fn decrypt_actor_profile(
        &self,
        actor: &SpaceActorResponse,
    ) -> Result<Option<Vec<u8>>> {
        if actor.encrypted_profile.trim().is_empty()
            || actor.space_id.trim().is_empty()
            || actor.key_version <= 0
        {
            return Ok(None);
        }
        let Some(space_key) = self
            .resolve_space_key_for_version(&actor.space_id, Some(actor.key_version))
            .await?
        else {
            return Ok(None);
        };
        Ok(Some(decrypt_secretbox_payload(
            &space_key,
            &decode_b64(&actor.encrypted_profile)?,
        )?))
    }

    pub async fn decrypt_feed_item(&self, item: &FeedItem) -> Result<DecryptedPost> {
        let post = post_response_from_feed_item(item);
        self.decrypt_post_for_space(&item.space_id, &post).await
    }

    pub async fn update_post_caption(
        &self,
        space_id: &str,
        post_id: i64,
        post_key: &[u8],
        caption_plaintext: Option<&[u8]>,
    ) -> Result<()> {
        let request = UpdatePostCaptionRequest {
            caption_cipher: match caption_plaintext {
                Some(value) => Some(encode_b64(&encrypt_secretbox_payload(post_key, value)?)),
                None => None,
            },
        };
        let path = format!("/spaces/{space_id}/posts/{post_id}/caption");
        self.api()
            .post(&path)
            .json(&request)
            .send()
            .await?
            .error_for_status()?;
        Ok(())
    }

    pub async fn delete_post(&self, space_id: &str, post_id: i64) -> Result<()> {
        let path = format!("/spaces/{space_id}/posts/{post_id}");
        self.api().delete(&path).send().await?.error_for_status()?;
        Ok(())
    }

    pub async fn like_post(
        &self,
        space_id: &str,
        post_id: i64,
        like: bool,
    ) -> Result<LikePostResponse> {
        let path = format!("/spaces/{space_id}/posts/{post_id}/like");
        if like {
            Ok(self
                .api()
                .put(&path)
                .json(&serde_json::json!({}))
                .send()
                .await?
                .error_for_status()?
                .json()
                .await?)
        } else {
            Ok(self
                .api()
                .delete(&path)
                .send()
                .await?
                .error_for_status()?
                .json()
                .await?)
        }
    }
}
