use std::collections::BTreeMap;

use ente_core::b64;
use ente_space::{
    AccountSpaceCtx, CreatedSpace, DecryptedMessage, DecryptedPost, DecryptedSpaceProfile,
    MessageConversationActivity, MessageResponse, OpenAccountSpaceCtxInput, OpenSpaceLinkCtxInput,
    PostPhotoAssetOptions, PostResponse, ProfileAvatarResponse, ProfileCoverResponse,
    SpaceActorResponse, SpaceKeyResponse, SpaceLinkCtx,
};
use serde::{Deserialize, Serialize};
use serde_wasm_bindgen as swb;
use wasm_bindgen::prelude::*;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Space(#[from] ente_space::Error),
    #[error(transparent)]
    Serde(#[from] swb::Error),
}

impl Error {
    fn name(&self) -> Option<&'static str> {
        match self {
            Self::Space(error) if error.is_content_error() => Some("content_unavailable"),
            Self::Space(ente_space::Error::SpaceLimitReached) => Some("space_limit_reached"),
            Self::Space(ente_space::Error::SpaceSlugAlreadyExists) => {
                Some("space_slug_already_exists")
            }
            Self::Space(ente_space::Error::SpaceSlugReserved) => Some("space_slug_reserved"),
            Self::Space(ente_space::Error::InvalidSpaceSlug) => Some("invalid_space_slug"),
            Self::Space(ente_space::Error::PostLimitReached) => Some("post_limit_reached"),
            Self::Space(ente_space::Error::SessionUnauthorized) => Some("session_unauthorized"),
            Self::Space(ente_space::Error::PermissionDenied) => Some("permission_denied"),
            _ => None,
        }
    }

    fn message(&self) -> String {
        ente_core::error::chain(self)
    }

    fn is_content_error(&self) -> bool {
        matches!(self, Self::Space(error) if error.is_content_error())
    }
}

