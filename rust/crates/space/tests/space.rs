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
    let confirmed = target_ctx
        .confirm_friend_request(target_space_id, request.request_id)
        .await
        .expect("friend request should confirm");
    assert_eq!(confirmed.status, "friend");
}

#[test]
fn space_e2e() -> TestResult {
    Museum::run_async(run)
}

async fn run(endpoint: String) -> TestResult {
    space_bootstrap_posts_and_friend_share_suite(&endpoint).await;
    space_unfriend_revokes_reciprocal_account_access_suite(&endpoint).await;
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
    let owner_conversations = owner_ctx
        .list_conversations(&owner_space.space_id)
        .await
        .expect("owner conversations should include post like");
    let post_like_summary = owner_conversations
        .chat_summaries
        .get(&friend_space.space_id)
        .expect("friend summary should exist after post like");
    assert_eq!(post_like_summary.latest_activity.activity_type, "post_like");
    assert_eq!(post_like_summary.latest_activity.post_id, Some(post_id));
    assert_eq!(
        post_like_summary.latest_activity.post_space_id.as_deref(),
        Some(owner_space.space_id.as_str())
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
