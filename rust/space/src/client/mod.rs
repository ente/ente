mod assets;
mod entity_keys;
mod friends;
mod keys;
mod media;
mod messages;
mod posts;
mod profiles;

#[cfg(test)]
mod test_support;
#[cfg(test)]
mod tests;

use std::{
    cmp::Reverse,
    collections::BTreeMap,
    sync::{Mutex, MutexGuard},
};

use media::{ensure_supported_photo_bytes, ensure_supported_photo_media_type};

use crate::crypto::{
    ASSET_PAYLOAD_OVERHEAD_BYTES, SECRETBOX_PAYLOAD_OVERHEAD_BYTES, decrypt_secretbox_payload,
    encrypt_secretbox_payload, generate_key, generate_keypair, open_with_keypair,
};
use crate::error::{Result, SpaceError};
use crate::models::{
    CreatedSpace, DecryptedFriendShare, DecryptedSpaceProfile, FeedItem, MessagePayload,
    OpenAccountSpaceCtxInput, PostObjectMetadata,
};
use crate::transport::{
    CreateSpaceRequest, FriendShareResponse, PostObjectPayload, PostResponse, SpaceKeyResponse,
    SpaceKeyVersionResponse, SpaceLookupResponse, SpaceProfileResponse, UpdateSpaceSlugRequest,
};
use ente_core::{
    crypto::{SecretVec, decode_b64, encode_b64},
    http::{Api, ApiConfig, Auth, Http},
};
const UPLOAD_PURPOSE_AVATAR: &str = "avatar";
const UPLOAD_PURPOSE_COVER: &str = "cover";
const MESSAGE_KIND_REGULAR: &str = "regular";
const MESSAGE_KIND_POST_REPLY: &str = "post_reply";
const ONLY_PHOTOS_UPLOAD_MESSAGE: &str = "only photos can be uploaded";
pub const MAX_SPACE_POST_UPLOAD_BYTES: usize = 5 * 1024 * 1024;
pub const MAX_SPACE_AVATAR_UPLOAD_BYTES: usize = 2 * 1024 * 1024;
pub const MAX_SPACE_COVER_UPLOAD_BYTES: usize = 2 * 1024 * 1024;
pub const MAX_SPACE_POST_PLAINTEXT_BYTES: usize =
    MAX_SPACE_POST_UPLOAD_BYTES - ASSET_PAYLOAD_OVERHEAD_BYTES;
pub const MAX_SPACE_AVATAR_PLAINTEXT_BYTES: usize =
    MAX_SPACE_AVATAR_UPLOAD_BYTES - ASSET_PAYLOAD_OVERHEAD_BYTES;
pub const MAX_SPACE_COVER_PLAINTEXT_BYTES: usize =
    MAX_SPACE_COVER_UPLOAD_BYTES - ASSET_PAYLOAD_OVERHEAD_BYTES;
pub const MAX_SPACE_MESSAGE_TEXT_CHARS: usize = 1000;
pub const MAX_SPACE_MESSAGE_TEXT_BYTES: usize = 4 * 1024;
pub const MAX_SPACE_MESSAGE_CIPHER_DECODED_BYTES: usize = 6 * 1024;
pub const MAX_SPACE_MESSAGE_PAYLOAD_BYTES: usize =
    MAX_SPACE_MESSAGE_CIPHER_DECODED_BYTES - SECRETBOX_PAYLOAD_OVERHEAD_BYTES;

#[derive(Debug, Clone, Default)]
pub struct PostPhotoAssetOptions {
    pub width: Option<i32>,
    pub height: Option<i32>,
    pub media_type: Option<String>,
    pub thumb_hash: Option<String>,
}

fn profile_object_id_from_key(object_key: &str) -> Result<String> {
    object_key
        .rsplit('/')
        .next()
        .filter(|value| !value.trim().is_empty() && !value.contains('/'))
        .map(ToOwned::to_owned)
        .ok_or_else(|| SpaceError::InvalidInput("invalid profile asset object key".into()))
}

