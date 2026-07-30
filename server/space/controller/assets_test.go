package controller

import (
	"context"
	"net/http"
	"strconv"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/space/models"
	spacerepo "github.com/ente/museum/space/repo"
	"github.com/spf13/viper"
	"github.com/stretchr/testify/require"
)

type testSpaceAssetBuckets map[string]bool

func (b testSpaceAssetBuckets) IsBucketActive(bucketID string) bool {
	return b[bucketID]
}

func TestPresignUploadRejectsOversizedPost(t *testing.T) {
	controller := &AssetsController{}
	ctx := context.Background()
	space := &spacerepo.SpaceRecord{SpaceID: "space-1"}

	_, err := controller.PresignUpload(ctx, space, models.PresignUploadRequest{
		Size:       maxPostUploadBytes + 1,
		ContentMD5: "XUFAKrxLKna5cZ2REBfFkg==",
	})

	require.Error(t, err)
	require.Contains(t, err.Error(), strconv.FormatInt(maxPostUploadBytes, 10))
}

func TestPresignUploadRejectsOversizedAvatar(t *testing.T) {
	controller := &AssetsController{}
	ctx := context.Background()
	space := &spacerepo.SpaceRecord{SpaceID: "space-1"}
	purpose := uploadPurposeAvatar

	_, err := controller.PresignUpload(ctx, space, models.PresignUploadRequest{
		Size:       maxAvatarUploadBytes + 1,
		ContentMD5: "XUFAKrxLKna5cZ2REBfFkg==",
		Purpose:    &purpose,
	})

	require.Error(t, err)
	require.Contains(t, err.Error(), strconv.FormatInt(maxAvatarUploadBytes, 10))
}

func TestPresignUploadRejectsOversizedCover(t *testing.T) {
	controller := &AssetsController{}
	ctx := context.Background()
	space := &spacerepo.SpaceRecord{SpaceID: "space-1"}
	purpose := uploadPurposeCover

	_, err := controller.PresignUpload(ctx, space, models.PresignUploadRequest{
		Size:       maxCoverUploadBytes + 1,
		ContentMD5: "XUFAKrxLKna5cZ2REBfFkg==",
		Purpose:    &purpose,
	})

	require.Error(t, err)
	require.Contains(t, err.Error(), strconv.FormatInt(maxCoverUploadBytes, 10))
}

func TestMaxUploadBytesForPurpose(t *testing.T) {
	postLimit, err := maxUploadBytesForPurpose(uploadPurposePost)
	require.NoError(t, err)
	require.Equal(t, maxPostUploadBytes, postLimit)

	avatarLimit, err := maxUploadBytesForPurpose(uploadPurposeAvatar)
	require.NoError(t, err)
	require.Equal(t, maxAvatarUploadBytes, avatarLimit)

	coverLimit, err := maxUploadBytesForPurpose(uploadPurposeCover)
	require.NoError(t, err)
	require.Equal(t, maxCoverUploadBytes, coverLimit)
}

func TestNormalizeContentMD5(t *testing.T) {
	normalized, err := normalizeContentMD5("5d41402abc4b2a76b9719d911017c592")
	require.NoError(t, err)
	require.Equal(t, "XUFAKrxLKna5cZ2REBfFkg==", normalized)

	normalized, err = normalizeContentMD5(" XUFAKrxLKna5cZ2REBfFkg== ")
	require.NoError(t, err)
	require.Equal(t, "XUFAKrxLKna5cZ2REBfFkg==", normalized)
}

func TestNormalizeContentMD5RejectsInvalidValues(t *testing.T) {
	_, err := normalizeContentMD5("")
	require.Error(t, err)
	require.Contains(t, err.Error(), "contentMD5 is required")

	_, err = normalizeContentMD5("not-md5")
	require.Error(t, err)
	require.Contains(t, err.Error(), "contentMD5 must be base64 or hex encoded")

	_, err = normalizeContentMD5("aGVsbG8=")
	require.Error(t, err)
	require.Contains(t, err.Error(), "contentMD5 must be exactly 16 bytes")
}

