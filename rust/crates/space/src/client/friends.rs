use super::{AccountSpaceCtx, retain_content_error};
use crate::crypto::seal_with_public_key;
use crate::error::{Error, Result};
use crate::models::{SpaceActor, SpaceFriend, SpaceFriendRequest, SpaceSentFriendRequest};
use crate::transport::{
    AddFriendPayload, ConfirmFriendRequestPayload, FriendRelationshipResponse,
    FriendStatusResponse, FriendTargetPayload, RefreshFriendSharesRequest, ShareUpdatePayload,
    SpaceActorResponse, SpaceFriendRequestResponse, SpaceFriendResponse,
    SpaceSentFriendRequestResponse,
};
use ente_core::b64;
use ente_core::http;

fn map_friend_mutation_error(error: http::Error) -> Error {
    match &error {
        http::Error::Api { code, .. } => match code.as_str() {
            "SPACE_SELF_FRIENDSHIP" => Error::SelfFriendship,
            "SPACE_FRIEND_REQUEST_LIMIT_REACHED" => Error::FriendRequestLimitReached,
            "SPACE_SENT_FRIEND_REQUEST_LIMIT_REACHED" => Error::SentFriendRequestLimitReached,
            "SPACE_FRIEND_REQUEST_UNAVAILABLE" => Error::FriendRequestUnavailable,
            _ => error.into(),
        },
        _ => error.into(),
    }
}

impl AccountSpaceCtx {
    async fn request_friend_with_target(
        &self,
        requester_space_id: &str,
        target_space_id: &str,
        target_public_key: &[u8],
    ) -> Result<FriendStatusResponse> {
        if target_space_id.trim().is_empty() {
            return Err(Error::InvalidInput("target space id is required".into()));
        }
        if target_public_key.is_empty() {
            return Err(Error::InvalidInput("target public key is required".into()));
        }
        let (requester_space, requester_space_key) =
            self.profile_space_access(requester_space_id).await?;
        let requester_share = seal_with_public_key(&requester_space_key, target_public_key)?;
        let payload = AddFriendPayload {
            target_space_id: Some(target_space_id.to_owned()),
            target_username: None,
            requester_friend_sealed_space_key: b64::encode(&requester_share),
            requester_key_version: requester_space.key_version,
        };
        let path = format!("/spaces/{}/friends/add", requester_space.space_id);
        let response: FriendStatusResponse = self
            .api()
            .post(&path)
            .json(&payload)
            .send()
            .await?
            .error_for_code()
            .await
            .map_err(map_friend_mutation_error)?
            .json()
            .await?;
        if response.status == "friend" {
            self.clear_friend_share_cache()?;
        }
        Ok(response)
    }

    pub async fn request_friend_by_username(
        &self,
        space_id: &str,
        username: &str,
    ) -> Result<FriendStatusResponse> {
        let target = self.lookup_space_by_slug(username).await?;
        let target_public_key = b64::decode(&target.public_key)?;
        self.request_friend_with_target(space_id, &target.space_id, &target_public_key)
            .await
    }

    pub async fn list_friend_requests(&self, space_id: &str) -> Result<Vec<SpaceFriendRequest>> {
        let path = format!("/spaces/{space_id}/friends/requests");
        let requests: Vec<SpaceFriendRequestResponse> = self
            .api()
            .get(&path)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        Ok(requests.into_iter().map(Into::into).collect())
    }

    pub async fn list_sent_friend_requests(
        &self,
        space_id: &str,
    ) -> Result<Vec<SpaceSentFriendRequest>> {
        let path = format!("/spaces/{space_id}/friends/requests/sent");
        let requests: Vec<SpaceSentFriendRequestResponse> = self
            .api()
            .get(&path)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        Ok(requests.into_iter().map(Into::into).collect())
    }

    pub async fn confirm_friend_request(
        &self,
        space_id: &str,
        request_id: i64,
    ) -> Result<FriendStatusResponse> {
        if request_id <= 0 {
            return Err(Error::InvalidInput("friend request id is required".into()));
        }
        let request = self
            .list_friend_requests(space_id)
            .await?
            .into_iter()
            .find(|value| value.request_id == request_id)
            .ok_or(Error::FriendRequestUnavailable)?;
        if request.requester.public_key.trim().is_empty() {
            return Err(Error::InvalidInput(
                "requester public key is required".into(),
            ));
        }
        let requester_public_key = b64::decode(&request.requester.public_key)?;
        let (target_space, target_space_key) = self.profile_space_access(space_id).await?;
        let target_share = seal_with_public_key(&target_space_key, &requester_public_key)?;
        let payload = ConfirmFriendRequestPayload {
            target_friend_sealed_space_key: b64::encode(&target_share),
            target_key_version: target_space.key_version,
        };
        let path = format!(
            "/spaces/{}/friends/requests/{request_id}/confirm",
            target_space.space_id
        );
        let response = self
            .api()
            .post(&path)
            .json(&payload)
            .send()
            .await?
            .error_for_code()
            .await
            .map_err(map_friend_mutation_error)?
            .json()
            .await?;
        self.clear_friend_share_cache()?;
        Ok(response)
    }