#[derive(Clone)]
pub(crate) struct ResolvedSpaceAccess {
    space_key: Vec<u8>,
    key_version: i32,
}

#[derive(Clone)]
pub(crate) struct ResolvedOwnedSpaceAccess {
    space_key: Vec<u8>,
    key_version: i32,
}

pub(crate) struct SpaceIdentity {
    public_key: Vec<u8>,
    secret_key: SecretVec,
}

impl Clone for SpaceIdentity {
    fn clone(&self) -> Self {
        Self {
            public_key: self.public_key.clone(),
            secret_key: SecretVec::new(self.secret_key.to_vec()),
        }
    }
}

pub struct AccountSpaceCtx {
    api: Api,
    space_root_key: SecretVec,
    space_identity_cache: Mutex<BTreeMap<String, SpaceIdentity>>,
    owned_spaces_cache: Mutex<Option<Vec<SpaceKeyResponse>>>,
    friend_shares_cache: Mutex<BTreeMap<String, Vec<DecryptedFriendShare>>>,
}

impl AccountSpaceCtx {
    pub fn open(input: OpenAccountSpaceCtxInput) -> Result<Self> {
        let space_root_key = SecretVec::new(input.space_root_key);
        let api = build_api(
            &input.base_url,
            input.space_session_token,
            input.user_agent,
            input.client_package,
            input.client_version,
        )?;
        Ok(Self {
            api,
            space_root_key,
            space_identity_cache: Mutex::new(BTreeMap::new()),
            owned_spaces_cache: Mutex::new(None),
            friend_shares_cache: Mutex::new(BTreeMap::new()),
        })
    }

    pub fn api(&self) -> &Api {
        &self.api
    }

    pub fn space_root_key(&self) -> &[u8] {
        &self.space_root_key
    }

    pub async fn get_space_root_key(&self) -> Result<Option<Vec<u8>>> {
        Ok(Some(self.space_root_key.to_vec()))
    }

    pub async fn get_or_create_space_root_key(&self) -> Result<Vec<u8>> {
        Ok(self.space_root_key.to_vec())
    }

    pub async fn list_owned_spaces(&self) -> Result<Vec<SpaceKeyResponse>> {
        if let Some(value) = cache_lock(&self.owned_spaces_cache, "owned spaces")?.clone() {
            return Ok(value);
        }
        let spaces: Vec<SpaceKeyResponse> = self
            .api
            .get("/account/space")
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        *cache_lock(&self.owned_spaces_cache, "owned spaces")? = Some(spaces.clone());
        Ok(spaces)
    }

    pub async fn list_friend_shares(&self, space_id: &str) -> Result<Vec<FriendShareResponse>> {
        let path = format!("/spaces/{space_id}/friends/shares");
        Ok(self
            .api
            .get(&path)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?)
    }

    pub(crate) fn decrypt_space_identity(&self, space: &SpaceKeyResponse) -> Result<SpaceIdentity> {
        if space.public_key.trim().is_empty() || space.encrypted_secret_key.trim().is_empty() {
            return Err(SpaceError::MissingSecretKey);
        }
        let public_key = decode_b64(&space.public_key)?;
        let encrypted_secret_key = decode_b64(&space.encrypted_secret_key)?;
        let secret_key = decrypt_secretbox_payload(&self.space_root_key, &encrypted_secret_key)?;
        Ok(SpaceIdentity {
            public_key,
            secret_key: SecretVec::new(secret_key),
        })
    }