impl From<Error> for JsValue {
    fn from(error: Error) -> Self {
        let js_error = js_sys::Error::new(&error.message());
        if let Some(name) = error.name() {
            js_error.set_name(name);
        }
        js_error.into()
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct OpenAccountSpaceCtxJsInput {
    base_url: String,
    space_session_token: Option<String>,
    space_root_key_b64: String,
    #[serde(default)]
    owned_spaces: Option<Vec<SpaceKeyResponse>>,
    client_package: Option<String>,
    client_version: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct OpenSpaceLinkCtxJsInput {
    base_url: String,
    space_username: String,
    access_key: String,
    client_package: Option<String>,
    client_version: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct PostPhotoAssetOptionsJsInput {
    width: Option<i32>,
    height: Option<i32>,
    media_type: Option<String>,
    thumb_hash: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CreatedSpaceJs {
    space_id: String,
    space_slug: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CreatedSpaceLinkJs {
    space_id: String,
    space_slug: String,
    access_key: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct SpaceProfileJs {
    space_id: String,
    space_slug: String,
    version: i32,
    friends: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    posts: Option<i64>,
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
    is_unavailable: bool,
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
    is_unavailable: bool,
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
    is_unavailable: bool,
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
    latest_post_created_at: Option<String>,
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

fn decode_b64_field(value: &str) -> Result<Vec<u8>, Error> {
    b64::decode(value)
        .map_err(ente_space::Error::from)
        .map_err(Into::into)
}

#[wasm_bindgen(js_name = encryptSpaceRootEntityKey)]
pub fn encrypt_space_root_entity_key(
    space_root_key_b64: &str,
    master_key_b64: &str,
) -> Result<String, Error> {
    ente_space::encrypt_space_root_entity_key(space_root_key_b64, master_key_b64)
        .map_err(Into::into)
}

#[wasm_bindgen(js_name = decryptSpaceRootEntityKey)]
pub fn decrypt_space_root_entity_key(
    encrypted_key_b64: &str,
    master_key_b64: &str,
) -> Result<String, Error> {
    ente_space::decrypt_space_root_entity_key(encrypted_key_b64, master_key_b64).map_err(Into::into)
}

fn utf8_field(bytes: Vec<u8>, field: &str) -> Result<String, Error> {
    String::from_utf8(bytes).map_err(|err| {
        ente_space::Error::InvalidInput(format!("invalid {field} utf8: {err}")).into()
    })
}

fn optional_utf8_field(bytes: Option<Vec<u8>>, field: &str) -> Result<Option<String>, Error> {
    bytes.map(|value| utf8_field(value, field)).transpose()
}

fn created_space_to_js(value: CreatedSpace) -> CreatedSpaceJs {
    CreatedSpaceJs {
        space_id: value.space_id,
        space_slug: value.space_slug,
    }
}

fn profile_to_js(value: DecryptedSpaceProfile) -> Result<SpaceProfileJs, Error> {
    let profile = String::from_utf8(value.profile).unwrap_or_else(|error| {
        log::warn!(
            "Space profile {} has invalid UTF-8: {error}",
            value.space_id
        );
        String::new()
    });
    Ok(SpaceProfileJs {
        space_id: value.space_id,
        space_slug: value.space_slug,
        version: value.version,
        friends: value.friends,
        posts: None,
        profile,
        avatar: value.avatar,
        cover: value.cover,
        updated_at: value.updated_at,
    })
}

fn actor_to_js(actor: SpaceActorResponse, profile: Option<Vec<u8>>) -> Result<ActorJs, Error> {
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
) -> Result<ActorJs, Error> {
    let fallback = actor.clone();
    let converted = match ctx.decrypt_actor_profile(&actor).await {
        Ok(profile) => actor_to_js(actor, profile),
        Err(error) => Err(error.into()),
    };
    match converted {
        Ok(actor) => Ok(actor),
        Err(error) if error.is_content_error() => {
            log::warn!(
                "Space profile {} fell back to public fields: {}",
                fallback.space_id,
                error.message()
            );
            public_actor_to_js(fallback)
        }
        Err(error) => Err(error),
    }
}

fn public_actor_to_js(actor: SpaceActorResponse) -> Result<ActorJs, Error> {
    actor_to_js(actor, None)
}

fn post_object_to_js(
    post_key: Option<&[u8]>,
    object: ente_space::PostObjectPayload,
) -> Result<PostObjectJs, Error> {
    let metadata = match post_key {
        Some(post_key) => ente_space::client::decrypt_post_object_metadata(post_key, &object)?,
        None => None,
    };
    Ok(PostObjectJs {
        object_key: object.object_key,
        size: object.size,
        position: object.position,
        variant: metadata.as_ref().and_then(|value| value.variant.clone()),
        blur_hash: metadata.as_ref().and_then(|value| value.blur_hash.clone()),
        thumb_hash: metadata.as_ref().and_then(|value| value.thumb_hash.clone()),
        width: metadata.as_ref().and_then(|value| value.width),
        height: metadata.as_ref().and_then(|value| value.height),
        media_type: metadata.and_then(|value| value.media_type),
    })
}

fn post_objects_to_js(
    post_key: Option<&[u8]>,
    objects: Vec<ente_space::PostObjectPayload>,
) -> Result<Vec<PostObjectJs>, Error> {
    objects
        .into_iter()
        .map(|object| post_object_to_js(post_key, object))
        .collect()
}

async fn account_post_to_js(
    ctx: &AccountSpaceCtx,
    post: PostResponse,
    decrypted: DecryptedPost,
) -> Result<PostJs, Error> {
    let author = account_actor_to_js(ctx, post.author).await?;
    Ok(PostJs {
        post_id: post.post_id,
        space_id: post.space_id,
        space_slug: post.space_slug,
        author,
        caption: optional_utf8_field(decrypted.caption_plaintext, "caption")?,
        encrypted_post_key: post.encrypted_post_key,
        key_version: post.key_version,
        objects: post_objects_to_js(Some(&decrypted.post_key), post.objects)?,
        created_at: post.created_at,
        viewer_liked: post.viewer_liked,
        is_unavailable: false,
    })
}

fn unavailable_post_to_js(post: PostResponse) -> Result<PostJs, Error> {
    Ok(PostJs {
        post_id: post.post_id,
        space_id: post.space_id,
        space_slug: post.space_slug,
        author: public_actor_to_js(post.author)?,
        caption: None,
        encrypted_post_key: post.encrypted_post_key,
        key_version: post.key_version,
        objects: Vec::new(),
        created_at: post.created_at,
        viewer_liked: post.viewer_liked,
        is_unavailable: true,
    })
}

async fn account_post_page_to_js(
    ctx: &AccountSpaceCtx,
    page: ente_space::PostPage,
) -> Result<PostPageJs, Error> {
    let mut items = Vec::with_capacity(page.items.len());
    for post in page.items {
        let fallback = post.clone();
        let converted = match ctx.decrypt_post_for_space(&post.space_id, &post).await {
            Ok(decrypted) => account_post_to_js(ctx, post, decrypted).await,
            Err(error) => Err(error.into()),
        };
        match converted {
            Ok(post) => items.push(post),
            Err(error) if error.is_content_error() => {
                log::warn!(
                    "Space post {} is unavailable: {}",
                    fallback.post_id,
                    error.message()
                );
                items.push(unavailable_post_to_js(fallback)?);
            }
            Err(error) => return Err(error),
        }
    }
    Ok(PostPageJs {
        items,
        next_cursor: page.next_cursor,
    })
}

fn link_post_to_js(post: PostResponse, decrypted: DecryptedPost) -> Result<PostJs, Error> {
    Ok(PostJs {
        post_id: post.post_id,
        space_id: post.space_id,
        space_slug: post.space_slug,
        author: public_actor_to_js(post.author)?,
        caption: optional_utf8_field(decrypted.caption_plaintext, "caption")?,
        encrypted_post_key: post.encrypted_post_key,
        key_version: post.key_version,
        objects: post_objects_to_js(Some(&decrypted.post_key), post.objects)?,
        created_at: post.created_at,
        viewer_liked: false,
        is_unavailable: false,
    })
}

async fn account_message_to_js(
    message: MessageResponse,
    decrypted: DecryptedMessage,
) -> Result<MessageJs, Error> {
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
        is_unavailable: false,
    }
}

fn unavailable_message_to_js(message: MessageResponse) -> MessageJs {
    MessageJs {
        message_id: message.message_id,
        kind: message.kind,
        sender_space_id: message.sender_space_id,
        recipient_space_id: message.recipient_space_id,
        text: String::new(),
        reply_post_id: message.reply_post_id,
        reply_message_id: message.reply_message_id,
        liked: message.liked,
        viewer_liked: message.viewer_liked,
        is_deleted: message.is_deleted,
        created_at: message.created_at,
        updated_at: message.updated_at,
        is_unavailable: true,
    }
}

async fn account_message_response_to_js(
    ctx: &AccountSpaceCtx,
    viewer_space_id: &str,
    message: MessageResponse,
) -> Result<MessageJs, Error> {
    if message.is_deleted {
        return Ok(message_to_js(message, String::new()));
    }
    if message.kind != "post_like" && message.kind != "friend_added" {
        let decrypted = ctx.decrypt_message(viewer_space_id, &message).await?;
        return account_message_to_js(message, decrypted).await;
    }

    let text = message.text.clone();
    Ok(message_to_js(message, text))
}

async fn resilient_account_message_response_to_js(
    ctx: &AccountSpaceCtx,
    viewer_space_id: &str,
    message: MessageResponse,
) -> Result<MessageJs, Error> {
    let fallback = message.clone();
    match account_message_response_to_js(ctx, viewer_space_id, message).await {
        Ok(message) => Ok(message),
        Err(error) if error.is_content_error() => {
            log::warn!(
                "Space message {} is unavailable: {}",
                fallback.message_id,
                error.message()
            );
            Ok(unavailable_message_to_js(fallback))
        }
        Err(error) => Err(error),
    }
}

async fn message_conversation_activity_text(
    ctx: &AccountSpaceCtx,
    viewer_space_id: &str,
    activity: &MessageConversationActivity,
) -> Result<Option<String>, Error> {
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
    let decrypted = ctx.decrypt_message(viewer_space_id, &message).await?;
    Ok(Some(decrypted.payload.text))
}

async fn message_conversation_activity_to_js(
    ctx: &AccountSpaceCtx,
    viewer_space_id: &str,
    activity: MessageConversationActivity,
) -> Result<MessageConversationActivityJs, Error> {
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
        is_unavailable: false,
    })
}

fn unavailable_message_conversation_activity_to_js(
    activity: MessageConversationActivity,
) -> MessageConversationActivityJs {
    MessageConversationActivityJs {
        id: activity.id,
        activity_type: activity.activity_type,
        created_at: activity.created_at,
        outgoing: activity.outgoing,
        message_id: activity.message_id,
        text: None,
        post_id: activity.post_id,
        post_space_id: activity.post_space_id,
        is_unavailable: true,
    }
}

async fn resilient_message_conversation_activity_to_js(
    ctx: &AccountSpaceCtx,
    viewer_space_id: &str,
    activity: MessageConversationActivity,
) -> Result<MessageConversationActivityJs, Error> {
    let fallback = activity.clone();
    match message_conversation_activity_to_js(ctx, viewer_space_id, activity).await {
        Ok(activity) => Ok(activity),
        Err(error) if error.is_content_error() => {
            log::warn!(
                "Space conversation activity {} is unavailable: {}",
                fallback.id,
                error.message()
            );
            Ok(unavailable_message_conversation_activity_to_js(fallback))
        }
        Err(error) => Err(error),
    }
}

#[wasm_bindgen(js_name = spaceOpenAccountCtx)]
pub async fn space_open_account_ctx(input: JsValue) -> Result<SpaceAccountCtxHandle, Error> {
    let input: OpenAccountSpaceCtxJsInput = swb::from_value(input)?;
    let space_root_key = decode_b64_field(&input.space_root_key_b64)?;
    let ctx = AccountSpaceCtx::open(OpenAccountSpaceCtxInput {
        base_url: input.base_url,
        space_session_token: input.space_session_token,
        space_root_key,
        initial_owned_spaces: input.owned_spaces,
        user_agent: None,
        client_package: input.client_package,
        client_version: input.client_version,
    })?;
    Ok(SpaceAccountCtxHandle { inner: ctx })
}

#[wasm_bindgen(js_name = spaceOpenLinkCtx)]
pub async fn space_open_link_ctx(input: JsValue) -> Result<SpaceLinkCtxHandle, Error> {
    let input: OpenSpaceLinkCtxJsInput = swb::from_value(input)?;
    let inner = SpaceLinkCtx::open(OpenSpaceLinkCtxInput {
        base_url: input.base_url,
        space_slug: input.space_username,
        access_key: input.access_key,
        user_agent: None,
        client_package: input.client_package,
        client_version: input.client_version,
    })
    .await?;
    Ok(SpaceLinkCtxHandle { inner })
}

#[wasm_bindgen]
pub struct SpaceLinkCtxHandle {
    inner: SpaceLinkCtx,
}

#[wasm_bindgen]
impl SpaceLinkCtxHandle {
    #[wasm_bindgen(js_name = getProfile)]
    pub fn get_profile(&self) -> Result<JsValue, Error> {
        let mut profile = profile_to_js(self.inner.profile().clone())?;
        profile.posts = Some(self.inner.posts());
        swb::to_value(&profile).map_err(Into::into)
    }

    #[wasm_bindgen(js_name = listPosts)]
    pub async fn list_posts(&self) -> Result<JsValue, Error> {
        let page = self.inner.list_posts().await?;
        let mut items = Vec::with_capacity(page.items.len());
        for post in page.items {
            let fallback = post.clone();
            let converted = match self.inner.decrypt_post(&post) {
                Ok(decrypted) => link_post_to_js(post, decrypted),
                Err(error) => Err(error.into()),
            };
            match converted {
                Ok(post) => items.push(post),
                Err(error) if error.is_content_error() => {
                    log::warn!(
                        "Space post {} is unavailable: {}",
                        fallback.post_id,
                        error.message()
                    );
                    items.push(unavailable_post_to_js(fallback)?);
                }
                Err(error) => return Err(error),
            }
        }
        swb::to_value(&PostPageJs {
            items,
            next_cursor: page.next_cursor,
        })
        .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = subscribeWebPush)]
    pub async fn subscribe_web_push(
        &self,
        endpoint: String,
        p256dh: String,
        auth: String,
    ) -> Result<String, Error> {
        self.inner
            .subscribe_web_push(endpoint, p256dh, auth)
            .await
            .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = unsubscribeWebPush)]
    pub async fn unsubscribe_web_push(&self, endpoint: String) -> Result<(), Error> {
        self.inner
            .unsubscribe_web_push(endpoint)
            .await
            .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = downloadPostAsset)]
    pub async fn download_post_asset(
        &self,
        encrypted_post_key: String,
        key_version: i32,
        object_key: String,
    ) -> Result<Vec<u8>, Error> {
        self.inner
            .download_post_asset(&encrypted_post_key, key_version, &object_key)
            .await
            .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = downloadAvatar)]
    pub async fn download_avatar(
        &self,
        object_id: String,
        key_version: i32,
    ) -> Result<Vec<u8>, Error> {
        self.inner
            .download_profile_asset("avatar", &object_id, key_version)
            .await
            .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = downloadCover)]
    pub async fn download_cover(
        &self,
        object_id: String,
        key_version: i32,
    ) -> Result<Vec<u8>, Error> {
        self.inner
            .download_profile_asset("cover", &object_id, key_version)
            .await
            .map_err(Into::into)
    }
}

