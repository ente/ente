package api

import (
	"bytes"
	"crypto/rand"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/ente/jwt"
	"github.com/ente/museum/internal/testutil"
	museumcontroller "github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/middleware"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/repo/passkey"
	"github.com/ente/museum/pkg/utils/byteMarshaller"
	"github.com/ente/museum/pkg/utils/crypto"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/patrickmn/go-cache"
	"github.com/spf13/viper"
	"github.com/stretchr/testify/require"
	"golang.org/x/crypto/nacl/box"
)

type passkeyTestAccount struct {
	id                    int64
	email, accountsToken  string
	publicKey, privateKey *[32]byte
}

type passkeyEnrollmentTest struct {
	t       *testing.T
	db      *sql.DB
	handler *UserHandler
	pk      *passkey.Repository
	router  *gin.Engine
}

func newPasskeyEnrollmentTest(t *testing.T) *passkeyEnrollmentTest {
	t.Helper()
	h, db := setupUserHandlerTest(t)
	for _, key := range []string{"webauthn.rpid", "webauthn.rporigins", "webauthn.legacy-rpid", "webauthn.legacy-rporigins", "apps.accounts", "apps.accounts-legacy"} {
		previous := viper.Get(key)
		t.Cleanup(func() { viper.Set(key, previous) })
	}
	viper.Set("webauthn.rpid", passkeyTestRPID)
	viper.Set("webauthn.rporigins", []string{passkeyTestOrigin})
	viper.Set("webauthn.legacy-rpid", "")
	viper.Set("apps.accounts", passkeyTestOrigin)
	h.UserController.UserAuthRepo = &repo.UserAuthRepository{DB: db}
	h.UserController.HashingKey = testutil.HashingKey()
	h.UserController.JwtSecret = []byte("passkey-enrollment-test-signing-key")
	f := &passkeyEnrollmentTest{t: t, db: db, handler: h}
	var err error
	f.pk, err = passkey.NewRepository(f.db)
	require.NoError(f.t, err)
	c := f.handler.UserController
	c.PasskeyRepo = f.pk
	c.UserRepo.PasskeysRepository = f.pk
	ph := &PasskeyHandler{Controller: &museumcontroller.PasskeyController{Repo: f.pk, UserRepo: c.UserRepo}}
	am := &middleware.AuthMiddleware{UserAuthRepo: c.UserAuthRepo, UserController: c, Cache: cache.New(time.Minute, time.Minute)}
	gin.SetMode(gin.TestMode)
	f.router = gin.New()
	f.router.POST("/users/verify-email", f.handler.VerifyEmail)
	f.router.GET("/users/accounts-token", am.TokenAuthMiddleware(nil), f.handler.GetAccountsToken)
	protected := f.router.Group("/", am.TokenAuthMiddleware(jwt.ACCOUNTS.Ptr()))
	protected.GET("/passkeys", ph.GetPasskeys)
	protected.POST("/passkeys/registration/begin", ph.BeginRegistration)
	protected.POST("/passkeys/registration/finish", ph.FinishRegistration)
	f.router.POST("/users/two-factor/passkeys/begin", f.handler.BeginPasskeyAuthenticationCeremony)
	f.router.POST("/users/two-factor/passkeys/finish", f.handler.FinishPasskeyAuthenticationCeremony)
	return f
}

func (f *passkeyEnrollmentTest) send(method, path, token string, body any) *httptest.ResponseRecorder {
	f.t.Helper()
	data, err := json.Marshal(body)
	require.NoError(f.t, err)
	return f.sendRequest(method, path, token, httptest.NewRequest(method, path, bytes.NewReader(data)))
}

func (f *passkeyEnrollmentTest) sendRequest(method, path, token string, req *http.Request) *httptest.ResponseRecorder {
	f.t.Helper()
	var err error
	req.Method = method
	req.URL, err = url.Parse(path)
	require.NoError(f.t, err)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Auth-Token", token)
	response := httptest.NewRecorder()
	f.router.ServeHTTP(response, req)
	return response
}

func passkeyTestDecode(t *testing.T, response *httptest.ResponseRecorder, value any) {
	t.Helper()
	require.Equal(t, http.StatusOK, response.Code, response.Body.String())
	require.NoError(t, json.Unmarshal(response.Body.Bytes(), value))
}

