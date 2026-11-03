package user

import (
	"crypto/rand"
	"database/sql"
	"encoding/base64"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/ente/museum/ente"
	enteJWT "github.com/ente/museum/ente/jwt"
	"github.com/ente/museum/internal/testutil"
	museumcontroller "github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/repo/passkey"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
	"golang.org/x/crypto/nacl/box"
)

func TestEncryptedAuthTokenPayload(t *testing.T) {
	controller, ctx, publicKey, privateKey := setupAuthPayloadTest(t)
	legacyToken := auth.GenerateURLSafeRandomString(TokenLength)
	require.NoError(t, controller.UserAuthRepo.AddToken(12345, ente.Photos, legacyToken, "", ""))
	login, err := controller.onVerificationSuccess(ctx, "payload@example.com", nil, nil)
	require.NoError(t, err)
	require.Empty(t, login.Token)
	completion, err := controller.GetKeyAttributeAndToken(ctx, 12345, "", repo.NoPendingLogin, false, false)
	require.NoError(t, err)
	for _, ciphertext := range []string{login.EncryptedToken, completion.EncryptedToken} {
		payload := openAuthPayload(t, ciphertext, publicKey, privateKey)
		require.Len(t, payload, 42)
		require.Equal(t, "auth-token", string(payload[:10]))
		bearer := base64.URLEncoding.EncodeToString(payload)
		require.Len(t, bearer, 56)
		require.NotContains(t, bearer, "=")
		hash := auth.HashToken(bearer)
		userID, expired, err := controller.UserAuthRepo.GetUserIDWithTokenHash(hash[:], ente.Photos)
		require.NoError(t, err)
		require.EqualValues(t, 12345, userID)
		require.False(t, expired)
		strippedHash := auth.HashToken(base64.URLEncoding.EncodeToString(payload[10:]))
		_, _, err = controller.UserAuthRepo.GetUserIDWithTokenHash(strippedHash[:], ente.Photos)
		require.ErrorIs(t, err, sql.ErrNoRows)
	}
	legacyHash := auth.HashToken(legacyToken)
	userID, expired, err := controller.UserAuthRepo.GetUserIDWithTokenHash(legacyHash[:], ente.Photos)
	require.NoError(t, err)
	require.EqualValues(t, 12345, userID)
	require.False(t, expired)
}

func TestSignupTokenRemainsUnprefixed(t *testing.T) {
	controller, ctx, _, _ := setupAuthPayloadTest(t)
	_, err := controller.UserRepo.DB.Exec(`DELETE FROM key_attributes WHERE user_id = 12345`)
	require.NoError(t, err)
	response, err := controller.onVerificationSuccess(ctx, "payload@example.com", nil, nil)
	require.NoError(t, err)
	require.Empty(t, response.EncryptedToken)
	payload, err := base64.URLEncoding.DecodeString(response.Token)
	require.NoError(t, err)
	require.Len(t, payload, 32)
	hash := auth.HashToken(response.Token)
	userID, _, err := controller.UserAuthRepo.GetUserIDWithTokenHash(hash[:], ente.Photos)
	require.NoError(t, err)
	require.EqualValues(t, 12345, userID)
}

func TestDeleteChallengePayload(t *testing.T) {
	controller, ctx, publicKey, privateKey := setupAuthPayloadTest(t)
	response, err := controller.GetDeleteChallengeToken(ctx)
	require.NoError(t, err)
	require.NotNil(t, response.EncryptedChallenge)
	payload := openAuthPayload(t, *response.EncryptedChallenge, publicKey, privateKey)
	require.Greater(t, len(payload), 10)
	require.Equal(t, "delete-jwt", string(payload[:10]))
	claim, err := controller.ValidateJWTToken(string(payload[10:]), enteJWT.DELETE_ACCOUNT)
	require.NoError(t, err)
	require.EqualValues(t, 12345, claim.UserID)
}

func setupAuthPayloadTest(t *testing.T) (*UserController, *gin.Context, *[32]byte, *[32]byte) {
	t.Helper()
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	testutil.InsertUser(t, db, testutil.UserFixture{UserID: 12345, Email: "payload@example.com", CreationTime: 1})
	_, err := db.Exec(`UPDATE users SET email_mfa = true WHERE user_id = 12345`)
	require.NoError(t, err)
	publicKey, privateKey, err := box.GenerateKey(rand.Reader)
	require.NoError(t, err)
	userRepo := &repo.UserRepository{DB: db, SecretEncryptionKey: testutil.SecretEncryptionKey(), HashingKey: testutil.HashingKey()}
	userRepo.PasskeysRepository = &passkey.Repository{DB: db}
	require.NoError(t, userRepo.SetKeyAttributes(12345, ente.KeyAttributes{
		KEKSalt: "salt", EncryptedKey: "key", KeyDecryptionNonce: "nonce",
		PublicKey: base64.StdEncoding.EncodeToString(publicKey[:]), EncryptedSecretKey: "secret-key",
		SecretKeyDecryptionNonce: "secret-nonce", MemLimit: 1, OpsLimit: 1,
	}))
	controller := &UserController{
		UserRepo:          userRepo,
		UserAuthRepo:      &repo.UserAuthRepository{DB: db},
		BillingController: &museumcontroller.BillingController{BillingRepo: &repo.BillingRepository{DB: db}},
		JwtSecret:         []byte("test-jwt-signing-key"),
	}
	gin.SetMode(gin.TestMode)
	ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
	ctx.Request = httptest.NewRequest(http.MethodPost, "/users/verify-email", nil)
	ctx.Request.Header.Set("X-Auth-User-ID", "12345")
	return controller, ctx, publicKey, privateKey
}

func openAuthPayload(t *testing.T, ciphertext string, publicKey, privateKey *[32]byte) []byte {
	t.Helper()
	sealed, err := base64.StdEncoding.DecodeString(ciphertext)
	require.NoError(t, err)
	payload, ok := box.OpenAnonymous(nil, sealed, publicKey, privateKey)
	require.True(t, ok, "sealed payload failed authentication")
	return payload
}
