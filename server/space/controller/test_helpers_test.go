package controller

import (
	"context"
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/ente/museum/internal/testutil"
	timeutil "github.com/ente/museum/pkg/utils/time"
	spacerepo "github.com/ente/museum/space/repo"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func setupPostsControllerTest(t *testing.T) (*PostsController, *spacerepo.Module, context.Context) {
	t.Helper()
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})
	gin.SetMode(gin.TestMode)
	repos := spacerepo.NewModule(db, nil)
	return NewModule(repos, nil).Posts, repos, context.Background()
}

func testSpaceBytes(value string) []byte {
	return []byte(value)
}

func testCreateSpace(ctx context.Context, module *spacerepo.Module, ownerID int64, spaceSlug string, rootWrappedSpaceKey string, publicKey string, encryptedSecretKey string, _ string, encryptedProfile string) (*spacerepo.SpaceRecord, error) {
	return module.Spaces.CreateSpace(ctx, ownerID, spaceSlug, testSpaceBytes(rootWrappedSpaceKey), testSpaceBytes(publicKey), testSpaceBytes(encryptedSecretKey), testSpaceBytes(encryptedProfile), "")
}

func testUpdateProfile(ctx context.Context, module *spacerepo.Module, _ int64, spaceID string, keyVersion int, encryptedProfile string, avatar *spacerepo.ProfileAssetUpdate, cover *spacerepo.ProfileAssetUpdate, removeAvatar bool, removeCover bool) (*spacerepo.SpaceRecord, error) {
	return module.Spaces.UpdateProfile(ctx, spaceID, keyVersion, testSpaceBytes(encryptedProfile), avatar, cover, removeAvatar, removeCover)
}

func testRotateKey(ctx context.Context, module *spacerepo.Module, _ int64, spaceID string, keyVersion int, rootWrappedSpaceKey string, wrappedPrevKey string, encryptedProfile string) (*spacerepo.SpaceRecord, error) {
	return module.Spaces.RotateKey(ctx, spaceID, keyVersion, testSpaceBytes(rootWrappedSpaceKey), testSpaceBytes(wrappedPrevKey), testSpaceBytes(encryptedProfile))
}

func testAddFriend(ctx context.Context, module *spacerepo.Module, requesterID int64, requesterSpaceID string, targetSpaceID string, targetFriendSealedSpaceKey string, targetKeyVersion int, requesterFriendSealedSpaceKey string, requesterKeyVersion int) error {
	request, _, _, err := module.Friends.CreateFriendRequest(ctx, requesterID, requesterSpaceID, targetSpaceID, testSpaceBytes(requesterFriendSealedSpaceKey), requesterKeyVersion)
	if err != nil {
		return err
	}
	_, _, err = module.Friends.ConfirmFriendRequest(ctx, targetSpaceID, request.RequestID, testSpaceBytes(targetFriendSealedSpaceKey), targetKeyVersion)
	return err
}

func testCreatePost(ctx context.Context, module *spacerepo.Module, _ int64, spaceID string, encryptedPostKey string, captionCipher *string, keyVersion int, objects []spacerepo.SpacePostAssetRecord) (int64, error) {
	var caption []byte
	if captionCipher != nil {
		caption = testSpaceBytes(*captionCipher)
	}
	postID, _, err := module.Posts.CreatePost(ctx, spaceID, testSpaceBytes(encryptedPostKey), caption, keyVersion, objects)
	return postID, err
}

func insertSpaceControllerUser(t *testing.T, module *spacerepo.Module, email string, publicKey string) int64 {
	t.Helper()
	userID := testutil.InsertUser(t, module.Spaces.DB, testutil.UserFixture{
		Email:        email,
		CreationTime: timeutil.Microseconds(),
	})
	_, err := module.Spaces.DB.Exec(`
		INSERT INTO key_attributes (
			user_id, kek_salt, kek_hash_bytes, encrypted_key, key_decryption_nonce,
			public_key, encrypted_secret_key, secret_key_decryption_nonce
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
	`, userID, "salt", []byte{1, 2, 3}, "encrypted-key", "nonce", publicKey, "encrypted-secret-key", "secret-nonce")
	require.NoError(t, err)
	return userID
}

func newSpaceControllerContext(userID int64) *gin.Context {
	recorder := httptest.NewRecorder()
	ctx, _ := gin.CreateTestContext(recorder)
	ctx.Request = httptest.NewRequest("POST", "/", nil)
	ctx.Request.Header.Set("X-Auth-User-ID", strconv.FormatInt(userID, 10))
	return ctx
}