func (f *passkeyEnrollmentTest) account(email string) *passkeyTestAccount {
	f.t.Helper()
	id := testutil.InsertUser(f.t, f.db, testutil.UserFixture{Email: email, CreationTime: 1})
	_, err := f.db.Exec(`UPDATE users SET email_mfa=true WHERE user_id=$1`, id)
	require.NoError(f.t, err)
	pub, priv, err := box.GenerateKey(rand.Reader)
	require.NoError(f.t, err)
	require.NoError(f.t, f.handler.UserController.UserRepo.SetKeyAttributes(id, ente.KeyAttributes{
		KEKSalt: "salt", EncryptedKey: "key", KeyDecryptionNonce: "nonce", PublicKey: base64.StdEncoding.EncodeToString(pub[:]),
		EncryptedSecretKey: "secret", SecretKeyDecryptionNonce: "nonce", MemLimit: 1, OpsLimit: 1,
	}))
	a := &passkeyTestAccount{id: id, email: email, publicKey: pub, privateKey: priv}
	login := f.login(a)
	require.Empty(f.t, login.PasskeySessionID)
	a.accountsToken = f.accountsToken(a, login.EncryptedToken)
	return a
}

func (f *passkeyEnrollmentTest) login(a *passkeyTestAccount) ente.EmailAuthorizationResponse {
	f.t.Helper()
	hash, err := crypto.GetHash(a.email, testutil.HashingKey())
	require.NoError(f.t, err)
	// Deliver a test-owned code directly; the HTTP handler performs real primary
	// verification, consumes the code, and chooses the next authentication step.
	require.NoError(f.t, f.handler.UserController.UserAuthRepo.AddOTT(hash, ente.Photos, "123456", time.Now().Add(time.Minute).UnixMicro()))
	var result ente.EmailAuthorizationResponse
	passkeyTestDecode(f.t, f.send("POST", "/users/verify-email", "", ente.EmailVerificationRequest{Email: a.email, OTT: "123456"}), &result)
	require.Equal(f.t, a.id, result.ID)
	return result
}

func (f *passkeyEnrollmentTest) accountsToken(a *passkeyTestAccount, encrypted string) string {
	f.t.Helper()
	sealed, err := base64.StdEncoding.DecodeString(encrypted)
	require.NoError(f.t, err)
	payload, ok := box.OpenAnonymous(nil, sealed, a.publicKey, a.privateKey)
	require.True(f.t, ok)
	var result struct {
		AccountsToken string `json:"accountsToken"`
	}
	passkeyTestDecode(f.t, f.send("GET", "/users/accounts-token", base64.URLEncoding.EncodeToString(payload), nil), &result)
	require.NotEmpty(f.t, result.AccountsToken)
	return result.AccountsToken
}

func (f *passkeyEnrollmentTest) begin(a *passkeyTestAccount) (string, string) {
	f.t.Helper()
	var result struct {
		Options struct {
			PublicKey struct {
				Challenge string `json:"challenge"`
			} `json:"publicKey"`
		} `json:"options"`
		SessionID string `json:"sessionID"`
	}
	passkeyTestDecode(f.t, f.send("POST", "/passkeys/registration/begin", a.accountsToken, nil), &result)
	require.NotEmpty(f.t, result.Options.PublicKey.Challenge)
	return result.Options.PublicKey.Challenge, result.SessionID
}

func (f *passkeyEnrollmentTest) finish(a *passkeyTestAccount, id []byte, challenge, session string) *httptest.ResponseRecorder {
	f.t.Helper()
	req, err := passkeyTestRegistration(challenge, id, passkeyTestOrigin, passkeyTestRPID, 5)
	require.NoError(f.t, err)
	return f.sendRequest("POST", "/passkeys/registration/finish?friendlyName=test&sessionID="+session, a.accountsToken, req)
}

func (f *passkeyEnrollmentTest) register(a *passkeyTestAccount, id []byte) *httptest.ResponseRecorder {
	f.t.Helper()
	challenge, session := f.begin(a)
	return f.finish(a, id, challenge, session)
}

func (f *passkeyEnrollmentTest) counts(a *passkeyTestAccount, parents, credentials int) {
	f.t.Helper()
	var p, c int
	require.NoError(f.t, f.db.QueryRow(`SELECT count(*) FROM passkeys WHERE user_id=$1 AND deleted_at IS NULL`, a.id).Scan(&p))
	require.NoError(f.t, f.db.QueryRow(`SELECT count(*) FROM passkey_credentials pc JOIN passkeys p ON p.id=pc.passkey_id WHERE p.user_id=$1 AND p.deleted_at IS NULL`, a.id).Scan(&c))
	require.Equal(f.t, parents, p, "committed parent rows")
	require.Equal(f.t, credentials, c, "committed credentials")
}

