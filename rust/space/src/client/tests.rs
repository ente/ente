//! Integration tests for the Space client.
//!
//! Black-box tests over the public `AccountSpaceCtx` API, driven by a mock HTTP server.
//! Shared fixtures live in
//! [`test_support`](super::test_support). Kept in-crate (rather than `tests/`)
//! because a few fixtures need crate-internal crypto and constructors.

use super::test_support::*;
use super::*;
use crate::crypto::{encrypt_asset_payload, seal_with_public_key};
use crate::transport::{
    EntityKeyPayload, ProfileAvatarPayload, ProfileCoverPayload, SpaceActorResponse,
};

use mockito::{Matcher, Server};
use serde_json::json;
use zeroize::Zeroize;

#[test]
fn decrypted_friend_share_zeroizes_its_key() {
    let mut share = DecryptedFriendShare {
        friend: "friend@example.com".to_owned(),
        space_id: "space-friend".to_owned(),
        space_slug: "friend".to_owned(),
        space_key: vec![42; 32],
        key_version: 1,
    };

    share.zeroize();

    assert!(share.space_key.is_empty());
}

#[tokio::test]
async fn account_api_sends_space_session_token_header() {
    let mut server = Server::new_async().await;
    let request = server
        .mock("GET", "/account/space")
        .match_header("x-space-session-token", "space-session-token")
        .with_status(200)
        .with_body("{}")
        .create_async()
        .await;
    let api = build_api(
        &server.url(),
        Some("space-session-token".to_owned()),
        None,
        None,
        None,
    )
    .expect("API client");

    let _: serde_json::Value = api
        .get("/account/space")
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();

    request.assert_async().await;
}

#[tokio::test]
async fn get_space_root_key_returns_context_space_root_key() {
    let server = Server::new_async().await;
    let expected_space_root = generate_key();
    let ctx = test_account_ctx_with_space_root_key(&server.url(), expected_space_root.clone());

    let space_root = ctx
        .get_space_root_key()
        .await
        .expect("space root key should load")
        .expect("space root key should exist");

    assert_eq!(space_root, expected_space_root);
}

#[tokio::test]
async fn get_or_create_space_root_key_returns_context_space_root_key() {
    let server = Server::new_async().await;
    let expected_space_root = generate_key();
    let ctx = test_account_ctx_with_space_root_key(&server.url(), expected_space_root.clone());

    let space_root = ctx
        .get_or_create_space_root_key()
        .await
        .expect("space root key should load");

    assert_eq!(space_root, expected_space_root);
}

#[tokio::test]
async fn ensure_entity_key_uses_generic_split_key_endpoint() {
    let mut server = Server::new_async().await;
    let ctx = test_account_ctx(&server.url());
    let header = vec![1u8; 24];
    let encrypted_key = vec![2u8; 48];
    let mut combined = header.clone();
    combined.extend_from_slice(&encrypted_key);
    let ensure = server
        .mock("POST", "/user-entity/key/ensure")
        .match_body(Matcher::JsonString(
            json!({
                "type": "space",
                "encryptedKey": encode_b64(&encrypted_key),
                "header": encode_b64(&header),
            })
            .to_string(),
        ))
        .with_status(200)
        .with_body(
            json!({
                "userID": 1,
                "type": "space",
                "encryptedKey": encode_b64(&encrypted_key),
                "header": encode_b64(&header),
                "createdAt": 123,
            })
            .to_string(),
        )
        .create_async()
        .await;

    let payload = ctx
        .ensure_entity_key(
            "space",
            &EntityKeyPayload {
                encrypted_key: encode_b64(&combined),
            },
        )
        .await
        .expect("entity key");

    assert_eq!(payload.encrypted_key, encode_b64(&combined));
    ensure.assert_async().await;
}

#[tokio::test]
async fn account_space_key_resolution_is_cached_within_context() {
    let mut server = Server::new_async().await;
    let space_root_key = generate_key();
    let ctx = test_account_ctx_with_space_root_key(&server.url(), space_root_key.clone());
    let friend_space_key = generate_key();
    let encrypted_profile = encode_b64(
        &encrypt_secretbox_payload(&friend_space_key, b"friend-profile").expect("profile wrap"),
    );
    let sealed_share =
        seal_with_public_key(&friend_space_key, &test_public_key(&ctx)).expect("friend share seal");
    let friend_sealed_space_key = encode_b64(&sealed_share);

    let spaces = server
        .mock("GET", "/account/space")
        .match_header("x-space-session-token", "space-session-token")
        .with_status(200)
        .with_body(owned_space_response(
            &space_root_key,
            &generate_key(),
            "space_owner_main",
            "owner",
            1,
        ))
        .expect(1)
        .create_async()
        .await;
    let shares = server
        .mock("GET", "/spaces/space_owner_main/friends/shares")
        .match_header("x-space-session-token", "space-session-token")
        .with_status(200)
        .with_body(
            json!([{
                "friend": "friend",
                "spaceId": "space_friend",
                "spaceSlug": "friend",
                "friendSealedSpaceKey": friend_sealed_space_key,
                "keyVersion": 1
            }])
            .to_string(),
        )
        .expect(1)
        .create_async()
        .await;
    let actor = SpaceActorResponse {
        space_id: "space_friend".to_owned(),
        space_slug: "friend".to_owned(),
        key_version: 1,
        encrypted_profile,
        ..Default::default()
    };

    let first = ctx
        .decrypt_actor_profile(&actor)
        .await
        .expect("first profile decrypt");
    let second = ctx
        .decrypt_actor_profile(&actor)
        .await
        .expect("second profile decrypt");

    assert_eq!(first.as_deref(), Some(b"friend-profile".as_slice()));
    assert_eq!(second.as_deref(), Some(b"friend-profile".as_slice()));
    spaces.assert_async().await;
    shares.assert_async().await;
}

