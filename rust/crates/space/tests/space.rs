#![cfg(test)]
#![cfg(feature = "museum")]

mod support;

use ente_space::{AccountSpaceCtx, PostPhotoAssetOptions, PostPhotoInput};
use ente_test_support::{Museum, TestResult};

use crate::support::{auth, space};

const TEST_WEBP_BYTES: &[u8] = b"RIFF0000WEBP";

async fn request_and_confirm_friend(
    requester_ctx: &AccountSpaceCtx,
    requester_space_id: &str,
    target_ctx: &AccountSpaceCtx,
    target_space_id: &str,
    target_username: &str,
) {
    let status = requester_ctx
        .request_friend_by_username(requester_space_id, target_username)
        .await
        .expect("friend request should be sent");
    if status.status == "friend" {
        return;
    }
    assert_eq!(status.status, "requested");

    let requests = target_ctx
        .list_friend_requests(target_space_id)
        .await
        .expect("friend requests should load");
    let request = requests
        .iter()
        .find(|request| request.requester.space_id == requester_space_id)
        .expect("friend request should be visible to target");
    let pending = target_ctx
        .list_notifications(target_space_id, None, None)
        .await
        .expect("request notification should load");
    let notification = pending
        .items
        .iter()
        .find(|item| item.friend_request_id == Some(request.request_id))
        .expect("pending request should be in notifications");
    assert_eq!(notification.kind, "friend_request");
    let request_notification_id = notification.notification_id.clone();
    assert!(notification.actors[0].profile.as_ref().unwrap().is_none());
    assert!(notification.actors[0].avatar.is_none());
    assert!(
        requester_ctx
            .resolve_space_key_for_version_for_viewer(
                target_space_id,
                Some(requester_space_id),
                None
            )
            .await
            .unwrap()
            .is_none()
    );
    let confirmed = target_ctx
        .confirm_friend_request(target_space_id, request.request_id)
        .await
        .expect("friend request should confirm");
    assert_eq!(confirmed.status, "friend");
    let pending = target_ctx
        .list_notifications(target_space_id, None, None)
        .await
        .expect("notifications should refresh");
    assert!(
        !pending
            .items
            .iter()
            .any(|item| item.friend_request_id == Some(request.request_id))
    );
    let completed = pending
        .items
        .iter()
        .find(|item| item.notification_id == request_notification_id)
        .expect("accepted request should remain in the recipient's notifications");
    assert_eq!(completed.kind, "friend_accepted");
    assert_eq!(completed.actors[0].space_id, requester_space_id);
    assert!(!completed.unread);
    assert!(completed.actors[0].profile.as_ref().unwrap().is_some());
    let accepted = requester_ctx
        .list_notifications(requester_space_id, None, None)
        .await
        .expect("acceptance notification should load");
    let notification = accepted
        .items
        .iter()
        .find(|item| item.kind == "friend_accepted" && item.actors[0].space_id == target_space_id)
        .expect("requester should be notified of acceptance");
    assert!(notification.unread);
    assert!(notification.actors[0].profile.as_ref().unwrap().is_some());
    requester_ctx
        .mark_notification_items_read(requester_space_id, notification.notification_ids.clone())
        .await
        .expect("acceptance should be readable");
}

#[test]
fn space_e2e() -> TestResult {
    Museum::run(|museum| tokio::runtime::Runtime::new()?.block_on(run(museum)))
}

async fn run(museum: &Museum) -> TestResult {
    let endpoint = museum.endpoint();
    space_comments_suite(museum).await;
    space_bootstrap_posts_and_friend_share_suite(endpoint).await;
    space_unfriend_revokes_reciprocal_account_access_suite(endpoint).await;
    Ok(())
}