    pub(crate) async fn space_identity_for(&self, space_id: &str) -> Result<SpaceIdentity> {
        let space_id = space_id.trim();
        if space_id.is_empty() {
            return Err(SpaceError::InvalidInput("space id is required".into()));
        }
        if let Some(value) = cache_lock(&self.space_identity_cache, "space identity")?
            .get(space_id)
            .cloned()
        {
            return Ok(value);
        }
        let space = self
            .list_owned_spaces_cached()
            .await?
            .into_iter()
            .find(|value| value.space_id == space_id)
            .ok_or_else(|| {
                SpaceError::InvalidInput(format!("space {space_id} is not owned by the account"))
            })?;
        let identity = self.decrypt_space_identity(&space)?;
        cache_lock(&self.space_identity_cache, "space identity")?
            .insert(space.space_id.clone(), identity.clone());
        Ok(identity)
    }

    pub async fn decrypt_friend_share(
        &self,
        space_id: &str,
        share: &FriendShareResponse,
    ) -> Result<DecryptedFriendShare> {
        let identity = self.space_identity_for(space_id).await?;
        let ciphertext = decode_b64(&share.friend_sealed_space_key)?;
        if ciphertext.is_empty() {
            return Err(SpaceError::MissingFriendSealedSpaceKey);
        }
        let space_key = open_with_keypair(&ciphertext, &identity.public_key, &identity.secret_key)?;
        Ok(DecryptedFriendShare {
            friend: share.friend.clone(),
            space_id: share.space_id.clone(),
            space_slug: share.space_slug.clone(),
            space_key,
            key_version: share.key_version,
        })
    }

    pub(crate) async fn profile_space_access(
        &self,
        space_id: &str,
    ) -> Result<(SpaceKeyResponse, Vec<u8>)> {
        let space_root_key = self
            .get_space_root_key()
            .await?
            .ok_or_else(|| SpaceError::InvalidInput("space root key is missing".into()))?;
        let space_id = space_id.trim();
        if space_id.is_empty() {
            return Err(SpaceError::InvalidInput("space id is required".into()));
        }
        let space = self
            .list_owned_spaces()
            .await?
            .into_iter()
            .find(|value| value.space_id == space_id)
            .ok_or_else(|| {
                SpaceError::InvalidInput(format!("space {space_id} is not owned by the account"))
            })?;
        let packed = decode_b64(&space.root_wrapped_space_key)?;
        let space_key = decrypt_secretbox_payload(&space_root_key, &packed)?;
        Ok((space, space_key))
    }

    pub async fn resolve_owned_space_key(&self, space_id: &str) -> Result<Option<Vec<u8>>> {
        Ok(self
            .resolve_owned_space_access(space_id)
            .await?
            .map(|value| value.space_key))
    }

    pub async fn resolve_space_key(&self, space_id: &str) -> Result<Option<Vec<u8>>> {
        Ok(self
            .resolve_space_access(space_id)
            .await?
            .map(|value| value.space_key))
    }

    pub async fn create_space(&self, space_slug: &str, profile: &[u8]) -> Result<CreatedSpace> {
        self.create_space_with_referrer(space_slug, profile, None)
            .await
    }

    pub async fn create_space_with_referrer(
        &self,
        space_slug: &str,
        profile: &[u8],
        referred_by_space_id: Option<&str>,
    ) -> Result<CreatedSpace> {
        let space_key = generate_key();
        self.create_space_with_key_and_referrer(
            space_slug,
            &space_key,
            profile,
            referred_by_space_id,
        )
        .await
    }

    pub async fn create_space_with_key(
        &self,
        space_slug: &str,
        space_key: &[u8],
        profile: &[u8],
    ) -> Result<CreatedSpace> {
        self.create_space_with_key_and_referrer(space_slug, space_key, profile, None)
            .await
    }

