package api

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	baserepo "github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/auth"
	timeutil "github.com/ente/museum/pkg/utils/time"
	"github.com/ente/museum/space/controller"
	spacerepo "github.com/ente/museum/space/repo"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

var testSpaceBrowserSessionWrapKey = base64.StdEncoding.EncodeToString(make([]byte, 32))

func setTestAuthenticatedApp(c *gin.Context) {
	c.Set(auth.AppContextKey, auth.GetApp(c))
	c.Next()
}

type failingUserTokenTerminator struct{}

func (failingUserTokenTerminator) TerminateSession(int64, string) error {
	return errors.New("cache eviction failed")
}

func setupSpaceSessionAPITest(t *testing.T) (*Handlers, *spacerepo.Module, int64) {
	t.Helper()
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})
	gin.SetMode(gin.TestMode)
	repos := spacerepo.NewModule(db, nil)
	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		Email:        "space-session@example.com",
		CreationTime: timeutil.Microseconds(),
	})
	_, err := db.Exec(`
		INSERT INTO key_attributes (
			user_id, kek_salt, kek_hash_bytes, encrypted_key, key_decryption_nonce,
			public_key, encrypted_secret_key, secret_key_decryption_nonce
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
	`, userID, "salt", []byte{1, 2, 3}, "encrypted-key", "nonce", "public-key", "encrypted-secret-key", "secret-nonce")
	require.NoError(t, err)
	return NewHandlers(controller.NewModule(repos, &baserepo.UserAuthRepository{DB: db})), repos, userID
}

func TestCreateSpaceBrowserSessionReturnsTokenWhenCacheEvictionFails(t *testing.T) {
	handlers, repos, userID := setupSpaceSessionAPITest(t)
	handlers.Module.UserTokens = failingUserTokenTerminator{}
	authToken := "space-bootstrap-token"
	require.NoError(t, (&baserepo.UserAuthRepository{DB: repos.Sessions.DB}).AddToken(userID, ente.Photos, authToken, "127.0.0.1", "space-test"))
	router := gin.New()
	router.POST("/account/space/sessions", setTestAuthenticatedApp, handlers.CreateBrowserSession)
	req := httptest.NewRequest(http.MethodPost, "/account/space/sessions", bytes.NewBufferString(`{"sessionWrapKey":"`+testSpaceBrowserSessionWrapKey+`"}`))
	req.Header.Set("X-Auth-User-ID", strconv.FormatInt(userID, 10))
	req.Header.Set("X-Auth-Token", authToken)
	recorder := httptest.NewRecorder()

	router.ServeHTTP(recorder, req)

	require.Equal(t, http.StatusOK, recorder.Code)
	var resp struct {
		SessionToken string `json:"sessionToken"`
	}
	require.NoError(t, json.Unmarshal(recorder.Body.Bytes(), &resp))
	require.NotEmpty(t, resp.SessionToken)
	tokenHash := sha256.Sum256([]byte(resp.SessionToken))
	session, err := repos.Sessions.GetBrowserSession(context.Background(), tokenHash[:])
	require.NoError(t, err)
	require.Equal(t, userID, session.UserID)
	require.Equal(t, testSpaceBrowserSessionWrapKey, session.SessionWrapKey)
}

func TestCreateSpaceBrowserSessionRejectsInvalidWrapKey(t *testing.T) {
	handlers, repos, userID := setupSpaceSessionAPITest(t)
	router := gin.New()
	router.POST("/account/space/sessions", setTestAuthenticatedApp, handlers.CreateBrowserSession)

	for _, tt := range []struct {
		name string
		key  string
	}{
		{name: "invalid base64", key: testSpaceBrowserSessionWrapKey[:len(testSpaceBrowserSessionWrapKey)-1] + "!"},
		{name: "wrong decoded length", key: base64.StdEncoding.EncodeToString(make([]byte, 31))},
		{name: "too long", key: testSpaceBrowserSessionWrapKey + "A"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodPost, "/account/space/sessions", bytes.NewBufferString(`{"sessionWrapKey":"`+tt.key+`"}`))
			req.Header.Set("X-Auth-User-ID", strconv.FormatInt(userID, 10))
			recorder := httptest.NewRecorder()

			router.ServeHTTP(recorder, req)

			require.Equal(t, http.StatusBadRequest, recorder.Code)
		})
	}

	var count int
	require.NoError(t, repos.Sessions.DB.QueryRow(`SELECT COUNT(*) FROM space_browser_sessions WHERE user_id = $1`, userID).Scan(&count))
	require.Zero(t, count)
}

