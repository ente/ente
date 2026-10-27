use super::{AccountSpaceCtx, retain_content_error};
use crate::crypto::{decrypt_secretbox_payload, encrypt_secretbox_payload};
use crate::error::{Error, Result};
use crate::models::{Comment, CommentPage, CommentReaction, SpaceActor};
use crate::transport::CommentPageResponse;
use ente_core::{b64, crypto::SecretVec};
use serde::{Deserialize, Serialize};

const REACTION_PAYLOAD_BYTES: usize = 256;

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DiscussionPayload {
    kind: String,
    post_id: i64,
    comment_id: String,
    author_space_id: String,
    reply_to_id: String,
    text: String,
}

fn encrypt_contribution(key: &[u8], payload: &DiscussionPayload) -> Result<String> {
    let mut bytes =
        serde_json::to_vec(payload).map_err(|_| Error::InvalidInput("invalid comment".into()))?;
    if payload.kind == "reaction" {
        if bytes.len() > REACTION_PAYLOAD_BYTES {
            return Err(Error::InvalidInput("reaction is too large".into()));
        }
        bytes.resize(REACTION_PAYLOAD_BYTES, b' ');
    }
    Ok(b64::encode(&encrypt_secretbox_payload(key, &bytes)?))
}

fn decrypt_contribution(key: &[u8], cipher: &str, expected: &DiscussionPayload) -> Result<String> {
    let plaintext = decrypt_secretbox_payload(key, &b64::decode(cipher)?)?;
    if expected.kind == "reaction" && plaintext.len() != REACTION_PAYLOAD_BYTES {
        return Err(Error::InvalidInput("invalid reaction size".into()));
    }
    let payload: DiscussionPayload = serde_json::from_slice(&plaintext)
        .map_err(|_| Error::InvalidInput("invalid comment".into()))?;
    if payload.kind != expected.kind
        || payload.post_id != expected.post_id
        || payload.comment_id != expected.comment_id
        || payload.author_space_id != expected.author_space_id
        || payload.reply_to_id != expected.reply_to_id
    {
        return Err(Error::InvalidInput("discussion context mismatch".into()));
    }
    validate_contribution(&payload.kind, &payload.text)?;
    Ok(payload.text)
}

fn validate_contribution(kind: &str, text: &str) -> Result<()> {
    if kind == "reaction" {
        return super::reactions::validate_emoji(text);
    }
    if text.trim().is_empty()
        || text.chars().count() > super::MAX_SPACE_MESSAGE_TEXT_CHARS
        || text.len() > super::MAX_SPACE_MESSAGE_TEXT_BYTES
    {
        return Err(Error::InvalidInput("comment is empty or too long".into()));
    }
    Ok(())
}

fn validate_comment_id(comment_id: &str) -> Result<()> {
    if comment_id.is_empty()
        || comment_id.len() > 64
        || !comment_id
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-' || byte == b'_')
    {
        return Err(Error::InvalidInput("invalid comment ID".into()));
    }
    Ok(())
}

fn comment_path(viewer: &str, post_id: i64, comment_id: &str) -> Result<String> {
    validate_comment_id(comment_id)?;
    Ok(format!(
        "/spaces/{}/discussions/{post_id}/comments/{}",
        urlencoding::encode(viewer),
        urlencoding::encode(comment_id)
    ))
}

impl AccountSpaceCtx {
    async fn comment_post_key(
        &self,
        viewer: &str,
        post_space_id: &str,
        post_id: i64,
    ) -> Result<SecretVec> {
        let post = self
            .get_post_raw(post_space_id, post_id, Some(viewer))
            .await?;
        Ok(SecretVec::new(
            self.decrypt_post_key_fields(
                &post.space_id,
                Some(viewer),
                &post.encrypted_post_key,
                post.key_version,
            )
            .await?,
        ))
    }

