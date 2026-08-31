package user

import (
	"crypto/rand"
	"encoding/base64"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/crypto"
	enteTime "github.com/ente/museum/pkg/utils/time"
	"github.com/gin-gonic/gin"
	"github.com/pquerna/otp/totp"
	"golang.org/x/crypto/nacl/box"
)

func TestTwoFactorSessionIsConsumedOnlyAfterSuccessfulAuthorization(t *testing.T) {
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })

	const (
		userID     int64 = 12345
		totpSecret       = "JBSWY3DPEHPK3PXP"
	)
	testutil.InsertUser(t, db, testutil.UserFixture{UserID: userID, Email: "totp@example.com", CreationTime: 1})
	if _, err := db.Exec(`UPDATE users SET email_mfa = true WHERE user_id = $1`, userID); err != nil {
		t.Fatal(err)
	}

	publicKey, _, err := box.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	userRepo := &repo.UserRepository{
		DB:                  db,
		SecretEncryptionKey: testutil.SecretEncryptionKey(),
		HashingKey:          testutil.HashingKey(),
	}
	if err = userRepo.SetKeyAttributes(userID, ente.KeyAttributes{
		KEKSalt: "salt", KEKHash: "hash", EncryptedKey: "key", KeyDecryptionNonce: "nonce",
		PublicKey: base64.StdEncoding.EncodeToString(publicKey[:]), EncryptedSecretKey: "secret-key",
		SecretKeyDecryptionNonce: "secret-nonce", MemLimit: 1, OpsLimit: 1,
	}); err != nil {
		t.Fatal(err)
	}
	encryptedSecret, err := crypto.Encrypt(totpSecret, testutil.SecretEncryptionKey())
	if err != nil {
		t.Fatal(err)
	}
	secretHash, err := crypto.GetHash(totpSecret, testutil.HashingKey())
	if err != nil {
		t.Fatal(err)
	}
	if err = userRepo.SetTwoFactorSecret(userID, encryptedSecret, secretHash, "recovery-secret", "recovery-nonce"); err != nil {
		t.Fatal(err)
	}

	twoFactorRepo := &repo.TwoFactorRepository{DB: db, SecretEncryptionKey: testutil.SecretEncryptionKey()}
	if err = twoFactorRepo.UpdateTwoFactorStatus(userID, true); err != nil {
		t.Fatal(err)
	}
	controller := &UserController{
		UserRepo:      userRepo,
		UserAuthRepo:  &repo.UserAuthRepository{DB: db},
		TwoFactorRepo: twoFactorRepo,
		HashingKey:    testutil.HashingKey(),
	}
	gin.SetMode(gin.TestMode)
	context, _ := gin.CreateTestContext(httptest.NewRecorder())
	context.Request = httptest.NewRequest(http.MethodPost, "/users/two-factor/verify", nil)

	const verifySessionID = "verify-session"
	if err = twoFactorRepo.AddTwoFactorSession(userID, verifySessionID, enteTime.Microseconds()+TwoFactorValidityDurationInMicroSeconds); err != nil {
		t.Fatal(err)
	}
	code, err := totp.GenerateCode(totpSecret, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if _, err = controller.VerifyTwoFactor(context, verifySessionID, code); err != nil {
		t.Fatalf("verification failed: %v", err)
	}
	var sessionExists bool
	if err = db.QueryRow(`SELECT EXISTS(SELECT 1 FROM two_factor_sessions WHERE session_id = $1)`, verifySessionID).Scan(&sessionExists); err != nil {
		t.Fatal(err)
	}
	if sessionExists {
		t.Fatal("verification session was not consumed")
	}

	const recoverySessionID = "recovery-session"
	if err = twoFactorRepo.AddTwoFactorSession(userID, recoverySessionID, enteTime.Microseconds()+TwoFactorValidityDurationInMicroSeconds); err != nil {
		t.Fatal(err)
	}
	if _, err = controller.VerifyTwoFactor(context, recoverySessionID, "invalid"); !errors.Is(err, ente.ErrIncorrectTOTP) {
		t.Fatalf("invalid verification error = %v, want incorrect TOTP", err)
	}
	if err = db.QueryRow(`SELECT EXISTS(SELECT 1 FROM two_factor_sessions WHERE session_id = $1)`, recoverySessionID).Scan(&sessionExists); err != nil {
		t.Fatal(err)
	}
	if !sessionExists {
		t.Fatal("failed verification consumed the session")
	}
	if _, err = controller.RemoveTOTPTwoFactor(context, recoverySessionID, totpSecret); err != nil {
		t.Fatalf("recovery failed: %v", err)
	}
	if err = db.QueryRow(`SELECT EXISTS(SELECT 1 FROM two_factor_sessions WHERE session_id = $1)`, recoverySessionID).Scan(&sessionExists); err != nil {
		t.Fatal(err)
	}
	if sessionExists {
		t.Fatal("recovery session was not consumed")
	}
}