#[tokio::test]
async fn upload_post_asset_uses_presign_and_object_store() {
    let mut server = Server::new_async().await;
    let ctx = test_account_ctx(&server.url());

    let presign = server
        .mock("POST", "/spaces/space_owner_main/uploads/presign")
        .match_header("x-space-session-token", "space-session-token")
        .match_body(Matcher::AllOf(vec![
            Matcher::Regex("\"size\"".into()),
            Matcher::Regex("\"contentMD5\":\"[^\"]+\"".into()),
        ]))
        .with_status(200)
        .with_body(
            json!({
                "url": format!("{}/upload/object-1", server.url()),
                "method": "PUT",
                "headers": {
                    "content-type": "application/octet-stream",
                    "Content-MD5": "test-digest"
                },
                "objectKey": "object-1",
                "expiresIn": 300
            })
            .to_string(),
        )
        .create_async()
        .await;
    let upload = server
        .mock("PUT", "/upload/object-1")
        .match_header("content-type", "application/octet-stream")
        .match_header("content-md5", "test-digest")
        .with_status(200)
        .create_async()
        .await;

    let payload = ctx
        .upload_post_asset("space_owner_main", &generate_key(), b"tiny-image", Some(0))
        .await
        .expect("upload should succeed");

    assert_eq!(payload.object_key, "object-1");
    assert_eq!(payload.position, Some(0));
    assert!(payload.size.unwrap_or_default() > 0);
    presign.assert_async().await;
    upload.assert_async().await;
}

#[tokio::test]
async fn upload_post_photo_asset_attaches_photo_metadata() {
    let mut server = Server::new_async().await;
    let ctx = test_account_ctx(&server.url());
    let presign = server
        .mock("POST", "/spaces/space_owner_main/uploads/presign")
        .match_header("x-space-session-token", "space-session-token")
        .match_body(Matcher::AllOf(vec![Matcher::Regex(
            "\"contentMD5\":\"[^\"]+\"".into(),
        )]))
        .with_status(200)
        .with_body(
            json!({
                "url": format!("{}/upload/photo-object", server.url()),
                "method": "PUT",
                "headers": {
                    "content-type": "application/octet-stream",
                    "Content-MD5": "test-digest"
                },
                "objectKey": "photo-object",
                "expiresIn": 300
            })
            .to_string(),
        )
        .create_async()
        .await;
    let upload = server
        .mock("PUT", "/upload/photo-object")
        .match_header("content-type", "application/octet-stream")
        .match_header("content-md5", "test-digest")
        .with_status(200)
        .create_async()
        .await;

    let post_key = generate_key();
    let payload = ctx
        .upload_post_photo_asset(
            "space_owner_main",
            &post_key,
            TEST_WEBP_BYTES,
            PostPhotoAssetOptions {
                width: Some(4032),
                height: Some(3024),
                media_type: Some("image/webp".to_owned()),
                thumb_hash: Some("thumbhash-test".to_owned()),
            },
        )
        .await
        .expect("photo upload should succeed");

    assert_eq!(payload.object_key, "photo-object");
    assert_eq!(payload.position, Some(0));
    let metadata = ctx
        .decrypt_post_object_metadata(&post_key, &payload)
        .expect("metadata should decrypt")
        .expect("metadata should exist");
    assert_eq!(metadata.width, Some(4032));
    assert_eq!(metadata.height, Some(3024));
    assert_eq!(metadata.media_type.as_deref(), Some("image/webp"));
    assert_eq!(metadata.thumb_hash.as_deref(), Some("thumbhash-test"));
    presign.assert_async().await;
    upload.assert_async().await;
}

#[tokio::test]
async fn upload_post_photo_asset_rejects_video_media_type() {
    let server = Server::new_async().await;
    let ctx = test_account_ctx(&server.url());

    let err = ctx
        .upload_post_photo_asset(
            "space_owner_main",
            &generate_key(),
            TEST_WEBP_BYTES,
            PostPhotoAssetOptions {
                width: Some(4032),
                height: Some(3024),
                media_type: Some("video/mp4".to_owned()),
                thumb_hash: None,
            },
        )
        .await
        .expect_err("video media type should fail before upload");

    assert!(err.to_string().contains(ONLY_PHOTOS_UPLOAD_MESSAGE));
}

#[tokio::test]
async fn upload_post_photo_asset_rejects_video_bytes() {
    let server = Server::new_async().await;
    let ctx = test_account_ctx(&server.url());

    let err = ctx
        .upload_post_photo_asset(
            "space_owner_main",
            &generate_key(),
            TEST_MP4_BYTES,
            PostPhotoAssetOptions {
                width: Some(1920),
                height: Some(1080),
                media_type: Some("image/webp".to_owned()),
                thumb_hash: None,
            },
        )
        .await
        .expect_err("video bytes should fail before upload");

    assert!(err.to_string().contains(ONLY_PHOTOS_UPLOAD_MESSAGE));
}

#[tokio::test]
async fn presign_uploads_reject_oversized_space_assets() {
    let server = Server::new_async().await;
    let ctx = test_account_ctx(&server.url());

    let post_error = ctx
        .presign_post_upload(
            "space_owner_main",
            MAX_SPACE_POST_UPLOAD_BYTES + 1,
            "XUFAKrxLKna5cZ2REBfFkg==",
        )
        .await
        .expect_err("oversized post upload should fail before presign");
    assert!(post_error.to_string().contains("post upload size"));
    assert!(
        post_error
            .to_string()
            .contains(&MAX_SPACE_POST_UPLOAD_BYTES.to_string())
    );

    let avatar_error = ctx
        .presign_avatar_upload(
            "space_owner_main",
            MAX_SPACE_AVATAR_UPLOAD_BYTES + 1,
            "XUFAKrxLKna5cZ2REBfFkg==",
        )
        .await
        .expect_err("oversized avatar upload should fail before presign");
    assert!(avatar_error.to_string().contains("avatar upload size"));
    assert!(
        avatar_error
            .to_string()
            .contains(&MAX_SPACE_AVATAR_UPLOAD_BYTES.to_string())
    );

    let cover_error = ctx
        .presign_cover_upload(
            "space_owner_main",
            MAX_SPACE_COVER_UPLOAD_BYTES + 1,
            "XUFAKrxLKna5cZ2REBfFkg==",
        )
        .await
        .expect_err("oversized cover upload should fail before presign");
    assert!(cover_error.to_string().contains("cover upload size"));
    assert!(
        cover_error
            .to_string()
            .contains(&MAX_SPACE_COVER_UPLOAD_BYTES.to_string())
    );
}

