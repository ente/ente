use super::AccountSpaceCtx;
use crate::crypto::{open_with_keypair, seal_with_public_key};
use crate::error::{Error, Result};
use ente_core::b64;
use serde::{Deserialize, Serialize};

const REACTION_PAYLOAD_BYTES: usize = 256;

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ReactionPayload {
    message_id: String,
    emoji: String,
}

impl AccountSpaceCtx {
    pub async fn set_message_reaction(
        &self,
        space_id: &str,
        sender_space_id: &str,
        message_id: &str,
        emoji: Option<&str>,
    ) -> Result<()> {
        if message_id.trim().is_empty() {
            return Err(Error::InvalidInput("message id is required".into()));
        }
        let path = format!("/spaces/{space_id}/messages/{message_id}/reaction");
        let Some(emoji) = emoji else {
            self.api().delete(&path).send().await?.error_for_status()?;
            return Ok(());
        };
        let payload = pack_reaction(message_id, emoji)?;
        let identity = self.space_identity_for(space_id).await?;
        let sender = self
            .friend_actor_for_space(space_id, sender_space_id)
            .await?;
        let sender_cipher = seal_with_public_key(&payload, &b64::decode(&sender.public_key)?)?;
        let recipient_cipher = seal_with_public_key(&payload, &identity.public_key)?;
        self.api()
            .put(&path)
            .json(&serde_json::json!({
                "senderEncryptedReaction": b64::encode(&sender_cipher),
                "recipientEncryptedReaction": b64::encode(&recipient_cipher),
            }))
            .send()
            .await?
            .error_for_status()?;
        Ok(())
    }

    pub(super) async fn open_message_reaction(
        &self,
        space_id: &str,
        message_id: &str,
        encrypted_reaction: &str,
        liked: bool,
    ) -> Result<Option<String>> {
        if encrypted_reaction.is_empty() {
            return Ok(liked.then(|| "❤️".to_owned()));
        }
        let identity = self.space_identity_for(space_id).await?;
        let plaintext = open_with_keypair(
            &b64::decode(encrypted_reaction)?,
            &identity.public_key,
            &identity.secret_key,
        )?;
        Ok(Some(unpack_reaction(message_id, &plaintext)?))
    }
}

fn pack_reaction(message_id: &str, emoji: &str) -> Result<Vec<u8>> {
    validate_emoji(emoji)?;
    let mut payload = serde_json::to_vec(&ReactionPayload {
        message_id: message_id.to_owned(),
        emoji: emoji.to_owned(),
    })
    .map_err(|_| Error::InvalidInput("invalid reaction".into()))?;
    if payload.len() > REACTION_PAYLOAD_BYTES {
        return Err(Error::InvalidInput("reaction is too large".into()));
    }
    payload.resize(REACTION_PAYLOAD_BYTES, b' ');
    Ok(payload)
}

fn unpack_reaction(message_id: &str, plaintext: &[u8]) -> Result<String> {
    if plaintext.len() != REACTION_PAYLOAD_BYTES {
        return Err(Error::InvalidInput("invalid reaction size".into()));
    }
    let payload: ReactionPayload = serde_json::from_slice(plaintext)
        .map_err(|_| Error::InvalidInput("invalid reaction".into()))?;
    if payload.message_id != message_id {
        return Err(Error::InvalidInput(
            "reaction belongs to another message".into(),
        ));
    }
    validate_emoji(&payload.emoji)?;
    Ok(payload.emoji)
}

fn validate_emoji(emoji: &str) -> Result<()> {
    if emoji.is_empty() || emoji.len() > 64 || !is_emoji_sequence(emoji) {
        return Err(Error::InvalidInput("a single emoji is required".into()));
    }
    Ok(())
}