    pub async fn create_space_with_key_and_referrer(
        &self,
        space_slug: &str,
        space_key: &[u8],
        profile: &[u8],
        referred_by_space_id: Option<&str>,
    ) -> Result<CreatedSpace> {
        let space_root_key = self.get_or_create_space_root_key().await?;
        let root_wrapped_space_key =
            encode_b64(&encrypt_secretbox_payload(&space_root_key, space_key)?);
        let (public_key, secret_key) = generate_keypair()?;
        let encrypted_secret_key = encrypt_secretbox_payload(&space_root_key, &secret_key)?;
        let encrypted_profile = encode_b64(&encrypt_secretbox_payload(space_key, profile)?);
        let request = CreateSpaceRequest {
            space_slug: space_slug.to_owned(),
            root_wrapped_space_key: root_wrapped_space_key.clone(),
            public_key: encode_b64(&public_key),
            encrypted_secret_key: encode_b64(&encrypted_secret_key),
            encrypted_profile: encrypted_profile.clone(),
            referred_by_space_id: referred_by_space_id.map(str::to_owned),
        };
        let response = self
            .api
            .post("/account/space")
            .json(&request)
            .send()
            .await?
            .error_for_code()
            .await?
            .json::<SpaceKeyResponse>()
            .await?;
        self.cache_created_owned_space(SpaceKeyResponse {
            space_id: response.space_id.clone(),
            space_slug: response.space_slug.clone(),
            root_wrapped_space_key: root_wrapped_space_key.clone(),
            public_key: request.public_key.clone(),
            encrypted_secret_key: request.encrypted_secret_key.clone(),
            encrypted_profile: encrypted_profile.clone(),
            key_version: response.key_version,
        })?;
        cache_lock(&self.space_identity_cache, "space identity")?.insert(
            response.space_id.clone(),
            SpaceIdentity {
                public_key,
                secret_key: SecretVec::new(secret_key),
            },
        );
        Ok(CreatedSpace {
            space_id: response.space_id,
            space_slug: response.space_slug,
            key_version: response.key_version,
            space_key: space_key.to_vec(),
            root_wrapped_space_key,
            encrypted_profile,
        })
    }

    pub async fn lookup_space_by_slug(&self, space_slug: &str) -> Result<SpaceLookupResponse> {
        let path = format!("/space/public/by-slug/{}", urlencoding::encode(space_slug));
        Ok(self
            .api
            .get(&path)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?)
    }

    pub async fn update_space_slug(
        &self,
        space_id: &str,
        space_slug: &str,
    ) -> Result<SpaceLookupResponse> {
        let path = format!("/spaces/{space_id}/slug");
        let request = UpdateSpaceSlugRequest {
            space_slug: space_slug.to_owned(),
        };
        let response = self
            .api
            .put(&path)
            .json(&request)
            .send()
            .await?
            .error_for_code()
            .await?
            .json()
            .await?;
        self.clear_owned_space_cache()?;
        Ok(response)
    }

    pub(crate) async fn resolve_owned_space_access(
        &self,
        space_id: &str,
    ) -> Result<Option<ResolvedSpaceAccess>> {
        Ok(self
            .resolve_owned_space_access_with_root(space_id)
            .await?
            .map(|value| ResolvedSpaceAccess {
                space_key: value.space_key,
                key_version: value.key_version,
            }))
    }

    pub(crate) async fn resolve_owned_space_access_with_root(
        &self,
        space_id: &str,
    ) -> Result<Option<ResolvedOwnedSpaceAccess>> {
        let space_root_key = match self.get_space_root_key().await? {
            Some(value) => value,
            None => return Ok(None),
        };
        let spaces = self.list_owned_spaces_cached().await?;
        let Some(record) = spaces.into_iter().find(|value| value.space_id == space_id) else {
            return Ok(None);
        };
        let packed = decode_b64(&record.root_wrapped_space_key)?;
        let space_key = decrypt_secretbox_payload(&space_root_key, &packed)?;
        Ok(Some(ResolvedOwnedSpaceAccess {
            space_key,
            key_version: record.key_version,
        }))
    }

    pub(crate) async fn resolve_shared_space_access(
        &self,
        space_id: &str,
    ) -> Result<Option<ResolvedSpaceAccess>> {
        let shares = self.list_all_decrypted_friend_shares().await?;
        let Some(mut share) = shares.into_iter().find(|value| value.space_id == space_id) else {
            return Ok(None);
        };
        Ok(Some(ResolvedSpaceAccess {
            space_key: std::mem::take(&mut share.space_key),
            key_version: share.key_version,
        }))
    }