#[tokio::test]
async fn upload_avatar_uses_avatar_presign_and_object_store() {
    let mut server = Server::new_async().await;
    let ctx = test_account_ctx(&server.url());
    let presign = server
        .mock("POST", "/spaces/space_owner_main/uploads/presign")
        .match_header("x-space-session-token", "space-session-token")
        .match_body(Matcher::AllOf(vec![
            Matcher::Regex("\"purpose\":\"avatar\"".into()),
            Matcher::Regex("\"contentMD5\":\"[^\"]+\"".into()),
            Matcher::Regex("\"size\"".into()),
        ]))
        .with_status(200)
        .with_body(
            json!({
                "url": format!("{}/upload/avatar-object", server.url()),
                "method": "PUT",
                "headers": {
                    "content-type": "application/octet-stream",
                    "Content-MD5": "test-digest"
                },
                "objectKey": "avatar-object",
                "expiresIn": 300
            })
            .to_string(),
        )
        .create_async()
        .await;
    let upload = server
        .mock("PUT", "/upload/avatar-object")
        .match_header("content-type", "application/octet-stream")
        .match_header("content-md5", "test-digest")
        .with_status(200)
        .create_async()
        .await;

    let payload = ctx
        .upload_avatar("space_owner_main", &generate_key(), TEST_WEBP_BYTES)
        .await
        .expect("avatar upload should succeed");

    assert_eq!(payload.object_id, "avatar-object");
    assert!(payload.size.unwrap_or_default() > 0);
    presign.assert_async().await;
    upload.assert_async().await;
}

#[tokio::test]
async fn upload_avatar_rejects_video_bytes() {
    let server = Server::new_async().await;
    let ctx = test_account_ctx(&server.url());

    let err = ctx
        .upload_avatar("space_owner_main", &generate_key(), TEST_MP4_BYTES)
        .await
        .expect_err("video avatar bytes should fail before upload");

    assert!(err.to_string().contains(ONLY_PHOTOS_UPLOAD_MESSAGE));
}

#[tokio::test]
async fn upload_cover_uses_cover_presign_and_object_store() {
    let mut server = Server::new_async().await;
    let ctx = test_account_ctx(&server.url());
    let presign = server
        .mock("POST", "/spaces/space_owner_main/uploads/presign")
        .match_header("x-space-session-token", "space-session-token")
        .match_body(Matcher::AllOf(vec![
            Matcher::Regex("\"purpose\":\"cover\"".into()),
            Matcher::Regex("\"contentMD5\":\"[^\"]+\"".into()),
            Matcher::Regex("\"size\"".into()),
        ]))
        .with_status(200)
        .with_body(
            json!({
                "url": format!("{}/upload/cover-object", server.url()),
                "method": "PUT",
                "headers": {
                    "content-type": "application/octet-stream",
                    "Content-MD5": "test-digest"
                },
                "objectKey": "cover-object",
                "expiresIn": 300
            })
            .to_string(),
        )
        .create_async()
        .await;
    let upload = server
        .mock("PUT", "/upload/cover-object")
        .match_header("content-type", "application/octet-stream")
        .match_header("content-md5", "test-digest")
        .with_status(200)
        .create_async()
        .await;

    let payload = ctx
        .upload_cover("space_owner_main", &generate_key(), TEST_WEBP_BYTES)
        .await
        .expect("cover upload should succeed");

    assert_eq!(payload.object_id, "cover-object");
    assert!(payload.size.unwrap_or_default() > 0);
    presign.assert_async().await;
    upload.assert_async().await;
}

#[tokio::test]
async fn account_download_profile_avatar_uses_asset_key_version() {
    let mut server = Server::new_async().await;
    let space_root_key = generate_key();
    let ctx = test_account_ctx_with_space_root_key(&server.url(), space_root_key.clone());
    let space_key_v1 = generate_key();
    let space_key_v2 = generate_key();
    let encrypted_asset =
        encrypt_asset_payload(&space_key_v1, b"avatar-image").expect("asset encryption");
    let spaces = server
        .mock("GET", "/account/space")
        .match_header("x-space-session-token", "space-session-token")
        .with_status(200)
        .with_body(owned_space_response(
            &space_root_key,
            &space_key_v2,
            "space_owner_main",
            "owner-main",
            2,
        ))
        .create_async()
        .await;
    let versions = server
        .mock("GET", "/spaces/space_owner_main/versions")
        .match_header("x-space-session-token", "space-session-token")
        .with_status(200)
        .with_body(
            json!([{
                "version": 2,
                "wrappedPrevKey": encode_b64(
                    &encrypt_secretbox_payload(&space_key_v2, &space_key_v1)
                        .expect("previous key wrap")
                ),
                "createdAt": "2026-04-16T00:00:00Z"
            }])
            .to_string(),
        )
        .create_async()
        .await;
    let redirect = server
        .mock("GET", "/spaces/space_owner_main/assets/redirect")
        .match_header("x-space-session-token", "space-session-token")
        .match_query(Matcher::AllOf(vec![
            Matcher::UrlEncoded("assetType".into(), "avatar".into()),
            Matcher::UrlEncoded("objectID".into(), "avatar-object".into()),
        ]))
        .with_status(200)
        .with_body(
            json!({
                "url": format!("{}/objects/avatar-object", server.url()),
                "expiresIn": 900
            })
            .to_string(),
        )
        .create_async()
        .await;
    let object = server
        .mock("GET", "/objects/avatar-object")
        .with_status(200)
        .with_body(encrypted_asset)
        .create_async()
        .await;

    let bytes = ctx
        .download_profile_asset("space_owner_main", None, "avatar", "avatar-object", 1)
        .await
        .expect("avatar asset should download and decrypt");

    assert_eq!(bytes, b"avatar-image");
    spaces.assert_async().await;
    versions.assert_async().await;
    redirect.assert_async().await;
    object.assert_async().await;
}

#[tokio::test]
async fn create_space_with_key_sends_encrypted_space_and_profile_payloads() {
    let mut server = Server::new_async().await;
    let space_root_key = generate_key();
    let ctx = test_account_ctx_with_space_root_key(&server.url(), space_root_key);
    let space_key = generate_key();
    let create_space = server
        .mock("POST", "/account/space")
        .match_header("x-space-session-token", "space-session-token")
        .match_body(Matcher::AllOf(vec![
            Matcher::Regex("\"spaceSlug\":\"owner-main\"".into()),
            Matcher::Regex("\"rootWrappedSpaceKey\":\"[^\"]+\"".into()),
            Matcher::Regex("\"publicKey\":\"[^\"]+\"".into()),
            Matcher::Regex("\"encryptedSecretKey\":\"[^\"]+\"".into()),
            Matcher::Regex("\"encryptedProfile\":\"[^\"]+\"".into()),
            Matcher::Regex("\"referredBySpaceId\":\"space_source_owner\"".into()),
        ]))
        .with_status(200)
        .with_body(
            json!({
                "spaceId": "space_owner_main",
                "spaceSlug": "owner-main",
                "rootWrappedSpaceKey": "",
                "encryptedProfile": "",
                "keyVersion": 1
            })
            .to_string(),
        )
        .create_async()
        .await;

    let created = ctx
        .create_space_with_key_and_referrer(
            "owner-main",
            &space_key,
            b"profile-json",
            Some("space_source_owner"),
        )
        .await
        .expect("space should be created");

    assert_eq!(created.space_id, "space_owner_main");
    assert_eq!(created.space_slug, "owner-main");
    assert_eq!(created.key_version, 1);
    let profile_plaintext =
        decrypt_secretbox_payload(&space_key, &decode_b64(&created.encrypted_profile).unwrap())
            .expect("created profile should decrypt");
    assert_eq!(profile_plaintext, b"profile-json");
    create_space.assert_async().await;
}

