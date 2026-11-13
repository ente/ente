package controller

import (
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"testing"

	"github.com/ente/museum/ente"
	timeutil "github.com/ente/museum/pkg/utils/time"
	"github.com/ente/museum/space/models"
	spacerepo "github.com/ente/museum/space/repo"
	"github.com/stretchr/testify/require"
)

func TestGetProfileReturnsHistoricalVersion(t *testing.T) {
	module, repos, userAuthRepo, ctx := setupSpaceAuthControllerTest(t)
	aliceID := insertSpaceControllerUser(t, repos, "alice@example.com", "alice-public")
	space, err := testCreateSpace(ctx, repos, aliceID, "alice", "alice-space-key-v1", "alice-public", "alice-secret", "alice-secret-nonce", "alice-profile-v1")
	require.NoError(t, err)
	rotated, err := testRotateKey(ctx, repos, aliceID, space.SpaceID, space.CurrentVersion, "alice-space-key-v2", "wrapped-prev-key", "alice-profile-v2")
	require.NoError(t, err)
	require.Equal(t, 2, rotated.CurrentVersion)
	require.NoError(t, userAuthRepo.AddToken(aliceID, ente.Photos, "alice-token", "127.0.0.1", "space-test"))
	ginCtx := newPublicSpaceContext()
	ginCtx.Request.Header.Set("X-Auth-Token", "alice-token")
	version := 1

	resp, err := module.Spaces.GetProfile(ginCtx, models.GetSpaceProfileRequest{
		SpaceID: space.SpaceID,
		Version: &version,
	})

	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, space.SpaceID, resp.SpaceID)
	require.Equal(t, "alice", resp.SpaceSlug)
	require.Equal(t, 1, resp.Version)
	require.Equal(t, base64.StdEncoding.EncodeToString([]byte("alice-profile-v1")), resp.EncryptedProfile)
	require.NotEmpty(t, resp.UpdatedAt)
	require.Nil(t, resp.Avatar)
}