func (f *passkeyEnrollmentTest) factors(a *passkeyTestAccount, count int) {
	f.t.Helper()
	has, err := f.handler.UserController.UserRepo.HasPasskeys(a.id)
	require.NoError(f.t, err)
	require.Equal(f.t, count > 0, has)
	n, err := f.pk.GetPasskeyCount(a.id)
	require.NoError(f.t, err)
	require.EqualValues(f.t, count, n)
	var list struct {
		Passkeys []ente.Passkey `json:"passkeys"`
	}
	passkeyTestDecode(f.t, f.send("GET", "/passkeys", a.accountsToken, nil), &list)
	require.Len(f.t, list.Passkeys, count)
	login := f.login(a)
	require.Equal(f.t, count > 0, login.PasskeySessionID != "")
	if count == 0 {
		require.NotEmpty(f.t, f.accountsToken(a, login.EncryptedToken))
	}
}

func (f *passkeyEnrollmentTest) authenticate(a *passkeyTestAccount, id []byte) {
	f.t.Helper()
	login := f.login(a)
	require.NotEmpty(f.t, login.PasskeySessionID)
	require.Empty(f.t, login.EncryptedToken)
	var begin struct {
		Options struct {
			PublicKey struct {
				Challenge string `json:"challenge"`
			} `json:"publicKey"`
		} `json:"options"`
		CeremonySessionID string `json:"ceremonySessionID"`
	}
	passkeyTestDecode(f.t, f.send("POST", "/users/two-factor/passkeys/begin", "", map[string]string{"sessionID": login.PasskeySessionID}), &begin)
	userID, err := byteMarshaller.ConvertInt64ToByte(a.id)
	require.NoError(f.t, err)
	req, err := passkeyTestAssertion(begin.Options.PublicKey.Challenge, id, userID, passkeyTestOrigin, passkeyTestRPID)
	require.NoError(f.t, err)
	var result ente.TwoFactorAuthorizationResponse
	passkeyTestDecode(f.t, f.sendRequest("POST", "/users/two-factor/passkeys/finish?sessionID="+login.PasskeySessionID+"&ceremonySessionID="+begin.CeremonySessionID, "", req), &result)
	require.Equal(f.t, a.id, result.ID)
	require.NotEmpty(f.t, f.accountsToken(a, result.EncryptedToken))
}

func TestPasskeyEnrollmentPersistence(t *testing.T) {
	f := newPasskeyEnrollmentTest(t)
	a := f.account("enrollment@example.com")
	credential := []byte("test-owned-credential")
	seed := f.account("seed@example.com")
	require.Equal(t, http.StatusOK, f.register(seed, credential).Code)

	_, session := f.begin(a)
	require.NotEqual(t, http.StatusOK, f.finish(a, credential, "wrong-challenge", session).Code)
	f.counts(a, 0, 0)

	result := f.register(a, credential)
	require.Equal(t, http.StatusInternalServerError, result.Code, result.Body.String())
	f.counts(a, 0, 0)
	f.factors(a, 0)

	retry := []byte("retry-credential")
	result = f.register(a, retry)
	require.Equal(t, http.StatusOK, result.Code, result.Body.String())
	f.counts(a, 1, 1)
	f.factors(a, 1)
	f.authenticate(a, retry)

	require.Equal(t, http.StatusInternalServerError, f.register(a, credential).Code)
	f.counts(a, 1, 1)
	f.authenticate(a, retry)
}

func TestPasskeyEnrollmentExistingOrphans(t *testing.T) {
	f := newPasskeyEnrollmentTest(t)
	a := f.account("orphans@example.com")
	// Even enough old incomplete records to reach the enrollment limit must not
	// select a factor or prevent a new, usable enrollment.
	for i := 0; i < ente.MaxPasskeys; i++ {
		_, err := f.db.Exec(`INSERT INTO passkeys(id,user_id,friendly_name) VALUES($1,$2,'old incomplete enrollment')`, uuid.New(), a.id)
		require.NoError(t, err)
	}
	f.factors(a, 0)
	credential := []byte("after-orphans")
	result := f.register(a, credential)
	require.Equal(t, http.StatusOK, result.Code, result.Body.String())
	f.counts(a, ente.MaxPasskeys+1, 1)
	f.factors(a, 1)
	f.authenticate(a, credential)
}
