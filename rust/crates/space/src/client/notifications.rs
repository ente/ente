use super::{AccountSpaceCtx, retain_content_error};
use crate::error::Result;
use crate::models::{Notification, NotificationPage, SpaceActor};
use crate::transport::{NotificationPageResponse, NotificationUnreadResponse};

impl AccountSpaceCtx {
    pub async fn list_notifications(
        &self,
        space_id: &str,
        cursor: Option<String>,
        limit: Option<i32>,
    ) -> Result<NotificationPage> {
        let mut query = Vec::new();
        if let Some(value) = cursor.filter(|value| !value.is_empty()) {
            query.push(("cursor", value));
        }
        if let Some(value) = limit {
            query.push(("limit", value.to_string()));
        }
        let path = format!("/spaces/{space_id}/notifications");
        let page: NotificationPageResponse = self
            .api()
            .get(&path)
            .query(&query)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        if page.items.iter().any(|item| item.kind != "friend_request") {
            let shares = self.list_decrypted_friend_shares_cached(space_id).await?;
            if page
                .items
                .iter()
                .flat_map(|item| &item.actors)
                .any(|actor| {
                    !actor.encrypted_profile.is_empty()
                        && !shares.iter().any(|share| share.space_id == actor.space_id)
                })
            {
                self.clear_friend_share_cache()?;
                self.list_decrypted_friend_shares_cached(space_id).await?;
            }
        }
        let mut items = Vec::with_capacity(page.items.len());
        for item in page.items {
            let mut actors = Vec::with_capacity(item.actors.len());
            for actor in item.actors {
                let profile = retain_content_error(self.decrypt_actor_profile(&actor).await)?;
                actors.push(SpaceActor::from_response(actor, profile));
            }
            items.push(Notification {
                notification_id: item.notification_id,
                notification_ids: item.notification_ids,
                kind: item.kind,
                actors,
                actor_count: item.actor_count,
                post_id: item.post_id,
                friend_request_id: item.friend_request_id,
                created_at: item.created_at,
                unread: item.unread,
            });
        }
        Ok(NotificationPage {
            latest_post_created_at: page.latest_post_created_at,
            items,
            next_cursor: page.next_cursor,
        })
    }

    pub async fn notifications_unread(&self, space_id: &str) -> Result<bool> {
        let path = format!("/spaces/{space_id}/notifications/unread");
        let response: NotificationUnreadResponse = self
            .api()
            .get(&path)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        Ok(response.unread)
    }

    pub async fn mark_notification_items_read(
        &self,
        space_id: &str,
        notification_ids: Vec<String>,
    ) -> Result<()> {
        let path = format!("/spaces/{space_id}/notifications/read");
        self.api()
            .post(&path)
            .json(&serde_json::json!({"notificationIds": notification_ids}))
            .send()
            .await?
            .error_for_status()?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use crate::client::test_support::test_account_ctx;
    use mockito::Matcher;
    use serde_json::json;

    #[tokio::test]
    async fn pending_request_notifications_do_not_require_friend_access() {
        let mut server = mockito::Server::new_async().await;
        let ctx = test_account_ctx(&server.url());
        let page = server.mock("GET", "/spaces/space_owner_main/notifications")
            .with_body(json!({"items":[{"notificationId":"request-1","notificationIds":["request-1"],"kind":"friend_request","actors":[{"spaceId":"requester","spaceSlug":"maya"}],"actorCount":1,"friendRequestId":7,"createdAt":"2026-10-07T10:00:00Z","unread":true}]}).to_string())
            .create_async().await;
        let notifications = ctx
            .list_notifications("space_owner_main", None, None)
            .await
            .unwrap();
        assert_eq!(notifications.items[0].friend_request_id, Some(7));
        assert_eq!(notifications.items[0].post_id, None);
        assert_eq!(notifications.items[0].actors[0].space_slug, "maya");
        page.assert_async().await;
    }

    #[tokio::test]
    async fn notification_feed_and_read_state_use_separate_endpoints() {
        let notification_ids: Vec<String> = (0..50).map(|i| format!("wnot_{i}")).collect();
        let mut server = mockito::Server::new_async().await;
        let ctx = test_account_ctx(&server.url());
        let page = server.mock("GET", "/spaces/space_owner_main/notifications")
            .match_query(Matcher::AllOf(vec![Matcher::UrlEncoded("cursor".into(), "1000:wnot_a".into()), Matcher::UrlEncoded("limit".into(), "20".into())]))
            .match_header("x-space-session-token", "space-session-token")
            .with_body(json!({"items": [{"notificationId":"wnot_49", "notificationIds":notification_ids, "kind":"post_like", "actors":[{"spaceId":"friend", "spaceSlug":"bob"},{"spaceId":"friend2", "spaceSlug":"maya"}], "actorCount":50, "unread":true, "postId":42, "createdAt":"2026-10-07T10:00:00Z"}]}).to_string())
            .create_async().await;
        let shares = server
            .mock("GET", "/spaces/space_owner_main/friends/shares")
            .with_body("[]")
            .create_async()
            .await;
        let unread = server
            .mock("GET", "/spaces/space_owner_main/notifications/unread")
            .with_body("{\"unread\":true}")
            .create_async()
            .await;
        let read = server
            .mock("POST", "/spaces/space_owner_main/notifications/read")
            .match_body(Matcher::Json(json!({"notificationIds":notification_ids})))
            .with_status(200)
            .create_async()
            .await;
        let notifications = ctx
            .list_notifications("space_owner_main", Some("1000:wnot_a".into()), Some(20))
            .await
            .unwrap();
        assert_eq!(notifications.items.len(), 1);
        assert_eq!(notifications.items[0].actors[0].space_slug, "bob");
        assert_eq!(notifications.items[0].post_id, Some(42));
        assert_eq!(notifications.items[0].actors[1].space_slug, "maya");
        assert_eq!(notifications.items[0].actors.len(), 2);
        assert_eq!(notifications.items[0].actor_count, 50);
        assert_eq!(notifications.items[0].notification_ids, notification_ids);
        assert!(notifications.items[0].unread);
        assert!(notifications.next_cursor.is_empty());
        assert!(ctx.notifications_unread("space_owner_main").await.unwrap());
        ctx.mark_notification_items_read(
            "space_owner_main",
            notifications.items[0].notification_ids.clone(),
        )
        .await
        .unwrap();
        page.assert_async().await;
        shares.assert_async().await;
        unread.assert_async().await;
        read.assert_async().await;
    }
}