    pub(crate) async fn resolve_space_access(
        &self,
        space_id: &str,
    ) -> Result<Option<ResolvedSpaceAccess>> {
        if let Some(access) = self.resolve_owned_space_access(space_id).await? {
            return Ok(Some(access));
        }
        self.resolve_shared_space_access(space_id).await
    }

    pub(crate) async fn resolve_shared_space_access_for(
        &self,
        viewer_space_id: &str,
        space_id: &str,
    ) -> Result<Option<ResolvedSpaceAccess>> {
        let shares = self
            .list_decrypted_friend_shares_cached(viewer_space_id)
            .await?;
        let Some(mut share) = shares.into_iter().find(|value| value.space_id == space_id) else {
            return Ok(None);
        };
        Ok(Some(ResolvedSpaceAccess {
            space_key: std::mem::take(&mut share.space_key),
            key_version: share.key_version,
        }))
    }

    pub(crate) async fn resolve_space_access_for(
        &self,
        viewer_space_id: &str,
        space_id: &str,
    ) -> Result<Option<ResolvedSpaceAccess>> {
        if let Some(access) = self.resolve_owned_space_access(space_id).await? {
            return Ok(Some(access));
        }
        self.resolve_shared_space_access_for(viewer_space_id, space_id)
            .await
    }

    pub(crate) async fn resolve_space_key_for_version(
        &self,
        space_id: &str,
        version: Option<i32>,
    ) -> Result<Option<Vec<u8>>> {
        let access = match self.resolve_space_access(space_id).await? {
            Some(value) => value,
            None => return Ok(None),
        };
        let target_version = version.unwrap_or(access.key_version);
        if target_version == access.key_version {
            return Ok(Some(access.space_key));
        }
        let history = self.build_space_key_history_for_space(space_id).await?;
        Ok(history.get(&target_version).cloned())
    }

    pub async fn resolve_space_key_for_version_for_viewer(
        &self,
        space_id: &str,
        viewer_space_id: Option<&str>,
        version: Option<i32>,
    ) -> Result<Option<Vec<u8>>> {
        let access = match viewer_space_id.filter(|value| !value.trim().is_empty()) {
            Some(viewer_space_id) => {
                self.resolve_space_access_for(viewer_space_id, space_id)
                    .await?
            }
            None => self.resolve_space_access(space_id).await?,
        };
        let access = match access {
            Some(value) => value,
            None => return Ok(None),
        };
        let target_version = version.unwrap_or(access.key_version);
        if target_version == access.key_version {
            return Ok(Some(access.space_key));
        }
        let history = self
            .build_space_key_history_for_space_for_viewer(space_id, viewer_space_id)
            .await?;
        Ok(history.get(&target_version).cloned())
    }

    pub(crate) async fn list_owned_spaces_cached(&self) -> Result<Vec<SpaceKeyResponse>> {
        if let Some(value) = cache_lock(&self.owned_spaces_cache, "owned spaces")?.clone() {
            return Ok(value);
        }
        let value = self.list_owned_spaces().await?;
        *cache_lock(&self.owned_spaces_cache, "owned spaces")? = Some(value.clone());
        Ok(value)
    }

    pub(crate) async fn list_decrypted_friend_shares_cached(
        &self,
        space_id: &str,
    ) -> Result<Vec<DecryptedFriendShare>> {
        let space_id = space_id.trim();
        if space_id.is_empty() {
            return Err(SpaceError::InvalidInput("space id is required".into()));
        }
        if let Some(value) = cache_lock(&self.friend_shares_cache, "friend shares")?
            .get(space_id)
            .cloned()
        {
            return Ok(value);
        }
        let shares = self.list_friend_shares(space_id).await?;
        let mut value = Vec::with_capacity(shares.len());
        for share in shares {
            match self.decrypt_friend_share(space_id, &share).await {
                Ok(share) => value.push(share),
                Err(error) if error.is_unavailable_record() => {}
                Err(error) => return Err(error),
            }
        }
        cache_lock(&self.friend_shares_cache, "friend shares")?
            .insert(space_id.to_owned(), value.clone());
        Ok(value)
    }

