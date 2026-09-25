use super::{
    AccountSpaceCtx, MESSAGE_KIND_POKE, MESSAGE_KIND_POST_REPLY, MESSAGE_KIND_REGULAR,
    retain_content_error, validate_message_payload,
};
use crate::crypto::{
    decrypt_secretbox_payload, encrypt_secretbox_payload, generate_key, open_with_keypair,
    seal_with_public_key,
};
use crate::error::{Error, Result};
use crate::models::{
    ConversationChatSummary, Conversations, Message, MessageActivity, MessageContent, MessagePage,
    MessagePayload,
};
use crate::transport::{
    ConversationChatSummaryResponse, ConversationsResponse, CreateMessageRequest,
    LikeMessageResponse, MessageConversationActivity, MessagePageResponse, MessageResponse,
    SpaceActorResponse,
};
use ente_core::b64;

const MESSAGE_NOTIFICATION_KIND_POKE: &str = "poke";
const POKE_MESSAGE_TEXT: &str = "Poked";

impl AccountSpaceCtx {
    pub async fn list_conversations(&self, space_id: &str) -> Result<Conversations> {
        let path = format!("/spaces/{space_id}/conversations");
        let response: ConversationsResponse = self
            .api()
            .get(&path)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        let mut friends = Vec::with_capacity(response.friends.len());
        for friend in response.friends {
            friends.push(self.open_friend(friend).await?);
        }
        let mut chat_summaries = std::collections::BTreeMap::new();
        for (friend_space_id, summary) in response.chat_summaries {
            chat_summaries.insert(
                friend_space_id,
                self.open_conversation_summary(space_id, summary).await?,
            );
        }
        Ok(Conversations {
            friends,
            pending_requests: response
                .pending_requests
                .into_iter()
                .map(Into::into)
                .collect(),
            chat_summaries,
            latest_post_created_at: response.latest_post_created_at,
        })
    }

    pub async fn list_message_thread(
        &self,
        viewer_space_id: &str,
        space_id: &str,
        cursor: Option<String>,
        limit: Option<i32>,
    ) -> Result<MessagePage> {
        let mut query = Vec::new();
        if let Some(value) = cursor.filter(|value| !value.trim().is_empty()) {
            query.push(("cursor", value));
        }
        if let Some(value) = limit {
            query.push(("limit", value.to_string()));
        }
        let path = format!("/spaces/{viewer_space_id}/friends/{space_id}/messages");
        let page: MessagePageResponse = self
            .api()
            .get(&path)
            .query(&query)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        let mut items = Vec::with_capacity(page.items.len());
        for message in page.items {
            items.push(self.open_message(viewer_space_id, message).await?);
        }
        Ok(MessagePage {
            items,
            next_cursor: page.next_cursor,
        })
    }

    async fn open_message(
        &self,
        viewer_space_id: &str,
        message: MessageResponse,
    ) -> Result<Message> {
        let mut kind = message.kind.clone();
        let content = if message.is_deleted {
            Ok(None)
        } else if kind == "post_like" || kind == "friend_added" {
            Ok(Some(MessageContent {
                text: message.text.clone(),
                reply_object_key: None,
            }))
        } else {
            self.decrypt_message(viewer_space_id, &message)
                .await
                .map(|payload| {
                    kind = payload.kind;
                    Some(MessageContent {
                        text: payload.text,
                        reply_object_key: payload.reply_object_key,
                    })
                })
        };
        let content = retain_content_error(content)?;
        Ok(Message {
            message_id: message.message_id,
            kind,
            sender_space_id: message.sender_space_id,
            recipient_space_id: message.recipient_space_id,
            content,
            reply_post_id: message.reply_post_id,
            reply_message_id: message.reply_message_id,
            liked: message.liked,
            viewer_liked: message.viewer_liked,
            created_at: message.created_at,
            updated_at: message.updated_at,
        })
    }

    async fn open_sent_message(
        &self,
        space_id: &str,
        response: MessageResponse,
    ) -> Result<Message> {
        let message = self.open_message(space_id, response).await?;
        let content = message.content?;
        if content.is_none() {
            return Err(Error::InvalidInput("sent message is deleted".into()));
        }
        Ok(Message {
            content: Ok(content),
            ..message
        })
    }

    pub(super) async fn open_conversation_summary(
        &self,
        viewer_space_id: &str,
        summary: ConversationChatSummaryResponse,
    ) -> Result<ConversationChatSummary> {
        let mut unread_activities = Vec::with_capacity(summary.unread_activities.len());
        for activity in summary.unread_activities {
            unread_activities.push(
                self.open_message_activity(viewer_space_id, activity)
                    .await?,
            );
        }
        let latest_activity = self
            .open_message_activity(viewer_space_id, summary.latest_activity)
            .await?;
        for activity in &mut unread_activities {
            if activity.id == latest_activity.id && latest_activity.kind == MESSAGE_KIND_POKE {
                activity.kind = MESSAGE_KIND_POKE.to_owned();
            }
        }
        Ok(ConversationChatSummary {
            latest_activity,
            unread_activities,
        })
    }

