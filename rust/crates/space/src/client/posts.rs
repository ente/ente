use super::{
    AccountSpaceCtx, PostPhotoInput, decrypt_post_object_metadata, ensure_post_objects_are_photos,
    retain_content_error,
};
use crate::crypto::{decrypt_secretbox_payload, encrypt_secretbox_payload, generate_key};
use crate::error::{Error, Result};
use crate::models::{
    HydratedKeys, Post, PostAsset, PostContent, PostPage, PostPhoto, SpaceActor, SpaceProfile,
};
use crate::transport::{
    CreatePostRequest, CreatePostResponse, LikePostResponse, PostObjectPayload, PostPageResponse,
    PostResponse, SpaceActorResponse, SpaceUnreadStatusResponse, UpdatePostCaptionRequest,
};
use ente_core::{b64, http};

impl AccountSpaceCtx {
    pub fn generate_post_key(&self) -> Vec<u8> {
        generate_key()
    }

    pub async fn create_photo_post(
        &self,
        space_id: &str,
        photos: impl ExactSizeIterator<Item = PostPhotoInput>,
        caption: Option<&str>,
    ) -> Result<Post> {
        let photo_count = photos.len();
        if !(1..=10).contains(&photo_count) {
            return Err(Error::InvalidInput("Choose between 1 and 10 photos".into()));
        }
        let post_key = self.generate_post_key();
        let mut objects = Vec::with_capacity(photo_count);
        for (position, photo) in photos.enumerate() {
            let mut object = self
                .upload_post_photo_asset(space_id, &post_key, &photo.bytes, photo.options)
                .await?;
            object.position = Some(position as i32);
            objects.push(object);
        }
        let (post_id, _) = self
            .create_post(
                space_id,
                &objects,
                caption.map(str::as_bytes),
                Some(&post_key),
            )
            .await?;
        self.get_post(space_id, post_id, Some(space_id)).await
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
                Error::InvalidInput(format!("space {space_id} is not owned by the account"))
            })?;
        let caption_cipher = match caption_plaintext {
            Some(value) => Some(b64::encode(&encrypt_secretbox_payload(
                &post_key_bytes,
                value,
            )?)),
            None => None,
        };
        let request = CreatePostRequest {
            encrypted_post_key: b64::encode(&encrypt_secretbox_payload(
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
            .error_for_code()
            .await
            .map_err(|error| match &error {
                http::Error::Api { code, .. } if code == "CONFLICT" => Error::PostLimitReached,
                _ => error.into(),
            })?
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
        let page = self
            .api()
            .get(&path)
            .query(&query)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        self.open_post_page(page).await
    }

    pub async fn list_feed(
        &self,
        space_id: &str,
        cursor: Option<String>,
        limit: Option<i32>,
    ) -> Result<PostPage> {
        let mut query = Vec::new();
        if let Some(value) = cursor.filter(|value| !value.trim().is_empty()) {
            query.push(("cursor", value));
        }
        if let Some(value) = limit {
            query.push(("limit", value.to_string()));
        }
        let path = format!("/spaces/{space_id}/feed");
        let fetch_feed = async {
            Ok(self
                .api()
                .get(&path)
                .query(&query)
                .send()
                .await?
                .error_for_status()?
                .json()
                .await?)
        };
        let (page, _) = futures_util::try_join!(
            fetch_feed,
            self.list_decrypted_friend_shares_cached(space_id)
        )?;
        self.open_post_page(page).await
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
            return Err(Error::InvalidInput("space id is required".into()));
        }
        if friend_space_id.trim().is_empty() {
            return Err(Error::InvalidInput("friend space id is required".into()));
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
    ) -> Result<Post> {
        let post = self
            .get_post_raw(space_id, post_id, viewer_space_id)
            .await?;
        let post = self.open_post(post, viewer_space_id).await?;
        Ok(Post {
            content: Ok(post.content?),
            ..post
        })
    }

    async fn open_post_page(&self, page: PostPageResponse) -> Result<PostPage> {
        let mut items = Vec::with_capacity(page.items.len());
        for post in page.items {
            items.push(self.open_post(post, None).await?);
        }
        Ok(PostPage {
            items,
            next_cursor: page.next_cursor,
        })
    }

    async fn open_post(
        &self,
        mut post: PostResponse,
        viewer_space_id: Option<&str>,
    ) -> Result<Post> {
        let decrypted = self
            .decrypt_post_for_viewer(&post.space_id, viewer_space_id, &post)
            .await;
        let content = open_post_content(&mut post, decrypted)?;
        let profile = if content.is_ok() {
            retain_content_error(self.decrypt_actor_profile(&post.author).await)?
        } else {
            Ok(None)
        };
        Ok(opened_post(post, content, profile))
    }

    pub(super) async fn get_post_raw(
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

    pub async fn download_post_asset(
        &self,
        asset: &PostAsset,
        viewer_space_id: Option<&str>,
    ) -> Result<Vec<u8>> {
        let post_key = self
            .decrypt_post_key_fields(
                &asset.space_id,
                viewer_space_id,
                &asset.encrypted_post_key,
                asset.key_version,
            )
            .await?;
        self.download_decrypted_asset(
            &asset.space_id,
            viewer_space_id,
            &asset.object_key,
            &post_key,
        )
        .await
    }

    pub async fn hydrate_space_keys(&self) -> Result<HydratedKeys> {
        let space_root_key = self.get_space_root_key()?;
        let owned_records = self.list_owned_spaces().await?;
        let mut owned = Vec::with_capacity(owned_records.len());
        if let Some(space_root_key) = space_root_key {
            for record in owned_records {
                let packed = b64::decode(&record.root_wrapped_space_key)?;
                let space_key = decrypt_secretbox_payload(&space_root_key, &packed)?;
                owned.push((record.space_id, space_key));
            }
        }

        let mut friends = Vec::new();
        for (space_id, _) in &owned {
            let friends_records = self.list_friend_shares(space_id).await?;
            for record in &friends_records {
                friends.push(self.decrypt_friend_share(space_id, record).await?);
            }
        }

        Ok(HydratedKeys { owned, friends })
    }

    async fn decrypt_post_key_fields(
        &self,
        space_id: &str,
        viewer_space_id: Option<&str>,
        encrypted_post_key: &str,
        key_version: i32,
    ) -> Result<Vec<u8>> {
        let space_key = self
            .resolve_space_key_for_version_for_viewer(space_id, viewer_space_id, Some(key_version))
            .await?
            .ok_or_else(|| Error::InvalidInput("missing space key for post".into()))?;
        let packed = b64::decode(encrypted_post_key)?;
        decrypt_secretbox_payload(&space_key, &packed)
    }

    async fn decrypt_post_for_viewer(
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
                Error::InvalidInput(format!("no space key available for post {}", post.post_id))
            })?;
        decrypt_post(&space_key, post)
    }

    pub async fn decrypt_actor_profile(
        &self,
        actor: &SpaceActorResponse,
    ) -> Result<Option<SpaceProfile>> {
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
        Ok(Some(SpaceProfile::from_bytes(&decrypt_secretbox_payload(
            &space_key,
            &b64::decode(&actor.encrypted_profile)?,
        )?)?))
    }

    pub async fn update_post_caption(
        &self,
        space_id: &str,
        post_id: i64,
        caption_plaintext: Option<&[u8]>,
    ) -> Result<()> {
        let post = self.get_post_raw(space_id, post_id, Some(space_id)).await?;
        let decrypted = self
            .decrypt_post_for_viewer(&post.space_id, Some(space_id), &post)
            .await?;
        let request = UpdatePostCaptionRequest {
            caption_cipher: match caption_plaintext {
                Some(value) => Some(b64::encode(&encrypt_secretbox_payload(
                    &decrypted.post_key,
                    value,
                )?)),
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

pub(super) struct DecryptedPost {
    post_key: Vec<u8>,
    caption_plaintext: Option<Vec<u8>>,
}

pub(super) fn decrypt_post(space_key: &[u8], post: &PostResponse) -> Result<DecryptedPost> {
    let post_key = decrypt_secretbox_payload(space_key, &b64::decode(&post.encrypted_post_key)?)?;
    let caption_plaintext = if post.caption_cipher.is_empty() {
        None
    } else {
        Some(decrypt_secretbox_payload(
            &post_key,
            &b64::decode(&post.caption_cipher)?,
        )?)
    };
    Ok(DecryptedPost {
        post_key,
        caption_plaintext,
    })
}

fn utf8_field(bytes: Vec<u8>, field: &str) -> Result<String> {
    String::from_utf8(bytes)
        .map_err(|error| Error::InvalidInput(format!("invalid {field} utf8: {error}")))
}

pub(super) fn open_post_content(
    post: &mut PostResponse,
    decrypted: Result<DecryptedPost>,
) -> Result<Result<PostContent>> {
    retain_content_error(decrypted.and_then(|decrypted| {
        let caption = decrypted
            .caption_plaintext
            .map(|bytes| utf8_field(bytes, "caption"))
            .transpose()?;
        let photos = std::mem::take(&mut post.objects)
            .into_iter()
            .filter(|object| !object.object_key.trim().is_empty())
            .map(|object| {
                let metadata = decrypt_post_object_metadata(&decrypted.post_key, &object)?;
                Ok(PostPhoto {
                    asset: PostAsset {
                        space_id: post.space_id.clone(),
                        post_id: post.post_id,
                        object_key: object.object_key,
                        encrypted_post_key: post.encrypted_post_key.clone(),
                        key_version: post.key_version,
                        size: object.size,
                    },
                    position: object.position,
                    metadata,
                })
            })
            .collect::<Result<Vec<_>>>()?;
        if photos.is_empty() {
            return Err(Error::InvalidInput("post has no photos".into()));
        }
        Ok(PostContent { caption, photos })
    }))
}

pub(super) fn opened_post(
    post: PostResponse,
    content: Result<PostContent>,
    profile: Result<Option<SpaceProfile>>,
) -> Post {
    Post {
        post_id: post.post_id,
        space_id: post.space_id,
        space_slug: post.space_slug,
        author: SpaceActor::from_response(post.author, profile),
        content,
        created_at: post.created_at,
        viewer_liked: post.viewer_liked,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ente_core::crypto::{Key, secretbox};

    fn post(post_id: i64, encrypted_post_key: String) -> PostResponse {
        PostResponse {
            post_id,
            space_id: "space-1".into(),
            space_slug: "alice".into(),
            author: crate::SpaceActorResponse {
                space_id: "space-1".into(),
                space_slug: "alice".into(),
                ..Default::default()
            },
            encrypted_post_key,
            caption_cipher: String::new(),
            key_version: 1,
            objects: vec![PostObjectPayload {
                object_key: "photo".into(),
                size: None,
                position: None,
                metadata_cipher: None,
            }],
            created_at: format!("2026-08-0{post_id}T00:00:00Z"),
            viewer_liked: false,
        }
    }

    #[tokio::test]
    async fn corrupt_posts_reject_single_reads_but_not_pages() {
        let mut server = mockito::Server::new_async().await;
        let root_key = Key::generate();
        let space_key = Key::generate();
        let wrapped_space_key = secretbox::encrypt_combined(space_key.as_bytes(), &root_key);
        let post_key = Key::generate();
        let valid_post_key = secretbox::encrypt_combined(post_key.as_bytes(), &space_key);
        let ctx = AccountSpaceCtx::open(crate::OpenAccountSpaceCtxInput {
            base_url: server.url(),
            space_session_token: None,
            space_root_key: root_key.as_bytes().to_vec(),
            initial_owned_spaces: Some(vec![crate::SpaceKeyResponse {
                space_id: "space-1".into(),
                space_slug: "alice".into(),
                root_wrapped_space_key: b64::encode(&wrapped_space_key),
                public_key: String::new(),
                encrypted_secret_key: String::new(),
                encrypted_profile: String::new(),
                key_version: 1,
            }]),
            user_agent: None,
            client_package: None,
            client_version: None,
        })
        .unwrap();
        let mut post_with_corrupt_actor_profile = post(1, b64::encode(&valid_post_key));
        post_with_corrupt_actor_profile.author.key_version = 1;
        post_with_corrupt_actor_profile.author.encrypted_profile = "not-base64".into();
        let mut valid_post = post(3, b64::encode(&valid_post_key));
        valid_post.author.key_version = 1;
        valid_post.author.encrypted_profile = b64::encode(&secretbox::encrypt_combined(
            br#"{"fullName":"Alice"}"#,
            &space_key,
        ));
        let mut invalid_caption = post(4, b64::encode(&valid_post_key));
        invalid_caption.caption_cipher =
            b64::encode(&secretbox::encrypt_combined(&[0xff], &post_key));
        let mut invalid_metadata = post(5, b64::encode(&valid_post_key));
        invalid_metadata.objects.push(PostObjectPayload {
            object_key: "photo".into(),
            size: None,
            position: None,
            metadata_cipher: Some("not-base64".into()),
        });
        let mut corrupt_post = post(2, "not-base64".into());
        let mut corrupt_caption = post(6, b64::encode(&valid_post_key));
        corrupt_caption.caption_cipher =
            b64::encode(&secretbox::encrypt_combined(b"caption", &space_key));
        let mut empty_post = post(7, b64::encode(&valid_post_key));
        empty_post.objects.clear();
        let mut blank_photo = post(8, b64::encode(&valid_post_key));
        blank_photo.objects[0].object_key = " ".into();
        for post in [
            &mut empty_post,
            &mut blank_photo,
            &mut corrupt_post,
            &mut invalid_caption,
            &mut invalid_metadata,
            &mut corrupt_caption,
        ] {
            post.author.key_version = 2;
            post.author.encrypted_profile = "not-base64".into();
        }
        let profile_keys = server
            .mock("GET", "/account/space")
            .with_status(503)
            .expect(0)
            .create_async()
            .await;
        let page = PostPageResponse {
            items: vec![
                post_with_corrupt_actor_profile,
                corrupt_post,
                valid_post,
                invalid_caption,
                invalid_metadata,
                corrupt_caption,
                empty_post,
                blank_photo,
            ],
            next_cursor: "next".into(),
        };

        for index in [1, 3, 4, 5, 6, 7] {
            let post = &page.items[index];
            let read = server
                .mock(
                    "GET",
                    format!("/spaces/space-1/posts/{}", post.post_id).as_str(),
                )
                .with_body(serde_json::to_string(post).unwrap())
                .create_async()
                .await;
            assert!(matches!(
                ctx.get_post("space-1", post.post_id, None).await,
                Err(error) if error.is_content_error()
            ));
            read.assert_async().await;
        }

        let page = ctx.open_post_page(page).await.unwrap();

        assert_eq!(page.items.len(), 8);
        assert!(page.items[0].content.is_ok());
        assert!(matches!(
            page.items[0].author.profile,
            Err(Error::Base64Decode(_))
        ));
        assert!(matches!(page.items[1].content, Err(Error::Base64Decode(_))));
        assert_eq!(page.items[1].post_id, 2);
        assert!(page.items[2].content.is_ok());
        assert_eq!(
            page.items[2]
                .author
                .profile
                .as_ref()
                .unwrap()
                .as_ref()
                .unwrap()
                .full_name
                .as_deref(),
            Some("Alice")
        );
        assert!(
            matches!(&page.items[3].content, Err(Error::InvalidInput(message)) if message.contains("caption utf8"))
        );
        assert!(matches!(page.items[4].content, Err(Error::Base64Decode(_))));
        assert!(matches!(page.items[5].content, Err(Error::Crypto(_))));
        assert!(matches!(page.items[6].content, Err(Error::InvalidInput(_))));
        assert!(matches!(page.items[7].content, Err(Error::InvalidInput(_))));
        for index in [1, 3, 4, 5, 6, 7] {
            assert!(matches!(page.items[index].author.profile, Ok(None)));
        }
        assert_eq!(page.next_cursor, "next");
        profile_keys.assert_async().await;
    }

    #[tokio::test]
    async fn key_fetch_failure_rejects_the_page() {
        let mut server = mockito::Server::new_async().await;
        let ctx = crate::client::test_support::test_account_ctx(&server.url());
        let page = PostPageResponse {
            items: vec![post(1, "not-base64".into())],
            next_cursor: String::new(),
        };
        let posts = server
            .mock("GET", "/spaces/space-1/posts")
            .with_body(serde_json::to_string(&page).unwrap())
            .create_async()
            .await;
        let keys = server
            .mock("GET", "/account/space")
            .with_status(403)
            .create_async()
            .await;

        assert!(matches!(
            ctx.list_posts("space-1", None, None, None).await,
            Err(Error::Http(http::Error::Http { status: 403, .. }))
        ));
        posts.assert_async().await;
        keys.assert_async().await;
    }
}