    pub async fn delete_friend_request(&self, space_id: &str, request_id: i64) -> Result<()> {
        if request_id <= 0 {
            return Err(Error::InvalidInput("friend request id is required".into()));
        }
        let path = format!("/spaces/{space_id}/friends/requests/{request_id}");
        self.api()
            .delete(&path)
            .send()
            .await?
            .error_for_code()
            .await
            .map_err(map_friend_mutation_error)?;
        Ok(())
    }

    pub async fn unfriend_by_space(&self, actor_space_id: &str, space_id: &str) -> Result<()> {
        let request = FriendTargetPayload {
            target_username: None,
            target_space_id: Some(space_id.to_owned()),
        };
        let path = format!("/spaces/{actor_space_id}/friends/unfriend");
        self.api()
            .post(&path)
            .json(&request)
            .send()
            .await?
            .error_for_status()?;
        self.clear_friend_share_cache()?;
        Ok(())
    }

    pub async fn unfriend_by_username(&self, actor_space_id: &str, username: &str) -> Result<()> {
        let request = FriendTargetPayload {
            target_username: Some(username.to_owned()),
            target_space_id: None,
        };
        let path = format!("/spaces/{actor_space_id}/friends/unfriend");
        self.api()
            .post(&path)
            .json(&request)
            .send()
            .await?
            .error_for_status()?;
        self.clear_friend_share_cache()?;
        Ok(())
    }

    pub async fn list_space_friends(&self, space_id: &str) -> Result<Vec<SpaceFriend>> {
        let friends = self.list_space_friends_raw(space_id).await?;
        let mut items = Vec::with_capacity(friends.len());
        for friend in friends {
            items.push(self.open_friend(friend).await?);
        }
        Ok(items)
    }

    pub(super) async fn list_space_friends_raw(
        &self,
        space_id: &str,
    ) -> Result<Vec<SpaceFriendResponse>> {
        let path = format!("/spaces/{space_id}/friends");
        Ok(self
            .api()
            .get(&path)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?)
    }

    pub(super) async fn open_friend(&self, friend: SpaceFriendResponse) -> Result<SpaceFriend> {
        Ok(SpaceFriend {
            friend: self.open_friend_actor(friend.friend).await?,
            share_key_version: friend.share_key_version,
            created_at: friend.created_at,
        })
    }

    async fn open_friend_actor(&self, actor: SpaceActorResponse) -> Result<SpaceActor> {
        let profile = retain_content_error(self.decrypt_actor_profile(&actor).await)?;
        Ok(SpaceActor::from_response(actor, profile))
    }

    pub async fn get_relationship(
        &self,
        space_id: &str,
        target_space_id: &str,
    ) -> Result<FriendRelationshipResponse> {
        let query = vec![("targetSpaceId", target_space_id.to_owned())];
        let path = format!("/spaces/{space_id}/friends/relationship");
        Ok(self
            .api()
            .get(&path)
            .query(&query)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?)
    }

    pub async fn refresh_friend_shares(&self, space_id: &str) -> Result<usize> {
        let access = self
            .resolve_owned_space_access(space_id)
            .await?
            .ok_or_else(|| {
                Error::InvalidInput(format!("space {space_id} is not owned by the account"))
            })?;
        let friends = self.list_space_friends_raw(space_id).await?;
        let mut updates = Vec::new();
        for friend in friends {
            if friend.share_key_version == access.key_version {
                continue;
            }
            let public_key = b64::decode(&friend.friend.public_key)?;
            let sealed_share = seal_with_public_key(&access.space_key, &public_key)?;
            updates.push(ShareUpdatePayload {
                friend_space_id: friend.friend.space_id,
                friend_sealed_space_key: b64::encode(&sealed_share),
            });
        }
        if updates.is_empty() {
            return Ok(0);
        }
        let payload = RefreshFriendSharesRequest {
            key_version: access.key_version,
            shares: updates,
        };
        let updated = payload.shares.len();
        let path = format!("/spaces/{space_id}/friends/shares/refresh");
        self.api()
            .post(&path)
            .json(&payload)
            .send()
            .await?
            .error_for_status()?;
        self.clear_friend_share_cache()?;
        Ok(updated)
    }
}