#[tokio::test]
async fn create_space_preserves_api_error_code() {
    let mut server = Server::new_async().await;
    let ctx = test_account_ctx(&server.url());
    let create_space = server
        .mock("POST", "/account/space")
        .with_status(409)
        .with_body(json!({ "code": "CONFLICT" }).to_string())
        .create_async()
        .await;

    let error = match ctx
        .create_space_with_key("owner-main", &generate_key(), b"profile-json")
        .await
    {
        Ok(_) => panic!("space creation should fail"),
        Err(error) => error,
    };

    assert!(matches!(
        error,
        SpaceError::Http(ente_core::http::Error::Api {
            status: 409,
            ref code,
            ..
        }) if code == "CONFLICT"
    ));
    create_space.assert_async().await;
}

#[tokio::test]
async fn update_space_slug_preserves_api_error_code() {
    let mut server = Server::new_async().await;
    let ctx = test_account_ctx(&server.url());
    let update_slug = server
        .mock("PUT", "/spaces/space_owner_main/slug")
        .with_status(409)
        .with_body(json!({ "code": "ALREADY_EXISTS" }).to_string())
        .create_async()
        .await;

    let error = ctx
        .update_space_slug("space_owner_main", "taken")
        .await
        .expect_err("slug update should fail");

    assert!(matches!(
        error,
        SpaceError::Http(ente_core::http::Error::Api {
            status: 409,
            ref code,
            ..
        }) if code == "ALREADY_EXISTS"
    ));
    update_slug.assert_async().await;
}

#[tokio::test]
async fn create_space_updates_loaded_owned_space_cache() {
    let mut server = Server::new_async().await;
    let space_root_key = generate_key();
    let ctx = test_account_ctx_with_space_root_key(&server.url(), space_root_key);
    let space_key = generate_key();
    let list_spaces = server
        .mock("GET", "/account/space")
        .match_header("x-space-session-token", "space-session-token")
        .with_status(200)
        .with_body("[]")
        .expect(1)
        .create_async()
        .await;
    let create_space = server
        .mock("POST", "/account/space")
        .match_header("x-space-session-token", "space-session-token")
        .with_status(200)
        .with_body(
            json!({
                "spaceId": "space_owner_main",
                "spaceSlug": "owner-main",
                "rootWrappedSpaceKey": "",
                "encryptedProfile": "",
                "keyVersion": 1
            })
            .to_string(),
        )
        .create_async()
        .await;
    let update_profile = server
        .mock("POST", "/spaces/space_owner_main/profile")
        .match_header("x-space-session-token", "space-session-token")
        .match_body(Matcher::AllOf(vec![Matcher::Regex(
            "\"encryptedProfile\":\"[^\"]+\"".into(),
        )]))
        .with_status(200)
        .with_body(json!({ "status": "ok" }).to_string())
        .create_async()
        .await;

    let spaces = ctx
        .list_owned_spaces()
        .await
        .expect("space list should load");
    assert!(spaces.is_empty());

    let created = ctx
        .create_space_with_key("owner-main", &space_key, b"profile-json")
        .await
        .expect("space should be created");
    ctx.update_space_profile(&created.space_id, b"profile-json-2", None, false)
        .await
        .expect("created space should be available from cache");
    let cached = ctx
        .list_owned_spaces()
        .await
        .expect("owned space cache should remain usable");
    let cached_profile = decrypt_secretbox_payload(
        &space_key,
        &decode_b64(&cached[0].encrypted_profile).unwrap(),
    )
    .expect("cached profile should decrypt");
    assert_eq!(cached_profile.as_slice(), b"profile-json-2");

    list_spaces.assert_async().await;
    create_space.assert_async().await;
    update_profile.assert_async().await;
}

#[tokio::test]
async fn list_owned_spaces_reuses_loaded_cache() {
    let mut server = Server::new_async().await;
    let ctx = test_account_ctx(&server.url());
    let space_root_key = generate_key();
    let space_key = generate_key();
    let list_spaces = server
        .mock("GET", "/account/space")
        .match_header("x-space-session-token", "space-session-token")
        .with_status(200)
        .with_body(owned_space_response(
            &space_root_key,
            &space_key,
            "space_owner_main",
            "owner-main",
            3,
        ))
        .expect(1)
        .create_async()
        .await;

    let first = ctx
        .list_owned_spaces()
        .await
        .expect("space list should load");
    let second = ctx
        .list_owned_spaces()
        .await
        .expect("space list should reuse cache");

    assert_eq!(first.len(), 1);
    assert_eq!(second.len(), 1);
    assert_eq!(second[0].space_id, first[0].space_id);
    assert_eq!(second[0].space_slug, first[0].space_slug);
    assert_eq!(
        second[0].root_wrapped_space_key,
        first[0].root_wrapped_space_key
    );
    assert_eq!(second[0].key_version, first[0].key_version);
    list_spaces.assert_async().await;
}

#[tokio::test]
async fn create_post_includes_space_key_version() {
    let mut server = Server::new_async().await;
    let space_root_key = generate_key();
    let ctx = test_account_ctx_with_space_root_key(&server.url(), space_root_key.clone());
    let space_key = generate_key();
    let spaces = server
            .mock("GET", "/account/space")
            .match_header("x-space-session-token", "space-session-token")
            .with_status(200)
            .with_body(
                json!([{
                    "spaceId": "space_owner_main",
                    "spaceSlug": "owner-main",
                    "rootWrappedSpaceKey": encode_b64(&encrypt_secretbox_payload(&space_root_key, &space_key).expect("space key wrap")),
                    "encryptedProfile": "",
                    "keyVersion": 3
                }])
                .to_string(),
            )
            .create_async()
            .await;
    let create = server
        .mock("POST", "/spaces/space_owner_main/posts")
        .match_header("x-space-session-token", "space-session-token")
        .match_body(Matcher::Regex("\"keyVersion\":3".into()))
        .with_status(200)
        .with_body(json!({"postId": 42}).to_string())
        .create_async()
        .await;

    let (post_id, _) = ctx
        .create_post("space_owner_main", &[], None, None)
        .await
        .expect("post creation should send key version");

    assert_eq!(post_id, 42);
    spaces.assert_async().await;
    create.assert_async().await;
}