func TestRegisteredTokenSessionRoutesEnforceAppPolicy(t *testing.T) {
	handlers, repos, userID := setupSpaceSessionAPITest(t)
	authToken := "space-route-bootstrap-token"
	require.NoError(t, (&baserepo.UserAuthRepository{DB: repos.Sessions.DB}).AddToken(userID, ente.Photos, authToken, "127.0.0.1", "space-test"))
	router := gin.New()
	tokenPrivateAPI := router.Group("")
	tokenPrivateAPI.Use(setTestAuthenticatedApp)
	spacePrivateAPI := router.Group("")
	spacePrivateAPI.Use(handlers.RequireSpaceBrowserSession())
	RegisterTokenSessionRoutes(tokenPrivateAPI, handlers)
	Register(spacePrivateAPI, router.Group(""), handlers)

	for _, clientPackage := range []string{"io.ente.auth", "io.ente.locker"} {
		req := httptest.NewRequest(
			http.MethodPost,
			"/account/space/sessions",
			bytes.NewBufferString(`{"sessionWrapKey":"`+testSpaceBrowserSessionWrapKey+`"}`),
		)
		req.Header.Set("X-Auth-User-ID", strconv.FormatInt(userID, 10))
		req.Header.Set("X-Client-Package", clientPackage)
		recorder := httptest.NewRecorder()
		router.ServeHTTP(recorder, req)
		require.Equal(t, http.StatusForbidden, recorder.Code)
	}

	sessionReq := httptest.NewRequest(
		http.MethodPost,
		"/account/space/sessions",
		bytes.NewBufferString(`{"sessionWrapKey":"`+testSpaceBrowserSessionWrapKey+`"}`),
	)
	sessionReq.Header.Set("X-Auth-User-ID", strconv.FormatInt(userID, 10))
	sessionReq.Header.Set("X-Auth-Token", authToken)
	sessionReq.Header.Set("X-Client-Package", "io.ente.space.web")
	sessionRecorder := httptest.NewRecorder()

	router.ServeHTTP(sessionRecorder, sessionReq)

	require.Equal(t, http.StatusOK, sessionRecorder.Code)

	getReq := httptest.NewRequest(http.MethodGet, "/account/space", nil)
	getReq.Header.Set("X-Auth-User-ID", strconv.FormatInt(userID, 10))
	getRecorder := httptest.NewRecorder()

	router.ServeHTTP(getRecorder, getReq)

	require.Equal(t, http.StatusUnauthorized, getRecorder.Code)
}

func TestRequireSpaceBrowserSessionAcceptsValidHeader(t *testing.T) {
	handlers, repos, userID := setupSpaceSessionAPITest(t)
	token := "valid-space-session-token"
	tokenHash := sha256.Sum256([]byte(token))
	require.NoError(t, repos.Sessions.CreateBrowserSession(context.Background(), tokenHash[:], userID, "session-wrap-key", timeutil.NDaysFromNow(1)))

	router := gin.New()
	router.GET("/space", handlers.RequireSpaceBrowserSession(), func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"userID": c.Request.Header.Get("X-Auth-User-ID")})
	})
	req := httptest.NewRequest(http.MethodGet, "/space", nil)
	req.Header.Set("Origin", "https://ente.space")
	req.Header.Set(controller.SpaceBrowserSessionTokenHeader, token)
	recorder := httptest.NewRecorder()

	router.ServeHTTP(recorder, req)

	require.Equal(t, http.StatusOK, recorder.Code)
	require.JSONEq(t, `{"userID":"`+strconv.FormatInt(userID, 10)+`"}`, recorder.Body.String())
}

func TestValidateSpaceBrowserSessionCoalescesLastUsedAtUpdates(t *testing.T) {
	handlers, repos, userID := setupSpaceSessionAPITest(t)
	token := "space-session-touch-token"
	tokenHash := sha256.Sum256([]byte(token))
	require.NoError(t, repos.Sessions.CreateBrowserSession(context.Background(), tokenHash[:], userID, "session-wrap-key", timeutil.NDaysFromNow(1)))
	validate := func() {
		ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
		ctx.Request = httptest.NewRequest(http.MethodGet, "/space", nil)
		_, err := handlers.Module.Sessions.ValidateBrowserSession(ctx, token)
		require.NoError(t, err)
	}

	recent, err := repos.Sessions.GetBrowserSession(context.Background(), tokenHash[:])
	require.NoError(t, err)
	validate()
	afterRecentValidation, err := repos.Sessions.GetBrowserSession(context.Background(), tokenHash[:])
	require.NoError(t, err)
	require.Equal(t, recent.LastUsedAt, afterRecentValidation.LastUsedAt)

	oldLastUsedAt := timeutil.MicrosecondsBeforeMinutes(2)
	_, err = repos.Sessions.DB.Exec(`UPDATE space_browser_sessions SET last_used_at = $1 WHERE token_hash = $2`, oldLastUsedAt, tokenHash[:])
	require.NoError(t, err)
	validate()
	afterOldValidation, err := repos.Sessions.GetBrowserSession(context.Background(), tokenHash[:])
	require.NoError(t, err)
	require.Greater(t, afterOldValidation.LastUsedAt, oldLastUsedAt)
}

