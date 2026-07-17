package controller

import (
	"context"
	"encoding/base64"
	"testing"

	"github.com/ente/museum/space/models"
	spacerepo "github.com/ente/museum/space/repo"
	"github.com/stretchr/testify/require"
)

func setupFriendsControllerTest(t *testing.T) (*FriendsController, *spacerepo.Module, context.Context) {
	t.Helper()
	_, repos, ctx := setupPostsControllerTest(t)
	return NewModule(repos, nil).Friends, repos, ctx
}

func TestFriendRelationshipReportsSelfFriendAndEmpty(t *testing.T) {
	friends, repos, ctx := setupFriendsControllerTest(t)
	aliceID := insertSpaceControllerUser(t, repos, "alice@example.com", "alice-public")
	bobID := insertSpaceControllerUser(t, repos, "bob@example.com", "bob-public")
	charlieID := insertSpaceControllerUser(t, repos, "charlie@example.com", "charlie-public")
	aliceSpace, err := testCreateSpace(ctx, repos, aliceID, "alice", "alice-space-key", "alice-public", "alice-secret", "alice-secret-nonce", "alice-profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, repos, bobID, "bob", "bob-space-key", "bob-public", "bob-secret", "bob-secret-nonce", "bob-profile")
	require.NoError(t, err)
	charlieSpace, err := testCreateSpace(ctx, repos, charlieID, "charlie", "charlie-space-key", "charlie-public", "charlie-secret", "charlie-secret-nonce", "charlie-profile")
	require.NoError(t, err)
	require.NoError(t, testAddFriend(ctx, repos, aliceID, aliceSpace.SpaceID, bobSpace.SpaceID, "bob-share-key", bobSpace.CurrentVersion, "alice-share-key", aliceSpace.CurrentVersion))

	resp, err := friends.Relationship(ctx, aliceSpace, models.FriendRelationshipRequest{TargetSpaceID: aliceSpace.SpaceID})
	require.NoError(t, err)
	require.Equal(t, "self", resp.Relationship)

	resp, err = friends.Relationship(ctx, aliceSpace, models.FriendRelationshipRequest{TargetSpaceID: bobSpace.SpaceID})
	require.NoError(t, err)
	require.Equal(t, "friend", resp.Relationship)

	resp, err = friends.Relationship(ctx, aliceSpace, models.FriendRelationshipRequest{TargetSpaceID: charlieSpace.SpaceID})
	require.NoError(t, err)
	require.Empty(t, resp.Relationship)
}

func TestListFriendsReturnsAvatarKeyVersion(t *testing.T) {
	friends, repos, ctx := setupFriendsControllerTest(t)
	aliceID := insertSpaceControllerUser(t, repos, "alice-avatar-version@example.com", "alice-public")
	bobID := insertSpaceControllerUser(t, repos, "bob-avatar-version@example.com", "bob-public")
	aliceSpace, err := testCreateSpace(ctx, repos, aliceID, "alice_avatar_version", "alice-space-key-v1", "alice-public", "alice-secret", "alice-secret-nonce", "alice-profile-v1")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, repos, bobID, "bob_avatar_version", "bob-space-key", "bob-public", "bob-secret", "bob-secret-nonce", "bob-profile")
	require.NoError(t, err)
	_, err = repos.Spaces.DB.Exec(`
		INSERT INTO space_profile_assets (space_id, asset_type, object_id, bucket_id, size, key_version)
		VALUES ($1, $2, $3, $4, 111, 1)
	`, aliceSpace.SpaceID, spacerepo.ProfileAssetTypeAvatar, "alice-avatar", "b2-eu-cen")
	require.NoError(t, err)
	rotatedAlice, err := testRotateKey(ctx, repos, aliceID, aliceSpace.SpaceID, aliceSpace.CurrentVersion, "alice-space-key-v2", "wrapped-prev-key", "alice-profile-v2")
	require.NoError(t, err)
	require.NoError(t, testAddFriend(ctx, repos, bobID, bobSpace.SpaceID, aliceSpace.SpaceID, "alice-share-key", rotatedAlice.CurrentVersion, "bob-share-key", bobSpace.CurrentVersion))

	resp, err := friends.ListFriends(ctx, bobSpace)
	require.NoError(t, err)
	require.Len(t, resp, 1)
	require.Equal(t, 2, resp[0].Friend.KeyVersion)
	require.NotNil(t, resp[0].Friend.Avatar)
	require.Equal(t, 1, resp[0].Friend.Avatar.KeyVersion)
}