    pub async fn list_comments(
        &self,
        viewer: &str,
        post_space_id: &str,
        post_id: i64,
        cursor: Option<&str>,
    ) -> Result<CommentPage> {
        let path = format!(
            "/spaces/{}/discussions/{post_id}/comments",
            urlencoding::encode(viewer)
        );
        let query = cursor
            .map(|cursor| vec![("cursor", cursor)])
            .unwrap_or_default();
        let page: CommentPageResponse = self
            .api()
            .get(&path)
            .query(&query)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        let key = self
            .comment_post_key(viewer, post_space_id, post_id)
            .await?;
        let mut items = Vec::new();
        for comment in page.items {
            let deleted = comment.cipher.is_empty() || comment.author.is_none();
            let text = if let Some(author) = comment.author.as_ref().filter(|_| !deleted) {
                let expected = DiscussionPayload {
                    kind: "comment".into(),
                    post_id,
                    comment_id: comment.comment_id.clone(),
                    author_space_id: author.space_id.clone(),
                    reply_to_id: comment.reply_to_id.clone(),
                    text: String::new(),
                };
                retain_content_error(decrypt_contribution(&key, &comment.cipher, &expected))?.ok()
            } else {
                None
            };
            let mut reactions = Vec::new();
            for reaction in comment.reactions {
                let expected = DiscussionPayload {
                    kind: "reaction".into(),
                    post_id,
                    comment_id: comment.comment_id.clone(),
                    author_space_id: reaction.actor.space_id.clone(),
                    reply_to_id: String::new(),
                    text: String::new(),
                };
                if let Ok(emoji) =
                    retain_content_error(decrypt_contribution(&key, &reaction.cipher, &expected))?
                {
                    let profile =
                        retain_content_error(self.decrypt_actor_profile(&reaction.actor).await)?;
                    reactions.push(CommentReaction {
                        actor: SpaceActor::from_response(reaction.actor, profile),
                        emoji,
                        is_own: reaction.is_own,
                    });
                }
            }
            let author = if let Some(author) = comment.author {
                let profile = retain_content_error(self.decrypt_actor_profile(&author).await)?;
                Some(SpaceActor::from_response(author, profile))
            } else {
                None
            };
            items.push(Comment {
                comment_id: comment.comment_id,
                unread_notification_ids: comment.unread_notification_ids,
                author,
                parent_id: comment.parent_id,
                reply_to_id: comment.reply_to_id,
                text,
                deleted,
                created_at: comment.created_at,
                can_delete: comment.can_delete,
                reactions,
            });
        }
        Ok(CommentPage {
            items,
            next_cursor: page.next_cursor,
        })
    }

    pub async fn create_comment(
        &self,
        viewer: &str,
        post_space_id: &str,
        post_id: i64,
        comment_id: &str,
        reply_to_id: Option<&str>,
        text: &str,
    ) -> Result<()> {
        validate_comment_id(comment_id)?;
        let reply_to_id = reply_to_id.unwrap_or_default();
        if !reply_to_id.is_empty() {
            validate_comment_id(reply_to_id)?;
        }
        validate_contribution("comment", text)?;
        let key = self
            .comment_post_key(viewer, post_space_id, post_id)
            .await?;
        let payload = DiscussionPayload {
            kind: "comment".into(),
            post_id,
            comment_id: comment_id.into(),
            author_space_id: viewer.into(),
            reply_to_id: reply_to_id.into(),
            text: text.into(),
        };
        self.api().post(&format!("/spaces/{}/discussions/{post_id}/comments", urlencoding::encode(viewer)))
            .json(&serde_json::json!({"commentId":comment_id, "replyToId":reply_to_id, "cipher":encrypt_contribution(&key, &payload)?}))
            .send().await?.error_for_status()?;
        Ok(())
    }

    pub async fn delete_comment(&self, viewer: &str, post_id: i64, comment_id: &str) -> Result<()> {
        self.api()
            .delete(&comment_path(viewer, post_id, comment_id)?)
            .send()
            .await?
            .error_for_status()?;
        Ok(())
    }

    pub async fn remove_comment_reaction(
        &self,
        viewer: &str,
        post_id: i64,
        comment_id: &str,
        actor_space_id: &str,
    ) -> Result<()> {
        self.api()
            .delete(&format!(
                "{}/reaction",
                comment_path(viewer, post_id, comment_id)?
            ))
            .query(&[("actorSpaceId", actor_space_id)])
            .send()
            .await?
            .error_for_status()?;
        Ok(())
    }