func TestRequireSpaceBrowserSessionRejectsInvalidHeader(t *testing.T) {
	handlers, _, _ := setupSpaceSessionAPITest(t)
	router := gin.New()
	router.GET("/space", handlers.RequireSpaceBrowserSession(), func(c *gin.Context) {
		c.Status(http.StatusOK)
	})
	req := httptest.NewRequest(http.MethodGet, "/space", nil)
	req.Header.Set("Origin", "https://ente.space")
	req.Header.Set(controller.SpaceBrowserSessionTokenHeader, "invalid-session-token")
	recorder := httptest.NewRecorder()

	router.ServeHTTP(recorder, req)

	require.Equal(t, http.StatusUnauthorized, recorder.Code)
}

func TestBootstrapBrowserSessionAcceptsHeader(t *testing.T) {
	handlers, repos, userID := setupSpaceSessionAPITest(t)
	token := "valid-space-session-token"
	tokenHash := sha256.Sum256([]byte(token))
	require.NoError(t, repos.Sessions.CreateBrowserSession(context.Background(), tokenHash[:], userID, "session-wrap-key", timeutil.NDaysFromNow(1)))
	router := gin.New()
	router.POST("/account/space/sessions/bootstrap", handlers.BootstrapBrowserSession)
	req := httptest.NewRequest(http.MethodPost, "/account/space/sessions/bootstrap", nil)
	req.Header.Set(controller.SpaceBrowserSessionTokenHeader, token)
	recorder := httptest.NewRecorder()

	router.ServeHTTP(recorder, req)

	require.Equal(t, http.StatusOK, recorder.Code)
	require.JSONEq(t, `{"sessionWrapKey":"session-wrap-key"}`, recorder.Body.String())
}

func TestDeleteBrowserSessionRevokesAllUserSessions(t *testing.T) {
	handlers, repos, userID := setupSpaceSessionAPITest(t)
	otherUserID := testutil.InsertUser(t, repos.Sessions.DB, testutil.UserFixture{
		Email:        "other-space-session@example.com",
		CreationTime: timeutil.Microseconds(),
	})
	token := "valid-space-session-token"
	tokenHash := sha256.Sum256([]byte(token))
	require.NoError(t, repos.Sessions.CreateBrowserSession(context.Background(), tokenHash[:], userID, "session-wrap-key", timeutil.NDaysFromNow(1)))
	secondHash := sha256.Sum256([]byte("second-space-session-token"))
	require.NoError(t, repos.Sessions.CreateBrowserSession(context.Background(), secondHash[:], userID, "second-wrap-key", timeutil.NDaysFromNow(1)))
	otherHash := sha256.Sum256([]byte("other-user-space-session-token"))
	require.NoError(t, repos.Sessions.CreateBrowserSession(context.Background(), otherHash[:], otherUserID, "other-wrap-key", timeutil.NDaysFromNow(1)))
	router := gin.New()
	router.DELETE("/account/space/sessions/current", handlers.DeleteBrowserSession)
	req := httptest.NewRequest(http.MethodDelete, "/account/space/sessions/current", nil)
	req.Header.Set(controller.SpaceBrowserSessionTokenHeader, token)
	recorder := httptest.NewRecorder()

	router.ServeHTTP(recorder, req)

	require.Equal(t, http.StatusOK, recorder.Code)
	var count int
	require.NoError(t, repos.Sessions.DB.QueryRow(`SELECT COUNT(*) FROM space_browser_sessions WHERE user_id = $1`, userID).Scan(&count))
	require.Zero(t, count)
	require.NoError(t, repos.Sessions.DB.QueryRow(`SELECT COUNT(*) FROM space_browser_sessions WHERE user_id = $1`, otherUserID).Scan(&count))
	require.Equal(t, 1, count)
}

func TestDeleteBrowserSessionDoesNotAcceptExpiredSession(t *testing.T) {
	handlers, repos, userID := setupSpaceSessionAPITest(t)
	expiredToken := "expired-space-session-token"
	expiredHash := sha256.Sum256([]byte(expiredToken))
	require.NoError(t, repos.Sessions.CreateBrowserSession(context.Background(), expiredHash[:], userID, "expired-wrap-key", timeutil.Microseconds()-1))
	activeHash := sha256.Sum256([]byte("active-space-session-token"))
	require.NoError(t, repos.Sessions.CreateBrowserSession(context.Background(), activeHash[:], userID, "active-wrap-key", timeutil.NDaysFromNow(1)))
	router := gin.New()
	router.DELETE("/account/space/sessions/current", handlers.DeleteBrowserSession)
	req := httptest.NewRequest(http.MethodDelete, "/account/space/sessions/current", nil)
	req.Header.Set(controller.SpaceBrowserSessionTokenHeader, expiredToken)
	recorder := httptest.NewRecorder()

	router.ServeHTTP(recorder, req)

	require.Equal(t, http.StatusUnauthorized, recorder.Code)
	_, err := repos.Sessions.GetBrowserSession(context.Background(), activeHash[:])
	require.NoError(t, err)
}