func TestGetProfileIncludesFriendsCount(t *testing.T) {
	module, repos, userAuthRepo, ctx := setupSpaceAuthControllerTest(t)
	aliceID := insertSpaceControllerUser(t, repos, "alice-friends@example.com", "alice-public")
	bobID := insertSpaceControllerUser(t, repos, "bob-friends@example.com", "bob-public")
	aliceSpace, err := testCreateSpace(ctx, repos, aliceID, "alice_friends", "alice-space-key", "alice-friends-public", "alice-friends-secret", "alice-friends-secret-nonce", "alice-profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, repos, bobID, "bob_friends", "bob-space-key", "bob-friends-public", "bob-friends-secret", "bob-friends-secret-nonce", "bob-profile")
	require.NoError(t, err)
	require.NoError(t, testAddFriend(ctx, repos, aliceID, aliceSpace.SpaceID, bobSpace.SpaceID, "bob-share-key", bobSpace.CurrentVersion, "alice-share-key", aliceSpace.CurrentVersion))
	require.NoError(t, userAuthRepo.AddToken(aliceID, ente.Photos, "alice-friends-token", "127.0.0.1", "space-test"))
	ginCtx := newPublicSpaceContext()
	ginCtx.Request.Header.Set("X-Auth-Token", "alice-friends-token")

	resp, err := module.Spaces.GetProfile(ginCtx, models.GetSpaceProfileRequest{
		SpaceID: aliceSpace.SpaceID,
	})

	require.NoError(t, err)
	require.NotNil(t, resp)
	require.EqualValues(t, 1, resp.Friends)
}

func TestCreateStoresReferralAttribution(t *testing.T) {
	module, repos, _, ctx := setupSpaceAuthControllerTest(t)
	aliceID := insertSpaceControllerUser(t, repos, "alice-referrer@example.com", "alice-public")
	bobID := insertSpaceControllerUser(t, repos, "bob-referred@example.com", "bob-public")
	aliceSpace, err := testCreateSpace(ctx, repos, aliceID, "alice_referrer", "alice-space-key", "alice-referrer-public", "alice-secret", "alice-secret-nonce", "alice-profile")
	require.NoError(t, err)
	ginCtx := newSpaceControllerContext(bobID)

	resp, err := module.Spaces.Create(ginCtx, models.CreateSpaceRequest{
		SpaceSlug:           "bob_referred",
		RootWrappedSpaceKey: base64.StdEncoding.EncodeToString([]byte("bob-space-key")),
		PublicKey:           base64.StdEncoding.EncodeToString([]byte("bob-public")),
		EncryptedSecretKey:  base64.StdEncoding.EncodeToString([]byte("bob-secret")),
		EncryptedProfile:    base64.StdEncoding.EncodeToString([]byte("bob-profile")),
		ReferredBySpaceID:   aliceSpace.SpaceID,
	})

	require.NoError(t, err)
	require.NotNil(t, resp)
	var referredBySpaceID sql.NullString
	require.NoError(t, repos.Spaces.DB.QueryRow(`
		SELECT referred_by_space_id
		FROM spaces
		WHERE space_id = $1
	`, resp.SpaceID).Scan(&referredBySpaceID))
	require.Equal(t, sql.NullString{String: aliceSpace.SpaceID, Valid: true}, referredBySpaceID)
}

func TestCreateRejectsAdditionalSpaceForOwner(t *testing.T) {
	module, repos, _, ctx := setupSpaceAuthControllerTest(t)
	aliceID := insertSpaceControllerUser(t, repos, "alice-space-limit@example.com", "alice-public")

	_, err := testCreateSpace(ctx, repos, aliceID, "alice_space_limit", "alice-space-key", "alice-public", "alice-secret", "alice-secret-nonce", "alice-profile")
	require.NoError(t, err)

	resp, err := module.Spaces.Create(newSpaceControllerContext(aliceID), models.CreateSpaceRequest{
		SpaceSlug:           "another_space",
		RootWrappedSpaceKey: base64.StdEncoding.EncodeToString([]byte("another-space-key")),
		PublicKey:           base64.StdEncoding.EncodeToString([]byte("another-public")),
		EncryptedSecretKey:  base64.StdEncoding.EncodeToString([]byte("another-secret")),
	})

	require.Nil(t, resp)
	var apiErr *ente.ApiError
	require.ErrorAs(t, err, &apiErr)
	require.Equal(t, ente.CONFLICT, apiErr.Code)
	require.Equal(t, "space limit reached", apiErr.Message)
}

func TestGetProfileReturnsProfileAssetObjectIDs(t *testing.T) {
	module, repos, _, ctx := setupSpaceAuthControllerTest(t)
	aliceID := insertSpaceControllerUser(t, repos, "alice-assets-profile@example.com", "alice-assets-public")
	space, err := testCreateSpace(ctx, repos, aliceID, "alice_assets_profile", "alice-space-key", "alice-assets-public", "alice-secret", "alice-secret-nonce", "alice-profile")
	require.NoError(t, err)
	for _, rec := range []spacerepo.SpaceTempObjectRecord{
		{
			ObjectKey:    spacerepo.ProfileAssetObjectKey(space.SpaceID, spacerepo.ProfileAssetTypeAvatar, "avatar-object-id"),
			SpaceID:      sql.NullString{String: space.SpaceID, Valid: true},
			Purpose:      spacerepo.TempObjectPurposeAvatar,
			BucketID:     "b2-eu-cen",
			ExpectedSize: 111,
			ExpiresAt:    timeutil.MicrosecondsAfterMinutes(30),
		},
		{
			ObjectKey:    spacerepo.ProfileAssetObjectKey(space.SpaceID, spacerepo.ProfileAssetTypeCover, "cover-object-id"),
			SpaceID:      sql.NullString{String: space.SpaceID, Valid: true},
			Purpose:      spacerepo.TempObjectPurposeCover,
			BucketID:     "b2-us-west",
			ExpectedSize: 222,
			ExpiresAt:    timeutil.MicrosecondsAfterMinutes(30),
		},
	} {
		require.NoError(t, repos.Assets.AddTempObject(ctx, rec))
	}
	updated, err := testUpdateProfile(ctx, repos, aliceID, space.SpaceID, space.CurrentVersion, "alice-profile-v2",
		&spacerepo.ProfileAssetUpdate{ObjectID: "avatar-object-id", BucketID: "b2-eu-cen", Size: 111},
		&spacerepo.ProfileAssetUpdate{ObjectID: "cover-object-id", BucketID: "b2-us-west", Size: 222},
		false,
		false,
	)
	require.NoError(t, err)
	rotated, err := testRotateKey(ctx, repos, aliceID, space.SpaceID, updated.CurrentVersion, "alice-space-key-v2", "wrapped-prev-key", "alice-profile-v3")
	require.NoError(t, err)
	require.Equal(t, 2, rotated.CurrentVersion)
	sessionHash := sha256.Sum256([]byte("alice-assets-session-token"))
	require.NoError(t, repos.Sessions.CreateBrowserSession(ctx, sessionHash[:], aliceID, "session-wrap-key", timeutil.MicrosecondsAfterMinutes(5)))
	ginCtx := newPublicSpaceContext()
	ginCtx.Request.Header.Set(SpaceBrowserSessionTokenHeader, "alice-assets-session-token")

	resp, err := module.Spaces.GetProfile(ginCtx, models.GetSpaceProfileRequest{
		SpaceID: space.SpaceID,
	})

	require.NoError(t, err)
	require.Equal(t, 2, resp.Version)
	require.NotNil(t, resp.Avatar)
	require.Equal(t, "avatar-object-id", resp.Avatar.ObjectID)
	require.Equal(t, 1, resp.Avatar.KeyVersion)
	require.EqualValues(t, 111, resp.Avatar.Size)
	require.NotEmpty(t, resp.Avatar.UpdatedAt)
	require.NotNil(t, resp.Cover)
	require.Equal(t, "cover-object-id", resp.Cover.ObjectID)
	require.Equal(t, 1, resp.Cover.KeyVersion)
	require.EqualValues(t, 222, resp.Cover.Size)
	require.NotEmpty(t, resp.Cover.UpdatedAt)

	require.NoError(t, repos.Assets.AddTempObject(ctx, spacerepo.SpaceTempObjectRecord{
		ObjectKey:    spacerepo.ProfileAssetObjectKey(space.SpaceID, spacerepo.ProfileAssetTypeAvatar, "avatar-v2-object-id"),
		SpaceID:      sql.NullString{String: space.SpaceID, Valid: true},
		Purpose:      spacerepo.TempObjectPurposeAvatar,
		BucketID:     "b2-eu-cen",
		ExpectedSize: 333,
		ExpiresAt:    timeutil.MicrosecondsAfterMinutes(30),
	}))
	_, err = testUpdateProfile(ctx, repos, aliceID, space.SpaceID, rotated.CurrentVersion, "alice-profile-v4",
		&spacerepo.ProfileAssetUpdate{ObjectID: "avatar-v2-object-id", BucketID: "b2-eu-cen", Size: 333},
		nil,
		false,
		false,
	)
	require.NoError(t, err)

	resp, err = module.Spaces.GetProfile(ginCtx, models.GetSpaceProfileRequest{SpaceID: space.SpaceID})
	require.NoError(t, err)
	require.Equal(t, 2, resp.Avatar.KeyVersion)
	require.Equal(t, "avatar-v2-object-id", resp.Avatar.ObjectID)
	require.Equal(t, 1, resp.Cover.KeyVersion)
	require.Equal(t, "cover-object-id", resp.Cover.ObjectID)
}

func TestGetProfileRejectsInvalidVersion(t *testing.T) {
	module, repos, userAuthRepo, ctx := setupSpaceAuthControllerTest(t)
	aliceID := insertSpaceControllerUser(t, repos, "alice@example.com", "alice-public")
	space, err := testCreateSpace(ctx, repos, aliceID, "alice", "alice-space-key", "alice-public", "alice-secret", "alice-secret-nonce", "alice-profile")
	require.NoError(t, err)
	require.NoError(t, userAuthRepo.AddToken(aliceID, ente.Photos, "alice-token", "127.0.0.1", "space-test"))
	ginCtx := newPublicSpaceContext()
	ginCtx.Request.Header.Set("X-Auth-Token", "alice-token")
	version := 0

	resp, err := module.Spaces.GetProfile(ginCtx, models.GetSpaceProfileRequest{
		SpaceID: space.SpaceID,
		Version: &version,
	})

	require.Nil(t, resp)
	require.Error(t, err)
}

func TestRotateKeyRejectsStaleKeyVersion(t *testing.T) {
	module, repos, _, ctx := setupSpaceAuthControllerTest(t)
	aliceID := insertSpaceControllerUser(t, repos, "alice@example.com", "alice-public")
	space, err := testCreateSpace(ctx, repos, aliceID, "alice", "alice-space-key-v1", "alice-public", "alice-secret", "alice-secret-nonce", "alice-profile-v1")
	require.NoError(t, err)

	resp, err := module.Spaces.RotateKey(ctx, space, models.RotateSpaceKeyRequest{
		KeyVersion:          space.CurrentVersion + 1,
		RootWrappedSpaceKey: "YWxpY2Utc3BhY2Uta2V5LXYy",
		WrappedPrevKey:      "d3JhcHBlZC1wcmV2LWtleQ==",
		EncryptedProfile:    "YWxpY2UtcHJvZmlsZS12Mg==",
	})

	require.Nil(t, resp)
	var apiErr *ente.ApiError
	require.ErrorAs(t, err, &apiErr)
	require.Equal(t, ente.BadRequest, apiErr.Code)
	require.Equal(t, "keyVersion does not match current space version", apiErr.Message)
}

func TestUpdateProfileRejectsStaleKeyVersion(t *testing.T) {
	module, repos, _, ctx := setupSpaceAuthControllerTest(t)
	aliceID := insertSpaceControllerUser(t, repos, "alice@example.com", "alice-public")
	space, err := testCreateSpace(ctx, repos, aliceID, "alice", "alice-space-key-v1", "alice-public", "alice-secret", "alice-secret-nonce", "alice-profile-v1")
	require.NoError(t, err)

	resp, err := module.Spaces.UpdateProfile(ctx, space, models.UpdateSpaceProfileRequest{
		KeyVersion:       space.CurrentVersion + 1,
		EncryptedProfile: "YWxpY2UtcHJvZmlsZS12Mg==",
	})

	require.Nil(t, resp)
	var apiErr *ente.ApiError
	require.ErrorAs(t, err, &apiErr)
	require.Equal(t, ente.BadRequest, apiErr.Code)
	require.Equal(t, "keyVersion does not match current space version", apiErr.Message)
}

func TestSlugAvailabilityReturnsFalseForExistingAndReservedSlugs(t *testing.T) {
	module, repos, _, ctx := setupSpaceAuthControllerTest(t)
	aliceID := insertSpaceControllerUser(t, repos, "alice-availability@example.com", "alice-public")
	_, err := testCreateSpace(ctx, repos, aliceID, "alice", "alice-space-key", "alice-public", "alice-secret", "alice-secret-nonce", "alice-profile")
	require.NoError(t, err)
	ginCtx := newPublicSpaceContext()

	existing, err := module.Spaces.SlugAvailability(ginCtx, "Alice")
	require.NoError(t, err)
	require.False(t, existing.Available)

	reserved, err := module.Spaces.SlugAvailability(ginCtx, "support")
	require.NoError(t, err)
	require.False(t, reserved.Available)

	free, err := module.Spaces.SlugAvailability(ginCtx, "new_person")
	require.NoError(t, err)
	require.True(t, free.Available)
}

func TestLookupBySlugHidesDeletedOwnerButReservesSlug(t *testing.T) {
	module, repos, _, ctx := setupSpaceAuthControllerTest(t)
	aliceID := insertSpaceControllerUser(t, repos, "alice-deleted-lookup@example.com", "alice-public")
	_, err := testCreateSpace(ctx, repos, aliceID, "alice_deleted_lookup", "alice-space-key", "alice-public", "alice-secret", "alice-secret-nonce", "alice-profile")
	require.NoError(t, err)
	ginCtx := newPublicSpaceContext()

	lookup, err := module.Spaces.LookupBySlug(ginCtx, "alice_deleted_lookup")
	require.NoError(t, err)
	require.Equal(t, "alice_deleted_lookup", lookup.SpaceSlug)

	_, err = repos.Spaces.DB.Exec(`UPDATE users SET encrypted_email = NULL WHERE user_id = $1`, aliceID)
	require.NoError(t, err)

	lookup, err = module.Spaces.LookupBySlug(ginCtx, "alice_deleted_lookup")
	require.Nil(t, lookup)
	require.Error(t, err)

	availability, err := module.Spaces.SlugAvailability(ginCtx, "alice_deleted_lookup")
	require.NoError(t, err)
	require.False(t, availability.Available)
}