    pub async fn set_comment_reaction(
        &self,
        viewer: &str,
        post_space_id: &str,
        post_id: i64,
        comment_id: &str,
        emoji: Option<&str>,
    ) -> Result<()> {
        let path = format!("{}/reaction", comment_path(viewer, post_id, comment_id)?);
        let Some(emoji) = emoji else {
            self.api().delete(&path).send().await?.error_for_status()?;
            return Ok(());
        };
        validate_contribution("reaction", emoji)?;
        let key = self
            .comment_post_key(viewer, post_space_id, post_id)
            .await?;
        let payload = DiscussionPayload {
            kind: "reaction".into(),
            post_id,
            comment_id: comment_id.into(),
            author_space_id: viewer.into(),
            reply_to_id: String::new(),
            text: emoji.into(),
        };
        self.api()
            .put(&path)
            .json(&serde_json::json!({"cipher":encrypt_contribution(&key, &payload)?}))
            .send()
            .await?
            .error_for_status()?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::client::test_support::test_account_ctx;
    use crate::crypto::generate_key;
    use mockito::Matcher;

    #[tokio::test]
    async fn unsafe_comment_ids_never_send_requests() {
        let mut server = mockito::Server::new_async().await;
        let ctx = test_account_ctx(&server.url());
        let requests = server
            .mock("DELETE", Matcher::Any)
            .expect(0)
            .create_async()
            .await;
        let reads = server
            .mock("GET", Matcher::Any)
            .expect(0)
            .create_async()
            .await;
        let creates = server
            .mock("POST", Matcher::Any)
            .expect(0)
            .create_async()
            .await;
        let updates = server
            .mock("PUT", Matcher::Any)
            .expect(0)
            .create_async()
            .await;
        for id in [
            "../../../posts/42",
            r"..\..\..\posts\42",
            ".",
            "..",
            "",
            "%2e%2e%2fposts%2f42",
            "%252e%252e%252fposts%252f42",
            "comment/child",
            "comment?query=1",
            "comment#fragment",
            " comment",
            "comment ",
            "comment\n",
            "comment\0",
            "cömment",
            &"a".repeat(65),
        ] {
            assert!(
                matches!(
                    ctx.delete_comment("owner", 42, id).await,
                    Err(Error::InvalidInput(_))
                ),
                "{id}"
            );
            assert!(
                matches!(
                    ctx.remove_comment_reaction("owner", 42, id, "actor").await,
                    Err(Error::InvalidInput(_))
                ),
                "{id}"
            );
            for emoji in [None, Some("❤️")] {
                assert!(
                    matches!(
                        ctx.set_comment_reaction("owner", "owner", 42, id, emoji)
                            .await,
                        Err(Error::InvalidInput(_))
                    ),
                    "{id}"
                );
            }
            assert!(
                matches!(
                    ctx.create_comment("owner", "owner", 42, id, None, "Hello")
                        .await,
                    Err(Error::InvalidInput(_))
                ),
                "{id}"
            );
            if !id.is_empty() {
                assert!(
                    matches!(
                        ctx.create_comment("owner", "owner", 42, "comment-1", Some(id), "Hello")
                            .await,
                        Err(Error::InvalidInput(_))
                    ),
                    "{id}"
                );
            }
        }
        requests.assert_async().await;
        reads.assert_async().await;
        creates.assert_async().await;
        updates.assert_async().await;
    }

    #[tokio::test]
    async fn comment_deletion_and_reaction_removal_use_only_comment_routes() {
        let mut server = mockito::Server::new_async().await;
        let ctx = test_account_ctx(&server.url());
        let post_delete = server
            .mock("DELETE", "/spaces/space_owner_main/posts/42")
            .expect(0)
            .create_async()
            .await;
        for id in [
            "5249f283-aaf2-4e6d-96c0-091f04b72f90",
            "comment-y",
            "wcomment_123",
            &"a".repeat(64),
        ] {
            let path = format!("/spaces/space_owner_main/discussions/42/comments/{id}");
            let delete = server
                .mock("DELETE", path.as_str())
                .match_header("x-space-session-token", "space-session-token")
                .with_status(200)
                .create_async()
                .await;
            ctx.delete_comment("space_owner_main", 42, id)
                .await
                .unwrap();
            delete.assert_async().await;
            let reaction_path = format!("{path}/reaction");
            let remove_own = server
                .mock("DELETE", reaction_path.as_str())
                .with_status(200)
                .create_async()
                .await;
            ctx.set_comment_reaction("space_owner_main", "space_owner_main", 42, id, None)
                .await
                .unwrap();
            remove_own.assert_async().await;
            let remove_other = server
                .mock("DELETE", reaction_path.as_str())
                .match_query(Matcher::UrlEncoded(
                    "actorSpaceId".into(),
                    "other?actor#id".into(),
                ))
                .with_status(200)
                .create_async()
                .await;
            ctx.remove_comment_reaction("space_owner_main", 42, id, "other?actor#id")
                .await
                .unwrap();
            remove_other.assert_async().await;
        }
        post_delete.assert_async().await;
    }

    #[tokio::test]
    async fn comment_paths_encode_space_id_segments() {
        let mut server = mockito::Server::new_async().await;
        let ctx = test_account_ctx(&server.url());
        let delete = server
            .mock(
                "DELETE",
                "/spaces/owner%2Fother%3Fquery%23fragment/discussions/42/comments/comment-1",
            )
            .with_status(200)
            .create_async()
            .await;
        ctx.delete_comment("owner/other?query#fragment", 42, "comment-1")
            .await
            .unwrap();
        delete.assert_async().await;
    }

    #[test]
    fn contributions_use_the_post_key_without_unlocking_other_content() {
        let post_key = generate_key();
        let other_post_key = generate_key();
        let profile_key = generate_key();
        let payload = DiscussionPayload {
            kind: "comment".into(),
            post_id: 42,
            comment_id: "comment-y".into(),
            author_space_id: "y".into(),
            reply_to_id: String::new(),
            text: "Hello Z".into(),
        };
        let cipher = encrypt_contribution(&post_key, &payload).unwrap();
        assert_eq!(
            decrypt_secretbox_payload(&post_key, &b64::decode(&cipher).unwrap()).unwrap(),
            serde_json::to_vec(&payload).unwrap()
        );
        assert_eq!(
            decrypt_contribution(&post_key, &cipher, &payload).unwrap(),
            "Hello Z"
        );
        assert!(decrypt_contribution(&other_post_key, &cipher, &payload).is_err());
        assert!(decrypt_contribution(&profile_key, &cipher, &payload).is_err());
        let private_profile = encrypt_secretbox_payload(&profile_key, b"private profile").unwrap();
        assert!(decrypt_secretbox_payload(&post_key, &private_profile).is_err());
    }

    #[test]
    fn comment_reactions_are_padded_and_round_trip() {
        let key = generate_key();
        for emoji in ["👍", "❤️", "👍🏽", "👨‍👩‍👧‍👦", "🇮🇳", "1️⃣", "🏳️‍⚧️", "🧑🏿‍💻"]
        {
            let payload = DiscussionPayload {
                kind: "reaction".into(),
                post_id: i64::MAX,
                comment_id: "a".repeat(64),
                author_space_id: format!("space_{}", "a".repeat(22)),
                reply_to_id: String::new(),
                text: emoji.into(),
            };
            let cipher = encrypt_contribution(&key, &payload).unwrap();
            assert_eq!(b64::decode(&cipher).unwrap().len(), 296, "{emoji}");
            assert_eq!(
                decrypt_contribution(&key, &cipher, &payload).unwrap(),
                emoji
            );
        }
    }

    #[test]
    fn comment_reactions_reject_invalid_payload_sizes() {
        let key = generate_key();
        let mut payload = DiscussionPayload {
            kind: "reaction".into(),
            post_id: i64::MAX,
            comment_id: "a".repeat(64),
            author_space_id: format!("space_{}", "a".repeat(22)),
            reply_to_id: String::new(),
            text: "❤️".into(),
        };
        let bytes = serde_json::to_vec(&payload).unwrap();
        for size in [bytes.len(), 255, 257] {
            let mut plaintext = bytes.clone();
            plaintext.resize(size, b' ');
            let cipher = b64::encode(&encrypt_secretbox_payload(&key, &plaintext).unwrap());
            assert!(matches!(
                decrypt_contribution(&key, &cipher, &payload),
                Err(Error::InvalidInput(message)) if message == "invalid reaction size"
            ));
        }
        payload.text = "👨\u{200d}".repeat(8) + "👨";
        validate_contribution("reaction", &payload.text).unwrap();
        assert!(matches!(
            encrypt_contribution(&key, &payload),
            Err(Error::InvalidInput(message)) if message == "reaction is too large"
        ));
        payload.kind = "comment".into();
        let cipher = encrypt_contribution(&key, &payload).unwrap();
        assert_eq!(
            decrypt_contribution(&key, &cipher, &payload).unwrap(),
            payload.text
        );
    }

    #[test]
    fn encrypted_contributions_bind_post_author_target_and_kind() {
        let key = generate_key();
        let mut payload = DiscussionPayload {
            kind: "reaction".into(),
            post_id: 42,
            comment_id: "reply-z".into(),
            author_space_id: "y".into(),
            reply_to_id: String::new(),
            text: "❤️".into(),
        };
        let cipher = encrypt_contribution(&key, &payload).unwrap();
        assert_eq!(decrypt_contribution(&key, &cipher, &payload).unwrap(), "❤️");
        payload.post_id = 43;
        assert!(decrypt_contribution(&key, &cipher, &payload).is_err());
        payload.post_id = 42;
        payload.author_space_id = "z".into();
        assert!(decrypt_contribution(&key, &cipher, &payload).is_err());
        payload.author_space_id = "y".into();
        payload.comment_id = "other".into();
        assert!(decrypt_contribution(&key, &cipher, &payload).is_err());
        payload.comment_id = "reply-z".into();
        payload.reply_to_id = "another".into();
        assert!(decrypt_contribution(&key, &cipher, &payload).is_err());
        payload.reply_to_id.clear();
        payload.kind = "comment".into();
        assert!(decrypt_contribution(&key, &cipher, &payload).is_err());
        assert!(validate_contribution("reaction", "hello").is_err());
        assert!(validate_contribution("comment", " ").is_err());
    }
}
