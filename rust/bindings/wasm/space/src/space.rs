use std::collections::BTreeMap;

use ente_core::b64;
use ente_space::{AccountSpaceCtx, SpaceLinkCtx};
use serde::{Deserialize, Serialize};
use serde_wasm_bindgen as swb;
use tsify::Tsify;
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
            Self::Space(ente_space::Error::Http(ente_core::http::Error::Http {
                status: 404 | 410,
                ..
            })) => Some("content_unavailable"),
            Self::Space(ente_space::Error::Http(ente_core::http::Error::Http {
                status: 403,
                ..
            })) => Some("permission_denied"),
            Self::Space(error) if error.is_content_error() => Some("content_unavailable"),
            Self::Space(ente_space::Error::SpaceLimitReached) => Some("space_limit_reached"),
            Self::Space(ente_space::Error::SpaceSlugAlreadyExists) => {
                Some("space_slug_already_exists")
            }
            Self::Space(ente_space::Error::SpaceSlugReserved) => Some("space_slug_reserved"),
            Self::Space(ente_space::Error::InvalidSpaceSlug) => Some("invalid_space_slug"),
            Self::Space(ente_space::Error::PostLimitReached) => Some("post_limit_reached"),
            Self::Space(ente_space::Error::ProfileNotFound) => Some("profile_not_found"),
            Self::Space(ente_space::Error::SelfFriendship) => Some("self_friendship"),
            Self::Space(ente_space::Error::FriendRequestLimitReached) => {
                Some("friend_request_limit_reached")
            }
            Self::Space(ente_space::Error::SentFriendRequestLimitReached) => {
                Some("sent_friend_request_limit_reached")
            }
            Self::Space(ente_space::Error::FriendRequestUnavailable) => {
                Some("friend_request_unavailable")
            }
            Self::Space(ente_space::Error::SessionUnauthorized) => Some("session_unauthorized"),
            Self::Space(ente_space::Error::PermissionDenied) => Some("permission_denied"),
            _ => None,
        }
    }

    fn message(&self) -> String {
        ente_core::error::chain(self)
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

#[derive(Deserialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct OpenAccountSpaceCtxInput {
    base_url: String,
    #[tsify(optional)]
    space_session_token: Option<String>,
    space_root_key_b64: String,
    #[serde(default)]
    #[tsify(optional)]
    owned_spaces: Option<Vec<SpaceKeyResponse>>,
    #[tsify(optional)]
    client_package: Option<String>,
    #[tsify(optional)]
    client_version: Option<String>,
}

#[derive(Deserialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct OpenSpaceLinkCtxInput {
    base_url: String,
    space_username: String,
    access_key: String,
    #[tsify(optional)]
    client_package: Option<String>,
    #[tsify(optional)]
    client_version: Option<String>,
}

#[derive(Serialize, Deserialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct SpaceKeyResponse {
    space_id: String,
    space_slug: String,
    root_wrapped_space_key: String,
    #[serde(default)]
    public_key: String,
    #[serde(default)]
    encrypted_secret_key: String,
    #[serde(default)]
    encrypted_profile: String,
    key_version: i32,
}

impl From<SpaceKeyResponse> for ente_space::SpaceKeyResponse {
    fn from(value: SpaceKeyResponse) -> Self {
        Self {
            space_id: value.space_id,
            space_slug: value.space_slug,
            root_wrapped_space_key: value.root_wrapped_space_key,
            public_key: value.public_key,
            encrypted_secret_key: value.encrypted_secret_key,
            encrypted_profile: value.encrypted_profile,
            key_version: value.key_version,
        }
    }
}

impl From<ente_space::SpaceKeyResponse> for SpaceKeyResponse {
    fn from(value: ente_space::SpaceKeyResponse) -> Self {
        Self {
            space_id: value.space_id,
            space_slug: value.space_slug,
            root_wrapped_space_key: value.root_wrapped_space_key,
            public_key: value.public_key,
            encrypted_secret_key: value.encrypted_secret_key,
            encrypted_profile: value.encrypted_profile,
            key_version: value.key_version,
        }
    }
}

#[derive(Deserialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct PostPhotoAssetOptions {
    #[tsify(optional)]
    width: Option<i32>,
    #[tsify(optional)]
    height: Option<i32>,
    #[tsify(optional)]
    media_type: Option<String>,
    #[tsify(optional)]
    thumb_hash: Option<String>,
}

