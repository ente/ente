//! Shared test fixtures for the `client` modules.
//!
//! Helpers for constructing test contexts and canned server responses, used by
//! the per-module `#[cfg(test)] mod tests`. Gated on `cfg(test)`, so none of
//! this is compiled into the library.

use serde_json::json;

use super::{AccountSpaceCtx, SpaceIdentity, cache_lock, generate_key, generate_keypair};
use crate::crypto::encrypt_secretbox_payload;
use crate::models::OpenAccountSpaceCtxInput;
use ente_core::{b64, crypto::SecretVec};

/// A WEBP magic-number header, enough for the media sniffer to accept the bytes
/// as a photo.
pub(crate) const TEST_WEBP_BYTES: &[u8] = b"RIFF0000WEBP";
/// An MP4 `ftyp` header, used to assert that video bytes are rejected.
pub(crate) const TEST_MP4_BYTES: &[u8] = b"\0\0\0\x18ftypmp42";

/// Open an [`AccountSpaceCtx`] against `base_url` with a random Space root key
/// and a pre-seeded Space identity, so tests skip the identity round-trip.
pub(crate) fn test_account_ctx(base_url: &str) -> AccountSpaceCtx {
    test_account_ctx_with_space_root_key(base_url, generate_key())
}

/// Like [`test_account_ctx`] but with a caller-supplied Space root key, for
/// tests that need to wrap keys under a known root.
pub(crate) fn test_account_ctx_with_space_root_key(
    base_url: &str,
    space_root_key: Vec<u8>,
) -> AccountSpaceCtx {
    let (public_key, secret_key) = generate_keypair().expect("valid keypair");
    let ctx = AccountSpaceCtx::open(OpenAccountSpaceCtxInput {
        base_url: base_url.to_owned(),
        space_session_token: Some("space-session-token".to_owned()),
        space_root_key,
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

/// The public key of the identity seeded by [`test_account_ctx_with_space_root_key`].
pub(crate) fn test_public_key(ctx: &AccountSpaceCtx) -> Vec<u8> {
    cache_lock(&ctx.space_identity_cache, "space identity")
        .expect("space identity cache")
        .values()
        .next()
        .expect("test identity")
        .public_key
        .clone()
}

/// A canned `/space` owned-spaces list response wrapping `space_key` under
/// `space_root_key`.
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