func TestValidateSpaceAssetsBucketID(t *testing.T) {
	activeBuckets := testSpaceAssetBuckets{"b2-eu-cen": true}

	bucketID, err := validateSpaceAssetsBucketID(" b2-eu-cen ", activeBuckets)
	require.NoError(t, err)
	require.Equal(t, "b2-eu-cen", bucketID)

	for _, value := range []string{"", "   "} {
		bucketID, err = validateSpaceAssetsBucketID(value, activeBuckets)
		requireSpaceAssetsUnavailable(t, err)
		require.Empty(t, bucketID)
	}

	bucketID, err = validateSpaceAssetsBucketID("missing-bucket", activeBuckets)
	requireSpaceAssetsUnavailable(t, err)
	require.Empty(t, bucketID)

	bucketID, err = validateSpaceAssetsBucketID("b2-eu-cen", nil)
	requireSpaceAssetsUnavailable(t, err)
	require.Empty(t, bucketID)
}

func TestPresignUploadReturnsUnavailableWhenSpaceAssetBucketMissing(t *testing.T) {
	module, repos, _, ctx := setupSpaceAuthControllerTest(t)
	aliceID := insertSpaceControllerUser(t, repos, "alice-asset-config@example.com", "alice-public")
	space, err := testCreateSpace(ctx, repos, aliceID, "alice_asset_config", "alice-space-key", "alice-public", "alice-secret", "alice-secret-nonce", "alice-profile")
	require.NoError(t, err)
	viper.Set(spaceAssetsPrimaryBucketConfigKey, "")
	t.Cleanup(func() {
		viper.Set(spaceAssetsPrimaryBucketConfigKey, "")
	})
	resp, err := module.Assets.PresignUpload(ctx, space, models.PresignUploadRequest{
		Size:       1,
		ContentMD5: "XUFAKrxLKna5cZ2REBfFkg==",
	})

	require.Nil(t, resp)
	requireSpaceAssetsUnavailable(t, err)
}

func requireSpaceAssetsUnavailable(t *testing.T, err error) {
	t.Helper()
	var apiErr *ente.ApiError
	require.ErrorAs(t, err, &apiErr)
	require.Equal(t, ente.ErrorCode("SPACE_ASSETS_UNAVAILABLE"), apiErr.Code)
	require.Equal(t, http.StatusServiceUnavailable, apiErr.HttpStatusCode)
	require.Equal(t, "space asset storage is unavailable", apiErr.Message)
}

func TestRedirectRejectsInvalidProfileAssetObjectID(t *testing.T) {
	module, repos, userAuthRepo, ctx := setupSpaceAuthControllerTest(t)
	aliceID := insertSpaceControllerUser(t, repos, "alice-asset-redirect@example.com", "alice-public")
	space, err := testCreateSpace(ctx, repos, aliceID, "alice_asset_redirect", "alice-space-key", "alice-public", "alice-secret", "alice-secret-nonce", "alice-profile")
	require.NoError(t, err)
	require.NoError(t, userAuthRepo.AddToken(aliceID, ente.Photos, "alice-asset-token", "127.0.0.1", "space-test"))
	ginCtx := newPublicSpaceContext()
	ginCtx.Request.Header.Set("X-Auth-Token", "alice-asset-token")

	resp, err := module.Assets.Redirect(ginCtx, models.AssetRedirectRequest{
		SpaceID:   space.SpaceID,
		AssetType: "avatar",
		ObjectID:  "nested/object",
	})

	require.Nil(t, resp)
	var apiErr *ente.ApiError
	require.ErrorAs(t, err, &apiErr)
	require.Equal(t, ente.BadRequest, apiErr.Code)
	require.Equal(t, "objectKey or assetType and objectID are required", apiErr.Message)
}
