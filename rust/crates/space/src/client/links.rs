use std::{collections::BTreeMap, sync::Mutex};

use ente_core::{
    b64,
    crypto::{self, Key, Salt, argon, kdf},
    http::Api,
};

use super::{
    AccountSpaceCtx, build_api, build_space_key_history_map, cache_lock, decrypt_space_profile,
};
use crate::{
    crypto::{decrypt_asset_payload, decrypt_secretbox_payload, encrypt_secretbox_payload},
    error::{Result, SpaceError},
    models::{CreatedSpaceLink, DecryptedPost, DecryptedSpaceProfile, OpenSpaceLinkCtxInput},
    transport::{
        AssetDownloadResponse, PostPage, PostResponse, SpaceKeyVersionResponse,
        SpaceLinkBootstrapResponse, SpaceLinkProfileResponse, SpaceLinkStatusResponse,
        SpaceLinkWriteRequest, WebPushSubscriptionKeys, WebPushSubscriptionRequest,
        WebPushTargetResponse, WebPushUnsubscriptionRequest,
    },
};

const ACCESS_KEY_LENGTH: usize = 12;
const ACCESS_KEY_ALPHABET: &[u8] =
    b"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
const AUTH_HEADER: &str = "X-Ente-Space-Link-Auth";
const AUTH_CONTEXT: &[u8; 8] = b"spacauth";
const WRAP_CONTEXT: &[u8; 8] = b"spacwrap";

struct DerivedLinkKeys {
    auth: Vec<u8>,
    wrap: Vec<u8>,
}

struct SpaceLinkSnapshot {
    profile: DecryptedSpaceProfile,
    posts: i64,
    key_history: BTreeMap<i32, Vec<u8>>,
}

pub(crate) struct SpaceLinkKeyRotation {
    pub(crate) expected_link_id: i64,
    pub(crate) encrypted_space_key: Option<String>,
}

pub struct SpaceLinkCtx {
    api: Api,
    space_slug: String,
    auth_key: String,
    wrap_key: Vec<u8>,
    profile: DecryptedSpaceProfile,
    posts: i64,
    key_history: Mutex<BTreeMap<i32, Vec<u8>>>,
}

impl AccountSpaceCtx {
    pub async fn get_or_create_space_link(&self, space_id: &str) -> Result<CreatedSpaceLink> {
        let status = self.get_space_link_status(space_id).await?;
        if status.active {
            return self.created_link_from_status(status);
        }
        self.write_space_link(space_id, false).await
    }

    pub async fn rotate_space_link(&self, space_id: &str) -> Result<CreatedSpaceLink> {
        self.write_space_link(space_id, true).await
    }

    pub(crate) async fn active_link_wrapper(
        &self,
        space_id: &str,
        next_space_key: &[u8],
    ) -> Result<SpaceLinkKeyRotation> {
        let status = self.get_space_link_status(space_id).await?;
        if !status.active {
            return Ok(SpaceLinkKeyRotation {
                expected_link_id: 0,
                encrypted_space_key: None,
            });
        }
        if status.link_id <= 0 {
            return Err(SpaceError::InvalidInput(
                "active space link is missing its ID".into(),
            ));
        }
        let access_key = self.decrypt_link_access_key(&status)?;
        let keys = derive_link_keys(
            &access_key,
            &status.kdf_salt,
            status.kdf_mem_limit,
            status.kdf_ops_limit,
        )?;
        Ok(SpaceLinkKeyRotation {
            expected_link_id: status.link_id,
            encrypted_space_key: Some(b64::encode(&encrypt_secretbox_payload(
                &keys.wrap,
                next_space_key,
            )?)),
        })
    }

    async fn get_space_link_status(&self, space_id: &str) -> Result<SpaceLinkStatusResponse> {
        let path = format!("/spaces/{space_id}/link");
        Ok(self
            .api()
            .get(&path)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?)
    }