#[tokio::test]
async fn create_post_rejects_video_object_media_type() {
    let server = Server::new_async().await;
    let ctx = test_account_ctx(&server.url());
    let post_key = generate_key();
    let metadata_cipher = encrypt_post_object_metadata(
        &post_key,
        &PostObjectMetadata {
            width: Some(1920),
            height: Some(1080),
            media_type: Some("video/mp4".to_owned()),
            ..Default::default()
        },
    )
    .expect("metadata should encrypt");
    let err = ctx
        .create_post(
            "space_owner_main",
            &[PostObjectPayload {
                object_key: "object-1".to_owned(),
                size: None,
                position: Some(0),
                metadata_cipher: Some(metadata_cipher),
            }],
            None,
            Some(&post_key),
        )
        .await
        .expect_err("video post object should fail before network");

    assert!(err.to_string().contains(ONLY_PHOTOS_UPLOAD_MESSAGE));
}

#[tokio::test]
async fn update_space_profile_sends_encrypted_profile_and_profile_assets() {
    let mut server = Server::new_async().await;
    let space_root_key = generate_key();
    let ctx = test_account_ctx_with_space_root_key(&server.url(), space_root_key.clone());
    let space_key = generate_key();
    let spaces = server
        .mock("GET", "/account/space")
        .match_header("x-space-session-token", "space-session-token")
        .with_status(200)
        .with_body(owned_space_response(
            &space_root_key,
            &space_key,
            "space_owner_main",
            "owner-main",
            3,
        ))
        .create_async()
        .await;
    let update = server
        .mock("POST", "/spaces/space_owner_main/profile")
        .match_header("x-space-session-token", "space-session-token")
        .match_body(Matcher::AllOf(vec![
            Matcher::Regex("\"keyVersion\":3".into()),
            Matcher::Regex("\"encryptedProfile\":\"[^\"]+\"".into()),
            Matcher::Regex("\"avatar\"".into()),
            Matcher::Regex("\"objectID\":\"avatar-object\"".into()),
            Matcher::Regex("\"size\":123".into()),
            Matcher::Regex("\"cover\"".into()),
            Matcher::Regex("\"objectID\":\"cover-object\"".into()),
            Matcher::Regex("\"size\":456".into()),
        ]))
        .with_status(200)
        .with_body(
            json!({
                "status": "ok",
                "avatar": {
                    "objectID": "avatar-object",
                    "keyVersion": 3,
                    "size": 123,
                    "updatedAt": "2026-04-16T00:00:00Z"
                },
                "cover": {
                    "objectID": "cover-object",
                    "keyVersion": 3,
                    "size": 456,
                    "updatedAt": "2026-04-16T00:00:00Z"
                }
            })
            .to_string(),
        )
        .create_async()
        .await;

    let response = ctx
        .update_space_profile_assets(
            "space_owner_main",
            b"profile-v2",
            Some(ProfileAvatarPayload {
                object_id: "avatar-object".to_owned(),
                size: Some(123),
            }),
            Some(ProfileCoverPayload {
                object_id: "cover-object".to_owned(),
                size: Some(456),
            }),
            false,
            false,
        )
        .await
        .expect("profile update should succeed");

    assert_eq!(response.status, "ok");
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
        Some(3)
    );
    assert_eq!(
        response.cover.as_ref().map(|cover| cover.key_version),
        Some(3)
    );
    spaces.assert_async().await;
    update.assert_async().await;
}

#[tokio::test]
async fn get_space_profile_decrypted_loads_and_decrypts_profile() {
    let mut server = Server::new_async().await;
    let space_root_key = generate_key();
    let ctx = test_account_ctx_with_space_root_key(&server.url(), space_root_key.clone());
    let space_key = generate_key();
    let encrypted_profile =
        encode_b64(&encrypt_secretbox_payload(&space_key, b"profile-json").expect("profile wrap"));
    let profile = server
        .mock("GET", "/spaces/space_owner_main/profile")
        .match_header("x-space-session-token", "space-session-token")
        .with_status(200)
        .with_body(
            json!({
                "spaceId": "space_owner_main",
                "spaceSlug": "owner-main",
                "version": 3,
                "friends": 2,
                "encryptedProfile": encrypted_profile,
                "updatedAt": "2026-04-16T00:00:00Z"
            })
            .to_string(),
        )
        .create_async()
        .await;
    let spaces = server
        .mock("GET", "/account/space")
        .match_header("x-space-session-token", "space-session-token")
        .with_status(200)
        .with_body(owned_space_response(
            &space_root_key,
            &space_key,
            "space_owner_main",
            "owner-main",
            3,
        ))
        .create_async()
        .await;

    let decrypted = ctx
        .get_space_profile_decrypted("space_owner_main", None, None)
        .await
        .expect("profile should decrypt");

    assert_eq!(decrypted.space_id, "space_owner_main");
    assert_eq!(decrypted.space_slug, "owner-main");
    assert_eq!(decrypted.version, 3);
    assert_eq!(decrypted.friends, 2);
    assert_eq!(decrypted.profile, b"profile-json");
    profile.assert_async().await;
    spaces.assert_async().await;
}

#[tokio::test]
async fn space_status_mutations_accept_empty_server_responses() {
    let mut server = Server::new_async().await;
    let ctx = test_account_ctx(&server.url());

    let delete_post = server
        .mock("DELETE", "/spaces/space_viewer_main/posts/42")
        .match_header("x-space-session-token", "space-session-token")
        .with_status(200)
        .create_async()
        .await;
    let unfriend_space = server
        .mock("POST", "/spaces/space_viewer_main/friends/unfriend")
        .match_header("x-space-session-token", "space-session-token")
        .match_body(Matcher::JsonString(
            json!({"targetSpaceId": "space_owner_main"}).to_string(),
        ))
        .with_status(200)
        .create_async()
        .await;
    let unfriend_username = server
        .mock("POST", "/spaces/space_viewer_main/friends/unfriend")
        .match_header("x-space-session-token", "space-session-token")
        .match_body(Matcher::JsonString(
            json!({"targetUsername": "owner"}).to_string(),
        ))
        .with_status(200)
        .create_async()
        .await;

    ctx.delete_post("space_viewer_main", 42)
        .await
        .expect("delete post should accept empty response");
    ctx.unfriend_by_space("space_viewer_main", "space_owner_main")
        .await
        .expect("unfriend by space should accept empty response");
    ctx.unfriend_by_username("space_viewer_main", "owner")
        .await
        .expect("unfriend by username should accept empty response");

    delete_post.assert_async().await;
    unfriend_space.assert_async().await;
    unfriend_username.assert_async().await;
}