async fn space_bootstrap_posts_and_friend_share_suite(endpoint: &str) {
    let owner = auth::create_account(endpoint, "space-owner").await;
    let friend = auth::create_account(endpoint, "space-friend").await;
    let outsider = auth::create_account(endpoint, "space-outsider").await;

    let owner_ctx = space::open_ctx(endpoint, &owner).await;
    let friend_ctx = space::open_ctx(endpoint, &friend).await;
    let outsider_ctx = space::open_ctx(endpoint, &outsider).await;

    let owner_slug = format!("owner_{}", owner.user_id);
    let friend_slug = format!("friend_{}", friend.user_id);
    let outsider_slug = format!("outsider_{}", outsider.user_id);

    let owner_profile = space::profile_payload("Owner", "Owner bio");
    let owner_space = owner_ctx
        .create_space(&owner_slug, &owner_profile)
        .await
        .expect("owner space creation failed");
    let friend_profile_payload = space::profile_payload("Friender", "Friender bio");
    let friend_space = friend_ctx
        .create_space(&friend_slug, &friend_profile_payload)
        .await
        .expect("friend space creation failed");
    let outsider_space = outsider_ctx
        .create_space(
            &outsider_slug,
            &space::profile_payload("Outsider", "Outsider bio"),
        )
        .await
        .expect("outsider space creation failed");

    let owned = owner_ctx
        .list_owned_spaces()
        .await
        .expect("owned spaces should load");
    assert_eq!(owned.len(), 1);
    assert_eq!(owned[0].space_id, owner_space.space_id);

    let decrypted_profile = owner_ctx
        .get_space_profile_decrypted(&owner_space.space_id, None, None)
        .await
        .expect("owner should decrypt profile");
    assert_eq!(
        decrypted_profile.profile,
        Some(ente_space::SpaceProfile::from_bytes(&owner_profile).unwrap())
    );
    assert_eq!(decrypted_profile.space_slug, owner_slug);

    space::assert_http_status(
        outsider_ctx
            .get_space_profile_raw(&owner_space.space_id, Some(&outsider_space.space_id), None)
            .await,
        403,
    );

    let updated_slug = format!("{owner_slug}_updated");
    owner_ctx
        .update_space_slug(&owner_space.space_id, &updated_slug)
        .await
        .expect("slug update should succeed");
    let updated_profile = space::profile_payload("Owner Updated", "Bio v2");
    owner_ctx
        .update_space_profile(&owner_space.space_id, &updated_profile, None, false)
        .await
        .expect("profile update should succeed");
    let looked_up = outsider_ctx
        .lookup_space_by_slug(&updated_slug)
        .await
        .expect("public slug lookup should succeed");
    assert_eq!(looked_up.space_id, owner_space.space_id);
    assert_eq!(looked_up.space_slug, updated_slug);

    let post = owner_ctx
        .create_photo_post(
            &owner_space.space_id,
            std::iter::once(PostPhotoInput {
                bytes: TEST_WEBP_BYTES.to_vec(),
                options: PostPhotoAssetOptions {
                    width: Some(320),
                    height: Some(240),
                    media_type: Some("image/webp".to_owned()),
                    thumb_hash: None,
                },
            }),
            Some(r#"{"caption":"hello world"}"#),
        )
        .await
        .expect("post creation should succeed");
    let post_id = post.post_id;
    let owner_post = owner_ctx
        .get_post(&owner_space.space_id, post_id, None)
        .await
        .expect("owner should decrypt post");
    let owner_content = owner_post.content.as_ref().expect("owner post content");
    assert_eq!(
        owner_content.caption.as_deref(),
        Some(r#"{"caption":"hello world"}"#)
    );
    let owner_feed = owner_ctx
        .list_feed(&owner_space.space_id, None, Some(10))
        .await
        .expect("owner feed should load");
    assert_eq!(owner_feed.items.len(), 1);
    assert_eq!(owner_feed.items[0].post_id, post_id);
    let own_feed_post = owner_feed.items[0]
        .content
        .as_ref()
        .expect("own feed post should decrypt");
    assert_eq!(own_feed_post.caption, owner_content.caption);

    space::assert_http_status(
        owner_ctx
            .like_post(&owner_space.space_id, post_id, true)
            .await,
        400,
    );

    space::assert_http_status(
        friend_ctx
            .get_space_profile_raw(&owner_space.space_id, Some(&friend_space.space_id), None)
            .await,
        403,
    );

    request_and_confirm_friend(
        &friend_ctx,
        &friend_space.space_id,
        &owner_ctx,
        &owner_space.space_id,
        &updated_slug,
    )
    .await;

    let shares = friend_ctx
        .list_friend_shares(&friend_space.space_id)
        .await
        .expect("friend shares should load");
    assert_eq!(shares.len(), 1);
    let decrypted_share = friend_ctx
        .decrypt_friend_share(&friend_space.space_id, &shares[0])
        .await
        .expect("friend share should decrypt");
    assert_eq!(decrypted_share.space_id, owner_space.space_id);

    let hydrated = friend_ctx
        .hydrate_space_keys()
        .await
        .expect("space keys should hydrate");
    assert_eq!(hydrated.owned.len(), 1);
    assert_eq!(hydrated.friends.len(), 1);
    assert_eq!(hydrated.friends[0].space_id, owner_space.space_id);

    let friend_profile = friend_ctx
        .get_space_profile_decrypted(&owner_space.space_id, Some(&friend_space.space_id), None)
        .await
        .expect("approved friend should decrypt profile");
    assert_eq!(
        friend_profile.profile,
        Some(ente_space::SpaceProfile::from_bytes(&updated_profile).unwrap())
    );
    assert_eq!(friend_profile.space_slug, updated_slug);

    let owner_view_of_friend = owner_ctx
        .get_space_profile_decrypted(&friend_space.space_id, Some(&owner_space.space_id), None)
        .await
        .expect("approved owner should decrypt friend profile");
    assert_eq!(
        owner_view_of_friend.profile,
        Some(ente_space::SpaceProfile::from_bytes(&friend_profile_payload).unwrap())
    );
    assert_eq!(owner_view_of_friend.space_slug, friend_slug);

    let friend_feed = friend_ctx
        .list_feed(&friend_space.space_id, None, Some(10))
        .await
        .expect("friend feed should load");
    assert_eq!(friend_feed.items.len(), 1);
    assert_eq!(friend_feed.items[0].post_id, post_id);
    assert_eq!(friend_feed.items[0].author.space_id, owner_space.space_id);
    assert_eq!(friend_feed.items[0].author.space_slug, updated_slug);
    let feed_post_author_profile = friend_feed.items[0]
        .author
        .profile
        .as_ref()
        .expect("friend should decrypt feed post author profile");
    assert_eq!(
        feed_post_author_profile.as_ref(),
        Some(&ente_space::SpaceProfile::from_bytes(&updated_profile).unwrap())
    );
    let friend_feed_post = friend_feed.items[0]
        .content
        .as_ref()
        .expect("friend feed post should decrypt");
    assert_eq!(friend_feed_post.caption, owner_content.caption);

    let liked = friend_ctx
        .like_post(&friend_space.space_id, post_id, true)
        .await
        .expect("liking post should succeed");
    assert!(liked.liked);
    let liked_post = friend_ctx
        .get_post(&owner_space.space_id, post_id, Some(&friend_space.space_id))
        .await
        .expect("liked post should load");
    assert!(liked_post.viewer_liked);
    let notifications = owner_ctx
        .list_notifications(&owner_space.space_id, None, None)
        .await
        .expect("owner notifications should include post like");
    assert_eq!(notifications.items.len(), 2);
    assert_eq!(notifications.items[0].kind, "post_like");
    assert_eq!(notifications.items[0].post_id, Some(post_id));
    assert_eq!(
        notifications.items[0].actors[0].space_id,
        friend_space.space_id
    );

    let poke_request = uuid::Uuid::new_v4().to_string();
    friend_ctx
        .send_poke(&friend_space.space_id, &owner_space.space_id, &poke_request)
        .await
        .unwrap();
    friend_ctx
        .send_poke(&friend_space.space_id, &owner_space.space_id, &poke_request)
        .await
        .unwrap();
    let pokes = owner_ctx
        .list_notifications(&owner_space.space_id, None, None)
        .await
        .unwrap();
    assert_eq!(
        pokes
            .items
            .iter()
            .filter(|item| item.kind == "poke")
            .count(),
        1
    );
    assert_eq!(pokes.items[0].kind, "poke");
    assert_eq!(pokes.items[0].actors[0].space_id, friend_space.space_id);
    assert!(pokes.items[0].actors[0].profile.as_ref().unwrap().is_some());
    assert!(pokes.items[0].unread);
    assert!(pokes.latest_post_created_at.is_some());
    let thread = owner_ctx
        .list_message_thread(&owner_space.space_id, &friend_space.space_id, None, None)
        .await
        .unwrap();
    assert!(thread.items.is_empty());
    assert!(
        !owner_ctx
            .unread_status(&owner_space.space_id)
            .await
            .unwrap()
            .notifications_unread
    );
    friend_ctx
        .send_message(&friend_space.space_id, &owner_space.space_id, "Hello")
        .await
        .unwrap();
    assert!(
        owner_ctx
            .unread_status(&owner_space.space_id)
            .await
            .unwrap()
            .notifications_unread
    );
    owner_ctx
        .mark_notifications_read(&owner_space.space_id, &friend_space.space_id)
        .await
        .unwrap();
    assert!(
        !owner_ctx
            .unread_status(&owner_space.space_id)
            .await
            .unwrap()
            .notifications_unread
    );
    space::assert_http_status(
        outsider_ctx
            .send_poke(
                &outsider_space.space_id,
                &owner_space.space_id,
                "outsider-poke",
            )
            .await,
        403,
    );

    space::assert_http_status(
        outsider_ctx
            .get_post(&owner_space.space_id, post_id, None)
            .await,
        403,
    );
}

async fn space_unfriend_revokes_reciprocal_account_access_suite(endpoint: &str) {
    let owner = auth::create_account(endpoint, "space-unfriend-owner").await;
    let friend = auth::create_account(endpoint, "space-unfriend-friend").await;

    let owner_ctx = space::open_ctx(endpoint, &owner).await;
    let friend_ctx = space::open_ctx(endpoint, &friend).await;

    let owner_slug = format!("uo_{}", owner.user_id);
    let friend_slug = format!("uf_{}", friend.user_id);
    let owner_profile = space::profile_payload("Unfriend Owner", "Owner bio");
    let friend_profile = space::profile_payload("Unfriend Friend", "Friend bio");
    let owner_space = owner_ctx
        .create_space(&owner_slug, &owner_profile)
        .await
        .expect("owner space creation failed");
    let friend_space = friend_ctx
        .create_space(&friend_slug, &friend_profile)
        .await
        .expect("friend space creation failed");

    let post = owner_ctx
        .create_photo_post(
            &owner_space.space_id,
            std::iter::once(PostPhotoInput {
                bytes: TEST_WEBP_BYTES.to_vec(),
                options: PostPhotoAssetOptions {
                    width: Some(320),
                    height: Some(240),
                    media_type: Some("image/webp".to_owned()),
                    thumb_hash: None,
                },
            }),
            Some(r#"{"caption":"before unfriend"}"#),
        )
        .await
        .expect("post creation should succeed");
    let post_id = post.post_id;

    request_and_confirm_friend(
        &friend_ctx,
        &friend_space.space_id,
        &owner_ctx,
        &owner_space.space_id,
        &owner_slug,
    )
    .await;

    let friend_owner_profile = friend_ctx
        .get_space_profile_decrypted(&owner_space.space_id, Some(&friend_space.space_id), None)
        .await
        .expect("friend should decrypt owner profile before unfriend");
    assert_eq!(
        friend_owner_profile.profile,
        Some(ente_space::SpaceProfile::from_bytes(&owner_profile).unwrap())
    );
    let owner_friend_profile = owner_ctx
        .get_space_profile_decrypted(&friend_space.space_id, Some(&owner_space.space_id), None)
        .await
        .expect("owner should decrypt friend profile before unfriend");
    assert_eq!(
        owner_friend_profile.profile,
        Some(ente_space::SpaceProfile::from_bytes(&friend_profile).unwrap())
    );
    let friend_feed = friend_ctx
        .list_feed(&friend_space.space_id, None, Some(10))
        .await
        .expect("friend feed should load before unfriend");
    assert!(friend_feed.items.iter().any(|item| item.post_id == post_id));
    friend_ctx
        .like_post(&friend_space.space_id, post_id, true)
        .await
        .expect("friend should like owner post before unfriend");
    let direct_message = friend_ctx
        .send_message(
            &friend_space.space_id,
            &owner_space.space_id,
            "hello before unfriend",
        )
        .await
        .expect("friend should send owner a direct message before unfriend");
    let owner_thread = owner_ctx
        .list_message_thread(
            &owner_space.space_id,
            &friend_space.space_id,
            None,
            Some(10),
        )
        .await
        .expect("owner should read direct message thread before unfriend");
    let owner_thread_message = owner_thread
        .items
        .iter()
        .find(|message| message.message_id == direct_message.message_id)
        .expect("direct message should be in owner thread before unfriend");
    assert!(matches!(
        &owner_thread_message.content,
        Ok(Some(content)) if content.text == "hello before unfriend"
    ));
    owner_ctx
        .like_message(&owner_space.space_id, &direct_message.message_id, true)
        .await
        .expect("owner should like direct message before unfriend");

    owner_ctx
        .unfriend_by_space(&owner_space.space_id, &friend_space.space_id)
        .await
        .expect("owner should unfriend friend");

    let owner_shares = owner_ctx
        .list_friend_shares(&owner_space.space_id)
        .await
        .expect("owner friend shares should load after unfriend");
    assert!(owner_shares.is_empty());
    let friend_shares = friend_ctx
        .list_friend_shares(&friend_space.space_id)
        .await
        .expect("friend shares should load after unfriend");
    assert!(friend_shares.is_empty());
    let owner_friends = owner_ctx
        .list_space_friends(&owner_space.space_id)
        .await
        .expect("owner friend list should load after unfriend");
    assert!(owner_friends.is_empty());
    let friend_friends = friend_ctx
        .list_space_friends(&friend_space.space_id)
        .await
        .expect("friend friend list should load after unfriend");
    assert!(friend_friends.is_empty());

    let owner_relationship = owner_ctx
        .get_relationship(&owner_space.space_id, &friend_space.space_id)
        .await
        .expect("owner relationship should load after unfriend");
    assert!(owner_relationship.relationship.is_empty());
    let friend_relationship = friend_ctx
        .get_relationship(&friend_space.space_id, &owner_space.space_id)
        .await
        .expect("friend relationship should load after unfriend");
    assert!(friend_relationship.relationship.is_empty());

    let hydrated = friend_ctx
        .hydrate_space_keys()
        .await
        .expect("friend space keys should hydrate after unfriend");
    assert_eq!(hydrated.owned.len(), 1);
    assert!(hydrated.friends.is_empty());
    let friend_feed = friend_ctx
        .list_feed(&friend_space.space_id, None, Some(10))
        .await
        .expect("friend feed should load after unfriend");
    assert!(
        friend_feed
            .items
            .iter()
            .all(|item| item.space_id != owner_space.space_id)
    );
    let owner_thread = owner_ctx
        .list_message_thread(
            &owner_space.space_id,
            &friend_space.space_id,
            None,
            Some(10),
        )
        .await
        .expect("owner should still read direct message thread after unfriend");
    let owner_thread_message = owner_thread
        .items
        .iter()
        .find(|message| message.message_id == direct_message.message_id)
        .expect("direct message should remain in owner thread after unfriend");
    assert!(matches!(
        &owner_thread_message.content,
        Ok(Some(content)) if content.text == "hello before unfriend"
    ));
    space::assert_invalid_input_contains(
        friend_ctx
            .send_message(&friend_space.space_id, &owner_space.space_id, "should fail")
            .await,
        "not a friend",
    );
    space::assert_invalid_input_contains(
        owner_ctx
            .reply_to_message(
                &owner_space.space_id,
                &friend_space.space_id,
                &direct_message.message_id,
                "should fail",
            )
            .await,
        "not a friend",
    );
    space::assert_http_status(
        owner_ctx
            .like_message(&owner_space.space_id, &direct_message.message_id, false)
            .await,
        403,
    );
    space::assert_http_status(
        owner_ctx
            .delete_message(&owner_space.space_id, &direct_message.message_id)
            .await,
        403,
    );

    space::assert_http_status(
        friend_ctx
            .get_space_profile_raw(&owner_space.space_id, Some(&friend_space.space_id), None)
            .await,
        403,
    );
    space::assert_http_status(
        owner_ctx
            .get_space_profile_raw(&friend_space.space_id, Some(&owner_space.space_id), None)
            .await,
        403,
    );
    space::assert_http_status(
        friend_ctx
            .get_post(&owner_space.space_id, post_id, Some(&friend_space.space_id))
            .await,
        403,
    );
    space::assert_http_status(
        friend_ctx
            .like_post(&friend_space.space_id, post_id, true)
            .await,
        403,
    );
    space::assert_http_status(
        friend_ctx
            .reply_to_post(
                &friend_space.space_id,
                &owner_space.space_id,
                post_id,
                "should fail",
                None,
            )
            .await,
        403,
    );
}

async fn space_comments_suite(museum: &Museum) {
    let endpoint = museum.endpoint();
    let x_account = auth::create_account(endpoint, "comments-x").await;
    let y_account = auth::create_account(endpoint, "comments-y").await;
    let z_account = auth::create_account(endpoint, "comments-z").await;
    let outsider_account = auth::create_account(endpoint, "comments-outsider").await;
    let x = space::open_ctx(endpoint, &x_account).await;
    let y = space::open_ctx(endpoint, &y_account).await;
    let z = space::open_ctx(endpoint, &z_account).await;
    let outsider = space::open_ctx(endpoint, &outsider_account).await;
    let xs = x
        .create_space(
            &format!("cx_{}", x_account.user_id),
            &space::profile_payload("X private name", "X bio"),
        )
        .await
        .unwrap();
    let ys = y
        .create_space(
            &format!("cy_{}", y_account.user_id),
            &space::profile_payload("Y private name", "Y bio"),
        )
        .await
        .unwrap();
    let zs = z
        .create_space(
            &format!("cz_{}", z_account.user_id),
            &space::profile_payload("Z private name", "Z bio"),
        )
        .await
        .unwrap();
    let os = outsider
        .create_space(
            &format!("co_{}", outsider_account.user_id),
            &space::profile_payload("Outsider", "Private"),
        )
        .await
        .unwrap();
    z.update_space_profile_with_avatar(
        &zs.space_id,
        &space::profile_payload("Z private name", "Z bio"),
        TEST_WEBP_BYTES,
    )
    .await
    .unwrap();
    request_and_confirm_friend(&y, &ys.space_id, &x, &xs.space_id, &xs.space_slug).await;
    request_and_confirm_friend(&z, &zs.space_id, &x, &xs.space_id, &xs.space_slug).await;
    let post = x
        .create_photo_post(
            &xs.space_id,
            [PostPhotoInput {
                bytes: TEST_WEBP_BYTES.to_vec(),
                options: PostPhotoAssetOptions {
                    width: Some(320),
                    height: Some(240),
                    media_type: Some("image/webp".into()),
                    thumb_hash: None,
                },
            }]
            .into_iter(),
            Some("Post with comments"),
        )
        .await
        .unwrap();
    let id = post.post_id;
    space::assert_http_status(
        outsider
            .list_comments(&os.space_id, &xs.space_id, id, None)
            .await,
        404,
    );
    y.create_comment(
        &ys.space_id,
        &xs.space_id,
        id,
        "comment-y",
        None,
        "Hello everyone",
    )
    .await
    .unwrap();
    z.create_comment(
        &zs.space_id,
        &xs.space_id,
        id,
        "reply-z",
        Some("comment-y"),
        "Hello Y",
    )
    .await
    .unwrap();
    y.create_comment(
        &ys.space_id,
        &xs.space_id,
        id,
        "reply-y",
        Some("reply-z"),
        "Hello Z",
    )
    .await
    .unwrap();
    z.set_comment_reaction(&zs.space_id, &xs.space_id, id, "comment-y", Some("❤️"))
        .await
        .unwrap();
    y.set_comment_reaction(&ys.space_id, &xs.space_id, id, "reply-z", Some("🎉"))
        .await
        .unwrap();
    space::assert_http_status(
        y.remove_comment_reaction(&ys.space_id, id, "comment-y", &zs.space_id)
            .await,
        403,
    );
    let raw: serde_json::Value = y
        .api()
        .get(&format!(
            "/spaces/{}/discussions/{id}/comments",
            ys.space_id
        ))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    let asset = &post.content.as_ref().unwrap().photos[0].asset;
    let space_key = x
        .resolve_space_key_for_version_for_viewer(
            &xs.space_id,
            Some(&xs.space_id),
            Some(asset.key_version),
        )
        .await
        .unwrap()
        .unwrap();
    let post_key = ente_core::crypto::secretbox::decrypt_combined(
        &ente_core::b64::decode(&asset.encrypted_post_key).unwrap(),
        &ente_core::crypto::Key::try_from_slice(&space_key).unwrap(),
    )
    .unwrap();
    let post_key = ente_core::crypto::Key::try_from_slice(&post_key).unwrap();
    for (cipher, text) in [
        (&raw["items"][0]["cipher"], "Hello everyone"),
        (&raw["items"][0]["reactions"][0]["cipher"], "❤️"),
    ] {
        let bytes = ente_core::crypto::secretbox::decrypt_combined(
            &ente_core::b64::decode(cipher.as_str().unwrap()).unwrap(),
            &post_key,
        )
        .unwrap();
        let payload: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(payload["text"], text);
    }
    let comments = y
        .list_comments(&ys.space_id, &xs.space_id, id, None)
        .await
        .unwrap();
    assert_eq!(comments.items.len(), 3);
    assert_eq!(comments.items[0].text.as_deref(), Some("Hello everyone"));
    assert_eq!(comments.items[1].text.as_deref(), Some("Hello Y"));
    assert_eq!(comments.items[2].parent_id, "comment-y");
    assert_eq!(comments.items[2].reply_to_id, "reply-z");
    assert!(
        comments.items[1]
            .author
            .as_ref()
            .unwrap()
            .profile
            .as_ref()
            .unwrap()
            .is_none()
    );
    assert!(comments.items[1].author.as_ref().unwrap().avatar.is_none());
    assert_eq!(
        comments.items[1].author.as_ref().unwrap().space_slug,
        zs.space_slug
    );
    assert!(!comments.items[1].can_delete);
    assert_eq!(comments.items[0].reactions[0].emoji, "❤️");
    assert!(
        comments.items[0].reactions[0]
            .actor
            .profile
            .as_ref()
            .unwrap()
            .is_none()
    );
    assert!(
        y.resolve_space_key_for_version_for_viewer(&zs.space_id, Some(&ys.space_id), None)
            .await
            .unwrap()
            .is_none()
    );
    x.remove_comment_reaction(&xs.space_id, id, "reply-z", &ys.space_id)
        .await
        .unwrap();
    assert!(
        y.list_comments(&ys.space_id, &xs.space_id, id, None)
            .await
            .unwrap()
            .items[1]
            .reactions
            .is_empty()
    );
    let owner_view = x
        .list_comments(&xs.space_id, &xs.space_id, id, None)
        .await
        .unwrap();
    assert!(
        owner_view.items[1]
            .author
            .as_ref()
            .unwrap()
            .profile
            .as_ref()
            .unwrap()
            .is_some()
    );
    assert!(
        owner_view.items[1]
            .author
            .as_ref()
            .unwrap()
            .avatar
            .is_some()
    );
    request_and_confirm_friend(&y, &ys.space_id, &z, &zs.space_id, &zs.space_slug).await;
    let friend_view = y
        .list_comments(&ys.space_id, &xs.space_id, id, None)
        .await
        .unwrap();
    assert!(
        friend_view.items[1]
            .author
            .as_ref()
            .unwrap()
            .profile
            .as_ref()
            .unwrap()
            .is_some()
    );
    assert!(
        friend_view.items[1]
            .author
            .as_ref()
            .unwrap()
            .avatar
            .is_some()
    );
    z.unfriend_by_space(&zs.space_id, &ys.space_id)
        .await
        .unwrap();
    let nonfriend_view = y
        .list_comments(&ys.space_id, &xs.space_id, id, None)
        .await
        .unwrap();
    assert!(
        nonfriend_view.items[1]
            .author
            .as_ref()
            .unwrap()
            .profile
            .as_ref()
            .unwrap()
            .is_none()
    );
    assert!(
        nonfriend_view.items[1]
            .author
            .as_ref()
            .unwrap()
            .avatar
            .is_none()
    );
    assert!(
        nonfriend_view.items[0].reactions[0]
            .actor
            .profile
            .as_ref()
            .unwrap()
            .is_none()
    );
    assert!(nonfriend_view.items[0].reactions[0].actor.avatar.is_none());
    space::assert_http_status(
        y.get_space_profile_raw(&zs.space_id, Some(&ys.space_id), None)
            .await,
        403,
    );
    let notifications = y
        .list_notifications(&ys.space_id, None, None)
        .await
        .unwrap();
    let reply = notifications
        .items
        .iter()
        .find(|item| item.kind == "comment_reply")
        .unwrap();
    assert_eq!(reply.post_space_id.as_deref(), Some(xs.space_id.as_str()));
    assert!(reply.actors[0].profile.as_ref().unwrap().is_none());
    assert!(reply.actors[0].avatar.is_none());
    assert_eq!(reply.actors[0].space_slug, zs.space_slug);
    let object_key = &post.content.as_ref().unwrap().photos[0].asset.object_key;
    y.reply_to_post(
        &ys.space_id,
        &xs.space_id,
        id,
        "Only for X",
        Some(object_key),
    )
    .await
    .unwrap();
    assert_eq!(
        z.list_comments(&zs.space_id, &xs.space_id, id, None)
            .await
            .unwrap()
            .items
            .len(),
        3
    );
    space::assert_http_status(y.delete_comment(&ys.space_id, id, "reply-z").await, 403);
    z.set_comment_reaction(&zs.space_id, &xs.space_id, id, "comment-y", None)
        .await
        .unwrap();
    assert!(
        y.list_comments(&ys.space_id, &xs.space_id, id, None)
            .await
            .unwrap()
            .items[0]
            .reactions
            .is_empty()
    );
    x.delete_comment(&xs.space_id, id, "reply-z").await.unwrap();
    let comments = y
        .list_comments(&ys.space_id, &xs.space_id, id, None)
        .await
        .unwrap();
    assert!(comments.items[1].deleted);
    assert!(comments.items[1].text.is_none());
    assert!(comments.items[1].reactions.is_empty());
    assert!(comments.items[2].deleted);
    assert!(comments.items[2].text.is_none());
    assert!(comments.items[2].reactions.is_empty());
    space::assert_http_status(
        y.create_comment(
            &ys.space_id,
            &xs.space_id,
            id,
            "deleted-reply",
            Some("reply-z"),
            "No",
        )
        .await,
        404,
    );
    x.request_friend_by_username(&xs.space_id, &os.space_slug)
        .await
        .unwrap();
    y.create_comment(
        &ys.space_id,
        &xs.space_id,
        id,
        "while-pending",
        None,
        "During the request",
    )
    .await
    .unwrap();
    space::assert_http_status(
        outsider
            .list_comments(&os.space_id, &xs.space_id, id, None)
            .await,
        404,
    );
    let pending = outsider.list_friend_requests(&os.space_id).await.unwrap();
    outsider
        .confirm_friend_request(&os.space_id, pending[0].request_id)
        .await
        .unwrap();
    assert_eq!(
        outsider
            .list_comments(&os.space_id, &xs.space_id, id, None)
            .await
            .unwrap()
            .items
            .last()
            .unwrap()
            .text
            .as_deref(),
        Some("During the request")
    );
    assert_eq!(
        outsider
            .list_comments(&os.space_id, &xs.space_id, id, None)
            .await
            .unwrap()
            .items[0]
            .text
            .as_deref(),
        Some("Hello everyone")
    );
    x.unfriend_by_space(&xs.space_id, &zs.space_id)
        .await
        .unwrap();
    space::assert_http_status(
        z.list_comments(&zs.space_id, &xs.space_id, id, None).await,
        404,
    );
    space::assert_http_status(
        z.create_comment(
            &zs.space_id,
            &xs.space_id,
            id,
            "removed-z",
            None,
            "No access",
        )
        .await,
        403,
    );
    space::assert_http_status(
        z.set_comment_reaction(&zs.space_id, &xs.space_id, id, "comment-y", Some("❤️"))
            .await,
        403,
    );
    assert!(
        !z.list_notifications(&zs.space_id, None, None)
            .await
            .unwrap()
            .items
            .iter()
            .any(|item| item.kind.starts_with("comment"))
    );
    let revoked_write = z
        .api()
        .post(&format!(
            "/spaces/{}/discussions/{id}/comments",
            zs.space_id
        ))
        .json(&serde_json::json!({"commentId":"stale-access", "cipher":"YWJj"}))
        .send()
        .await
        .unwrap();
    assert_eq!(revoked_write.status(), 404);
    let revoked_reaction = z
        .api()
        .put(&format!(
            "/spaces/{}/discussions/{id}/comments/comment-y/reaction",
            zs.space_id
        ))
        .json(&serde_json::json!({"cipher":"YWJj"}))
        .send()
        .await
        .unwrap();
    assert_eq!(revoked_reaction.status(), 404);
    y.create_comment(
        &ys.space_id,
        &xs.space_id,
        id,
        "after-removal",
        None,
        "Still accessible",
    )
    .await
    .unwrap();
    assert_eq!(
        outsider
            .list_comments(&os.space_id, &xs.space_id, id, None)
            .await
            .unwrap()
            .items
            .last()
            .unwrap()
            .text
            .as_deref(),
        Some("Still accessible")
    );
    y.delete_comment(&ys.space_id, id, "comment-y")
        .await
        .unwrap();
    space::assert_http_status(
        outsider
            .create_comment(
                &os.space_id,
                &xs.space_id,
                id,
                "continued-thread",
                Some("reply-y"),
                "Cannot continue this thread",
            )
            .await,
        404,
    );
    let deleted_thread = y
        .list_comments(&ys.space_id, &xs.space_id, id, None)
        .await
        .unwrap();
    for comment in deleted_thread
        .items
        .iter()
        .filter(|item| item.comment_id == "comment-y" || item.parent_id == "comment-y")
    {
        assert!(comment.deleted);
        assert!(comment.text.is_none());
        assert!(comment.reactions.is_empty());
    }
    space::assert_http_status(
        y.create_comment(
            &ys.space_id,
            &xs.space_id,
            id,
            "deleted-root-target",
            Some("comment-y"),
            "No",
        )
        .await,
        404,
    );
    x.delete_post(&xs.space_id, id).await.unwrap();
    space::assert_http_status(
        y.list_comments(&ys.space_id, &xs.space_id, id, None).await,
        404,
    );
    assert!(
        !y.list_notifications(&ys.space_id, None, None)
            .await
            .unwrap()
            .items
            .iter()
            .any(|item| item.kind.starts_with("comment"))
    );
    let post = x
        .create_photo_post(
            &xs.space_id,
            [PostPhotoInput {
                bytes: TEST_WEBP_BYTES.to_vec(),
                options: PostPhotoAssetOptions {
                    width: Some(320),
                    height: Some(240),
                    media_type: Some("image/webp".into()),
                    thumb_hash: None,
                },
            }]
            .into_iter(),
            Some("Discussion deletion"),
        )
        .await
        .unwrap();
    for (ctx, viewer, id, target) in [
        (&x, &xs.space_id, "delete-root-x", None),
        (&y, &ys.space_id, "delete-reply-y", Some("delete-root-x")),
        (&x, &xs.space_id, "delete-reply-x", Some("delete-reply-y")),
        (&y, &ys.space_id, "delete-root-y", None),
        (&x, &xs.space_id, "delete-child-x", Some("delete-root-y")),
    ] {
        ctx.create_comment(viewer, &xs.space_id, post.post_id, id, target, id)
            .await
            .unwrap();
    }
    y.set_comment_reaction(
        &ys.space_id,
        &xs.space_id,
        post.post_id,
        "delete-root-x",
        Some("❤️"),
    )
    .await
    .unwrap();
    let before = x
        .list_comments(&xs.space_id, &xs.space_id, post.post_id, None)
        .await
        .unwrap();
    assert!(
        before.items[1]
            .author
            .as_ref()
            .unwrap()
            .profile
            .as_ref()
            .unwrap()
            .is_some()
    );
    for sql in [
        format!(
            "UPDATE users SET encrypted_email = NULL WHERE user_id = {}",
            y_account.user_id
        ),
        format!("DELETE FROM spaces WHERE owner_id = {}", y_account.user_id),
    ] {
        museum.execute_sql(&sql).unwrap();
        let comments = x
            .list_comments(&xs.space_id, &xs.space_id, post.post_id, None)
            .await
            .unwrap();
        assert_eq!(comments.items.len(), 5);
        for item in &comments.items {
            if item.comment_id != "delete-root-x" {
                assert!(item.deleted);
                assert!(item.text.is_none());
            } else {
                assert!(!item.deleted);
                assert_eq!(item.text.as_deref(), Some(item.comment_id.as_str()));
            }
            if item.comment_id == "delete-reply-y" || item.comment_id == "delete-root-y" {
                assert!(item.author.is_none());
            }
            assert!(item.reactions.is_empty());
        }
        assert_eq!(comments.items[2].reply_to_id, "delete-reply-y");
        assert_eq!(comments.items[2].parent_id, "delete-root-x");
        assert_eq!(comments.items[4].reply_to_id, "delete-root-y");
        assert_eq!(comments.items[4].parent_id, "delete-root-y");
    }
    space::assert_http_status(
        x.create_comment(
            &xs.space_id,
            &xs.space_id,
            post.post_id,
            "after-account-deletion",
            Some("delete-child-x"),
            "Cannot continue the deleted thread",
        )
        .await,
        404,
    );
    museum
        .execute_sql(&format!(
            "DELETE FROM space_posts WHERE post_id = {}",
            post.post_id
        ))
        .unwrap();
    space::assert_http_status(
        x.list_comments(&xs.space_id, &xs.space_id, post.post_id, None)
            .await,
        404,
    );
}
