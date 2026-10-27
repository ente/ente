package user

import (
	"encoding/base64"
	"net/http"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/crypto"
	enteTime "github.com/ente/museum/pkg/utils/time"
	"github.com/pquerna/otp/totp"
	"github.com/stretchr/testify/require"
)

func TestEnableTwoFactorValidatesRecoveryData(t *testing.T) {
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })

	const userID int64 = 12345
	const secret = "JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP"
	testutil.InsertUser(t, db, testutil.UserFixture{UserID: userID, Email: "totp@example.com", CreationTime: 1})
	controller := &UserController{
		UserRepo:            &repo.UserRepository{DB: db},
		TwoFactorRepo:       &repo.TwoFactorRepository{DB: db},
		SecretEncryptionKey: testutil.SecretEncryptionKey(),
		HashingKey:          testutil.HashingKey(),
	}
	encryptedSecret, err := crypto.Encrypt(secret, controller.SecretEncryptionKey)
	require.NoError(t, err)
	secretHash, err := crypto.GetHash(secret, controller.HashingKey)
	require.NoError(t, err)
	require.NoError(t, controller.TwoFactorRepo.SetTempTwoFactorSecret(userID, encryptedSecret, secretHash,
		enteTime.Microseconds()+TwoFactorValidityDurationInMicroSeconds))

	secretBytes, err := base64.StdEncoding.DecodeString(secret)
	require.NoError(t, err)
	recoverySecret, err := crypto.Encrypt(string(secretBytes), testutil.SecretEncryptionKey())
	require.NoError(t, err)
	code, err := totp.GenerateCode(secret, time.Now())
	require.NoError(t, err)
	request := ente.TwoFactorEnableRequest{
		Code:                           code,
		EncryptedTwoFactorSecret:       base64.StdEncoding.EncodeToString(recoverySecret.Cipher),
		TwoFactorSecretDecryptionNonce: base64.StdEncoding.EncodeToString(recoverySecret.Nonce),
	}
	for _, tc := range []struct{ name, ciphertext, nonce string }{
		{"old CLI encoding", base64.StdEncoding.EncodeToString(encryptedSecret.Cipher), request.TwoFactorSecretDecryptionNonce},
		{"empty ciphertext", "", request.TwoFactorSecretDecryptionNonce},
		{"malformed ciphertext", "!", request.TwoFactorSecretDecryptionNonce},
		{"empty nonce", request.EncryptedTwoFactorSecret, ""},
		{"malformed nonce", request.EncryptedTwoFactorSecret, "!"},
		{"short nonce", request.EncryptedTwoFactorSecret, base64.StdEncoding.EncodeToString(recoverySecret.Nonce[:23])},
	} {
		t.Run(tc.name, func(t *testing.T) {
			invalid := request
			invalid.EncryptedTwoFactorSecret = tc.ciphertext
			invalid.TwoFactorSecretDecryptionNonce = tc.nonce
			var apiError *ente.ApiError
			require.ErrorAs(t, controller.EnableTwoFactor(userID, invalid), &apiError)
			require.Equal(t, http.StatusBadRequest, apiError.HttpStatusCode)
		})
	}
	var count int
	require.NoError(t, db.QueryRow(`SELECT count(*) FROM two_factor WHERE user_id = $1`, userID).Scan(&count))
	require.Zero(t, count)
	enabled, err := controller.UserRepo.IsTwoFactorEnabled(userID)
	require.NoError(t, err)
	require.False(t, enabled)

	require.NoError(t, controller.EnableTwoFactor(userID, request))
	enabled, err = controller.UserRepo.IsTwoFactorEnabled(userID)
	require.NoError(t, err)
	require.True(t, enabled)
	recovery, err := controller.TwoFactorRepo.GetRecoveryKeyEncryptedTwoFactorSecret(userID)
	require.NoError(t, err)
	require.Equal(t, request.EncryptedTwoFactorSecret, recovery.EncryptedSecret)
	require.Equal(t, request.TwoFactorSecretDecryptionNonce, recovery.SecretDecryptionNonce)
}