    async fn write_space_link(&self, space_id: &str, rotate: bool) -> Result<CreatedSpaceLink> {
        let access = self
            .resolve_owned_space_access(space_id)
            .await?
            .ok_or_else(|| {
                SpaceError::InvalidInput(format!("space {space_id} is not owned by the account"))
            })?;
        let access_key = generate_access_key();
        let salt = Salt::generate();
        let keys = derive_link_keys_with_salt(&access_key, &salt, argon::Params::INTERACTIVE)?;
        let request = SpaceLinkWriteRequest {
            auth_key: b64::encode(&keys.auth),
            kdf_salt: b64::encode(salt.as_bytes()),
            kdf_mem_limit: argon::Params::INTERACTIVE.mem_limit,
            kdf_ops_limit: argon::Params::INTERACTIVE.ops_limit,
            key_version: access.key_version,
            encrypted_space_key: b64::encode(&encrypt_secretbox_payload(
                &keys.wrap,
                &access.space_key,
            )?),
            encrypted_access_key: b64::encode(&encrypt_secretbox_payload(
                self.space_root_key(),
                access_key.as_bytes(),
            )?),
        };
        let path = if rotate {
            format!("/spaces/{space_id}/link/rotate")
        } else {
            format!("/spaces/{space_id}/link")
        };
        let status: SpaceLinkStatusResponse = self
            .api()
            .post(&path)
            .json(&request)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        if status.encrypted_access_key == request.encrypted_access_key {
            Ok(CreatedSpaceLink {
                space_id: status.space_id,
                space_slug: status.space_slug,
                access_key,
            })
        } else {
            self.created_link_from_status(status)
        }
    }

    fn created_link_from_status(
        &self,
        status: SpaceLinkStatusResponse,
    ) -> Result<CreatedSpaceLink> {
        let access_key = self.decrypt_link_access_key(&status)?;
        Ok(CreatedSpaceLink {
            space_id: status.space_id,
            space_slug: status.space_slug,
            access_key,
        })
    }

    fn decrypt_link_access_key(&self, status: &SpaceLinkStatusResponse) -> Result<String> {
        let encrypted = b64::decode(&status.encrypted_access_key)?;
        let plaintext = decrypt_secretbox_payload(self.space_root_key(), &encrypted)?;
        let access_key = String::from_utf8(plaintext).map_err(|error| {
            SpaceError::InvalidInput(format!("invalid link access key: {error}"))
        })?;
        validate_access_key(&access_key)?;
        Ok(access_key)
    }
}

impl SpaceLinkCtx {
    pub async fn open(input: OpenSpaceLinkCtxInput) -> Result<Self> {
        validate_access_key(&input.access_key)?;
        let space_slug = input.space_slug.trim().to_lowercase();
        if space_slug.is_empty() {
            return Err(SpaceError::InvalidInput(
                "space username is required".into(),
            ));
        }
        let api = build_api(
            &input.base_url,
            None,
            input.user_agent,
            input.client_package,
            input.client_version,
        )?;
        let prefix = format!("/space/public/by-slug/{space_slug}/link");
        let bootstrap: SpaceLinkBootstrapResponse = api
            .get(&format!("{prefix}/bootstrap"))
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        let keys = derive_link_keys(
            &input.access_key,
            &bootstrap.kdf_salt,
            bootstrap.kdf_mem_limit,
            bootstrap.kdf_ops_limit,
        )?;
        let auth_key = b64::encode(&keys.auth);
        let snapshot = fetch_link_snapshot(&api, &prefix, &auth_key, &keys.wrap).await?;
        Ok(Self {
            api,
            space_slug,
            auth_key,
            wrap_key: keys.wrap,
            profile: snapshot.profile,
            posts: snapshot.posts,
            key_history: Mutex::new(snapshot.key_history),
        })
    }

    pub fn profile(&self) -> &DecryptedSpaceProfile {
        &self.profile
    }

    pub fn posts(&self) -> i64 {
        self.posts
    }

    pub async fn list_posts(&self) -> Result<PostPage> {
        let page: PostPage = self
            .api
            .get(&format!("{}/posts", self.prefix()))
            .header(AUTH_HEADER, &self.auth_key)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        if !self.has_keys_for_posts(&page)? {
            let snapshot =
                fetch_link_snapshot(&self.api, &self.prefix(), &self.auth_key, &self.wrap_key)
                    .await?;
            *cache_lock(&self.key_history, "space link key history")? = snapshot.key_history;
        }
        if !self.has_keys_for_posts(&page)? {
            return Err(SpaceError::InvalidInput(
                "space link changed while posts were being loaded".into(),
            ));
        }
        Ok(page)
    }

    pub async fn subscribe_web_push(
        &self,
        endpoint: String,
        p256dh: String,
        auth: String,
    ) -> Result<String> {
        let response: WebPushTargetResponse = self
            .api
            .put(&format!("{}/push/subscription", self.prefix()))
            .header(AUTH_HEADER, &self.auth_key)
            .json(&WebPushSubscriptionRequest {
                endpoint,
                keys: WebPushSubscriptionKeys { p256dh, auth },
            })
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        Ok(response.target_id)
    }