    async fn open_message_activity(
        &self,
        viewer_space_id: &str,
        activity: MessageConversationActivity,
    ) -> Result<MessageActivity> {
        let mut kind = activity.kind.clone();
        let content = if activity.message_cipher.trim().is_empty()
            || activity.encrypted_message_key.trim().is_empty()
            || activity.message_id.is_none()
        {
            Ok(None)
        } else {
            let server_kind = if kind.trim().is_empty() {
                MESSAGE_KIND_REGULAR
            } else {
                &kind
            };
            self.decrypt_message_fields(
                viewer_space_id,
                server_kind,
                &activity.encrypted_message_key,
                &activity.message_cipher,
            )
            .await
            .map(|payload| {
                kind = payload.kind;
                Some(MessageContent {
                    text: payload.text,
                    reply_object_key: payload.reply_object_key,
                })
            })
        };
        let content = retain_content_error(content)?;
        Ok(MessageActivity {
            id: activity.id,
            activity_type: activity.activity_type,
            kind,
            created_at: activity.created_at,
            outgoing: activity.outgoing,
            message_id: activity.message_id,
            content,
            post_id: activity.post_id,
            post_space_id: activity.post_space_id,
        })
    }

    pub async fn send_message(
        &self,
        sender_space_id: &str,
        space_id: &str,
        text: &str,
    ) -> Result<Message> {
        self.send_direct_message(
            sender_space_id,
            space_id,
            MessagePayload {
                version: 1,
                kind: MESSAGE_KIND_REGULAR.to_owned(),
                text: text.to_owned(),
                reply_object_key: None,
            },
            None,
        )
        .await
    }

    pub async fn send_poke(&self, sender_space_id: &str, space_id: &str) -> Result<Message> {
        self.send_direct_message(
            sender_space_id,
            space_id,
            MessagePayload {
                version: 1,
                kind: MESSAGE_KIND_POKE.to_owned(),
                text: POKE_MESSAGE_TEXT.to_owned(),
                reply_object_key: None,
            },
            Some(MESSAGE_NOTIFICATION_KIND_POKE),
        )
        .await
    }

    async fn send_direct_message(
        &self,
        sender_space_id: &str,
        space_id: &str,
        payload: MessagePayload,
        notification_kind: Option<&str>,
    ) -> Result<Message> {
        let friend = self
            .friend_actor_for_space(sender_space_id, space_id)
            .await?;
        let request = self
            .message_request_for_payload(
                sender_space_id,
                &friend.public_key,
                &payload,
                None,
                notification_kind.map(str::to_owned),
            )
            .await?;
        let path = format!("/spaces/{sender_space_id}/friends/{space_id}/messages");
        let response = self
            .api()
            .post(&path)
            .json(&request)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        self.open_sent_message(sender_space_id, response).await
    }

    pub async fn reply_to_message(
        &self,
        sender_space_id: &str,
        space_id: &str,
        message_id: &str,
        text: &str,
    ) -> Result<Message> {
        let reply_message_id = message_id.trim();
        if reply_message_id.is_empty() {
            return Err(Error::InvalidInput("message id is required".into()));
        }
        let friend = self
            .friend_actor_for_space(sender_space_id, space_id)
            .await?;
        let payload = MessagePayload {
            version: 1,
            kind: MESSAGE_KIND_REGULAR.to_owned(),
            text: text.to_owned(),
            reply_object_key: None,
        };
        let request = self
            .message_request_for_payload(
                sender_space_id,
                &friend.public_key,
                &payload,
                Some(reply_message_id),
                None,
            )
            .await?;
        let path = format!("/spaces/{sender_space_id}/friends/{space_id}/messages");
        let response = self
            .api()
            .post(&path)
            .json(&request)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        self.open_sent_message(sender_space_id, response).await
    }

