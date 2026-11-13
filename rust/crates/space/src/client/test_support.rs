use serde_json::json;

use super::{AccountSpaceCtx, SpaceIdentity, cache_lock, generate_key, generate_keypair};
use crate::crypto::encrypt_secretbox_payload;
use crate::models::OpenAccountSpaceCtxInput;
use ente_core::{b64, crypto::SecretVec};

pub(crate) const TEST_WEBP_BYTES: &[u8] = b"RIFF0000WEBP";
pub(crate) const TEST_MP4_BYTES: &[u8] = b"\0\0\0\x18ftypmp42";

pub(crate) fn test_account_ctx(base_url: &str) -> AccountSpaceCtx {
    test_account_ctx_with_space_root_key(base_url, generate_key())
}

pub(crate) fn test_account_ctx_with_space_root_key(
    base_url: &str,
    space_root_key: Vec<u8>,
) -> AccountSpaceCtx {
    let (public_key, secret_key) = generate_keypair().expect("valid keypair");
    let ctx = AccountSpaceCtx::open(OpenAccountSpaceCtxInput {
        base_url: base_url.to_owned(),
        space_session_token: Some("space-session-token".to_owned()),
        space_root_key,
        initial_owned_spaces: None,
        user_agent: None,
        client_package: None,
        client_version: None,
    })
    .expect("account space ctx should open");
    cache_lock(&ctx.space_identity_cache, "space identity")
        .expect("space identity cache")
        .insert(
            "space_owner_main".to_owned(),
            SpaceIdentity {
                public_key,
                secret_key: SecretVec::new(secret_key),
            },
        );
    ctx
}

pub(crate) fn test_public_key(ctx: &AccountSpaceCtx) -> Vec<u8> {
    cache_lock(&ctx.space_identity_cache, "space identity")
        .expect("space identity cache")
        .values()
        .next()
        .expect("test identity")
        .public_key
        .clone()
}

pub(crate) fn owned_space_response(
    space_root_key: &[u8],
    space_key: &[u8],
    space_id: &str,
    space_slug: &str,
    key_version: i32,
) -> String {
    json!([{
        "spaceId": space_id,
        "spaceSlug": space_slug,
        "rootWrappedSpaceKey": b64::encode(
            &encrypt_secretbox_payload(space_root_key, space_key).expect("space key wrap")
        ),
        "encryptedProfile": "",
        "keyVersion": key_version
    }])
    .to_string()
}