#[tokio::test]
async fn update_post_caption_uses_caption_endpoint() {
    let mut server = Server::new_async().await;
    let ctx = test_account_ctx(&server.url());
    let update = server
        .mock("POST", "/spaces/space_owner_main/posts/42/caption")
        .match_header("x-space-session-token", "space-session-token")
        .match_body(Matcher::AllOf(vec![Matcher::Regex(
            "\"captionCipher\":\"[^\"]+\"".into(),
        )]))
        .with_status(200)
        .create_async()
        .await;

    ctx.update_post_caption(
        "space_owner_main",
        42,
        &generate_key(),
        Some(b"updated caption".as_slice()),
    )
    .await
    .expect("caption update should succeed");

    update.assert_async().await;
}

#[tokio::test]
async fn like_post_uses_post_like_endpoint() {
    let mut server = Server::new_async().await;
    let ctx = test_account_ctx(&server.url());
    let like = server
        .mock("PUT", "/spaces/space_owner_main/posts/42/like")
        .match_header("x-space-session-token", "space-session-token")
        .with_status(200)
        .with_body(json!({"liked": true}).to_string())
        .create_async()
        .await;

    let response = ctx
        .like_post("space_owner_main", 42, true)
        .await
        .expect("post like should succeed");

    assert!(response.liked);
    like.assert_async().await;
}

#[tokio::test]
async fn unread_methods_use_read_marker_endpoints() {
    let mut server = Server::new_async().await;
    let ctx = test_account_ctx(&server.url());
    let status = server
        .mock("GET", "/spaces/space_owner_main/unread")
        .match_header("x-space-session-token", "space-session-token")
        .with_status(200)
        .with_body(json!({"notificationsUnread": false}).to_string())
        .create_async()
        .await;
    let notifications_read = server
        .mock("POST", "/spaces/space_owner_main/friends/space_friend/read")
        .match_header("x-space-session-token", "space-session-token")
        .with_status(200)
        .with_body(json!({"notificationsUnread": false}).to_string())
        .create_async()
        .await;

    let unread = ctx
        .unread_status("space_owner_main")
        .await
        .expect("unread status should load");
    assert!(!unread.notifications_unread);
    assert!(
        !ctx.mark_notifications_read("space_owner_main", "space_friend")
            .await
            .expect("notifications read")
            .notifications_unread
    );

    status.assert_async().await;
    notifications_read.assert_async().await;
}

#[tokio::test]
async fn message_actions_use_message_endpoints() {
    let mut server = Server::new_async().await;
    let space_root_key = generate_key();
    let ctx = test_account_ctx_with_space_root_key(&server.url(), space_root_key.clone());
    let (friend_public_key, _) = generate_keypair().expect("valid friend keypair");

    let friends = server
        .mock("GET", "/spaces/space_owner_main/friends")
        .match_header("x-space-session-token", "space-session-token")
        .with_status(200)
        .with_body(
            json!([{
                "friend": {
                    "spaceId": "space_friend",
                    "spaceSlug": "friend",
                    "publicKey": encode_b64(&friend_public_key),
                    "keyVersion": 2
                },
                "shareKeyVersion": 2,
                "createdAt": "2026-04-16T00:00:00Z"
            }])
            .to_string(),
        )
        .create_async()
        .await;
    let reply = server
        .mock(
            "POST",
            "/spaces/space_owner_main/friends/space_friend/messages",
        )
        .match_header("x-space-session-token", "space-session-token")
        .match_body(Matcher::AllOf(vec![
            Matcher::Regex("\"replyMessageId\":\"wmsg_parent\"".into()),
            Matcher::Regex("\"messageCipher\":\"[^\"]+\"".into()),
            Matcher::Regex("\"senderEncryptedMessageKey\":\"[^\"]+\"".into()),
            Matcher::Regex("\"recipientEncryptedMessageKey\":\"[^\"]+\"".into()),
        ]))
        .with_status(200)
        .with_body(
            json!({
                "messageId": "wmsg_reply",
                "kind": "regular",
                "senderSpaceId": "space_owner_main",
                "recipientSpaceId": "space_friend",
                "messageCipher": "cipher",
                "encryptedMessageKey": "key",
                "replyMessageId": "wmsg_parent",
                "liked": false,
                "viewerLiked": false,
                "isDeleted": false,
                "createdAt": "2026-04-16T00:00:00Z",
                "updatedAt": "2026-04-16T00:00:00Z"
            })
            .to_string(),
        )
        .create_async()
        .await;
    let like = server
        .mock("PUT", "/spaces/space_owner_main/messages/wmsg_reply/like")
        .match_header("x-space-session-token", "space-session-token")
        .with_status(200)
        .with_body(json!({"liked": true}).to_string())
        .create_async()
        .await;
    let delete = server
        .mock("DELETE", "/spaces/space_owner_main/messages/wmsg_reply")
        .match_header("x-space-session-token", "space-session-token")
        .with_status(200)
        .create_async()
        .await;

    let created = ctx
        .reply_to_message("space_owner_main", "space_friend", "wmsg_parent", "hello")
        .await
        .expect("message reply should be sent");
    let liked = ctx
        .like_message("space_owner_main", "wmsg_reply", true)
        .await
        .expect("message like should be sent");
    ctx.delete_message("space_owner_main", "wmsg_reply")
        .await
        .expect("message delete should be sent");

    assert_eq!(created.reply_message_id.as_deref(), Some("wmsg_parent"));
    assert!(liked.liked);
    friends.assert_async().await;
    reply.assert_async().await;
    like.assert_async().await;
    delete.assert_async().await;
}