#[wasm_bindgen]
pub struct SpaceAccountCtxHandle {
    inner: AccountSpaceCtx,
}

#[wasm_bindgen]
impl SpaceAccountCtxHandle {
    #[wasm_bindgen(js_name = getOrCreateSpaceLink)]
    pub async fn get_or_create_space_link(&self, space_id: String) -> Result<JsValue, Error> {
        let value = self.inner.get_or_create_space_link(&space_id).await?;
        swb::to_value(&CreatedSpaceLinkJs {
            space_id: value.space_id,
            space_slug: value.space_slug,
            access_key: value.access_key,
        })
        .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = rotateSpaceLink)]
    pub async fn rotate_space_link(&self, space_id: String) -> Result<JsValue, Error> {
        let value = self.inner.rotate_space_link(&space_id).await?;
        swb::to_value(&CreatedSpaceLinkJs {
            space_id: value.space_id,
            space_slug: value.space_slug,
            access_key: value.access_key,
        })
        .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = createSpace)]
    pub async fn create_space(
        &self,
        space_slug: String,
        profile: String,
        referred_by_space_id: Option<String>,
    ) -> Result<JsValue, Error> {
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

    #[wasm_bindgen(js_name = listOwnedSpaces)]
    pub async fn list_owned_spaces(&self) -> Result<JsValue, Error> {
        swb::to_value(&self.inner.list_owned_spaces().await?).map_err(Into::into)
    }

    #[wasm_bindgen(js_name = getSpaceProfile)]
    pub async fn get_space_profile(
        &self,
        space_id: String,
        viewer_space_id: Option<String>,
    ) -> Result<JsValue, Error> {
        swb::to_value(&profile_to_js(
            self.inner
                .get_space_profile_for_display(&space_id, viewer_space_id.as_deref(), None)
                .await?,
        )?)
        .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = updateSpaceProfile)]
    pub async fn update_space_profile(
        &self,
        space_id: String,
        profile: String,
    ) -> Result<JsValue, Error> {
        swb::to_value(
            &self
                .inner
                .update_space_profile(&space_id, profile.as_bytes(), None, false)
                .await?,
        )
        .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = updateSpaceProfileWithAvatar)]
    pub async fn update_space_profile_with_avatar(
        &self,
        space_id: String,
        profile: String,
        avatar_bytes: Vec<u8>,
    ) -> Result<JsValue, Error> {
        let space_key = self
            .inner
            .resolve_owned_space_key(&space_id)
            .await?
            .ok_or_else(|| {
                ente_space::Error::InvalidInput(format!(
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

    #[wasm_bindgen(js_name = updateSpaceProfileWithCover)]
    pub async fn update_space_profile_with_cover(
        &self,
        space_id: String,
        profile: String,
        cover_bytes: Vec<u8>,
    ) -> Result<JsValue, Error> {
        let space_key = self
            .inner
            .resolve_owned_space_key(&space_id)
            .await?
            .ok_or_else(|| {
                ente_space::Error::InvalidInput(format!(
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

    #[wasm_bindgen(js_name = updateSpaceSlug)]
    pub async fn update_space_slug(
        &self,
        space_id: String,
        space_slug: String,
    ) -> Result<JsValue, Error> {
        swb::to_value(&self.inner.update_space_slug(&space_id, &space_slug).await?)
            .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = lookupSpaceBySlug)]
    pub async fn lookup_space_by_slug(&self, space_slug: String) -> Result<JsValue, Error> {
        swb::to_value(&self.inner.lookup_space_by_slug(&space_slug).await?).map_err(Into::into)
    }

    #[wasm_bindgen(js_name = getRelationship)]
    pub async fn get_relationship(
        &self,
        space_id: String,
        target_space_id: String,
    ) -> Result<JsValue, Error> {
        swb::to_value(
            &self
                .inner
                .get_relationship(&space_id, &target_space_id)
                .await?,
        )
        .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = requestFriendByUsername)]
    pub async fn request_friend_by_username(
        &self,
        space_id: String,
        space_username: String,
    ) -> Result<JsValue, Error> {
        swb::to_value(
            &self
                .inner
                .request_friend_by_username(&space_id, &space_username)
                .await?,
        )
        .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = listFeed)]
    pub async fn list_feed(
        &self,
        space_id: String,
        cursor: Option<String>,
        limit: Option<i32>,
    ) -> Result<JsValue, Error> {
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

    #[wasm_bindgen(js_name = unreadStatus)]
    pub async fn unread_status(&self, space_id: String) -> Result<JsValue, Error> {
        swb::to_value(&self.inner.unread_status(&space_id).await?).map_err(Into::into)
    }

    #[wasm_bindgen(js_name = markNotificationsRead)]
    pub async fn mark_notifications_read(
        &self,
        space_id: String,
        friend_space_id: String,
    ) -> Result<JsValue, Error> {
        swb::to_value(
            &self
                .inner
                .mark_notifications_read(space_id, friend_space_id)
                .await?,
        )
        .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = listPosts)]
    pub async fn list_posts(
        &self,
        space_id: String,
        viewer_space_id: Option<String>,
        cursor: Option<String>,
        limit: Option<i32>,
    ) -> Result<JsValue, Error> {
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

    #[wasm_bindgen(js_name = getPost)]
    pub async fn get_post(
        &self,
        space_id: String,
        post_id: i64,
        viewer_space_id: Option<String>,
    ) -> Result<JsValue, Error> {
        let post = self
            .inner
            .get_post(&space_id, post_id, viewer_space_id.as_deref())
            .await?;
        let decrypted = self
            .inner
            .decrypt_post_for_viewer(&post.space_id, viewer_space_id.as_deref(), &post)
            .await?;
        swb::to_value(&account_post_to_js(&self.inner, post, decrypted).await?).map_err(Into::into)
    }

    #[wasm_bindgen(js_name = createPhotoPost)]
    pub async fn create_photo_post(
        &self,
        space_id: String,
        photo_bytes: Vec<u8>,
        caption: Option<String>,
        photo_options: JsValue,
    ) -> Result<JsValue, Error> {
        let photo_options: PostPhotoAssetOptionsJsInput = swb::from_value(photo_options)?;
        let post_key = self.inner.generate_post_key();
        let object = self
            .inner
            .upload_post_photo_asset(
                &space_id,
                &post_key,
                &photo_bytes,
                PostPhotoAssetOptions {
                    width: photo_options.width,
                    height: photo_options.height,
                    media_type: photo_options.media_type,
                    thumb_hash: photo_options.thumb_hash,
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

    #[wasm_bindgen(js_name = downloadPostAsset)]
    pub async fn download_post_asset(
        &self,
        space_id: String,
        post_id: i64,
        viewer_space_id: Option<String>,
        object_key: String,
    ) -> Result<Vec<u8>, Error> {
        self.inner
            .download_post_asset(&space_id, post_id, viewer_space_id.as_deref(), &object_key)
            .await
            .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = downloadPostAssetWithKey)]
    pub async fn download_post_asset_with_key(
        &self,
        space_id: String,
        encrypted_post_key: String,
        key_version: i32,
        viewer_space_id: Option<String>,
        object_key: String,
    ) -> Result<Vec<u8>, Error> {
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

    #[wasm_bindgen(js_name = downloadSpaceAvatar)]
    pub async fn download_space_avatar(
        &self,
        space_id: String,
        viewer_space_id: Option<String>,
        object_id: String,
        key_version: i32,
    ) -> Result<Vec<u8>, Error> {
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

    #[wasm_bindgen(js_name = downloadSpaceCover)]
    pub async fn download_space_cover(
        &self,
        space_id: String,
        viewer_space_id: Option<String>,
        object_id: String,
        key_version: i32,
    ) -> Result<Vec<u8>, Error> {
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

    #[wasm_bindgen(js_name = likePost)]
    pub async fn like_post(
        &self,
        space_id: String,
        post_id: i64,
        like: bool,
    ) -> Result<JsValue, Error> {
        swb::to_value(&self.inner.like_post(&space_id, post_id, like).await?).map_err(Into::into)
    }

    #[wasm_bindgen(js_name = sendMessage)]
    pub async fn send_message(
        &self,
        sender_space_id: String,
        space_id: String,
        text: String,
    ) -> Result<JsValue, Error> {
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

    #[wasm_bindgen(js_name = replyToMessage)]
    pub async fn reply_to_message(
        &self,
        sender_space_id: String,
        space_id: String,
        message_id: String,
        text: String,
    ) -> Result<JsValue, Error> {
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

    #[wasm_bindgen(js_name = replyToPost)]
    pub async fn reply_to_post(
        &self,
        sender_space_id: String,
        post_space_id: String,
        post_id: i64,
        text: String,
    ) -> Result<JsValue, Error> {
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

    #[wasm_bindgen(js_name = likeMessage)]
    pub async fn like_message(
        &self,
        space_id: String,
        message_id: String,
        like: bool,
    ) -> Result<JsValue, Error> {
        swb::to_value(
            &self
                .inner
                .like_message(&space_id, &message_id, like)
                .await?,
        )
        .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = deleteMessage)]
    pub async fn delete_message(&self, space_id: String, message_id: String) -> Result<(), Error> {
        self.inner
            .delete_message(&space_id, &message_id)
            .await
            .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = listConversations)]
    pub async fn list_conversations(&self, space_id: String) -> Result<JsValue, Error> {
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
                    resilient_message_conversation_activity_to_js(&self.inner, &space_id, activity)
                        .await?,
                );
            }
            chat_summaries.insert(
                friend_space_id,
                ConversationChatSummaryJs {
                    latest_activity: resilient_message_conversation_activity_to_js(
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
            latest_post_created_at: response.latest_post_created_at,
        })
        .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = listMessageThread)]
    pub async fn list_message_thread(
        &self,
        viewer_space_id: String,
        space_id: String,
        cursor: Option<String>,
        limit: Option<i32>,
    ) -> Result<JsValue, Error> {
        let page = self
            .inner
            .list_message_thread(&viewer_space_id, &space_id, cursor, limit)
            .await?;
        let mut items = Vec::with_capacity(page.items.len());
        for message in page.items {
            items.push(
                resilient_account_message_response_to_js(&self.inner, &viewer_space_id, message)
                    .await?,
            );
        }
        swb::to_value(&MessagePageJs {
            items,
            next_cursor: page.next_cursor,
        })
        .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = updatePostCaption)]
    pub async fn update_post_caption(
        &self,
        space_id: String,
        post_id: i64,
        caption: Option<String>,
    ) -> Result<(), Error> {
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

    #[wasm_bindgen(js_name = deletePost)]
    pub async fn delete_post(&self, space_id: String, post_id: i64) -> Result<(), Error> {
        self.inner
            .delete_post(&space_id, post_id)
            .await
            .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = listSpaceFriends)]
    pub async fn list_space_friends(&self, space_id: String) -> Result<JsValue, Error> {
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

    #[wasm_bindgen(js_name = listFriendRequests)]
    pub async fn list_friend_requests(&self, space_id: String) -> Result<JsValue, Error> {
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

    #[wasm_bindgen(js_name = listSentFriendRequests)]
    pub async fn list_sent_friend_requests(&self, space_id: String) -> Result<JsValue, Error> {
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

    #[wasm_bindgen(js_name = confirmFriendRequest)]
    pub async fn confirm_friend_request(
        &self,
        space_id: String,
        request_id: i64,
    ) -> Result<JsValue, Error> {
        swb::to_value(
            &self
                .inner
                .confirm_friend_request(&space_id, request_id)
                .await?,
        )
        .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = deleteFriendRequest)]
    pub async fn delete_friend_request(
        &self,
        space_id: String,
        request_id: i64,
    ) -> Result<(), Error> {
        self.inner
            .delete_friend_request(&space_id, request_id)
            .await
            .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = removeFriendBySpace)]
    pub async fn remove_friend_by_space(
        &self,
        actor_space_id: String,
        space_id: String,
    ) -> Result<(), Error> {
        self.inner
            .unfriend_by_space(&actor_space_id, &space_id)
            .await
            .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = listFriendShares)]
    pub async fn list_friend_shares(&self, space_id: String) -> Result<JsValue, Error> {
        swb::to_value(&self.inner.list_friend_shares(&space_id).await?).map_err(Into::into)
    }

    #[wasm_bindgen(js_name = refreshFriendShares)]
    pub async fn refresh_friend_shares(&self, space_id: String) -> Result<usize, Error> {
        self.inner
            .refresh_friend_shares(&space_id)
            .await
            .map_err(Into::into)
    }
}

#[cfg(test)]
mod tests {
    use ente_core::crypto::{Key, SecretKey, sealed, secretbox};

    use super::*;

    fn post(post_id: i64, encrypted_post_key: String) -> PostResponse {
        PostResponse {
            post_id,
            space_id: "space-1".into(),
            space_slug: "alice".into(),
            author: SpaceActorResponse {
                space_id: "space-1".into(),
                space_slug: "alice".into(),
                ..Default::default()
            },
            encrypted_post_key,
            caption_cipher: String::new(),
            key_version: 1,
            objects: Vec::new(),
            created_at: format!("2026-08-0{post_id}T00:00:00Z"),
            viewer_liked: false,
        }
    }

    fn message(
        message_id: &str,
        encrypted_message_key: &str,
        message_cipher: &str,
    ) -> MessageResponse {
        MessageResponse {
            message_id: message_id.into(),
            kind: "regular".into(),
            sender_space_id: "space-2".into(),
            recipient_space_id: "space-1".into(),
            message_cipher: message_cipher.into(),
            encrypted_message_key: encrypted_message_key.into(),
            text: String::new(),
            reply_post_id: None,
            reply_message_id: None,
            liked: false,
            viewer_liked: false,
            is_deleted: false,
            created_at: "2026-08-01T00:00:00Z".into(),
            updated_at: "2026-08-01T00:00:00Z".into(),
        }
    }

    #[tokio::test]
    async fn corrupt_post_does_not_reject_account_page() {
        let root_key = Key::generate();
        let space_key = Key::generate();
        let wrapped_space_key = secretbox::encrypt_combined(space_key.as_bytes(), &root_key);
        let valid_post_key = secretbox::encrypt_combined(Key::generate().as_bytes(), &space_key);
        let ctx = AccountSpaceCtx::open(OpenAccountSpaceCtxInput {
            base_url: "http://localhost".into(),
            space_session_token: None,
            space_root_key: root_key.as_bytes().to_vec(),
            initial_owned_spaces: Some(vec![SpaceKeyResponse {
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
        let page = ente_space::PostPage {
            items: vec![
                post_with_corrupt_actor_profile,
                post(2, "not-base64".into()),
                post(3, b64::encode(&valid_post_key)),
            ],
            next_cursor: "next".into(),
        };

        let converted = match account_post_page_to_js(&ctx, page).await {
            Ok(converted) => converted,
            Err(error) => panic!("{error}"),
        };

        assert_eq!(converted.items.len(), 3);
        assert!(!converted.items[0].is_unavailable);
        assert!(converted.items[1].is_unavailable);
        assert!(!converted.items[2].is_unavailable);
        assert_eq!(converted.next_cursor, "next");
    }

    #[tokio::test]
    async fn corrupt_message_and_activity_become_unavailable() {
        let root_key = Key::generate();
        let secret_key = SecretKey::generate();
        let public_key = secret_key.public_key();
        let encrypted_secret_key = secretbox::encrypt_combined(secret_key.as_bytes(), &root_key);
        let ctx = AccountSpaceCtx::open(OpenAccountSpaceCtxInput {
            base_url: "http://localhost".into(),
            space_session_token: None,
            space_root_key: root_key.as_bytes().to_vec(),
            initial_owned_spaces: Some(vec![SpaceKeyResponse {
                space_id: "space-1".into(),
                space_slug: "alice".into(),
                root_wrapped_space_key: String::new(),
                public_key: b64::encode(public_key.as_bytes()),
                encrypted_secret_key: b64::encode(&encrypted_secret_key),
                encrypted_profile: String::new(),
                key_version: 1,
            }]),
            user_agent: None,
            client_package: None,
            client_version: None,
        })
        .unwrap();
        let message_key = Key::generate();
        let sealed_message_key = sealed::seal(message_key.as_bytes(), &public_key).unwrap();
        let encrypted_message_key = b64::encode(&sealed_message_key);
        let valid_cipher = b64::encode(&secretbox::encrypt_combined(
            br#"{"version":1,"kind":"regular","text":"hello"}"#,
            &message_key,
        ));
        let corrupt_cipher = b64::encode(&secretbox::encrypt_combined(b"not-json", &message_key));

        let first = resilient_account_message_response_to_js(
            &ctx,
            "space-1",
            message("message-1", &encrypted_message_key, &valid_cipher),
        )
        .await
        .unwrap_or_else(|error| panic!("{error}"));
        let corrupt = resilient_account_message_response_to_js(
            &ctx,
            "space-1",
            message("message-2", &encrypted_message_key, &corrupt_cipher),
        )
        .await
        .unwrap_or_else(|error| panic!("{error}"));
        let last = resilient_account_message_response_to_js(
            &ctx,
            "space-1",
            message("message-3", &encrypted_message_key, &valid_cipher),
        )
        .await
        .unwrap_or_else(|error| panic!("{error}"));

        assert!(!first.is_unavailable);
        assert!(corrupt.is_unavailable);
        assert!(!last.is_unavailable);

        let activity = MessageConversationActivity {
            id: "activity-1".into(),
            activity_type: "message".into(),
            kind: "regular".into(),
            created_at: "2026-08-01T00:00:00Z".into(),
            outgoing: false,
            message_id: Some("message-2".into()),
            sender_space_id: "space-2".into(),
            recipient_space_id: "space-1".into(),
            message_cipher: corrupt_cipher,
            encrypted_message_key,
            reply_message_id: None,
            post_id: None,
            post_space_id: None,
        };
        let activity = resilient_message_conversation_activity_to_js(&ctx, "space-1", activity)
            .await
            .unwrap_or_else(|error| panic!("{error}"));

        assert!(activity.is_unavailable);
    }

    #[test]
    fn http_errors_are_not_content_errors() {
        let error = Error::from(ente_space::Error::Http(ente_core::http::Error::Http {
            status: 500,
            path: "/space".into(),
        }));

        assert!(!error.is_content_error());
    }

    #[test]
    fn invalid_profile_utf8_uses_empty_payload() {
        let profile = profile_to_js(DecryptedSpaceProfile {
            space_id: "space-1".into(),
            space_slug: "alice".into(),
            version: 1,
            friends: 2,
            profile: vec![0xff],
            avatar: None,
            cover: None,
            updated_at: None,
        })
        .unwrap_or_else(|error| panic!("{error}"));

        assert!(profile.profile.is_empty());
        assert_eq!(profile.space_slug, "alice");
    }
}