    pub async fn unsubscribe_web_push(&self, endpoint: String) -> Result<()> {
        self.api
            .delete(&format!("{}/push/subscription", self.prefix()))
            .header(AUTH_HEADER, &self.auth_key)
            .json(&WebPushUnsubscriptionRequest { endpoint })
            .send()
            .await?
            .error_for_status()?;
        Ok(())
    }

    pub fn decrypt_post(&self, post: &PostResponse) -> Result<DecryptedPost> {
        let space_key = self.space_key(post.key_version, "post")?;
        let post_key =
            decrypt_secretbox_payload(&space_key, &b64::decode(&post.encrypted_post_key)?)?;
        let caption_plaintext = if post.caption_cipher.is_empty() {
            None
        } else {
            Some(decrypt_secretbox_payload(
                &post_key,
                &b64::decode(&post.caption_cipher)?,
            )?)
        };
        Ok(DecryptedPost {
            post_key,
            caption_plaintext,
        })
    }

    pub async fn download_post_asset(
        &self,
        encrypted_post_key: &str,
        key_version: i32,
        object_key: &str,
    ) -> Result<Vec<u8>> {
        let space_key = self.space_key(key_version, "post")?;
        let post_key = decrypt_secretbox_payload(&space_key, &b64::decode(encrypted_post_key)?)?;
        self.download_asset(vec![("objectKey", object_key.to_owned())], &post_key)
            .await
    }

    pub async fn download_profile_asset(
        &self,
        asset_type: &str,
        object_id: &str,
        key_version: i32,
    ) -> Result<Vec<u8>> {
        let space_key = self.space_key(key_version, "profile")?;
        self.download_asset(
            vec![
                ("assetType", asset_type.to_owned()),
                ("objectID", object_id.to_owned()),
            ],
            &space_key,
        )
        .await
    }

    async fn download_asset(&self, query: Vec<(&str, String)>, key: &[u8]) -> Result<Vec<u8>> {
        let download: AssetDownloadResponse = self
            .api
            .get(&format!("{}/assets/redirect", self.prefix()))
            .query(&query)
            .header(AUTH_HEADER, &self.auth_key)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        let encrypted = self
            .api
            .http()
            .get(&download.url)
            .send()
            .await?
            .error_for_status()?
            .bytes()
            .await?;
        decrypt_asset_payload(key, &encrypted)
    }

    fn prefix(&self) -> String {
        format!("/space/public/by-slug/{}/link", self.space_slug)
    }

    fn has_keys_for_posts(&self, page: &PostPage) -> Result<bool> {
        let key_history = cache_lock(&self.key_history, "space link key history")?;
        Ok(page
            .items
            .iter()
            .all(|post| key_history.contains_key(&post.key_version)))
    }

    fn space_key(&self, key_version: i32, subject: &str) -> Result<Vec<u8>> {
        cache_lock(&self.key_history, "space link key history")?
            .get(&key_version)
            .cloned()
            .ok_or_else(|| SpaceError::InvalidInput(format!("missing space key for {subject}")))
    }
}

async fn fetch_link_snapshot(
    api: &Api,
    prefix: &str,
    auth_key: &str,
    wrap_key: &[u8],
) -> Result<SpaceLinkSnapshot> {
    for _ in 0..2 {
        let fetch_profile = async {
            Ok::<SpaceLinkProfileResponse, SpaceError>(
                api.get(&format!("{prefix}/profile"))
                    .header(AUTH_HEADER, auth_key)
                    .send()
                    .await?
                    .error_for_status()?
                    .json()
                    .await?,
            )
        };
        let fetch_versions = async {
            Ok::<Vec<SpaceKeyVersionResponse>, SpaceError>(
                api.get(&format!("{prefix}/versions"))
                    .header(AUTH_HEADER, auth_key)
                    .send()
                    .await?
                    .error_for_status()?
                    .json()
                    .await?,
            )
        };
        let (profile_response, versions) = futures_util::try_join!(fetch_profile, fetch_versions)?;
        let current_version = profile_response.key_version;
        let versions_current =
            versions.iter().map(|version| version.version).max() == Some(current_version);
        if profile_response.profile.version != current_version || !versions_current {
            continue;
        }
        let encrypted_space_key = b64::decode(&profile_response.encrypted_space_key)?;
        let space_key = decrypt_secretbox_payload(wrap_key, &encrypted_space_key)?;
        let profile = decrypt_space_profile(&profile_response.profile, &space_key)?;
        let key_history = build_space_key_history_map(current_version, &space_key, &versions)?;
        return Ok(SpaceLinkSnapshot {
            profile,
            posts: profile_response.posts,
            key_history,
        });
    }
    Err(SpaceError::InvalidInput(
        "space link changed while it was being opened".into(),
    ))
}

