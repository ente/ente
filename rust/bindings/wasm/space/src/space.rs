//! WASM bindings for Space flows.

use std::collections::BTreeMap;

use ente_core::{crypto::decode_b64, http::Error as HttpError};
use ente_space::{
    AccountSpaceCtx, CreatedSpace, DecryptedMessage, DecryptedPost, DecryptedSpaceProfile,
    MessageConversationActivity, MessageResponse, OpenAccountSpaceCtxInput, PostPhotoAssetOptions,
    PostResponse, ProfileAvatarResponse, ProfileCoverResponse, SpaceActorResponse,
    SpaceError as CoreSpaceError,
};
use serde::{Deserialize, Serialize};
use serde_wasm_bindgen as swb;
use wasm_bindgen::prelude::*;

/// Space client error.
#[wasm_bindgen]
pub struct WasmSpaceError {
    code: String,
    message: String,
    status: Option<u16>,
}

#[wasm_bindgen]
impl WasmSpaceError {
    /// Machine-readable error code.
    #[wasm_bindgen(getter)]
    pub fn code(&self) -> String {
        self.code.clone()
    }

    /// Human-readable error message.
    #[wasm_bindgen(getter)]
    pub fn message(&self) -> String {
        self.message.clone()
    }

    /// HTTP status code when the error came from an HTTP response.
    #[wasm_bindgen(getter)]
    pub fn status(&self) -> Option<u16> {
        self.status
    }
}

impl From<CoreSpaceError> for WasmSpaceError {
    fn from(e: CoreSpaceError) -> Self {
        let (code, status) = match &e {
            CoreSpaceError::Http(HttpError::Http { status, .. }) => ("http", Some(*status)),
            CoreSpaceError::Http(HttpError::Api { status, code, .. }) => {
                (code.as_str(), Some(*status))
            }
            CoreSpaceError::Http(HttpError::Network(_)) => ("network", None),
            CoreSpaceError::Http(HttpError::Parse(_)) => ("parse", None),
            CoreSpaceError::Crypto(_) => ("crypto", None),
            CoreSpaceError::InvalidInput(_) => ("invalid_input", None),
            CoreSpaceError::MissingSecretKey => ("missing_secret_key", None),
            CoreSpaceError::MissingFriendSealedSpaceKey => {
                ("missing_friend_sealed_space_key", None)
            }
            CoreSpaceError::EntityKeyConflict => ("entity_key_conflict", None),
        };
        Self {
            code: code.to_owned(),
            message: e.to_string(),
            status,
        }
    }
}

