//! Space direct messages.
//!
//! Messages are sealed to a per-message key that is in turn sealed to both the
//! sender's and recipient's Space identity public keys, so either party can
//! open them. These methods list conversations and threads, send and reply to
//! messages (including replies to a post), and decrypt, like, and delete them.

use super::{
    AccountSpaceCtx, MESSAGE_KIND_POST_REPLY, MESSAGE_KIND_REGULAR, validate_message_payload,
};
use crate::crypto::{
    decrypt_secretbox_payload, encrypt_secretbox_payload, generate_key, open_with_keypair,
    seal_with_public_key,
};
use crate::error::{Result, SpaceError};
use crate::models::{DecryptedMessage, MessagePayload};
use crate::transport::{
    ConversationsResponse, CreateMessageRequest, LikeMessageResponse, MessagePage, MessageResponse,
    SpaceActorResponse,
};
use ente_core::b64;

impl AccountSpaceCtx {
    pub async fn list_conversations(&self, space_id: &str) -> Result<ConversationsResponse> {
        let path = format!("/spaces/{space_id}/conversations");
        Ok(self
            .api()
            .get(&path)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?)
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

    pub async fn send_message(
        &self,
        sender_space_id: &str,
        space_id: &str,
        text: &str,
    ) -> Result<MessageResponse> {
        let friend = self
            .friend_actor_for_space(sender_space_id, space_id)
            .await?;
        let payload = MessagePayload {
            version: 1,
            kind: MESSAGE_KIND_REGULAR.to_owned(),
            text: text.to_owned(),
        };
        let request = self
            .message_request_for_payload(sender_space_id, &friend.public_key, &payload, None)
            .await?;
        let path = format!("/spaces/{sender_space_id}/friends/{space_id}/messages");
        Ok(self
            .api()
            .post(&path)
            .json(&request)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?)
    }

    pub async fn reply_to_message(
        &self,
        sender_space_id: &str,
        space_id: &str,
        message_id: &str,
        text: &str,
    ) -> Result<MessageResponse> {
        let reply_message_id = message_id.trim();
        if reply_message_id.is_empty() {
            return Err(SpaceError::InvalidInput("message id is required".into()));
        }
        let friend = self
            .friend_actor_for_space(sender_space_id, space_id)
            .await?;
        let payload = MessagePayload {
            version: 1,
            kind: MESSAGE_KIND_REGULAR.to_owned(),
            text: text.to_owned(),
        };
        let request = self
            .message_request_for_payload(
                sender_space_id,
                &friend.public_key,
                &payload,
                Some(reply_message_id),
            )
            .await?;
        let path = format!("/spaces/{sender_space_id}/friends/{space_id}/messages");
        Ok(self
            .api()
            .post(&path)
            .json(&request)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?)
    }

    pub async fn reply_to_post(
        &self,
        sender_space_id: &str,
        post_space_id: &str,
        post_id: i64,
        text: &str,
    ) -> Result<MessageResponse> {
        let post = self
            .get_post(post_space_id, post_id, Some(sender_space_id))
            .await?;
        if self
            .resolve_owned_space_access(&post.space_id)
            .await?
            .is_some()
        {
            return Err(SpaceError::InvalidInput(
                "cannot reply to your own post".into(),
            ));
        }
        if post.author.public_key.trim().is_empty() {
            return Err(SpaceError::InvalidInput(
                "post author public key is missing".into(),
            ));
        }
        let payload = MessagePayload {
            version: 1,
            kind: MESSAGE_KIND_POST_REPLY.to_owned(),
            text: text.to_owned(),
        };
        let request = self
            .message_request_for_payload(sender_space_id, &post.author.public_key, &payload, None)
            .await?;
        let path = format!("/spaces/{sender_space_id}/posts/{post_id}/reply");
        Ok(self
            .api()
            .post(&path)
            .json(&request)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?)
    }

    pub async fn decrypt_message(
        &self,
        space_id: &str,
        message: &MessageResponse,
    ) -> Result<DecryptedMessage> {
        if message.is_deleted {
            return Err(SpaceError::InvalidInput("message is deleted".into()));
        }
        let identity = self.space_identity_for(space_id).await?;
        let sealed_key = b64::decode(&message.encrypted_message_key)?;
        let message_key =
            open_with_keypair(&sealed_key, &identity.public_key, &identity.secret_key)?;
        let packed_message = b64::decode(&message.message_cipher)?;
        let plaintext = decrypt_secretbox_payload(&message_key, &packed_message)?;
        let payload: MessagePayload = serde_json::from_slice(&plaintext)
            .map_err(|err| SpaceError::InvalidInput(format!("invalid message payload: {err}")))?;
        Ok(DecryptedMessage {
            message_key,
            payload,
        })
    }

    pub async fn like_message(
        &self,
        space_id: &str,
        message_id: &str,
        like: bool,
    ) -> Result<LikeMessageResponse> {
        let message_id = message_id.trim();
        if message_id.is_empty() {
            return Err(SpaceError::InvalidInput("message id is required".into()));
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
            return Err(SpaceError::InvalidInput("message id is required".into()));
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
        let friends = self.list_space_friends(sender_space_id).await?;
        friends
            .into_iter()
            .map(|value| value.friend)
            .find(|friend| friend.space_id == space_id)
            .ok_or_else(|| SpaceError::InvalidInput(format!("space {space_id} is not a friend")))
    }

    async fn message_request_for_payload(
        &self,
        sender_space_id: &str,
        recipient_public_key: &str,
        payload: &MessagePayload,
        reply_message_id: Option<&str>,
    ) -> Result<CreateMessageRequest> {
        let identity = self.space_identity_for(sender_space_id).await?;
        let recipient_public_key = b64::decode(recipient_public_key)?;
        let message_key = generate_key();
        let plaintext = serde_json::to_vec(payload)
            .map_err(|err| SpaceError::InvalidInput(format!("invalid message payload: {err}")))?;
        validate_message_payload(payload, plaintext.len())?;
        let sender_key = seal_with_public_key(&message_key, &identity.public_key)?;
        let recipient_key = seal_with_public_key(&message_key, &recipient_public_key)?;
        Ok(CreateMessageRequest {
            message_id: None,
            message_cipher: b64::encode(&encrypt_secretbox_payload(&message_key, &plaintext)?),
            sender_encrypted_message_key: b64::encode(&sender_key),
            recipient_encrypted_message_key: b64::encode(&recipient_key),
            reply_message_id: reply_message_id.map(ToOwned::to_owned),
        })
    }
}
