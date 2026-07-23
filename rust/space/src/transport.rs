use serde::{Deserialize, Serialize};

fn is_false(value: &bool) -> bool {
    !*value
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct EntityKeyPayload {
    pub encrypted_key: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EntityKeyResponse {
    #[serde(rename = "type")]
    pub key_type: String,
    pub encrypted_key: String,
    pub header: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateEntityKeyRequest {
    #[serde(rename = "type")]
    pub key_type: String,
    pub encrypted_key: String,
    pub header: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateSpaceRequest {
    pub space_slug: String,
    pub root_wrapped_space_key: String,
    pub public_key: String,
    pub encrypted_secret_key: String,
    pub encrypted_profile: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub referred_by_space_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpaceKeyResponse {
    pub space_id: String,
    pub space_slug: String,
    pub root_wrapped_space_key: String,
    #[serde(default)]
    pub public_key: String,
    #[serde(default)]
    pub encrypted_secret_key: String,
    #[serde(default)]
    pub encrypted_profile: String,
    pub key_version: i32,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PresignUploadRequest {
    pub size: i64,
    #[serde(rename = "contentMD5")]
    pub content_md5: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub purpose: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PresignUploadResponse {
    pub url: String,
    pub method: String,
    pub headers: std::collections::BTreeMap<String, String>,
    pub object_key: String,
    pub expires_in: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AssetDownloadResponse {
    pub url: String,
    pub expires_in: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct PostObjectPayload {
    pub object_key: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub size: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub position: Option<i32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub metadata_cipher: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CreatePostRequest {
    pub encrypted_post_key: String,
    pub key_version: i32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub caption_cipher: Option<String>,
    pub objects: Vec<PostObjectPayload>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreatePostResponse {
    pub post_id: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LikePostResponse {
    pub liked: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpaceUnreadStatusResponse {
    pub notifications_unread: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LikeMessageResponse {
    pub liked: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateMessageRequest {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message_id: Option<String>,
    pub message_cipher: String,
    pub sender_encrypted_message_key: String,
    pub recipient_encrypted_message_key: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reply_message_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MessageResponse {
    pub message_id: String,
    pub kind: String,
    pub sender_space_id: String,
    pub recipient_space_id: String,
    #[serde(default)]
    pub message_cipher: String,
    #[serde(default)]
    pub encrypted_message_key: String,
    #[serde(default)]
    pub text: String,
    #[serde(default)]
    pub reply_post_id: Option<i64>,
    #[serde(default)]
    pub reply_message_id: Option<String>,
    #[serde(default)]
    pub liked: bool,
    #[serde(default)]
    pub viewer_liked: bool,
    #[serde(default)]
    pub is_deleted: bool,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MessagePage {
    pub items: Vec<MessageResponse>,
    #[serde(default)]
    pub next_cursor: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MessageConversationActivity {
    pub id: String,
    #[serde(rename = "type")]
    pub activity_type: String,
    #[serde(default)]
    pub kind: String,
    pub created_at: String,
    #[serde(default)]
    pub outgoing: bool,
    #[serde(default)]
    pub message_id: Option<String>,
    #[serde(default)]
    pub sender_space_id: String,
    #[serde(default)]
    pub recipient_space_id: String,
    #[serde(default)]
    pub message_cipher: String,
    #[serde(default)]
    pub encrypted_message_key: String,
    #[serde(default)]
    pub reply_message_id: Option<String>,
    #[serde(default)]
    pub post_id: Option<i64>,
    #[serde(default)]
    pub post_space_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConversationChatSummaryResponse {
    pub latest_activity: MessageConversationActivity,
    #[serde(default)]
    pub unread_activities: Vec<MessageConversationActivity>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConversationsResponse {
    pub friends: Vec<SpaceFriendResponse>,
    #[serde(default)]
    pub pending_requests: Vec<SpaceFriendRequestResponse>,
    #[serde(default)]
    pub chat_summaries: std::collections::BTreeMap<String, ConversationChatSummaryResponse>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdatePostCaptionRequest {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub caption_cipher: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PostResponse {
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

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PostPage {
    pub items: Vec<PostResponse>,
    #[serde(default)]
    pub next_cursor: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct SpaceActorResponse {
    #[serde(default)]
    pub space_id: String,
    pub space_slug: String,
    #[serde(default)]
    pub public_key: String,
    #[serde(default)]
    pub key_version: i32,
    #[serde(default)]
    pub encrypted_profile: String,
    #[serde(default)]
    pub avatar: Option<ProfileAvatarResponse>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ProfileAvatarPayload {
    #[serde(rename = "objectID")]
    pub object_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub size: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ProfileAvatarResponse {
    #[serde(rename = "objectID")]
    pub object_id: String,
    pub key_version: i32,
    #[serde(default)]
    pub size: i64,
    #[serde(default)]
    pub updated_at: String,
}

pub type ProfileCoverPayload = ProfileAvatarPayload;
pub type ProfileCoverResponse = ProfileAvatarResponse;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateSpaceProfileRequest {
    pub key_version: i32,
    pub encrypted_profile: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub avatar: Option<ProfileAvatarPayload>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cover: Option<ProfileCoverPayload>,
    #[serde(skip_serializing_if = "is_false")]
    pub remove_avatar: bool,
    #[serde(skip_serializing_if = "is_false")]
    pub remove_cover: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateSpaceProfileResponse {
    pub status: String,
    #[serde(default)]
    pub avatar: Option<ProfileAvatarResponse>,
    #[serde(default)]
    pub cover: Option<ProfileCoverResponse>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpaceProfileResponse {
    pub space_id: String,
    pub space_slug: String,
    pub version: i32,
    #[serde(default)]
    pub friends: i64,
    #[serde(default)]
    pub encrypted_profile: String,
    #[serde(default)]
    pub updated_at: String,
    #[serde(default)]
    pub avatar: Option<ProfileAvatarResponse>,
    #[serde(default)]
    pub cover: Option<ProfileCoverResponse>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RotateSpaceKeyRequest {
    pub root_wrapped_space_key: String,
    pub key_version: i32,
    pub wrapped_prev_key: String,
    pub encrypted_profile: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpaceKeyVersionResponse {
    pub version: i32,
    #[serde(default)]
    pub wrapped_prev_key: String,
    pub created_at: String,
}

#[cfg(test)]
mod tests {
    use super::{
        AssetDownloadResponse, ConversationsResponse, MessageConversationActivity,
        ProfileAvatarPayload, ProfileCoverPayload, SpaceProfileResponse, UpdateSpaceProfileRequest,
    };

    #[test]
    fn asset_download_response_deserializes_camel_case() {
        let response: AssetDownloadResponse =
            serde_json::from_str(r#"{"url":"http://127.0.0.1:3900/example","expiresIn":900}"#)
                .expect("asset download response should deserialize");
        assert_eq!(response.url, "http://127.0.0.1:3900/example");
        assert_eq!(response.expires_in, 900);
    }

    #[test]
    fn message_conversation_activity_deserializes_outgoing() {
        let activity: MessageConversationActivity = serde_json::from_str(
            r#"{"id":"message:example","type":"message","kind":"regular","createdAt":"2026-05-25T00:00:00Z","outgoing":true,"messageId":"message-1","senderSpaceId":"space-a","recipientSpaceId":"space-b","messageCipher":"cipher","encryptedMessageKey":"key","replyMessageId":"parent-1"}"#,
        )
        .expect("activity should deserialize");
        assert!(activity.outgoing);
        assert_eq!(activity.kind, "regular");
        assert_eq!(activity.message_id.as_deref(), Some("message-1"));
        assert_eq!(activity.sender_space_id, "space-a");
        assert_eq!(activity.recipient_space_id, "space-b");
        assert_eq!(activity.message_cipher, "cipher");
        assert_eq!(activity.encrypted_message_key, "key");
        assert_eq!(activity.reply_message_id.as_deref(), Some("parent-1"));
    }

    #[test]
    fn profile_asset_payloads_serialize_object_id_for_avatar_and_cover() {
        let request = UpdateSpaceProfileRequest {
            key_version: 3,
            encrypted_profile: "encrypted-profile".to_owned(),
            avatar: Some(ProfileAvatarPayload {
                object_id: "avatar-object".to_owned(),
                size: Some(123),
            }),
            cover: Some(ProfileCoverPayload {
                object_id: "cover-object".to_owned(),
                size: Some(456),
            }),
            remove_avatar: false,
            remove_cover: false,
        };

        let value = serde_json::to_value(&request).expect("profile request should serialize");

        assert_eq!(value["avatar"]["objectID"], "avatar-object");
        assert_eq!(value["cover"]["objectID"], "cover-object");
        assert!(value["avatar"].get("objectId").is_none());
        assert!(value["cover"].get("objectId").is_none());
    }

    #[test]
    fn profile_asset_responses_deserialize_object_id_for_avatar_and_cover() {
        let response: SpaceProfileResponse = serde_json::from_str(
            r#"{
                "spaceId":"space_owner_main",
                "spaceSlug":"owner-main",
                "version":3,
                "avatar":{"objectID":"avatar-object","keyVersion":2,"size":123,"updatedAt":"2026-04-16T00:00:00Z"},
                "cover":{"objectID":"cover-object","keyVersion":3,"size":456,"updatedAt":"2026-04-17T00:00:00Z"}
            }"#,
        )
        .expect("profile response should deserialize");

        assert_eq!(
            response
                .avatar
                .as_ref()
                .map(|avatar| avatar.object_id.as_str()),
            Some("avatar-object")
        );
        assert_eq!(
            response
                .cover
                .as_ref()
                .map(|cover| cover.object_id.as_str()),
            Some("cover-object")
        );
        assert_eq!(
            response.avatar.as_ref().map(|avatar| avatar.key_version),
            Some(2)
        );
        assert_eq!(
            response.cover.as_ref().map(|cover| cover.key_version),
            Some(3)
        );
    }

    #[test]
    fn conversations_response_deserializes_thin_activity() {
        let response: ConversationsResponse = serde_json::from_str(
            r#"{
                "friends":[{"friend":{"spaceId":"space_friend","spaceSlug":"friend-main"},"createdAt":"2026-05-25T00:00:00Z"}],
                "pendingRequests":[],
                "chatSummaries":{
                    "space_friend":{
                        "latestActivity":{
                        "id":"message:msg_1",
                        "type":"message",
                        "createdAt":"2026-05-25T00:00:00Z",
                        "messageId":"msg_1"
                        }
                    }
                }
            }"#,
        )
        .expect("conversations response should deserialize");

        let friend = &response.friends[0];
        assert_eq!(friend.friend.space_slug, "friend-main");
        let activity = &response.chat_summaries["space_friend"].latest_activity;
        assert_eq!(activity.message_id.as_deref(), Some("msg_1"));
        assert_eq!(activity.post_id, None);
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AddFriendPayload {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub target_space_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub target_username: Option<String>,
    pub requester_friend_sealed_space_key: String,
    pub requester_key_version: i32,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ConfirmFriendRequestPayload {
    pub target_friend_sealed_space_key: String,
    pub target_key_version: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FriendStatusResponse {
    pub status: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FriendRelationshipResponse {
    pub relationship: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FriendTargetPayload {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub target_username: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub target_space_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpaceFriendResponse {
    pub friend: SpaceActorResponse,
    #[serde(default)]
    pub share_key_version: i32,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpaceFriendRequestResponse {
    pub request_id: i64,
    pub requester: SpaceActorResponse,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ShareUpdatePayload {
    pub friend_space_id: String,
    pub friend_sealed_space_key: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RefreshFriendSharesRequest {
    pub key_version: i32,
    pub shares: Vec<ShareUpdatePayload>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FriendShareResponse {
    pub friend: String,
    pub space_id: String,
    pub space_slug: String,
    pub friend_sealed_space_key: String,
    pub key_version: i32,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateSpaceSlugRequest {
    pub space_slug: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpaceLookupResponse {
    pub space_id: String,
    pub space_slug: String,
    pub owner: String,
    #[serde(default)]
    pub public_key: String,
}