impl From<swb::Error> for WasmSpaceError {
    fn from(e: swb::Error) -> Self {
        Self {
            code: "serde".to_owned(),
            message: e.to_string(),
            status: None,
        }
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct OpenAccountSpaceCtxJsInput {
    base_url: String,
    space_session_token: Option<String>,
    space_root_key_b64: String,
    user_agent: Option<String>,
    client_package: Option<String>,
    client_version: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CreatedSpaceJs {
    space_id: String,
    space_slug: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct SpaceProfileJs {
    space_id: String,
    space_slug: String,
    version: i32,
    friends: i64,
    profile: String,
    avatar: Option<ProfileAvatarResponse>,
    cover: Option<ProfileCoverResponse>,
    updated_at: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ActorJs {
    space_id: String,
    space_slug: String,
    public_key: String,
    key_version: i32,
    profile: Option<String>,
    avatar: Option<ProfileAvatarResponse>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PostJs {
    post_id: i64,
    space_id: String,
    space_slug: String,
    author: ActorJs,
    caption: Option<String>,
    encrypted_post_key: String,
    key_version: i32,
    objects: Vec<PostObjectJs>,
    created_at: String,
    viewer_liked: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PostPageJs {
    items: Vec<PostJs>,
    next_cursor: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct MessageJs {
    message_id: String,
    kind: String,
    sender_space_id: String,
    recipient_space_id: String,
    text: String,
    reply_post_id: Option<i64>,
    reply_message_id: Option<String>,
    liked: bool,
    viewer_liked: bool,
    is_deleted: bool,
    created_at: String,
    updated_at: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct MessagePageJs {
    items: Vec<MessageJs>,
    next_cursor: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct MessageConversationActivityJs {
    id: String,
    #[serde(rename = "type")]
    activity_type: String,
    created_at: String,
    outgoing: bool,
    message_id: Option<String>,
    text: Option<String>,
    post_id: Option<i64>,
    post_space_id: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PostObjectJs {
    object_key: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    size: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    position: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    variant: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    blur_hash: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    thumb_hash: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    width: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    height: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    media_type: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ConversationChatSummaryJs {
    latest_activity: MessageConversationActivityJs,
    unread_activities: Vec<MessageConversationActivityJs>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ConversationsJs {
    friends: Vec<FriendJs>,
    pending_requests: Vec<FriendRequestJs>,
    chat_summaries: BTreeMap<String, ConversationChatSummaryJs>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct FriendJs {
    friend: ActorJs,
    share_key_version: i32,
    created_at: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct FriendRequestJs {
    request_id: i64,
    requester: ActorJs,
    created_at: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct SentFriendRequestJs {
    request_id: i64,
    target: ActorJs,
    created_at: String,
}

fn decode_b64_field(value: &str) -> Result<Vec<u8>, WasmSpaceError> {
    decode_b64(value)
        .map_err(CoreSpaceError::from)
        .map_err(Into::into)
}

fn utf8_field(bytes: Vec<u8>, field: &str) -> Result<String, WasmSpaceError> {
    String::from_utf8(bytes)
        .map_err(|err| CoreSpaceError::InvalidInput(format!("invalid {field} utf8: {err}")).into())
}

fn optional_utf8_field(
    bytes: Option<Vec<u8>>,
    field: &str,
) -> Result<Option<String>, WasmSpaceError> {
    bytes.map(|value| utf8_field(value, field)).transpose()
}

fn created_space_to_js(value: CreatedSpace) -> CreatedSpaceJs {
    CreatedSpaceJs {
        space_id: value.space_id,
        space_slug: value.space_slug,
    }
}

fn profile_to_js(value: DecryptedSpaceProfile) -> SpaceProfileJs {
    let profile = utf8_field(value.profile, "profile").unwrap_or_default();
    SpaceProfileJs {
        space_id: value.space_id,
        space_slug: value.space_slug,
        version: value.version,
        friends: value.friends,
        profile,
        avatar: value.avatar,
        cover: value.cover,
        updated_at: value.updated_at,
    }
}

fn actor_to_js(
    actor: SpaceActorResponse,
    profile: Option<Vec<u8>>,
) -> Result<ActorJs, WasmSpaceError> {
    Ok(ActorJs {
        space_id: actor.space_id,
        space_slug: actor.space_slug,
        public_key: actor.public_key,
        key_version: actor.key_version,
        profile: optional_utf8_field(profile, "actor profile")?,
        avatar: actor.avatar,
    })
}

async fn account_actor_to_js(
    ctx: &AccountSpaceCtx,
    actor: SpaceActorResponse,
) -> Result<ActorJs, WasmSpaceError> {
    let profile = match ctx.decrypt_actor_profile(&actor).await {
        Ok(profile) => profile,
        Err(error) if error.is_unavailable_record() => None,
        Err(error) => return Err(error.into()),
    };
    match actor_to_js(actor.clone(), profile) {
        Ok(actor) => Ok(actor),
        Err(_) => actor_to_js(actor, None),
    }
}

fn public_actor_to_js(actor: SpaceActorResponse) -> Result<ActorJs, WasmSpaceError> {
    actor_to_js(actor, None)
}

fn post_object_to_js(
    post_key: Option<&[u8]>,
    object: ente_space::PostObjectPayload,
) -> PostObjectJs {
    let metadata = match post_key {
        Some(post_key) => {
            ente_space::client::decrypt_post_object_metadata(post_key, &object).unwrap_or(None)
        }
        None => None,
    };
    PostObjectJs {
        object_key: object.object_key,
        size: object.size,
        position: object.position,
        variant: metadata.as_ref().and_then(|value| value.variant.clone()),
        blur_hash: metadata.as_ref().and_then(|value| value.blur_hash.clone()),
        thumb_hash: metadata.as_ref().and_then(|value| value.thumb_hash.clone()),
        width: metadata.as_ref().and_then(|value| value.width),
        height: metadata.as_ref().and_then(|value| value.height),
        media_type: metadata.and_then(|value| value.media_type),
    }
}

fn post_objects_to_js(
    post_key: Option<&[u8]>,
    objects: Vec<ente_space::PostObjectPayload>,
) -> Vec<PostObjectJs> {
    objects
        .into_iter()
        .map(|object| post_object_to_js(post_key, object))
        .collect()
}

async fn account_post_to_js(
    ctx: &AccountSpaceCtx,
    post: PostResponse,
    decrypted: DecryptedPost,
) -> Result<PostJs, WasmSpaceError> {
    let author = account_actor_to_js(ctx, post.author).await?;
    Ok(PostJs {
        post_id: post.post_id,
        space_id: post.space_id,
        space_slug: post.space_slug,
        author,
        caption: optional_utf8_field(decrypted.caption_plaintext, "caption").unwrap_or(None),
        encrypted_post_key: post.encrypted_post_key,
        key_version: post.key_version,
        objects: post_objects_to_js(Some(&decrypted.post_key), post.objects),
        created_at: post.created_at,
        viewer_liked: post.viewer_liked,
    })
}

async fn account_post_page_to_js(
    ctx: &AccountSpaceCtx,
    page: ente_space::PostPage,
) -> Result<PostPageJs, WasmSpaceError> {
    let mut items = Vec::with_capacity(page.items.len());
    for post in page.items {
        let decrypted = match ctx.decrypt_post_for_space(&post.space_id, &post).await {
            Ok(decrypted) => decrypted,
            Err(error) if error.is_unavailable_record() => {
                continue;
            }
            Err(error) => return Err(error.into()),
        };
        items.push(account_post_to_js(ctx, post, decrypted).await?);
    }
    Ok(PostPageJs {
        items,
        next_cursor: page.next_cursor,
    })
}

async fn account_message_to_js(
    message: MessageResponse,
    decrypted: DecryptedMessage,
) -> Result<MessageJs, WasmSpaceError> {
    Ok(message_to_js(message, decrypted.payload.text))
}

fn message_to_js(message: MessageResponse, text: String) -> MessageJs {
    MessageJs {
        message_id: message.message_id,
        kind: message.kind,
        sender_space_id: message.sender_space_id,
        recipient_space_id: message.recipient_space_id,
        text,
        reply_post_id: message.reply_post_id,
        reply_message_id: message.reply_message_id,
        liked: message.liked,
        viewer_liked: message.viewer_liked,
        is_deleted: message.is_deleted,
        created_at: message.created_at,
        updated_at: message.updated_at,
    }
}

async fn account_message_response_to_js(
    ctx: &AccountSpaceCtx,
    viewer_space_id: &str,
    message: MessageResponse,
) -> Result<MessageJs, WasmSpaceError> {
    if message.is_deleted {
        return Ok(message_to_js(message, String::new()));
    }
    if message.kind != "post_like" && message.kind != "friend_added" {
        let decrypted = match ctx.decrypt_message(viewer_space_id, &message).await {
            Ok(decrypted) => decrypted,
            Err(error) if error.is_unavailable_record() => {
                return Ok(message_to_js(message, String::new()));
            }
            Err(error) => return Err(error.into()),
        };
        return account_message_to_js(message, decrypted).await;
    }

    let text = message.text.clone();
    Ok(message_to_js(message, text))
}

async fn message_conversation_activity_text(
    ctx: &AccountSpaceCtx,
    viewer_space_id: &str,
    activity: &MessageConversationActivity,
) -> Result<Option<String>, WasmSpaceError> {
    if activity.message_cipher.trim().is_empty()
        || activity.encrypted_message_key.trim().is_empty()
        || activity.message_id.is_none()
    {
        return Ok(None);
    }

    let message = MessageResponse {
        message_id: activity.message_id.clone().unwrap_or_default(),
        kind: if activity.kind.trim().is_empty() {
            "regular".to_owned()
        } else {
            activity.kind.clone()
        },
        sender_space_id: activity.sender_space_id.clone(),
        recipient_space_id: activity.recipient_space_id.clone(),
        message_cipher: activity.message_cipher.clone(),
        encrypted_message_key: activity.encrypted_message_key.clone(),
        text: String::new(),
        reply_post_id: activity.post_id,
        reply_message_id: activity.reply_message_id.clone(),
        liked: false,
        viewer_liked: false,
        is_deleted: false,
        created_at: activity.created_at.clone(),
        updated_at: activity.created_at.clone(),
    };
    match ctx.decrypt_message(viewer_space_id, &message).await {
        Ok(decrypted) => Ok(Some(decrypted.payload.text)),
        Err(error) if error.is_unavailable_record() => Ok(None),
        Err(error) => Err(error.into()),
    }
}

async fn message_conversation_activity_to_js(
    ctx: &AccountSpaceCtx,
    viewer_space_id: &str,
    activity: MessageConversationActivity,
) -> Result<MessageConversationActivityJs, WasmSpaceError> {
    let text = message_conversation_activity_text(ctx, viewer_space_id, &activity).await?;
    Ok(MessageConversationActivityJs {
        id: activity.id,
        activity_type: activity.activity_type,
        created_at: activity.created_at,
        outgoing: activity.outgoing,
        message_id: activity.message_id,
        text,
        post_id: activity.post_id,
        post_space_id: activity.post_space_id,
    })
}

/// Open an authenticated space context for web.
#[wasm_bindgen(js_name = spaceOpenAccountCtx)]
pub async fn space_open_account_ctx(
    input: JsValue,
) -> Result<SpaceAccountCtxHandle, WasmSpaceError> {
    let input: OpenAccountSpaceCtxJsInput = swb::from_value(input)?;
    let space_root_key = decode_b64_field(&input.space_root_key_b64)?;
    let ctx = AccountSpaceCtx::open(OpenAccountSpaceCtxInput {
        base_url: input.base_url.clone(),
        space_session_token: input.space_session_token,
        space_root_key,
        user_agent: input.user_agent.clone(),
        client_package: input.client_package.clone(),
        client_version: input.client_version.clone(),
    })?;
    Ok(SpaceAccountCtxHandle { inner: ctx })
}

/// Handle to an authenticated space context.
#[wasm_bindgen]
pub struct SpaceAccountCtxHandle {
    inner: AccountSpaceCtx,
}

#[wasm_bindgen]
impl SpaceAccountCtxHandle {
    /// Create a space with an encrypted JSON profile payload.
    #[wasm_bindgen(js_name = createSpace)]
    pub async fn create_space(
        &self,
        space_slug: String,
        profile: String,
        referred_by_space_id: Option<String>,
    ) -> Result<JsValue, WasmSpaceError> {
        swb::to_value(&created_space_to_js(
            self.inner
                .create_space_with_referrer(
                    &space_slug,
                    profile.as_bytes(),
                    referred_by_space_id.as_deref(),
                )
                .await?,
        ))
        .map_err(Into::into)
    }

    /// List spaces owned by the current account.
    #[wasm_bindgen(js_name = listOwnedSpaces)]
    pub async fn list_owned_spaces(&self) -> Result<JsValue, WasmSpaceError> {
        swb::to_value(&self.inner.list_owned_spaces().await?).map_err(Into::into)
    }

    /// Fetch and decrypt a space profile.
    #[wasm_bindgen(js_name = getSpaceProfile)]
    pub async fn get_space_profile(
        &self,
        space_id: String,
        viewer_space_id: Option<String>,
    ) -> Result<JsValue, WasmSpaceError> {
        swb::to_value(&profile_to_js(
            self.inner
                .get_space_profile_decrypted(&space_id, viewer_space_id.as_deref(), None)
                .await?,
        ))
        .map_err(Into::into)
    }

    /// Update a space's encrypted JSON profile payload.
    #[wasm_bindgen(js_name = updateSpaceProfile)]
    pub async fn update_space_profile(
        &self,
        space_id: String,
        profile: String,
    ) -> Result<JsValue, WasmSpaceError> {
        swb::to_value(
            &self
                .inner
                .update_space_profile(&space_id, profile.as_bytes(), None, false)
                .await?,
        )
        .map_err(Into::into)
    }

    /// Update a space profile and replace its encrypted avatar asset.
    #[wasm_bindgen(js_name = updateSpaceProfileWithAvatar)]
    pub async fn update_space_profile_with_avatar(
        &self,
        space_id: String,
        profile: String,
        avatar_bytes: Vec<u8>,
    ) -> Result<JsValue, WasmSpaceError> {
        let space_key = self
            .inner
            .resolve_owned_space_key(&space_id)
            .await?
            .ok_or_else(|| {
                CoreSpaceError::InvalidInput(format!(
                    "space {space_id} is not owned by the account"
                ))
            })?;
        let avatar = self
            .inner
            .upload_avatar(&space_id, &space_key, &avatar_bytes)
            .await?;
        swb::to_value(
            &self
                .inner
                .update_space_profile(&space_id, profile.as_bytes(), Some(avatar), false)
                .await?,
        )
        .map_err(Into::into)
    }

    /// Update a space profile and replace its encrypted cover asset.
    #[wasm_bindgen(js_name = updateSpaceProfileWithCover)]
    pub async fn update_space_profile_with_cover(
        &self,
        space_id: String,
        profile: String,
        cover_bytes: Vec<u8>,
    ) -> Result<JsValue, WasmSpaceError> {
        let space_key = self
            .inner
            .resolve_owned_space_key(&space_id)
            .await?
            .ok_or_else(|| {
                CoreSpaceError::InvalidInput(format!(
                    "space {space_id} is not owned by the account"
                ))
            })?;
        let cover = self
            .inner
            .upload_cover(&space_id, &space_key, &cover_bytes)
            .await?;
        swb::to_value(
            &self
                .inner
                .update_space_profile_assets(
                    &space_id,
                    profile.as_bytes(),
                    None,
                    Some(cover),
                    false,
                    false,
                )
                .await?,
        )
        .map_err(Into::into)
    }

    /// Update a space's slug.
    #[wasm_bindgen(js_name = updateSpaceSlug)]
    pub async fn update_space_slug(
        &self,
        space_id: String,
        space_slug: String,
    ) -> Result<JsValue, WasmSpaceError> {
        swb::to_value(&self.inner.update_space_slug(&space_id, &space_slug).await?)
            .map_err(Into::into)
    }

    /// Lookup public space metadata by slug.
    #[wasm_bindgen(js_name = lookupSpaceBySlug)]
    pub async fn lookup_space_by_slug(
        &self,
        space_slug: String,
    ) -> Result<JsValue, WasmSpaceError> {
        swb::to_value(&self.inner.lookup_space_by_slug(&space_slug).await?).map_err(Into::into)
    }

    /// Return whether the target space is self, friend, or neither.
    #[wasm_bindgen(js_name = getRelationship)]
    pub async fn get_relationship(
        &self,
        space_id: String,
        target_space_id: String,
    ) -> Result<JsValue, WasmSpaceError> {
        swb::to_value(
            &self
                .inner
                .get_relationship(&space_id, &target_space_id)
                .await?,
        )
        .map_err(Into::into)
    }

    /// Request to add a public username as a friend.
    #[wasm_bindgen(js_name = requestFriendByUsername)]
    pub async fn request_friend_by_username(
        &self,
        space_id: String,
        space_username: String,
    ) -> Result<JsValue, WasmSpaceError> {
        swb::to_value(
            &self
                .inner
                .request_friend_by_username(&space_id, &space_username)
                .await?,
        )
        .map_err(Into::into)
    }

    /// List the current account feed with captions decrypted.
    #[wasm_bindgen(js_name = listFeed)]
    pub async fn list_feed(
        &self,
        space_id: String,
        cursor: Option<String>,
        limit: Option<i32>,
    ) -> Result<JsValue, WasmSpaceError> {
        let page = self.inner.list_feed(&space_id, cursor, limit).await?;
        swb::to_value(
            &account_post_page_to_js(
                &self.inner,
                ente_space::PostPage {
                    items: page
                        .items
                        .into_iter()
                        .map(|item| PostResponse {
                            post_id: item.post_id,
                            space_id: item.space_id,
                            space_slug: item.space_slug.clone(),
                            author: item.author,
                            encrypted_post_key: item.encrypted_post_key,
                            caption_cipher: item.caption_cipher,
                            key_version: item.key_version,
                            objects: item.objects,
                            created_at: item.created_at,
                            viewer_liked: item.viewer_liked,
                        })
                        .collect(),
                    next_cursor: page.next_cursor,
                },
            )
            .await?,
        )
        .map_err(Into::into)
    }

    /// Return whether the current account has unread notification activity.
    #[wasm_bindgen(js_name = unreadStatus)]
    pub async fn unread_status(&self, space_id: String) -> Result<JsValue, WasmSpaceError> {
        swb::to_value(&self.inner.unread_status(&space_id).await?).map_err(Into::into)
    }

    /// Mark notification activity for one friend as read.
    #[wasm_bindgen(js_name = markNotificationsRead)]
    pub async fn mark_notifications_read(
        &self,
        space_id: String,
        friend_space_id: String,
    ) -> Result<JsValue, WasmSpaceError> {
        swb::to_value(
            &self
                .inner
                .mark_notifications_read(space_id, friend_space_id)
                .await?,
        )
        .map_err(Into::into)
    }

    /// List posts on a space with captions decrypted.
    #[wasm_bindgen(js_name = listPosts)]
    pub async fn list_posts(
        &self,
        space_id: String,
        viewer_space_id: Option<String>,
        cursor: Option<String>,
        limit: Option<i32>,
    ) -> Result<JsValue, WasmSpaceError> {
        swb::to_value(
            &account_post_page_to_js(
                &self.inner,
                self.inner
                    .list_posts(&space_id, viewer_space_id.as_deref(), cursor, limit)
                    .await?,
            )
            .await?,
        )
        .map_err(Into::into)
    }

    /// Fetch one post with its caption decrypted.
    #[wasm_bindgen(js_name = getPost)]
    pub async fn get_post(
        &self,
        space_id: String,
        post_id: i64,
        viewer_space_id: Option<String>,
    ) -> Result<JsValue, WasmSpaceError> {
        let post = self
            .inner
            .get_post(&space_id, post_id, viewer_space_id.as_deref())
            .await?;
        let decrypted = self
            .inner
            .decrypt_post_for_viewer(&post.space_id, viewer_space_id.as_deref(), &post)
            .await;
        let decrypted = match decrypted {
            Ok(decrypted) => decrypted,
            Err(error) if error.is_unavailable_record() => {
                return Ok(JsValue::NULL);
            }
            Err(error) => return Err(error.into()),
        };
        swb::to_value(&account_post_to_js(&self.inner, post, decrypted).await?).map_err(Into::into)
    }

    /// Create a single-photo post with optional caption.
    #[allow(clippy::too_many_arguments)]
    #[wasm_bindgen(js_name = createPhotoPost)]
    pub async fn create_photo_post(
        &self,
        space_id: String,
        photo_bytes: Vec<u8>,
        caption: Option<String>,
        width: Option<i32>,
        height: Option<i32>,
        media_type: Option<String>,
        thumb_hash: Option<String>,
    ) -> Result<JsValue, WasmSpaceError> {
        let post_key = self.inner.generate_post_key();
        let object = self
            .inner
            .upload_post_photo_asset(
                &space_id,
                &post_key,
                &photo_bytes,
                PostPhotoAssetOptions {
                    width,
                    height,
                    media_type,
                    thumb_hash,
                },
            )
            .await?;
        let (post_id, _) = self
            .inner
            .create_post(
                &space_id,
                &[object],
                caption.as_ref().map(|value| value.as_bytes()),
                Some(&post_key),
            )
            .await?;
        let post = self
            .inner
            .get_post(&space_id, post_id, Some(&space_id))
            .await?;
        let decrypted = self
            .inner
            .decrypt_post_for_viewer(&post.space_id, Some(&space_id), &post)
            .await?;
        swb::to_value(&account_post_to_js(&self.inner, post, decrypted).await?).map_err(Into::into)
    }

    /// Download and decrypt one object from a space post.
    #[wasm_bindgen(js_name = downloadPostAsset)]
    pub async fn download_post_asset(
        &self,
        space_id: String,
        post_id: i64,
        viewer_space_id: Option<String>,
        object_key: String,
    ) -> Result<Vec<u8>, WasmSpaceError> {
        self.inner
            .download_post_asset(&space_id, post_id, viewer_space_id.as_deref(), &object_key)
            .await
            .map_err(Into::into)
    }

    /// Download and decrypt one object from an already fetched space post.
    #[wasm_bindgen(js_name = downloadPostAssetWithKey)]
    pub async fn download_post_asset_with_key(
        &self,
        space_id: String,
        encrypted_post_key: String,
        key_version: i32,
        viewer_space_id: Option<String>,
        object_key: String,
    ) -> Result<Vec<u8>, WasmSpaceError> {
        self.inner
            .download_post_asset_with_key(
                &space_id,
                &encrypted_post_key,
                key_version,
                viewer_space_id.as_deref(),
                &object_key,
            )
            .await
            .map_err(Into::into)
    }

    /// Download and decrypt a space avatar using an owned or friend space key.
    #[wasm_bindgen(js_name = downloadSpaceAvatar)]
    pub async fn download_space_avatar(
        &self,
        space_id: String,
        viewer_space_id: Option<String>,
        object_id: String,
        key_version: i32,
    ) -> Result<Vec<u8>, WasmSpaceError> {
        self.inner
            .download_profile_asset(
                &space_id,
                viewer_space_id.as_deref(),
                "avatar",
                &object_id,
                key_version,
            )
            .await
            .map_err(Into::into)
    }

    /// Download and decrypt a space cover using an owned or friend space key.
    #[wasm_bindgen(js_name = downloadSpaceCover)]
    pub async fn download_space_cover(
        &self,
        space_id: String,
        viewer_space_id: Option<String>,
        object_id: String,
        key_version: i32,
    ) -> Result<Vec<u8>, WasmSpaceError> {
        self.inner
            .download_profile_asset(
                &space_id,
                viewer_space_id.as_deref(),
                "cover",
                &object_id,
                key_version,
            )
            .await
            .map_err(Into::into)
    }

    /// Like or unlike a post.
    #[wasm_bindgen(js_name = likePost)]
    pub async fn like_post(
        &self,
        space_id: String,
        post_id: i64,
        like: bool,
    ) -> Result<JsValue, WasmSpaceError> {
        swb::to_value(&self.inner.like_post(&space_id, post_id, like).await?).map_err(Into::into)
    }

    /// Send a regular 1:1 message to a friend space.
    #[wasm_bindgen(js_name = sendMessage)]
    pub async fn send_message(
        &self,
        sender_space_id: String,
        space_id: String,
        text: String,
    ) -> Result<JsValue, WasmSpaceError> {
        let message = self
            .inner
            .send_message(&sender_space_id, &space_id, &text)
            .await?;
        let decrypted = self
            .inner
            .decrypt_message(&sender_space_id, &message)
            .await?;
        swb::to_value(&account_message_to_js(message, decrypted).await?).map_err(Into::into)
    }

    /// Send a 1:1 reply to an existing message.
    #[wasm_bindgen(js_name = replyToMessage)]
    pub async fn reply_to_message(
        &self,
        sender_space_id: String,
        space_id: String,
        message_id: String,
        text: String,
    ) -> Result<JsValue, WasmSpaceError> {
        let message = self
            .inner
            .reply_to_message(&sender_space_id, &space_id, &message_id, &text)
            .await?;
        let decrypted = self
            .inner
            .decrypt_message(&sender_space_id, &message)
            .await?;
        swb::to_value(&account_message_to_js(message, decrypted).await?).map_err(Into::into)
    }

    /// Send a private post reply message to the post owner.
    #[wasm_bindgen(js_name = replyToPost)]
    pub async fn reply_to_post(
        &self,
        sender_space_id: String,
        post_space_id: String,
        post_id: i64,
        text: String,
    ) -> Result<JsValue, WasmSpaceError> {
        let message = self
            .inner
            .reply_to_post(&sender_space_id, &post_space_id, post_id, &text)
            .await?;
        let decrypted = self
            .inner
            .decrypt_message(&sender_space_id, &message)
            .await?;
        swb::to_value(&account_message_to_js(message, decrypted).await?).map_err(Into::into)
    }

    /// Like or unlike a message.
    #[wasm_bindgen(js_name = likeMessage)]
    pub async fn like_message(
        &self,
        space_id: String,
        message_id: String,
        like: bool,
    ) -> Result<JsValue, WasmSpaceError> {
        swb::to_value(
            &self
                .inner
                .like_message(&space_id, &message_id, like)
                .await?,
        )
        .map_err(Into::into)
    }

    /// Delete a message sent by the current account.
    #[wasm_bindgen(js_name = deleteMessage)]
    pub async fn delete_message(
        &self,
        space_id: String,
        message_id: String,
    ) -> Result<(), WasmSpaceError> {
        self.inner
            .delete_message(&space_id, &message_id)
            .await
            .map_err(Into::into)
    }

    /// List current friends, pending requests, and latest chat summaries.
    #[wasm_bindgen(js_name = listConversations)]
    pub async fn list_conversations(&self, space_id: String) -> Result<JsValue, WasmSpaceError> {
        let response = self.inner.list_conversations(&space_id).await?;
        let mut friends = Vec::with_capacity(response.friends.len());
        for friend in response.friends {
            friends.push(FriendJs {
                friend: account_actor_to_js(&self.inner, friend.friend).await?,
                share_key_version: friend.share_key_version,
                created_at: friend.created_at,
            });
        }

        let mut pending_requests = Vec::with_capacity(response.pending_requests.len());
        for request in response.pending_requests {
            pending_requests.push(FriendRequestJs {
                request_id: request.request_id,
                requester: public_actor_to_js(request.requester)?,
                created_at: request.created_at,
            });
        }

        let mut chat_summaries = BTreeMap::new();
        for (friend_space_id, summary) in response.chat_summaries {
            let mut unread_activities = Vec::with_capacity(summary.unread_activities.len());
            for activity in summary.unread_activities {
                unread_activities.push(
                    message_conversation_activity_to_js(&self.inner, &space_id, activity).await?,
                );
            }
            chat_summaries.insert(
                friend_space_id,
                ConversationChatSummaryJs {
                    latest_activity: message_conversation_activity_to_js(
                        &self.inner,
                        &space_id,
                        summary.latest_activity,
                    )
                    .await?,
                    unread_activities,
                },
            );
        }

        swb::to_value(&ConversationsJs {
            friends,
            pending_requests,
            chat_summaries,
        })
        .map_err(Into::into)
    }

    /// List a 1:1 message thread with decrypted messages.
    #[wasm_bindgen(js_name = listMessageThread)]
    pub async fn list_message_thread(
        &self,
        viewer_space_id: String,
        space_id: String,
        cursor: Option<String>,
        limit: Option<i32>,
    ) -> Result<JsValue, WasmSpaceError> {
        let page = self
            .inner
            .list_message_thread(&viewer_space_id, &space_id, cursor, limit)
            .await?;
        let mut items = Vec::with_capacity(page.items.len());
        for message in page.items {
            items.push(
                account_message_response_to_js(&self.inner, &viewer_space_id, message).await?,
            );
        }
        swb::to_value(&MessagePageJs {
            items,
            next_cursor: page.next_cursor,
        })
        .map_err(Into::into)
    }

    /// Update a post caption.
    #[wasm_bindgen(js_name = updatePostCaption)]
    pub async fn update_post_caption(
        &self,
        space_id: String,
        post_id: i64,
        caption: Option<String>,
    ) -> Result<(), WasmSpaceError> {
        let post = self
            .inner
            .get_post(&space_id, post_id, Some(&space_id))
            .await?;
        let decrypted_post = self
            .inner
            .decrypt_post_for_viewer(&post.space_id, Some(&space_id), &post)
            .await?;
        self.inner
            .update_post_caption(
                &space_id,
                post_id,
                &decrypted_post.post_key,
                caption.as_ref().map(|value| value.as_bytes()),
            )
            .await
            .map_err(Into::into)
    }

    /// Delete a post.
    #[wasm_bindgen(js_name = deletePost)]
    pub async fn delete_post(&self, space_id: String, post_id: i64) -> Result<(), WasmSpaceError> {
        self.inner
            .delete_post(&space_id, post_id)
            .await
            .map_err(Into::into)
    }

    /// List friends for a space.
    #[wasm_bindgen(js_name = listSpaceFriends)]
    pub async fn list_space_friends(&self, space_id: String) -> Result<JsValue, WasmSpaceError> {
        let friends = self.inner.list_space_friends(&space_id).await?;
        let mut items = Vec::with_capacity(friends.len());
        for friend in friends {
            items.push(FriendJs {
                friend: account_actor_to_js(&self.inner, friend.friend).await?,
                share_key_version: friend.share_key_version,
                created_at: friend.created_at,
            });
        }
        swb::to_value(&items).map_err(Into::into)
    }

    /// List incoming friend requests for the current account.
    #[wasm_bindgen(js_name = listFriendRequests)]
    pub async fn list_friend_requests(&self, space_id: String) -> Result<JsValue, WasmSpaceError> {
        let requests = self.inner.list_friend_requests(&space_id).await?;
        let mut items = Vec::with_capacity(requests.len());
        for request in requests {
            items.push(FriendRequestJs {
                request_id: request.request_id,
                requester: public_actor_to_js(request.requester)?,
                created_at: request.created_at,
            });
        }
        swb::to_value(&items).map_err(Into::into)
    }

    /// List outgoing friend requests for the current account.
    #[wasm_bindgen(js_name = listSentFriendRequests)]
    pub async fn list_sent_friend_requests(
        &self,
        space_id: String,
    ) -> Result<JsValue, WasmSpaceError> {
        let requests = self.inner.list_sent_friend_requests(&space_id).await?;
        let mut items = Vec::with_capacity(requests.len());
        for request in requests {
            items.push(SentFriendRequestJs {
                request_id: request.request_id,
                target: public_actor_to_js(request.target)?,
                created_at: request.created_at,
            });
        }
        swb::to_value(&items).map_err(Into::into)
    }

    /// Confirm an incoming friend request.
    #[wasm_bindgen(js_name = confirmFriendRequest)]
    pub async fn confirm_friend_request(
        &self,
        space_id: String,
        request_id: i64,
    ) -> Result<JsValue, WasmSpaceError> {
        swb::to_value(
            &self
                .inner
                .confirm_friend_request(&space_id, request_id)
                .await?,
        )
        .map_err(Into::into)
    }

    /// Delete a pending friend request.
    #[wasm_bindgen(js_name = deleteFriendRequest)]
    pub async fn delete_friend_request(
        &self,
        space_id: String,
        request_id: i64,
    ) -> Result<(), WasmSpaceError> {
        self.inner
            .delete_friend_request(&space_id, request_id)
            .await
            .map_err(Into::into)
    }

    /// Remove a friend by their space ID.
    #[wasm_bindgen(js_name = removeFriendBySpace)]
    pub async fn remove_friend_by_space(
        &self,
        actor_space_id: String,
        space_id: String,
    ) -> Result<(), WasmSpaceError> {
        self.inner
            .unfriend_by_space(&actor_space_id, &space_id)
            .await
            .map_err(Into::into)
    }

    /// List friend shares available to the current account.
    #[wasm_bindgen(js_name = listFriendShares)]
    pub async fn list_friend_shares(&self, space_id: String) -> Result<JsValue, WasmSpaceError> {
        swb::to_value(&self.inner.list_friend_shares(&space_id).await?).map_err(Into::into)
    }

    /// Refresh friend shares for a rotated space key.
    #[wasm_bindgen(js_name = refreshFriendShares)]
    pub async fn refresh_friend_shares(&self, space_id: String) -> Result<usize, WasmSpaceError> {
        self.inner
            .refresh_friend_shares(&space_id)
            .await
            .map_err(Into::into)
    }
}
