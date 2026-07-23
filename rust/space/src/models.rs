use serde::{Deserialize, Serialize};
use zeroize::Zeroize;

use crate::transport::{
    PostObjectPayload, ProfileAvatarResponse, ProfileCoverResponse, SpaceActorResponse,
};

#[derive(Clone)]
pub struct OpenAccountSpaceCtxInput {
    pub base_url: String,
    pub space_session_token: Option<String>,
    pub space_root_key: Vec<u8>,
    pub user_agent: Option<String>,
    pub client_package: Option<String>,
    pub client_version: Option<String>,
}

#[derive(Clone)]
pub struct CreatedSpace {
    pub space_id: String,
    pub space_slug: String,
    pub key_version: i32,
    pub space_key: Vec<u8>,
    pub root_wrapped_space_key: String,
    pub encrypted_profile: String,
}

#[derive(Debug, Clone)]
pub struct DecryptedSpaceProfile {
    pub space_id: String,
    pub space_slug: String,
    pub version: i32,
    pub friends: i64,
    pub profile: Vec<u8>,
    pub avatar: Option<ProfileAvatarResponse>,
    pub cover: Option<ProfileCoverResponse>,
    pub updated_at: Option<String>,
}

#[derive(Clone)]
pub struct DecryptedPost {
    pub post_key: Vec<u8>,
    pub caption_plaintext: Option<Vec<u8>>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct PostObjectMetadata {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub variant: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub blur_hash: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub thumb_hash: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub width: Option<i32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub height: Option<i32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub media_type: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct MessagePayload {
    pub version: i32,
    pub kind: String,
    pub text: String,
}

#[derive(Clone)]
pub struct DecryptedMessage {
    pub message_key: Vec<u8>,
    pub payload: MessagePayload,
}

#[derive(Clone, Zeroize)]
#[zeroize(drop)]
pub struct DecryptedFriendShare {
    pub friend: String,
    pub space_id: String,
    pub space_slug: String,
    pub space_key: Vec<u8>,
    pub key_version: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct FeedItem {
    pub post_id: i64,
    pub space_id: String,
    pub space_slug: String,
    pub author: SpaceActorResponse,
    pub encrypted_post_key: String,
    #[serde(default)]
    pub caption_cipher: String,
    pub key_version: i32,
    #[serde(default)]
    pub objects: Vec<PostObjectPayload>,
    pub created_at: String,
    pub viewer_liked: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct FeedPage {
    pub items: Vec<FeedItem>,
    #[serde(default)]
    pub next_cursor: String,
}

#[derive(Clone)]
pub struct HydratedKeys {
    pub owned: Vec<(String, Vec<u8>)>,
    pub friends: Vec<DecryptedFriendShare>,
}