func TestAddFriendRejectsOwnSpace(t *testing.T) {
	friends, repos, ctx := setupFriendsControllerTest(t)
	aliceID := insertSpaceControllerUser(t, repos, "alice-own-link@example.com", "alice-public")
	aliceSpace, err := testCreateSpace(ctx, repos, aliceID, "alice_own_link", "alice-space-key", "alice-own-link-public", "alice-own-link-secret", "alice-own-link-secret-nonce", "alice-profile")
	require.NoError(t, err)

	resp, err := friends.Add(ctx, aliceSpace, models.AddFriendPayload{
		TargetSpaceID:                 aliceSpace.SpaceID,
		RequesterFriendSealedSpaceKey: base64.StdEncoding.EncodeToString([]byte("alice-requester-key")),
		RequesterKeyVersion:           aliceSpace.CurrentVersion,
	})

	require.Nil(t, resp)
	require.Error(t, err)
	require.Contains(t, err.Error(), "cannot add yourself as a friend")
}

func TestUnfriendBySpaceIDRemovesReciprocalShares(t *testing.T) {
	friends, repos, ctx := setupFriendsControllerTest(t)
	aliceID := insertSpaceControllerUser(t, repos, "alice-unfriend-space@example.com", "alice-public")
	bobID := insertSpaceControllerUser(t, repos, "bob-unfriend-space@example.com", "bob-public")
	aliceSpace, err := testCreateSpace(ctx, repos, aliceID, "alice_unfriend_space", "alice-space-key", "alice-unfriend-space-public", "alice-unfriend-space-secret", "alice-unfriend-space-secret-nonce", "alice-profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, repos, bobID, "bob_unfriend_space", "bob-space-key", "bob-unfriend-space-public", "bob-unfriend-space-secret", "bob-unfriend-space-secret-nonce", "bob-profile")
	require.NoError(t, err)
	require.NoError(t, testAddFriend(ctx, repos, aliceID, aliceSpace.SpaceID, bobSpace.SpaceID, "bob-share-key", bobSpace.CurrentVersion, "alice-share-key", aliceSpace.CurrentVersion))

	err = friends.Unfriend(ctx, aliceSpace, models.FriendTargetPayload{TargetSpaceID: &bobSpace.SpaceID})

	require.NoError(t, err)
	aliceShares, err := repos.Friends.ListSharesForFriendAndSpace(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.Empty(t, aliceShares)
	bobShares, err := repos.Friends.ListSharesForFriendAndSpace(ctx, bobSpace.SpaceID)
	require.NoError(t, err)
	require.Empty(t, bobShares)
}

func TestUnfriendByUsernameRemovesReciprocalShares(t *testing.T) {
	friends, repos, ctx := setupFriendsControllerTest(t)
	aliceID := insertSpaceControllerUser(t, repos, "alice-unfriend-username@example.com", "alice-public")
	bobID := insertSpaceControllerUser(t, repos, "bob-unfriend-username@example.com", "bob-public")
	aliceSpace, err := testCreateSpace(ctx, repos, aliceID, "alice_unfriend_username", "alice-space-key", "alice-unfriend-username-public", "alice-unfriend-username-secret", "alice-unfriend-username-secret-nonce", "alice-profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, repos, bobID, "bob_unfriend_username", "bob-space-key", "bob-unfriend-username-public", "bob-unfriend-username-secret", "bob-unfriend-username-secret-nonce", "bob-profile")
	require.NoError(t, err)
	require.NoError(t, testAddFriend(ctx, repos, aliceID, aliceSpace.SpaceID, bobSpace.SpaceID, "bob-share-key", bobSpace.CurrentVersion, "alice-share-key", aliceSpace.CurrentVersion))

	targetUsername := "bob_unfriend_username"
	err = friends.Unfriend(ctx, aliceSpace, models.FriendTargetPayload{TargetUsername: &targetUsername})

	require.NoError(t, err)
	aliceShares, err := repos.Friends.ListSharesForFriendAndSpace(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.Empty(t, aliceShares)
	bobShares, err := repos.Friends.ListSharesForFriendAndSpace(ctx, bobSpace.SpaceID)
	require.NoError(t, err)
	require.Empty(t, bobShares)
}