    pub(crate) async fn list_all_decrypted_friend_shares(
        &self,
    ) -> Result<Vec<DecryptedFriendShare>> {
        let spaces = self.list_owned_spaces_cached().await?;
        let mut all = Vec::new();
        for space in spaces {
            all.extend(
                self.list_decrypted_friend_shares_cached(&space.space_id)
                    .await?,
            );
        }
        Ok(all)
    }

    pub(crate) fn clear_owned_space_cache(&self) -> Result<()> {
        *cache_lock(&self.owned_spaces_cache, "owned spaces")? = None;
        Ok(())
    }

    pub(crate) fn cache_created_owned_space(&self, created: SpaceKeyResponse) -> Result<()> {
        let mut cache = cache_lock(&self.owned_spaces_cache, "owned spaces")?;
        if let Some(spaces) = cache.as_mut() {
            spaces.retain(|space| space.space_id != created.space_id);
            spaces.push(created);
        }
        Ok(())
    }

    pub(crate) fn update_cached_owned_space_profile(
        &self,
        space_id: &str,
        encrypted_profile: String,
    ) -> Result<()> {
        let mut cache = cache_lock(&self.owned_spaces_cache, "owned spaces")?;
        if let Some(spaces) = cache.as_mut()
            && let Some(space) = spaces.iter_mut().find(|space| space.space_id == space_id)
        {
            space.encrypted_profile = encrypted_profile;
        }
        Ok(())
    }

    pub(crate) fn clear_friend_share_cache(&self) -> Result<()> {
        cache_lock(&self.friend_shares_cache, "friend shares")?.clear();
        Ok(())
    }
}

fn ensure_space_upload_size(purpose: &str, encrypted_size: usize, max_bytes: usize) -> Result<()> {
    if encrypted_size == 0 || encrypted_size > max_bytes {
        return Err(SpaceError::InvalidInput(format!(
            "{purpose} upload size must be between 1 and {max_bytes} bytes"
        )));
    }
    Ok(())
}

fn encrypt_post_object_metadata(post_key: &[u8], metadata: &PostObjectMetadata) -> Result<String> {
    let plaintext = serde_json::to_vec(metadata)
        .map_err(|err| SpaceError::InvalidInput(format!("invalid post object metadata: {err}")))?;
    Ok(encode_b64(&encrypt_secretbox_payload(
        post_key, &plaintext,
    )?))
}

pub fn decrypt_post_object_metadata(
    post_key: &[u8],
    object: &PostObjectPayload,
) -> Result<Option<PostObjectMetadata>> {
    let Some(cipher) = object.metadata_cipher.as_deref() else {
        return Ok(None);
    };
    let plaintext = decrypt_secretbox_payload(post_key, &decode_b64(cipher)?)?;
    serde_json::from_slice(&plaintext)
        .map(Some)
        .map_err(|err| SpaceError::InvalidInput(format!("invalid post object metadata: {err}")))
}

fn ensure_post_objects_are_photos(objects: &[PostObjectPayload], post_key: &[u8]) -> Result<()> {
    for object in objects {
        let metadata = decrypt_post_object_metadata(post_key, object)?
            .ok_or_else(|| SpaceError::InvalidInput("post object metadata is required".into()))?;
        if ensure_supported_photo_media_type(metadata.media_type.as_deref())?.is_none() {
            return Err(SpaceError::InvalidInput(ONLY_PHOTOS_UPLOAD_MESSAGE.into()));
        }
    }
    Ok(())
}