#[derive(Deserialize, Tsify)]
pub struct PostPhotoInput {
    #[serde(with = "swb::preserve")]
    #[tsify(type = "Uint8Array")]
    bytes: js_sys::Uint8Array,
    options: PostPhotoAssetOptions,
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct CreatedSpace {
    space_id: String,
    space_slug: String,
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct DecryptedSpaceProfile {
    space_id: String,
    space_slug: String,
    version: i32,
    friends: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    posts: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    profile: Option<SpaceProfile>,
    avatar: Option<ProfileAvatarResponse>,
    cover: Option<ProfileAvatarResponse>,
    updated_at: Option<String>,
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
struct ProfileAvatarResponse {
    #[serde(rename = "objectID")]
    object_id: String,
    key_version: i32,
    size: i64,
    updated_at: String,
}

impl From<ente_space::ProfileAvatarResponse> for ProfileAvatarResponse {
    fn from(value: ente_space::ProfileAvatarResponse) -> Self {
        Self {
            object_id: value.object_id,
            key_version: value.key_version,
            size: value.size,
            updated_at: value.updated_at,
        }
    }
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct UpdateSpaceProfileResponse {
    status: String,
    avatar: Option<ProfileAvatarResponse>,
    cover: Option<ProfileAvatarResponse>,
}

impl From<ente_space::transport::UpdateSpaceProfileResponse> for UpdateSpaceProfileResponse {
    fn from(value: ente_space::transport::UpdateSpaceProfileResponse) -> Self {
        Self {
            status: value.status,
            avatar: value.avatar.map(Into::into),
            cover: value.cover.map(Into::into),
        }
    }
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
struct SpaceActorResponse {
    space_id: String,
    space_slug: String,
    public_key: String,
    key_version: i32,
    #[serde(skip_serializing_if = "Option::is_none")]
    profile: Option<SpaceProfile>,
    #[serde(skip_serializing_if = "Option::is_none")]
    avatar: Option<ProfileAvatarResponse>,
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct PostResponse {
    post_id: i64,
    space_id: String,
    space_slug: String,
    author: SpaceActorResponse,
    caption: Option<String>,
    photos: Vec<PostPhoto>,
    is_unavailable: bool,
    created_at: String,
    viewer_liked: bool,
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct PostPage {
    items: Vec<PostResponse>,
    next_cursor: String,
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct MessageResponse {
    message_id: String,
    kind: String,
    sender_space_id: String,
    recipient_space_id: String,
    text: String,
    reply_post_id: Option<i64>,
    reply_object_key: Option<String>,
    reply_message_id: Option<String>,
    liked: bool,
    viewer_liked: bool,
    reaction: Option<String>,
    is_deleted: bool,
    created_at: String,
    updated_at: String,
    is_unavailable: bool,
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct MessagePage {
    items: Vec<MessageResponse>,
    next_cursor: String,
}

impl From<ente_space::MessagePage> for MessagePage {
    fn from(page: ente_space::MessagePage) -> Self {
        Self {
            items: page.items.into_iter().map(Into::into).collect(),
            next_cursor: page.next_cursor,
        }
    }
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
struct MessageConversationActivity {
    id: String,
    #[serde(rename = "type")]
    activity_type: String,
    kind: String,
    created_at: String,
    outgoing: bool,
    message_id: Option<String>,
    text: Option<String>,
    reaction: Option<String>,
    post_id: Option<i64>,
    reply_object_key: Option<String>,
    post_space_id: Option<String>,
    is_unavailable: bool,
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
struct PostPhoto {
    asset: PostAsset,
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

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
struct ConversationChatSummaryResponse {
    latest_activity: MessageConversationActivity,
    unread_activities: Vec<MessageConversationActivity>,
}

impl From<ente_space::ConversationChatSummary> for ConversationChatSummaryResponse {
    fn from(summary: ente_space::ConversationChatSummary) -> Self {
        Self {
            latest_activity: summary.latest_activity.into(),
            unread_activities: summary
                .unread_activities
                .into_iter()
                .map(Into::into)
                .collect(),
        }
    }
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct ConversationsResponse {
    friends: Vec<SpaceFriendResponse>,
    pending_requests: Vec<SpaceFriendRequestResponse>,
    chat_summaries: BTreeMap<String, ConversationChatSummaryResponse>,
    latest_post_created_at: Option<String>,
}

impl From<ente_space::Conversations> for ConversationsResponse {
    fn from(conversations: ente_space::Conversations) -> Self {
        Self {
            friends: conversations.friends.into_iter().map(Into::into).collect(),
            pending_requests: conversations
                .pending_requests
                .into_iter()
                .map(Into::into)
                .collect(),
            chat_summaries: conversations
                .chat_summaries
                .into_iter()
                .map(|(space_id, summary)| (space_id, summary.into()))
                .collect(),
            latest_post_created_at: conversations.latest_post_created_at,
        }
    }
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct SpaceFriendResponse {
    friend: SpaceActorResponse,
    share_key_version: i32,
    created_at: String,
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct SpaceFriendRequestResponse {
    request_id: i64,
    requester: SpaceActorResponse,
    created_at: String,
}

impl From<ente_space::SpaceFriendRequest> for SpaceFriendRequestResponse {
    fn from(request: ente_space::SpaceFriendRequest) -> Self {
        Self {
            request_id: request.request_id,
            requester: request.requester.into(),
            created_at: request.created_at,
        }
    }
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct SpaceSentFriendRequestResponse {
    request_id: i64,
    target: SpaceActorResponse,
    created_at: String,
}

impl From<ente_space::SpaceSentFriendRequest> for SpaceSentFriendRequestResponse {
    fn from(request: ente_space::SpaceSentFriendRequest) -> Self {
        Self {
            request_id: request.request_id,
            target: request.target.into(),
            created_at: request.created_at,
        }
    }
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct SpaceLookupResponse {
    space_id: String,
    space_slug: String,
    owner: String,
    public_key: String,
}

impl From<ente_space::SpaceLookupResponse> for SpaceLookupResponse {
    fn from(value: ente_space::SpaceLookupResponse) -> Self {
        Self {
            space_id: value.space_id,
            space_slug: value.space_slug,
            owner: value.owner,
            public_key: value.public_key,
        }
    }
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct FriendRelationshipResponse {
    relationship: String,
}

impl From<ente_space::FriendRelationshipResponse> for FriendRelationshipResponse {
    fn from(value: ente_space::FriendRelationshipResponse) -> Self {
        Self {
            relationship: value.relationship,
        }
    }
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct FriendStatusResponse {
    status: String,
}

impl From<ente_space::FriendStatusResponse> for FriendStatusResponse {
    fn from(value: ente_space::FriendStatusResponse) -> Self {
        Self {
            status: value.status,
        }
    }
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct SpaceUnreadStatusResponse {
    notifications_unread: bool,
}

impl From<ente_space::SpaceUnreadStatusResponse> for SpaceUnreadStatusResponse {
    fn from(value: ente_space::SpaceUnreadStatusResponse) -> Self {
        Self {
            notifications_unread: value.notifications_unread,
        }
    }
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct LikePostResponse {
    liked: bool,
}

impl From<ente_space::LikePostResponse> for LikePostResponse {
    fn from(value: ente_space::LikePostResponse) -> Self {
        Self { liked: value.liked }
    }
}

fn decode_b64_field(value: &str) -> Result<Vec<u8>, Error> {
    b64::decode(value)
        .map_err(ente_space::Error::from)
        .map_err(Into::into)
}

impl From<ente_space::CreatedSpace> for CreatedSpace {
    fn from(value: ente_space::CreatedSpace) -> Self {
        Self {
            space_id: value.space_id,
            space_slug: value.space_slug,
        }
    }
}

impl From<ente_space::DecryptedSpaceProfile> for DecryptedSpaceProfile {
    fn from(value: ente_space::DecryptedSpaceProfile) -> Self {
        Self {
            space_id: value.space_id,
            space_slug: value.space_slug,
            version: value.version,
            friends: value.friends,
            posts: None,
            profile: value.profile.map(Into::into),
            avatar: value.avatar.map(Into::into),
            cover: value.cover.map(Into::into),
            updated_at: value.updated_at,
        }
    }
}

impl From<ente_space::SpaceActor> for SpaceActorResponse {
    fn from(actor: ente_space::SpaceActor) -> Self {
        let profile = actor.profile.unwrap_or_else(|error| {
            log::warn!(
                "Space profile {} fell back to public fields: {}",
                actor.space_id,
                ente_core::error::chain(&error)
            );
            None
        });
        Self {
            space_id: actor.space_id,
            space_slug: actor.space_slug,
            public_key: actor.public_key,
            key_version: actor.key_version,
            profile: profile.map(Into::into),
            avatar: actor.avatar.map(Into::into),
        }
    }
}

impl From<ente_space::SpaceFriend> for SpaceFriendResponse {
    fn from(friend: ente_space::SpaceFriend) -> Self {
        Self {
            friend: friend.friend.into(),
            share_key_version: friend.share_key_version,
            created_at: friend.created_at,
        }
    }
}

impl From<ente_space::Post> for PostResponse {
    fn from(post: ente_space::Post) -> Self {
        let (caption, photos, is_unavailable) = match post.content {
            Ok(content) => (
                content.caption,
                content.photos.into_iter().map(Into::into).collect(),
                false,
            ),
            Err(error) => {
                log::warn!(
                    "Space post {} is unavailable: {}",
                    post.post_id,
                    ente_core::error::chain(&error)
                );
                (None, Vec::new(), true)
            }
        };
        Self {
            post_id: post.post_id,
            space_id: post.space_id,
            space_slug: post.space_slug,
            author: post.author.into(),
            caption,
            photos,
            is_unavailable,
            created_at: post.created_at,
            viewer_liked: post.viewer_liked,
        }
    }
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
struct SpaceProfile {
    #[serde(skip_serializing_if = "Option::is_none")]
    full_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    display_name: Option<String>,
}

impl From<ente_space::SpaceProfile> for SpaceProfile {
    fn from(profile: ente_space::SpaceProfile) -> Self {
        Self {
            full_name: profile.full_name,
            display_name: profile.display_name,
        }
    }
}

#[derive(Serialize, Deserialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct PostAsset {
    space_id: String,
    post_id: i64,
    object_key: String,
    encrypted_post_key: String,
    key_version: i32,
    #[serde(skip_serializing_if = "Option::is_none")]
    size: Option<i64>,
}

impl From<PostAsset> for ente_space::PostAsset {
    fn from(asset: PostAsset) -> Self {
        Self {
            space_id: asset.space_id,
            post_id: asset.post_id,
            object_key: asset.object_key,
            encrypted_post_key: asset.encrypted_post_key,
            key_version: asset.key_version,
            size: asset.size,
        }
    }
}

impl From<ente_space::PostPhoto> for PostPhoto {
    fn from(photo: ente_space::PostPhoto) -> Self {
        let metadata = photo.metadata.unwrap_or_default();
        Self {
            asset: PostAsset {
                space_id: photo.asset.space_id,
                post_id: photo.asset.post_id,
                object_key: photo.asset.object_key,
                encrypted_post_key: photo.asset.encrypted_post_key,
                key_version: photo.asset.key_version,
                size: photo.asset.size,
            },
            position: photo.position,
            variant: metadata.variant,
            blur_hash: metadata.blur_hash,
            thumb_hash: metadata.thumb_hash,
            width: metadata.width,
            height: metadata.height,
            media_type: metadata.media_type,
        }
    }
}

impl From<ente_space::PostPage> for PostPage {
    fn from(page: ente_space::PostPage) -> Self {
        Self {
            items: page.items.into_iter().map(Into::into).collect(),
            next_cursor: page.next_cursor,
        }
    }
}

impl From<ente_space::Message> for MessageResponse {
    fn from(message: ente_space::Message) -> Self {
        let (text, reply_object_key, is_deleted, is_unavailable) = match message.content {
            Ok(Some(content)) => (content.text, content.reply_object_key, false, false),
            Ok(None) => (String::new(), None, true, false),
            Err(error) => {
                log::warn!(
                    "Space message {} is unavailable: {}",
                    message.message_id,
                    ente_core::error::chain(&error)
                );
                (String::new(), None, false, true)
            }
        };
        Self {
            message_id: message.message_id,
            kind: message.kind,
            sender_space_id: message.sender_space_id,
            recipient_space_id: message.recipient_space_id,
            text,
            reply_post_id: message.reply_post_id,
            reply_object_key,
            reply_message_id: message.reply_message_id,
            liked: message.liked,
            viewer_liked: message.viewer_liked,
            reaction: message.reaction,
            is_deleted,
            created_at: message.created_at,
            updated_at: message.updated_at,
            is_unavailable,
        }
    }
}

impl From<ente_space::MessageActivity> for MessageConversationActivity {
    fn from(activity: ente_space::MessageActivity) -> Self {
        let (text, reply_object_key, is_unavailable) = match activity.content {
            Ok(Some(content)) => (Some(content.text), content.reply_object_key, false),
            Ok(None) => (None, None, false),
            Err(error) => {
                log::warn!(
                    "Space conversation activity {} is unavailable: {}",
                    activity.id,
                    ente_core::error::chain(&error)
                );
                (None, None, true)
            }
        };
        Self {
            id: activity.id,
            activity_type: activity.activity_type,
            kind: activity.kind,
            created_at: activity.created_at,
            outgoing: activity.outgoing,
            message_id: activity.message_id,
            text,
            reaction: activity.reaction,
            post_id: activity.post_id,
            reply_object_key,
            post_space_id: activity.post_space_id,
            is_unavailable,
        }
    }
}

#[derive(Serialize, Tsify)]
pub struct ReactionEmoji {
    emoji: String,
    name: String,
    group: u8,
    tags: Vec<String>,
    skins: Vec<ReactionEmojiVariant>,
}

#[derive(Serialize, Tsify)]
pub struct ReactionEmojiVariant {
    emoji: String,
    name: String,
    tone: Vec<u8>,
}

#[wasm_bindgen(js_name = spaceReactionEmojis)]
pub fn space_reaction_emojis() -> Result<Vec<<ReactionEmoji as Tsify>::JsType>, Error> {
    ente_space::reaction_emojis()
        .iter()
        .map(|entry| {
            ReactionEmoji {
                emoji: entry.emoji.clone(),
                name: entry.name.clone(),
                group: entry.group,
                tags: entry.tags.clone(),
                skins: entry
                    .skins
                    .iter()
                    .map(|skin| ReactionEmojiVariant {
                        emoji: skin.emoji.clone(),
                        name: skin.name.clone(),
                        tone: skin.tone.clone(),
                    })
                    .collect(),
            }
            .into_js()
            .map_err(Into::into)
        })
        .collect()
}

#[wasm_bindgen(js_name = spaceOpenAccountCtx)]
pub fn space_open_account_ctx(
    input: <OpenAccountSpaceCtxInput as Tsify>::JsType,
) -> Result<SpaceAccountCtxHandle, Error> {
    let input = OpenAccountSpaceCtxInput::from_js(input)?;
    let space_root_key = decode_b64_field(&input.space_root_key_b64)?;
    let ctx = AccountSpaceCtx::open(ente_space::OpenAccountSpaceCtxInput {
        base_url: input.base_url,
        space_session_token: input.space_session_token,
        space_root_key,
        initial_owned_spaces: input
            .owned_spaces
            .map(|spaces| spaces.into_iter().map(Into::into).collect()),
        user_agent: None,
        client_package: input.client_package,
        client_version: input.client_version,
    })?;
    Ok(SpaceAccountCtxHandle { inner: ctx })
}

#[wasm_bindgen(js_name = spaceOpenLinkCtx)]
pub async fn space_open_link_ctx(
    input: <OpenSpaceLinkCtxInput as Tsify>::JsType,
) -> Result<SpaceLinkCtxHandle, Error> {
    let input = OpenSpaceLinkCtxInput::from_js(input)?;
    let inner = SpaceLinkCtx::open(ente_space::OpenSpaceLinkCtxInput {
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
    pub fn get_profile(&self) -> Result<<DecryptedSpaceProfile as Tsify>::JsType, Error> {
        let mut profile = DecryptedSpaceProfile::from(self.inner.profile().clone());
        profile.posts = Some(self.inner.posts());
        profile.into_js().map_err(Into::into)
    }

    #[wasm_bindgen(js_name = listPosts)]
    pub async fn list_posts(&self) -> Result<<PostPage as Tsify>::JsType, Error> {
        let page = self.inner.list_posts().await?;
        PostPage::from(page).into_js().map_err(Into::into)
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
        asset: <PostAsset as Tsify>::JsType,
    ) -> Result<Vec<u8>, Error> {
        let asset = PostAsset::from_js(asset)?;
        self.inner
            .download_post_asset(&asset.into())
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
    #[wasm_bindgen(js_name = createSpace)]
    pub async fn create_space(
        &self,
        space_slug: String,
        profile: String,
        referred_by_space_id: Option<String>,
    ) -> Result<<CreatedSpace as Tsify>::JsType, Error> {
        CreatedSpace::from(
            self.inner
                .create_space_with_referrer(
                    &space_slug,
                    profile.as_bytes(),
                    referred_by_space_id.as_deref(),
                )
                .await?,
        )
        .into_js()
        .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = listOwnedSpaces)]
    pub async fn list_owned_spaces(
        &self,
    ) -> Result<Vec<<SpaceKeyResponse as Tsify>::JsType>, Error> {
        self.inner
            .list_owned_spaces()
            .await?
            .into_iter()
            .map(|space| SpaceKeyResponse::from(space).into_js().map_err(Into::into))
            .collect()
    }

    #[wasm_bindgen(js_name = getSpaceProfile)]
    pub async fn get_space_profile(
        &self,
        space_id: String,
        viewer_space_id: Option<String>,
    ) -> Result<<DecryptedSpaceProfile as Tsify>::JsType, Error> {
        DecryptedSpaceProfile::from(
            self.inner
                .get_space_profile_for_display(&space_id, viewer_space_id.as_deref(), None)
                .await?,
        )
        .into_js()
        .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = updateSpaceProfile)]
    pub async fn update_space_profile(
        &self,
        space_id: String,
        profile: String,
    ) -> Result<<UpdateSpaceProfileResponse as Tsify>::JsType, Error> {
        UpdateSpaceProfileResponse::from(
            self.inner
                .update_space_profile(&space_id, profile.as_bytes(), None, false)
                .await?,
        )
        .into_js()
        .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = updateSpaceProfileWithAvatar)]
    pub async fn update_space_profile_with_avatar(
        &self,
        space_id: String,
        profile: String,
        avatar_bytes: Vec<u8>,
    ) -> Result<<UpdateSpaceProfileResponse as Tsify>::JsType, Error> {
        UpdateSpaceProfileResponse::from(
            self.inner
                .update_space_profile_with_avatar(&space_id, profile.as_bytes(), &avatar_bytes)
                .await?,
        )
        .into_js()
        .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = updateSpaceProfileWithCover)]
    pub async fn update_space_profile_with_cover(
        &self,
        space_id: String,
        profile: String,
        cover_bytes: Vec<u8>,
    ) -> Result<<UpdateSpaceProfileResponse as Tsify>::JsType, Error> {
        UpdateSpaceProfileResponse::from(
            self.inner
                .update_space_profile_with_cover(&space_id, profile.as_bytes(), &cover_bytes)
                .await?,
        )
        .into_js()
        .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = removeSpaceProfileCover)]
    pub async fn remove_space_profile_cover(
        &self,
        space_id: String,
        profile: String,
    ) -> Result<<UpdateSpaceProfileResponse as Tsify>::JsType, Error> {
        UpdateSpaceProfileResponse::from(
            self.inner
                .remove_space_profile_cover(&space_id, profile.as_bytes())
                .await?,
        )
        .into_js()
        .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = removeSpaceProfileAvatar)]
    pub async fn remove_space_profile_avatar(
        &self,
        space_id: String,
        profile: String,
    ) -> Result<<UpdateSpaceProfileResponse as Tsify>::JsType, Error> {
        UpdateSpaceProfileResponse::from(
            self.inner
                .remove_space_profile_avatar(&space_id, profile.as_bytes())
                .await?,
        )
        .into_js()
        .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = updateSpaceSlug)]
    pub async fn update_space_slug(
        &self,
        space_id: String,
        space_slug: String,
    ) -> Result<<SpaceLookupResponse as Tsify>::JsType, Error> {
        SpaceLookupResponse::from(self.inner.update_space_slug(&space_id, &space_slug).await?)
            .into_js()
            .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = getRelationship)]
    pub async fn get_relationship(
        &self,
        space_id: String,
        target_space_id: String,
    ) -> Result<<FriendRelationshipResponse as Tsify>::JsType, Error> {
        FriendRelationshipResponse::from(
            self.inner
                .get_relationship(&space_id, &target_space_id)
                .await?,
        )
        .into_js()
        .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = requestFriendByUsername)]
    pub async fn request_friend_by_username(
        &self,
        space_id: String,
        space_username: String,
    ) -> Result<<FriendStatusResponse as Tsify>::JsType, Error> {
        FriendStatusResponse::from(
            self.inner
                .request_friend_by_username(&space_id, &space_username)
                .await?,
        )
        .into_js()
        .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = listFeed)]
    pub async fn list_feed(
        &self,
        space_id: String,
        cursor: Option<String>,
        limit: Option<i32>,
    ) -> Result<<PostPage as Tsify>::JsType, Error> {
        let page = self.inner.list_feed(&space_id, cursor, limit).await?;
        PostPage::from(page).into_js().map_err(Into::into)
    }

    #[wasm_bindgen(js_name = unreadStatus)]
    pub async fn unread_status(
        &self,
        space_id: String,
    ) -> Result<<SpaceUnreadStatusResponse as Tsify>::JsType, Error> {
        SpaceUnreadStatusResponse::from(self.inner.unread_status(&space_id).await?)
            .into_js()
            .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = markNotificationsRead)]
    pub async fn mark_notifications_read(
        &self,
        space_id: String,
        friend_space_id: String,
    ) -> Result<<SpaceUnreadStatusResponse as Tsify>::JsType, Error> {
        SpaceUnreadStatusResponse::from(
            self.inner
                .mark_notifications_read(space_id, friend_space_id)
                .await?,
        )
        .into_js()
        .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = listPosts)]
    pub async fn list_posts(
        &self,
        space_id: String,
        viewer_space_id: Option<String>,
        cursor: Option<String>,
        limit: Option<i32>,
    ) -> Result<<PostPage as Tsify>::JsType, Error> {
        PostPage::from(
            self.inner
                .list_posts(&space_id, viewer_space_id.as_deref(), cursor, limit)
                .await?,
        )
        .into_js()
        .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = getPost)]
    pub async fn get_post(
        &self,
        space_id: String,
        post_id: i64,
        viewer_space_id: Option<String>,
    ) -> Result<<PostResponse as Tsify>::JsType, Error> {
        let post = self
            .inner
            .get_post(&space_id, post_id, viewer_space_id.as_deref())
            .await?;
        PostResponse::from(post).into_js().map_err(Into::into)
    }

    #[wasm_bindgen(js_name = createPhotoPost)]
    pub async fn create_photo_post(
        &self,
        space_id: String,
        photos: Vec<<PostPhotoInput as Tsify>::JsType>,
        caption: Option<String>,
    ) -> Result<<PostResponse as Tsify>::JsType, Error> {
        let photos = photos
            .into_iter()
            .map(PostPhotoInput::from_js)
            .collect::<Result<Vec<_>, _>>()?;
        let photos = photos.into_iter().map(|photo| ente_space::PostPhotoInput {
            bytes: photo.bytes.to_vec(),
            options: ente_space::PostPhotoAssetOptions {
                width: photo.options.width,
                height: photo.options.height,
                media_type: photo.options.media_type,
                thumb_hash: photo.options.thumb_hash,
            },
        });
        let post = self
            .inner
            .create_photo_post(&space_id, photos, caption.as_deref())
            .await?;
        PostResponse::from(post).into_js().map_err(Into::into)
    }

    #[wasm_bindgen(js_name = downloadPostAsset)]
    pub async fn download_post_asset(
        &self,
        asset: <PostAsset as Tsify>::JsType,
        viewer_space_id: Option<String>,
    ) -> Result<Vec<u8>, Error> {
        let asset = PostAsset::from_js(asset)?;
        self.inner
            .download_post_asset(&asset.into(), viewer_space_id.as_deref())
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
    ) -> Result<<LikePostResponse as Tsify>::JsType, Error> {
        LikePostResponse::from(self.inner.like_post(&space_id, post_id, like).await?)
            .into_js()
            .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = sendMessage)]
    pub async fn send_message(
        &self,
        sender_space_id: String,
        space_id: String,
        text: String,
    ) -> Result<<MessageResponse as Tsify>::JsType, Error> {
        let message = self
            .inner
            .send_message(&sender_space_id, &space_id, &text)
            .await?;
        MessageResponse::from(message).into_js().map_err(Into::into)
    }

    #[wasm_bindgen(js_name = sendPoke)]
    pub async fn send_poke(
        &self,
        sender_space_id: String,
        space_id: String,
    ) -> Result<<MessageResponse as Tsify>::JsType, Error> {
        let message = self.inner.send_poke(&sender_space_id, &space_id).await?;
        MessageResponse::from(message).into_js().map_err(Into::into)
    }

    #[wasm_bindgen(js_name = replyToMessage)]
    pub async fn reply_to_message(
        &self,
        sender_space_id: String,
        space_id: String,
        message_id: String,
        text: String,
    ) -> Result<<MessageResponse as Tsify>::JsType, Error> {
        let message = self
            .inner
            .reply_to_message(&sender_space_id, &space_id, &message_id, &text)
            .await?;
        MessageResponse::from(message).into_js().map_err(Into::into)
    }

    #[wasm_bindgen(js_name = replyToPost)]
    pub async fn reply_to_post(
        &self,
        sender_space_id: String,
        post_space_id: String,
        post_id: i64,
        text: String,
        object_key: Option<String>,
    ) -> Result<<MessageResponse as Tsify>::JsType, Error> {
        let message = self
            .inner
            .reply_to_post(
                &sender_space_id,
                &post_space_id,
                post_id,
                &text,
                object_key.as_deref(),
            )
            .await?;
        MessageResponse::from(message).into_js().map_err(Into::into)
    }

    #[wasm_bindgen(js_name = setMessageReaction)]
    pub async fn set_message_reaction(
        &self,
        space_id: String,
        message_id: String,
        sender_space_id: String,
        emoji: String,
    ) -> Result<(), Error> {
        self.inner
            .set_message_reaction(&space_id, &message_id, &sender_space_id, &emoji)
            .await
            .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = deleteMessageReaction)]
    pub async fn delete_message_reaction(
        &self,
        space_id: String,
        message_id: String,
    ) -> Result<(), Error> {
        self.inner
            .delete_message_reaction(&space_id, &message_id)
            .await
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
    pub async fn list_conversations(
        &self,
        space_id: String,
    ) -> Result<<ConversationsResponse as Tsify>::JsType, Error> {
        let response = self.inner.list_conversations(&space_id).await?;
        ConversationsResponse::from(response)
            .into_js()
            .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = listMessageThread)]
    pub async fn list_message_thread(
        &self,
        viewer_space_id: String,
        space_id: String,
        cursor: Option<String>,
        limit: Option<i32>,
    ) -> Result<<MessagePage as Tsify>::JsType, Error> {
        let page = self
            .inner
            .list_message_thread(&viewer_space_id, &space_id, cursor, limit)
            .await?;
        MessagePage::from(page).into_js().map_err(Into::into)
    }

    #[wasm_bindgen(js_name = updatePostCaption)]
    pub async fn update_post_caption(
        &self,
        space_id: String,
        post_id: i64,
        caption: Option<String>,
    ) -> Result<(), Error> {
        self.inner
            .update_post_caption(&space_id, post_id, caption.as_ref().map(String::as_bytes))
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
    pub async fn list_space_friends(
        &self,
        space_id: String,
    ) -> Result<Vec<<SpaceFriendResponse as Tsify>::JsType>, Error> {
        let friends = self.inner.list_space_friends(&space_id).await?;
        friends
            .into_iter()
            .map(|friend| {
                SpaceFriendResponse::from(friend)
                    .into_js()
                    .map_err(Into::into)
            })
            .collect()
    }

    #[wasm_bindgen(js_name = listFriendRequests)]
    pub async fn list_friend_requests(
        &self,
        space_id: String,
    ) -> Result<Vec<<SpaceFriendRequestResponse as Tsify>::JsType>, Error> {
        let requests = self.inner.list_friend_requests(&space_id).await?;
        requests
            .into_iter()
            .map(|request| {
                SpaceFriendRequestResponse::from(request)
                    .into_js()
                    .map_err(Into::into)
            })
            .collect()
    }

    #[wasm_bindgen(js_name = listSentFriendRequests)]
    pub async fn list_sent_friend_requests(
        &self,
        space_id: String,
    ) -> Result<Vec<<SpaceSentFriendRequestResponse as Tsify>::JsType>, Error> {
        let requests = self.inner.list_sent_friend_requests(&space_id).await?;
        requests
            .into_iter()
            .map(|request| {
                SpaceSentFriendRequestResponse::from(request)
                    .into_js()
                    .map_err(Into::into)
            })
            .collect()
    }

    #[wasm_bindgen(js_name = confirmFriendRequest)]
    pub async fn confirm_friend_request(
        &self,
        space_id: String,
        request_id: i64,
    ) -> Result<<FriendStatusResponse as Tsify>::JsType, Error> {
        FriendStatusResponse::from(
            self.inner
                .confirm_friend_request(&space_id, request_id)
                .await?,
        )
        .into_js()
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
}