#[test]
fn message_payload_limits_reject_oversized_text_and_payload() {
    let valid = MessagePayload {
        version: 1,
        kind: MESSAGE_KIND_REGULAR.to_owned(),
        text: "hello".to_owned(),
    };
    let valid_plaintext = serde_json::to_vec(&valid).expect("valid payload json");
    validate_message_payload(&valid, valid_plaintext.len())
        .expect("short message should be accepted");

    let too_many_chars = MessagePayload {
        text: "a".repeat(MAX_SPACE_MESSAGE_TEXT_CHARS + 1),
        ..valid.clone()
    };
    let plaintext = serde_json::to_vec(&too_many_chars).expect("long text json");
    let err = validate_message_payload(&too_many_chars, plaintext.len())
        .expect_err("long message text should be rejected");
    assert!(err.to_string().contains("characters or fewer"));

    let err = validate_message_payload(&valid, MAX_SPACE_MESSAGE_PAYLOAD_BYTES + 1)
        .expect_err("large serialized payload should be rejected");
    assert!(err.to_string().contains("payload must be"));
}

#[tokio::test]
async fn list_space_friends_uses_space_friends_endpoint() {
    let mut server = Server::new_async().await;
    let ctx = test_account_ctx(&server.url());
    let friends = server
        .mock("GET", "/spaces/space_owner_main/friends")
        .match_header("x-space-session-token", "space-session-token")
        .with_status(200)
        .with_body(
            json!([{
                "friend": {
                    "spaceId": "space_friend",
                    "spaceSlug": "friend",
                    "publicKey": "friend-public-key",
                    "keyVersion": 2,
                    "encryptedProfile": "profile-cipher"
                },
                "shareKeyVersion": 2,
                "createdAt": "2026-04-16T00:00:00Z"
            }])
            .to_string(),
        )
        .create_async()
        .await;

    let response = ctx
        .list_space_friends("space_owner_main")
        .await
        .expect("friends should load");

    assert_eq!(response.len(), 1);
    assert_eq!(response[0].friend.space_id, "space_friend");
    assert_eq!(response[0].share_key_version, 2);
    friends.assert_async().await;
}

#[tokio::test]
async fn get_relationship_uses_relationship_endpoint() {
    let mut server = Server::new_async().await;
    let ctx = test_account_ctx(&server.url());
    let relationship = server
        .mock("GET", "/spaces/space_owner_main/friends/relationship")
        .match_header("x-space-session-token", "space-session-token")
        .match_query(Matcher::AllOf(vec![Matcher::UrlEncoded(
            "targetSpaceId".into(),
            "space_friend".into(),
        )]))
        .with_status(200)
        .with_body(json!({"relationship": "friend"}).to_string())
        .create_async()
        .await;

    let response = ctx
        .get_relationship("space_owner_main", "space_friend")
        .await
        .expect("relationship should load");

    assert_eq!(response.relationship, "friend");
    relationship.assert_async().await;
}

#[tokio::test]
async fn refresh_friend_shares_accepts_empty_server_response() {
    let mut server = Server::new_async().await;
    let space_root_key = generate_key();
    let ctx = test_account_ctx_with_space_root_key(&server.url(), space_root_key.clone());
    let space_key = generate_key();
    let (friend_public_key, _) = generate_keypair().expect("valid friend keypair");

    let spaces = server
            .mock("GET", "/account/space")
            .match_header("x-space-session-token", "space-session-token")
            .with_status(200)
            .with_body(
                json!([{
                    "spaceId": "space_owner_main",
                    "spaceSlug": "owner-main",
                    "rootWrappedSpaceKey": encode_b64(&encrypt_secretbox_payload(&space_root_key, &space_key).expect("space key wrap")),
                    "encryptedProfile": "",
                    "keyVersion": 3
                }])
                .to_string(),
            )
            .create_async()
            .await;
    let friends = server
        .mock("GET", "/spaces/space_owner_main/friends")
        .match_header("x-space-session-token", "space-session-token")
        .with_status(200)
        .with_body(
            json!([{
                "friend": {
                    "spaceId": "space_viewer",
                    "spaceSlug": "viewer",
                    "publicKey": encode_b64(&friend_public_key),
                    "keyVersion": 2
                },
                "shareKeyVersion": 2,
                "createdAt": "2026-04-16T00:00:00Z"
            }])
            .to_string(),
        )
        .create_async()
        .await;
    let refresh = server
        .mock("POST", "/spaces/space_owner_main/friends/shares/refresh")
        .match_header("x-space-session-token", "space-session-token")
        .match_body(Matcher::AllOf(vec![
            Matcher::Regex("\"friendSpaceId\":\"space_viewer\"".into()),
            Matcher::Regex("\"keyVersion\":3".into()),
        ]))
        .with_status(200)
        .create_async()
        .await;

    let updated = ctx
        .refresh_friend_shares("space_owner_main")
        .await
        .expect("refresh should accept empty response");

    assert_eq!(updated, 1);
    spaces.assert_async().await;
    friends.assert_async().await;
    refresh.assert_async().await;
}

#[tokio::test]
async fn list_feed_uses_space_feed_endpoint() {
    let mut server = Server::new_async().await;
    let ctx = test_account_ctx(&server.url());
    let feed = server
        .mock("GET", "/spaces/space_owner_main/feed")
        .match_header("x-space-session-token", "space-session-token")
        .match_query(Matcher::AllOf(vec![
            Matcher::UrlEncoded("cursor".into(), "cursor-1".into()),
            Matcher::UrlEncoded("limit".into(), "5".into()),
        ]))
        .with_status(200)
        .with_body(
            json!({
                "items": [{
                    "postId": 42,
                    "spaceId": "space_owner_main",
                    "spaceSlug": "owner-main",
                    "author": {
                        "spaceId": "space_owner_gallery",
                        "spaceSlug": "owner-gallery"
                    },
                    "encryptedPostKey": "cGFja2Vk",
                    "captionCipher": "",
                    "keyVersion": 3,
                    "objects": [],
                    "createdAt": "2026-04-16T00:00:00Z",
                    "viewerLiked": true
                }],
                "nextCursor": "cursor-2"
            })
            .to_string(),
        )
        .create_async()
        .await;

    let page = ctx
        .list_feed("space_owner_main", Some("cursor-1".to_owned()), Some(5))
        .await
        .expect("feed page should load");

    assert_eq!(page.items.len(), 1);
    assert_eq!(page.items[0].post_id, 42);
    assert_eq!(page.next_cursor, "cursor-2");
    feed.assert_async().await;
}

