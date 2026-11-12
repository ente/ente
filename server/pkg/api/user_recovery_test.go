package api

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/repo/passkey"
	"github.com/ente/museum/pkg/repo/two_factor_recovery"
	"github.com/ente/museum/pkg/utils/crypto"
	enteTime "github.com/ente/museum/pkg/utils/time"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
	"golang.org/x/crypto/nacl/box"
)

func TestRemoveTwoFactorRejectsInvalidCredentials(t *testing.T) {
	gin.SetMode(gin.TestMode)
	handler := &UserHandler{}
	for _, body := range []string{
		`{}`,
		`{"secret":"","proof":""}`,
		`{"secret":"secret","proof":"proof","twoFactorType":"totp"}`,
		`{"proof":"proof"}`,
		`{"proof":"proof","twoFactorType":"other"}`,
		`{"proof":"proof","twoFactorType":"TOTP"}`,
	} {
		t.Run(body, func(t *testing.T) {
			recorder := httptest.NewRecorder()
			ctx, _ := gin.CreateTestContext(recorder)
			ctx.Request = httptest.NewRequest(http.MethodPost, "/users/two-factor/remove", strings.NewReader(body))
			handler.RemoveTwoFactor(ctx)
			require.Equal(t, http.StatusBadRequest, recorder.Code)
		})
	}
}