    pub async fn reply_to_post(
        &self,
        sender_space_id: &str,
        post_space_id: &str,
        post_id: i64,
        text: &str,
        object_key: Option<&str>,
    ) -> Result<Message> {
        let post = self
            .get_post_raw(post_space_id, post_id, Some(sender_space_id))
            .await?;
        if self
            .resolve_owned_space_access(&post.space_id)
            .await?
            .is_some()
        {
            return Err(Error::InvalidInput("cannot reply to your own post".into()));
        }
        if post.author.public_key.trim().is_empty() {
            return Err(Error::InvalidInput(
                "post author public key is missing".into(),
            ));
        }
        if let Some(object_key) = object_key
            && !post
                .objects
                .iter()
                .any(|object| object.object_key == object_key)
        {
            return Err(Error::InvalidInput("photo does not belong to post".into()));
        }
        let payload = MessagePayload {
            version: 1,
            kind: MESSAGE_KIND_POST_REPLY.to_owned(),
            text: text.to_owned(),
            reply_object_key: object_key.map(str::to_owned),
        };
        let request = self
            .message_request_for_payload(
                sender_space_id,
                &post.author.public_key,
                &payload,
                None,
                None,
            )
            .await?;
        let path = format!("/spaces/{sender_space_id}/posts/{post_id}/reply");
        let response = self
            .api()
            .post(&path)
            .json(&request)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        self.open_sent_message(sender_space_id, response).await
    }

    async fn decrypt_message(
        &self,
        space_id: &str,
        message: &MessageResponse,
    ) -> Result<MessagePayload> {
        if message.is_deleted {
            return Err(Error::InvalidInput("message is deleted".into()));
        }
        self.decrypt_message_fields(
            space_id,
            &message.kind,
            &message.encrypted_message_key,
            &message.message_cipher,
        )
        .await
    }

    async fn decrypt_message_fields(
        &self,
        space_id: &str,
        kind: &str,
        encrypted_message_key: &str,
        message_cipher: &str,
    ) -> Result<MessagePayload> {
        let identity = self.space_identity_for(space_id).await?;
        let sealed_key = b64::decode(encrypted_message_key)?;
        let message_key =
            open_with_keypair(&sealed_key, &identity.public_key, &identity.secret_key)?;
        let packed_message = b64::decode(message_cipher)?;
        let plaintext = decrypt_secretbox_payload(&message_key, &packed_message)?;
        let mut payload: MessagePayload = serde_json::from_slice(&plaintext)
            .map_err(|err| Error::InvalidInput(format!("invalid message payload: {err}")))?;
        if kind != MESSAGE_KIND_REGULAR || payload.kind != MESSAGE_KIND_POKE {
            payload.kind = kind.to_owned();
        }
        Ok(payload)
    }

    pub async fn like_message(
        &self,
        space_id: &str,
        message_id: &str,
        like: bool,
    ) -> Result<LikeMessageResponse> {
        let message_id = message_id.trim();
        if message_id.is_empty() {
            return Err(Error::InvalidInput("message id is required".into()));
        }
        let path = format!("/spaces/{space_id}/messages/{message_id}/like");
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

    pub async fn delete_message(&self, space_id: &str, message_id: &str) -> Result<()> {
        let message_id = message_id.trim();
        if message_id.is_empty() {
            return Err(Error::InvalidInput("message id is required".into()));
        }
        let path = format!("/spaces/{space_id}/messages/{message_id}");
        self.api().delete(&path).send().await?.error_for_status()?;
        Ok(())
    }

    pub(crate) async fn friend_actor_for_space(
        &self,
        sender_space_id: &str,
        space_id: &str,
    ) -> Result<SpaceActorResponse> {
        let friends = self.list_space_friends_raw(sender_space_id).await?;
        friends
            .into_iter()
            .map(|value| value.friend)
            .find(|friend| friend.space_id == space_id)
            .ok_or_else(|| Error::InvalidInput(format!("space {space_id} is not a friend")))
    }

    async fn message_request_for_payload(
        &self,
        sender_space_id: &str,
        recipient_public_key: &str,
        payload: &MessagePayload,
        reply_message_id: Option<&str>,
        notification_kind: Option<String>,
    ) -> Result<CreateMessageRequest> {
        let identity = self.space_identity_for(sender_space_id).await?;
        let recipient_public_key = b64::decode(recipient_public_key)?;
        let message_key = generate_key();
        let plaintext = serde_json::to_vec(payload)
            .map_err(|err| Error::InvalidInput(format!("invalid message payload: {err}")))?;
        validate_message_payload(payload, plaintext.len())?;
        let sender_key = seal_with_public_key(&message_key, &identity.public_key)?;
        let recipient_key = seal_with_public_key(&message_key, &recipient_public_key)?;
        Ok(CreateMessageRequest {
            message_id: None,
            message_cipher: b64::encode(&encrypt_secretbox_payload(&message_key, &plaintext)?),
            sender_encrypted_message_key: b64::encode(&sender_key),
            recipient_encrypted_message_key: b64::encode(&recipient_key),
            reply_message_id: reply_message_id.map(ToOwned::to_owned),
            notification_kind,
        })
    }
}