fn validate_access_key(access_key: &str) -> Result<()> {
    if access_key.len() == ACCESS_KEY_LENGTH
        && access_key.bytes().all(|byte| byte.is_ascii_alphanumeric())
    {
        Ok(())
    } else {
        Err(SpaceError::InvalidInput(
            "space link access key must be 12 alphanumeric characters".into(),
        ))
    }
}

fn generate_access_key() -> String {
    let threshold = 256 - (256 % ACCESS_KEY_ALPHABET.len());
    let mut access_key = String::with_capacity(ACCESS_KEY_LENGTH);
    while access_key.len() < ACCESS_KEY_LENGTH {
        for byte in crypto::random_bytes(ACCESS_KEY_LENGTH) {
            let byte = usize::from(byte);
            if byte >= threshold {
                continue;
            }
            access_key.push(char::from(
                ACCESS_KEY_ALPHABET[byte % ACCESS_KEY_ALPHABET.len()],
            ));
            if access_key.len() == ACCESS_KEY_LENGTH {
                break;
            }
        }
    }
    access_key
}

fn derive_link_keys(
    access_key: &str,
    encoded_salt: &str,
    mem_limit: u32,
    ops_limit: u32,
) -> Result<DerivedLinkKeys> {
    if mem_limit != argon::Params::INTERACTIVE.mem_limit
        || ops_limit != argon::Params::INTERACTIVE.ops_limit
    {
        return Err(SpaceError::InvalidInput(
            "unsupported space link KDF parameters".into(),
        ));
    }
    let salt_bytes = b64::decode(encoded_salt)?;
    let salt = Salt::try_from_slice(&salt_bytes)?;
    derive_link_keys_with_salt(
        access_key,
        &salt,
        argon::Params {
            mem_limit,
            ops_limit,
        },
    )
}