func TestRemoveTwoFactorRecovery(t *testing.T) {
	for _, factor := range []string{"totp", "passkey"} {
		cases := []string{"proof", "secret", "invalid proof", "invalid secret", "expired"}
		if factor == "passkey" {
			cases = append(cases, "claimed")
		} else {
			cases = append(cases, "legacy missing type", "legacy unknown type")
		}
		for _, name := range cases {
			t.Run(factor+"/"+name, func(t *testing.T) {
				handler, db := setupUserHandlerTest(t)
				controller := handler.UserController
				const userID int64 = 12345
				const sessionID = "recovery-session"
				secret := "JBSWY3DPEHPK3PXP"
				if factor == "passkey" {
					secret = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8="
				}
				testutil.InsertUser(t, db, testutil.UserFixture{UserID: userID, Email: "recovery@example.com", CreationTime: 1})
				_, err := db.Exec(`UPDATE users SET email_mfa = true, is_two_factor_enabled = true WHERE user_id = $1`, userID)
				require.NoError(t, err)
				publicKey, _, err := box.GenerateKey(rand.Reader)
				require.NoError(t, err)
				attributes := ente.KeyAttributes{
					KEKSalt: "salt", EncryptedKey: "key", KeyDecryptionNonce: "nonce",
					PublicKey: base64.StdEncoding.EncodeToString(publicKey[:]), EncryptedSecretKey: "secret-key",
					SecretKeyDecryptionNonce: "secret-nonce", MemLimit: 1, OpsLimit: 1,
				}
				require.NoError(t, controller.UserRepo.SetKeyAttributes(userID, attributes))
				controller.UserAuthRepo = &repo.UserAuthRepository{DB: db}
				controller.TwoFactorRepo = &repo.TwoFactorRepository{DB: db, SecretEncryptionKey: testutil.SecretEncryptionKey()}
				controller.PasskeyRepo = &passkey.Repository{DB: db}
				controller.TwoFactorRecoveryRepo = &two_factor_recovery.Repository{Db: db, SecretEncryptionKey: testutil.SecretEncryptionKey()}
				controller.HashingKey = testutil.HashingKey()
				expires := enteTime.NMinFromNow(10)
				if name == "expired" {
					expires = enteTime.Microseconds() - 1
				}
				sessionTable := "two_factor_sessions"
				if factor == "totp" {
					encrypted, err := crypto.Encrypt(secret, testutil.SecretEncryptionKey())
					require.NoError(t, err)
					hash, err := crypto.GetHash(secret, testutil.HashingKey())
					require.NoError(t, err)
					require.NoError(t, controller.UserRepo.SetTwoFactorSecret(userID, encrypted, hash, "recovery-secret", "recovery-nonce"))
					require.NoError(t, controller.TwoFactorRepo.AddTwoFactorSession(userID, sessionID, expires))
				} else {
					sessionTable = "passkey_login_sessions"
					require.NoError(t, controller.TwoFactorRecoveryRepo.SetPasskeyRecovery(t.Context(), userID, &ente.SetPasskeyRecoveryRequest{Secret: secret, UserSecretCipher: "cipher", UserSecretNonce: "nonce"}))
					require.NoError(t, controller.PasskeyRepo.AddPasskeyTwoFactorSession(userID, sessionID, expires))
					_, err = db.Exec(`INSERT INTO passkeys (id, user_id, friendly_name) VALUES ('00000000-0000-0000-0000-000000000001', $1, 'Test')`, userID)
					require.NoError(t, err)
					if name == "claimed" {
						_, err = db.Exec(`UPDATE passkey_login_sessions SET verified_at = $1 WHERE session_id = $2`, enteTime.Microseconds(), sessionID)
						require.NoError(t, err)
					}
				}
				request := ente.TwoFactorRemovalRequest{SessionID: sessionID, TwoFactorType: factor}
				if strings.Contains(name, "secret") || strings.HasPrefix(name, "legacy") {
					request.Secret = secret
					if name == "invalid secret" {
						request.Secret += "x"
					}
				} else {
					mac := hmac.New(sha256.New, []byte(secret))
					mac.Write([]byte("recovery:" + factor + ":" + sessionID))
					request.Proof = base64.StdEncoding.EncodeToString(mac.Sum(nil))
					if name == "invalid proof" {
						request.Proof = "invalid"
					}
				}
				if name == "legacy missing type" {
					request.TwoFactorType = ""
				} else if name == "legacy unknown type" {
					request.TwoFactorType = "unknown"
				}
				body, err := json.Marshal(request)
				require.NoError(t, err)
				send := func() *httptest.ResponseRecorder {
					recorder := httptest.NewRecorder()
					ctx, _ := gin.CreateTestContext(recorder)
					ctx.Request = httptest.NewRequest(http.MethodPost, "/users/two-factor/remove", strings.NewReader(string(body)))
					handler.RemoveTwoFactor(ctx)
					return recorder
				}
				recorder := send()
				success := name == "proof" || name == "secret" || strings.HasPrefix(name, "legacy")
				if success {
					require.Equal(t, http.StatusOK, recorder.Code, recorder.Body.String())
					var response ente.TwoFactorAuthorizationResponse
					require.NoError(t, json.Unmarshal(recorder.Body.Bytes(), &response))
					require.NotEmpty(t, response.EncryptedToken)
					require.NotEqual(t, http.StatusOK, send().Code, "replayed recovery succeeded")
				} else {
					require.NotEqual(t, http.StatusOK, recorder.Code)
				}
				var sessions, tokens int
				require.NoError(t, db.QueryRow("SELECT COUNT(*) FROM "+sessionTable+" WHERE session_id = $1", sessionID).Scan(&sessions))
				require.NoError(t, db.QueryRow(`SELECT COUNT(*) FROM tokens WHERE user_id = $1`, userID).Scan(&tokens))
				if success {
					require.Equal(t, 0, sessions)
					require.Equal(t, 1, tokens)
				} else {
					require.Equal(t, 1, sessions)
					require.Equal(t, 0, tokens)
				}
				enabled, err := controller.UserRepo.IsTwoFactorEnabled(userID)
				require.NoError(t, err)
				require.Equal(t, !(success && factor == "totp"), enabled)
				if factor == "passkey" {
					count, err := controller.PasskeyRepo.GetPasskeyCount(userID)
					require.NoError(t, err)
					require.EqualValues(t, 1, count)
				}
			})
		}
	}
}