#[tokio::test]
async fn list_posts_uses_space_posts_page_endpoint() {
    let mut server = Server::new_async().await;
    let ctx = test_account_ctx(&server.url());
    let posts = server
        .mock("GET", "/spaces/space_owner_gallery/posts")
        .match_header("x-space-session-token", "space-session-token")
        .match_query(Matcher::AllOf(vec![
            Matcher::UrlEncoded("viewerSpaceId".into(), "space_owner_main".into()),
            Matcher::UrlEncoded("cursor".into(), "42".into()),
            Matcher::UrlEncoded("limit".into(), "5".into()),
        ]))
        .with_status(200)
        .with_body(
            json!({
                "items": [{
                    "postId": 41,
                    "spaceId": "space_owner_main",
                    "spaceSlug": "owner-main",
                    "author": {
                        "spaceId": "space_owner_gallery",
                        "spaceSlug": "owner-gallery"
                    },
                    "encryptedPostKey": "cGFja2Vk",
                    "captionCipher": "",
                    "keyVersion": 3,
                    "objects": [],
                    "createdAt": "2026-04-16T00:00:00Z",
                    "viewerLiked": true
                }],
                "nextCursor": "41"
            })
            .to_string(),
        )
        .create_async()
        .await;

    let page = ctx
        .list_posts(
            "space_owner_gallery",
            Some("space_owner_main"),
            Some("42".to_owned()),
            Some(5),
        )
        .await
        .expect("post page should load");

    assert_eq!(page.items.len(), 1);
    assert_eq!(page.items[0].post_id, 41);
    assert_eq!(page.next_cursor, "41");
    posts.assert_async().await;
}

#[tokio::test]
async fn fetch_post_decrypted_uses_post_by_id_endpoint() {
    let mut server = Server::new_async().await;
    let space_root_key = generate_key();
    let ctx = test_account_ctx_with_space_root_key(&server.url(), space_root_key.clone());
    let space_key = generate_key();
    let post_key = generate_key();
    let caption = b"hello from post";

    let spaces = server
            .mock("GET", "/account/space")
            .match_header("x-space-session-token", "space-session-token")
            .with_status(200)
            .with_body(
                json!([{
                    "spaceId": "space_owner_gallery",
                    "spaceSlug": "owner-gallery",
                    "rootWrappedSpaceKey": encode_b64(&encrypt_secretbox_payload(&space_root_key, &space_key).expect("space key wrap")),
                    "encryptedProfile": "",
                    "keyVersion": 3
                }])
                .to_string(),
            )
            .create_async()
            .await;
    let post = server
            .mock("GET", "/spaces/space_owner_gallery/posts/42")
            .match_header("x-space-session-token", "space-session-token")
            .with_status(200)
            .with_body(
                json!({
                    "postId": 42,
                    "spaceId": "space_owner_gallery",
                    "spaceSlug": "owner-gallery",
                    "author": {
                        "spaceId": "space_owner_gallery",
                        "spaceSlug": "owner-gallery"
                    },
                    "encryptedPostKey": encode_b64(&encrypt_secretbox_payload(&space_key, &post_key).expect("post key wrap")),
                    "captionCipher": encode_b64(&encrypt_secretbox_payload(&post_key, caption).expect("caption wrap")),
                    "keyVersion": 3,
                    "objects": [],
                    "createdAt": "2026-04-16T00:00:00Z",
                    "viewerLiked": false
                })
                .to_string(),
            )
            .create_async()
            .await;

    let decrypted = ctx
        .fetch_post_decrypted("space_owner_gallery", 42, None)
        .await
        .expect("post should decrypt");

    assert_eq!(decrypted.post_key, post_key);
    assert_eq!(
        decrypted.caption_plaintext.as_deref(),
        Some(caption.as_slice())
    );
    spaces.assert_async().await;
    post.assert_async().await;
}

#[tokio::test]
async fn hydrate_space_keys_loads_owned_and_friends_spaces() {
    let mut server = Server::new_async().await;
    let space_root_key = generate_key();
    let ctx = test_account_ctx_with_space_root_key(&server.url(), space_root_key.clone());
    let owned_space_key = generate_key();
    let shared_space_key = generate_key();
    let sealed_share = seal_with_public_key(&shared_space_key, &test_public_key(&ctx))
        .expect("sealed space share");

    let owned = server
        .mock("GET", "/account/space")
        .match_header("x-space-session-token", "space-session-token")
        .with_status(200)
        .with_body(
            json!([{
                "spaceId": "space_owner_main",
                "spaceSlug": "owner-main",
                "rootWrappedSpaceKey": encode_b64(&encrypt_secretbox_payload(&space_root_key, &owned_space_key).expect("owned wrap")),
                "encryptedProfile": "",
                "keyVersion": 1
            }])
            .to_string(),
        )
        .create_async()
        .await;
    let shares = server
        .mock("GET", "/spaces/space_owner_main/friends/shares")
        .match_header("x-space-session-token", "space-session-token")
        .with_status(200)
        .with_body(
            json!([{
                "friend": "owner",
                "spaceId": "space_shared_gallery",
                "spaceSlug": "shared-gallery",
                "friendSealedSpaceKey": encode_b64(&sealed_share),
                "encryptedProfile": "",
                "keyVersion": 4
            }])
            .to_string(),
        )
        .create_async()
        .await;

    let hydrated = ctx
        .hydrate_space_keys()
        .await
        .expect("space keys should hydrate");

    assert_eq!(hydrated.owned.len(), 1);
    assert_eq!(hydrated.owned[0].0, "space_owner_main");
    assert_eq!(hydrated.owned[0].1, owned_space_key);
    assert_eq!(hydrated.friends.len(), 1);
    assert_eq!(hydrated.friends[0].space_id, "space_shared_gallery");
    assert_eq!(hydrated.friends[0].space_key, shared_space_key);
    owned.assert_async().await;
    shares.assert_async().await;
}

#[test]
fn build_history_walks_back_versions() {
    let v3 = generate_key();
    let v2 = generate_key();
    let v1 = generate_key();
    let versions = vec![
        SpaceKeyVersionResponse {
            version: 3,
            wrapped_prev_key: encode_b64(&encrypt_secretbox_payload(&v3, &v2).expect("wrap v2")),
            created_at: "2026-01-03T00:00:00Z".to_owned(),
        },
        SpaceKeyVersionResponse {
            version: 2,
            wrapped_prev_key: encode_b64(&encrypt_secretbox_payload(&v2, &v1).expect("wrap v1")),
            created_at: "2026-01-02T00:00:00Z".to_owned(),
        },
    ];

    let history = build_space_key_history_map(3, &v3, &versions).expect("history");

    assert_eq!(history.get(&3), Some(&v3));
    assert_eq!(history.get(&2), Some(&v2));
    assert_eq!(history.get(&1), Some(&v1));
}