fn derive_link_keys_with_salt(
    access_key: &str,
    salt: &Salt,
    params: argon::Params,
) -> Result<DerivedLinkKeys> {
    validate_access_key(access_key)?;
    let root = argon::derive_key(access_key, salt, params)?;
    Ok(DerivedLinkKeys {
        auth: kdf::derive_subkey(&root, Key::BYTES, 1, AUTH_CONTEXT)?.to_vec(),
        wrap: kdf::derive_subkey(&root, Key::BYTES, 2, WRAP_CONTEXT)?.to_vec(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use mockito::{Matcher, Server};
    use serde_json::json;

    const WEB_PUSH_ENDPOINT: &str = "https://push.example/subscription";
    const WEB_PUSH_P256DH: &str =
        "BGsX0fLhLEJH-Lzm5WOkQPJ3A32BLeszoPShOUXYmMKWT-NC4v4af5uO5-tKfA-eFivOM1drMV7Oy7ZAaDe_UfU";
    const WEB_PUSH_AUTH: &str = "AAAAAAAAAAAAAAAAAAAAAA";

    #[test]
    fn generated_access_keys_are_valid() {
        for _ in 0..100 {
            validate_access_key(&generate_access_key()).unwrap();
        }
    }

    #[test]
    fn auth_and_wrap_keys_are_separate_and_stable() {
        let salt = Salt::from_bytes([7; Salt::BYTES]);
        let first =
            derive_link_keys_with_salt("5d2a9WhmD2NU", &salt, argon::Params::INTERACTIVE).unwrap();
        let second =
            derive_link_keys_with_salt("5d2a9WhmD2NU", &salt, argon::Params::INTERACTIVE).unwrap();
        assert_eq!(first.auth, second.auth);
        assert_eq!(first.wrap, second.wrap);
        assert_ne!(first.auth, first.wrap);
    }

    #[tokio::test]
    async fn public_link_opens_with_derived_auth_and_decrypts_profile() {
        let mut server = Server::new_async().await;
        let access_key = "5d2a9WhmD2NU";
        let salt = Salt::from_bytes([9; Salt::BYTES]);
        let keys =
            derive_link_keys_with_salt(access_key, &salt, argon::Params::INTERACTIVE).unwrap();
        let space_key = vec![4; Key::BYTES];
        let encrypted_space_key =
            b64::encode(&encrypt_secretbox_payload(&keys.wrap, &space_key).unwrap());
        let profile = br#"{"fullName":"Alice"}"#;
        let encrypted_profile =
            b64::encode(&encrypt_secretbox_payload(&space_key, profile).unwrap());
        let auth = b64::encode(&keys.auth);
        let prefix = "/space/public/by-slug/alice/link";

        let bootstrap = server
            .mock("GET", format!("{prefix}/bootstrap").as_str())
            .with_status(200)
            .with_body(
                json!({
                    "kdfSalt": b64::encode(salt.as_bytes()),
                    "kdfMemLimit": argon::Params::INTERACTIVE.mem_limit,
                    "kdfOpsLimit": argon::Params::INTERACTIVE.ops_limit,
                })
                .to_string(),
            )
            .create_async()
            .await;
        let profile_request = server
            .mock("GET", format!("{prefix}/profile").as_str())
            .match_header("x-ente-space-link-auth", auth.as_str())
            .with_status(200)
            .with_body(
                json!({
                    "encryptedSpaceKey": encrypted_space_key,
                    "keyVersion": 1,
                    "posts": 3,
                    "profile": {
                        "spaceId": "space-alice",
                        "spaceSlug": "alice",
                        "version": 1,
                        "friends": 2,
                        "encryptedProfile": encrypted_profile,
                        "updatedAt": "2026-07-26T00:00:00Z"
                    }
                })
                .to_string(),
            )
            .create_async()
            .await;
        let versions = server
            .mock("GET", format!("{prefix}/versions").as_str())
            .match_header("x-ente-space-link-auth", auth.as_str())
            .with_status(200)
            .with_body(
                json!([{
                    "version": 1,
                    "createdAt": "2026-07-26T00:00:00Z"
                }])
                .to_string(),
            )
            .create_async()
            .await;
        let ctx = SpaceLinkCtx::open(OpenSpaceLinkCtxInput {
            base_url: server.url(),
            space_slug: "Alice".to_owned(),
            access_key: access_key.to_owned(),
            user_agent: None,
            client_package: None,
            client_version: None,
        })
        .await
        .unwrap();

        assert_eq!(ctx.profile().profile, profile);
        assert_eq!(ctx.profile().friends, 2);
        assert_eq!(ctx.posts(), 3);
        bootstrap.assert_async().await;
        profile_request.assert_async().await;
        versions.assert_async().await;
    }

    #[tokio::test]
    async fn public_link_serializes_web_push_subscriptions() {
        let mut server = Server::new_async().await;
        let prefix = "/space/public/by-slug/alice/link";
        let link_auth = "link-auth";
        let subscribe = server
            .mock("PUT", format!("{prefix}/push/subscription").as_str())
            .match_header("x-ente-space-link-auth", link_auth)
            .match_body(Matcher::Json(json!({
                "endpoint": WEB_PUSH_ENDPOINT,
                "keys": {
                    "p256dh": WEB_PUSH_P256DH,
                    "auth": WEB_PUSH_AUTH
                }
            })))
            .with_status(200)
            .with_body(json!({"targetId": "wpt_target"}).to_string())
            .create_async()
            .await;
        let unsubscribe = server
            .mock("DELETE", format!("{prefix}/push/subscription").as_str())
            .match_header("x-ente-space-link-auth", link_auth)
            .match_body(Matcher::Json(json!({
                "endpoint": WEB_PUSH_ENDPOINT
            })))
            .with_status(204)
            .create_async()
            .await;
        let ctx = SpaceLinkCtx {
            api: build_api(&server.url(), None, None, None, None).unwrap(),
            space_slug: "alice".to_owned(),
            auth_key: link_auth.to_owned(),
            wrap_key: Vec::new(),
            profile: DecryptedSpaceProfile {
                space_id: "space-alice".to_owned(),
                space_slug: "alice".to_owned(),
                version: 1,
                friends: 0,
                profile: Vec::new(),
                avatar: None,
                cover: None,
                updated_at: None,
            },
            posts: 0,
            key_history: Mutex::new(BTreeMap::new()),
        };

        assert_eq!(
            ctx.subscribe_web_push(
                WEB_PUSH_ENDPOINT.to_owned(),
                WEB_PUSH_P256DH.to_owned(),
                WEB_PUSH_AUTH.to_owned(),
            )
            .await
            .unwrap(),
            "wpt_target"
        );
        ctx.unsubscribe_web_push(WEB_PUSH_ENDPOINT.to_owned())
            .await
            .unwrap();

        subscribe.assert_async().await;
        unsubscribe.assert_async().await;
    }
}