fn is_emoji_sequence(emoji: &str) -> bool {
    let mut chars = emoji.chars().peekable();
    let Some(first) = chars.next() else {
        return false;
    };
    if ('\u{1f1e6}'..='\u{1f1ff}').contains(&first) {
        return chars
            .next()
            .is_some_and(|c| ('\u{1f1e6}'..='\u{1f1ff}').contains(&c))
            && chars.next().is_none();
    }
    if first.is_ascii_digit() || first == '#' || first == '*' {
        if chars.peek() == Some(&'\u{fe0f}') {
            chars.next();
        }
        return chars.next() == Some('\u{20e3}') && chars.next().is_none();
    }
    let mut base = first;
    loop {
        if !matches!(base as u32, 0xa9 | 0xae | 0x203c | 0x2049 | 0x2122 | 0x2139 | 0x2194..=0x21ff | 0x2300..=0x23ff | 0x25a0..=0x27bf | 0x2934..=0x2935 | 0x2b00..=0x2bff | 0x3030 | 0x303d | 0x3297 | 0x3299 | 0x1f000..=0x1faff)
            || matches!(base as u32, 0x1f1e6..=0x1f1ff | 0x1f3fb..=0x1f3ff)
        {
            return false;
        }
        if chars.peek() == Some(&'\u{fe0f}') {
            chars.next();
        }
        if chars
            .peek()
            .is_some_and(|c| ('\u{1f3fb}'..='\u{1f3ff}').contains(c))
        {
            chars.next();
        }
        match chars.next() {
            None => return true,
            Some('\u{200d}') => match chars.next() {
                Some(next) => base = next,
                None => return false,
            },
            _ => return false,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::generate_keypair;

    #[tokio::test]
    async fn reaction_endpoint_encrypts_for_both_participants_and_removes() {
        use super::super::test_support::{test_account_ctx, test_public_key};
        use mockito::Server;
        use serde_json::json;
        use std::sync::{Arc, Mutex};

        let mut server = Server::new_async().await;
        let recipient = test_account_ctx(&server.url());
        let sender = test_account_ctx(&server.url());
        let friends = server.mock("GET", "/spaces/space_owner_main/friends")
            .with_status(200)
            .with_body(json!([{
                "friend": { "spaceId": "space_friend", "spaceSlug": "friend", "publicKey": b64::encode(&test_public_key(&sender)), "keyVersion": 1 },
                "shareKeyVersion": 1, "createdAt": "2026-09-29T00:00:00Z"
            }]).to_string()).create_async().await;
        let captured = Arc::new(Mutex::new(serde_json::Value::Null));
        let captured_request = captured.clone();
        let put = server
            .mock(
                "PUT",
                "/spaces/space_owner_main/messages/wmsg_test/reaction",
            )
            .match_header("x-space-session-token", "space-session-token")
            .with_status(200)
            .with_body_from_request(move |request| {
                *captured_request.lock().unwrap() =
                    serde_json::from_slice(request.body().unwrap()).unwrap();
                b"{\"liked\":true}".to_vec()
            })
            .create_async()
            .await;
        recipient
            .set_message_reaction("space_owner_main", "space_friend", "wmsg_test", Some("👍🏽"))
            .await
            .unwrap();
        let body = captured.lock().unwrap().clone();
        for (ctx, field) in [
            (&sender, "senderEncryptedReaction"),
            (&recipient, "recipientEncryptedReaction"),
        ] {
            let cipher = body[field].as_str().unwrap();
            assert_eq!(b64::decode(cipher).unwrap().len(), 304);
            assert_eq!(
                ctx.open_message_reaction("space_owner_main", "wmsg_test", cipher, true)
                    .await
                    .unwrap()
                    .as_deref(),
                Some("👍🏽")
            );
        }
        assert_eq!(
            recipient
                .open_message_reaction("space_owner_main", "wmsg_test", "", true)
                .await
                .unwrap()
                .as_deref(),
            Some("❤️")
        );
        assert_eq!(
            recipient
                .open_message_reaction("space_owner_main", "wmsg_test", "", false)
                .await
                .unwrap(),
            None
        );
        let delete = server
            .mock(
                "DELETE",
                "/spaces/space_owner_main/messages/wmsg_test/reaction",
            )
            .match_header("x-space-session-token", "space-session-token")
            .with_status(200)
            .create_async()
            .await;
        recipient
            .set_message_reaction("space_owner_main", "space_friend", "wmsg_test", None)
            .await
            .unwrap();
        put.assert_async().await;
        delete.assert_async().await;
        friends.assert_async().await;
    }

    #[test]
    fn reaction_is_padded_and_readable_only_with_participant_key() {
        let (public, secret) = generate_keypair().unwrap();
        let (other_public, other_secret) = generate_keypair().unwrap();
        for emoji in ["❤️", "👍🏽", "👨‍👩‍👧‍👦", "🇮🇳", "1️⃣"] {
            let packed = pack_reaction("wmsg_test", emoji).unwrap();
            let cipher = seal_with_public_key(&packed, &public).unwrap();
            assert_eq!(cipher.len(), 304);
            assert!(open_with_keypair(&cipher, &other_public, &other_secret).is_err());
            let opened = open_with_keypair(&cipher, &public, &secret).unwrap();
            assert_eq!(unpack_reaction("wmsg_test", &opened).unwrap(), emoji);
            assert!(unpack_reaction("wmsg_other", &opened).is_err());
        }
    }

    #[test]
    fn reaction_rejects_text_multiple_emojis_and_incomplete_sequences() {
        for emoji in ["", "hello", "😀😀", "👍\u{200d}", "🏽", "🇮", "1", "\n"] {
            assert!(validate_emoji(emoji).is_err(), "{emoji:?}");
        }
    }
}