fn validate_message_payload(payload: &MessagePayload, plaintext_len: usize) -> Result<()> {
    if payload.text.chars().count() > MAX_SPACE_MESSAGE_TEXT_CHARS {
        return Err(SpaceError::InvalidInput(format!(
            "message text must be {MAX_SPACE_MESSAGE_TEXT_CHARS} characters or fewer"
        )));
    }
    if payload.text.len() > MAX_SPACE_MESSAGE_TEXT_BYTES {
        return Err(SpaceError::InvalidInput(format!(
            "message text must be {MAX_SPACE_MESSAGE_TEXT_BYTES} bytes or fewer"
        )));
    }
    if plaintext_len > MAX_SPACE_MESSAGE_PAYLOAD_BYTES {
        return Err(SpaceError::InvalidInput(format!(
            "message payload must be {MAX_SPACE_MESSAGE_PAYLOAD_BYTES} bytes or fewer"
        )));
    }
    Ok(())
}

fn post_response_from_feed_item(item: &FeedItem) -> PostResponse {
    PostResponse {
        post_id: item.post_id,
        space_id: item.space_id.clone(),
        space_slug: item.space_slug.clone(),
        author: item.author.clone(),
        encrypted_post_key: item.encrypted_post_key.clone(),
        caption_cipher: item.caption_cipher.clone(),
        key_version: item.key_version,
        objects: item.objects.clone(),
        created_at: item.created_at.clone(),
        viewer_liked: item.viewer_liked,
    }
}

pub(super) fn build_api(
    base_url: &str,
    space_session_token: Option<String>,
    user_agent: Option<String>,
    client_package: Option<String>,
    client_version: Option<String>,
) -> Result<Api> {
    let auth = space_session_token.map(Auth::SpaceSession);
    Ok(Api::new(
        Http::new()?,
        ApiConfig {
            origin: base_url.to_owned(),
            auth,
            user_agent,
            client_package,
            client_version,
        },
    ))
}

fn cache_lock<'a, T>(cache: &'a Mutex<T>, name: &str) -> Result<MutexGuard<'a, T>> {
    cache
        .lock()
        .map_err(|_| SpaceError::InvalidInput(format!("{name} cache poisoned")))
}

pub(super) fn decrypt_space_profile(
    profile: &SpaceProfileResponse,
    space_key: &[u8],
) -> Result<DecryptedSpaceProfile> {
    let profile_bytes = if profile.encrypted_profile.is_empty() {
        Vec::new()
    } else {
        decrypt_secretbox_payload(space_key, &decode_b64(&profile.encrypted_profile)?)?
    };
    Ok(DecryptedSpaceProfile {
        space_id: profile.space_id.clone(),
        space_slug: profile.space_slug.clone(),
        version: profile.version,
        friends: profile.friends,
        profile: profile_bytes,
        avatar: profile.avatar.clone(),
        cover: profile.cover.clone(),
        updated_at: if profile.updated_at.is_empty() {
            None
        } else {
            Some(profile.updated_at.clone())
        },
    })
}

pub(super) fn build_space_key_history_map(
    current_version: i32,
    current_key: &[u8],
    versions: &[SpaceKeyVersionResponse],
) -> Result<BTreeMap<i32, Vec<u8>>> {
    let mut history = BTreeMap::new();
    history.insert(current_version, current_key.to_vec());
    let mut ordered = versions.to_vec();
    ordered.sort_by_key(|entry| Reverse(entry.version));
    for entry in ordered {
        if entry.wrapped_prev_key.is_empty() || entry.version <= 1 {
            continue;
        }
        let Some(known_key) = history.get(&entry.version).cloned() else {
            continue;
        };
        let packed = decode_b64(&entry.wrapped_prev_key)?;
        let previous_key = decrypt_secretbox_payload(&known_key, &packed)?;
        history.insert(entry.version - 1, previous_key);
    }
    Ok(history)
}
